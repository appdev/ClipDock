import Foundation

public struct PanelCachedListScopeState: Equatable, Sendable {
    public var result: RustCoreListResult
    public var isFiltered: Bool
    public var selectedItemID: String?

    public init(
        result: RustCoreListResult,
        isFiltered: Bool,
        selectedItemID: String?
    ) {
        self.result = result
        self.isFiltered = isFiltered
        self.selectedItemID = selectedItemID
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
            selectedItemID: selectedItemID
        )
    }

    public mutating func updateSelectedItemID(_ selectedItemID: String?, for scope: ClipboardListScope) {
        guard var state = states[scope] else { return }
        state.selectedItemID = selectedItemID
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
