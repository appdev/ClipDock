export type ClipKind = "text" | "image" | "file" | "link" | "color" | "richText";

export type SourceKind =
  | "clipboard"
  | "notes"
  | "chrome"
  | "photos"
  | "finder"
  | "safari"
  | "color"
  | "xcode"
  | "textedit"
  | "terminal";

export type ClipItem = {
  id: string;
  kind: ClipKind;
  typeLabel: string;
  relativeTime: string;
  title: string;
  summary: string;
  footer: string;
  commandIndex: string;
  isPinned?: boolean;
  sourceName: string;
  sourceKind: SourceKind;
  sourcePathHints?: {
    macos?: string[];
    windows?: string[];
  };
  sourceIconAssetPath?: string;
  sourceIconAssetUrl?: string;
  sourceIconHeaderColor?: string;
  sourceColor: string;
  selectedColor: string;
  pinboardIds: string[];
  preview?: {
    domain?: string;
    url?: string;
    colorValue?: string;
    filePath?: string;
    imageTone?: "water" | "document" | "github" | "code" | "clipboard" | "captured";
    imageAssetPath?: string;
    imageAssetUrl?: string;
    linkIconAssetPath?: string;
    linkIconAssetUrl?: string;
    linkPreviewAssetPath?: string;
    linkPreviewAssetUrl?: string;
  };
};

export type TypeFilter = {
  id: "all" | ClipKind;
  label: string;
};

export type PinboardFilter = {
  id: string;
  label: string;
  color: string;
};
