import AppKit
import ClipboardPanelApp
import Testing
@testable import ClipDock

struct PreferencesShellTests {
    @Test
    @MainActor
    func preferencesWindowUsesSystemSplitShellAtMinimumSize() throws {
        let controller = PreferencesWindowController()
        defer { controller.close() }
        let window = try #require(controller.window)

        window.setFrame(NSRect(x: 0, y: 0, width: 820, height: 600), display: false)
        window.layoutIfNeeded()
        let snapshot = try #require(controller.preferencesShellSmokeSnapshot())

        #expect(window.contentViewController is NSSplitViewController)
        #expect(snapshot.windowHasToolbar)
        #expect(snapshot.windowUsesUnifiedToolbarStyle)
        #expect(snapshot.windowUsesFullSizeContentView)
        #expect(snapshot.windowTitleIsHidden)
        #expect(snapshot.windowTitlebarAppearsTransparent)
        #expect(!snapshot.toolbarShowsBaselineSeparator)
        #expect(snapshot.toolbarUsesSidebarTrackingSeparator)
        #expect(!snapshot.toolbarHasNavigationItem)
        #expect(snapshot.windowBackgroundMatchesTheme)
        #expect(snapshot.splitBackgroundMatchesTheme)
        #expect(snapshot.sidebarBackgroundMatchesTheme)
        #expect(snapshot.contentBackgroundMatchesTheme)
        #expect(snapshot.splitItemCount == 2)
        #expect(snapshot.sidebarMinimumThickness >= 220)
        #expect(snapshot.sidebarMaximumThickness <= 264)
        #expect(!snapshot.sidebarCanCollapse)
        #expect(!snapshot.sidebarCanCollapseFromWindowResize)
        #expect(snapshot.sidebarFrameWidth >= 220)
        #expect(snapshot.sidebarFrameWidth <= 264)
        #expect(snapshot.contentFrameWidth >= 520)
        #expect(snapshot.visibleSidebarSectionCount == PreferenceSection.allCases.count)
    }

    @Test
    @MainActor
    func preferencesWindowUsesUnifiedThemeInDarkMode() throws {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { app.appearance = originalAppearance }

        app.appearance = NSAppearance(named: .darkAqua)
        let controller = PreferencesWindowController()
        defer { controller.close() }
        let window = try #require(controller.window)

        window.setFrame(NSRect(x: 0, y: 0, width: 820, height: 600), display: false)
        window.layoutIfNeeded()
        let snapshot = try #require(controller.preferencesShellSmokeSnapshot())

        #expect(snapshot.windowBackgroundMatchesTheme)
        #expect(snapshot.splitBackgroundMatchesTheme)
        #expect(snapshot.sidebarBackgroundMatchesTheme)
        #expect(snapshot.contentBackgroundMatchesTheme)
        #expect(snapshot.sidebarBackgroundWhiteComponent < 0.25)
        #expect(snapshot.sidebarHostingAppearanceIsDark)
        #expect(snapshot.contentHostingAppearanceIsDark)
    }

    @Test
    @MainActor
    func preferencesWindowHonorsForcedDarkModeBeforeGlobalAppearanceChanges() throws {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { app.appearance = originalAppearance }

        app.appearance = NSAppearance(named: .aqua)
        let controller = PreferencesWindowController()
        defer { controller.close() }
        let window = try #require(controller.window)

        var preferences = RustPreferencesDocument()
        preferences.appearance.mode = "dark"
        controller.updatePreferences(preferences)

        window.setFrame(NSRect(x: 0, y: 0, width: 820, height: 600), display: false)
        window.layoutIfNeeded()
        let snapshot = try #require(controller.preferencesShellSmokeSnapshot())

        #expect(snapshot.windowBackgroundMatchesTheme)
        #expect(snapshot.splitBackgroundMatchesTheme)
        #expect(snapshot.sidebarBackgroundMatchesTheme)
        #expect(snapshot.contentBackgroundMatchesTheme)
        #expect(snapshot.sidebarBackgroundWhiteComponent < 0.25)
        #expect(snapshot.sidebarHostingAppearanceIsDark)
        #expect(snapshot.contentHostingAppearanceIsDark)
    }

