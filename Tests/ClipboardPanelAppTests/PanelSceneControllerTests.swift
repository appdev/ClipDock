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

        #expect(PanelSceneController.escapeAction(state, isPreviewShown: false) == .clearSearch)
        #expect(PanelSceneController.escapeAction(state, isPreviewShown: true) == .closePreview)
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
            selection: PanelSelectionState(selectedItemID: "selected")
        )

        let nextState = PanelSceneController.stateByClearingSelection(state)

        #expect(nextState.selection.selectedItemID == nil)
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
}
