import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp

private enum PanelPresentationAnimation {
    static let showDuration: TimeInterval = 0.16
    static let hideDuration: TimeInterval = 0.18
    static let frameIntervalNanoseconds: UInt64 = 16_666_667

    static func entranceFrame(for frame: NSRect) -> NSRect {
        offscreenFrame(for: frame)
    }

    static func dismissedFrame(for frame: NSRect) -> NSRect {
        offscreenFrame(for: frame)
    }

    private static let offscreenMargin: CGFloat = 12

    private static func offscreenFrame(for frame: NSRect) -> NSRect {
        frame.offsetBy(dx: 0, dy: -(frame.height + offscreenMargin))
    }

    static func interpolatedFrame(from startFrame: NSRect, to endFrame: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: startFrame.origin.x + (endFrame.origin.x - startFrame.origin.x) * progress,
            y: startFrame.origin.y + (endFrame.origin.y - startFrame.origin.y) * progress,
            width: startFrame.size.width + (endFrame.size.width - startFrame.size.width) * progress,
            height: startFrame.size.height + (endFrame.size.height - startFrame.size.height) * progress
        )
    }
}

private enum PanelPresentationTiming {
    case easeIn
    case easeInOut
    case easeOut

    func progress(for linearProgress: CGFloat) -> CGFloat {
        let clamped = min(max(linearProgress, 0), 1)
        switch self {
        case .easeIn:
            return clamped * clamped * clamped
        case .easeInOut:
            if clamped < 0.5 {
                return 4 * clamped * clamped * clamped
            }
            let inverse = -2 * clamped + 2
            return 1 - (inverse * inverse * inverse) / 2
        case .easeOut:
            let inverse = 1 - clamped
            return 1 - inverse * inverse * inverse
        }
    }
}

@MainActor
protocol PanelFocusApplication: AnyObject {
    var processIdentifier: pid_t { get }
    var bundleIdentifier: String? { get }
    var isTerminated: Bool { get }

    @discardableResult
    func activateForPanelFocusRestore() -> Bool
}

extension NSRunningApplication: PanelFocusApplication {
    func activateForPanelFocusRestore() -> Bool {
        activate(options: [.activateIgnoringOtherApps])
    }
}

@MainActor
protocol PanelFocusApplicationProviding {
    func frontmostPanelFocusApplication() -> PanelFocusApplication?
}

extension NSWorkspace: PanelFocusApplicationProviding {
    func frontmostPanelFocusApplication() -> PanelFocusApplication? {
        frontmostApplication
    }
}

protocol PanelHeightPreferenceStoring: AnyObject {
    var preferredPanelHeight: CGFloat? { get set }
}

final class UserDefaultsPanelHeightPreferenceStore: PanelHeightPreferenceStoring {
    private let defaults: UserDefaults
    private let key = "floatingPanel.preferredHeight"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferredPanelHeight: CGFloat? {
        get {
            guard defaults.object(forKey: key) != nil else { return nil }
            let height = defaults.double(forKey: key)
            guard height.isFinite, height > 0 else { return nil }
            return CGFloat(height)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(Double(newValue), forKey: key)
        }
    }
}

@MainActor
final class FloatingPanelController {
    private static let defaultPanelHeight = BottomPanelGeometryPlanner.defaultHeight

    private let panel: FloatingPanel
    private let contentView: FloatingPanelContentView
    private let focusApplicationProvider: PanelFocusApplicationProviding
    private let heightPreferenceStore: PanelHeightPreferenceStoring
    private let mainBundleIdentifier: String?
    private(set) var levelMode: PanelLevelMode = .aboveDock
    private var preferredHeight = FloatingPanelController.defaultPanelHeight
    private var resizeStartHeight = FloatingPanelController.defaultPanelHeight
    private var resizeScreen: NSScreen?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var previousFocusApplication: PanelFocusApplication?
    private var isPanelPresented = false
    private var animationGeneration = 0
    private var panelAnimationTask: Task<Void, Never>?
    private var resizePerformanceStart: TimeInterval?
    private var resizePerformanceEventCount = 0
    private var resizePerformanceSlowestFrameMilliseconds = 0.0

    var onRuntimeAction: ((PanelRuntimeAction) -> Void)?

