import AppKit
import Carbon.HIToolbox

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

final class HorizontalWheelScrollView: NSScrollView {
    var onScrollDidChange: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard documentView != nil else {
            super.scrollWheel(with: event)
            return
        }

        let initialHorizontalOrigin = contentView.bounds.origin.x
        let fallbackDelta = dominantVerticalDelta(from: event)
        guard let projectedEvent = horizontalOnlyEvent(from: event) else {
            super.scrollWheel(with: event)
            applyManualHorizontalFallbackIfNeeded(
                initialHorizontalOrigin: initialHorizontalOrigin,
                delta: fallbackDelta
            )
            return
        }

        super.scrollWheel(with: projectedEvent)
        applyManualHorizontalFallbackIfNeeded(
            initialHorizontalOrigin: initialHorizontalOrigin,
            delta: fallbackDelta
        )
        onScrollDidChange?()
    }

    private func horizontalOnlyEvent(from event: NSEvent) -> NSEvent? {
        guard let cgEvent = event.cgEvent?.copy() else { return nil }

        let verticalDelta = scrollDelta(
            for: event,
            cgEvent: cgEvent,
            preciseValue: event.scrollingDeltaY,
            pointField: .scrollWheelEventPointDeltaAxis1,
            fixedField: .scrollWheelEventFixedPtDeltaAxis1,
            lineField: .scrollWheelEventDeltaAxis1
        )
        let horizontalDelta = scrollDelta(
            for: event,
            cgEvent: cgEvent,
            preciseValue: event.scrollingDeltaX,
            pointField: .scrollWheelEventPointDeltaAxis2,
            fixedField: .scrollWheelEventFixedPtDeltaAxis2,
            lineField: .scrollWheelEventDeltaAxis2
        )
        let shouldMapVertical = abs(verticalDelta) > abs(horizontalDelta)
        if shouldMapVertical {
            projectScrollAxis(in: cgEvent, from: .scrollWheelEventDeltaAxis1, to: .scrollWheelEventDeltaAxis2)
            projectScrollAxis(in: cgEvent, from: .scrollWheelEventPointDeltaAxis1, to: .scrollWheelEventPointDeltaAxis2)
            projectScrollAxis(in: cgEvent, from: .scrollWheelEventFixedPtDeltaAxis1, to: .scrollWheelEventFixedPtDeltaAxis2)
        }

        clearScrollAxis(in: cgEvent, field: .scrollWheelEventDeltaAxis1)
        clearScrollAxis(in: cgEvent, field: .scrollWheelEventPointDeltaAxis1)
        clearScrollAxis(in: cgEvent, field: .scrollWheelEventFixedPtDeltaAxis1)
        return NSEvent(cgEvent: cgEvent)
    }

    private func projectScrollAxis(in event: CGEvent, from source: CGEventField, to target: CGEventField) {
        let value = event.getIntegerValueField(source)
        guard value != 0 else { return }
        event.setIntegerValueField(target, value: value)
    }

    private func scrollDelta(
        for event: NSEvent,
        cgEvent: CGEvent,
        preciseValue: CGFloat,
        pointField: CGEventField,
        fixedField: CGEventField,
        lineField: CGEventField
    ) -> CGFloat {
        if preciseValue != 0 {
            return preciseValue
        }

        let pointValue = cgEvent.getIntegerValueField(pointField)
        if pointValue != 0 {
            return CGFloat(pointValue)
        }

        let fixedValue = cgEvent.getIntegerValueField(fixedField)
        if fixedValue != 0 {
            return CGFloat(fixedValue)
        }

        return CGFloat(cgEvent.getIntegerValueField(lineField))
    }

    private func clearScrollAxis(in event: CGEvent, field: CGEventField) {
        event.setIntegerValueField(field, value: 0)
    }

    private func dominantVerticalDelta(from event: NSEvent) -> CGFloat {
        guard let cgEvent = event.cgEvent else { return event.scrollingDeltaY }
        let verticalDelta = scrollDelta(
            for: event,
            cgEvent: cgEvent,
            preciseValue: event.scrollingDeltaY,
            pointField: .scrollWheelEventPointDeltaAxis1,
            fixedField: .scrollWheelEventFixedPtDeltaAxis1,
            lineField: .scrollWheelEventDeltaAxis1
        )
        let horizontalDelta = scrollDelta(
            for: event,
            cgEvent: cgEvent,
            preciseValue: event.scrollingDeltaX,
            pointField: .scrollWheelEventPointDeltaAxis2,
            fixedField: .scrollWheelEventFixedPtDeltaAxis2,
            lineField: .scrollWheelEventDeltaAxis2
        )
        return abs(verticalDelta) > abs(horizontalDelta) ? verticalDelta : 0
    }

    private func applyManualHorizontalFallbackIfNeeded(
        initialHorizontalOrigin: CGFloat,
        delta: CGFloat
    ) {
        guard abs(contentView.bounds.origin.x - initialHorizontalOrigin) < 0.5,
              delta != 0,
              let documentView
        else {
            return
        }

        let minimumX: CGFloat = 0
        let maximumX = max(minimumX, documentView.frame.width - contentView.bounds.width)
        let targetX = min(max(initialHorizontalOrigin + delta, minimumX), maximumX)
        guard abs(targetX - initialHorizontalOrigin) >= 0.5 else { return }

        contentView.scroll(to: NSPoint(x: targetX, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
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
        if let imageName {
            image = NSImage(systemSymbolName: imageName, accessibilityDescription: title)
        }
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
