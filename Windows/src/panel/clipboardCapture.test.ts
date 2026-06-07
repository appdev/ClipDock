import { describe, expect, it } from "vitest";
import {
  clipboardCaptureDecision,
  clipboardPayloadForItem,
  clipboardSnapshotToPanelItem,
  type ClipboardSnapshot
} from "./clipboardCapture";

const textSnapshot = (text: string, changeKey = "text-key"): ClipboardSnapshot => ({
  changeKey,
  kind: "text",
  text
});

describe("clipboard capture", () => {
  it("turns a remote URL into a link item", () => {
    const item = clipboardSnapshotToPanelItem(
      textSnapshot("https://github.com/openai/codex", "url-key"),
      "1",
      (path) => `asset://${path}`
    );

    expect(item?.id).toBe("clipboard-url-key");
    expect(item?.kind).toBe("link");
    expect(item?.title).toBe("github.com");
    expect(item?.preview?.url).toBe("https://github.com/openai/codex");
  });

  it("turns a hex value into a color item", () => {
    const item = clipboardSnapshotToPanelItem(textSnapshot("#12a4ff", "color-key"), "2");

    expect(item?.kind).toBe("color");
    expect(item?.summary).toBe("#12A4FF");
    expect(item?.preview?.colorValue).toBe("#12A4FF");
    expect(item?.sourceColor).toBe("#12A4FF");
  });

  it("turns ordinary clipboard text into a text item", () => {
    const item = clipboardSnapshotToPanelItem(
      textSnapshot("ClipDock captured text\nsecond line", "plain-key"),
      "3"
    );

    expect(item?.kind).toBe("text");
    expect(item?.title).toBe("ClipDock captured text");
    expect(item?.footer).toBe("34 characters");
  });

  it("turns an image snapshot into an image item with an asset URL", () => {
    const item = clipboardSnapshotToPanelItem(
      {
        changeKey: "image-key",
        kind: "image",
        imagePath: "/tmp/clipboard.png",
        imageWidth: 320,
        imageHeight: 180
      },
      "4",
      (path) => `asset://${path}`
    );

    expect(item?.kind).toBe("image");
    expect(item?.footer).toBe("320 x 180");
    expect(item?.preview?.imageAssetPath).toBe("/tmp/clipboard.png");
    expect(item?.preview?.imageAssetUrl).toBe("asset:///tmp/clipboard.png");
  });

  it("skips duplicate, empty, and app self-written snapshots", () => {
    const capturedKeys = new Set(["existing"]);

    expect(clipboardCaptureDecision(null, capturedKeys, null).reason).toBe("empty");
    expect(clipboardCaptureDecision(textSnapshot("   ", "blank"), capturedKeys, null).reason).toBe(
      "empty"
    );
    expect(clipboardCaptureDecision(textSnapshot("value", "existing"), capturedKeys, null).reason)
      .toBe("duplicate");
    expect(clipboardCaptureDecision(textSnapshot("value", "own"), capturedKeys, "own").reason).toBe(
      "self-write"
    );
    expect(clipboardCaptureDecision(textSnapshot("value", "new"), capturedKeys, null).shouldCapture)
      .toBe(true);
  });

  it("copies URLs and captured images as their native clipboard payloads", () => {
    const link = clipboardSnapshotToPanelItem(textSnapshot("https://example.com", "url"), "1");
    const image = clipboardSnapshotToPanelItem(
      {
        changeKey: "image",
        kind: "image",
        imagePath: "/tmp/image.png",
        imageWidth: 10,
        imageHeight: 10
      },
      "2",
      (path) => path
    );

    expect(link && clipboardPayloadForItem(link)).toEqual({
      kind: "text",
      text: "https://example.com/"
    });
    expect(image && clipboardPayloadForItem(image)).toEqual({
      kind: "image",
      imagePath: "/tmp/image.png"
    });
  });
});
