import { beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { loadStoredPanelItems, loadStoredPinboards } from "./panelStore";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(), isTauri: () => true, convertFileSrc: (path: string) => path }));
beforeEach(() => vi.mocked(invoke).mockReset());

it("displays imported pinboard names and colors from storage", async () => {
  vi.mocked(invoke).mockResolvedValue({ pinboards: [{ id: "restored", title: "工作收藏", color_code: 0xffff453a }] });
  expect(await loadStoredPinboards()).toEqual([{ id: "restored", label: "工作收藏", color: "#ff453a" }]);
});

it("loads imported pinboard contents using the native pinboard filter", async () => {
  vi.mocked(invoke).mockResolvedValue({ items: [], total_count: 0, has_more: false });
  expect(await loadStoredPanelItems(100, "", "restored")).toEqual([]);
  expect(invoke).toHaveBeenCalledWith("list_clipboard_items", { limit: 100, searchText: "", pinboardId: "restored" });
});