    @Test
    @MainActor
    func showSectionRoutesThroughSharedPreferencesModel() throws {
        let controller = PreferencesWindowController()
        defer { controller.close() }

        controller.showSection(.rules)
        #expect(try #require(controller.preferencesShellSmokeSnapshot()).selectedSection == .rules)

        controller.showSection(.sync)
        #expect(try #require(controller.preferencesShellSmokeSnapshot()).selectedSection == .sync)

        controller.showSection(.shortcuts)
        #expect(try #require(controller.preferencesShellSmokeSnapshot()).selectedSection == .shortcuts)

        controller.showSection(.history)
        #expect(try #require(controller.preferencesShellSmokeSnapshot()).selectedSection == .general)
    }

    @Test
    @MainActor
    func syncCreateResultKeepsPairingCodeAsUserVisibleState() throws {
        let controller = PreferencesWindowController()
        defer { controller.close() }
        var preferences = RustPreferencesDocument()
        preferences.sync.enabled = true
        preferences.sync.syncID = "sync_internal"
        preferences.sync.deviceID = "dev_internal"
        preferences.sync.deviceName = "Ying MacBook Pro"

        controller.smokeApplySyncActionResultForQA(SyncSettingsActionResult(
            preferences: preferences,
            statusText: "同步：已创建，请在其他设备输入配对码",
            pairingCode: "A1B2C",
            pairingExpiresAtMs: 1_780_320_000_000
        ))

        let snapshot = controller.preferencesSyncSmokeSnapshot()
        #expect(snapshot.pairingCode == "A1B2C")
        #expect(snapshot.pairingExpiresAtMs == 1_780_320_000_000)
        #expect(snapshot.statusText == "同步：已创建，请在其他设备输入配对码")
        #expect(!snapshot.statusIsError)
        #expect(!snapshot.isActionInFlight)
    }

    @Test
    @MainActor
    func syncJoinResultClearsStalePairingCode() throws {
        let controller = PreferencesWindowController()
        defer { controller.close() }

        controller.smokeApplySyncActionResultForQA(SyncSettingsActionResult(
            preferences: RustPreferencesDocument(),
            statusText: "created",
            pairingCode: "A1B2C",
            pairingExpiresAtMs: 1_780_320_000_000
        ))
        controller.smokeApplySyncActionResultForQA(SyncSettingsActionResult(
            preferences: RustPreferencesDocument(),
            statusText: "joined",
            clearsPairingCode: true
        ))

        let snapshot = controller.preferencesSyncSmokeSnapshot()
        #expect(snapshot.pairingCode == nil)
        #expect(snapshot.pairingExpiresAtMs == nil)
        #expect(snapshot.statusText == "joined")
        #expect(!snapshot.statusIsError)
        #expect(!snapshot.isActionInFlight)
    }

    @Test
    @MainActor
    func syncJoinErrorKeepsUserVisibleErrorState() throws {
        let controller = PreferencesWindowController()
        defer { controller.close() }

        controller.smokeApplySyncActionResultForQA(SyncSettingsActionResult(
            preferences: nil,
            statusText: "同步：服务端返回 404 invalid_invite",
            isError: true
        ))

        let snapshot = controller.preferencesSyncSmokeSnapshot()
        #expect(snapshot.pairingCode == nil)
        #expect(snapshot.pairingExpiresAtMs == nil)
        #expect(snapshot.statusText == "同步：服务端返回 404 invalid_invite")
        #expect(snapshot.statusIsError)
        #expect(!snapshot.isActionInFlight)
    }

    @Test
    @MainActor
    func enablingDirectPasteRequestsAccessibilityPermissionWhenMissing() {
        let controller = PreferencesWindowController()
        defer { controller.close() }
        var requestCount = 0
        controller.onAccessibilityPermissionRequested = {
            requestCount += 1
        }
        controller.updateAccessibilityPermissionState(AccessibilityPermissionPresentation(
            isTrusted: false,
            detail: "未允许",
            actionTitle: "打开系统设置",
            canOpenSettings: true
        ))

        #expect(controller.smokeEnableDirectPasteToTargetForPermissionQA())
        #expect(requestCount == 1)
    }

