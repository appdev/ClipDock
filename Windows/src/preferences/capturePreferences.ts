import type { PreferencesState, RetentionDays } from "./preferencesTypes";

export type CapturePreferencesDocument = {
  revision: number;
  history: { retention_days: number; retention_forever?: boolean };
  ignore_list: { ignored_app_identifiers: string[] };
  warnings?: Array<{ stage: string; code: string }>;
  maintenance?: { status: "not_needed" | "applied" | "warning"; may_have_changed: boolean } | null;
};

export function capturePreferencesWarning(document: CapturePreferencesDocument): string | null {
  if (document.warnings?.some((warning) => warning.stage === "legacy_marker")) {
    return "采集设置已保存，但采集启动标记写入失败；请重试保存";
  }
  if (document.maintenance?.status === "warning" || document.warnings?.some((warning) => warning.stage === "history_maintenance")) {
    return "采集设置已确认，但历史清理未完成；设置仍可修改";
  }
  return null;
}
export type CapturePreferencesPatch = {
  retentionDays?: number; retentionForever?: boolean; ignoredAppIdentifiers?: string[];
};

export function capturePatch(state: PreferencesState): CapturePreferencesPatch {
  return {
    ...(state.history.retentionDays === "forever" ? {} : { retentionDays: state.history.retentionDays }),
    retentionForever: state.history.retentionDays === "forever",
    ignoredAppIdentifiers: state.rules.ignoredAppIdentifiers
  };
}

export function applyCaptureDocument(state: PreferencesState, document: CapturePreferencesDocument): PreferencesState {
  const days = document.history.retention_forever ? "forever" : document.history.retention_days;
  return {
    ...state,
    history: { ...state.history, retentionDays: days as RetentionDays },
    rules: { ...state.rules, ignoredAppIdentifiers: document.ignore_list.ignored_app_identifiers }
  };
}

export function sameCapturePreferences(a: PreferencesState, b: PreferencesState): boolean {
  return JSON.stringify(capturePatch(a)) === JSON.stringify(capturePatch(b));
}

export function capturePatchDifference(previous: PreferencesState, next: PreferencesState): CapturePreferencesPatch {
  const patch: CapturePreferencesPatch = {};
  if (previous.history.retentionDays !== next.history.retentionDays) {
    patch.retentionForever = next.history.retentionDays === "forever";
    if (next.history.retentionDays !== "forever") patch.retentionDays = next.history.retentionDays;
  }
  if (JSON.stringify(previous.rules.ignoredAppIdentifiers) !== JSON.stringify(next.rules.ignoredAppIdentifiers)) {
    patch.ignoredAppIdentifiers = next.rules.ignoredAppIdentifiers;
  }
  return patch;
}

export function newestCaptureDocument(current: CapturePreferencesDocument | null, incoming: CapturePreferencesDocument) {
  return current && current.revision > incoming.revision ? current : incoming;
}

export function mergeExternalPreferences(local: PreferencesState, current: PreferencesState, persisted: CapturePreferencesDocument | null, pending: boolean) {
  if (pending) return { ...local, history: current.history,
    rules: { ...local.rules, ignoredAppIdentifiers: current.rules.ignoredAppIdentifiers } };
  return persisted ? applyCaptureDocument(local, persisted) : local;
}
