import AppKit
import ApplicationServices
import ClipboardPanelApp

@MainActor
protocol SourceApplicationTracking: AnyObject {
    func start()
    func stop()
    func currentSource() -> CapturedSourceApplication?
}

@MainActor
protocol SourceWindowTitleProviding {
    func title(for application: NSRunningApplication) -> String?
    func title(forProcessIdentifier processIdentifier: pid_t) -> String?
}

@MainActor
struct CapturedSourceApplication {
    let processIdentifier: pid_t
    let bundleId: String?
    let name: String
    let bundlePath: String?
    let windowTitle: String?
    let icon: NSImage?

    func updatingWindowTitle(_ windowTitle: String?) -> CapturedSourceApplication {
        CapturedSourceApplication(
            processIdentifier: processIdentifier,
            bundleId: bundleId,
            name: name,
            bundlePath: bundlePath,
            windowTitle: windowTitle,
            icon: icon
        )
    }

    static func capture(
        from application: NSRunningApplication,
        windowTitleProvider: SourceWindowTitleProviding
    ) -> CapturedSourceApplication {
        CapturedSourceApplication(
            processIdentifier: application.processIdentifier,
            bundleId: application.bundleIdentifier,
            name: application.localizedName
                ?? application.bundleURL?.deletingPathExtension().lastPathComponent
                ?? "未知来源",
            bundlePath: application.bundleURL?.path,
            windowTitle: windowTitleProvider.title(for: application),
            icon: application.icon
        )
    }
}

final class SourceWindowTitleProvider: SourceWindowTitleProviding {
    func title(for application: NSRunningApplication) -> String? {
        title(forProcessIdentifier: application.processIdentifier)
    }

    func title(forProcessIdentifier processIdentifier: pid_t) -> String? {
        accessibilityFocusedWindowTitle(forProcessIdentifier: processIdentifier)
            ?? visibleWindowTitle(forProcessIdentifier: processIdentifier)
    }

    private func accessibilityFocusedWindowTitle(forProcessIdentifier processIdentifier: pid_t) -> String? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        guard focusedWindowResult == .success,
              let focusedWindowValue,
              CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let windowElement = focusedWindowValue as! AXUIElement
        return stringAttribute(kAXTitleAttribute as CFString, from: windowElement)
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return normalizedTitle(value as? String)
    }

    private func visibleWindowTitle(forProcessIdentifier processIdentifier: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowInfoList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == processIdentifier,
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? NSNumber,
                  windowLayer.intValue == 0
            else {
                continue
            }

            if let title = normalizedTitle(windowInfo[kCGWindowName as String] as? String) {
                return title
            }
        }

        return nil
    }

    private func normalizedTitle(_ value: String?) -> String? {
        let title = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            ?? ""
        return title.isEmpty ? nil : title
    }
}

@MainActor
final class SourceApplicationTracker: SourceApplicationTracking {
    private var latestExternalApplication: CapturedSourceApplication?
    private var observer: NSObjectProtocol?
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private let mainBundleIdentifier: String?
    private let windowTitleProvider: SourceWindowTitleProviding

    init(
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter? = nil,
        mainBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        windowTitleProvider: SourceWindowTitleProviding = SourceWindowTitleProvider()
    ) {
        self.workspace = workspace
        self.notificationCenter = notificationCenter ?? workspace.notificationCenter
        self.mainBundleIdentifier = mainBundleIdentifier
        self.windowTitleProvider = windowTitleProvider
    }

    func start() {
        updateLatestApplication(workspace.frontmostApplication)
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                self?.updateLatestApplication(application)
            }
        }
    }

    func stop() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    func currentSource() -> CapturedSourceApplication? {
        if let application = workspace.frontmostApplication,
           shouldTrack(application) {
            updateLatestApplication(application)
        } else if let source = latestExternalApplication {
            let windowTitle = windowTitleProvider.title(forProcessIdentifier: source.processIdentifier)
                ?? source.windowTitle
            latestExternalApplication = source.updatingWindowTitle(windowTitle)
        }

        return latestExternalApplication
    }

    private func updateLatestApplication(_ application: NSRunningApplication?) {
        guard let application else { return }
        guard shouldTrack(application) else {
            return
        }

        latestExternalApplication = CapturedSourceApplication.capture(
            from: application,
            windowTitleProvider: windowTitleProvider
        )
    }

    private func shouldTrack(_ application: NSRunningApplication) -> Bool {
        application.bundleIdentifier != mainBundleIdentifier
    }
}

extension CapturedSourceApplication {
    var clipboardCaptureSource: ClipboardCaptureSource {
        ClipboardCaptureSource(
            bundleId: bundleId,
            appName: name,
            bundlePath: bundlePath,
            windowTitle: windowTitle
        )
    }
}
