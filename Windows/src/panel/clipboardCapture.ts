import { convertFileSrc, invoke, isTauri } from "@tauri-apps/api/core";
import type { ClipItem, ClipKind } from "./panelTypes";

export type ClipboardSnapshot = {
  changeKey: string;
  kind: "text" | "image";
  text?: string | null;
  imagePath?: string | null;
  imageWidth?: number | null;
  imageHeight?: number | null;
};

export type ClipboardCaptureDecision = {
  shouldCapture: boolean;
  reason?: "empty" | "self-write" | "duplicate";
};

export type ClipboardWritePayload =
  | {
      kind: "text";
      text: string;
    }
  | {
      kind: "image";
      imagePath: string;
    };

type FileSrcConverter = (path: string) => string;

const SOURCE_COLORS: Record<ClipKind, string> = {
  text: "#8e8e93",
  image: "#5ac8fa",
  file: "#34c759",
  link: "#0a84ff",
  color: "#ff9f0a",
  richText: "#af52de"
};

const TYPE_LABELS: Record<ClipKind, string> = {
  text: "Text",
  image: "Image",
  file: "File",
  link: "Link",
  color: "Color",
  richText: "Text"
};

export async function readClipboardSnapshot(): Promise<ClipboardSnapshot | null> {
  if (!isTauri()) {
    return null;
  }

  return invoke<ClipboardSnapshot | null>("read_clipboard_snapshot");
}

export async function writeClipboardText(text: string): Promise<string | null> {
  if (!isTauri()) {
    return null;
  }

  return invoke<string>("write_clipboard_text", { text });
}

export async function writeClipboardImage(imagePath: string): Promise<string | null> {
  if (!isTauri()) {
    return null;
  }

  return invoke<string>("write_clipboard_image", { imagePath });
}

export function clipboardPayloadForItem(item: ClipItem): ClipboardWritePayload | null {
  if (item.kind === "image" && item.preview?.imageAssetPath) {
    return {
      kind: "image",
      imagePath: item.preview.imageAssetPath
    };
  }
  if (item.kind === "link") {
    return {
      kind: "text",
      text: item.preview?.url ?? item.summary
    };
  }
  if (item.kind === "color") {
    return {
      kind: "text",
      text: item.preview?.colorValue ?? item.summary
    };
  }
  if (item.kind === "image") {
    return {
      kind: "text",
      text: item.summary
    };
  }
  if (item.kind === "file") {
    return {
      kind: "text",
      text: item.preview?.filePath ?? item.summary
    };
  }
  return {
    kind: "text",
    text: item.summary
  };
}

export function clipboardCaptureDecision(
  snapshot: ClipboardSnapshot | null,
  capturedKeys: ReadonlySet<string>,
  selfWriteKey: string | null
): ClipboardCaptureDecision {
  if (!snapshot || !snapshot.changeKey) {
    return { shouldCapture: false, reason: "empty" };
  }
  if (snapshot.changeKey === selfWriteKey) {
    return { shouldCapture: false, reason: "self-write" };
  }
  if (capturedKeys.has(snapshot.changeKey)) {
    return { shouldCapture: false, reason: "duplicate" };
  }
  if (snapshot.kind === "text" && (snapshot.text ?? "").trim().length === 0) {
    return { shouldCapture: false, reason: "empty" };
  }
  if (snapshot.kind === "image" && !snapshot.imagePath) {
    return { shouldCapture: false, reason: "empty" };
  }
  return { shouldCapture: true };
}

export function clipboardSnapshotToPanelItem(
  snapshot: ClipboardSnapshot,
  commandIndex: string,
  toAssetUrl: FileSrcConverter = convertFileSrc
): ClipItem | null {
  if (snapshot.kind === "image") {
    if (!snapshot.imagePath) {
      return null;
    }
    const width = Math.max(0, Math.round(snapshot.imageWidth ?? 0));
    const height = Math.max(0, Math.round(snapshot.imageHeight ?? 0));
    const footer = width > 0 && height > 0 ? `${width} x ${height}` : "Image";
    return baseClipboardItem({
      snapshot,
      kind: "image",
      commandIndex,
      title: "剪贴板图片",
      summary: footer,
      footer,
      preview: {
        imageTone: "captured",
        imageAssetPath: snapshot.imagePath,
        imageAssetUrl: toAssetUrl(snapshot.imagePath)
      }
    });
  }

  const text = snapshot.text ?? "";
  const displayText = text.trim();
  if (!displayText) {
    return null;
  }

  const url = remoteHttpUrl(displayText);
  if (url) {
    const domain = url.hostname.replace(/^www\./i, "");
    return baseClipboardItem({
      snapshot,
      kind: "link",
      commandIndex,
      title: domain,
      summary: url.href,
      footer: domain,
      preview: {
        domain,
        url: url.href
      }
    });
  }

  const colorValue = normalizedHexColor(displayText);
  if (colorValue) {
    return baseClipboardItem({
      snapshot,
      kind: "color",
      commandIndex,
      title: colorValue,
      summary: colorValue,
      footer: colorValue,
      sourceColor: colorValue,
      preview: {
        colorValue
      }
    });
  }

  const title = truncateText(firstVisibleLine(displayText), 30);
  return baseClipboardItem({
    snapshot,
    kind: "text",
    commandIndex,
    title,
    summary: text,
    footer: `${Array.from(text).length} characters`
  });
}

function baseClipboardItem({
  snapshot,
  kind,
  commandIndex,
  title,
  summary,
  footer,
  sourceColor,
  preview
}: {
  snapshot: ClipboardSnapshot;
  kind: ClipKind;
  commandIndex: string;
  title: string;
  summary: string;
  footer: string;
  sourceColor?: string;
  preview?: ClipItem["preview"];
}): ClipItem {
  return {
    id: `clipboard-${snapshot.changeKey.slice(0, 18)}`,
    kind,
    typeLabel: TYPE_LABELS[kind],
    relativeTime: "now",
    title,
    summary,
    footer,
    commandIndex,
    sourceName: "Clipboard",
    sourceKind: "clipboard",
    sourceColor: sourceColor ?? SOURCE_COLORS[kind],
    selectedColor: "#0a84ff",
    pinboardIds: ["product"],
    preview
  };
}

function remoteHttpUrl(value: string): URL | null {
  if (/\s/.test(value)) {
    return null;
  }
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:" ? url : null;
  } catch {
    return null;
  }
}

function normalizedHexColor(value: string): string | null {
  const match = /^#?([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(value);
  if (!match) {
    return null;
  }

  const hex = match[1].toUpperCase();
  if (hex.length === 3) {
    return `#${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}`;
  }
  return `#${hex}`;
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
