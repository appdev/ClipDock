import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp

enum PanelLevelMode: String, CaseIterable {
    case floating = "Floating"
    case statusBar = "StatusBar"
    case aboveDock = "AboveDock"

    var title: String {
        switch self {
        case .floating:
            return "普通悬浮"
        case .statusBar:
            return "状态栏层级"
        case .aboveDock:
            return "高于 Dock"
        }
    }

    var detail: String {
        switch self {
        case .floating:
            return "NSWindow.Level.floating，适合大多数工具面板"
        case .statusBar:
            return "NSWindow.Level.statusBar，层级更高"
        case .aboveDock:
            return "CGWindowLevel(.dockWindow) + 1，可压到 Dock 层级之上"
        }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class HeightResizeHandleView: NSView {
    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    private let indicatorLayer = CALayer()
    private var initialMouseY: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            applyTheme()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        let indicatorSize = CGSize(width: isHovering ? 74 : 58, height: 3)
        indicatorLayer.frame = CGRect(
            x: bounds.midX - indicatorSize.width / 2,
            y: bounds.midY - indicatorSize.height / 2,
            width: indicatorSize.width,
            height: indicatorSize.height
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsLayout = true
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseY = NSEvent.mouseLocation.y
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDragChanged?(NSEvent.mouseLocation.y - initialMouseY)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
    }

    private func configureAppearance() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        indicatorLayer.cornerRadius = 1.5
        layer?.addSublayer(indicatorLayer)
        applyTheme()
    }

    private func applyTheme() {
        let alpha: CGFloat = isHovering ? 0.28 : 0
        indicatorLayer.backgroundColor = ClipShelfTheme.current(for: self)
            .panel
            .resizeHandleColor
            .withAlphaComponent(alpha)
            .cgColor
    }
}

private final class HorizontalOnlyClipView: NSClipView {
    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: newOrigin.x, y: 0))
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: newOrigin.x, y: 0))
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        constrainedBounds.origin.y = 0
        return constrainedBounds
    }
}

final class HorizontalWheelScrollView: NSScrollView {
    var onScrollDidChange: (() -> Void)?
    private var isApplyingScrollerVisibility = false

    private enum ScrollExecution {
        static let minimumVisibleMove: CGFloat = 0.5
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installHorizontalOnlyClipView()
        suppressScrollers()
        configureScrollObservation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installHorizontalOnlyClipView()
        suppressScrollers()
        configureScrollObservation()
    }

    override func tile() {
        super.tile()
        suppressScrollers()
    }

    override func scrollWheel(with event: NSEvent) {
        guard documentView != nil else {
            super.scrollWheel(with: event)
            return
        }

        let plan = PanelHorizontalScrollPlanner.plan(for: PanelHorizontalScrollInput(
            horizontalDelta: event.scrollingDeltaX,
            verticalDelta: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        ))

        switch plan.mode {
        case .none:
            return

        case .nativeHorizontal:
            if scrollUsingSystemEvent(event) {
                return
            }

            _ = scrollHorizontally(by: plan.contentOffsetDelta)

        case .projectedVertical:
            if let rewrittenEvent = ScrollWheelAxisRewriter.eventByProjectingVerticalAxis(from: event),
               scrollUsingSystemEvent(rewrittenEvent) {
                return
            }

            _ = scrollHorizontally(by: plan.contentOffsetDelta)
        }
    }

