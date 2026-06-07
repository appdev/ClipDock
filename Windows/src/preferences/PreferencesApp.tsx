import {
  CheckCircle,
  ClipboardList,
  ExternalLink,
  Hand,
  Info,
  Keyboard,
  Minus,
  Monitor,
  Plus,
  RefreshCw,
  Settings,
  X
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { useEffect, useMemo, useState } from "react";
import {
  formatKeyboardShortcut,
  modifierDisplayName,
  shortcutFromKeyboardEvent
} from "./shortcutPresenter";
import type {
  AppearanceMode,
  DownloadPathMode,
  KeyboardShortcut,
  ModifierKey,
  PlainTextModifier,
  PreferenceSectionId,
  PreferencesState,
  RetentionDays,
  ShortcutModifier
} from "./preferencesTypes";
import { usePreferences } from "./usePreferences";

type UpdatePreferences = (updater: (current: PreferencesState) => PreferencesState) => void;

type PreferenceSectionDefinition = {
  id: PreferenceSectionId;
  title: string;
  subtitle: string;
  icon: LucideIcon;
};

const preferenceSections: PreferenceSectionDefinition[] = [
  {
    id: "general",
    title: "General",
    subtitle: "Startup, menu bar, paste behavior, copy HUD, theme, previews, and retention",
    icon: Settings
  },
  {
    id: "sync",
    title: "同步",
    subtitle: "连接自托管服务端并配置 P2P 元数据登记",
    icon: RefreshCw
  },
  {
    id: "rules",
    title: "Privacy",
    subtitle: "Source permissions and ignored apps",
    icon: Hand
  },
  {
    id: "shortcuts",
    title: "Keyboard Shortcuts",
    subtitle: "Open, search, and quick access",
    icon: Keyboard
  },
  {
    id: "about",
    title: "About",
    subtitle: "Version, build, and project information",
    icon: Info
  }
];

const modifierOptions: ShortcutModifier[] = ["command", "control", "option"];
const plainTextModifierOptions: PlainTextModifier[] = ["shift", "command", "control", "option"];

export function PreferencesApp() {
  const { preferences, updatePreferences, resetShortcuts } = usePreferences();
  const [selectedSection, setSelectedSection] = useState<PreferenceSectionId>("general");

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    let currentWindow: WebviewWindow | null = null;

    const restoreMainPanel = async () => {
      try {
        const mainWindow = await WebviewWindow.getByLabel("main");
        await mainWindow?.show();
      } catch {
        // Browser preview mode has no Tauri IPC; ignore restore there.
      }
    };

    const closePreferencesWindow = async () => {
      await restoreMainPanel();
      try {
        await currentWindow?.hide();
      } catch {
        // Browser preview mode has no Tauri IPC; ignore close there.
      }
    };

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.metaKey && event.key.toLocaleLowerCase() === "w") {
        event.preventDefault();
        void closePreferencesWindow();
      }
    };

    try {
      currentWindow = WebviewWindow.getCurrent();
      void currentWindow
        .onCloseRequested(async (event) => {
          event.preventDefault();
          await closePreferencesWindow();
        })
        .then((nextUnlisten) => {
          if (disposed) {
            nextUnlisten();
          } else {
            unlisten = nextUnlisten;
          }
        });
    } catch {
      // Browser preview mode has no Tauri IPC.
    }
    window.addEventListener("keydown", onKeyDown);

    return () => {
      disposed = true;
      unlisten?.();
      window.removeEventListener("keydown", onKeyDown);
      void restoreMainPanel();
    };
  }, []);

  const currentSection = useMemo(
    () => preferenceSections.find((section) => section.id === selectedSection) ?? preferenceSections[0],
    [selectedSection]
  );

  return (
    <main className="preferences-root" data-testid="preferences-root">
      <aside className="preferences-sidebar" data-tauri-drag-region>
        <div className="preferences-sidebar-spacer" data-tauri-drag-region />
        <nav className="preferences-sidebar-list" aria-label="设置分区">
          {preferenceSections.map((section) => {
            const SectionIcon = section.icon;
            return (
              <button
                key={section.id}
                type="button"
                className={`preferences-nav-button ${
                  selectedSection === section.id ? "is-selected" : ""
                }`}
                onClick={() => setSelectedSection(section.id)}
              >
                <SectionIcon size={17} strokeWidth={2.15} />
                <span>{section.title}</span>
              </button>
            );
          })}
        </nav>
      </aside>

      <section className="preferences-content">
        <div className="preferences-scroll">
          <PreferencePageHeader section={currentSection} />
          {selectedSection === "general" && (
            <PreferenceGeneralSection
              preferences={preferences}
              updatePreferences={updatePreferences}
            />
          )}
          {selectedSection === "sync" && (
            <PreferenceSyncSection preferences={preferences} updatePreferences={updatePreferences} />
          )}
          {selectedSection === "rules" && (
            <PreferenceRulesSection
              preferences={preferences}
              updatePreferences={updatePreferences}
            />
          )}
          {selectedSection === "shortcuts" && (
            <PreferenceShortcutSection
              preferences={preferences}
              updatePreferences={updatePreferences}
              resetShortcuts={resetShortcuts}
            />
          )}
          {selectedSection === "about" && (
            <PreferenceAboutSection preferences={preferences} updatePreferences={updatePreferences} />
          )}
        </div>
      </section>
    </main>
  );
}

