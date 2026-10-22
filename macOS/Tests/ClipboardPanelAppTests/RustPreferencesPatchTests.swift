import Foundation
import Testing
@testable import ClipboardPanelApp

struct RustPreferencesPatchTests {
    @Test
    func fieldPatchRoundTripsThroughTheRustBridge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("preferences-patch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = RustCoreClient()
        _ = try client.openWithoutHistoryMaintenance(appSupportDirectory: directory).get()
        let before = try client.getPreferencesWithoutHistoryMaintenance(appSupportDirectory: directory).get().preferences
        var next = before
        next.appearance.mode = "dark"
        next.shortcuts.openPanel = nil
        let saved = try client.patchPreferences(appSupportDirectory: directory,
            patch: RustPreferencesPatch(previous: before, next: next)).get()
        #expect(saved.document.appearance.mode == "dark")
        #expect(saved.document.shortcuts.openPanel == nil)
        #expect(Set(saved.changedSections) == ["appearance", "shortcuts"])
        #expect(saved.maintenance.status == "not_needed")
        #expect(try client.getPreferencesWithoutHistoryMaintenance(appSupportDirectory: directory).get().preferences == saved.document)
    }

    @Test
    func editedLeavesAndExplicitShortcutClearAreEncodedWithoutUnrelatedFields() throws {
        let before = RustPreferencesDocument()
        var after = before
        after.shortcuts.openPanel = nil
        after.history.retentionForever = true
        let patch = RustPreferencesPatch(previous: before, next: after)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        #expect(Set(object.keys) == ["history", "shortcuts"])
        let shortcuts = try #require(object["shortcuts"] as? [String: [String: String]])
        #expect(shortcuts["open_panel"]?["op"] == "clear")
        let applied = try patch.applying(to: before)
        #expect(applied.shortcuts.openPanel == nil)
        #expect(applied.history.retentionForever)
        #expect(applied.general == before.general)
        #expect(RustPreferencesPatch(previous: after, next: after).isEmpty)
    }

    @Test
    @MainActor
    func queuedReverseEditIsNotLostWhileTheFirstSaveIsSuspended() async throws {
        var persisted = RustPreferencesDocument()
        var saves = 0
        var resumeFirst: CheckedContinuation<Void, Never>?
        let coordinator = makeCoordinator { patch in
            saves += 1
            if saves == 1 {
                await withCheckedContinuation { resumeFirst = $0 }
            }
            persisted = try! patch.applying(to: persisted)
            return .success(saved(persisted))
        }
        let initial = persisted
        var dark = initial
        dark.appearance.mode = "dark"
        let firstPatch = RustPreferencesPatch(previous: initial, next: dark)
        let reversePatch = RustPreferencesPatch(previous: dark, next: initial)
        let first = Task { await coordinator.persist(patch: firstPatch) }
        for _ in 0..<1_000 where resumeFirst == nil { await Task.yield() }
        let resume = try #require(resumeFirst)
        let second = Task { await coordinator.persist(patch: reversePatch) }
        resume.resume()
        _ = try await first.value.get()
        _ = try await second.value.get()
        #expect(saves == 2)
        #expect(persisted.appearance.mode == "system")
        #expect(coordinator.currentPreferences.appearance.mode == "system")
    }

    @Test
    @MainActor
    func laterPatchRebasesOnConfirmedFieldsAfterEarlierSaveFails() async throws {
        var persisted = RustPreferencesDocument()
        var saves = 0
        let coordinator = makeCoordinator { patch in
            saves += 1
            if saves == 1 {
                return .failure(RustCoreError(code: "database_unavailable", messageKey: "test", recoverable: true, message: "fixture"))
            }
            persisted = try! patch.applying(to: persisted)
            return .success(saved(persisted))
        }
        let initial = persisted
        var firstDisplay = initial
        firstDisplay.appearance.mode = "dark"
        var secondDisplay = firstDisplay
        secondDisplay.general.showMenuBarItem = false
        let firstPatch = RustPreferencesPatch(previous: initial, next: firstDisplay)
        let secondPatch = RustPreferencesPatch(previous: firstDisplay, next: secondDisplay)
        _ = await coordinator.persist(patch: firstPatch)
        let result = try await coordinator.persist(patch: secondPatch).get()
        #expect(result.preferences.appearance.mode == "system")
        #expect(!result.preferences.general.showMenuBarItem)
    }

