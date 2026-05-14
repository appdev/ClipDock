import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp
import ServiceManagement

enum PanelSnapshotCommand {
    private static let flag = "--render-panel-snapshot"
    private static let selectedPinboardFlag = "--snapshot-selected-pinboard"

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
    static func render(to outputURL: URL, arguments: [String] = CommandLine.arguments) throws {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 320)
        let view = FloatingPanelContentView(frame: frame)
        view.updatePinboards(snapshotPinboards)
        if let selectedPinboardID = selectedPinboardID(arguments: arguments),
           let pinboardButton = view.smokePinboardFilterButton(pinboardID: selectedPinboardID) {
            pinboardButton.onPress?()
        }
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
        let backdropView = PanelSnapshotBackdropView(frame: frame)
        backdropView.addSubview(view)
        window.contentView = backdropView
        window.layoutIfNeeded()
        backdropView.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        try ViewSnapshotRenderer.render(view: backdropView, to: outputURL)
    }

    private static func selectedPinboardID(arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: selectedPinboardFlag) else { return nil }
        let nextIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(nextIndex), !arguments[nextIndex].hasPrefix("--") else {
            return nil
        }
        return arguments[nextIndex]
    }

    private static var snapshotPinboards: [RustPinboardSummary] {
        [
            RustPinboardSummary(
                id: "ai",
                title: "AI",
                colorCode: 4_293_940_557,
                sortOrder: 1,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "untitled",
                title: "未命名",
                colorCode: 4_293_088_528,
                sortOrder: 2,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "name",
                title: "Name",
                colorCode: 4_290_925_536,
                sortOrder: 3,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "blue-name",
                title: "一个很长的 Pinboard 名称用于验证 chip 不截断",
                colorCode: 4_283_973_119,
                sortOrder: 4,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ]
    }
}

private final class PanelSnapshotBackdropView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 模拟 ClipShelf 面板背后的编辑器底色，不能作为产品面板背景使用。
        NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()

        NSColor(calibratedWhite: 1, alpha: 0.30).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 1)).fill()

        NSColor(calibratedWhite: 0.74, alpha: 0.14).setFill()
        for row in 0..<6 {
            let y = 34 + CGFloat(row) * 24
            NSBezierPath(rect: NSRect(x: 80, y: y, width: bounds.width - 160, height: 1)).fill()
        }
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
        preferences.ignoreList.ignoredAppIdentifiers = [
            "com.apple.Terminal",
            "Xcode"
        ]
        preferences.ignoreList.windowTitleKeywords = [
            "验证码",
            "Private"
        ]

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
        case "appearance":
            return .general
        case "history":
            return .general
        case "shortcuts":
            return .shortcuts
        case "privacy", "rules":
            return .rules
        case "about":
            return .about
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

        controller.exerciseForSmoke()
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

