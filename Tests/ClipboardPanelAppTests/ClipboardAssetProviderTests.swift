import AppKit
import Foundation
import Testing
@testable import ClipboardPanelApp
@testable import ClipDock

struct ClipboardAssetProviderTests {
    @Test
    @MainActor
    func sourceAppIconProviderCachesHighResolutionPNGAndReusesExistingFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let provider = SourceAppIconProvider(appSupportURL: tempDirectory)
        let source = ClipboardCaptureSource(
            bundleId: "com.example.HighResolutionIcon",
            appName: "High Resolution Icon",
            bundlePath: nil,
            windowTitle: nil,
            iconTIFFData: try makeIconTIFFData(width: 1024, height: 1024)
        )

        let relativePath = try #require(provider.cacheIcon(for: source))
        let iconURL = tempDirectory.appendingPathComponent(relativePath)
        let cachedData = try Data(contentsOf: iconURL)
        let cachedImage = try #require(NSImage(contentsOf: iconURL))
        let bitmap = try #require(cachedImage.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        #expect(relativePath == "app-icons/com.example.HighResolutionIcon.png")
        #expect(cachedData.count < 500_000)
        #expect(bitmap.pixelsWide == 512)
        #expect(bitmap.pixelsHigh == 512)

        let reusedPath = try #require(provider.cacheIcon(for: ClipboardCaptureSource(
            bundleId: "com.example.HighResolutionIcon",
            appName: "High Resolution Icon",
            bundlePath: nil,
            windowTitle: nil,
            iconTIFFData: Data("invalid-icon-data".utf8)
        )))

        #expect(reusedPath == relativePath)
        #expect(try Data(contentsOf: iconURL) == cachedData)
    }

    @Test
    func richTextAssetProviderPersistsFlatRTFUnderRichTextAssets() throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = ClipboardRichTextAssetProvider(
            appSupportURL: appSupportURL,
            fileStemFactory: PlatformAssetFileStemFactory(
                timestampProvider: { 3000 },
                uuidProvider: { UUID(uuidString: "00000000-0000-0000-0000-000000000004")! }
            )
        )
        let rtfData = Data(#"{\rtf1\ansi\b Stored\b0}"#.utf8)

        let asset = try #require(provider.cacheRichText(
            ClipboardCapturedRichText(text: "Stored", rtfData: rtfData),
            changeCount: 14
        ))

        #expect(asset.rtfRelativePath == "assets/rich-text/rich-text-14-3000-00000000-0000-0000-0000-000000000004.rtf")
        #expect(asset.mimeType == "application/rtf")
        #expect(asset.byteCount == rtfData.count)
        #expect(try Data(contentsOf: appSupportURL.appendingPathComponent(asset.rtfRelativePath)) == rtfData)
        #expect(!FileManager.default.fileExists(
            atPath: appSupportURL
                .appendingPathComponent(".staging/rich-text/rich-text-14-3000-00000000-0000-0000-0000-000000000004.rtf")
                .path
        ))
    }
}

private func makeIconTIFFData(width: Int, height: Int) throws -> Data {
    let widthValue = CGFloat(width)
    let heightValue = CGFloat(height)
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
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: widthValue, height: heightValue).fill()
    NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.90, alpha: 1).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 80, y: 80, width: widthValue - 160, height: heightValue - 160),
        xRadius: 180,
        yRadius: 180
    ).fill()
    NSColor.white.withAlphaComponent(0.90).setFill()
    NSBezierPath(
        ovalIn: NSRect(
            x: widthValue / 3,
            y: heightValue / 3,
            width: widthValue / 3,
            height: heightValue / 3
        )
    ).fill()
    NSGraphicsContext.restoreGraphicsState()

    return try #require(bitmap.representation(using: .tiff, properties: [:]))
}
