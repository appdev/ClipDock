import Foundation

public enum PanelFocusTarget: Equatable, Sendable {
    case searchField
    case panel
}

public struct PanelQueryState: Equatable, Sendable {
    public var searchText: String
    public var itemType: String?
    public var pinboardID: String?
    public var isSearchVisible: Bool

    public init(
        searchText: String = "",
        itemType: String? = nil,
        pinboardID: String? = nil,
        isSearchVisible: Bool = false
    ) {
        self.searchText = searchText
        self.itemType = itemType
        self.pinboardID = pinboardID
        self.isSearchVisible = isSearchVisible
    }
}

public struct PanelSelectionState: Equatable, Sendable {
    public var selectedItemID: String?
    public var selectedItemIDs: Set<String>
    public var rangeAnchorItemID: String?
    public var isCommandHintModeEnabled: Bool

    public init(
        selectedItemID: String? = nil,
        selectedItemIDs: Set<String> = [],
        rangeAnchorItemID: String? = nil,
        isCommandHintModeEnabled: Bool = false
    ) {
        var normalizedSelectedIDs = selectedItemIDs
        if let selectedItemID {
            normalizedSelectedIDs.insert(selectedItemID)
        }

        self.selectedItemID = selectedItemID
        self.selectedItemIDs = selectedItemID == nil ? [] : normalizedSelectedIDs
        self.rangeAnchorItemID = selectedItemID == nil ? nil : (rangeAnchorItemID ?? selectedItemID)
        self.isCommandHintModeEnabled = isCommandHintModeEnabled
    }
}

public struct PanelSelectionSnapshot: Equatable, Sendable {
    public var selectedItemID: String?
    public var selectedItemIDs: Set<String>
    public var rangeAnchorItemID: String?

    public init(
        selectedItemID: String? = nil,
        selectedItemIDs: Set<String> = [],
        rangeAnchorItemID: String? = nil
    ) {
        self.selectedItemID = selectedItemID
        self.selectedItemIDs = selectedItemIDs
        self.rangeAnchorItemID = rangeAnchorItemID
    }
}

public enum PanelSelectionIntent: Equatable, Sendable {
    case replace(itemID: String, scrollIntoView: Bool)
    case toggle(itemID: String)
    case range(toItemID: String)
    case extendByOffset(Int)
    case prepareContextMenu(itemID: String)
}

public struct PanelPreviewState: Equatable, Sendable {
    public var isPopoverEnabled: Bool

    public init(isPopoverEnabled: Bool = true) {
        self.isPopoverEnabled = isPopoverEnabled
    }
}

public struct PanelSceneState: Equatable, Sendable {
    public var query: PanelQueryState
    public var selection: PanelSelectionState
    public var preview: PanelPreviewState

    public init(
        query: PanelQueryState = PanelQueryState(),
        selection: PanelSelectionState = PanelSelectionState(),
        preview: PanelPreviewState = PanelPreviewState()
    ) {
        self.query = query
        self.selection = selection
        self.preview = preview
    }
}

public struct PanelSearchToggleResult: Equatable, Sendable {
    public let state: PanelSceneState
    public let focusTarget: PanelFocusTarget?

    public init(state: PanelSceneState, focusTarget: PanelFocusTarget?) {
        self.state = state
        self.focusTarget = focusTarget
    }
}

public struct PanelSelectionUpdate: Equatable, Sendable {
    public let state: PanelSceneState
    public let shouldClosePreview: Bool
    public let didChangeSelection: Bool

    public init(
        state: PanelSceneState,
        shouldClosePreview: Bool,
        didChangeSelection: Bool
    ) {
        self.state = state
        self.shouldClosePreview = shouldClosePreview
        self.didChangeSelection = didChangeSelection
    }
}

public struct PanelSearchFocusResult: Equatable, Sendable {
    public let state: PanelSceneState
    public let focusTarget: PanelFocusTarget

    public init(state: PanelSceneState, focusTarget: PanelFocusTarget) {
        self.state = state
        self.focusTarget = focusTarget
    }
}

public struct PanelStartSearchResult: Equatable, Sendable {
    public let state: PanelSceneState
    public let focusTarget: PanelFocusTarget

