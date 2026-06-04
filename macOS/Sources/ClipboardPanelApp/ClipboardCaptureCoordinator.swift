import Foundation
import UniformTypeIdentifiers

public struct ClipboardCaptureSource: Equatable, Sendable {
    public let bundleId: String?
    public let appName: String?
    public let bundlePath: String?
    public let windowTitle: String?
    public let iconTIFFData: Data?

    public init(
        bundleId: String? = nil,
        appName: String? = nil,
        bundlePath: String? = nil,
        windowTitle: String? = nil,
        iconTIFFData: Data? = nil
    ) {
        self.bundleId = bundleId
        self.appName = appName
        self.bundlePath = bundlePath
        self.windowTitle = windowTitle
        self.iconTIFFData = iconTIFFData
    }
}

public struct ClipboardCapturedFiles: Equatable, Sendable {
    public let paths: [String]
    public let fileItems: [ClipboardCapturedFileMetadata]
    public let preview: ClipboardStoredFilePreview?

    public init(
        paths: [String],
        fileItems: [ClipboardCapturedFileMetadata] = [],
        preview: ClipboardStoredFilePreview? = nil
    ) {
        self.paths = paths
        self.fileItems = fileItems
        self.preview = preview
    }
}

public struct ClipboardCapturedFileMetadata: Equatable, Codable, Sendable {
    public let path: String
    public let fileName: String
    public let fileExtension: String?
    public let byteCount: Int64
    public let isDirectory: Bool
    public let width: Int64?
    public let height: Int64?
    public let contentType: String?

    public init(
        path: String,
        fileName: String,
        fileExtension: String?,
        byteCount: Int64,
        isDirectory: Bool,
        width: Int64?,
        height: Int64?,
        contentType: String?
    ) {
        self.path = path
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.isDirectory = isDirectory
        self.width = width
        self.height = height
        self.contentType = contentType
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case fileName = "file_name"
        case fileExtension = "file_extension"
        case byteCount = "byte_count"
        case isDirectory = "is_directory"
        case width
        case height
        case contentType = "content_type"
    }
}

public struct ClipboardCapturedImage: Equatable, Sendable {
    public let data: Data
    public let thumbnailData: Data
    public let mimeType: String
    public let fileExtension: String
    public let width: Int
    public let height: Int

    public init(
        data: Data,
        thumbnailData: Data,
        mimeType: String,
        fileExtension: String,
        width: Int,
        height: Int
    ) {
        self.data = data
        self.thumbnailData = thumbnailData
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
    }

    public init(
        pngData: Data,
        thumbnailPNGData: Data,
        width: Int,
        height: Int
    ) {
        self.init(
            data: pngData,
            thumbnailData: thumbnailPNGData,
            mimeType: "image/png",
            fileExtension: "png",
            width: width,
            height: height
        )
    }

    public var pngData: Data { data }
    public var thumbnailPNGData: Data { thumbnailData }
}

public struct ClipboardCapturedRichText: Equatable, Sendable {
    public let text: String
    public let rtfData: Data

    public init(text: String, rtfData: Data) {
        self.text = text
        self.rtfData = rtfData
    }
}

public struct ClipboardStoredRichTextAsset: Equatable, Sendable {
    public let rtfRelativePath: String
    public let mimeType: String
    public let byteCount: Int

    public init(
        rtfRelativePath: String,
        mimeType: String = "application/rtf",
        byteCount: Int
    ) {
        self.rtfRelativePath = rtfRelativePath
        self.mimeType = mimeType
        self.byteCount = byteCount
    }
}

public struct ClipboardStoredFileSnapshot: Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int

    public init(relativePath: String, byteCount: Int) {
        self.relativePath = relativePath
        self.byteCount = byteCount
    }
}

public struct ClipboardStoredImageAsset: Equatable, Sendable {
    public let payloadRelativePath: String
    public let previewRelativePath: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let byteCount: Int

    public init(
        payloadRelativePath: String,
        previewRelativePath: String,
        mimeType: String,
        width: Int,
        height: Int,
        byteCount: Int
    ) {
        self.payloadRelativePath = payloadRelativePath
        self.previewRelativePath = previewRelativePath
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }
}