function PreferencePageHeader({ section }: { section: PreferenceSectionDefinition }) {
  const SectionIcon = section.icon;
  return (
    <header className="preference-page-header" data-tauri-drag-region>
      <div>
        <h1>{section.title}</h1>
        <p>{section.subtitle}</p>
      </div>
      <div className="preference-page-icon">
        <SectionIcon size={16} strokeWidth={2.2} />
      </div>
    </header>
  );
}

function PreferenceGeneralSection({
  preferences,
  updatePreferences
}: {
  preferences: PreferencesState;
  updatePreferences: UpdatePreferences;
}) {
  return (
    <div className="preferences-section-stack">
      <PreferenceSectionGroup title="Basic">
        <PreferenceRow title="Open at Login" detail="已开启">
          <SwitchControl
            checked={preferences.general.launchAtLogin}
            onChange={(launchAtLogin) =>
              updatePreferences((current) => ({
                ...current,
                general: { ...current.general, launchAtLogin }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="Show in Menu Bar" detail="Keep the status bar entry and quick menu">
          <SwitchControl
            checked={preferences.general.showMenuBarItem}
            onChange={(showMenuBarItem) =>
              updatePreferences((current) => ({
                ...current,
                general: { ...current.general, showMenuBarItem }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="Copy Completion HUD" detail="复制成功后显示短暂提示">
          <SwitchControl
            checked={preferences.general.copyCompletionHudEnabled}
            onChange={(copyCompletionHudEnabled) =>
              updatePreferences((current) => ({
                ...current,
                general: { ...current.general, copyCompletionHudEnabled }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="Copy sound" detail="Play a sound after copying in other apps">
          <SwitchControl
            checked={preferences.general.externalCopySoundEnabled}
            onChange={(externalCopySoundEnabled) =>
              updatePreferences((current) => ({
                ...current,
                general: { ...current.general, externalCopySoundEnabled }
              }))
            }
          />
        </PreferenceRow>
      </PreferenceSectionGroup>

      <PreferenceSectionGroup title="Paste Items">
        <PreferenceRow title="Paste directly to target" detail="Paste the selected item into the current app automatically">
          <SwitchControl
            checked={preferences.shortcuts.pasteDirectlyToTarget}
            onChange={(pasteDirectlyToTarget) =>
              updatePreferences((current) => ({
                ...current,
                shortcuts: { ...current.shortcuts, pasteDirectlyToTarget }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="Always paste as plain text" detail="文本、链接与颜色取用时写入纯文本">
          <SwitchControl
            checked={preferences.shortcuts.alwaysPasteAsPlainText}
            onChange={(alwaysPasteAsPlainText) =>
              updatePreferences((current) => ({
                ...current,
                shortcuts: { ...current.shortcuts, alwaysPasteAsPlainText }
              }))
            }
          />
        </PreferenceRow>
      </PreferenceSectionGroup>

      <PreferenceSectionGroup title="Appearance">
        <PreferenceRow title="Display mode" detail="控制面板、设置与预览">
          <SegmentedControl<AppearanceMode>
            width={220}
            value={preferences.appearance.mode}
            options={[
              { label: "系统", value: "system" },
              { label: "浅色", value: "light" },
              { label: "深色", value: "dark" }
            ]}
            onChange={(mode) =>
              updatePreferences((current) => ({
                ...current,
                appearance: { ...current.appearance, mode }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="Preview Popover" detail="Press Space to preview the selected item">
          <SwitchControl
            checked={preferences.appearance.previewPopoverEnabled}
            onChange={(previewPopoverEnabled) =>
              updatePreferences((current) => ({
                ...current,
                appearance: { ...current.appearance, previewPopoverEnabled }
              }))
            }
          />
        </PreferenceRow>
      </PreferenceSectionGroup>

      <PreferenceSectionGroup title="Retention">
        <PreferenceRow
          title="Retention"
          detail={retentionDetail(preferences.history.retentionDays)}
        >
          <SegmentedControl<RetentionDays>
            width={250}
            value={preferences.history.retentionDays}
            options={[
              { label: "天", value: 1 },
              { label: "周", value: 7 },
              { label: "月", value: 30 },
              { label: "年", value: 365 },
              { label: "永久", value: "forever" }
            ]}
            onChange={(retentionDays) =>
              updatePreferences((current) => ({
                ...current,
                history: { ...current.history, retentionDays }
              }))
            }
          />
        </PreferenceRow>
      </PreferenceSectionGroup>
    </div>
  );
}

function PreferenceSyncSection({
  preferences,
  updatePreferences
}: {
  preferences: PreferencesState;
  updatePreferences: UpdatePreferences;
}) {
  const sync = preferences.sync;
  return (
    <div className="preferences-section-stack">
      <PreferenceSectionGroup title="服务端">
        <PreferenceRow title="启用同步" detail="开启后使用自托管服务端同步剪贴板元数据">
          <SwitchControl
            checked={sync.enabled}
            onChange={(enabled) =>
              updatePreferences((current) => ({
                ...current,
                sync: { ...current.sync, enabled }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceStackedRow title="服务端地址" detail="例如 http://127.0.0.1:8787">
          <TextInput
            value={sync.serverUrl}
            placeholder="https://clipdock.example.com"
            onChange={(serverUrl) =>
              updatePreferences((current) => ({
                ...current,
                sync: { ...current.sync, serverUrl }
              }))
            }
          />
        </PreferenceStackedRow>
        <PreferenceDivider />
        <PreferenceStackedRow title="本机名称" detail="创建或加入同步时登记到服务端">
          <TextInput
            value={sync.deviceName}
            placeholder="Windows PC"
            onChange={(deviceName) =>
              updatePreferences((current) => ({
                ...current,
                sync: { ...current.sync, deviceName }
              }))
            }
          />
        </PreferenceStackedRow>
        <PreferenceDivider />
        <PreferenceRow
          title="P2P 元数据登记"
          detail="向服务端上报本机 P2P endpoint，供其他端按需选择下载路径"
        >
          <SwitchControl
            checked={sync.p2pEnabled}
            onChange={(p2pEnabled) =>
              updatePreferences((current) => ({
                ...current,
                sync: { ...current.sync, p2pEnabled }
              }))
            }
          />
        </PreferenceRow>
      </PreferenceSectionGroup>

      <PreferenceSectionGroup title="同步空间">
        <PreferenceRow
          title="当前同步空间"
          detail={sync.syncSpaceJoined ? "当前设备已加入一个同步空间" : "尚未加入同步"}
        >
          <div className="preference-pill-row">
            <PreferenceValuePill text={sync.syncSpaceJoined ? "已加入" : "未加入"} prominent />
            <PreferenceValuePill text={sync.enabled ? "已启用" : "未启用"} />
          </div>
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceStackedRow
          title="当前设备"
          detail={
            sync.syncSpaceJoined
              ? "其他设备会看到这个本机名称"
              : "创建或加入同步后显示在同步空间中"
          }
        >
          <PreferenceInlineValue value={sync.deviceName || "Windows PC"} />
        </PreferenceStackedRow>
        <PreferenceDivider />
        <PreferenceStackedRow
          title="同步操作"
          detail="创建新同步空间，或输入其他设备分享的五位同步码加入"
        >
          <div className="preference-action-row">
            <button
              className="preference-push-button"
              type="button"
              onClick={() =>
                updatePreferences((current) => ({
                  ...current,
                  sync: { ...current.sync, syncSpaceJoined: true, enabled: true }
                }))
              }
            >
              创建同步空间
            </button>
            <input className="preference-code-input" maxLength={5} placeholder="同步码" />
            <button
              className="preference-push-button"
              type="button"
              onClick={() =>
                updatePreferences((current) => ({
                  ...current,
                  sync: { ...current.sync, syncSpaceJoined: true, enabled: true }
                }))
              }
            >
              加入
            </button>
          </div>
        </PreferenceStackedRow>
        <PreferenceDivider />
        <PreferenceStackedRow title="连接状态" detail="测试当前服务端地址和设备凭据是否可用">
          <div className="preference-status-row">
            <PreferenceStatusLabel text={sync.serverUrl ? "已配置服务端" : "尚未检查连接"} />
            <button className="preference-push-button" type="button">
              测试连接
            </button>
          </div>
        </PreferenceStackedRow>
      </PreferenceSectionGroup>

      <PreferenceSectionGroup title="下载路径偏好">
        <PreferenceStackedRow
          title="优先局域网 / P2P"
          detail="下载真实文件时按偏好选择 P2P 或服务端路径"
        >
          <SegmentedControl<DownloadPathMode>
            width={300}
            value={sync.downloadPathMode}
            options={[
              { label: "自动", value: "auto" },
              { label: "仅 P2P", value: "p2p_only" },
              { label: "仅服务端", value: "server_only" }
            ]}
            onChange={(downloadPathMode) =>
              updatePreferences((current) => ({
                ...current,
                sync: { ...current.sync, downloadPathMode }
              }))
            }
          />
        </PreferenceStackedRow>
        <PreferenceDivider />
        <PreferenceRow title="当前路径质量" detail="尚未测速；下载时会比较可用路径并按偏好选择">
          <PreferenceValuePill text={downloadPathLabel(sync.downloadPathMode)} prominent />
        </PreferenceRow>
      </PreferenceSectionGroup>
    </div>
  );
}

function PreferenceRulesSection({
  preferences,
  updatePreferences
}: {
  preferences: PreferencesState;
  updatePreferences: UpdatePreferences;
}) {
  const ignoredApps = preferences.rules.ignoredAppIdentifiers;
  const [selectedIdentifier, setSelectedIdentifier] = useState<string | null>(ignoredApps[0] ?? null);

  useEffect(() => {
    if (selectedIdentifier && !ignoredApps.includes(selectedIdentifier)) {
      setSelectedIdentifier(ignoredApps[0] ?? null);
    }
  }, [ignoredApps, selectedIdentifier]);

  function addIgnoredApp() {
    const value = window.prompt("输入要忽略的应用标识", "com.example.App");
    const trimmed = value?.trim();
    if (!trimmed) {
      return;
    }
    updatePreferences((current) => ({
      ...current,
      rules: {
        ...current.rules,
        ignoredAppIdentifiers: Array.from(
          new Set([...current.rules.ignoredAppIdentifiers, trimmed])
        )
      }
    }));
    setSelectedIdentifier(trimmed);
  }

  function removeIgnoredApp() {
    if (!selectedIdentifier) {
      return;
    }
    updatePreferences((current) => ({
      ...current,
      rules: {
        ...current.rules,
        ignoredAppIdentifiers: current.rules.ignoredAppIdentifiers.filter(
          (identifier) => identifier !== selectedIdentifier
        )
      }
    }));
  }

  return (
    <div className="preferences-section-stack privacy-stack">
      <PreferenceSectionGroup title="系统权限">
        <PreferenceRow title="窗口标题采集" detail="Windows 版本会在接入原生权限后显示当前授权状态">
          <button
            className="preference-push-button"
            type="button"
            onClick={() =>
              updatePreferences((current) => ({
                ...current,
                rules: { ...current.rules, accessibilityPermissionRequested: true }
              }))
            }
          >
            打开系统设置
          </button>
        </PreferenceRow>
      </PreferenceSectionGroup>

      <PreferenceSectionGroup title="链接预览">
        <PreferenceRow title="网页完整预览" detail="按空格时加载真实网页">
          <SwitchControl
            checked={preferences.rules.webPreviewEnabled}
            onChange={(webPreviewEnabled) =>
              updatePreferences((current) => ({
                ...current,
                rules: { ...current.rules, webPreviewEnabled }
              }))
            }
          />
        </PreferenceRow>
      </PreferenceSectionGroup>

      <section className="ignored-app-section">
        <div className="ignored-app-heading">
          <h2>忽略应用程序</h2>
          <p>不要保存从以下应用程序或窗口复制的内容。</p>
        </div>
        <div className="ignored-app-card">
          {ignoredApps.length === 0 ? (
            <div className="ignored-app-empty">
              <Monitor size={20} strokeWidth={2} />
              <div>
                <strong>未添加应用程序</strong>
                <span>点击 + 选择需要忽略的应用。</span>
              </div>
            </div>
          ) : (
            ignoredApps.map((identifier, index) => (
              <div key={identifier}>
                <button
                  type="button"
                  className={`ignored-app-row ${
                    selectedIdentifier === identifier ? "is-selected" : ""
                  }`}
                  onClick={() => setSelectedIdentifier(identifier)}
                >
                  <span className="ignored-app-icon">
                    <Monitor size={18} strokeWidth={2} />
                  </span>
                  <div>
                    <strong>{applicationNameFromIdentifier(identifier)}</strong>
                    <span>{identifier}</span>
                  </div>
                </button>
                {index < ignoredApps.length - 1 && <PreferenceDivider />}
              </div>
            ))
          )}

          <div className="ignored-app-toolbar">
            <button type="button" aria-label="添加应用程序" onClick={addIgnoredApp}>
              <Plus size={14} strokeWidth={2.2} />
            </button>
            <span />
            <button
              type="button"
              aria-label="移除选中的应用程序"
              disabled={!selectedIdentifier}
              onClick={removeIgnoredApp}
            >
              <Minus size={14} strokeWidth={2.2} />
            </button>
          </div>
        </div>
      </section>
    </div>
  );
}

function PreferenceShortcutSection({
  preferences,
  updatePreferences,
  resetShortcuts
}: {
  preferences: PreferencesState;
  updatePreferences: UpdatePreferences;
  resetShortcuts: () => void;
}) {
  const shortcuts = preferences.shortcuts;
  return (
    <div className="preferences-section-stack">
      <PreferenceSectionGroup title="Global Actions">
        <PreferenceRow title="Open Clipboard" detail="Open the bottom panel from any app">
          <PreferenceEditableShortcutControl
            shortcut={shortcuts.openPanel}
            onChange={(openPanel) =>
              updatePreferences((current) => ({
                ...current,
                shortcuts: { ...current.shortcuts, openPanel }
              }))
            }
          />
        </PreferenceRow>
      </PreferenceSectionGroup>

      <PreferenceSectionGroup title="Panel Actions">
        <PreferenceRow title="显示下一个 Pinboard" detail="在面板内切换到下一个 Pinboard">
          <PreferenceEditableShortcutControl
            shortcut={shortcuts.nextPinboard}
            onChange={(nextPinboard) =>
              updatePreferences((current) => ({
                ...current,
                shortcuts: { ...current.shortcuts, nextPinboard }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="显示上一个 Pinboard" detail="在面板内切换到上一个 Pinboard">
          <PreferenceEditableShortcutControl
            shortcut={shortcuts.previousPinboard}
            onChange={(previousPinboard) =>
              updatePreferences((current) => ({
                ...current,
                shortcuts: { ...current.shortcuts, previousPinboard }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="Quick Access Items" detail="Hold Command to show numbers, then press a number to copy">
          <div className="shortcut-modifier-row">
            <ModifierPicker<ShortcutModifier>
              value={shortcuts.quickPasteModifier}
              options={modifierOptions}
              onChange={(quickPasteModifier) =>
                updatePreferences((current) => ({
                  ...current,
                  shortcuts: { ...current.shortcuts, quickPasteModifier }
                }))
              }
            />
            <span className="shortcut-plus-label">+ 1...9</span>
          </div>
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="纯文本模式" detail="快速取用时按住该修饰键复制纯文本">
          <ModifierPicker<PlainTextModifier>
            value={shortcuts.plainTextModifier}
            options={plainTextModifierOptions}
            onChange={(plainTextModifier) =>
              updatePreferences((current) => ({
                ...current,
                shortcuts: { ...current.shortcuts, plainTextModifier }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="Search Current Content" detail="Expand and focus the search field">
          <PreferenceShortcutPill label="⌘ F" />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="Preview Selected Item" detail="Open or close the temporary preview popover">
          <PreferenceShortcutPill label="Space" />
        </PreferenceRow>
      </PreferenceSectionGroup>

      <div className="preference-reset-row">
        <button className="preference-push-button" type="button" onClick={resetShortcuts}>
          将快捷方式重置为默认...
        </button>
      </div>
    </div>
  );
}

function PreferenceAboutSection({
  preferences,
  updatePreferences
}: {
  preferences: PreferencesState;
  updatePreferences: UpdatePreferences;
}) {
  return (
    <div className="preferences-section-stack">
      <PreferenceSectionGroup>
        <div className="preference-about-hero">
          <div className="preference-app-icon">
            <ClipboardList size={30} strokeWidth={1.9} />
          </div>
          <div>
            <h2>ClipDock Panel</h2>
            <p>本地剪贴坞</p>
          </div>
        </div>
      </PreferenceSectionGroup>

      <PreferenceSectionGroup title="应用信息">
        <PreferenceRow title="版本" detail="Windows / Tauri 面板预览版">
          <PreferenceValuePill text="0.1.0" prominent />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="检查更新" detail="自动检查新版本并在可用时提醒">
          <SwitchControl
            checked={preferences.about.automaticUpdateChecksEnabled}
            onChange={(automaticUpdateChecksEnabled) =>
              updatePreferences((current) => ({
                ...current,
                about: { ...current.about, automaticUpdateChecksEnabled }
              }))
            }
          />
        </PreferenceRow>
        <PreferenceDivider />
        <PreferenceRow title="项目" detail="打开 ClipDock 仓库说明">
          <button className="preference-icon-push-button" type="button" aria-label="打开项目说明">
            <ExternalLink size={15} strokeWidth={2.2} />
          </button>
        </PreferenceRow>
      </PreferenceSectionGroup>
    </div>
  );
}

function PreferenceSectionGroup({
  title,
  children
}: {
  title?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="preference-group">
      {title && <h2 className="preference-group-title">{title}</h2>}
      <div className="preference-group-card">{children}</div>
    </section>
  );
}

function PreferenceRow({
  title,
  detail,
  children
}: {
  title: string;
  detail: string;
  children: React.ReactNode;
}) {
  return (
    <div className="preference-row">
      <div className="preference-row-text">
        <strong>{title}</strong>
        <span>{detail}</span>
      </div>
      <div className="preference-row-accessory">{children}</div>
    </div>
  );
}

function PreferenceStackedRow({
  title,
  detail,
  children
}: {
  title: string;
  detail: string;
  children: React.ReactNode;
}) {
  return (
    <div className="preference-stacked-row">
      <div className="preference-row-text">
        <strong>{title}</strong>
        <span>{detail}</span>
      </div>
      <div className="preference-stacked-content">{children}</div>
    </div>
  );
}

function PreferenceDivider() {
  return <div className="preference-divider" role="separator" />;
}

function SwitchControl({
  checked,
  onChange
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <button
      type="button"
      className={`preference-switch ${checked ? "is-on" : ""}`}
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
    >
      <span />
    </button>
  );
}

function SegmentedControl<T extends string | number>({
  value,
  options,
  width,
  onChange
}: {
  value: T;
  width: number;
  options: Array<{ label: string; value: T }>;
  onChange: (value: T) => void;
}) {
  return (
    <div className="preference-segmented" style={{ width }}>
      {options.map((option) => (
        <button
          key={String(option.value)}
          type="button"
          className={value === option.value ? "is-selected" : ""}
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function TextInput({
  value,
  placeholder,
  onChange
}: {
  value: string;
  placeholder: string;
  onChange: (value: string) => void;
}) {
  return (
    <input
      className="preference-text-input"
      value={value}
      placeholder={placeholder}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

function PreferenceEditableShortcutControl({
  shortcut,
  onChange
}: {
  shortcut: KeyboardShortcut | null;
  onChange: (shortcut: KeyboardShortcut | null) => void;
}) {
  return (
    <div className="editable-shortcut-control">
      <ShortcutRecorder shortcut={shortcut} onChange={onChange} />
      {shortcut && (
        <>
          <div className="editable-shortcut-divider" />
          <button
            className="shortcut-clear-button"
            type="button"
            aria-label="移除快捷键"
            onClick={() => onChange(null)}
          >
            <X size={13} strokeWidth={2.6} />
          </button>
        </>
      )}
    </div>
  );
}

function ShortcutRecorder({
  shortcut,
  onChange
}: {
  shortcut: KeyboardShortcut | null;
  onChange: (shortcut: KeyboardShortcut) => void;
}) {
  const [recording, setRecording] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!recording) {
      return undefined;
    }

    const onKeyDown = (event: KeyboardEvent) => {
      event.preventDefault();
      event.stopPropagation();

      const result = shortcutFromKeyboardEvent(event);
      if (result.kind === "cancel") {
        setRecording(false);
        setError(null);
      } else if (result.kind === "recorded") {
        onChange(result.shortcut);
        setRecording(false);
        setError(null);
      } else if (result.kind === "invalid") {
        setError(result.message);
        window.setTimeout(() => setError(null), 1200);
      }
    };

    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, [onChange, recording]);

  return (
    <button
      className={`shortcut-recorder ${recording ? "is-recording" : ""} ${error ? "has-error" : ""}`}
      type="button"
      onClick={() => {
        setRecording(true);
        setError(null);
      }}
    >
      {error ?? (recording ? "按下快捷键" : formatKeyboardShortcut(shortcut))}
    </button>
  );
}

function ModifierPicker<T extends ModifierKey>({
  value,
  options,
  onChange
}: {
  value: T;
  options: T[];
  onChange: (value: T) => void;
}) {
  return (
    <select
      className="modifier-picker"
      value={value}
      onChange={(event) => onChange(event.target.value as T)}
    >
      {options.map((option) => (
            <option key={option} value={option}>
          {modifierDisplayName(option)}
        </option>
      ))}
    </select>
  );
}

function PreferenceShortcutPill({ label }: { label: string }) {
  return <span className="shortcut-pill">{label}</span>;
}

function PreferenceValuePill({ text, prominent = false }: { text: string; prominent?: boolean }) {
  return <span className={`preference-value-pill ${prominent ? "is-prominent" : ""}`}>{text}</span>;
}

function PreferenceInlineValue({ value }: { value: string }) {
  return <span className="preference-inline-value">{value}</span>;
}

function PreferenceStatusLabel({ text }: { text: string }) {
  return (
    <span className="preference-status-label">
      <CheckCircle size={14} strokeWidth={2.2} />
      {text}
    </span>
  );
}

function retentionDetail(days: RetentionDays): string {
  switch (days) {
    case 1:
      return "保留 1 天";
    case 7:
      return "保留 1 周";
    case 30:
      return "保留 1 个月";
    case 365:
      return "保留 1 年";
    case "forever":
      return "永久保留";
  }
}

function downloadPathLabel(mode: DownloadPathMode): string {
  switch (mode) {
    case "p2p_only":
      return "仅 P2P";
    case "server_only":
      return "仅服务端";
    case "auto":
      return "自动选择";
  }
}

function applicationNameFromIdentifier(identifier: string): string {
  const fileName = identifier.split(/[\\/]/).filter(Boolean).at(-1) ?? identifier;
  const withoutExtension = fileName.replace(/\.app$/i, "");
  const bundleName = withoutExtension.split(".").at(-1);
  return bundleName && bundleName.length > 1 ? bundleName : withoutExtension;
}
