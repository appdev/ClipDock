import Foundation

public struct PreferencesSystemError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public struct PreferencesApplyResult: Equatable, Sendable {
    public let preferences: RustPreferencesDocument
    public let launchAtLoginState: LaunchAtLoginPresentation
    public let accessibilityPermissionState: AccessibilityPermissionPresentation
    public let statusText: String?
    public let shouldRefreshList: Bool

    public init(
        preferences: RustPreferencesDocument,
        launchAtLoginState: LaunchAtLoginPresentation,
        accessibilityPermissionState: AccessibilityPermissionPresentation,
        statusText: String?,
        shouldRefreshList: Bool
    ) {
        self.preferences = preferences
        self.launchAtLoginState = launchAtLoginState
        self.accessibilityPermissionState = accessibilityPermissionState
        self.statusText = statusText
        self.shouldRefreshList = shouldRefreshList
    }
}

public struct PreferencesAccessibilityActionResult: Equatable, Sendable {
    public let accessibilityPermissionState: AccessibilityPermissionPresentation
    public let statusText: String

    public init(
        accessibilityPermissionState: AccessibilityPermissionPresentation,
        statusText: String
    ) {
        self.accessibilityPermissionState = accessibilityPermissionState
        self.statusText = statusText
    }
}

public struct PreferencesSceneSnapshot: Equatable, Sendable {
    public let preferences: RustPreferencesDocument
    public let launchAtLoginState: LaunchAtLoginPresentation
    public let accessibilityPermissionState: AccessibilityPermissionPresentation

    public init(
        preferences: RustPreferencesDocument,
        launchAtLoginState: LaunchAtLoginPresentation,
        accessibilityPermissionState: AccessibilityPermissionPresentation
    ) {
        self.preferences = preferences
        self.launchAtLoginState = launchAtLoginState
        self.accessibilityPermissionState = accessibilityPermissionState
    }
}

@MainActor
public final class PreferencesCoordinator {
    private let loadPreferencesOperation: () async -> Result<RustPreferencesResult, RustCoreError>
    private let savePreferencesOperation: ((RustPreferencesDocument) async -> Result<RustPreferencesResult, RustCoreError>)?
    private let patchPreferencesOperation: ((RustPreferencesPatch) async -> Result<RustPreferencesPatchResult, RustCoreError>)?
    private var pendingOperation: Task<Result<PreferencesApplyResult, RustCoreError>, Never>?
    private var operationGeneration = 0
    private let currentLaunchAtLoginState: () -> LaunchAtLoginPresentation
    private let setLaunchAtLoginEnabled: (Bool) -> Result<LaunchAtLoginPresentation, PreferencesSystemError>
    private let currentAccessibilityPermissionState: () -> AccessibilityPermissionPresentation
    private let openAccessibilitySettings: () -> Void

    public private(set) var currentPreferences = RustPreferencesDocument()

    public init(
        loadPreferencesOperation: @escaping () async -> Result<RustPreferencesResult, RustCoreError>,
        savePreferencesOperation: ((RustPreferencesDocument) async -> Result<RustPreferencesResult, RustCoreError>)? = nil,
        patchPreferencesOperation: ((RustPreferencesPatch) async -> Result<RustPreferencesPatchResult, RustCoreError>)? = nil,
        currentLaunchAtLoginState: @escaping () -> LaunchAtLoginPresentation,
        setLaunchAtLoginEnabled: @escaping (Bool) -> Result<LaunchAtLoginPresentation, PreferencesSystemError>,
        currentAccessibilityPermissionState: @escaping () -> AccessibilityPermissionPresentation,
        openAccessibilitySettings: @escaping () -> Void
    ) {
        self.loadPreferencesOperation = loadPreferencesOperation
        self.savePreferencesOperation = savePreferencesOperation
        self.patchPreferencesOperation = patchPreferencesOperation
        self.currentLaunchAtLoginState = currentLaunchAtLoginState
        self.setLaunchAtLoginEnabled = setLaunchAtLoginEnabled
        self.currentAccessibilityPermissionState = currentAccessibilityPermissionState
        self.openAccessibilitySettings = openAccessibilitySettings
    }

