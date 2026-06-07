import type { ClipItem, PinboardFilter, TypeFilter } from "./panelTypes";

export const typeFilters: TypeFilter[] = [
  { id: "all", label: "剪贴板" },
  { id: "text", label: "文本" },
  { id: "image", label: "图片" },
  { id: "file", label: "文件" },
  { id: "link", label: "链接" },
  { id: "color", label: "颜色" },
  { id: "richText", label: "富文本" }
];

export const pinboardFilters: PinboardFilter[] = [
  { id: "product", label: "产品资料", color: "#ff453a" },
  { id: "design", label: "设计参考", color: "#e64a00" },
  { id: "release", label: "发布说明", color: "#c244df" },
  { id: "customers", label: "客户资料归档", color: "#4f37f5" }
];

export const panelItems: ClipItem[] = [
  {
    id: "snapshot-text",
    kind: "text",
    typeLabel: "Text",
    relativeTime: "22h ago",
    title: "UgAdaptiveDialog",
    summary:
      "UgAdaptiveDialog(\n    modifier =\nugAdaptiveDialogModifier,\n    visible =\nisShowScanDeviceDialog,\n    dismissOnSwipeDown =\nfalse\n)",
    footer: "129 characters",
    commandIndex: "1",
    sourceName: "Chrome",
    sourceKind: "chrome",
    sourcePathHints: {
      macos: ["/Applications/Google Chrome.app"],
      windows: [
        "{ProgramFiles}\\Google\\Chrome\\Application\\chrome.exe",
        "{LOCALAPPDATA}\\Google\\Chrome\\Application\\chrome.exe"
      ]
    },
    sourceColor: "#f7d329",
    selectedColor: "#0a84ff",
    pinboardIds: ["product"],
    preview: {
      imageTone: "code"
    }
  },
  {
    id: "color-pink",
    kind: "color",
    typeLabel: "Color",
    relativeTime: "2m ago",
    title: "#FF00AA",
    summary: "#FF00AA",
    footer: "#FF00AA",
    commandIndex: "2",
    sourceName: "Digital Color Meter",
    sourceKind: "color",
    sourcePathHints: {
      macos: ["/System/Applications/Utilities/Digital Color Meter.app"],
      windows: ["{WINDIR}\\System32\\mspaint.exe"]
    },
    sourceColor: "#ff9f0a",
    selectedColor: "#0a84ff",
    pinboardIds: ["design"],
    preview: {
      colorValue: "#ff00aa"
    }
  },
  {
    id: "rich-product",
    kind: "richText",
    typeLabel: "Text",
    relativeTime: "4m ago",
    title: "产品说明",
    summary: "产品说明\n· 本地剪贴板历史\n· Pinboard 分类管理\n· 快速预览与回贴",
    footer: "40 characters",
    commandIndex: "3",
    sourceName: "Xcode",
    sourceKind: "xcode",
    sourcePathHints: {
      macos: ["/Applications/Xcode.app"],
      windows: [
        "{LOCALAPPDATA}\\Programs\\Microsoft VS Code\\Code.exe",
        "{ProgramFiles}\\Microsoft VS Code\\Code.exe"
      ]
    },
    sourceColor: "#625edb",
    selectedColor: "#0a84ff",
    pinboardIds: ["product", "customers"]
  },
  {
    id: "image-clipboard",
    kind: "image",
    typeLabel: "Image",
    relativeTime: "6m ago",
    title: "ClipDock App Icon",
    summary: "Clipboard app icon",
    footer: "1024 x 1024",
    commandIndex: "4",
    sourceName: "Photos",
    sourceKind: "photos",
    sourcePathHints: {
      macos: ["/System/Applications/Photos.app"],
      windows: ["{WINDIR}\\System32\\mspaint.exe"]
    },
    sourceColor: "#0a84ff",
    selectedColor: "#0a84ff",
    pinboardIds: ["design"],
    preview: {
      imageTone: "clipboard"
    }
  },
  {
    id: "link-github",
    kind: "link",
    typeLabel: "Link",
    relativeTime: "8m ago",
    title: "GitHub · Change is constant.",
    summary: "The future of building happens together",
    footer: "github.com",
    commandIndex: "5",
    sourceName: "Safari",
    sourceKind: "safari",
    sourcePathHints: {
      macos: ["/Applications/Safari.app"],
      windows: [
        "{ProgramFiles}\\Google\\Chrome\\Application\\chrome.exe",
        "{ProgramFiles}\\Microsoft\\Edge\\Application\\msedge.exe"
      ]
    },
    sourceColor: "#635bff",
    selectedColor: "#0a84ff",
    pinboardIds: ["release"],
    preview: {
      domain: "github.com",
      url: "https://github.com/",
      imageTone: "github"
    }
  },
  {
    id: "file-spec",
    kind: "file",
    typeLabel: "File",
    relativeTime: "9m ago",
    title: "panel-window-contract.md",
    summary: "/Volumes/extendData/Data/IdeaProjects/ClipDock/Windows/",
    footer: "/Volumes/extendData/Data/IdeaProjects/ClipDock/Windows/",
    commandIndex: "6",
    sourceName: "Finder",
    sourceKind: "finder",
    sourcePathHints: {
      macos: ["/System/Library/CoreServices/Finder.app"],
      windows: ["{WINDIR}\\explorer.exe"]
    },
    sourceColor: "#34c759",
    selectedColor: "#0a84ff",
    pinboardIds: ["product"],
    preview: {
      filePath: "/Volumes/extendData/Data/IdeaProjects/ClipDock/Windows/",
      imageTone: "document"
    }
  },
  {
    id: "text-terminal",
    kind: "text",
    typeLabel: "Text",
    relativeTime: "10m ago",
    title: "产品资料条目 7",
    summary: "产品资料条目 7",
    footer: "8 characters",
    commandIndex: "7",
    sourceName: "Terminal",
    sourceKind: "terminal",
    sourcePathHints: {
      macos: ["/System/Applications/Utilities/Terminal.app"],
      windows: [
        "{LOCALAPPDATA}\\Microsoft\\WindowsApps\\wt.exe",
        "{WINDIR}\\System32\\cmd.exe"
      ]
    },
    sourceColor: "#67b7c5",
    selectedColor: "#0a84ff",
    pinboardIds: ["customers"]
  }
];
