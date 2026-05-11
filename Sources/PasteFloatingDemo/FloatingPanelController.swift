import AppKit
import ClipboardPanelApp

@MainActor
final class FloatingPanelController {
    private static let defaultPanelHeight = BottomPanelGeometryPlanner.defaultHeight

    private let panel: FloatingPanel
    private let contentView: FloatingPanelContentView
    private(set) var levelMode: PanelLevelMode = .aboveDock
    private var preferredHeight = FloatingPanelController.defaultPanelHeight
    private var resizeStartHeight = FloatingPanelController.defaultPanelHeight
    private var resizeScreen: NSScreen?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?

    var onRuntimeAction: ((PanelRuntimeAction) -> Void)?

    init() {
        contentView = FloatingPanelContentView(frame: .zero)
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: Self.defaultPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        configureCallbacks()
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show() {
        positionOverDock()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        focusContentView()
        startOutsideClickMonitoring()
    }

    func hide() {
        contentView.closePreviewPopover()
        panel.orderOut(nil)
        stopOutsideClickMonitoring()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func cycleLevel() {
        guard let currentIndex = PanelLevelMode.allCases.firstIndex(of: levelMode) else {
            levelMode = .floating
            applyLevelMode()
            return
        }

        let nextIndex = PanelLevelMode.allCases.index(after: currentIndex)
        levelMode = nextIndex == PanelLevelMode.allCases.endIndex ? .floating : PanelLevelMode.allCases[nextIndex]
        applyLevelMode()
        show()
    }

    func updateStorageState(_ result: Result<RustCoreOpenResult, RustCoreError>) {
        contentView.updateStorageState(result)
    }

    func updateListState(_ result: Result<RustCoreListResult, RustCoreError>, isFiltered: Bool, append: Bool = false) {
        contentView.updateListState(result, isFiltered: isFiltered, append: append)
    }

    func updateLoadingMoreState(_ isLoading: Bool) {
        contentView.updateLoadingMoreState(isLoading)
    }

    func refreshPanelContentLayout() {
        contentView.updatePanelHeight(preferredHeight)
    }

    func setAppSupportDirectory(_ url: URL) {
        contentView.updateAppSupportDirectory(url)
    }

    func setPreviewPopoverEnabled(_ enabled: Bool) {
        contentView.setPreviewPopoverEnabled(enabled)
    }

    func resetFiltersForCapturedItem() {
        contentView.resetFiltersForCapturedItem()
    }

    func setPreferredHeight(_ height: CGFloat) {
        guard let screen = targetScreenForPresentation() else {
            preferredHeight = height
            contentView.updatePanelHeight(height)
            return
        }

        preferredHeight = clampedHeight(height, for: screen)
        if panel.isVisible {
            applyPanelFrame(on: screen, height: preferredHeight, animate: true)
        } else {
            contentView.updatePanelHeight(preferredHeight)
        }
    }

    func positionOverDock() {
        guard let screen = targetScreenForPresentation() else { return }

        preferredHeight = clampedHeight(preferredHeight, for: screen)
        applyPanelFrame(on: screen, height: preferredHeight, animate: true)
    }

    private func beginHeightResize() {
        resizeStartHeight = panel.frame.height
        resizeScreen = panel.screen ?? targetScreenForPresentation()
    }

    private func resizeHeight(deltaY: CGFloat) {
        guard let screen = resizeScreen ?? targetScreenForPresentation() else { return }

        preferredHeight = BottomPanelGeometryPlanner.resizedHeight(
            startHeight: resizeStartHeight,
            deltaY: deltaY,
            screenHeight: screen.frame.height
        )
        applyPanelFrame(on: screen, height: preferredHeight, animate: false)
    }

    private func applyPanelFrame(on screen: NSScreen, height: CGFloat, animate: Bool) {
        let frame = BottomPanelGeometryPlanner.frame(
            screenFrame: screen.frame,
            preferredHeight: height
        )

        panel.setFrame(frame, display: true, animate: animate)
        contentView.updatePanelHeight(height)
    }

    private func focusContentView() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(contentView)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.orderFrontRegardless()
            self.panel.makeKey()
            self.panel.makeFirstResponder(self.contentView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.orderFrontRegardless()
            self.panel.makeKey()
            self.panel.makeFirstResponder(self.contentView)
        }
    }

    private func clampedHeight(_ height: CGFloat, for screen: NSScreen) -> CGFloat {
        BottomPanelGeometryPlanner.clampedHeight(
            height,
            screenHeight: screen.frame.height
        )
    }

    private func configurePanel() {
        panel.contentView = contentView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]

        applyLevelMode()
    }

