import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
import WebKit
@testable import ClipShelf
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
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(controller.smokeContentView.smokePanelUsesWindowLocalBackdropBlend())
        let backgroundAlphaBeforeHide = controller.smokePanelContentBackgroundAlpha

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
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(controller.smokeHasActivePanelAnimation)
        #expect(abs(controller.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(abs(controller.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)
    }

    @Test
    @MainActor
    func searchResultCopyKeepsSearchActive() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, pinboardID: String?, debounce: Bool)] = []
        var copiedItemID: String?
        let item = PanelQASamples.makePagedPanelItems(count: 1)[0]
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, let pinboardID, let debounce) = action {
                queries.append((searchText, pinboardID, debounce))
            }
            if case .copyItem(let item) = action {
                copiedItemID = item.id
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeOpenSearch(text: "report")
        #expect(contentView.smokeIsSearchVisible)
        #expect(contentView.smokeSearchText == "report")

        let card = try #require(contentView.smokeCardBoxes().first)
        PanelQAHarness.sendMouseDown(to: card, clickCount: 2)

        #expect(copiedItemID == item.id)
        #expect(contentView.smokeIsSearchVisible)
        #expect(contentView.smokeSearchText == "report")
        #expect(!queries.contains { $0.searchText.isEmpty })
        #expect(queries.last?.searchText == "report")
        #expect(queries.last?.pinboardID == nil)
        #expect(queries.last?.debounce == true)

        controller.hide()
    }

    @Test
    func typeToSearchKeyPlannerAllowsShiftAndRejectsShortcutOrNonPrintableKeys() {
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: "A",
            charactersIgnoringModifiers: "a",
            modifierFlags: [.shift]
        ) == "A")
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifierFlags: [.command]
        ) == nil)
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: " ",
            charactersIgnoringModifiers: " ",
            modifierFlags: []
        ) == nil)
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifierFlags: []
        ) == nil)
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: "ab",
            charactersIgnoringModifiers: "ab",
            modifierFlags: []
        ) == nil)
    }

    @Test
    @MainActor
    func printableKeyStartsSearchFocusesFieldAndEmitsDebouncedQuery() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, debounce: Bool)] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, let debounce) = action {
                queries.append((searchText, debounce))
            }
        }

        controller.show()
        #expect(await waitForMainActor {
            controller.smokeFirstResponderIsContentView
        })

        PanelQAHarness.sendPrintable(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.shift],
            keyCode: UInt16(kVK_ANSI_R),
            to: contentView
        )

        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText == "R"
                && contentView.smokeFirstResponderIsSearchField
        })
        #expect(queries.count == 1)
        #expect(queries.first?.searchText == "R")
        #expect(queries.first?.debounce == true)
        #expect(await waitForMainActor(attempts: 120) {
            abs(contentView.smokeSearchFieldWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldInnerWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldHeight - 48) < 0.5
                && abs(contentView.smokeSearchFieldAlpha - 1) < 0.01
                && !contentView.smokeSearchFieldIsHidden
                && contentView.smokeToolbarSearchButtonIsHidden
        })

        controller.hide()
    }

    @Test
    @MainActor
    func printableKeyDoesNotStealInputFromFocusedSearchField() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [String] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, _) = action {
                queries.append(searchText)
            }
        }

        controller.show()
        contentView.smokeOpenSearch(text: "report")
        #expect(await waitForMainActor {
            contentView.smokeFirstResponderIsSearchField
                && contentView.smokeSearchText == "report"
        })
        let queryCount = queries.count

        PanelQAHarness.sendPrintable(characters: "x", to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeSearchText == "report")
        #expect(queries.count == queryCount)

        controller.hide()
    }

    @Test
    @MainActor
    func searchFieldCancelOperationUsesEscapePolicy() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, debounce: Bool)] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, let debounce) = action {
                queries.append((searchText, debounce))
            }
        }

        controller.show()
        contentView.smokeOpenSearch(text: "report")
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible && contentView.smokeSearchText == "report"
        })

        #expect(contentView.smokeCancelSearchOperation())
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible && contentView.smokeSearchText.isEmpty
        })
        #expect(queries.last?.searchText == "")
        #expect(queries.last?.debounce == false)
        let queryCountAfterClear = queries.count

        #expect(contentView.smokeCancelSearchOperation())
        #expect(await waitForMainActor(attempts: 120) {
            !contentView.smokeIsSearchVisible
                && contentView.smokeSearchFieldIsHidden
                && abs(contentView.smokeSearchFieldWidth) < 0.5
                && abs(contentView.smokeSearchFieldAlpha) < 0.01
                && controller.smokeFirstResponderIsContentView
        })
        #expect(queries.count == queryCountAfterClear)

        controller.hide()
    }

    @Test
    @MainActor
    func nativeSearchCancelTextChangeBeforeActionEmitsOneImmediateClearQuery() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, debounce: Bool)] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, let debounce) = action {
                queries.append((searchText, debounce))
            }
        }

        controller.show()
        contentView.smokeOpenSearch(text: "report")
        let queryCountBeforeCancel = queries.count

        #expect(contentView.smokeNativeSearchCancelTextChangeBeforeAction())
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText.isEmpty
                && contentView.smokeFirstResponderIsSearchField
        })
        let cancelQueries = Array(queries.dropFirst(queryCountBeforeCancel))
        #expect(cancelQueries.count == 1)
        #expect(cancelQueries.first?.searchText == "")
        #expect(cancelQueries.first?.debounce == false)
        #expect(!cancelQueries.contains { $0.debounce })

        controller.hide()
    }

    @Test
    @MainActor
    func nativeSearchCancelActionBeforeTextChangeEmitsOneImmediateClearQuery() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, debounce: Bool)] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, let debounce) = action {
                queries.append((searchText, debounce))
            }
        }

        controller.show()
        contentView.smokeOpenSearch(text: "report")
        let queryCountBeforeCancel = queries.count

        #expect(contentView.smokeNativeSearchCancelActionBeforeTextChange())
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText.isEmpty
                && contentView.smokeFirstResponderIsSearchField
        })
        let cancelQueries = Array(queries.dropFirst(queryCountBeforeCancel))
        #expect(cancelQueries.count == 1)
        #expect(cancelQueries.first?.searchText == "")
        #expect(cancelQueries.first?.debounce == false)
        #expect(!cancelQueries.contains { $0.debounce })

        controller.hide()
    }

    @Test
    @MainActor
    func emptySearchClickAwayOnCardAndChipClosesSearchWithoutConsumingClick() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 2))
        var pinboardQueries: [String?] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(_, _, _, let pinboardID, _) = action {
                pinboardQueries.append(pinboardID)
            }
        }

        controller.show()
        controller.updatePinboards([
            RustPinboardSummary(
                id: "default",
                title: "固定",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        contentView.smokeOpenSearch(text: "")
        #expect(contentView.smokeIsSearchVisible)
        contentView.smokeClickCardWithSearchClickAway(itemID: items[1].id)
        #expect(await waitForMainActor {
            !contentView.smokeIsSearchVisible && contentView.smokeSelectedItemID == items[1].id
        })

        contentView.smokeOpenSearch(text: "")
        #expect(contentView.smokeIsSearchVisible)
        contentView.smokeClickPinboardFilterWithSearchClickAway(pinboardID: "default")
        #expect(await waitForMainActor {
            !contentView.smokeIsSearchVisible && pinboardQueries.last == "default"
        })

        controller.hide()
    }

    @Test
    @MainActor
    func nonEmptySearchClickAwayPreservesSearchWhileOriginalClickContinues() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 2))

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeOpenSearch(text: "report")

        contentView.smokeClickCardWithSearchClickAway(itemID: items[1].id)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsSearchVisible)
        #expect(contentView.smokeSearchText == "report")
        #expect(contentView.smokeSelectedItemID == items[1].id)

        controller.hide()
    }

    @Test
    @MainActor
    func menuTrackingDefersEmptySearchClickAwayAndRechecksBeforeClosing() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView

        controller.show()
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeOpenSearch(text: "")
        let closingMenu = contentView.smokeMenuTrackingDefersEmptySearchClickAway(makeSearchNonEmptyBeforeExit: false)

        #expect(closingMenu.pendingDuringTracking)
        #expect(closingMenu.searchVisibleDuringTracking)
        #expect(await waitForMainActor {
            !contentView.smokeIsSearchVisible && controller.smokeFirstResponderIsContentView
        })

        contentView.smokeOpenSearch(text: "")
        let preservedMenu = contentView.smokeMenuTrackingDefersEmptySearchClickAway(makeSearchNonEmptyBeforeExit: true)

        #expect(preservedMenu.pendingDuringTracking)
        #expect(preservedMenu.searchVisibleDuringTracking)
        PanelQAHarness.drainMainRunLoop()
        #expect(contentView.smokeIsSearchVisible)
        #expect(contentView.smokeSearchText == "menu")

        controller.hide()
    }

    @Test
    @MainActor
    func searchFieldHideAnimationIgnoresStaleCompletionAfterReopen() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView

        controller.show()
        contentView.smokeOpenSearch(text: "")
        #expect(await waitForMainActor(attempts: 120) {
            contentView.smokeIsSearchVisible
                && abs(contentView.smokeSearchFieldWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldInnerWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldAlpha - 1) < 0.01
        })

        PanelQAHarness.sendEscape(to: contentView)
        contentView.smokeOpenSearch(text: "z")

        #expect(await waitForMainActor(attempts: 160) {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText == "z"
                && !contentView.smokeSearchFieldIsHidden
                && abs(contentView.smokeSearchFieldWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldInnerWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldAlpha - 1) < 0.01
        })

        controller.hide()
    }

    @Test
    @MainActor
    func panelKeyboardShortcutsCopyAndDeleteSelectedItem() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 2))
        var copiedItemID: String?
        var deletedItemID: String?
        controller.onRuntimeAction = { action in
            switch action {
            case .copyItem(let item):
                copiedItemID = item.id
            case .deleteItem(let item, _):
                deletedItemID = item.id
            default:
                break
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        #expect(contentView.smokeSelectedItemID == items[0].id)
        PanelQAHarness.sendCommandC(to: contentView)
        #expect(copiedItemID == items[0].id)

        PanelQAHarness.sendArrow(.right, to: contentView)
        #expect(contentView.smokeSelectedItemID == items[1].id)
        PanelQAHarness.sendDelete(to: contentView)
        #expect(deletedItemID == items[1].id)

        controller.hide()
    }

    @Test
    @MainActor
    func emptyListStatesRenderNoStatusCards() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let sampleItems = Array(PanelQASamples.makePagedPanelItems(count: 1))

        controller.show()
        controller.updateStorageState(.success(RustCoreOpenResult(
            databasePath: "/tmp/empty-history.sqlite",
            schemaVersion: 1,
            itemCount: 0,
            items: []
        )))

        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == 0 && contentView.smokeCardBoxes().isEmpty
        })

        controller.updateStorageState(.success(RustCoreOpenResult(
            databasePath: "/tmp/non-empty-history.sqlite",
            schemaVersion: 1,
            itemCount: 1,
            items: sampleItems
        )))
        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == 1 && contentView.smokeCardBoxes().count == 1
        })

        controller.updateListState(
            .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false)),
            isFiltered: true
        )
        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == 0 && contentView.smokeCardBoxes().isEmpty
        })

        controller.hide()
    }

    @Test
    @MainActor
    func reloadWithSameItemsReusesRenderedCardViews() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let sampleItems = Array(PanelQASamples.makePagedPanelItems(count: 4))
        let result = RustCoreListResult(
            items: sampleItems,
            totalCount: Int64(sampleItems.count),
            hasMore: false
        )

        controller.show()
        contentView.updateListState(.success(result), isFiltered: false)

        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == sampleItems.count
                && contentView.smokeCardBoxes().count == sampleItems.count
        })
        let firstRenderIdentifiers = contentView.smokeCardBoxObjectIdentifiers()

        contentView.updateListState(.success(result), isFiltered: false)

        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == sampleItems.count
                && contentView.smokeCardBoxes().count == sampleItems.count
        })
        #expect(contentView.smokeCardBoxObjectIdentifiers() == firstRenderIdentifiers)

        controller.hide()
    }

    @Test
    @MainActor
    func reconcileReordersInsertsDeletesAndReplacesChangedCardsWithoutStaleTracking() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 4))

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == items.map(\.id) })

        let inserted = makeRuntimeTextItem(id: "runtime-reconcile-inserted", summary: "Inserted")
        let changed = runtimeLinkItemByUpdatingMetadata(items[1], title: "Changed title")
        let nextItems = [items[2], inserted, changed]

        contentView.updateListState(
            .success(RustCoreListResult(items: nextItems, totalCount: Int64(nextItems.count), hasMore: false)),
            isFiltered: false
        )

        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == nextItems.map(\.id) })
        #expect(contentView.smokeRenderedCardTrackingIsConsistent)
        #expect(contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound)

        controller.hide()
    }

    @Test
    @MainActor
    func reconcilePreservesAndClampsScrollAndKeepsPreviewOnlyForRemainingItem() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 18)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == items.count })

        contentView.smokeScrollToX(720)
        let scrolledX = contentView.smokeScrollOriginX
        #expect(scrolledX > 0)
        contentView.smokeSelectItem(id: items[6].id, scrollIntoView: true)
        #expect(await waitForMainActor { contentView.smokeCardBoxes().contains { $0.itemID == items[6].id } })
        #expect(contentView.smokePerformManagementAction(itemID: items[6].id, title: "预览"))
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        let remainingWithPreview = Array(items[3...9])
        contentView.updateListState(
            .success(RustCoreListResult(
                items: remainingWithPreview,
                totalCount: Int64(remainingWithPreview.count),
                hasMore: false
            )),
            isFiltered: false
        )
        #expect(!contentView.smokeIsPreviewShown)
        #expect(contentView.smokeScrollOriginX <= scrolledX)
        #expect(contentView.smokeRenderedCardTrackingIsConsistent)

        let withoutPreviewedItem = Array(items[10...12])
        contentView.updateListState(
            .success(RustCoreListResult(
                items: withoutPreviewedItem,
                totalCount: Int64(withoutPreviewedItem.count),
                hasMore: false
            )),
            isFiltered: false
        )
        #expect(!contentView.smokeIsPreviewShown)
        #expect(contentView.smokeSelectedItemID == withoutPreviewedItem.first?.id)

        controller.hide()
    }

    @Test
    @MainActor
    func scrollEdgeOverlaysStayRemovedWhileScrolling() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        contentView.updateListState(
            .success(RustCoreListResult(items: [PanelQASamples.makePagedPanelItems(count: 1)[0]], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        #expect(scrollView.horizontalScrollElasticity == .none)
        var overlayState = contentView.smokeScrollEdgeOverlayState
        #expect(!overlayState.leadingVisible)
        #expect(!overlayState.trailingVisible)
        #expect(overlayState.leadingHitTestNil)
        #expect(overlayState.trailingHitTestNil)

        let items = PanelQASamples.makePagedPanelItems(count: 18)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        overlayState = contentView.smokeScrollEdgeOverlayState
        #expect(!overlayState.leadingVisible)
        #expect(!overlayState.trailingVisible)

        contentView.smokeScrollToX(.greatestFiniteMagnitude)
        overlayState = contentView.smokeScrollEdgeOverlayState
        #expect(contentView.smokeScrollOriginX > 0)
        #expect(!overlayState.leadingVisible)
        #expect(!overlayState.trailingVisible)
        #expect(overlayState.leadingHitTestNil)
        #expect(overlayState.trailingHitTestNil)
    }

    @Test
    @MainActor
    func itemBandUsesCollectionViewReusableSurface() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 12)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        #expect(scrollView.documentView is NSCollectionView)
        #expect(!scrollView.hasHorizontalScroller)
        #expect(!scrollView.hasVerticalScroller)
        #expect(scrollView.horizontalScroller == nil)
        #expect(scrollView.verticalScroller == nil)
        #expect(contentView.smokeOrderedCardItemIDs() == items.map(\.id))
    }

    @Test
    @MainActor
    func itemBandUsesTransparentSpacersForHorizontalContentPadding() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 8)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let metrics = contentView.smokeItemBandLayoutMetrics
        let smallestBandVerticalInset = min(abs(metrics.verticalEdgeInsets.0), abs(metrics.verticalEdgeInsets.1))
        let largestBandVerticalInset = max(metrics.verticalEdgeInsets.0, metrics.verticalEdgeInsets.1)

        #expect(abs(metrics.leadingInset) < 0.5)
        #expect(abs(metrics.trailingInset) < 0.5)
        #expect(abs(smallestBandVerticalInset - 22) < 0.5)
        #expect(abs(largestBandVerticalInset - 64) < 0.5)
        #expect(abs(metrics.scrollOriginX) < 0.5)
        #expect(abs((metrics.firstCardVisibleMinX ?? -1) - 22) < 0.5)
        #expect(abs((metrics.firstCardDocumentMinX ?? -1) - 22) < 0.5)
        #expect(abs((metrics.lastCardDocumentTrailingInset ?? -1) - 22) < 0.5)

        contentView.smokeScrollToX(0)
        let leadingEdgeMetrics = contentView.smokeItemBandLayoutMetrics
        #expect(abs(leadingEdgeMetrics.scrollOriginX) < 0.5)
        #expect(abs((leadingEdgeMetrics.firstCardVisibleMinX ?? -1) - 22) < 0.5)

        contentView.smokeScrollToX(.greatestFiniteMagnitude)
        let trailingEdgeMetrics = contentView.smokeItemBandLayoutMetrics
        #expect(abs((trailingEdgeMetrics.lastCardVisibleMaxXAtTrailingEdge ?? -1) - (trailingEdgeMetrics.viewportWidth - 22)) < 0.5)
        #expect(abs(trailingEdgeMetrics.scrollOriginX - (try #require(metrics.trailingContentEdgeOriginX))) < 0.5)
    }

    @Test
    @MainActor
    func itemBandWheelScrollIgnoresBoundaryOverscroll() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 12)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        let documentView = try #require(scrollView.documentView)
        let maxX = max(CGFloat(0), documentView.frame.width - scrollView.contentView.bounds.width)
        #expect(maxX > 0)

        var callbackCount = 0
        scrollView.onScrollDidChange = {
            callbackCount += 1
        }

        sendWheel(to: scrollView, deltaX: 0, deltaY: -180)
        PanelQAHarness.drainMainRunLoop()
        #expect(scrollView.contentView.bounds.origin.x > 0)
        #expect(callbackCount >= 1)

        callbackCount = 0
        scrollView.contentView.scroll(to: NSPoint(x: maxX, y: scrollView.contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        PanelQAHarness.drainMainRunLoop()
        callbackCount = 0
        for _ in 0..<5 {
            sendWheel(to: scrollView, deltaX: 0, deltaY: -180)
        }
        PanelQAHarness.drainMainRunLoop()
        #expect(abs(scrollView.contentView.bounds.origin.x - maxX) < 0.5)
        #expect(callbackCount == 0)

        callbackCount = 0
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        PanelQAHarness.drainMainRunLoop()
        callbackCount = 0
        for _ in 0..<5 {
            sendWheel(to: scrollView, deltaX: 0, deltaY: 180)
        }
        PanelQAHarness.drainMainRunLoop()
        #expect(abs(scrollView.contentView.bounds.origin.x) < 0.5)
        #expect(callbackCount == 0)

        sendWheel(to: scrollView, deltaX: -180, deltaY: 0)
        PanelQAHarness.drainMainRunLoop()
        #expect(scrollView.contentView.bounds.origin.x > 0)
        #expect(callbackCount >= 1)
    }

    @Test
    @MainActor
    func itemBandWheelProjectionDoesNotAddSyntheticInertia() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 18)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        sendWheel(to: scrollView, deltaX: 0, deltaY: -120)
        let immediateX = scrollView.contentView.bounds.origin.x

        PanelQAHarness.drainMainRunLoop()
        let settledX = scrollView.contentView.bounds.origin.x

        #expect(immediateX > 0)
        #expect(abs(settledX - immediateX) < 0.5)
    }

    @Test
    @MainActor
    func itemBandLocksVerticalClipOrigin() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 18)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 12))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        PanelQAHarness.drainMainRunLoop()
        #expect(abs(scrollView.contentView.bounds.origin.y) < 0.5)

        sendWheel(to: scrollView, deltaX: -180, deltaY: 24)
        PanelQAHarness.drainMainRunLoop()
        #expect(scrollView.contentView.bounds.origin.x > 0)
        #expect(abs(scrollView.contentView.bounds.origin.y) < 0.5)
    }

    @Test
    @MainActor
    func cardClickSelectionDoesNotMoveHorizontalListVertically() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 12)
        controller.show()
        #expect(await waitForMainActor { controller.isVisible })

        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let clickedCard = try #require(contentView.smokeOrderedCardBoxes().first { $0.itemID == items[2].id })
        let clickedFrameBefore = clickedCard.convert(clickedCard.bounds, to: contentView)
        let scrollOriginBeforeClick = contentView.smokeScrollOrigin
        contentView.smokeClickCard(itemID: items[2].id)
        contentView.layoutSubtreeIfNeeded()
        let clickedFrameAfter = clickedCard.convert(clickedCard.bounds, to: contentView)
        #expect(contentView.smokeSelectedItemID == items[2].id)
        #expect(abs(clickedFrameAfter.minY - clickedFrameBefore.minY) < 0.5)
        #expect(abs(clickedFrameAfter.height - clickedFrameBefore.height) < 0.5)
        #expect(abs(contentView.smokeScrollOrigin.y - scrollOriginBeforeClick.y) < 0.5)

        contentView.smokeSelectItem(id: items[10].id, scrollIntoView: true)
        #expect(await waitForMainActor { contentView.smokeCardBoxes().contains { $0.itemID == items[10].id } })
        let farCard = try #require(contentView.smokeOrderedCardBoxes().first { $0.itemID == items[10].id })
        contentView.layoutSubtreeIfNeeded()
        let farFrameAfter = farCard.convert(farCard.bounds, to: contentView)
        #expect(contentView.smokeSelectedItemID == items[10].id)
        #expect(contentView.smokeScrollOrigin.x > 0)
        #expect(abs(farFrameAfter.minY - clickedFrameBefore.minY) < 0.5)
        #expect(abs(farFrameAfter.height - clickedFrameBefore.height) < 0.5)
        #expect(abs(contentView.smokeScrollOrigin.y - scrollOriginBeforeClick.y) < 0.5)

        controller.hide()
    }

    @Test
    func cardRenderPathDoesNotUseNetworkOrWebRenderingAPIs() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cardPathSources = [
            root.appendingPathComponent("Sources/ClipShelf/PanelItemCardRenderer.swift"),
            root.appendingPathComponent("Sources/ClipShelf/PanelCardSupport.swift")
        ]
        let forbiddenSymbols = [
            "URLSession",
            "LPMetadataProvider",
            "LPLinkView",
            "WKWebView",
            "import WebKit",
            "import LinkPresentation"
        ]
        let combinedSource = try cardPathSources
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for forbiddenSymbol in forbiddenSymbols {
            #expect(!combinedSource.contains(forbiddenSymbol))
        }
    }

    @Test
    @MainActor
    func panelOverflowMenuContainsOnlyHideAndPreferences() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        var didHidePanel = false
        var didShowPreferences = false
        contentView.onRuntimeAction = { action in
            switch action {
            case .hidePanel:
                didHidePanel = true
            case .showPreferences:
                didShowPreferences = true
            default:
                break
            }
        }

        let items = contentView.smokePanelOverflowMenuItems()

        #expect(items.map(\.title) == ["隐藏面板", "偏好设置"])
        #expect(items.allSatisfy { $0.isEnabled && !$0.hasSubmenu && !$0.hasCustomView })
        #expect(items.allSatisfy { $0.hasImage })
        #expect(contentView.smokeToolbarButtonToolTips().contains("更多功能"))
        #expect(contentView.smokePerformPanelOverflowAction(title: "隐藏面板"))
        #expect(didHidePanel)
        #expect(contentView.smokePerformPanelOverflowAction(title: "偏好设置"))
        #expect(didShowPreferences)
    }

    @Test
    @MainActor
    func managementMenuCopiesOriginalImagePathForImageItems() async throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadURL = appSupportURL
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("captured.heic")
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let item = makeRuntimeImageItem(
            id: "image-path-copy",
            previewAssetPath: "thumbnails/captured.heic",
            payloadAssetPath: "assets/captured.heic"
        )
        var copiedPathText: String?

        contentView.updateAppSupportDirectory(appSupportURL)
        contentView.onRuntimeAction = { action in
            if case .copyPath(let pathText) = action {
                copiedPathText = pathText
            }
        }
        contentView.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )

        let items = contentView.smokeManagementMenuItems(itemID: item.id)
        #expect(items.map(\.title) == ["复制", "复制路径", "删除", "固定", "预览"])
        #expect(items.allSatisfy { $0.hasImage })
        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "复制路径"))
        #expect(copiedPathText == payloadURL.standardizedFileURL.path)
    }

    @Test
    @MainActor
    func managementMenuCopiesOriginalImagePathsForImageFileItems() async throws {
        let firstImagePath = "/Users/evan/Pictures/first.png"
        let secondImagePath = "/Users/evan/Pictures/second.webp"
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let item = makeRuntimeImageFileItem(
            id: "file-image-path-copy",
            primaryText: "\(firstImagePath)\n/Users/evan/Documents/report.pdf\n\(secondImagePath)"
        )
        var copiedPathText: String?

        contentView.onRuntimeAction = { action in
            if case .copyPath(let pathText) = action {
                copiedPathText = pathText
            }
        }
        contentView.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )

        let items = contentView.smokeManagementMenuItems(itemID: item.id)
        #expect(items.map(\.title) == ["复制", "复制路径", "删除", "固定", "预览"])
        #expect(items.allSatisfy { $0.hasImage })
        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "复制路径"))
        #expect(copiedPathText == "\(firstImagePath)\n\(secondImagePath)")
    }

    @Test
    @MainActor
    func managementMenuHidesCopyPathForNonImageItems() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let item = makeRuntimeFileItem(
            id: "pdf-path-copy",
            primaryText: "/Users/evan/Documents/report.pdf"
        )

        contentView.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )

        let items = contentView.smokeManagementMenuItems(itemID: item.id)
        #expect(items.map(\.title) == ["复制", "删除", "固定", "预览"])
        #expect(items.allSatisfy { $0.hasImage })
        #expect(!contentView.smokePerformManagementAction(itemID: item.id, title: "复制路径"))
    }

    @Test
    @MainActor
    func showPreferencesHidesPanelAndClosesPreviewWhenNotBlocking() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        let controller = delegate.smokePanelControllerForRealFunctionQA
        let contentView = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: false)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        #expect(await waitForMainActor {
            delegate.smokePanelIsVisibleForRealFunctionQA && contentView.smokeCurrentItemCount == 1
        })
        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "预览"))
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        delegate.smokeShowPreferencesForRealFunctionQA()

        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
        #expect(!contentView.smokeIsPreviewShown)
    }

    @Test
    @MainActor
    func blockingPanelOperationPreservesPanelForImplicitHides() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        delegate.smokeTogglePanelForRealFunctionQA()
        let controller = delegate.smokePanelControllerForRealFunctionQA

        #expect(await waitForMainActor {
            delegate.smokePanelIsVisibleForRealFunctionQA && !controller.smokeHasActivePanelAnimation
        })

        controller.smokeWithBlockingPanelOperation {
            delegate.smokeShowPreferencesForRealFunctionQA()
            #expect(delegate.smokePanelIsVisibleForRealFunctionQA)

            delegate.smokeResignActiveForRealFunctionQA()
            #expect(delegate.smokePanelIsVisibleForRealFunctionQA)

            controller.smokeHandleOutsideMouseDown(
                eventWindowIsPanel: false,
                mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
            )
            #expect(controller.isVisible)
        }

        #expect(controller.isVisible)
        delegate.smokeResignActiveForRealFunctionQA()
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
    }

    @Test
    @MainActor
    func blockingPanelOperationDoesNotBlockExplicitHide() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()
        #expect(await waitForMainActor {
            controller.isVisible && !controller.smokeHasActivePanelAnimation
        })

        controller.smokeWithBlockingPanelOperation {
            controller.hide()
            #expect(!controller.isVisible)
        }

        #expect(!controller.isVisible)
    }

    @Test
    @MainActor
    func blockingPanelModalWrapperResetsAfterConfirmCancelAndNestedResponses() {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))

        let probe = contentView.smokeBlockingPanelModalProbe()

        #expect(probe.outerDuring)
        #expect(probe.nestedDuring)
        #expect(probe.afterNested)
        #expect(!probe.afterOuter)
        #expect(!contentView.smokeHasBlockingPanelOperation)
        #expect(probe.responses == [
            .alertSecondButtonReturn,
            .alertFirstButtonReturn,
            .alertSecondButtonReturn
        ])
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
    func manualPanelHeightResizePersistsAcrossControllerRecreation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let heightStore = InMemoryPanelHeightPreferenceStore()

        let firstController = FloatingPanelController(heightPreferenceStore: heightStore)
        firstController.setConfiguredDefaultHeight(BottomPanelGeometryPlanner.defaultHeight)
        firstController.show()
        #expect(await waitForMainActor(attempts: 240) {
            firstController.smokePanelIsActuallyVisible && !firstController.smokeHasActivePanelAnimation
        })

        firstController.smokeResizePanelHeight(deltaY: 96)
        let resizedHeight = firstController.smokePreferredHeight
        #expect(resizedHeight > BottomPanelGeometryPlanner.defaultHeight)
        #expect(abs((heightStore.preferredPanelHeight ?? 0) - resizedHeight) < 0.001)
        firstController.hide(restoresPreviousApplicationFocus: false)

        let secondController = FloatingPanelController(heightPreferenceStore: heightStore)
        secondController.setConfiguredDefaultHeight(BottomPanelGeometryPlanner.defaultHeight)
        secondController.show()
        #expect(await waitForMainActor(attempts: 240) {
            secondController.smokePanelIsActuallyVisible && !secondController.smokeHasActivePanelAnimation
        })

        #expect(abs(secondController.smokePanelFrame.height - resizedHeight) < 0.001)
        #expect(abs(secondController.smokePreferredHeight - resizedHeight) < 0.001)
        secondController.hide(restoresPreviousApplicationFocus: false)
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
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(controller.smokeContentView.smokePanelUsesWindowLocalBackdropBlend())
        let backgroundAlphaBeforeHide = controller.smokePanelContentBackgroundAlpha
        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
        )

        #expect(!controller.isVisible)
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(controller.smokeHasActivePanelAnimation)
        #expect(abs(controller.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)
        #expect(previousApplication.activateCount == 0)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(abs(controller.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)
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
    func singleWordTextPreviewUsesClipShelfMinimumWindow() {
        let content = makeTextPreviewContent(body: "Vault")

        let size = smokePreferredClipboardPreviewSize(for: content)

        #expect(abs(size.width - 390) < 1)
        #expect(abs(size.height - 316) < 1)
    }

    @Test
    @MainActor
    func textPreviewSizeUsesClipShelfMeasuredContent() {
        let content = makeTextPreviewContent(body: "短文本预览\nsecond line")

        let size = smokePreferredClipboardPreviewSize(for: content)
        let expectedSize = expectedClipShelfTextPreviewSize(for: content.body)

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func richTextPreviewSizeUsesClipShelfTextMetrics() {
        let content = makeTextPreviewContent(
            body: "富文本预览\nbold title\nregular body",
            itemType: "rich_text"
        )

        let size = smokePreferredClipboardPreviewSize(for: content)
        let expectedSize = expectedClipShelfTextPreviewSize(for: content.body)

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func longTextPreviewSizeUsesClipShelfMeasurementLimitAndHalfScreenCap() {
        let body = Array(
            repeating: "ClipShelf preview sizing should measure a bounded prefix and cap the viewport by half of the screen.",
            count: 80
        ).joined(separator: "\n")
        let content = makeTextPreviewContent(body: body)

        let size = smokePreferredClipboardPreviewSize(for: content)
        let expectedSize = expectedClipShelfTextPreviewSize(for: body)
        let maximumContentSize = expectedClipShelfTextMaximumContentSize()

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
        #expect(size.width <= floor(maximumContentSize.width + 10))
        #expect(size.height <= floor(maximumContentSize.height + 76))
    }

    @Test
    @MainActor
    func textPreviewFooterOmitsWordCount() async throws {
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

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        let previewLabels = contentView.smokePreviewLabelTexts().joined(separator: " ")
        #expect(previewLabels.contains("个字符"))
        #expect(previewLabels.contains("行"))
        #expect(!previewLabels.contains("单词"))

        controller.hide()
    }

    @Test
    @MainActor
    func textPreviewUsesOpaqueContentSurface() async throws {
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

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })
        let expectedBackground = ClipShelfTheme.current(for: contentView).panel.backgroundColor
        let actualBackground = try #require(contentView.smokePreviewRootBackgroundColor())
        #expect(colorAndAlphaDistance(actualBackground, expectedBackground) < 0.001)
        let directSubviewBackgrounds = contentView.smokePreviewDirectSubviewBackgroundColors()
        let expectedSurface = ClipShelfTheme.current(for: contentView)
            .preview
            .surfaceBackgroundColor
            .withAlphaComponent(1)
        #expect(directSubviewBackgrounds.contains { background in
            colorAndAlphaDistance(background, expectedSurface) < 0.001
        })
        #expect(directSubviewBackgrounds.filter { background in
            (background.usingColorSpace(.sRGB)?.alphaComponent ?? background.alphaComponent) < 0.001
        }.count >= 2)

        controller.hide()
    }

    @Test
    @MainActor
    func capturedFileFromStorageOpensQuickLookPreview() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("storage-preview.md")
        try Data("# Storage preview\n\nQuick Look should open this file.".utf8).write(to: fileURL)

        let client = RustCoreClient()
        _ = try client.captureFiles(
            appSupportDirectory: tempDirectory,
            request: RustCaptureFilesRequest(
                filePaths: [fileURL.path],
                snapshotRelativePath: nil,
                snapshotByteCount: 0,
                sourceBundleId: "com.apple.finder",
                sourceAppName: "Finder",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 32
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)
        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(item.fileItems.map(\.path) == [fileURL.path])
        #expect(preview.fileURLs == [fileURL.standardizedFileURL])

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(tempDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsPreviewShown)
        #expect(contentView.smokePreviewContainsQuickLookView())

        controller.hide()
    }

    @Test
    @MainActor
    func filePreviewUsesQuickLookViewAndKeepsKeyboardClose() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("quicklook-preview.txt")
        try Data("Quick Look file preview".utf8).write(to: fileURL)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(tempDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: [makeRuntimeFileItem(id: "quicklook-file", primaryText: fileURL.path)],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsPreviewShown)
        #expect(contentView.smokePreviewContainsQuickLookView())
        #expect(contentView.smokePreviewQuickLookAcceptsFirstResponder() == false)
        #expect(contentView.smokeClosePreviewWithSpaceFromPopoverFocus())
        PanelQAHarness.drainMainRunLoop()
        #expect(!contentView.smokeIsPreviewShown)

        controller.hide()
    }

    @Test
    @MainActor
    func imagePreviewSizeKeepsNaturalImageSizeWithClipShelfShellInsets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("natural-image-preview.png")
        try writePNG(to: imageURL, width: 220, height: 140)

        let size = smokePreferredClipboardPreviewSize(for: makeImagePreviewContent(imageURL: imageURL))
        let expectedSize = expectedClipShelfImagePreviewSize(imageWidth: 220, imageHeight: 140)

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func imagePreviewSizeDownscalesLargeImageToHalfScreenLikeClipShelf() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("large-image-preview.png")
        try writePNG(to: imageURL, width: 2000, height: 1000)

        let size = smokePreferredClipboardPreviewSize(for: makeImagePreviewContent(imageURL: imageURL))
        let expectedSize = expectedClipShelfImagePreviewSize(imageWidth: 2000, imageHeight: 1000)

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func imageFilePreviewSizeFollowsImageAspectRatio() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("wide-preview.png")
        try writePNG(to: imageURL, width: 1200, height: 600)

        let size = smokePreferredClipboardPreviewSize(for: makePreviewContent(fileURLs: [imageURL]))
        let contentWidth = size.width - 10
        let contentHeight = size.height - 76

        #expect(contentWidth >= 420)
        #expect(contentHeight >= 180)
        #expect(abs((contentWidth / contentHeight) - 2.0) < 0.08)
    }

    @Test
    @MainActor
    func imageFilePreviewSizePreservesTransparentPadding() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("transparent-padding-preview.png")
        try writeTransparentPNG(
            to: imageURL,
            width: 1200,
            height: 600,
            opaqueRect: NSRect(x: 500, y: 200, width: 200, height: 200)
        )

        let size = smokePreferredClipboardPreviewSize(for: makePreviewContent(fileURLs: [imageURL]))
        let contentWidth = size.width - 10
        let contentHeight = size.height - 76

        #expect(abs((contentWidth / contentHeight) - 2.0) < 0.08)
    }

    @Test
    @MainActor
    func imageCardPreviewFillsCardBelowHeader() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("card-fill-preview.png")
        try writePNG(to: imageURL, width: 1200, height: 600)

        let app = NSApplication.shared
        let theme = ClipShelfTheme.current(for: app.effectiveAppearance)
        let itemSide: CGFloat = 218
        let headerHeight: CGFloat = 48
        let renderer = PanelItemCardRenderer(
            cardAssetResolver: PanelCardAssetResolver(appSupportDirectory: tempDirectory),
            metrics: PanelItemCardRendererMetrics(
                defaultItemSide: itemSide,
                cardCornerRadius: 10,
                innerCornerRadius: 8,
                cardHeaderHeight: headerHeight,
                cardInset: 12,
                cardFooterHeight: 17,
                sourceIconSize: 54,
                linkPreviewHeight: 84,
                theme: theme
            ),
            backingScaleFactor: NSScreen.main?.backingScaleFactor ?? 2
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "image-card-fill",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "1200 × 600",
            isSelected: true,
            preview: .image(
                previewPath: imageURL.path,
                payloadPath: imageURL.path,
                summary: "图片 1200 x 600"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: imageURL.path,
                payloadAssetPath: imageURL.path
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let imageFrame = imageView.convert(imageView.bounds, to: renderedCard.view)

        #expect(renderedCard.artifacts.previewHeightConstraints.isEmpty)
        #expect(abs(imageFrame.width - itemSide) <= 1.5)
        #expect(abs(imageFrame.height - (itemSide - headerHeight)) <= 1.5)

        let resizedItemSide: CGFloat = 234
        host.setFrameSize(NSSize(width: resizedItemSide, height: resizedItemSide))
        renderedCard.artifacts.itemWidthConstraint.constant = resizedItemSide
        renderedCard.artifacts.itemHeightConstraint.constant = resizedItemSide
        host.layoutSubtreeIfNeeded()

        let resizedImageFrame = imageView.convert(imageView.bounds, to: renderedCard.view)
        #expect(abs(resizedImageFrame.width - resizedItemSide) <= 1.5)
        #expect(abs(resizedImageFrame.height - (resizedItemSide - headerHeight)) <= 1.5)
    }

    @Test
    @MainActor
    func imageCardPreviewUsesProportionallyDownScalingAndBadgesResolution() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let largeImageURL = tempDirectory.appendingPathComponent("large-proportional-preview.png")
        try writePNG(to: largeImageURL, width: 400, height: 200)
        let smallImageURL = tempDirectory.appendingPathComponent("small-proportional-preview.png")
        try writePNG(to: smallImageURL, width: 60, height: 40)

        let app = NSApplication.shared
        let theme = ClipShelfTheme.current(for: app.effectiveAppearance)
        let itemSide: CGFloat = 218
        let headerHeight: CGFloat = 48
        let renderer = PanelItemCardRenderer(
            cardAssetResolver: PanelCardAssetResolver(appSupportDirectory: tempDirectory),
            metrics: PanelItemCardRendererMetrics(
                defaultItemSide: itemSide,
                cardCornerRadius: 10,
                innerCornerRadius: 8,
                cardHeaderHeight: headerHeight,
                cardInset: 12,
                cardFooterHeight: 17,
                sourceIconSize: 54,
                linkPreviewHeight: 84,
                theme: theme
            ),
            backingScaleFactor: NSScreen.main?.backingScaleFactor ?? 2
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "image-card-proportional-down",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "400 × 200",
            isSelected: true,
            preview: .image(
                previewPath: largeImageURL.path,
                payloadPath: largeImageURL.path,
                summary: "图片 400 x 200"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: largeImageURL.path,
                payloadAssetPath: largeImageURL.path
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(await waitForMainActor(attempts: 240) { imageView.image != nil })

        let badgeView = try #require(renderedCard.artifacts.footnoteBadgeViews.first)
        let badgeBackground = try #require(badgeView.layer?.backgroundColor)
        let badgeBackgroundAlpha = NSColor(cgColor: badgeBackground)?.alphaComponent ?? 0
        #expect(!badgeView.isHidden)
        #expect(badgeBackgroundAlpha > (theme.scheme == .light ? 0.85 : 0.65))
        #expect((badgeView.layer?.cornerRadius ?? 0) >= 6)

        let smallRenderedCard = renderer.render(PanelItemCardViewState(
            itemID: "image-card-small-no-upscale",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "60 × 40",
            isSelected: true,
            preview: .image(
                previewPath: smallImageURL.path,
                payloadPath: smallImageURL.path,
                summary: "图片 60 x 40"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: smallImageURL.path,
                payloadAssetPath: smallImageURL.path
            )
        ))
        let smallHost = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        smallHost.addSubview(smallRenderedCard.view)
        NSLayoutConstraint.activate([
            smallRenderedCard.view.leadingAnchor.constraint(equalTo: smallHost.leadingAnchor),
            smallRenderedCard.view.topAnchor.constraint(equalTo: smallHost.topAnchor)
        ])
        smallHost.layoutSubtreeIfNeeded()

        let smallImageView = try #require(smallRenderedCard.artifacts.imagePreviewViews.first)
        #expect(smallImageView.imageScaling == .scaleProportionallyDown)
        #expect(await waitForMainActor(attempts: 240) { smallImageView.image != nil })
    }

    @Test
    @MainActor
    func removedImageCardCancelsPendingPreviewImageLoad() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let previewURL = tempDirectory.appendingPathComponent("delayed-card-preview.png")
        try writePNG(to: previewURL, width: 64, height: 64)

        PanelCardAssetResolver.previewImageLoadDelayForSmoke = .milliseconds(100)
        defer {
            PanelCardAssetResolver.previewImageLoadDelayForSmoke = nil
        }

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "cancel-image-card",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "64 × 64",
            isSelected: true,
            preview: .image(
                previewPath: previewURL.path,
                payloadPath: nil,
                summary: "图片 64 x 64"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: previewURL.path
            )
        ))

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let loadToken = try #require(renderedCard.artifacts.previewImageLoadTokensForSmoke().first)
        #expect(imageView.image == nil)
        #expect(PanelCardAssetResolver.previewImageLoadIsActiveForSmoke(loadToken))

        renderedCard.artifacts.prepareForRemoval()
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))

        #expect(!PanelCardAssetResolver.previewImageLoadIsActiveForSmoke(loadToken))
        #expect(imageView.image == nil)
    }

    @Test
    @MainActor
    func removedLinkCardCancelsPendingPreviewAndIconImageLoads() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let iconURL = tempDirectory.appendingPathComponent("delayed-link-icon.png")
        let imageURL = tempDirectory.appendingPathComponent("delayed-link-image.png")
        try writePNG(to: iconURL, width: 32, height: 32)
        try writePNG(to: imageURL, width: 96, height: 64)

        PanelCardAssetResolver.previewImageLoadDelayForSmoke = .milliseconds(100)
        defer {
            PanelCardAssetResolver.previewImageLoadDelayForSmoke = nil
        }

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            iconPath: iconURL.path,
            imagePath: imageURL.path
        )

        let backgroundImageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let iconView = try #require(renderedCard.artifacts.linkIconViews.first)
        let loadTokens = renderedCard.artifacts.previewImageLoadTokensForSmoke()
        #expect(backgroundImageView.image == nil)
        #expect(loadTokens.count == 2)
        #expect(loadTokens.allSatisfy { PanelCardAssetResolver.previewImageLoadIsActiveForSmoke($0) })

        renderedCard.artifacts.prepareForRemoval()
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))

        #expect(loadTokens.allSatisfy { !PanelCardAssetResolver.previewImageLoadIsActiveForSmoke($0) })
        #expect(backgroundImageView.image == nil)
        #expect(iconView.image != nil)
    }

    @Test
    @MainActor
    func removedFileCardCancelsPendingThumbnailRequest() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("thumbnail-source.txt")
        try "thumbnail smoke".write(to: fileURL, atomically: true, encoding: .utf8)

        PanelCardAssetResolver.fileThumbnailGenerationDelayForSmoke = .milliseconds(100)
        defer {
            PanelCardAssetResolver.fileThumbnailGenerationDelayForSmoke = nil
        }

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "cancel-file-card",
            sourceAppName: "Finder",
            relativeTimeText: "now",
            symbolName: "doc",
            typeText: "文件",
            summaryText: "",
            footnoteText: fileURL.lastPathComponent,
            isSelected: true,
            preview: .file(accessibilityLabel: "Finder"),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Finder",
                primaryText: fileURL.path
            )
        ))

        let thumbnailToken = try #require(renderedCard.artifacts.filePreviewThumbnailTokensForSmoke().first)
        #expect(PanelCardAssetResolver.filePreviewImageRequestIsActiveForSmoke(thumbnailToken))

        renderedCard.artifacts.prepareForRemoval()
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))

        #expect(!PanelCardAssetResolver.filePreviewImageRequestIsActiveForSmoke(thumbnailToken))
    }

    @Test
    @MainActor
    func filePreviewThumbnailCompletionReturnsToMainActor() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("quicklook-thumbnail-source.png")
        try writePNG(to: fileURL, width: 96, height: 64)

        var didComplete = false
        var completedOnMainThread = false
        let token = try #require(PanelCardAssetResolver.loadFilePreviewImageAsync(
            urls: [fileURL],
            maximumSize: NSSize(width: 96, height: 96),
            scale: NSScreen.main?.backingScaleFactor ?? 2
        ) { _ in
            didComplete = true
            completedOnMainThread = Thread.isMainThread
        })

        #expect(await waitForMainActor(attempts: 400) { didComplete })
        #expect(completedOnMainThread)
        #expect(!PanelCardAssetResolver.filePreviewImageRequestIsActiveForSmoke(token))
    }

    @Test
    @MainActor
    func imageCardRenderDoesNotLoadOriginalPayloadFallback() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let payloadURL = tempDirectory.appendingPathComponent("original-payload.png")
        try writePNG(to: payloadURL, width: 80, height: 80)
        let missingPreviewURL = tempDirectory.appendingPathComponent("missing-preview.png")

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "payload-fallback-image-card",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "80 × 80",
            isSelected: true,
            preview: .image(
                previewPath: missingPreviewURL.path,
                payloadPath: payloadURL.path,
                summary: "图片 80 x 80"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: missingPreviewURL.path,
                payloadAssetPath: payloadURL.path
            )
        ))

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        #expect(imageView.image == nil)
        #expect(renderedCard.artifacts.previewImageLoadTokensForSmoke().isEmpty)
    }

    @Test
    @MainActor
    func colorCardRenderUsesFullNativeSurfaceWithoutAsyncImageTokens() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let colorValue = try #require(ClipboardColorValue(normalizedHex: "#FF00AA"))

        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "color-card",
            sourceAppName: "Color Meter",
            relativeTimeText: "now",
            symbolName: "paintpalette",
            typeText: "颜色",
            summaryText: "#FF00AA",
            footnoteText: "",
            commandIndexText: "7",
            isSelected: true,
            preview: .color(colorValue),
            assetRequest: PanelCardAssetRequest(
                sourceAppId: "com.apple.DigitalColorMeter",
                sourceAppName: "Color Meter",
                sourceAppIconHeaderColor: 0xFF11_2233,
                previewAssetPath: "missing-preview.png",
                payloadAssetPath: "missing-payload.png",
                primaryText: "#FF00AA"
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let surface = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardSurface"
        })
        let hexLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardHexLabel"
        } as? NSTextField)
        let commandIndexLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardCommandIndexLabel"
        } as? NSTextField)
        let typeLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "PanelCardTypeLabel"
        } as? NSTextField)
        let timeLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "PanelCardTimeLabel"
        } as? NSTextField)
        let header = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "PanelCardHeader"
        })
        let surfaceColor = try #require(surface.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
        let headerColor = try #require(header.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
        let surfaceFrame = surface.convert(surface.bounds, to: renderedCard.view)

        #expect(typeLabel.stringValue == "颜色")
        #expect(timeLabel.stringValue == "now")
        #expect(colorAndAlphaDistance(
            headerColor,
            NSColor(srgbRed: CGFloat(0x11) / 255, green: CGFloat(0x22) / 255, blue: CGFloat(0x33) / 255, alpha: 0.96)
        ) < 0.001)
        #expect(surface.toolTip == "#FF00AA")
        #expect(surfaceFrame.width > 210)
        #expect(surfaceFrame.height > 165)
        #expect(abs(surfaceFrame.minY) < 0.5)
        #expect(colorAndAlphaDistance(surfaceColor, NSColor(srgbRed: 1, green: 0, blue: CGFloat(0xAA) / 255, alpha: 1)) < 0.001)
        #expect(hexLabel.stringValue == "#FF00AA")
        #expect(hexLabel.alignment == .center)
        #expect(colorAndAlphaDistance(hexLabel.textColor ?? .clear, .black) < 0.001)
        #expect(commandIndexLabel.stringValue == "7")
        #expect(!commandIndexLabel.isHidden)
        #expect(colorAndAlphaDistance(commandIndexLabel.textColor ?? .clear, .black) < 0.001)
        #expect(!renderedCard.view.subviewsRecursiveForSmoke().contains {
            ($0 as? NSTextField)?.stringValue == "RGB 255, 0, 170"
        })
        #expect(renderedCard.artifacts.imagePreviewViews.isEmpty)
        #expect(renderedCard.artifacts.previewImageLoadTokensForSmoke().isEmpty)
        #expect(renderedCard.artifacts.filePreviewThumbnailTokensForSmoke().isEmpty)
    }

    @Test
    @MainActor
    func colorCardSurfaceForegroundCoversLightDarkSaturatedAndMidGrayColors() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let cases: [(hex: String, foreground: NSColor)] = [
            ("#FDF6E3", .black),
            ("#000000", .white),
            ("#FFFFFF", .black),
            ("#FF00AA", .black),
            ("#777777", .black),
            ("#666666", .white)
        ]

        for testCase in cases {
            let colorValue = try #require(ClipboardColorValue(normalizedHex: testCase.hex))
            let renderedCard = renderer.render(PanelItemCardViewState(
                itemID: "color-card-\(testCase.hex)",
                sourceAppName: "Color Meter",
                relativeTimeText: "now",
                symbolName: "paintpalette",
                typeText: "颜色",
                summaryText: testCase.hex,
                footnoteText: "",
                isSelected: false,
                preview: .color(colorValue),
                assetRequest: PanelCardAssetRequest(primaryText: testCase.hex)
            ))
            let hexLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
                $0.identifier?.rawValue == "ColorCardHexLabel"
            } as? NSTextField)
            let commandIndexLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
                $0.identifier?.rawValue == "ColorCardCommandIndexLabel"
            } as? NSTextField)

            #expect(hexLabel.stringValue == testCase.hex)
            #expect(colorAndAlphaDistance(hexLabel.textColor ?? .clear, testCase.foreground) < 0.001)
            #expect(colorAndAlphaDistance(commandIndexLabel.textColor ?? .clear, testCase.foreground) < 0.001)
        }
    }

    @Test
    @MainActor
    func collectionCellReuseClearsColorStateWhenReconfiguredAsImage() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let metrics = PanelItemCollectionLayoutMetrics(
            itemSide: 218,
            itemSpacing: 22,
            horizontalContentInset: 22,
            imagePreviewMinHeight: 78,
            imagePreviewMaxHeight: 116,
            cardInset: 12
        )
        let cell = PanelItemCollectionCell()
        _ = cell.view
        let colorValue = try #require(ClipboardColorValue(normalizedHex: "#FF00AA"))

        cell.configure(
            entry: PanelItemCollectionEntry(
                id: "reuse-item",
                state: PanelItemCardViewState(
                    itemID: "reuse-item",
                    sourceAppName: "Color Meter",
                    relativeTimeText: "now",
                    symbolName: "paintpalette",
                    typeText: "颜色",
                    summaryText: "#FF00AA",
                    footnoteText: "",
                    commandIndexText: "8",
                    isSelected: false,
                    preview: .color(colorValue),
                    assetRequest: PanelCardAssetRequest(primaryText: "#FF00AA")
                ),
                callbacks: PanelItemCollectionCallbacks(toolTip: nil, onSelect: nil, onDoubleClick: nil, onContextMenu: nil)
            ),
            renderer: renderer,
            metrics: metrics
        )
        #expect(cell.hostedCard?.subviewsRecursiveForSmoke().contains {
            $0.identifier?.rawValue == "ColorCardSurface" && $0.toolTip == "#FF00AA"
        } == true)
        #expect((cell.hostedCard?.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardCommandIndexLabel"
        } as? NSTextField)?.stringValue == "8")

        cell.applyTransientDecorations(isSelected: false, commandIndexText: nil)
        #expect((cell.hostedCard?.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardCommandIndexLabel"
        } as? NSTextField)?.isHidden == true)

        cell.configure(
            entry: PanelItemCollectionEntry(
                id: "reuse-item",
                state: PanelItemCardViewState(
                    itemID: "reuse-item",
                    sourceAppName: "Preview",
                    relativeTimeText: "now",
                    symbolName: "photo",
                    typeText: "图片",
                    summaryText: "",
                    footnoteText: "120 × 80",
                    isSelected: false,
                    preview: .image(previewPath: nil, payloadPath: nil, summary: "图片 120 x 80"),
                    assetRequest: PanelCardAssetRequest(sourceAppName: "Preview")
                ),
                callbacks: PanelItemCollectionCallbacks(toolTip: nil, onSelect: nil, onDoubleClick: nil, onContextMenu: nil)
            ),
            renderer: renderer,
            metrics: metrics
        )

        #expect(cell.hostedCard?.subviewsRecursiveForSmoke().contains {
            $0.identifier?.rawValue == "ColorCardSurface" || $0.identifier?.rawValue == "ColorCardHexLabel"
        } == false)
        #expect(cell.hostedCard?.subviewsRecursiveForSmoke().contains { $0.toolTip == "#FF00AA" } == false)
    }

    @Test
    @MainActor
    func colorPreviewPopoverPreservesHexRgbHslAndHsbDetails() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let item = makeRuntimeColorItem(id: "preview-color", hex: "#FF00AA")
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "预览"))
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        let previewLabels = contentView.smokePreviewLabelTexts().joined(separator: " ")
        #expect(previewLabels.contains("HEX"))
        #expect(previewLabels.contains("#FF00AA"))
        #expect(previewLabels.contains("RGB"))
        #expect(previewLabels.contains("255, 0, 170"))
        #expect(previewLabels.contains("HSL"))
        #expect(previewLabels.contains("320°, 100%, 50%"))
        #expect(previewLabels.contains("HSB"))
        #expect(previewLabels.contains("320°, 100%, 100%"))

        controller.hide()
    }

    @Test
    @MainActor
    func fileCardUsesPersistedThumbnailWhenOriginalFileIsMissing() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("file-thumb.png")
        try writePNG(to: thumbnailURL, width: 80, height: 60)
        let missingPath = tempDirectory.appendingPathComponent("deleted.txt").path

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "deleted-file-card",
            sourceAppName: "Finder",
            relativeTimeText: "now",
            symbolName: "doc",
            typeText: "文件",
            summaryText: "",
            footnoteText: "deleted.txt",
            isSelected: true,
            preview: .file(accessibilityLabel: "Finder"),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Finder",
                previewAssetPath: "thumbnails/file-thumb.png",
                primaryText: missingPath
            )
        ))

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        #expect(imageView.image != nil)
        #expect(renderedCard.artifacts.filePreviewThumbnailTokensForSmoke().isEmpty)
    }

    @Test
    @MainActor
    func itemCardBaseBorderIsHidden() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil
        )
        let cardBox = try #require(renderedCard.view as? NSBox)

        #expect(abs(cardBox.borderWidth) < 0.001)
        #expect(cardBox.borderColor.alphaComponent < 0.001)
    }

    @Test
    @MainActor
    func textCardBodyExtendsBehindFooterAndUsesBottomFadeOverlay() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let itemSide: CGFloat = 218
        let theme = ClipShelfTheme.current(for: NSAppearance(named: .aqua))
        let renderer = makeRuntimeCardRenderer(
            appSupportDirectory: tempDirectory,
            itemSide: itemSide,
            theme: theme
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "text-card-fade",
            sourceAppName: "TextEdit",
            relativeTimeText: "now",
            symbolName: "doc.text",
            typeText: "文本",
            summaryText: String(repeating: "172.17.170.82:{\"data\":\n", count: 30),
            footnoteText: "1,524 个字符",
            isSelected: true,
            preview: .none,
            assetRequest: PanelCardAssetRequest(sourceAppName: "TextEdit")
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)
        let cardBox = try #require(renderedCard.view as? NSBox)
        let fadeView = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "TextBodyBottomFade"
        })
        let bodyFrame = bodyLabel.convert(bodyLabel.bounds, to: renderedCard.view)
        let fadeFrame = fadeView.convert(fadeView.bounds, to: renderedCard.view)

        #expect(colorAndAlphaDistance(
            cardBox.fillColor,
            theme.card.textItemBackgroundColor
        ) < 0.001)
        #expect(!fadeView.isHidden)
        #expect(fadeFrame.height >= 70)
        #expect(bodyFrame.intersects(fadeFrame))
    }

    @Test
    @MainActor
    func linkCardPreviewFillsResponsiveContentAreaAndKeepsFooterSeparate() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let sourceIconURL = tempDirectory.appendingPathComponent("source-icon.png")
        try writePNG(to: sourceIconURL, width: 20, height: 20)

        let theme = ClipShelfTheme.current(for: NSAppearance(named: .aqua))
        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: sourceIconURL.path,
            theme: theme
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let previewFrame = previewView.convert(previewView.bounds, to: renderedCard.view)
        let footerBackgroundView = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "LinkFooterBackground"
        })
        let footerBackgroundFrame = footerBackgroundView.convert(footerBackgroundView.bounds, to: renderedCard.view)
        let footerBackgroundColor = try #require(footerBackgroundView.layer?.backgroundColor)
        let linkIconView = try #require(renderedCard.artifacts.linkIconViews.first)
        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)

        #expect(renderedCard.artifacts.previewHeightConstraints.isEmpty)
        #expect(bodyLabel.isHidden)
        #expect(abs(previewFrame.minX) <= 1.5)
        #expect(abs(previewFrame.width - 218) <= 1.5)
        #expect(abs(previewFrame.height - 120) <= 1.5)
        #expect(abs(footerBackgroundFrame.minX) <= 1.5)
        #expect(abs(footerBackgroundFrame.width - 218) <= 1.5)
        #expect(colorAndAlphaDistance(
            NSColor(cgColor: footerBackgroundColor) ?? .clear,
            theme.card.linkFooterBackgroundColor
        ) < 0.001)
        #expect(linkIconView.toolTip == "github.com")
        #expect(!linkIconView.isHidden)
        #expect(!renderedCard.view.subviewsRecursiveForSmoke().contains { $0 is WKWebView })
    }

    @Test
    @MainActor
    func linkCardFooterBackgroundUsesThemePaletteInBothSchemes() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let lightTheme = ClipShelfTheme.current(for: NSAppearance(named: .aqua))
        let darkTheme = ClipShelfTheme.current(for: NSAppearance(named: .darkAqua))
        let lightCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            theme: lightTheme
        )
        let darkCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            theme: darkTheme
        )

        let lightFooterColor = try #require(linkFooterBackgroundColor(in: lightCard))
        let darkFooterColor = try #require(linkFooterBackgroundColor(in: darkCard))

        #expect(colorAndAlphaDistance(lightFooterColor, lightTheme.card.linkFooterBackgroundColor) < 0.001)
        #expect(colorAndAlphaDistance(darkFooterColor, darkTheme.card.linkFooterBackgroundColor) < 0.001)
        #expect(colorAndAlphaDistance(lightFooterColor, darkFooterColor) > 0.2)
    }

    @Test
    @MainActor
    func linkCardDefaultIconUsesReferenceBackgroundAndMonochromeSafariSymbol() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            theme: ClipShelfTheme.current(for: NSAppearance(named: .aqua))
        )
        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let linkIconView = try #require(renderedCard.artifacts.linkIconViews.first)
        let previewBackground = try #require(previewView.layer?.backgroundColor)
        let iconTintColor = try #require(linkIconView.contentTintColor)
        let backgroundAlpha = linkIconView.layer?.backgroundColor
            .flatMap { NSColor(cgColor: $0)?.alphaComponent } ?? 0
        let expectedPreviewBackground = NSColor(calibratedRed: 0.955, green: 0.963, blue: 0.982, alpha: 1)
        let expectedIconTint = NSColor(calibratedRed: 0.745, green: 0.745, blue: 0.775, alpha: 1)

        #expect(linkIconView.image?.isTemplate == true)
        #expect(colorAndAlphaDistance(NSColor(cgColor: previewBackground) ?? .clear, expectedPreviewBackground) < 0.001)
        #expect(colorAndAlphaDistance(iconTintColor, expectedIconTint) < 0.001)
        #expect(backgroundAlpha < 0.001)
        #expect(linkIconView.layer?.borderWidth == 0)
    }

    @Test
    @MainActor
    func linkCardPreviewGrowsWithPanelItemSide() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 274,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 274, height: 274))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let previewFrame = previewView.convert(previewView.bounds, to: renderedCard.view)

        #expect(abs(previewFrame.width - 274) <= 1.5)
        #expect(abs(previewFrame.height - 176) <= 1.5)
    }

    @Test
    @MainActor
    func linkCardWithBackgroundImageHidesIconTile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let previewDirectory = tempDirectory.appendingPathComponent("assets/link-previews", isDirectory: true)
        let iconDirectory = tempDirectory.appendingPathComponent("assets/link-icons", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
        try writePNG(to: previewDirectory.appendingPathComponent("example.png"), width: 120, height: 72)
        try writePNG(to: iconDirectory.appendingPathComponent("example.png"), width: 24, height: 24)

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            iconPath: "assets/link-icons/example.png",
            imagePath: "assets/link-previews/example.png"
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let backgroundImageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let linkIconView = try #require(renderedCard.artifacts.linkIconViews.first)

        #expect(await waitForMainActor(attempts: 240) { backgroundImageView.image != nil })
        host.layoutSubtreeIfNeeded()
        #expect(!backgroundImageView.isHidden)
        #expect(linkIconView.isHidden)
    }

    @Test
    @MainActor
    func linkCardPreviewCompactsAtMinimumPanelItemSide() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 156,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 156, height: 156))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let previewFrame = previewView.convert(previewView.bounds, to: renderedCard.view)
        let linkIconView = try #require(renderedCard.artifacts.linkIconViews.first)
        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)
        let visibleGithubLabels = renderedCard.view.subviewsRecursiveForSmoke()
            .compactMap { $0 as? NSTextField }
            .filter { !$0.isHidden && $0.stringValue.contains("github.com") }

        #expect(abs(previewFrame.width - 156) <= 1.5)
        #expect(abs(previewFrame.height - 58) <= 1.5)
        #expect(linkIconView.isHidden)
        #expect(bodyLabel.isHidden)
        #expect(visibleGithubLabels.count >= 2)
    }

    @Test
    @MainActor
    func linkCardWithoutTitleShowsOnlyCompactURLInFooter() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            linkTitle: "",
            footnoteText: "github.com/clipshelf/clipshelf",
            primaryText: "https://github.com/clipshelf/clipshelf"
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let visibleLabels = renderedCard.view.subviewsRecursiveForSmoke()
            .compactMap { $0 as? NSTextField }
            .filter { !$0.isHidden }
        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let previewFrame = previewView.convert(previewView.bounds, to: renderedCard.view)

        #expect(visibleLabels.contains { $0.stringValue == "github.com/clipshelf/clipshelf" })
        #expect(!visibleLabels.contains { $0.stringValue == "github.com" })
        #expect(abs(previewFrame.height - 138) <= 1.5)
    }

    @Test
    @MainActor
    func linkCardWithoutTitleUsesShorterFooterThanTitledLink() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let titledCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            linkTitle: "GitHub · Change is constant",
            footnoteText: "github.com"
        )
        let noTitleCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            linkTitle: "",
            footnoteText: "github.com/clipshelf/clipshelf",
            primaryText: "https://github.com/clipshelf/clipshelf"
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 436, height: 218))
        host.addSubview(titledCard.view)
        host.addSubview(noTitleCard.view)
        NSLayoutConstraint.activate([
            titledCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            titledCard.view.topAnchor.constraint(equalTo: host.topAnchor),
            noTitleCard.view.leadingAnchor.constraint(equalTo: titledCard.view.trailingAnchor),
            noTitleCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let titledPreview = try #require(titledCard.artifacts.linkPreviewViews.first)
        let noTitlePreview = try #require(noTitleCard.artifacts.linkPreviewViews.first)
        let titledPreviewFrame = titledPreview.convert(titledPreview.bounds, to: titledCard.view)
        let noTitlePreviewFrame = noTitlePreview.convert(noTitlePreview.bounds, to: noTitleCard.view)

        #expect(abs(titledPreviewFrame.height - 120) <= 1.5)
        #expect(abs(noTitlePreviewFrame.height - 138) <= 1.5)
        #expect(abs(noTitlePreviewFrame.height - titledPreviewFrame.height - 18) <= 1.5)
    }

    @Test
    @MainActor
    func videoFilePreviewSizeUsesClipShelfDocumentQuickLookViewport() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let videoURL = tempDirectory.appendingPathComponent("empty-preview.mp4")
        try Data().write(to: videoURL)

        let size = smokePreferredClipboardPreviewSize(for: makePreviewContent(fileURLs: [videoURL]))
        let expectedSize = expectedClipShelfDocumentPreviewSize()

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func missingFilePreviewFallsBackToText() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let missingPath = tempDirectory.appendingPathComponent("missing.pdf").path

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(tempDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: [makeRuntimeFileItem(id: "missing-file", primaryText: missingPath)],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsPreviewShown)
        #expect(!contentView.smokePreviewContainsQuickLookView())
        #expect(contentView.smokePreviewTextContent().contains(missingPath))

        controller.hide()
    }

    @Test
    @MainActor
    func missingFilePreviewUsesPersistedThumbnailWhenAvailable() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("deleted-file.png")
        try writePNG(to: thumbnailURL, width: 180, height: 120)
        let missingPath = tempDirectory.appendingPathComponent("deleted.md").path

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(tempDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: [
                    makeRuntimeFileItem(
                        id: "deleted-file-with-thumbnail",
                        primaryText: missingPath,
                        previewAssetPath: "thumbnails/deleted-file.png"
                    )
                ],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsPreviewShown)
        #expect(!contentView.smokePreviewContainsQuickLookView())
        #expect(contentView.smokePreviewTextContent().isEmpty)
        #expect(contentView.smokePreviewScreenFrame?.width ?? 0 > 0)

        controller.hide()
    }

    @Test
    @MainActor
    func fileCardHotPathDoesNotReadSnapshotFallback() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshotDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("file-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        let existingFile = tempDirectory.appendingPathComponent("legacy-file.pdf")
        try Data("legacy".utf8).write(to: existingFile)
        let snapshotURL = snapshotDirectory.appendingPathComponent("files.json")
        let snapshotData = try JSONEncoder().encode(["paths": [existingFile.path]])
        try snapshotData.write(to: snapshotURL)

        let resolver = PanelCardAssetResolver(appSupportDirectory: tempDirectory)
        let request = PanelCardAssetRequest(
            payloadAssetPath: "assets/file-snapshots/files.json",
            primaryText: nil
        )

        #expect(resolver.filePreviewURLs(for: request).isEmpty)
        #expect(resolver.filePreviewImage(for: request) != nil)
    }

    @Test
    @MainActor
    func sourceIconColorKeepsSmallSaturatedLogoOnPaleIcon() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let iconURL = tempDirectory.appendingPathComponent("small-saturated-logo.png")
        try writeSourceIconPNG(
            to: iconURL,
            width: 100,
            height: 100,
            background: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1),
            accents: [
                (rect:
                    NSRect(x: 12, y: 20, width: 10, height: 60),
                    color: NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.24, alpha: 1)
                )
            ]
        )

        let resolver = PanelCardAssetResolver(appSupportDirectory: tempDirectory)
        let resolved = resolver.resolvedItem(for: PanelCardAssetRequest(
            sourceAppId: "com.example.small-saturated-logo.\(UUID().uuidString)",
            sourceAppName: "Small Saturated Logo",
            sourceAppIconPath: iconURL.path
        ))
        let color = try #require(resolved.sourceIconColor?.usingColorSpace(.sRGB))
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        #expect(saturation >= 0.65)
        #expect(color.redComponent > color.greenComponent + 0.25)
        #expect(color.redComponent > color.blueComponent + 0.20)
        #expect(brightness >= 0.58)
    }

    @Test
    @MainActor
    func sourceIconPersistedHeaderColorSkipsDominantColorComputation() throws {
        var dominantComputationCount = 0
        let resolver = PanelCardAssetResolver(
            appSupportDirectory: nil,
            sourceIconImageLoader: { _ in NSImage(size: NSSize(width: 4, height: 4)) },
            dominantHeaderColorProvider: { _, _, _ in
                dominantComputationCount += 1
                return NSColor.systemRed
            }
        )

        let resolved = resolver.resolvedItem(for: PanelCardAssetRequest(
            sourceAppId: "source-app",
            sourceAppName: "Safari",
            sourceAppIconPath: "/tmp/icon.png",
            sourceAppIconHeaderColor: 0xFF11_2233
        ))
        let color = try #require(resolved.sourceIconColor?.usingColorSpace(.sRGB))

        #expect(dominantComputationCount == 0)
        #expect(abs(color.redComponent - CGFloat(0x11) / 255) < 0.001)
        #expect(abs(color.greenComponent - CGFloat(0x22) / 255) < 0.001)
        #expect(abs(color.blueComponent - CGFloat(0x33) / 255) < 0.001)
        #expect(color.alphaComponent == 1)
    }

    @Test
    @MainActor
    func sourceIconMissingPersistedHeaderColorComputesAndSchedulesWrite() async throws {
        var dominantComputationCount = 0
        let recorder = SourceColorWriteRecorder()
        let resolver = PanelCardAssetResolver(
            appSupportDirectory: nil,
            sourceIconHeaderColorWriter: { request in
                await recorder.append(request)
            },
            sourceIconImageLoader: { _ in NSImage(size: NSSize(width: 4, height: 4)) },
            dominantHeaderColorProvider: { _, _, _ in
                dominantComputationCount += 1
                return NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
            }
        )

        let resolved = resolver.resolvedItem(for: PanelCardAssetRequest(
            sourceAppId: "source-app",
            sourceAppName: "Safari",
            sourceAppIconPath: "/tmp/icon.png",
            sourceAppIconHeaderColor: nil
        ))

        #expect(resolved.sourceIconColor != nil)
        #expect(dominantComputationCount == 1)
        #expect(await waitForMainActor(attempts: 120) { recorder.requests.count == 1 })
        #expect(recorder.requests.first?.sourceAppID == "source-app")
        #expect(recorder.requests.first?.sourceAppIconPath == "/tmp/icon.png")
        #expect(recorder.requests.first?.headerColorARGB == 0xFF33_6699)
    }

    @Test
    @MainActor
    func outsideClickHidesPanelAfterSpaceClosesPreview() async throws {
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

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })
        let stalePreviewFrame = try #require(controller.smokePreviewScreenFrame)

        #expect(contentView.smokeClosePreviewWithSpaceFromPopoverFocus())
        PanelQAHarness.drainMainRunLoop()
        #expect(!contentView.smokeIsPreviewShown)

        let panelFrame = controller.smokePanelFrame
        let outsidePoint = CGPoint(
            x: max(stalePreviewFrame.maxX, panelFrame.maxX) + 80,
            y: max(stalePreviewFrame.maxY, panelFrame.maxY) + 80
        )
        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: outsidePoint
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
        try? await Task.sleep(nanoseconds: 260_000_000)
        #expect(!delegate.smokePanelControllerForRealFunctionQA.smokeHasActivePanelAnimation)
        let backgroundAlphaBeforeHide = delegate.smokePanelControllerForRealFunctionQA.smokePanelContentBackgroundAlpha

        delegate.smokeResignActiveForRealFunctionQA()
        #expect(await waitForMainActor { !delegate.smokePanelIsVisibleForRealFunctionQA })
        #expect(delegate.smokePanelControllerForRealFunctionQA.smokePanelIsActuallyVisible)
        #expect(delegate.smokePanelControllerForRealFunctionQA.smokeHasActivePanelAnimation)
        #expect(abs(delegate.smokePanelControllerForRealFunctionQA.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)

        #expect(await waitForMainActor(attempts: 240) {
            !delegate.smokePanelControllerForRealFunctionQA.smokePanelIsActuallyVisible
                && !delegate.smokePanelControllerForRealFunctionQA.smokeHasActivePanelAnimation
        })
        #expect(abs(delegate.smokePanelControllerForRealFunctionQA.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)
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

        delegate.smokeApplyInitialPresentationForRealFunctionQA(arguments: ["ClipShelf"])

        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
    }

    @Test
    @MainActor
    func appRuntimeShowsPreferencesForPackagedInitialPresentation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        delegate.smokeApplyInitialPresentationForRealFunctionQA(
            arguments: ["/Applications/ClipShelf.app/Contents/MacOS/ClipShelf"],
            isRunningAsApplicationBundle: true
        )

        #expect(await waitForMainActor { delegate.smokePreferencesIsVisibleForRealFunctionQA })
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
        delegate.smokeClosePreferencesForRealFunctionQA()
    }

    @Test
    @MainActor
    func appRuntimeKeepsPreferencesHiddenForLaunchAtLoginPresentation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        delegate.smokeApplyInitialPresentationForRealFunctionQA(
            arguments: [
                "/Applications/ClipShelf.app/Contents/MacOS/ClipShelf",
                ClipShelfLaunchArgument.launchedAtLogin
            ],
            isRunningAsApplicationBundle: true
        )

        #expect(!delegate.smokePreferencesIsVisibleForRealFunctionQA)
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
    }

    @Test
    @MainActor
    func appRuntimeShowsPreferencesWhenApplicationReopens() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        delegate.smokeHandleReopenForRealFunctionQA()

        #expect(await waitForMainActor { delegate.smokePreferencesIsVisibleForRealFunctionQA })
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
        delegate.smokeClosePreferencesForRealFunctionQA()
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
        #expect(contentView.smokeOrderedCardItemIDs() == pagedItems.map(\.id))
        #expect(contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound)
        controller.hide()
    }

    @Test
    @MainActor
    func loadMoreAppendFailureClearsSuppressionAndAllowsRetryForSameLoadedCount() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let firstPage = Array(PanelQASamples.makePagedPanelItems(count: 50))
        var loadMoreRequestCount = 0

        controller.onRuntimeAction = { action in
            if case .loadMore = action {
                loadMoreRequestCount += 1
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: firstPage, totalCount: 75, hasMore: true)),
            isFiltered: false
        )

        contentView.smokeScrollToLoadMoreThreshold()
        #expect(await waitForMainActor {
            loadMoreRequestCount == 1 && contentView.smokeIsLoadingMoreActive
        })

        contentView.updateListState(
            .failure(RustCoreError(
                code: "test",
                messageKey: "test",
                recoverable: true,
                message: "append failed"
            )),
            isFiltered: false,
            append: true
        )
        #expect(!contentView.smokeIsLoadingMoreActive)
        #expect(contentView.smokeCurrentItemCount == firstPage.count)

        contentView.smokeScrollToLoadMoreThreshold()
        #expect(await waitForMainActor {
            loadMoreRequestCount == 2 && contentView.smokeIsLoadingMoreActive
        })

        controller.hide()
    }

    @Test
    @MainActor
    func collectionSurfaceKeepsRetainedCellsBoundedWhenScrollingLargeLoadedList() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 90)

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == items.map(\.id) })

        for x in [CGFloat(0), CGFloat(3_800), CGFloat.greatestFiniteMagnitude] {
            contentView.smokeScrollToX(x)
            PanelQAHarness.drainMainRunLoop()
            #expect(contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound)
        }

        controller.hide()
    }

    @Test
    @MainActor
    func commandHintsUseFullyVisibleVisualOrderOnly() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 16)

        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeScrollToX(110)

        let visibleIDs = contentView.smokeVisibleCommandItemIDs()
        let orderedIDs = contentView.smokeOrderedCardItemIDs()
        let visibleIndexes = visibleIDs.compactMap { orderedIDs.firstIndex(of: $0) }

        #expect(visibleIDs.count <= 9)
        #expect(visibleIndexes == visibleIndexes.sorted())
        #expect(visibleIDs.first != items.first?.id)
    }

    @Test
    @MainActor
    func inactiveScopeUpdateDoesNotAttachCellsToActiveSurface() async throws {
        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let clipboardItems = PanelQASamples.makePagedPanelItems(count: 24)
        let inactiveItems = [clipboardItems[8], clipboardItems[9]]

        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: clipboardItems,
                totalCount: Int64(clipboardItems.count),
                hasMore: false
            )),
            isFiltered: false,
            scope: .clipboard
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == clipboardItems.map(\.id) })
        let retainedCountBefore = contentView.smokeRetainedCollectionSurfaceCount

        controller.updateListState(
            .success(RustCoreListResult(
                items: inactiveItems,
                totalCount: Int64(inactiveItems.count),
                hasMore: false
            )),
            isFiltered: true,
            scope: ClipboardListScope(pinboardID: "inactive-board")
        )

        #expect(contentView.smokeActiveListScope == .clipboard)
        #expect(contentView.smokeOrderedCardItemIDs() == clipboardItems.map(\.id))
        #expect(contentView.smokeRetainedCollectionSurfaceCount == retainedCountBefore)

        controller.hide()
    }

    @Test
    @MainActor
    func searchScopeSwitchRestoresOrderedIDsSelectionAndScrollOrigin() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let clipboardItems = PanelQASamples.makePagedPanelItems(count: 30)
        let searchItems = Array(clipboardItems[10...18])
        let searchScope = ClipboardListScope(normalizedSearch: "needle")

        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: clipboardItems,
                totalCount: Int64(clipboardItems.count),
                hasMore: false
            )),
            isFiltered: false,
            scope: .clipboard
        )

        contentView.smokeOpenSearch(text: "needle")
        controller.updateListState(
            .success(RustCoreListResult(
                items: searchItems,
                totalCount: Int64(searchItems.count),
                hasMore: false
            )),
            isFiltered: true,
            scope: searchScope
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == searchItems.map(\.id) })

        contentView.smokeSelectItem(id: searchItems[4].id, scrollIntoView: true)
        contentView.smokeScrollToX(420)
        let savedSearchX = contentView.smokeScrollOriginX

        contentView.resetFiltersForCapturedItem()
        #expect(contentView.smokeActiveListScope == .clipboard)

        contentView.smokeOpenSearch(text: "needle")
        controller.updateListState(
            .success(RustCoreListResult(
                items: searchItems,
                totalCount: Int64(searchItems.count),
                hasMore: false
            )),
            isFiltered: true,
            scope: searchScope
        )

        #expect(contentView.smokeActiveListScope == searchScope)
        #expect(contentView.smokeOrderedCardItemIDs() == searchItems.map(\.id))
        #expect(contentView.smokeSelectedItemID == searchItems[4].id)
        #expect(abs(contentView.smokeScrollOriginX - savedSearchX) < 1)

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
            if case .queryChanged(_, _, _, let pinboardID, let debounce) = action {
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
        contentView.smokeSelectItem(id: clipboardItems[8].id, scrollIntoView: true)
        #expect(await waitForMainActor { contentView.smokeSelectedItemID == clipboardItems[8].id })
        contentView.smokeScrollToX(640)
        let savedScrollX = contentView.smokeScrollOriginX
        #expect(savedScrollX > 0)

        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == pinboardItems.count })

        contentView.smokePinboardFilterButton(pinboardID: nil)?.onPress?()
        #expect(contentView.smokeCurrentItemCount == clipboardItems.count)
        #expect(contentView.smokeOrderedCardItemIDs() == clipboardItems.map(\.id))
        #expect(contentView.smokeSelectedItemID == clipboardItems[8].id)
        #expect(contentView.smokeActiveListScope == .clipboard)
        #expect(abs(contentView.smokeScrollOriginX - savedScrollX) < 1)
        #expect(contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound)
        #expect(queries.map(\.debounce) == [false, false])

        controller.hide()
    }

    @Test
    @MainActor
    func pinboardScopedDeleteKeepsOtherCachedPinboardListIndependent() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let samples = PanelQASamples.makePagedPanelItems(count: 4)
        let boardAItems = [samples[0]]
        let boardBItems = [samples[1]]
        var deletedItem: (id: String, pinboardID: String?)?
        var shouldApplyQueryResponses = true

        controller.onRuntimeAction = { action in
            switch action {
            case .queryChanged(_, _, _, let pinboardID, _):
                guard shouldApplyQueryResponses else { return }
                if pinboardID == "board-a" {
                    controller.updateListState(
                        .success(RustCoreListResult(
                            items: boardAItems,
                            totalCount: Int64(boardAItems.count),
                            hasMore: false
                        )),
                        isFiltered: true,
                        scope: ClipboardListScope(pinboardID: "board-a")
                    )
                } else if pinboardID == "board-b" {
                    controller.updateListState(
                        .success(RustCoreListResult(
                            items: boardBItems,
                            totalCount: Int64(boardBItems.count),
                            hasMore: false
                        )),
                        isFiltered: true,
                        scope: ClipboardListScope(pinboardID: "board-b")
                    )
                }
            case .deleteItem(let item, let pinboardID):
                deletedItem = (item.id, pinboardID)
            default:
                break
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
            ),
            RustPinboardSummary(
                id: "board-b",
                title: "Board B",
                colorCode: 4_294_620_928,
                sortOrder: 1,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])

        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == boardAItems.map(\.id) })

        contentView.smokePinboardFilterButton(pinboardID: "board-b")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == boardBItems.map(\.id) })

        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == boardAItems.map(\.id) })
        #expect(contentView.smokePerformManagementAction(itemID: boardAItems[0].id, title: "删除"))
        #expect(deletedItem?.id == boardAItems[0].id)
        #expect(deletedItem?.pinboardID == "board-a")

        shouldApplyQueryResponses = false
        contentView.invalidateCachedPinboardListPages(pinboardID: "board-a")
        contentView.smokePinboardFilterButton(pinboardID: "board-b")?.onPress?()

        #expect(contentView.smokeOrderedCardItemIDs() == boardBItems.map(\.id))

        controller.hide()
    }

    @Test
    @MainActor
    func topFilterChipsDoNotExposeColorCategory() async throws {
        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(itemType: String?, pinboardID: String?, debounce: Bool)] = []

        controller.onRuntimeAction = { action in
            if case .queryChanged(_, let itemType, _, let pinboardID, let debounce) = action {
                queries.append((itemType, pinboardID, debounce))
            }
        }
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

        #expect(contentView.smokeItemTypeFilterButton(itemType: "color") == nil)
        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()

        #expect(queries.map(\.pinboardID) == ["board-a"])
        #expect(queries.map(\.itemType) == [nil])
        #expect(queries.map(\.debounce) == [false])
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

