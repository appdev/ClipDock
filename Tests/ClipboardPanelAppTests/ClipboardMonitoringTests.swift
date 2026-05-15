import AppKit
import ClipboardPanelApp
import Foundation
import Testing
@testable import ClipShelf

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
