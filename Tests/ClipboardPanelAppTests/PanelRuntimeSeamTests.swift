import AppKit
import Foundation
import Testing
@testable import PasteFloating
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
    func floatingPanelControllerUsesBottomEdgeAnimationGeometry() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()

        #expect(await waitForMainActor { controller.isVisible })
        #expect(controller.smokePanelAlphaValue == 1)
        let shownFrame = controller.smokePanelFrame
        let entranceFrame = controller.smokeEntranceAnimationFrame
        let hiddenFrame = controller.smokeHiddenAnimationFrame

        #expect(entranceFrame.minY < shownFrame.minY)
        #expect(entranceFrame.maxY < shownFrame.minY)
        #expect(entranceFrame.width == shownFrame.width)
        #expect(entranceFrame.height == shownFrame.height)
        #expect(hiddenFrame.minY < shownFrame.minY)
        #expect(hiddenFrame.maxY < shownFrame.minY)
        #expect(hiddenFrame.width == shownFrame.width)
        #expect(hiddenFrame.height == shownFrame.height)

        controller.hide()
        #expect(!controller.isVisible)
        #expect(controller.smokePanelAlphaValue == 1)
    }

    @Test
    @MainActor
    func floatingPanelControllerSurvivesRapidHideShowToggleDuringAnimation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()
        try? await Task.sleep(nanoseconds: 40_000_000)

        controller.hide()
        try? await Task.sleep(nanoseconds: 40_000_000)

        controller.show()
        try? await Task.sleep(nanoseconds: 260_000_000)

        #expect(controller.isVisible)
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(!controller.smokeHasActivePanelAnimation)
        #expect(controller.smokeHasOutsideClickMonitoring)
        #expect(controller.smokePanelAlphaValue == 1)
    }

    @Test
    @MainActor
    func hidingPanelRestoresPreviouslyFocusedApplication() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let previousApplication = StubFocusApplication(
            processIdentifier: 42_001,
            bundleIdentifier: "com.example.editor"
        )
        let provider = StubFocusApplicationProvider(frontmostApplication: previousApplication)
        let controller = FloatingPanelController(
            focusApplicationProvider: provider,
            mainBundleIdentifier: "com.example.paste"
        )

        controller.show()
        provider.frontmostApplication = StubFocusApplication(
            processIdentifier: 42_002,
            bundleIdentifier: "com.example.browser"
        )

        controller.hide()

        #expect(!controller.isVisible)
        #expect(previousApplication.activateCount == 1)
        #expect(provider.frontmostApplication?.activateCount == 0)
    }

    @Test
    @MainActor
    func outsideClickHideDoesNotStealFocusBackFromClickedApplication() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let previousApplication = StubFocusApplication(
            processIdentifier: 42_101,
            bundleIdentifier: "com.example.editor"
        )
        let controller = FloatingPanelController(
            focusApplicationProvider: StubFocusApplicationProvider(frontmostApplication: previousApplication),
            mainBundleIdentifier: "com.example.paste"
        )

        controller.show()
        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
        )

        #expect(!controller.isVisible)
        #expect(previousApplication.activateCount == 0)
    }

    @Test
    @MainActor
    func appOwnedDialogClickDoesNotHidePanel() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()
        #expect(await waitForMainActor { controller.isVisible })

        controller.smokeHandleAppOwnedNonPanelMouseDown(
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
        )

        #expect(controller.isVisible)
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
    func spacePreviewCanReopenAfterPopoverSpaceClosesIt() async throws {
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

        #expect(await waitForMainActor { controller.isVisible && contentView.smokeCurrentItemCount == 1 })
        #expect(controller.smokeFirstResponderIsContentView)

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })
        #expect(controller.smokeFirstResponderIsContentView)

        #expect(contentView.smokeClosePreviewWithSpaceFromPopoverFocus())
        PanelQAHarness.drainMainRunLoop()
        #expect(!contentView.smokeIsPreviewShown)
        #expect(controller.smokeFirstResponderIsContentView)

        #expect(controller.smokeSendSpaceToFirstResponder())
        PanelQAHarness.drainMainRunLoop()
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        controller.hide()
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
    func appRuntimeAcceptsFastIntentionalHideShowToggles() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { delegate.smokePanelIsVisibleForRealFunctionQA })

        try? await Task.sleep(nanoseconds: 60_000_000)
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { !delegate.smokePanelIsVisibleForRealFunctionQA })

        try? await Task.sleep(nanoseconds: 60_000_000)
        delegate.smokeTogglePanelForRealFunctionQA()
        try? await Task.sleep(nanoseconds: 260_000_000)

        #expect(delegate.smokePanelIsVisibleForRealFunctionQA)
        #expect(delegate.smokePanelControllerForRealFunctionQA.smokePanelIsActuallyVisible)
        #expect(!delegate.smokePanelControllerForRealFunctionQA.smokeHasActivePanelAnimation)
    }

    @Test
    @MainActor
    func appRuntimeKeepsPanelHiddenForDefaultInitialPresentation() async throws {
        let delegate = AppDelegate()

        delegate.smokeApplyInitialPresentationForRealFunctionQA(arguments: ["PasteFloating"])

        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
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
    func pinboardChipSwitchRestoresCachedClipboardPageWithoutRebuildingCards() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let clipboardItems = PanelQASamples.makePagedPanelItems(count: 75)
        let pinboardItems = [clipboardItems[3]]
        var queries: [(pinboardID: String?, debounce: Bool)] = []

        controller.onRuntimeAction = { action in
            if case .queryChanged(_, _, let pinboardID, let debounce) = action {
                queries.append((pinboardID, debounce))
                if pinboardID == "board-a" {
                    controller.updateListState(
                        .success(RustCoreListResult(
                            items: pinboardItems,
                            totalCount: Int64(pinboardItems.count),
                            hasMore: false
                        )),
                        isFiltered: true,
                        scope: ClipboardListScope(pinboardID: "board-a")
                    )
                }
            }
        }

        controller.show()
        controller.updatePinboards([
            RustPinboardSummary(
                id: "board-a",
                title: "Board A",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])
        controller.updateListState(
            .success(RustCoreListResult(
                items: clipboardItems,
                totalCount: Int64(clipboardItems.count),
                hasMore: false
            )),
            isFiltered: false,
            scope: .clipboard
        )

        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == clipboardItems.count })
        let firstClipboardCard = try #require(contentView.smokeCardBoxes().first)
        contentView.smokeScrollToX(640)
        let savedScrollX = contentView.smokeScrollOriginX
        #expect(savedScrollX > 0)

        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == pinboardItems.count })

        contentView.smokePinboardFilterButton(pinboardID: nil)?.onPress?()
        #expect(contentView.smokeCurrentItemCount == clipboardItems.count)
        #expect(contentView.smokeCardBoxes().first === firstClipboardCard)
        #expect(abs(contentView.smokeScrollOriginX - savedScrollX) < 1)
        #expect(queries.map(\.debounce) == [false, false])

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

@MainActor
private final class StubFocusApplication: PanelFocusApplication {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    var isTerminated = false
    private(set) var activateCount = 0

    init(processIdentifier: pid_t, bundleIdentifier: String?) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
    }

    func activateForPanelFocusRestore() -> Bool {
        activateCount += 1
        return true
    }
}

@MainActor
private final class StubFocusApplicationProvider: PanelFocusApplicationProviding {
    var frontmostApplication: StubFocusApplication?

    init(frontmostApplication: StubFocusApplication?) {
        self.frontmostApplication = frontmostApplication
    }

    func frontmostPanelFocusApplication() -> PanelFocusApplication? {
        frontmostApplication
    }
}
