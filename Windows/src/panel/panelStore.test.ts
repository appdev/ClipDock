import { expect, it } from "vitest";
import { summaryToClipItem, type ClipboardItemSummary } from "./panelStore";
import { clipboardPayloadForItem, clipboardSnapshotToPanelItem } from "./clipboardCapture";

const summary: ClipboardItemSummary = {
  id: "database-id", item_type: "text", custom_title: "工作资料", summary: "original content",
  primary_text: "original content", content_hash: "hash", source_app_id: null, source_app_name: null,
  source_app_icon_path: null, source_app_icon_header_color: null, preview_asset_path: null,
  payload_asset_path: null, source_confidence: "unknown", first_copied_at_ms: 0, last_copied_at_ms: 0,
  copy_count: 1, is_pinned: false, size_bytes: 16, preview_state: "none", payload_state: "none",
  file_items: [], link_metadata: null
};

it("loads custom labels separately from the original clipboard contents", () => {
  const item = summaryToClipItem(summary, "1");
  expect(item.customTitle).toBe("工作资料");
  expect(item.title).toBe("original content");
  expect(clipboardPayloadForItem(item)).toEqual({ kind: "text", text: "original content" });
  expect(summaryToClipItem({ ...summary, custom_title: undefined }, "1").customTitle).toBeNull();
});

it("uses the persisted id and title for new captures, retaining link detection", () => {
  const item = clipboardSnapshotToPanelItem({ changeKey: "temporary-key", kind: "text",
    text: "https://example.com", storedItem: summary }, "1");
  expect(item?.id).toBe("database-id");
  expect(item?.customTitle).toBe("工作资料");
  expect(item?.kind).toBe("link");
  expect(clipboardPayloadForItem(item!)).toEqual({ kind: "text", text: "https://example.com/" });
});
