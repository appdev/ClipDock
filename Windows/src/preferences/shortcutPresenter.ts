import type { KeyboardShortcut, ModifierKey } from "./preferencesTypes";

type KeyboardEventLike = {
  key: string;
  code?: string;
  metaKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  shiftKey: boolean;
};

export type ShortcutRecordResult =
  | { kind: "cancel" }
  | { kind: "waiting" }
  | { kind: "invalid"; message: string }
  | { kind: "recorded"; shortcut: KeyboardShortcut };

const modifierOrder: ModifierKey[] = ["command", "option", "control", "shift"];
const requiredRecorderModifiers: ModifierKey[] = ["command", "option", "control"];

const modifierSymbols: Record<ModifierKey, string> = {
  command: "⌘",
  option: "⌥",
  control: "⌃",
  shift: "⇧"
};

const modifierNames: Record<ModifierKey, string> = {
  command: "Command",
  option: "Option",
  control: "Control",
  shift: "Shift"
};

const keyCodeLabels = new Map<number, string>([
  [0, "A"],
  [1, "S"],
  [2, "D"],
  [3, "F"],
  [4, "H"],
  [5, "G"],
  [6, "Z"],
  [7, "X"],
  [8, "C"],
  [9, "V"],
  [11, "B"],
  [12, "Q"],
  [13, "W"],
  [14, "E"],
  [15, "R"],
  [16, "Y"],
  [17, "T"],
  [18, "1"],
  [19, "2"],
  [20, "3"],
  [21, "4"],
  [22, "6"],
  [23, "5"],
  [24, "="],
  [25, "9"],
  [26, "7"],
  [27, "-"],
  [28, "8"],
  [29, "0"],
  [30, "]"],
  [31, "O"],
  [32, "U"],
  [33, "["],
  [34, "I"],
  [35, "P"],
  [37, "L"],
  [38, "J"],
  [39, "'"],
  [40, "K"],
  [41, ";"],
  [42, "\\"],
  [43, ","],
  [44, "/"],
  [45, "N"],
  [46, "M"],
  [47, "."],
  [49, "Space"],
  [50, "`"],
  [53, "Esc"],
  [123, "←"],
  [124, "→"],
  [125, "↓"],
  [126, "↑"]
]);

const keyCodeByCode = new Map<string, number>([
  ["KeyA", 0],
  ["KeyS", 1],
  ["KeyD", 2],
  ["KeyF", 3],
  ["KeyH", 4],
  ["KeyG", 5],
  ["KeyZ", 6],
  ["KeyX", 7],
  ["KeyC", 8],
  ["KeyV", 9],
  ["KeyB", 11],
  ["KeyQ", 12],
  ["KeyW", 13],
  ["KeyE", 14],
  ["KeyR", 15],
  ["KeyY", 16],
  ["KeyT", 17],
  ["Digit1", 18],
  ["Digit2", 19],
  ["Digit3", 20],
  ["Digit4", 21],
  ["Digit6", 22],
  ["Digit5", 23],
  ["Equal", 24],
  ["Digit9", 25],
  ["Digit7", 26],
  ["Minus", 27],
  ["Digit8", 28],
  ["Digit0", 29],
  ["BracketRight", 30],
  ["KeyO", 31],
  ["KeyU", 32],
  ["BracketLeft", 33],
  ["KeyI", 34],
  ["KeyP", 35],
  ["KeyL", 37],
  ["KeyJ", 38],
  ["Quote", 39],
  ["KeyK", 40],
  ["Semicolon", 41],
  ["Backslash", 42],
  ["Comma", 43],
  ["Slash", 44],
  ["KeyN", 45],
  ["KeyM", 46],
  ["Period", 47],
  ["Space", 49],
  ["Backquote", 50],
  ["Escape", 53],
  ["ArrowLeft", 123],
  ["ArrowRight", 124],
  ["ArrowDown", 125],
  ["ArrowUp", 126]
]);

const modifierOnlyKeys = new Set(["Meta", "Alt", "Control", "Shift"]);

export function modifierSymbol(modifier: ModifierKey): string {
  return modifierSymbols[modifier];
}

export function modifierDisplayName(modifier: ModifierKey): string {
  return `${modifierSymbols[modifier]} ${modifierNames[modifier]}`;
}

export function formatKeyboardShortcut(shortcut: KeyboardShortcut | null): string {
  if (!shortcut) {
    return "未设置";
  }

  const labels = modifierOrder
    .filter((modifier) => shortcut.modifiers.includes(modifier))
    .map((modifier) => modifierSymbols[modifier]);
  labels.push(keyCodeLabels.get(shortcut.keyCode) ?? `Key ${shortcut.keyCode}`);
  return labels.join(" ");
}

export function shortcutFromKeyboardEvent(event: KeyboardEventLike): ShortcutRecordResult {
  if (event.key === "Escape") {
    return { kind: "cancel" };
  }

  if (modifierOnlyKeys.has(event.key)) {
    return { kind: "waiting" };
  }

  const modifiers = activeModifiers(event);
  if (!requiredRecorderModifiers.some((modifier) => modifiers.includes(modifier))) {
    return { kind: "invalid", message: "需要 ⌘ / ⌥ / ⌃" };
  }

  const keyCode = keyCodeFromKeyboardEvent(event);
  if (keyCode === null) {
    return { kind: "invalid", message: "不可用的按键" };
  }

  return {
    kind: "recorded",
    shortcut: {
      keyCode,
      modifiers
    }
  };
}

export function matchesKeyboardShortcut(
  event: KeyboardEventLike,
  shortcut: KeyboardShortcut | null
): boolean {
  if (!shortcut) {
    return false;
  }

  const eventKeyCode = keyCodeFromKeyboardEvent(event);
  if (eventKeyCode !== shortcut.keyCode) {
    return false;
  }

  return modifierOrder.every((modifier) => {
    const expected = shortcut.modifiers.includes(modifier);
    return modifierIsPressed(event, modifier) === expected;
  });
}

export function modifierIsPressed(event: KeyboardEventLike, modifier: ModifierKey): boolean {
  switch (modifier) {
    case "command":
      return event.metaKey;
    case "option":
      return event.altKey;
    case "control":
      return event.ctrlKey;
    case "shift":
      return event.shiftKey;
  }
}

export function eventHasAnyShortcutModifier(event: KeyboardEventLike): boolean {
  return event.metaKey || event.ctrlKey || event.altKey || event.shiftKey;
}

export function matchesSearchShortcut(event: KeyboardEventLike): boolean {
  return (
    keyCodeFromKeyboardEvent(event) === 3 &&
    event.metaKey &&
    !event.ctrlKey &&
    !event.altKey &&
    !event.shiftKey
  );
}

function activeModifiers(event: KeyboardEventLike): ModifierKey[] {
  return modifierOrder.filter((modifier) => modifierIsPressed(event, modifier));
}

function keyCodeFromKeyboardEvent(event: KeyboardEventLike): number | null {
  if (event.code) {
    const mapped = keyCodeByCode.get(event.code);
    if (mapped !== undefined) {
      return mapped;
    }
  }

  const normalizedKey = event.key.length === 1 ? event.key.toLocaleUpperCase() : event.key;
  for (const [keyCode, label] of keyCodeLabels) {
    if (label === normalizedKey) {
      return keyCode;
    }
  }

  return null;
}
