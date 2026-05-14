import Foundation

public enum PreferencesSceneSection: String, CaseIterable, Equatable, Sendable {
    case general
    case appearance
    case history
    case shortcuts
    case rules
    case about

    public static var allCases: [PreferencesSceneSection] {
        [
            .general,
            .shortcuts,
            .rules,
            .about
        ]
    }
}

public struct PreferencesSceneState: Equatable, Sendable {
    public var selectedSection: PreferencesSceneSection
    public var preferences: RustPreferencesDocument
    public var launchAtLoginState: LaunchAtLoginPresentation
    public var accessibilityPermissionState: AccessibilityPermissionPresentation
    public var isPersistingPreferenceChange: Bool
    public var hasPendingDeferredRender: Bool

    public init(
        selectedSection: PreferencesSceneSection = .general,
        preferences: RustPreferencesDocument = RustPreferencesDocument(),
        launchAtLoginState: LaunchAtLoginPresentation = LaunchAtLoginPresentation(
            isOn: false,
            canChange: false,
            detail: "正在读取状态"
        ),
        accessibilityPermissionState: AccessibilityPermissionPresentation = AccessibilityPermissionPresentation(
            isTrusted: false,
            detail: "正在读取状态",
            actionTitle: "重新检查",
            canOpenSettings: true
        ),
        isPersistingPreferenceChange: Bool = false,
        hasPendingDeferredRender: Bool = false
    ) {
        self.selectedSection = selectedSection
        self.preferences = preferences
        self.launchAtLoginState = launchAtLoginState
        self.accessibilityPermissionState = accessibilityPermissionState
        self.isPersistingPreferenceChange = isPersistingPreferenceChange
        self.hasPendingDeferredRender = hasPendingDeferredRender
    }
}

public struct PreferencesSceneUpdate: Equatable, Sendable {
    public let state: PreferencesSceneState
    public let shouldRenderSection: Bool
    public let shouldUpdateNavigationSelection: Bool
    public let shouldScheduleDeferredRender: Bool

    public init(
        state: PreferencesSceneState,
        shouldRenderSection: Bool,
        shouldUpdateNavigationSelection: Bool,
        shouldScheduleDeferredRender: Bool
    ) {
        self.state = state
        self.shouldRenderSection = shouldRenderSection
        self.shouldUpdateNavigationSelection = shouldUpdateNavigationSelection
        self.shouldScheduleDeferredRender = shouldScheduleDeferredRender
    }
}

public final class PreferencesSceneController {
    public private(set) var state: PreferencesSceneState

    public init(state: PreferencesSceneState = PreferencesSceneState()) {
        self.state = state
    }

    public func selectSection(_ section: PreferencesSceneSection) -> PreferencesSceneUpdate {
        let resolvedSection = normalizedSection(section)
        guard state.selectedSection != resolvedSection else {
            return noOpUpdate()
        }

        state.selectedSection = resolvedSection
        return PreferencesSceneUpdate(
            state: state,
            shouldRenderSection: true,
            shouldUpdateNavigationSelection: true,
            shouldScheduleDeferredRender: false
        )
    }

    public func updatePreferences(_ preferences: RustPreferencesDocument) -> PreferencesSceneUpdate {
        state.preferences = preferences
        return PreferencesSceneUpdate(
            state: state,
            shouldRenderSection: true,
            shouldUpdateNavigationSelection: false,
            shouldScheduleDeferredRender: false
        )
    }

    public func updateLaunchAtLoginState(
        _ launchAtLoginState: LaunchAtLoginPresentation
    ) -> PreferencesSceneUpdate {
        state.launchAtLoginState = launchAtLoginState
        guard state.selectedSection == .general else {
            return noOpUpdate()
        }
        return updateForSectionRenderRespectingPersistence()
    }

    public func updateAccessibilityPermissionState(
        _ accessibilityPermissionState: AccessibilityPermissionPresentation
    ) -> PreferencesSceneUpdate {
        state.accessibilityPermissionState = accessibilityPermissionState
        guard state.selectedSection == .rules else {
            return noOpUpdate()
        }
        return updateForSectionRenderRespectingPersistence()
    }

    public func makeUpdatedPreferences(
        _ update: (inout RustPreferencesDocument) -> Void
    ) -> RustPreferencesDocument {
        var nextPreferences = state.preferences
        update(&nextPreferences)
        return nextPreferences
    }

    public func beginPreferencePersistence() {
        state.isPersistingPreferenceChange = true
    }

    public func completePreferencePersistence(
        persistedPreferences: RustPreferencesDocument?,
        fallbackPreferences: RustPreferencesDocument
    ) -> PreferencesSceneUpdate {
        state.preferences = persistedPreferences ?? fallbackPreferences
        state.isPersistingPreferenceChange = false
        return noOpUpdate()
    }

    public func consumeDeferredRenderIfNeeded() -> PreferencesSceneUpdate {
        guard state.hasPendingDeferredRender else {
            return noOpUpdate()
        }

        guard !state.isPersistingPreferenceChange else {
            return noOpUpdate()
        }

        state.hasPendingDeferredRender = false
        return PreferencesSceneUpdate(
            state: state,
            shouldRenderSection: true,
            shouldUpdateNavigationSelection: false,
            shouldScheduleDeferredRender: false
        )
    }

    private func updateForSectionRenderRespectingPersistence() -> PreferencesSceneUpdate {
        guard !state.isPersistingPreferenceChange else {
            state.hasPendingDeferredRender = true
            return PreferencesSceneUpdate(
                state: state,
                shouldRenderSection: false,
                shouldUpdateNavigationSelection: false,
                shouldScheduleDeferredRender: true
            )
        }

        return PreferencesSceneUpdate(
            state: state,
            shouldRenderSection: true,
            shouldUpdateNavigationSelection: false,
            shouldScheduleDeferredRender: false
        )
    }

    private func noOpUpdate() -> PreferencesSceneUpdate {
        PreferencesSceneUpdate(
            state: state,
            shouldRenderSection: false,
            shouldUpdateNavigationSelection: false,
            shouldScheduleDeferredRender: false
        )
    }

    private func normalizedSection(_ section: PreferencesSceneSection) -> PreferencesSceneSection {
        switch section {
        case .history:
            return .general
        default:
            return section
        }
    }
}