private func makeRuntimeFileItem(
    id: String,
    primaryText: String,
    previewAssetPath: String? = nil
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "file",
        summary: URL(fileURLWithPath: primaryText).lastPathComponent,
        primaryText: primaryText,
        contentHash: id,
        sourceAppId: "com.apple.finder",
        sourceAppName: "Finder",
        sourceAppIconPath: nil,
        previewAssetPath: previewAssetPath,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 0,
        previewState: "ready"
    )
}

private func makeRuntimeTextItem(id: String, summary: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "text",
        summary: summary,
        primaryText: summary,
        contentHash: id,
        sourceAppId: "com.apple.TextEdit",
        sourceAppName: "TextEdit",
        sourceAppIconPath: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: Int64(summary.utf8.count),
        previewState: "ready"
    )
}

private func runtimeLinkItemByUpdatingMetadata(
    _ item: RustClipboardItemSummary,
    title: String
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: item.id,
        itemType: "link",
        summary: item.summary,
        primaryText: item.primaryText ?? "https://example.com/\(item.id)",
        contentHash: item.contentHash,
        sourceAppId: item.sourceAppId,
        sourceAppName: item.sourceAppName,
        sourceAppIconPath: item.sourceAppIconPath,
        previewAssetPath: item.previewAssetPath,
        payloadAssetPath: item.payloadAssetPath,
        sourceConfidence: item.sourceConfidence,
        firstCopiedAtMs: item.firstCopiedAtMs,
        lastCopiedAtMs: item.lastCopiedAtMs,
        copyCount: item.copyCount,
        isPinned: item.isPinned,
        sizeBytes: item.sizeBytes,
        previewState: item.previewState,
        fileItems: item.fileItems,
        linkMetadata: RustLinkMetadataSummary(
            canonicalURL: item.primaryText ?? "https://example.com/\(item.id)",
            displayURL: "example.com/\(item.id)",
            host: "example.com",
            title: title,
            metadataState: "ready"
        )
    )
}