    public func load() async -> Result<PreferencesApplyResult, RustCoreError> {
        await enqueue { await self.loadNow() }
    }

    private func loadNow() async -> Result<PreferencesApplyResult, RustCoreError> {
        switch await loadPreferencesOperation() {
        case .success(let result):
            let reconciliation = reconcileLaunchAtLoginPreference(
                result.preferences,
                applyRequestedChange: false
            )

            var preferences = result.preferences
            var statusText = reconciliation.statusText
            if reconciliation.preferences != result.preferences {
                if let patchPreferencesOperation {
                    let patch = RustPreferencesPatch().settingLaunchAtLogin(reconciliation.preferences.general.launchAtLogin)
                    switch await patchPreferencesOperation(patch) {
                    case .success(let saved): preferences = saved.document
                    case .failure(let error): statusText = "偏好同步失败：\(error.code)；登录项以系统状态为准"
                    }
                } else if let savePreferencesOperation {
                    switch await savePreferencesOperation(reconciliation.preferences) {
                    case .success(let saved): preferences = saved.preferences
                    case .failure(let error): statusText = "偏好同步失败：\(error.code)；登录项以系统状态为准"
                    }
                }
            }

            currentPreferences = preferences
            return .success(PreferencesApplyResult(
                preferences: preferences,
                launchAtLoginState: reconciliation.launchAtLoginState,
                accessibilityPermissionState: currentAccessibilityPermissionState(),
                statusText: statusText,
                shouldRefreshList: false
            ))

        case .failure(let error):
            return .failure(error)
        }
    }

    public func persist(
        _ preferences: RustPreferencesDocument
    ) async -> Result<PreferencesApplyResult, RustCoreError> {
        await enqueue { await self.persistNow(preferences) }
    }

    public func persist(patch: RustPreferencesPatch) async -> Result<PreferencesApplyResult, RustCoreError> {
        await enqueue { await self.persistPatchNow(patch) }
    }

    private func persistPatchNow(_ patch: RustPreferencesPatch) async -> Result<PreferencesApplyResult, RustCoreError> {
        guard let patchPreferencesOperation else {
            return .failure(RustCoreError(code: "invalid_input", messageKey: "clipboard.error.invalid_input",
                                          recoverable: false, message: "Preferences patch operation is unavailable"))
        }
        let requested: RustPreferencesDocument
        do { requested = try patch.applying(to: currentPreferences) }
        catch {
            return .failure(RustCoreError(code: "invalid_input", messageKey: "clipboard.error.invalid_input",
                                          recoverable: false, message: "Invalid preferences patch"))
        }
        var effectivePatch = patch
        var launchState = currentLaunchAtLoginState()
        var statusText: String?
        if patch.changesLaunchAtLogin {
            let reconciliation = reconcileLaunchAtLoginPreference(requested, applyRequestedChange: true)
            launchState = reconciliation.launchAtLoginState
            statusText = reconciliation.statusText
            effectivePatch = patch.settingLaunchAtLogin(reconciliation.preferences.general.launchAtLogin)
        }
        switch await patchPreferencesOperation(effectivePatch) {
        case .success(let saved):
            currentPreferences = saved.document
            return .success(PreferencesApplyResult(
                preferences: saved.document, launchAtLoginState: launchState,
                accessibilityPermissionState: currentAccessibilityPermissionState(),
                statusText: saved.warningText ?? statusText ?? AppLocalization.text("preferences.saved", defaultValue: "偏好：已保存"),
                shouldRefreshList: saved.changedSections.contains("history") || saved.maintenance.mayHaveChanged
            ))
        case .failure(let error): return .failure(error)
        }
    }

    private func enqueue(
        _ operation: @escaping @MainActor () async -> Result<PreferencesApplyResult, RustCoreError>
    ) async -> Result<PreferencesApplyResult, RustCoreError> {
        operationGeneration += 1
        let generation = operationGeneration
        let previous = pendingOperation
        let task = Task { @MainActor in
            _ = await previous?.value
            return await operation()
        }
        pendingOperation = task
        let result = await task.value
        if generation == operationGeneration { pendingOperation = nil }
        return result
    }

