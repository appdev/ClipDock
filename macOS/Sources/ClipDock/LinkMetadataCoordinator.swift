import AppKit
import ClipboardPanelApp
@preconcurrency import Foundation
import ImageIO
@preconcurrency import LinkPresentation
import UniformTypeIdentifiers

typealias LinkMetadataChangeHandler = @Sendable () async -> Void

struct LinkMetadataImagePayload: Sendable, Equatable {
    let data: Data
    let typeIdentifier: String?
}

struct LinkMetadataFetchPayload: Sendable, Equatable {
    let title: String?
    let canonicalURL: URL
    let originalURL: URL?
    let iconData: LinkMetadataImagePayload?
    let previewData: LinkMetadataImagePayload?
}

protocol LinkMetadataFetching: Sendable {
    func fetch(url: URL) async throws -> LinkMetadataFetchPayload
}

protocol LinkMetadataAssetWriting: Sendable {
    func writeAssets(
        itemID: String,
        icon: LinkMetadataImagePayload?,
        preview: LinkMetadataImagePayload?
    ) async throws -> LinkMetadataAssetWriteResult
    func cleanupAssets(_ assets: LinkMetadataAssetWriteResult) async
}

extension LinkMetadataAssetWriting {
    func cleanupAssets(_ assets: LinkMetadataAssetWriteResult) async {}
}

struct LinkMetadataAssetWriteResult: Sendable, Equatable {
    let iconRelativePath: String?
    let imageRelativePath: String?
}

struct LinkMetadataCoordinatorConfiguration: Sendable, Equatable {
    let maxConcurrentFetches: Int
    let batchLimit: Int64
    let leaseTimeoutMs: Int64

    init(
        maxConcurrentFetches: Int = 3,
        batchLimit: Int64 = 6,
        leaseTimeoutMs: Int64 = 60_000
    ) {
        self.maxConcurrentFetches = max(1, maxConcurrentFetches)
        self.batchLimit = max(1, batchLimit)
        self.leaseTimeoutMs = max(1, leaseTimeoutMs)
    }
}