private func makeRuntimeImageItem(
    id: String,
    previewAssetPath: String?,
    payloadAssetPath: String?
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "image",
        summary: "图片 800 x 600",
        primaryText: nil,
        contentHash: id,
        sourceAppId: "com.apple.Preview",
        sourceAppName: "预览",
        sourceAppIconPath: nil,
        previewAssetPath: previewAssetPath,
        payloadAssetPath: payloadAssetPath,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 4096,
        previewState: "ready"
    )
}

private func makeRuntimeImageFileItem(id: String, primaryText: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "file",
        summary: "2 个图片文件",
        primaryText: primaryText,
        contentHash: id,
        sourceAppId: "com.apple.finder",
        sourceAppName: "Finder",
        sourceAppIconPath: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 0,
        previewState: "ready"
    )
}

private func makeRuntimeColorItem(id: String, hex: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "color",
        summary: hex,
        primaryText: hex,
        contentHash: id,
        sourceAppId: "com.apple.DigitalColorMeter",
        sourceAppName: "Color Meter",
        sourceAppIconPath: nil,
        previewAssetPath: "should-not-load.png",
        payloadAssetPath: "should-not-load-payload.png",
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: Int64(hex.utf8.count),
        previewState: "ready"
    )
}

private func makePreviewContent(fileURLs: [URL]) -> ClipboardPreviewContent {
    ClipboardPreviewContent(
        itemID: UUID().uuidString,
        itemType: "file",
        title: fileURLs.first?.lastPathComponent ?? "文件",
        subtitle: "文件",
        body: fileURLs.first?.path ?? "",
        metadata: "",
        sourceAppName: "Finder",
        sourceAppIconPath: nil,
        imageURL: nil,
        linkURL: nil,
        linkDisplayURL: nil,
        linkTitle: nil,
        colorValue: nil,
        fileURLs: fileURLs,
        copiedAtMilliseconds: 1
    )
}

