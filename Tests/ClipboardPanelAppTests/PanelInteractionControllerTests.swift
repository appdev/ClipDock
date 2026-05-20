import Testing
@testable import ClipboardPanelApp

struct PanelInteractionControllerTests {
    @Test
    func setSearchTextEmitsTrimmedQueryAction() {
        let controller = PanelInteractionController()

        let result = controller.dispatch(.setSearchText("  report  "))

        #expect(result.viewState.toolbar.searchText == "report")
        #expect(result.effects == [
            .external(.queryChanged(searchText: "report", itemType: nil, sourceAppID: nil, pinboardID: nil, debounce: true))
        ])
        #expect(!result.shouldSyncToolbar)
    }

    @Test
    func pinboardFilterEmitsPinboardQuery() {
        let controller = makePanelInteractionController()

        let result = controller.dispatch(.setPinboardFilter("default"))

        #expect(result.viewState.toolbar.selectedPinboardID == "default")
        #expect(result.effects == [
            .external(.queryChanged(searchText: "", itemType: nil, sourceAppID: nil, pinboardID: "default", debounce: false))
        ])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func itemTypeFilterComposesWithSearchAndPinboard() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "#FF00AA",
                    pinboardID: "default",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.setItemTypeFilter("color"))

        #expect(result.viewState.toolbar.searchText == "#FF00AA")
        #expect(result.viewState.toolbar.selectedItemType == "color")
        #expect(result.viewState.toolbar.selectedPinboardID == "default")
        #expect(result.effects == [
            .external(.queryChanged(
                searchText: "#FF00AA",
                itemType: "color",
                sourceAppID: nil,
                pinboardID: "default",
                debounce: false
            ))
        ])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func scopeFilterClearsItemTypeAndPinboardWithoutClearingSearch() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "#FF00AA",
                    itemType: "color",
                    pinboardID: "default",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.setScopeFilters(itemType: nil, pinboardID: nil))

        #expect(result.viewState.toolbar.searchText == "#FF00AA")
        #expect(result.viewState.toolbar.selectedItemType == nil)
        #expect(result.viewState.toolbar.selectedPinboardID == nil)
        #expect(result.effects == [
            .external(.queryChanged(
                searchText: "#FF00AA",
                itemType: nil,
                sourceAppID: nil,
                pinboardID: nil,
                debounce: false
            ))
        ])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func startSearchReplacesHiddenTextFocusesSearchAndEmitsDebouncedQueryWithFilters() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "rep",
                    itemType: "text",
                    pinboardID: "default",
                    isSearchVisible: false
                )
            )
        )

        let result = controller.dispatch(.startSearch(initialText: "A"))

        #expect(result.viewState.toolbar.searchText == "A")
        #expect(result.viewState.toolbar.isSearchVisible)
        #expect(result.viewState.toolbar.selectedItemType == "text")
        #expect(result.viewState.toolbar.selectedPinboardID == "default")
        #expect(result.effects == [
            .focus(.searchField),
            .external(.queryChanged(
                searchText: "A",
                itemType: "text",
                sourceAppID: nil,
                pinboardID: "default",
                debounce: true
            ))
        ])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func startSearchAppendsVisibleTextFocusesSearchAndEmitsDebouncedQueryWithFilters() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "rep",
                    itemType: "text",
                    pinboardID: "default",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.startSearch(initialText: "A"))

        #expect(result.viewState.toolbar.searchText == "repA")
        #expect(result.viewState.toolbar.isSearchVisible)
        #expect(result.viewState.toolbar.selectedItemType == "text")
        #expect(result.viewState.toolbar.selectedPinboardID == "default")
        #expect(result.effects == [
            .focus(.searchField),
            .external(.queryChanged(
                searchText: "repA",
                itemType: "text",
                sourceAppID: nil,
                pinboardID: "default",
                debounce: true
            ))
        ])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func clearSearchTextClearsNonEmptySearchKeepsVisibleFocusedAndEmitsImmediateQuery() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "report",
                    itemType: "text",
                    pinboardID: "default",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.clearSearchText)

        #expect(result.viewState.toolbar.searchText.isEmpty)
        #expect(result.viewState.toolbar.isSearchVisible)
        #expect(result.viewState.toolbar.selectedItemType == "text")
        #expect(result.viewState.toolbar.selectedPinboardID == "default")
        #expect(result.effects == [
            .focus(.searchField),
            .external(.queryChanged(
                searchText: "",
                itemType: "text",
                sourceAppID: nil,
                pinboardID: "default",
                debounce: false
            ))
        ])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func clearSearchTextWhenEmptyKeepsVisibleFocusedWithoutQuery() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "",
                    itemType: "text",
                    pinboardID: "default",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.clearSearchText)

        #expect(result.viewState.toolbar.searchText.isEmpty)
        #expect(result.viewState.toolbar.isSearchVisible)
        #expect(result.viewState.toolbar.selectedItemType == "text")
        #expect(result.viewState.toolbar.selectedPinboardID == "default")
        #expect(result.effects == [.focus(.searchField)])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func selectionActionClosesPreviewAndRequestsSelectionRefresh() {
        let items = [makePanelInteractionItem(id: "a"), makePanelInteractionItem(id: "b")]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                selection: PanelSelectionState(selectedItemID: "a")
            ),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 2,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.selectOffset(1))

        #expect(result.viewState.selectedItemID == "b")
        #expect(result.effects == [
            .preview(.close),
            .selectionChanged(scrollIntoView: true)
        ])
    }

    @Test
    func explicitSelectionIntentsToggleRangeAndExtend() {
        let items = [
            makePanelInteractionItem(id: "a"),
            makePanelInteractionItem(id: "b"),
            makePanelInteractionItem(id: "c"),
            makePanelInteractionItem(id: "d")
        ]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(selection: PanelSelectionState(selectedItemID: "b")),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 4,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let toggled = controller.dispatch(.selection(.toggle(itemID: "d")))
        #expect(toggled.viewState.selectedItemID == "d")
        #expect(toggled.viewState.selectedItemIDs == ["b", "d"])
        #expect(toggled.effects == [
            .preview(.close),
            .selectionChanged(scrollIntoView: true)
        ])

        let ranged = controller.dispatch(.selection(.range(toItemID: "a")))
        #expect(ranged.viewState.selectedItemID == "a")
        #expect(ranged.viewState.selectedItemIDs == ["a", "b", "c", "d"])

        let extended = controller.dispatch(.selection(.extendByOffset(1)))
        #expect(extended.viewState.selectedItemID == "b")
        #expect(extended.viewState.selectedItemIDs == ["b", "c", "d"])
    }

    @Test
    func prepareManagementMenuPreservesSelectedItemSelectionAndReplacesUnselectedItem() {
        let items = [
            makePanelInteractionItem(id: "a"),
            makePanelInteractionItem(id: "b"),
            makePanelInteractionItem(id: "c")
        ]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(selection: PanelSelectionState(
                selectedItemID: "a",
                selectedItemIDs: ["a", "c"],
                rangeAnchorItemID: "a"
            )),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 3,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let selectedResult = controller.dispatch(.prepareManagementMenu(itemID: "c"))
        #expect(selectedResult.viewState.selectedItemID == "c")
        #expect(selectedResult.viewState.selectedItemIDs == ["a", "c"])
        #expect(selectedResult.effects == [
            .preview(.close),
            .selectionChanged(scrollIntoView: false)
        ])

        let unselectedResult = controller.dispatch(.prepareManagementMenu(itemID: "b"))
        #expect(unselectedResult.viewState.selectedItemID == "b")
        #expect(unselectedResult.viewState.selectedItemIDs == ["b"])
    }

    @Test
    func scrollActionUpdatesCommandHintsAndRequestsLoadMore() {
        let items = [
            makePanelInteractionItem(id: "a"),
            makePanelInteractionItem(id: "b"),
            makePanelInteractionItem(id: "c")
        ]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                selection: PanelSelectionState(
                    selectedItemID: "a",
                    isCommandHintModeEnabled: true
                )
            ),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 6,
                hasMoreItems: true,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.didScroll(
            visibleCommandItemIDs: ["a", "b", "c"],
            reachedLoadMoreThreshold: true
        ))

        #expect(result.effects == [
            .commandHints(["a": "1", "b": "2", "c": "3"]),
            .external(.loadMore)
        ])
        #expect(controller.isLoadingMoreItems)
    }

    @Test
    func commandCopyClearsHintsAndEmitsCopyAction() {
        let items = [
            makePanelInteractionItem(id: "a"),
            makePanelInteractionItem(id: "b"),
            makePanelInteractionItem(id: "c")
        ]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                selection: PanelSelectionState(
                    selectedItemID: "a",
                    isCommandHintModeEnabled: true
                )
            ),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 3,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.copyCommandItem(
            number: 2,
            visibleItemIDs: ["a", "b", "c"]
        ))

        #expect(result.viewState.selectedItemID == "b")
        #expect(!result.viewState.isCommandHintModeEnabled)
        #expect(result.effects == [
            .commandHints([:]),
            .preview(.close),
            .external(.copyItem(itemID: "b"))
        ])
    }

    @Test
    func copySelectedItemEmitsCopyActionAndClearsCommandHints() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                selection: PanelSelectionState(
                    selectedItemID: "b",
                    selectedItemIDs: ["a", "b"],
                    rangeAnchorItemID: "a",
                    isCommandHintModeEnabled: true
                )
            )
        )

        let result = controller.dispatch(.copySelectedItem)

        #expect(result.viewState.selectedItemID == "b")
        #expect(result.viewState.selectedItemIDs == ["a", "b"])
        #expect(!result.viewState.isCommandHintModeEnabled)
        #expect(result.effects == [
            .commandHints([:]),
            .preview(.close),
            .external(.copyItem(itemID: "b"))
        ])
    }

    @Test
    func collapseSelectionToPrimaryClearsTransientMultiSelection() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                selection: PanelSelectionState(
                    selectedItemID: "b",
                    selectedItemIDs: ["a", "b"],
                    rangeAnchorItemID: "a"
                )
            )
        )

        let result = controller.collapseSelectionToPrimary()

        #expect(result.viewState.selectedItemID == "b")
        #expect(result.viewState.selectedItemIDs == ["b"])
        #expect(result.effects == [.selectionChanged(scrollIntoView: false)])
    }

    @Test
    func deleteSelectedItemEmitsDeleteActionAndClearsCommandHints() {
        let items = [makePanelInteractionItem(id: "b")]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                selection: PanelSelectionState(
                    selectedItemID: "b",
                    isCommandHintModeEnabled: true
                )
            ),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 1,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.deleteSelectedItem)

        #expect(!result.viewState.isCommandHintModeEnabled)
        #expect(result.effects == [
            .commandHints([:]),
            .preview(.close),
            .external(.deleteItem(itemID: "b", pinboardID: nil))
        ])
    }

    @Test
    func deleteSelectedItemInPinboardCarriesCurrentPinboardScope() {
        let items = [makePanelInteractionItem(id: "b")]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(pinboardID: "board-a"),
                selection: PanelSelectionState(selectedItemID: "b")
            ),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 1,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.deleteSelectedItem)

        #expect(result.effects == [
            .commandHints([:]),
            .preview(.close),
            .external(.deleteItem(itemID: "b", pinboardID: "board-a"))
        ])
    }

    @Test
    func deleteSelectedItemUsesOrderedBatchTargetsInVisualOrder() {
        let items = [
            makePanelInteractionItem(id: "a"),
            makePanelInteractionItem(id: "b"),
            makePanelInteractionItem(id: "c")
        ]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(selection: PanelSelectionState(
                selectedItemID: "c",
                selectedItemIDs: ["c", "a"],
                rangeAnchorItemID: "c"
            )),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 3,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.deleteSelectedItem)

        #expect(result.effects == [
            .commandHints([:]),
            .preview(.close),
            .external(.deleteItems(itemIDs: ["a", "c"], pinboardID: nil))
        ])
    }

    @Test
    func managementPinboardActionUsesOrderedBatchTargetsWhenItemIsSelected() {
        let items = [
            makePanelInteractionItem(id: "a"),
            makePanelInteractionItem(id: "b"),
            makePanelInteractionItem(id: "c")
        ]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(selection: PanelSelectionState(
                selectedItemID: "c",
                selectedItemIDs: ["c", "a"],
                rangeAnchorItemID: "c"
            )),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 3,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.management(
            itemID: "c",
            action: .setPinboardMembership(pinboardID: "board-a", isMember: true)
        ))

        #expect(result.effects == [
            .external(.setPinboardMembershipBatch(
                itemIDs: ["a", "c"],
                pinboardID: "board-a",
                isMember: true
            ))
        ])
    }

    @Test
    func previewRemainsPrimaryOnlyWithMultiSelection() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(selection: PanelSelectionState(
                selectedItemID: "b",
                selectedItemIDs: ["a", "b"],
                rangeAnchorItemID: "a"
            ))
        )

        let result = controller.dispatch(.activateSelectedPreview)

        #expect(result.viewState.selectedItemIDs == ["a", "b"])
        #expect(result.effects == [.preview(.toggle(itemID: "b"))])
    }

    @Test
    func managementCopyAsPlainTextEmitsPlainTextCopyAction() {
        let items = [makePanelInteractionItem(id: "a"), makePanelInteractionItem(id: "b")]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                selection: PanelSelectionState(selectedItemID: "a")
            ),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 2,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.management(
            itemID: "b",
            action: .copyAsPlainText
        ))

        #expect(result.viewState.selectedItemID == "b")
        #expect(result.effects == [
            .preview(.close),
            .external(.copyItemAsPlainText(itemID: "b"))
        ])
    }

    @Test
    func managementPreviewUsesActionBoundaryInsteadOfExternalMutation() {
        let items = [makePanelInteractionItem(id: "a"), makePanelInteractionItem(id: "b")]
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                selection: PanelSelectionState(selectedItemID: "a")
            ),
            listViewState: PanelListViewState(
                presentation: .items(items),
                totalCount: 2,
                hasMoreItems: false,
                isLoadingMoreItems: false
            )
        )

        let result = controller.dispatch(.management(
            itemID: "b",
            action: .preview
        ))

        #expect(result.viewState.selectedItemID == "b")
        #expect(result.effects == [
            .selectionChanged(scrollIntoView: false),
            .preview(.show(itemID: "b"))
        ])
    }

    @Test
    func escapeClearsSearchAndEmitsUpdatedQuery() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "report",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.escape(isPreviewShown: false))

        #expect(result.viewState.toolbar.searchText.isEmpty)
        #expect(result.viewState.toolbar.isSearchVisible)
        #expect(result.effects == [
            .external(.queryChanged(searchText: "", itemType: nil, sourceAppID: nil, pinboardID: nil, debounce: false))
        ])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func escapeClosesVisibleEmptySearchFocusesPanelWithoutReloadingQuery() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "",
                    pinboardID: "default",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.escape(isPreviewShown: false))

        #expect(result.viewState.toolbar.searchText.isEmpty)
        #expect(!result.viewState.toolbar.isSearchVisible)
        #expect(result.viewState.toolbar.selectedPinboardID == "default")
        #expect(result.effects == [.focus(.panel)])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func escapeHidesPanelWhenSearchIsClosedAndEmpty() {
        let controller = makePanelInteractionController()

        let result = controller.dispatch(.escape(isPreviewShown: false))

        #expect(result.effects == [.external(.hidePanel)])
        #expect(!result.shouldSyncToolbar)
    }

    @Test
    func dismissSearchClearsQueryHidesFieldAndPreservesPinboard() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "report",
                    pinboardID: "default",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.dismissSearch)

        #expect(result.viewState.toolbar.searchText.isEmpty)
        #expect(!result.viewState.toolbar.isSearchVisible)
        #expect(result.viewState.toolbar.selectedPinboardID == "default")
        #expect(result.effects == [
            .external(.queryChanged(searchText: "", itemType: nil, sourceAppID: nil, pinboardID: "default", debounce: false))
        ])
        #expect(result.shouldSyncToolbar)
    }

    @Test
    func dismissSearchHidesEmptyFieldWithoutReloadingQuery() {
        let controller = makePanelInteractionController(
            sceneState: PanelSceneState(
                query: PanelQueryState(
                    searchText: "",
                    isSearchVisible: true
                )
            )
        )

        let result = controller.dispatch(.dismissSearch)

        #expect(!result.viewState.toolbar.isSearchVisible)
        #expect(result.effects.isEmpty)
        #expect(result.shouldSyncToolbar)
    }
}

private func makePanelInteractionController(
    sceneState: PanelSceneState = PanelSceneState(),
    listViewState: PanelListViewState = PanelListViewState()
) -> PanelInteractionController {
    PanelInteractionController(
        contentController: PanelContentController(
            sceneStore: PanelSceneRuntimeController(state: sceneState),
            listViewState: listViewState
        )
    )
}

private func makePanelInteractionItem(id: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "text",
        summary: id,
        primaryText: id,
        contentHash: id,
        sourceAppId: nil,
        sourceAppName: nil,
        sourceAppIconPath: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 1,
        previewState: "ready"
    )
}
