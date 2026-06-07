import { useCallback, useEffect, useState } from "react";
import {
  makeDefaultPreferencesState,
  preferencesStorageKey
} from "./preferencesDefaults";
import type { PreferencesState } from "./preferencesTypes";

type PreferencesUpdater = (current: PreferencesState) => PreferencesState;

export function usePreferences() {
  const [preferences, setPreferences] = useState<PreferencesState>(() => readPreferences());

  useEffect(() => {
    const onStorage = (event: StorageEvent) => {
      if (event.key === preferencesStorageKey) {
        setPreferences(readPreferences());
      }
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  const updatePreferences = useCallback((updater: PreferencesUpdater) => {
    setPreferences((current) => {
      const next = updater(current);
      writePreferences(next);
      return next;
    });
  }, []);

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

function mergePreferences(value: unknown): PreferencesState {
  const defaults = makeDefaultPreferencesState();
  if (!value || typeof value !== "object") {
    return defaults;
  }

  const candidate = value as Partial<PreferencesState>;
  return {
    ...defaults,
    ...candidate,
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
    sync: {
      ...defaults.sync,
      ...candidate.sync
    },
    rules: {
      ...defaults.rules,
      ...candidate.rules,
      ignoredAppIdentifiers: Array.isArray(candidate.rules?.ignoredAppIdentifiers)
        ? candidate.rules.ignoredAppIdentifiers
        : defaults.rules.ignoredAppIdentifiers
    },
    about: {
      ...defaults.about,
      ...candidate.about
    }
  };
}
