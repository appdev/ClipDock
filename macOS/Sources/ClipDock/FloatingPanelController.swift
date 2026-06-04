import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp
import QuartzCore

private enum PanelPresentationAnimation {
    static let showDuration: TimeInterval = 0.16
    static let hideDuration: TimeInterval = 0.18
    static let hiddenOpacity: Float = 0.92
    static let layerAnimationKey = "clipdock.panel.presentation"

    static func entranceFrame(for frame: NSRect) -> NSRect {
        offscreenFrame(for: frame)
    }

    static func dismissedFrame(for frame: NSRect) -> NSRect {
        offscreenFrame(for: frame)
    }

    static func hiddenTranslationY(shownFrame: NSRect, hiddenFrame: NSRect) -> CGFloat {
        hiddenFrame.minY - shownFrame.minY
    }

    private static let offscreenMargin: CGFloat = 12

    private static func offscreenFrame(for frame: NSRect) -> NSRect {
        frame.offsetBy(dx: 0, dy: -(frame.height + offscreenMargin))
    }
}

struct PanelPresentationAnimationSample: Equatable {
    let name: String
    let durationMilliseconds: Double
    let frameCount: Int
}

struct PanelPresentationAnimationCompletionSnapshot: Equatable {
    let name: String
    let panelIsVisible: Bool
    let hostTransformTranslationY: CGFloat
    let hostTransformIsIdentity: Bool
    let hostOpacity: Float
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

    var mediaTimingFunction: CAMediaTimingFunction {
        switch self {
        case .easeIn:
            return CAMediaTimingFunction(controlPoints: 0.55, 0, 1, 0.45)
        case .easeInOut:
            return CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
        case .easeOut:
            return CAMediaTimingFunction(controlPoints: 0, 0.55, 0.45, 1)
        }
    }
}

private final class PanelAnimationCompletionDelegate: NSObject, CAAnimationDelegate {
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        completion(flag)
    }
}

private extension CATransform3D {
    var isApproximatelyIdentity: Bool {
        let identity = CATransform3DIdentity
        let tolerance: CGFloat = 0.0001
        return abs(m11 - identity.m11) < tolerance
            && abs(m12 - identity.m12) < tolerance
            && abs(m13 - identity.m13) < tolerance
            && abs(m14 - identity.m14) < tolerance
            && abs(m21 - identity.m21) < tolerance
            && abs(m22 - identity.m22) < tolerance
            && abs(m23 - identity.m23) < tolerance
            && abs(m24 - identity.m24) < tolerance
            && abs(m31 - identity.m31) < tolerance
            && abs(m32 - identity.m32) < tolerance
            && abs(m33 - identity.m33) < tolerance
            && abs(m34 - identity.m34) < tolerance
            && abs(m41 - identity.m41) < tolerance
            && abs(m42 - identity.m42) < tolerance
            && abs(m43 - identity.m43) < tolerance
            && abs(m44 - identity.m44) < tolerance
    }
}

@MainActor
private final class PanelAnimationFrameSampler {
    private var timer: Timer?
    private(set) var frameCount = 0
    let samplingMode = "tickTimer"