    init(
        focusApplicationProvider: PanelFocusApplicationProviding = NSWorkspace.shared,
        heightPreferenceStore: PanelHeightPreferenceStoring = UserDefaultsPanelHeightPreferenceStore(),
        mainBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.focusApplicationProvider = focusApplicationProvider
        self.heightPreferenceStore = heightPreferenceStore
        self.mainBundleIdentifier = mainBundleIdentifier
        if let storedHeight = heightPreferenceStore.preferredPanelHeight {
            preferredHeight = storedHeight
            resizeStartHeight = storedHeight
        }
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
        isPanelPresented
    }

    func show() {
        let showStart = ClipDockPerformanceLog.mark()
        rememberPreviousFocusApplicationIfNeeded()
        guard let screen = targetScreenForPresentation() else { return }

        preferredHeight = clampedHeight(preferredHeight, for: screen)
        let finalFrame = targetPanelFrame(on: screen, height: preferredHeight)
        ClipDockPerformanceLog.measure("panel.show.updateHeight") {
            contentView.updatePanelHeight(preferredHeight)
        }

        let shouldAnimateEntrance = !panel.isVisible || !isPanelPresented
        isPanelPresented = true
        animationGeneration += 1
        let generation = animationGeneration
        let startFrame: NSRect

        if shouldAnimateEntrance, !panel.isVisible {
            startFrame = PanelPresentationAnimation.entranceFrame(for: finalFrame)
            ClipDockPerformanceLog.measure("panel.show.setEntranceFrame") {
                panel.setFrame(startFrame, display: true)
            }
        } else {
            startFrame = panel.frame
            panel.alphaValue = 1
        }

        ClipDockPerformanceLog.event(
            "panel.show.request",
            detail: "animated=\(shouldAnimateEntrance) alreadyVisible=\(panel.isVisible)"
        )
        ClipDockPerformanceLog.measure("panel.show.orderWindow") {
            panel.makeKeyAndOrderFront(nil)
        }
        focusContentView()
        startOutsideClickMonitoring()

        guard shouldAnimateEntrance else {
            cancelPanelAnimation()
            panel.setFrame(finalFrame, display: true)
            ClipDockPerformanceLog.finish("panel.show.finished", start: showStart, detail: "animated=false")
            return
        }

        startPanelFrameAnimation(
            name: "show",
            from: startFrame,
            to: finalFrame,
            duration: PanelPresentationAnimation.showDuration,
            timing: .easeInOut,
            generation: generation
        ) { [weak self] in
            guard let self, self.isPanelPresented else { return }
            self.panel.setFrame(finalFrame, display: true)
            self.panel.alphaValue = 1
            ClipDockPerformanceLog.finish("panel.show.finished", start: showStart, detail: "animated=true")
        }
    }

    func hide(restoresPreviousApplicationFocus: Bool = true) {
        let hideStart = ClipDockPerformanceLog.mark()
        let wasPresented = isPanelPresented
        guard wasPresented || panel.isVisible else {
            previousFocusApplication = nil
            stopOutsideClickMonitoring()
            ClipDockPerformanceLog.finish("panel.hide.skipped", start: hideStart)
            return
        }

        let shouldRestoreFocus = wasPresented && restoresPreviousApplicationFocus
        let focusApplication = shouldRestoreFocus ? previousFocusApplication : nil
        previousFocusApplication = nil
        ClipDockPerformanceLog.measure("panel.hide.closePreview") {
            contentView.closePreviewPopover()
        }
        isPanelPresented = false
        stopOutsideClickMonitoring()
        ClipDockPerformanceLog.measure("panel.hide.restoreFocus") {
            restoreFocus(to: focusApplication)
        }

        guard panel.isVisible else {
            ClipDockPerformanceLog.finish("panel.hide.finished", start: hideStart, detail: "alreadyHidden=true")
            return
        }

        animationGeneration += 1
        let generation = animationGeneration
        let startFrame = panel.frame
        let shownFrame = targetPanelFrameForCurrentPresentation() ?? panel.frame
        let hiddenFrame = PanelPresentationAnimation.dismissedFrame(for: shownFrame)

        startPanelFrameAnimation(
            name: "hide",
            from: startFrame,
            to: hiddenFrame,
            duration: PanelPresentationAnimation.hideDuration,
            timing: .easeIn,
            generation: generation
        ) { [weak self] in
            guard let self, !self.isPanelPresented else { return }
            self.panel.orderOut(nil)
            self.panel.setFrame(shownFrame, display: false)
            self.panel.alphaValue = 1
            ClipDockPerformanceLog.finish("panel.hide.finished", start: hideStart, detail: "animated=true")
        }
    }

