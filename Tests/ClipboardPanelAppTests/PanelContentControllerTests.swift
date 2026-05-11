import Testing
@testable import ClipboardPanelApp

struct PanelContentControllerTests {
    @Test
    func storageUpdateProducesReloadPlanAndSelectsFirstVisibleItem() {
        let controller = PanelContentController()

        let plan = controller.updateStorageState(
            .success(RustCoreOpenResult(
                databasePath: "/tmp/test.sqlite",
                schemaVersion: 1,
                itemCount: 2,
                items: [makePanelContentItem(id: "a"), makePanelContentItem(id: "b")]
            ))
        )

        #expect(plan.instruction == .reloadAll(scrollSelectedItem: true, preserveScrollPosition: false))
        #expect(!plan.shouldClosePreview)
        #expect(plan.viewState.selectedItemID == "a")
        #expect(controller.currentItemIDs == ["a", "b"])
    }

    @Test
    func storageFailureClearsSelectionAndShowsDatabaseError() {
        let controller = PanelContentController(
            sceneStore: PanelSceneRuntimeController(
                state: PanelSceneState(selection: PanelSelectionState(selectedItemID: "selected"))
            )
        )

        let plan = controller.updateStorageState(
            .failure(makePanelContentError(message: "db unavailable"))
        )

        #expect(plan.viewState.list.presentation == .databaseError)
        #expect(plan.viewState.selectedItemID == nil)
    }

    @Test
    func appendUpdateReturnsOnlyNewItemsAndKeepsPreviewOpen() {
        let existing = makePanelContentItem(id: "a")
        let appended = makePanelContentItem(id: "b")
        let controller = PanelContentController(
            sceneStore: PanelSceneRuntimeController(
                state: PanelSceneState(selection: PanelSelectionState(selectedItemID: "a"))
            ),
            listViewState: PanelListViewState(
                presentation: .items([existing]),
                totalCount: 1,
                hasMoreItems: true,
                isLoadingMoreItems: true
            )
        )

        let plan = controller.updateListState(
            .success(RustCoreListResult(
                items: [existing, appended],
                totalCount: 2,
                hasMore: false
            )),
            isFiltered: false,
            append: true
        )

        #expect(plan.instruction == .appendItems([appended], preserveScrollPosition: true))
        #expect(!plan.shouldClosePreview)
        #expect(plan.viewState.list.items.map(\.id) == ["a", "b"])
        #expect(plan.viewState.selectedItemID == "a")
        #expect(!controller.isLoadingMoreItems)
    }

    @Test
    func replacingListReloadsAndClosesPreview() {
        let controller = PanelContentController()

        let plan = controller.updateListState(
            .success(RustCoreListResult(
                items: [makePanelContentItem(id: "next")],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false,
            append: false
        )

        #expect(plan.instruction == .reloadAll(scrollSelectedItem: true, preserveScrollPosition: false))
        #expect(plan.shouldClosePreview)
        #expect(plan.viewState.selectedItemID == "next")
    }

    @Test
    func appendFailureKeepsCurrentItemsAndStopsLoadingWithoutReload() {
        let controller = PanelContentController(
            listViewState: PanelListViewState(
                presentation: .items([makePanelContentItem(id: "a")]),
                totalCount: 1,
                hasMoreItems: true,
                isLoadingMoreItems: true
            )
        )

        let plan = controller.updateListState(
            .failure(makePanelContentError(message: "load more failed")),
            isFiltered: false,
            append: true
        )

        #expect(plan.instruction == .noVisualChange)
        #expect(controller.currentItemIDs == ["a"])
        #expect(!controller.isLoadingMoreItems)
    }
}

private func makePanelContentItem(id: String) -> RustClipboardItemSummary {
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

private func makePanelContentError(message: String) -> RustCoreError {
    RustCoreError(
        code: "test",
        messageKey: "test",
        recoverable: true,
        message: message
    )
}
