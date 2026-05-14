import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipboardPanelApp
import ServiceManagement
import SwiftUI

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
            .shortcuts,
            .rules,
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
            return "启动、菜单栏、主题、预览与保留策略"
        case .appearance:
            return "主题与预览浮层"
        case .history:
            return "记录类型、保留时长与数量"
        case .shortcuts:
            return "打开、搜索与快速取用"
        case .rules:
            return "来源权限、忽略规则与窗口标题"
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

private enum LocalDocsNavigator {
    static func open(relativePath: String? = nil) {
        guard let url = url(relativePath: relativePath) else { return }
        NSWorkspace.shared.open(url)
    }

    static func url(relativePath: String? = nil) -> URL? {
        guard let rootURL = workspaceRootURL() else { return nil }

        let docsURL = rootURL.appendingPathComponent("docs", isDirectory: true)
        guard let relativePath, !relativePath.isEmpty else {
            return docsURL
        }

        return docsURL.appendingPathComponent(relativePath)
    }

    private static func workspaceRootURL() -> URL? {
        let fileManager = FileManager.default
        let startingPoints = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        ]

        var visitedPaths = Set<String>()
        for startURL in startingPoints {
            var currentURL = startURL.standardizedFileURL
            while true {
                let path = currentURL.path
                if visitedPaths.insert(path).inserted {
                    let docsURL = currentURL.appendingPathComponent("docs", isDirectory: true)
                    let markerURL = currentURL.appendingPathComponent("AGENTS.md")
                    if fileManager.fileExists(atPath: docsURL.path),
                       fileManager.fileExists(atPath: markerURL.path) {
                        return currentURL
                    }
                }

                let parentURL = currentURL.deletingLastPathComponent()
                if parentURL.path == currentURL.path {
                    break
                }
                currentURL = parentURL
            }
        }

        return nil
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
            if enabled {
                if service.status != .enabled,
                   service.status != .requiresApproval {
                    try service.register()
                }
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else if service.status == .enabled
                || service.status == .requiresApproval {
                try service.unregister()
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

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .unknown
        }
    }

    private var isRunningAsApplicationBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier != nil
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
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    private enum Layout {
        static let defaultWindowSize = NSSize(width: 920, height: 700)
        static let minimumWindowSize = NSSize(width: 820, height: 600)
    }

    private let viewModel = PreferencesSwiftUIViewModel()
    private var hostingView: NSHostingView<PreferencesRootView>?

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
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.isOpaque = true

        super.init(window: window)

