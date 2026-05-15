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
