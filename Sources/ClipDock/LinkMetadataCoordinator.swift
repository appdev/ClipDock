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
    private let appSupportDirectory: URL
    private let configuration: LinkMetadataCoordinatorConfiguration
    private let fetcher: LinkMetadataFetching
    private let assetWriter: LinkMetadataAssetWriting
    private let onMetadataChanged: LinkMetadataChangeHandler
    private var isStopped = false
    private var schedulerTask: Task<Void, Never>?
    private var activeFetchTasks: [String: Task<Void, Never>] = [:]
    private var rescheduleRequested = false

    init(
        coreClient: RustCoreClient,
        appSupportDirectory: URL,
        configuration: LinkMetadataCoordinatorConfiguration = LinkMetadataCoordinatorConfiguration(),
        fetcher: LinkMetadataFetching = LinkPresentationMetadataFetcher(),
        assetWriter: LinkMetadataAssetWriting? = nil,
        onMetadataChanged: @escaping LinkMetadataChangeHandler
    ) {
        self.coreClient = coreClient
        self.appSupportDirectory = appSupportDirectory
        self.configuration = configuration
        self.fetcher = fetcher
        self.assetWriter = assetWriter ?? LinkMetadataAssetWriter(appSupportDirectory: appSupportDirectory)
        self.onMetadataChanged = onMetadataChanged
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
        schedulerTask = Task { [weak self] in
            await self?.runScheduledPass()
        }
    }

    func stop() {
        isStopped = true
        rescheduleRequested = false
        schedulerTask?.cancel()
        schedulerTask = nil
        for task in activeFetchTasks.values {
            task.cancel()
        }
        activeFetchTasks.removeAll()
    }

    private func runScheduledPass() async {
        defer {
            schedulerTask = nil
            if !isStopped, rescheduleRequested {
                rescheduleRequested = false
                scheduleSoon()
            }
        }
        while !isStopped, !Task.isCancelled {
            let availableSlots = configuration.maxConcurrentFetches - activeFetchTasks.count
            guard availableSlots > 0 else { return }
            let claimLimit = min(configuration.batchLimit, Int64(availableSlots))
            switch coreClient.claimLinkMetadataFetchBatch(
                appSupportDirectory: appSupportDirectory,
                limit: claimLimit,
                leaseTimeoutMs: configuration.leaseTimeoutMs
            ) {
            case .success(let candidates):
                guard !candidates.isEmpty else { return }
                let activeCountBeforeStarting = activeFetchTasks.count
                for candidate in candidates {
                    guard !isStopped, !Task.isCancelled else { break }
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
        guard activeFetchTasks[candidate.itemId] == nil else { return }
        activeFetchTasks[candidate.itemId] = Task { [weak self] in
            await self?.process(candidate)
            await self?.processDidFinish(itemID: candidate.itemId)
        }
    }

    private func processDidFinish(itemID: String) {
        activeFetchTasks[itemID] = nil
        guard !isStopped else { return }
        scheduleSoon()
    }

    private func process(_ candidate: RustLinkMetadataFetchCandidate) async {
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
            guard !isStopped, !Task.isCancelled else { return }
            let assets = try await assetWriter.writeAssets(
                itemID: candidate.itemId,
                icon: payload.iconData,
                preview: payload.previewData
            )
            guard !isStopped, !Task.isCancelled else { return }
            await completeSuccess(candidate, payload: payload, assets: assets)
        } catch let error as LinkMetadataFetchError {
            await completeFailure(candidate, failureCode: error.failureCode, retry: error.shouldRetry)
        } catch {
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
        switch coreClient.completeLinkMetadataFetch(
            appSupportDirectory: appSupportDirectory,
            request: request
        ) {
        case .success(let result) where result.affectedCount > 0:
            await onMetadataChanged()
        case .success, .failure:
            break
        }
    }

    private func completeFailure(
        _ candidate: RustLinkMetadataFetchCandidate,
        failureCode: String,
        retry: Bool
    ) async {
        let nextRetryAtMs = retry ? Self.nextRetryAtMs(fetchAttempts: candidate.fetchAttempts) : nil
        switch coreClient.failLinkMetadataFetch(
            appSupportDirectory: appSupportDirectory,
            itemId: candidate.itemId,
            leaseStartedAtMs: candidate.leaseStartedAtMs,
            failureCode: failureCode,
            nextRetryAtMs: nextRetryAtMs
        ) {
        case .success(let result) where result.affectedCount > 0:
            await onMetadataChanged()
        case .success, .failure:
            break
        }
    }

    private static func nextRetryAtMs(fetchAttempts: Int64) -> Int64 {
        let delays: [Int64] = [
            5 * 60 * 1_000,
            30 * 60 * 1_000,
            6 * 60 * 60 * 1_000,
            24 * 60 * 60 * 1_000
        ]
        let index = min(max(Int(fetchAttempts), 0), delays.count - 1)
        return Int64(Date().timeIntervalSince1970 * 1_000) + delays[index]
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
            if !images.hasAssets, payload.canonicalURL != url {
                images = await imageFetcher.fetchImages(for: payload.canonicalURL)
            }
            return LinkMetadataFetchPayload(
                title: payload.title,
                canonicalURL: payload.canonicalURL,
                originalURL: payload.originalURL,
                iconData: images.iconData,
                previewData: images.previewData
            )
        } catch {
            let images = await originalImages
            guard images.hasAssets else { throw error }
            return LinkMetadataFetchPayload(
                title: nil,
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
        static let pageTimeout: TimeInterval = 8
        static let imageTimeout: TimeInterval = 6
        static let maxHTMLBytes = 512 * 1_024
        static let maxImageBytes = 5 * 1_024 * 1_024
        static let maxPreviewCandidates = 4
        static let maxIconCandidates = 4
        static let svgIconMaxPixelSize = 128
        static let svgPreviewMaxPixelSize = 640
    }

    private let httpClient: LinkMetadataHTTPClient

    init(httpClient: LinkMetadataHTTPClient = URLSessionLinkMetadataHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchImages(for pageURL: URL) async -> LinkMetadataFetchedImages {
        guard LinkMetadataURLPolicy.isSupportedRemoteURL(pageURL),
              !LinkMetadataURLPolicy.isPrivacySensitive(pageURL)
        else {
            return LinkMetadataFetchedImages(iconData: nil, previewData: nil)
        }

        guard let html = try? await loadHTML(from: pageURL) else {
            return LinkMetadataFetchedImages(iconData: nil, previewData: nil)
        }
        let candidates = LinkMetadataHTMLImageParser.imageCandidates(
            in: html,
            baseURL: pageURL
        )
        async let iconData = loadFirstImage(
            from: candidates.iconURLs,
            limit: Defaults.maxIconCandidates,
            svgMaxPixelSize: Defaults.svgIconMaxPixelSize
        )
        async let previewData = loadFirstImage(
            from: candidates.previewURLs,
            limit: Defaults.maxPreviewCandidates,
            svgMaxPixelSize: Defaults.svgPreviewMaxPixelSize
        )
        return await LinkMetadataFetchedImages(
            iconData: iconData,
            previewData: previewData
        )
    }

    private func loadHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = Defaults.pageTimeout
        request.setValue(
            "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        let (data, response) = try await httpClient.data(for: request)
        guard isSuccessfulHTTPResponse(response),
              response.mimeType?.lowercased().contains("html") != false
        else {
            throw LinkMetadataFetchError.provider
        }
        let limitedData = data.count > Defaults.maxHTMLBytes
            ? data.prefix(Defaults.maxHTMLBytes)
            : data[...]
        return String(data: Data(limitedData), encoding: .utf8)
            ?? String(data: Data(limitedData), encoding: .isoLatin1)
            ?? ""
    }

    private func loadFirstImage(
        from urls: [URL],
        limit: Int,
        svgMaxPixelSize: Int
    ) async -> LinkMetadataImagePayload? {
        for url in urls.prefix(limit) {
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
        var request = URLRequest(url: url)
        request.timeoutInterval = Defaults.imageTimeout
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await httpClient.data(for: request)
        guard isSuccessfulHTTPResponse(response), !data.isEmpty else {
            return nil
        }
        if isSVGImage(url: url, response: response, data: data) {
            return rasterizedSVGImagePayload(data, maxPixelSize: svgMaxPixelSize)
        }
        guard data.count <= Defaults.maxImageBytes,
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
        guard data.count <= Defaults.maxHTMLBytes else { return nil }
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
    private static let metaImageKeys: Set<String> = [
        "og:image",
        "og:image:url",
        "twitter:image",
        "twitter:image:src"
    ]
    private static let fallbackIconPaths = [
        "/favicon.ico",
        "/favicon.png",
        "/apple-touch-icon.png"
    ]

    static func imageCandidates(in html: String, baseURL: URL) -> LinkMetadataImageCandidates {
        let metaTags = tags(named: "meta", in: html)
        let linkTags = tags(named: "link", in: html)
        let previewURLs = metaTags.compactMap { tag -> URL? in
            let attributes = attributes(in: tag)
            let key = (attributes["property"] ?? attributes["name"])?.lowercased()
            guard let key,
                  metaImageKeys.contains(key),
                  let content = attributes["content"]
            else {
                return nil
            }
            return resolvedURL(from: content, baseURL: baseURL)
        }
        let declaredIconURLs = linkTags.compactMap { tag -> URL? in
            let attributes = attributes(in: tag)
            guard let rel = attributes["rel"]?.lowercased(),
                  rel.split(separator: " ").contains(where: { $0 == "icon" || $0 == "apple-touch-icon" }),
                  let href = attributes["href"]
            else {
                return nil
            }
            return resolvedURL(from: href, baseURL: baseURL)
        }
        return LinkMetadataImageCandidates(
            iconURLs: unique(declaredIconURLs + fallbackIconURLs(baseURL: baseURL)),
            previewURLs: unique(previewURLs)
        )
    }

    private static func tags(named name: String, in html: String) -> [String] {
        let pattern = "<\\s*\(name)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: html) else { return nil }
            return String(html[matchRange])
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>/]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [:]
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }
            let valueRange = [3, 4, 5]
                .compactMap { index -> Range<String.Index>? in
                    let range = match.range(at: index)
                    guard range.location != NSNotFound else { return nil }
                    return Range(range, in: tag)
                }
                .first
            guard let valueRange else { continue }
            result[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func resolvedURL(from value: String, baseURL: URL) -> URL? {
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              LinkMetadataURLPolicy.isSupportedRemoteURL(url),
              !LinkMetadataURLPolicy.isPrivacySensitive(url)
        else {
            return nil
        }
        return url
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { url in
            let value = url.absoluteString
            guard !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }

    private static func fallbackIconURLs(baseURL: URL) -> [URL] {
        fallbackIconPaths.compactMap { path in
            guard var components = URLComponents(
                url: baseURL,
                resolvingAgainstBaseURL: true
            ) else {
                return nil
            }
            components.path = path
            components.query = nil
            components.fragment = nil
            return components.url
        }
    }
}

protocol LinkMetadataHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionLinkMetadataHTTPClient: LinkMetadataHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
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
        let safeID = Self.safeFileStem(for: itemID)
        let iconPath = try await writeImage(
            icon,
            relativePath: "assets/link-icons/\(safeID).png",
            typeIdentifier: UTType.png.identifier,
            maxPixelSize: Limits.iconMaxPixelSize,
            maxBytes: nil
        )
        let previewPath = try await writeImage(
            preview,
            relativePath: "assets/link-previews/\(safeID).jpg",
            typeIdentifier: UTType.jpeg.identifier,
            maxPixelSize: Limits.previewMaxPixelSize,
            maxBytes: Limits.previewMaxBytes
        )
        return LinkMetadataAssetWriteResult(
            iconRelativePath: iconPath,
            imageRelativePath: previewPath
        )
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
        let fileManager = fileManager
        return try await Task.detached(priority: .utility) {
            let destinationURL = appSupportDirectory.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let temporaryURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let source = CGImageSourceCreateWithData(payload.data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let destination = CGImageDestinationCreateWithURL(
                    temporaryURL as CFURL,
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

            if let maxBytes,
               let byteCount = try? fileManager
                .attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber,
               byteCount.intValue > maxBytes {
                try? fileManager.removeItem(at: temporaryURL)
                return nil
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(
                    destinationURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            return relativePath
        }.value
    }

    private static func safeFileStem(for itemID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = itemID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? UUID().uuidString : value
    }
}

enum LinkMetadataURLPolicy {
    static func isSupportedRemoteURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
    }

    static func isPrivacySensitive(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return true
        }

        let sensitiveQueryKeywords: Set<String> = [
            "auth",
            "code",
            "jwt",
            "key",
            "otp",
            "password",
            "secret",
            "session",
            "signature",
            "token"
        ]
        return components.queryItems?.contains { item in
            let name = item.name.lowercased()
            return sensitiveQueryKeywords.contains(name)
                || sensitiveQueryKeywords.contains { keyword in
                    name.contains("_\(keyword)")
                        || name.contains("\(keyword)_")
                        || name.contains("-\(keyword)")
                        || name.contains("\(keyword)-")
                }
        } ?? false
    }
}
