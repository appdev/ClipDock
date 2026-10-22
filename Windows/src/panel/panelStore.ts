import { convertFileSrc, invoke, isTauri } from "@tauri-apps/api/core";
import type { ClipItem, ClipKind, PinboardFilter } from "./panelTypes";
import type { HistoryPage, HistoryScope, HistoryRepository } from "./historyController";

/// Mirror of `clipboard_core::ClipboardItemSummary` (serde snake_case fields).
export type ClipboardItemSummary = {
  id: string;
  custom_title?: string | null;
  item_type: "text" | "link" | "image" | "file" | "color" | "rich_text" | "unknown";
  summary: string;
  primary_text: string | null;
  content_hash: string;
  source_app_id: string | null;
  source_app_name: string | null;
  source_app_icon_path: string | null;
  source_app_icon_header_color: number | null;
  preview_asset_path: string | null;
  payload_asset_path: string | null;
  source_confidence: string;
  first_copied_at_ms: number;
  last_copied_at_ms: number;
  copy_count: number;
  is_pinned: boolean;
  pinboard_ids?: string[];
  size_bytes: number;
  preview_state: string;
  payload_state: string;
  file_items: Array<{ file_name: string; path: string }>;
  link_metadata: {
    canonical_url: string;
    display_url: string;
    host: string;
    title: string | null;
    site_name: string | null;
    icon_asset_path: string | null;
    image_asset_path: string | null;
  } | null;
};

/// `clipboard_core::ClipboardListEntry` flattens the summary. Text cards carry
/// only this bounded projection; copying retrieves the full item by ID.
export type ClipboardListEntry = ClipboardItemSummary & {
  text_preview: string | null;
  preview_truncated: boolean;
  trimmed_grapheme_count: number | null;
  scalar_count: number | null;
};

type ClipboardItemPage = {
  items: ClipboardListEntry[];
  total_count: number;
  has_more: boolean;
  revision: number;
};

export const historyRepository: HistoryRepository = {
  async list(scope: HistoryScope, limit: number, offset: number): Promise<HistoryPage> {
    const page = await invoke<ClipboardItemPage>("list_clipboard_entries", {
      itemType: scope.itemType === "richText" ? "rich_text" : scope.itemType,
      pinboardId: scope.pinboardId, searchText: scope.searchText || null, limit, offset
    });
    return {
      items: page.items.map((item, index) => summaryToClipItem(item, String(offset + index + 1))),
      totalCount: page.total_count, hasMore: page.has_more, revision: page.revision
    };
  },
  async pinboards(): Promise<PinboardFilter[]> {
    const page = await invoke<{ pinboards: Array<{ id: string; title: string; color_code: number }> }>("list_pinboards");
    return page.pinboards.map((board) => ({ id: board.id, label: board.title,
      color: `#${(board.color_code >>> 0).toString(16).padStart(8, "0").slice(-6)}` }));
  }
};

const KIND_FROM_STORAGE: Record<ClipboardItemSummary["item_type"], ClipKind> = {
  text: "text",
  link: "link",
  image: "image",
  file: "file",
  color: "color",
  rich_text: "richText",
  unknown: "text"
};

const TYPE_LABELS: Record<ClipKind, string> = {
  text: "Text",
  image: "Image",
  file: "File",
  link: "Link",
  color: "Color",
  richText: "Text"
};

const SOURCE_COLORS: Record<ClipKind, string> = {
  text: "#8e8e93",
  image: "#5ac8fa",
  file: "#34c759",
  link: "#0a84ff",
  color: "#ff9f0a",
  richText: "#af52de"
};

/// Load persisted clipboard history from the database. Returns an empty list
/// outside of Tauri (e.g. the Vite-only browser preview) so the panel still
/// renders.
export async function loadStoredPanelItems(limit = 100, searchText?: string, pinboardId?: string): Promise<ClipItem[]> {
  if (!isTauri()) {
    return [];
  }

  const page = await invoke<ClipboardItemPage>("list_clipboard_items", { limit, searchText, pinboardId });
  return page.items.map((summary, index) => summaryToClipItem(summary, String(index + 1)));
}

export async function loadStoredPinboards(): Promise<PinboardFilter[]> {
  if (!isTauri()) return [];
  const page = await invoke<{ pinboards: Array<{ id: string; title: string; color_code: number }> }>("list_pinboards");
  return page.pinboards.map((board) => ({
    id: board.id,
    label: board.title,
    color: `#${(board.color_code & 0xffffff).toString(16).padStart(6, "0")}`
  }));
}

export function mergeLoadedPanelItems(current: ClipItem[], stored: ClipItem[], atLoad: ClipItem[]): ClipItem[] {
  const previous = new Map(atLoad.map((item) => [item.id, item]));
  const currentById = new Map(current.map((item) => [item.id, item]));
  const storedIds = new Set(stored.map((item) => item.id));
  return [
    ...current.filter((item) => !previous.has(item.id) && !storedIds.has(item.id)),
    ...stored.map((item) => {
      const local = currentById.get(item.id);
      const before = previous.get(item.id);
      return local && before ? {
        ...item,
        customTitle: local.customTitle !== before.customTitle ? local.customTitle : item.customTitle,
        isPinned: local.isPinned !== before.isPinned ? local.isPinned : item.isPinned
      } : item;
    }),
    ...current.filter((item) => previous.has(item.id) && !storedIds.has(item.id))
  ];
}