        configureWindow(window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showPreferences() {
        guard let window else { return }

        if !window.isVisible {
            window.center()
        }

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updatePreferences(_ preferences: RustPreferencesDocument) {
        viewModel.updatePreferences(preferences)
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
        viewModel.persist { $0.linkPreview.metadataEnabled.toggle() }
        viewModel.persist { $0.linkPreview.webPreviewEnabled.toggle() }
        viewModel.persist { $0.shortcuts.pasteDirectlyToTarget.toggle() }
        viewModel.persist { $0.ignoreList.skipUnknownSource.toggle() }
        viewModel.persist {
            $0.shortcuts.openPanel = RustKeyboardShortcut(
                keyCode: Int64(kVK_ANSI_B),
                modifiers: ["command", "option"]
            )
        }
    }

    private func configureWindow(_ window: NSWindow) {
        let rootView = PreferencesRootView(model: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: Layout.defaultWindowSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 22
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        self.hostingView = hostingView
    }
}

@MainActor
private final class PreferencesSwiftUIViewModel: ObservableObject {
    @Published private(set) var state = PreferencesSceneState()

    private let sceneController = PreferencesSceneController()
    private var pendingDeferredRender = false

    var onPreferencesChanged: ((RustPreferencesDocument) -> RustPreferencesDocument?)?
    var onAccessibilityPermissionRequested: (() -> Void)?

    var selectedSection: PreferenceSection {
        preferenceSection(for: state.selectedSection)
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
        let nextPreferences = sceneController.makeUpdatedPreferences(update)
        sceneController.beginPreferencePersistence()
        state = sceneController.state

        let savedPreferences = onPreferencesChanged?(nextPreferences)
        apply(sceneController.completePreferencePersistence(
            persistedPreferences: savedPreferences,
            fallbackPreferences: nextPreferences
        ))
    }

    func requestAccessibilityPermission() {
        onAccessibilityPermissionRequested?()
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

private struct PreferencesRootView: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel

    var body: some View {
        HStack(spacing: 0) {
            PreferencesSidebar(model: model)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            PreferencesContent(model: model)
        }
        .frame(minWidth: 820, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PreferencesSidebar: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ForEach(PreferenceSection.allCases, id: \.self) { section in
                PreferenceSidebarRow(
                    section: section,
                    isSelected: model.selectedSection == section
                ) {
                    model.selectSection(section)
                }
            }

            Spacer(minLength: 16)
        }
        .padding(.top, 66)
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
        .frame(width: 264)
        .background(.ultraThinMaterial)
    }
}

private struct PreferenceSidebarRow: View {
    let section: PreferenceSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 13.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.76))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.7)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PreferencesContent: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PreferencePageHeader(section: model.selectedSection)
            pageContent
        }
        .frame(maxWidth: 660, alignment: .leading)
        .padding(.top, 56)
        .padding(.horizontal, 42)
        .padding(.bottom, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: section.symbolName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.7)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(section.subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PreferenceGeneralSection: View {
    @ObservedObject var model: PreferencesSwiftUIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
        VStack(alignment: .leading, spacing: 20) {
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
                PreferenceDivider()
                PreferenceRow(title: "直接复制到目标", detail: "取用条目后自动粘贴到原应用") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.preferences.shortcuts.pasteDirectlyToTarget },
                            set: { isOn in model.persist { $0.shortcuts.pasteDirectlyToTarget = isOn } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PreferenceSectionGroup(title: "系统权限") {
                PreferenceRow(title: "窗口标题采集", detail: model.state.accessibilityPermissionState.detail) {
                    Button(model.state.accessibilityPermissionState.actionTitle) {
                        model.requestAccessibilityPermission()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.state.accessibilityPermissionState.canOpenSettings)
                }
            }

            PreferenceSectionGroup(title: "链接预览") {
                PreferenceRow(title: "生成卡片信息", detail: "后台下载标题、图标和摘要图") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.preferences.linkPreview.metadataEnabled },
                            set: { isOn in model.persist { $0.linkPreview.metadataEnabled = isOn } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                PreferenceDivider()
                PreferenceRow(title: "网页完整预览", detail: "按空格时加载真实网页") {
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

            PreferenceSectionGroup(title: "忽略规则") {
                PreferenceRow(title: "应用标识", detail: "逗号分隔，如 com.apple.Terminal") {
                    RuleListField(
                        values: model.state.preferences.ignoreList.ignoredAppIdentifiers,
                        placeholder: "com.apple.Terminal, Xcode"
                    ) { apps in
                        model.persist { $0.ignoreList.ignoredAppIdentifiers = apps }
                    }
                }
                PreferenceDivider()
                PreferenceRow(title: "未知来源", detail: "无法识别来源时不写入历史") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.state.preferences.ignoreList.skipUnknownSource },
                            set: { isOn in model.persist { $0.ignoreList.skipUnknownSource = isOn } }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                PreferenceDivider()
                PreferenceRow(title: "窗口标题关键词", detail: "标题命中关键词时不写入历史") {
                    RuleListField(
                        values: model.state.preferences.ignoreList.windowTitleKeywords,
                        placeholder: "验证码, Private"
                    ) { keywords in
                        model.persist { $0.ignoreList.windowTitleKeywords = keywords }
                    }
                }
            }
        }
    }
}

private struct PreferenceAboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PreferenceSectionGroup {
                HStack(spacing: 16) {
                    PreferenceAppIconView()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(aboutDisplayName())
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("本地剪贴架")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
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

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) {
                content
            }
            .preferenceGlass(cornerRadius: 8)
        }
    }
}

private struct PreferenceRow<Accessory: View>: View {
    let title: String
    let detail: String
    let accessory: Accessory

    init(title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
    }
}

private struct PreferenceDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 22)
    }
}

private struct PreferenceNumberStepper: View {
    let value: Binding<Int>
    let range: ClosedRange<Int>
    let step: Int
    let suffix: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(value.wrappedValue)\(suffix)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: suffix.isEmpty ? 66 : 82, alignment: .trailing)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct PreferenceShortcutPill: View {
    let shortcut: String

    init(_ shortcut: String) {
        self.shortcut = shortcut
    }

    var body: some View {
        Text(shortcut)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(minWidth: 92)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.6)
            )
    }
}

private struct PreferenceValuePill: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.6)
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
            .frame(width: 304)
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

    init(shortcut: RustKeyboardShortcut, onRecord: @escaping (RustKeyboardShortcut) -> Void) {
        self.shortcut = shortcut
        self.onRecord = onRecord
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(shortcut: shortcut)
        button.normalTextColor = .labelColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
        button.layer?.borderWidth = 0.5
        button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        button.onShortcutRecorded = onRecord
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.normalTextColor = .labelColor
        nsView.onShortcutRecorded = onRecord
        nsView.updateShortcut(shortcut)
    }
}

private struct PreferenceGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
            )
    }
}