public struct ClipboardPendingImageAsset: Equatable, Sendable {
    public let thumbnailRelativePath: String
    public let reservedPayloadRelativePath: String
    public let stagedPayloadRelativePath: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let thumbnailWidth: Int
    public let thumbnailHeight: Int
    public let thumbnailByteCount: Int

    public init(
        thumbnailRelativePath: String,
        reservedPayloadRelativePath: String,
        stagedPayloadRelativePath: String,
        mimeType: String,
        width: Int,
        height: Int,
        thumbnailWidth: Int,
        thumbnailHeight: Int,
        thumbnailByteCount: Int
    ) {
        self.thumbnailRelativePath = thumbnailRelativePath
        self.reservedPayloadRelativePath = reservedPayloadRelativePath
        self.stagedPayloadRelativePath = stagedPayloadRelativePath
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.thumbnailWidth = thumbnailWidth
        self.thumbnailHeight = thumbnailHeight
        self.thumbnailByteCount = thumbnailByteCount
    }
}

public struct ClipboardCompletedPendingImageAsset: Equatable, Sendable {
    public let jobID: String
    public let stagedPayloadRelativePath: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let byteCount: Int

    public init(
        jobID: String,
        stagedPayloadRelativePath: String,
        mimeType: String,
        width: Int,
        height: Int,
        byteCount: Int
    ) {
        self.jobID = jobID
        self.stagedPayloadRelativePath = stagedPayloadRelativePath
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }
}

public struct ClipboardStoredFilePreview: Equatable, Sendable {
    public let relativePath: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let byteCount: Int

    public init(
        relativePath: String,
        mimeType: String,
        width: Int,
        height: Int,
        byteCount: Int
    ) {
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }
}

public enum ClipboardCaptureHUDTrigger: Equatable, Sendable {
    case none
    case copyCompleted(eventID: String)
}

public struct ClipboardSyncCandidate: Equatable, Sendable {
    public let itemId: String
    public let contentHash: String
    public let itemType: String
    public let payload: [String: SyncEventPayloadValue]
    public let copyCountDelta: Int64
    public let assetRegistration: SyncOutboxAssetRegistration?

    public init(
        itemId: String,
        contentHash: String,
        itemType: String,
        payload: [String: SyncEventPayloadValue],
        copyCountDelta: Int64 = 1,
        assetRegistration: SyncOutboxAssetRegistration? = nil
    ) {
        self.itemId = itemId
        self.contentHash = contentHash
        self.itemType = itemType
        self.payload = payload
        self.copyCountDelta = copyCountDelta
        self.assetRegistration = assetRegistration
    }
}

public struct ClipboardCaptureHandlingResult: Equatable, Sendable {
    public let statusText: String?
    public let shouldRefreshList: Bool
    public let hudTrigger: ClipboardCaptureHUDTrigger
    public let syncCandidate: ClipboardSyncCandidate?
    public let storageError: RustCoreError?

    public init(
        statusText: String?,
        shouldRefreshList: Bool,
        hudTrigger: ClipboardCaptureHUDTrigger = .none,
        syncCandidate: ClipboardSyncCandidate? = nil,
        storageError: RustCoreError?
    ) {
        self.statusText = statusText
        self.shouldRefreshList = shouldRefreshList
        self.hudTrigger = hudTrigger
        self.syncCandidate = syncCandidate
        self.storageError = storageError
    }
}

public typealias ClipboardTextCapturePerformer =
    (RustCaptureTextRequest) -> Result<RustCaptureTextResult, RustCoreError>
public typealias ClipboardRichTextCapturePerformer =
    (RustCaptureRichTextRequest) -> Result<RustCaptureRichTextResult, RustCoreError>
public typealias ClipboardImageCapturePerformer =
    (RustCaptureImageRequest) -> Result<RustCaptureImageResult, RustCoreError>
public typealias ClipboardPendingImageCapturePerformer =
    (RustCapturePendingImageRequest) -> Result<RustPendingImageCaptureResult, RustCoreError>