    var hasBlockingPanelOperation: Bool {
        contentView.hasBlockingPanelOperation
    }

    @discardableResult
    func hideUnlessBlockingPanelOperation(restoresPreviousApplicationFocus: Bool = true) -> Bool {
        guard !hasBlockingPanelOperation else { return false }

        hide(restoresPreviousApplicationFocus: restoresPreviousApplicationFocus)
        return true
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

    func updateListState(
        _ result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool = false,
        scope: ClipboardListScope? = nil
    ) {
        contentView.updateListState(result, isFiltered: isFiltered, append: append, scope: scope)
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

    func setSourceIconHeaderColorWriter(_ writer: SourceAppIconHeaderColorWriter?) {
        contentView.updateSourceIconHeaderColorWriter(writer)
    }

    func updatePinboards(_ pinboards: [RustPinboardSummary]) {
        contentView.updatePinboards(pinboards)
    }

    func setPreviewPopoverEnabled(_ enabled: Bool) {
        contentView.setPreviewPopoverEnabled(enabled)
    }

    func setLinkWebPreviewEnabled(_ enabled: Bool) {
        contentView.setLinkWebPreviewEnabled(enabled)
    }

    func resetFiltersForCapturedItem() {
        contentView.resetFiltersForCapturedItem()
    }

    func clearPinboardSelectionIfNeeded(deletedPinboardID: String) {
        contentView.clearPinboardSelectionIfNeeded(deletedPinboardID: deletedPinboardID)
    }

    func invalidateCachedListPages() {
        contentView.invalidateCachedListPages()
    }

    func invalidateCachedPinboardListPages(pinboardID: String) {
        contentView.invalidateCachedPinboardListPages(pinboardID: pinboardID)
    }

    func setPreferredHeight(_ height: CGFloat) {
        applyPreferredHeight(height, persistUserChoice: true)
    }

    func setConfiguredDefaultHeight(_ height: CGFloat) {
        if let storedHeight = heightPreferenceStore.preferredPanelHeight {
            applyPreferredHeight(storedHeight, persistUserChoice: false)
        } else {
            applyPreferredHeight(height, persistUserChoice: false)
        }
    }

    private func applyPreferredHeight(_ height: CGFloat, persistUserChoice: Bool) {
        guard let screen = targetScreenForPresentation() else {
            preferredHeight = height
            contentView.updatePanelHeight(height)
            if persistUserChoice {
                heightPreferenceStore.preferredPanelHeight = height
            }
            return
        }

        preferredHeight = clampedHeight(height, for: screen)
        if persistUserChoice {
            heightPreferenceStore.preferredPanelHeight = preferredHeight
        }
        if panel.isVisible && isPanelPresented {
            applyPanelFrame(on: screen, height: preferredHeight, animate: true)
        } else {
            contentView.updatePanelHeight(preferredHeight)
        }
    }

    func positionOverDock() {
        guard let screen = targetScreenForPresentation() else { return }

        preferredHeight = clampedHeight(preferredHeight, for: screen)
        applyPanelFrame(on: screen, height: preferredHeight, animate: panel.isVisible && isPanelPresented)
    }

    private func beginHeightResize() {
        resizeStartHeight = panel.frame.height
        resizeScreen = panel.screen ?? targetScreenForPresentation()
        resizePerformanceStart = ClipDockPerformanceLog.mark()
        resizePerformanceEventCount = 0
        resizePerformanceSlowestFrameMilliseconds = 0
    }

    private func resizeHeight(deltaY: CGFloat) {
        guard let screen = resizeScreen ?? targetScreenForPresentation() else { return }

        preferredHeight = BottomPanelGeometryPlanner.resizedHeight(
            startHeight: resizeStartHeight,
            deltaY: deltaY,
            screenHeight: screen.frame.height
        )
        let frameStart = ClipDockPerformanceLog.mark()
        applyPanelFrame(on: screen, height: preferredHeight, animate: false)
        let frameMilliseconds = ClipDockPerformanceLog.milliseconds(since: frameStart)
        resizePerformanceEventCount += 1
        resizePerformanceSlowestFrameMilliseconds = max(
            resizePerformanceSlowestFrameMilliseconds,
            frameMilliseconds
        )
        if frameMilliseconds >= 24 {
            ClipDockPerformanceLog.event(
                "panel.resize.slowFrame",
                detail: "durationMs=\(ClipDockPerformanceLog.format(frameMilliseconds)) height=\(ClipDockPerformanceLog.format(Double(preferredHeight)))"
            )
        }
    }

    private func endHeightResize() {
        heightPreferenceStore.preferredPanelHeight = preferredHeight
        resizeScreen = nil
        if let resizePerformanceStart {
            let totalMilliseconds = ClipDockPerformanceLog.milliseconds(since: resizePerformanceStart)
            ClipDockPerformanceLog.event(
                "panel.resize.finished",
                detail: [
                    "durationMs=\(ClipDockPerformanceLog.format(totalMilliseconds))",
                    "events=\(resizePerformanceEventCount)",
                    "slowestFrameMs=\(ClipDockPerformanceLog.format(resizePerformanceSlowestFrameMilliseconds))",
                    "height=\(ClipDockPerformanceLog.format(Double(preferredHeight)))"
                ].joined(separator: " ")
            )
        }
        resizePerformanceStart = nil
    }

    private func applyPanelFrame(on screen: NSScreen, height: CGFloat, animate: Bool) {
        let frame = targetPanelFrame(on: screen, height: height)

        contentView.updatePanelHeight(height)
        panel.setFrame(frame, display: true, animate: animate)
    }

    private func targetPanelFrameForCurrentPresentation() -> NSRect? {
        guard let screen = panel.screen ?? targetScreenForPresentation() else { return nil }
        return targetPanelFrame(on: screen, height: clampedHeight(preferredHeight, for: screen))
    }

    private func targetPanelFrame(on screen: NSScreen, height: CGFloat) -> NSRect {
        BottomPanelGeometryPlanner.frame(
            screenFrame: screen.frame,
            preferredHeight: height
        )
    }

    private func cancelPanelAnimation() {
        panelAnimationTask?.cancel()
        panelAnimationTask = nil
    }

    private func startPanelFrameAnimation(
        name: String,
        from startFrame: NSRect,
        to endFrame: NSRect,
        duration: TimeInterval,
        timing: PanelPresentationTiming,
        generation: Int,
        completion: @escaping @MainActor () -> Void
    ) {
        cancelPanelAnimation()

        guard startFrame != endFrame, duration > 0 else {
            panel.setFrame(endFrame, display: true)
            completion()
            return
        }

        panelAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let startTime = ProcessInfo.processInfo.systemUptime
            var frameCount = 0

            while !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                let linearProgress = min(max(elapsed / duration, 0), 1)
                let progress = timing.progress(for: CGFloat(linearProgress))
                let frame = PanelPresentationAnimation.interpolatedFrame(
                    from: startFrame,
                    to: endFrame,
                    progress: progress
                )
                frameCount += 1
                self.panel.setFrame(frame, display: true)

                if linearProgress >= 1 {
                    break
                }

                do {
                    try await Task.sleep(nanoseconds: PanelPresentationAnimation.frameIntervalNanoseconds)
                } catch {
                    if self.animationGeneration == generation {
                        self.panelAnimationTask = nil
                    }
                    return
                }
            }

            guard !Task.isCancelled, self.animationGeneration == generation else { return }
            self.panel.setFrame(endFrame, display: true)
            self.panelAnimationTask = nil
            ClipDockPerformanceLog.event(
                "panel.animation.finished",
                detail: "name=\(name) durationMs=\(ClipDockPerformanceLog.format((ProcessInfo.processInfo.systemUptime - startTime) * 1_000)) frames=\(frameCount)"
            )
            completion()
        }
    }

