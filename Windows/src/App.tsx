import {
  Check,
  CircleEllipsis,
  ClipboardList,
  Copy,
  FileText,
  Folder,
  Github,
  History,
  Image as ImageIcon,
  Link as LinkIcon,
  Palette,
  Pencil,
  Pin,
  Plus,
  Search,
  Sparkles,
  Terminal,
  Trash2,
  Type,
  X
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { LogicalPosition } from "@tauri-apps/api/dpi";
import { listen } from "@tauri-apps/api/event";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { useEffect, useMemo, useRef, useState } from "react";
import { panelItems, pinboardFilters as demoPinboards, typeFilters } from "./panel/panelData";
import {
  clipboardPayloadForItem,
  writeClipboardText
} from "./panel/clipboardCapture";
import { cancelPendingClipboardCopy, copyNativeText, copyStoredItem, panelCopyIntents } from "./panel/copyIntent";
import {
  clampedPanelHeight,
  itemSideLength,
  panelGeometry,
  resizedPanelHeight
} from "./panel/panelGeometry";
import {
  addPanelItem,
  deletePanelItem,
  sortedPanelItemsForDisplay,
  togglePinnedItem
} from "./panel/panelInteractions";
import { applyResolvedPanelAssets, resolvePanelNativeAssets } from "./panel/nativeAssets";
import { CardTitleEditor } from "./panel/CardTitleEditor";
import { CardRenameQueue, matchesRenameShortcut, normalizedCardTitle, persistCardTitle } from "./panel/cardRename";
import { Effect } from "@tauri-apps/api/window";
import { useHistory } from "./panel/useHistory";
import { useVirtualRail } from "./panel/useVirtualRail";
import { cardOffset, mountedCardIndices, railWidth } from "./panel/virtualRail";
import { convertFileSrc, invoke, isTauri } from "@tauri-apps/api/core";
import type { ClipItem, ClipKind, SourceKind } from "./panel/panelTypes";
import { PreferencesApp } from "./preferences/PreferencesApp";
import {
  eventHasAnyShortcutModifier,
  matchesKeyboardShortcut,
  matchesSearchShortcut,
  modifierIsPressed
} from "./preferences/shortcutPresenter";
import { usePreferences } from "./preferences/usePreferences";

const sourceIcons: Record<SourceKind, LucideIcon> = {
  clipboard: ClipboardList,
  notes: FileText,
  chrome: LinkIcon,
  photos: ImageIcon,
  finder: Folder,
  safari: LinkIcon,
  color: Palette,
  xcode: Terminal,
  textedit: Type,
  terminal: Terminal
};

const kindLabels: Record<ClipKind, string> = {
  text: "文本",
  image: "图片",
  file: "文件",
  link: "链接",
  color: "颜色",
  richText: "富文本"
};

type PanelContextMenuState = {
  itemId: string;
  x: number;
  y: number;
};

function availableScreenHeight(): number {
  return Math.max(window.screen.availHeight || 0, window.innerHeight || 0, 1080);
}

export default function App() {
  if (isPreferencesRoute()) {
    return <PreferencesApp />;
  }

  return <PanelApp />;
}

function PanelApp() {
  const { preferences, error: preferencesError } = usePreferences();
  const native = isTauri();
  const [activeType, setActiveType] = useState<(typeof typeFilters)[number]["id"]>("all");
  const [activePinboard, setActivePinboard] = useState<string | null>(null);
  const [demoItems, setItems] = useState(panelItems);
  const [renamingItemId, setRenamingItemId] = useState<string | null>(null);
  const renameQueue = useRef(new CardRenameQueue(persistCardTitle));
  const [searchVisible, setSearchVisible] = useState(false);
  const [searchText, setSearchText] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedSearch(searchText.trim()), 180);
    return () => window.clearTimeout(timer);
  }, [searchText]);
  const history = useHistory({ itemType: activeType === "all" ? null : activeType, pinboardId: activePinboard, searchText: debouncedSearch });
  const items = native ? history.items : demoItems;
  const pinboardFilters = native ? history.pinboards : demoPinboards;
  const [selectedItemId, setSelectedItemId] = useState(panelItems[0]?.id ?? "");
  const [panelHeight, setPanelHeight] = useState<number>(panelGeometry.defaultHeight);
  const [quickAccessMode, setQuickAccessMode] = useState(false);
  const [contextMenu, setContextMenu] = useState<PanelContextMenuState | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const searchInputRef = useRef<HTMLInputElement | null>(null);
  const cardRailRef = useRef<HTMLDivElement | null>(null);
  const mutationInFlight = useRef(false);
  const thumbnailQueue = useRef<string[]>([]);
  const thumbnailVisible = useRef(new Set<string>());
  const thumbnailInFlight = useRef<string | null>(null);
  const thumbnailAlive = useRef(true);
  useEffect(() => { thumbnailAlive.current = true; return () => { thumbnailAlive.current = false; thumbnailQueue.current = []; }; }, []);
  useEffect(() => {
    const onVisibilityChanged = () => { if (document.hidden) cancelPendingClipboardCopy(); };
    document.addEventListener("visibilitychange", onVisibilityChanged);
    return () => {
      document.removeEventListener("visibilitychange", onVisibilityChanged);
      cancelPendingClipboardCopy();
    };
  }, []);

  const filteredItems = useMemo(() => {
    if (native) return items;
    const normalizedSearch = searchText.trim().toLocaleLowerCase();
    return sortedPanelItemsForDisplay(items).filter((item) => {
      const typeMatches = activeType === "all" || item.kind === activeType;
      const pinboardMatches = !activePinboard || item.pinboardIds.includes(activePinboard);
      const textMatches =
        normalizedSearch.length === 0 ||
        [item.customTitle, item.typeLabel, item.title, item.summary, item.footer, item.sourceName]
          .join(" ")
          .toLocaleLowerCase()
          .includes(normalizedSearch);
      return typeMatches && pinboardMatches && textMatches;
    });
  }, [activePinboard, activeType, items, searchText, native]);

  const itemSide = itemSideLength(panelHeight);
  const rail = useVirtualRail(cardRailRef, filteredItems.length, itemSide);
  const visibleItems = filteredItems.slice(rail.start, rail.end);
  const mountedIndices = mountedCardIndices(filteredItems.length, rail.start, rail.end,
    filteredItems.findIndex((item) => item.id === renamingItemId));
  const visibleImageIds = visibleItems.filter((item) => item.kind === "image" && !item.preview?.imageAssetUrl).map((item) => item.id).join(",");
  useEffect(() => {
    const ids = visibleImageIds ? visibleImageIds.split(",") : [];
    thumbnailVisible.current = new Set(ids);
    thumbnailQueue.current = ids.filter((id) => id !== thumbnailInFlight.current);
    if (!native || thumbnailInFlight.current) return;
    void (async () => {
      while (thumbnailAlive.current && thumbnailQueue.current.length > 0) {
        const itemId = thumbnailQueue.current.shift()!;
        thumbnailInFlight.current = itemId;
        try {
          const result = await invoke<{ itemId: string; path: string | null }>("ensure_image_thumbnail", { itemId });
          if (thumbnailAlive.current && thumbnailVisible.current.has(itemId) && result.path) history.controller.updateItem(itemId, (item) => ({ ...item, preview: { ...item.preview, imageAssetUrl: convertFileSrc(result.path!) } }));
        } catch { /* Keep the placeholder; retry when the card becomes visible again. */ }
        finally { thumbnailInFlight.current = null; }
      }
    })();
  }, [native, visibleImageIds, history.controller]);

  useEffect(() => {
    if (native && history.revision >= 0 && !history.refreshing && activePinboard && !pinboardFilters.some((board) => board.id === activePinboard)) setActivePinboard(null);
  }, [activePinboard, history.revision, history.refreshing, native, pinboardFilters]);

  useEffect(() => {
    if (native) return;
    let cancelled = false;
    resolvePanelNativeAssets(panelItems)
      .then((nextItems) => {
        if (!cancelled) {
          setItems((currentItems) => applyResolvedPanelAssets(currentItems, nextItems));
        }
      })
      .catch((error) => {
        console.error("Failed to resolve native panel assets", error);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!native) return;
    let cancelled = false;
    const unlisteners: Array<() => void> = [];
    listen("clipdock://open-preferences", () => {
      void openPreferencesWindow();
    })
      .then((unlisten) => {
        if (cancelled) unlisten();
        else unlisteners.push(unlisten);
      })
      .catch((error) => console.error("Failed to listen open-preferences", error));
    listen("clipdock://copy-diagnostics", () => {
      copyClipboardDiagnostics();
    })
      .then((unlisten) => {
        if (cancelled) unlisten();
        else unlisteners.push(unlisten);
      })
      .catch((error) => console.error("Failed to listen copy-diagnostics", error));
    return () => {
      cancelled = true;
      unlisteners.forEach((unlisten) => unlisten());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!contextMenu) {
      return;
    }

    const closeMenu = () => setContextMenu(null);
    window.addEventListener("click", closeMenu);
    window.addEventListener("resize", closeMenu);
    return () => {
      window.removeEventListener("click", closeMenu);
      window.removeEventListener("resize", closeMenu);
    };
  }, [contextMenu]);

  useEffect(() => {
    if (filteredItems.length === 0) {
      setSelectedItemId("");
      return;
    }
    if (!filteredItems.some((item) => item.id === selectedItemId)) {
      setSelectedItemId(filteredItems[0].id);
    }
  }, [filteredItems, selectedItemId]);

  useEffect(() => {
    const index = filteredItems.findIndex((item) => item.id === selectedItemId);
    if (index >= 0) rail.scrollToIndex(index);
  }, [selectedItemId]);

  useEffect(() => {
    if (searchVisible) {
      searchInputRef.current?.focus();
    }
  }, [searchVisible]);

  useEffect(() => {
    cardRailRef.current?.scrollTo({ left: 0, top: 0 });
  }, [activePinboard, activeType, searchText]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      const isTextEntry =
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target instanceof HTMLSelectElement ||
        target?.isContentEditable === true;
      if (isTextEntry && event.key !== "Escape" && !matchesSearchShortcut(event)) {
        return;
      }

      if (!isTextEntry && matchesRenameShortcut(event)) {
        event.preventDefault();
        const item = filteredItems.find((candidate) => candidate.id === selectedItemId);
        if (item) beginRename(item);
        return;
      }

      if (matchesSearchShortcut(event)) {
        event.preventDefault();
        setSearchVisible(true);
        window.requestAnimationFrame(() => searchInputRef.current?.focus());
        return;
      }

      if (matchesKeyboardShortcut(event, preferences.shortcuts.openPanel)) {
        event.preventDefault();
        showPanelShortcutToast("剪贴板面板已打开");
        return;
      }

      if (matchesKeyboardShortcut(event, preferences.shortcuts.nextPinboard)) {
        event.preventDefault();
        movePinboard(1);
        return;
      }

      if (matchesKeyboardShortcut(event, preferences.shortcuts.previousPinboard)) {
        event.preventDefault();
        movePinboard(-1);
        return;
      }

      if (event.ctrlKey && event.shiftKey && event.key === "D") {
        event.preventDefault();
        copyClipboardDiagnostics();
        return;
      }

      if (
        event.key >= "1" &&
        event.key <= "9" &&
        modifierIsPressed(event, preferences.shortcuts.quickPasteModifier)
      ) {
        const index = Number(event.key) - 1;
        const next = filteredItems[index];
        if (next) {
          event.preventDefault();
          setSelectedItemId(next.id);
          const shouldPastePlainText =
            preferences.shortcuts.alwaysPasteAsPlainText ||
            modifierIsPressed(event, preferences.shortcuts.plainTextModifier);
          void copyItemToClipboard(next, shouldPastePlainText ? "已复制纯文本" : "已复制");
        }
      } else if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        if (eventHasAnyShortcutModifier(event)) {
          return;
        }
        const selectedIndex = filteredItems.findIndex((item) => item.id === selectedItemId);
        if (selectedIndex >= 0) {
          event.preventDefault();
          const offset = event.key === "ArrowRight" ? 1 : -1;
          const nextIndex = Math.min(
            Math.max(selectedIndex + offset, 0),
            filteredItems.length - 1
          );
          setSelectedItemId(filteredItems[nextIndex].id);
          if (native && offset > 0 && nextIndex === filteredItems.length - 1) void history.controller.loadMore();
        }
      } else if (event.key === "Escape") {
        cancelPendingClipboardCopy();
        if (contextMenu) {
          setContextMenu(null);
          return;
        }
        if (searchVisible && searchText.trim().length > 0) {
          setSearchText("");
        } else if (searchVisible) {
          setSearchVisible(false);
        }
      } else if (event.key === "Backspace" || event.key === "Delete") {
        const selected = filteredItems.find((item) => item.id === selectedItemId);
        if (selected) {
          event.preventDefault();
          deleteItem(selected);
        }
      } else if (event.key === " " || event.key === "Spacebar") {
        if (eventHasAnyShortcutModifier(event) || !preferences.appearance.previewPopoverEnabled) {
          return;
        }
        const selected = filteredItems.find((item) => item.id === selectedItemId);
        if (selected) {
          event.preventDefault();
          showPanelShortcutToast(`预览 · ${selected.title}`);
        }
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [
    filteredItems,
    contextMenu,
    preferences.appearance.previewPopoverEnabled,
    preferences.shortcuts,
    searchText,
    searchVisible,
    selectedItemId
  ]);

  useEffect(() => {
    const updateShortcutMode = (event: KeyboardEvent) => {
      setQuickAccessMode(modifierIsPressed(event, preferences.shortcuts.quickPasteModifier));
    };
    const clearShortcutMode = () => setQuickAccessMode(false);
    window.addEventListener("keydown", updateShortcutMode);
    window.addEventListener("keyup", updateShortcutMode);
    window.addEventListener("blur", clearShortcutMode);
    return () => {
      window.removeEventListener("keydown", updateShortcutMode);
      window.removeEventListener("keyup", updateShortcutMode);
      window.removeEventListener("blur", clearShortcutMode);
    };
  }, [preferences.shortcuts.quickPasteModifier]);

  function showCopyToast(item: ClipItem, prefix = "已复制") {
    setToast(`${prefix} · ${kindLabels[item.kind]} · ${item.title}`);
    window.setTimeout(() => {
      setToast(null);
    }, 1400);
  }

  async function copyItemToClipboard(item: ClipItem, prefix = "已复制") {
    const intent = panelCopyIntents.begin();
    if (native) {
      try {
        const result = await copyStoredItem(item.id, intent);
        if (!panelCopyIntents.isCurrent(intent) || result.status === "superseded") return;
        if (result.record_warning) showPanelShortcutToast(`已复制；历史记录更新失败 · ${item.title}`);
        else showCopyToast(item, prefix);
      } catch {
        if (panelCopyIntents.isCurrent(intent)) showPanelShortcutToast(`复制失败 · ${item.title}`);
      }
      return;
    }
    const payload = clipboardPayloadForItem(item);
    if (!payload) {
      showPanelShortcutToast(`无法复制 · ${item.title}`);
      return;
    }

    try {
      if (payload.kind === "text") await writeClipboardText(payload.text);
      if (panelCopyIntents.isCurrent(intent)) showCopyToast(item, prefix);
    } catch (error) {
      console.error("Failed to write clipboard item", error);
      showPanelShortcutToast(`复制失败 · ${item.title}`);
    }
  }

  function showPanelShortcutToast(message: string) {
    setToast(message);
    window.setTimeout(() => {
      setToast(null);
    }, 1400);
  }

  function movePinboard(offset: 1 | -1) {
    if (pinboardFilters.length === 0) return;
    setActivePinboard((current) => {
      const currentIndex = pinboardFilters.findIndex((pinboard) => pinboard.id === current);
      const nextIndex =
        currentIndex === -1
          ? offset > 0
            ? 0
            : pinboardFilters.length - 1
          : (currentIndex + offset + pinboardFilters.length) % pinboardFilters.length;
      const next = pinboardFilters[nextIndex];
      showPanelShortcutToast(`Pinboard · ${next.label}`);
      return next.id;
    });
  }

  async function addItem() {
    const [nextItem] = addPanelItem(items);
    setActiveType("all");
    setActivePinboard(null);
    setSearchText("");
    setContextMenu(null);
    if (native) {
      try {
        await invoke("capture_clipboard_text", { text: nextItem.summary, sourceAppName: "ClipDock" });
        history.controller.refresh();
        showPanelShortcutToast(`新增 · ${nextItem.title}`);
      } catch { showPanelShortcutToast("新增失败，请重试"); }
    } else {
      setItems((currentItems) => [nextItem, ...currentItems]);
      setSelectedItemId(nextItem.id);
      showPanelShortcutToast(`新增 · ${nextItem.title}`);
    }
  }

  function beginRename(item: ClipItem) {
    setContextMenu(null);
    setSelectedItemId(item.id);
    setRenamingItemId(item.id);
  }

  function saveRename(item: ClipItem, draft: string) {
    const title = normalizedCardTitle(draft);
    if (title !== (item.customTitle ?? null)) {
      void renameQueue.current.save(item.id, item.customTitle ?? null, title,
        (customTitle) => {
          if (native) history.controller.updateItem(item.id, (entry) => ({ ...entry, customTitle }));
          else setItems((current) => current.map((entry) => entry.id === item.id ? { ...entry, customTitle } : entry));
        },
        () => showPanelShortcutToast("重命名失败，已恢复原名称")
      ).then(() => { if (native) history.controller.refresh(); });
    }
    setRenamingItemId(null);
  }

  async function deleteItem(item: ClipItem) {
    if (mutationInFlight.current) return;
    setContextMenu(null);
    if (!native) { setItems((current) => deletePanelItem(current, item.id)); return; }
    mutationInFlight.current = true;
    try {
      const result = activePinboard
        ? await invoke<{ affected_count: number }>("set_item_pinboard_membership", { itemId: item.id, pinboardId: activePinboard, isMember: false })
        : await invoke<{ affected_count: number }>("delete_clipboard_item", { itemId: item.id });
      history.controller.refresh();
      showPanelShortcutToast(result.affected_count > 0 ? `${activePinboard ? "已从 Pinboard 移除" : "已从历史删除"} · ${item.title}` : "项目已不存在，列表已刷新");
    } catch { showPanelShortcutToast("删除失败，请重试"); }
    finally { mutationInFlight.current = false; }
  }

  async function toggleItemPinned(item: ClipItem) {
    if (mutationInFlight.current) return;
    setContextMenu(null);
    if (!native) { setItems((current) => togglePinnedItem(current, item.id)); return; }
    const isMember = !item.pinboardIds.includes("default");
    mutationInFlight.current = true;
    try {
      const result = await invoke<{ affected_count: number }>("set_item_pinboard_membership", { itemId: item.id, pinboardId: "default", isMember });
      history.controller.refresh();
      showPanelShortcutToast(result.affected_count > 0 ? `${isMember ? "已固定" : "取消固定"} · ${item.title}` : "项目已不存在，列表已刷新");
    } catch { showPanelShortcutToast("固定操作失败，请重试"); }
    finally { mutationInFlight.current = false; }
  }

  function copyClipboardDiagnostics() {
    const intent = panelCopyIntents.begin();
    const diagnosticsReport = generateClipboardDiagnostics(filteredItems);
    const payload = clipboardPayloadForItem({
      id: "diagnostics",
      kind: "text",
      typeLabel: "诊断",
      relativeTime: "now",
      title: "剪贴板诊断信息",
      summary: diagnosticsReport,
      footer: "diagnostics",
      commandIndex: "0",
      sourceName: "ClipDock",
      sourceKind: "clipboard",
      sourcePathHints: { macos: [], windows: [] },
      sourceColor: "#0a84ff",
      selectedColor: "#0a84ff",
      pinboardIds: [],
      isPinned: false
    });

    if (!payload || payload.kind !== "text") {
      showPanelShortcutToast("诊断复制失败");
      return;
    }

    void (native ? copyNativeText(payload.text, intent) : writeClipboardText(payload.text))
      .then((result) => {
        if (!panelCopyIntents.isCurrent(intent) || result?.status === "superseded") return;
        showPanelShortcutToast("已复制诊断信息");
      })
      .catch((error) => {
        console.error("Failed to copy diagnostics", error);
        if (panelCopyIntents.isCurrent(intent)) showPanelShortcutToast("复制诊断信息失败");
      });
  }

  function openCardContextMenu(event: React.MouseEvent<HTMLElement>, item: ClipItem) {
    event.preventDefault();
    event.stopPropagation();
    setSelectedItemId(item.id);
    setContextMenu({
      itemId: item.id,
      x: Math.min(event.clientX, window.innerWidth - 190),
      y: Math.max(0, Math.min(event.clientY, window.innerHeight - 205))
    });
  }

  function beginResize(event: React.PointerEvent<HTMLDivElement>) {
    event.currentTarget.setPointerCapture(event.pointerId);
    const startY = event.clientY;
    const startHeight = panelHeight;
    const screenHeight = availableScreenHeight();
    const handleMove = (moveEvent: PointerEvent) => {
      const deltaY = startY - moveEvent.clientY;
      setPanelHeight(resizedPanelHeight(startHeight, deltaY, screenHeight));
    };
    const handleUp = () => {
      window.removeEventListener("pointermove", handleMove);
      window.removeEventListener("pointerup", handleUp);
    };
    window.addEventListener("pointermove", handleMove);
    window.addEventListener("pointerup", handleUp);
  }

  return (
    <main className="stage" data-testid="clipdock-panel-stage">
        <section
        className={`panel-shell ${quickAccessMode ? "is-shortcut-mode" : ""}`}
        style={{
          height: clampedPanelHeight(panelHeight, availableScreenHeight()),
          "--item-side": `${itemSide}px`
        } as React.CSSProperties}
        aria-label="ClipDock panel"
      >
        <div
          className="resize-handle"
          onPointerDown={beginResize}
          role="separator"
          aria-orientation="horizontal"
          aria-label="拖动调整高度"
        >
          <span />
        </div>

        <div className="toolbar" data-testid="panel-toolbar">
          <div className="toolbar-left">
            <button
              className={`icon-button ${searchVisible ? "is-active" : ""}`}
              type="button"
              aria-label="搜索"
              data-testid="search-toggle"
              onClick={() => setSearchVisible((value) => !value)}
            >
              <Search size={20} strokeWidth={2.3} />
            </button>
            <div className={`search-slot ${searchVisible ? "is-open" : ""}`}>
              <input
                ref={searchInputRef}
                value={searchText}
                onChange={(event) => setSearchText(event.target.value)}
                placeholder="搜索剪贴内容"
                aria-label="搜索剪贴内容"
              />
              {searchText.length > 0 && (
                <button type="button" aria-label="清空搜索" onClick={() => setSearchText("")}>
                  <X size={14} strokeWidth={2.4} />
                </button>
              )}
            </div>
            <select className="content-type-select" aria-label="内容类型筛选" value={activeType} onChange={(event) => setActiveType(event.target.value as typeof activeType)}>
              {typeFilters.map((filter) => <option key={filter.id} value={filter.id}>{filter.label}</option>)}
            </select>
          </div>

          <div className="pinboard-strip" aria-label="Pinboard 分类">
            <button
              type="button"
              className={`pinboard-chip clipboard-chip ${activePinboard === null ? "is-active" : ""}`}
              onClick={() => setActivePinboard(null)}
            >
              <History size={16} strokeWidth={2.2} />
              Clipboard
            </button>
            {pinboardFilters.map((pinboard) => (
              <button
                key={pinboard.id}
                type="button"
                className={`pinboard-chip ${activePinboard === pinboard.id ? "is-active" : ""}`}
                onClick={() =>
                  setActivePinboard((current) => (current === pinboard.id ? null : pinboard.id))
                }
              >
                <span style={{ backgroundColor: pinboard.color }} />
                {pinboard.label}
              </button>
            ))}
          </div>

          <div className="toolbar-actions">
            <button
              className="icon-button"
              type="button"
              aria-label="新增剪贴项目"
              data-testid="add-item-button"
              onClick={addItem}
            >
              <Plus size={21} strokeWidth={2.2} />
            </button>
            <button
              className="icon-button"
              type="button"
              aria-label="设置"
              onClick={openPreferencesWindow}
            >
              <CircleEllipsis size={20} strokeWidth={2.1} />
            </button>
          </div>
        </div>

        <div
          ref={cardRailRef}
          className="card-rail is-virtual"
          data-testid="panel-card-rail"
          role="listbox"
          tabIndex={0}
          aria-label="剪贴项目列表"
          aria-busy={native && (history.refreshing || history.loadingMore)}
          aria-activedescendant={visibleItems.some((item) => item.id === selectedItemId) ? `card-${selectedItemId}` : undefined}
          onScroll={() => setContextMenu(null)}
        >
          {filteredItems.length === 0 ? (
            native && history.refreshing ? <div role="status">正在加载…</div> : <EmptyState />
          ) : (
            <div className="virtual-card-canvas" style={{ width: railWidth(filteredItems.length, itemSide), height: itemSide }}>
              {mountedIndices.map((index) => {
                const item = filteredItems[index];
                return <div className="virtual-card-slot" key={item.id} style={{ left: cardOffset(index, itemSide), width: itemSide }}>
                  <PanelCard
                    item={item}
                    commandIndex={String(index + 1)}
                    totalCount={native ? history.totalCount : filteredItems.length}
                    selected={item.id === selectedItemId}
                    renaming={item.id === renamingItemId}
                    onRenameSave={(draft) => saveRename(item, draft)}
                    onRenameCancel={() => setRenamingItemId(null)}
                    onSelect={() => { setSelectedItemId(item.id); cardRailRef.current?.focus({ preventScroll: true }); }}
                    onCopy={() => void copyItemToClipboard(item)}
                    onOpenContextMenu={(event) => openCardContextMenu(event, item)}
                  />
                </div>;
              })}
            </div>
          )}
        </div>
        {native && (preferencesError || history.error || history.captureError || history.hasMore || history.refreshing) && <div className="history-status" role="status">
          {preferencesError && <span>{preferencesError}</span>}
          {history.captureError && <span>{history.captureError}</span>}
          {history.error && <><span>{history.error}</span><button onClick={() => history.controller.refresh()}>重试</button></>}
          {!history.error && history.refreshing && <span>正在更新…</span>}
          {!history.refreshing && history.hasMore && <button disabled={history.loadingMore} onClick={() => void history.controller.loadMore()}>{history.loadingMore ? "正在加载…" : `加载更多（${history.items.length} / ${history.totalCount}）`}</button>}
        </div>}

        {contextMenu && (
          <PanelContextMenu
            state={contextMenu}
            item={items.find((item) => item.id === contextMenu.itemId) ?? null}
            onCopy={(item) => {
              setContextMenu(null);
              void copyItemToClipboard(item);
            }}
            onAdd={addItem}
            onTogglePinned={toggleItemPinned}
            onDelete={deleteItem}
            onRename={beginRename}
            pinLabel={native ? (items.find((item) => item.id === contextMenu.itemId)?.pinboardIds.includes("default") ? "取消固定" : "固定") : undefined}
            deleteLabel={activePinboard ? "从此 Pinboard 移除" : "从历史删除"}
          />
        )}

        {toast && (
          <div className="copy-toast" role="status" aria-live="polite">
            <Check size={15} strokeWidth={2.5} />
            {toast}
          </div>
        )}
      </section>
    </main>
  );
}

