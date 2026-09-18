import { describe, expect, it, vi } from "vitest";
import { CardRenameQueue, matchesRenameShortcut, normalizedCardTitle, persistCardTitle } from "./cardRename";
import { invoke, isTauri } from "@tauri-apps/api/core";
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(), isTauri: vi.fn() }));

describe("card rename", () => {
  it("trims names and restores the default label for blank input", () => {
    expect(normalizedCardTitle("  中文名称  ")).toBe("中文名称");
    expect(normalizedCardTitle(" \n\t ")).toBeNull();
  });
  it("accepts F2 and Ctrl+R, excluding composition and other modifiers", () => {
    const key = { key: "F2", ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, isComposing: false };
    expect(matchesRenameShortcut(key)).toBe(true);
    expect(matchesRenameShortcut({ ...key, key: "R", ctrlKey: true })).toBe(true);
    for (const modifier of ["metaKey", "altKey", "shiftKey", "isComposing"] as const) {
      expect(matchesRenameShortcut({ ...key, [modifier]: true })).toBe(false);
    }
  });
  it("requires a successful storage update, including when clearing the title", async () => {
    vi.mocked(isTauri).mockReturnValue(true);
    vi.mocked(invoke).mockResolvedValueOnce({ affected_count: 1 });
    await persistCardTitle("saved-id", null);
    expect(invoke).toHaveBeenLastCalledWith("rename_clipboard_item", { itemId: "saved-id", title: "" });
    vi.mocked(invoke).mockResolvedValueOnce({ affected_count: 0 });
    await expect(persistCardTitle("missing", "new")).rejects.toThrow();
  });
  it("keeps the optimistic title until success without restoring the old label", async () => {
    let complete!: () => void;
    const queue = new CardRenameQueue(() => new Promise<void>((resolve) => { complete = resolve; }));
    const update = vi.fn();
    const result = queue.save("one", null, "new", update, vi.fn());
    expect(update.mock.calls).toEqual([["new"]]);
    await Promise.resolve();
    complete();
    await result;
    expect(update.mock.calls).toEqual([["new"]]);
  });
  it("serializes edits and rolls the newest failure back to the last successful name", async () => {
    const persist = vi.fn().mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error());
    const queue = new CardRenameQueue(persist);
    const update = vi.fn(), failed = vi.fn();
    const first = queue.save("one", "old", "first", update, failed);
    const second = queue.save("one", "first", "second", update, failed);
    await Promise.all([first, second]);
    expect(persist.mock.calls).toEqual([["one", "first"], ["one", "second"]]);
    expect(update.mock.calls).toEqual([["first"], ["second"], ["first"]]);
    expect(failed).toHaveBeenCalledOnce();
  });
  it("does not let an earlier failure overwrite a newer edit", async () => {
    const queue = new CardRenameQueue(vi.fn().mockRejectedValueOnce(new Error()).mockResolvedValueOnce(undefined));
    const update = vi.fn(), failed = vi.fn();
    await Promise.all([queue.save("one", null, "first", update, failed), queue.save("one", "first", "second", update, failed)]);
    expect(update.mock.calls).toEqual([["first"], ["second"]]);
    expect(failed).not.toHaveBeenCalled();
  });
  it("rolls two failed saves back to the durable original", async () => {
    const queue = new CardRenameQueue(vi.fn().mockRejectedValue(new Error()));
    const update = vi.fn();
    await Promise.all([queue.save("one", null, "first", update, vi.fn()), queue.save("one", "first", "second", update, vi.fn())]);
    expect(update.mock.calls).toEqual([["first"], ["second"], [null]]);
  });
});
