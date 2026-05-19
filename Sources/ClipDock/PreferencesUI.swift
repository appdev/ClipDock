import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipboardPanelApp
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum PreferenceSection: Int, CaseIterable, Hashable {
    case general
    case appearance
    case history
    case shortcuts
    case rules
    case about

    static var allCases: [PreferenceSection] {
        [
            .general,
            .rules,
            .shortcuts,
            .about
        ]
    }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .appearance:
            return "外观"
        case .history:
            return "保留历史"
        case .shortcuts:
            return "键盘快捷键"
        case .rules:
            return "隐私"
        case .about:
            return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "启动、菜单栏、粘贴项目、主题、预览与保留策略"
        case .appearance:
            return "主题与预览浮层"
        case .history:
            return "记录类型、保留时长与数量"
        case .shortcuts:
            return "打开、搜索与快速取用"
        case .rules:
            return "来源权限与忽略应用"
        case .about:
            return "版本、构建与项目说明"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .appearance:
            return "paintpalette"
        case .history:
            return "clock.arrow.circlepath"
        case .shortcuts:
            return "keyboard"
        case .rules:
            return "hand.raised"
        case .about:
            return "info.circle"
        }
    }
}

@MainActor
private final class StepperTextBinding: NSObject, NSTextFieldDelegate {
    private let textField: NSTextField
    private let stepper: NSStepper
    private let minimumValue: Int
    private let maximumValue: Int
    private let onChange: (Int) -> Void

    init(
        textField: NSTextField,
        stepper: NSStepper,
        minimumValue: Int,
        maximumValue: Int,
        onChange: @escaping (Int) -> Void
    ) {
        self.textField = textField
        self.stepper = stepper
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.onChange = onChange
        super.init()

        textField.delegate = self
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let value = Int(textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Int(stepper.doubleValue)
        let clampedValue = min(max(value, minimumValue), maximumValue)
        stepper.doubleValue = Double(clampedValue)
        textField.stringValue = "\(clampedValue)"
        onChange(clampedValue)
    }
}

@MainActor
private final class TextInputBinding: NSObject, NSTextFieldDelegate {
    private let textField: NSTextField
    private let onCommit: (String) -> Void

    init(textField: NSTextField, onCommit: @escaping (String) -> Void) {
        self.textField = textField
        self.onCommit = onCommit
        super.init()

        textField.delegate = self
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        onCommit(textField.stringValue)
    }
}

final class PreferenceNavigationButton: NSButton {
    var onPress: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        triggerPress()
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter:
            triggerPress()
        default:
            super.keyDown(with: event)
        }
    }

    func triggerPress() {
        onPress?()
    }
}

final class PreferenceActionButton: NSButton {
    var onPress: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        triggerPress()
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter:
            triggerPress()
        default:
            super.keyDown(with: event)
        }
    }

    func triggerPress() {
        onPress?()
    }
}

final class ShortcutRecorderButton: NSButton {
    var onShortcutRecorded: ((RustKeyboardShortcut) -> Void)?
    var normalTextColor = NSColor.labelColor {
        didSet {
            refreshTitle()
        }
    }
    private var shortcut: RustKeyboardShortcut
    private var isRecordingShortcut = false

    init(shortcut: RustKeyboardShortcut) {
        self.shortcut = KeyboardShortcutPresenter.normalized(shortcut)
        super.init(frame: .zero)

        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        isBordered = true
        focusRingType = .exterior
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        alignment = .center
        refreshTitle()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            switch Int(event.keyCode) {
            case kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter:
                beginRecording()
            default:
                super.keyDown(with: event)
            }
            return
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            cancelRecording()
        default:
            recordShortcut(from: event)
        }
    }

    func triggerForSmoke() {
        beginRecording()
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: "b",
            charactersIgnoringModifiers: "b",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_B)
        ) else {
            return
        }
        keyDown(with: event)
    }

    func updateShortcut(_ shortcut: RustKeyboardShortcut) {
        self.shortcut = KeyboardShortcutPresenter.normalized(shortcut)
        refreshTitle()
    }

    private func beginRecording() {
        isRecordingShortcut = true
        window?.makeFirstResponder(self)
        refreshTitle(overrideText: "按下快捷键", color: NSColor.systemBlue)
    }

    private func cancelRecording() {
        isRecordingShortcut = false
        refreshTitle()
    }

    private func recordShortcut(from event: NSEvent) {
        let shortcut = RustKeyboardShortcut(
            keyCode: Int64(event.keyCode),
            modifiers: modifierNames(from: event.modifierFlags)
        )

        guard KeyboardShortcutPresenter.isRecordable(shortcut) else {
            refreshTitle(overrideText: "需要 ⌘ / ⌥ / ⌃", color: NSColor.systemRed)
            return
        }

        self.shortcut = KeyboardShortcutPresenter.normalized(shortcut)
        isRecordingShortcut = false
        refreshTitle()
        onShortcutRecorded?(self.shortcut)
    }

    private func modifierNames(from flags: NSEvent.ModifierFlags) -> [String] {
        let modifiers = flags.intersection(.deviceIndependentFlagsMask)
        var names: [String] = []
        if modifiers.contains(.command) {
            names.append("command")
        }
        if modifiers.contains(.option) {
            names.append("option")
        }
        if modifiers.contains(.control) {
            names.append("control")
        }
        if modifiers.contains(.shift) {
            names.append("shift")
        }
        return names
    }

    private func refreshTitle(overrideText: String? = nil, color: NSColor? = nil) {
        let text = overrideText ?? KeyboardShortcutPresenter.displayText(for: shortcut)
        attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: font ?? .monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: color ?? normalTextColor
            ]
        )
    }
}

final class PreferenceSwitch: NSSwitch {
    var onChange: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        emitChange()
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        emitChange()
    }

    func triggerForSmoke() {
        state = state == .on ? .off : .on
        emitChange()
    }

    private func emitChange() {
        onChange?(state == .on)
    }
}

final class PreferenceSegmentedControl: NSSegmentedControl {
    var onChange: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        emitChange()
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        emitChange()
    }

    func triggerForSmoke() {
        selectedSegment = min(segmentCount - 1, max(0, selectedSegment + 1))
        emitChange()
    }

    private func emitChange() {
        onChange?(selectedSegment)
    }
}

final class PreferenceStepper: NSStepper {
    var onChange: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        emitChange()
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        emitChange()
    }

    func triggerForSmoke() {
        doubleValue = min(maxValue, doubleValue + increment)
        emitChange()
    }

    private func emitChange() {
        onChange?(Int(doubleValue))
    }
}

typealias LaunchAtLoginState = LaunchAtLoginPresentation
typealias AccessibilityPermissionState = AccessibilityPermissionPresentation

struct LaunchAtLoginError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

struct LaunchAtLoginFallbackAgent {
    let label: String
    let plistURL: URL
    let executableURL: URL
    let bundleIdentifier: String
    var fileManager = FileManager.default

    init(
        bundleIdentifier: String,
        executableURL: URL,
        launchAgentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        let label = "\(bundleIdentifier).launch-at-login"
        self.label = label
        self.plistURL = launchAgentsDirectory.appendingPathComponent("\(label).plist")
        self.executableURL = executableURL
        self.bundleIdentifier = bundleIdentifier
        self.fileManager = fileManager
    }

    var isEnabled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func register() throws {
        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "AssociatedBundleIdentifiers": [bundleIdentifier],
            "Label": label,
            "LimitLoadToSessionType": "Aqua",
            "ProgramArguments": [
                executableURL.path,
                ClipDockLaunchArgument.launchedAtLogin
            ],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    func unregister() throws {
        guard isEnabled else { return }
        try fileManager.removeItem(at: plistURL)
    }
}

@MainActor
final class LaunchAtLoginController {
    func currentState() -> LaunchAtLoginState {
        LaunchAtLoginPresenter.presentation(
            isRunningAsApplicationBundle: isRunningAsApplicationBundle,
            status: currentSystemStatus()
        )
    }

    func setEnabled(_ enabled: Bool) -> Result<LaunchAtLoginState, LaunchAtLoginError> {
        guard isRunningAsApplicationBundle else {
            return .failure(LaunchAtLoginError(message: "当前 swift run 形态不能注册登录项"))
        }

        let service = SMAppService.mainApp
        do {
            let status = service.status
            let fallbackAgent = currentFallbackAgent()
            if enabled {
                if status == .notFound,
                   let fallbackAgent {
                    try fallbackAgent.register()
                } else if status != .enabled,
                          status != .requiresApproval {
                    try service.register()
                }
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                if status == .enabled || status == .requiresApproval {
                    try service.unregister()
                }
                try fallbackAgent?.unregister()
            }

            return .success(currentState())
        } catch {
            return .failure(LaunchAtLoginError(message: error.localizedDescription))
        }
    }

    private func currentSystemStatus() -> LaunchAtLoginSystemStatus {
        guard isRunningAsApplicationBundle else {
            return .unknown
        }

        let fallbackEnabled = currentFallbackAgent()?.isEnabled ?? false
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            if fallbackEnabled {
                return .enabled
            }
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            if fallbackEnabled {
                return .enabled
            }
            return .notFound
        @unknown default:
            return .unknown
        }
    }

    private var isRunningAsApplicationBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier != nil
    }

    private func currentFallbackAgent() -> LaunchAtLoginFallbackAgent? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let executableURL = Bundle.main.executableURL,
              Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }

        return LaunchAtLoginFallbackAgent(
            bundleIdentifier: bundleIdentifier,
            executableURL: executableURL
        )
    }
}

@MainActor
final class AccessibilityPermissionController {
    func currentState() -> AccessibilityPermissionState {
        AccessibilityPermissionPresenter.presentation(
            status: AXIsProcessTrusted() ? .trusted : .notTrusted
        )
    }

