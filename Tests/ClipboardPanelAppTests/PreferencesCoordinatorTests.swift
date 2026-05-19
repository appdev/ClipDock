import Testing
@testable import ClipboardPanelApp

struct PreferencesCoordinatorTests {
    @Test
    func sceneSectionsExposeSettingsNavigationOrder() {
        #expect(PreferencesSceneSection.allCases == [
            .general,
            .rules,
            .shortcuts,
            .about
        ])
    }

    @Test
    func sceneControllerRoutesLegacyHistorySectionToGeneral() {
        let controller = PreferencesSceneController()

        let update = controller.selectSection(.history)

        #expect(update.state.selectedSection == .general)
        #expect(!update.shouldRenderSection)
        #expect(!update.shouldUpdateNavigationSelection)
    }

    @Test
    func sceneControllerSelectSectionRequestsNavigationAndRender() {
        let controller = PreferencesSceneController()

        let update = controller.selectSection(.rules)

        #expect(update.state.selectedSection == .rules)
        #expect(update.shouldRenderSection)
        #expect(update.shouldUpdateNavigationSelection)
        #expect(!update.shouldScheduleDeferredRender)
    }

    @Test
    func sceneControllerDefersGeneralSectionRenderDuringPreferencePersistence() {
        let controller = PreferencesSceneController(state: PreferencesSceneState(
            selectedSection: .general
        ))
        controller.beginPreferencePersistence()

        let deferredUpdate = controller.updateLaunchAtLoginState(LaunchAtLoginPresentation(
            isOn: true,
            canChange: true,
            detail: "已加入登录项"
        ))

        #expect(!deferredUpdate.shouldRenderSection)
        #expect(deferredUpdate.shouldScheduleDeferredRender)
        #expect(deferredUpdate.state.hasPendingDeferredRender)

        let completedUpdate = controller.completePreferencePersistence(
            persistedPreferences: RustPreferencesDocument(
                general: RustGeneralPreferences(launchAtLogin: true)
            ),
            fallbackPreferences: RustPreferencesDocument()
        )
        #expect(!completedUpdate.shouldRenderSection)

        let replayedUpdate = controller.consumeDeferredRenderIfNeeded()
        #expect(replayedUpdate.shouldRenderSection)
        #expect(!replayedUpdate.shouldScheduleDeferredRender)
        #expect(!replayedUpdate.state.hasPendingDeferredRender)
    }

    @Test
    func sceneControllerIgnoresAccessibilityRenderOutsideRulesSection() {
        let controller = PreferencesSceneController(state: PreferencesSceneState(
            selectedSection: .general
        ))

        let update = controller.updateAccessibilityPermissionState(
            AccessibilityPermissionPresentation(
                isTrusted: true,
                detail: "已允许，可读取窗口标题并直接粘贴到目标",
                actionTitle: "重新检查",
                canOpenSettings: true
            )
        )

        #expect(!update.shouldRenderSection)
        #expect(!update.shouldScheduleDeferredRender)
        #expect(update.state.accessibilityPermissionState.isTrusted)
    }

    @Test
    @MainActor
    func loadNormalizesLaunchAtLoginAndPersistsReconciledPreferences() throws {
        var savedPreferences: [RustPreferencesDocument] = []
        let coordinator = PreferencesCoordinator(
            loadPreferencesOperation: {
                .success(RustPreferencesResult(
                    schemaVersion: 1,
                    preferences: RustPreferencesDocument(
                        general: RustGeneralPreferences(launchAtLogin: true)
                    )
                ))
            },
            savePreferencesOperation: { preferences in
                savedPreferences.append(preferences)
                return .success(RustPreferencesResult(
                    schemaVersion: 1,
                    preferences: preferences
                ))
            },
            currentLaunchAtLoginState: {
                LaunchAtLoginPresentation(
                    isOn: false,
                    canChange: true,
                    detail: "登录后自动启动"
                )
            },
            setLaunchAtLoginEnabled: { _ in
                .failure(PreferencesSystemError(message: "unused"))
            },
            currentAccessibilityPermissionState: {
                AccessibilityPermissionPresentation(
                    isTrusted: false,
                    detail: "未允许，直接粘贴需在系统辅助功能中允许 ClipDock",
                    actionTitle: "打开系统设置",
                    canOpenSettings: true
                )
            },
            openAccessibilitySettings: {}
        )

        let result = try coordinator.load().get()

        #expect(result.preferences.general.launchAtLogin == false)
        #expect(result.statusText == "登录项：登录后自动启动")
        #expect(savedPreferences.count == 1)
        #expect(savedPreferences[0].general.launchAtLogin == false)
        #expect(!result.shouldRefreshList)
    }

    @Test
    @MainActor
    func persistAppliesRequestedLaunchAtLoginChangeBeforeSaving() throws {
        var savedPreference: RustPreferencesDocument?
        let coordinator = PreferencesCoordinator(
            loadPreferencesOperation: {
                .success(RustPreferencesResult(
                    schemaVersion: 1,
                    preferences: RustPreferencesDocument()
                ))
            },
            savePreferencesOperation: { preferences in
                savedPreference = preferences
                return .success(RustPreferencesResult(
                    schemaVersion: 1,
                    preferences: preferences
                ))
            },
            currentLaunchAtLoginState: {
                LaunchAtLoginPresentation(
                    isOn: false,
                    canChange: true,
                    detail: "登录后自动启动"
                )
            },
            setLaunchAtLoginEnabled: { enabled in
                #expect(enabled)
                return .success(LaunchAtLoginPresentation(
                    isOn: true,
                    canChange: true,
                    detail: "已加入登录项"
                ))
            },
            currentAccessibilityPermissionState: {
                AccessibilityPermissionPresentation(
                    isTrusted: true,
                    detail: "已允许，可读取窗口标题并直接粘贴到目标",
                    actionTitle: "重新检查",
                    canOpenSettings: true
                )
            },
            openAccessibilitySettings: {}
        )

        let result = try coordinator.persist(RustPreferencesDocument(
            general: RustGeneralPreferences(launchAtLogin: true)
        )).get()

        #expect(savedPreference?.general.launchAtLogin == true)
        #expect(result.preferences.general.launchAtLogin == true)
        #expect(result.statusText == "登录项：已加入登录项")
        #expect(result.launchAtLoginState.isOn)
        #expect(result.shouldRefreshList)
    }

    @Test
    @MainActor
    func persistFallsBackToCurrentStateWhenLaunchAtLoginChangeFails() throws {
        var savedPreference: RustPreferencesDocument?
        let coordinator = PreferencesCoordinator(
            loadPreferencesOperation: {
                .success(RustPreferencesResult(
                    schemaVersion: 1,
                    preferences: RustPreferencesDocument()
                ))
            },
            savePreferencesOperation: { preferences in
                savedPreference = preferences
                return .success(RustPreferencesResult(
                    schemaVersion: 1,
                    preferences: preferences
                ))
            },
            currentLaunchAtLoginState: {
                LaunchAtLoginPresentation(
                    isOn: false,
                    canChange: true,
                    detail: "登录后自动启动"
                )
            },
            setLaunchAtLoginEnabled: { _ in
                .failure(PreferencesSystemError(message: "系统拒绝修改"))
            },
            currentAccessibilityPermissionState: {
                AccessibilityPermissionPresentation(
                    isTrusted: true,
                    detail: "已允许，可读取窗口标题并直接粘贴到目标",
                    actionTitle: "重新检查",
                    canOpenSettings: true
                )
            },
            openAccessibilitySettings: {}
        )

        let result = try coordinator.persist(RustPreferencesDocument(
            general: RustGeneralPreferences(launchAtLogin: true)
        )).get()

        #expect(savedPreference?.general.launchAtLogin == false)
        #expect(result.preferences.general.launchAtLogin == false)
        #expect(result.statusText == "登录项：系统拒绝修改")
        #expect(!result.launchAtLoginState.isOn)
    }
}
