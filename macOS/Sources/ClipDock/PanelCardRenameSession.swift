import AppKit
import ClipboardPanelApp

/// The editor is hosted above the collection so a cell refresh cannot discard
/// its field editor or an in-progress input-method composition.
@MainActor
final class PanelCardRenameSession: NSObject, NSTextFieldDelegate {
    let itemID: String
    let field = NSTextField()
    private weak var titleLabel: NSTextField?
    private weak var host: NSView?
    private let originalTitle: String
    private let onFinish: (String?) -> Void
    private var isFinished = false
    private var isInstallingFieldEditor = false

    init(itemID: String, title: String, label: NSTextField, host: NSView, onFinish: @escaping (String?) -> Void) {
        self.itemID = itemID
        self.originalTitle = title
        self.host = host
        self.onFinish = onFinish
        super.init()
        field.identifier = NSUserInterfaceItemIdentifier("PanelCardRenameField")
        field.stringValue = title
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.delegate = self
        field.setAccessibilityLabel(AppLocalization.text("action.rename", defaultValue: "重命名"))
        host.addSubview(field)
        updateAnchor(label)
    }

    func focus() {
        // AppKit can end the first field-editor session while selectText installs
        // the selected editor. This is initialization, not a user's focus change.
        isInstallingFieldEditor = true
        defer { isInstallingFieldEditor = false }
        host?.window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    func updateAnchor(_ label: NSTextField) {
        guard let host, !isFinished else { return }
        if titleLabel !== label {
            titleLabel?.alphaValue = 1
            titleLabel = label
        }
        label.alphaValue = 0
        field.font = label.font
        field.textColor = label.textColor
        field.frame = label.convert(label.bounds, to: host)
    }

    func finish(commit: Bool, restoreFocus: Bool = true) {
        guard !isFinished else { return }
        isFinished = true
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.delegate = nil
        // Publish the draft before revealing the label or handing off focus.
        // Persistence is asynchronous, but the visible title must not revert.
        onFinish(commit && title != originalTitle ? title : nil)
        titleLabel?.alphaValue = 1
        if restoreFocus, let host {
            host.window?.makeFirstResponder(host)
        }
        field.removeFromSuperview()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !isInstallingFieldEditor else { return }
        finish(commit: true, restoreFocus: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Enter and Escape belong to the input method while it is composing.
        guard !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            finish(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish(commit: false)
            return true
        default:
            return false
        }
    }
}