    public init(state: PanelSceneState, focusTarget: PanelFocusTarget) {
        self.state = state
        self.focusTarget = focusTarget
    }
}

public final class PanelSceneRuntimeController {
    public private(set) var state: PanelSceneState

    public init(state: PanelSceneState = PanelSceneState()) {
        self.state = state
    }

    public func applyListUpdate(itemIDs: [String]) {
        state = PanelSceneController.stateAfterListUpdate(state, itemIDs: itemIDs)
    }

    public func selectOffset(itemIDs: [String], offset: Int) -> PanelSelectionUpdate {
        let update = PanelSceneController.stateBySelectingOffset(
            state,
            itemIDs: itemIDs,
            offset: offset
        )
        state = update.state
        return update
    }

    public func applySelectionIntent(
        itemIDs: [String],
        intent: PanelSelectionIntent
    ) -> PanelSelectionUpdate {
        let update = PanelSceneController.stateByApplyingSelectionIntent(
            state,
            itemIDs: itemIDs,
            intent: intent
        )
        state = update.state
        return update
    }

    public func restoreSelectionSnapshot(
        _ snapshot: PanelSelectionSnapshot,
        itemIDs: [String]
    ) {
        state = PanelSceneController.stateByRestoringSelectionSnapshot(
            state,
            snapshot: snapshot,
            itemIDs: itemIDs
        )
    }

    public func selectItem(itemIDs: [String], selectedItemID: String) -> PanelSelectionUpdate {
        let update = PanelSceneController.stateBySelectingItem(
            state,
            itemIDs: itemIDs,
            selectedItemID: selectedItemID
        )
        state = update.state
        return update
    }

    public func copyItem(itemID: String) {
        state = PanelSceneController.stateByCopyingItem(state, itemID: itemID)
    }

    public func collapseSelectionToPrimary() -> PanelSelectionUpdate {
        let update = PanelSceneController.stateByCollapsingSelectionToPrimary(state)
        state = update.state
        return update
    }

    public func clearSelection() {
        state = PanelSceneController.stateByClearingSelection(state)
    }

    public func setSearchText(_ searchText: String) {
        state = PanelSceneController.stateBySettingSearchText(state, searchText: searchText)
    }

    public func setPinboardFilter(_ pinboardID: String?) {
        state = PanelSceneController.stateBySettingPinboardFilter(state, pinboardID: pinboardID)
    }

    public func setItemTypeFilter(_ itemType: String?) {
        state = PanelSceneController.stateBySettingItemTypeFilter(state, itemType: itemType)
    }

    public func setScopeFilters(itemType: String?, pinboardID: String?) {
        state = PanelSceneController.stateBySettingScopeFilters(
            state,
            itemType: itemType,
            pinboardID: pinboardID
        )
    }

    public func clearFilters() {
        state = PanelSceneController.stateByClearingFilters(state)
    }

    public func toggleSearch() -> PanelSearchToggleResult {
        let result = PanelSceneController.searchToggleResult(state)
        state = result.state
        return result
    }

    public func focusSearch() -> PanelSearchFocusResult {
        let result = PanelSceneController.focusSearchResult(state)
        state = result.state
        return result
    }

    public func startSearch(initialText: String) -> PanelStartSearchResult {
        let result = PanelSceneController.startSearchResult(state, initialText: initialText)
        state = result.state
        return result
    }

    public func dismissSearch() {
        state = PanelSceneController.stateByDismissingSearch(state)
    }

    public func setCommandHintMode(enabled: Bool) {
        state = PanelSceneController.stateByUpdatingCommandHintMode(state, enabled: enabled)
    }

    public func setPreviewPopoverEnabled(_ enabled: Bool) {
        state = PanelSceneController.stateBySettingPreviewPopoverEnabled(state, enabled: enabled)
    }

    public func escapeAction(isPreviewShown: Bool) -> PanelEscapeAction {
        PanelSceneController.escapeAction(state, isPreviewShown: isPreviewShown)
    }

    public func commandCopyTarget(number: Int, visibleItemIDs: [String]) -> String? {
        PanelSceneController.commandCopyTarget(number: number, visibleItemIDs: visibleItemIDs)
    }
}