function isPreferencesRoute(): boolean {
  return new URLSearchParams(window.location.search).get("view") === "preferences";
}

async function openPreferencesWindow() {
  try {
    const mainWindow = WebviewWindow.getCurrent();
    const existingWindow = await WebviewWindow.getByLabel("preferences");
    if (existingWindow) {
      await existingWindow.show();
      await existingWindow.setFocus();
      await hidePanelWindow(mainWindow);
      return;
    }

    const preferencesWindow = new WebviewWindow("preferences", {
      url: "/?view=preferences",
      title: "偏好设置",
      width: 920,
      height: 700,
      minWidth: 820,
      minHeight: 600,
      center: true,
      resizable: true,
      decorations: true,
      transparent: true,
      windowEffects: { effects: [Effect.Mica, Effect.Sidebar] },
      visible: true,
      focus: true,
      titleBarStyle: "overlay",
      hiddenTitle: true,
      trafficLightPosition: new LogicalPosition(14, 14)
    });
    void preferencesWindow.once("tauri://created", async () => {
      await hidePanelWindow(mainWindow);
    });
    window.setTimeout(() => {
      void hidePanelWindow(mainWindow);
    }, 180);
    void preferencesWindow.once("tauri://error", (event) => {
      console.error("Failed to create preferences window", event.payload);
    });
  } catch {
    window.open("/?view=preferences", "clipdock-preferences", "width=920,height=700");
  }
}

