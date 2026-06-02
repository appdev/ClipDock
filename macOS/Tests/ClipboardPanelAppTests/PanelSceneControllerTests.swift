import Testing
@testable import ClipboardPanelApp

struct PanelSceneControllerTests {
    @Test
    func searchToggleShowsFieldAndRequestsFocus() {
        let result = PanelSceneController.searchToggleResult(PanelSceneState())

        #expect(result.state.query.isSearchVisible)
        #expect(result.focusTarget == .searchField)
    }

    @Test
    func searchToggleHidesEmptyFieldAndReturnsPanelFocus() {
        let state = PanelSceneState(
            query: PanelQueryState(searchText: "", isSearchVisible: true)
        )

        let result = PanelSceneController.searchToggleResult(state)

        #expect(!result.state.query.isSearchVisible)
        #expect(result.focusTarget == .panel)
    }

    @Test
    func searchToggleKeepsVisibleFieldWhenSearchIsNotEmpty() {
        let state = PanelSceneState(
            query: PanelQueryState(searchText: "report", isSearchVisible: true)
        )

        let result = PanelSceneController.searchToggleResult(state)

        #expect(result.state.query.isSearchVisible)
        #expect(result.focusTarget == nil)
    }

    @Test
    func selectingOffsetChangesSelectionAndClosesPreview() {
        let state = PanelSceneState(
            selection: PanelSelectionState(selectedItemID: "a")
        )

        let update = PanelSceneController.stateBySelectingOffset(
            state,
            itemIDs: ["a", "b", "c"],
            offset: 1
        )

        #expect(update.state.selection.selectedItemID == "b")
        #expect(update.state.selection.selectedItemIDs == ["b"])
        #expect(update.state.selection.rangeAnchorItemID == "b")
        #expect(update.didChangeSelection)
        #expect(update.shouldClosePreview)
    }

    @Test
    func selectingSameItemIsNoOp() {
        let state = PanelSceneState(
            selection: PanelSelectionState(selectedItemID: "b")
        )

        let update = PanelSceneController.stateBySelectingItem(
            state,
            itemIDs: ["a", "b", "c"],
            selectedItemID: "b"
        )

        #expect(update.state == state)
        #expect(!update.didChangeSelection)
        #expect(!update.shouldClosePreview)
    }

    @Test
    func escapeActionUsesSceneSearchState() {
        let state = PanelSceneState(
            query: PanelQueryState(searchText: " report ", isSearchVisible: true)
        )
        let visibleEmptyState = PanelSceneState(
            query: PanelQueryState(searchText: "", isSearchVisible: true)
        )

        #expect(PanelSceneController.escapeAction(state, isPreviewShown: false) == .clearSearch)
        #expect(PanelSceneController.escapeAction(state, isPreviewShown: true) == .closePreview)
        #expect(PanelSceneController.escapeAction(visibleEmptyState, isPreviewShown: false) == .closeSearch)
    }

    @Test
    func clearingFiltersResetsSearchVisibilityAndPinboard() {
        let state = PanelSceneState(
            query: PanelQueryState(searchText: "report", pinboardID: "default", isSearchVisible: true)
        )

        let nextState = PanelSceneController.stateByClearingFilters(state)

        #expect(nextState.query.searchText.isEmpty)
        #expect(nextState.query.pinboardID == nil)
        #expect(!nextState.query.isSearchVisible)
    }

    @Test
    func focusSearchShowsFieldAndFocusesSearchField() {
        let result = PanelSceneController.focusSearchResult(PanelSceneState())

        #expect(result.state.query.isSearchVisible)
        #expect(result.focusTarget == .searchField)
    }

    @Test
    func startSearchReplacesHiddenSearchTextShowsFieldFocusesSearchAndPreservesFilters() {
        let state = PanelSceneState(
            query: PanelQueryState(
                searchText: "rep",
                itemType: "text",
                pinboardID: "default",
                isSearchVisible: false
            )
        )

        let result = PanelSceneController.startSearchResult(state, initialText: "A")

        #expect(result.state.query.searchText == "A")
        #expect(result.state.query.itemType == "text")
        #expect(result.state.query.pinboardID == "default")
        #expect(result.state.query.isSearchVisible)
        #expect(result.focusTarget == .searchField)
    }

