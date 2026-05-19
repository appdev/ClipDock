import Foundation
import Testing
@testable import ClipboardPanelApp

struct RustCoreClientTests {
    @Test
    func rustCoreClientIsSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(RustCoreClient.self)
    }

    @Test
    func encodesLosslessWebPThroughSwiftBridge() throws {
        let rgbaData = Data([
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 255, 255
        ])

        let webPData = try RustCoreClient()
            .encodeLosslessWebP(rgbaData: rgbaData, width: 2, height: 2)
            .get()

        #expect(String(bytes: webPData.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(bytes: webPData.dropFirst(8).prefix(4), encoding: .ascii) == "WEBP")
    }

    @Test
    func rasterizesSVGToPNGThroughSwiftBridge() throws {
        let svgData = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
          <rect width="512" height="512" fill="#1A5FB8" rx="112"/>
          <rect x="84" y="126" width="222" height="64" fill="#FFFFFF" rx="24"/>
        </svg>
        """.utf8)

        let result = try RustCoreClient()
            .rasterizeSVGToPNG(svgData: svgData, maxWidth: 128, maxHeight: 128)
            .get()

        #expect(result.width == 128)
        #expect(result.height == 128)
        #expect(result.pngData.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test
    func opensRustCoreThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        let value = try client.open(appSupportDirectory: tempDirectory).get()

        #expect(value.databasePath.hasSuffix("clipboard.sqlite"))
        #expect(value.schemaVersion == 11)
        #expect(value.itemCount == 0)
        #expect(value.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("clipboard.sqlite").path))
    }

    @Test
    func listsEmptyHistoryThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        let value = try client.listItems(appSupportDirectory: tempDirectory).get()

        #expect(value.items.isEmpty)
        #expect(value.totalCount == 0)
        #expect(!value.hasMore)
        #expect(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("clipboard.sqlite").path))
    }

    @Test
    func listItemsFiltersColorTypeThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "#ff00aa",
                sourceBundleId: "com.example.Color",
                sourceAppName: "Color",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 1
            )
        ).get()
        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "text #FF00AA",
                sourceBundleId: "com.example.Notes",
                sourceAppName: "Notes",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 2
            )
        ).get()

        let colorPage = try client.listItems(
            appSupportDirectory: tempDirectory,
            itemType: "color",
            searchText: "#FF00AA"
        ).get()
        let textPage = try client.listItems(
            appSupportDirectory: tempDirectory,
            itemType: "text",
            searchText: "#FF00AA"
        ).get()

        #expect(colorPage.totalCount == 1)
        #expect(colorPage.items[0].itemType == "color")
        #expect(colorPage.items[0].summary == "#FF00AA")
        #expect(colorPage.items[0].primaryText == "#FF00AA")
        #expect(textPage.totalCount == 1)
        #expect(textPage.items[0].itemType == "text")
    }

    @Test
    func capturesAndDeduplicatesTextThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        let request = RustCaptureTextRequest(
            text: "https://example.com",
            sourceBundleId: "com.apple.Safari",
            sourceAppName: "Safari",
            sourceBundlePath: "/Applications/Safari.app",
            sourceIconRelativePath: "app-icons/safari.tiff",
            sourceConfidence: "high",
            pasteboardChangeCount: 1
        )

        let first = try client.captureText(appSupportDirectory: tempDirectory, request: request).get()
        let second = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "https://example.com",
                sourceBundleId: "com.apple.Safari",
                sourceAppName: "Safari",
                sourceBundlePath: "/Applications/Safari.app",
                sourceIconRelativePath: "app-icons/safari.tiff",
                sourceConfidence: "high",
                pasteboardChangeCount: 2
            )
        ).get()
        let page = try client.listItems(appSupportDirectory: tempDirectory).get()

        #expect(first.inserted)
        #expect(!second.inserted)
        #expect(first.itemId == second.itemId)
        #expect(second.copyCount == 2)
        #expect(page.totalCount == 1)
        #expect(page.items.count == 1)
        #expect(page.items[0].itemType == "link")
        #expect(page.items[0].copyCount == 2)
        #expect(page.items[0].sourceAppName == "Safari")
        #expect(page.items[0].sourceAppIconPath?.hasSuffix("app-icons/safari.tiff") == true)
        #expect(page.items[0].linkMetadata?.canonicalURL == "https://example.com")
        #expect(page.items[0].linkMetadata?.host == "example.com")
        #expect(page.items[0].linkMetadata?.metadataState == "pending")
    }

    @Test
    func sourceAppIconHeaderColorRoundTripsThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Header color bridge",
                sourceBundleId: "com.apple.Safari",
                sourceAppName: "Safari",
                sourceBundlePath: "/Applications/Safari.app",
                sourceIconRelativePath: "app-icons/safari.tiff",
                sourceConfidence: "high",
                pasteboardChangeCount: 11
            )
        ).get()

        let beforePage = try client.listItems(appSupportDirectory: tempDirectory).get()
        let item = try #require(beforePage.items.first)
        let sourceAppID = try #require(item.sourceAppId)
        let sourceIconPath = try #require(item.sourceAppIconPath)
        #expect(item.sourceAppIconHeaderColor == nil)
        #expect(RustCoreClient.activeSourceIconHeaderColorCacheVersion() == 1)

        let color: Int64 = 4_281_553_305
        let update = try client.updateSourceAppIconHeaderColor(
            appSupportDirectory: tempDirectory,
            sourceAppId: sourceAppID,
            sourceAppIconPath: sourceIconPath,
            headerColorARGB: color
        ).get()
        let afterPage = try client.listItems(appSupportDirectory: tempDirectory).get()
        let sourceApps = try client.listSourceApps(appSupportDirectory: tempDirectory).get()

        #expect(update.affectedCount == 1)
        #expect(afterPage.items.first?.sourceAppIconHeaderColor == color)
        #expect(sourceApps.apps.first?.iconHeaderColor == color)
    }

    @Test
    func sourceAppIconHeaderColorDecodesFromBridgeJSONField() throws {
        let json = """
        {
          "id": "item-1",
          "item_type": "text",
          "summary": "Example",
          "primary_text": "Example",
          "content_hash": "hash",
          "source_app_id": "source-app",
          "source_app_name": "Safari",
          "source_app_icon_path": "/tmp/icon.png",
          "source_app_icon_header_color": 4281553305,
          "preview_asset_path": null,
          "payload_asset_path": null,
          "source_confidence": "high",
          "first_copied_at_ms": 1,
          "last_copied_at_ms": 2,
          "copy_count": 1,
          "is_pinned": false,
          "size_bytes": 12,
          "preview_state": "ready",
          "file_items": []
        }
        """

        let item = try JSONDecoder().decode(
            RustClipboardItemSummary.self,
            from: Data(json.utf8)
        )

        #expect(item.sourceAppIconHeaderColor == 4_281_553_305)
    }

    @Test
    func payloadStateDefaultsToReadyWhenBridgeJSONOmitsField() throws {
        let json = """
        {
          "id": "item-1",
          "item_type": "image",
          "summary": "图片",
          "primary_text": null,
          "content_hash": "hash",
          "source_app_id": null,
          "source_app_name": "Preview",
          "source_app_icon_path": null,
          "source_app_icon_header_color": null,
          "preview_asset_path": "thumbnails/image.webp",
          "payload_asset_path": "assets/image.webp",
          "source_confidence": "high",
          "first_copied_at_ms": 1,
          "last_copied_at_ms": 2,
          "copy_count": 1,
          "is_pinned": false,
          "size_bytes": 12,
          "preview_state": "ready",
          "file_items": []
        }
        """

        let item = try JSONDecoder().decode(
            RustClipboardItemSummary.self,
            from: Data(json.utf8)
        )

        #expect(item.payloadState == "ready")
    }

    @Test
    func linkMetadataFetchStateRoundTripsThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "https://example.com/docs",
                sourceBundleId: "com.apple.Safari",
                sourceAppName: "Safari",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 3
            )
        ).get()

        let candidates = try client.claimLinkMetadataFetchBatch(
            appSupportDirectory: tempDirectory,
            limit: 1,
            leaseTimeoutMs: 60_000
        ).get()
        let candidate = try #require(candidates.first)
        #expect(candidate.canonicalURL == "https://example.com/docs")
        #expect(candidate.leaseStartedAtMs > 0)

        let stale = try client.completeLinkMetadataFetch(
            appSupportDirectory: tempDirectory,
            request: RustCompleteLinkMetadataFetchRequest(
                itemId: candidate.itemId,
                leaseStartedAtMs: candidate.leaseStartedAtMs - 1,
                canonicalURL: "https://example.com/docs",
                displayURL: "example.com/docs",
                host: "example.com",
                title: "Should not land"
            )
        ).get()
        #expect(stale.affectedCount == 0)

        let completed = try client.completeLinkMetadataFetch(
            appSupportDirectory: tempDirectory,
            request: RustCompleteLinkMetadataFetchRequest(
                itemId: candidate.itemId,
                leaseStartedAtMs: candidate.leaseStartedAtMs,
                canonicalURL: "https://example.com/docs",
                displayURL: "example.com/docs",
                host: "example.com",
                title: "Example Docs",
                iconRelativePath: "assets/link-icons/example.png"
            )
        ).get()
        #expect(completed.affectedCount == 1)

        let page = try client.listItems(appSupportDirectory: tempDirectory).get()
        #expect(page.items[0].linkMetadata?.metadataState == "ready")
        #expect(page.items[0].linkMetadata?.title == "Example Docs")
        #expect(page.items[0].linkMetadata?.displayURL == "example.com/docs")
        #expect(page.items[0].linkMetadata?.iconAssetPath?.hasSuffix("assets/link-icons/example.png") == true)
    }

    @Test
    func capturesImageThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadDirectory = tempDirectory.appendingPathComponent("assets", isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try Data("swift bridge image payload".utf8).write(
            to: payloadDirectory.appendingPathComponent("sample.png")
        )
        try Data("swift bridge image thumbnail".utf8).write(
            to: thumbnailDirectory.appendingPathComponent("sample.png")
        )
        let client = RustCoreClient()

        let result = try client.captureImage(
            appSupportDirectory: tempDirectory,
            request: RustCaptureImageRequest(
                payloadRelativePath: "assets/sample.png",
                previewRelativePath: "thumbnails/sample.png",
                mimeType: "image/png",
                width: 320,
                height: 180,
                byteCount: 26,
                sourceBundleId: "com.apple.Preview",
                sourceAppName: "Preview",
                sourceBundlePath: "/System/Applications/Preview.app",
                sourceIconRelativePath: "app-icons/preview.tiff",
                sourceConfidence: "high",
                pasteboardChangeCount: 8
            )
        ).get()
        let page = try client.listItems(appSupportDirectory: tempDirectory).get()

        #expect(result.inserted)
        #expect(page.totalCount == 1)
        #expect(page.items.count == 1)
        #expect(page.items[0].itemType == "image")
        #expect(page.items[0].summary == "图片 320 x 180")
        #expect(page.items[0].primaryText == nil)
        #expect(page.items[0].sourceAppName == "Preview")
        #expect(page.items[0].previewAssetPath?.hasSuffix("thumbnails/sample.png") == true)
        #expect(page.items[0].payloadAssetPath?.hasSuffix("assets/sample.png") == true)
        #expect(page.items[0].payloadState == "ready")
    }

    @Test
    func pendingImageBridgeGatesPayloadSemanticsUntilCompletion() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let thumbnail = try writeBridgeWebP(
            appSupportDirectory: tempDirectory,
            relativePath: "thumbnails/pending.webp",
            payload: Data("pending thumbnail".utf8)
        )
        let client = RustCoreClient()

        let pending = try client.capturePendingImage(
            appSupportDirectory: tempDirectory,
            request: RustCapturePendingImageRequest(
                ownerSessionId: "swift-test-session",
                thumbnailRelativePath: "thumbnails/pending.webp",
                reservedPayloadRelativePath: "assets/pending.webp",
                stagedPayloadRelativePath: ".staging/image-captures/pending-payload.webp",
                width: 640,
                height: 360,
                thumbnailWidth: 420,
                thumbnailHeight: 236,
                thumbnailByteCount: Int64(thumbnail.byteCount),
                sourceBundleId: "com.apple.Preview",
                sourceAppName: "Preview",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 88
            )
        ).get()
        var item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        #expect(pending.inserted)
        #expect(item.payloadState == "pending")
        #expect(item.previewAssetPath?.hasSuffix("thumbnails/pending.webp") == true)
        #expect(item.payloadAssetPath == nil)
        #expect(ClipboardPastePayloadPlanner.payload(for: item, appSupportDirectory: tempDirectory) == .unsupported(reason: "missing_image_asset"))
        #expect(ClipboardPreviewContentPlanner.preview(for: item, appSupportDirectory: tempDirectory).imageURL == nil)
        #expect(ClipboardOriginalImagePathResolver.originalImagePaths(for: item, appSupportDirectory: tempDirectory).isEmpty)
        let cardState = PanelItemCardViewStateAdapter.makeViewState(for: item, selectedItemID: nil)
        guard case .image(let previewPath, _, _) = cardState.preview else {
            Issue.record("expected thumbnail card preview")
            return
        }
        #expect(previewPath?.hasSuffix("thumbnails/pending.webp") == true)

        let staged = try writeBridgeWebP(
            appSupportDirectory: tempDirectory,
            relativePath: ".staging/image-captures/pending-payload.webp",
            payload: Data("ready payload".utf8)
        )
        let completion = try client.completePendingImagePayload(
            appSupportDirectory: tempDirectory,
            request: RustCompletePendingImagePayloadRequest(
                jobId: pending.jobId,
                stagedPayloadRelativePath: ".staging/image-captures/pending-payload.webp",
                width: 640,
                height: 360,
                byteCount: Int64(staged.byteCount)
            )
        ).get()
        item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)
        let payloadURL = tempDirectory.appendingPathComponent("assets/pending.webp")

        #expect(completion.status == "ready")
        #expect(completion.effectiveItemId == pending.itemId)
        #expect(completion.contentHash?.isEmpty == false)
        #expect(completion.cleanedRelativePaths.isEmpty)
        #expect(item.payloadState == "ready")
        #expect(item.payloadAssetPath?.hasSuffix("assets/pending.webp") == true)
        #expect(ClipboardPastePayloadPlanner.payload(for: item, appSupportDirectory: tempDirectory) == .imageFile(payloadURL))
        #expect(ClipboardPreviewContentPlanner.preview(for: item, appSupportDirectory: tempDirectory).imageURL == payloadURL)
        #expect(ClipboardOriginalImagePathResolver.originalImagePaths(for: item, appSupportDirectory: tempDirectory) == [payloadURL.path])
    }

    @Test
    func capturesFilesThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try Data("file thumbnail".utf8).write(
            to: thumbnailDirectory.appendingPathComponent("files.png")
        )
        let filePaths = [
            "/Users/evan/Desktop/report.pdf",
            "/Users/evan/Desktop/design.sketch"
        ]
        let client = RustCoreClient()

        let result = try client.captureFiles(
            appSupportDirectory: tempDirectory,
            request: RustCaptureFilesRequest(
                filePaths: filePaths,
                fileItems: [
                    ClipboardCapturedFileMetadata(
                        path: filePaths[0],
                        fileName: "report.pdf",
                        fileExtension: "pdf",
                        byteCount: 1024,
                        isDirectory: false,
                        width: nil,
                        height: nil,
                        contentType: "com.adobe.pdf"
                    ),
                    ClipboardCapturedFileMetadata(
                        path: filePaths[1],
                        fileName: "design.sketch",
                        fileExtension: "sketch",
                        byteCount: 2048,
                        isDirectory: false,
                        width: nil,
                        height: nil,
                        contentType: nil
                    )
                ],
                previewRelativePath: "thumbnails/files.png",
                previewMimeType: "image/png",
                previewWidth: 420,
                previewHeight: 320,
                previewByteCount: 14,
                snapshotRelativePath: nil,
                snapshotByteCount: 0,
                sourceBundleId: "com.apple.finder",
                sourceAppName: "Finder",
                sourceBundlePath: "/System/Library/CoreServices/Finder.app",
                sourceIconRelativePath: "app-icons/finder.tiff",
                sourceConfidence: "high",
                pasteboardChangeCount: 9
            )
        ).get()
        let page = try client.listItems(appSupportDirectory: tempDirectory).get()

        #expect(result.inserted)
        #expect(page.totalCount == 1)
        #expect(page.items.count == 1)
        #expect(page.items[0].itemType == "file")
        #expect(page.items[0].summary == "2 个文件 · report.pdf")
        #expect(page.items[0].primaryText?.contains("design.sketch") == true)
        #expect(page.items[0].sourceAppName == "Finder")
        #expect(page.items[0].payloadAssetPath == nil)
        #expect(page.items[0].previewAssetPath?.hasSuffix("thumbnails/files.png") == true)
        #expect(page.items[0].sizeBytes == 3072)
        #expect(page.items[0].fileItems.map(\.path) == filePaths)
        #expect(page.items[0].fileItems.map(\.byteCount) == [1024, 2048])
    }

    @Test
    func listsItemsWithSearchThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadDirectory = tempDirectory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        try Data("filter image payload".utf8).write(
            to: payloadDirectory.appendingPathComponent("filter.png")
        )
        let client = RustCoreClient()

        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Alpha target from Safari",
                sourceBundleId: "com.apple.Safari",
                sourceAppName: "Safari",
                sourceBundlePath: "/Applications/Safari.app",
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 1
            )
        ).get()
        _ = try client.captureImage(
            appSupportDirectory: tempDirectory,
            request: RustCaptureImageRequest(
                payloadRelativePath: "assets/filter.png",
                previewRelativePath: nil,
                mimeType: "image/png",
                width: 400,
                height: 300,
                byteCount: 20,
                sourceBundleId: "com.apple.Preview",
                sourceAppName: "Preview",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 2
            )
        ).get()

        let allPage = try client.listItems(appSupportDirectory: tempDirectory).get()
        let searchPage = try client.listItems(
            appSupportDirectory: tempDirectory,
            searchText: "Alpha Safari"
        ).get()

        #expect(allPage.totalCount == 2)
        #expect(allPage.items.contains { $0.itemType == "image" })
        #expect(searchPage.totalCount == 1)
        #expect(searchPage.items[0].sourceAppName == "Safari")
    }

    @Test
    func listsSourceAppsAndFiltersItemsBySourceThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Source app filter target from Safari",
                sourceBundleId: "com.apple.Safari",
                sourceAppName: "Safari",
                sourceBundlePath: "/Applications/Safari.app",
                sourceIconRelativePath: "app-icons/safari.tiff",
                sourceConfidence: "high",
                pasteboardChangeCount: 1
            )
        ).get()
        Thread.sleep(forTimeInterval: 0.1)
        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Source app filter target from TextEdit",
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: "/System/Applications/TextEdit.app",
                sourceIconRelativePath: "app-icons/textedit.tiff",
                sourceConfidence: "high",
                pasteboardChangeCount: 2
            )
        ).get()

        let sourceApps = try client.listSourceApps(appSupportDirectory: tempDirectory).get()
        let safari = try #require(sourceApps.apps.first { $0.name == "Safari" })
        let safariPage = try client.listItems(
            appSupportDirectory: tempDirectory,
            sourceAppId: safari.id
        ).get()

        #expect(sourceApps.totalCount == 2)
        #expect(sourceApps.apps.first?.name == "TextEdit")
        #expect(safari.itemCount == 1)
        #expect(safari.iconPath?.hasSuffix("app-icons/safari.tiff") == true)
        #expect(safariPage.totalCount == 1)
        #expect(safariPage.items[0].sourceAppName == "Safari")
    }

    @Test
    func managesPinnedAndDeletedItemsThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        let first = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Pinned item management target",
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 1
            )
        ).get()
        Thread.sleep(forTimeInterval: 0.01)
        let second = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Regular item management target",
                sourceBundleId: "com.apple.Safari",
                sourceAppName: "Safari",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 2
            )
        ).get()

        let pinResult = try client.setItemPinboardMembership(
            appSupportDirectory: tempDirectory,
            itemId: first.itemId,
            pinboardId: "default",
            isMember: true
        ).get()
        let pinnedPage = try client.listItems(appSupportDirectory: tempDirectory).get()
        let pinboards = try client.listPinboards(appSupportDirectory: tempDirectory).get()
        let defaultPinboardPage = try client.listItems(
            appSupportDirectory: tempDirectory,
            pinboardId: "default"
        ).get()
        let deleteResult = try client.deleteItem(
            appSupportDirectory: tempDirectory,
            itemId: first.itemId
        ).get()
        let afterDelete = try client.listItems(appSupportDirectory: tempDirectory).get()
        let defaultPinboardAfterDelete = try client.listItems(
            appSupportDirectory: tempDirectory,
            pinboardId: "default"
        ).get()

        #expect(pinResult.affectedCount == 1)
        #expect(pinboards.totalCount == 1)
        #expect(pinboards.pinboards.first?.id == "default")
        #expect(pinboards.pinboards.first?.title == "固定")
        #expect(pinboards.pinboards.first?.colorCode ?? 0 > 0)
        #expect(pinboards.pinboards.first?.itemCount == 1)
        #expect(pinnedPage.items.first?.id == second.itemId)
        #expect(pinnedPage.items.contains { $0.id == first.itemId && $0.isPinned })
        #expect(defaultPinboardPage.totalCount == 1)
        #expect(defaultPinboardPage.items.first?.id == first.itemId)
        #expect(deleteResult.affectedCount == 1)
        #expect(afterDelete.totalCount == 1)
        #expect(afterDelete.items.first?.id != first.itemId)
        #expect(defaultPinboardAfterDelete.totalCount == 0)
    }

    @Test
    func managesPinboardsThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        let createResult = try client.createPinboard(
            appSupportDirectory: tempDirectory,
            title: "Research",
            colorCode: 4_294_620_928
        ).get()
        let createdPage = try client.listPinboards(appSupportDirectory: tempDirectory).get()
        let created = try #require(createdPage.pinboards.first { $0.title == "Research" })
        let renameResult = try client.renamePinboard(
            appSupportDirectory: tempDirectory,
            pinboardId: created.id,
            title: "AI Clips"
        ).get()
        let colorResult = try client.updatePinboardColor(
            appSupportDirectory: tempDirectory,
            pinboardId: created.id,
            colorCode: 4_290_925_536
        ).get()
        let updatedPage = try client.listPinboards(appSupportDirectory: tempDirectory).get()
        let updated = try #require(updatedPage.pinboards.first { $0.id == created.id })
        let deleteResult = try client.deletePinboard(
            appSupportDirectory: tempDirectory,
            pinboardId: created.id
        ).get()
        let deletedPage = try client.listPinboards(appSupportDirectory: tempDirectory).get()

        #expect(createResult.affectedCount == 1)
        #expect(renameResult.affectedCount == 1)
        #expect(colorResult.affectedCount == 1)
        #expect(updated.title == "AI Clips")
        #expect(updated.colorCode == 4_290_925_536)
        #expect(deleteResult.affectedCount == 0)
        #expect(!deletedPage.pinboards.contains { $0.id == created.id })
    }

    @Test
    func clearsMatchingUnpinnedItemsThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        let pinned = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Clear bridge pinned text",
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 1
            )
        ).get()
        _ = try client.setItemPinboardMembership(
            appSupportDirectory: tempDirectory,
            itemId: pinned.itemId,
            pinboardId: "default",
            isMember: true
        ).get()
        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Clear bridge removable text",
                sourceBundleId: "com.apple.Safari",
                sourceAppName: "Safari",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 2
            )
        ).get()
        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Different bridge text",
                sourceBundleId: "com.apple.Notes",
                sourceAppName: "Notes",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 3
            )
        ).get()

        let clearResult = try client.clearItems(
            appSupportDirectory: tempDirectory,
            searchText: "Clear bridge"
        ).get()
        let page = try client.listItems(appSupportDirectory: tempDirectory).get()

        #expect(clearResult.affectedCount == 1)
        #expect(page.totalCount == 2)
        #expect(page.items.contains { $0.id == pinned.itemId })
        #expect(!page.items.contains { $0.summary == "Clear bridge removable text" })
    }

    @Test
    func readsDefaultPreferencesThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        let result = try client.getPreferences(appSupportDirectory: tempDirectory).get()

        #expect(result.schemaVersion == 11)
        #expect(result.preferences.general.defaultPanelHeight == 320)
        #expect(result.preferences.general.showMenuBarItem)
        #expect(result.preferences.history.maxItems == 5000)
        #expect(result.preferences.history.retentionDays == 30)
        #expect(result.preferences.history.recordImages)
        #expect(result.preferences.history.recordFiles)
        #expect(result.preferences.appearance.mode == "system")
        #expect(result.preferences.appearance.itemDensity == "standard")
        #expect(result.preferences.appearance.previewPopoverEnabled)
        #expect(result.preferences.linkPreview.webPreviewEnabled)
        #expect(result.preferences.shortcuts.openPanel.keyCode == 7)
        #expect(result.preferences.shortcuts.openPanel.modifiers == ["command", "shift"])
        #expect(!result.preferences.shortcuts.pasteDirectlyToTarget)
        #expect(result.preferences.ignoreList.ignoredAppIdentifiers == RustIgnoreListPreferences.defaultIgnoredAppIdentifiers)
        #expect(result.preferences.ignoreList.windowTitleKeywords.isEmpty)
        #expect(!result.preferences.ignoreList.skipUnknownSource)
    }

    @Test
    func updatesAndNormalizesPreferencesThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        var preferences = RustPreferencesDocument()
        preferences.general.defaultPanelHeight = 999
        preferences.history.maxItems = 10
        preferences.history.retentionDays = 999
        preferences.history.recordImages = false
        preferences.history.recordFiles = true
        preferences.appearance.mode = "neon"
        preferences.appearance.itemDensity = "compact"
        preferences.appearance.previewPopoverEnabled = false
        preferences.linkPreview.webPreviewEnabled = false
        preferences.shortcuts.openPanel = RustKeyboardShortcut(
            keyCode: 11,
            modifiers: ["shift", "cmd", "alt", "command", "ignored"]
        )
        preferences.shortcuts.pasteDirectlyToTarget = true
        preferences.ignoreList.ignoredAppIdentifiers = [
            "  com.apple.Terminal  ",
            "terminal",
            "COM.APPLE.TERMINAL",
            ""
        ]
        preferences.ignoreList.windowTitleKeywords = [
            " 密码 ",
            "验证码",
            "密码"
        ]
        preferences.ignoreList.skipUnknownSource = true

        let saved = try client.updatePreferences(
            appSupportDirectory: tempDirectory,
            preferences: preferences
        ).get()
        let reloaded = try client.getPreferences(appSupportDirectory: tempDirectory).get()

        #expect(saved.preferences.general.defaultPanelHeight == 560)
        #expect(saved.preferences.history.maxItems == 5000)
        #expect(saved.preferences.history.retentionDays == 365)
        #expect(saved.preferences.history.recordImages)
        #expect(saved.preferences.history.recordFiles)
        #expect(saved.preferences.appearance.mode == "system")
        #expect(saved.preferences.appearance.itemDensity == "compact")
        #expect(!saved.preferences.appearance.previewPopoverEnabled)
        #expect(!saved.preferences.linkPreview.webPreviewEnabled)
        #expect(saved.preferences.shortcuts.openPanel.keyCode == 11)
        #expect(saved.preferences.shortcuts.openPanel.modifiers == ["command", "option", "shift"])
        #expect(saved.preferences.shortcuts.pasteDirectlyToTarget)
        #expect(saved.preferences.ignoreList.ignoredAppIdentifiers == ["com.apple.Terminal", "terminal"])
        #expect(saved.preferences.ignoreList.windowTitleKeywords == ["密码", "验证码"])
        #expect(saved.preferences.ignoreList.skipUnknownSource)
        #expect(reloaded.preferences == saved.preferences)
    }

    @Test
    func decodesLegacyPreferencesWithoutIgnoreList() throws {
        let json = """
        {
          "general": {
            "launch_at_login": false,
            "show_menu_bar_item": true,
            "default_panel_height": 320
          },
          "history": {
            "max_items": 500,
            "retention_days": 30,
            "record_images": true,
            "record_files": false
          },
          "appearance": {
            "mode": "system",
            "item_density": "standard",
            "preview_popover_enabled": true
          }
        }
        """

        let preferences = try JSONDecoder().decode(
            RustPreferencesDocument.self,
            from: Data(json.utf8)
        )

        #expect(preferences.ignoreList == RustIgnoreListPreferences())
        #expect(preferences.ignoreList.ignoredAppIdentifiers == RustIgnoreListPreferences.defaultIgnoredAppIdentifiers)
        #expect(preferences.shortcuts == RustShortcutsPreferences())
        #expect(!preferences.shortcuts.pasteDirectlyToTarget)
        #expect(preferences.history.maxItems == 5000)
        #expect(preferences.history.recordImages)
        #expect(preferences.history.recordFiles)
    }

    @Test
    func runsMaintenanceAndRemovesOrphanAssetFilesThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assetDirectory = tempDirectory.appendingPathComponent("assets", isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        let iconDirectory = tempDirectory.appendingPathComponent("app-icons", isDirectory: true)
        let stagingDirectory = tempDirectory.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let orphanAsset = assetDirectory.appendingPathComponent("orphan.bin")
        let orphanThumbnail = thumbnailDirectory.appendingPathComponent("orphan.png")
        let orphanIcon = iconDirectory.appendingPathComponent("orphan.tiff")
        let stagingFile = stagingDirectory.appendingPathComponent("leftover.tmp")
        try Data("orphan asset".utf8).write(to: orphanAsset)
        try Data("orphan thumbnail".utf8).write(to: orphanThumbnail)
        try Data("orphan icon".utf8).write(to: orphanIcon)
        try Data("staging leftover".utf8).write(to: stagingFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: stagingFile.path
        )
        let client = RustCoreClient()

        let result = try client.runMaintenance(appSupportDirectory: tempDirectory).get()

        #expect(result.purgedItemCount == 0)
        #expect(result.deletedAssetRowCount == 0)
        #expect(result.deletedAssetFileCount == 0)
        #expect(result.deletedOrphanFileCount == 4)
        #expect(result.reclaimedBytes > 0)
        #expect(!FileManager.default.fileExists(atPath: orphanAsset.path))
        #expect(!FileManager.default.fileExists(atPath: orphanThumbnail.path))
        #expect(!FileManager.default.fileExists(atPath: orphanIcon.path))
        #expect(!FileManager.default.fileExists(atPath: stagingFile.path))
    }

    @Test
    func plansTextPastePayloadFromCapturedItem() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "ClipDock payload text\nsecond line",
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: "/System/Applications/TextEdit.app",
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 3
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(payload == .text("ClipDock payload text\nsecond line"))
        #expect(ClipboardPastePayloadPlanner.plainTextPayload(for: item) == .text("ClipDock payload text\nsecond line"))
    }

    @Test
    func plansRichTextPastePayloadFromRTFAssetWithPlainFallback() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("rich-text", isDirectory: true)
        try FileManager.default.createDirectory(at: richDirectory, withIntermediateDirectories: true)
        let rtfURL = richDirectory.appendingPathComponent("payload.rtf")
        let rtfData = Data(#"{\rtf1\ansi\b Rich payload\b0}"#.utf8)
        try rtfData.write(to: rtfURL)
        let client = RustCoreClient()

        _ = try client.captureRichText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureRichTextRequest(
                text: "Rich payload",
                rtfRelativePath: "assets/rich-text/payload.rtf",
                byteCount: Int64(rtfData.count),
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 13
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(payload == .richText(rtfURL: rtfURL, fallbackText: "Rich payload"))
        #expect(ClipboardPastePayloadPlanner.plainTextPayload(for: item) == .text("Rich payload"))
        #expect(item.previewAssetPath?.hasSuffix("assets/rich-text/payload.rtf") == true)
        #expect(item.payloadAssetPath?.hasSuffix("assets/rich-text/payload.rtf") == true)
    }

    @Test
    func plansRichTextPastePayloadAsStringFallbackWhenRTFAssetMissing() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("rich-text", isDirectory: true)
        try FileManager.default.createDirectory(at: richDirectory, withIntermediateDirectories: true)
        let rtfURL = richDirectory.appendingPathComponent("missing.rtf")
        let rtfData = Data(#"{\rtf1\ansi\b Missing later\b0}"#.utf8)
        try rtfData.write(to: rtfURL)
        let client = RustCoreClient()

        _ = try client.captureRichText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureRichTextRequest(
                text: "Missing later",
                rtfRelativePath: "assets/rich-text/missing.rtf",
                byteCount: Int64(rtfData.count),
                sourceBundleId: nil,
                sourceAppName: nil,
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "unknown",
                pasteboardChangeCount: 14
            )
        ).get()
        try FileManager.default.removeItem(at: rtfURL)
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(payload == .richText(rtfURL: nil, fallbackText: "Missing later"))
    }

    @Test
    func plansImagePastePayloadFromCapturedItemAsset() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadDirectory = tempDirectory.appendingPathComponent("assets", isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        let payloadURL = payloadDirectory.appendingPathComponent("paste.png")
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("paste.png")
        try Data("paste image payload".utf8).write(to: payloadURL)
        try Data("paste image thumbnail".utf8).write(to: thumbnailURL)
        let client = RustCoreClient()

        _ = try client.captureImage(
            appSupportDirectory: tempDirectory,
            request: RustCaptureImageRequest(
                payloadRelativePath: "assets/paste.png",
                previewRelativePath: "thumbnails/paste.png",
                mimeType: "image/png",
                width: 240,
                height: 120,
                byteCount: 19,
                sourceBundleId: "com.apple.Preview",
                sourceAppName: "Preview",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 4
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(payload == .imageFile(payloadURL))
    }

    @Test
    func plansFilePastePayloadFromSnapshotAsset() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let copiedFilesDirectory = tempDirectory.appendingPathComponent("copied-files", isDirectory: true)
        let snapshotDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("file-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: copiedFilesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        let firstFile = copiedFilesDirectory.appendingPathComponent("report.pdf")
        let secondFile = copiedFilesDirectory.appendingPathComponent("design.sketch")
        try Data("report".utf8).write(to: firstFile)
        try Data("design".utf8).write(to: secondFile)
        let filePaths = [firstFile.path, secondFile.path]
        let snapshotData = try JSONEncoder().encode(["paths": filePaths])
        try snapshotData.write(to: snapshotDirectory.appendingPathComponent("paste-files.json"))
        let client = RustCoreClient()

        _ = try client.captureFiles(
            appSupportDirectory: tempDirectory,
            request: RustCaptureFilesRequest(
                filePaths: filePaths,
                snapshotRelativePath: "assets/file-snapshots/paste-files.json",
                snapshotByteCount: Int64(snapshotData.count),
                sourceBundleId: "com.apple.finder",
                sourceAppName: "Finder",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 10
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(payload == .fileURLs([firstFile, secondFile]))
    }

    @Test
    func plansTextPreviewContentFromCapturedItem() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "Preview body first line\nPreview body second line",
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: "/System/Applications/TextEdit.app",
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 5
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(preview.itemID == item.id)
        #expect(preview.itemType == "text")
        #expect(preview.sourceAppName == "TextEdit")
        #expect(preview.body.contains("Preview body second line"))
        #expect(preview.imageURL == nil)
    }

    @Test
    func plansRichTextPreviewContentWithLazyRTFURLAndPlainBody() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("rich-text", isDirectory: true)
        try FileManager.default.createDirectory(at: richDirectory, withIntermediateDirectories: true)
        let rtfURL = richDirectory.appendingPathComponent("preview.rtf")
        let rtfData = Data(#"{\rtf1\ansi\b Preview rich\b0}"#.utf8)
        try rtfData.write(to: rtfURL)
        let client = RustCoreClient()

        _ = try client.captureRichText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureRichTextRequest(
                text: "Preview rich",
                rtfRelativePath: "assets/rich-text/preview.rtf",
                byteCount: Int64(rtfData.count),
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 15
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(preview.itemType == "rich_text")
        #expect(preview.subtitle == "富文本")
        #expect(preview.body == "Preview rich")
        #expect(preview.richTextURL == rtfURL)
        #expect(preview.imageURL == nil)
    }

    @Test
    func plansTextPreviewContentFromPrimaryTextWhenSummaryIsTruncated() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        let longText = Array(repeating: "Preview body should use the complete primary text instead of the truncated summary.", count: 12)
            .joined(separator: "\n")

        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: longText,
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: "/System/Applications/TextEdit.app",
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 7
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(item.summary.count < longText.count)
        #expect(item.primaryText == longText)
        #expect(preview.body == longText)
    }

    @Test
    func keepsCopyAndDetailFullTextWhenCardPreviewIsBounded() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        let lateToken = "LATE_TOKEN_AFTER_UI_PREVIEW_500"
        let longText = "\(String(repeating: "a", count: 520)) \(lateToken)"

        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: longText,
                sourceBundleId: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                sourceBundlePath: "/System/Applications/TextEdit.app",
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 8
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let presentation = PanelItemCardPresenter.presentation(for: item)
        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: tempDirectory
        )
        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect((presentation.summaryText as NSString).length <= 500)
        #expect(!presentation.summaryText.contains(lateToken))
        #expect(payload == .text(longText))
        #expect(preview.body == longText)
        #expect(preview.body.contains(lateToken))
    }

    @Test
    func plansImagePreviewContentFromOriginalPayloadAsset() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadDirectory = tempDirectory.appendingPathComponent("assets", isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        let payloadURL = payloadDirectory.appendingPathComponent("preview-payload.png")
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("preview-thumbnail.png")
        try Data("preview image payload".utf8).write(to: payloadURL)
        try Data("preview image thumbnail".utf8).write(to: thumbnailURL)
        let client = RustCoreClient()

        _ = try client.captureImage(
            appSupportDirectory: tempDirectory,
            request: RustCaptureImageRequest(
                payloadRelativePath: "assets/preview-payload.png",
                previewRelativePath: "thumbnails/preview-thumbnail.png",
                mimeType: "image/png",
                width: 420,
                height: 260,
                byteCount: 21,
                sourceBundleId: "com.apple.Preview",
                sourceAppName: "Preview",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 6
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)

        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(preview.itemType == "image")
        #expect(preview.title == "图片 420 x 260")
        #expect(preview.imageURL == payloadURL)
        #expect(preview.metadata.hasPrefix("PNG"))
    }

    @Test
    func invalidAppSupportPathReturnsRecoverableError() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let fileURL = tempDirectory.appendingPathComponent("not-a-directory")
        _ = FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        let client = RustCoreClient()

        let result = client.open(appSupportDirectory: fileURL)

        guard case .failure(let error) = result else {
            Issue.record("expected invalid directory failure")
            return
        }

        #expect(error.code == "io_failed")
        #expect(error.recoverable)
    }

    @Test
    func rustCoreDatabaseErrorCrossesSwiftBridge() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        try Data("not a sqlite database".utf8).write(
            to: tempDirectory.appendingPathComponent("clipboard.sqlite")
        )
        let client = RustCoreClient()

        let result = client.open(appSupportDirectory: tempDirectory)

        guard case .failure(let error) = result else {
            Issue.record("expected rust database failure")
            return
        }

        #expect(error.code == "database_unavailable")
        #expect(error.messageKey == "clipboard.error.database_unavailable")
        #expect(error.recoverable)
    }
}

private struct BridgeWebPFixture {
    let url: URL
    let byteCount: Int
}

private func writeBridgeWebP(
    appSupportDirectory: URL,
    relativePath: String,
    payload: Data
) throws -> BridgeWebPFixture {
    let url = appSupportDirectory.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    var data = Data("RIFF0000WEBP".utf8)
    data.append(payload)
    try data.write(to: url)
    return BridgeWebPFixture(url: url, byteCount: data.count)
}
