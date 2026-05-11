import Foundation

public struct PanelToolbarViewState: Equatable, Sendable {
    public let searchText: String
    public let isSearchVisible: Bool
    public let selectedItemType: String?
    public let clearActionTitle: String

    public init(
        searchText: String,
        isSearchVisible: Bool,
        selectedItemType: String?,
        clearActionTitle: String
    ) {
        self.searchText = searchText
        self.isSearchVisible = isSearchVisible
        self.selectedItemType = selectedItemType
        self.clearActionTitle = clearActionTitle
    }
}

public struct PanelViewState: Equatable, Sendable {
    public let toolbar: PanelToolbarViewState
    public let list: PanelListViewState
    public let selectedItemID: String?
    public let isPreviewPopoverEnabled: Bool
    public let isCommandHintModeEnabled: Bool

    public init(
        toolbar: PanelToolbarViewState,
        list: PanelListViewState,
        selectedItemID: String?,
        isPreviewPopoverEnabled: Bool,
        isCommandHintModeEnabled: Bool
    ) {
        self.toolbar = toolbar
        self.list = list
        self.selectedItemID = selectedItemID
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
        let clearActionTitle = (scene.query.itemType != nil || hasSearch)
            ? "清空当前结果"
            : "清空未固定历史"

        return PanelViewState(
            toolbar: PanelToolbarViewState(
                searchText: scene.query.searchText,
                isSearchVisible: scene.query.isSearchVisible,
                selectedItemType: scene.query.itemType,
                clearActionTitle: clearActionTitle
            ),
            list: list,
            selectedItemID: scene.selection.selectedItemID,
            isPreviewPopoverEnabled: scene.preview.isPopoverEnabled,
            isCommandHintModeEnabled: scene.selection.isCommandHintModeEnabled
        )
    }
}