private func makeTextPreviewContent(body: String, itemType: String = "text") -> ClipboardPreviewContent {
    ClipboardPreviewContent(
        itemID: UUID().uuidString,
        itemType: itemType,
        title: "文本",
        subtitle: itemType == "rich_text" ? "富文本" : "文本",
        body: body,
        metadata: "",
        sourceAppName: "Notes",
        sourceAppIconPath: nil,
        imageURL: nil,
        linkURL: nil,
        linkDisplayURL: nil,
        linkTitle: nil,
        colorValue: nil,
        fileURLs: [],
        copiedAtMilliseconds: 1
    )
}

private func makeImagePreviewContent(imageURL: URL) -> ClipboardPreviewContent {
    ClipboardPreviewContent(
        itemID: UUID().uuidString,
        itemType: "image",
        title: imageURL.lastPathComponent,
        subtitle: "图片",
        body: "",
        metadata: "",
        sourceAppName: "Preview",
        sourceAppIconPath: nil,
        imageURL: imageURL,
        linkURL: nil,
        linkDisplayURL: nil,
        linkTitle: nil,
        colorValue: nil,
        fileURLs: [],
        copiedAtMilliseconds: 1
    )
}

private func expectedClipShelfTextPreviewSize(for text: String) -> NSSize {
    let maximumContentSize = expectedClipShelfTextMaximumContentSize()
    let measuredText = NSAttributedString(
        string: text.isEmpty ? " " : text,
        attributes: [
            .font: NSFont(name: "HelveticaNeue", size: 13) ?? NSFont.systemFont(ofSize: 13),
            .paragraphStyle: {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byCharWrapping
                paragraphStyle.lineSpacing = 0
                return paragraphStyle
            }()
        ]
    )
    let measuredPrefix = measuredText.length >= 2_001
        ? measuredText.attributedSubstring(from: NSRange(location: 0, length: 2_000))
        : measuredText
    let measured = measuredPrefix.boundingRect(
        with: maximumContentSize,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
    )
    let contentWidth = min(maximumContentSize.width, ceil(measured.width) + 8 * 2 + 20)
    let contentHeight = min(maximumContentSize.height, ceil(measured.height) + 10 * 2)
    return NSSize(
        width: max(floor(contentWidth + 10), 390),
        height: floor(max(contentHeight, 240) + 76)
    )
}