async function hidePanelWindow(window: WebviewWindow) {
  cancelPendingClipboardCopy();
  try {
    await window.hide();
  } catch (error) {
    console.error("Failed to hide panel window", error);
  }
}

function FilterStrip({
  activeType,
  onChange
}: {
  activeType: (typeof typeFilters)[number]["id"];
  onChange: (next: (typeof typeFilters)[number]["id"]) => void;
}) {
  return (
    <div className="type-filter-strip" aria-label="内容类型筛选">
      {typeFilters.map((filter) => (
        <button
          key={filter.id}
          type="button"
          className={`filter-chip ${activeType === filter.id ? "is-active" : ""}`}
          onClick={() => onChange(filter.id)}
        >
          {filter.id === "all" && <ClipboardList size={15} strokeWidth={2.2} />}
          {filter.label}
        </button>
      ))}
    </div>
  );
}

function PanelCard({
  item,
  commandIndex,
  totalCount,
  selected,
  renaming,
  onRenameSave,
  onRenameCancel,
  onSelect,
  onCopy,
  onOpenContextMenu
}: {
  item: ClipItem;
  commandIndex: string;
  totalCount: number;
  selected: boolean;
  renaming: boolean;
  onRenameSave: (draft: string) => void;
  onRenameCancel: () => void;
  onSelect: () => void;
  onCopy: () => void;
  onOpenContextMenu: (event: React.MouseEvent<HTMLElement>) => void;
}) {
  const SourceIcon = sourceIcons[item.sourceKind];
  return (
    <article
      className={`panel-card ${selected ? "is-selected" : ""} ${item.isPinned ? "is-pinned" : ""} is-${item.kind}`}
      onClick={onSelect}
      onDoubleClick={onCopy}
      onContextMenu={onOpenContextMenu}
      data-testid={`panel-card-${item.id}`}
      aria-label={`${item.customTitle ?? item.typeLabel} ${item.title}`}
      id={`card-${item.id}`}
      role="option"
      aria-selected={selected}
      aria-posinset={Number(commandIndex)}
      aria-setsize={totalCount}
      tabIndex={-1}
      style={
        {
          "--source-color": item.sourceColor,
          "--selected-color": item.selectedColor
        } as React.CSSProperties
      }
    >
      <header className="card-header">
        <div className="card-title-group">
          {renaming ? <CardTitleEditor value={item.customTitle ?? ""} placeholder={item.typeLabel}
            onSave={onRenameSave} onCancel={onRenameCancel} /> :
            <strong title={item.customTitle ?? item.typeLabel}>{item.customTitle ?? item.typeLabel}</strong>}
          <span>{item.relativeTime}</span>
        </div>
        {item.isPinned && (
          <span className="pin-badge" aria-label="已固定">
            <Pin size={12} strokeWidth={2.4} />
          </span>
        )}
        <div className="source-icon" title={item.sourceName}>
          {item.sourceIconAssetUrl ? (
            <img className="source-icon-image" src={item.sourceIconAssetUrl} alt="" />
          ) : (
            <SourceIcon size={34} strokeWidth={1.7} />
          )}
        </div>
      </header>

      <CardPreview item={item} />

      <footer className="card-footer">
        {item.kind === "link" ? (
          <div className="link-footer-text">
            <strong>
              {item.preview?.linkIconAssetUrl && (
                <img className="link-site-icon" src={item.preview.linkIconAssetUrl} alt="" />
              )}
              <span>{item.title}</span>
            </strong>
            <span>{item.footer}</span>
          </div>
        ) : (
          <span className="footer-label">{item.footer}</span>
        )}
        <span className="command-index">{commandIndex}</span>
      </footer>
    </article>
  );
}

