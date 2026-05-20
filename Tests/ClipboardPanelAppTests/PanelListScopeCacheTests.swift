import Testing
@testable import ClipboardPanelApp

struct PanelListScopeCacheTests {
    @Test
    func storeAppendMergesNewItemsAndDeduplicatesExistingIDs() {
        var cache = PanelListScopeCache()
        let scope = ClipboardListScope.clipboard

        cache.store(
            .success(RustCoreListResult(
                items: [makeItem(id: "a"), makeItem(id: "b")],
                totalCount: 4,
                hasMore: true
            )),
            isFiltered: false,
            append: false,
            selectedItemID: "a",
            scope: scope
        )
        cache.store(
            .success(RustCoreListResult(
                items: [makeItem(id: "b"), makeItem(id: "c")],
                totalCount: 4,
                hasMore: false
            )),
            isFiltered: false,
            append: true,
            selectedItemID: "b",
            scope: scope
        )

        #expect(cache[scope]?.result.items.map(\.id) == ["a", "b", "c"])
        #expect(cache[scope]?.result.totalCount == 4)
        #expect(cache[scope]?.result.hasMore == false)
        #expect(cache[scope]?.selectedItemID == "b")
    }

    @Test
    func selectionSnapshotStoresUpdatesPrunesAndRestoresAcrossScopes() throws {
        var cache = PanelListScopeCache()
        let clipboard = ClipboardListScope.clipboard
        let search = ClipboardListScope(normalizedSearch: "report")

        cache.store(
            .success(RustCoreListResult(
                items: [makeItem(id: "a"), makeItem(id: "b"), makeItem(id: "c")],
                totalCount: 3,
                hasMore: false
            )),
            isFiltered: false,
            append: false,
            selectedItemID: "b",
            selectionSnapshot: PanelSelectionSnapshot(
                selectedItemID: "c",
                selectedItemIDs: ["a", "c", "missing"],
                rangeAnchorItemID: "missing"
            ),
            scope: clipboard
        )
        cache.store(
            .success(RustCoreListResult(
                items: [makeItem(id: "search")],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: true,
            append: false,
            selectedItemID: "search",
            scope: search
        )

        #expect(cache[clipboard]?.selectionSnapshot == PanelSelectionSnapshot(
            selectedItemID: "c",
            selectedItemIDs: ["a", "c"],
            rangeAnchorItemID: "c"
        ))
        #expect(cache[search]?.selectionSnapshot.selectedItemID == "search")

        cache.updateSelectionSnapshot(
            PanelSelectionSnapshot(
                selectedItemID: "b",
                selectedItemIDs: ["b", "c"],
                rangeAnchorItemID: "c"
            ),
            for: clipboard
        )

        let snapshot = try #require(cache[clipboard]?.selectionSnapshot)
        #expect(snapshot.selectedItemID == "b")
        #expect(snapshot.selectedItemIDs == ["b", "c"])
        #expect(snapshot.rangeAnchorItemID == "c")
    }

    @Test
    func failureRemovesCachedScope() {
        var cache = PanelListScopeCache()
        let scope = ClipboardListScope(normalizedSearch: "report")
        cache[scope] = PanelCachedListScopeState(
            result: RustCoreListResult(items: [makeItem(id: "a")], totalCount: 1, hasMore: false),
            isFiltered: true,
            selectedItemID: "a"
        )

        cache.store(
            .failure(RustCoreError(
                code: "db",
                messageKey: "db",
                recoverable: true,
                message: "failed"
            )),
            isFiltered: true,
            append: false,
            selectedItemID: nil,
            scope: scope
        )

        #expect(cache[scope] == nil)
    }

    @Test
    func itemTypeParticipatesInScopeIdentity() {
        var cache = PanelListScopeCache()
        let textSearch = ClipboardListScope(normalizedSearch: "#FF00AA")
        let colorSearch = ClipboardListScope(itemType: "color", normalizedSearch: "#FF00AA")

        cache[textSearch] = PanelCachedListScopeState(
            result: RustCoreListResult(items: [makeItem(id: "text")], totalCount: 1, hasMore: false),
            isFiltered: true,
            selectedItemID: "text"
        )
        cache[colorSearch] = PanelCachedListScopeState(
            result: RustCoreListResult(items: [makeItem(id: "color")], totalCount: 1, hasMore: false),
            isFiltered: true,
            selectedItemID: "color"
        )

        #expect(cache[textSearch]?.result.items.map(\.id) == ["text"])
        #expect(cache[colorSearch]?.result.items.map(\.id) == ["color"])
        #expect(textSearch != colorSearch)
    }

    @Test
    func pinboardPruningKeepsCurrentScopeAndValidPinboards() {
        var cache = PanelListScopeCache()
        let clipboard = ClipboardListScope.clipboard
        let currentDeletedPinboard = ClipboardListScope(pinboardID: "deleted")
        let stalePinboard = ClipboardListScope(pinboardID: "stale")
        let validPinboard = ClipboardListScope(pinboardID: "valid")

        for scope in [clipboard, currentDeletedPinboard, stalePinboard, validPinboard] {
            cache[scope] = PanelCachedListScopeState(
                result: RustCoreListResult(
                    items: [makeItem(id: scope.pinboardID ?? "clipboard")],
                    totalCount: 1,
                    hasMore: false
                ),
                isFiltered: scope.isFiltered,
                selectedItemID: nil
            )
        }

        cache.pruneInvalidPinboards(
            validPinboardIDs: ["valid"],
            keeping: currentDeletedPinboard
        )

        #expect(cache[clipboard] != nil)
        #expect(cache[currentDeletedPinboard] != nil)
        #expect(cache[validPinboard] != nil)
        #expect(cache[stalePinboard] == nil)
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
        sourceAppIconHeaderColor: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 0,
        isPinned: false,
        sizeBytes: 1,
        previewState: "ready",
        payloadState: "ready"
    )
}