    func openAccessibilitySettings() {
        requestAccessibilityPermissionPrompt()

        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for value in settingsURLs {
            guard let url = URL(string: value) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func requestAccessibilityPermissionPrompt() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    private enum Layout {
        static let defaultWindowSize = NSSize(width: 920, height: 700)
        static let minimumWindowSize = NSSize(width: 820, height: 600)
    }

    private let viewModel = PreferencesSwiftUIViewModel()
    private let toolbarCoordinator = PreferencesToolbarCoordinator()
    private var splitViewController: PreferencesSplitViewController?
    private var theme: ClipDockPreferencesTheme {
        viewModel.preferencesTheme(fallbackAppearance: window?.effectiveAppearance)
    }

    var onPreferencesChanged: ((RustPreferencesDocument) -> RustPreferencesDocument?)? {
        didSet {
            viewModel.onPreferencesChanged = onPreferencesChanged
        }
    }

    var onAccessibilityPermissionRequested: (() -> Void)? {
        didSet {
            viewModel.onAccessibilityPermissionRequested = onAccessibilityPermissionRequested
        }
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "偏好设置"
        window.minSize = Layout.minimumWindowSize
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        window.toolbar = toolbarCoordinator.makeToolbar()
        window.isMovableByWindowBackground = true
        window.isOpaque = true

        super.init(window: window)

        viewModel.onAppearanceModeChanged = { [weak self] in
            self?.applyTheme()
        }
        configureWindow(window)
        applyTheme()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showPreferences() {
        guard let window else { return }

        if !window.isVisible {
            window.center()
        }

        applyTheme()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updatePreferences(_ preferences: RustPreferencesDocument) {
        viewModel.updatePreferences(preferences)
        applyTheme()
    }

    func showSection(_ section: PreferenceSection) {
        viewModel.selectSection(section)
    }

    func updateLaunchAtLoginState(_ state: LaunchAtLoginState) {
        viewModel.updateLaunchAtLoginState(state)
    }

    func updateAccessibilityPermissionState(_ state: AccessibilityPermissionState) {
        viewModel.updateAccessibilityPermissionState(state)
    }

    func exerciseForSmoke() {
        PreferenceSection.allCases.forEach { section in
            viewModel.selectSection(section)
        }
        viewModel.persist { $0.general.showMenuBarItem.toggle() }
        viewModel.persist { $0.appearance.previewPopoverEnabled.toggle() }
        viewModel.persist { $0.linkPreview.webPreviewEnabled.toggle() }
        viewModel.persist { $0.shortcuts.pasteDirectlyToTarget.toggle() }
        viewModel.persist { $0.shortcuts.alwaysPasteAsPlainText.toggle() }
        viewModel.persist {
            $0.shortcuts.openPanel = RustKeyboardShortcut(
                keyCode: Int64(kVK_ANSI_B),
                modifiers: ["command", "option"]
            )
        }
    }

    private func configureWindow(_ window: NSWindow) {
        let splitViewController = PreferencesSplitViewController(model: viewModel)
        splitViewController.view.frame = NSRect(origin: .zero, size: Layout.defaultWindowSize)
        splitViewController.view.autoresizingMask = [.width, .height]
        window.contentViewController = splitViewController
        self.splitViewController = splitViewController
    }

    private func applyTheme() {
        window?.backgroundColor = theme.windowBackgroundColor
        splitViewController?.applyTheme()
    }

    func preferencesShellSmokeSnapshot() -> PreferencesShellSmokeSnapshot? {
        guard let splitViewController else { return nil }
        window?.layoutIfNeeded()
        splitViewController.view.layoutSubtreeIfNeeded()
        return splitViewController.smokeSnapshot(
            selectedSection: viewModel.selectedSection,
            visibleSidebarSectionCount: PreferenceSection.allCases.count,
            window: window
        )
    }

    func smokeEnableDirectPasteToTargetForPermissionQA() -> Bool {
        viewModel.persistDirectPasteToTarget(true)
        return viewModel.state.preferences.shortcuts.pasteDirectlyToTarget
    }
}

@MainActor
private final class PreferencesToolbarCoordinator: NSObject, NSToolbarDelegate {
    private enum Identifier {
        static let toolbar = NSToolbar.Identifier("ClipDock.Preferences.Toolbar")
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: Identifier.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = false
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            .flexibleSpace
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            .flexibleSpace
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        nil
    }
}

@MainActor
private final class PreferencesSwiftUIViewModel: ObservableObject {
    @Published private(set) var state = PreferencesSceneState()

    private let sceneController = PreferencesSceneController()
    private var pendingDeferredRender = false

    var onPreferencesChanged: ((RustPreferencesDocument) -> RustPreferencesDocument?)?
    var onAccessibilityPermissionRequested: (() -> Void)?
    var onAppearanceModeChanged: (() -> Void)?

    var selectedSection: PreferenceSection {
        preferenceSection(for: state.selectedSection)
    }

    var forcedAppearance: NSAppearance? {
        switch state.preferences.appearance.mode {
        case "light":
            return NSAppearance(named: .aqua)
        case "dark":
            return NSAppearance(named: .darkAqua)
        default:
            return nil
        }
    }

    func selectSection(_ section: PreferenceSection) {
        apply(sceneController.selectSection(sceneSection(for: section)))
    }

    func updatePreferences(_ preferences: RustPreferencesDocument) {
        apply(sceneController.updatePreferences(preferences))
    }

    func updateLaunchAtLoginState(_ state: LaunchAtLoginState) {
        apply(sceneController.updateLaunchAtLoginState(state))
    }

    func updateAccessibilityPermissionState(_ state: AccessibilityPermissionState) {
        apply(sceneController.updateAccessibilityPermissionState(state))
    }

    func persist(_ update: (inout RustPreferencesDocument) -> Void) {
        let previousAppearanceMode = sceneController.state.preferences.appearance.mode
        let nextPreferences = sceneController.makeUpdatedPreferences(update)
        sceneController.beginPreferencePersistence()
        state = sceneController.state

        let savedPreferences = onPreferencesChanged?(nextPreferences)
        apply(sceneController.completePreferencePersistence(
            persistedPreferences: savedPreferences,
            fallbackPreferences: nextPreferences
        ))
        if previousAppearanceMode != state.preferences.appearance.mode {
            onAppearanceModeChanged?()
        }
    }

    func requestAccessibilityPermission() {
        onAccessibilityPermissionRequested?()
    }

    func persistDirectPasteToTarget(_ isOn: Bool) {
        if isOn, !state.accessibilityPermissionState.isTrusted {
            requestAccessibilityPermission()
        }

        persist { $0.shortcuts.pasteDirectlyToTarget = isOn }
    }

    func addIgnoredApplications(at urls: [URL]) {
        let identifiers = urls.compactMap(IgnoredApplicationRuleResolver.ruleIdentifier(forApplicationAt:))
        guard !identifiers.isEmpty else { return }

        persist { preferences in
            var nextIdentifiers = preferences.ignoreList.ignoredAppIdentifiers
            for identifier in identifiers where !nextIdentifiers.contains(where: { $0.caseInsensitiveCompare(identifier) == .orderedSame }) {
                nextIdentifiers.append(identifier)
            }
            preferences.ignoreList.ignoredAppIdentifiers = nextIdentifiers
        }
    }

    func removeIgnoredApplication(identifier: String) {
        persist { preferences in
            preferences.ignoreList.ignoredAppIdentifiers.removeAll {
                $0.caseInsensitiveCompare(identifier) == .orderedSame
            }
        }
    }

    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        switch state.preferences.appearance.mode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return systemColorScheme
        }
    }

    func preferencesTheme(fallbackAppearance: NSAppearance?) -> ClipDockPreferencesTheme {
        ClipDockTheme.current(for: forcedAppearance ?? fallbackAppearance).preferences
    }

    private func apply(_ update: PreferencesSceneUpdate) {
        state = update.state
        if update.shouldScheduleDeferredRender {
            scheduleDeferredRender()
        }
    }

    private func scheduleDeferredRender() {
        guard !pendingDeferredRender else { return }
        pendingDeferredRender = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingDeferredRender = false
            self.apply(self.sceneController.consumeDeferredRenderIfNeeded())
        }
    }

    private func sceneSection(for section: PreferenceSection) -> PreferencesSceneSection {
        switch section {
        case .general:
            return .general
        case .appearance:
            return .general
        case .history:
            return .general
        case .shortcuts:
            return .shortcuts
        case .rules:
            return .rules
        case .about:
            return .about
        }
    }

    private func preferenceSection(for section: PreferencesSceneSection) -> PreferenceSection {
        switch section {
        case .general:
            return .general
        case .appearance:
            return .general
        case .history:
            return .general
        case .shortcuts:
            return .shortcuts
        case .rules:
            return .rules
        case .about:
            return .about
        }
    }
}

struct PreferencesShellSmokeSnapshot: Equatable {
    let selectedSection: PreferenceSection
    let splitItemCount: Int
    let sidebarMinimumThickness: CGFloat
    let sidebarMaximumThickness: CGFloat
    let sidebarCanCollapse: Bool
    let sidebarCanCollapseFromWindowResize: Bool
    let sidebarFrameWidth: CGFloat
    let contentFrameWidth: CGFloat
    let visibleSidebarSectionCount: Int
    let windowHasToolbar: Bool
    let windowUsesUnifiedToolbarStyle: Bool
    let windowUsesFullSizeContentView: Bool
    let windowTitleIsHidden: Bool
    let windowTitlebarAppearsTransparent: Bool
    let toolbarShowsBaselineSeparator: Bool
    let toolbarUsesSidebarTrackingSeparator: Bool
    let toolbarHasNavigationItem: Bool
    let windowBackgroundMatchesTheme: Bool
    let splitBackgroundMatchesTheme: Bool
    let sidebarBackgroundMatchesTheme: Bool
    let contentBackgroundMatchesTheme: Bool
    let sidebarBackgroundWhiteComponent: CGFloat
    let sidebarHostingAppearanceIsDark: Bool
    let contentHostingAppearanceIsDark: Bool
}

@MainActor
private final class PreferencesSplitViewController: NSSplitViewController {
    private enum Layout {
        static let sidebarPreferredWidth: CGFloat = 252
        static let sidebarMinimumWidth: CGFloat = 220
        static let sidebarMaximumWidth: CGFloat = 264
        static let contentMinimumWidth: CGFloat = 520
    }