    private func rememberPreviousFocusApplicationIfNeeded() {
        guard !isPanelPresented,
              let application = focusApplicationProvider.frontmostPanelFocusApplication(),
              shouldRestoreFocus(to: application)
        else {
            return
        }

        previousFocusApplication = application
    }

    private func restoreFocus(to application: PanelFocusApplication?) {
        guard let application,
              shouldRestoreFocus(to: application)
        else {
            return
        }

        application.activateForPanelFocusRestore()
    }

    private func shouldRestoreFocus(to application: PanelFocusApplication) -> Bool {
        guard !application.isTerminated else { return false }
        if application.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        if let mainBundleIdentifier,
           application.bundleIdentifier == mainBundleIdentifier {
            return false
        }
        return true
    }

    private func focusContentView() {
        panel.makeKey()
        panel.makeFirstResponder(contentView)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPanelPresented, self.panel.isVisible else { return }
            self.repairContentFocusIfNeeded(orderWindow: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, self.isPanelPresented, self.panel.isVisible else { return }
            self.repairContentFocusIfNeeded(orderWindow: true)
        }
    }

    private func repairContentFocusIfNeeded(orderWindow: Bool) {
        guard panel.firstResponder !== contentView || !panel.isKeyWindow else { return }

        let start = ClipDockPerformanceLog.mark()
        if orderWindow {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.makeKey()
        }
        panel.makeFirstResponder(contentView)
        ClipDockPerformanceLog.finish(
            "panel.focus.repair",
            start: start,
            detail: "ordered=\(orderWindow) firstResponderRestored=\(panel.firstResponder === contentView)"
        )
    }

