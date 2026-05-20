import Foundation

public struct PanelCachedListScopeState: Equatable, Sendable {
    public var result: RustCoreListResult
    public var isFiltered: Bool
    public var selectionSnapshot: PanelSelectionSnapshot

    public var selectedItemID: String? {
        get { selectionSnapshot.selectedItemID }
        set { selectionSnapshot.selectedItemID = newValue }
    }

    public init(
        result: RustCoreListResult,
        isFiltered: Bool,
        selectedItemID: String? = nil,
        selectionSnapshot: PanelSelectionSnapshot? = nil
    ) {
        self.result = result
        self.isFiltered = isFiltered
        self.selectionSnapshot = selectionSnapshot
            ?? PanelSelectionSnapshot(
                selectedItemID: selectedItemID,
                selectedItemIDs: selectedItemID.map { Set([$0]) } ?? [],
                rangeAnchorItemID: selectedItemID
            )
        self.selectionSnapshot = Self.repairedSnapshot(
            self.selectionSnapshot,
            itemIDs: result.items.map(\.id)
        )
    }

    public static func repairedSnapshot(
        _ snapshot: PanelSelectionSnapshot,
        itemIDs: [String]
    ) -> PanelSelectionSnapshot {
        guard !itemIDs.isEmpty else { return PanelSelectionSnapshot() }

        let validIDs = Set(itemIDs)
        var selectedIDs = snapshot.selectedItemIDs.intersection(validIDs)
        if let selectedItemID = snapshot.selectedItemID,
           validIDs.contains(selectedItemID) {
            selectedIDs.insert(selectedItemID)
        }
        guard !selectedIDs.isEmpty else { return PanelSelectionSnapshot() }

        let primaryID = snapshot.selectedItemID.flatMap {
            selectedIDs.contains($0) ? $0 : nil
        } ?? itemIDs.first { selectedIDs.contains($0) }
        let anchorID = snapshot.rangeAnchorItemID.flatMap {
            selectedIDs.contains($0) ? $0 : nil
        } ?? primaryID

        return PanelSelectionSnapshot(
            selectedItemID: primaryID,
            selectedItemIDs: selectedIDs,
            rangeAnchorItemID: anchorID
        )
    }
}

public struct PanelListScopeCache: Equatable, Sendable {
    private var states: [ClipboardListScope: PanelCachedListScopeState] = [:]

    public init() {}

    public subscript(scope: ClipboardListScope) -> PanelCachedListScopeState? {
        get { states[scope] }
        set { states[scope] = newValue }
    }

    public mutating func store(
        _ result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool,
        selectedItemID: String?,
        selectionSnapshot: PanelSelectionSnapshot? = nil,
        scope: ClipboardListScope
    ) {
        guard case .success(let listResult) = result else {
            states.removeValue(forKey: scope)
            return
        }

        let cachedResult: RustCoreListResult
        if append, let previous = states[scope]?.result {
            cachedResult = mergedResult(previous: previous, next: listResult)
        } else {
            cachedResult = listResult
        }

        states[scope] = PanelCachedListScopeState(
            result: cachedResult,
            isFiltered: isFiltered,
            selectedItemID: selectedItemID,
            selectionSnapshot: selectionSnapshot
        )
    }

    public mutating func updateSelectedItemID(_ selectedItemID: String?, for scope: ClipboardListScope) {
        guard var state = states[scope] else { return }
        state.selectedItemID = selectedItemID
        if let selectedItemID {
            state.selectionSnapshot.selectedItemIDs = [selectedItemID]
            state.selectionSnapshot.rangeAnchorItemID = selectedItemID
        } else {
            state.selectionSnapshot.selectedItemIDs = []
            state.selectionSnapshot.rangeAnchorItemID = nil
        }
        state.selectionSnapshot = PanelCachedListScopeState.repairedSnapshot(
            state.selectionSnapshot,
            itemIDs: state.result.items.map(\.id)
        )
        states[scope] = state
    }

    public mutating func updateSelectionSnapshot(
        _ snapshot: PanelSelectionSnapshot,
        for scope: ClipboardListScope
    ) {
        guard var state = states[scope] else { return }
        state.selectionSnapshot = PanelCachedListScopeState.repairedSnapshot(
            snapshot,
            itemIDs: state.result.items.map(\.id)
        )
        states[scope] = state
    }

    public mutating func keepOnly(_ scopeToKeep: ClipboardListScope) {
        states = states.filter { scope, _ in scope == scopeToKeep }
    }

    public mutating func remove(_ scope: ClipboardListScope) {
        states.removeValue(forKey: scope)
    }

    public mutating func removePinboard(_ pinboardID: String, keeping currentScope: ClipboardListScope) {
        states = states.filter { scope, _ in
            scope.pinboardID != pinboardID || scope == currentScope
        }
    }

    public mutating func pruneInvalidPinboards(
        validPinboardIDs: Set<String>,
        keeping currentScope: ClipboardListScope
    ) {
        states = states.filter { scope, _ in
            guard let pinboardID = scope.pinboardID else { return true }
            return validPinboardIDs.contains(pinboardID) || scope == currentScope
        }
    }

    private func mergedResult(
        previous: RustCoreListResult,
        next: RustCoreListResult
    ) -> RustCoreListResult {
        let existingIDs = Set(previous.items.map(\.id))
        let appendedItems = next.items.filter { !existingIDs.contains($0.id) }
        return RustCoreListResult(
            items: previous.items + appendedItems,
            totalCount: next.totalCount,
            hasMore: next.hasMore
        )
    }
}