    private let model: PreferencesSwiftUIViewModel
    private let sidebarController: NSHostingController<PreferencesSidebarList>
    private let contentController: NSHostingController<PreferencesContent>
    private var didApplyInitialSidebarWidth = false
    private var pendingDeferredThemeRefresh = false

    init(model: PreferencesSwiftUIViewModel) {
        self.model = model
        self.sidebarController = NSHostingController(rootView: PreferencesSidebarList(model: model))
        self.contentController = NSHostingController(rootView: PreferencesContent(model: model))

        super.init(nibName: nil, bundle: nil)

        sidebarController.preferredContentSize = NSSize(
            width: Layout.sidebarPreferredWidth,
            height: 600
        )
        contentController.preferredContentSize = NSSize(
            width: Layout.contentMinimumWidth,
            height: 600
        )

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = Layout.sidebarMinimumWidth
        sidebarItem.maximumThickness = Layout.sidebarMaximumWidth
        sidebarItem.canCollapse = false
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.holdingPriority = .defaultHigh

        let contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.minimumThickness = Layout.contentMinimumWidth
        contentItem.canCollapse = false

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        applyTheme()
        scheduleDeferredThemeRefresh()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        applyTheme()
        scheduleDeferredThemeRefresh()
        guard !didApplyInitialSidebarWidth, splitViewItems.count > 1 else { return }
        didApplyInitialSidebarWidth = true
        splitView.setPosition(Layout.sidebarPreferredWidth, ofDividerAt: 0)
    }

    func applyTheme() {
        let preferencesTheme = model.preferencesTheme(fallbackAppearance: view.effectiveAppearance)
        let forcedAppearance = model.forcedAppearance
        view.wantsLayer = true
        splitView.wantsLayer = true
        sidebarController.view.wantsLayer = true
        contentController.view.wantsLayer = true
        sidebarController.view.appearance = forcedAppearance
        contentController.view.appearance = forcedAppearance
        view.layer?.backgroundColor = preferencesTheme.contentBackgroundColor.cgColor
        splitView.layer?.backgroundColor = preferencesTheme.contentBackgroundColor.cgColor
        sidebarController.view.layer?.backgroundColor = preferencesTheme.sidebarBackgroundColor.cgColor
        contentController.view.layer?.backgroundColor = preferencesTheme.contentBackgroundColor.cgColor
        view.window?.backgroundColor = preferencesTheme.windowBackgroundColor
        configureScrollViews(
            in: sidebarController.view,
            backgroundColor: preferencesTheme.sidebarBackgroundColor,
            overridesVisualEffects: true
        )
        configureScrollViews(
            in: contentController.view,
            backgroundColor: preferencesTheme.contentBackgroundColor,
            overridesVisualEffects: false
        )
    }

    private func scheduleDeferredThemeRefresh() {
        guard !pendingDeferredThemeRefresh else { return }
        pendingDeferredThemeRefresh = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingDeferredThemeRefresh = false
            self.applyTheme()
        }
    }

    func smokeSnapshot(
        selectedSection: PreferenceSection,
        visibleSidebarSectionCount: Int,
        window: NSWindow?
    ) -> PreferencesShellSmokeSnapshot? {
        guard let sidebarItem = splitViewItems.first,
              splitViewItems.count > 1 else {
            return nil
        }

        let toolbar = window?.toolbar
        let preferencesTheme = model.preferencesTheme(fallbackAppearance: window?.effectiveAppearance)
        let windowBackground = window?.backgroundColor
        let splitBackground = view.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        let sidebarBackground = sidebarController.view.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        let contentBackground = contentController.view.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        return PreferencesShellSmokeSnapshot(
            selectedSection: selectedSection,
            splitItemCount: splitViewItems.count,
            sidebarMinimumThickness: sidebarItem.minimumThickness,
            sidebarMaximumThickness: sidebarItem.maximumThickness,
            sidebarCanCollapse: sidebarItem.canCollapse,
            sidebarCanCollapseFromWindowResize: sidebarItem.canCollapseFromWindowResize,
            sidebarFrameWidth: sidebarController.view.frame.width,
            contentFrameWidth: contentController.view.frame.width,
            visibleSidebarSectionCount: visibleSidebarSectionCount,
            windowHasToolbar: toolbar != nil,
            windowUsesUnifiedToolbarStyle: window?.toolbarStyle == .unified,
            windowUsesFullSizeContentView: window?.styleMask.contains(.fullSizeContentView) == true,
            windowTitleIsHidden: window?.titleVisibility == .hidden,
            windowTitlebarAppearsTransparent: window?.titlebarAppearsTransparent == true,
            toolbarShowsBaselineSeparator: toolbar?.showsBaselineSeparator == true,
            toolbarUsesSidebarTrackingSeparator: toolbar?.items.contains {
                $0.itemIdentifier == .sidebarTrackingSeparator
            } == true,
            toolbarHasNavigationItem: toolbar?.items.contains {
                $0.itemIdentifier.rawValue == "ClipDock.Preferences.Toolbar.Navigation"
            } == true,
            windowBackgroundMatchesTheme: preferenceColorsMatch(windowBackground, preferencesTheme.windowBackgroundColor),
            splitBackgroundMatchesTheme: preferenceColorsMatch(splitBackground, preferencesTheme.contentBackgroundColor),
            sidebarBackgroundMatchesTheme: preferenceColorsMatch(sidebarBackground, preferencesTheme.sidebarBackgroundColor),
            contentBackgroundMatchesTheme: preferenceColorsMatch(contentBackground, preferencesTheme.contentBackgroundColor),
            sidebarBackgroundWhiteComponent: preferenceWhiteComponent(sidebarBackground),
            sidebarHostingAppearanceIsDark: ClipDockTheme.isDark(sidebarController.view.effectiveAppearance),
            contentHostingAppearanceIsDark: ClipDockTheme.isDark(contentController.view.effectiveAppearance)
        )
    }

    private func configureScrollViews(
        in view: NSView,
        backgroundColor: NSColor,
        overridesVisualEffects: Bool
    ) {
        if let scrollView = view as? NSScrollView {
            scrollView.drawsBackground = false
            scrollView.backgroundColor = backgroundColor
            scrollView.contentView.drawsBackground = false
            scrollView.contentView.backgroundColor = backgroundColor
        }

        if let tableView = view as? NSTableView {
            tableView.backgroundColor = backgroundColor
            tableView.enclosingScrollView?.drawsBackground = false
            tableView.enclosingScrollView?.backgroundColor = backgroundColor
        }

        if overridesVisualEffects, let visualEffectView = view as? NSVisualEffectView {
            visualEffectView.state = .inactive
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.backgroundColor = backgroundColor.cgColor
        }

        view.subviews.forEach {
            configureScrollViews(
                in: $0,
                backgroundColor: backgroundColor,
                overridesVisualEffects: overridesVisualEffects
            )
        }
    }
}

@MainActor
private struct PreferencesThemeValues {
    let palette: ClipDockPreferencesTheme

    init(colorScheme: ColorScheme) {
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        self.palette = ClipDockTheme.current(for: appearance).preferences
    }

    var windowBackground: Color { Color(nsColor: palette.windowBackgroundColor) }
    var contentBackground: Color { Color(nsColor: palette.contentBackgroundColor) }
    var sidebarBackground: Color { Color(nsColor: palette.sidebarBackgroundColor) }
    var cardBackground: Color { Color(nsColor: palette.cardBackgroundColor) }
    var cardBorder: Color { Color(nsColor: palette.cardBorderColor) }
    var primaryText: Color { Color(nsColor: palette.primaryTextColor) }
    var secondaryText: Color { Color(nsColor: palette.secondaryTextColor) }
    var separator: Color { Color(nsColor: palette.separatorColor) }
    var controlBackground: Color { Color(nsColor: palette.controlBackgroundColor) }
    var navigationText: Color { Color(nsColor: palette.navigationTextColor) }
}

private func preferenceColorsMatch(_ lhs: NSColor?, _ rhs: NSColor, tolerance: CGFloat = 0.01) -> Bool {
    guard let lhs = lhs?.usingColorSpace(.sRGB),
          let rhs = rhs.usingColorSpace(.sRGB) else {
        return false
    }

    return abs(lhs.redComponent - rhs.redComponent) <= tolerance
        && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
        && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
        && abs(lhs.alphaComponent - rhs.alphaComponent) <= tolerance
}

private func preferenceWhiteComponent(_ color: NSColor?) -> CGFloat {
    guard let color = color?.usingColorSpace(.sRGB) else { return 1 }
    return max(color.redComponent, color.greenComponent, color.blueComponent)
}

