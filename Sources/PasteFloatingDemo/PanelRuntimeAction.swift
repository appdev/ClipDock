import ClipboardPanelApp

enum PanelRuntimeAction {
    case showPreferences
    case hidePanel
    case queryChanged(searchText: String, itemType: String?, sourceAppID: String?)
    case copyItem(RustClipboardItemSummary)
    case setPinned(RustClipboardItemSummary, isPinned: Bool)
    case deleteItem(RustClipboardItemSummary)
    case loadMore
}
