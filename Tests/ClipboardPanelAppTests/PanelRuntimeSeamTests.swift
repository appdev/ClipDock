import AppKit
import Foundation
import Testing
@testable import PasteFloatingDemo
@testable import ClipboardPanelApp

struct PanelRuntimeSeamTests {
    @Test
    @MainActor
    func floatingPanelControllerShowsFocusesAndHidesOnOutsideClick() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()

        #expect(await waitForMainActor {
            controller.isVisible && controller.smokeHasOutsideClickMonitoring
        })
        #expect(await waitForMainActor {
            controller.smokeFirstResponderIsContentView
        })

        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: true,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.midX, y: controller.smokePanelFrame.midY)
        )
        #expect(controller.isVisible)

        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
        )
        #expect(await waitForMainActor { !controller.isVisible && !controller.smokeHasOutsideClickMonitoring })
    }

    @Test
    @MainActor
    func clickingPreviewPopoverDoesNotHidePanel() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: false)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()
        contentView.layoutSubtreeIfNeeded()

        #expect(await waitForMainActor { controller.isVisible && contentView.smokeCurrentItemCount == 1 })
        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "预览"))
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        let previewFrame = try #require(controller.smokePreviewScreenFrame)
        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: previewFrame.midX, y: previewFrame.midY)
        )
        #expect(controller.isVisible)

        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + previewFrame.width + 80, y: controller.smokePanelFrame.maxY + previewFrame.height + 80)
        )
        #expect(await waitForMainActor { !controller.isVisible })
    }

    @Test
    @MainActor
    func appRuntimeIgnoresDuplicateShortcutToggleAndHidesOnDeactivate() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { delegate.smokePanelIsVisibleForRealFunctionQA })

        try? await Task.sleep(nanoseconds: 140_000_000)
        delegate.smokeTogglePanelForRealFunctionQA()
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { !delegate.smokePanelIsVisibleForRealFunctionQA })

        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)

        try? await Task.sleep(nanoseconds: 140_000_000)
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { delegate.smokePanelIsVisibleForRealFunctionQA })

        delegate.smokeResignActiveForRealFunctionQA()
        #expect(await waitForMainActor { !delegate.smokePanelIsVisibleForRealFunctionQA })
    }

    @Test
    @MainActor
    func loadMoreAppendKeepsExistingCardsAndClearsLoadingState() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let pagedItems = PanelQASamples.makePagedPanelItems(count: 75)
        let firstPage = Array(pagedItems.prefix(50))
        let secondPage = Array(pagedItems.dropFirst(50))
        var loadMoreRequestCount = 0

        controller.onRuntimeAction = { action in
            if case .loadMore = action {
                loadMoreRequestCount += 1
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(
                items: firstPage,
                totalCount: Int64(pagedItems.count),
                hasMore: true
            )),
            isFiltered: false
        )

        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == 50 })
        let firstCardBeforeAppend = try #require(contentView.smokeCardBoxes().first)

        contentView.smokeScrollToLoadMoreThreshold()

        #expect(await waitForMainActor {
            loadMoreRequestCount == 1 && contentView.smokeIsLoadingMoreActive
        })

        contentView.updateListState(
            .success(RustCoreListResult(
                items: secondPage,
                totalCount: Int64(pagedItems.count),
                hasMore: false
            )),
            isFiltered: false,
            append: true
        )

        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == 75
                && !contentView.smokeIsLoadingMoreActive
        })
        #expect(contentView.smokeCardBoxes().first === firstCardBeforeAppend)
        controller.hide()
    }

    @Test
    @MainActor
    func prefetchedLoadMoreAppendsImmediatelyWithoutEnteringLoadingState() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let pagedItems = PanelQASamples.makePagedPanelItems(count: 75)
        let firstPage = Array(pagedItems.prefix(50))
        let secondPage = Array(pagedItems.dropFirst(50))
        let delegate = AppDelegate()
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        delegate.smokePreparePrefetchedLoadMore(
            appSupportURL: appSupportURL,
            firstPage: firstPage,
            prefetchedPage: secondPage,
            totalCount: Int64(pagedItems.count)
        )
        delegate.smokeConsumeLoadMore()

        #expect(await waitForMainActor {
            delegate.smokeLoadedClipboardItemCount == 75
                && delegate.smokePanelItemCount == 75
                && !delegate.smokeIsLoadingMoreClipboardItems
        })
    }
}

@MainActor
private func waitForMainActor(
    attempts: Int = 80,
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() {
            return true
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}