private struct PreferencesSidebarList: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel
    @Environment(\.colorScheme) private var colorScheme

    private enum Layout {
        static let topInset: CGFloat = 16
    }

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: effectiveColorScheme)
    }

    private var effectiveColorScheme: ColorScheme {
        model.resolvedColorScheme(systemColorScheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(PreferenceSection.allCases, id: \.self) { section in
                    PreferenceSidebarButton(
                        section: section,
                        isSelected: model.selectedSection == section,
                        colors: colors
                    ) {
                        model.selectSection(section)
                    }
                    .tag(section)
                }
            }
            .padding(.top, Layout.topInset)
            .padding(.horizontal, 12)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .frame(
            minWidth: 220,
            idealWidth: 252,
            maxWidth: 264,
            maxHeight: .infinity
        )
        .background(colors.sidebarBackground.ignoresSafeArea())
        .environment(\.colorScheme, effectiveColorScheme)
    }
}

private struct PreferenceSidebarButton: View {
    let section: PreferenceSection
    let isSelected: Bool
    let colors: PreferencesThemeValues
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)

                Text(section.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : colors.navigationText)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}

private struct PreferenceMiniAppIconView: View {
    var body: some View {
        Group {
            if let image = aboutAppIconImage() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
            } else {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 34, height: 34)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
        )
    }
}

private struct PreferencesContent: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: effectiveColorScheme)
    }

    private var effectiveColorScheme: ColorScheme {
        model.resolvedColorScheme(systemColorScheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreferencePageHeader(section: model.selectedSection)
                pageContent
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.top, 16)
            .padding(.horizontal, 52)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scrollContentBackground(.hidden)
        .background(colors.contentBackground.ignoresSafeArea())
        .environment(\.colorScheme, effectiveColorScheme)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch model.selectedSection {
        case .general, .appearance:
            PreferenceGeneralSection(model: model)
        case .history:
            PreferenceGeneralSection(model: model)
        case .shortcuts:
            PreferenceShortcutSection(model: model)
        case .rules:
            PreferencePrivacySection(model: model)
        case .about:
            PreferenceAboutSection()
        }
    }
}

private struct PreferencePageHeader: View {
    let section: PreferenceSection
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    var body: some View {
        Group {
            if section == .rules {
                Text(section.title)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(colors.primaryText)
                        Text(section.subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(colors.secondaryText)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 16)

                    Image(systemName: section.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.6)
                        )
                }
            }
        }
    }
}

private struct PreferenceGeneralSection: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PreferenceSectionGroup(title: "基础") {
                PreferenceRow(title: "登录时打开", detail: model.state.launchAtLoginState.detail) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.launchAtLoginState.isOn },
                            set: { isOn in model.persist { $0.general.launchAtLogin = isOn } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!model.state.launchAtLoginState.canChange)
                }
                PreferenceDivider()
                PreferenceRow(title: "显示在菜单栏上", detail: "保留状态栏入口与快速菜单") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.preferences.general.showMenuBarItem },
                            set: { isOn in model.persist { $0.general.showMenuBarItem = isOn } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            PreferenceSectionGroup(title: "粘贴项目") {
                PreferenceRow(
                    title: "直接粘贴到目标",
                    detail: model.state.accessibilityPermissionState.isTrusted
                        ? "取用条目后自动粘贴到当前应用"
                        : "需要在系统设置的辅助功能中允许 ClipDock"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.preferences.shortcuts.pasteDirectlyToTarget },
                            set: { isOn in model.persistDirectPasteToTarget(isOn) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                PreferenceDivider()
                PreferenceRow(title: "始终以纯文本粘贴", detail: "文本、富文本、链接与颜色取用时写入纯文本") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.preferences.shortcuts.alwaysPasteAsPlainText },
                            set: { isOn in model.persist { $0.shortcuts.alwaysPasteAsPlainText = isOn } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            PreferenceSectionGroup(title: "外观") {
                PreferenceRow(title: "显示模式", detail: "控制面板、设置与预览") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.state.preferences.appearance.mode },
                            set: { mode in model.persist { $0.appearance.mode = mode } }
                        )
                    ) {
                        Text("系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                PreferenceDivider()
                PreferenceRow(title: "预览浮层", detail: "按空格预览选中项目") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.preferences.appearance.previewPopoverEnabled },
                            set: { isOn in model.persist { $0.appearance.previewPopoverEnabled = isOn } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            PreferenceSectionGroup(title: "保留策略") {
                PreferenceRow(
                    title: "保留时长",
                    detail: retentionLabel(days: model.state.preferences.history.retentionDays)
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.state.preferences.history.retentionDays },
                            set: { days in model.persist { $0.history.retentionDays = days } }
                        )
                    ) {
                        Text("天").tag(Int64(1))
                        Text("周").tag(Int64(7))
                        Text("月").tag(Int64(30))
                        Text("年").tag(Int64(365))
                        Text("永久").tag(Int64.max)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
            }
        }
    }
}

private struct PreferenceShortcutSection: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PreferenceSectionGroup(title: "全局操作") {
                PreferenceRow(title: "打开剪贴板", detail: "从任意应用呼出底部面板") {
                    ShortcutRecorderRepresentable(
                        shortcut: model.state.preferences.shortcuts.openPanel
                    ) { shortcut in
                        model.persist { $0.shortcuts.openPanel = shortcut }
                    }
                    .frame(width: 144, height: 32)
                }
                PreferenceDivider()
                PreferenceRow(title: "快速取用条目", detail: "按住 Command 显示编号，按对应数字复制") {
                    PreferenceShortcutPill("⌘ 1...9")
                }
            }

            PreferenceSectionGroup(title: "面板内操作") {
                PreferenceRow(title: "搜索当前内容", detail: "展开并聚焦搜索框") {
                    PreferenceShortcutPill("⌘ F")
                }
                PreferenceDivider()
                PreferenceRow(title: "预览选中条目", detail: "展开或关闭临时预览浮层") {
                    PreferenceShortcutPill("Space")
                }
            }
        }
    }
}

private struct PreferencePrivacySection: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PreferenceSectionGroup(title: "系统权限") {
                PrivacySettingRow(title: "窗口标题采集", detail: model.state.accessibilityPermissionState.detail) {
                    Button(model.state.accessibilityPermissionState.actionTitle) {
                        model.requestAccessibilityPermission()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.state.accessibilityPermissionState.canOpenSettings)
                }
            }

            PreferenceSectionGroup(title: "链接预览") {
                PrivacySettingRow(title: "网页完整预览", detail: "按空格时加载真实网页") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.preferences.linkPreview.webPreviewEnabled },
                            set: { isOn in model.persist { $0.linkPreview.webPreviewEnabled = isOn } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("忽略应用程序")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.primaryText)
                    Text("不要保存从以下应用程序或窗口复制的内容。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(colors.secondaryText)
                }
                .padding(.leading, 4)

                IgnoredApplicationsPicker(model: model)
            }
        }
    }
}

private struct IgnoredApplicationsPicker: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel
    @State private var selectedIdentifier: String?
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    private var descriptors: [IgnoredApplicationDescriptor] {
        model.state.preferences.ignoreList.ignoredAppIdentifiers.map {
            IgnoredApplicationDescriptor(ruleIdentifier: $0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if descriptors.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("未添加应用程序")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.primaryText)
                        Text("点击 + 选择需要忽略的应用。")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.secondaryText)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 15)
                .frame(minHeight: 70)
            } else {
                ForEach(Array(descriptors.enumerated()), id: \.element.id) { index, descriptor in
                    IgnoredApplicationRow(
                        descriptor: descriptor,
                        isSelected: selectedIdentifier == descriptor.id
                    ) {
                        selectedIdentifier = descriptor.id
                    }

                    if index < descriptors.count - 1 {
                        PreferenceDivider()
                    }
                }
            }

            Divider()

            HStack(spacing: 0) {
                IgnoredApplicationPickerToolbarButton(
                    symbolName: "plus",
                    help: "添加应用程序"
                ) {
                    addApplications()
                }

                Divider()
                    .frame(height: 20)

                IgnoredApplicationPickerToolbarButton(
                    symbolName: "minus",
                    help: "移除选中的应用程序",
                    isDisabled: selectedIdentifier == nil
                ) {
                    removeSelectedApplication()
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(colors.secondaryText)
            .background(colors.controlBackground)
        }
        .background(
            colors.cardBackground,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(colors.cardBorder, lineWidth: 0.6)
        )
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.title = "选择要忽略的应用程序"
        panel.message = "选择后会自动读取应用标识，用于忽略该应用复制的内容。"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK else { return }
        model.addIgnoredApplications(at: panel.urls)
        selectedIdentifier = panel.urls
            .compactMap(IgnoredApplicationRuleResolver.ruleIdentifier(forApplicationAt:))
            .last
    }

    private func removeSelectedApplication() {
        guard let selectedIdentifier else { return }
        model.removeIgnoredApplication(identifier: selectedIdentifier)
        self.selectedIdentifier = nil
    }
}

private struct IgnoredApplicationPickerToolbarButton: View {
    let symbolName: String
    let help: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(width: 52, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }
}

private struct IgnoredApplicationRow: View {
    let descriptor: IgnoredApplicationDescriptor
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(nsImage: descriptor.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                    Text(descriptor.detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.13))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PrivacySettingRow<Accessory: View>: View {
    let title: String
    let detail: String
    let accessory: Accessory
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    init(title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
        .frame(minHeight: 70)
    }
}

private struct PrivacyRuleFieldRow<Accessory: View>: View {
    let title: String
    let detail: String
    let accessory: Accessory
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    init(title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 164, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            accessory
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(minHeight: 72)
    }
}

struct IgnoredApplicationRuleResolver {
    static func ruleIdentifier(forApplicationAt url: URL) -> String? {
        let bundle = Bundle(url: url)

        if let bundleIdentifier = bundle?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        let displayName = displayName(forApplicationAt: url, bundle: bundle)
        if !displayName.isEmpty {
            return displayName
        }

        let fallbackName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackName.isEmpty ? nil : fallbackName
    }

