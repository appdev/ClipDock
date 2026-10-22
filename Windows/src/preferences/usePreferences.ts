import { useCallback, useEffect, useRef, useState } from "react";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { applyCaptureDocument, capturePatch, capturePatchDifference, capturePreferencesWarning, mergeExternalPreferences, newestCaptureDocument, sameCapturePreferences, type CapturePreferencesDocument } from "./capturePreferences";
import {
  makeDefaultPreferencesState,
  preferencesStorageKey
} from "./preferencesDefaults";
import type { PreferencesState } from "./preferencesTypes";
import { PreferenceSaveStatus } from "./preferenceSaveStatus";

type PreferencesUpdater = (current: PreferencesState) => PreferencesState;
let saveQueue: Promise<unknown> = Promise.resolve();

export function usePreferences() {
  const [preferences, setPreferences] = useState<PreferencesState>(() => readPreferences());
  const currentRef = useRef(preferences);
  const legacyRef = useRef(preferences);
  const captureGeneration = useRef(0);
  const saveStatus = useRef(new PreferenceSaveStatus());
  const initialized = useRef<Promise<unknown>>(Promise.resolve());
  const persisted = useRef<CapturePreferencesDocument | null>(null);
  const [error, setError] = useState<string | null>(null);
  const commit = useCallback((next: PreferencesState) => {
    currentRef.current = next;
    setPreferences(next);
  }, []);

  useEffect(() => {
    const onStorage = (event: StorageEvent) => {
      if (event.key === preferencesStorageKey) {
        const local = readPreferences();
        commit(isTauri() ? mergeExternalPreferences(local, currentRef.current, persisted.current, saveStatus.current.hasPending) : local);
      }
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, [commit]);

  useEffect(() => {
    if (!isTauri()) return;
    let cancelled = false;
    let unlisten: (() => void) | undefined;
    const generation = captureGeneration.current;
    const accept = (document: CapturePreferencesDocument) => {
      persisted.current = newestCaptureDocument(persisted.current, document);
      if (cancelled) return;
      saveStatus.current.observe(capturePreferencesWarning(persisted.current));
      setError(saveStatus.current.message);
      if (saveStatus.current.hasPending) return;
      const next = applyCaptureDocument(currentRef.current, persisted.current);
      commit(next);
      writePreferences(next);
    };
    initialized.current = (async () => {
      unlisten = await listen<CapturePreferencesDocument>("capture-preferences-changed", (event) => accept(event.payload));
      if (cancelled) { unlisten(); return; }
      const hasLegacy = window.localStorage.getItem(preferencesStorageKey) !== null;
      const document = await invoke<CapturePreferencesDocument>("patch_capture_preferences", {
        patch: hasLegacy ? capturePatch(legacyRef.current) : {}, migrateLegacy: true
      });
      if (captureGeneration.current === generation) accept(document);
      else persisted.current = newestCaptureDocument(persisted.current, document);
    })().catch(() => {
      if (!cancelled) {
        saveStatus.current.observe("采集设置加载失败；请重试保存");
        setError(saveStatus.current.message);
      }
    });
    return () => { cancelled = true; unlisten?.(); };
  }, [commit]);

  const updatePreferences = useCallback((updater: PreferencesUpdater) => {
    const previous = currentRef.current;
    const next = updater(previous);
    commit(next);
    writePreferences(next);
    if (!isTauri() || sameCapturePreferences(previous, next)) return;
    const patch = capturePatchDifference(previous, next);
    captureGeneration.current++;
    saveStatus.current.begin();
    setError(saveStatus.current.message);
    saveQueue = saveQueue.catch(() => undefined).then(async () => {
      await initialized.current;
      let notice: string | null = null;
      try {
        const saved = await invoke<CapturePreferencesDocument>("patch_capture_preferences", { patch });
        persisted.current = newestCaptureDocument(persisted.current, saved);
        notice = capturePreferencesWarning(saved);
      } catch {
        notice = "采集设置保存失败，请重试；尚未确认生效";
      } finally {
        saveStatus.current.complete(notice);
        setError(saveStatus.current.message);
        if (!saveStatus.current.hasPending && persisted.current) {
          const confirmed = applyCaptureDocument(currentRef.current, persisted.current);
          commit(confirmed);
          writePreferences(confirmed);
        }
      }
    });
  }, [commit]);

  const resetShortcuts = useCallback(() => {
    updatePreferences((current) => {
      const defaults = makeDefaultPreferencesState();
      return {
        ...current,
        shortcuts: defaults.shortcuts
      };
    });
  }, [updatePreferences]);

  return {
    preferences,
    error,
    updatePreferences,
    resetShortcuts
  };
}

function readPreferences(): PreferencesState {
  try {
    const raw = window.localStorage.getItem(preferencesStorageKey);
    if (!raw) {
      return makeDefaultPreferencesState();
    }

    return mergePreferences(JSON.parse(raw));
  } catch {
    return makeDefaultPreferencesState();
  }
}

function writePreferences(preferences: PreferencesState) {
  window.localStorage.setItem(preferencesStorageKey, JSON.stringify(preferences));
}

export function mergePreferences(value: unknown): PreferencesState {
  const defaults = makeDefaultPreferencesState();
  if (!value || typeof value !== "object") {
    return defaults;
  }

  const candidate = value as Partial<PreferencesState>;
  return {
    ...defaults,
    general: {
      ...defaults.general,
      ...candidate.general
    },
    shortcuts: {
      ...defaults.shortcuts,
      ...candidate.shortcuts
    },
    appearance: {
      ...defaults.appearance,
      ...candidate.appearance
    },
    history: {
      ...defaults.history,
      ...candidate.history
    },
    rules: {
      ...defaults.rules,
      ...candidate.rules,
      ignoredAppIdentifiers: Array.isArray(candidate.rules?.ignoredAppIdentifiers)
        ? candidate.rules.ignoredAppIdentifiers.filter((value): value is string => typeof value === "string")
        : defaults.rules.ignoredAppIdentifiers
    },
    about: {
      ...defaults.about,
      ...candidate.about
    }
  };
}