private extension View {
    func preferenceGlass(cornerRadius: CGFloat) -> some View {
        modifier(PreferenceGlassModifier(cornerRadius: cornerRadius))
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

    return "ClipShelf"
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
    private var theme: ClipShelfThemePalette {
        ClipShelfTheme.current(for: window)
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
        window.backgroundColor = ClipShelfTheme.current(for: window).preferences.windowBackgroundColor
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
                        ),
                        makeSettingRow(
                            title: "直接复制到目标",
                            detail: "取用条目后自动粘贴到原应用",
                            control: makeSwitch(
                                isOn: preferences.shortcuts.pasteDirectlyToTarget
                            ) { [weak self] isOn in
                                self?.persist { $0.shortcuts.pasteDirectlyToTarget = isOn }
                            }
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
                            title: "生成卡片信息",
                            detail: "后台下载标题、图标和摘要图",
                            control: makeSwitch(isOn: preferences.linkPreview.metadataEnabled) { [weak self] isOn in
                                self?.persist { $0.linkPreview.metadataEnabled = isOn }
                            }
                        ),
                        makeSettingRow(
                            title: "网页完整预览",
                            detail: "按空格时加载真实网页",
                            control: makeSwitch(isOn: preferences.linkPreview.webPreviewEnabled) { [weak self] isOn in
                                self?.persist { $0.linkPreview.webPreviewEnabled = isOn }
                            }
                        )
                    ]),
                    makeSection(title: "应用", rows: [
                        makeTextInputRow(
                            title: "应用标识",
                            detail: "Bundle ID、应用名或 .app 名称",
                            value: joinedRuleList(preferences.ignoreList.ignoredAppIdentifiers)
                        ) { [weak self] value in
                            guard let self else { return }
                            let identifiers = self.splitRuleList(value)
                            self.persist {
                                $0.ignoreList.ignoredAppIdentifiers = identifiers
                            }
                        },
                        makeSettingRow(
                            title: "未知来源",
                            detail: "来源为空时跳过",
                            control: makeSwitch(isOn: preferences.ignoreList.skipUnknownSource) { [weak self] isOn in
                                self?.persist { $0.ignoreList.skipUnknownSource = isOn }
                            }
                        )
                    ]),
                    makeSection(title: "窗口标题", rows: [
                        makeTextInputRow(
                            title: "标题关键词",
                            detail: "命中时跳过",
                            value: joinedRuleList(preferences.ignoreList.windowTitleKeywords)
                        ) { [weak self] value in
                            guard let self else { return }
                            let keywords = self.splitRuleList(value)
                            self.persist {
                                $0.ignoreList.windowTitleKeywords = keywords
                            }
                        }
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
        static let defaultWindowSize = NSSize(width: 456, height: 520)
        static let minimumWindowSize = defaultWindowSize
        static let windowCornerRadius: CGFloat = 16
        static let contentInset: CGFloat = 42
        static let iconSize: CGFloat = 110
        static let socialButtonSize: CGFloat = 40
    }

    private let rootView = AboutRootView()
    private weak var titleLabel: NSTextField?
    private weak var versionLabel: NSTextField?
    private weak var copyrightLabel: NSTextField?
    private weak var linksSeparatorLabel: NSTextField?
    private var socialButtons: [AboutIconButton] = []
    private var linkButtons: [NSButton] = []
    private var theme: AboutWindowTheme {
        AboutWindowTheme(palette: ClipShelfTheme.current(for: window))
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
        window.backgroundColor = ClipShelfTheme.current(for: window).preferences.windowBackgroundColor
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
        let socialButtons = makeSocialButtonRow()
        let linksRow = makeLinksRow()
        let copyrightLabel = makeCenteredLabel(
            "© 2026 ClipShelf\nBuilt with AppKit and Rust.",
            font: .systemFont(ofSize: 12.5, weight: .medium),
            color: theme.mutedTextColor
        )
        self.copyrightLabel = copyrightLabel

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(versionLabel)
        stack.addArrangedSubview(socialButtons)
        stack.addArrangedSubview(linksRow)
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

        return "ClipShelf"
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

    private func makeSocialButtonRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let buttons: [(String, String, String?)] = [
            ("book", "文档首页", nil),
            ("square.stack.3d.up", "架构说明", "architecture.md"),
            ("checkmark.seal", "UI QA", "ui-qa-review.md"),
            ("shippingbox", "发布说明", "release.md")
        ]

        buttons.forEach { symbolName, title, relativePath in
            stack.addArrangedSubview(
                makeSocialButton(
                    symbolName: symbolName,
                    title: title,
                    relativePath: relativePath
                )
            )
        }

        return stack
    }

    private func makeSocialButton(symbolName: String, title: String, relativePath: String?) -> AboutIconButton {
        let button = AboutIconButton(symbolName: symbolName, accessibilityDescription: title)
        button.toolTip = title
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = LocalDocsNavigator.url(relativePath: relativePath) != nil
        button.onPress = {
            LocalDocsNavigator.open(relativePath: relativePath)
        }
        socialButtons.append(button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Layout.socialButtonSize),
            button.heightAnchor.constraint(equalToConstant: Layout.socialButtonSize)
        ])

        return button
    }

    private func makeLinksRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeLinkButton(title: "项目文档", relativePath: nil))
        let separatorLabel = makeCenteredLabel("·", font: .systemFont(ofSize: 14, weight: .medium), color: theme.separatorTextColor)
        linksSeparatorLabel = separatorLabel
        stack.addArrangedSubview(separatorLabel)
        stack.addArrangedSubview(makeLinkButton(title: "发布说明", relativePath: "release.md"))

        return stack
    }

    private func makeLinkButton(title: String, relativePath: String?) -> NSButton {
        let button = PreferenceActionButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = LocalDocsNavigator.url(relativePath: relativePath) != nil
        button.onPress = {
            LocalDocsNavigator.open(relativePath: relativePath)
        }
        linkButtons.append(button)
        return button
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
        linksSeparatorLabel?.textColor = theme.separatorTextColor

        socialButtons.forEach { button in
            button.iconTintColor = theme.secondaryTextColor
            button.buttonBackgroundColor = theme.socialButtonBackgroundColor
            button.buttonBorderColor = theme.socialButtonBorderColor
        }

        linkButtons.forEach { button in
            button.contentTintColor = theme.linkTextColor
        }
    }
}