public typealias ClipboardPendingImageCompletionPerformer =
    (RustCompletePendingImagePayloadRequest) -> Result<RustPendingImageCompletionResult, RustCoreError>
public typealias ClipboardPendingImageFailurePerformer =
    (RustFailPendingImagePayloadRequest) -> Result<RustPendingImageCompletionResult, RustCoreError>
public typealias ClipboardFilesCapturePerformer =
    (RustCaptureFilesRequest) -> Result<RustCaptureFilesResult, RustCoreError>
public typealias ClipboardSourceIconCache = (ClipboardCaptureSource?) -> String?
public typealias ClipboardImageAssetCache =
    (ClipboardCapturedImage, Int) -> ClipboardStoredImageAsset?
public typealias ClipboardRichTextAssetCache =
    (ClipboardCapturedRichText, Int) -> ClipboardStoredRichTextAsset?
public typealias ClipboardFileSnapshotCache =
    (ClipboardCapturedFiles, Int) -> ClipboardStoredFileSnapshot?

@MainActor
public final class ClipboardCaptureCoordinator {
    private let captureText: ClipboardTextCapturePerformer
    private let captureRichTextRequest: ClipboardRichTextCapturePerformer
    private let captureImage: ClipboardImageCapturePerformer
    private let capturePendingImageRequest: ClipboardPendingImageCapturePerformer
    private let completePendingImagePayloadRequest: ClipboardPendingImageCompletionPerformer
    private let failPendingImagePayloadRequest: ClipboardPendingImageFailurePerformer
    private let captureFiles: ClipboardFilesCapturePerformer
    private let cacheIcon: ClipboardSourceIconCache
    private let cacheImageAsset: ClipboardImageAssetCache
    private let cacheRichTextAsset: ClipboardRichTextAssetCache
    private let cacheFileSnapshot: ClipboardFileSnapshotCache
    private let linkDetector: ClipboardLinkDetector

    public init(
        captureText: @escaping ClipboardTextCapturePerformer,
        captureRichText: @escaping ClipboardRichTextCapturePerformer = { _ in
            .failure(ClipboardCaptureCoordinator.unavailableRichTextError())
        },
        captureImage: @escaping ClipboardImageCapturePerformer,
        capturePendingImage: @escaping ClipboardPendingImageCapturePerformer = { _ in
            .failure(ClipboardCaptureCoordinator.unavailablePendingImageError())
        },
        completePendingImagePayload: @escaping ClipboardPendingImageCompletionPerformer = { _ in
            .failure(ClipboardCaptureCoordinator.unavailablePendingImageError())
        },
        failPendingImagePayload: @escaping ClipboardPendingImageFailurePerformer = { _ in
            .failure(ClipboardCaptureCoordinator.unavailablePendingImageError())
        },
        captureFiles: @escaping ClipboardFilesCapturePerformer,
        cacheIcon: @escaping ClipboardSourceIconCache,
        cacheImageAsset: @escaping ClipboardImageAssetCache,
        cacheRichTextAsset: @escaping ClipboardRichTextAssetCache = { _, _ in nil },
        cacheFileSnapshot: @escaping ClipboardFileSnapshotCache,
        linkDetector: ClipboardLinkDetector = ClipboardLinkDetector()
    ) {
        self.captureText = captureText
        self.captureRichTextRequest = captureRichText
        self.captureImage = captureImage
        self.capturePendingImageRequest = capturePendingImage
        self.completePendingImagePayloadRequest = completePendingImagePayload
        self.failPendingImagePayloadRequest = failPendingImagePayload
        self.captureFiles = captureFiles
        self.cacheIcon = cacheIcon
        self.cacheImageAsset = cacheImageAsset
        self.cacheRichTextAsset = cacheRichTextAsset
        self.cacheFileSnapshot = cacheFileSnapshot
        self.linkDetector = linkDetector
    }

