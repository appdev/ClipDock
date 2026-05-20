import ClipboardPanelApp

enum PanelRuntimeAction {
    case showPreferences
    case hidePanel
    case queryChanged(searchText: String, itemType: String?, sourceAppID: String?, pinboardID: String?, debounce: Bool)
    case copyItem(RustClipboardItemSummary)
    case copyItemAsPlainText(RustClipboardItemSummary)
    case copyPath(String)
    case setPinboardMembership(RustClipboardItemSummary, pinboardID: String, isMember: Bool)
    case setPinboardMembershipBatch([RustClipboardItemSummary], pinboardID: String, isMember: Bool)
    case createPinboard(title: String, colorCode: Int64)
    case renamePinboard(pinboardID: String, title: String)
    case updatePinboardColor(pinboardID: String, colorCode: Int64)
    case deletePinboard(pinboardID: String)
    case deleteItem(RustClipboardItemSummary, pinboardID: String?)
    case deleteItems([RustClipboardItemSummary], pinboardID: String?)
    case loadMore
}