private final class AboutRootView: NSView {
    var onAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
}

private final class AboutIconButton: NSControl {
    var onPress: (() -> Void)?
    var buttonBackgroundColor = NSColor.clear {
        didSet {
            layer?.backgroundColor = buttonBackgroundColor.cgColor
        }
    }
    var buttonBorderColor = NSColor.clear {
        didSet {
            layer?.borderColor = buttonBorderColor.cgColor
        }
    }
    var iconTintColor = NSColor.secondaryLabelColor {
        didSet {
            imageView.contentTintColor = iconTintColor
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 40, height: 40)
    }

    private let imageView = NSImageView()

    init(symbolName: String, accessibilityDescription: String) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.7

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = iconTintColor
        addSubview(imageView)

        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityDescription)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.backgroundColor = buttonBackgroundColor.cgColor
        layer?.borderColor = buttonBorderColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onPress?()
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter:
            guard isEnabled else { return }
            onPress?()
        default:
            super.keyDown(with: event)
        }
    }
}

private struct AboutWindowTheme {
    let windowBackgroundColor: NSColor
    let contentBackgroundColor: NSColor
    let borderColor: NSColor
    let titleTextColor: NSColor
    let secondaryTextColor: NSColor
    let mutedTextColor: NSColor
    let separatorTextColor: NSColor
    let linkTextColor: NSColor
    let socialButtonBackgroundColor: NSColor
    let socialButtonBorderColor: NSColor

    init(palette: ClipShelfThemePalette) {
        let preferences = palette.preferences
        windowBackgroundColor = preferences.windowBackgroundColor
        contentBackgroundColor = preferences.contentBackgroundColor
        borderColor = preferences.borderColor
        titleTextColor = preferences.primaryTextColor
        secondaryTextColor = preferences.secondaryTextColor
        mutedTextColor = preferences.secondaryTextColor.withAlphaComponent(
            palette.scheme == .light ? 0.72 : 0.66
        )
        separatorTextColor = preferences.secondaryTextColor.withAlphaComponent(
            palette.scheme == .light ? 0.48 : 0.42
        )
        linkTextColor = preferences.secondaryTextColor.withAlphaComponent(
            palette.scheme == .light ? 0.86 : 0.78
        )
        socialButtonBackgroundColor = preferences.cardBackgroundColor.withAlphaComponent(
            palette.scheme == .light ? 0.82 : 0.54
        )
        socialButtonBorderColor = preferences.cardBorderColor.withAlphaComponent(
            palette.scheme == .light ? 0.70 : 0.84
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
        let cropInset = sourceSide * 0.052
        let sourceRect = NSRect(
            x: max(0, (sourceSize.width - sourceSide) / 2 + cropInset),
            y: max(0, (sourceSize.height - sourceSide) / 2 + cropInset),
            width: max(1, sourceSide - cropInset * 2),
            height: max(1, sourceSide - cropInset * 2)
        )
        let destinationRect = NSRect(origin: .zero, size: outputSize)

        outputImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
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
