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

    private func configureAppearance() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        indicatorLayer.cornerRadius = 1.5
        layer?.addSublayer(indicatorLayer)
        applyTheme()
    }

    private func applyTheme() {
        let alpha: CGFloat = isHovering ? 0.34 : 0.18
        indicatorLayer.backgroundColor = PasteTheme.current(for: self)
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

        guard let projectedEvent = horizontalOnlyEvent(from: event) else {
            super.scrollWheel(with: event)
            return
        }

        super.scrollWheel(with: projectedEvent)
        onScrollDidChange?()
    }

    private func horizontalOnlyEvent(from event: NSEvent) -> NSEvent? {
        guard let cgEvent = event.cgEvent?.copy() else { return nil }

        let shouldMapVertical = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
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

    private func clearScrollAxis(in event: CGEvent, field: CGEventField) {
        event.setIntegerValueField(field, value: 0)
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
    private var themeBorderColor: NSColor = NSColor.black.withAlphaComponent(0.14)
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
        selectionBorderLayer.frame = bounds.insetBy(dx: 1, dy: 1)
        selectionBorderLayer.cornerRadius = max(0, cornerRadius - 1)
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

    func configureSelectionAppearance(
        headerView: NSView,
        typeHeaderLabel: NSTextField,
        timeLabel: NSTextField,
        unselectedHeaderColor: NSColor,
        borderColor: NSColor,
        selectionBorderColor: NSColor,
        headerTextColor: NSColor,
        headerSecondaryTextColor: NSColor,
        isSelected: Bool
    ) {
        self.selectionHeaderView = headerView
        self.typeHeaderLabel = typeHeaderLabel
        self.timeLabel = timeLabel
        self.unselectedHeaderColor = unselectedHeaderColor
        self.themeBorderColor = borderColor
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
        borderColor = themeBorderColor
        borderWidth = 0.5
        selectionBorderLayer.isHidden = !isSelected
        selectionBorderLayer.borderWidth = isSelected ? 2 : 0
        selectionBorderLayer.borderColor = themeSelectionBorderColor.cgColor
        selectionHeaderView?.layer?.backgroundColor = unselectedHeaderColor.cgColor
        selectionHeaderView?.layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        typeHeaderLabel?.textColor = themeHeaderTextColor
        timeLabel?.textColor = themeHeaderSecondaryTextColor
        needsDisplay = true
    }

    private func installSelectionBorderLayerIfNeeded() {
        guard selectionBorderLayer.superlayer == nil else { return }
        selectionBorderLayer.backgroundColor = NSColor.clear.cgColor
        selectionBorderLayer.masksToBounds = false
        selectionBorderLayer.zPosition = 100
        selectionBorderLayer.cornerRadius = cornerRadius
        selectionBorderLayer.frame = bounds.insetBy(dx: 1, dy: 1)
        selectionBorderLayer.contentsScale = layer?.contentsScale ?? 2
        layer?.addSublayer(selectionBorderLayer)
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

final class TypeFilterChipButton: PanelActionButton {
    var itemType: String?
    var chipTitleText = ""
    var chipDotColor: NSColor = .clear
}