enum LinkPreviewSmokeCommand {
    private static let flag = "--exercise-link-preview"
    private static let urlFlag = "--link-preview-url"
    private static let fallbackURL = URL(string: "http://127.0.0.1:9/smoke")!

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run(arguments: [String] = CommandLine.arguments) throws {
        let linkURL = try previewURL(arguments: arguments)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let appSupportURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("link-preview-smoke", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(appSupportURL)
        controller.setLinkWebPreviewEnabled(true)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: [smokeLinkItem(url: linkURL)],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        guard !contentView.smokeCardsContainWebView() else {
            throw QAError(message: "链接卡片层不应包含 WKWebView")
        }

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        guard contentView.smokeIsPreviewShown,
              contentView.smokePreviewContainsWebView()
        else {
            throw QAError(message: "链接完整预览未创建 WKWebView")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let previewWebViewURL = contentView.smokePreviewWebViewURLString(),
              previewWebViewURL == linkURL.absoluteString
        else {
            throw QAError(message: "链接完整预览未加载指定 URL")
        }

        guard contentView.smokeClosePreviewWithSpaceFromPopoverFocus() else {
            throw QAError(message: "链接预览无法通过 Space 关闭")
        }
        PanelQAHarness.drainMainRunLoop()
        guard !contentView.smokeIsPreviewShown,
              !contentView.smokePreviewContainsWebView()
        else {
            throw QAError(message: "链接预览关闭后 WKWebView 未从视图树释放")
        }

        controller.hide()
        print("link_preview_smoke=passed")
        print("link_preview_url=\(linkURL.absoluteString)")
        print("preview_webview_url=\(linkURL.absoluteString)")
        print("card_contains_webview=false")
        print("preview_contains_webview=true")
        print("metadata_background_fetch=disabled")
    }

    private static func previewURL(arguments: [String]) throws -> URL {
        guard let flagIndex = arguments.firstIndex(of: urlFlag) else {
            return fallbackURL
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex),
              !arguments[valueIndex].hasPrefix("--"),
              let url = URL(string: arguments[valueIndex]),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else {
            throw QAError(message: "链接预览 URL 参数无效")
        }

        return url
    }

    private static func smokeLinkItem(url: URL) -> RustClipboardItemSummary {
        let absoluteString = url.absoluteString
        let host = url.host ?? absoluteString
        return RustClipboardItemSummary(
            id: "link-preview-smoke",
            itemType: "link",
            summary: absoluteString,
            primaryText: absoluteString,
            contentHash: "link-preview-smoke",
            sourceAppId: nil,
            sourceAppName: "Safari",
            sourceAppIconPath: nil,
            previewAssetPath: nil,
            payloadAssetPath: nil,
            sourceConfidence: "high",
            firstCopiedAtMs: 1,
            lastCopiedAtMs: 1,
            copyCount: 1,
            isPinned: false,
            sizeBytes: Int64(absoluteString.utf8.count),
            previewState: "ready",
            linkMetadata: RustLinkMetadataSummary(
                canonicalURL: absoluteString,
                displayURL: absoluteString,
                host: host,
                metadataState: "disabled"
            )
        )
    }

    private struct QAError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
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
        window.contentView = makeFloatingPanelHostView(contentView: contentView)
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

enum PinboardRealQACommand {
    private static let flag = "--show-pinboard-ui"
    @MainActor
    private static var qaWindow: NSWindow?
    @MainActor
    private static var qaContentView: FloatingPanelContentView?

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run(arguments: [String]) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        let appSupportURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("pinboard-real-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let imageURL = try PanelQASamples.makePanelInteractionSmokeImageURL(outputDirectory: appSupportURL)
        let sampleItems = PanelQASamples.makePanelInteractionItems(imagePath: imageURL.path)
        let frame = NSRect(x: 46, y: 120, width: 1840, height: 330)
        let contentView = FloatingPanelContentView(frame: frame)
        contentView.updatePinboards(samplePinboards)
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
        window.contentView = makeFloatingPanelHostView(contentView: contentView)
        qaWindow = window
        qaContentView = contentView
        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()

        let mode = mode(arguments: arguments)
        let targetPinboardID = "untitled-new"
        contentView.smokePinboardFilterButton(pinboardID: targetPinboardID)?.onPress?()

        switch mode {
        case "rename", "toolbar", "rename-long":
            _ = contentView.smokeBeginPinboardRenameForScreenshot(pinboardID: targetPinboardID)
            if mode == "rename-long" {
                _ = contentView.smokeSetActivePinboardRenameTextForScreenshot("输入中的长 Pinboard 名称会实时撑开 chip")
            }
        default:
            break
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            switch mode {
            case "menu":
                _ = contentView.smokeShowPinboardChipMenu(pinboardID: targetPinboardID)
            case "delete":
                _ = contentView.smokeShowPinboardDeleteConfirmationForScreenshot(pinboardID: targetPinboardID)
            default:
                break
            }
        }

        RunLoop.main.run()
    }

    private static func mode(arguments: [String]) -> String {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return "toolbar" }
        let nextIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(nextIndex), !arguments[nextIndex].hasPrefix("--") else {
            return "toolbar"
        }
        return arguments[nextIndex]
    }

    private static var samplePinboards: [RustPinboardSummary] {
        [
            RustPinboardSummary(
                id: "ai",
                title: "AI",
                colorCode: 4_293_940_557,
                sortOrder: 1,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "untitled",
                title: "未命名",
                colorCode: 4_294_620_928,
                sortOrder: 2,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "name",
                title: "Name",
                colorCode: 4_290_925_536,
                sortOrder: 3,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "blue-name",
                title: "一个很长的 Pinboard 名称用于验证 chip 不截断",
                colorCode: 4_283_973_119,
                sortOrder: 4,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "untitled-new",
                title: "未命名",
                colorCode: 4_279_606_035,
                sortOrder: 5,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ]
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

enum LaunchAtLoginDiagnosticsCommand {
    private static let flag = "--print-launch-at-login-diagnostics"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run() {
        let controller = LaunchAtLoginController()
        let state = controller.currentState()

        print("bundleURL=\(Bundle.main.bundleURL.path)")
        print("bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "none")")
        print("serviceStatus=\(serviceStatusDescription(SMAppService.mainApp.status))")
        print("isOn=\(state.isOn)")
        print("canChange=\(state.canChange)")
        print("detail=\(state.detail)")
    }

    private static func serviceStatusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "enabled"
        case .notRegistered:
            return "notRegistered"
        case .requiresApproval:
            return "requiresApproval"
        case .notFound:
            return "notFound"
        @unknown default:
            return "unknown"
        }
    }
}
