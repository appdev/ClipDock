import { describe, expect, it } from "vitest";
import {
  bottomPanelFrame,
  clampedPanelHeight,
  itemSideLength,
  resizedPanelHeight
} from "./panelGeometry";

describe("panel geometry", () => {
  it("applies macOS bottom-panel margins and clamps height", () => {
    const frame = bottomPanelFrame(
      { x: -1440, y: -40, width: 1440, height: 900 },
      999
    );

    expect(frame).toEqual({
      x: -1430,
      y: -30,
      width: 1420,
      height: 270
    });
  });

  it("uses the screen-height ratio without a fixed ceiling", () => {
    expect(clampedPanelHeight(999, 3000)).toBe(900);
  });

  it("never falls below the minimum height on short screens", () => {
    expect(clampedPanelHeight(120, 400)).toBe(260);
    expect(clampedPanelHeight(600, 400)).toBe(260);
  });

  it("resizes only within panel bounds", () => {
    expect(resizedPanelHeight(320, 120, 1200)).toBe(360);
    expect(resizedPanelHeight(320, -300, 1200)).toBe(260);
  });

  it("keeps card sides consistent with the macOS panel height contract", () => {
    expect(itemSideLength(320)).toBe(218);
    expect(itemSideLength(260)).toBe(174);
  });
});