actor LinkMetadataCoordinator {
    private let coreClient: RustCoreClient
    private let databaseWorker: ClipboardCoreDatabaseWorker
    private let appSupportDirectory: URL
    private let configuration: LinkMetadataCoordinatorConfiguration
    private let fetcher: LinkMetadataFetching
    private let assetWriter: LinkMetadataAssetWriting
    private let onMetadataChanged: LinkMetadataChangeHandler
    private let beforeCompletionSubmission: @Sendable () -> Void
    private var isStopped = false
    private var schedulerTask: Task<Void, Never>?
    private var schedulerToken: UUID?
    private var activeFetchTasks: [String: (token: UUID, leaseStartedAtMs: Int64, task: Task<Void, Never>)] = [:]
    private var rescheduleRequested = false

    init(
        coreClient: RustCoreClient,
        appSupportDirectory: URL,
        databaseWorker: ClipboardCoreDatabaseWorker = ClipboardCoreDatabaseWorker(),
        configuration: LinkMetadataCoordinatorConfiguration = LinkMetadataCoordinatorConfiguration(),
        fetcher: LinkMetadataFetching = LinkPresentationMetadataFetcher(),
        assetWriter: LinkMetadataAssetWriting? = nil,
        beforeCompletionSubmission: @escaping @Sendable () -> Void = {},
        onMetadataChanged: @escaping LinkMetadataChangeHandler
    ) {
        self.coreClient = coreClient
        self.databaseWorker = databaseWorker
        self.appSupportDirectory = appSupportDirectory
        self.configuration = configuration
        self.fetcher = fetcher
        self.assetWriter = assetWriter ?? LinkMetadataAssetWriter(appSupportDirectory: appSupportDirectory)
        self.onMetadataChanged = onMetadataChanged
        self.beforeCompletionSubmission = beforeCompletionSubmission
    }

    func apply(preferences: RustPreferencesDocument) async {
        _ = preferences
        isStopped = false
        scheduleSoon()
    }

    func scheduleSoon() {
        guard !isStopped else { return }
        if schedulerTask != nil {
            rescheduleRequested = true
            return
        }
        let token = UUID()
        schedulerToken = token
        schedulerTask = Task { [weak self] in
            await self?.runScheduledPass(token: token)
        }
    }

    func stop() {
        isStopped = true
        rescheduleRequested = false
        schedulerTask?.cancel()
        schedulerTask = nil
        schedulerToken = nil
        for task in activeFetchTasks.values {
            task.task.cancel()
        }
        activeFetchTasks.removeAll()
    }

    private func runScheduledPass(token: UUID) async {
        defer {
            if schedulerToken == token {
                schedulerTask = nil
                schedulerToken = nil
                if !isStopped, rescheduleRequested {
                    rescheduleRequested = false
                    scheduleSoon()
                }
            }
        }
        while !isStopped, !Task.isCancelled, schedulerToken == token {
            let availableSlots = configuration.maxConcurrentFetches - activeFetchTasks.count
            guard availableSlots > 0 else { return }
            let claimLimit = min(configuration.batchLimit, Int64(availableSlots))
            let leaseTimeoutMs = configuration.leaseTimeoutMs
            let result = await databaseWorker.perform { [coreClient, appSupportDirectory] in
                coreClient.claimLinkMetadataFetchBatch(
                    appSupportDirectory: appSupportDirectory,
                    limit: claimLimit,
                    leaseTimeoutMs: leaseTimeoutMs
                )
            }
            switch result {
            case .success(let candidates):
                guard !candidates.isEmpty else { return }
                let activeCountBeforeStarting = activeFetchTasks.count
                for candidate in candidates {
                    guard !isStopped, !Task.isCancelled, schedulerToken == token else { break }
                    startProcessing(candidate)
                }
                if candidates.count < claimLimit ||
                    activeFetchTasks.count == activeCountBeforeStarting ||
                    activeFetchTasks.count >= configuration.maxConcurrentFetches {
                    return
                }
            case .failure:
                return
            }
        }
    }

    private func startProcessing(_ candidate: RustLinkMetadataFetchCandidate) {
        if let previous = activeFetchTasks[candidate.itemId] {
            guard previous.leaseStartedAtMs != candidate.leaseStartedAtMs else { return }
            previous.task.cancel()
        }
        let token = UUID()
        let task = Task { [weak self] in
            await self?.process(candidate, token: token)
            await self?.processDidFinish(itemID: candidate.itemId, token: token)
        }
        activeFetchTasks[candidate.itemId] = (token, candidate.leaseStartedAtMs, task)
    }

    private func processDidFinish(itemID: String, token: UUID) {
        guard activeFetchTasks[itemID]?.token == token else { return }
        activeFetchTasks[itemID] = nil
        guard !isStopped else { return }
        scheduleSoon()
    }

    private func isCurrent(_ candidate: RustLinkMetadataFetchCandidate, token: UUID) -> Bool {
        !isStopped && !Task.isCancelled && activeFetchTasks[candidate.itemId]?.token == token
    }

    private func process(_ candidate: RustLinkMetadataFetchCandidate, token: UUID) async {
        guard isCurrent(candidate, token: token) else { return }
        guard let url = URL(string: candidate.canonicalURL),
              LinkMetadataURLPolicy.isSupportedRemoteURL(url)
        else {
            await completeFailure(candidate, failureCode: "invalid_url", retry: false)
            return
        }

        if LinkMetadataURLPolicy.isPrivacySensitive(url) {
            await completeFailure(candidate, failureCode: "privacy_sensitive", retry: false)
            return
        }

        do {
            let payload = try await fetcher.fetch(url: url)
            guard isCurrent(candidate, token: token) else { return }
            let assets = try await assetWriter.writeAssets(
                itemID: candidate.itemId,
                icon: payload.iconData,
                preview: payload.previewData
            )
            guard isCurrent(candidate, token: token) else {
                await assetWriter.cleanupAssets(assets)
                return
            }
            await completeSuccess(candidate, payload: payload, assets: assets)
        } catch let error as LinkMetadataFetchError {
            // Lifecycle cancellation leaves the lease recoverable. A provider's
            // own cancelled result, while this attempt is live, remains terminal.
            guard isCurrent(candidate, token: token) else { return }
            await completeFailure(candidate, failureCode: error.failureCode, retry: error.shouldRetry)
        } catch {
            guard isCurrent(candidate, token: token), !(error is CancellationError) else { return }
            await completeFailure(candidate, failureCode: "provider_error", retry: true)
        }
    }

    private func completeSuccess(
        _ candidate: RustLinkMetadataFetchCandidate,
        payload: LinkMetadataFetchPayload,
        assets: LinkMetadataAssetWriteResult
    ) async {
        let canonicalURL = payload.canonicalURL.absoluteString
        let displayURL = LinkDisplayURLFormatter.displayURL(from: payload.canonicalURL)
            ?? candidate.displayURL
        let host = payload.canonicalURL.host?.lowercased() ?? candidate.host
        let request = RustCompleteLinkMetadataFetchRequest(
            itemId: candidate.itemId,
            leaseStartedAtMs: candidate.leaseStartedAtMs,
            canonicalURL: canonicalURL,
            displayURL: displayURL,
            host: host,
            title: payload.title,
            siteName: nil,
            iconRelativePath: assets.iconRelativePath,
            imageRelativePath: assets.imageRelativePath
        )
        beforeCompletionSubmission()
        let result: Result<RustItemManagementResult, RustCoreError>? = await databaseWorker.perform { [coreClient, appSupportDirectory] in
            // An actor hop can queue behind a long operation. Check in the
            // same task immediately before the synchronous mutation begins.
            guard !Task.isCancelled else { return nil }
            return coreClient.completeLinkMetadataFetch(appSupportDirectory: appSupportDirectory, request: request)
        }
        switch result {
        case .some(.success(let result)) where result.affectedCount > 0:
            await onMetadataChanged()
        case .some, .none:
            // AssetStore checks current DB references under its lifecycle lock,
            // including an uncertain committed response; never delete a winner.
            await assetWriter.cleanupAssets(assets)
        }
    }

    private func completeFailure(
        _ candidate: RustLinkMetadataFetchCandidate,
        failureCode: String,
        retry: Bool
    ) async {
        let nextRetryAtMs: Int64?
        if retry {
            guard let retryAt = try? RustMetadataPolicy.retryAtMs(fetchAttempts: candidate.fetchAttempts,
                nowMs: Int64(Date().timeIntervalSince1970 * 1_000)) else { return }
            nextRetryAtMs = retryAt
        } else { nextRetryAtMs = nil }
        beforeCompletionSubmission()
        let result: Result<RustItemManagementResult, RustCoreError>? = await databaseWorker.perform { [coreClient, appSupportDirectory] in
            guard !Task.isCancelled else { return nil }
            return coreClient.failLinkMetadataFetch(
                appSupportDirectory: appSupportDirectory,
                itemId: candidate.itemId,
                leaseStartedAtMs: candidate.leaseStartedAtMs,
                failureCode: failureCode,
                nextRetryAtMs: nextRetryAtMs
            )
        }
        switch result {
        case .some(.success(let result)) where result.affectedCount > 0:
            await onMetadataChanged()
        case .some, .none:
            break
        }
    }

}

