import { describe, expect, it } from "vitest";
import { summaryToClipItem, type ClipboardItemSummary, type ClipboardListEntry } from "./panelStore";
import { clipboardPayloadForItem } from "./clipboardCapture";
import contractFixture from "./fixtures/clipboard-list-entries.json";

const summary = { id: "item_authoritative", item_type: "image", summary: "image", primary_text: null,
  last_copied_at_ms: 0, is_pinned: true, pinboard_ids: ["default", "work"],
  payload_asset_path: "/assets/full.png", preview_asset_path: "/thumbnails/small.png",
  source_app_name: null, source_app_icon_path: null, file_items: [], link_metadata: null
} as unknown as ClipboardItemSummary;

describe("authoritative summary mapper", () => {
  it("consumes the real Rust lightweight serde contract without restoring full text", () => {
    const entries = contractFixture as ClipboardListEntry[];
    const text = entries.find((entry) => entry.item_type === "text")!;
    const item = summaryToClipItem(text, "1");
    expect(text.primary_text).toBeNull();
    expect(text.preview_truncated).toBe(true);
    expect(item.summary).toBe(text.text_preview);
    expect(item.summary).not.toContain("tail outside preview");
    expect(item.footer).toBe(`${text.scalar_count} characters`);
    expect(text.scalar_count).toBeGreaterThan(Array.from(item.summary).length);
    const link = summaryToClipItem(entries.find((entry) => entry.item_type === "link")!, "2");
    expect(link.preview?.url).toBe("https://example.test/docs?q=1");
    expect(link.preview?.domain).toBe("example.test");
    expect(link.footer).toBe("example.test");
  });
  it("uses thumbnails for cards and preserves full payload only for copying", () => {
    const item = summaryToClipItem(summary, "93", (path) => `asset:${path}`);
    expect(item.id).toBe(summary.id); expect(item.pinboardIds).toEqual(["default", "work"]);
    expect(item.preview?.imageAssetUrl).toBe("asset:/thumbnails/small.png");
    expect(clipboardPayloadForItem(item)).toEqual({ kind: "image", imagePath: "/assets/full.png" });
  });
  it("never loads a full legacy payload as a card preview", () => {
    for (const preview of [null, summary.payload_asset_path]) {
      expect(summaryToClipItem({ ...summary, preview_asset_path: preview }, "1").preview?.imageAssetUrl).toBeUndefined();
    }
  });
});
