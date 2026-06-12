import AppKit
import ClipboardPanelApp
import Foundation
import Testing
@testable import ClipDock

struct ClipboardDiagnosticsTests {
    @Test
    @MainActor
    func reportDescribesImageDecisionWithoutLeakingPasteboardText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let sensitiveText = "Confidential Word text that should stay redacted"
        defer { pasteboard.clearContents() }

        pasteboard.clearContents()
        _ = pasteboard.declareTypes([.string, .png], owner: nil)
        #expect(pasteboard.setString(sensitiveText, forType: .string))
        #expect(pasteboard.setData(Data([0x89, 0x50, 0x4e, 0x47]), forType: .png))

        let report = ClipboardDiagnosticsReport.make(
            pasteboard: pasteboard,
            latestItem: .unavailable(reason: "test"),
            appVersion: "9.9.9",
            appBuild: "99",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(report.contains("decision=image"))
        #expect(report.contains("type=\"public.png\""))
        #expect(report.contains("string_chars=\(sensitiveText.count)"))
        #expect(report.contains("normalized_chars=\(sensitiveText.count)"))
        #expect(!report.contains(sensitiveText))
    }

    @Test
    @MainActor
    func reportClassifiesPureLinksWithoutIncludingTheURL() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let copiedURL = "https://english.news.cn/20260609/9e32edbd6ad94d4e8d6a42441cf14d1b/c.html"
        defer { pasteboard.clearContents() }

        pasteboard.clearContents()
        #expect(pasteboard.setString(copiedURL, forType: .string))

        let report = ClipboardDiagnosticsReport.make(
            pasteboard: pasteboard,
            latestItem: .unavailable(reason: "test"),
            appVersion: "9.9.9",
            appBuild: "99",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(report.contains("decision=text"))
        #expect(report.contains("pure_link=true"))
        #expect(report.contains("text_chars=\(copiedURL.count)"))
        #expect(!report.contains(copiedURL))
    }

    @Test
    @MainActor
    func reportDescribesLatestStoredItemWithoutLeakingSummaryOrPrimaryText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let sensitiveSummary = "Sensitive stored summary"
        let sensitivePrimaryText = "Sensitive stored primary text"
        defer { pasteboard.clearContents() }

        pasteboard.clearContents()
        #expect(pasteboard.setString("diagnostic trigger", forType: .string))

        let report = ClipboardDiagnosticsReport.make(
            pasteboard: pasteboard,
            latestItem: .item(makeDiagnosticsItem(
                itemType: "image",
                summary: sensitiveSummary,
                primaryText: sensitivePrimaryText
            )),
            appVersion: "9.9.9",
            appBuild: "99",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(report.contains("status=available"))
        #expect(report.contains("item_type=\"image\""))
        #expect(report.contains("source_app_name=\"Microsoft Word\""))
        #expect(report.contains("summary_chars=\(sensitiveSummary.count)"))
        #expect(report.contains("primary_text_chars=\(sensitivePrimaryText.count)"))
        #expect(!report.contains(sensitiveSummary))
        #expect(!report.contains(sensitivePrimaryText))
    }
}

private func makeDiagnosticsItem(
    itemType: String,
    summary: String,
    primaryText: String?
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: "diagnostics-item",
        itemType: itemType,
        summary: summary,
        primaryText: primaryText,
        contentHash: "diagnostics-hash",
        sourceAppId: "com.microsoft.Word",
        sourceAppName: "Microsoft Word",
        sourceAppIconPath: nil,
        previewAssetPath: "previews/item.webp",
        payloadAssetPath: "payloads/item.webp",
        sourceConfidence: "foreground",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 2,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 2048,
        previewState: "ready",
        payloadState: "ready"
    )
}
