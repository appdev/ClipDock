import AppKit
import Foundation
import Testing
@testable import ClipDock
@testable import ClipboardPanelApp

struct ClipboardDetailRuntimeTests {
    @Test
    @MainActor
    func removedDetailIsInvalidatedBeforeDeferredListRendering() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let controller = FloatingPanelController()
        defer {
            controller.smokeSetPresentationAnimationTimelinePaused(false)
            controller.hide()
        }
        let view = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: true)
        let loader = DeferredDetailLoader()
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.setCompleteItemLoader { await loader.load($0) }
        controller.updateListState(.success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)), isFiltered: false)
        controller.smokeSetPresentationAnimationTimelinePaused(true)
        controller.show()
        PanelQAHarness.drainMainRunLoop()
        PanelQAHarness.sendSpace(to: view)
        let detailTask = try #require(view.smokeDetailLoadTask)
        await loader.waitUntilPending()
        #expect(controller.smokeHasActivePanelAnimation)
        #expect(view.smokePendingDetailItemID == item.id)

        controller.updateListState(.success(RustCoreListResult(items: [], totalCount: 0, hasMore: false)), isFiltered: false)

        #expect(controller.smokeHasDeferredListUpdate)
        #expect(view.smokeOrderedCardItemIDs() == [item.id])
        #expect(view.smokePendingDetailItemID == nil)
        #expect(detailTask.isCancelled)
        await loader.finish(item)
        await detailTask.value
        #expect(!view.smokeIsPreviewShown)
        #expect(view.smokePendingDetailItemID == nil)
        #expect(controller.smokeHasActivePanelAnimation)

        // A nonanimated show releases the pending render without a timer.
        controller.show()
        #expect(!controller.smokeHasDeferredListUpdate)
        #expect(view.smokeOrderedCardItemIDs().isEmpty)
    }

    @Test(arguments: ["close", "scope", "removed", "disabled"])
    @MainActor
    func delayedDetailCannotReopenAfterIntentIsInvalidated(action: String) async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let controller = FloatingPanelController()
        defer { controller.hide() }
        let view = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: true)
        let loader = DeferredDetailLoader()
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.setCompleteItemLoader { await loader.load($0) }
        controller.show()
        controller.updateListState(.success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)), isFiltered: false)
        PanelQAHarness.drainMainRunLoop()
        PanelQAHarness.sendSpace(to: view)
        #expect(await waitForDetailCondition { await loader.isPending })
        #expect(view.smokePendingDetailItemID == item.id)
        switch action {
        case "scope": view.smokeOpenSearch(text: "new-scope")
        case "removed": controller.updateListState(.success(RustCoreListResult(items: [], totalCount: 0, hasMore: false)), isFiltered: false)
        case "disabled": controller.setPreviewPopoverEnabled(false)
        default: controller.hide()
        }
        await loader.finish(item)
        PanelQAHarness.drainMainRunLoop()
        for _ in 0..<10 { await Task.yield() }
        #expect(!view.smokeIsPreviewShown)
        #expect(view.smokePendingDetailItemID == nil)
    }

    @Test(arguments: ["retained", "background_scope", "append", "failure"])
    @MainActor
    func deferredListUpdatesPreserveDetailsWithoutAuthoritativeRemoval(update: String) async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let controller = FloatingPanelController()
        defer {
            controller.smokeSetPresentationAnimationTimelinePaused(false)
            controller.hide()
        }
        let view = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: true)
        let loader = DeferredDetailLoader()
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.setCompleteItemLoader { await loader.load($0) }
        controller.updateListState(.success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)), isFiltered: false)
        controller.smokeSetPresentationAnimationTimelinePaused(true)
        controller.show()
        PanelQAHarness.drainMainRunLoop()
        PanelQAHarness.sendSpace(to: view)
        let detailTask = try #require(view.smokeDetailLoadTask)
        await loader.waitUntilPending()

        let result: Result<RustCoreListResult, RustCoreError> = update == "failure"
            ? .failure(RustCoreError(code: "test_failure", messageKey: "test_failure", recoverable: true, message: "test"))
            : .success(RustCoreListResult(items: update == "retained" ? [item] : [], totalCount: 1, hasMore: false))
        controller.updateListState(
            result,
            isFiltered: update == "background_scope",
            append: update == "append",
            scope: update == "background_scope" ? ClipboardListScope(normalizedSearch: "background") : .clipboard
        )

        #expect(controller.smokeHasActivePanelAnimation)
        #expect(controller.smokeHasDeferredListUpdate == (update != "append"))
        #expect(view.smokePendingDetailItemID == item.id)
        #expect(!detailTask.isCancelled)
        await loader.finish(item)
        await detailTask.value
        #expect(view.smokeIsPreviewShown)
        #expect(view.smokePreviewTextContent() == item.primaryText)
        #expect(view.smokePendingDetailItemID == item.id)
    }

    @Test
    @MainActor
    func detailsDisplayLoadedBodyAndReleaseItWhenClosed() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let controller = FloatingPanelController()
        defer { controller.hide() }
        let view = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: true)
        let loader = DeferredDetailLoader()
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.setCompleteItemLoader { await loader.load($0) }
        controller.show()
        controller.updateListState(.success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)), isFiltered: false)
        PanelQAHarness.drainMainRunLoop()
        PanelQAHarness.sendSpace(to: view)
        #expect(await waitForDetailCondition { await loader.isPending })
        #expect(!view.smokeIsPreviewShown)
        await loader.finish(item)
        #expect(await waitForDetailCondition { view.smokeIsPreviewShown })
        #expect(view.smokePreviewTextContent() == item.primaryText)
        view.closePreviewPopover()
        #expect(view.smokePendingDetailItemID == nil)
        #expect(view.smokePreviewTextContent().isEmpty)
    }

    @Test
    @MainActor
    func automaticCopyHideAndExplicitHideHaveDistinctCancellationSemantics() {
        let controller = FloatingPanelController()
        var causes: [Bool] = []
        controller.onWillHide = { causes.append($0) }
        controller.hideAfterCopyingSelection()
        controller.hide()
        #expect(causes == [true, false])
    }
}

private actor DeferredDetailLoader {
    private var continuation: CheckedContinuation<Result<[RustClipboardItemSummary], RustCoreError>, Never>?
    private var pendingWaiter: CheckedContinuation<Void, Never>?
    var isPending: Bool { continuation != nil }
    func load(_ ids: [String]) async -> Result<[RustClipboardItemSummary], RustCoreError> {
        await withCheckedContinuation {
            continuation = $0
            pendingWaiter?.resume()
            pendingWaiter = nil
        }
    }
    func waitUntilPending() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { pendingWaiter = $0 }
    }
    func finish(_ item: RustClipboardItemSummary) {
        continuation?.resume(returning: .success([item]))
        continuation = nil
    }
}

@MainActor
private func waitForDetailCondition(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}
