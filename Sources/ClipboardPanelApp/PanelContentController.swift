import Foundation

public enum PanelContentRenderInstruction: Equatable, Sendable {
    case reloadAll(scrollSelectedItem: Bool, preserveScrollPosition: Bool)
    case appendItems([RustClipboardItemSummary], preserveScrollPosition: Bool)
    case noVisualChange
}

public struct PanelContentRenderPlan: Equatable, Sendable {
    public let viewState: PanelViewState
    public let instruction: PanelContentRenderInstruction
    public let shouldClosePreview: Bool

    public init(
        viewState: PanelViewState,
        instruction: PanelContentRenderInstruction,
        shouldClosePreview: Bool
    ) {
        self.viewState = viewState
        self.instruction = instruction
        self.shouldClosePreview = shouldClosePreview
    }
}

public final class PanelContentController {
    private let sceneStore: PanelSceneRuntimeController
    private var listViewState: PanelListViewState

    public init(
        sceneStore: PanelSceneRuntimeController = PanelSceneRuntimeController(),
        listViewState: PanelListViewState = PanelListViewState()
    ) {
        self.sceneStore = sceneStore
        self.listViewState = listViewState
    }

    public var viewState: PanelViewState {
        PanelViewStateAdapter.makeViewState(
            scene: sceneStore.state,
            list: listViewState
        )
    }

    public var currentItems: [RustClipboardItemSummary] {
        listViewState.items
    }

    public var currentItemIDs: [String] {
        currentItems.map(\.id)
    }

    public var isLoadingMoreItems: Bool {
        listViewState.isLoadingMoreItems
    }

    public func updateStorageState(
        _ result: Result<RustCoreOpenResult, RustCoreError>
    ) -> PanelContentRenderPlan {
        listViewState = PanelListViewStateAdapter.openState(from: result)
        switch listViewState.presentation {
        case .databaseError:
            sceneStore.clearSelection()
        case .emptyHistory, .filteredEmpty, .items:
            sceneStore.applyListUpdate(itemIDs: currentItemIDs)
        }

        return PanelContentRenderPlan(
            viewState: viewState,
            instruction: .reloadAll(scrollSelectedItem: true, preserveScrollPosition: false),
            shouldClosePreview: false
        )
    }

    public func updateListState(
        _ result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool = false
    ) -> PanelContentRenderPlan {
        switch result {
        case .success(let listResult):
            return updateItems(
                listResult.items,
                isFiltered: isFiltered,
                totalCount: listResult.totalCount,
                hasMore: listResult.hasMore,
                append: append
            )
        case .failure(let error):
            let update = PanelListViewStateAdapter.listUpdate(
                current: listViewState,
                result: .failure(error),
                isFiltered: isFiltered,
                append: append
            )
            listViewState = update.state

            if append {
                return PanelContentRenderPlan(
                    viewState: viewState,
                    instruction: .noVisualChange,
                    shouldClosePreview: false
                )
            }

            sceneStore.clearSelection()
            return PanelContentRenderPlan(
                viewState: viewState,
                instruction: .reloadAll(scrollSelectedItem: true, preserveScrollPosition: false),
                shouldClosePreview: false
            )
        }
    }

    public func updateLoadingMoreState(_ isLoading: Bool) {
        guard listViewState.isLoadingMoreItems != isLoading else { return }
        listViewState = PanelListViewStateAdapter.stateByUpdatingLoadingMore(
            listViewState,
            isLoading: isLoading
        )
    }

    public func setPreviewPopoverEnabled(_ enabled: Bool) {
        sceneStore.setPreviewPopoverEnabled(enabled)
    }

    public func selectOffset(offset: Int) -> PanelSelectionUpdate {
        sceneStore.selectOffset(itemIDs: currentItemIDs, offset: offset)
    }

    public func selectItem(id: String) -> PanelSelectionUpdate {
        sceneStore.selectItem(itemIDs: currentItemIDs, selectedItemID: id)
    }

    public func copyItem(itemID: String) {
        sceneStore.copyItem(itemID: itemID)
    }

    public func setSearchText(_ searchText: String) {
        sceneStore.setSearchText(searchText)
    }

    public func setPinboardFilter(_ pinboardID: String?) {
        sceneStore.setPinboardFilter(pinboardID)
    }

    public func clearFilters() {
        sceneStore.clearFilters()
    }

    public func toggleSearch() -> PanelSearchToggleResult {
        sceneStore.toggleSearch()
    }

    public func focusSearch() -> PanelSearchFocusResult {
        sceneStore.focusSearch()
    }

    public func setCommandHintMode(enabled: Bool) {
        sceneStore.setCommandHintMode(enabled: enabled)
    }

    public func clearSelection() {
        sceneStore.clearSelection()
    }

    public func escapeAction(isPreviewShown: Bool) -> PanelEscapeAction {
        sceneStore.escapeAction(isPreviewShown: isPreviewShown)
    }

    public func commandCopyTarget(number: Int, visibleItemIDs: [String]) -> String? {
        sceneStore.commandCopyTarget(number: number, visibleItemIDs: visibleItemIDs)
    }

    private func updateItems(
        _ items: [RustClipboardItemSummary],
        isFiltered: Bool,
        totalCount: Int64,
        hasMore: Bool,
        append: Bool
    ) -> PanelContentRenderPlan {
        let update = PanelListViewStateAdapter.listUpdate(
            current: listViewState,
            result: .success(RustCoreListResult(items: items, totalCount: totalCount, hasMore: hasMore)),
            isFiltered: isFiltered,
            append: append
        )
        listViewState = update.state
        sceneStore.applyListUpdate(itemIDs: currentItemIDs)

        let instruction: PanelContentRenderInstruction
        if update.didAppendToExistingItems {
            instruction = .appendItems(update.appendedItems, preserveScrollPosition: true)
        } else {
            instruction = .reloadAll(scrollSelectedItem: true, preserveScrollPosition: false)
        }

        return PanelContentRenderPlan(
            viewState: viewState,
            instruction: instruction,
            shouldClosePreview: !append
        )
    }
}