    static func displayName(forApplicationAt url: URL, bundle: Bundle?) -> String {
        let infoDictionary = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary
        let candidate = (infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct IgnoredApplicationDescriptor: Identifiable {
    let id: String
    let displayName: String
    let detail: String
    let icon: NSImage

    init(ruleIdentifier: String) {
        let trimmedIdentifier = ruleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let applicationURL = Self.applicationURL(for: trimmedIdentifier)
        let bundle = applicationURL.flatMap(Bundle.init(url:))
        let resolvedName = applicationURL.map {
            IgnoredApplicationRuleResolver.displayName(forApplicationAt: $0, bundle: bundle)
        }
        let displayName = resolvedName?.isEmpty == false
            ? resolvedName ?? trimmedIdentifier
            : trimmedIdentifier

        self.id = trimmedIdentifier
        self.displayName = displayName
        self.detail = bundle?.bundleIdentifier ?? trimmedIdentifier
        self.icon = applicationURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: displayName)
            ?? NSImage(size: NSSize(width: 32, height: 32))
    }

    private static func applicationURL(for identifier: String) -> URL? {
        if identifier.hasSuffix(".app") || identifier.contains("/") {
            let url = URL(fileURLWithPath: NSString(string: identifier).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }
}

private struct PreferenceAboutSection: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PreferenceSectionGroup {
                HStack(spacing: 16) {
                    PreferenceAppIconView()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(aboutDisplayName())
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(colors.primaryText)
                        Text("本地剪贴坞")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.secondaryText)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }

            PreferenceSectionGroup(title: "应用信息") {
                PreferenceRow(title: "版本", detail: "当前应用版本") {
                    PreferenceValuePill(aboutVersionText())
                }
            }
        }
    }
}

private struct PreferenceAppIconView: View {
    var body: some View {
        Group {
            if let image = aboutAppIconImage() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 58, height: 58)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 0.7)
        )
    }
}

private struct PreferenceSectionGroup<Content: View>: View {
    let title: String?
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(colors.secondaryText)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                colors.cardBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(colors.cardBorder, lineWidth: 0.6)
            )
        }
    }
}

private struct PreferenceRow<Accessory: View>: View {
    let title: String
    let detail: String
    let accessory: Accessory
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    init(title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .frame(minHeight: 58)
    }
}

private struct PreferenceDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    var body: some View {
        Rectangle()
            .fill(colors.separator)
            .frame(height: 0.5)
            .padding(.horizontal, 22)
    }
}

private struct PreferenceNumberStepper: View {
    let value: Binding<Int>
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(value.wrappedValue)\(suffix)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(colors.primaryText)
                .frame(width: suffix.isEmpty ? 66 : 82, alignment: .trailing)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct PreferenceShortcutPill: View {
    let shortcut: String
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    init(_ shortcut: String) {
        self.shortcut = shortcut
    }

    var body: some View {
        Text(shortcut)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(colors.primaryText)
            .frame(minWidth: 92)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(colors.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(colors.separator, lineWidth: 0.6)
            )
    }
}

private struct PreferenceValuePill: View {
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(colors.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(colors.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(colors.separator, lineWidth: 0.6)
            )
    }
}

private struct RuleListField: View {
    let values: [String]
    let placeholder: String
    let onCommit: ([String]) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(values: [String], placeholder: String, onCommit: @escaping ([String]) -> Void) {
        self.values = values
        self.placeholder = placeholder
        self.onCommit = onCommit
        _text = State(initialValue: joinedRuleList(values))
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))
            .frame(width: 300)
            .focused($isFocused)
            .onSubmit(commit)
            .onDisappear(perform: commit)
            .onChange(of: isFocused) { focused in
                if !focused {
                    commit()
                }
            }
            .onChange(of: values) { nextValues in
                let nextText = joinedRuleList(nextValues)
                if nextText != text, !isFocused {
                    text = nextText
                }
            }
    }

    private func commit() {
        onCommit(splitRuleList(text))
    }
}

private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    let shortcut: RustKeyboardShortcut
    let onRecord: (RustKeyboardShortcut) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var colors: PreferencesThemeValues {
        PreferencesThemeValues(colorScheme: colorScheme)
    }

    init(shortcut: RustKeyboardShortcut, onRecord: @escaping (RustKeyboardShortcut) -> Void) {
        self.shortcut = shortcut
        self.onRecord = onRecord
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(shortcut: shortcut)
        button.normalTextColor = colors.palette.primaryTextColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
        button.layer?.borderWidth = 0.5
        button.layer?.backgroundColor = colors.palette.controlBackgroundColor.cgColor
        button.layer?.borderColor = colors.palette.separatorColor.cgColor
        button.onShortcutRecorded = onRecord
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.normalTextColor = colors.palette.primaryTextColor
        nsView.layer?.backgroundColor = colors.palette.controlBackgroundColor.cgColor
        nsView.layer?.borderColor = colors.palette.separatorColor.cgColor
        nsView.onShortcutRecorded = onRecord
        nsView.updateShortcut(shortcut)
    }
}

private func retentionLabel(days: Int64) -> String {
    switch days {
    case ..<7:
        return "按天保留"
    case 7..<30:
        return "按周保留"
    case 30..<365:
        return "按月保留"
    case 365..<Int64.max:
        return "按年保留"
    default:
        return "永久保留"
    }
}

private func joinedRuleList(_ values: [String]) -> String {
    values.joined(separator: ", ")
}