    private func configureCallbacks() {
        contentView.onRuntimeAction = { [weak self] action in
            self?.onRuntimeAction?(action)
        }
        contentView.onHeightResizeBegan = { [weak self] in self?.beginHeightResize() }
        contentView.onHeightResizeChanged = { [weak self] deltaY in self?.resizeHeight(deltaY: deltaY) }
    }

    private func startOutsideClickMonitoring() {
        guard localOutsideClickMonitor == nil, globalOutsideClickMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.hideIfClickIsOutsidePanel(event)
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.hideIfClickIsOutsidePanel(event)
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }

        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    private func hideIfClickIsOutsidePanel(_ event: NSEvent) {
        guard panel.isVisible else {
            stopOutsideClickMonitoring()
            return
        }

        if shouldHideForMouseDown(eventWindow: event.window, mouseLocation: NSEvent.mouseLocation) {
            hide()
        }
    }

    private func shouldHideForMouseDown(eventWindow: NSWindow?, mouseLocation: CGPoint) -> Bool {
        if contentView.containsPreviewSurface(eventWindow: eventWindow, mouseLocation: mouseLocation) {
            return false
        }

        return PanelInteractionPlanner.shouldHideForOutsideMouseDown(
            eventWindowIsPanel: eventWindow === panel,
            mouseLocation: mouseLocation,
            panelFrame: panel.frame
        )
    }

    private func applyLevelMode() {
        switch levelMode {
        case .floating:
            panel.level = .floating
        case .statusBar:
            panel.level = .statusBar
        case .aboveDock:
            let dockLevel = CGWindowLevelForKey(.dockWindow)
            panel.level = NSWindow.Level(rawValue: Int(dockLevel) + 1)
        }
    }

    private func targetScreenForPresentation() -> NSScreen? {
        screenContainingMouse() ?? panel.screen ?? NSScreen.main
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        guard let index = ScreenSelectionPlanner.selectedScreenIndex(
            mouseLocation: mouseLocation,
            screenFrames: frames
        ) else {
            return nil
        }
        return screens[index]
    }
}

@MainActor
extension FloatingPanelController {
    var smokeContentView: FloatingPanelContentView {
        contentView
    }

    var smokePanelFrame: CGRect {
        panel.frame
    }

    var smokeHasOutsideClickMonitoring: Bool {
        localOutsideClickMonitor != nil && globalOutsideClickMonitor != nil
    }

    var smokePanelIsKeyWindow: Bool {
        panel.isKeyWindow
    }

    var smokeFirstResponderIsContentView: Bool {
        panel.firstResponder === contentView
    }

    var smokeFocusDiagnostic: String {
        let firstResponderType = panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        return "visible=\(panel.isVisible) key=\(panel.isKeyWindow) main=\(panel.isMainWindow) appActive=\(NSApp.isActive) firstResponder=\(firstResponderType)"
    }

    func smokeHandleOutsideMouseDown(
        eventWindowIsPanel: Bool,
        mouseLocation: CGPoint
    ) {
        let eventWindow = eventWindowIsPanel ? panel : nil
        if shouldHideForMouseDown(eventWindow: eventWindow, mouseLocation: mouseLocation) {
            hide()
        }
    }

    var smokePreviewScreenFrame: CGRect? {
        contentView.smokePreviewScreenFrame
    }
}
