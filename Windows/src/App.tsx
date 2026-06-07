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
import { panelItems, pinboardFilters, typeFilters } from "./panel/panelData";
import {
  clipboardCaptureDecision,
  clipboardPayloadForItem,
  clipboardSnapshotToPanelItem,
  readClipboardSnapshot,
  writeClipboardImage,
  writeClipboardText
} from "./panel/clipboardCapture";
import type { ClipboardSnapshot } from "./panel/clipboardCapture";
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

declare global {
  interface Window {
    __clipdockHandleClipboardSnapshot?: (snapshot: ClipboardSnapshot) => void;
  }
}

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
  const { preferences } = usePreferences();
  const [activeType, setActiveType] = useState<(typeof typeFilters)[number]["id"]>("all");
  const [activePinboard, setActivePinboard] = useState<string | null>(null);
  const [items, setItems] = useState(panelItems);
  const [searchVisible, setSearchVisible] = useState(false);
  const [searchText, setSearchText] = useState("");
  const [selectedItemId, setSelectedItemId] = useState(panelItems[0]?.id ?? "");
  const [panelHeight, setPanelHeight] = useState<number>(panelGeometry.defaultHeight);
  const [quickAccessMode, setQuickAccessMode] = useState(false);
  const [contextMenu, setContextMenu] = useState<PanelContextMenuState | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const searchInputRef = useRef<HTMLInputElement | null>(null);
  const cardRailRef = useRef<HTMLDivElement | null>(null);
  const capturedClipboardKeysRef = useRef<Set<string>>(new Set());
  const selfWriteClipboardKeyRef = useRef<string | null>(null);
  const clipboardPollInFlightRef = useRef(false);

  const filteredItems = useMemo(() => {
    const normalizedSearch = searchText.trim().toLocaleLowerCase();
    return sortedPanelItemsForDisplay(items).filter((item) => {
      const typeMatches = activeType === "all" || item.kind === activeType;
      const pinboardMatches = !activePinboard || item.pinboardIds.includes(activePinboard);
      const textMatches =
        normalizedSearch.length === 0 ||
        [item.typeLabel, item.title, item.summary, item.footer, item.sourceName]
          .join(" ")
          .toLocaleLowerCase()
          .includes(normalizedSearch);
      return typeMatches && pinboardMatches && textMatches;
    });
  }, [activePinboard, activeType, items, searchText]);

  useEffect(() => {
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
    const clipboardHandler = (snapshot: ClipboardSnapshot) => {
      captureClipboardSnapshot(snapshot);
    };
    window.__clipdockHandleClipboardSnapshot = clipboardHandler;
    const onNativeClipboardChange = (event: Event) => {
      const snapshot = (event as CustomEvent<ClipboardSnapshot>).detail;
      captureClipboardSnapshot(snapshot);
    };
    window.addEventListener("clipdock-native-clipboard-changed", onNativeClipboardChange);
    return () => {
      if (window.__clipdockHandleClipboardSnapshot === clipboardHandler) {
        delete window.__clipdockHandleClipboardSnapshot;
      }
      window.removeEventListener("clipdock-native-clipboard-changed", onNativeClipboardChange);
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    let unlisten: (() => void) | null = null;

    listen<ClipboardSnapshot>("clipboard-changed", (event) => {
      if (!cancelled) {
        captureClipboardSnapshot(event.payload);
      }
    })
      .then((nextUnlisten) => {
        if (cancelled) {
          nextUnlisten();
          return;
        }
        unlisten = nextUnlisten;
      })
      .catch((error) => {
        console.error("Failed to subscribe clipboard changes", error);
      });

    return () => {
      cancelled = true;
      unlisten?.();
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    const pollClipboard = async () => {
      if (clipboardPollInFlightRef.current) {
        return;
      }
      clipboardPollInFlightRef.current = true;
      try {
        const snapshot = await readClipboardSnapshot();
        if (cancelled) {
          return;
        }
        captureClipboardSnapshot(snapshot);
      } catch (error) {
        console.error("Failed to read clipboard snapshot", error);
      } finally {
        clipboardPollInFlightRef.current = false;
      }
    };

    void pollClipboard();
    const timer = window.setInterval(() => {
      void pollClipboard();
    }, 900);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, []);

  function captureClipboardSnapshot(snapshot: ClipboardSnapshot | null) {
    const decision = clipboardCaptureDecision(
      snapshot,
      capturedClipboardKeysRef.current,
      selfWriteClipboardKeyRef.current
    );
    if (!snapshot || !decision.shouldCapture) {
      if (decision.reason === "self-write" && snapshot?.changeKey) {
        capturedClipboardKeysRef.current.add(snapshot.changeKey);
        selfWriteClipboardKeyRef.current = null;
      }
      return;
    }

    const nextItem = clipboardSnapshotToPanelItem(
      snapshot,
      String(capturedClipboardKeysRef.current.size + 1)
    );
    capturedClipboardKeysRef.current.add(snapshot.changeKey);
    if (!nextItem) {
      return;
    }

    setActiveType("all");
    setActivePinboard(null);
    setSearchText("");
    setContextMenu(null);
    setSelectedItemId(nextItem.id);
    setItems((currentItems) => {
      if (currentItems.some((item) => item.id === nextItem.id)) {
        return currentItems;
      }
      return [nextItem, ...currentItems];
    });
    showPanelShortcutToast(`已捕获 · ${kindLabels[nextItem.kind]} · ${nextItem.title}`);

    if (nextItem.kind === "link") {
      void resolvePanelNativeAssets([nextItem])
        .then((resolvedItems) => {
          setItems((currentItems) => applyResolvedPanelAssets(currentItems, resolvedItems));
        })
        .catch((error) => {
          console.error("Failed to resolve captured link assets", error);
        });
    }
  }

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
        target?.isContentEditable === true;
      if (isTextEntry && event.key !== "Escape" && !matchesSearchShortcut(event)) {
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
        }
      } else if (event.key === "Escape") {
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

  const itemSide = itemSideLength(panelHeight);

  function showCopyToast(item: ClipItem, prefix = "已复制") {
    setToast(`${prefix} · ${kindLabels[item.kind]} · ${item.title}`);
    window.setTimeout(() => {
      setToast(null);
    }, 1400);
  }

  async function copyItemToClipboard(item: ClipItem, prefix = "已复制") {
    const payload = clipboardPayloadForItem(item);
    if (!payload) {
      showPanelShortcutToast(`无法复制 · ${item.title}`);
      return;
    }

    try {
      const changeKey =
        payload.kind === "image"
          ? await writeClipboardImage(payload.imagePath)
          : await writeClipboardText(payload.text);
      if (changeKey) {
        capturedClipboardKeysRef.current.add(changeKey);
        selfWriteClipboardKeyRef.current = changeKey;
      }
      showCopyToast(item, prefix);
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

  function addItem() {
    const [nextItem] = addPanelItem(items);
    setActiveType("all");
    setActivePinboard(null);
    setSearchText("");
    setContextMenu(null);
    setItems((currentItems) => [nextItem, ...currentItems]);
    setSelectedItemId(nextItem.id);
    showPanelShortcutToast(`新增 · ${nextItem.title}`);
  }

  function deleteItem(item: ClipItem) {
    setItems((currentItems) => deletePanelItem(currentItems, item.id));
    setContextMenu(null);
    showPanelShortcutToast(`已删除 · ${item.title}`);
  }

  function toggleItemPinned(item: ClipItem) {
    setItems((currentItems) => togglePinnedItem(currentItems, item.id));
    setContextMenu(null);
    showPanelShortcutToast(`${item.isPinned ? "取消固定" : "已固定"} · ${item.title}`);
  }

  function openCardContextMenu(event: React.MouseEvent<HTMLElement>, item: ClipItem) {
    event.preventDefault();
    event.stopPropagation();
    setSelectedItemId(item.id);
    setContextMenu({
      itemId: item.id,
      x: Math.min(event.clientX, window.innerWidth - 190),
      y: Math.min(event.clientY, window.innerHeight - 150)
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
          className="card-rail"
          data-testid="panel-card-rail"
          aria-label="剪贴项目列表"
        >
          {filteredItems.length === 0 ? (
            <EmptyState />
          ) : (
            filteredItems.map((item, index) => (
              <PanelCard
                key={item.id}
                item={item}
                commandIndex={String(index + 1)}
                selected={item.id === selectedItemId}
                onSelect={() => setSelectedItemId(item.id)}
                onCopy={() => void copyItemToClipboard(item)}
                onOpenContextMenu={(event) => openCardContextMenu(event, item)}
              />
            ))
          )}
        </div>

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
      transparent: false,
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
  selected,
  onSelect,
  onCopy,
  onOpenContextMenu
}: {
  item: ClipItem;
  commandIndex: string;
  selected: boolean;
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
      aria-label={`${item.typeLabel} ${item.title}`}
      tabIndex={0}
      style={
        {
          "--source-color": item.sourceColor,
          "--selected-color": item.selectedColor
        } as React.CSSProperties
      }
    >
      <header className="card-header">
        <div className="card-title-group">
          <strong>{item.typeLabel}</strong>
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
  onDelete
}: {
  state: PanelContextMenuState;
  item: ClipItem | null;
  onCopy: (item: ClipItem) => void;
  onAdd: () => void;
  onTogglePinned: (item: ClipItem) => void;
  onDelete: (item: ClipItem) => void;
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
        {item.isPinned ? "取消固定" : "固定"}
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
        删除
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