enum LinkMetadataFetchError: Error, Equatable {
    case invalidURL
    case privacySensitive
    case timedOut
    case cancelled
    case provider
    case assetWriteFailed

    var failureCode: String {
        switch self {
        case .invalidURL:
            return "invalid_url"
        case .privacySensitive:
            return "privacy_sensitive"
        case .timedOut:
            return "timeout"
        case .cancelled:
            return "cancelled"
        case .provider:
            return "provider_error"
        case .assetWriteFailed:
            return "asset_write_failed"
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .invalidURL, .privacySensitive, .cancelled:
            return false
        case .timedOut, .provider, .assetWriteFailed:
            return true
        }
    }
}

final class LinkPresentationMetadataFetcher: LinkMetadataFetching, @unchecked Sendable {
    private let timeout: TimeInterval
    private let metadataProvider: LinkMetadataProviderLoading
    private let imageFetcher: LinkMetadataPageImageFetching

    init(
        timeout: TimeInterval = 12,
        metadataProvider: LinkMetadataProviderLoading = LinkPresentationMetadataProviderLoader(),
        imageFetcher: LinkMetadataPageImageFetching = OpenGraphLinkMetadataImageFetcher()
    ) {
        self.timeout = timeout
        self.metadataProvider = metadataProvider
        self.imageFetcher = imageFetcher
    }

