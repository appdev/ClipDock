import ClipboardPanelApp

enum PanelRuntimeAction {
    case showPreferences
    case hidePanel
    case queryChanged(searchText: String, sourceAppID: String?, pinboardID: String?, debounce: Bool)
    case copyItem(RustClipboardItemSummary)
    case setPinboardMembership(RustClipboardItemSummary, pinboardID: String, isMember: Bool)
    case createPinboard(title: String, colorCode: Int64)
    case renamePinboard(pinboardID: String, title: String)
    case updatePinboardColor(pinboardID: String, colorCode: Int64)
    case deletePinboard(pinboardID: String)
    case deleteItem(RustClipboardItemSummary)
    case loadMore
}