    func start() {
        _ = stop()
        frameCount = 1
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.frameCount += 1
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() -> Int {
        timer?.invalidate()
        timer = nil
        return frameCount
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
    private let presentationHostView: NSView
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
    private var pendingCopySelectionCollapseAfterHide = false
    private var activePanelAnimation: ActivePanelAnimation?
    private var semanticPanelFrame: NSRect?
    private var pendingListUpdateAfterPresentation: PendingListUpdate?
    private var presentationAnimationSamples: [PanelPresentationAnimationSample] = []
    private var presentationAnimationCompletionObserver: ((PanelPresentationAnimationCompletionSnapshot) -> Void)?
    private var resizePerformanceStart: TimeInterval?
    private var resizePerformanceEventCount = 0
    private var resizePerformanceSlowestFrameMilliseconds = 0.0

    var onRuntimeAction: ((PanelRuntimeAction) -> Void)?

    private struct ActivePanelAnimation {
        let generation: Int
        let name: String
        let startTime: TimeInterval
        let sampler: PanelAnimationFrameSampler
        let delegate: PanelAnimationCompletionDelegate
    }

    private struct PendingListUpdate {
        let result: Result<RustCoreListResult, RustCoreError>
        let isFiltered: Bool
        let append: Bool
        let scope: ClipboardListScope?
        let preserveScrollPositionOnStructuralChange: Bool
    }

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
        presentationHostView = makeFloatingPanelHostView(contentView: contentView)
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
        pendingCopySelectionCollapseAfterHide = false
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
        let hiddenFrame = PanelPresentationAnimation.entranceFrame(for: finalFrame)
        let startingLayerState = captureCurrentPresentationLayerState()
        let fromTransform = startingLayerState?.transform
            ?? CATransform3DMakeTranslation(
                0,
                PanelPresentationAnimation.hiddenTranslationY(shownFrame: finalFrame, hiddenFrame: hiddenFrame),
                0
            )
        let fromOpacity = startingLayerState?.opacity ?? PanelPresentationAnimation.hiddenOpacity

        ClipDockPerformanceLog.event(
            "panel.show.request",
            detail: "animated=\(shouldAnimateEntrance) alreadyVisible=\(panel.isVisible)"
        )
        configurePresentationWindow(shownFrame: finalFrame)
        if shouldAnimateEntrance {
            setPresentationLayerState(transform: fromTransform, opacity: fromOpacity)
        }
        ClipDockPerformanceLog.measure("panel.show.orderWindow") {
            panel.makeKeyAndOrderFront(nil)
        }
        focusContentView()
        startOutsideClickMonitoring()

        guard shouldAnimateEntrance else {
            cancelPanelAnimation()
            panel.setFrame(finalFrame, display: true)
            semanticPanelFrame = finalFrame
            configurePresentationHostForStableShownFrame(finalFrame)
            ClipDockPerformanceLog.finish("panel.show.finished", start: showStart, detail: "animated=false")
            flushPendingListUpdateAfterPresentationIfNeeded()
            return
        }

        startPanelLayerPresentationAnimation(
            name: "show",
            fromTransform: fromTransform,
            toTransform: CATransform3DIdentity,
            fromOpacity: fromOpacity,
            toOpacity: 1,
            shownFrame: finalFrame,
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

    func hide(
        restoresPreviousApplicationFocus: Bool = true,
        afterHidden: (() -> Void)? = nil
    ) {
        hide(
            restoresPreviousApplicationFocus: restoresPreviousApplicationFocus,
            restoresFocusAfterWindowOrderOut: false,
            afterHidden: afterHidden
        )
    }

    private func hide(
        restoresPreviousApplicationFocus: Bool,
        restoresFocusAfterWindowOrderOut: Bool,
        afterHidden: (() -> Void)? = nil
    ) {
        let hideStart = ClipDockPerformanceLog.mark()
        let wasPresented = isPanelPresented
        guard wasPresented || panel.isVisible else {
            previousFocusApplication = nil
            stopOutsideClickMonitoring()
            ClipDockPerformanceLog.finish("panel.hide.skipped", start: hideStart)
            finishHiddenTransition(afterHidden: afterHidden)
            return
        }

        let shouldRestoreFocus = wasPresented && restoresPreviousApplicationFocus
        let focusApplication = shouldRestoreFocus ? previousFocusApplication : nil
        let shouldRestoreFocusAfterWindowOrderOut = focusApplication != nil && restoresFocusAfterWindowOrderOut
        previousFocusApplication = nil
        ClipDockPerformanceLog.measure("panel.hide.closePreview") {
            contentView.closePreviewPopover()
        }
        isPanelPresented = false
        stopOutsideClickMonitoring()
        if !shouldRestoreFocusAfterWindowOrderOut {
            restoreFocusToPreviousApplication(focusApplication, stage: "panel.hide.restoreFocus")
        }

        guard panel.isVisible else {
            ClipDockPerformanceLog.finish("panel.hide.finished", start: hideStart, detail: "alreadyHidden=true")
            finishHiddenPanel(
                afterHidden: afterHidden,
                focusApplication: focusApplication,
                restoresFocusAfterWindowOrderOut: shouldRestoreFocusAfterWindowOrderOut
            )
            return
        }

        animationGeneration += 1
        let generation = animationGeneration
        let shownFrame = targetPanelFrameForCurrentPresentation() ?? panel.frame
        let hiddenFrame = PanelPresentationAnimation.dismissedFrame(for: shownFrame)
        let startingLayerState = captureCurrentPresentationLayerState()
        configurePresentationWindow(shownFrame: shownFrame)

        startPanelLayerPresentationAnimation(
            name: "hide",
            fromTransform: startingLayerState?.transform ?? CATransform3DIdentity,
            toTransform: CATransform3DMakeTranslation(
                0,
                PanelPresentationAnimation.hiddenTranslationY(shownFrame: shownFrame, hiddenFrame: hiddenFrame),
                0
            ),
            fromOpacity: startingLayerState?.opacity ?? 1,
            toOpacity: PanelPresentationAnimation.hiddenOpacity,
            shownFrame: shownFrame,
            duration: PanelPresentationAnimation.hideDuration,
            timing: .easeIn,
            generation: generation,
            resetPresentationLayerBeforeCompletion: false
        ) { [weak self] in
            guard let self, !self.isPanelPresented else { return }
            self.panel.orderOut(nil)
            self.panel.setFrame(shownFrame, display: false)
            self.semanticPanelFrame = shownFrame
            self.configurePresentationHostForStableShownFrame(shownFrame)
            ClipDockPerformanceLog.finish("panel.hide.finished", start: hideStart, detail: "animated=true")
            self.finishHiddenPanel(
                afterHidden: afterHidden,
                focusApplication: focusApplication,
                restoresFocusAfterWindowOrderOut: shouldRestoreFocusAfterWindowOrderOut
            )
        }
    }

    private func finishHiddenPanel(
        afterHidden: (() -> Void)?,
        focusApplication: PanelFocusApplication?,
        restoresFocusAfterWindowOrderOut: Bool
    ) {
        if restoresFocusAfterWindowOrderOut {
            restoreFocusToPreviousApplication(
                focusApplication,
                stage: "panel.hide.restoreFocusAfterOrderOut"
            )
        }
        finishHiddenTransition(afterHidden: afterHidden)
    }

    private func restoreFocusToPreviousApplication(
        _ focusApplication: PanelFocusApplication?,
        stage: String
    ) {
        ClipDockPerformanceLog.measure(stage) {
            restoreFocus(to: focusApplication)
        }
    }

    func hideAfterCopyingSelection(restoresPreviousApplicationFocus: Bool = true) {
        pendingCopySelectionCollapseAfterHide = true
        hide(
            restoresPreviousApplicationFocus: restoresPreviousApplicationFocus,
            restoresFocusAfterWindowOrderOut: true
        )
    }

    private func finishHiddenTransition(afterHidden: (() -> Void)?) {
        if pendingCopySelectionCollapseAfterHide {
            pendingCopySelectionCollapseAfterHide = false
            contentView.collapseCopySelectionAfterPanelHidden()
        }
        afterHidden?()
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
        scope: ClipboardListScope? = nil,
        preserveScrollPositionOnStructuralChange: Bool = false
    ) {
        if shouldDeferListUpdateUntilPresentationCompletes(append: append) {
            pendingListUpdateAfterPresentation = PendingListUpdate(
                result: result,
                isFiltered: isFiltered,
                append: append,
                scope: scope,
                preserveScrollPositionOnStructuralChange: preserveScrollPositionOnStructuralChange
            )
            ClipDockPerformanceLog.event(
                "panel.listUpdate.deferred",
                detail: "append=\(append) scope=\(scope.map(String.init(describing:)) ?? "nil")"
            )
            return
        }

        contentView.updateListState(
            result,
            isFiltered: isFiltered,
            append: append,
            scope: scope,
            preserveScrollPositionOnStructuralChange: preserveScrollPositionOnStructuralChange
        )
    }

    func updateLoadingMoreState(_ isLoading: Bool) {
        contentView.updateLoadingMoreState(isLoading)
    }

    func setSyncStatusProvider(_ provider: @escaping (RustClipboardItemSummary) -> PanelItemSyncStatus) {
        contentView.setSyncStatusProvider(provider)
    }

    func refreshSyncStatusDecorations() {
        contentView.refreshSyncStatusDecorations()
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

    func updateShortcutPreferences(_ shortcuts: RustShortcutsPreferences) {
        contentView.updateShortcutPreferences(shortcuts)
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

        cancelPanelAnimation()
        contentView.updatePanelHeight(height)
        panel.setFrame(frame, display: true, animate: animate)
        semanticPanelFrame = frame
        configurePresentationHostForStableShownFrame(frame)
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

    private func configurePresentationWindow(shownFrame: NSRect) {
        cancelPanelAnimation()
        semanticPanelFrame = shownFrame
        if panel.frame != shownFrame {
            panel.setFrame(shownFrame, display: true)
        }
        presentationHostView.frame = NSRect(origin: .zero, size: shownFrame.size)
        contentView.frame = presentationHostView.bounds
        configurePresentationWindowMask()
    }

    private func configurePresentationHostForStableShownFrame(_ shownFrame: NSRect) {
        semanticPanelFrame = shownFrame
        presentationHostView.frame = NSRect(origin: .zero, size: shownFrame.size)
        contentView.frame = presentationHostView.bounds
        configurePresentationWindowMask()
        resetPresentationLayerState()
    }

    private func configurePresentationWindowMask() {
        guard let maskView = presentationHostView.superview else { return }
        maskView.wantsLayer = true
        guard let layer = maskView.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = NSColor.clear.cgColor
        layer.cornerRadius = FloatingPanelContentView.panelBackgroundCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        CATransaction.commit()
    }

    private func resetPresentationLayerState() {
        guard let layer = presentationHostView.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: PanelPresentationAnimation.layerAnimationKey)
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        layer.shouldRasterize = false
        CATransaction.commit()
    }

    private func setPresentationLayerState(transform: CATransform3D, opacity: Float) {
        guard let layer = presentationHostView.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        layer.opacity = opacity
        CATransaction.commit()
    }

    private func captureCurrentPresentationLayerState() -> (transform: CATransform3D, opacity: Float)? {
        guard let layer = presentationHostView.layer else { return nil }

        if let presentationLayer = layer.presentation() {
            let transform = presentationLayer.transform
            let opacity = presentationLayer.opacity
            layer.removeAnimation(forKey: PanelPresentationAnimation.layerAnimationKey)
            setPresentationLayerState(transform: transform, opacity: opacity)
            return (transform, opacity)
        }

        return (layer.transform, layer.opacity)
    }

    private func cancelPanelAnimation() {
        guard let activePanelAnimation else { return }

        _ = activePanelAnimation.sampler.stop()
        self.activePanelAnimation = nil
        presentationHostView.layer?.removeAnimation(forKey: PanelPresentationAnimation.layerAnimationKey)
    }

    private func shouldDeferListUpdateUntilPresentationCompletes(append: Bool) -> Bool {
        activePanelAnimation != nil && !append && contentView.hasRenderedNonEmptyListContent
    }

    private func flushPendingListUpdateAfterPresentationIfNeeded() {
        guard let pendingListUpdateAfterPresentation else { return }

        self.pendingListUpdateAfterPresentation = nil
        contentView.updateListState(
            pendingListUpdateAfterPresentation.result,
            isFiltered: pendingListUpdateAfterPresentation.isFiltered,
            append: pendingListUpdateAfterPresentation.append,
            scope: pendingListUpdateAfterPresentation.scope,
            preserveScrollPositionOnStructuralChange: pendingListUpdateAfterPresentation.preserveScrollPositionOnStructuralChange
        )
        ClipDockPerformanceLog.event(
            "panel.listUpdate.flushed",
            detail: "append=\(pendingListUpdateAfterPresentation.append) scope=\(pendingListUpdateAfterPresentation.scope.map(String.init(describing:)) ?? "nil")"
        )
    }

    private func startPanelLayerPresentationAnimation(
        name: String,
        fromTransform: CATransform3D,
        toTransform: CATransform3D,
        fromOpacity: Float,
        toOpacity: Float,
        shownFrame: NSRect,
        duration: TimeInterval,
        timing: PanelPresentationTiming,
        generation: Int,
        resetPresentationLayerBeforeCompletion: Bool = true,
        completion: @escaping @MainActor () -> Void
    ) {
        cancelPanelAnimation()

        guard duration > 0,
              let layer = presentationHostView.layer
        else {
            panel.setFrame(shownFrame, display: true)
            semanticPanelFrame = shownFrame
            configurePresentationHostForStableShownFrame(shownFrame)
            completion()
            flushPendingListUpdateAfterPresentationIfNeeded()
            return
        }

        if panel.frame != shownFrame {
            panel.setFrame(shownFrame, display: true)
        }
        semanticPanelFrame = shownFrame
        presentationHostView.frame = NSRect(origin: .zero, size: shownFrame.size)
        contentView.frame = presentationHostView.bounds
        configurePresentationWindowMask()

        let sampler = PanelAnimationFrameSampler()
        sampler.start()
        let startTime = ProcessInfo.processInfo.systemUptime
        let delegate = PanelAnimationCompletionDelegate { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self,
                      finished,
                      self.animationGeneration == generation,
                      self.activePanelAnimation?.generation == generation
                else {
                    return
                }

                let frameCount = self.activePanelAnimation?.sampler.stop() ?? 0
                self.activePanelAnimation = nil
                self.panel.setFrame(shownFrame, display: true)
                if resetPresentationLayerBeforeCompletion {
                    self.configurePresentationHostForStableShownFrame(shownFrame)
                }
                if let observer = self.presentationAnimationCompletionObserver {
                    self.presentationAnimationCompletionObserver = nil
                    let layer = self.presentationHostView.layer
                    let transform = layer?.transform ?? CATransform3DIdentity
                    observer(PanelPresentationAnimationCompletionSnapshot(
                        name: name,
                        panelIsVisible: self.panel.isVisible,
                        hostTransformTranslationY: transform.m42,
                        hostTransformIsIdentity: transform.isApproximatelyIdentity,
                        hostOpacity: layer?.opacity ?? 0
                    ))
                }
                let durationMilliseconds = (ProcessInfo.processInfo.systemUptime - startTime) * 1_000
                self.presentationAnimationSamples.append(PanelPresentationAnimationSample(
                    name: name,
                    durationMilliseconds: durationMilliseconds,
                    frameCount: frameCount
                ))
                ClipDockPerformanceLog.event(
                    "panel.animation.finished",
                    detail: [
                        "name=\(name)",
                        "driver=coreAnimation",
                        "samplingMode=\(sampler.samplingMode)",
                        "durationMs=\(ClipDockPerformanceLog.format(durationMilliseconds))",
                        "frames=\(frameCount)"
                    ].joined(separator: " ")
                )
                completion()
                self.flushPendingListUpdateAfterPresentationIfNeeded()
            }
        }

        activePanelAnimation = ActivePanelAnimation(
            generation: generation,
            name: name,
            startTime: startTime,
            sampler: sampler,
            delegate: delegate
        )

        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = NSValue(caTransform3D: fromTransform)
        transformAnimation.toValue = NSValue(caTransform3D: toTransform)
        transformAnimation.duration = duration
        transformAnimation.timingFunction = timing.mediaTimingFunction

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = fromOpacity
        opacityAnimation.toValue = toOpacity
        opacityAnimation.duration = duration
        opacityAnimation.timingFunction = timing.mediaTimingFunction

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [transformAnimation, opacityAnimation]
        animationGroup.duration = duration
        animationGroup.timingFunction = timing.mediaTimingFunction
        animationGroup.isRemovedOnCompletion = true
        animationGroup.delegate = delegate

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shouldRasterize = false
        layer.allowsEdgeAntialiasing = true
        layer.transform = toTransform
        layer.opacity = toOpacity
        layer.add(animationGroup, forKey: PanelPresentationAnimation.layerAnimationKey)
        CATransaction.commit()
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
        panel.contentView = presentationHostView
        configurePresentationWindowMask()
        panel.isOpaque = false
        panel.alphaValue = 1
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
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
            panelFrame: semanticPanelFrame ?? panel.frame
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
        semanticPanelFrame ?? panel.frame
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

    var smokePresentationWindowFrame: CGRect {
        panel.frame
    }

    var smokePresentationHostFrame: CGRect {
        presentationHostView.frame
    }

    var smokePresentationHostTransformIsIdentity: Bool {
        guard let transform = presentationHostView.layer?.transform else { return false }
        return transform.isApproximatelyIdentity
    }

    var smokePresentationHostOpacity: Float {
        presentationHostView.layer?.opacity ?? 0
    }

    var smokePresentationHostIsWindowContentView: Bool {
        panel.contentView === presentationHostView
    }

    var smokePresentationWindowHasRoundedMask: Bool {
        guard let layer = presentationHostView.superview?.layer else { return false }

        return layer.masksToBounds
            && abs(layer.cornerRadius - FloatingPanelContentView.panelBackgroundCornerRadius) < 0.001
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
        activePanelAnimation != nil
    }

    var smokePresentationAnimationSamples: [PanelPresentationAnimationSample] {
        presentationAnimationSamples
    }

    func smokeResetPresentationAnimationSamples() {
        presentationAnimationSamples.removeAll()
    }

    func smokeObserveNextPresentationAnimationCompletion(
        _ observer: @escaping (PanelPresentationAnimationCompletionSnapshot) -> Void
    ) {
        presentationAnimationCompletionObserver = observer
    }

    var smokeEntranceAnimationFrame: CGRect {
        PanelPresentationAnimation.entranceFrame(for: semanticPanelFrame ?? panel.frame)
    }

    var smokeHiddenAnimationFrame: CGRect {
        PanelPresentationAnimation.dismissedFrame(for: semanticPanelFrame ?? panel.frame)
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