private func splitRuleList(_ value: String) -> [String] {
    value
        .components(separatedBy: CharacterSet(charactersIn: ",，;；\n"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func aboutDisplayName() -> String {
    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
       !name.isEmpty {
        return name
    }

    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
       !name.isEmpty {
        return name
    }

    return "ClipDock"
}

private func aboutVersionText() -> String {
    let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    let buildVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    return "\(shortVersion) (\(buildVersion))"
}

private func aboutAppIconImage() -> NSImage? {
    AppIconDisplayImageProvider.image(accessibilityDescription: aboutDisplayName())
}

@MainActor
private final class LegacyPreferencesWindowController: NSWindowController {
    private enum Layout {
        static let defaultWindowSize = NSSize(width: 920, height: 700)
        static let minimumWindowSize = NSSize(width: 820, height: 600)
        static let sidebarWidth: CGFloat = 264
        static let contentInset: CGFloat = 36
        static let contentMaxWidth: CGFloat = 640
        static let sidebarInset: CGFloat = 16
        static let sidebarTopInset: CGFloat = 74
        static let sidebarBottomInset: CGFloat = 18
        static let navigationRowHeight: CGFloat = 38
        static let rowHeight: CGFloat = 62
        static let rowHorizontalInset: CGFloat = 24
        static let cardCornerRadius: CGFloat = 18
        static let windowCornerRadius: CGFloat = 24
        static var pageTitleFont: NSFont {
            NSFont.systemFont(ofSize: 28, weight: .semibold)
        }
        static var sectionTitleFont: NSFont {
            NSFont.systemFont(ofSize: 13, weight: .medium)
        }
        static var rowTitleFont: NSFont {
            NSFont.systemFont(ofSize: 14.5, weight: .medium)
        }
        static var rowDetailFont: NSFont {
            NSFont.systemFont(ofSize: 12.5, weight: .regular)
        }
        static var navigationFont: NSFont {
            NSFont.systemFont(ofSize: 13, weight: .medium)
        }
    }

    private let rootView = NSView()
    private let sidebarStack = NSStackView()
    private let contentView = NSView()
    private let sceneController = PreferencesSceneController()
    private weak var sidebarView: NSView?
    private var navigationButtons: [PreferenceSection: NSButton] = [:]
    private var stepperBindings: [StepperTextBinding] = []
    private var textInputBindings: [TextInputBinding] = []
    private var pendingDeferredRender = false

    var onPreferencesChanged: ((RustPreferencesDocument) -> RustPreferencesDocument?)?
    var onAccessibilityPermissionRequested: (() -> Void)?
    private var theme: ClipDockThemePalette {
        ClipDockTheme.current(for: window)
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "偏好设置"
        window.minSize = Layout.minimumWindowSize
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = ClipDockTheme.current(for: window).preferences.windowBackgroundColor
        window.isOpaque = true

        super.init(window: window)

        configureWindow(window)
        renderSelectedSection()
        updateNavigationSelection()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showPreferences() {
        guard let window else { return }

        if !window.isVisible {
            window.center()
        }

        applyTheme()
        renderSelectedSection()
        updateNavigationSelection()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updatePreferences(_ preferences: RustPreferencesDocument) {
        applySceneUpdate(sceneController.updatePreferences(preferences))
    }

    func showSection(_ section: PreferenceSection) {
        selectSection(section)
    }

    func updateLaunchAtLoginState(_ state: LaunchAtLoginState) {
        applySceneUpdate(sceneController.updateLaunchAtLoginState(state))
    }

    func updateAccessibilityPermissionState(_ state: AccessibilityPermissionState) {
        applySceneUpdate(sceneController.updateAccessibilityPermissionState(state))
    }

    private func configureWindow(_ window: NSWindow) {
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = Layout.windowCornerRadius
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true
        rootView.layer?.borderWidth = 0.6
        window.contentView = rootView

        let sidebar = makeSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true

        rootView.addSubview(sidebar)
        rootView.addSubview(contentView)
        applyTheme()

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth),

            contentView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 1),
            contentView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSView()
        sidebarView = sidebar
        sidebar.wantsLayer = true
        sidebar.layer?.cornerRadius = 0
        sidebar.layer?.masksToBounds = true

        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .width
        sidebarStack.spacing = 6
        sidebarStack.edgeInsets = NSEdgeInsets(
            top: Layout.sidebarTopInset,
            left: Layout.sidebarInset,
            bottom: Layout.sidebarBottomInset,
            right: Layout.sidebarInset
        )
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false

        PreferenceSection.allCases.forEach { section in
            let button = makeNavigationButton(for: section)
            navigationButtons[section] = button
            sidebarStack.addArrangedSubview(button)

            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth - Layout.sidebarInset * 2),
                button.heightAnchor.constraint(equalToConstant: Layout.navigationRowHeight)
            ])
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        sidebarStack.addArrangedSubview(spacer)

        sidebar.addSubview(sidebarStack)

        NSLayoutConstraint.activate([
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])

        return sidebar
    }

    private func applyTheme() {
        let preferencesTheme = theme.preferences
        window?.backgroundColor = preferencesTheme.windowBackgroundColor
        rootView.layer?.backgroundColor = preferencesTheme.contentBackgroundColor.cgColor
        rootView.layer?.borderColor = preferencesTheme.borderColor.cgColor
        contentView.layer?.backgroundColor = preferencesTheme.contentBackgroundColor.cgColor
        sidebarView?.layer?.backgroundColor = preferencesTheme.sidebarBackgroundColor.cgColor
    }

    private func makeNavigationButton(for section: PreferenceSection) -> NSButton {
        let button = PreferenceNavigationButton(title: section.title, target: nil, action: nil)
        button.setButtonType(.toggle)
        button.bezelStyle = .rounded
        button.isBordered = false
        button.alignment = .left
        button.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.font = Layout.navigationFont
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.cornerCurve = .continuous
        button.contentTintColor = NSColor.systemBlue.withAlphaComponent(0.72)
        button.tag = section.rawValue
        button.translatesAutoresizingMaskIntoConstraints = false
        button.onPress = { [weak self] in
            self?.selectSection(section)
        }
        return button
    }

    private func selectSection(_ section: PreferenceSection) {
        applySceneUpdate(sceneController.selectSection(sceneSection(for: section)))
    }

    private func updateNavigationSelection() {
        navigationButtons.forEach { section, button in
            let isSelected = section == selectedSection
            button.state = isSelected ? .on : .off
            button.layer?.backgroundColor = isSelected
                ? theme.preferences.navigationSelectedBackgroundColor.cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = NSColor.systemBlue.withAlphaComponent(isSelected ? 0.92 : 0.72)
            button.attributedTitle = NSAttributedString(
                string: section.title,
                attributes: [
                    .font: Layout.navigationFont,
                    .foregroundColor: isSelected
                        ? theme.preferences.navigationSelectedTextColor
                        : theme.preferences.navigationTextColor
                ]
            )
        }
    }

    private func renderSelectedSection() {
        stepperBindings.removeAll()
        textInputBindings.removeAll()
        contentView.subviews.forEach { $0.removeFromSuperview() }

        let pageView = makePage(for: selectedSection)
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageView)

        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func makePage(for section: PreferenceSection) -> NSView {
        let sceneState = sceneController.state
        let preferences = sceneState.preferences
        let launchAtLoginState = sceneState.launchAtLoginState
        let accessibilityPermissionState = sceneState.accessibilityPermissionState

        switch section {
        case .general:
            return makeContentPage(
                title: section.title,
                subtitle: section.subtitle,
                sections: [
                    makeSection(title: nil, rows: [
                        makeSettingRow(
                            title: "登录时打开",
                            detail: launchAtLoginState.detail,
                            control: makeSwitch(
                                isOn: launchAtLoginState.isOn,
                                isEnabled: launchAtLoginState.canChange
                            ) { [weak self] isOn in
                                self?.persist { $0.general.launchAtLogin = isOn }
                            }
                        ),
                        makeSettingRow(
                            title: "显示在菜单栏上",
                            detail: "保留状态栏入口与快速菜单",
                            control: makeSwitch(isOn: preferences.general.showMenuBarItem) { [weak self] isOn in
                                self?.persist { $0.general.showMenuBarItem = isOn }
                            }
                        )
                    ]),
                    makeSection(title: "粘贴项目", rows: [
                        makeSettingRow(
                            title: "直接粘贴到目标",
                            detail: accessibilityPermissionState.isTrusted
                                ? "取用条目后自动粘贴到当前应用"
                                : "需要在系统设置的辅助功能中允许 ClipDock",
                            control: makeSwitch(
                                isOn: preferences.shortcuts.pasteDirectlyToTarget
                            ) { [weak self] isOn in
                                self?.persistDirectPasteToTarget(isOn)
                            }
                        ),
                        makeSettingRow(
                            title: "始终以纯文本粘贴",
                            detail: "文本、富文本、链接与颜色取用时写入纯文本",
                            control: makeSwitch(
                                isOn: preferences.shortcuts.alwaysPasteAsPlainText
                            ) { [weak self] isOn in
                                self?.persist { $0.shortcuts.alwaysPasteAsPlainText = isOn }
                            }
                        )
                    ]),
                    makeSection(title: "保留策略", rows: [
                        makeSettingRow(
                            title: "保留时长",
                            detail: retentionLabel(days: preferences.history.retentionDays),
                            control: makeSegmentedControl(
                                labels: ["天", "周", "月", "年", "永久"],
                                selected: retentionIndex(days: preferences.history.retentionDays)
                            ) { [weak self] selected in
                                self?.persist { $0.history.retentionDays = self?.retentionDays(for: selected) ?? 30 }
                            }
                        )
                    ])
                ]
            )
        case .appearance:
            return makeContentPage(
                title: section.title,
                subtitle: section.subtitle,
                sections: [
                    makeSection(title: nil, rows: [
                        makeSettingRow(
                            title: "显示模式",
                            detail: "控制面板、设置与预览",
                            control: makeAppearanceModeControl(selectedMode: preferences.appearance.mode) { [weak self] mode in
                                self?.persist { $0.appearance.mode = mode }
                            }
                        ),
                        makeSettingRow(
                            title: "预览浮层",
                            detail: "按空格预览选中项目",
                            control: makeSwitch(isOn: preferences.appearance.previewPopoverEnabled) { [weak self] isOn in
                                self?.persist { $0.appearance.previewPopoverEnabled = isOn }
                            }
                        )
                    ])
                ]
            )
        case .history:
            return makeContentPage(
                title: PreferenceSection.general.title,
                subtitle: PreferenceSection.general.subtitle,
                sections: [
                    makeSection(title: "保留策略", rows: [
                        makeSettingRow(
                            title: "保留时长",
                            detail: retentionLabel(days: preferences.history.retentionDays),
                            control: makeSegmentedControl(
                                labels: ["天", "周", "月", "年", "永久"],
                                selected: retentionIndex(days: preferences.history.retentionDays)
                            ) { [weak self] selected in
                                self?.persist { $0.history.retentionDays = self?.retentionDays(for: selected) ?? 30 }
                            }
                        )
                    ])
                ]
            )
        case .shortcuts:
            return makeContentPage(
                title: section.title,
                subtitle: section.subtitle,
                sections: [
                    makeSection(title: "全局操作", rows: [
                        makeShortcutRow(
                            title: "打开剪贴板",
                            detail: "从任意应用呼出底部面板",
                            shortcut: preferences.shortcuts.openPanel
                        ),
                        makeShortcutRow(
                            title: "快速取用条目",
                            detail: "按住 Command 显示编号，按对应数字复制",
                            shortcut: "⌘ 1...9"
                        )
                    ]),
                    makeSection(title: "面板内操作", rows: [
                        makeShortcutRow(
                            title: "搜索当前内容",
                            detail: "展开并聚焦搜索框",
                            shortcut: "⌘ F"
                        ),
                        makeShortcutRow(
                            title: "预览选中条目",
                            detail: "展开或关闭临时预览浮层",
                            shortcut: "Space"
                        )
                    ])
                ]
            )
        case .rules:
            return makeContentPage(
                title: section.title,
                subtitle: section.subtitle,
                sections: [
                    makeSection(title: "系统权限", rows: [
                        makeSettingRow(
                            title: "窗口标题采集",
                            detail: accessibilityPermissionState.detail,
                            control: makeActionButton(
                                title: accessibilityPermissionState.actionTitle,
                                isEnabled: accessibilityPermissionState.canOpenSettings
                            ) { [weak self] in
                                self?.onAccessibilityPermissionRequested?()
                            }
                        )
                    ]),
                    makeSection(title: "链接预览", rows: [
                        makeSettingRow(
                            title: "网页完整预览",
                            detail: "按空格时加载真实网页",
                            control: makeSwitch(isOn: preferences.linkPreview.webPreviewEnabled) { [weak self] isOn in
                                self?.persist { $0.linkPreview.webPreviewEnabled = isOn }
                            }
                        )
                    ]),
                    makeSection(title: "应用", rows: [
                        makeIgnoredApplicationsPickerRow(preferences: preferences)
                    ])
                ]
            )
        case .about:
            return makeContentPage(
                title: section.title,
                subtitle: section.subtitle,
                sections: [
                    makeSection(title: nil, rows: [
                        makeSettingRow(
                            title: aboutDisplayName(),
                            detail: "版本 \(aboutVersionText())",
                            control: makeShortcutPill("SwiftUI")
                        )
                    ])
                ]
            )
        }
    }

    private func makeContentPage(title: String, subtitle: String, sections: [NSView]) -> NSView {
        let page = NSView()
        page.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 26
        stack.translatesAutoresizingMaskIntoConstraints = false

        let headingStack = NSStackView()
        headingStack.orientation = .vertical
        headingStack.alignment = .leading
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(title, font: Layout.pageTitleFont, color: theme.preferences.primaryTextColor)
        let subtitleLabel = makeLabel(subtitle, font: Layout.rowDetailFont, color: theme.preferences.secondaryTextColor)
        headingStack.addArrangedSubview(titleLabel)
        if !subtitle.isEmpty {
            headingStack.addArrangedSubview(subtitleLabel)
        }
        stack.addArrangedSubview(headingStack)
        headingStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        sections.forEach { sectionView in
            stack.addArrangedSubview(sectionView)
            sectionView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spacer)

        page.addSubview(stack)

        let contentWidthConstraint = stack.widthAnchor.constraint(
            equalTo: page.widthAnchor,
            constant: -Layout.contentInset * 2
        )
        contentWidthConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: Layout.contentInset),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -Layout.contentInset),
            contentWidthConstraint,
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: page.leadingAnchor, constant: Layout.contentInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor, constant: -Layout.contentInset),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.contentMaxWidth),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 450)
        ])

        return page
    }

    private func makeSection(title: String?, rows: [NSView]) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let title, !title.isEmpty {
            let titleContainer = NSView()
            titleContainer.translatesAutoresizingMaskIntoConstraints = false
            let titleLabel = makeLabel(title, font: Layout.sectionTitleFont, color: theme.preferences.secondaryTextColor)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleContainer.addSubview(titleLabel)
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
                titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor, constant: 1),
                titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleContainer.trailingAnchor)
            ])
            stack.addArrangedSubview(titleContainer)
        }

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = theme.preferences.cardBackgroundColor.cgColor
        card.layer?.cornerRadius = Layout.cardCornerRadius
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = theme.preferences.cardBorderColor.cgColor

        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        rows.enumerated().forEach { index, row in
            rowsStack.addArrangedSubview(row)
            if index < rows.count - 1 {
                rowsStack.addArrangedSubview(makeSeparator())
            }
        }

        card.addSubview(rowsStack)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: card.topAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeSettingRow(title: String, detail: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(title, font: Layout.rowTitleFont, color: theme.preferences.primaryTextColor)
        let detailLabel = makeLabel(detail, font: Layout.rowDetailFont, color: theme.preferences.secondaryTextColor)

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.required, for: .horizontal)

        let rowStack = NSStackView(views: [textStack, spacer, control])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 16
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(rowStack)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.rowHeight),
            rowStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Layout.rowHorizontalInset),
            rowStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Layout.rowHorizontalInset),
            rowStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
            rowStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -9)
        ])

        return row
    }

    private func makeShortcutRow(
        title: String,
        detail: String,
        shortcut: RustKeyboardShortcut
    ) -> NSView {
        let recorder = makeShortcutRecorder(shortcut) { [weak self] shortcut in
            self?.persist { $0.shortcuts.openPanel = shortcut }
        }
        return makeSettingRow(title: title, detail: detail, control: recorder)
    }

    private func makeShortcutRow(title: String, detail: String, shortcut: String) -> NSView {
        makeSettingRow(title: title, detail: detail, control: makeShortcutPill(shortcut))
    }

    private func makeShortcutPill(_ shortcut: String) -> NSView {
        let shortcutField = NSTextField(labelWithString: shortcut)
        shortcutField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        shortcutField.alignment = .center
        shortcutField.textColor = theme.preferences.primaryTextColor
        shortcutField.wantsLayer = true
        shortcutField.layer?.backgroundColor = theme.preferences.controlBackgroundColor.cgColor
        shortcutField.layer?.cornerRadius = 7
        shortcutField.layer?.cornerCurve = .continuous
        shortcutField.layer?.borderWidth = 0.4
        shortcutField.layer?.borderColor = theme.preferences.separatorColor.cgColor
        shortcutField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            shortcutField.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            shortcutField.heightAnchor.constraint(equalToConstant: 29)
        ])

        return shortcutField
    }

    private func makeShortcutRecorder(
        _ shortcut: RustKeyboardShortcut,
        onRecord: @escaping (RustKeyboardShortcut) -> Void
    ) -> NSView {
        let recorder = ShortcutRecorderButton(shortcut: shortcut)
        recorder.normalTextColor = theme.preferences.primaryTextColor
        recorder.wantsLayer = true
        recorder.layer?.backgroundColor = theme.preferences.controlBackgroundColor.cgColor
        recorder.layer?.cornerRadius = 7
        recorder.layer?.cornerCurve = .continuous
        recorder.layer?.borderWidth = 0.4
        recorder.layer?.borderColor = theme.preferences.separatorColor.cgColor
        recorder.onShortcutRecorded = onRecord
        recorder.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 124),
            recorder.heightAnchor.constraint(equalToConstant: 30)
        ])

        return recorder
    }

    private func makeTextInputRow(
        title: String,
        detail: String,
        value: String,
        onCommit: ((String) -> Void)? = nil
    ) -> NSView {
        let textField = NSTextField(string: value)
        textField.font = .systemFont(ofSize: 13.5)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior

        if let onCommit {
            textInputBindings.append(TextInputBinding(textField: textField, onCommit: onCommit))
        }

        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 324),
            textField.heightAnchor.constraint(equalToConstant: 30)
        ])

        return makeSettingRow(title: title, detail: detail, control: textField)
    }

    private func makeIgnoredApplicationsPickerRow(preferences: RustPreferencesDocument) -> NSView {
        let count = preferences.ignoreList.ignoredAppIdentifiers.count
        let detail = count == 0
            ? "未添加应用；选择后自动读取应用标识"
            : "已忽略 \(count) 个应用；选择后自动读取应用标识"
        return makeSettingRow(
            title: "忽略应用程序",
            detail: detail,
            control: makeActionButton(title: "选择应用...") { [weak self] in
                self?.openIgnoredApplicationsPanel()
            }
        )
    }

    private func openIgnoredApplicationsPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要忽略的应用程序"
        panel.message = "选择后会自动读取应用标识，用于忽略该应用复制的内容。"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK else { return }
        addIgnoredApplications(at: panel.urls)
    }

    private func addIgnoredApplications(at urls: [URL]) {
        let identifiers = urls.compactMap(IgnoredApplicationRuleResolver.ruleIdentifier(forApplicationAt:))
        guard !identifiers.isEmpty else { return }

        persist { preferences in
            var nextIdentifiers = preferences.ignoreList.ignoredAppIdentifiers
            for identifier in identifiers where !nextIdentifiers.contains(where: { $0.caseInsensitiveCompare(identifier) == .orderedSame }) {
                nextIdentifiers.append(identifier)
            }
            preferences.ignoreList.ignoredAppIdentifiers = nextIdentifiers
        }
        renderSelectedSection()
    }

    private func joinedRuleList(_ values: [String]) -> String {
        values.joined(separator: ", ")
    }

    private func splitRuleList(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",，;；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func persist(_ update: (inout RustPreferencesDocument) -> Void) {
        let previousAppearanceMode = sceneController.state.preferences.appearance.mode
        let nextPreferences = sceneController.makeUpdatedPreferences(update)
        sceneController.beginPreferencePersistence()
        if let savedPreferences = onPreferencesChanged?(nextPreferences) {
            _ = sceneController.completePreferencePersistence(
                persistedPreferences: savedPreferences,
                fallbackPreferences: nextPreferences
            )
        } else {
            _ = sceneController.completePreferencePersistence(
                persistedPreferences: nil,
                fallbackPreferences: nextPreferences
            )
        }

        if previousAppearanceMode != sceneController.state.preferences.appearance.mode {
            applyTheme()
            renderSelectedSection()
            updateNavigationSelection()
        }
    }

    private func persistDirectPasteToTarget(_ isOn: Bool) {
        if isOn, !sceneController.state.accessibilityPermissionState.isTrusted {
            onAccessibilityPermissionRequested?()
        }

        persist { $0.shortcuts.pasteDirectlyToTarget = isOn }
    }

    private func renderSelectedSectionRespectingControlAction() {
        applySceneUpdate(sceneController.consumeDeferredRenderIfNeeded())
    }

    private func scheduleDeferredRender() {
        guard !pendingDeferredRender else { return }
        pendingDeferredRender = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingDeferredRender = false
            self.renderSelectedSectionRespectingControlAction()
        }
    }

    private var selectedSection: PreferenceSection {
        preferenceSection(for: sceneController.state.selectedSection)
    }

    private func applySceneUpdate(_ update: PreferencesSceneUpdate) {
        if update.shouldUpdateNavigationSelection {
            updateNavigationSelection()
        }

        if update.shouldRenderSection {
            renderSelectedSection()
        }

        if update.shouldScheduleDeferredRender {
            scheduleDeferredRender()
        }
    }

    private func sceneSection(for section: PreferenceSection) -> PreferencesSceneSection {
        switch section {
        case .general:
            return .general
        case .appearance:
            return .appearance
        case .history:
            return .general
        case .shortcuts:
            return .shortcuts
        case .rules:
            return .rules
        case .about:
            return .about
        }
    }

    private func preferenceSection(for section: PreferencesSceneSection) -> PreferenceSection {
        switch section {
        case .general:
            return .general
        case .appearance:
            return .appearance
        case .history:
            return .general
        case .shortcuts:
            return .shortcuts
        case .rules:
            return .rules
        case .about:
            return .about
        }
    }

    private func makeSwitch(
        isOn: Bool,
        isEnabled: Bool = true,
        onChange: ((Bool) -> Void)? = nil
    ) -> NSSwitch {
        let control = PreferenceSwitch()
        control.controlSize = .small
        control.state = isOn ? .on : .off
        control.isEnabled = isEnabled
        control.target = nil
        control.action = nil
        control.onChange = onChange
        return control
    }

    private func makeStepperField(
        value: Int,
        minimumValue: Int,
        maximumValue: Int,
        onChange: @escaping (Int) -> Void
    ) -> NSView {
        let textField = NSTextField(string: "\(value)")
        textField.alignment = .right
        textField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.translatesAutoresizingMaskIntoConstraints = false

        let stepper = PreferenceStepper()
        stepper.controlSize = .small
        stepper.minValue = Double(minimumValue)
        stepper.maxValue = Double(maximumValue)
        stepper.increment = 1
        stepper.doubleValue = Double(value)
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.target = nil
        stepper.action = nil
        stepper.onChange = { [weak textField] value in
            textField?.stringValue = "\(value)"
            onChange(value)
        }

        let binding = StepperTextBinding(
            textField: textField,
            stepper: stepper,
            minimumValue: minimumValue,
            maximumValue: maximumValue,
            onChange: onChange
        )
        stepperBindings.append(binding)

        let stack = NSStackView(views: [textField, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 82),
            textField.heightAnchor.constraint(equalToConstant: 30)
        ])

        return stack
    }

    private func makeSegmentedControl(
        labels: [String],
        selected: Int,
        onChange: ((Int) -> Void)? = nil
    ) -> NSSegmentedControl {
        let control = PreferenceSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
        control.segmentStyle = .capsule
        control.controlSize = .small
        control.selectedSegment = selected
        control.target = nil
        control.action = nil
        control.onChange = onChange
        labels.indices.forEach { index in
            control.setWidth(labels[index].count > 3 ? 76 : 54, forSegment: index)
        }
        return control
    }

    private func makeAppearanceModeControl(
        selectedMode: String,
        onChange: @escaping (String) -> Void
    ) -> NSSegmentedControl {
        makeSegmentedControl(
            labels: ["跟随系统", "浅色", "深色"],
            selected: appearanceModeIndex(for: selectedMode)
        ) { selected in
            onChange(self.appearanceMode(for: selected))
        }
    }

    private func appearanceModeIndex(for mode: String) -> Int {
        switch mode {
        case "light":
            return 1
        case "dark":
            return 2
        default:
            return 0
        }
    }

    private func appearanceMode(for index: Int) -> String {
        switch index {
        case 1:
            return "light"
        case 2:
            return "dark"
        default:
            return "system"
        }
    }

    private func makeActionButton(
        title: String,
        isEnabled: Bool = true,
        onPress: (() -> Void)? = nil
    ) -> NSButton {
        let button = PreferenceActionButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.isEnabled = isEnabled
        button.target = nil
        button.action = nil
        button.onPress = onPress
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true
        return button
    }

    private func retentionLabel(days: Int64) -> String {
        switch days {
        case ..<7:
            return "按天保留"
        case 7..<30:
            return "按周保留"
        case 30..<365:
            return "按月保留"
        case 365..<Int64.max:
            return "按年保留"
        default:
            return "永久保留"
        }
    }

    private func retentionIndex(days: Int64) -> Int {
        switch days {
        case ..<7:
            return 0
        case 7..<30:
            return 1
        case 30..<365:
            return 2
        case 365..<Int64.max:
            return 3
        default:
            return 4
        }
    }

    private func retentionDays(for index: Int) -> Int64 {
        switch index {
        case 0:
            return 1
        case 1:
            return 7
        case 2:
            return 30
        case 3:
            return 365
        default:
            return Int64.max
        }
    }

    private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        return label
    }

    private func makeSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let line = NSBox()
        line.boxType = .custom
        line.borderColor = .clear
        line.fillColor = theme.preferences.separatorColor
        line.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(line)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.rowHorizontalInset),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.rowHorizontalInset),
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    private enum Layout {
        static let defaultWindowSize = NSSize(width: 456, height: 430)
        static let minimumWindowSize = defaultWindowSize
        static let windowCornerRadius: CGFloat = 16
        static let contentInset: CGFloat = 42
        static let iconSize: CGFloat = 110
    }

    private let rootView = AboutRootView()
    private weak var titleLabel: NSTextField?
    private weak var versionLabel: NSTextField?
    private weak var copyrightLabel: NSTextField?
    private var theme: AboutWindowTheme {
        AboutWindowTheme(palette: ClipDockTheme.current(for: window))
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于"
        window.minSize = Layout.minimumWindowSize
        window.maxSize = Layout.minimumWindowSize
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = ClipDockTheme.current(for: window).preferences.windowBackgroundColor
        window.isOpaque = true

        super.init(window: window)

        configureWindow(window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showAbout() {
        guard let window else { return }

        if !window.isVisible {
            window.center()
        }

        applyTheme()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureWindow(_ window: NSWindow) {
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = Layout.windowCornerRadius
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true
        rootView.layer?.borderWidth = 0.8
        rootView.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
        }
        window.contentView = rootView

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = makeAppIconView()
        let titleLabel = makeCenteredLabel(
            displayName,
            font: .systemFont(ofSize: 29, weight: .semibold),
            color: theme.titleTextColor
        )
        self.titleLabel = titleLabel
        let versionLabel = makeCenteredLabel(
            versionText,
            font: .systemFont(ofSize: 13, weight: .medium),
            color: theme.secondaryTextColor
        )
        self.versionLabel = versionLabel
        let copyrightLabel = makeCenteredLabel(
            "© 2026 ClipDock\nBuilt with AppKit and Rust.",
            font: .systemFont(ofSize: 12.5, weight: .medium),
            color: theme.mutedTextColor
        )
        self.copyrightLabel = copyrightLabel

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(versionLabel)
        stack.addArrangedSubview(copyrightLabel)

        rootView.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Layout.iconSize),

            stack.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: rootView.centerYAnchor, constant: -14),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: Layout.contentInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -Layout.contentInset),
            stack.topAnchor.constraint(greaterThanOrEqualTo: rootView.topAnchor, constant: 54),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -46)
        ])

        applyTheme()
    }

    private var displayName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty {
            return name
        }

        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }

        return "ClipDock"
    }

    private var versionText: String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
        let buildVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
        return "版本 \(shortVersion) (\(buildVersion))"
    }

    private func makeAppIconView() -> NSView {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = AppIconDisplayImageProvider.image(accessibilityDescription: displayName)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.30).cgColor
        imageView.layer?.shadowOpacity = 1
        imageView.layer?.shadowRadius = 12
        imageView.layer?.shadowOffset = CGSize(width: 0, height: -2)

        return imageView
    }

    private func makeCenteredLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func applyTheme() {
        let theme = theme
        window?.backgroundColor = theme.windowBackgroundColor
        rootView.layer?.backgroundColor = theme.contentBackgroundColor.cgColor
        rootView.layer?.borderColor = theme.borderColor.cgColor
        titleLabel?.textColor = theme.titleTextColor
        versionLabel?.textColor = theme.secondaryTextColor
        copyrightLabel?.textColor = theme.mutedTextColor
    }
}