function PanelContextMenu({
  state,
  item,
  onCopy,
  onAdd,
  onTogglePinned,
  onDelete,
  pinLabel,
  onRename,
  deleteLabel
}: {
  state: PanelContextMenuState;
  item: ClipItem | null;
  onCopy: (item: ClipItem) => void;
  onAdd: () => void;
  onTogglePinned: (item: ClipItem) => void;
  onDelete: (item: ClipItem) => void;
  pinLabel?: string;
  onRename: (item: ClipItem) => void;
  deleteLabel: string;
}) {
  if (!item) {
    return null;
  }

  return (
    <div
      className="panel-context-menu"
      role="menu"
      aria-label={`${item.title} 操作菜单`}
      data-testid="panel-context-menu"
      style={{ left: state.x, top: state.y }}
      onClick={(event) => event.stopPropagation()}
      onContextMenu={(event) => event.preventDefault()}
    >
      <button type="button" role="menuitem" onClick={() => onCopy(item)}>
        <Copy size={15} strokeWidth={2.2} />
        复制
      </button>
      <button type="button" role="menuitem" data-testid="context-menu-pin" onClick={() => onTogglePinned(item)}>
        <Pin size={15} strokeWidth={2.2} />
        {pinLabel ?? (item.isPinned ? "取消固定" : "固定")}
      </button>
      <button type="button" role="menuitem" onClick={() => onRename(item)}>
        <Pencil size={15} strokeWidth={2.2} />
        重命名 <kbd className="menu-shortcut">F2</kbd>
      </button>
      <button type="button" role="menuitem" onClick={onAdd}>
        <Plus size={15} strokeWidth={2.2} />
        新增剪贴项目
      </button>
      <button
        type="button"
        role="menuitem"
        className="is-danger"
        data-testid="context-menu-delete"
        onClick={() => onDelete(item)}
      >
        <Trash2 size={15} strokeWidth={2.2} />
        {deleteLabel}
      </button>
    </div>
  );
}

