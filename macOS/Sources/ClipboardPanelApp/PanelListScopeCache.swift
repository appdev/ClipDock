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
    private var accessOrder: [ClipboardListScope] = []

    public init() {}

    public subscript(scope: ClipboardListScope) -> PanelCachedListScopeState? {
        get { states[scope] }
        set {
            states[scope] = newValue
            if newValue != nil {
                recordAccess(scope)
            } else {
                accessOrder.removeAll { $0 == scope }
            }
        }
    }

    public var scopes: Set<ClipboardListScope> { Set(states.keys) }

    public mutating func recordAccess(_ scope: ClipboardListScope) {
        accessOrder.removeAll { $0 == scope }
        accessOrder.append(scope)
    }

    /// One retention decision owns both cached data and the caller's view surfaces.
    @discardableResult
    public mutating func retainRecentlyUsedScopes(
        currentScope: ClipboardListScope,
        additionalScopes: Set<ClipboardListScope> = [],
        maximumInactiveScopes: Int = 3
    ) -> Set<ClipboardListScope> {
        let allScopes = scopes.union(additionalScopes)
        let protected: Set<ClipboardListScope> = [.clipboard, currentScope]
        let recentInactive = accessOrder.filter { allScopes.contains($0) && !protected.contains($0) }
            .suffix(max(0, maximumInactiveScopes))
        let retained = protected.union(recentInactive)
        let evicted = allScopes.subtracting(retained)
        for scope in evicted {
            remove(scope)
        }
        accessOrder.removeAll { !allScopes.contains($0) }
        return evicted
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
            remove(scope)
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
        recordAccess(scope)
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
        accessOrder.removeAll { $0 != scopeToKeep }
    }

    public mutating func remove(_ scope: ClipboardListScope) {
        states.removeValue(forKey: scope)
        accessOrder.removeAll { $0 == scope }
    }

    public mutating func removePinboard(_ pinboardID: String, keeping currentScope: ClipboardListScope) {
        states = states.filter { scope, _ in
            scope.pinboardID != pinboardID || scope == currentScope
        }
        accessOrder.removeAll { $0.pinboardID == pinboardID && $0 != currentScope }
    }

    public mutating func pruneInvalidPinboards(
        validPinboardIDs: Set<String>,
        keeping currentScope: ClipboardListScope
    ) {
        states = states.filter { scope, _ in
            guard let pinboardID = scope.pinboardID else { return true }
            return validPinboardIDs.contains(pinboardID) || scope == currentScope
        }
        accessOrder.removeAll { scope in
            guard let pinboardID = scope.pinboardID else { return false }
            return !validPinboardIDs.contains(pinboardID) && scope != currentScope
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
