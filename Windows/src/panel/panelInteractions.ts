import type { ClipItem } from "./panelTypes";

export function nextCreatedItemOrdinal(items: ClipItem[]): number {
  const ordinals = items
    .map((item) => /^created-text-(\d+)$/.exec(item.id)?.[1])
    .filter((value): value is string => value !== undefined)
    .map((value) => Number(value))
    .filter(Number.isFinite);
  return ordinals.length === 0 ? 1 : Math.max(...ordinals) + 1;
}

export function createPanelTextItem(ordinal: number): ClipItem {
  return {
    id: `created-text-${ordinal}`,
    kind: "text",
    typeLabel: "Text",
    relativeTime: "now",
    title: `新增剪贴内容 ${ordinal}`,
    summary: `新增剪贴内容 ${ordinal}\n用于验证新增、右键、固定和删除交互`,
    footer: "33 characters",
    commandIndex: String(ordinal),
    sourceName: "Notes",
    sourceKind: "notes",
    sourcePathHints: {
      macos: ["/System/Applications/Notes.app"],
      windows: ["{WINDIR}\\System32\\notepad.exe"]
    },
    sourceColor: "#af52de",
    selectedColor: "#0a84ff",
    pinboardIds: ["product"]
  };
}

export function addPanelItem(items: ClipItem[]): ClipItem[] {
  return [createPanelTextItem(nextCreatedItemOrdinal(items)), ...items];
}

export function deletePanelItem(items: ClipItem[], itemId: string): ClipItem[] {
  return items.filter((item) => item.id !== itemId);
}

export function togglePinnedItem(items: ClipItem[], itemId: string): ClipItem[] {
  return items.map((item) => {
    if (item.id !== itemId) {
      return item;
    }
    return {
      ...item,
      isPinned: !item.isPinned
    };
  });
}

export function sortedPanelItemsForDisplay(items: ClipItem[]): ClipItem[] {
  return [...items].sort((left, right) => {
    if (left.isPinned === right.isPinned) {
      return 0;
    }
    return left.isPinned ? -1 : 1;
  });
}
