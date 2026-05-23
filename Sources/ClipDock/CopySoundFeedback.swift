import AppKit
import ClipboardPanelApp

@MainActor
protocol CopySoundFeedbackPlaying: AnyObject {
    func playCopySound()
}

@MainActor
final class CopySoundFeedbackPlayer: CopySoundFeedbackPlaying {
    private lazy var copySound: NSSound? = Self.makeCopySound()

    func playCopySound() {
        guard let copySound else { return }
        if copySound.isPlaying {
            copySound.stop()
        }
        copySound.currentTime = 0
        copySound.play()
    }

    static func copySoundResourceURL(bundle: Bundle = .module) -> URL? {
        bundle.url(forResource: "Copy", withExtension: "aiff")
    }

    private static func makeCopySound(bundle: Bundle = .module) -> NSSound? {
        guard let url = copySoundResourceURL(bundle: bundle) else {
            return nil
        }
        return NSSound(contentsOf: url, byReference: false)
    }
}

struct ExternalCopySoundApplicationIdentity: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}

enum ExternalCopySoundPolicy {
    static func shouldPlay(
        preferences: RustPreferencesDocument,
        frontmostApplication: ExternalCopySoundApplicationIdentity?,
        isCurrentApplicationActive: Bool = false,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        mainBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        guard preferences.general.externalCopySoundEnabled else {
            return false
        }

        guard !isCurrentApplicationActive else {
            return false
        }

        guard let frontmostApplication else {
            return true
        }

        if frontmostApplication.processIdentifier == currentProcessIdentifier {
            return false
        }

        if let mainBundleIdentifier,
           frontmostApplication.bundleIdentifier == mainBundleIdentifier {
            return false
        }

        return true
    }
}
