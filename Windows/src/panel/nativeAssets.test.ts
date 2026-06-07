import { describe, expect, it } from "vitest";
import {
  applyResolvedPanelAssets,
  mergePanelNativeAssets,
  panelNativeAssetRequests,
  type PanelNativeAssetResolution
} from "./nativeAssets";
import type { ClipItem } from "./panelTypes";

const baseItem: ClipItem = {
  id: "link-github",
  kind: "link",
  typeLabel: "Link",
  relativeTime: "8m ago",
  title: "Original title",
  summary: "Original summary",
  footer: "github.com",
  commandIndex: "1",
  sourceName: "Safari",
  sourceKind: "safari",
  sourceColor: "#635bff",
  selectedColor: "#0a84ff",
  pinboardIds: ["release"],
  sourcePathHints: {
    macos: ["/Applications/Safari.app"],
    windows: ["{ProgramFiles}\\Microsoft\\Edge\\Application\\msedge.exe"]
  },
  preview: {
    domain: "github.com",
    url: "https://github.com/"
  }
};

describe("panel native assets", () => {
  it("creates Tauri requests from panel items", () => {
    expect(panelNativeAssetRequests([baseItem])).toEqual([
      {
        itemId: "link-github",
        sourceName: "Safari",
        sourceKind: "safari",
        sourcePathHints: baseItem.sourcePathHints,
        linkUrl: "https://github.com/"
      }
    ]);
  });

  it("merges native source and link assets without losing fallbacks", () => {
    const resolution: PanelNativeAssetResolution = {
      items: [
        {
          itemId: "link-github",
          sourceIconPath: "/tmp/safari.png",
          sourceIconHeaderColor: "#123456",
          linkIconPath: "/tmp/favicon.png",
          linkPreviewPath: "/tmp/preview.png",
          linkTitle: "Fetched title",
          linkDomain: "github.com"
        }
      ]
    };

    const [merged] = mergePanelNativeAssets([baseItem], resolution, (path) => `asset://${path}`);

    expect(merged.title).toBe("Fetched title");
    expect(merged.sourceColor).toBe("#123456");
    expect(merged.sourceIconAssetUrl).toBe("asset:///tmp/safari.png");
    expect(merged.preview?.linkIconAssetUrl).toBe("asset:///tmp/favicon.png");
    expect(merged.preview?.linkPreviewAssetUrl).toBe("asset:///tmp/preview.png");
  });

  it("applies resolved assets by id without restoring deleted items", () => {
    const resolved = {
      ...baseItem,
      sourceColor: "#123456",
      sourceIconAssetUrl: "asset:///tmp/safari.png"
    };
    const created: ClipItem = {
      ...baseItem,
      id: "created-text-1",
      kind: "text",
      title: "新增剪贴内容 1"
    };

    const merged = applyResolvedPanelAssets([created], [resolved]);

    expect(merged).toEqual([created]);
  });
});
