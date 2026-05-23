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
    func boundsLongTextCardSummaryWhileFootnoteCountUsesFullText() {
        let longText = String(repeating: "alpha beta gamma\n", count: 30)
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "text",
                summary: longText,
                primaryText: longText
            )
        )

        #expect(presentation.summaryText == String((longText as NSString).substring(to: 500)))
        #expect((presentation.summaryText as NSString).length == 500)
        #expect(!presentation.summaryText.hasSuffix("…"))
        #expect(presentation.footnoteText == "\(longText.trimmingCharacters(in: .whitespacesAndNewlines).count) 个字符")
    }

    @Test
    func keepsFourHundredNinetyNineUTF16UnitTextSummaryUnchanged() {
        let text = String(repeating: "z", count: 499)
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "text",
                summary: "fallback",
                primaryText: text
            )
        )

        #expect(presentation.summaryText == text)
        #expect((presentation.summaryText as NSString).length == 499)
    }

    @Test
    func keepsExactFiveHundredUTF16UnitTextSummaryUnchanged() {
        let text = String(repeating: "a", count: 500)
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "text",
                summary: "fallback",
                primaryText: text
            )
        )

        #expect(presentation.summaryText == text)
        #expect((presentation.summaryText as NSString).length == 500)
    }

    @Test
    func truncatesFiveHundredOneUTF16UnitTextSummaryToFiveHundredWithoutEllipsis() {
        let text = String(repeating: "b", count: 501)
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "text",
                summary: "fallback",
                primaryText: text
            )
        )

        #expect(presentation.summaryText == String((text as NSString).substring(to: 500)))
        #expect((presentation.summaryText as NSString).length == 500)
        #expect(!presentation.summaryText.hasSuffix("…"))
    }

    @Test
    func preservesWhitespaceAndNewlinesInBoundedTextSummary() {
        let text = "\(String(repeating: "a", count: 498)) \nZ"
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "text",
                summary: "fallback",
                primaryText: text
            )
        )

        #expect(presentation.summaryText == "\(String(repeating: "a", count: 498)) \n")
        #expect((presentation.summaryText as NSString).length == 500)
    }

    @Test
    func avoidsSplittingSurrogatePairAtTextSummaryBoundary() {
        let text = "\(String(repeating: "a", count: 499))🙂Z"
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "text",
                summary: "fallback",
                primaryText: text
            )
        )

        #expect(presentation.summaryText == String(repeating: "a", count: 499))
        #expect((presentation.summaryText as NSString).length <= 500)
    }

    @Test
    func boundsRichTextSummaryLikeTextSummary() {
        let richText = String(repeating: "rich text\n", count: 60)
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "rich_text",
                summary: "fallback",
                primaryText: richText
            )
        )

        #expect(presentation.symbolName == "doc.text")
        #expect(presentation.displayType == "文本")
        #expect(presentation.summaryText == String((richText as NSString).substring(to: 500)))
        #expect((presentation.summaryText as NSString).length == 500)
        #expect(presentation.footnoteText == "\(richText.trimmingCharacters(in: .whitespacesAndNewlines).count) 个字符")
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
    func presentsNormalizedColorWithoutCardFootnoteAndKeepsPreviewDetails() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "color",
                summary: "#FF00AA",
                primaryText: "#FF00AA"
            )
        )

        #expect(presentation.symbolName == "paintpalette")
        #expect(presentation.displayType == "颜色")
        #expect(presentation.summaryText == "#FF00AA")
        #expect(presentation.footnoteText.isEmpty)
        #expect(presentation.colorValue?.normalizedHex == "#FF00AA")
        #expect(presentation.colorValue?.rgbText == "RGB 255, 0, 170")
        #expect(presentation.colorValue?.hslText == "HSL 320°, 100%, 50%")
        #expect(presentation.colorValue?.hsbText == "HSB 320°, 100%, 100%")
        #expect(presentation.colorValue?.previewMetadataText.contains("RGB 255, 0, 170") == true)
    }

    @Test
    func presentsMalformedStoredColorAsFallbackText() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "color",
                summary: "not-a-color",
                primaryText: "not-a-color"
            )
        )

        #expect(presentation.displayType == "颜色")
        #expect(presentation.summaryText == "not-a-color")
        #expect(presentation.footnoteText == "颜色格式不可用")
        #expect(presentation.colorValue == nil)
    }

    @Test
    func presentsFileSummaryAndMetadata() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "file",
                summary: "report.pdf · /tmp/report.pdf",
                primaryText: "/Users/evan/Downloads/report.pdf",
                copyCount: 3
            )
        )

        #expect(presentation.symbolName == "folder")
        #expect(presentation.displayType == "文件")
        #expect(presentation.summaryText.isEmpty)
        #expect(presentation.footnoteText == "/Users/evan/Downloads/report.pdf")
        #expect(presentation.fileTitle == "report.pdf")
        #expect(presentation.fileDetail == "/Users/evan/Downloads/report.pdf")
    }

    @Test
    func presentsSingleImageFileAsImageCard() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "file",
                summary: "shot.png · /Users/evan/Desktop/shot.png",
                primaryText: "/Users/evan/Desktop/shot.png",
                fileItems: [
                    RustClipboardFileItemSummary(
                        path: "/Users/evan/Desktop/shot.png",
                        fileName: "shot.png",
                        fileExtension: "png",
                        byteCount: 4096,
                        isDirectory: false,
                        width: 721,
                        height: 679,
                        contentType: "public.png"
                    )
                ]
            )
        )

        #expect(presentation.symbolName == "photo")
        #expect(presentation.displayType == "图片")
        #expect(presentation.summaryText.isEmpty)
        #expect(presentation.footnoteText == "721 × 679")
        #expect(presentation.fileTitle == nil)
        #expect(presentation.fileDetail == nil)
    }

    @Test
    func presentsMultiFileCountAsHeaderTitle() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "file",
                summary: "2 个文件 · first.png",
                primaryText: "/Users/evan/Downloads/first.png\n/Users/evan/Desktop/second.jpg"
            )
        )

        #expect(presentation.symbolName == "folder")
        #expect(presentation.displayType == "2 个文件")
        #expect(presentation.fileTitle == "2 个文件")
        #expect(presentation.footnoteText == "多个文件")
        #expect(presentation.fileDetail == "多个文件")
    }

    @Test
    func presentsMultipleImageFilesAsMultiFileCard() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "file",
                summary: "2 个图片文件",
                primaryText: "/Users/evan/Downloads/first.png\n/Users/evan/Desktop/second.jpg",
                fileItems: [
                    RustClipboardFileItemSummary(
                        path: "/Users/evan/Downloads/first.png",
                        fileName: "first.png",
                        fileExtension: "png",
                        byteCount: 1024,
                        isDirectory: false,
                        width: 96,
                        height: 64,
                        contentType: "public.png"
                    ),
                    RustClipboardFileItemSummary(
                        path: "/Users/evan/Desktop/second.jpg",
                        fileName: "second.jpg",
                        fileExtension: "jpg",
                        byteCount: 2048,
                        isDirectory: false,
                        width: 88,
                        height: 66,
                        contentType: "public.jpeg"
                    )
                ]
            )
        )

        #expect(presentation.symbolName == "folder")
        #expect(presentation.displayType == "2 个文件")
        #expect(presentation.footnoteText == "多个文件")
    }

    @Test
    func presentsMultiFileWithoutStoredPathUsingMultipleFilesLabel() {
        let presentation = PanelItemCardPresenter.presentation(
            for: makeItem(
                itemType: "file",
                summary: "2 个文件 · report.pdf",
                primaryText: nil,
                copyCount: 2
            )
        )

        #expect(presentation.summaryText.isEmpty)
        #expect(presentation.footnoteText == "多个文件")
        #expect(presentation.fileDetail == "多个文件")
    }
}

private func makeItem(
    itemType: String,
    summary: String,
    primaryText: String?,
    isPinned: Bool = false,
    copyCount: Int64 = 1,
    sizeBytes: Int64 = 128,
    linkMetadata: RustLinkMetadataSummary? = nil,
    fileItems: [RustClipboardFileItemSummary] = []
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
        fileItems: fileItems,
        linkMetadata: linkMetadata
    )
}
