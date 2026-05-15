import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardCaptureCoordinatorTests {
    @Test
    @MainActor
    func capturesTextWithSourceMetadataAndIconPath() {
        var capturedRequest: RustCaptureTextRequest?
        let coordinator = ClipboardCaptureCoordinator(
            captureText: { request in
                capturedRequest = request
                return .success(RustCaptureTextResult(
                    itemId: "text-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureImage: { _ in
                .success(RustCaptureImageResult(
                    itemId: "image-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureFiles: { _ in
                .success(RustCaptureFilesResult(
                    itemId: "files-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            cacheIcon: { _ in "app-icons/safari.tiff" },
            cacheImageAsset: { _, _ in nil },
            cacheFileSnapshot: { _, _ in nil }
        )

        let source = ClipboardCaptureSource(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            bundlePath: "/Applications/Safari.app",
            windowTitle: "Example"
        )
        let result = coordinator.captureText(
            "https://example.com",
            changeCount: 8,
            preferences: RustPreferencesDocument(),
            source: source
        )

        #expect(result == ClipboardCaptureHandlingResult(
            statusText: nil,
            shouldRefreshList: true,
            storageError: nil
        ))
        #expect(capturedRequest?.text == "https://example.com")
        #expect(capturedRequest?.detectedLink == RustDetectedLink(
            originalText: "https://example.com",
            canonicalURL: "https://example.com",
            displayURL: "example.com",
            host: "example.com",
            metadataState: "pending"
        ))
        #expect(capturedRequest?.sourceBundleId == "com.apple.Safari")
        #expect(capturedRequest?.sourceAppName == "Safari")
        #expect(capturedRequest?.sourceBundlePath == "/Applications/Safari.app")
        #expect(capturedRequest?.sourceIconRelativePath == "app-icons/safari.tiff")
        #expect(capturedRequest?.sourceConfidence == "high")
        #expect(capturedRequest?.pasteboardChangeCount == 8)
    }

    @Test
    @MainActor
    func capturesProtocolLessDomainAsTextWithoutLinkMetadata() {
        var capturedRequest: RustCaptureTextRequest?
        let coordinator = ClipboardCaptureCoordinator(
            captureText: { request in
                capturedRequest = request
                return .success(RustCaptureTextResult(
                    itemId: "text-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureImage: { _ in
                .success(RustCaptureImageResult(
                    itemId: "image-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureFiles: { _ in
                .success(RustCaptureFilesResult(
                    itemId: "files-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            cacheIcon: { _ in nil },
            cacheImageAsset: { _, _ in nil },
            cacheFileSnapshot: { _, _ in nil }
        )

        let result = coordinator.captureText(
            "github.com",
            changeCount: 9,
            preferences: RustPreferencesDocument(),
            source: ClipboardCaptureSource(appName: "Finder")
        )

        #expect(result.shouldRefreshList)
        #expect(capturedRequest?.text == "github.com")
        #expect(capturedRequest?.detectedLink == nil)
    }

    @Test
    @MainActor
    func skipsCaptureWhenWindowTitleRuleMatches() {
        var didCaptureText = false
        let coordinator = ClipboardCaptureCoordinator(
            captureText: { _ in
                didCaptureText = true
                return .success(RustCaptureTextResult(
                    itemId: "text-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureImage: { _ in
                .success(RustCaptureImageResult(
                    itemId: "image-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureFiles: { _ in
                .success(RustCaptureFilesResult(
                    itemId: "files-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            cacheIcon: { _ in nil },
            cacheImageAsset: { _, _ in nil },
            cacheFileSnapshot: { _, _ in nil }
        )

        let preferences = RustPreferencesDocument(
            ignoreList: RustIgnoreListPreferences(windowTitleKeywords: ["验证码"])
        )
        let result = coordinator.captureText(
            "123456",
            changeCount: 3,
            preferences: preferences,
            source: ClipboardCaptureSource(
                appName: "Safari",
                windowTitle: "登录验证码 - Safari"
            )
        )

        #expect(!didCaptureText)
        #expect(result.statusText == "捕获：标题命中 验证码")
        #expect(!result.shouldRefreshList)
        #expect(result.storageError == nil)
    }

    @Test
    @MainActor
    func imagePreflightSkipPreventsBackgroundFinalizerAndWriterWork() {
        var didFinalizeImage = false
        var didCaptureImage = false
        let coordinator = ClipboardCaptureCoordinator(
            captureText: { _ in
                .success(RustCaptureTextResult(
                    itemId: "text-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureImage: { _ in
                didCaptureImage = true
                return .success(RustCaptureImageResult(
                    itemId: "image-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureFiles: { _ in
                .success(RustCaptureFilesResult(
                    itemId: "files-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            cacheIcon: { _ in nil },
            cacheImageAsset: { _, _ in
                Issue.record("Preflight skip should happen before image asset writing")
                return nil
            },
            cacheFileSnapshot: { _, _ in nil }
        )
        let preferences = RustPreferencesDocument(
            ignoreList: RustIgnoreListPreferences(ignoredAppIdentifiers: ["Preview"])
        )
        let source = ClipboardCaptureSource(appName: "Preview")

        if let result = coordinator.preflightCapture(source: source, preferences: preferences) {
            #expect(result.statusText == "捕获：已忽略 Preview")
            #expect(!result.shouldRefreshList)
        } else {
            didFinalizeImage = true
            _ = coordinator.captureImage(
                ClipboardCapturedImage(
                    data: Data("payload".utf8),
                    thumbnailData: Data("thumb".utf8),
                    mimeType: "image/webp",
                    fileExtension: "webp",
                    width: 10,
                    height: 10
                ),
                changeCount: 4,
                preferences: preferences,
                source: source
            )
        }

        #expect(!didFinalizeImage)
        #expect(!didCaptureImage)
    }

    @Test
    @MainActor
    func capturesImageUsingCachedAssets() {
        var capturedRequest: RustCaptureImageRequest?
        let coordinator = ClipboardCaptureCoordinator(
            captureText: { _ in
                .success(RustCaptureTextResult(
                    itemId: "text-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureImage: { request in
                capturedRequest = request
                return .success(RustCaptureImageResult(
                    itemId: "image-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureFiles: { _ in
                .success(RustCaptureFilesResult(
                    itemId: "files-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            cacheIcon: { _ in "app-icons/preview.tiff" },
            cacheImageAsset: { _, _ in
                ClipboardStoredImageAsset(
                    payloadRelativePath: "assets/image.png",
                    previewRelativePath: "thumbnails/image.png",
                    mimeType: "image/png",
                    width: 320,
                    height: 180,
                    byteCount: 42
                )
            },
            cacheFileSnapshot: { _, _ in nil }
        )

        let result = coordinator.captureImage(
            ClipboardCapturedImage(
                pngData: Data("payload".utf8),
                thumbnailPNGData: Data("thumb".utf8),
                width: 320,
                height: 180
            ),
            changeCount: 11,
            preferences: RustPreferencesDocument(),
            source: ClipboardCaptureSource(appName: "Preview")
        )

        #expect(result.shouldRefreshList)
        #expect(capturedRequest?.payloadRelativePath == "assets/image.png")
        #expect(capturedRequest?.previewRelativePath == "thumbnails/image.png")
        #expect(capturedRequest?.mimeType == "image/png")
        #expect(capturedRequest?.width == 320)
        #expect(capturedRequest?.height == 180)
        #expect(capturedRequest?.byteCount == 42)
        #expect(capturedRequest?.sourceAppName == "Preview")
    }

    @Test
    @MainActor
    func capturesFilesUsingStructuredMetadata() {
        var capturedRequest: RustCaptureFilesRequest?
        let coordinator = ClipboardCaptureCoordinator(
            captureText: { _ in
                .success(RustCaptureTextResult(
                    itemId: "text-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureImage: { _ in
                .success(RustCaptureImageResult(
                    itemId: "image-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureFiles: { request in
                capturedRequest = request
                return .success(RustCaptureFilesResult(
                    itemId: "files-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            cacheIcon: { _ in "app-icons/finder.tiff" },
            cacheImageAsset: { _, _ in nil },
            cacheFileSnapshot: { _, _ in
                Issue.record("文件元数据已经结构化入库，不应再写 JSON 快照")
                return nil
            }
        )

        let preferences = RustPreferencesDocument(
            history: RustHistoryPreferences(recordFiles: true)
        )
        let result = coordinator.captureFiles(
            ClipboardCapturedFiles(
                paths: ["/tmp/a.txt", "/tmp/b.txt"],
                fileItems: [
                    ClipboardCapturedFileMetadata(
                        path: "/tmp/a.txt",
                        fileName: "a.txt",
                        fileExtension: "txt",
                        byteCount: 24,
                        isDirectory: false,
                        width: nil,
                        height: nil,
                        contentType: "public.plain-text"
                    ),
                    ClipboardCapturedFileMetadata(
                        path: "/tmp/b.txt",
                        fileName: "b.txt",
                        fileExtension: "txt",
                        byteCount: 40,
                        isDirectory: false,
                        width: nil,
                        height: nil,
                        contentType: "public.plain-text"
                    )
                ],
                preview: ClipboardStoredFilePreview(
                    relativePath: "thumbnails/files-12.png",
                    mimeType: "image/png",
                    width: 420,
                    height: 320,
                    byteCount: 2048
                )
            ),
            changeCount: 12,
            preferences: preferences,
            source: ClipboardCaptureSource(appName: "Finder")
        )

        #expect(result.shouldRefreshList)
        #expect(capturedRequest?.snapshotRelativePath == nil)
        #expect(capturedRequest?.snapshotByteCount == 0)
        #expect(capturedRequest?.previewRelativePath == "thumbnails/files-12.png")
        #expect(capturedRequest?.previewMimeType == "image/png")
        #expect(capturedRequest?.previewWidth == 420)
        #expect(capturedRequest?.previewHeight == 320)
        #expect(capturedRequest?.previewByteCount == 2048)
        #expect(capturedRequest?.filePaths == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(capturedRequest?.fileItems.map(\.byteCount) == [24, 40])
        #expect(capturedRequest?.fileItems.first?.contentType == "public.plain-text")
        #expect(capturedRequest?.sourceAppName == "Finder")
    }
}
