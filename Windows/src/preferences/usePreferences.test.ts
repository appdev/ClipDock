import { expect, test } from "vitest";
import { mergePreferences } from "./usePreferences";

test("legacy sync configuration is dropped while local preferences survive", () => {
  const preferences = mergePreferences({
    version: 1,
    appearance: { mode: "dark" },
    history: { retentionDays: 365 },
    shortcuts: { alwaysPasteAsPlainText: true },
    sync: { enabled: true, serverUrl: "https://example.invalid" }
  });

  expect(preferences.appearance.mode).toBe("dark");
  expect(preferences.history.retentionDays).toBe(365);
  expect(preferences.shortcuts.alwaysPasteAsPlainText).toBe(true);
  expect(preferences).not.toHaveProperty("sync");
  expect(mergePreferences(JSON.parse(JSON.stringify(preferences)))).toEqual(preferences);
});