    func fetch(url: URL) async throws -> LinkMetadataFetchPayload {
        guard LinkMetadataURLPolicy.isSupportedRemoteURL(url) else {
            throw LinkMetadataFetchError.invalidURL
        }
        guard !LinkMetadataURLPolicy.isPrivacySensitive(url) else {
            throw LinkMetadataFetchError.privacySensitive
        }

        async let originalImages = imageFetcher.fetchImages(for: url)
        do {
            let payload = try await metadataProvider.fetchPayload(url: url, timeout: timeout)
            var images = await originalImages
            try Task.checkCancellation()
            if !images.hasAssets, payload.canonicalURL != url {
                images = await imageFetcher.fetchImages(for: payload.canonicalURL)
            }
            try Task.checkCancellation()
            return LinkMetadataFetchPayload(
                title: payload.title ?? images.title,
                canonicalURL: payload.canonicalURL,
                originalURL: payload.originalURL,
                iconData: images.iconData,
                previewData: images.previewData
            )
        } catch {
            try Task.checkCancellation()
            let images = await originalImages
            try Task.checkCancellation()
            guard images.hasAssets || images.title != nil else { throw error }
            return LinkMetadataFetchPayload(
                title: images.title,
                canonicalURL: url,
                originalURL: url,
                iconData: images.iconData,
                previewData: images.previewData
            )
        }
    }
}

protocol LinkMetadataProviderLoading: Sendable {
    func fetchPayload(url: URL, timeout: TimeInterval) async throws -> LinkMetadataFetchPayload
}

struct LinkPresentationMetadataProviderLoader: LinkMetadataProviderLoading {
    func fetchPayload(url: URL, timeout: TimeInterval) async throws -> LinkMetadataFetchPayload {
        try await MetadataProviderBox(timeout: timeout).fetchPayload(url: url)
    }
}

struct LinkMetadataFetchedImages: Sendable, Equatable {
    let iconData: LinkMetadataImagePayload?
    let previewData: LinkMetadataImagePayload?
    let title: String?

    init(iconData: LinkMetadataImagePayload?, previewData: LinkMetadataImagePayload?, title: String? = nil) {
        self.iconData = iconData
        self.previewData = previewData
        self.title = title
    }
}

private extension LinkMetadataFetchedImages {
    var hasAssets: Bool {
        iconData != nil || previewData != nil
    }
}

protocol LinkMetadataPageImageFetching: Sendable {
    func fetchImages(for pageURL: URL) async -> LinkMetadataFetchedImages
}