    public func captureText(
        _ text: String,
        displayRichText: ClipboardCapturedRichText? = nil,
        changeCount: Int,
        preferences: RustPreferencesDocument,
        source: ClipboardCaptureSource?
    ) -> ClipboardCaptureHandlingResult {
        if let skipResult = skipResult(for: source, preferences: preferences) {
            return skipResult
        }

        let detectedLink = linkDetector.detectPureLink(in: text).map { link in
            RustDetectedLink(
                originalText: link.originalText,
                canonicalURL: link.canonicalURL,
                displayURL: link.displayURL,
                host: link.host,
                metadataState: "pending"
            )
        }
        let storedDisplayRTF = displayRichText.flatMap { richText in
            cacheRichTextAsset(richText, changeCount)
        }
        let request = RustCaptureTextRequest(
            text: text,
            detectedLink: detectedLink,
            displayRTFRelativePath: storedDisplayRTF?.rtfRelativePath,
            displayRTFMimeType: storedDisplayRTF?.mimeType,
            displayRTFByteCount: Int64(storedDisplayRTF?.byteCount ?? 0),
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.appName,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: cacheIcon(source),
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch captureText(request) {
        case .success(let result):
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                syncCandidate: syncCandidate(
                    result: result,
                    text: text,
                    detectedLink: detectedLink,
                    source: source
                ),
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: AppLocalization.format("capture.status.error", defaultValue: "捕获：%@", error.code),
                shouldRefreshList: false,
                storageError: error
            )
        }
    }

    public func captureRichText(
        _ richText: ClipboardCapturedRichText,
        changeCount: Int,
        preferences: RustPreferencesDocument,
        source: ClipboardCaptureSource?
    ) -> ClipboardCaptureHandlingResult {
        if let skipResult = skipResult(for: source, preferences: preferences) {
            return skipResult
        }

        guard let storedAsset = cacheRichTextAsset(richText, changeCount) else {
            return captureText(
                richText.text,
                changeCount: changeCount,
                preferences: preferences,
                source: source
            )
        }

        let request = RustCaptureRichTextRequest(
            text: richText.text,
            rtfRelativePath: storedAsset.rtfRelativePath,
            mimeType: storedAsset.mimeType,
            byteCount: Int64(storedAsset.byteCount),
            contentHash: nil,
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.appName,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: cacheIcon(source),
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch captureRichTextRequest(request) {
        case .success(let result):
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                syncCandidate: syncCandidate(
                    result: result,
                    richText: richText,
                    storedAsset: storedAsset,
                    source: source
                ),
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: AppLocalization.format("capture.status.error", defaultValue: "捕获：%@", error.code),
                shouldRefreshList: false,
                storageError: error
            )
        }
    }

    public func captureImage(
        _ image: ClipboardCapturedImage,
        changeCount: Int,
        preferences: RustPreferencesDocument,
        source: ClipboardCaptureSource?
    ) -> ClipboardCaptureHandlingResult {
        if let skipResult = skipResult(for: source, preferences: preferences) {
            return skipResult
        }

        guard let storedImage = cacheImageAsset(image, changeCount) else {
            return ClipboardCaptureHandlingResult(
                statusText: AppLocalization.text("capture.status.imageAssetWriteFailed", defaultValue: "捕获：图片资产写入失败"),
                shouldRefreshList: false,
                storageError: nil
            )
        }

        let request = RustCaptureImageRequest(
            payloadRelativePath: storedImage.payloadRelativePath,
            previewRelativePath: storedImage.previewRelativePath,
            mimeType: storedImage.mimeType,
            width: Int64(storedImage.width),
            height: Int64(storedImage.height),
            byteCount: Int64(storedImage.byteCount),
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.appName,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: cacheIcon(source),
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch captureImage(request) {
        case .success(let result):
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                syncCandidate: syncCandidate(
                    result: result,
                    storedImage: storedImage,
                    source: source
                ),
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: AppLocalization.format("capture.status.error", defaultValue: "捕获：%@", error.code),
                shouldRefreshList: false,
                storageError: error
            )
        }
    }

