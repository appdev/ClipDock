import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp

enum PanelSnapshotCommand {
    private static let flag = "--render-panel-snapshot"

    static func outputURL(arguments: [String]) -> URL? {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: flagIndex)
        if arguments.indices.contains(nextIndex), !arguments[nextIndex].hasPrefix("--") {
            return URL(fileURLWithPath: arguments[nextIndex])
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("panel-runtime-snapshot.png")
    }

    @MainActor
    static func render(to outputURL: URL) throws {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 320)
        let view = FloatingPanelContentView(frame: frame)
        let previewURL = try PanelQASamples.makePanelSnapshotPreviewImageURL(outputDirectory: outputURL.deletingLastPathComponent())
        let sampleItems = PanelQASamples.makePanelSnapshotItems(imagePath: previewURL.path)
        view.updateListState(
            .success(RustCoreListResult(
                items: sampleItems,
                totalCount: Int64(sampleItems.count),
                hasMore: false
            )),
            isFiltered: false
        )
        view.updatePanelHeight(frame.height)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        try ViewSnapshotRenderer.render(view: view, to: outputURL)
    }
}

enum PreferencesSnapshotCommand {
    private static let flag = "--render-preferences-snapshot"
    private static let sectionFlag = "--preferences-section"

    static func outputURL(arguments: [String]) -> URL? {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: flagIndex)
        if arguments.indices.contains(nextIndex), !arguments[nextIndex].hasPrefix("--") {
            return URL(fileURLWithPath: arguments[nextIndex])
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("preferences-runtime-snapshot.png")
    }

    @MainActor
    static func render(to outputURL: URL, arguments: [String] = CommandLine.arguments) throws {
        let controller = PreferencesWindowController()
        var preferences = RustPreferencesDocument()
        preferences.general.launchAtLogin = true
        preferences.general.defaultPanelHeight = 360
        preferences.history.recordFiles = true
        preferences.ignoreList.ignoredAppIdentifiers = [
            "com.apple.Terminal",
            "Xcode"
        ]
        preferences.ignoreList.windowTitleKeywords = [
            "验证码",
            "Private"
        ]
        preferences.appearance.itemDensity = "standard"

        controller.updatePreferences(preferences)
        controller.showSection(section(arguments: arguments))
        controller.updateLaunchAtLoginState(
            LaunchAtLoginState(
                isOn: true,
                canChange: true,
                detail: "已开启"
            )
        )
        controller.updateAccessibilityPermissionState(
            AccessibilityPermissionState(
                isTrusted: true,
                detail: "已允许读取当前窗口标题",
                actionTitle: "打开系统设置",
                canOpenSettings: true
            )
        )

        guard let window = controller.window,
              let rootView = window.contentView
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let targetFrame = NSRect(x: 0, y: 0, width: 920, height: 700)
        window.setFrame(targetFrame, display: false)
        rootView.frame = NSRect(origin: .zero, size: targetFrame.size)
        window.layoutIfNeeded()
        rootView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        try ViewSnapshotRenderer.render(view: rootView, to: outputURL)
    }

    private static func section(arguments: [String]) -> PreferenceSection {
        guard let flagIndex = arguments.firstIndex(of: sectionFlag) else { return .general }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return .general }

        switch arguments[valueIndex].lowercased() {
        case "general":
            return .general
        case "shortcuts":
            return .shortcuts
        case "rules":
            return .rules
        default:
            return .general
        }
    }

}

enum PreferencesSmokeCommand {
    private static let flag = "--exercise-preferences"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run() {
        let controller = PreferencesWindowController()
        controller.updatePreferences(RustPreferencesDocument())
        controller.updateLaunchAtLoginState(
            LaunchAtLoginState(
                isOn: false,
                canChange: true,
                detail: "Smoke"
            )
        )
        controller.updateAccessibilityPermissionState(
            AccessibilityPermissionState(
                isTrusted: false,
                detail: "Smoke",
                actionTitle: "重新检查",
                canOpenSettings: true
            )
        )
        controller.onPreferencesChanged = { [weak controller] preferences in
            controller?.updateLaunchAtLoginState(
                LaunchAtLoginState(
                    isOn: preferences.general.launchAtLogin,
                    canChange: true,
                    detail: "Smoke"
                )
            )
            return preferences
        }

        guard let rootView = controller.window?.contentView else { return }
        PreferencesQAHarness.exerciseAllSections(in: rootView)
    }
}