function CardPreview({ item }: { item: ClipItem }) {
  if (item.preview?.imageTone === "code") {
    return (
      <div className="card-preview code-preview">
        <pre>
          <span className="code-call">UgAdaptiveDialog</span>
          <span>(</span>
          {"\n"}
          <span className="code-key">    modifier</span>
          <span> =</span>
          {"\n"}
          <span>ugAdaptiveDialogModifier,</span>
          {"\n"}
          <span className="code-key">    visible</span>
          <span> =</span>
          {"\n"}
          <span>isShowScanDeviceDialog,</span>
          {"\n"}
          <span className="code-key">    dismissOnSwipeDown</span>
          <span> =</span>
          {"\n"}
          <span>false</span>
          {"\n"}
          <span>)</span>
        </pre>
      </div>
    );
  }

  if (item.kind === "image") {
    if (item.preview?.imageAssetUrl) {
      return (
        <div className="card-preview image-preview captured-image-frame" aria-label={item.title}>
          <img className="captured-image-preview" src={item.preview.imageAssetUrl} alt="" />
        </div>
      );
    }

    if (item.preview?.imageTone === "captured") {
      return <div className="card-preview image-preview" aria-label="图片缩略图尚未就绪"><ImageIcon size={36} aria-hidden="true" /></div>;
    }

    if (item.preview?.imageTone === "clipboard") {
      return (
        <div className="card-preview image-preview clipboard-image-preview" aria-label={item.title}>
          <div className="clipboard-app-art">
            <ClipboardList size={74} strokeWidth={1.8} />
            <span />
            <span />
          </div>
        </div>
      );
    }

    return (
      <div className="card-preview image-preview" aria-label={item.title}>
        <div className="water-texture" />
      </div>
    );
  }

  if (item.kind === "file") {
    return (
      <div className="card-preview file-preview">
        <div className="document-sheet">
          <span />
          <span />
          <span />
          <span />
          <span />
        </div>
        <p>{item.preview?.filePath}</p>
      </div>
    );
  }

  if (item.kind === "link") {
    if (item.preview?.linkPreviewAssetUrl) {
      return (
        <div className="card-preview link-preview">
          <img className="link-preview-image" src={item.preview.linkPreviewAssetUrl} alt="" />
        </div>
      );
    }

    return (
      <div className="card-preview link-preview">
        <div className={item.preview?.url ? "captured-link-preview" : "github-preview"}>
          {item.preview?.url ? (
            <LinkIcon size={19} strokeWidth={2.2} />
          ) : (
            <Github size={16} strokeWidth={2.2} />
          )}
          <strong>{item.preview?.url ? item.title : "The future of building happens together"}</strong>
          {item.preview?.url && <small>{item.preview.domain}</small>}
          <span />
          <span />
        </div>
      </div>
    );
  }

  if (item.kind === "color") {
    return (
      <div
        className="card-preview color-preview"
        style={{ backgroundColor: item.preview?.colorValue ?? "#ff00aa" }}
      >
        <strong>{item.summary}</strong>
      </div>
    );
  }

  if (item.kind === "richText") {
    const [heading, ...lines] = item.summary.split("\n");
    return (
      <div className="card-preview text-preview rich-text-preview">
        <strong>{heading}</strong>
        {lines.map((line) => (
          <span key={line}>{line}</span>
        ))}
      </div>
    );
  }

  return (
    <div className="card-preview text-preview">
      <p>{item.summary}</p>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="empty-state">
      <Sparkles size={22} strokeWidth={1.8} />
      <strong>没有匹配的剪贴项目</strong>
      <span>调整搜索或筛选条件</span>
    </div>
  );
}

