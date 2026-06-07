import type { PreferencesState } from "./preferencesTypes";

export const preferencesStorageKey = "clipdock.windows.preferences.v1";

export const defaultPreferencesState: PreferencesState = {
  version: 1,
  general: {
    launchAtLogin: false,
    showMenuBarItem: true,
    copyCompletionHudEnabled: true,
    externalCopySoundEnabled: false
  },
  shortcuts: {
    openPanel: {
      keyCode: 7,
      modifiers: ["command", "shift"]
    },
    previousPinboard: {
      keyCode: 123,
      modifiers: ["command"]
    },
    nextPinboard: {
      keyCode: 124,
      modifiers: ["command"]
    },
    quickPasteModifier: "command",
    plainTextModifier: "shift",
    pasteDirectlyToTarget: false,
    alwaysPasteAsPlainText: false
  },
  appearance: {
    mode: "system",
    previewPopoverEnabled: true
  },
  history: {
    retentionDays: 30
  },
  sync: {
    enabled: false,
    serverUrl: "",
    deviceName: "Windows PC",
    p2pEnabled: true,
    syncSpaceJoined: false,
    downloadPathMode: "auto"
  },
  rules: {
    accessibilityPermissionRequested: false,
    webPreviewEnabled: false,
    ignoredAppIdentifiers: []
  },
  about: {
    automaticUpdateChecksEnabled: true
  }
};

export function makeDefaultPreferencesState(): PreferencesState {
  return structuredClone(defaultPreferencesState);
}