    public func capturePreparedImage(
        _ storedImage: ClipboardStoredImageAsset,
        changeCount: Int,
        preferences: RustPreferencesDocument,
        source: ClipboardCaptureSource?
    ) -> ClipboardCaptureHandlingResult {
        if let skipResult = skipResult(for: source, preferences: preferences) {
            return skipResult
        }

        let request = RustCaptureImageRequest(
            payloadRelativePath: storedImage.payloadRelativePath,
            previewRelativePath: storedImage.previewRelativePath,
            mimeType: storedImage.mimeType,
            width: Int64(storedImage.width),
            height: Int64(storedImage.height),
            byteCount: Int64(storedImage.byteCount),
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.appName,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: cacheIcon(source),
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch captureImage(request) {
        case .success(let result):
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                syncCandidate: syncCandidate(
                    result: result,
                    storedImage: storedImage,
                    source: source
                ),
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: AppLocalization.format("capture.status.error", defaultValue: "捕获：%@", error.code),
                shouldRefreshList: false,
                storageError: error
            )
        }
    }

    public func capturePendingImage(
        _ pendingImage: ClipboardPendingImageAsset,
        changeCount: Int,
        preferences: RustPreferencesDocument,
        source: ClipboardCaptureSource?,
        ownerSessionID: String
    ) -> Result<RustPendingImageCaptureResult, RustCoreError> {
        if let skipResult = skipResult(for: source, preferences: preferences) {
            return .failure(skipResult.storageError ?? Self.unavailablePendingImageError())
        }

        let request = RustCapturePendingImageRequest(
            ownerSessionId: ownerSessionID,
            thumbnailRelativePath: pendingImage.thumbnailRelativePath,
            reservedPayloadRelativePath: pendingImage.reservedPayloadRelativePath,
            stagedPayloadRelativePath: pendingImage.stagedPayloadRelativePath,
            mimeType: pendingImage.mimeType,
            width: Int64(pendingImage.width),
            height: Int64(pendingImage.height),
            thumbnailWidth: Int64(pendingImage.thumbnailWidth),
            thumbnailHeight: Int64(pendingImage.thumbnailHeight),
            thumbnailByteCount: Int64(pendingImage.thumbnailByteCount),
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.appName,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: cacheIcon(source),
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )
        return capturePendingImageRequest(request)
    }

    public func completePendingImagePayload(
        _ completedImage: ClipboardCompletedPendingImageAsset
    ) -> Result<RustPendingImageCompletionResult, RustCoreError> {
        completePendingImagePayloadRequest(RustCompletePendingImagePayloadRequest(
            jobId: completedImage.jobID,
            stagedPayloadRelativePath: completedImage.stagedPayloadRelativePath,
            mimeType: completedImage.mimeType,
            width: Int64(completedImage.width),
            height: Int64(completedImage.height),
            byteCount: Int64(completedImage.byteCount)
        ))
    }

    public func failPendingImagePayload(
        jobID: String,
        stagedPayloadRelativePath: String?,
        failureCode: String
    ) -> Result<RustPendingImageCompletionResult, RustCoreError> {
        failPendingImagePayloadRequest(RustFailPendingImagePayloadRequest(
            jobId: jobID,
            stagedPayloadRelativePath: stagedPayloadRelativePath,
            failureCode: failureCode
        ))
    }

    public func captureFiles(
        _ files: ClipboardCapturedFiles,
        changeCount: Int,
        preferences: RustPreferencesDocument,
        source: ClipboardCaptureSource?
    ) -> ClipboardCaptureHandlingResult {
        if let skipResult = skipResult(for: source, preferences: preferences) {
            return skipResult
        }

        let request = RustCaptureFilesRequest(
            filePaths: files.paths,
            fileItems: files.fileItems,
            previewRelativePath: files.preview?.relativePath,
            previewMimeType: files.preview?.mimeType,
            previewWidth: Int64(files.preview?.width ?? 0),
            previewHeight: Int64(files.preview?.height ?? 0),
            previewByteCount: Int64(files.preview?.byteCount ?? 0),
            snapshotRelativePath: nil,
            snapshotByteCount: 0,
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.appName,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: cacheIcon(source),
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch captureFiles(request) {
        case .success(let result):
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                syncCandidate: syncCandidate(
                    result: result,
                    files: files,
                    source: source
                ),
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: AppLocalization.format("capture.status.error", defaultValue: "捕获：%@", error.code),
                shouldRefreshList: false,
                storageError: error
            )
        }
    }

