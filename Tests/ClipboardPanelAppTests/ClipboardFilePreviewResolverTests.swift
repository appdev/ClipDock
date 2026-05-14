import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardFilePreviewResolverTests {
    @Test
    func resolvesFileURLsFromPrimaryTextAndFiltersMissingPaths() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let firstFile = tempDirectory.appendingPathComponent("report.pdf")
        let secondFile = tempDirectory.appendingPathComponent("notes.txt")
        try Data("report".utf8).write(to: firstFile)
        try Data("notes".utf8).write(to: secondFile)

        let urls = ClipboardFilePreviewResolver.fileURLs(
            previewAssetPath: nil,
            payloadAssetPath: nil,
            primaryText: "\(firstFile.path)\n\(secondFile.path)\n\(firstFile.path)\n/tmp/missing-file",
            appSupportDirectory: tempDirectory
        )

        #expect(urls == [firstFile.standardizedFileURL, secondFile.standardizedFileURL])
    }

    @Test
    func resolvesFileURLsFromSnapshotWhenPrimaryTextIsMissing() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshotDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("file-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("archive.zip")
        try Data("archive".utf8).write(to: fileURL)
        let snapshotURL = snapshotDirectory.appendingPathComponent("files.json")
        let snapshotData = try JSONEncoder().encode(["paths": [fileURL.path]])
        try snapshotData.write(to: snapshotURL)

        let urls = ClipboardFilePreviewResolver.fileURLs(
            previewAssetPath: nil,
            payloadAssetPath: "assets/file-snapshots/files.json",
            primaryText: nil,
            appSupportDirectory: tempDirectory
        )

        #expect(urls == [fileURL.standardizedFileURL])
    }

    @Test
    func resolvesFileURLsFromStructuredMetadataBeforeLegacySnapshot() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("metadata.mov")
        try Data("movie".utf8).write(to: fileURL)

        let urls = ClipboardFilePreviewResolver.fileURLsFromMetadata(
            [
                RustClipboardFileItemSummary(
                    path: fileURL.path,
                    fileName: "metadata.mov",
                    fileExtension: "mov",
                    byteCount: 5,
                    isDirectory: false,
                    width: 1280,
                    height: 720,
                    contentType: "com.apple.quicktime-movie"
                )
            ],
            appSupportDirectory: tempDirectory
        )

        #expect(urls == [fileURL.standardizedFileURL])
    }

    @Test
    func previewPlannerIncludesFileURLsForFileItems() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("design.sketch")
        try Data("design".utf8).write(to: fileURL)
        let item = RustClipboardItemSummary(
            id: "file-preview",
            itemType: "file",
            summary: "design.sketch",
            primaryText: fileURL.path,
            contentHash: "file-preview",
            sourceAppId: "com.apple.finder",
            sourceAppName: "Finder",
            sourceAppIconPath: nil,
            previewAssetPath: nil,
            payloadAssetPath: nil,
            sourceConfidence: "high",
            firstCopiedAtMs: 1,
            lastCopiedAtMs: 1,
            copyCount: 1,
            isPinned: false,
            sizeBytes: 12,
            previewState: "ready",
            fileItems: [
                RustClipboardFileItemSummary(
                    path: fileURL.path,
                    fileName: "design.sketch",
                    fileExtension: "sketch",
                    byteCount: 6,
                    isDirectory: false,
                    width: nil,
                    height: nil,
                    contentType: nil
                )
            ]
        )

        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(preview.itemType == "file")
        #expect(preview.fileURLs == [fileURL.standardizedFileURL])
        #expect(preview.imageURL == nil)
    }
}
