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
        #expect(presentation.summaryText.isEmpty)
        #expect(presentation.footnoteText == "example.com/docs?q=1")
        #expect(presentation.linkHost == "example.com")
        #expect(presentation.linkDetail == "example.com/docs?q=1")
        #expect(presentation.linkTitle == nil)
    }

    @Test
    func presentsLinkTitleWhenMetadataProvidesTitle() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "link",
                summary: "GitHub",
                primaryText: "https://github.com/",
                linkMetadata: RustLinkMetadataSummary(
                    canonicalURL: "https://github.com/",
                    displayURL: "https://github.com/",
                    host: "github.com",
                    title: "GitHub · Change is constant",
                    metadataState: "ready"
                )
            )
        )

        #expect(presentation.footnoteText == "github.com")
        #expect(presentation.linkHost == "github.com")
        #expect(presentation.linkDetail == "https://github.com/")
        #expect(presentation.linkTitle == "GitHub · Change is constant")
    }

    @Test
    func doesNotUseSiteNameAsMissingLinkTitle() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "link",
                summary: "GitHub",
                primaryText: "https://github.com/",
                linkMetadata: RustLinkMetadataSummary(
                    canonicalURL: "https://github.com/",
                    displayURL: "https://github.com/",
                    host: "github.com",
                    siteName: "GitHub",
                    metadataState: "ready"
                )
            )
        )

        #expect(presentation.footnoteText == "github.com")
        #expect(presentation.linkHost == "github.com")
        #expect(presentation.linkDetail == "https://github.com/")
        #expect(presentation.linkTitle == nil)
    }

    @Test
    func presentsCachedLinkMetadataForDisplay() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "link",
                summary: "GitHub",
                primaryText: "https://github.com/",
                linkMetadata: RustLinkMetadataSummary(
                    canonicalURL: "https://github.com/",
                    displayURL: "github.com",
                    host: "github.com",
                    title: "Cached title",
                    metadataState: "ready"
                )
            )
        )

        #expect(presentation.footnoteText == "github.com")
        #expect(presentation.linkHost == "github.com")
        #expect(presentation.linkDetail == "github.com")
        #expect(presentation.linkTitle == "Cached title")
    }

    @Test
    func presentsImageFooterResolutionWithoutBodyMetadata() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "image",
                summary: "图片 100 x 100",
                primaryText: nil
            )
        )

        #expect(presentation.symbolName == "photo")
        #expect(presentation.summaryText.isEmpty)
        #expect(presentation.footnoteText == "100 × 100")
    }

    @Test
    func presentsFileSummaryAndMetadata() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "file",
                summary: "report.pdf · /tmp/report.pdf",
                primaryText: "/Users/evan/Downloads/report.pdf\n/Users/evan/Desktop/notes.txt",
                copyCount: 3
            )
        )

        #expect(presentation.symbolName == "folder")
        #expect(presentation.displayType == "文件")
        #expect(presentation.summaryText.isEmpty)
        #expect(presentation.footnoteText == "/Users/evan/Downloads/report.pdf\n/Users/evan/Desktop/notes.txt")
        #expect(presentation.fileTitle == "report.pdf")
        #expect(presentation.fileDetail == "/Users/evan/Downloads/report.pdf\n/Users/evan/Desktop/notes.txt")
    }

    @Test
    func presentsFileWithoutStoredPathUsingPathFallback() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "file",
                summary: "2 个文件 · report.pdf",
                primaryText: nil,
                copyCount: 2
            )
        )

        #expect(presentation.summaryText.isEmpty)
        #expect(presentation.footnoteText == "本地文件路径")
        #expect(presentation.fileDetail == "本地文件路径")
    }
}

private func makeItem(
    itemType: String,
    summary: String,
    primaryText: String?,
    isPinned: Bool = false,
    copyCount: Int64 = 1,
    sizeBytes: Int64 = 128,
    linkMetadata: RustLinkMetadataSummary? = nil
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
        previewState: "ready",
        linkMetadata: linkMetadata
    )
}