public enum PanelSceneController {
    public static func stateAfterListUpdate(
        _ state: PanelSceneState,
        itemIDs: [String]
    ) -> PanelSceneState {
        var nextState = state
        nextState.selection = repairedSelectionAfterListUpdate(
            state.selection,
            itemIDs: itemIDs
        )
        return nextState
    }

    public static func stateBySelectingOffset(
        _ state: PanelSceneState,
        itemIDs: [String],
        offset: Int
    ) -> PanelSelectionUpdate {
        guard let nextID = PanelInteractionPlanner.selectedIDAfterOffset(
            currentSelectedID: state.selection.selectedItemID,
            itemIDs: itemIDs,
            offset: offset
        ) else {
            return PanelSelectionUpdate(
                state: state,
                shouldClosePreview: false,
                didChangeSelection: false
            )
        }

        return stateByApplyingSelectionIntent(
            state,
            itemIDs: itemIDs,
            intent: .replace(itemID: nextID, scrollIntoView: true)
        )
    }

    public static func stateBySelectingItem(
        _ state: PanelSceneState,
        itemIDs: [String],
        selectedItemID: String
    ) -> PanelSelectionUpdate {
        stateByApplyingSelectionIntent(
            state,
            itemIDs: itemIDs,
            intent: .replace(itemID: selectedItemID, scrollIntoView: true)
        )
    }

    public static func stateByApplyingSelectionIntent(
        _ state: PanelSceneState,
        itemIDs: [String],
        intent: PanelSelectionIntent
    ) -> PanelSelectionUpdate {
        switch intent {
        case .replace(let selectedItemID, _):
            return stateByReplacingSelection(state, itemIDs: itemIDs, selectedItemID: selectedItemID)
        case .toggle(let itemID):
            return stateByTogglingSelection(state, itemIDs: itemIDs, itemID: itemID)
        case .range(let toItemID):
            return stateBySelectingRange(state, itemIDs: itemIDs, toItemID: toItemID)
        case .extendByOffset(let offset):
            return stateByExtendingSelection(state, itemIDs: itemIDs, offset: offset)
        case .prepareContextMenu(let itemID):
            return stateByPreparingContextMenu(state, itemIDs: itemIDs, itemID: itemID)
        }
    }

    public static func orderedSelectedItemIDs(
        _ state: PanelSceneState,
        itemIDs: [String]
    ) -> [String] {
        itemIDs.filter { state.selection.selectedItemIDs.contains($0) }
    }

    public static func stateByRestoringSelectionSnapshot(
        _ state: PanelSceneState,
        snapshot: PanelSelectionSnapshot,
        itemIDs: [String]
    ) -> PanelSceneState {
        var nextState = state
        nextState.selection = repairedSelection(
            selectedItemID: snapshot.selectedItemID,
            selectedItemIDs: snapshot.selectedItemIDs,
            rangeAnchorItemID: snapshot.rangeAnchorItemID,
            itemIDs: itemIDs,
            selectsFirstWhenEmpty: false,
            isCommandHintModeEnabled: state.selection.isCommandHintModeEnabled
        )
        return nextState
    }

    public static func selectionSnapshot(_ state: PanelSceneState) -> PanelSelectionSnapshot {
        PanelSelectionSnapshot(
            selectedItemID: state.selection.selectedItemID,
            selectedItemIDs: state.selection.selectedItemIDs,
            rangeAnchorItemID: state.selection.rangeAnchorItemID
        )
    }

    private static func stateByReplacingSelection(
        _ state: PanelSceneState,
        itemIDs: [String],
        selectedItemID: String
    ) -> PanelSelectionUpdate {
        guard itemIDs.contains(selectedItemID) else {
            return PanelSelectionUpdate(
                state: state,
                shouldClosePreview: false,
                didChangeSelection: false
            )
        }

        let didChangeSelection = state.selection.selectedItemID != selectedItemID
            || state.selection.selectedItemIDs != Set([selectedItemID])
            || state.selection.rangeAnchorItemID != selectedItemID
        var nextState = state
        nextState.selection.selectedItemID = selectedItemID
        nextState.selection.selectedItemIDs = [selectedItemID]
        nextState.selection.rangeAnchorItemID = selectedItemID
        return PanelSelectionUpdate(
            state: nextState,
            shouldClosePreview: didChangeSelection,
            didChangeSelection: didChangeSelection
        )
    }