    private func persistNow(
        _ preferences: RustPreferencesDocument
    ) async -> Result<PreferencesApplyResult, RustCoreError> {
        guard let savePreferencesOperation else {
            return await persistPatchNow(RustPreferencesPatch(previous: currentPreferences, next: preferences))
        }
        let launchAtLoginChanged =
            preferences.general.launchAtLogin != currentPreferences.general.launchAtLogin
        let reconciliation = reconcileLaunchAtLoginPreference(
            preferences,
            applyRequestedChange: launchAtLoginChanged
        )

        switch await savePreferencesOperation(reconciliation.preferences) {
        case .success(let result):
            currentPreferences = result.preferences
            return .success(PreferencesApplyResult(
                preferences: result.preferences,
                launchAtLoginState: reconciliation.launchAtLoginState,
                accessibilityPermissionState: currentAccessibilityPermissionState(),
                statusText: reconciliation.statusText ?? AppLocalization.text("preferences.saved", defaultValue: "偏好：已保存"),
                shouldRefreshList: true
            ))

        case .failure(let error):
            return .failure(error)
        }
    }

    public func refreshAccessibilityPermissionState() -> AccessibilityPermissionPresentation {
        currentAccessibilityPermissionState()
    }

    public func currentSceneSnapshot() -> PreferencesSceneSnapshot {
        PreferencesSceneSnapshot(
            preferences: currentPreferences,
            launchAtLoginState: currentLaunchAtLoginState(),
            accessibilityPermissionState: currentAccessibilityPermissionState()
        )
    }

    public func openAccessibilitySettingsFromPreferences() -> PreferencesAccessibilityActionResult {
        let currentState = currentAccessibilityPermissionState()
        let statusText: String

        if currentState.isTrusted {
            statusText = AppLocalization.text("accessibility.status.trusted", defaultValue: "权限：辅助功能已允许")
        } else {
            openAccessibilitySettings()
            statusText = AppLocalization.text("accessibility.status.requestPermission", defaultValue: "权限：请在辅助功能中允许 ClipDock")
        }

        return PreferencesAccessibilityActionResult(
            accessibilityPermissionState: currentAccessibilityPermissionState(),
            statusText: statusText
        )
    }

    private func reconcileLaunchAtLoginPreference(
        _ preferences: RustPreferencesDocument,
        applyRequestedChange: Bool
    ) -> (
        preferences: RustPreferencesDocument,
        launchAtLoginState: LaunchAtLoginPresentation,
        statusText: String?
    ) {
        var resolvedPreferences = preferences
        let currentState = currentLaunchAtLoginState()

        guard applyRequestedChange else {
            resolvedPreferences.general.launchAtLogin = currentState.isOn
            if preferences.general.launchAtLogin != currentState.isOn {
                return (resolvedPreferences, currentState, AppLocalization.format("launchAtLogin.statusFormat", defaultValue: "登录项：%@", currentState.detail))
            }
            return (resolvedPreferences, currentState, nil)
        }

        guard currentState.canChange else {
            resolvedPreferences.general.launchAtLogin = currentState.isOn
            return (resolvedPreferences, currentState, AppLocalization.format("launchAtLogin.statusFormat", defaultValue: "登录项：%@", currentState.detail))
        }

        switch setLaunchAtLoginEnabled(preferences.general.launchAtLogin) {
        case .success(let state):
            resolvedPreferences.general.launchAtLogin = state.isOn
            return (resolvedPreferences, state, AppLocalization.format("launchAtLogin.statusFormat", defaultValue: "登录项：%@", state.detail))

        case .failure(let error):
            let fallbackState = currentLaunchAtLoginState()
            resolvedPreferences.general.launchAtLogin = fallbackState.isOn
            return (resolvedPreferences, fallbackState, AppLocalization.format("launchAtLogin.statusFormat", defaultValue: "登录项：%@", error.localizedDescription))
        }
    }

}