private func expectedClipShelfTextMaximumContentSize() -> NSSize {
    guard let screenFrame = NSScreen.main?.frame else {
        return NSSize(width: 1_000, height: 1_000)
    }

    return NSSize(
        width: floor(screenFrame.width * 0.5),
        height: floor(screenFrame.height * 0.5)
    )
}

private func expectedClipShelfDocumentPreviewSize() -> NSSize {
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
    return NSSize(
        width: floor(screenFrame.width * 0.5 + 10),
        height: floor(screenFrame.height * 0.5 + 76)
    )
}

private func expectedClipShelfImagePreviewSize(imageWidth: CGFloat, imageHeight: CGFloat) -> NSSize {
    let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
    let maximumContentWidth = screenFrame.width * 0.5
    let maximumContentHeight = screenFrame.height * 0.5
    let scale = (imageWidth > maximumContentWidth || imageHeight > maximumContentHeight)
        ? min(maximumContentWidth / imageWidth, maximumContentHeight / imageHeight)
        : 1
    return NSSize(
        width: max(floor(imageWidth * scale + 10), 112),
        height: floor(imageHeight * scale + 76)
    )
}

private func writePNG(to url: URL, width: Int, height: Int) throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.24, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
    NSGraphicsContext.restoreGraphicsState()

    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
}

