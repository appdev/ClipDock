import Foundation
import Testing
@testable import ClipboardPanelApp

struct PanelItemCardPresentationTests {
    @Test
    func presentsPinnedTextItemWithoutInlinePinnedLabel() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "text",
                summary: "hello",
                primaryText: "hello",
                isPinned: true
            )
        )

        #expect(presentation.symbolName == "doc.text")
        #expect(presentation.displayType == "文本")
        #expect(presentation.summaryText == "hello")
        #expect(presentation.footnoteText == "5 个字符")
    }

    @Test
    func presentsLinkHostAndDetail() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "link",
                summary: "example.com",
                primaryText: "https://example.com/docs?q=1"
            )
        )

        #expect(presentation.symbolName == "link")
        #expect(presentation.displayType == "链接")
        #expect(presentation.summaryText == "https://example.com/docs?q=1")
        #expect(presentation.footnoteText == "example.com")
        #expect(presentation.linkHost == "example.com")
        #expect(presentation.linkDetail == "https://example.com/docs?q=1")
    }

    @Test
    func presentsImageSummaryFromByteCountAndCopyCount() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "image",
                summary: "图片 100 x 100",
                primaryText: nil,
                copyCount: 2,
                sizeBytes: 2048
            ),
            byteCountFormatter: { _ in "2 KB" }
        )

        #expect(presentation.symbolName == "photo")
        #expect(presentation.summaryText == "PNG · 2 KB · 2 次复制")
        #expect(presentation.footnoteText == "2 KB")
    }

    @Test
    func presentsFileSummaryAndMetadata() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "file",
                summary: "report.pdf · /tmp/report.pdf",
                primaryText: nil,
                copyCount: 3
            )
        )

        #expect(presentation.symbolName == "folder")
        #expect(presentation.displayType == "文件")
        #expect(presentation.summaryText == "report.pdf · 3 次复制")
        #expect(presentation.footnoteText == "3 次复制")
        #expect(presentation.fileTitle == "report.pdf")
        #expect(presentation.fileDetail == "/tmp/report.pdf")
    }
}

private func makeItem(
    itemType: String,
    summary: String,
    primaryText: String?,
    isPinned: Bool = false,
    copyCount: Int64 = 1,
    sizeBytes: Int64 = 128
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: UUID().uuidString,
        itemType: itemType,
        summary: summary,
        primaryText: primaryText,
        contentHash: UUID().uuidString,
        sourceAppId: nil,
        sourceAppName: nil,
        sourceAppIconPath: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: copyCount,
        isPinned: isPinned,
        sizeBytes: sizeBytes,
        previewState: "ready"
    )
}
