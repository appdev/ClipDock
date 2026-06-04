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
            syncCandidate: ClipboardSyncCandidate(
                itemId: "text-1",
                contentHash: "hash",
                itemType: "link",
                payload: [
                    "url": .string("https://example.com"),
                    "display_url": .string("example.com"),
                    "host": .string("example.com"),
                    "text": .string("https://example.com"),
                    "summary": .string("https://example.com"),
                    "source_app_name": .string("Safari"),
                    "source_bundle_id": .string("com.apple.Safari")
                ]
            ),
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
    func capturesTextWithDisplayRichTextPreviewAsset() {
        let rtfData = Data(#"{\rtf1\ansi{\colortbl;\red0\green128\blue0;}\cf1 let value = 1\cf0}"#.utf8)
        let displayRichText = ClipboardCapturedRichText(text: "let value = 1", rtfData: rtfData)
        var capturedRequest: RustCaptureTextRequest?
        var cachedRichText: ClipboardCapturedRichText?
        var cachedChangeCount: Int?
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
            cacheRichTextAsset: { richText, changeCount in
                cachedRichText = richText
                cachedChangeCount = changeCount
                return ClipboardStoredRichTextAsset(
                    rtfRelativePath: "assets/rich-text/code.rtf",
                    byteCount: richText.rtfData.count
                )
            },
            cacheFileSnapshot: { _, _ in nil }
        )

        let result = coordinator.captureText(
            "let value = 1",
            displayRichText: displayRichText,
            changeCount: 12,
            preferences: RustPreferencesDocument(),
            source: nil
        )

        #expect(result == ClipboardCaptureHandlingResult(
            statusText: nil,
            shouldRefreshList: true,
            syncCandidate: ClipboardSyncCandidate(
                itemId: "text-1",
                contentHash: "hash",
                itemType: "text",
                payload: [
                    "text": .string("let value = 1"),
                    "summary": .string("let value = 1")
                ]
            ),
            storageError: nil
        ))
        #expect(cachedRichText == displayRichText)
        #expect(cachedChangeCount == 12)
        #expect(capturedRequest?.text == "let value = 1")
        #expect(capturedRequest?.displayRTFRelativePath == "assets/rich-text/code.rtf")
        #expect(capturedRequest?.displayRTFMimeType == "application/rtf")
        #expect(capturedRequest?.displayRTFByteCount == Int64(rtfData.count))
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
        #expect(result.hudTrigger == .none)
        #expect(capturedRequest?.text == "github.com")
        #expect(capturedRequest?.detectedLink == nil)
    }

    @Test
    @MainActor
    func capturesRichTextUsingStoredRTFAsset() {
        var capturedRequest: RustCaptureRichTextRequest?
        var didCaptureTextFallback = false
        let coordinator = ClipboardCaptureCoordinator(
            captureText: { _ in
                didCaptureTextFallback = true
                return .success(RustCaptureTextResult(
                    itemId: "text-1",
                    contentHash: "hash",
                    copyCount: 1,
                    inserted: true
                ))
            },
            captureRichText: { request in
                capturedRequest = request
                return .success(RustCaptureRichTextResult(
                    itemId: "rich-1",
                    contentHash: "rich-hash",
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
            cacheIcon: { _ in "app-icons/textedit.tiff" },
            cacheImageAsset: { _, _ in nil },
            cacheRichTextAsset: { richText, changeCount in
                #expect(richText.text == "Bold")
                #expect(changeCount == 12)
                return ClipboardStoredRichTextAsset(
                    rtfRelativePath: "assets/rich-text/bold.rtf",
                    byteCount: richText.rtfData.count
                )
            },
            cacheFileSnapshot: { _, _ in nil }
        )

        let result = coordinator.captureRichText(
            ClipboardCapturedRichText(text: "Bold", rtfData: Data("rtf".utf8)),
            changeCount: 12,
            preferences: RustPreferencesDocument(),
            source: ClipboardCaptureSource(appName: "TextEdit")
        )

        #expect(result.shouldRefreshList)
        #expect(result.hudTrigger == .none)
        #expect(!didCaptureTextFallback)
        #expect(capturedRequest?.text == "Bold")
        #expect(capturedRequest?.rtfRelativePath == "assets/rich-text/bold.rtf")
        #expect(capturedRequest?.mimeType == "application/rtf")
        #expect(capturedRequest?.byteCount == 3)
        #expect(capturedRequest?.sourceAppName == "TextEdit")
        #expect(capturedRequest?.sourceIconRelativePath == "app-icons/textedit.tiff")
    }

    @Test
    @MainActor
    func richTextAssetWriteFailureFallsBackToTextCapture() {
        var capturedTextRequest: RustCaptureTextRequest?
        let coordinator = ClipboardCaptureCoordinator(
            captureText: { request in
                capturedTextRequest = request
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
            cacheRichTextAsset: { _, _ in nil },
            cacheFileSnapshot: { _, _ in nil }
        )

        let result = coordinator.captureRichText(
            ClipboardCapturedRichText(text: "Fallback", rtfData: Data("rtf".utf8)),
            changeCount: 13,
            preferences: RustPreferencesDocument(),
            source: nil
        )

        #expect(result.shouldRefreshList)
        #expect(result.hudTrigger == .none)
        #expect(capturedTextRequest?.text == "Fallback")
        #expect(capturedTextRequest?.pasteboardChangeCount == 13)
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
        #expect(result.hudTrigger == .none)
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
            #expect(result.hudTrigger == .none)
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
        #expect(result.hudTrigger == .none)
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
        #expect(result.hudTrigger == .none)
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

    @Test
    @MainActor
    func singleFileSyncCandidateUsesServerCompatibleMIMEType() {
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

        let result = coordinator.captureFiles(
            ClipboardCapturedFiles(
                paths: ["/tmp/a.txt"],
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
                    )
                ]
            ),
            changeCount: 12,
            preferences: RustPreferencesDocument(history: RustHistoryPreferences(recordFiles: true)),
            source: ClipboardCaptureSource(appName: "Finder")
        )

        #expect(result.syncCandidate?.payload["mime_type"] == .string("text/plain"))
        #expect(result.syncCandidate?.assetRegistration?.mimeType == "text/plain")
    }

    @Test
    func handlingResultDefaultsHUDTriggerToNoneEvenWhenListRefreshes() {
        let result = ClipboardCaptureHandlingResult(
            statusText: nil,
            shouldRefreshList: true,
            storageError: nil
        )

        #expect(result.shouldRefreshList)
        #expect(result.hudTrigger == .none)
    }
}
