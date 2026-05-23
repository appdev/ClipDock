import AppKit
import ClipboardPanelApp
import Foundation
import Testing
@testable import ClipDock

struct ClipboardMonitoringTests {
    @Test
    @MainActor
    func imageFileURLIsCapturedAsFileSnapshotInsteadOfImagePayload() async throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("sample.png")
        try FileManager.default.createDirectory(
            at: imageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makePNGData(width: 24, height: 16).write(to: imageURL)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([imageURL as NSURL]))

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .files(let files) = snapshot else {
            Issue.record("图片文件 URL 应作为文件路径捕获，而不是重新编码为图片资产")
            return
        }

        #expect(files.paths == [imageURL.standardizedFileURL.path])
        #expect(files.fileItems.isEmpty)

        let enrichedFiles = await Task.detached(priority: .utility) {
            await files.collectingMetadata()
        }.value
        #expect(enrichedFiles.fileItems.first?.path == imageURL.standardizedFileURL.path)
        #expect(enrichedFiles.fileItems.first?.fileName == "sample.png")
        #expect(enrichedFiles.fileItems.first?.fileExtension == "png")
        #expect(enrichedFiles.fileItems.first?.byteCount ?? 0 > 0)
        #expect(enrichedFiles.fileItems.first?.width == 24)
        #expect(enrichedFiles.fileItems.first?.height == 16)
        #expect(CapturedClipboardImage.read(from: pasteboard) == nil)
    }

    @Test
    @MainActor
    func filePreviewProviderPersistsThumbnailForTextFile() async throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let textURL = sourceDirectory.appendingPathComponent("notes.txt")
        try "Persistent text file thumbnail".write(to: textURL, atomically: true, encoding: .utf8)
        let provider = ClipboardFilePreviewProvider(
            appSupportURL: appSupportURL,
            fileStemFactory: PlatformAssetFileStemFactory(
                timestampProvider: { 1000 },
                uuidProvider: { UUID(uuidString: "00000000-0000-0000-0000-000000000002")! }
            ),
            scaleProvider: { 1 }
        )

        let preview = try #require(await provider.cachePreview(
            for: CapturedClipboardFiles(urls: [textURL]),
            changeCount: 12
        ))
        let thumbnailURL = appSupportURL.appendingPathComponent(preview.relativePath)
        let thumbnailData = try Data(contentsOf: thumbnailURL)

        #expect(preview.relativePath == "thumbnails/file-thumbnail-12-1000-00000000-0000-0000-0000-000000000002.png")
        #expect(preview.mimeType == "image/png")
        #expect(preview.byteCount == thumbnailData.count)
        #expect(preview.width > 0)
        #expect(preview.height > 0)
        #expect(NSImage(data: thumbnailData) != nil)
    }

    @Test
    @MainActor
    func filePreviewProviderSkipsThumbnailForMultipleFiles() async throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let firstURL = sourceDirectory.appendingPathComponent("first.png")
        let secondURL = sourceDirectory.appendingPathComponent("second.jpg")
        try makePNGData(width: 20, height: 20).write(to: firstURL)
        try makePNGData(width: 22, height: 22).write(to: secondURL)
        let provider = ClipboardFilePreviewProvider(
            appSupportURL: appSupportURL,
            scaleProvider: { 1 }
        )

        let preview = await provider.cachePreview(
            for: CapturedClipboardFiles(urls: [firstURL, secondURL]),
            changeCount: 15
        )

        #expect(preview == nil)
    }

    @Test
    @MainActor
    func bitmapImageDataIsCapturedAsLightweightImageSource() throws {
        let pngData = try makePNGData(width: 32, height: 20)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .image(let image) = snapshot else {
            Issue.record("无文件路径的位图图片应作为图片资产捕获")
            return
        }

        guard case .encodedData(let data, let typeIdentifier) = image.source else {
            Issue.record("PNG pasteboard data should be captured as a lightweight data snapshot")
            return
        }
        #expect(data == pngData)
        #expect(typeIdentifier == "public.png")
    }

    @Test
    @MainActor
    func rtfOnlyRichContentRemainsRichText() throws {
        let rtfData = Data(#"{\rtf1\ansi{\fonttbl\f0 Helvetica;}\f0\b Bold rich text\b0}"#.utf8)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .richText(let richText) = snapshot else {
            Issue.record("RTF with non-default rich attributes should capture as rich text")
            return
        }

        #expect(richText.text == "Bold rich text")
        #expect(richText.rtfData == rtfData)
    }

    @Test
    @MainActor
    func plainBeforeRTFMatchingCapturesTextWithDisplayRichText() throws {
        let text = "Plain-first styled text"
        let rtfData = try makeRTFData(text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.systemPurple
        ])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        _ = pasteboard.declareTypes([.string, .rtf], owner: nil)
        #expect(pasteboard.setString(text, forType: .string))
        #expect(pasteboard.setData(rtfData, forType: .rtf))

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .text(let capturedText, let displayRichText) = snapshot else {
            Issue.record("Plain text declared before matching RTF should stay text with a display RTF snapshot")
            return
        }

        #expect(capturedText == text)
        #expect(displayRichText?.text == text)
        #expect(displayRichText?.rtfData == rtfData)
    }

    @Test
    @MainActor
    func rtfBeforePlainMatchingCapturesRichText() throws {
        let text = "RTF-first styled text"
        let rtfData = try makeRTFData(text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.systemPurple
        ])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        _ = pasteboard.declareTypes([.rtf, .string], owner: nil)
        #expect(pasteboard.setData(rtfData, forType: .rtf))
        #expect(pasteboard.setString(text, forType: .string))

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .richText(let richText) = snapshot else {
            Issue.record("RTF declared before matching plain text should remain rich text")
            return
        }

        #expect(richText.text == text)
        #expect(richText.rtfData == rtfData)
    }

    @Test
    @MainActor
    func htmlTextConvertsToFlatRTFWhenNoImageOrFileEvidenceExists() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString(
            #"<p>Hello <span style="font-weight: 700; color: #c00000">rich</span> text</p>"#,
            forType: .html
        )

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .richText(let richText) = snapshot else {
            Issue.record("Semantic textual HTML should convert to flat RTF rich text")
            return
        }

        #expect(richText.text == "Hello rich text")
        #expect(richText.rtfData.count > 0)
        #expect(NSAttributedString(
            rtf: richText.rtfData,
            documentAttributes: nil
        )?.string.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello rich text")
    }

    @Test
    @MainActor
    func codexCodePresentationHTMLFallsBackToPlainTextLikePaste() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString(
            """
            <article class="markdown prose">
                <p><code style="background: #fff8df; color: #5f6b73; font-family: ui-monospace;">text</code>
                捕获新增可选
                <code style="background: #fff8df; color: #5f6b73; font-family: ui-monospace;">displayRTF</code>，</p>
                <p>分类、搜索、普通粘贴仍走纯文本。</p>
                <p>Rust 存储把
                <code style="background-color: #fff8df; color: #5f6b73;">text</code>
                的 RTF 展示快照作为
                <code style="background-color: #fff8df; color: #5f6b73;">preview_asset_path</code>
                暴露，不作为
                <code style="background-color: #fff8df; color: #5f6b73;">payload_asset_path</code>。</p>
                <pre style="background: #f8f8f8;"><code>rich_text 仍保留原来的 RTF payload 逻辑。</code></pre>
            </article>
            """,
            forType: .html
        )

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .text(let text, let displayRichText) = snapshot else {
            Issue.record("Codex-style code presentation HTML should remain a plain text item")
            return
        }

        #expect(text.contains("text"))
        #expect(text.contains("displayRTF"))
        #expect(text.contains("preview_asset_path"))
        #expect(text.contains("payload_asset_path"))
        #expect(displayRichText == nil)
    }

    @Test
    @MainActor
    func plainStringWinsOverRTFStylesLikePasteTextItems() throws {
        let plainText = """
        对，你这个截图把证据补齐了。我修正前面的判断：

        Paste 的这个背景色很大概率来自复制源携带的 RTF/HTML 样式，
        不是 Paste 自己的统一卡片背景。
        """
        let rtfData = try makeRTFData(plainText, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.darkGray
        ])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
        pasteboard.setData(rtfData, forType: .rtf)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .text(let text, let displayRichText) = snapshot else {
            Issue.record("Paste-like text items should keep text classification when .string is present")
            return
        }

        #expect(text == plainText)
        #expect(displayRichText?.text == plainText)
        #expect(displayRichText?.rtfData == rtfData)
    }

    @Test
    @MainActor
    func styledCodeSnippetWithPlainStringStaysTextLikePaste() throws {
        let code = """
        UgAdaptiveDialog(
            modifier =
                ugAdaptiveDialogModifier,
            visible =
                isShowScanDeviceDialog,
            phoneDecorFit = false,
            dismissOnSwipeDown = false
        )
        """
        let attributed = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .backgroundColor: NSColor.textBackgroundColor
            ]
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemGreen,
            range: (code as NSString).range(of: "UgAdaptiveDialog")
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemBlue,
            range: (code as NSString).range(of: "modifier")
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemBlue,
            range: (code as NSString).range(of: "visible")
        )

        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        pasteboard.setData(rtfData, forType: .rtf)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .text(let text, let displayRichText) = snapshot else {
            Issue.record("Styled source-code pasteboard data should remain a text item when .string is present")
            return
        }

        #expect(text == code)
        #expect(displayRichText?.text == code)
        #expect(displayRichText?.rtfData == rtfData)
    }

    @Test
    @MainActor
    func structuralHTMLListFallsBackToPlainTextLikePaste() throws {
        let plainText = """
        富文本 rich_text

        粗体、斜体、下划线、删除线
        前景色、背景色、高亮色
        多字号、多字体、标题样式
        """
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setString(
            """
            <article>
                <p><span>富文本 <code>rich_text</code></span></p>
                <ul>
                    <li>粗体、斜体、下划线、删除线</li>
                    <li>前景色、背景色、高亮色</li>
                    <li>多字号、多字体、标题样式</li>
                </ul>
            </article>
            """,
            forType: .html
        )
        pasteboard.setString(plainText, forType: .string)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .text(let text, let displayRichText) = snapshot else {
            Issue.record("Structural HTML from rendered Markdown should remain plain text")
            return
        }

        #expect(text == plainText)
        #expect(displayRichText == nil)
    }

    @Test
    @MainActor
    func htmlBackedRTFWithOnlyLightMarkupFallsBackToPlainText() throws {
        let plainText = """
        富文本 rich_text

        粗体、斜体、下划线、删除线
        """
        let rtfData = Data(#"{\rtf1\ansi\b 富文本 rich_text\b0\par \bullet\tab 粗体、斜体、下划线、删除线}"#.utf8)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)
        pasteboard.setString(
            """
            <p><strong>富文本 <code>rich_text</code></strong></p>
            <ul><li>粗体、斜体、下划线、删除线</li></ul>
            """,
            forType: .html
        )
        pasteboard.setString(plainText, forType: .string)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .text(let text, let displayRichText) = snapshot else {
            Issue.record("HTML-backed RTF with only a single light markup signal should remain text")
            return
        }

        #expect(text == plainText)
        #expect(displayRichText == nil)
    }

    @Test
    @MainActor
    func imageWithImageOnlyHTMLMetadataRemainsImage() throws {
        let pngData = try makePNGData(width: 32, height: 20)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setString(#"<html><body><img src="https://example.com/a.png" alt="logo"></body></html>"#, forType: .html)
        pasteboard.setString("logo", forType: .string)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .image = snapshot else {
            Issue.record("Bitmap evidence plus image-only HTML metadata should remain image")
            return
        }
    }

    @Test
    @MainActor
    func fileEvidenceWinsOverRTF() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("notes.rtf")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "file".write(to: fileURL, atomically: true, encoding: .utf8)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([fileURL as NSURL]))
        pasteboard.setData(try makeRTFData("Inline rich", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14)
        ]), forType: .rtf)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .files(let files) = snapshot else {
            Issue.record("File URLs should win over inline RTF evidence")
            return
        }

        #expect(files.paths == [fileURL.standardizedFileURL.path])
    }

    @Test
    @MainActor
    func nsImageFallbackCreatesImmutableCGImageSnapshot() throws {
        let image = NSImage(size: NSSize(width: 18, height: 12))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 18, height: 12).fill()
        image.unlockFocus()

        let snapshot = try #require(CapturedClipboardImage.snapshot(from: image))
        guard case .cgImage(let cgImageSnapshot) = snapshot.source else {
            Issue.record("NSImage-only fallback should snapshot a CGImage on the MainActor")
            return
        }

        #expect(cgImageSnapshot.image.width > 0)
        #expect(cgImageSnapshot.image.height > 0)
        #expect(cgImageSnapshot.image.width * 12 == cgImageSnapshot.image.height * 18)
    }

    @Test
    func imageAssetProviderStoresWebPImageExtensionAndMimeType() throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = ClipboardImageAssetProvider(appSupportURL: appSupportURL)
        let image = ClipboardCapturedImage(
            data: Data("webp-payload".utf8),
            thumbnailData: Data("webp-thumb".utf8),
            mimeType: "image/webp",
            fileExtension: "webp",
            width: 32,
            height: 20
        )

        let storedImage = try #require(provider.cacheImage(image, changeCount: 4))

        #expect(storedImage.payloadRelativePath.hasSuffix(".webp"))
        #expect(storedImage.previewRelativePath.hasSuffix(".webp"))
        #expect(storedImage.mimeType == "image/webp")
        #expect(storedImage.byteCount == image.data.count)
        #expect(FileManager.default.fileExists(
            atPath: appSupportURL.appendingPathComponent(storedImage.payloadRelativePath).path
        ))
    }

    @Test
    func imageAssetProviderFinalizesWebPPayloadThumbnailAndDimensions() throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = ClipboardImageAssetProvider(
            appSupportURL: appSupportURL,
            fileStemFactory: PlatformAssetFileStemFactory(
                timestampProvider: { 1000 },
                uuidProvider: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
            )
        )
        let image = CapturedClipboardImage(
            source: .encodedData(try makePNGData(width: 640, height: 320), typeIdentifier: "public.png")
        )

        let prepared = try provider.prepareImage(image, changeCount: 9).get()

        #expect(prepared.storedImage.payloadRelativePath == "assets/image-9-1000-00000000-0000-0000-0000-000000000001.webp")
        #expect(prepared.storedImage.previewRelativePath == "thumbnails/image-9-1000-00000000-0000-0000-0000-000000000001.webp")
        #expect(prepared.storedImage.mimeType == "image/webp")
        #expect(prepared.storedImage.width == 640)
        #expect(prepared.storedImage.height == 320)
        #expect(prepared.storedImage.byteCount > 0)

        let payloadURL = appSupportURL.appendingPathComponent(prepared.storedImage.payloadRelativePath)
        let thumbnailURL = appSupportURL.appendingPathComponent(prepared.storedImage.previewRelativePath)
        let payloadData = try Data(contentsOf: payloadURL)
        let thumbnailData = try Data(contentsOf: thumbnailURL)
        #expect(payloadData.starts(with: Data("RIFF".utf8)))
        #expect(payloadData.dropFirst(8).starts(with: Data("WEBP".utf8)))
        #expect(thumbnailData.starts(with: Data("RIFF".utf8)))
        #expect(thumbnailData.dropFirst(8).starts(with: Data("WEBP".utf8)))
        #expect(try #require(NSImage(data: thumbnailData)).pixelDimensions.width == 420)
    }

    @Test
    func imageAssetProviderPreparesThumbnailBeforeStagedPayloadCompletion() throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = ClipboardImageAssetProvider(
            appSupportURL: appSupportURL,
            fileStemFactory: PlatformAssetFileStemFactory(
                timestampProvider: { 1500 },
                uuidProvider: { UUID(uuidString: "00000000-0000-0000-0000-000000000003")! }
            )
        )
        let image = CapturedClipboardImage(
            source: .encodedData(try makePNGData(width: 640, height: 320), typeIdentifier: "public.png")
        )

        let pending = try provider.preparePendingImage(image, changeCount: 11).get()
        let reservedPayloadURL = appSupportURL.appendingPathComponent(pending.pendingImage.reservedPayloadRelativePath)
        let thumbnailURL = appSupportURL.appendingPathComponent(pending.pendingImage.thumbnailRelativePath)
        let stagedPayloadURL = appSupportURL.appendingPathComponent(pending.pendingImage.stagedPayloadRelativePath)

        #expect(pending.pendingImage.thumbnailRelativePath == "thumbnails/image-11-1500-00000000-0000-0000-0000-000000000003.webp")
        #expect(pending.pendingImage.reservedPayloadRelativePath == "assets/image-11-1500-00000000-0000-0000-0000-000000000003.webp")
        #expect(pending.pendingImage.stagedPayloadRelativePath == ".staging/image-captures/image-11-1500-00000000-0000-0000-0000-000000000003-payload.webp")
        #expect(pending.pendingImage.mimeType == "image/webp")
        #expect(pending.pendingImage.width == 640)
        #expect(pending.pendingImage.height == 320)
        #expect(pending.pendingImage.thumbnailByteCount > 0)
        #expect(FileManager.default.fileExists(atPath: thumbnailURL.path))
        #expect(!FileManager.default.fileExists(atPath: reservedPayloadURL.path))
        #expect(!FileManager.default.fileExists(atPath: stagedPayloadURL.path))

        let completed = try provider.completePendingImagePayload(
            image,
            pendingImage: pending,
            jobID: "job-1"
        ).get()

        #expect(completed.completedImage.jobID == "job-1")
        #expect(completed.completedImage.stagedPayloadRelativePath == pending.pendingImage.stagedPayloadRelativePath)
        #expect(completed.completedImage.width == 640)
        #expect(completed.completedImage.height == 320)
        #expect(completed.completedImage.byteCount > 0)
        #expect(FileManager.default.fileExists(atPath: stagedPayloadURL.path))
        #expect(!FileManager.default.fileExists(atPath: reservedPayloadURL.path))
    }

    @Test
    func imageAssetProviderCleansStagingAndPreparedFilesWhenThumbnailEncodingFails() throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = ClipboardImageAssetProvider(
            appSupportURL: appSupportURL,
            fileStemFactory: PlatformAssetFileStemFactory(
                timestampProvider: { 2000 },
                uuidProvider: { UUID(uuidString: "00000000-0000-0000-0000-000000000002")! }
            ),
            encoder: CountingWebPEncoder(successfulCallLimit: 1)
        )
        let image = CapturedClipboardImage(
            source: .encodedData(try makePNGData(width: 100, height: 50), typeIdentifier: "public.png")
        )

        let result = provider.prepareImage(image, changeCount: 10)

        guard case .failure(.webPEncodingFailed) = result else {
            Issue.record("Expected thumbnail WebP encoding failure")
            return
        }
        #expect(!FileManager.default.fileExists(
            atPath: appSupportURL.appendingPathComponent("assets/image-10-2000-00000000-0000-0000-0000-000000000002.webp").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: appSupportURL.appendingPathComponent("thumbnails/image-10-2000-00000000-0000-0000-0000-000000000002.webp").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: appSupportURL.appendingPathComponent(".staging/image-captures/image-10-2000-00000000-0000-0000-0000-000000000002-payload.webp").path
        ))
    }

    @Test
    @MainActor
    func captureRegistrationPipelinePreservesPasteboardOrderWhenImageWorkIsSlow() async {
        let pipeline = ClipboardCaptureRegistrationPipeline()
        var events: [String] = []
        var releaseImage: CheckedContinuation<Void, Never>?

        pipeline.enqueue {
            events.append("image-start")
            await withCheckedContinuation { continuation in
                releaseImage = continuation
            }
            events.append("image-register")
        }
        pipeline.enqueue {
            events.append("text-register")
        }

        await Task.yield()
        #expect(events == ["image-start"])
        releaseImage?.resume()

        for _ in 0..<20 where events.count < 3 {
            await Task.yield()
        }

        #expect(events == ["image-start", "image-register", "text-register"])
        pipeline.cancel()
    }
}

private final class CountingWebPEncoder: ClipboardWebPEncoding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let successfulCallLimit: Int

    init(successfulCallLimit: Int) {
        self.successfulCallLimit = successfulCallLimit
    }

    func encodeLosslessRGBA(_ rgbaData: Data, width: Int, height: Int) -> Data? {
        lock.lock()
        calls += 1
        let shouldSucceed = calls <= successfulCallLimit
        lock.unlock()
        return shouldSucceed ? Data("RIFFxxxxWEBPstub".utf8) : nil
    }
}

private func makePNGData(width: Int, height: Int) throws -> Data {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.78, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
    NSGraphicsContext.restoreGraphicsState()

    return try #require(bitmap.representation(using: .png, properties: [:]))
}

private func makeRTFData(
    _ text: String,
    attributes: [NSAttributedString.Key: Any]
) throws -> Data {
    let attributed = NSAttributedString(string: text, attributes: attributes)
    return try attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
}
