import Testing
@testable import ClipboardPanelApp

struct KeyboardShortcutPresenterTests {
    @Test
    func displaysDefaultOpenPanelShortcut() {
        #expect(KeyboardShortcutPresenter.displayText(for: RustKeyboardShortcut()) == "⌘ ⇧ V")
        #expect(KeyboardShortcutPresenter.keyEquivalent(for: RustKeyboardShortcut()) == "v")
    }

    @Test
    func normalizesRecordedShortcutModifierAliases() {
        let shortcut = RustKeyboardShortcut(
            keyCode: 11,
            modifiers: ["shift", "cmd", "alt", "command"]
        )

        let normalized = KeyboardShortcutPresenter.normalized(shortcut)

        #expect(normalized.keyCode == 11)
        #expect(normalized.modifiers == ["command", "option", "shift"])
        #expect(KeyboardShortcutPresenter.displayText(for: normalized) == "⌘ ⌥ ⇧ B")
        #expect(KeyboardShortcutPresenter.isRecordable(shortcut))
    }

    @Test
    func rejectsModifierOnlyGlobalShortcut() {
        let shortcut = RustKeyboardShortcut(keyCode: 9, modifiers: ["shift"])

        #expect(!KeyboardShortcutPresenter.isRecordable(shortcut))
        #expect(KeyboardShortcutPresenter.normalized(shortcut) == RustKeyboardShortcut())
    }
}