export function summaryToClipItem(
  summary: ClipboardItemSummary | ClipboardListEntry,
  commandIndex: string,
  toAssetUrl: (path: string) => string = convertFileSrc
): ClipItem {
  const kind = KIND_FROM_STORAGE[summary.item_type] ?? "text";
  const title = deriveTitle(summary, kind);

  const item: ClipItem = {
    id: summary.id,
    kind,
    typeLabel: TYPE_LABELS[kind],
    customTitle: summary.custom_title ?? null,
    relativeTime: relativeTimeFrom(summary.last_copied_at_ms),
    title,
    summary: cardText(summary),
    footer: deriveFooter(summary, kind),
    commandIndex,
    isPinned: summary.is_pinned,
    sourceName: summary.source_app_name ?? "Clipboard",
    sourceKind: "clipboard",
    sourceColor: SOURCE_COLORS[kind],
    selectedColor: "#0a84ff",
    pinboardIds: summary.pinboard_ids ?? [],
    preview: derivePreview(summary, kind, toAssetUrl)
  };

  if (summary.source_app_icon_path) {
    item.sourceIconAssetPath = summary.source_app_icon_path;
    item.sourceIconAssetUrl = toAssetUrl(summary.source_app_icon_path);
  }

  return item;
}

function cardText(summary: ClipboardItemSummary | ClipboardListEntry): string {
  return ("text_preview" in summary ? summary.text_preview : null) ?? summary.primary_text ?? summary.summary;
}

function deriveTitle(summary: ClipboardItemSummary | ClipboardListEntry, kind: ClipKind): string {
  if (kind === "link" && summary.link_metadata?.canonical_url) {
    try {
      return new URL(summary.link_metadata.canonical_url).hostname.replace(/^www\./i, "");
    } catch {
      return summary.summary;
    }
  }
  if (kind === "image") {
    return "剪贴板图片";
  }
  const source = cardText(summary);
  return truncateText(firstVisibleLine(source), 30);
}

function deriveFooter(summary: ClipboardItemSummary | ClipboardListEntry, kind: ClipKind): string {
  if (kind === "text" || kind === "richText") {
    const count = "scalar_count" in summary ? summary.scalar_count : null;
    return `${count ?? Array.from(cardText(summary)).length} characters`;
  }
  if (kind === "link" && summary.link_metadata?.canonical_url) {
    try {
      return new URL(summary.link_metadata.canonical_url).hostname.replace(/^www\./i, "");
    } catch {
      return summary.summary;
    }
  }
  if (kind === "file") {
    return summary.file_items[0]?.file_name ?? "File";
  }
  return summary.summary;
}

function derivePreview(
  summary: ClipboardItemSummary,
  kind: ClipKind,
  toAssetUrl: (path: string) => string
): ClipItem["preview"] {
  if (kind === "image" && summary.payload_asset_path) {
    return {
      imageTone: "captured",
      imageAssetPath: summary.payload_asset_path,
      imageAssetUrl: summary.preview_asset_path && summary.preview_asset_path !== summary.payload_asset_path
        ? toAssetUrl(summary.preview_asset_path) : undefined
    };
  }
  if (kind === "link" && summary.link_metadata) {
    const meta = summary.link_metadata;
    let domain: string | undefined;
    if (meta.canonical_url) {
      try {
        domain = new URL(meta.canonical_url).hostname.replace(/^www\./i, "");
      } catch {
        domain = undefined;
      }
    }
    return {
      url: meta.canonical_url || undefined,
      domain,
      linkIconAssetPath: meta.icon_asset_path ?? undefined,
      linkIconAssetUrl: meta.icon_asset_path ? toAssetUrl(meta.icon_asset_path) : undefined,
      linkPreviewAssetPath: meta.image_asset_path ?? undefined,
      linkPreviewAssetUrl: meta.image_asset_path ? toAssetUrl(meta.image_asset_path) : undefined
    };
  }
  if (kind === "color") {
    return { colorValue: summary.summary };
  }
  if (kind === "file") {
    return { filePath: summary.file_items[0]?.path ?? summary.summary };
  }
  return undefined;
}

function relativeTimeFrom(timestampMs: number): string {
  const deltaSeconds = Math.max(0, Math.round((Date.now() - timestampMs) / 1000));
  if (deltaSeconds < 60) {
    return "now";
  }
  const minutes = Math.round(deltaSeconds / 60);
  if (minutes < 60) {
    return `${minutes}m`;
  }
  const hours = Math.round(minutes / 60);
  if (hours < 24) {
    return `${hours}h`;
  }
  const days = Math.round(hours / 24);
  return `${days}d`;
}

function firstVisibleLine(value: string): string {
  return value.split(/\r?\n/).find((line) => line.trim().length > 0)?.trim() ?? "剪贴板文本";
}

function truncateText(value: string, maxLength: number): string {
  const characters = Array.from(value);
  if (characters.length <= maxLength) {
    return value;
  }
  return `${characters.slice(0, maxLength - 1).join("")}…`;
}