    @Test
    func startSearchAppendsInitialTextWhenSearchIsAlreadyVisible() {
        let state = PanelSceneState(
            query: PanelQueryState(
                searchText: "rep",
                itemType: "text",
                pinboardID: "default",
                isSearchVisible: true
            )
        )

        let result = PanelSceneController.startSearchResult(state, initialText: "A")

        #expect(result.state.query.searchText == "repA")
        #expect(result.state.query.itemType == "text")
        #expect(result.state.query.pinboardID == "default")
        #expect(result.state.query.isSearchVisible)
        #expect(result.focusTarget == .searchField)
    }

    @Test
    func dismissingSearchClearsTextHidesFieldAndKeepsPinboardFilter() {
        let state = PanelSceneState(
            query: PanelQueryState(
                searchText: "report",
                pinboardID: "default",
                isSearchVisible: true
            )
        )

        let nextState = PanelSceneController.stateByDismissingSearch(state)

        #expect(nextState.query.searchText.isEmpty)
        #expect(!nextState.query.isSearchVisible)
        #expect(nextState.query.pinboardID == "default")
    }

    @Test
    func runtimeControllerDismissSearchMutatesState() {
        let controller = PanelSceneRuntimeController(
            state: PanelSceneState(
                query: PanelQueryState(searchText: "report", isSearchVisible: true)
            )
        )

        controller.dismissSearch()

        #expect(controller.state.query.searchText.isEmpty)
        #expect(!controller.state.query.isSearchVisible)
    }

    @Test
    func clearingSelectionRemovesSelectedItem() {
        let state = PanelSceneState(
            selection: PanelSelectionState(
                selectedItemID: "selected",
                selectedItemIDs: ["selected", "other"],
                rangeAnchorItemID: "other"
            )
        )

        let nextState = PanelSceneController.stateByClearingSelection(state)

        #expect(nextState.selection.selectedItemID == nil)
        #expect(nextState.selection.selectedItemIDs.isEmpty)
        #expect(nextState.selection.rangeAnchorItemID == nil)
    }

    @Test
    func previewPopoverEnabledTracksPureState() {
        let enabled = PanelSceneController.stateBySettingPreviewPopoverEnabled(
            PanelSceneState(),
            enabled: true
        )
        let disabled = PanelSceneController.stateBySettingPreviewPopoverEnabled(
            enabled,
            enabled: false
        )

        #expect(enabled.preview.isPopoverEnabled)
        #expect(!disabled.preview.isPopoverEnabled)
    }

    @Test
    func runtimeControllerPersistsSelectionUpdates() {
        let controller = PanelSceneRuntimeController(
            state: PanelSceneState(selection: PanelSelectionState(selectedItemID: "a"))
        )

        let update = controller.selectOffset(itemIDs: ["a", "b", "c"], offset: 1)

        #expect(update.didChangeSelection)
        #expect(controller.state.selection.selectedItemID == "b")
    }

    @Test
    func runtimeControllerPersistsSearchAndPinboardState() {
        let controller = PanelSceneRuntimeController()

        controller.setSearchText(" report ")
        controller.setPinboardFilter("default")

        #expect(controller.state.query.searchText == "report")
        #expect(controller.state.query.pinboardID == "default")
    }

    @Test
    func runtimeControllerToggleSearchMutatesState() {
        let controller = PanelSceneRuntimeController()

        let result = controller.toggleSearch()

        #expect(result.focusTarget == .searchField)
        #expect(controller.state.query.isSearchVisible)
    }

    @Test
    func runtimeControllerStartSearchMutatesState() {
        let controller = PanelSceneRuntimeController(
            state: PanelSceneState(
                query: PanelQueryState(searchText: "#", pinboardID: "colors")
            )
        )

        let result = controller.startSearch(initialText: "F")

        #expect(result.focusTarget == .searchField)
        #expect(controller.state.query.searchText == "F")
        #expect(controller.state.query.pinboardID == "colors")
        #expect(controller.state.query.isSearchVisible)
    }

    @Test
    func commandHintModeTracksPureState() {
        let enabled = PanelSceneController.stateByUpdatingCommandHintMode(
            PanelSceneState(),
            enabled: true
        )
        let disabled = PanelSceneController.stateByUpdatingCommandHintMode(
            enabled,
            enabled: false
        )

        #expect(enabled.selection.isCommandHintModeEnabled)
        #expect(!disabled.selection.isCommandHintModeEnabled)
    }

