import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardColorPlannerTests {
    @Test
    func pastePayloadCopiesNormalizedColorText() {
        let item = makeColorPlannerItem(summary: "#ff00aa", primaryText: "#ff00aa")
        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        #expect(payload == .text("#FF00AA"))
    }

    @Test
    func previewPlannerIncludesColorMetadata() throws {
        let item = makeColorPlannerItem(summary: "#FF00AA", primaryText: "#FF00AA")
        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        let color = try #require(preview.colorValue)
        #expect(preview.itemType == "color")
        #expect(preview.title == "#FF00AA")
        #expect(preview.body.contains("RGB 255, 0, 170"))
        #expect(preview.metadata.contains("HSL 320°, 100%, 50%"))
        #expect(color.hsbText == "HSB 320°, 100%, 100%")
    }

    @Test
    func malformedColorPreviewFallsBackToStoredText() {
        let item = makeColorPlannerItem(summary: "bad-color", primaryText: "bad-color")
        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        #expect(preview.colorValue == nil)
        #expect(preview.body == "bad-color")
        #expect(preview.metadata == "颜色格式不可用")
        #expect(payload == .unsupported(reason: "invalid_color"))
    }
}

private func makeColorPlannerItem(summary: String, primaryText: String?) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: "color-item",
        itemType: "color",
        summary: summary,
        primaryText: primaryText,
        contentHash: "color",
        sourceAppId: nil,
        sourceAppName: "Digital Color Meter",
        sourceAppIconPath: nil,
        sourceAppIconHeaderColor: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 7,
        previewState: "ready",
        payloadState: "ready"
    )
}
