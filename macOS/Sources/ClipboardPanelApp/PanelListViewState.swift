import Foundation

public enum PanelListPresentation: Equatable, Sendable {
    case items([RustClipboardItemSummary])
    case emptyHistory
    case filteredEmpty
    case databaseError
}

public struct PanelListViewState: Equatable, Sendable {
    public var presentation: PanelListPresentation
    public var totalCount: Int64
    public var hasMoreItems: Bool
    public var isLoadingMoreItems: Bool

    public init(
        presentation: PanelListPresentation = .emptyHistory,
        totalCount: Int64 = 0,
        hasMoreItems: Bool = false,
        isLoadingMoreItems: Bool = false
    ) {
        self.presentation = presentation
        self.totalCount = totalCount
        self.hasMoreItems = hasMoreItems
        self.isLoadingMoreItems = isLoadingMoreItems
    }

    public var items: [RustClipboardItemSummary] {
        switch presentation {
        case .items(let items):
            return items
        case .emptyHistory, .filteredEmpty, .databaseError:
            return []
        }
    }
}

public struct PanelListRenderUpdate: Equatable, Sendable {
    public let state: PanelListViewState
    public let appendedItems: [RustClipboardItemSummary]
    public let didAppendToExistingItems: Bool

    public init(
        state: PanelListViewState,
        appendedItems: [RustClipboardItemSummary],
        didAppendToExistingItems: Bool
    ) {
        self.state = state
        self.appendedItems = appendedItems
        self.didAppendToExistingItems = didAppendToExistingItems
    }
}

public enum PanelListViewStateAdapter {
    public static func openState(
        from result: Result<RustCoreOpenResult, RustCoreError>
    ) -> PanelListViewState {
        switch result {
        case .success(let openResult):
            return stateForLoadedItems(
                items: openResult.items,
                isFiltered: false,
                totalCount: openResult.itemCount,
                hasMore: Int64(openResult.items.count) < openResult.itemCount
            )
        case .failure:
            return PanelListViewState(presentation: .databaseError)
        }
    }

    public static func listUpdate(
        current state: PanelListViewState,
        result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool
    ) -> PanelListRenderUpdate {
        switch result {
        case .success(let listResult):
            return updateForLoadedItems(
                current: state,
                items: listResult.items,
                isFiltered: isFiltered,
                totalCount: listResult.totalCount,
                hasMore: listResult.hasMore,
                append: append
            )
        case .failure:
            if append {
                var nextState = state
                nextState.isLoadingMoreItems = false
                return PanelListRenderUpdate(
                    state: nextState,
                    appendedItems: [],
                    didAppendToExistingItems: false
                )
            }

            return PanelListRenderUpdate(
                state: PanelListViewState(presentation: .databaseError),
                appendedItems: [],
                didAppendToExistingItems: false
            )
        }
    }

    public static func stateByUpdatingLoadingMore(
        _ state: PanelListViewState,
        isLoading: Bool
    ) -> PanelListViewState {
        var nextState = state
        nextState.isLoadingMoreItems = isLoading
        return nextState
    }

    private static func updateForLoadedItems(
        current state: PanelListViewState,
        items: [RustClipboardItemSummary],
        isFiltered: Bool,
        totalCount: Int64,
        hasMore: Bool,
        append: Bool
    ) -> PanelListRenderUpdate {
        let nextState: PanelListViewState
        let appendedItems: [RustClipboardItemSummary]

        if append {
            let existingItems = state.items
            let existingIDs = Set(existingItems.map(\.id))
            appendedItems = items.filter { !existingIDs.contains($0.id) }
            let mergedItems = existingItems + appendedItems
            nextState = stateForLoadedItems(
                items: mergedItems,
                isFiltered: isFiltered,
                totalCount: totalCount,
                hasMore: hasMore
            )
        } else {
            appendedItems = []
            nextState = stateForLoadedItems(
                items: items,
                isFiltered: isFiltered,
                totalCount: totalCount,
                hasMore: hasMore
            )
        }

        return PanelListRenderUpdate(
            state: nextState,
            appendedItems: appendedItems,
            didAppendToExistingItems: append
        )
    }

    private static func stateForLoadedItems(
        items: [RustClipboardItemSummary],
        isFiltered: Bool,
        totalCount: Int64,
        hasMore: Bool
    ) -> PanelListViewState {
        let presentation: PanelListPresentation
        if items.isEmpty {
            presentation = isFiltered ? .filteredEmpty : .emptyHistory
        } else {
            presentation = .items(items)
        }

        return PanelListViewState(
            presentation: presentation,
            totalCount: totalCount,
            hasMoreItems: hasMore,
            isLoadingMoreItems: false
        )
    }
}