    private static func stateByTogglingSelection(
        _ state: PanelSceneState,
        itemIDs: [String],
        itemID: String
    ) -> PanelSelectionUpdate {
        guard itemIDs.contains(itemID) else {
            return unchangedSelectionUpdate(state)
        }

        var selectedIDs = state.selection.selectedItemIDs
        var nextPrimaryID: String?
        var nextAnchorID: String?
        if selectedIDs.contains(itemID) {
            selectedIDs.remove(itemID)
            nextPrimaryID = state.selection.selectedItemID == itemID
                ? itemIDs.first { selectedIDs.contains($0) }
                : state.selection.selectedItemID
            nextAnchorID = state.selection.rangeAnchorItemID == itemID
                ? nextPrimaryID
                : state.selection.rangeAnchorItemID
        } else {
            selectedIDs.insert(itemID)
            nextPrimaryID = itemID
            nextAnchorID = itemID
        }

        return selectionUpdate(
            from: state,
            selectedItemID: nextPrimaryID,
            selectedItemIDs: selectedIDs,
            rangeAnchorItemID: nextAnchorID,
            itemIDs: itemIDs
        )
    }

    private static func stateBySelectingRange(
        _ state: PanelSceneState,
        itemIDs: [String],
        toItemID: String
    ) -> PanelSelectionUpdate {
        guard let targetIndex = itemIDs.firstIndex(of: toItemID) else {
            return unchangedSelectionUpdate(state)
        }

        let anchorID = [state.selection.rangeAnchorItemID, state.selection.selectedItemID]
            .compactMap { $0 }
            .first { itemIDs.contains($0) } ?? toItemID
        guard let anchorIndex = itemIDs.firstIndex(of: anchorID) else {
            return unchangedSelectionUpdate(state)
        }

        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        let selectedIDs = Set(itemIDs[bounds])
        return selectionUpdate(
            from: state,
            selectedItemID: toItemID,
            selectedItemIDs: selectedIDs,
            rangeAnchorItemID: anchorID,
            itemIDs: itemIDs
        )
    }

    private static func stateByExtendingSelection(
        _ state: PanelSceneState,
        itemIDs: [String],
        offset: Int
    ) -> PanelSelectionUpdate {
        guard !itemIDs.isEmpty else {
            return unchangedSelectionUpdate(state)
        }

        guard let selectedItemID = state.selection.selectedItemID else {
            return stateByReplacingSelection(state, itemIDs: itemIDs, selectedItemID: itemIDs[0])
        }

        guard let nextID = PanelInteractionPlanner.selectedIDAfterOffset(
            currentSelectedID: selectedItemID,
            itemIDs: itemIDs,
            offset: offset
        ) else {
            return unchangedSelectionUpdate(state)
        }

        return stateBySelectingRange(state, itemIDs: itemIDs, toItemID: nextID)
    }

    private static func stateByPreparingContextMenu(
        _ state: PanelSceneState,
        itemIDs: [String],
        itemID: String
    ) -> PanelSelectionUpdate {
        guard itemIDs.contains(itemID) else {
            return unchangedSelectionUpdate(state)
        }

        guard state.selection.selectedItemIDs.contains(itemID) else {
            return stateByReplacingSelection(state, itemIDs: itemIDs, selectedItemID: itemID)
        }

        return selectionUpdate(
            from: state,
            selectedItemID: itemID,
            selectedItemIDs: state.selection.selectedItemIDs,
            rangeAnchorItemID: state.selection.rangeAnchorItemID ?? itemID,
            itemIDs: itemIDs
        )
    }

    public static func stateByCopyingItem(
        _ state: PanelSceneState,
        itemID: String
    ) -> PanelSceneState {
        var nextState = state
        nextState.selection.selectedItemID = itemID
        nextState.selection.selectedItemIDs.insert(itemID)
        nextState.selection.rangeAnchorItemID = nextState.selection.rangeAnchorItemID ?? itemID
        return nextState
    }

