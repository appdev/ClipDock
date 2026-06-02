import Foundation

public enum KeyboardShortcutPresenter {
    public static let defaultOpenPanelShortcut = RustKeyboardShortcut()

    private static let canonicalModifierOrder = ["command", "option", "control", "shift"]
    private static let requiredGlobalModifiers = Set(["command", "option", "control"])

    public static func normalized(_ shortcut: RustKeyboardShortcut) -> RustKeyboardShortcut {
        guard (0...127).contains(shortcut.keyCode) else {
            return defaultOpenPanelShortcut
        }

        let modifiers = normalizedModifiers(shortcut.modifiers)
        guard !requiredGlobalModifiers.isDisjoint(with: Set(modifiers)) else {
            return defaultOpenPanelShortcut
        }

        return RustKeyboardShortcut(keyCode: shortcut.keyCode, modifiers: modifiers)
    }

    public static func normalizedOptional(_ shortcut: RustKeyboardShortcut?) -> RustKeyboardShortcut? {
        shortcut.map(normalized)
    }

    public static func isRecordable(_ shortcut: RustKeyboardShortcut) -> Bool {
        normalized(shortcut) == RustKeyboardShortcut(
            keyCode: shortcut.keyCode,
            modifiers: normalizedModifiers(shortcut.modifiers)
        )
    }

    public static func displayText(for shortcut: RustKeyboardShortcut) -> String {
        let shortcut = normalized(shortcut)
        let modifierText = shortcut.modifiers
            .compactMap(modifierSymbol)
            .joined(separator: " ")
        let keyText = keyDisplayText(forKeyCode: shortcut.keyCode)

        guard !modifierText.isEmpty else {
            return keyText
        }

        return "\(modifierText) \(keyText)"
    }

    public static func displayText(for shortcut: RustKeyboardShortcut?, noneText: String) -> String {
        guard let shortcut else {
            return noneText
        }
        return displayText(for: shortcut)
    }

    public static func keyEquivalent(for shortcut: RustKeyboardShortcut) -> String? {
        let shortcut = normalized(shortcut)
        guard let value = keyEquivalentByCode[shortcut.keyCode] else {
            return nil
        }
        return value
    }

    public static func keyEquivalent(for shortcut: RustKeyboardShortcut?) -> String? {
        guard let shortcut else { return nil }
        return keyEquivalent(for: shortcut)
    }

    public static func modifierDisplayText(_ modifier: String) -> String {
        switch canonicalModifier(modifier) {
        case "command":
            return "⌘ Command"
        case "control":
            return "⌃ Control"
        case "option":
            return "⌥ Option"
        case "shift":
            return "⇧ Shift"
        default:
            return modifier
        }
    }

    public static func modifierGlyph(_ modifier: String) -> String {
        switch canonicalModifier(modifier) {
        case "command":
            return "⌘"
        case "control":
            return "⌃"
        case "option":
            return "⌥"
        case "shift":
            return "⇧"
        default:
            return modifier
        }
    }

    private static func normalizedModifiers(_ modifiers: [String]) -> [String] {
        let modifierSet = Set(modifiers.compactMap(canonicalModifier))
        return canonicalModifierOrder.filter { modifierSet.contains($0) }
    }

    private static func canonicalModifier(_ modifier: String) -> String? {
        switch modifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "command", "cmd", "meta":
            return "command"
        case "option", "alt":
            return "option"
        case "control", "ctrl":
            return "control"
        case "shift":
            return "shift"
        default:
            return nil
        }
    }

    private static func modifierSymbol(_ modifier: String) -> String? {
        switch modifier {
        case "command":
            return "⌘"
        case "option":
            return "⌥"
        case "control":
            return "⌃"
        case "shift":
            return "⇧"
        default:
            return nil
        }
    }

    private static func keyDisplayText(forKeyCode keyCode: Int64) -> String {
        keyDisplayByCode[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyDisplayByCode: [Int64: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`", 36: "Return", 48: "Tab",
        49: "Space", 51: "Delete", 53: "Esc", 64: "F17", 79: "F18",
        80: "F19", 90: "F20", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16",
        107: "F14", 109: "F10", 111: "F12", 113: "F15", 115: "Home",
        116: "Page Up", 117: "Forward Delete", 118: "F4", 119: "End",
        120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→",
        125: "↓", 126: "↑"
    ]

    private static let keyEquivalentByCode: [Int64: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`", 36: "\r", 48: "\t", 49: " "
    ]
}
