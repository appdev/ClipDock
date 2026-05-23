import ClipboardPanelApp
import Foundation
import Testing
@testable import ClipDock

struct CopySoundFeedbackTests {
    @Test
    @MainActor
    func copySoundResourceIsBundledWithClipDockTarget() throws {
        let url = try #require(CopySoundFeedbackPlayer.copySoundResourceURL())
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])

        #expect(url.lastPathComponent == "Copy.aiff")
        #expect((resourceValues.fileSize ?? 0) > 0)
    }

    @Test
    func externalCopySoundPolicyUsesPreferenceAndSkipsCurrentApplication() {
        let enabledPreferences = RustPreferencesDocument()
        var disabledPreferences = RustPreferencesDocument()
        disabledPreferences.general.externalCopySoundEnabled = false

        #expect(ExternalCopySoundPolicy.shouldPlay(
            preferences: enabledPreferences,
            frontmostApplication: nil,
            currentProcessIdentifier: 11,
            mainBundleIdentifier: "app.clipdock"
        ))
        #expect(!ExternalCopySoundPolicy.shouldPlay(
            preferences: disabledPreferences,
            frontmostApplication: nil,
            isCurrentApplicationActive: false,
            currentProcessIdentifier: 11,
            mainBundleIdentifier: "app.clipdock"
        ))
        #expect(!ExternalCopySoundPolicy.shouldPlay(
            preferences: enabledPreferences,
            frontmostApplication: nil,
            isCurrentApplicationActive: true,
            currentProcessIdentifier: 11,
            mainBundleIdentifier: "app.clipdock"
        ))
        #expect(!ExternalCopySoundPolicy.shouldPlay(
            preferences: enabledPreferences,
            frontmostApplication: ExternalCopySoundApplicationIdentity(
                processIdentifier: 11,
                bundleIdentifier: "other.app"
            ),
            currentProcessIdentifier: 11,
            mainBundleIdentifier: "app.clipdock"
        ))
        #expect(!ExternalCopySoundPolicy.shouldPlay(
            preferences: enabledPreferences,
            frontmostApplication: ExternalCopySoundApplicationIdentity(
                processIdentifier: 22,
                bundleIdentifier: "app.clipdock"
            ),
            currentProcessIdentifier: 11,
            mainBundleIdentifier: "app.clipdock"
        ))
        #expect(ExternalCopySoundPolicy.shouldPlay(
            preferences: enabledPreferences,
            frontmostApplication: ExternalCopySoundApplicationIdentity(
                processIdentifier: 22,
                bundleIdentifier: "other.app"
            ),
            currentProcessIdentifier: 11,
            mainBundleIdentifier: "app.clipdock"
        ))
    }
}
