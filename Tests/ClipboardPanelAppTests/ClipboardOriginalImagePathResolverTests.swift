import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardOriginalImagePathResolverTests {
    @Test
    func imageItemsCopyPayloadAssetPathInsteadOfThumbnailPath() {
        let appSupportDirectory = URL(fileURLWithPath: "/tmp/clipboard-workbench", isDirectory: true)
        let item = makeImagePathResolverItem(
            id: "clipboard-image",
            itemType: "image",
            primaryText: nil,
            previewAssetPath: "thumbnails/captured.heic",
            payloadAssetPath: "assets/captured.heic"
        )

        let paths = ClipboardOriginalImagePathResolver.originalImagePaths(
            for: item,
            appSupportDirectory: appSupportDirectory
        )

        #expect(paths == ["/tmp/clipboard-workbench/assets/captured.heic"])
    }

    @Test
    func fileItemsCopyOnlyImageFileMetadataPaths() {
        let imagePath = "/Users/evan/Desktop/photo.png"
        let jpegPath = "/Users/evan/Desktop/scan.jpeg"
        let item = makeImagePathResolverItem(
            id: "file-images",
            itemType: "file",
            primaryText: "\(imagePath)\n/Users/evan/Desktop/report.pdf\n\(jpegPath)",
            previewAssetPath: nil,
            payloadAssetPath: nil,
            fileItems: [
                RustClipboardFileItemSummary(
                    path: imagePath,
                    fileName: "photo.png",
                    fileExtension: "png",
                    byteCount: 42,
                    isDirectory: false,
                    width: 120,
                    height: 90,
                    contentType: "public.png"
                ),
                RustClipboardFileItemSummary(
                    path: "/Users/evan/Desktop/report.pdf",
                    fileName: "report.pdf",
                    fileExtension: "pdf",
                    byteCount: 100,
                    isDirectory: false,
                    width: nil,
                    height: nil,
                    contentType: "com.adobe.pdf"
                ),
                RustClipboardFileItemSummary(
                    path: "/Users/evan/Desktop/folder",
                    fileName: "folder",
                    fileExtension: nil,
                    byteCount: 0,
                    isDirectory: true,
                    width: nil,
                    height: nil,
                    contentType: nil
                )
            ]
        )

        let paths = ClipboardOriginalImagePathResolver.originalImagePaths(
            for: item,
            appSupportDirectory: nil
        )

        #expect(paths == [imagePath, jpegPath])
    }

    @Test
    func fileItemsRecognizeMimeTypeAndKnownImageExtensions() {
        let webpPath = "/Users/evan/Pictures/cover.webp"
        let svgPath = "/Users/evan/Pictures/logo.svg"
        let item = makeImagePathResolverItem(
            id: "extension-images",
            itemType: "file",
            primaryText: nil,
            previewAssetPath: nil,
            payloadAssetPath: nil,
            fileItems: [
                RustClipboardFileItemSummary(
                    path: webpPath,
                    fileName: "cover.webp",
                    fileExtension: "webp",
                    byteCount: 20,
                    isDirectory: false,
                    width: nil,
                    height: nil,
                    contentType: "image/webp"
                ),
                RustClipboardFileItemSummary(
                    path: svgPath,
                    fileName: "logo.svg",
                    fileExtension: "svg",
                    byteCount: 12,
                    isDirectory: false,
                    width: nil,
                    height: nil,
                    contentType: nil
                )
            ]
        )

        let paths = ClipboardOriginalImagePathResolver.originalImagePaths(
            for: item,
            appSupportDirectory: nil
        )

        #expect(paths == [webpPath, svgPath])
    }

    @Test
    func nonImageItemsDoNotExposePathCopyTargets() {
        let item = makeImagePathResolverItem(
            id: "text",
            itemType: "text",
            primaryText: "/Users/evan/Desktop/photo.png",
            previewAssetPath: nil,
            payloadAssetPath: nil
        )

        let paths = ClipboardOriginalImagePathResolver.originalImagePaths(
            for: item,
            appSupportDirectory: nil
        )

        #expect(paths.isEmpty)
    }
}

private func makeImagePathResolverItem(
    id: String,
    itemType: String,
    primaryText: String?,
    previewAssetPath: String?,
    payloadAssetPath: String?,
    fileItems: [RustClipboardFileItemSummary] = []
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: itemType,
        summary: primaryText ?? id,
        primaryText: primaryText,
        contentHash: id,
        sourceAppId: nil,
        sourceAppName: nil,
        sourceAppIconPath: nil,
        previewAssetPath: previewAssetPath,
        payloadAssetPath: payloadAssetPath,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 0,
        previewState: "ready",
        fileItems: fileItems
    )
}
