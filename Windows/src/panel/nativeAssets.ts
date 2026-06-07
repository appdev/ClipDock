import { convertFileSrc, invoke, isTauri } from "@tauri-apps/api/core";
import type { ClipItem } from "./panelTypes";

export type PanelNativeAssetRequest = {
  itemId: string;
  sourceName: string;
  sourceKind: string;
  sourcePathHints?: {
    macos?: string[];
    windows?: string[];
  };
  linkUrl?: string;
};

export type PanelNativeAsset = {
  itemId: string;
  sourceIconPath?: string;
  sourceIconHeaderColor?: string;
  sourceIconError?: string;
  linkIconPath?: string;
  linkPreviewPath?: string;
  linkTitle?: string;
  linkDomain?: string;
  linkError?: string;
};

export type PanelNativeAssetResolution = {
  items: PanelNativeAsset[];
};

type FileSrcConverter = (path: string) => string;

export function panelNativeAssetRequests(items: ClipItem[]): PanelNativeAssetRequest[] {
  return items.map((item) => ({
    itemId: item.id,
    sourceName: item.sourceName,
    sourceKind: item.sourceKind,
    sourcePathHints: item.sourcePathHints,
    linkUrl: item.kind === "link" ? item.preview?.url : undefined
  }));
}

export function mergePanelNativeAssets(
  items: ClipItem[],
  resolution: PanelNativeAssetResolution,
  toAssetUrl: FileSrcConverter
): ClipItem[] {
  const assetsByItem = new Map(resolution.items.map((item) => [item.itemId, item]));

  return items.map((item) => {
    const assets = assetsByItem.get(item.id);
    if (!assets) {
      return item;
    }

    const sourceIconAssetUrl = assets.sourceIconPath
      ? toAssetUrl(assets.sourceIconPath)
      : item.sourceIconAssetUrl;
    const linkIconAssetUrl = assets.linkIconPath
      ? toAssetUrl(assets.linkIconPath)
      : item.preview?.linkIconAssetUrl;
    const linkPreviewAssetUrl = assets.linkPreviewPath
      ? toAssetUrl(assets.linkPreviewPath)
      : item.preview?.linkPreviewAssetUrl;

    return {
      ...item,
      title: item.kind === "link" && assets.linkTitle ? assets.linkTitle : item.title,
      footer: item.kind === "link" && assets.linkDomain ? assets.linkDomain : item.footer,
      sourceColor: assets.sourceIconHeaderColor ?? item.sourceColor,
      sourceIconAssetPath: assets.sourceIconPath ?? item.sourceIconAssetPath,
      sourceIconAssetUrl,
      sourceIconHeaderColor: assets.sourceIconHeaderColor ?? item.sourceIconHeaderColor,
      preview: {
        ...item.preview,
        domain: assets.linkDomain ?? item.preview?.domain,
        linkIconAssetPath: assets.linkIconPath ?? item.preview?.linkIconAssetPath,
        linkIconAssetUrl,
        linkPreviewAssetPath: assets.linkPreviewPath ?? item.preview?.linkPreviewAssetPath,
        linkPreviewAssetUrl
      }
    };
  });
}

export function applyResolvedPanelAssets(currentItems: ClipItem[], resolvedItems: ClipItem[]): ClipItem[] {
  const resolvedByItem = new Map(resolvedItems.map((item) => [item.id, item]));

  return currentItems.map((item) => {
    const resolved = resolvedByItem.get(item.id);
    if (!resolved) {
      return item;
    }

    return {
      ...item,
      title: item.kind === "link" ? resolved.title : item.title,
      footer: item.kind === "link" ? resolved.footer : item.footer,
      sourceColor: resolved.sourceColor,
      sourceIconAssetPath: resolved.sourceIconAssetPath,
      sourceIconAssetUrl: resolved.sourceIconAssetUrl,
      sourceIconHeaderColor: resolved.sourceIconHeaderColor,
      preview: {
        ...item.preview,
        domain: resolved.preview?.domain ?? item.preview?.domain,
        linkIconAssetPath: resolved.preview?.linkIconAssetPath ?? item.preview?.linkIconAssetPath,
        linkIconAssetUrl: resolved.preview?.linkIconAssetUrl ?? item.preview?.linkIconAssetUrl,
        linkPreviewAssetPath:
          resolved.preview?.linkPreviewAssetPath ?? item.preview?.linkPreviewAssetPath,
        linkPreviewAssetUrl:
          resolved.preview?.linkPreviewAssetUrl ?? item.preview?.linkPreviewAssetUrl
      }
    };
  });
}

export async function resolvePanelNativeAssets(items: ClipItem[]): Promise<ClipItem[]> {
  if (!isTauri()) {
    return items;
  }

  const resolution = await invoke<PanelNativeAssetResolution>("resolve_panel_native_assets", {
    requests: panelNativeAssetRequests(items)
  });
  return mergePanelNativeAssets(items, resolution, convertFileSrc);
}
