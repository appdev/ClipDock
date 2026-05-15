import Foundation

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

public struct ClipboardCaptureHandlingResult: Equatable, Sendable {
    public let statusText: String?
    public let shouldRefreshList: Bool
    public let storageError: RustCoreError?

    public init(
        statusText: String?,
        shouldRefreshList: Bool,
        storageError: RustCoreError?
    ) {
        self.statusText = statusText
        self.shouldRefreshList = shouldRefreshList
        self.storageError = storageError
    }
}

public typealias ClipboardTextCapturePerformer =
    (RustCaptureTextRequest) -> Result<RustCaptureTextResult, RustCoreError>
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
public typealias ClipboardFileSnapshotCache =
    (ClipboardCapturedFiles, Int) -> ClipboardStoredFileSnapshot?

@MainActor
public final class ClipboardCaptureCoordinator {
    private let captureText: ClipboardTextCapturePerformer
    private let captureImage: ClipboardImageCapturePerformer
    private let capturePendingImageRequest: ClipboardPendingImageCapturePerformer
    private let completePendingImagePayloadRequest: ClipboardPendingImageCompletionPerformer
    private let failPendingImagePayloadRequest: ClipboardPendingImageFailurePerformer
    private let captureFiles: ClipboardFilesCapturePerformer
    private let cacheIcon: ClipboardSourceIconCache
    private let cacheImageAsset: ClipboardImageAssetCache
    private let cacheFileSnapshot: ClipboardFileSnapshotCache
    private let linkDetector: ClipboardLinkDetector

    public init(
        captureText: @escaping ClipboardTextCapturePerformer,
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
        cacheFileSnapshot: @escaping ClipboardFileSnapshotCache,
        linkDetector: ClipboardLinkDetector = ClipboardLinkDetector()
    ) {
        self.captureText = captureText
        self.captureImage = captureImage
        self.capturePendingImageRequest = capturePendingImage
        self.completePendingImagePayloadRequest = completePendingImagePayload
        self.failPendingImagePayloadRequest = failPendingImagePayload
        self.captureFiles = captureFiles
        self.cacheIcon = cacheIcon
        self.cacheImageAsset = cacheImageAsset
        self.cacheFileSnapshot = cacheFileSnapshot
        self.linkDetector = linkDetector
    }

    public func captureText(
        _ text: String,
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
        let request = RustCaptureTextRequest(
            text: text,
            detectedLink: detectedLink,
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.appName,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: cacheIcon(source),
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch captureText(request) {
        case .success:
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: "捕获：\(error.code)",
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
                statusText: "捕获：图片资产写入失败",
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
        case .success:
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: "捕获：\(error.code)",
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
        case .success:
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: "捕获：\(error.code)",
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
        case .success:
            return ClipboardCaptureHandlingResult(
                statusText: nil,
                shouldRefreshList: true,
                storageError: nil
            )

        case .failure(let error):
            return ClipboardCaptureHandlingResult(
                statusText: "捕获：\(error.code)",
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
            return "捕获：已跳过未知来源"

        case .sourceApplication:
            if let matchedRule = decision.matchedRule, !matchedRule.isEmpty {
                return "捕获：已忽略 \(matchedRule)"
            }
            return "捕获：已按应用规则跳过"

        case .windowTitle:
            if let matchedRule = decision.matchedRule, !matchedRule.isEmpty {
                return "捕获：标题命中 \(matchedRule)"
            }
            return "捕获：已按标题规则跳过"

        case nil:
            return "捕获：已按忽略规则跳过"
        }
    }

    public static func unavailablePendingImageError() -> RustCoreError {
        RustCoreError(
            code: "unavailable",
            messageKey: "clipboard.error.unavailable",
            recoverable: true,
            message: "clipboard.error.unavailable"
        )
    }
}
