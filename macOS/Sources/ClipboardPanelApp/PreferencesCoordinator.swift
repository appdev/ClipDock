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

public struct PreferencesSyncResult: Equatable, Sendable {
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
    private let loadPreferencesOperation: () -> Result<RustPreferencesResult, RustCoreError>
    private let savePreferencesOperation: (RustPreferencesDocument) -> Result<RustPreferencesResult, RustCoreError>
    private let currentLaunchAtLoginState: () -> LaunchAtLoginPresentation
    private let setLaunchAtLoginEnabled: (Bool) -> Result<LaunchAtLoginPresentation, PreferencesSystemError>
    private let currentAccessibilityPermissionState: () -> AccessibilityPermissionPresentation
    private let openAccessibilitySettings: () -> Void
    private let currentDeviceName: () -> String

    public private(set) var currentPreferences = RustPreferencesDocument()

    public init(
        loadPreferencesOperation: @escaping () -> Result<RustPreferencesResult, RustCoreError>,
        savePreferencesOperation: @escaping (RustPreferencesDocument) -> Result<RustPreferencesResult, RustCoreError>,
        currentLaunchAtLoginState: @escaping () -> LaunchAtLoginPresentation,
        setLaunchAtLoginEnabled: @escaping (Bool) -> Result<LaunchAtLoginPresentation, PreferencesSystemError>,
        currentAccessibilityPermissionState: @escaping () -> AccessibilityPermissionPresentation,
        openAccessibilitySettings: @escaping () -> Void,
        currentDeviceName: @escaping () -> String = { RustSyncPreferences.defaultDeviceName() }
    ) {
        self.loadPreferencesOperation = loadPreferencesOperation
        self.savePreferencesOperation = savePreferencesOperation
        self.currentLaunchAtLoginState = currentLaunchAtLoginState
        self.setLaunchAtLoginEnabled = setLaunchAtLoginEnabled
        self.currentAccessibilityPermissionState = currentAccessibilityPermissionState
        self.openAccessibilitySettings = openAccessibilitySettings
        self.currentDeviceName = currentDeviceName
    }

    public func load() -> Result<PreferencesSyncResult, RustCoreError> {
        switch loadPreferencesOperation() {
        case .success(let result):
            let deviceNameReconciliation = reconcileDefaultSyncDeviceName(result.preferences)
            let reconciliation = reconcileLaunchAtLoginPreference(
                deviceNameReconciliation.preferences,
                applyRequestedChange: false
            )

            if reconciliation.preferences != result.preferences || deviceNameReconciliation.didChange {
                _ = savePreferencesOperation(reconciliation.preferences)
            }

            currentPreferences = reconciliation.preferences
            return .success(PreferencesSyncResult(
                preferences: reconciliation.preferences,
                launchAtLoginState: reconciliation.launchAtLoginState,
                accessibilityPermissionState: currentAccessibilityPermissionState(),
                statusText: reconciliation.statusText,
                shouldRefreshList: false
            ))

        case .failure(let error):
            return .failure(error)
        }
    }

    public func persist(
        _ preferences: RustPreferencesDocument
    ) -> Result<PreferencesSyncResult, RustCoreError> {
        let launchAtLoginChanged =
            preferences.general.launchAtLogin != currentPreferences.general.launchAtLogin
        let reconciliation = reconcileLaunchAtLoginPreference(
            preferences,
            applyRequestedChange: launchAtLoginChanged
        )

        switch savePreferencesOperation(reconciliation.preferences) {
        case .success(let result):
            currentPreferences = result.preferences
            return .success(PreferencesSyncResult(
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

    private func reconcileDefaultSyncDeviceName(
        _ preferences: RustPreferencesDocument
    ) -> (preferences: RustPreferencesDocument, didChange: Bool) {
        var resolvedPreferences = preferences
        guard preferences.sync.syncID == nil,
              preferences.sync.deviceID == nil else {
            return (resolvedPreferences, false)
        }

        let currentName = currentDeviceName().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentName.isEmpty else {
            return (resolvedPreferences, false)
        }

        let storedName = preferences.sync.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard storedName.isEmpty || storedName == "Mac" else {
            return (resolvedPreferences, false)
        }
        guard storedName != currentName else {
            return (resolvedPreferences, false)
        }

        resolvedPreferences.sync.deviceName = currentName
        return (resolvedPreferences, true)
    }
}
