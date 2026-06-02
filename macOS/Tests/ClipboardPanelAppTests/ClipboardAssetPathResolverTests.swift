import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardAssetPathResolverTests {
    @Test
    func resolvesRelativeAbsoluteAndTildePaths() {
        let appSupportDirectory = URL(fileURLWithPath: "/tmp/clipboard-workbench", isDirectory: true)

        #expect(
            ClipboardAssetPathResolver.resolvedURL(
                for: "assets/example.png",
                appSupportDirectory: appSupportDirectory
            ).path == "/tmp/clipboard-workbench/assets/example.png"
        )
        #expect(
            ClipboardAssetPathResolver.resolvedURL(
                for: "/tmp/example.png",
                appSupportDirectory: appSupportDirectory
            ).path == "/tmp/example.png"
        )
        #expect(
            ClipboardAssetPathResolver.resolvedURL(
                for: "~/Library/Application Support/example.png",
                appSupportDirectory: appSupportDirectory
            ).path == NSString(string: "~/Library/Application Support/example.png").expandingTildeInPath
        )
    }

    @Test
    func findsFirstExistingURLFromNormalizedCandidates() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assetsDirectory = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let existingURL = assetsDirectory.appendingPathComponent("sample.png")
        try Data("payload".utf8).write(to: existingURL)

        let resolvedURL = ClipboardAssetPathResolver.firstExistingURL(
            for: [nil, "  ", "assets/sample.png", "assets/missing.png"],
            appSupportDirectory: root
        )

        #expect(resolvedURL == existingURL)
    }
}
