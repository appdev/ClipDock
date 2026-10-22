import AppKit
import Foundation
import Testing
@testable import ClipDock
@testable import ClipboardPanelApp

struct RustCopyPlanTests {
    @Test
    func filePlanReportsOnlyOwnersOfExistingExternalFiles() throws {
        let root = try directory()
        let external = try directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        let url = external.appendingPathComponent("document.txt")
        try Data("synthetic".utf8).write(to: url)
        let plan = try RustCopyPlan.plan(items: [
            item("missing", "file", text: external.appendingPathComponent("missing.txt").path),
            item("valid", "file", text: url.path)
        ], mode: .original, appSupportDirectory: root).get()
        #expect(plan.includedIDs == ["valid"])
        #expect(plan.skipped.map(\.itemID) == ["missing"])
        #expect(plan.payload == .fileURLs([url]))
        try FileManager.default.removeItem(at: url)
        #expect(plan.payloadForWriting() == .unsupported(reason: "missing_file_url"))
    }

    @Test
    func managedAssetsRejectOutsideRootAndSymlinksButExternalFilesRemainAllowed() throws {
        let root = try directory()
        let external = try directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        let outside = external.appendingPathComponent("image.png")
        try Data("synthetic".utf8).write(to: outside)
        let alias = root.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        for path in [outside.path, alias.path] {
            let plan = try RustCopyPlan.plan(items: [item("image", "image", asset: path)], mode: .original, appSupportDirectory: root).get()
            #expect(plan.payload == .unsupported(reason: "missing_image_asset"))
        }
        let file = try RustCopyPlan.plan(items: [item("file", "file", text: outside.path)], mode: .original, appSupportDirectory: root).get()
        #expect(file.includedIDs == ["file"])
        #expect(file.payload == .imageFile(outside))
    }

    @Test
    @MainActor
    func invalidImagePreparationLeavesNamedPasteboardUntouched() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("invalid.bin")
        try Data("not an image".utf8).write(to: path)
        let plan = try RustCopyPlan.plan(items: [item("image", "image", asset: path.path)], mode: .original, appSupportDirectory: root).get()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipDock.CopyPlan.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep fixture", forType: .string)
        let changeCount = pasteboard.changeCount
        #expect(!AppDelegate().smokeWriteCopyPlan(plan, to: pasteboard))
        #expect(pasteboard.changeCount == changeCount)
        #expect(pasteboard.string(forType: .string) == "keep fixture")
    }

    @Test
    @MainActor
    func lostRTFUsesCompleteFallbackWithoutDroppingItsOwner() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rtf = root.appendingPathComponent("body.rtf")
        try Data("{\\rtf1 full}".utf8).write(to: rtf)
        let body = String(repeating: "full text", count: 200)
        let plan = try RustCopyPlan.plan(items: [item("rich", "rich_text", text: body, asset: rtf.path)], mode: .original, appSupportDirectory: root).get()
        try FileManager.default.removeItem(at: rtf)
        #expect(plan.payloadForWriting() == .richText(rtfURL: nil, fallbackText: body))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipDock.CopyPlan.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(AppDelegate().smokeWriteCopyPlan(plan, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == body)
        #expect(plan.includedIDs == ["rich"])
    }

    @Test
    func explicitAndGlobalPlainAndDuplicateSelectionUseRealRustPolicy() throws {
        let link = item("link", "link", text: "https://fixture.example")
        #expect(try RustCopyPlan.plan(items: [link], mode: .explicitPlainText, appSupportDirectory: nil).get().payload == .unsupported(reason: "unsupported_type"))
        #expect(try RustCopyPlan.plan(items: [link], mode: .preferPlainText, appSupportDirectory: nil).get().payload == .text("https://fixture.example"))
        let text = item("text", "text", text: "complete")
        let plan = try RustCopyPlan.plan(items: [text, text, item("media", "image")], mode: .explicitPlainText, appSupportDirectory: nil).get()
        #expect(plan.includedIDs == ["text"])
        #expect(plan.skipped.map(\.itemID) == ["media"])
        #expect(plan.payload == .pasteboardItems([ClipboardPasteboardItemPayload(sourceItemIDs: ["text"], representations: [.string("complete\ncomplete")])]))
    }

    @Test
    @MainActor
    func copyRecordFailureIsReportedSeparatelyFromSuccessfulClipboardWrite() async {
        var statuses: [String] = []
        let coordinator = ClipboardListCoordinator(
            pageLoader: { _ in .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false)) },
            mutationPerformer: { _ in .success(RustItemManagementResult(affectedCount: 0)) }
        )
        coordinator.onStatusTextChanged = { statuses.append($0) }
        coordinator.performBatchMutation([.recordCopied(itemID: "missing")], summaryKind: .recordCopied)
        for _ in 0..<100 where statuses.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000) }
        #expect(statuses.first == "已复制；历史记录更新失败")
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func item(_ id: String, _ type: String, text: String? = nil, asset: String? = nil) -> RustClipboardItemSummary {
        RustClipboardItemSummary(id: id, itemType: type, summary: text ?? id, primaryText: text, contentHash: id,
            sourceAppId: nil, sourceAppName: nil, sourceAppIconPath: nil, previewAssetPath: nil, payloadAssetPath: asset,
            sourceConfidence: "unknown", firstCopiedAtMs: 1, lastCopiedAtMs: 1, copyCount: 1, isPinned: false,
            sizeBytes: 1, previewState: "ready")
    }
}
