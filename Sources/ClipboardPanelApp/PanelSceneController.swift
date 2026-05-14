import Foundation

public enum PanelFocusTarget: Equatable, Sendable {
    case searchField
    case panel
}

public struct PanelQueryState: Equatable, Sendable {
    public var searchText: String
    public var pinboardID: String?
    public var isSearchVisible: Bool

    public init(
        searchText: String = "",
        pinboardID: String? = nil,
        isSearchVisible: Bool = false
    ) {
        self.searchText = searchText
        self.pinboardID = pinboardID
        self.isSearchVisible = isSearchVisible
    }
}

public struct PanelSelectionState: Equatable, Sendable {
    public var selectedItemID: String?
    public var isCommandHintModeEnabled: Bool

    public init(
        selectedItemID: String? = nil,
        isCommandHintModeEnabled: Bool = false
    ) {
        self.selectedItemID = selectedItemID
        self.isCommandHintModeEnabled = isCommandHintModeEnabled
    }
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

    public func clearSelection() {
        state = PanelSceneController.stateByClearingSelection(state)
    }

    public func setSearchText(_ searchText: String) {
        state = PanelSceneController.stateBySettingSearchText(state, searchText: searchText)
    }

    public func setPinboardFilter(_ pinboardID: String?) {
        state = PanelSceneController.stateBySettingPinboardFilter(state, pinboardID: pinboardID)
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
        nextState.selection.selectedItemID = PanelInteractionPlanner.selectedIDAfterListUpdate(
            previousSelectedID: state.selection.selectedItemID,
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

        return stateBySelectingItem(state, itemIDs: itemIDs, selectedItemID: nextID)
    }

    public static func stateBySelectingItem(
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
        var nextState = state
        nextState.selection.selectedItemID = selectedItemID
        return PanelSelectionUpdate(
            state: nextState,
            shouldClosePreview: didChangeSelection,
            didChangeSelection: didChangeSelection
        )
    }

    public static func stateByCopyingItem(
        _ state: PanelSceneState,
        itemID: String
    ) -> PanelSceneState {
        var nextState = state
        nextState.selection.selectedItemID = itemID
        return nextState
    }

    public static func stateByClearingSelection(_ state: PanelSceneState) -> PanelSceneState {
        var nextState = state
        nextState.selection.selectedItemID = nil
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

    public static func stateByClearingFilters(_ state: PanelSceneState) -> PanelSceneState {
        var nextState = state
        nextState.query.searchText = ""
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
            searchText: state.query.searchText
        )
    }

    public static func commandCopyTarget(
        number: Int,
        visibleItemIDs: [String]
    ) -> String? {
        PanelInteractionPlanner.selectedIDForCommandNumber(number, itemIDs: visibleItemIDs)
    }
}
