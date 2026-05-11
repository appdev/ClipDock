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

    public init(paths: [String]) {
        self.paths = paths
    }
}

public struct ClipboardCapturedImage: Equatable, Sendable {
    public let pngData: Data
    public let thumbnailPNGData: Data
    public let width: Int
    public let height: Int

    public init(
        pngData: Data,
        thumbnailPNGData: Data,
        width: Int,
        height: Int
    ) {
        self.pngData = pngData
        self.thumbnailPNGData = thumbnailPNGData
        self.width = width
        self.height = height
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
    private let captureFiles: ClipboardFilesCapturePerformer
    private let cacheIcon: ClipboardSourceIconCache
    private let cacheImageAsset: ClipboardImageAssetCache
    private let cacheFileSnapshot: ClipboardFileSnapshotCache

    public init(
        captureText: @escaping ClipboardTextCapturePerformer,
        captureImage: @escaping ClipboardImageCapturePerformer,
        captureFiles: @escaping ClipboardFilesCapturePerformer,
        cacheIcon: @escaping ClipboardSourceIconCache,
        cacheImageAsset: @escaping ClipboardImageAssetCache,
        cacheFileSnapshot: @escaping ClipboardFileSnapshotCache
    ) {
        self.captureText = captureText
        self.captureImage = captureImage
        self.captureFiles = captureFiles
        self.cacheIcon = cacheIcon
        self.cacheImageAsset = cacheImageAsset
        self.cacheFileSnapshot = cacheFileSnapshot
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

        let request = RustCaptureTextRequest(
            text: text,
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
        guard preferences.history.recordImages else {
            return ClipboardCaptureHandlingResult(
                statusText: "捕获：图片记录已关闭",
                shouldRefreshList: false,
                storageError: nil
            )
        }

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

    public func captureFiles(
        _ files: ClipboardCapturedFiles,
        changeCount: Int,
        preferences: RustPreferencesDocument,
        source: ClipboardCaptureSource?
    ) -> ClipboardCaptureHandlingResult {
        guard preferences.history.recordFiles else {
            return ClipboardCaptureHandlingResult(
                statusText: "捕获：文件记录已关闭",
                shouldRefreshList: false,
                storageError: nil
            )
        }

        if let skipResult = skipResult(for: source, preferences: preferences) {
            return skipResult
        }

        guard let snapshot = cacheFileSnapshot(files, changeCount) else {
            return ClipboardCaptureHandlingResult(
                statusText: "捕获：文件快照写入失败",
                shouldRefreshList: false,
                storageError: nil
            )
        }

        let request = RustCaptureFilesRequest(
            filePaths: files.paths,
            snapshotRelativePath: snapshot.relativePath,
            snapshotByteCount: Int64(snapshot.byteCount),
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
}
