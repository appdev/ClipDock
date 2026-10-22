import { describe, expect, it } from "vitest";
import { cardOffset, mountedCardIndices, railWidth, scrollForIndex, virtualRange } from "./virtualRail";

describe("fixed-size horizontal virtual rail", () => {
  it("keeps only one offscreen editing card mounted until editing ends", () => {
    expect(mountedCardIndices(5000, 20, 30, 0)).toEqual([0, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29]);
    expect(mountedCardIndices(5000, 20, 30, 25)).toHaveLength(10);
    expect(mountedCardIndices(5000, 20, 30, -1)).toHaveLength(10);
    expect(mountedCardIndices(0, 0, 0, 0)).toEqual([]);
  });
  it("retains geometry while bounding mounted cards independently of history size", () => {
    expect(cardOffset(3, 218)).toBe(22 + 3 * 242);
    expect(railWidth(3, 218)).toBe(44 + 3 * 218 + 2 * 24);
    for (const count of [100, 5000, 100000]) {
      const range = virtualRange(count, 218, 242 * 20, 1280);
      expect(range.end - range.start).toBeLessThanOrEqual(11);
      expect(range.start).toBeLessThanOrEqual(20);
      expect(range.end).toBeGreaterThan(25);
    }
  });
  it("scrolls keyboard-selected absolute indices into view, including a far shortcut", () => {
    const left = scrollForIndex(90, 174, 0, 800);
    const range = virtualRange(100, 174, left, 800);
    expect(range.start).toBeLessThanOrEqual(90); expect(range.end).toBeGreaterThan(90);
    expect(scrollForIndex(0, 174, left, 800)).toBe(0);
    expect(virtualRange(0, 174, 0, 800)).toEqual({ start: 0, end: 0 });
  });
});
