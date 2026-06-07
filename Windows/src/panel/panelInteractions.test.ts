import { describe, expect, it } from "vitest";
import {
  addPanelItem,
  deletePanelItem,
  sortedPanelItemsForDisplay,
  togglePinnedItem
} from "./panelInteractions";
import type { ClipItem } from "./panelTypes";

const baseItems: ClipItem[] = [
  {
    id: "first",
    kind: "text",
    typeLabel: "Text",
    relativeTime: "1m ago",
    title: "First",
    summary: "First",
    footer: "5 characters",
    commandIndex: "1",
    sourceName: "Chrome",
    sourceKind: "chrome",
    sourceColor: "#f7d329",
    selectedColor: "#0a84ff",
    pinboardIds: ["product"]
  },
  {
    id: "second",
    kind: "text",
    typeLabel: "Text",
    relativeTime: "2m ago",
    title: "Second",
    summary: "Second",
    footer: "6 characters",
    commandIndex: "2",
    sourceName: "Terminal",
    sourceKind: "terminal",
    sourceColor: "#333333",
    selectedColor: "#0a84ff",
    pinboardIds: ["product"]
  }
];

describe("panel interactions", () => {
  it("adds a concrete text item at the front", () => {
    const [created, ...rest] = addPanelItem(baseItems);

    expect(created.id).toBe("created-text-1");
    expect(created.title).toBe("新增剪贴内容 1");
    expect(created.sourceKind).toBe("notes");
    expect(rest).toEqual(baseItems);
  });

  it("deletes only the requested item", () => {
    expect(deletePanelItem(baseItems, "first").map((item) => item.id)).toEqual(["second"]);
  });

  it("toggles pinned state and displays pinned items first", () => {
    const pinned = togglePinnedItem(baseItems, "second");

    expect(pinned.find((item) => item.id === "second")?.isPinned).toBe(true);
    expect(sortedPanelItemsForDisplay(pinned).map((item) => item.id)).toEqual([
      "second",
      "first"
    ]);
  });
});
