import Testing
@testable import ClipboardPanelApp

struct PanelViewStateTests {
    @Test
    func viewStateMapsToolbarSelectionAndSearchVisibility() {
        let scene = PanelSceneState(
            query: PanelQueryState(searchText: "report", pinboardID: "default", isSearchVisible: true),
            selection: PanelSelectionState(selectedItemID: "item-1", isCommandHintModeEnabled: true),
            preview: PanelPreviewState(isPopoverEnabled: false)
        )
        let list = PanelListViewState(
            presentation: .items([]),
            totalCount: 1,
            hasMoreItems: false,
            isLoadingMoreItems: false
        )

        let viewState = PanelViewStateAdapter.makeViewState(scene: scene, list: list)

        #expect(viewState.toolbar.searchText == "report")
        #expect(viewState.toolbar.isSearchVisible)
        #expect(viewState.toolbar.selectedPinboardID == "default")
        #expect(viewState.toolbar.clearActionTitle == "清空当前结果")
        #expect(viewState.selectedItemID == "item-1")
        #expect(!viewState.isPreviewPopoverEnabled)
        #expect(viewState.isCommandHintModeEnabled)
    }

    @Test
    func viewStateUsesHistoryTitleWhenFiltersAreEmpty() {
        let viewState = PanelViewStateAdapter.makeViewState(
            scene: PanelSceneState(),
            list: PanelListViewState()
        )

        #expect(viewState.toolbar.clearActionTitle == "清空历史")
    }

    @Test
    func viewStateTreatsPinboardAsCurrentResultScope() {
        let viewState = PanelViewStateAdapter.makeViewState(
            scene: PanelSceneState(
                query: PanelQueryState(pinboardID: "default")
            ),
            list: PanelListViewState()
        )

        #expect(viewState.toolbar.selectedPinboardID == "default")
        #expect(viewState.toolbar.clearActionTitle == "清空当前结果")
    }
}