    @discardableResult
    private func scrollHorizontally(by delta: CGFloat) -> Bool {
        guard let documentView else { return false }

        let initialHorizontalOrigin = contentView.bounds.origin.x
        let minimumX: CGFloat = 0
        let maximumX = max(minimumX, documentView.frame.width - contentView.bounds.width)
        let targetX = min(max(initialHorizontalOrigin + delta, minimumX), maximumX)
        guard abs(targetX - initialHorizontalOrigin) >= ScrollExecution.minimumVisibleMove else {
            return false
        }

        contentView.scroll(to: NSPoint(x: targetX, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
        return true
    }

    private func scrollUsingSystemEvent(_ event: NSEvent) -> Bool {
        let initialOriginX = contentView.bounds.origin.x
        super.scrollWheel(with: event)
        return abs(contentView.bounds.origin.x - initialOriginX) >= ScrollExecution.minimumVisibleMove
    }

    private func configureScrollObservation() {
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    private func installHorizontalOnlyClipView() {
        guard !(contentView is HorizontalOnlyClipView) else { return }

        let originalClipView = contentView
        let originalDocumentView = documentView
        let horizontalClipView = HorizontalOnlyClipView(frame: originalClipView.frame)
        horizontalClipView.autoresizingMask = originalClipView.autoresizingMask
        horizontalClipView.drawsBackground = originalClipView.drawsBackground
        horizontalClipView.backgroundColor = originalClipView.backgroundColor
        horizontalClipView.postsBoundsChangedNotifications = originalClipView.postsBoundsChangedNotifications
        contentView = horizontalClipView
        documentView = originalDocumentView
    }

    private func suppressScrollers() {
        guard !isApplyingScrollerVisibility else { return }
        isApplyingScrollerVisibility = true
        defer { isApplyingScrollerVisibility = false }

        autohidesScrollers = true
        scrollerStyle = .overlay
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScroller?.isHidden = true
        verticalScroller?.isHidden = true
        horizontalScroller = nil
        verticalScroller = nil
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        onScrollDidChange?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private enum ScrollWheelAxisRewriter {
    static func eventByProjectingVerticalAxis(from event: NSEvent) -> NSEvent? {
        guard let rewrittenCGEvent = event.cgEvent?.copy() else { return nil }

        swapScrollWheelFields(
            event: rewrittenCGEvent,
            axis1: .scrollWheelEventDeltaAxis1,
            axis2: .scrollWheelEventDeltaAxis2,
            fallbackAxis1: integerDelta(event.scrollingDeltaY),
            fallbackAxis2: integerDelta(event.scrollingDeltaX)
        )
        swapScrollWheelFields(
            event: rewrittenCGEvent,
            axis1: .scrollWheelEventPointDeltaAxis1,
            axis2: .scrollWheelEventPointDeltaAxis2,
            fallbackAxis1: 0,
            fallbackAxis2: 0
        )
        swapScrollWheelFields(
            event: rewrittenCGEvent,
            axis1: .scrollWheelEventFixedPtDeltaAxis1,
            axis2: .scrollWheelEventFixedPtDeltaAxis2,
            fallbackAxis1: 0,
            fallbackAxis2: 0
        )

        return NSEvent(cgEvent: rewrittenCGEvent)
    }

    private static func swapScrollWheelFields(
        event: CGEvent,
        axis1: CGEventField,
        axis2: CGEventField,
        fallbackAxis1: Int64,
        fallbackAxis2: Int64
    ) {
        let originalAxis1 = event.getIntegerValueField(axis1)
        let originalAxis2 = event.getIntegerValueField(axis2)
        event.setIntegerValueField(axis1, value: originalAxis2 == 0 ? fallbackAxis2 : originalAxis2)
        event.setIntegerValueField(axis2, value: originalAxis1 == 0 ? fallbackAxis1 : originalAxis1)
    }

    private static func integerDelta(_ delta: CGFloat) -> Int64 {
        Int64(delta.rounded(.toNearestOrAwayFromZero))
    }
}

final class ClipboardItemCardBox: NSBox {
    var itemID: String?
    var onSelect: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    private weak var selectionHeaderView: NSView?
    private weak var typeHeaderLabel: NSTextField?
    private weak var timeLabel: NSTextField?
    private weak var commandIndexLabel: NSTextField?
    private var unselectedHeaderColor: NSColor = .clear
    private var themeSelectionBorderColor: NSColor = .systemBlue
    private var themeHeaderTextColor: NSColor = .white
    private var themeHeaderSecondaryTextColor: NSColor = NSColor.white.withAlphaComponent(0.80)
    private let selectionBorderLayer = CALayer()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        contentView?.layer?.contentsScale = layer?.contentsScale ?? 2
        selectionBorderLayer.contentsScale = layer?.contentsScale ?? 2
    }

    override func layout() {
        super.layout()
        updateSelectionBorderLayerLayout()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }

        onSelect?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    func prepareForRemoval() {
        itemID = nil
        onSelect = nil
        onDoubleClick = nil
        onContextMenu = nil
        toolTip = nil
        identifier = nil
        commandIndexLabel = nil
        selectionHeaderView = nil
        typeHeaderLabel = nil
        timeLabel = nil
    }

    func configureSelectionAppearance(
        headerView: NSView,
        typeHeaderLabel: NSTextField,
        timeLabel: NSTextField,
        unselectedHeaderColor: NSColor,
        selectionBorderColor: NSColor,
        headerTextColor: NSColor,
        headerSecondaryTextColor: NSColor,
        isSelected: Bool
    ) {
        self.selectionHeaderView = headerView
        self.typeHeaderLabel = typeHeaderLabel
        self.timeLabel = timeLabel
        self.unselectedHeaderColor = unselectedHeaderColor
        self.themeSelectionBorderColor = selectionBorderColor
        self.themeHeaderTextColor = headerTextColor
        self.themeHeaderSecondaryTextColor = headerSecondaryTextColor
        installSelectionBorderLayerIfNeeded()
        applySelection(isSelected)
    }

    func configureCommandIndexLabel(_ label: NSTextField) {
        commandIndexLabel = label
        setCommandIndexText(nil)
    }

    func setCommandIndexText(_ text: String?) {
        commandIndexLabel?.stringValue = text ?? ""
        commandIndexLabel?.isHidden = text == nil
    }

    func applySelection(_ isSelected: Bool) {
        borderColor = .clear
        borderWidth = 0
        withoutSelectionBorderAnimation {
            selectionBorderLayer.isHidden = !isSelected
            selectionBorderLayer.borderWidth = isSelected ? 4 : 0
            selectionBorderLayer.borderColor = themeSelectionBorderColor.cgColor
        }
        selectionHeaderView?.layer?.backgroundColor = unselectedHeaderColor.cgColor
        selectionHeaderView?.layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        typeHeaderLabel?.textColor = themeHeaderTextColor
        timeLabel?.textColor = themeHeaderSecondaryTextColor
        needsDisplay = true
    }

    private func installSelectionBorderLayerIfNeeded() {
        guard selectionBorderLayer.superlayer == nil else { return }
        withoutSelectionBorderAnimation {
            selectionBorderLayer.backgroundColor = NSColor.clear.cgColor
            selectionBorderLayer.masksToBounds = false
            selectionBorderLayer.zPosition = 100
            selectionBorderLayer.cornerRadius = cornerRadius
            selectionBorderLayer.frame = bounds
            selectionBorderLayer.contentsScale = layer?.contentsScale ?? 2
        }
        layer?.addSublayer(selectionBorderLayer)
    }

    private func updateSelectionBorderLayerLayout() {
        withoutSelectionBorderAnimation {
            selectionBorderLayer.frame = bounds
            selectionBorderLayer.cornerRadius = cornerRadius
        }
    }

    private func withoutSelectionBorderAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}


enum MenuIcon {
    static func image(named symbolName: String, title: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: title)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(
        title: String,
        imageName: String? = nil,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [],
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(performAction(_:)), keyEquivalent: keyEquivalent)
        target = self
        keyEquivalentModifierMask = modifierMask
        image = imageName.flatMap { MenuIcon.image(named: $0, title: title) }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func performAction(_ sender: Any?) {
        handler()
    }

    func triggerForSmoke() {
        handler()
    }
}

class PanelActionButton: NSButton {
    var onPress: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        highlight(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.highlight(false)
        }
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

final class PinboardChipButton: PanelActionButton {
    var pinboardID: String?
    var itemType: String?
    var chipTitleText = "" {
        didSet {
            title = chipTitleText
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var chipDotColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var chipSymbolName: String? {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var chipIsSelected = false {
        didSet { needsDisplay = true }
    }
    var chipDrawsSelectionPill = false {
        didSet { needsDisplay = true }
    }
    var chipIsRenaming = false {
        didSet { needsDisplay = true }
    }
    var chipTextColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }
    var chipSelectedTextColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }
    var chipSelectedBackgroundColor: NSColor = .controlBackgroundColor {
        didSet { needsDisplay = true }
    }
    var chipSelectedBorderColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var chipSelectedBorderWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var chipHeight: CGFloat = 34 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var chipFontSize: CGFloat = 16 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var chipDotDiameter: CGFloat = 13 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var chipIconSide: CGFloat = 19 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var chipMarkerTextSpacing: CGFloat = 8 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var chipHorizontalPadding: CGFloat = 12 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var onContextMenu: ((NSEvent) -> Void)?

    override var intrinsicContentSize: NSSize {
        let font = chipFont()
        let textWidth = ceil((chipTitleText as NSString).size(withAttributes: [.font: font]).width)
        let markerWidth = chipSymbolName == nil ? chipDotDiameter : chipIconSide
        let contentWidth = markerWidth + chipMarkerTextSpacing + textWidth
        return NSSize(width: ceil(contentWidth + chipHorizontalPadding * 2), height: chipHeight)
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let selectedTextColor = chipDrawsSelectionPill && chipIsSelected
            ? chipSelectedTextColor
            : chipTextColor
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: chipFont(),
            .foregroundColor: selectedTextColor
        ]
        let titleSize = (chipTitleText as NSString).size(withAttributes: textAttributes)
        let markerWidth = chipSymbolName == nil ? chipDotDiameter : chipIconSide
        let contentWidth = markerWidth + chipMarkerTextSpacing + titleSize.width

        if chipDrawsSelectionPill && chipIsSelected {
            let fillRect = bounds.insetBy(dx: 0, dy: 1)
            let fillRadius = fillRect.height / 2
            let fillPath = NSBezierPath(
                roundedRect: fillRect,
                xRadius: fillRadius,
                yRadius: fillRadius
            )
            chipSelectedBackgroundColor.setFill()
            fillPath.fill()

            if chipSelectedBorderWidth > 0 {
                let borderInset = chipSelectedBorderWidth / 2
                let borderRect = fillRect.insetBy(dx: borderInset, dy: borderInset)
                let borderRadius = borderRect.height / 2
                let borderPath = NSBezierPath(
                    roundedRect: borderRect,
                    xRadius: borderRadius,
                    yRadius: borderRadius
                )
                chipSelectedBorderColor.setStroke()
                borderPath.lineWidth = chipSelectedBorderWidth
                borderPath.stroke()
            }
        }

        if chipIsRenaming {
            let focusPath = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 1, dy: 2),
                xRadius: (bounds.height - 4) / 2,
                yRadius: (bounds.height - 4) / 2
            )
            NSColor.systemBlue.setStroke()
            focusPath.lineWidth = 2
            focusPath.stroke()
        }

        let originX = max(chipHorizontalPadding, (bounds.width - contentWidth) / 2)
        let centerY = bounds.midY

        if let chipSymbolName,
           let symbol = monochromeSymbolImage(named: chipSymbolName, color: selectedTextColor) {
            symbol.draw(
                in: NSRect(
                    x: originX,
                    y: centerY - chipIconSide / 2,
                    width: chipIconSide,
                    height: chipIconSide
                ),
                from: NSRect.zero,
                operation: NSCompositingOperation.sourceOver,
                fraction: 1
            )
        } else {
            let dotRect = NSRect(
                x: originX,
                y: centerY - chipDotDiameter / 2,
                width: chipDotDiameter,
                height: chipDotDiameter
            )
            chipDotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            NSColor.black.withAlphaComponent(0.16).setStroke()
            let dotStroke = NSBezierPath(ovalIn: dotRect.insetBy(dx: 0.5, dy: 0.5))
            dotStroke.lineWidth = 1
            dotStroke.stroke()
        }

        if !chipIsRenaming {
            (chipTitleText as NSString).draw(
                at: NSPoint(
                    x: originX + markerWidth + chipMarkerTextSpacing,
                    y: centerY - titleSize.height / 2
                ),
                withAttributes: textAttributes
            )
        }
    }

    private func chipFont() -> NSFont {
        NSFont.systemFont(ofSize: chipFontSize, weight: chipIsSelected ? .medium : .regular)
    }

    private func monochromeSymbolImage(named symbolName: String, color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: chipTitleText)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: chipIconSide, weight: .regular))
        else {
            return nil
        }

        let imageSize = NSSize(width: chipIconSide, height: chipIconSide)
        let tintedImage = NSImage(size: imageSize)
        tintedImage.lockFocus()
        defer { tintedImage.unlockFocus() }

        let imageRect = NSRect(origin: .zero, size: imageSize)
        symbol.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        // 使用 sourceIn 将 SF Symbol 当作透明度蒙版，避免层级渲染把图标压淡。
        imageRect.fill(using: .sourceIn)
        tintedImage.isTemplate = false
        return tintedImage
    }
}
