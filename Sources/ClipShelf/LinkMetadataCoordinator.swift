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

actor LinkMetadataCoordinator {
    private enum Defaults {
        static let batchLimit: Int64 = 3
        static let leaseTimeoutMs: Int64 = 60_000
    }

    private let coreClient: RustCoreClient
    private let appSupportDirectory: URL
    private let fetcher: LinkMetadataFetching
    private let assetWriter: LinkMetadataAssetWriting
    private let onMetadataChanged: LinkMetadataChangeHandler
    private var isStopped = false
    private var task: Task<Void, Never>?
    private var rescheduleRequested = false

    init(
        coreClient: RustCoreClient,
        appSupportDirectory: URL,
        fetcher: LinkMetadataFetching = LinkPresentationMetadataFetcher(),
        assetWriter: LinkMetadataAssetWriting? = nil,
        onMetadataChanged: @escaping LinkMetadataChangeHandler
    ) {
        self.coreClient = coreClient
        self.appSupportDirectory = appSupportDirectory
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
        if task != nil {
            rescheduleRequested = true
            return
        }
        task = Task { [weak self] in
            await self?.runScheduledPass()
        }
    }

    func stop() {
        isStopped = true
        rescheduleRequested = false
        task?.cancel()
        task = nil
    }

    private func runScheduledPass() async {
        defer {
            task = nil
            if !isStopped, rescheduleRequested {
                rescheduleRequested = false
                scheduleSoon()
            }
        }
        while !isStopped, !Task.isCancelled {
            switch coreClient.claimLinkMetadataFetchBatch(
                appSupportDirectory: appSupportDirectory,
                limit: Defaults.batchLimit,
                leaseTimeoutMs: Defaults.leaseTimeoutMs
            ) {
            case .success(let candidates):
                guard !candidates.isEmpty else { return }
                for candidate in candidates {
                    guard !isStopped, !Task.isCancelled else { break }
                    await process(candidate)
                }
                if candidates.count < Defaults.batchLimit {
                    return
                }
            case .failure:
                return
            }
        }
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

    init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    func fetch(url: URL) async throws -> LinkMetadataFetchPayload {
        guard LinkMetadataURLPolicy.isSupportedRemoteURL(url) else {
            throw LinkMetadataFetchError.invalidURL
        }
        guard !LinkMetadataURLPolicy.isPrivacySensitive(url) else {
            throw LinkMetadataFetchError.privacySensitive
        }

        return try await MetadataProviderBox(timeout: timeout).fetchPayload(url: url)
    }
}

private final class MetadataProviderBox: @unchecked Sendable {
    private let provider = LPMetadataProvider()

    init(timeout: TimeInterval) {
        provider.timeout = timeout
        provider.shouldFetchSubresources = false
    }

    func fetchPayload(url: URL) async throws -> LinkMetadataFetchPayload {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(isolation: nil) { continuation in
                provider.startFetchingMetadata(for: url) { metadata, error in
                    if let error = error as NSError? {
                        continuation.resume(throwing: Self.fetchError(from: error))
                        return
                    }
                    guard let metadata else {
                        continuation.resume(throwing: LinkMetadataFetchError.provider)
                        return
                    }
                    let title = Self.nonEmpty(metadata.title)
                    let canonicalURL = metadata.url ?? url
                    let originalURL = metadata.originalURL
                    continuation.resume(returning: LinkMetadataFetchPayload(
                        title: title,
                        canonicalURL: canonicalURL,
                        originalURL: originalURL,
                        iconData: nil,
                        previewData: nil
                    ))
                }
            }
        } onCancel: {
            provider.cancel()
        }
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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased()
        else {
            return true
        }

        if host == "localhost" || host.hasSuffix(".local") || isPrivateIPAddress(host) {
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

    private static func isPrivateIPAddress(_ host: String) -> Bool {
        let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if host == "::1" || host == "0:0:0:0:0:0:0:1" {
            return true
        }
        if host.contains(":") {
            return host.hasPrefix("fc")
                || host.hasPrefix("fd")
                || host.hasPrefix("fe80:")
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch parts[0] {
        case 10, 127:
            return true
        case 100:
            return (64...127).contains(parts[1])
        case 172:
            return (16...31).contains(parts[1])
        case 192:
            return parts[1] == 168
        case 169:
            return parts[1] == 254
        default:
            return false
        }
    }
}
