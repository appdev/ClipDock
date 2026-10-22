import { describe, expect, it } from "vitest";
import { applyCaptureDocument, capturePatch, capturePatchDifference, capturePreferencesWarning, mergeExternalPreferences, newestCaptureDocument } from "./capturePreferences";
import { makeDefaultPreferencesState } from "./preferencesDefaults";

describe("capture preferences adapter", () => {
  it("accepts the committed document when maintenance or marker work failed", () => {
    const saved = { revision: 7, history: { retention_days: 7 },
      ignore_list: { ignored_app_identifiers: ["KeePass.exe"] },
      warnings: [{ stage: "legacy_marker", code: "io_failed" }] };
    const state = applyCaptureDocument(makeDefaultPreferencesState(), saved);
    expect(state.history.retentionDays).toBe(7);
    expect(state.rules.ignoredAppIdentifiers).toEqual(["KeePass.exe"]);
    expect(capturePreferencesWarning(saved)).toContain("已保存");
    expect(capturePreferencesWarning({ ...saved, warnings: [{ stage: "history_maintenance", code: "io_failed" }] })).toContain("设置仍可修改");
  });
  it("maps forever explicitly without claiming 365 days is permanent", () => {
    const state = makeDefaultPreferencesState(); state.history.retentionDays = "forever";
    expect(capturePatch(state)).toMatchObject({ retentionForever: true });
    expect(capturePatch(state).retentionDays).toBeUndefined();
    const mapped = applyCaptureDocument(state, { revision: 1, history: { retention_days: 365, retention_forever: false }, ignore_list: { ignored_app_identifiers: [] } });
    expect(mapped.history.retentionDays).toBe(365);
    expect(mapped.shortcuts).toBe(state.shortcuts);
  });
  it("does not overwrite another window's rules when changing only retention", () => {
    const stale = makeDefaultPreferencesState(); stale.rules.ignoredAppIdentifiers = [];
    const updated = { ...stale, history: { retentionDays: 7 as const } };
    const patch = capturePatchDifference(stale, updated);
    const server = { retentionDays: 30, retentionForever: false, ignoredAppIdentifiers: ["KeePass.exe"] };
    expect({ ...server, ...patch }).toEqual({ retentionDays: 7, retentionForever: false, ignoredAppIdentifiers: ["KeePass.exe"] });
    expect(capturePatchDifference(stale, { ...stale, rules: { ...stale.rules, ignoredAppIdentifiers: ["KeePass.exe"] } })).toEqual({ ignoredAppIdentifiers: ["KeePass.exe"] });
  });
  it("ignores a stale IPC response that follows a newer change event", () => {
    const latest = { revision: 9, history: { retention_days: 7 }, ignore_list: { ignored_app_identifiers: ["KeePass.exe"] } };
    expect(newestCaptureDocument(latest, { ...latest, revision: 8 })).toBe(latest);
  });
  it("keeps an optimistic pending edit through another window's storage event so it can be undone", () => {
    const local = makeDefaultPreferencesState(); local.appearance.mode = "dark";
    const pending = { ...local, history: { retentionDays: 7 as const } };
    const saved = { revision: 1, history: { retention_days: 30 }, ignore_list: { ignored_app_identifiers: [] } };
    const merged = mergeExternalPreferences(local, pending, saved, true);
    expect(merged.history.retentionDays).toBe(7);
    expect(merged.appearance.mode).toBe("dark");
    expect(capturePatchDifference(merged, { ...merged, history: { retentionDays: 30 } })).toEqual({ retentionDays: 30, retentionForever: false });
    expect(mergeExternalPreferences(local, pending, saved, false).history.retentionDays).toBe(30);
  });
});
