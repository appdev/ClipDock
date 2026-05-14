import Foundation
import Testing
@testable import ClipShelf

struct LaunchAtLoginFallbackAgentTests {
    @Test
    func fallbackAgentWritesAndRemovesUserLaunchAgentPlist() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let launchAgentsDirectory = rootURL.appendingPathComponent("LaunchAgents", isDirectory: true)
        let executableURL = rootURL
            .appendingPathComponent("ClipShelf.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("ClipShelf")
        let agent = LaunchAtLoginFallbackAgent(
            bundleIdentifier: "dev.codex.clipshelf",
            executableURL: executableURL,
            launchAgentsDirectory: launchAgentsDirectory
        )

        #expect(!agent.isEnabled)
        try agent.register()
        #expect(agent.isEnabled)

        let plistData = try Data(contentsOf: agent.plistURL)
        let plist = try #require(PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any])
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == ["dev.codex.clipshelf"])
        #expect(plist["Label"] as? String == "dev.codex.clipshelf.launch-at-login")
        #expect(plist["LimitLoadToSessionType"] as? String == "Aqua")
        #expect(plist["ProgramArguments"] as? [String] == [
            executableURL.path,
            ClipShelfLaunchArgument.launchedAtLogin
        ])
        #expect(plist["RunAtLoad"] as? Bool == true)

        try agent.unregister()
        #expect(!agent.isEnabled)
    }
}