    @Test
    @MainActor
    func explicitLoginToggleCanReverseNativeSuccessAfterDatabaseSaveFails() async throws {
        var systemEnabled = false
        var nativeRequests: [Bool] = []
        var saves = 0
        let coordinator = PreferencesCoordinator(
            loadPreferencesOperation: { .success(RustPreferencesResult(schemaVersion: 17, preferences: RustPreferencesDocument())) },
            patchPreferencesOperation: { patch in
                saves += 1
                if saves == 1 {
                    return .failure(RustCoreError(code: "database_unavailable", messageKey: "test", recoverable: true, message: "fixture"))
                }
                return .success(saved(try! patch.applying(to: RustPreferencesDocument())))
            },
            currentLaunchAtLoginState: { LaunchAtLoginPresentation(isOn: systemEnabled, canChange: true, detail: "fixture") },
            setLaunchAtLoginEnabled: { enabled in
                nativeRequests.append(enabled)
                systemEnabled = enabled
                return .success(LaunchAtLoginPresentation(isOn: enabled, canChange: true, detail: "fixture"))
            },
            currentAccessibilityPermissionState: {
                AccessibilityPermissionPresentation(isTrusted: false, detail: "fixture", actionTitle: "fixture", canOpenSettings: true)
            },
            openAccessibilitySettings: {}
        )
        _ = await coordinator.persist(patch: RustPreferencesPatch().settingLaunchAtLogin(true))
        #expect(systemEnabled)
        #expect(!coordinator.currentPreferences.general.launchAtLogin)
        // Both confirmed document snapshots are false after the failed save;
        // the UI's explicit false intent must still reach the native controller.
        let confirmed = coordinator.currentPreferences
        let reverse = RustPreferencesPatch(previous: confirmed, next: confirmed, launchAtLoginIntent: false)
        #expect(!reverse.isEmpty)
        let result = try await coordinator.persist(patch: reverse).get()
        #expect(nativeRequests == [true, false])
        #expect(!systemEnabled)
        #expect(!result.preferences.general.launchAtLogin)
    }

    @Test
    @MainActor
    func maintenanceWarningKeepsTheSavedDocumentAndRequestsHistoryRefresh() async throws {
        let coordinator = makeCoordinator { patch in
            let document = try! patch.applying(to: RustPreferencesDocument())
            return .success(RustPreferencesPatchResult(document: document, changedSections: ["history"], maintenance:
                RustPreferencesMaintenance(status: "warning", stage: "history_policy", code: "io_failed", mayHaveChanged: true)))
        }
        let before = RustPreferencesDocument()
        var next = before
        next.history.retentionDays = 7
        let result = try await coordinator.persist(patch: RustPreferencesPatch(previous: before, next: next)).get()
        #expect(result.preferences.history.retentionDays == 7)
        #expect(coordinator.currentPreferences.history.retentionDays == 7)
        #expect(result.shouldRefreshList)
        #expect(result.statusText?.contains("io_failed") == true)
    }

    @MainActor
    private func makeCoordinator(
        save: @escaping (RustPreferencesPatch) async -> Result<RustPreferencesPatchResult, RustCoreError>
    ) -> PreferencesCoordinator {
        PreferencesCoordinator(
            loadPreferencesOperation: { .success(RustPreferencesResult(schemaVersion: 17, preferences: RustPreferencesDocument())) },
            patchPreferencesOperation: save,
            currentLaunchAtLoginState: { LaunchAtLoginPresentation(isOn: false, canChange: true, detail: "fixture") },
            setLaunchAtLoginEnabled: { enabled in .success(LaunchAtLoginPresentation(isOn: enabled, canChange: true, detail: "fixture")) },
            currentAccessibilityPermissionState: {
                AccessibilityPermissionPresentation(isTrusted: false, detail: "fixture", actionTitle: "fixture", canOpenSettings: true)
            },
            openAccessibilitySettings: {}
        )
    }

    private func saved(_ document: RustPreferencesDocument) -> RustPreferencesPatchResult {
        RustPreferencesPatchResult(document: document, changedSections: ["appearance"],
                                   maintenance: RustPreferencesMaintenance(status: "not_needed", stage: nil, code: nil, mayHaveChanged: false))
    }
}
