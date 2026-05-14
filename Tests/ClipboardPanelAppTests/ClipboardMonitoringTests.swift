import AppKit
import ClipboardPanelApp
import Foundation
import Testing
@testable import PasteFloating

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
    func bitmapImageDataIsCapturedAsImagePayload() throws {
        let pngData = try makePNGData(width: 32, height: 20)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        let snapshot = ClipboardPayloadReader().readContent(from: pasteboard)
        guard case .image(let image) = snapshot else {
            Issue.record("无文件路径的位图图片应作为图片资产捕获")
            return
        }

        #expect(image.width == 32)
        #expect(image.height == 20)
        #expect(image.mimeType == "image/heic")
        #expect(image.fileExtension == "heic")
        #expect(NSImage(data: image.data) != nil)
        #expect(image.data != pngData)
    }

    @Test
    @MainActor
    func imageAssetProviderStoresPreferredImageExtensionAndMimeType() throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = ClipboardImageAssetProvider(appSupportURL: appSupportURL)
        let image = ClipboardCapturedImage(
            data: Data("heic-payload".utf8),
            thumbnailData: Data("heic-thumb".utf8),
            mimeType: "image/heic",
            fileExtension: "heic",
            width: 32,
            height: 20
        )

        let storedImage = try #require(provider.cacheImage(image, changeCount: 4))

        #expect(storedImage.payloadRelativePath.hasSuffix(".heic"))
        #expect(storedImage.previewRelativePath.hasSuffix(".heic"))
        #expect(storedImage.mimeType == "image/heic")
        #expect(storedImage.byteCount == image.data.count)
        #expect(FileManager.default.fileExists(
            atPath: appSupportURL.appendingPathComponent(storedImage.payloadRelativePath).path
        ))
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