    @Test
    @MainActor
    func enablingDirectPasteSkipsPermissionRequestWhenAlreadyTrusted() {
        let controller = PreferencesWindowController()
        defer { controller.close() }
        var requestCount = 0
        controller.onAccessibilityPermissionRequested = {
            requestCount += 1
        }
        controller.updateAccessibilityPermissionState(AccessibilityPermissionPresentation(
            isTrusted: true,
            detail: "已允许",
            actionTitle: "重新检查",
            canOpenSettings: true
        ))

        #expect(controller.smokeEnableDirectPasteToTargetForPermissionQA())
        #expect(requestCount == 0)
    }

    @Test
    @MainActor
    func copyCompletionHUDControllerReusesOnePanelForRepeatedShows() throws {
        let controller = CopyCompletionHUDController()

        controller.show(eventID: "self-copy-1")
        let firstWindow = try #require(controller.debugWindowIdentity)
        #expect(controller.lastEventID == "self-copy-1")

        controller.show(eventID: "self-copy-2")
        #expect(controller.debugWindowIdentity == firstWindow)
        #expect(controller.lastEventID == "self-copy-2")

        controller.hideImmediatelyForTesting()
    }

    @Test
    @MainActor
    func copyCompletionHUDControllerRefreshesContentColorsForDarkAppearance() throws {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { app.appearance = originalAppearance }

        let controller = CopyCompletionHUDController()
        defer { controller.hideImmediatelyForTesting() }

        app.appearance = NSAppearance(named: .aqua)
        controller.show(eventID: "self-copy-light")
        let lightColors = try #require(controller.debugContentColors)
        let lightLabelColor = try #require(lightColors.labelTextColor?.usingColorSpace(.sRGB))

        app.appearance = NSAppearance(named: .darkAqua)
        controller.show(eventID: "self-copy-dark")
        let darkColors = try #require(controller.debugContentColors)
        let darkIconColor = try #require(darkColors.iconTintColor?.usingColorSpace(.sRGB))
        let darkLabelColor = try #require(darkColors.labelTextColor?.usingColorSpace(.sRGB))

        #expect(lightLabelColor.redComponent < 0.4)
        #expect(darkIconColor.redComponent > 0.8)
        #expect(darkLabelColor.redComponent > 0.8)
        #expect(darkLabelColor.redComponent - lightLabelColor.redComponent > 0.5)
        #expect(abs(darkIconColor.alphaComponent - lightLabelColor.alphaComponent) < 0.001)
        #expect(abs(darkLabelColor.alphaComponent - lightLabelColor.alphaComponent) < 0.001)
    }

    @Test
    func ignoredApplicationResolverUsesBundleIdentifierFromSelectedApp() throws {
        let appURL = try makeTemporaryApplicationBundle(
            bundleIdentifier: "com.example.SecretApp",
            displayName: "Secret App"
        )

        #expect(IgnoredApplicationRuleResolver.ruleIdentifier(forApplicationAt: appURL) == "com.example.SecretApp")
    }

    @Test
    func ignoredApplicationResolverFallsBackToDisplayNameWhenBundleIdentifierIsMissing() throws {
        let appURL = try makeTemporaryApplicationBundle(
            bundleIdentifier: nil,
            displayName: "Local Secret"
        )

        #expect(IgnoredApplicationRuleResolver.ruleIdentifier(forApplicationAt: appURL) == "Local Secret")
    }

    private func makeTemporaryApplicationBundle(bundleIdentifier: String?, displayName: String) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = rootURL.appendingPathComponent("\(displayName).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var info: [String: Any] = [
            "CFBundleName": displayName,
            "CFBundlePackageType": "APPL"
        ]
        if let bundleIdentifier {
            info["CFBundleIdentifier"] = bundleIdentifier
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return appURL
    }
}