function generateClipboardDiagnostics(items: ClipItem[]): string {
  const timestamp = new Date().toISOString();
  const appVersion = navigator.appVersion || "Unknown";
  const userAgent = navigator.userAgent || "Unknown";
  const pinnedCount = items.filter((item) => item.isPinned).length;

  return [
    "=== ClipDock 诊断报告 ===",
    `生成时间: ${timestamp}`,
    `应用版本: 0.1.0 (Windows Panel)`,
    `用户代理: ${userAgent}`,
    "",
    "=== 剪贴历史统计 ===",
    `总项数: ${items.length}`,
    `已固定: ${pinnedCount}`,
    `未固定: ${items.length - pinnedCount}`,
    "",
    "=== 类型分布 ===",
    getItemKindDistribution(items),
    "",
    "=== 系统信息 ===",
    `屏幕分辨率: ${window.screen.width}x${window.screen.height}`,
    `可用高度: ${window.screen.availHeight}`,
    `页面宽度: ${window.innerWidth}x${window.innerHeight}`,
    "",
    "=== 最近项目 (前5个) ===",
    items
      .slice(0, 5)
      .map((item, index) => `${index + 1}. [${item.kind}] ${item.title} (${item.relativeTime})`)
      .join("\n"),
    "",
    "=== 固定项目 ===",
    items
      .filter((item) => item.isPinned)
      .map((item) => `- [${item.kind}] ${item.title}`)
      .join("\n") || "无"
  ].join("\n");
}

function getItemKindDistribution(items: ClipItem[]): string {
  const distribution: Record<string, number> = {};
  items.forEach((item) => {
    distribution[item.kind] = (distribution[item.kind] || 0) + 1;
  });
  return Object.entries(distribution)
    .map(([kind, count]) => `  ${kind}: ${count}`)
    .join("\n");
}