private final class AboutRootView: NSView {
    var onAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
}

private struct AboutWindowTheme {
    let windowBackgroundColor: NSColor
    let contentBackgroundColor: NSColor
    let borderColor: NSColor
    let titleTextColor: NSColor
    let secondaryTextColor: NSColor
    let mutedTextColor: NSColor

    init(palette: ClipDockThemePalette) {
        let preferences = palette.preferences
        windowBackgroundColor = preferences.windowBackgroundColor
        contentBackgroundColor = preferences.contentBackgroundColor
        borderColor = preferences.borderColor
        titleTextColor = preferences.primaryTextColor
        secondaryTextColor = preferences.secondaryTextColor
        mutedTextColor = preferences.secondaryTextColor.withAlphaComponent(
            palette.scheme == .light ? 0.72 : 0.66
        )
    }
}

private enum AppIconDisplayImageProvider {
    static func image(accessibilityDescription: String) -> NSImage? {
        if let sourceImage = sourceImage() {
            let image = cleanedRoundedIcon(from: sourceImage)
            image.accessibilityDescription = accessibilityDescription
            return image
        }

        let fallbackImage = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: accessibilityDescription)
        fallbackImage?.accessibilityDescription = accessibilityDescription
        return fallbackImage
    }

    private static func sourceImage() -> NSImage? {
        let packagedIconURL = Bundle.main.resourceURL?
            .appendingPathComponent("AppIcon.icns")
        let moduleIconURL = Bundle.module
            .url(forResource: "AppIcon", withExtension: "icns")
        let moduleSourceURL = Bundle.module
            .url(forResource: "AppIcon", withExtension: "png")

        return [packagedIconURL, moduleIconURL, moduleSourceURL]
            .compactMap { $0 }
            .lazy
            .compactMap(NSImage.init(contentsOf:))
            .first
    }

    private static func cleanedRoundedIcon(from sourceImage: NSImage) -> NSImage {
        let sourceSize = sourceImage.size
        let sourceSide = max(1, min(sourceSize.width, sourceSize.height))
        let outputSide = max(256, sourceSide)
        let outputSize = NSSize(width: outputSide, height: outputSide)
        let outputImage = NSImage(size: outputSize)
        let sourceRect = NSRect(
            x: max(0, (sourceSize.width - sourceSide) / 2),
            y: max(0, (sourceSize.height - sourceSide) / 2),
            width: sourceSide,
            height: sourceSide
        )
        let destinationRect = NSRect(origin: .zero, size: outputSize)

        outputImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        destinationRect.fill()
        NSBezierPath(
            roundedRect: destinationRect,
            xRadius: outputSide * 0.225,
            yRadius: outputSide * 0.225
        ).addClip()
        sourceImage.draw(
            in: destinationRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        outputImage.unlockFocus()

        outputImage.isTemplate = false
        return outputImage
    }
}