enum PanelInteractionSmokeCommand {
    private static let flag = "--exercise-panel-interactions"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run() throws {
        try PanelInteractionSmokeScenario.run().emit()
    }
}

enum RealFunctionQACommand {
    private static let flag = "--exercise-real-functions"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run() async throws {
        let report = try await RealFunctionQAScenario.run()
        report.emit()
    }
}

enum ContextMenuRealQACommand {
    private static let flag = "--show-context-menu"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let appSupportURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("panel-interaction-smoke", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let imageURL = try PanelQASamples.makePanelInteractionSmokeImageURL(outputDirectory: appSupportURL)
        let sampleItems = PanelQASamples.makePanelInteractionItems(imagePath: imageURL.path)
        let frame = NSRect(x: 46, y: 120, width: 1840, height: 330)
        let contentView = FloatingPanelContentView(frame: frame)
        contentView.updateListState(
            .success(RustCoreListResult(
                items: sampleItems,
                totalCount: Int64(sampleItems.count),
                hasMore: false
            )),
            isFiltered: false
        )
        contentView.updatePanelHeight(frame.height)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        guard let card = contentView.smokeCardBoxes().first else {
            throw QAError(message: "未找到可展示右键菜单的条目")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let localPoint = NSPoint(x: card.bounds.midX, y: card.bounds.midY)
            let windowPoint = card.convert(localPoint, to: nil)
            guard let event = NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: windowPoint,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: card.window?.windowNumber ?? 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ) else {
                return
            }
            card.rightMouseDown(with: event)
        }
        RunLoop.main.run()
    }

    private struct QAError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }
}

enum PreviewRealQACommand {
    private static let flag = "--show-preview"
    private static let longTextFlag = "--show-preview-long"
    private static let imageFlag = "--show-preview-image"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag) || arguments.contains(longTextFlag) || arguments.contains(imageFlag)
    }

    @MainActor
    static func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("preview-real-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let controller = FloatingPanelController()
        let item: RustClipboardItemSummary
        if CommandLine.arguments.contains(imageFlag) {
            item = try PanelQASamples.makePreviewImageItem(outputDirectory: outputDirectory)
        } else {
            item = PanelQASamples.makePreviewItem(isLongText: CommandLine.arguments.contains(longTextFlag))
        }
        controller.setAppSupportDirectory(outputDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        let contentView = controller.smokeContentView
        contentView.layoutSubtreeIfNeeded()
        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        guard contentView.smokeIsPreviewShown else {
            throw PanelQASamples.PreviewQAError(message: "预览浮层未打开")
        }

        app.activate(ignoringOtherApps: true)
        RunLoop.main.run()
    }
}

enum UIDiagnosticsCommand {
    private static let flag = "--print-ui-diagnostics"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run() {
        _ = NSApplication.shared
        let screens = NSScreen.screens
        let mouseLocation = NSEvent.mouseLocation
        let frames = screens.map(\.frame)
        let targetIndex = ScreenSelectionPlanner.selectedScreenIndex(
            mouseLocation: mouseLocation,
            screenFrames: frames
        )
        let plannedFrames = ScreenSelectionPlanner.panelFrames(
            screenFrames: frames,
            preferredHeight: BottomPanelGeometryPlanner.defaultHeight
        )

        print("screenCount=\(screens.count)")
        print("mouseLocation=\(format(point: mouseLocation))")
        print("targetScreenIndex=\(targetIndex.map(String.init) ?? "none")")

        for (index, screen) in screens.enumerated() {
            let plannedFrame = plannedFrames[index]
            print(
                [
                    "screen[\(index)]",
                    "frame=\(format(rect: screen.frame))",
                    "visibleFrame=\(format(rect: screen.visibleFrame))",
                    "scale=\(String(format: "%.2f", screen.backingScaleFactor))",
                    "panelFrame=\(format(rect: plannedFrame))"
                ].joined(separator: " ")
            )
        }
    }

    private static func format(point: CGPoint) -> String {
        "(\(format(point.x)),\(format(point.y)))"
    }

    private static func format(rect: CGRect) -> String {
        "(x:\(format(rect.origin.x)),y:\(format(rect.origin.y)),w:\(format(rect.width)),h:\(format(rect.height)))"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
