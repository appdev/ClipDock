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
    func opensRustCoreThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()

        let value = try client.open(appSupportDirectory: tempDirectory).get()

        #expect(value.databasePath.hasSuffix("clipboard.sqlite"))
        #expect(value.schemaVersion == 1)
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
    }

    @Test
    func capturesFilesThroughSwiftBridgeBinding() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshotDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("file-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        let filePaths = [
            "/Users/evan/Desktop/report.pdf",
            "/Users/evan/Desktop/design.sketch"
        ]
        let snapshotData = try JSONEncoder().encode(["paths": filePaths])
        try snapshotData.write(to: snapshotDirectory.appendingPathComponent("files.json"))
        let client = RustCoreClient()

        let result = try client.captureFiles(
            appSupportDirectory: tempDirectory,
            request: RustCaptureFilesRequest(
                filePaths: filePaths,
                snapshotRelativePath: "assets/file-snapshots/files.json",
                snapshotByteCount: Int64(snapshotData.count),
                sourceBundleId: "com.apple.finder",
                sourceAppName: "Finder",
                sourceBundlePath: "/System/Library/CoreServices/Finder.app",
                sourceIconRelativePath: "app-icons/finder.tiff",
                sourceConfidence: "high",
                pasteboardChangeCount: 9
            )
        ).get()
        let page = try client.listItems(
            appSupportDirectory: tempDirectory,
            itemType: "file"
        ).get()

        #expect(result.inserted)
        #expect(page.totalCount == 1)
        #expect(page.items.count == 1)
        #expect(page.items[0].itemType == "file")
        #expect(page.items[0].summary == "2 个文件 · report.pdf")
        #expect(page.items[0].primaryText?.contains("design.sketch") == true)
        #expect(page.items[0].sourceAppName == "Finder")
        #expect(page.items[0].payloadAssetPath?.hasSuffix("assets/file-snapshots/files.json") == true)
    }

    @Test
    func listsItemsWithSearchAndTypeFiltersThroughSwiftBridgeBinding() throws {
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

        let imagePage = try client.listItems(
            appSupportDirectory: tempDirectory,
            itemType: "image"
        ).get()
        let searchPage = try client.listItems(
            appSupportDirectory: tempDirectory,
            searchText: "Alpha Safari"
        ).get()

        #expect(imagePage.totalCount == 1)
        #expect(imagePage.items[0].itemType == "image")
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
        Thread.sleep(forTimeInterval: 0.01)
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
        _ = try client.captureText(
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

        let pinResult = try client.setItemPinned(
            appSupportDirectory: tempDirectory,
            itemId: first.itemId,
            isPinned: true
        ).get()
        let pinnedPage = try client.listItems(appSupportDirectory: tempDirectory).get()
        let deleteResult = try client.deleteItem(
            appSupportDirectory: tempDirectory,
            itemId: first.itemId
        ).get()
        let afterDelete = try client.listItems(appSupportDirectory: tempDirectory).get()

        #expect(pinResult.affectedCount == 1)
        #expect(pinnedPage.items.first?.id == first.itemId)
        #expect(pinnedPage.items.first?.isPinned == true)
        #expect(deleteResult.affectedCount == 1)
        #expect(afterDelete.totalCount == 1)
        #expect(afterDelete.items.first?.id != first.itemId)
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
        _ = try client.setItemPinned(
            appSupportDirectory: tempDirectory,
            itemId: pinned.itemId,
            isPinned: true
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
            itemType: "text",
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

        #expect(result.schemaVersion == 1)
        #expect(result.preferences.general.defaultPanelHeight == 320)
        #expect(result.preferences.general.showMenuBarItem)
        #expect(result.preferences.history.maxItems == 500)
        #expect(result.preferences.history.retentionDays == 30)
        #expect(result.preferences.history.recordImages)
        #expect(!result.preferences.history.recordFiles)
        #expect(result.preferences.appearance.mode == "system")
        #expect(result.preferences.appearance.itemDensity == "standard")
        #expect(result.preferences.appearance.previewPopoverEnabled)
        #expect(result.preferences.ignoreList.ignoredAppIdentifiers.isEmpty)
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
        #expect(saved.preferences.history.maxItems == 50)
        #expect(saved.preferences.history.retentionDays == 365)
        #expect(!saved.preferences.history.recordImages)
        #expect(saved.preferences.history.recordFiles)
        #expect(saved.preferences.appearance.mode == "system")
        #expect(saved.preferences.appearance.itemDensity == "compact")
        #expect(!saved.preferences.appearance.previewPopoverEnabled)
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
                text: "Paste payload text\nsecond line",
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

        #expect(payload == .text("Paste payload text\nsecond line"))
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
    func plansImagePreviewContentFromThumbnailAsset() throws {
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
        #expect(preview.imageURL == thumbnailURL)
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
