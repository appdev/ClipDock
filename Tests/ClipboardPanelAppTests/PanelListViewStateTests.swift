import Testing
@testable import ClipboardPanelApp

struct PanelListViewStateTests {
    @Test
    func openStateMapsEmptyHistoryAndDatabaseError() {
        let empty = PanelListViewStateAdapter.openState(
            from: .success(RustCoreOpenResult(
                databasePath: "/tmp/test.sqlite",
                schemaVersion: 1,
                itemCount: 0,
                items: []
            ))
        )
        let failure = PanelListViewStateAdapter.openState(
            from: .failure(makeError(message: "db unavailable"))
        )

        #expect(empty.presentation == .emptyHistory)
        #expect(failure.presentation == PanelListPresentation.databaseError)
    }

    @Test
    func listUpdateMapsFilteredEmptyAndLoadedItems() {
        let filteredEmpty = PanelListViewStateAdapter.listUpdate(
            current: PanelListViewState(),
            result: .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false)),
            isFiltered: true,
            append: false
        )
        let loaded = PanelListViewStateAdapter.listUpdate(
            current: PanelListViewState(),
            result: .success(RustCoreListResult(
                items: [makeItem(id: "a")],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false,
            append: false
        )

        #expect(filteredEmpty.state.presentation == .filteredEmpty)
        #expect(loaded.state.items.map(\.id) == ["a"])
    }

    @Test
    func appendUpdateDeduplicatesExistingItems() {
        let current = PanelListViewState(
            presentation: .items([makeItem(id: "a"), makeItem(id: "b")]),
            totalCount: 2,
            hasMoreItems: true,
            isLoadingMoreItems: true
        )

        let update = PanelListViewStateAdapter.listUpdate(
            current: current,
            result: .success(RustCoreListResult(
                items: [makeItem(id: "b"), makeItem(id: "c")],
                totalCount: 3,
                hasMore: false
            )),
            isFiltered: false,
            append: true
        )

        #expect(update.didAppendToExistingItems)
        #expect(update.appendedItems.map(\.id) == ["c"])
        #expect(update.state.items.map(\.id) == ["a", "b", "c"])
        #expect(!update.state.isLoadingMoreItems)
    }

    @Test
    func appendFailureKeepsCurrentItemsAndStopsLoading() {
        let current = PanelListViewState(
            presentation: .items([makeItem(id: "a")]),
            totalCount: 1,
            hasMoreItems: true,
            isLoadingMoreItems: true
        )

        let update = PanelListViewStateAdapter.listUpdate(
            current: current,
            result: .failure(makeError(message: "load more failed")),
            isFiltered: false,
            append: true
        )

        #expect(update.state.items.map { $0.id } == ["a"])
        #expect(!update.state.isLoadingMoreItems)
    }

    @Test
    func loadingStateUpdatesPurely() {
        let state = PanelListViewStateAdapter.stateByUpdatingLoadingMore(
            PanelListViewState(),
            isLoading: true
        )

        #expect(state.isLoadingMoreItems)
    }
}

private func makeItem(id: String) -> RustClipboardItemSummary {
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

private func makeError(message: String) -> RustCoreError {
    RustCoreError(
        code: "test",
        messageKey: "test",
        recoverable: true,
        message: message
    )
}