    public func preflightCapture(
        source: ClipboardCaptureSource?,
        preferences: RustPreferencesDocument
    ) -> ClipboardCaptureHandlingResult? {
        skipResult(for: source, preferences: preferences)
    }

    private func skipResult(
        for source: ClipboardCaptureSource?,
        preferences: RustPreferencesDocument
    ) -> ClipboardCaptureHandlingResult? {
        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: source.map {
                ClipboardIgnoreRuleSource(
                    bundleId: $0.bundleId,
                    appName: $0.appName,
                    bundlePath: $0.bundlePath
                )
            },
            windowTitle: source?.windowTitle,
            preferences: preferences.ignoreList
        )

        guard decision.shouldSkip else {
            return nil
        }

        return ClipboardCaptureHandlingResult(
            statusText: captureSkipStatusText(for: decision),
            shouldRefreshList: false,
            storageError: nil
        )
    }

    private func captureSkipStatusText(
        for decision: ClipboardIgnoreRuleDecision
    ) -> String {
        switch decision.reason {
        case .unknownSource:
            return AppLocalization.text("capture.status.skippedUnknownSource", defaultValue: "捕获：已跳过未知来源")

        case .sourceApplication:
            if let matchedRule = decision.matchedRule, !matchedRule.isEmpty {
                return AppLocalization.format("capture.status.ignoredRule", defaultValue: "捕获：已忽略 %@", matchedRule)
            }
            return AppLocalization.text("capture.status.skippedApplicationRule", defaultValue: "捕获：已按应用规则跳过")

        case .windowTitle:
            if let matchedRule = decision.matchedRule, !matchedRule.isEmpty {
                return AppLocalization.format("capture.status.matchedWindowTitle", defaultValue: "捕获：标题命中 %@", matchedRule)
            }
            return AppLocalization.text("capture.status.skippedWindowTitleRule", defaultValue: "捕获：已按标题规则跳过")

        case nil:
            return AppLocalization.text("capture.status.skippedIgnoreRule", defaultValue: "捕获：已按忽略规则跳过")
        }
    }

    private func syncCandidate(
        result: RustCaptureTextResult,
        text: String,
        detectedLink: RustDetectedLink?,
        source: ClipboardCaptureSource?
    ) -> ClipboardSyncCandidate {
        if let detectedLink {
            return ClipboardSyncCandidate(
                itemId: result.itemId,
                contentHash: result.contentHash,
                itemType: "link",
                payload: payload(
                    [
                        "url": .string(detectedLink.canonicalURL),
                        "display_url": .string(detectedLink.displayURL),
                        "host": .string(detectedLink.host),
                        "text": .string(text),
                        "summary": .string(text.linePreview())
                    ],
                    source: source
                )
            )
        }

        if let colorValue = ClipboardColorValue(normalizedHex: text) {
            return ClipboardSyncCandidate(
                itemId: result.itemId,
                contentHash: result.contentHash,
                itemType: "color",
                payload: payload(
                    [
                        "hex": .string(colorValue.normalizedHex),
                        "color": .string(colorValue.normalizedHex),
                        "summary": .string(colorValue.previewMetadataText)
                    ],
                    source: source
                )
            )
        }

        return ClipboardSyncCandidate(
            itemId: result.itemId,
            contentHash: result.contentHash,
            itemType: "text",
            payload: payload(
                [
                    "text": .string(text),
                    "summary": .string(text.linePreview())
                ],
                source: source
            )
        )
    }

    private func syncCandidate(
        result: RustCaptureRichTextResult,
        richText: ClipboardCapturedRichText,
        storedAsset: ClipboardStoredRichTextAsset,
        source: ClipboardCaptureSource?
    ) -> ClipboardSyncCandidate {
        ClipboardSyncCandidate(
            itemId: result.itemId,
            contentHash: result.contentHash,
            itemType: "rich_text",
            payload: payload(
                [
                    "plain_text": .string(richText.text),
                    "text": .string(richText.text),
                    "summary": .string(richText.text.linePreview()),
                    "mime_type": .string(storedAsset.mimeType),
                    "byte_count": .int(Int64(storedAsset.byteCount))
                ],
                source: source
            )
        )
    }

    private func syncCandidate(
        result: RustCaptureImageResult,
        storedImage: ClipboardStoredImageAsset,
        source: ClipboardCaptureSource?
    ) -> ClipboardSyncCandidate {
        ClipboardSyncCandidate(
            itemId: result.itemId,
            contentHash: result.contentHash,
            itemType: "image",
            payload: payload(
                [
                    "file_name": .string(storedImage.payloadRelativePath.lastPathComponentFallback(defaultValue: "image")),
                    "mime_type": .string(storedImage.mimeType),
                    "byte_count": .int(Int64(storedImage.byteCount)),
                    "summary": .string("image")
                ],
                source: source
            ),
            assetRegistration: SyncOutboxAssetRegistration(
                filePath: storedImage.payloadRelativePath,
                kind: "image_payload",
                mimeType: storedImage.mimeType
            )
        )
    }

    private func syncCandidate(
        result: RustCaptureFilesResult,
        files: ClipboardCapturedFiles,
        source: ClipboardCaptureSource?
    ) -> ClipboardSyncCandidate? {
        guard files.paths.count == 1,
              let path = files.paths.first,
              let file = files.fileItems.first,
              !file.isDirectory else {
            return nil
        }

        return ClipboardSyncCandidate(
            itemId: result.itemId,
            contentHash: result.contentHash,
            itemType: "file",
            payload: payload(filePayload(for: file, path: path), source: source),
            assetRegistration: SyncOutboxAssetRegistration(
                filePath: path,
                kind: "file_payload",
                mimeType: syncMIMEType(for: file, path: path)
            )
        )
    }

    private func filePayload(
        for file: ClipboardCapturedFileMetadata,
        path: String
    ) -> [String: SyncEventPayloadValue] {
        var payload: [String: SyncEventPayloadValue] = [
            "file_name": .string(file.fileName),
            "summary": .string(file.fileName),
            "byte_count": .int(file.byteCount)
        ]
        if let mimeType = syncMIMEType(for: file, path: path) {
            payload["mime_type"] = .string(mimeType)
        }
        return payload
    }

    private func syncMIMEType(
        for file: ClipboardCapturedFileMetadata,
        path: String
    ) -> String? {
        if let contentType = file.contentType?.trimmedNonEmpty {
            if contentType.contains("/") {
                return contentType
            }
            if let mimeType = UTType(contentType)?.preferredMIMEType {
                return mimeType
            }
        }

        let fileExtension = (path as NSString).pathExtension.trimmedNonEmpty
        guard let fileExtension,
              let mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType else {
            return nil
        }
        return mimeType
    }

    private func payload(
        _ values: [String: SyncEventPayloadValue],
        source: ClipboardCaptureSource?
    ) -> [String: SyncEventPayloadValue] {
        var payload = values
        if let appName = source?.appName?.trimmedNonEmpty {
            payload["source_app_name"] = .string(appName)
        }
        if let bundleId = source?.bundleId?.trimmedNonEmpty {
            payload["source_bundle_id"] = .string(bundleId)
        }
        return payload
    }

    public static func unavailablePendingImageError() -> RustCoreError {
        RustCoreError(
            code: "unavailable",
            messageKey: "clipboard.error.unavailable",
            recoverable: true,
            message: "clipboard.error.unavailable"
        )
    }

    public static func unavailableRichTextError() -> RustCoreError {
        RustCoreError(
            code: "unavailable",
            messageKey: "clipboard.error.unavailable",
            recoverable: true,
            message: "clipboard.error.unavailable"
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func linePreview(max length: Int = 120) -> String {
        let singleLine = trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        guard singleLine.count > length else {
            return singleLine
        }
        return String(singleLine.prefix(length))
    }

    func lastPathComponentFallback(defaultValue: String) -> String {
        let component = (self as NSString).lastPathComponent.trimmedNonEmpty
        return component ?? defaultValue
    }
}