private func writeTransparentPNG(to url: URL, width: Int, height: Int, opaqueRect: NSRect) throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
    NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.24, alpha: 1).setFill()
    opaqueRect.fill()
    NSGraphicsContext.restoreGraphicsState()

    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
}

private func writeSourceIconPNG(
    to url: URL,
    width: Int,
    height: Int,
    background: NSColor,
    accents: [(rect: NSRect, color: NSColor)]
) throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    background.setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
    for accent in accents {
        accent.color.setFill()
        accent.rect.fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
}

@MainActor
private final class SourceColorWriteRecorder: @unchecked Sendable {
    private(set) var requests: [SourceAppIconHeaderColorWriteRequest] = []

    func append(_ request: SourceAppIconHeaderColorWriteRequest) {
        requests.append(request)
    }
}

@MainActor
private func makeRuntimeCardRenderer(
    appSupportDirectory: URL,
    itemSide: CGFloat,
    theme: ClipShelfThemePalette? = nil
) -> PanelItemCardRenderer {
    let app = NSApplication.shared
    let theme = theme ?? ClipShelfTheme.current(for: app.effectiveAppearance)
    return PanelItemCardRenderer(
        cardAssetResolver: PanelCardAssetResolver(appSupportDirectory: appSupportDirectory),
        metrics: PanelItemCardRendererMetrics(
            defaultItemSide: itemSide,
            cardCornerRadius: 10,
            innerCornerRadius: 8,
            cardHeaderHeight: 48,
            cardInset: 12,
            cardFooterHeight: 17,
            sourceIconSize: 54,
            linkPreviewHeight: 84,
            theme: theme
        ),
        backingScaleFactor: NSScreen.main?.backingScaleFactor ?? 2
    )
}