    public static func stateByCollapsingSelectionToPrimary(_ state: PanelSceneState) -> PanelSelectionUpdate {
        var nextState = state
        let selectedItemID = state.selection.selectedItemID
        nextState.selection = PanelSelectionState(
            selectedItemID: selectedItemID,
            selectedItemIDs: selectedItemID.map { Set([$0]) } ?? [],
            rangeAnchorItemID: selectedItemID,
            isCommandHintModeEnabled: state.selection.isCommandHintModeEnabled
        )
        let didChangeSelection = nextState.selection != state.selection
        return PanelSelectionUpdate(
            state: nextState,
            shouldClosePreview: false,
            didChangeSelection: didChangeSelection
        )
    }

    public static func stateByClearingSelection(_ state: PanelSceneState) -> PanelSceneState {
        var nextState = state
        nextState.selection.selectedItemID = nil
        nextState.selection.selectedItemIDs = []
        nextState.selection.rangeAnchorItemID = nil
        return nextState
    }

    public static func stateBySettingSearchText(
        _ state: PanelSceneState,
        searchText: String
    ) -> PanelSceneState {
        var nextState = state
        nextState.query.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return nextState
    }

    public static func stateBySettingPinboardFilter(
        _ state: PanelSceneState,
        pinboardID: String?
    ) -> PanelSceneState {
        var nextState = state
        nextState.query.pinboardID = pinboardID
        return nextState
    }

    public static func stateBySettingItemTypeFilter(
        _ state: PanelSceneState,
        itemType: String?
    ) -> PanelSceneState {
        var nextState = state
        nextState.query.itemType = itemType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return nextState
    }

    public static func stateBySettingScopeFilters(
        _ state: PanelSceneState,
        itemType: String?,
        pinboardID: String?
    ) -> PanelSceneState {
        var nextState = stateBySettingItemTypeFilter(state, itemType: itemType)
        nextState.query.pinboardID = pinboardID
        return nextState
    }

    public static func stateByClearingFilters(_ state: PanelSceneState) -> PanelSceneState {
        var nextState = state
        nextState.query.searchText = ""
        nextState.query.itemType = nil
        nextState.query.pinboardID = nil
        nextState.query.isSearchVisible = false
        return nextState
    }

    public static func searchToggleResult(_ state: PanelSceneState) -> PanelSearchToggleResult {
        var nextState = state
        if state.query.isSearchVisible {
            if state.query.searchText.isEmpty {
                nextState.query.isSearchVisible = false
                return PanelSearchToggleResult(state: nextState, focusTarget: .panel)
            }

            return PanelSearchToggleResult(state: nextState, focusTarget: nil)
        }

        nextState.query.isSearchVisible = true
        return PanelSearchToggleResult(state: nextState, focusTarget: .searchField)
    }

    public static func stateByUpdatingCommandHintMode(
        _ state: PanelSceneState,
        enabled: Bool
    ) -> PanelSceneState {
        var nextState = state
        nextState.selection.isCommandHintModeEnabled = enabled
        return nextState
    }

    public static func stateBySettingPreviewPopoverEnabled(
        _ state: PanelSceneState,
        enabled: Bool
    ) -> PanelSceneState {
        var nextState = state
        nextState.preview.isPopoverEnabled = enabled
        return nextState
    }

    public static func focusSearchResult(_ state: PanelSceneState) -> PanelSearchFocusResult {
        var nextState = state
        nextState.query.isSearchVisible = true
        return PanelSearchFocusResult(state: nextState, focusTarget: .searchField)
    }

    public static func startSearchResult(
        _ state: PanelSceneState,
        initialText: String
    ) -> PanelStartSearchResult {
        var nextState = state
        nextState.query.isSearchVisible = true
        let searchText = state.query.isSearchVisible
            ? state.query.searchText + initialText
            : initialText
        nextState.query.searchText = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PanelStartSearchResult(state: nextState, focusTarget: .searchField)
    }

