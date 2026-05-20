import Foundation
import Testing
@testable import ClipboardPanelApp

struct PanelItemCardViewStateTests {
    @Test
    func imageItemMapsSelectionRelativeTimeAndPreviewState() {
        let item = makePanelItemCardStateItem(
            id: "image-1",
            itemType: "image",
            summary: "图片 100 x 100",
            primaryText: nil,
            previewAssetPath: "preview.png",
            payloadAssetPath: "payload.png"
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: "image-1",
            relativeTimeFormatter: { _ in "2m ago" }
        )

        #expect(state.itemID == "image-1")
        #expect(state.sourceAppName == "Preview")
        #expect(state.relativeTimeText == "2m ago")
        #expect(state.isSelected)
        #expect(state.footnoteText == "100 × 100")
        #expect(state.preview == .image(previewPath: "preview.png", payloadPath: nil, summary: "图片 100 x 100"))
        #expect(state.assetRequest.payloadAssetPath == "payload.png")
    }

    @Test
    func linkItemMapsLinkPreviewMetadata() {
        let item = makePanelItemCardStateItem(
            id: "link-1",
            itemType: "link",
            summary: "example.com",
            primaryText: "https://example.com/docs?q=1"
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "now" }
        )

        #expect(state.symbolName == "link")
        #expect(state.typeText == "链接")
        #expect(state.summaryText.isEmpty)
        #expect(state.footnoteText == "example.com/docs?q=1")
        #expect(state.preview == .link(
            title: "",
            host: "example.com",
            detail: "example.com/docs?q=1",
            iconPath: nil,
            imagePath: nil,
            accessibilityLabel: "Preview"
        ))
        #expect(state.assetRequest.sourceAppIconPath == "/tmp/Preview.app/icon.icns")
    }

    @Test
    func fileItemMapsFilePreviewAndAssetRequest() {
        let item = makePanelItemCardStateItem(
            id: "file-1",
            itemType: "file",
            summary: "report.pdf · /tmp/report.pdf",
            primaryText: "/tmp/report.pdf\n/tmp/notes.txt",
            payloadAssetPath: "snapshots/report.json"
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "yesterday" }
        )

        #expect(state.preview == .file(accessibilityLabel: "Preview"))
        #expect(state.summaryText.isEmpty)
        #expect(state.footnoteText == "/tmp/report.pdf\n/tmp/notes.txt")
        #expect(state.assetRequest.payloadAssetPath == "snapshots/report.json")
        #expect(state.assetRequest.primaryText == "/tmp/report.pdf\n/tmp/notes.txt")
    }

    @Test
    func linkMetadataExposesCachedAssets() {
        let item = makePanelItemCardStateItem(
            id: "link-ready",
            itemType: "link",
            summary: "example.com",
            primaryText: "https://example.com/docs",
            linkMetadata: RustLinkMetadataSummary(
                canonicalURL: "https://example.com/docs",
                displayURL: "example.com/docs",
                host: "example.com",
                title: "Cached title",
                iconAssetPath: "assets/link-icons/example.png",
                imageAssetPath: "assets/link-previews/example.jpg",
                metadataState: "ready"
            )
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "now" }
        )

        #expect(state.preview == .link(
            title: "Cached title",
            host: "example.com",
            detail: "example.com/docs",
            iconPath: "assets/link-icons/example.png",
            imagePath: "assets/link-previews/example.jpg",
            accessibilityLabel: "Preview"
        ))
    }

    @Test
    func textItemMapsPlainCardWithoutPreview() {
        let item = makePanelItemCardStateItem(
            id: "text-1",
            itemType: "text",
            summary: "hello",
            primaryText: "hello"
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "now" }
        )

        #expect(state.preview == .none)
        #expect(state.summaryText == "hello")
        #expect(state.commandIndexText == nil)
        #expect(state.isSelected == false)
    }

    @Test
    func selectedIDSetMarksAnyMemberSelected() {
        let item = makePanelItemCardStateItem(
            id: "text-2",
            itemType: "text",
            summary: "hello",
            primaryText: "hello"
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: "text-1",
            selectedItemIDs: ["text-1", "text-2"],
            relativeTimeFormatter: { _ in "now" }
        )

        #expect(state.isSelected)
    }

    @Test
    func colorItemMapsColorPreviewWithoutAssetPreview() throws {
        let item = makePanelItemCardStateItem(
            id: "color-1",
            itemType: "color",
            summary: "#FF00AA",
            primaryText: "#FF00AA",
            previewAssetPath: "should-not-load.png",
            payloadAssetPath: "should-not-load-payload.png"
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "now" }
        )

        let color = try #require({
            if case .color(let value) = state.preview {
                return value
            }
            return nil
        }())
        #expect(color.normalizedHex == "#FF00AA")
        #expect(state.summaryText == "#FF00AA")
        #expect(state.footnoteText.isEmpty)
        #expect(state.assetRequest.previewAssetPath == "should-not-load.png")
    }

    @Test
    func malformedColorItemFallsBackWithoutColorPreview() {
        let item = makePanelItemCardStateItem(
            id: "bad-color",
            itemType: "color",
            summary: "bad",
            primaryText: "bad"
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "now" }
        )

        #expect(state.preview == .none)
        #expect(state.summaryText == "bad")
        #expect(state.footnoteText == "颜色格式不可用")
    }

    @Test
    func colorItemTransientCommandIndexPreservesPreviewAndClearsCleanly() {
        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: makePanelItemCardStateItem(
                id: "color-command",
                itemType: "color",
                summary: "#FDF6E3",
                primaryText: "#FDF6E3"
            ),
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "now" }
        )

        let indexedState = PanelItemCardViewStateAdapter.stateBySettingCommandIndexText(
            state,
            commandIndexText: "4"
        )
        let clearedState = PanelItemCardViewStateAdapter.stateBySettingCommandIndexText(
            indexedState,
            commandIndexText: nil
        )

        #expect(indexedState.commandIndexText == "4")
        #expect(indexedState.preview == state.preview)
        #expect(indexedState.footnoteText.isEmpty)
        #expect(clearedState.commandIndexText == nil)
        #expect(clearedState.preview == state.preview)
    }

    @Test
    func textItemKeepsAssetRequestPrimaryTextFullWhileSummaryTextIsBounded() {
        let fullText = "\(String(repeating: "a", count: 499))🙂Z"
        let item = makePanelItemCardStateItem(
            id: "text-long",
            itemType: "text",
            summary: "fallback",
            primaryText: fullText
        )

        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "now" }
        )

        #expect(state.preview == .none)
        #expect(state.summaryText == String(repeating: "a", count: 499))
        #expect((state.summaryText as NSString).length <= 500)
        #expect(state.assetRequest.primaryText == fullText)
    }

    @Test
    func commandIndexStateUpdatesAndMapsVisibleItems() {
        let baseState = PanelItemCardViewStateAdapter.makeViewState(
            for: makePanelItemCardStateItem(
                id: "a",
                itemType: "text",
                summary: "alpha",
                primaryText: "alpha"
            ),
            selectedItemID: nil,
            relativeTimeFormatter: { _ in "now" }
        )

        let updatedState = PanelItemCardViewStateAdapter.stateBySettingCommandIndexText(
            baseState,
            commandIndexText: "3"
        )
        let mapping = PanelItemCardViewStateAdapter.commandIndexTextByItemID(
            for: ["a", "b", "c"],
            enabled: true
        )

        #expect(updatedState.commandIndexText == "3")
        #expect(mapping == ["a": "1", "b": "2", "c": "3"])
        #expect(PanelItemCardViewStateAdapter.commandIndexTextByItemID(for: ["a"], enabled: false).isEmpty)
    }
}

private func makePanelItemCardStateItem(
    id: String,
    itemType: String,
    summary: String,
    primaryText: String?,
    previewAssetPath: String? = nil,
    payloadAssetPath: String? = nil,
    linkMetadata: RustLinkMetadataSummary? = nil
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: itemType,
        summary: summary,
        primaryText: primaryText,
        contentHash: id,
        sourceAppId: "com.example.preview",
        sourceAppName: "Preview",
        sourceAppIconPath: "/tmp/Preview.app/icon.icns",
        previewAssetPath: previewAssetPath,
        payloadAssetPath: payloadAssetPath,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 2,
        isPinned: false,
        sizeBytes: 2048,
        previewState: "ready",
        linkMetadata: linkMetadata
    )
}