@MainActor
private func renderLinkCard(
    itemSide: CGFloat,
    appSupportDirectory: URL,
    sourceAppIconPath: String?,
    linkTitle: String = "github.com",
    footnoteText: String = "github.com",
    primaryText: String = "https://github.com/",
    iconPath: String? = nil,
    imagePath: String? = nil,
    theme: ClipShelfThemePalette? = nil
) -> PanelRenderedItemCard {
    let renderer = makeRuntimeCardRenderer(
        appSupportDirectory: appSupportDirectory,
        itemSide: itemSide,
        theme: theme
    )

    return renderer.render(PanelItemCardViewState(
        itemID: "link-card-paste-style",
        sourceAppName: "Safari",
        relativeTimeText: "now",
        symbolName: "link",
        typeText: "链接",
        summaryText: "",
        footnoteText: footnoteText,
        isSelected: true,
        preview: .link(
            title: linkTitle,
            host: "github.com",
            detail: primaryText,
            iconPath: iconPath,
            imagePath: imagePath,
            accessibilityLabel: "Safari"
        ),
        assetRequest: PanelCardAssetRequest(
            sourceAppName: "Safari",
            sourceAppIconPath: sourceAppIconPath,
            primaryText: primaryText
        )
    ))
}

@MainActor
private func linkFooterBackgroundColor(in renderedCard: PanelRenderedItemCard) -> NSColor? {
    renderedCard.view.subviewsRecursiveForSmoke()
        .first { $0.identifier?.rawValue == "LinkFooterBackground" }?
        .layer?
        .backgroundColor
        .flatMap(NSColor.init(cgColor:))
}

private extension NSView {
    func subviewsRecursiveForSmoke() -> [NSView] {
        subviews + subviews.flatMap { $0.subviewsRecursiveForSmoke() }
    }
}

private func colorAndAlphaDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
    guard let lhs = lhs.usingColorSpace(.sRGB),
          let rhs = rhs.usingColorSpace(.sRGB)
    else {
        return 1
    }

    return abs(lhs.redComponent - rhs.redComponent)
        + abs(lhs.greenComponent - rhs.greenComponent)
        + abs(lhs.blueComponent - rhs.blueComponent)
        + abs(lhs.alphaComponent - rhs.alphaComponent)
}

@MainActor
private func sendWheel(to scrollView: NSScrollView, deltaX: Int32, deltaY: Int32) {
    guard let cgEvent = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 2,
        wheel1: deltaY,
        wheel2: deltaX,
        wheel3: 0
    ) else {
        return
    }
    cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(deltaY))
    cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(deltaX))

    guard let event = NSEvent(cgEvent: cgEvent) else { return }
    scrollView.scrollWheel(with: event)
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

private final class InMemoryPanelHeightPreferenceStore: PanelHeightPreferenceStoring {
    var preferredPanelHeight: CGFloat?
}