    @Test
    func selectionIntentToggleAddsAndRemovesItemsRepairingPrimary() {
        let state = PanelSceneState(selection: PanelSelectionState(selectedItemID: "b"))

        let added = PanelSceneController.stateByApplyingSelectionIntent(
            state,
            itemIDs: ["a", "b", "c"],
            intent: .toggle(itemID: "c")
        )
        #expect(added.state.selection.selectedItemID == "c")
        #expect(added.state.selection.selectedItemIDs == ["b", "c"])
        #expect(added.state.selection.rangeAnchorItemID == "c")

        let removedPrimary = PanelSceneController.stateByApplyingSelectionIntent(
            added.state,
            itemIDs: ["a", "b", "c"],
            intent: .toggle(itemID: "c")
        )
        #expect(removedPrimary.state.selection.selectedItemID == "b")
        #expect(removedPrimary.state.selection.selectedItemIDs == ["b"])
        #expect(removedPrimary.state.selection.rangeAnchorItemID == "b")
    }

    @Test
    func selectionIntentRangeAndExtendUseVisualOrderAndAnchor() {
        let state = PanelSceneState(selection: PanelSelectionState(selectedItemID: "b"))

        let ranged = PanelSceneController.stateByApplyingSelectionIntent(
            state,
            itemIDs: ["a", "b", "c", "d"],
            intent: .range(toItemID: "d")
        )
        #expect(ranged.state.selection.selectedItemID == "d")
        #expect(ranged.state.selection.selectedItemIDs == ["b", "c", "d"])
        #expect(ranged.state.selection.rangeAnchorItemID == "b")

        let extendedBack = PanelSceneController.stateByApplyingSelectionIntent(
            ranged.state,
            itemIDs: ["a", "b", "c", "d"],
            intent: .extendByOffset(-1)
        )
        #expect(extendedBack.state.selection.selectedItemID == "c")
        #expect(extendedBack.state.selection.selectedItemIDs == ["b", "c"])
        #expect(extendedBack.state.selection.rangeAnchorItemID == "b")
    }

    @Test
    func contextMenuIntentPreservesSelectedSetOrReplacesUnselectedItem() {
        let state = PanelSceneState(selection: PanelSelectionState(
            selectedItemID: "a",
            selectedItemIDs: ["a", "c"],
            rangeAnchorItemID: "a"
        ))

        let selectedContext = PanelSceneController.stateByApplyingSelectionIntent(
            state,
            itemIDs: ["a", "b", "c"],
            intent: .prepareContextMenu(itemID: "c")
        )
        #expect(selectedContext.state.selection.selectedItemID == "c")
        #expect(selectedContext.state.selection.selectedItemIDs == ["a", "c"])

        let unselectedContext = PanelSceneController.stateByApplyingSelectionIntent(
            selectedContext.state,
            itemIDs: ["a", "b", "c"],
            intent: .prepareContextMenu(itemID: "b")
        )
        #expect(unselectedContext.state.selection.selectedItemID == "b")
        #expect(unselectedContext.state.selection.selectedItemIDs == ["b"])
        #expect(unselectedContext.state.selection.rangeAnchorItemID == "b")
    }

    @Test
    func listUpdatePrunesStaleSelectionAndClearsEmptyList() {
        let state = PanelSceneState(selection: PanelSelectionState(
            selectedItemID: "d",
            selectedItemIDs: ["b", "d", "missing"],
            rangeAnchorItemID: "missing"
        ))

        let pruned = PanelSceneController.stateAfterListUpdate(
            state,
            itemIDs: ["a", "b", "c"]
        )
        #expect(pruned.selection.selectedItemID == "b")
        #expect(pruned.selection.selectedItemIDs == ["b"])
        #expect(pruned.selection.rangeAnchorItemID == "b")

        let cleared = PanelSceneController.stateAfterListUpdate(pruned, itemIDs: [])
        #expect(cleared.selection.selectedItemID == nil)
        #expect(cleared.selection.selectedItemIDs.isEmpty)
        #expect(cleared.selection.rangeAnchorItemID == nil)
    }

    @Test
    func orderedSelectedItemIDsNeverUsesSetOrder() {
        let state = PanelSceneState(selection: PanelSelectionState(
            selectedItemID: "c",
            selectedItemIDs: ["c", "a"],
            rangeAnchorItemID: "c"
        ))

        #expect(PanelSceneController.orderedSelectedItemIDs(
            state,
            itemIDs: ["a", "b", "c"]
        ) == ["a", "c"])
    }
}