    public static func stateByDismissingSearch(_ state: PanelSceneState) -> PanelSceneState {
        var nextState = state
        nextState.query.searchText = ""
        nextState.query.isSearchVisible = false
        return nextState
    }

    public static func escapeAction(
        _ state: PanelSceneState,
        isPreviewShown: Bool
    ) -> PanelEscapeAction {
        PanelInteractionPlanner.escapeAction(
            isPreviewShown: isPreviewShown,
            searchText: state.query.searchText,
            isSearchVisible: state.query.isSearchVisible
        )
    }

    public static func commandCopyTarget(
        number: Int,
        visibleItemIDs: [String]
    ) -> String? {
        PanelInteractionPlanner.selectedIDForCommandNumber(number, itemIDs: visibleItemIDs)
    }
}

private extension PanelSceneController {
    static func repairedSelectionAfterListUpdate(
        _ selection: PanelSelectionState,
        itemIDs: [String]
    ) -> PanelSelectionState {
        repairedSelection(
            selectedItemID: selection.selectedItemID,
            selectedItemIDs: selection.selectedItemIDs,
            rangeAnchorItemID: selection.rangeAnchorItemID,
            itemIDs: itemIDs,
            selectsFirstWhenEmpty: true,
            isCommandHintModeEnabled: selection.isCommandHintModeEnabled
        )
    }

    static func repairedSelection(
        selectedItemID: String?,
        selectedItemIDs: Set<String>,
        rangeAnchorItemID: String?,
        itemIDs: [String],
        selectsFirstWhenEmpty: Bool,
        isCommandHintModeEnabled: Bool
    ) -> PanelSelectionState {
        guard !itemIDs.isEmpty else {
            return PanelSelectionState(isCommandHintModeEnabled: isCommandHintModeEnabled)
        }

        var prunedSelectedIDs = selectedItemIDs.intersection(Set(itemIDs))
        if let selectedItemID, itemIDs.contains(selectedItemID) {
            prunedSelectedIDs.insert(selectedItemID)
        }

        if prunedSelectedIDs.isEmpty {
            guard selectsFirstWhenEmpty, let firstID = itemIDs.first else {
                return PanelSelectionState(isCommandHintModeEnabled: isCommandHintModeEnabled)
            }
            return PanelSelectionState(
                selectedItemID: firstID,
                selectedItemIDs: [firstID],
                rangeAnchorItemID: firstID,
                isCommandHintModeEnabled: isCommandHintModeEnabled
            )
        }

        let repairedPrimaryID = selectedItemID.flatMap {
            prunedSelectedIDs.contains($0) ? $0 : nil
        } ?? itemIDs.first { prunedSelectedIDs.contains($0) }
        let repairedAnchorID = rangeAnchorItemID.flatMap {
            prunedSelectedIDs.contains($0) ? $0 : nil
        } ?? repairedPrimaryID

        return PanelSelectionState(
            selectedItemID: repairedPrimaryID,
            selectedItemIDs: prunedSelectedIDs,
            rangeAnchorItemID: repairedAnchorID,
            isCommandHintModeEnabled: isCommandHintModeEnabled
        )
    }

    static func selectionUpdate(
        from state: PanelSceneState,
        selectedItemID: String?,
        selectedItemIDs: Set<String>,
        rangeAnchorItemID: String?,
        itemIDs: [String]
    ) -> PanelSelectionUpdate {
        var nextState = state
        nextState.selection = repairedSelection(
            selectedItemID: selectedItemID,
            selectedItemIDs: selectedItemIDs,
            rangeAnchorItemID: rangeAnchorItemID,
            itemIDs: itemIDs,
            selectsFirstWhenEmpty: false,
            isCommandHintModeEnabled: state.selection.isCommandHintModeEnabled
        )
        let didChangeSelection = nextState.selection != state.selection
        return PanelSelectionUpdate(
            state: nextState,
            shouldClosePreview: didChangeSelection,
            didChangeSelection: didChangeSelection
        )
    }

    static func unchangedSelectionUpdate(_ state: PanelSceneState) -> PanelSelectionUpdate {
        PanelSelectionUpdate(
            state: state,
            shouldClosePreview: false,
            didChangeSelection: false
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
