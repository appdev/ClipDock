import { describe, expect, test } from "vitest";
import {
  formatKeyboardShortcut,
  matchesKeyboardShortcut,
  shortcutFromKeyboardEvent
} from "./shortcutPresenter";
import type { KeyboardShortcut } from "./preferencesTypes";

describe("shortcut presenter", () => {
  test("formats macOS default shortcuts", () => {
    expect(formatKeyboardShortcut({ keyCode: 7, modifiers: ["command", "shift"] })).toBe("⌘ ⇧ X");
    expect(formatKeyboardShortcut({ keyCode: 123, modifiers: ["command"] })).toBe("⌘ ←");
    expect(formatKeyboardShortcut({ keyCode: 124, modifiers: ["command"] })).toBe("⌘ →");
  });

  test("records shortcuts that include a required modifier", () => {
    const result = shortcutFromKeyboardEvent({
      key: "K",
      code: "KeyK",
      metaKey: true,
      ctrlKey: false,
      altKey: true,
      shiftKey: false
    });

    expect(result).toEqual({
      kind: "recorded",
      shortcut: {
        keyCode: 40,
        modifiers: ["command", "option"]
      }
    });
  });

  test("rejects shortcuts without command option or control", () => {
    expect(
      shortcutFromKeyboardEvent({
        key: "X",
        code: "KeyX",
        metaKey: false,
        ctrlKey: false,
        altKey: false,
        shiftKey: true
      })
    ).toEqual({ kind: "invalid", message: "需要 ⌘ / ⌥ / ⌃" });
  });

  test("matches key and modifier combinations exactly", () => {
    const shortcut: KeyboardShortcut = { keyCode: 3, modifiers: ["command"] };
    expect(
      matchesKeyboardShortcut(
        {
          key: "f",
          code: "KeyF",
          metaKey: true,
          ctrlKey: false,
          altKey: false,
          shiftKey: false
        },
        shortcut
      )
    ).toBe(true);
    expect(
      matchesKeyboardShortcut(
        {
          key: "f",
          code: "KeyF",
          metaKey: true,
          ctrlKey: false,
          altKey: false,
          shiftKey: true
        },
        shortcut
      )
    ).toBe(false);
  });
});
