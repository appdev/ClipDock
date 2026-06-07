export type PreferenceSectionId = "general" | "sync" | "rules" | "shortcuts" | "about";

export type ModifierKey = "command" | "option" | "control" | "shift";

export type ShortcutModifier = "command" | "control" | "option";

export type PlainTextModifier = ModifierKey;

export type AppearanceMode = "system" | "light" | "dark";

export type RetentionDays = 1 | 7 | 30 | 365 | "forever";

export type DownloadPathMode = "auto" | "p2p_only" | "server_only";

export type KeyboardShortcut = {
  keyCode: number;
  modifiers: ModifierKey[];
};

export type GeneralPreferences = {
  launchAtLogin: boolean;
  showMenuBarItem: boolean;
  copyCompletionHudEnabled: boolean;
  externalCopySoundEnabled: boolean;
};

export type ShortcutPreferences = {
  openPanel: KeyboardShortcut | null;
  previousPinboard: KeyboardShortcut | null;
  nextPinboard: KeyboardShortcut | null;
  quickPasteModifier: ShortcutModifier;
  plainTextModifier: PlainTextModifier;
  pasteDirectlyToTarget: boolean;
  alwaysPasteAsPlainText: boolean;
};

export type AppearancePreferences = {
  mode: AppearanceMode;
  previewPopoverEnabled: boolean;
};

export type HistoryPreferences = {
  retentionDays: RetentionDays;
};

export type SyncPreferences = {
  enabled: boolean;
  serverUrl: string;
  deviceName: string;
  p2pEnabled: boolean;
  syncSpaceJoined: boolean;
  downloadPathMode: DownloadPathMode;
};

export type RulePreferences = {
  accessibilityPermissionRequested: boolean;
  webPreviewEnabled: boolean;
  ignoredAppIdentifiers: string[];
};

export type AboutPreferences = {
  automaticUpdateChecksEnabled: boolean;
};

export type PreferencesState = {
  version: 1;
  general: GeneralPreferences;
  shortcuts: ShortcutPreferences;
  appearance: AppearancePreferences;
  history: HistoryPreferences;
  sync: SyncPreferences;
  rules: RulePreferences;
  about: AboutPreferences;
};
