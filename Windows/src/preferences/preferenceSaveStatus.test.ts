import { describe, expect, it } from "vitest";
import { applyCaptureDocument, capturePatchDifference, capturePreferencesWarning, type CapturePreferencesDocument } from "./capturePreferences";
import { makeDefaultPreferencesState } from "./preferencesDefaults";
import { PreferenceSaveStatus } from "./preferenceSaveStatus";

const failed = "采集设置保存失败，请重试；尚未确认生效";
const initial: CapturePreferencesDocument = {
  revision: 1, history: { retention_days: 30 }, ignore_list: { ignored_app_identifiers: [] }
};

describe("preference save cycle", () => {
  it("retains A's failure when B saves a different field and restores confirmed values", () => {
    const status = new PreferenceSaveStatus();
    const before = applyCaptureDocument(makeDefaultPreferencesState(), initial);
    const editA = { ...before, rules: { ...before.rules, ignoredAppIdentifiers: ["Private.exe"] } };
    const editB = { ...editA, history: { retentionDays: 7 as const } };
    const patchB = capturePatchDifference(editA, editB);
    expect(patchB).not.toHaveProperty("ignoredAppIdentifiers");
    status.begin();
    status.begin();
    status.complete(failed);
    expect(status.hasPending).toBe(true);
    expect(status.message).toBe(failed);
    // The event and response for B must not erase A's failure notice.
    const savedB = { ...initial, revision: 2, history: { retention_days: patchB.retentionDays! } };
    status.observe(capturePreferencesWarning(savedB));
    status.complete(capturePreferencesWarning(savedB));
    const confirmed = applyCaptureDocument(editB, savedB);
    expect(status.hasPending).toBe(false);
    expect(status.message).toBe(failed);
    expect(confirmed.rules.ignoredAppIdentifiers).toEqual([]);
    expect(confirmed.history.retentionDays).toBe(7);
    status.observe(null);
    expect(status.message).toBe(failed);
  });

  it("retains B's failure while preserving A's confirmed field", () => {
    const status = new PreferenceSaveStatus();
    status.begin();
    status.begin();
    const savedA = { ...initial, revision: 2, ignore_list: { ignored_app_identifiers: ["Private.exe"] } };
    status.complete(capturePreferencesWarning(savedA));
    status.complete(failed);
    const confirmed = applyCaptureDocument(makeDefaultPreferencesState(), savedA);
    expect(confirmed.rules.ignoredAppIdentifiers).toEqual(["Private.exe"]);
    expect(confirmed.history.retentionDays).toBe(30);
    expect(status.message).toBe(failed);
    expect(status.hasPending).toBe(false);
  });

  it("accumulates maintenance warnings and failures until a new user save cycle", () => {
    const status = new PreferenceSaveStatus();
    const warning = capturePreferencesWarning({ ...initial, maintenance: { status: "warning", may_have_changed: true } });
    status.begin();
    status.begin();
    status.complete(warning);
    status.begin(); // Another edit joins the still-pending cycle.
    expect(status.message).toBe(warning);
    status.complete(failed);
    status.observe(warning); // Duplicate external event is reported once.
    status.complete(null);
    status.observe(null);
    expect(status.message).toBe(`${warning}；${failed}`);
    status.begin();
    expect(status.message).toBeNull();
    status.complete(null);
  });
});
