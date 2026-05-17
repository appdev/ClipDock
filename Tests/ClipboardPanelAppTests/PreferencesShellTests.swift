import AppKit
import ClipboardPanelApp
import Testing
@testable import ClipShelf

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

        controller.showSection(.shortcuts)
        #expect(try #require(controller.preferencesShellSmokeSnapshot()).selectedSection == .shortcuts)

        controller.showSection(.history)
        #expect(try #require(controller.preferencesShellSmokeSnapshot()).selectedSection == .general)
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
