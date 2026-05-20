import Foundation

public struct PanelToolbarViewState: Equatable, Sendable {
    public let searchText: String
    public let isSearchVisible: Bool
    public let selectedItemType: String?
    public let selectedPinboardID: String?
    public let clearActionTitle: String

    public init(
        searchText: String,
        isSearchVisible: Bool,
        selectedItemType: String? = nil,
        selectedPinboardID: String?,
        clearActionTitle: String
    ) {
        self.searchText = searchText
        self.isSearchVisible = isSearchVisible
        self.selectedItemType = selectedItemType
        self.selectedPinboardID = selectedPinboardID
        self.clearActionTitle = clearActionTitle
    }
}

public struct PanelViewState: Equatable, Sendable {
    public let toolbar: PanelToolbarViewState
    public let list: PanelListViewState
    public let selectedItemID: String?
    public let selectedItemIDs: Set<String>
    public let isPreviewPopoverEnabled: Bool
    public let isCommandHintModeEnabled: Bool

    public init(
        toolbar: PanelToolbarViewState,
        list: PanelListViewState,
        selectedItemID: String?,
        selectedItemIDs: Set<String> = [],
        isPreviewPopoverEnabled: Bool,
        isCommandHintModeEnabled: Bool
    ) {
        self.toolbar = toolbar
        self.list = list
        self.selectedItemID = selectedItemID
        self.selectedItemIDs = selectedItemIDs
        self.isPreviewPopoverEnabled = isPreviewPopoverEnabled
        self.isCommandHintModeEnabled = isCommandHintModeEnabled
    }
}

public enum PanelViewStateAdapter {
    public static func makeViewState(
        scene: PanelSceneState,
        list: PanelListViewState
    ) -> PanelViewState {
        let hasSearch = !scene.query.searchText.isEmpty
        let clearActionTitle = (scene.query.itemType != nil || scene.query.pinboardID != nil || hasSearch)
            ? AppLocalization.text("toolbar.clearCurrentResults", defaultValue: "清空当前结果")
            : AppLocalization.text("toolbar.clearHistory", defaultValue: "清空历史")

        return PanelViewState(
            toolbar: PanelToolbarViewState(
                searchText: scene.query.searchText,
                isSearchVisible: scene.query.isSearchVisible,
                selectedItemType: scene.query.itemType,
                selectedPinboardID: scene.query.pinboardID,
                clearActionTitle: clearActionTitle
            ),
            list: list,
            selectedItemID: scene.selection.selectedItemID,
            selectedItemIDs: scene.selection.selectedItemIDs,
            isPreviewPopoverEnabled: scene.preview.isPopoverEnabled,
            isCommandHintModeEnabled: scene.selection.isCommandHintModeEnabled
        )
    }
}
