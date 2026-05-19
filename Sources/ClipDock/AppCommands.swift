import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp
import ServiceManagement

private enum CommandLineArgumentReader {
    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex),
              !arguments[valueIndex].hasPrefix("--")
        else {
            return nil
        }
        return arguments[valueIndex]
    }

    static func outputURL(
        after flag: String,
        in arguments: [String],
        defaultArtifactFilename: String
    ) -> URL? {
        guard arguments.contains(flag) else { return nil }
        if let path = value(after: flag, in: arguments) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent(defaultArtifactFilename)
    }
}

private enum PreferencesCommandArguments {
    static func section(arguments: [String], flag: String) -> PreferenceSection {
        switch CommandLineArgumentReader.value(after: flag, in: arguments)?.lowercased() {
        case "general", "appearance", "history":
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

    static func appearanceMode(arguments: [String], flag: String) -> String {
        switch CommandLineArgumentReader.value(after: flag, in: arguments)?.lowercased() {
        case "light":
            return "light"
        case "dark":
            return "dark"
        default:
            return "system"
        }
    }
}

private enum CommandLineWindowPlacement {
    private static let screenFlag = "--qa-screen"

    @MainActor
    static func frame(
        arguments: [String],
        defaultOrigin: NSPoint,
        size: NSSize
    ) -> NSRect {
        let screenOrigin = screenFrame(arguments: arguments)?.origin ?? .zero
        return NSRect(
            x: screenOrigin.x + defaultOrigin.x,
            y: screenOrigin.y + defaultOrigin.y,
            width: size.width,
            height: size.height
        )
    }

    @MainActor
    static func bottomPanelFrame(
        arguments: [String],
        preferredHeight: CGFloat
    ) -> NSRect {
        let targetScreenFrame = targetScreenFrame(arguments: arguments)
        return BottomPanelGeometryPlanner.frame(
            screenFrame: targetScreenFrame,
            preferredHeight: preferredHeight
        )
    }

    @MainActor
    static func targetScreen(arguments: [String]) -> NSScreen? {
        guard let value = CommandLineArgumentReader.value(after: screenFlag, in: arguments),
              let index = Int(value),
              NSScreen.screens.indices.contains(index)
        else {
            return NSScreen.main
        }
        return NSScreen.screens[index]
    }

    @MainActor
    static func targetScreenFrame(arguments: [String]) -> NSRect {
        targetScreen(arguments: arguments)?.frame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    @MainActor
    static func cleanDesktopFrame(arguments: [String]) -> NSRect {
        targetScreenFrame(arguments: arguments)
    }

    @MainActor
    private static func screenFrame(arguments: [String]) -> NSRect? {
        guard let value = CommandLineArgumentReader.value(after: screenFlag, in: arguments),
              let index = Int(value),
              NSScreen.screens.indices.contains(index)
        else {
            return nil
        }
        return NSScreen.screens[index].frame
    }
}

private final class QACleanDesktopBackdropView: NSView {
    private let desktopImage: NSImage?

    init(frame: NSRect, desktopImage: NSImage?) {
        self.desktopImage = desktopImage
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.045, green: 0.058, blue: 0.070, alpha: 1).setFill()
        bounds.fill()

        guard let desktopImage, desktopImage.size.width > 0, desktopImage.size.height > 0 else {
            return
        }

        let imageSize = desktopImage.size
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = NSRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        desktopImage.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: imageSize),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

private struct CommandLineQAError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

enum PanelSnapshotCommand {
    private static let flag = "--render-panel-snapshot"
    private static let selectedPinboardFlag = "--snapshot-selected-pinboard"
    private static let searchOpenFlag = "--snapshot-search-open"
    private static let searchTextFlag = "--snapshot-search-text"

    static func outputURL(arguments: [String]) -> URL? {
        CommandLineArgumentReader.outputURL(
            after: flag,
            in: arguments,
            defaultArtifactFilename: "panel-runtime-snapshot.png"
        )
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
        let previewURL = try PanelQASamples.makeRealSampleImageURL()
        let sourceIconPaths = try PanelQASamples.makeSourceAppIconPaths(outputDirectory: outputURL.deletingLastPathComponent())
        let styledTextPreviewURL = try PanelQASamples.makeStyledCodeRTFPreviewURL(
            outputDirectory: outputURL.deletingLastPathComponent()
        )
        let sampleItems = PanelQASamples.makePanelSnapshotItems(
            imagePath: previewURL.path,
            sourceIconPaths: sourceIconPaths,
            styledTextPreviewPath: styledTextPreviewURL.path
        )
        view.updateListState(
            .success(RustCoreListResult(
                items: sampleItems,
                totalCount: Int64(sampleItems.count),
                hasMore: false
            )),
            isFiltered: false
        )
        view.smokeSelectItem(id: "snapshot-text", scrollIntoView: false)
        view.updatePanelHeight(frame.height)
        if arguments.contains(searchOpenFlag) {
            view.smokeOpenSearch(text: searchText(arguments: arguments))
        }
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
        CommandLineArgumentReader.value(after: selectedPinboardFlag, in: arguments)
    }

    private static func searchText(arguments: [String]) -> String {
        CommandLineArgumentReader.value(after: searchTextFlag, in: arguments) ?? ""
    }

    private static var snapshotPinboards: [RustPinboardSummary] {
        [
            RustPinboardSummary(
                id: "ai",
                title: "产品资料",
                colorCode: 4_293_940_557,
                sortOrder: 1,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "untitled",
                title: "设计参考",
                colorCode: 4_293_088_528,
                sortOrder: 2,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "name",
                title: "发布说明",
                colorCode: 4_290_925_536,
                sortOrder: 3,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "blue-name",
                title: "客户资料归档",
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
        // 模拟 ClipDock 面板背后的编辑器底色，不能作为产品面板背景使用。
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
    private static let appearanceFlag = "--preferences-appearance"

    static func outputURL(arguments: [String]) -> URL? {
        CommandLineArgumentReader.outputURL(
            after: flag,
            in: arguments,
            defaultArtifactFilename: "preferences-runtime-snapshot.png"
        )
    }

    @MainActor
    static func render(to outputURL: URL, arguments: [String] = CommandLine.arguments) throws {
        let controller = PreferencesWindowController()
        var preferences = RustPreferencesDocument()
        preferences.general.launchAtLogin = true
        preferences.general.defaultPanelHeight = 360
        preferences.appearance.mode = PreferencesCommandArguments.appearanceMode(
            arguments: arguments,
            flag: appearanceFlag
        )
        preferences.ignoreList.ignoredAppIdentifiers = [
            "com.apple.Terminal",
            "Xcode"
        ]
        preferences.ignoreList.windowTitleKeywords = [
            "验证码",
            "Private"
        ]

        ClipDockTheme.applyAppearanceMode(preferences.appearance.mode)
        controller.updatePreferences(preferences)
        controller.showSection(PreferencesCommandArguments.section(arguments: arguments, flag: sectionFlag))
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

enum PreferencesRealUICommand {
    private static let flag = "--show-preferences-ui"
    private static let sectionFlag = "--preferences-section"
    private static let appearanceFlag = "--preferences-appearance"
    @MainActor
    private static var qaController: PreferencesWindowController?

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run(arguments: [String] = CommandLine.arguments) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        var preferences = RustPreferencesDocument()
        preferences.general.launchAtLogin = true
        preferences.general.showMenuBarItem = true
        preferences.general.defaultPanelHeight = 360
        preferences.appearance.mode = PreferencesCommandArguments.appearanceMode(
            arguments: arguments,
            flag: appearanceFlag
        )
        preferences.appearance.previewPopoverEnabled = true
        preferences.ignoreList.ignoredAppIdentifiers = [
            "com.apple.Terminal",
            "com.apple.dt.Xcode"
        ]
        preferences.ignoreList.windowTitleKeywords = [
            "验证码",
            "Private"
        ]

        ClipDockTheme.applyAppearanceMode(preferences.appearance.mode)

        let controller = PreferencesWindowController()
        controller.updatePreferences(preferences)
        controller.showSection(PreferencesCommandArguments.section(arguments: arguments, flag: sectionFlag))
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
        controller.showPreferences()

        if let window = controller.window {
            window.setFrame(
                CommandLineWindowPlacement.frame(
                    arguments: arguments,
                    defaultOrigin: NSPoint(x: 500, y: 170),
                    size: NSSize(width: 920, height: 700)
                ),
                display: true
            )
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        qaController = controller
        RunLoop.main.run()
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
            throw CommandLineQAError(message: "链接卡片层不应包含 WKWebView")
        }

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        guard contentView.smokeIsPreviewShown,
              contentView.smokePreviewContainsWebView()
        else {
            throw CommandLineQAError(message: "链接完整预览未创建 WKWebView")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let previewWebViewURL = contentView.smokePreviewWebViewURLString(),
              urlsMatchForSmoke(previewWebViewURL, linkURL)
        else {
            throw CommandLineQAError(message: "链接完整预览未加载指定 URL")
        }

        guard contentView.smokeClosePreviewWithSpaceFromPopoverFocus() else {
            throw CommandLineQAError(message: "链接预览无法通过 Space 关闭")
        }
        PanelQAHarness.drainMainRunLoop()
        guard !contentView.smokeIsPreviewShown,
              !contentView.smokePreviewContainsWebView()
        else {
            throw CommandLineQAError(message: "链接预览关闭后 WKWebView 未从视图树释放")
        }

        controller.hide()
        print("link_preview_smoke=passed")
        print("link_preview_url=\(linkURL.absoluteString)")
        print("preview_webview_url=\(linkURL.absoluteString)")
        print("card_contains_webview=false")
        print("preview_contains_webview=true")
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
            throw CommandLineQAError(message: "链接预览 URL 参数无效")
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
                metadataState: "pending"
            )
        )
    }

    private static func urlsMatchForSmoke(_ actualURLString: String, _ expectedURL: URL) -> Bool {
        guard let actualURL = URL(string: actualURLString) else {
            return false
        }
        return normalizedSmokeURLString(actualURL) == normalizedSmokeURLString(expectedURL)
    }

    private static func normalizedSmokeURLString(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.path.isEmpty == true {
            components?.path = "/"
        }
        return components?.url?.absoluteString ?? url.absoluteString
    }

}

enum PanelReconcileBenchmarkCommand {
    private static let benchmarkFlag = "--panel-reconcile-benchmark"
    private static let scrollSmokeFlag = "--panel-scroll-smoke"
    private static let itemsFlag = "--items"

    static func shouldRunBenchmark(arguments: [String]) -> Bool {
        arguments.contains(benchmarkFlag)
    }

    static func shouldRunScrollSmoke(arguments: [String]) -> Bool {
        arguments.contains(scrollSmokeFlag)
    }

    @MainActor
    static func runBenchmark(arguments: [String] = CommandLine.arguments) throws {
        let itemCount = try parsedItemCount(arguments: arguments)
        let frame = NSRect(x: 0, y: 0, width: 960, height: 320)
        let contentView = FloatingPanelContentView(frame: frame)
        contentView.updateAppSupportDirectory(FileManager.default.temporaryDirectory)
        contentView.updatePanelHeight(frame.height)

        let baseItems = benchmarkItems(count: itemCount)
        contentView.updateListState(
            .success(RustCoreListResult(items: baseItems, totalCount: Int64(baseItems.count), hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        let clock = ContinuousClock()
        var samples: [Double] = []
        var currentItems = baseItems
        for index in 0..<32 {
            let nextItems = mutation(of: currentItems, baseItems: baseItems, index: index)
            let start = clock.now
            contentView.updateListState(
                .success(RustCoreListResult(items: nextItems, totalCount: Int64(nextItems.count), hasMore: false)),
                isFiltered: false
            )
            contentView.layoutSubtreeIfNeeded()
            samples.append(milliseconds(from: start.duration(to: clock.now)))
            currentItems = nextItems
        }

        let p50 = percentile(samples, percentile: 0.50)
        let p95 = percentile(samples, percentile: 0.95)
        let targetP95 = targetP95Milliseconds(itemCount: itemCount)
        try emit(BenchmarkReport(
            command: benchmarkFlag,
            build: buildConfiguration,
            itemCount: itemCount,
            sampleCount: samples.count,
            p50Ms: p50,
            p95Ms: p95,
            targetP95Ms: targetP95,
            nsCollectionViewMigrationTriggerRaised: p95 > targetP95,
            machine: machineMetadata,
            itemMix: "text/link deterministic; reorder/delete/middle-insert/metadata-update mutations"
        ))
    }

    @MainActor
    static func runScrollSmoke(arguments: [String] = CommandLine.arguments) throws {
        let itemCount = try parsedItemCount(arguments: arguments)
        let frame = NSRect(x: 0, y: 0, width: 960, height: 320)
        let contentView = FloatingPanelContentView(frame: frame)
        contentView.updateListState(
            .success(RustCoreListResult(
                items: benchmarkItems(count: itemCount),
                totalCount: Int64(itemCount),
                hasMore: false
            )),
            isFiltered: false
        )
        contentView.updatePanelHeight(frame.height)
        contentView.layoutSubtreeIfNeeded()

        let scrollOriginAtStart = contentView.smokeScrollOriginX
        contentView.smokeScrollToX(.greatestFiniteMagnitude)
        let scrollOriginAtEnd = contentView.smokeScrollOriginX
        try emit(ScrollSmokeReport(
            command: scrollSmokeFlag,
            build: buildConfiguration,
            itemCount: itemCount,
            machine: machineMetadata,
            scrollOriginAtStart: Double(scrollOriginAtStart),
            scrollOriginAtEnd: Double(scrollOriginAtEnd),
            scrollEdgeOverlaysEnabled: false
        ))
    }

    private static func parsedItemCount(arguments: [String]) throws -> Int {
        guard let value = CommandLineArgumentReader.value(after: itemsFlag, in: arguments) else { return 500 }
        guard let count = Int(value),
              count > 0
        else {
            throw CommandLineQAError(message: "--items 参数必须是正整数")
        }
        return count
    }

    private static func benchmarkItems(count: Int) -> [RustClipboardItemSummary] {
        PanelQASamples.makePagedPanelItems(count: count)
    }

    private static func mutation(
        of currentItems: [RustClipboardItemSummary],
        baseItems: [RustClipboardItemSummary],
        index: Int
    ) -> [RustClipboardItemSummary] {
        guard !baseItems.isEmpty else { return [] }
        switch index % 4 {
        case 0:
            return Array(currentItems.reversed())
        case 1:
            return Array(baseItems.dropLast())
        case 2:
            var nextItems = Array(baseItems.prefix(max(1, baseItems.count - 1)))
            let inserted = benchmarkInsertedItem(index: index)
            nextItems.insert(inserted, at: min(nextItems.count / 2, nextItems.count))
            return nextItems
        default:
            var nextItems = baseItems
            let updateIndex = min(max(0, baseItems.count / 3), baseItems.count - 1)
            nextItems[updateIndex] = linkItemByUpdatingMetadata(nextItems[updateIndex], index: index)
            return nextItems
        }
    }

    private static func benchmarkInsertedItem(index: Int) -> RustClipboardItemSummary {
        RustClipboardItemSummary(
            id: "panel-benchmark-inserted-\(index)",
            itemType: "text",
            summary: "Benchmark inserted item \(index)",
            primaryText: "Benchmark inserted item \(index)",
            contentHash: "panel-benchmark-inserted-\(index)",
            sourceAppId: nil,
            sourceAppName: "Benchmark",
            sourceAppIconPath: nil,
            previewAssetPath: nil,
            payloadAssetPath: nil,
            sourceConfidence: "high",
            firstCopiedAtMs: 1,
            lastCopiedAtMs: 1,
            copyCount: 1,
            isPinned: false,
            sizeBytes: 32,
            previewState: "ready"
        )
    }

    private static func linkItemByUpdatingMetadata(
        _ item: RustClipboardItemSummary,
        index: Int
    ) -> RustClipboardItemSummary {
        RustClipboardItemSummary(
            id: item.id,
            itemType: "link",
            summary: item.summary,
            primaryText: item.primaryText ?? "https://example.com/reconcile/\(index)",
            contentHash: item.contentHash,
            sourceAppId: item.sourceAppId,
            sourceAppName: item.sourceAppName,
            sourceAppIconPath: item.sourceAppIconPath,
            previewAssetPath: item.previewAssetPath,
            payloadAssetPath: item.payloadAssetPath,
            sourceConfidence: item.sourceConfidence,
            firstCopiedAtMs: item.firstCopiedAtMs,
            lastCopiedAtMs: item.lastCopiedAtMs,
            copyCount: item.copyCount,
            isPinned: item.isPinned,
            sizeBytes: item.sizeBytes,
            previewState: item.previewState,
            fileItems: item.fileItems,
            linkMetadata: RustLinkMetadataSummary(
                canonicalURL: item.primaryText ?? "https://example.com/reconcile/\(index)",
                displayURL: "example.com/reconcile/\(index)",
                host: "example.com",
                title: "Benchmark metadata \(index)",
                siteName: "Example",
                metadataState: "ready",
                fetchedAtMs: Int64(index)
            )
        )
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(
            sorted.count - 1,
            max(0, Int((Double(sorted.count - 1) * percentile).rounded(.up)))
        )
        return sorted[index]
    }

    private static func targetP95Milliseconds(itemCount: Int) -> Double {
        if itemCount <= 50 {
            return 120
        }
        if itemCount <= 150 {
            return 400
        }
        return 1_000
    }

    private static func emit<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    private static var machineMetadata: MachineMetadata {
        let processInfo = ProcessInfo.processInfo
        return MachineMetadata(
            operatingSystem: processInfo.operatingSystemVersionString,
            processorCount: processInfo.activeProcessorCount,
            physicalMemoryBytes: processInfo.physicalMemory
        )
    }

    private struct MachineMetadata: Encodable {
        let operatingSystem: String
        let processorCount: Int
        let physicalMemoryBytes: UInt64
    }

    private struct BenchmarkReport: Encodable {
        let command: String
        let build: String
        let itemCount: Int
        let sampleCount: Int
        let p50Ms: Double
        let p95Ms: Double
        let targetP95Ms: Double
        let nsCollectionViewMigrationTriggerRaised: Bool
        let machine: MachineMetadata
        let itemMix: String
    }

    private struct ScrollSmokeReport: Encodable {
        let command: String
        let build: String
        let itemCount: Int
        let machine: MachineMetadata
        let scrollOriginAtStart: Double
        let scrollOriginAtEnd: Double
        let scrollEdgeOverlaysEnabled: Bool
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

        let imageURL = try PanelQASamples.makeRealSampleImageURL()
        let sampleItems = PanelQASamples.makePanelInteractionItems(imagePath: imageURL.path)
        let frame = CommandLineWindowPlacement.bottomPanelFrame(
            arguments: CommandLine.arguments,
            preferredHeight: 330
        )
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
            throw CommandLineQAError(message: "未找到可展示右键菜单的条目")
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

}

enum PinboardRealQACommand {
    private static let flag = "--show-pinboard-ui"
    private static let sampleImageFlag = "--qa-sample-image"
    private static let cleanDesktopFlag = "--qa-clean-desktop"
    private static let cleanDesktopImageFlag = "--qa-clean-desktop-image"
    @MainActor
    private static var qaBackdropWindow: NSWindow?
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
        installCleanDesktopBackdropIfNeeded(arguments: arguments)

        let appSupportURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("pinboard-real-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let imageURL = try PanelQASamples.validatedRealSampleImageURL(
            path: CommandLineArgumentReader.value(after: sampleImageFlag, in: arguments)
        )
        let imagePreviewURL = try PanelQASamples.makeCardFillingImagePreviewURL(
            sourceURL: imageURL,
            appSupportURL: appSupportURL
        )
        let filePreviewURL = try PanelQASamples.makeRealDocumentPreviewURL(
            filePaths: PanelQASamples.realSampleFilePaths(),
            appSupportURL: appSupportURL
        )
        let githubAssets = try PanelQASamples.prepareRealGitHubSampleAssets(appSupportURL: appSupportURL)
        let sourceIconPaths = try PanelQASamples.makeSourceAppIconPaths(outputDirectory: appSupportURL)
        PanelCardAssetResolver.primePreviewImageCacheForSmoke(paths: [
            imagePreviewURL.path,
            filePreviewURL.path,
            githubAssets.linkMetadata.imageAssetPath
        ].compactMap { $0 })
        let sampleItems = PanelQASamples.makePanelInteractionItems(
            imagePath: imagePreviewURL.path,
            imagePayloadPath: imageURL.path,
            filePreviewPath: filePreviewURL.path,
            linkMetadata: githubAssets.linkMetadata,
            sourceIconPaths: sourceIconPaths
        )
        let frame = CommandLineWindowPlacement.bottomPanelFrame(
            arguments: arguments,
            preferredHeight: 330
        )
        let contentView = FloatingPanelContentView(frame: frame)
        contentView.updateAppSupportDirectory(appSupportURL)
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
        window.level = panelWindowLevel(arguments: arguments)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = makeFloatingPanelHostView(contentView: contentView)
        qaWindow = window
        qaContentView = contentView
        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()

        let mode = mode(arguments: arguments)
        let targetPinboardID = mode == "ai" ? "ai" : "untitled-new"
        if mode == "overview" || mode == "preview" {
            contentView.updateListState(
                .success(RustCoreListResult(
                    items: sampleItems,
                    totalCount: Int64(sampleItems.count),
                    hasMore: false
                )),
                isFiltered: false
            )
            contentView.layoutSubtreeIfNeeded()
        } else {
            contentView.smokePinboardFilterButton(pinboardID: targetPinboardID)?.onPress?()
            contentView.updateListState(
                .success(RustCoreListResult(
                    items: sampleItems,
                    totalCount: Int64(sampleItems.count),
                    hasMore: false
                )),
                isFiltered: true
            )
        }

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
            case "preview":
                contentView.smokeSelectItem(id: "panel-smoke-image", scrollIntoView: false)
                contentView.layoutSubtreeIfNeeded()
                PanelQAHarness.sendSpace(to: contentView)
            default:
                break
            }
        }

        runMainLoop()
    }

    @MainActor
    private static func runMainLoop() {
        RunLoop.main.run()
    }

    private static func mode(arguments: [String]) -> String {
        CommandLineArgumentReader.value(after: flag, in: arguments) ?? "toolbar"
    }

    @MainActor
    private static func installCleanDesktopBackdropIfNeeded(arguments: [String]) {
        guard arguments.contains(cleanDesktopFlag) else {
            return
        }

        let screen = CommandLineWindowPlacement.targetScreen(arguments: arguments)
        let explicitImage = CommandLineArgumentReader
            .value(after: cleanDesktopImageFlag, in: arguments)
            .map(URL.init(fileURLWithPath:))
            .flatMap(NSImage.init(contentsOf:))
        let desktopImageURL = screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        let desktopImage = explicitImage ?? desktopImageURL.flatMap(NSImage.init(contentsOf:))
        let frame = CommandLineWindowPlacement.cleanDesktopFrame(arguments: arguments)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = cleanDesktopWindowLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.contentView = QACleanDesktopBackdropView(
            frame: NSRect(origin: .zero, size: frame.size),
            desktopImage: desktopImage
        )
        qaBackdropWindow = window
        window.orderFrontRegardless()
    }

    private static var cleanDesktopWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    }

    private static func panelWindowLevel(arguments: [String]) -> NSWindow.Level {
        guard arguments.contains(cleanDesktopFlag) else {
            return .floating
        }
        return NSWindow.Level(rawValue: cleanDesktopWindowLevel.rawValue + 1)
    }

    private static var samplePinboards: [RustPinboardSummary] {
        [
            RustPinboardSummary(
                id: "ai",
                title: "产品资料",
                colorCode: 4_293_940_557,
                sortOrder: 1,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "untitled",
                title: "设计参考",
                colorCode: 4_294_620_928,
                sortOrder: 2,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "name",
                title: "发布说明",
                colorCode: 4_290_925_536,
                sortOrder: 3,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "blue-name",
                title: "客户资料归档",
                colorCode: 4_283_973_119,
                sortOrder: 4,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "untitled-new",
                title: "团队知识库",
                colorCode: 4_279_606_035,
                sortOrder: 5,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ]
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
        let sourceIconPaths = try PanelQASamples.makeSourceAppIconPaths(outputDirectory: outputDirectory)
        let item: RustClipboardItemSummary
        if CommandLine.arguments.contains(imageFlag) {
            item = try PanelQASamples.makePreviewImageItem(
                outputDirectory: outputDirectory,
                sourceIconPaths: sourceIconPaths
            )
        } else {
            item = PanelQASamples.makePreviewItem(
                isLongText: CommandLine.arguments.contains(longTextFlag),
                sourceIconPaths: sourceIconPaths
            )
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
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           let executableURL = Bundle.main.executableURL,
           Bundle.main.bundleURL.pathExtension == "app" {
            let fallbackAgent = LaunchAtLoginFallbackAgent(
                bundleIdentifier: bundleIdentifier,
                executableURL: executableURL
            )
            print("fallbackPlist=\(fallbackAgent.plistURL.path)")
            print("fallbackEnabled=\(fallbackAgent.isEnabled)")
        }
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