private final class MetadataProviderContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LinkMetadataFetchPayload, any Error>?
    private var result: Result<LinkMetadataFetchPayload, any Error>?

    func install(_ continuation: CheckedContinuation<LinkMetadataFetchPayload, any Error>) {
        let storedResult: Result<LinkMetadataFetchPayload, any Error>?
        lock.lock()
        if let result {
            storedResult = result
        } else {
            self.continuation = continuation
            storedResult = nil
        }
        lock.unlock()

        if let storedResult {
            Self.resume(continuation, with: storedResult)
        }
    }

    @discardableResult
    func finish(_ result: Result<LinkMetadataFetchPayload, any Error>) -> Bool {
        let continuation: CheckedContinuation<LinkMetadataFetchPayload, any Error>?
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return false
        }
        self.result = result
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        if let continuation {
            Self.resume(continuation, with: result)
        }
        return true
    }

    private static func resume(
        _ continuation: CheckedContinuation<LinkMetadataFetchPayload, any Error>,
        with result: Result<LinkMetadataFetchPayload, any Error>
    ) {
        switch result {
        case .success(let payload):
            continuation.resume(returning: payload)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class MetadataProviderBox: @unchecked Sendable {
    private let provider = LPMetadataProvider()
    private let timeout: TimeInterval

    init(timeout: TimeInterval) {
        self.timeout = timeout
        provider.timeout = timeout
        provider.shouldFetchSubresources = false
    }

    func fetchPayload(url: URL) async throws -> LinkMetadataFetchPayload {
        let gate = MetadataProviderContinuationGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(isolation: nil) { continuation in
                gate.install(continuation)
                let timeoutTask = Task { [provider, timeout] in
                    try? await Task.sleep(nanoseconds: Self.timeoutNanoseconds(timeout))
                    guard !Task.isCancelled else { return }
                    if gate.finish(.failure(LinkMetadataFetchError.timedOut)) {
                        provider.cancel()
                    }
                }
                provider.startFetchingMetadata(for: url) { metadata, error in
                    timeoutTask.cancel()
                    if let error = error as NSError? {
                        gate.finish(.failure(Self.fetchError(from: error)))
                        return
                    }
                    guard let metadata else {
                        gate.finish(.failure(LinkMetadataFetchError.provider))
                        return
                    }
                    let title = Self.nonEmpty(metadata.title)
                    let canonicalURL = metadata.url ?? url
                    let originalURL = metadata.originalURL
                    gate.finish(.success(LinkMetadataFetchPayload(
                        title: title,
                        canonicalURL: canonicalURL,
                        originalURL: originalURL,
                        iconData: nil,
                        previewData: nil
                    )))
                }
            }
        } onCancel: {
            if gate.finish(.failure(LinkMetadataFetchError.cancelled)) {
                provider.cancel()
            }
        }
    }

    private static func timeoutNanoseconds(_ timeout: TimeInterval) -> UInt64 {
        UInt64(max(timeout, 0.001) * 1_000_000_000)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fetchError(from error: NSError) -> LinkMetadataFetchError {
        guard error.domain == LPError.errorDomain,
              let code = LPError.Code(rawValue: error.code)
        else {
            return "cancelled" == error.localizedDescription.lowercased() ? .cancelled : .provider
        }

        switch code {
        case .metadataFetchCancelled:
            return .cancelled
        case .metadataFetchTimedOut:
            return .timedOut
        default:
            return .provider
        }
    }
}

final class OpenGraphLinkMetadataImageFetcher: LinkMetadataPageImageFetching, @unchecked Sendable {
    private enum Defaults {
        static let limits = try? RustMetadataPolicy.limits()
        static let svgIconMaxPixelSize = 128
        static let svgPreviewMaxPixelSize = 640
    }

    private let httpClient: LinkMetadataHTTPClient

    init(httpClient: LinkMetadataHTTPClient = URLSessionLinkMetadataHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchImages(for pageURL: URL) async -> LinkMetadataFetchedImages {
        guard !Task.isCancelled, let limits = Defaults.limits,
              LinkMetadataURLPolicy.isSupportedRemoteURL(pageURL),
              !LinkMetadataURLPolicy.isPrivacySensitive(pageURL)
        else {
            return LinkMetadataFetchedImages(iconData: nil, previewData: nil)
        }

        guard let (html, finalURL) = try? await loadHTML(from: pageURL, limits: limits), !Task.isCancelled else {
            return LinkMetadataFetchedImages(iconData: nil, previewData: nil)
        }
        guard let parsed = try? RustMetadataPolicy.parse(html: html, baseURL: finalURL) else {
            return LinkMetadataFetchedImages(iconData: nil, previewData: nil)
        }
        async let iconData = loadFirstImage(
            from: parsed.iconUrls.compactMap(URL.init(string:)),
            limit: limits.maxIconCandidates,
            svgMaxPixelSize: Defaults.svgIconMaxPixelSize
        )
        async let previewData = loadFirstImage(
            from: parsed.previewUrls.compactMap(URL.init(string:)),
            limit: limits.maxPreviewCandidates,
            svgMaxPixelSize: Defaults.svgPreviewMaxPixelSize
        )
        return await LinkMetadataFetchedImages(
            iconData: iconData,
            previewData: previewData,
            title: parsed.title
        )
    }

    private func loadHTML(from url: URL, limits: RustMetadataLimits) async throws -> (String, URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = Double(limits.pageTimeoutMs) / 1_000
        request.setValue(
            "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        let (data, response) = try await httpClient.data(for: request,
            maxBytes: limits.maxHtmlBytes, maxRedirects: limits.maxRedirects)
        guard isSuccessfulHTTPResponse(response),
              response.mimeType?.lowercased().contains("html") != false
        else {
            throw LinkMetadataFetchError.provider
        }
        return (String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) ?? "", response.url ?? url)
    }

    private func loadFirstImage(
        from urls: [URL],
        limit: Int,
        svgMaxPixelSize: Int
    ) async -> LinkMetadataImagePayload? {
        for url in urls.prefix(limit) {
            guard !Task.isCancelled else { return nil }
            guard LinkMetadataURLPolicy.isSupportedRemoteURL(url),
                  !LinkMetadataURLPolicy.isPrivacySensitive(url),
                  let payload = try? await loadImage(from: url, svgMaxPixelSize: svgMaxPixelSize)
            else {
                continue
            }
            return payload
        }
        return nil
    }

    private func loadImage(from url: URL, svgMaxPixelSize: Int) async throws -> LinkMetadataImagePayload? {
        guard let limits = Defaults.limits else { throw LinkMetadataFetchError.provider }
        var request = URLRequest(url: url)
        request.timeoutInterval = Double(limits.imageTimeoutMs) / 1_000
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await httpClient.data(for: request,
            maxBytes: limits.maxImageBytes, maxRedirects: limits.maxRedirects)
        guard isSuccessfulHTTPResponse(response), !data.isEmpty else {
            return nil
        }
        if isSVGImage(url: url, response: response, data: data) {
            return rasterizedSVGImagePayload(data, maxPixelSize: svgMaxPixelSize)
        }
        guard data.count <= limits.maxImageBytes,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0
        else { return nil }
        return LinkMetadataImagePayload(
            data: data,
            typeIdentifier: imageTypeIdentifier(from: response) ?? UTType.png.identifier
        )
    }

    private func isSuccessfulHTTPResponse(_ response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return true }
        return (200..<300).contains(httpResponse.statusCode)
    }

    private func imageTypeIdentifier(from response: URLResponse) -> String? {
        if let mimeType = response.mimeType,
           let type = UTType(mimeType: mimeType),
           type.conforms(to: .image) {
            return type.identifier
        }
        if let suggestedFilename = response.suggestedFilename,
           let type = UTType(filenameExtension: URL(fileURLWithPath: suggestedFilename).pathExtension),
           type.conforms(to: .image) {
            return type.identifier
        }
        return nil
    }

    private func isSVGImage(url: URL, response: URLResponse, data: Data) -> Bool {
        if url.pathExtension.caseInsensitiveCompare("svg") == .orderedSame {
            return true
        }
        if response.suggestedFilename?.lowercased().hasSuffix(".svg") == true {
            return true
        }
        if response.mimeType?.lowercased() == "image/svg+xml" {
            return true
        }
        let prefix = String(decoding: data.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return prefix.hasPrefix("<svg") || (prefix.hasPrefix("<?xml") && prefix.contains("<svg"))
    }

    private func rasterizedSVGImagePayload(_ data: Data, maxPixelSize: Int) -> LinkMetadataImagePayload? {
        guard let limits = Defaults.limits, data.count <= limits.maxHtmlBytes else { return nil }
        guard case let .success(result) = RustCoreClient().rasterizeSVGToPNG(
            svgData: data,
            maxWidth: maxPixelSize,
            maxHeight: maxPixelSize
        ) else {
            return nil
        }
        return LinkMetadataImagePayload(
            data: result.pngData,
            typeIdentifier: UTType.png.identifier
        )
    }
}

struct LinkMetadataImageCandidates: Equatable, Sendable {
    let iconURLs: [URL]
    let previewURLs: [URL]
}

enum LinkMetadataHTMLImageParser {
    static func imageCandidates(in html: String, baseURL: URL) -> LinkMetadataImageCandidates {
        guard let parsed = try? RustMetadataPolicy.parse(html: html, baseURL: baseURL) else {
            return LinkMetadataImageCandidates(iconURLs: [], previewURLs: [])
        }
        return LinkMetadataImageCandidates(
            iconURLs: parsed.iconUrls.compactMap(URL.init(string:)),
            previewURLs: parsed.previewUrls.compactMap(URL.init(string:))
        )
    }
}

protocol LinkMetadataHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func data(for request: URLRequest, maxBytes: Int, maxRedirects: Int) async throws -> (Data, URLResponse)
}

extension LinkMetadataHTTPClient {
    // Existing deterministic fixture clients return finite data. Production
    // overrides this method and enforces the limit while bytes arrive.
    func data(for request: URLRequest, maxBytes: Int, maxRedirects: Int) async throws -> (Data, URLResponse) {
        let result = try await data(for: request)
        guard result.0.count <= maxBytes else { throw MetadataHTTPError.byteLimit }
        return result
    }
}

final class LinkMetadataAssetWriter: LinkMetadataAssetWriting, @unchecked Sendable {
    private enum Limits {
        static let iconMaxPixelSize = 128
        static let previewMaxPixelSize = 640
        static let previewMaxBytes = 512 * 1_024
    }

    private let appSupportDirectory: URL
    private let fileManager: FileManager

    init(
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.appSupportDirectory = appSupportDirectory
        self.fileManager = fileManager
    }

    func writeAssets(
        itemID: String,
        icon: LinkMetadataImagePayload?,
        preview: LinkMetadataImagePayload?
    ) async throws -> LinkMetadataAssetWriteResult {
        _ = itemID
        let attemptID = UUID().uuidString
        var iconPath: String?
        var previewPath: String?
        do {
            try Task.checkCancellation()
            iconPath = try await writeImage(icon,
                relativePath: "assets/link-icons/\(attemptID).png",
                typeIdentifier: UTType.png.identifier,
                maxPixelSize: Limits.iconMaxPixelSize, maxBytes: nil)
            try Task.checkCancellation()
            previewPath = try await writeImage(preview,
                relativePath: "assets/link-previews/\(attemptID).jpg",
                typeIdentifier: UTType.jpeg.identifier,
                maxPixelSize: Limits.previewMaxPixelSize, maxBytes: Limits.previewMaxBytes)
            try Task.checkCancellation()
            return LinkMetadataAssetWriteResult(iconRelativePath: iconPath, imageRelativePath: previewPath)
        } catch {
            await cleanupAssets(LinkMetadataAssetWriteResult(iconRelativePath: iconPath, imageRelativePath: previewPath))
            throw error
        }
    }

    func cleanupAssets(_ assets: LinkMetadataAssetWriteResult) async {
        let paths = [assets.iconRelativePath, assets.imageRelativePath].compactMap { $0 }
        guard !paths.isEmpty else { return }
        let root = appSupportDirectory
        _ = await Task.detached(priority: .utility) {
            RustAssetStore(appSupportDirectory: root).cleanupUncommitted(relativePaths: paths)
        }.value
    }

    private func writeImage(
        _ payload: LinkMetadataImagePayload?,
        relativePath: String,
        typeIdentifier: String,
        maxPixelSize: Int,
        maxBytes: Int?
    ) async throws -> String? {
        guard let payload else { return nil }
        let appSupportDirectory = appSupportDirectory
        return try await Task.detached(priority: .utility) {
            let encoded = NSMutableData()
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let source = CGImageSourceCreateWithData(payload.data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let destination = CGImageDestinationCreateWithData(
                    encoded as CFMutableData,
                    typeIdentifier as CFString,
                    1,
                    nil
                  )
            else {
                throw LinkMetadataFetchError.assetWriteFailed
            }

            let properties: [CFString: Any] = typeIdentifier == UTType.jpeg.identifier
                ? [kCGImageDestinationLossyCompressionQuality: 0.78]
                : [:]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw LinkMetadataFetchError.assetWriteFailed
            }

            if let maxBytes, encoded.length > maxBytes { return nil }
            let store = RustAssetStore(appSupportDirectory: appSupportDirectory)
            _ = try store.write(data: encoded as Data, relativePath: relativePath).get()
            return relativePath
        }.value
    }
}

enum LinkMetadataURLPolicy {
    static func isSupportedRemoteURL(_ url: URL) -> Bool {
        (try? RustMetadataPolicy.decision(for: url).supported) ?? false
    }

    static func isPrivacySensitive(_ url: URL) -> Bool {
        (try? RustMetadataPolicy.decision(for: url).privacySensitive) ?? true
    }
}