    private func clampedHeight(_ height: CGFloat, for screen: NSScreen) -> CGFloat {
        BottomPanelGeometryPlanner.clampedHeight(
            height,
            screenHeight: screen.frame.height
        )
    }

    private func configurePanel() {
        panel.contentView = makeFloatingPanelHostView(contentView: contentView)
        panel.isOpaque = false
        panel.alphaValue = 1
        panel.backgroundColor = .clear
        panel.hasShadow = false
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
        contentView.onHeightResizeEnded = { [weak self] in self?.endHeightResize() }
    }

    private func startOutsideClickMonitoring() {
        guard localOutsideClickMonitor == nil, globalOutsideClickMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let eventWindow = event.window
            let mouseLocation = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.hideIfClickIsOutsidePanel(eventWindow: eventWindow, mouseLocation: mouseLocation)
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let eventWindow = event.window
            let mouseLocation = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.hideIfClickIsOutsidePanel(eventWindow: eventWindow, mouseLocation: mouseLocation)
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

    private func hideIfClickIsOutsidePanel(eventWindow: NSWindow?, mouseLocation: CGPoint) {
        guard panel.isVisible else {
            stopOutsideClickMonitoring()
            return
        }

        if shouldHideForMouseDown(eventWindow: eventWindow, mouseLocation: mouseLocation) {
            hideUnlessBlockingPanelOperation(restoresPreviousApplicationFocus: false)
        }
    }

    private func shouldHideForMouseDown(eventWindow: NSWindow?, mouseLocation: CGPoint) -> Bool {
        if let eventWindow, eventWindow !== panel {
            return false
        }

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

    var smokePreferredHeight: CGFloat {
        preferredHeight
    }

    var smokePanelIsActuallyVisible: Bool {
        panel.isVisible
    }

    var smokePanelAlphaValue: CGFloat {
        panel.alphaValue
    }

    var smokePanelContentBackgroundAlpha: CGFloat {
        contentView.smokePanelContentBackgroundAlpha
    }

    var smokeHasBlockingPanelOperation: Bool {
        hasBlockingPanelOperation
    }

    func smokeWithBlockingPanelOperation(_ body: () -> Void) {
        contentView.smokeWithBlockingPanelOperation(body)
    }

    func smokeBlockingPanelModalProbe() -> (
        outerDuring: Bool,
        nestedDuring: Bool,
        afterNested: Bool,
        afterOuter: Bool,
        responses: [NSApplication.ModalResponse]
    ) {
        contentView.smokeBlockingPanelModalProbe()
    }

    var smokeHasActivePanelAnimation: Bool {
        panelAnimationTask != nil
    }

    var smokeEntranceAnimationFrame: CGRect {
        PanelPresentationAnimation.entranceFrame(for: panel.frame)
    }

    var smokeHiddenAnimationFrame: CGRect {
        PanelPresentationAnimation.dismissedFrame(for: panel.frame)
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

    @discardableResult
    func smokeSendSpaceToFirstResponder() -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: UInt16(kVK_Space)
        ) else {
            return false
        }

        panel.firstResponder?.keyDown(with: event)
        return true
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
            hideUnlessBlockingPanelOperation(restoresPreviousApplicationFocus: false)
        }
    }

    func smokeResizePanelHeight(deltaY: CGFloat) {
        beginHeightResize()
        resizeHeight(deltaY: deltaY)
        endHeightResize()
    }

    func smokeHandleAppOwnedNonPanelMouseDown(mouseLocation: CGPoint) {
        let appOwnedWindow = NSWindow(
            contentRect: NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 80, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        if shouldHideForMouseDown(eventWindow: appOwnedWindow, mouseLocation: mouseLocation) {
            hideUnlessBlockingPanelOperation(restoresPreviousApplicationFocus: false)
        }
    }

    var smokePreviewScreenFrame: CGRect? {
        contentView.smokePreviewScreenFrame
    }
}
