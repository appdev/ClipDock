import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ClipboardPanelApp
@testable import ClipDock

@Suite(.serialized)
struct CardRenameTests {
    @Test
    func bridgeRoundTripSearchResetAndCopyPayload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = RustCoreClient()
        let captured = try client.captureText(appSupportDirectory: root, request: RustCaptureTextRequest(
            text: "Original clipboard body", sourceBundleId: nil, sourceAppName: nil,
            sourceBundlePath: nil, sourceIconRelativePath: nil, sourceConfidence: "unknown",
            pasteboardChangeCount: 1
        )).get()
        _ = try client.renameItem(appSupportDirectory: root, itemId: captured.itemId, title: "测试重命名").get()
        let page = try client.listItems(appSupportDirectory: root, searchText: "ces").get()
        let item = try #require(page.items.first)
        #expect(item.customTitle == "测试重命名")
        #expect(item.primaryText == "Original clipboard body")
        let result = try client.renameItem(appSupportDirectory: root, itemId: item.id, title: "").get()
        #expect(result.affectedCount == 1)
        #expect(try client.listItems(appSupportDirectory: root).get().items.first?.customTitle == nil)
        #expect(try client.listItems(appSupportDirectory: root, searchText: "ceshi").get().totalCount == 0)
    }

    @Test(arguments: ["text", "rich_text", "image", "link", "file", "color"])
    func customTitleDoesNotChangeTypeOrContentPresentation(type: String) {
        let original = item(type: type)
        let renamed = item(type: type, title: "工作资料 📝")
        let before = PanelItemCardViewStateAdapter.makeViewState(for: original, selectedItemID: nil)
        let after = PanelItemCardViewStateAdapter.makeViewState(for: renamed, selectedItemID: nil)
        #expect(before.titleText == before.typeText)
        #expect(after.titleText == "工作资料 📝")
        #expect(after.typeText == before.typeText)
        #expect(after.summaryText == before.summaryText)
        #expect(after.footnoteText == before.footnoteText)
        #expect(after.preview == before.preview)
        #expect(after.assetRequest == before.assetRequest)
        #expect(PanelItemCardViewStateAdapter.stateBySettingTransientDecorations(
            after, isSelected: true, commandIndexText: "1"
        ).titleText == after.titleText)
    }

    @Test
    @MainActor
    func inlineRenameCommitsCancelsAndSurvivesReconcile() throws {
        let (window, view) = makePanel(items: [item()])
        defer { window.orderOut(nil) }
        var requests: [String] = []
        view.onRuntimeAction = { action in
            if case .renameItem(let id, let title, _) = action {
                #expect(id == "rename-fixture")
                requests.append(title)
            }
        }
        view.smokePrepareManagementMenu(itemID: "rename-fixture")
        let menu = try #require(view.smokeManagementMenuItems(itemID: "rename-fixture").first { $0.title == "重命名" })
        #expect(menu.isEnabled && menu.keyEquivalent == "r" && menu.modifiers == [.command])
        #expect(view.smokePerformManagementAction(itemID: "rename-fixture", title: "重命名"))
        let field = try #require(view.smokeCardRenameField)
        let session = try #require(field.delegate as? PanelCardRenameSession)
        #expect(field.stringValue == "文本")
        #expect(field.currentEditor()?.selectedRange == NSRange(location: 0, length: 2))
        field.stringValue = "  测试重命名  "
        // Different content forces cell reconstruction; the active field survives.
        view.updateListState(.success(RustCoreListResult(
            items: [item(body: "Updated synthetic preview")], totalCount: 1, hasMore: false
        )), isFiltered: false)
        view.layoutSubtreeIfNeeded()
        #expect(view.smokeCardRenameField === field)
        #expect(field.stringValue == "  测试重命名  ")
        #expect(session.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(requests == ["测试重命名"])
        #expect(view.smokeCardRenameField == nil)
        // Persistence has not returned: the submitted title stays visible.
        #expect(view.smokeCardBoxes().first?.typeHeaderLabel?.stringValue == "测试重命名")

        PanelQAHarness.sendPrintable(characters: "r", charactersIgnoringModifiers: "r", modifiers: [.command], keyCode: UInt16(kVK_ANSI_R), to: view)
        let cancelled = try #require(view.smokeCardRenameField)
        cancelled.stringValue = "Discarded draft"
        let cancelledSession = try #require(cancelled.delegate as? PanelCardRenameSession)
        #expect(cancelledSession.control(cancelled, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(requests == ["测试重命名"])
        #expect(view.smokeCardRenameField == nil)
    }

    @Test
    @MainActor
    func inlineRenameHandlesIMEFocusLossEmptyTitleAndMultiSelection() throws {
        let (window, view) = makePanel(items: [item(title: "Existing name"), item(id: "second")])
        defer { window.orderOut(nil) }
        var requests: [String] = []
        view.onRuntimeAction = { if case .renameItem(_, let title, _) = $0 { requests.append(title) } }
        view.smokeSelectItem(id: "rename-fixture")
        #expect(view.smokePerformManagementAction(itemID: "rename-fixture", title: "重命名"))
        let field = try #require(view.smokeCardRenameField)
        let session = try #require(field.delegate as? PanelCardRenameSession)
        let editor = NSTextView()
        editor.setMarkedText("ce", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!session.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(!session.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(view.smokeCardRenameField === field)
        editor.unmarkText()
        field.stringValue = "  "
        session.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(requests == [""])
        #expect(view.smokeCardRenameField == nil)
        view.smokeClickCard(itemID: "second", modifiers: [.command])
        #expect(view.smokeSelectedItemIDs.count == 2)
        #expect(view.smokeManagementMenuItems(itemID: "second").first { $0.title == "重命名" }?.isEnabled == false)
        PanelQAHarness.sendPrintable(characters: "r", charactersIgnoringModifiers: "r", modifiers: [.command], keyCode: UInt16(kVK_ANSI_R), to: view)
        #expect(view.smokeCardRenameField == nil)
    }

    @Test
    @MainActor
    func hideCommitsAndLongTitleStaysInsideHeader() throws {
        let longTitle = String(repeating: "测试长名称", count: 12)
        let (window, view) = makePanel(items: [item(title: longTitle)])
        defer { window.orderOut(nil) }
        let card = try #require(view.smokeCardBoxes().first)
        let label = try #require(card.typeHeaderLabel)
        #expect(label.toolTip == longTitle)
        #expect(label.lineBreakMode == .byTruncatingTail)
        #expect(label.frame.width < card.frame.width)
        view.smokeSelectItem(id: "rename-fixture")
        _ = view.smokePerformManagementAction(itemID: "rename-fixture", title: "重命名")
        let field = try #require(view.smokeCardRenameField)
        #expect(field.frame.width > 80)
        field.stringValue = "Saved on hide"
        var saved: String?
        view.onRuntimeAction = { if case .renameItem(_, let title, _) = $0 { saved = title } }
        view.finishCardRenameBeforeHiding()
        #expect(saved == "Saved on hide")
        #expect(label.alphaValue == 1)
    }

    @Test(arguments: [true, false])
    @MainActor
    func persistenceResultControlsRefreshAndFailureStatus(succeeds: Bool) async throws {
        let nextItem = item(title: "Saved title")
        var updates: [ClipboardListUpdate] = []
        var completions = 0
        var statuses: [String] = []
        var completionResults: [Bool] = []
        let coordinator = ClipboardListCoordinator(
            debounceNanoseconds: 0,
            pageLoader: { _ in .success(RustCoreListResult(items: [nextItem], totalCount: 1, hasMore: false)) },
            mutationPerformer: { request in
                #expect(request == .rename(itemID: "rename-fixture", title: "Saved title"))
                return succeeds ? .success(RustItemManagementResult(affectedCount: 1)) : .failure(
                    RustCoreError(code: "database_unavailable", messageKey: "clipboard.error.database_unavailable", recoverable: true, message: "Synthetic failure")
                )
            }
        )
        coordinator.onListUpdate = { updates.append($0) }
        coordinator.onMutationCompleted = { _, _ in completions += 1 }
        coordinator.onStatusTextChanged = { statuses.append($0) }
        coordinator.performMutation(.rename(itemID: "rename-fixture", title: "Saved title")) {
            completionResults.append($0)
        }
        for _ in 0..<100 {
            if succeeds ? !updates.isEmpty : !statuses.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(completions == (succeeds ? 1 : 0))
        #expect(completionResults == [succeeds])
        if succeeds {
            #expect(try updates.last?.result.get().items.first?.customTitle == "Saved title")
            #expect(updates.last?.preserveScrollPositionOnStructuralChange == true)
        } else {
            #expect(updates.isEmpty)
            #expect(statuses.contains { $0.contains("database_unavailable") })
        }
    }

    @Test(arguments: [true, false])
    @MainActor
    func submittedTitleStaysVisibleUntilSaveCompletesWithoutReplacingCards(succeeds: Bool) throws {
        let original = item(title: "Original")
        let neighbor = item(id: "neighbor", title: "Unchanged")
        let (window, view) = makePanel(items: [original, neighbor])
        defer { window.orderOut(nil) }
        view.smokeSelectItem(id: original.id)
        let card = try #require(view.smokeCardBoxes().first { $0.itemID == original.id })
        let otherCard = try #require(view.smokeCardBoxes().first { $0.itemID == neighbor.id })
        let label = try #require(card.typeHeaderLabel)
        let originalFrame = card.convert(card.bounds, to: view)
        var completion: ((Bool) -> Void)?
        view.onRuntimeAction = {
            if case .renameItem(_, _, let callback) = $0 { completion = callback }
        }
        #expect(view.smokePerformManagementAction(itemID: original.id, title: "重命名"))
        let field = try #require(view.smokeCardRenameField)
        field.stringValue = "Saved title"
        let session = try #require(field.delegate as? PanelCardRenameSession)
        #expect(session.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(label.stringValue == "Saved title")
        #expect(label.alphaValue == 1)
        #expect(label.toolTip == "Saved title")
        // A list result from before the save must not expose the original name.
        view.updateListState(.success(RustCoreListResult(items: [original, neighbor], totalCount: 2, hasMore: false)), isFiltered: false)
        #expect(label.stringValue == "Saved title")
        let finishSave = try #require(completion)
        finishSave(succeeds)
        #expect(label.stringValue == (succeeds ? "Saved title" : "Original"))
        if succeeds {
            // A relative-time change during persistence must not rebuild it either.
            view.updateListState(.success(RustCoreListResult(items: [item(title: "Saved title", ageMilliseconds: 120_000), neighbor], totalCount: 2, hasMore: false)), isFiltered: false)
            #expect(label.stringValue == "Saved title")
        }
        view.layoutSubtreeIfNeeded()
        #expect(view.smokeCardBoxes().first { $0.itemID == original.id } === card)
        #expect(view.smokeCardBoxes().first { $0.itemID == neighbor.id } === otherCard)
        #expect(card.convert(card.bounds, to: view) == originalFrame)
        #expect(view.smokeSelectedItemIDs == [original.id])
    }

    @Test
    @MainActor
    func earlierRenameCompletionCannotOverrideNewerDraftAndEmptyNameUsesType() throws {
        let (window, view) = makePanel(items: [item(title: "Original")])
        defer { window.orderOut(nil) }
        view.smokeSelectItem(id: "rename-fixture")
        var completions: [(Bool) -> Void] = []
        view.onRuntimeAction = {
            if case .renameItem(_, _, let callback) = $0 { completions.append(callback) }
        }
        for title in ["First", "Second", ""] {
            #expect(view.smokePerformManagementAction(itemID: "rename-fixture", title: "重命名"))
            let field = try #require(view.smokeCardRenameField)
            field.stringValue = title
            (field.delegate as? PanelCardRenameSession)?.finish(commit: true)
            #expect(view.smokeCardBoxes().first?.typeHeaderLabel?.stringValue == (title.isEmpty ? "文本" : title))
        }
        #expect(completions.count == 3)
        completions[0](false)
        completions[1](true)
        #expect(view.smokeCardBoxes().first?.typeHeaderLabel?.stringValue == "文本")
        completions[2](true)
        view.updateListState(.success(RustCoreListResult(items: [item()], totalCount: 1, hasMore: false)), isFiltered: false)
        #expect(view.smokeCardBoxes().first?.typeHeaderLabel?.stringValue == "文本")
        // The acknowledged override is retired, so subsequent real data wins.
        view.updateListState(.success(RustCoreListResult(items: [item(title: "External change")], totalCount: 1, hasMore: false)), isFiltered: false)
        #expect(view.smokeCardBoxes().first?.typeHeaderLabel?.stringValue == "External change")
    }

    @Test
    @MainActor
    func visualFixtureShowsSavedAndEditingTitles() throws {
        let (window, view) = makePanel(items: [
            item(title: "测试重命名", body: "名称可以用中文或拼音搜索。"),
            item(id: "english", title: "Computer Use", body: "Copy and paste still use the original content."),
            item(id: "editing", body: "Enter 保存 · Esc 取消\n清空名称可恢复默认标题。")
        ])
        defer { window.orderOut(nil) }
        view.smokeSelectItem(id: "editing")
        _ = view.smokePerformManagementAction(itemID: "editing", title: "重命名")
        let field = try #require(view.smokeCardRenameField)
        field.stringValue = "正在编辑名称"
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".codex/artifacts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for compact in [false, true] {
            let size = compact ? NSSize(width: 760, height: 260) : NSSize(width: 940, height: 302)
            window.setContentSize(size)
            view.updatePanelHeight(size.height)
            view.layoutSubtreeIfNeeded()
            let label = try #require(view.smokeCardBoxes().first { $0.itemID == "editing" }?.typeHeaderLabel)
            #expect(field.frame == label.convert(label.bounds, to: view))
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent(compact ? "card-rename-compact.png" : "card-rename.png"))
            #expect(view.smokeCardRenameField === field)
        }
        (field.delegate as? PanelCardRenameSession)?.finish(commit: false)
    }

    private func item(id: String = "rename-fixture", type: String = "text", title: String? = nil, body: String = "Computer Use", ageMilliseconds: Int64 = 0) -> RustClipboardItemSummary {
        let capturedAt = Int64(Date().timeIntervalSince1970 * 1_000) - ageMilliseconds
        return RustClipboardItemSummary(
            id: id, itemType: type, summary: body, primaryText: body,
            contentHash: id, sourceAppId: nil, sourceAppName: "ClipDock QA",
            sourceAppIconPath: nil, previewAssetPath: nil, payloadAssetPath: nil,
            sourceConfidence: "unknown", firstCopiedAtMs: capturedAt, lastCopiedAtMs: capturedAt,
            copyCount: 1, isPinned: false, sizeBytes: 12, previewState: "ready", customTitle: title
        )
    }

    @MainActor
    private func makePanel(items: [RustClipboardItemSummary]) -> (NSWindow, FloatingPanelContentView) {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: 940, height: 302)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = FloatingPanelContentView(frame: frame)
        window.contentView = view
        view.updateListState(.success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)), isFiltered: false)
        view.layoutSubtreeIfNeeded()
        return (window, view)
    }
}
