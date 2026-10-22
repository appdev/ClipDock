import { describe, expect, it, vi } from "vitest";
import { HistoryController, type HistoryPage, type HistoryRepository } from "./historyController";
import { panelItems } from "./panelData";

const item = (id: string) => ({ ...panelItems[0], id });
const page = (ids: string[], revision = 1, hasMore = false): HistoryPage => ({ items: ids.map(item), revision, hasMore, totalCount: hasMore ? 800 : ids.length });
const settle = async () => { for (let index = 0; index < 12; index++) await Promise.resolve(); };
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>((done) => { resolve = done; }); return { resolve, promise }; }
function repository(list: HistoryRepository["list"]): HistoryRepository { return { list, pinboards: async () => [] }; }

describe("database history controller", () => {
  it("discards old scope responses and combines filter/search in the database request", async () => {
    const old = deferred<HistoryPage>();
    const list = vi.fn().mockReturnValueOnce(old.promise).mockResolvedValue(page(["new"]));
    const controller = new HistoryController(repository(list));
    controller.start();
    controller.setScope({ itemType: "image", pinboardId: "board", searchText: "完整查询" });
    old.resolve(page(["old"])); await settle();
    expect(list).toHaveBeenLastCalledWith({ itemType: "image", pinboardId: "board", searchText: "完整查询" }, 50, 0);
    expect(controller.snapshot().items.map((item) => item.id)).toEqual(["new"]);
  });

  it("coalesces changes during an in-flight query and never publishes its stale page", async () => {
    const first = deferred<HistoryPage>();
    const list = vi.fn().mockReturnValueOnce(first.promise).mockResolvedValue(page(["committed"], 9));
    const controller = new HistoryController(repository(list));
    const published: string[][] = [];
    controller.subscribe(() => published.push(controller.snapshot().items.map((item) => item.id)));
    controller.start(); controller.invalidate(2); controller.invalidate(9);
    first.resolve(page(["stale"], 1)); await settle();
    expect(list).toHaveBeenCalledTimes(2);
    expect(published.flat()).not.toContain("stale");
    expect(controller.snapshot().revision).toBe(9);
    controller.invalidate(8); await settle(); expect(list).toHaveBeenCalledTimes(2);
  });

  it("refreshes the complete explicitly loaded window in <=200-row requests atomically", async () => {
    let revision = 1;
    const list = vi.fn(async (_scope, limit: number, offset: number) => page(Array.from({ length: limit }, (_, i) => `${revision}-${offset + i}`), revision, true));
    const controller = new HistoryController(repository(list));
    controller.start(); await settle();
    for (let index = 0; index < 4; index++) await controller.loadMore();
    expect(controller.snapshot().items).toHaveLength(250);
    list.mockClear(); revision = 2;
    const sizes: number[] = [];
    controller.subscribe(() => sizes.push(controller.snapshot().items.length));
    controller.invalidate(2); await settle();
    expect(list.mock.calls.map((args) => [args[1], args[2]])).toEqual([[200, 0], [50, 200]]);
    expect(sizes.every((size) => size === 250)).toBe(true);
    expect(controller.snapshot().items[249].id).toBe("2-249");
  });

  it("keeps the old window after refresh failure and blocks stale-offset pagination until retry", async () => {
    const list = vi.fn().mockResolvedValueOnce(page(Array.from({ length: 50 }, (_, i) => i === 0 ? "kept" : `row-${i}`), 1, true)).mockRejectedValueOnce(new Error("database busy")).mockResolvedValue(page(["recovered"], 2));
    const controller = new HistoryController(repository(list));
    controller.start(); await settle(); controller.invalidate(2); await settle();
    expect(controller.snapshot().items[0].id).toBe("kept");
    expect(controller.snapshot().error).toBeTruthy();
    await controller.loadMore(); expect(list).toHaveBeenCalledTimes(2);
    controller.refresh(); await settle(); expect(controller.snapshot().items[0].id).toBe("recovered");
  });

  it("does not append a page from another revision or after changing the scope", async () => {
    const later = deferred<HistoryPage>();
    const list = vi.fn().mockResolvedValueOnce(page(Array.from({ length: 50 }, (_, i) => `first-${i}`), 1, true)).mockReturnValueOnce(later.promise).mockResolvedValue(page(["board-item"], 3));
    const controller = new HistoryController(repository(list));
    controller.start(); await settle(); const loading = controller.loadMore();
    controller.setScope({ itemType: null, pinboardId: "board", searchText: "" }); await settle();
    later.resolve(page(["wrong-offset"], 2)); await loading;
    expect(controller.snapshot().items.map((item) => item.id)).toEqual(["board-item"]);
  });
});
