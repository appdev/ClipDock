import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipboardPanelApp
import Darwin
import ServiceManagement

private enum PanelLevelMode: String, CaseIterable {
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

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class HeightResizeHandleView: NSView {
    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?

    private let indicatorLayer = CALayer()
    private var initialMouseY: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            indicatorLayer.backgroundColor = NSColor.labelColor
                .withAlphaComponent(isHovering ? 0.46 : 0.28)
                .cgColor
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

        let indicatorSize = CGSize(width: isHovering ? 92 : 72, height: 4)
        indicatorLayer.frame = CGRect(
            x: bounds.midX - indicatorSize.width / 2,
            y: bounds.midY - indicatorSize.height / 2,
            width: indicatorSize.width,
            height: indicatorSize.height
        )
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

        indicatorLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.28).cgColor
        indicatorLayer.cornerRadius = 2
        layer?.addSublayer(indicatorLayer)
    }
}

private final class HorizontalWheelScrollView: NSScrollView {
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

private final class ClipboardItemCardBox: NSBox {
    var itemID: String?
    var onSelect: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    private weak var selectionHeaderView: NSView?
    private weak var typeHeaderLabel: NSTextField?
    private weak var timeLabel: NSTextField?
    private weak var commandIndexLabel: NSTextField?
    private var unselectedHeaderColor: NSColor = .clear

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        contentView?.layer?.contentsScale = layer?.contentsScale ?? 2
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
        isSelected: Bool
    ) {
        self.selectionHeaderView = headerView
        self.typeHeaderLabel = typeHeaderLabel
        self.timeLabel = timeLabel
        self.unselectedHeaderColor = unselectedHeaderColor
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
        borderColor = isSelected
            ? NSColor.controlAccentColor
            : NSColor.separatorColor.withAlphaComponent(0.08)
        borderWidth = isSelected ? 3 : 0.5
        selectionHeaderView?.layer?.backgroundColor = (
            isSelected ? NSColor.controlAccentColor : unselectedHeaderColor
        ).cgColor
        selectionHeaderView?.layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        typeHeaderLabel?.textColor = .white
        timeLabel?.textColor = NSColor.white.withAlphaComponent(0.80)
        needsDisplay = true
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, imageName: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        target = self
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

private class PanelActionButton: NSButton {
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

private final class TypeFilterChipButton: PanelActionButton {
    var itemType: String?
}

@MainActor
private final class ClipboardPreviewPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var shownItemID: String?
    private var keyDownMonitor: Any?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    var isShown: Bool {
        popover.isShown
    }

    func toggle(
        item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        relativeTo anchorView: NSView
    ) {
        if popover.isShown, shownItemID == item.id {
            close()
            return
        }

        show(item: item, appSupportDirectory: appSupportDirectory, relativeTo: anchorView)
    }

    func show(
        item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        relativeTo anchorView: NSView
    ) {
        close()

        let content = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: appSupportDirectory
        )
        let viewController = ClipboardPreviewViewController(content: content)
        popover.contentViewController = viewController
        popover.contentSize = viewController.preferredContentSize
        shownItemID = item.id
        startKeyDownMonitor()
        popover.show(
            relativeTo: anchorView.bounds.insetBy(dx: 10, dy: 10),
            of: anchorView,
            preferredEdge: .maxY
        )
        anchorView.window?.makeFirstResponder(anchorView.window?.contentView)
    }

    func close() {
        if popover.isShown {
            popover.performClose(nil)
            popover.close()
        }
        stopKeyDownMonitor()
        shownItemID = nil
    }

    func popoverDidClose(_ notification: Notification) {
        stopKeyDownMonitor()
        shownItemID = nil
    }

    private func startKeyDownMonitor() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDownForShownPopover(event) ? nil : event
        }
    }

    func handleKeyDownForShownPopover(_ event: NSEvent) -> Bool {
        guard popover.isShown else {
            stopKeyDownMonitor()
            return false
        }

        switch Int(event.keyCode) {
        case kVK_Space, kVK_Escape:
            close()
            return true
        default:
            return false
        }
    }

    private func stopKeyDownMonitor() {
        guard let keyDownMonitor else { return }
        NSEvent.removeMonitor(keyDownMonitor)
        self.keyDownMonitor = nil
    }
}

private final class ClipboardPreviewViewController: NSViewController {
    private enum Layout {
        static let width: CGFloat = 420
        static let textHeight: CGFloat = 250
        static let imageHeight: CGFloat = 236
    }

    private let content: ClipboardPreviewContent

    init(content: ClipboardPreviewContent) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.preferredSize(for: content)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeHeader())
        if content.itemType == "image" {
            stack.addArrangedSubview(makeImagePreview())
        } else {
            stack.addArrangedSubview(makeTextPreview())
        }
        stack.addArrangedSubview(makeFooter())

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: preferredContentSize.width),
            root.heightAnchor.constraint(equalToConstant: preferredContentSize.height)
        ])

        view = root
    }

    private static func preferredSize(for content: ClipboardPreviewContent) -> NSSize {
        NSSize(
            width: Layout.width,
            height: content.itemType == "image" ? 342 : 354
        )
    }

    private func makeHeader() -> NSView {
        let iconView = NSImageView()
        iconView.image = content.sourceAppIconPath.flatMap(NSImage.init(contentsOfFile:))
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: content.sourceAppName)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true

        let titleLabel = NSTextField(labelWithString: content.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let subtitleLabel = NSTextField(labelWithString: "\(content.sourceAppName) · \(content.subtitle)")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [iconView, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34)
        ])

        return row
    }

    private func makeImagePreview() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.42).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = content.imageURL.flatMap(NSImage.init(contentsOf:))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        if imageView.image == nil {
            let fallbackLabel = NSTextField(labelWithString: "预览不可用")
            fallbackLabel.font = .systemFont(ofSize: 13, weight: .medium)
            fallbackLabel.textColor = .secondaryLabelColor
            fallbackLabel.alignment = .center
            fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(fallbackLabel)

            NSLayoutConstraint.activate([
                fallbackLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                fallbackLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: Layout.imageHeight),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeTextPreview() -> NSView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 13)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: Layout.width - 28,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = content.body
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: Layout.textHeight)
        ])

        return scrollView
    }

    private func makeFooter() -> NSView {
        let metadataLabel = NSTextField(labelWithString: content.metadata)
        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingMiddle
        metadataLabel.maximumNumberOfLines = 1

        let timeLabel = NSTextField(labelWithString: Self.relativeTime(from: content.copiedAtMilliseconds))
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.alignment = .right
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [metadataLabel, NSView(), timeLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private static func relativeTime(from milliseconds: Int64) -> String {
        let seconds = TimeInterval(milliseconds) / 1000
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private final class FloatingPanelContentView: NSVisualEffectView, NSSearchFieldDelegate {
    private static let imageCache = NSCache<NSString, NSImage>()
    private static let sourceColorCache = NSCache<NSString, NSColor>()

    var onHide: (() -> Void)?
    var onHeightResizeBegan: (() -> Void)?
    var onHeightResizeChanged: ((CGFloat) -> Void)?
    var onQueryChanged: ((String, String?, String?) -> Void)?
    var onCopyRequested: ((RustClipboardItemSummary) -> Void)?
    var onPinRequested: ((RustClipboardItemSummary, Bool) -> Void)?
    var onDeleteRequested: ((RustClipboardItemSummary) -> Void)?
    var onClearRequested: ((String, String?, String?) -> Void)?

    private enum Layout {
        static let padding: CGFloat = 24
        static let resizeHandleHeight: CGFloat = 18
        static let controlBarHeight: CGFloat = 48
        static let sectionSpacing: CGFloat = 2
        static let defaultItemWidth: CGFloat = 206
        static let defaultItemHeight: CGFloat = 220
        static let compactItemHeight: CGFloat = 160
        static let imagePreviewMinHeight: CGFloat = 78
        static let imagePreviewMaxHeight: CGFloat = 116
        static let scrollEdgeInset: CGFloat = 6
        static let panelCornerRadius: CGFloat = 22
        static let cardCornerRadius: CGFloat = 14
        static let innerCornerRadius: CGFloat = 10
        static let chipCornerRadius: CGFloat = 15
        static let cardHeaderHeight: CGFloat = 52
        static let cardInset: CGFloat = 12
        static let sourceIconSize: CGFloat = 56
        static let linkPreviewHeight: CGFloat = 58
        static let filePreviewHeight: CGFloat = 58
        static let hairlineWidth: CGFloat = 1
    }

    private let searchField = NSSearchField()
    private let previewPopoverController = ClipboardPreviewPopoverController()
    private let itemBandDocumentView = NSView()
    private let itemBandStack = NSStackView()
    private weak var itemBandScrollView: HorizontalWheelScrollView?
    private var itemHeightConstraints: [NSLayoutConstraint] = []
    private var itemPreviewHeightConstraints: [NSLayoutConstraint] = []
    private var itemImagePreviewViews: [NSImageView] = []
    private var currentPanelHeight: CGFloat = 320
    private var currentItems: [RustClipboardItemSummary] = []
    private var typeFilterButtons: [TypeFilterChipButton] = []
    private var searchFieldWidthConstraint: NSLayoutConstraint?
    private var appSupportDirectory: URL?
    private var selectedItemID: String?
    private var currentItemTypeFilter: String?
    private var previewPopoverEnabled = true
    private var isShowingFilteredEmptyState = false
    private var commandHintModeEnabled = false
    private var flagsChangedMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
        configureLayout()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopFlagsChangedMonitor()
            commandHintModeEnabled = false
            updateCommandNumberHints()
        } else {
            startFlagsChangedMonitor()
        }
    }

    func update(levelMode: PanelLevelMode, dockIconVisible: Bool, hotKeyAvailable: Bool, panelHeight: CGFloat) {
        updatePanelHeight(panelHeight)
    }

    func updateStorageState(_ result: Result<RustCoreOpenResult, RustCoreError>) {
        switch result {
        case .success(let openResult):
            updateItems(openResult.items, isFiltered: false)
        case .failure:
            currentItems = []
            selectedItemID = nil
            renderItemCards([makeDatabaseErrorCard()])
        }
    }

    func updateListState(_ result: Result<RustCoreListResult, RustCoreError>, isFiltered: Bool) {
        switch result {
        case .success(let listResult):
            updateItems(listResult.items, isFiltered: isFiltered)
        case .failure:
            currentItems = []
            selectedItemID = nil
            renderItemCards([makeDatabaseErrorCard()])
        }
    }

    func updateSourceApps(_ apps: [RustSourceAppSummary], selectedSourceAppID: String?) {
        _ = apps
        _ = selectedSourceAppID
    }

    func updateAppSupportDirectory(_ url: URL) {
        appSupportDirectory = url
    }

    func setPreviewPopoverEnabled(_ enabled: Bool) {
        previewPopoverEnabled = enabled
        if !enabled {
            previewPopoverController.close()
        }
    }

    func closePreviewPopover() {
        previewPopoverController.close()
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyboardCommand(event) {
            return
        }

        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        updateCommandHintMode(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        )
        super.flagsChanged(with: event)
    }

    func updatePanelHeight(_ panelHeight: CGFloat) {
        currentPanelHeight = panelHeight
        let availableItemHeight = max(
            Layout.compactItemHeight,
            panelHeight - Layout.resizeHandleHeight - Layout.controlBarHeight - Layout.sectionSpacing - Layout.padding
        )
        let itemHeight = availableItemHeight
        let previewHeight = min(
            Layout.imagePreviewMaxHeight,
            max(Layout.imagePreviewMinHeight, itemHeight * 0.48)
        )

        itemHeightConstraints.forEach { $0.constant = itemHeight }
        itemPreviewHeightConstraints.forEach { $0.constant = previewHeight }
        itemImagePreviewViews.forEach { imageView in
            imageView.needsLayout = true
        }
        itemBandDocumentView.setFrameSize(
            NSSize(width: itemBandDocumentView.frame.width, height: itemHeight)
        )
        itemBandDocumentView.needsLayout = true
    }

    private func configureAppearance() {
        userInterfaceLayoutDirection = .leftToRight
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.58).cgColor
        layer?.cornerRadius = Layout.panelCornerRadius
        layer?.masksToBounds = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    private func configureLayout() {
        let resizeHandle = HeightResizeHandleView(frame: .zero)
        resizeHandle.onDragBegan = { [weak self] in self?.onHeightResizeBegan?() }
        resizeHandle.onDragChanged = { [weak self] deltaY in self?.onHeightResizeChanged?(deltaY) }
        resizeHandle.toolTip = "拖动调整高度"
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        let controlBar = makeControlBar()
        controlBar.translatesAutoresizingMaskIntoConstraints = false

        let itemBand = makeItemBand()
        itemBand.translatesAutoresizingMaskIntoConstraints = false

        addSubview(controlBar)
        addSubview(itemBand)
        addSubview(resizeHandle)

        NSLayoutConstraint.activate([
            resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: topAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: Layout.resizeHandleHeight),

            controlBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.padding),
            controlBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.padding),
            controlBar.topAnchor.constraint(equalTo: resizeHandle.bottomAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: Layout.controlBarHeight),

            itemBand.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.padding),
            itemBand.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.padding),
            itemBand.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: Layout.sectionSpacing),
            itemBand.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.padding)
        ])

        renderItemCards([makeEmptyHistoryCard()])
        updatePanelHeight(currentPanelHeight)
    }

    private func makeControlBar() -> NSView {
        let container = NSView()

        searchField.placeholderString = "搜索剪贴板内容、应用或类型"
        searchField.font = .systemFont(ofSize: 13)
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.target = nil
        searchField.action = nil
        searchField.isHidden = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let searchButton = makeToolbarIconButton(
            symbolName: "magnifyingglass",
            accessibilityLabel: "搜索"
        ) { [weak self] in
            self?.toggleSearchField()
        }

        let chips = [
            makeTypeFilterChip(title: "剪贴板", itemType: nil, dotColor: .clear),
            makeTypeFilterChip(title: "文本", itemType: "text", dotColor: NSColor.systemBlue),
            makeTypeFilterChip(title: "链接", itemType: "link", dotColor: NSColor.systemPurple),
            makeTypeFilterChip(title: "图片", itemType: "image", dotColor: NSColor.systemGreen),
            makeTypeFilterChip(title: "文件", itemType: "file", dotColor: NSColor.systemOrange)
        ]
        typeFilterButtons = chips
        updateTypeFilterChipAppearance()

        let addButton = makeToolbarIconButton(
            symbolName: "plus",
            accessibilityLabel: "显示全部"
        ) { [weak self] in
            guard let self else { return }
            self.currentItemTypeFilter = nil
            self.searchField.stringValue = ""
            self.searchField.isHidden = true
            self.updateTypeFilterChipAppearance()
            self.emitQueryChanged()
        }

        let row = NSStackView(views: [searchButton, searchField] + chips + [addButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.userInterfaceLayoutDirection = .leftToRight
        row.translatesAutoresizingMaskIntoConstraints = false

        let moreButton = makeToolbarIconButton(
            symbolName: "ellipsis",
            accessibilityLabel: "更多"
        ) { [weak self] in
            self?.showPanelOverflowMenu()
        }
        moreButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(row)
        container.addSubview(moreButton)
        searchFieldWidthConstraint = searchField.widthAnchor.constraint(equalToConstant: 220)
        searchFieldWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 30),

            moreButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            moreButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func showPanelOverflowMenu() {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "偏好设置…", imageName: "gearshape") {
            NSApp.sendAction(#selector(AppDelegate.showPreferences(_:)), to: nil, from: nil)
        })
        menu.addItem(ActionMenuItem(title: "隐藏面板", imageName: "eye.slash") { [weak self] in
            self?.onHide?()
        })

        guard let event = NSApp.currentEvent else { return }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    private func makeItemBand() -> NSView {
        let scrollView = HorizontalWheelScrollView()
        itemBandScrollView = scrollView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.usesPredominantAxisScrolling = true
        scrollView.onScrollDidChange = { [weak self] in
            guard let self, self.commandHintModeEnabled else { return }
            self.updateCommandNumberHints()
        }

        itemBandStack.orientation = .horizontal
        itemBandStack.alignment = .top
        itemBandStack.spacing = 10
        itemBandStack.userInterfaceLayoutDirection = .leftToRight
        itemBandStack.translatesAutoresizingMaskIntoConstraints = false

        itemBandDocumentView.addSubview(itemBandStack)

        NSLayoutConstraint.activate([
            itemBandStack.leadingAnchor.constraint(equalTo: itemBandDocumentView.leadingAnchor, constant: Layout.scrollEdgeInset),
            itemBandStack.trailingAnchor.constraint(equalTo: itemBandDocumentView.trailingAnchor, constant: -Layout.scrollEdgeInset),
            itemBandStack.topAnchor.constraint(equalTo: itemBandDocumentView.topAnchor),
            itemBandStack.bottomAnchor.constraint(equalTo: itemBandDocumentView.bottomAnchor)
        ])

        scrollView.documentView = itemBandDocumentView
        return scrollView
    }

    private func updateItems(_ items: [RustClipboardItemSummary], isFiltered: Bool) {
        previewPopoverController.close()
        currentItems = Array(items.prefix(30))
        isShowingFilteredEmptyState = isFiltered
        selectedItemID = PanelInteractionPlanner.selectedIDAfterListUpdate(
            previousSelectedID: selectedItemID,
            itemIDs: currentItems.map(\.id)
        )

        renderCurrentItems()
    }

    private func renderCurrentItems() {
        if currentItems.isEmpty {
            renderItemCards([
                isShowingFilteredEmptyState ? makeNoResultsCard() : makeEmptyHistoryCard()
            ])
            return
        }

        renderItemCards(currentItems.map(makeItemCard))
        scrollSelectedItemIntoView()
    }

    private func handleKeyboardCommand(_ event: NSEvent) -> Bool {
        let commandPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)

        if commandPressed,
           let character = event.charactersIgnoringModifiers?.lowercased() {
            if character == "f" {
                focusSearchField()
                return true
            }

            if let segment = Int(character), (1...9).contains(segment) {
                copyCommandNumberedItem(number: segment)
                return true
            }
        }

        switch Int(event.keyCode) {
        case kVK_Space:
            return toggleSelectedPreview()
        case kVK_RightArrow:
            selectItem(offset: 1)
            return true
        case kVK_LeftArrow:
            selectItem(offset: -1)
            return true
        case kVK_Escape:
            switch PanelInteractionPlanner.escapeAction(
                isPreviewShown: previewPopoverController.isShown,
                searchText: searchField.stringValue
            ) {
            case .closePreview:
                previewPopoverController.close()
            case .clearSearch:
                searchField.stringValue = ""
                emitQueryChanged()
            case .hidePanel:
                onHide?()
            }
            return true
        default:
            return false
        }
    }

    private func selectItem(offset: Int) {
        guard let nextID = PanelInteractionPlanner.selectedIDAfterOffset(
            currentSelectedID: selectedItemID,
            itemIDs: currentItems.map(\.id),
            offset: offset
        ) else { return }

        guard selectedItemID != nextID else { return }
        previewPopoverController.close()
        selectedItemID = nextID
        updateVisibleSelection()
    }

    private func copyCommandNumberedItem(number: Int) {
        guard let nextID = PanelInteractionPlanner.selectedIDForCommandNumber(
            number,
            itemIDs: fullyVisibleCommandItemIDs()
        ) else {
            return
        }

        guard let item = currentItems.first(where: { $0.id == nextID }) else { return }
        copyItemToPasteboard(item)
    }

    private func selectItem(id: String) {
        guard currentItems.contains(where: { $0.id == id }) else { return }

        guard selectedItemID != id else { return }
        previewPopoverController.close()
        selectedItemID = id
        updateVisibleSelection()
    }

    private func copyItemToPasteboard(_ item: RustClipboardItemSummary) {
        previewPopoverController.close()
        selectedItemID = item.id
        onCopyRequested?(item)
    }

    private func showManagementMenu(for item: RustClipboardItemSummary, event: NSEvent) {
        previewPopoverController.close()
        let didChangeSelection = selectedItemID != item.id
        selectedItemID = item.id
        if didChangeSelection {
            updateVisibleSelection(scrollIntoView: false)
        }

        guard let index = currentItems.firstIndex(where: { $0.id == item.id }),
              index < itemBandStack.arrangedSubviews.count
        else { return }

        let menu = makeManagementMenu(for: item)
        let cardView = itemBandStack.arrangedSubviews[index]
        menu.popUp(
            positioning: nil,
            at: cardView.convert(event.locationInWindow, from: nil),
            in: cardView
        )
    }

    private func makeManagementMenu(for item: RustClipboardItemSummary) -> NSMenu {
        let menu = NSMenu()
        let pinTitle = item.isPinned ? "取消固定" : "固定条目"
        let pinImage = item.isPinned ? "pin.slash" : "pin"
        menu.addItem(ActionMenuItem(title: pinTitle, imageName: pinImage) { [weak self] in
            self?.onPinRequested?(item, !item.isPinned)
        })
        menu.addItem(ActionMenuItem(title: "复制到剪贴板", imageName: "doc.on.clipboard") { [weak self] in
            self?.copyItemToPasteboard(item)
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "删除条目", imageName: "trash") { [weak self] in
            self?.previewPopoverController.close()
            self?.onDeleteRequested?(item)
        })
        let clearTitle = currentScopeClearTitle()
        menu.addItem(ActionMenuItem(title: clearTitle, imageName: "xmark.bin") { [weak self] in
            guard let self else { return }
            self.previewPopoverController.close()
            self.onClearRequested?(
                self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                self.selectedTypeFilter(),
                nil
            )
        })
        return menu
    }

    private func updateVisibleSelection(scrollIntoView: Bool = true) {
        for view in itemBandStack.arrangedSubviews {
            guard let card = view as? ClipboardItemCardBox else { continue }
            card.applySelection(card.itemID == selectedItemID)
        }

        if scrollIntoView {
            scrollSelectedItemIntoView()
        }
    }

    private func currentScopeClearTitle() -> String {
        let hasSearch = !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if currentItemTypeFilter != nil || hasSearch {
            return "清空当前结果"
        }

        return "清空未固定历史"
    }

    private func toggleSelectedPreview() -> Bool {
        guard previewPopoverEnabled else {
            previewPopoverController.close()
            return true
        }

        guard let appSupportDirectory,
              let selectedItemID,
              let index = currentItems.firstIndex(where: { $0.id == selectedItemID }),
              index < itemBandStack.arrangedSubviews.count
        else {
            return true
        }

        previewPopoverController.toggle(
            item: currentItems[index],
            appSupportDirectory: appSupportDirectory,
            relativeTo: itemBandStack.arrangedSubviews[index]
        )
        return true
    }

    private func scrollSelectedItemIntoView() {
        guard let selectedItemID,
              let index = currentItems.firstIndex(where: { $0.id == selectedItemID }),
              index < itemBandStack.arrangedSubviews.count
        else {
            return
        }

        let selectedView = itemBandStack.arrangedSubviews[index]
        itemBandDocumentView.scrollToVisible(selectedView.frame.insetBy(dx: -24, dy: 0))
        if commandHintModeEnabled {
            updateCommandNumberHints()
        }
    }

    private func startFlagsChangedMonitor() {
        guard flagsChangedMonitor == nil else { return }
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            self.updateCommandHintMode(
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            )
            return event
        }
    }

    private func stopFlagsChangedMonitor() {
        if let flagsChangedMonitor {
            NSEvent.removeMonitor(flagsChangedMonitor)
        }
        flagsChangedMonitor = nil
    }

    private func updateCommandHintMode(_ enabled: Bool) {
        guard commandHintModeEnabled != enabled else {
            if enabled {
                updateCommandNumberHints()
            }
            return
        }

        commandHintModeEnabled = enabled
        updateCommandNumberHints()
    }

    private func updateCommandNumberHints() {
        let visibleItemIDs = commandHintModeEnabled ? fullyVisibleCommandItemIDs() : []
        let commandNumbersByID = Dictionary(uniqueKeysWithValues: visibleItemIDs.enumerated().map {
            ($0.element, "\($0.offset + 1)")
        })

        for view in itemBandStack.arrangedSubviews {
            guard let card = view as? ClipboardItemCardBox else { continue }
            card.setCommandIndexText(card.itemID.flatMap { commandNumbersByID[$0] })
        }
    }

    private func fullyVisibleCommandItemIDs(limit: Int = 9) -> [String] {
        guard let scrollView = itemBandScrollView else { return [] }
        let visibleRect = scrollView.contentView.bounds
        let visibleMinX = visibleRect.minX - 0.5
        let visibleMaxX = visibleRect.maxX + 0.5

        return itemBandStack.arrangedSubviews.compactMap { view -> String? in
            guard let card = view as? ClipboardItemCardBox,
                  let itemID = card.itemID
            else { return nil }

            let frame = card.frame
            guard frame.minX >= visibleMinX, frame.maxX <= visibleMaxX else {
                return nil
            }

            return itemID
        }
        .prefix(limit)
        .map { $0 }
    }

    private func focusSearchField() {
        searchField.isHidden = false
        window?.makeFirstResponder(searchField)
    }

    private func selectedTypeFilter() -> String? {
        currentItemTypeFilter
    }

    private func emitQueryChanged() {
        let searchText = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onQueryChanged?(searchText, selectedTypeFilter(), nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        emitQueryChanged()
    }

    private func typeFilterChipPressed(_ sender: TypeFilterChipButton) {
        currentItemTypeFilter = sender.itemType
        updateTypeFilterChipAppearance()
        emitQueryChanged()
    }

    private func toggleSearchField() {
        let shouldShow = searchField.isHidden
        searchField.isHidden = !shouldShow && searchField.stringValue.isEmpty
        if shouldShow {
            focusSearchField()
        } else if searchField.stringValue.isEmpty {
            window?.makeFirstResponder(self)
        }
    }

    private func renderItemCards(_ cards: [NSView]) {
        itemHeightConstraints.removeAll()
        itemPreviewHeightConstraints.removeAll()
        itemImagePreviewViews.removeAll()

        itemBandStack.arrangedSubviews.forEach { view in
            itemBandStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        cards.forEach { itemBandStack.addArrangedSubview($0) }

        let cardCount = max(cards.count, 1)
        itemBandDocumentView.frame = NSRect(
            x: 0,
            y: 0,
            width: CGFloat(cardCount) * Layout.defaultItemWidth
                + CGFloat(max(cardCount - 1, 0)) * itemBandStack.spacing
                + Layout.scrollEdgeInset * 2,
            height: Layout.defaultItemHeight
        )
        updatePanelHeight(currentPanelHeight)
        updateCommandNumberHints()
    }

    private func makeEmptyHistoryCard() -> NSView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "暂无剪贴板记录")
        return makeItemCard(
            iconView: imageView,
            appNameLabel: NSTextField(labelWithString: "暂无剪贴板记录"),
            timeLabel: NSTextField(labelWithString: ""),
            typeText: "空态",
            summary: "复制内容后会显示在这里",
            footnote: "",
            isSelected: true
        )
    }

    private func makeDatabaseErrorCard() -> NSView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "数据库不可用")
        return makeItemCard(
            iconView: imageView,
            appNameLabel: NSTextField(labelWithString: "数据库不可用"),
            timeLabel: NSTextField(labelWithString: "可重试"),
            typeText: "错误",
            summary: "本地历史暂时无法读取",
            footnote: "",
            isSelected: true
        )
    }

    private func makeNoResultsCard() -> NSView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "没有匹配结果")
        return makeItemCard(
            iconView: imageView,
            appNameLabel: NSTextField(labelWithString: "没有匹配结果"),
            timeLabel: NSTextField(labelWithString: ""),
            typeText: "空态",
            summary: "换个关键词或切回全部类型",
            footnote: "",
            isSelected: true
        )
    }

    private func makeItemCard(_ item: RustClipboardItemSummary) -> NSView {
        let imageView = NSImageView()
        let sourceIconImage = item.sourceAppIconPath.flatMap(Self.loadCachedImage(path:))
        let sourceColorKey = sourceColorKey(for: item)
        let sourceColorCacheKey = sourceColorKey ?? item.sourceAppIconPath
        let sourceIconColor = sourceIconImage.flatMap {
            Self.dominantHeaderColor(
                for: $0,
                cacheKey: sourceColorCacheKey,
                fallbackCacheKey: item.sourceAppIconPath
            )
        }
        imageView.image = sourceIconImage
            ?? NSImage(
                systemSymbolName: symbolName(forItemType: item.itemType),
                accessibilityDescription: item.sourceAppName ?? displayType(for: item)
            )

        let previewView: NSView?
        switch item.itemType {
        case "image":
            previewView = makeImagePreview(
                previewPath: item.previewAssetPath,
                payloadPath: item.payloadAssetPath,
                summary: item.summary
            )
        case "file":
            previewView = makeFilePreview(for: item)
        default:
            previewView = nil
        }

        return makeItemCard(
            itemID: item.id,
            iconView: imageView,
            appNameLabel: NSTextField(labelWithString: item.sourceAppName ?? "未知来源"),
            timeLabel: NSTextField(labelWithString: relativeTime(from: item.lastCopiedAtMs)),
            typeText: displayType(for: item),
            sourceColorKey: sourceColorKey,
            sourceIconColor: sourceIconColor,
            summary: displaySummary(for: item),
            footnote: contentFootnote(for: item),
            previewView: previewView,
            isSelected: item.id == selectedItemID,
            toolTip: "单击选中，双击复制到剪贴板，右键管理",
            onSelect: { [weak self] in
                self?.selectItem(id: item.id)
            },
            onDoubleClick: { [weak self] in
                self?.copyItemToPasteboard(item)
            },
            onContextMenu: { [weak self] event in
                self?.showManagementMenu(for: item, event: event)
            }
        )
    }

    private func makeItemCard(
        symbolName: String,
        appName: String,
        time: String,
        typeText: String,
        isSelected: Bool
    ) -> NSView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: appName)
        return makeItemCard(
            iconView: imageView,
            appNameLabel: NSTextField(labelWithString: appName),
            timeLabel: NSTextField(labelWithString: time),
            typeText: typeText,
            sourceColorKey: nil,
            summary: "等待本地历史数据",
            previewView: nil,
            isSelected: isSelected
        )
    }

    private func makeItemCard(
        itemID: String? = nil,
        iconView: NSImageView,
        appNameLabel: NSTextField,
        timeLabel: NSTextField,
        typeText: String,
        sourceColorKey: String? = nil,
        sourceIconColor: NSColor? = nil,
        summary: String,
        footnote: String? = nil,
        previewView: NSView? = nil,
        isSelected: Bool,
        toolTip: String? = nil,
        onSelect: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onContextMenu: ((NSEvent) -> Void)? = nil
    ) -> NSView {
        let container = ClipboardItemCardBox()
        container.boxType = .custom
        container.borderColor = isSelected
            ? NSColor.controlAccentColor
            : NSColor.separatorColor.withAlphaComponent(0.08)
        container.borderWidth = isSelected ? 3 : 0.5
        container.fillColor = NSColor.textBackgroundColor.withAlphaComponent(0.95)
        container.cornerRadius = Layout.cardCornerRadius
        container.contentViewMargins = .zero
        container.wantsLayer = true
        container.layer?.cornerRadius = Layout.cardCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        container.contentView?.wantsLayer = true
        container.contentView?.layer?.masksToBounds = true
        container.contentView?.layer?.contentsScale = container.layer?.contentsScale ?? 2
        container.translatesAutoresizingMaskIntoConstraints = false
        container.toolTip = toolTip
        container.itemID = itemID
        container.onSelect = onSelect
        container.onDoubleClick = onDoubleClick
        container.onContextMenu = onContextMenu

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = Layout.innerCornerRadius
        iconView.layer?.masksToBounds = true
        iconView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.30).cgColor
        iconView.layer?.borderWidth = 0
        iconView.layer?.contentsScale = container.layer?.contentsScale ?? 2
        iconView.toolTip = appNameLabel.stringValue

        let typeHeaderLabel = NSTextField(labelWithString: typeText)
        typeHeaderLabel.font = .systemFont(ofSize: 14, weight: .bold)
        typeHeaderLabel.textColor = headerTextColor(isSelected: isSelected)
        typeHeaderLabel.lineBreakMode = .byTruncatingTail
        typeHeaderLabel.maximumNumberOfLines = 1
        configureLeftToRightText(typeHeaderLabel)

        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = headerSecondaryTextColor(isSelected: isSelected)
        timeLabel.lineBreakMode = .byTruncatingTail
        timeLabel.maximumNumberOfLines = 1
        configureLeftToRightText(timeLabel)

        let headerTextStack = NSStackView(views: [typeHeaderLabel, timeLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 2
        headerTextStack.userInterfaceLayoutDirection = .leftToRight

        let headerView = NSView()
        headerView.userInterfaceLayoutDirection = .leftToRight
        headerView.wantsLayer = true
        let unselectedHeaderColor = headerColor(
            forTypeText: typeText,
            sourceColorKey: sourceColorKey,
            sourceIconColor: sourceIconColor,
            isSelected: false
        )
        headerView.layer?.backgroundColor = headerColor(
            forTypeText: typeText,
            sourceColorKey: sourceColorKey,
            sourceIconColor: sourceIconColor,
            isSelected: isSelected
        ).cgColor
        headerView.layer?.cornerRadius = Layout.cardCornerRadius
        headerView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        headerView.layer?.masksToBounds = true
        headerView.layer?.contentsScale = container.layer?.contentsScale ?? 2
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerTextStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerTextStack)
        headerView.addSubview(iconView)
        container.configureSelectionAppearance(
            headerView: headerView,
            typeHeaderLabel: typeHeaderLabel,
            timeLabel: timeLabel,
            unselectedHeaderColor: unselectedHeaderColor,
            isSelected: isSelected
        )

        let summaryLabel = makeBodyLabel(summary)
        let contentContainer = makeCardContentContainer(
            previewView: previewView,
            summaryLabel: summaryLabel
        )

        let indexLabel = NSTextField(labelWithString: "")
        indexLabel.font = .systemFont(ofSize: 11, weight: .medium)
        indexLabel.textColor = .tertiaryLabelColor
        indexLabel.lineBreakMode = .byTruncatingTail
        configureLeftToRightText(indexLabel, alignment: .right)
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)
        indexLabel.isHidden = true

        let countLabel = NSTextField(labelWithString: contentFootnote(for: summary))
        countLabel.stringValue = footnote ?? contentFootnote(for: summary)
        countLabel.font = .systemFont(ofSize: 10, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        configureLeftToRightText(countLabel)

        let footerRow = NSStackView(views: [countLabel, NSView(), indexLabel])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 6
        footerRow.userInterfaceLayoutDirection = .leftToRight
        container.configureCommandIndexLabel(indexLabel)

        let flexibleSpacer = NSView()
        flexibleSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        flexibleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let bodyStack = NSStackView(views: [contentContainer, flexibleSpacer, footerRow])
        bodyStack.orientation = .vertical
        bodyStack.alignment = .width
        bodyStack.spacing = 8
        bodyStack.userInterfaceLayoutDirection = .leftToRight
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        container.contentView?.addSubview(headerView)
        container.contentView?.addSubview(bodyStack)

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: Layout.defaultItemHeight)
        itemHeightConstraints.append(heightConstraint)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Layout.defaultItemWidth),
            heightConstraint,

            headerView.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: container.contentView!.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Layout.cardHeaderHeight),

            headerTextStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: Layout.cardInset),
            headerTextStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor, constant: -1),
            headerTextStack.trailingAnchor.constraint(lessThanOrEqualTo: iconView.leadingAnchor, constant: -8),

            iconView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: headerView.topAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Layout.sourceIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Layout.cardHeaderHeight),

            bodyStack.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor, constant: Layout.cardInset),
            bodyStack.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor, constant: -Layout.cardInset),
            bodyStack.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            bodyStack.bottomAnchor.constraint(equalTo: container.contentView!.bottomAnchor, constant: -10)
        ])

        return container
    }

    private func makeCardContentContainer(
        previewView: NSView?,
        summaryLabel: NSTextField
    ) -> NSView {
        let container = NSView()
        container.userInterfaceLayoutDirection = .leftToRight
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)

        if let previewView {
            previewView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(previewView)
            container.addSubview(summaryLabel)

            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                previewView.topAnchor.constraint(equalTo: container.topAnchor),

                summaryLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                summaryLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                summaryLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
                summaryLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            container.addSubview(summaryLabel)

            NSLayoutConstraint.activate([
                summaryLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                summaryLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                summaryLabel.topAnchor.constraint(equalTo: container.topAnchor),
                summaryLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        container.widthAnchor.constraint(equalToConstant: Layout.defaultItemWidth - Layout.cardInset * 2).isActive = true

        return container
    }

    private func makeSkeletonBar(width: CGFloat, height: CGFloat) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.13).cgColor
        view.layer?.cornerRadius = height / 2
        view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height)
        ])

        return view
    }

    private func makeImagePreview(previewPath: String?, payloadPath: String?, summary: String) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = 0
        container.layer?.masksToBounds = false
        container.layer?.borderWidth = 0
        container.layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        let imagePaths = Self.existingPreviewImagePaths(paths: [previewPath, payloadPath])
        let resolvedImage = Self.cachedPreviewImage(paths: imagePaths)
        imageView.image = resolvedImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 7
        imageView.layer?.masksToBounds = true
        imageView.toolTip = [previewPath, payloadPath]
            .compactMap { $0 }
            .joined(separator: "\n")
        imageView.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)
        itemImagePreviewViews.append(imageView)

        container.addSubview(imageView)

        let fallbackLabel = NSTextField(labelWithString: imagePaths.isEmpty ? "预览不可用" : "载入预览")
        fallbackLabel.font = .systemFont(ofSize: 12, weight: .medium)
        fallbackLabel.textColor = .secondaryLabelColor
        fallbackLabel.alignment = .center
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.isHidden = resolvedImage != nil
        container.addSubview(fallbackLabel)

        NSLayoutConstraint.activate([
            fallbackLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        if resolvedImage == nil, !imagePaths.isEmpty {
            let loadIdentifier = imageView.identifier
            Self.loadPreviewImageAsync(paths: imagePaths) { [weak imageView, weak fallbackLabel] image in
                guard imageView?.identifier == loadIdentifier else { return }
                imageView?.image = image
                fallbackLabel?.stringValue = image == nil ? "预览不可用" : ""
                fallbackLabel?.isHidden = image != nil
            }
        }

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: 92)
        heightConstraint.priority = .defaultHigh
        itemPreviewHeightConstraints.append(heightConstraint)

        NSLayoutConstraint.activate([
            heightConstraint,
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 18),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])

        return container
    }

    private func makeLinkPreview(for item: RustClipboardItemSummary) -> NSView {
        let presentation = linkPresentation(for: item)
        let container = makePreviewSurface(
            tintColor: NSColor.systemBlue,
            height: Layout.linkPreviewHeight
        )

        let iconContainer = makePreviewIconContainer(
            symbolName: "link",
            tintColor: NSColor.systemBlue,
            accessibilityLabel: "链接"
        )

        let titleLabel = NSTextField(labelWithString: presentation.host)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        configureLeftToRightText(titleLabel)

        let detailLabel = NSTextField(labelWithString: presentation.detail)
        detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        configureLeftToRightText(detailLabel)

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.userInterfaceLayoutDirection = .leftToRight
        textStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconContainer)
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            iconContainer.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 9),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeFilePreview(for item: RustClipboardItemSummary) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = filePreviewImage(for: item)
            ?? NSImage(systemSymbolName: "doc", accessibilityDescription: "文件")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: 92)
        heightConstraint.priority = .defaultHigh
        itemPreviewHeightConstraints.append(heightConstraint)
        NSLayoutConstraint.activate([
            heightConstraint,
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.defaultItemWidth - 72),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 76),
            imageView.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])

        return container
    }

    private func makePreviewSurface(tintColor: NSColor, height: CGFloat) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = tintColor.withAlphaComponent(0.09).cgColor
        container.layer?.cornerRadius = Layout.innerCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = Layout.hairlineWidth
        container.layer?.borderColor = tintColor.withAlphaComponent(0.16).cgColor
        container.layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        container.translatesAutoresizingMaskIntoConstraints = false

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: height)
        heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([heightConstraint])

        return container
    }

    private func makePreviewIconContainer(
        symbolName: String,
        tintColor: NSColor,
        accessibilityLabel: String
    ) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = tintColor.withAlphaComponent(0.16).cgColor
        container.layer?.cornerRadius = 9
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        iconView.contentTintColor = tintColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalToConstant: 34),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])

        return container
    }

    private func makePreviewBadge(_ text: String) -> NSView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 7
        visualEffectView.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -4),
            visualEffectView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.defaultItemWidth - 44)
        ])

        return visualEffectView
    }

    private static func existingPreviewImagePaths(paths: [String?]) -> [String] {
        paths.compactMap { path in
            let path = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty else { return nil }
            let url = resolvedImageURL(for: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return url.path
        }
    }

    private static func cachedPreviewImage(paths: [String]) -> NSImage? {
        for path in paths {
            if let image = imageCache.object(forKey: path as NSString) {
                return image
            }
        }

        return nil
    }

    private static func loadPreviewImageAsync(
        paths: [String],
        completion: @escaping @MainActor (NSImage?) -> Void
    ) {
        Task { @MainActor in
            let loadedData = await Task.detached(priority: .userInitiated) { () -> (String, Data)? in
                for path in paths {
                    let url = URL(fileURLWithPath: path)
                    if let data = try? Data(contentsOf: url) {
                        return (path, data)
                    }
                }
                return nil
            }.value

            guard let (path, data) = loadedData,
                  let image = NSImage(data: data)
            else {
                completion(nil)
                return
            }

            imageCache.setObject(image, forKey: path as NSString)
            completion(image)
        }
    }

    private static func loadCachedImage(path: String) -> NSImage? {
        let key = path as NSString
        if let cachedImage = imageCache.object(forKey: key) {
            return cachedImage
        }

        let url = URL(fileURLWithPath: path)
        let image = NSImage(contentsOf: url)
            ?? ((try? Data(contentsOf: url)).flatMap(NSImage.init(data:)))
        if let image {
            imageCache.setObject(image, forKey: key)
        }

        return image
    }

    private static func dominantHeaderColor(
        for image: NSImage,
        cacheKey: String?,
        fallbackCacheKey: String?
    ) -> NSColor? {
        let resolvedCacheKey = cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedCacheKey,
           !resolvedCacheKey.isEmpty,
           let cachedColor = sourceColorCache.object(forKey: resolvedCacheKey as NSString) {
            return cachedColor
        }

        let resolvedFallbackCacheKey = fallbackCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedFallbackCacheKey,
           !resolvedFallbackCacheKey.isEmpty,
           resolvedFallbackCacheKey != resolvedCacheKey,
           let cachedColor = sourceColorCache.object(forKey: resolvedFallbackCacheKey as NSString) {
            if let resolvedCacheKey, !resolvedCacheKey.isEmpty {
                sourceColorCache.setObject(cachedColor, forKey: resolvedCacheKey as NSString)
            }
            return cachedColor
        }

        guard let bitmap = sampledBitmap(for: image) else {
            return nil
        }

        struct Bucket {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var weight: CGFloat = 0
        }

        var buckets = Array(repeating: Bucket(), count: 24)
        let step = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 24)

        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB)
                else {
                    continue
                }

                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

                guard alpha > 0.35,
                      saturation > 0.18,
                      brightness > 0.12,
                      !(brightness > 0.94 && saturation < 0.30)
                else {
                    continue
                }

                let bucketIndex = min(buckets.count - 1, max(0, Int((hue * CGFloat(buckets.count)).rounded(.down))))
                let weight = pow(saturation, 1.35) * alpha * min(max(brightness, 0.25), 1)
                guard weight > 0 else { continue }

                buckets[bucketIndex].red += color.redComponent * weight
                buckets[bucketIndex].green += color.greenComponent * weight
                buckets[bucketIndex].blue += color.blueComponent * weight
                buckets[bucketIndex].weight += weight
            }
        }

        guard let selectedBucket = buckets.max(by: { $0.weight < $1.weight }),
              selectedBucket.weight > 0
        else {
            return nil
        }

        let averagedColor = NSColor(
            srgbRed: selectedBucket.red / selectedBucket.weight,
            green: selectedBucket.green / selectedBucket.weight,
            blue: selectedBucket.blue / selectedBucket.weight,
            alpha: 1
        )
        guard let normalizedColor = normalizedHeaderColor(averagedColor) else {
            return nil
        }

        if let resolvedCacheKey, !resolvedCacheKey.isEmpty {
            sourceColorCache.setObject(normalizedColor, forKey: resolvedCacheKey as NSString)
        }
        if let resolvedFallbackCacheKey,
           !resolvedFallbackCacheKey.isEmpty,
           resolvedFallbackCacheKey != resolvedCacheKey {
            sourceColorCache.setObject(normalizedColor, forKey: resolvedFallbackCacheKey as NSString)
        }

        return normalizedColor
    }

    private static func sampledBitmap(for image: NSImage) -> NSBitmapImageRep? {
        if let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return bitmap
        }

        let targetSize = NSSize(width: 48, height: 48)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func normalizedHeaderColor(_ color: NSColor) -> NSColor? {
        guard let color = color.usingColorSpace(.sRGB) else {
            return nil
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return NSColor(
            calibratedHue: hue,
            saturation: min(max(saturation, 0.48), 0.82),
            brightness: min(max(brightness, 0.58), 0.88),
            alpha: 1
        )
    }

    private static func resolvedImageURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }

        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first?
        .appendingPathComponent("ClipboardWorkbench", isDirectory: true)

        return (appSupportURL ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent(path)
    }

    private func makeBodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: leftToRightDisplayText(text))
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4
        label.preferredMaxLayoutWidth = Layout.defaultItemWidth - Layout.cardInset * 2 - 4
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.cell?.lineBreakMode = .byWordWrapping
        configureLeftToRightText(label, lineSpacing: 2)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func leftToRightDisplayText(_ text: String) -> String {
        text.isEmpty ? text : "\u{200E}\(text)"
    }

    private func configureLeftToRightText(
        _ label: NSTextField,
        alignment: NSTextAlignment = .left,
        lineSpacing: CGFloat = 0
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.baseWritingDirection = .leftToRight
        paragraph.lineBreakMode = label.lineBreakMode
        paragraph.lineSpacing = lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: label.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: label.textColor ?? NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        label.attributedStringValue = NSAttributedString(
            string: label.stringValue,
            attributes: attributes
        )
        label.alignment = alignment
        label.userInterfaceLayoutDirection = .leftToRight
        label.cell?.alignment = alignment
        label.cell?.baseWritingDirection = .leftToRight
    }

    private func makeToolbarIconButton(
        symbolName: String,
        accessibilityLabel: String,
        onPress: @escaping () -> Void
    ) -> PanelActionButton {
        let button = PanelActionButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        button.imageScaling = .scaleProportionallyDown
        button.target = nil
        button.action = nil
        button.onPress = onPress
        button.toolTip = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = Layout.chipCornerRadius
        button.layer?.backgroundColor = NSColor.clear.cgColor

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])

        return button
    }

    private func makeTypeFilterChip(
        title: String,
        itemType: String?,
        dotColor: NSColor
    ) -> TypeFilterChipButton {
        let button = TypeFilterChipButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.target = nil
        button.action = nil
        button.itemType = itemType
        button.onPress = { [weak self, weak button] in
            guard let button else { return }
            self?.typeFilterChipPressed(button)
        }
        button.toolTip = itemType == nil ? "全部类型" : "仅显示\(title)"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = Layout.chipCornerRadius
        button.setButtonType(.momentaryChange)
        button.attributedTitle = chipTitle(title, dotColor: dotColor)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: itemType == nil ? 72 : 58)
        ])

        return button
    }

    private func updateTypeFilterChipAppearance() {
        typeFilterButtons.forEach { button in
            let isSelected = button.itemType == currentItemTypeFilter
            button.layer?.backgroundColor = isSelected
                ? NSColor.windowBackgroundColor.withAlphaComponent(0.48).cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = isSelected ? .controlAccentColor : .labelColor
        }
    }

    private func chipTitle(_ title: String, dotColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.baseWritingDirection = .leftToRight
        if dotColor != .clear {
            result.append(NSAttributedString(
                string: "● ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: dotColor,
                    .paragraphStyle: paragraph
                ]
            ))
        }
        result.append(NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        ))
        return result
    }

    private func symbolName(forType typeText: String) -> String {
        switch typeText {
        case "链接":
            return "link"
        case "图片":
            return "photo"
        case "文件":
            return "folder"
        case "颜色":
            return "paintpalette"
        case "错误":
            return "exclamationmark.triangle"
        case "空态":
            return "tray"
        default:
            return "text.alignleft"
        }
    }

    private func symbolName(forItemType itemType: String) -> String {
        switch itemType {
        case "link":
            return "link"
        case "image":
            return "photo"
        case "file":
            return "folder"
        case "color":
            return "paintpalette"
        case "rich_text":
            return "doc.richtext"
        default:
            return "doc.text"
        }
    }

    private func displayType(forItemType itemType: String) -> String {
        switch itemType {
        case "link":
            return "链接"
        case "image":
            return "图片"
        case "file":
            return "文件"
        case "color":
            return "颜色"
        case "rich_text":
            return "富文本"
        default:
            return "文本"
        }
    }

    private func displayType(for item: RustClipboardItemSummary) -> String {
        let type = displayType(forItemType: item.itemType)
        return item.isPinned ? "固定 · \(type)" : type
    }

    private func displaySummary(for item: RustClipboardItemSummary) -> String {
        if item.itemType == "file" {
            let copyText = item.copyCount > 1 ? " · \(item.copyCount) 次复制" : ""
            return "\(firstFileDisplayPath(for: item) ?? filePreviewDetail(for: item))\(copyText)"
        }

        if item.itemType == "link" {
            let presentation = linkPresentation(for: item)
            if item.summary.trimmingCharacters(in: .whitespacesAndNewlines) == presentation.host {
                return presentation.detail
            }

            return item.summary
        }

        guard item.itemType == "image" else {
            return item.summary
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        let sizeText = formatter.string(fromByteCount: item.sizeBytes)
        let copyText = item.copyCount > 1 ? " · \(item.copyCount) 次复制" : ""
        return "PNG · \(sizeText)\(copyText)"
    }

    private func linkPresentation(for item: RustClipboardItemSummary) -> (host: String, detail: String) {
        let rawText = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = normalizedURL(from: rawText)
        let host = url?.host?.replacingOccurrences(of: "www.", with: "") ?? rawText
        let path = url.map { url -> String in
            let path = url.path.isEmpty ? "/" : url.path
            let query = url.query.map { "?\($0)" } ?? ""
            return "\(url.scheme ?? "https")://\(url.host ?? host)\(path)\(query)"
        }

        return (
            host: host.isEmpty ? "网页链接" : host,
            detail: path ?? (rawText.isEmpty ? "网页链接" : rawText)
        )
    }

    private func normalizedURL(from text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.host != nil {
            return url
        }

        return URL(string: "https://\(text)").flatMap { $0.host == nil ? nil : $0 }
    }

    private func filePreviewTitle(for item: RustClipboardItemSummary) -> String {
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return "文件" }
        if let separatorRange = summary.range(of: " · ") {
            return String(summary[..<separatorRange.lowerBound])
        }

        return summary
    }

    private func filePreviewDetail(for item: RustClipboardItemSummary) -> String {
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return "本地文件路径" }
        if let separatorRange = summary.range(of: " · ") {
            let detail = String(summary[separatorRange.upperBound...])
            return detail.isEmpty ? summary : detail
        }

        return item.copyCount > 1 ? "\(item.copyCount) 次复制" : summary
    }

    private func firstFileDisplayPath(for item: RustClipboardItemSummary) -> String? {
        filePreviewURLs(for: item)
            .first?
            .path
    }

    private func filePreviewImage(for item: RustClipboardItemSummary) -> NSImage? {
        for url in filePreviewURLs(for: item) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 96, height: 96)
            return icon
        }

        return NSImage(systemSymbolName: "folder", accessibilityDescription: "文件")
    }

    private func filePreviewURLs(for item: RustClipboardItemSummary) -> [URL] {
        if let snapshotPaths = fileSnapshotPaths(for: item), !snapshotPaths.isEmpty {
            return snapshotPaths.map(resolvedFileURL(for:))
        }

        return item.primaryText?
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map(resolvedFileURL(for:)) ?? []
    }

    private func fileSnapshotPaths(for item: RustClipboardItemSummary) -> [String]? {
        for path in [item.payloadAssetPath, item.previewAssetPath]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !path.isEmpty {
            let url = resolvedFileURL(for: path)
            guard let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(FileSnapshotPreviewDocument.self, from: data),
                  !document.paths.isEmpty
            else {
                continue
            }
            return document.paths
        }

        return nil
    }

    private func resolvedFileURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }

        if let appSupportDirectory {
            return appSupportDirectory.appendingPathComponent(path)
        }

        return Self.resolvedImageURL(for: path)
    }

    private struct FileSnapshotPreviewDocument: Decodable {
        let paths: [String]
    }

    private func sourceColorKey(for item: RustClipboardItemSummary) -> String? {
        if let sourceAppID = item.sourceAppId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceAppID.isEmpty {
            return sourceAppID
        }

        if let sourceAppName = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceAppName.isEmpty {
            return sourceAppName
        }

        return nil
    }

    private func headerColor(
        forTypeText typeText: String,
        sourceColorKey: String?,
        sourceIconColor: NSColor?,
        isSelected: Bool
    ) -> NSColor {
        if typeText.contains("错误") {
            return NSColor.systemRed.withAlphaComponent(isSelected ? 0.96 : 0.88)
        }

        if typeText.contains("空态") {
            return NSColor.systemGray.withAlphaComponent(isSelected ? 0.90 : 0.82)
        }

        if let sourceIconColor {
            return sourceIconColor.withAlphaComponent(isSelected ? 0.98 : 0.90)
        }

        if let sourceColorKey,
           !sourceColorKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceHeaderColor(for: sourceColorKey, isSelected: isSelected)
        }

        if typeText.contains("链接") {
            return NSColor.systemPurple.withAlphaComponent(isSelected ? 1 : 0.92)
        }

        if typeText.contains("图片") {
            return NSColor.systemBlue.withAlphaComponent(isSelected ? 1 : 0.86)
        }

        if typeText.contains("文件") {
            return NSColor.systemBlue.withAlphaComponent(isSelected ? 0.94 : 0.78)
        }

        return NSColor.systemBlue.withAlphaComponent(isSelected ? 1 : 0.92)
    }

    private func sourceHeaderColor(for key: String, isSelected: Bool) -> NSColor {
        let palette: [NSColor] = [
            .systemBlue,
            .systemPurple,
            .systemGreen,
            .systemOrange,
            .systemTeal,
            .systemPink,
            .systemIndigo,
            .systemMint,
            .systemBrown
        ]
        let index = stableColorIndex(for: key, count: palette.count)
        return palette[index].withAlphaComponent(isSelected ? 0.98 : 0.90)
    }

    private func stableColorIndex(for key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }

        return Int(hash % UInt64(count))
    }

    private func headerTextColor(isSelected: Bool) -> NSColor {
        .white
    }

    private func headerSecondaryTextColor(isSelected: Bool) -> NSColor {
        NSColor.white.withAlphaComponent(0.80)
    }

    private func contentFootnote(for summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        return count > 0 ? "\(count) 个字符" : ""
    }

    private func contentFootnote(for item: RustClipboardItemSummary) -> String {
        switch item.itemType {
        case "image":
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: item.sizeBytes)
        case "link":
            return linkPresentation(for: item).host
        case "file":
            return item.copyCount > 1 ? "\(item.copyCount) 次复制" : ""
        default:
            return contentFootnote(for: item.summary)
        }
    }

    private func relativeTime(from milliseconds: Int64) -> String {
        let seconds = TimeInterval(milliseconds) / 1000
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

}

@MainActor
private extension FloatingPanelContentView {
    var smokeSelectedItemID: String? {
        selectedItemID
    }

    var smokeSearchField: NSSearchField {
        searchField
    }

    func smokeCardBoxes() -> [ClipboardItemCardBox] {
        allSmokeSubviews(of: self)
            .compactMap { $0 as? ClipboardItemCardBox }
            .filter { $0.itemID != nil }
    }

    func smokeTypeFilterButton(itemType: String?) -> TypeFilterChipButton? {
        typeFilterButtons.first { $0.itemType == itemType }
    }

    func smokeHorizontalScrollView() -> HorizontalWheelScrollView? {
        allSmokeSubviews(of: self)
            .compactMap { $0 as? HorizontalWheelScrollView }
            .first
    }

    func smokeCommandHintTexts() -> [String] {
        smokeCardBoxes()
            .compactMap { card in
                allSmokeSubviews(of: card)
                    .compactMap { $0 as? NSTextField }
                    .map(\.stringValue)
                    .first { Int($0) != nil }
            }
    }

    var smokeIsPreviewShown: Bool {
        previewPopoverController.isShown
    }

    func smokeClosePreviewWithSpaceFromPopoverFocus() -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: UInt16(kVK_Space)
        ) else {
            return false
        }

        return previewPopoverController.handleKeyDownForShownPopover(event)
    }

    func smokePerformManagementAction(itemID: String, title: String) -> Bool {
        guard let item = currentItems.first(where: { $0.id == itemID }) else { return false }
        let menu = makeManagementMenu(for: item)
        guard let actionItem = menu.items
            .compactMap({ $0 as? ActionMenuItem })
            .first(where: { $0.title == title })
        else {
            return false
        }

        actionItem.triggerForSmoke()
        return true
    }

    private func allSmokeSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSmokeSubviews(of:))
    }
}

@MainActor
private final class FloatingPanelController {
    private static let defaultPanelHeight = BottomPanelGeometryPlanner.defaultHeight

    private let panel: FloatingPanel
    private let contentView: FloatingPanelContentView
    private(set) var levelMode: PanelLevelMode = .aboveDock
    private var preferredHeight = FloatingPanelController.defaultPanelHeight
    private var resizeStartHeight = FloatingPanelController.defaultPanelHeight
    private var resizeScreen: NSScreen?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?

    var onRequestHide: (() -> Void)?
    var onQueryChanged: ((String, String?, String?) -> Void)?
    var onCopyRequested: ((RustClipboardItemSummary) -> Void)?
    var onPinRequested: ((RustClipboardItemSummary, Bool) -> Void)?
    var onDeleteRequested: ((RustClipboardItemSummary) -> Void)?
    var onClearRequested: ((String, String?, String?) -> Void)?

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
        panel.orderFrontRegardless()
        panel.makeFirstResponder(contentView)
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

    func updateStatus(dockIconVisible: Bool, hotKeyAvailable: Bool) {
        contentView.update(
            levelMode: levelMode,
            dockIconVisible: dockIconVisible,
            hotKeyAvailable: hotKeyAvailable,
            panelHeight: preferredHeight
        )
    }

    func updateStorageState(_ result: Result<RustCoreOpenResult, RustCoreError>) {
        contentView.updateStorageState(result)
    }

    func updateListState(_ result: Result<RustCoreListResult, RustCoreError>, isFiltered: Bool) {
        contentView.updateListState(result, isFiltered: isFiltered)
    }

    func updateSourceApps(_ apps: [RustSourceAppSummary], selectedSourceAppID: String?) {
        contentView.updateSourceApps(apps, selectedSourceAppID: selectedSourceAppID)
    }

    func setAppSupportDirectory(_ url: URL) {
        contentView.updateAppSupportDirectory(url)
    }

    func setPreviewPopoverEnabled(_ enabled: Bool) {
        contentView.setPreviewPopoverEnabled(enabled)
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
        // 使用完整 screen.frame，而不是 visibleFrame；这样窗口会进入 Dock 所在区域。
        // x 和 width 每次都锁死到显示器完整宽度，用户拖拽时只会改变高度。
        let frame = BottomPanelGeometryPlanner.frame(
            screenFrame: screen.frame,
            preferredHeight: height
        )

        panel.setFrame(frame, display: true, animate: animate)
        contentView.updatePanelHeight(height)
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
        contentView.onHide = { [weak self] in self?.onRequestHide?() }
        contentView.onHeightResizeBegan = { [weak self] in self?.beginHeightResize() }
        contentView.onHeightResizeChanged = { [weak self] deltaY in self?.resizeHeight(deltaY: deltaY) }
        contentView.onQueryChanged = { [weak self] searchText, itemType, sourceAppID in
            self?.onQueryChanged?(searchText, itemType, sourceAppID)
        }
        contentView.onCopyRequested = { [weak self] item in
            self?.onCopyRequested?(item)
        }
        contentView.onPinRequested = { [weak self] item, isPinned in
            self?.onPinRequested?(item, isPinned)
        }
        contentView.onDeleteRequested = { [weak self] item in
            self?.onDeleteRequested?(item)
        }
        contentView.onClearRequested = { [weak self] searchText, itemType, sourceAppID in
            self?.onClearRequested?(searchText, itemType, sourceAppID)
        }
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

        if PanelInteractionPlanner.shouldHideForOutsideMouseDown(
            eventWindowIsPanel: event.window === panel,
            mouseLocation: NSEvent.mouseLocation,
            panelFrame: panel.frame
        ) {
            hide()
        }
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
private extension FloatingPanelController {
    var smokeContentView: FloatingPanelContentView {
        contentView
    }
}

private enum PreferenceSection: Int, CaseIterable {
    case general
    case ignoreList
    case shortcuts
    case history
    case appearance

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .shortcuts:
            return "键盘快捷键"
        case .history:
            return "保留历史"
        case .ignoreList:
            return "隐私"
        case .appearance:
            return "外观"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "启动、菜单栏与底部面板"
        case .shortcuts:
            return "打开、搜索与快速取用"
        case .history:
            return "保存数量、保留时长与内容类型"
        case .ignoreList:
            return "来源权限、忽略规则与窗口标题"
        case .appearance:
            return "外观模式、密度与预览行为"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .shortcuts:
            return "keyboard"
        case .history:
            return "clock.arrow.circlepath"
        case .ignoreList:
            return "hand.raised"
        case .appearance:
            return "circle.lefthalf.filled"
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

private final class PreferenceNavigationButton: NSButton {
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

private final class PreferenceActionButton: NSButton {
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

private final class PreferenceSwitch: NSSwitch {
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

private final class PreferenceCheckboxButton: NSButton {
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

private final class PreferenceSegmentedControl: NSSegmentedControl {
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

private final class PreferenceStepper: NSStepper {
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

private typealias LaunchAtLoginState = LaunchAtLoginPresentation
private typealias AccessibilityPermissionState = AccessibilityPermissionPresentation

private struct LaunchAtLoginError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
private final class LaunchAtLoginController {
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

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled,
                   SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled
                || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
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
private final class AccessibilityPermissionController {
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
private final class PreferencesWindowController: NSWindowController {
    private enum Layout {
        static let defaultWindowSize = NSSize(width: 920, height: 700)
        static let minimumWindowSize = NSSize(width: 820, height: 600)
        static let sidebarWidth: CGFloat = 264
        static let contentInset: CGFloat = 36
        static let sidebarInset: CGFloat = 16
        static let sidebarTopInset: CGFloat = 74
        static let rowHeight: CGFloat = 62
        static let rowHorizontalInset: CGFloat = 20
        static let cardCornerRadius: CGFloat = 18
        static let windowCornerRadius: CGFloat = 24
        static let contentMaximumWidth: CGFloat = 640
    }

    private let rootView = NSView()
    private let sidebarStack = NSStackView()
    private let contentView = NSView()
    private var selectedSection: PreferenceSection = .general
    private var navigationButtons: [PreferenceSection: NSButton] = [:]
    private var stepperBindings: [StepperTextBinding] = []
    private var textInputBindings: [TextInputBinding] = []
    private var isPersistingPreferenceChange = false
    private var pendingDeferredRender = false
    private var preferences = RustPreferencesDocument()
    private var launchAtLoginState = LaunchAtLoginState(
        isOn: false,
        canChange: false,
        detail: "正在读取状态"
    )
    private var accessibilityPermissionState = AccessibilityPermissionState(
        isTrusted: false,
        detail: "正在读取状态",
        actionTitle: "重新检查",
        canOpenSettings: true
    )

    var onPreferencesChanged: ((RustPreferencesDocument) -> RustPreferencesDocument?)?
    var onAccessibilityPermissionRequested: (() -> Void)?

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
        window.backgroundColor = .clear
        window.isOpaque = false

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

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updatePreferences(_ preferences: RustPreferencesDocument) {
        self.preferences = preferences
        renderSelectedSection()
    }

    func updateLaunchAtLoginState(_ state: LaunchAtLoginState) {
        launchAtLoginState = state
        if selectedSection == .general {
            renderSelectedSectionRespectingControlAction()
        }
    }

    func updateAccessibilityPermissionState(_ state: AccessibilityPermissionState) {
        accessibilityPermissionState = state
        if selectedSection == .ignoreList {
            renderSelectedSectionRespectingControlAction()
        }
    }

    private func configureWindow(_ window: NSWindow) {
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        rootView.layer?.cornerRadius = Layout.windowCornerRadius
        rootView.layer?.masksToBounds = true
        rootView.layer?.borderWidth = 0.5
        rootView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        window.contentView = rootView

        let sidebar = makeSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(sidebar)
        rootView.addSubview(contentView)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 14),
            sidebar.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),
            sidebar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -14),
            sidebar.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth),

            contentView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 24),
            contentView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),
            contentView.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    private func makeSidebar() -> NSView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = Layout.windowCornerRadius - 6
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 0.5
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .width
        sidebarStack.spacing = 6
        sidebarStack.edgeInsets = NSEdgeInsets(
            top: Layout.sidebarTopInset,
            left: Layout.sidebarInset,
            bottom: 22,
            right: Layout.sidebarInset
        )
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false

        PreferenceSection.allCases.forEach { section in
            let button = makeNavigationButton(for: section)
            navigationButtons[section] = button
            sidebarStack.addArrangedSubview(button)

            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth - Layout.sidebarInset * 2),
                button.heightAnchor.constraint(equalToConstant: 42)
            ])
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        sidebarStack.addArrangedSubview(spacer)

        visualEffectView.addSubview(sidebarStack)

        NSLayoutConstraint.activate([
            sidebarStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            sidebarStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            sidebarStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            sidebarStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        return visualEffectView
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
        button.font = .systemFont(ofSize: 16, weight: .semibold)
        button.wantsLayer = true
        button.layer?.cornerRadius = 11
        button.contentTintColor = .labelColor
        button.tag = section.rawValue
        button.translatesAutoresizingMaskIntoConstraints = false
        button.onPress = { [weak self] in
            self?.selectSection(section)
        }
        return button
    }

    private func selectSection(_ section: PreferenceSection) {
        selectedSection = section
        renderSelectedSection()
        updateNavigationSelection()
    }

    private func updateNavigationSelection() {
        navigationButtons.forEach { section, button in
            let isSelected = section == selectedSection
            button.state = isSelected ? .on : .off
            button.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = isSelected ? .white : .labelColor
            button.attributedTitle = NSAttributedString(
                string: section.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: isSelected ? NSColor.white : NSColor.labelColor
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
        switch section {
        case .general:
            return makeContentPage(
                title: section.title,
                subtitle: section.subtitle,
                sections: [
                    makeSection(title: "启动", rows: [
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
                            title: "在菜单栏显示",
                            detail: "保留状态栏入口与快速菜单",
                            control: makeSwitch(isOn: preferences.general.showMenuBarItem) { [weak self] isOn in
                                self?.persist { $0.general.showMenuBarItem = isOn }
                            }
                        )
                    ]),
                    makeSection(title: "底部面板", rows: [
                        makeSettingRow(
                            title: "面板高度",
                            detail: "当前 \(preferences.general.defaultPanelHeight) pt，宽度跟随显示器",
                            control: makeStepperField(
                                value: Int(preferences.general.defaultPanelHeight),
                                minimumValue: 260,
                                maximumValue: 560
                            ) { [weak self] value in
                                self?.persist { $0.general.defaultPanelHeight = Int64(value) }
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
                            shortcut: "⌘ ⇧ V"
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
        case .history:
            return makeContentPage(
                title: section.title,
                subtitle: section.subtitle,
                sections: [
                    makeSection(title: "保存规则", rows: [
                        makeSettingRow(
                            title: "保存数量",
                            detail: "最多保留条目",
                            control: makeStepperField(
                                value: Int(preferences.history.maxItems),
                                minimumValue: 50,
                                maximumValue: 5000
                            ) { [weak self] value in
                                self?.persist { $0.history.maxItems = Int64(value) }
                            }
                        ),
                        makeSettingRow(
                            title: "保留时长",
                            detail: "过期后可清理",
                            control: makeStepperField(
                                value: Int(preferences.history.retentionDays),
                                minimumValue: 1,
                                maximumValue: 365
                            ) { [weak self] value in
                                self?.persist { $0.history.retentionDays = Int64(value) }
                            }
                        )
                    ]),
                    makeSection(title: "内容类型", rows: [
                        makeSettingRow(
                            title: "记录图片",
                            detail: "保存图片摘要",
                            control: makeSwitch(isOn: preferences.history.recordImages) { [weak self] isOn in
                                self?.persist { $0.history.recordImages = isOn }
                            }
                        ),
                        makeSettingRow(
                            title: "记录文件",
                            detail: "保存文件路径",
                            control: makeSwitch(isOn: preferences.history.recordFiles) { [weak self] isOn in
                                self?.persist { $0.history.recordFiles = isOn }
                            }
                        )
                    ])
                ]
            )
        case .ignoreList:
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
        case .appearance:
            return makeContentPage(
                title: section.title,
                subtitle: section.subtitle,
                sections: [
                    makeSection(title: "颜色模式", rows: [
                        makeSettingRow(
                            title: "外观模式",
                            detail: "窗口颜色偏好",
                            control: makeSegmentedControl(
                                labels: ["亮色", "暗色", "跟随系统"],
                                selected: appearanceModeIndex(preferences.appearance.mode)
                            ) { [weak self] selected in
                                self?.persist { $0.appearance.mode = self?.appearanceModeValue(selected) ?? "system" }
                            }
                        )
                    ]),
                    makeSection(title: "浏览体验", rows: [
                        makeSettingRow(
                            title: "条目密度",
                            detail: "调整条目间距",
                            control: makeSegmentedControl(
                                labels: ["紧凑", "标准"],
                                selected: preferences.appearance.itemDensity == "compact" ? 0 : 1
                            ) { [weak self] selected in
                                self?.persist { $0.appearance.itemDensity = selected == 0 ? "compact" : "standard" }
                            }
                        ),
                        makeSettingRow(
                            title: "预览浮层",
                            detail: "空格展开预览",
                            control: makeSwitch(isOn: preferences.appearance.previewPopoverEnabled) { [weak self] isOn in
                                self?.persist { $0.appearance.previewPopoverEnabled = isOn }
                            }
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
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false

        let headingStack = NSStackView()
        headingStack.orientation = .vertical
        headingStack.alignment = .leading
        headingStack.spacing = 4
        headingStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 28, weight: .bold), color: .labelColor)
        let subtitleLabel = makeLabel(subtitle, font: .systemFont(ofSize: 13, weight: .regular), color: .secondaryLabelColor)
        headingStack.addArrangedSubview(titleLabel)
        headingStack.addArrangedSubview(subtitleLabel)
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

        let availableWidthConstraint = stack.widthAnchor.constraint(
            equalTo: page.widthAnchor,
            constant: -Layout.contentInset * 2
        )
        availableWidthConstraint.priority = .defaultHigh
        let preferredMaximumWidthConstraint = stack.widthAnchor.constraint(
            equalToConstant: Layout.contentMaximumWidth
        )
        preferredMaximumWidthConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: Layout.contentInset + 8),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -Layout.contentInset),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.contentMaximumWidth),
            availableWidthConstraint,
            preferredMaximumWidthConstraint
        ])

        return page
    }

    private func makeSection(title: String, rows: [NSView]) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor)
        stack.addArrangedSubview(titleLabel)

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
        card.layer?.cornerRadius = Layout.cardCornerRadius
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.36).cgColor

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

        let titleLabel = makeLabel(title, font: .systemFont(ofSize: 15, weight: .medium), color: .labelColor)
        let detailLabel = makeLabel(detail, font: .systemFont(ofSize: 12.5), color: .secondaryLabelColor)

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
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(rowStack)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.rowHeight),
            rowStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Layout.rowHorizontalInset),
            rowStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Layout.rowHorizontalInset),
            rowStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            rowStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8)
        ])

        return row
    }

    private func makeShortcutRow(title: String, detail: String, shortcut: String) -> NSView {
        makeSettingRow(title: title, detail: detail, control: makeShortcutPill(shortcut))
    }

    private func makeShortcutPill(_ shortcut: String) -> NSView {
        let shortcutField = NSTextField(labelWithString: shortcut)
        shortcutField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        shortcutField.alignment = .center
        shortcutField.textColor = .labelColor
        shortcutField.wantsLayer = true
        shortcutField.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        shortcutField.layer?.cornerRadius = 9
        shortcutField.layer?.cornerCurve = .continuous
        shortcutField.layer?.borderWidth = 0.5
        shortcutField.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        shortcutField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            shortcutField.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            shortcutField.heightAnchor.constraint(equalToConstant: 30)
        ])

        return shortcutField
    }

    private func makeTextInputRow(
        title: String,
        detail: String,
        value: String,
        onCommit: ((String) -> Void)? = nil
    ) -> NSView {
        let textField = NSTextField(string: value)
        textField.font = .systemFont(ofSize: 13)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior

        if let onCommit {
            textInputBindings.append(TextInputBinding(textField: textField, onCommit: onCommit))
        }

        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 300),
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
        var nextPreferences = preferences
        update(&nextPreferences)

        isPersistingPreferenceChange = true
        if let savedPreferences = onPreferencesChanged?(nextPreferences) {
            preferences = savedPreferences
        } else {
            preferences = nextPreferences
        }
        isPersistingPreferenceChange = false
    }

    private func renderSelectedSectionRespectingControlAction() {
        guard !isPersistingPreferenceChange else {
            scheduleDeferredRender()
            return
        }

        renderSelectedSection()
    }

    private func scheduleDeferredRender() {
        guard !pendingDeferredRender else { return }
        pendingDeferredRender = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingDeferredRender = false
            self.renderSelectedSection()
        }
    }

    private func makeSwitch(
        isOn: Bool,
        isEnabled: Bool = true,
        onChange: ((Bool) -> Void)? = nil
    ) -> NSSwitch {
        let control = PreferenceSwitch()
        control.state = isOn ? .on : .off
        control.isEnabled = isEnabled
        control.target = nil
        control.action = nil
        control.onChange = onChange
        return control
    }

    private func makeCheckbox(title: String, isOn: Bool, onChange: ((Bool) -> Void)? = nil) -> NSButton {
        let button = PreferenceCheckboxButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = isOn ? .on : .off
        button.target = nil
        button.action = nil
        button.onChange = onChange
        return button
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
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 72),
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
        control.controlSize = .regular
        control.selectedSegment = selected
        control.target = nil
        control.action = nil
        control.onChange = onChange
        labels.indices.forEach { index in
            control.setWidth(labels[index].count > 3 ? 86 : 64, forSegment: index)
        }
        return control
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
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
        return button
    }

    private func appearanceModeIndex(_ mode: String) -> Int {
        switch mode {
        case "light":
            return 0
        case "dark":
            return 1
        default:
            return 2
        }
    }

    private func appearanceModeValue(_ index: Int) -> String {
        switch index {
        case 0:
            return "light"
        case 1:
            return "dark"
        default:
            return "system"
        }
    }

    private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
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
        line.fillColor = NSColor.separatorColor.withAlphaComponent(0.5)
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
private struct CapturedSourceApplication {
    let processIdentifier: pid_t
    let bundleId: String?
    let name: String
    let bundlePath: String?
    let windowTitle: String?
    let icon: NSImage?

    func updatingWindowTitle(_ windowTitle: String?) -> CapturedSourceApplication {
        CapturedSourceApplication(
            processIdentifier: processIdentifier,
            bundleId: bundleId,
            name: name,
            bundlePath: bundlePath,
            windowTitle: windowTitle,
            icon: icon
        )
    }
}

private final class SourceWindowTitleProvider {
    func title(for application: NSRunningApplication) -> String? {
        title(forProcessIdentifier: application.processIdentifier)
    }

    func title(forProcessIdentifier processIdentifier: pid_t) -> String? {
        accessibilityFocusedWindowTitle(forProcessIdentifier: processIdentifier)
            ?? visibleWindowTitle(forProcessIdentifier: processIdentifier)
    }

    private func accessibilityFocusedWindowTitle(forProcessIdentifier processIdentifier: pid_t) -> String? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        guard focusedWindowResult == .success,
              let focusedWindowValue,
              CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let windowElement = focusedWindowValue as! AXUIElement
        return stringAttribute(kAXTitleAttribute as CFString, from: windowElement)
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return normalizedTitle(value as? String)
    }

    private func visibleWindowTitle(forProcessIdentifier processIdentifier: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowInfoList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == processIdentifier,
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? NSNumber,
                  windowLayer.intValue == 0
            else {
                continue
            }

            if let title = normalizedTitle(windowInfo[kCGWindowName as String] as? String) {
                return title
            }
        }

        return nil
    }

    private func normalizedTitle(_ value: String?) -> String? {
        let title = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            ?? ""
        return title.isEmpty ? nil : title
    }
}

@MainActor
private final class SourceApplicationTracker {
    private var latestExternalApplication: CapturedSourceApplication?
    private var observer: NSObjectProtocol?
    private let windowTitleProvider = SourceWindowTitleProvider()

    func start() {
        updateLatestApplication(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                self?.updateLatestApplication(application)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    func currentSource() -> CapturedSourceApplication? {
        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier != Bundle.main.bundleIdentifier {
            updateLatestApplication(application)
        } else if let source = latestExternalApplication {
            let windowTitle = windowTitleProvider.title(forProcessIdentifier: source.processIdentifier)
                ?? source.windowTitle
            latestExternalApplication = source.updatingWindowTitle(windowTitle)
        }

        return latestExternalApplication
    }

    private func updateLatestApplication(_ application: NSRunningApplication?) {
        guard let application else { return }
        if application.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        let name = application.localizedName
            ?? application.bundleURL?.deletingPathExtension().lastPathComponent
            ?? "未知来源"

        latestExternalApplication = CapturedSourceApplication(
            processIdentifier: application.processIdentifier,
            bundleId: application.bundleIdentifier,
            name: name,
            bundlePath: application.bundleURL?.path,
            windowTitle: windowTitleProvider.title(for: application),
            icon: application.icon
        )
    }
}

@MainActor
private final class SourceAppIconProvider {
    private let appSupportURL: URL
    private let fileManager: FileManager

    init(appSupportURL: URL, fileManager: FileManager = .default) {
        self.appSupportURL = appSupportURL
        self.fileManager = fileManager
    }

    func cacheIcon(for source: CapturedSourceApplication?) -> String? {
        guard let source else { return nil }
        let icon = source.icon ?? source.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
        guard let icon, let data = icon.tiffRepresentation else { return nil }

        let directoryURL = appSupportURL.appendingPathComponent("app-icons", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let fileName = "\(safeCacheKey(for: source)).tiff"
            let fileURL = directoryURL.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            return "app-icons/\(fileName)"
        } catch {
            return nil
        }
    }

    private func safeCacheKey(for source: CapturedSourceApplication) -> String {
        let rawValue = source.bundleId ?? source.bundlePath ?? source.name
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = rawValue.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return value.isEmpty ? "unknown" : value
    }
}

@MainActor
private struct CapturedClipboardFiles {
    let urls: [URL]

    var paths: [String] {
        urls.map(\.path)
    }

    static func read(from pasteboard: NSPasteboard) -> CapturedClipboardFiles? {
        var urls: [URL] = []

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let objectURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] {
            urls.append(contentsOf: objectURLs)
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let fileURL = URL(string: fileURLString) {
            urls.append(fileURL)
        }

        if let filenames = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            urls.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
        }

        var seenPaths = Set<String>()
        let fileURLs = urls.compactMap(normalizedFileURL).filter { url in
            seenPaths.insert(url.path).inserted
        }

        return fileURLs.isEmpty ? nil : CapturedClipboardFiles(urls: fileURLs)
    }

    private static func normalizedFileURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        return URL(fileURLWithPath: url.path).standardizedFileURL
    }
}

private struct StoredClipboardFileSnapshot {
    let relativePath: String
    let byteCount: Int
}

private struct ClipboardFileSnapshotDocument: Codable {
    let paths: [String]
}

@MainActor
private final class ClipboardFileSnapshotProvider {
    private let appSupportURL: URL
    private let fileManager: FileManager

    init(appSupportURL: URL, fileManager: FileManager = .default) {
        self.appSupportURL = appSupportURL
        self.fileManager = fileManager
    }

    func cacheFiles(_ files: CapturedClipboardFiles, changeCount: Int) -> StoredClipboardFileSnapshot? {
        let directoryURL = appSupportURL
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("file-snapshots", isDirectory: true)
        let fileStem = "files-\(changeCount)-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
        let snapshotURL = directoryURL.appendingPathComponent("\(fileStem).json")
        let document = ClipboardFileSnapshotDocument(paths: files.paths)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(document)
            try data.write(to: snapshotURL, options: .atomic)
            return StoredClipboardFileSnapshot(
                relativePath: "assets/file-snapshots/\(fileStem).json",
                byteCount: data.count
            )
        } catch {
            return nil
        }
    }
}

private struct CapturedClipboardImage {
    let image: NSImage
    let pngData: Data
    let width: Int
    let height: Int

    static func read(from pasteboard: NSPasteboard) -> CapturedClipboardImage? {
        for type in [
            NSPasteboard.PasteboardType.png,
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType.tiff,
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic")
        ] {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data),
               let pngData = type == .png || type.rawValue == "public.png"
                ? data
                : image.pngRepresentation() {
                return make(image: image, pngData: pngData)
            }
        }

        let images = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        ) as? [NSImage]
        if let image = images?.first,
           let pngData = image.pngRepresentation() {
            return make(image: image, pngData: pngData)
        }

        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: nil
        ) as? [URL]
        for url in urls ?? [] where isImageFile(url) {
            if let image = NSImage(contentsOf: url),
               let pngData = image.pngRepresentation() {
                return make(image: image, pngData: pngData)
            }
        }

        return nil
    }

    private static func make(image: NSImage, pngData: Data) -> CapturedClipboardImage {
        let dimensions = image.pixelDimensions
        return CapturedClipboardImage(
            image: image,
            pngData: pngData,
            width: dimensions.width,
            height: dimensions.height
        )
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp", "gif"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
}

private struct StoredClipboardImageAsset {
    let payloadRelativePath: String
    let previewRelativePath: String
    let mimeType: String
    let width: Int
    let height: Int
    let byteCount: Int
}

@MainActor
private final class ClipboardImageAssetProvider {
    private let appSupportURL: URL
    private let fileManager: FileManager

    init(appSupportURL: URL, fileManager: FileManager = .default) {
        self.appSupportURL = appSupportURL
        self.fileManager = fileManager
    }

    func cacheImage(_ capturedImage: CapturedClipboardImage, changeCount: Int) -> StoredClipboardImageAsset? {
        let payloadDirectoryURL = appSupportURL.appendingPathComponent("assets", isDirectory: true)
        let thumbnailDirectoryURL = appSupportURL.appendingPathComponent("thumbnails", isDirectory: true)
        let fileStem = "image-\(changeCount)-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
        let payloadURL = payloadDirectoryURL.appendingPathComponent("\(fileStem).png")
        let thumbnailURL = thumbnailDirectoryURL.appendingPathComponent("\(fileStem).png")
        let thumbnailData = capturedImage.image.pngRepresentation(maxPixelDimension: 420)
            ?? capturedImage.pngData

        do {
            try fileManager.createDirectory(at: payloadDirectoryURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: thumbnailDirectoryURL, withIntermediateDirectories: true)
            try capturedImage.pngData.write(to: payloadURL, options: .atomic)
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
        } catch {
            return nil
        }

        return StoredClipboardImageAsset(
            payloadRelativePath: "assets/\(fileStem).png",
            previewRelativePath: "thumbnails/\(fileStem).png",
            mimeType: "image/png",
            width: capturedImage.width,
            height: capturedImage.height,
            byteCount: capturedImage.pngData.count
        )
    }
}

private extension NSImage {
    var pixelDimensions: (width: Int, height: Int) {
        if let bitmap = representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return (max(bitmap.pixelsWide, 1), max(bitmap.pixelsHigh, 1))
        }

        return (
            max(Int(size.width.rounded()), 1),
            max(Int(size.height.rounded()), 1)
        )
    }

    func pngRepresentation(maxPixelDimension: CGFloat? = nil) -> Data? {
        let sourceSize = size == .zero ? NSSize(width: 1, height: 1) : size
        let targetSize: NSSize

        if let maxPixelDimension {
            let scale = min(
                1,
                maxPixelDimension / max(sourceSize.width, sourceSize.height)
            )
            targetSize = NSSize(
                width: max(sourceSize.width * scale, 1),
                height: max(sourceSize.height * scale, 1)
            )
        } else {
            targetSize = sourceSize
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(Int(targetSize.width.rounded()), 1),
            pixelsHigh: max(Int(targetSize.height.rounded()), 1),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
private final class ClipboardMonitor {
    static let selfWriteTokenPasteboardType = NSPasteboard.PasteboardType("com.clipboardworkbench.self-write-token")

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var ignoredChangeCounts = Set<Int>()
    private var ignoredSelfWriteTokens = Set<String>()
    var onTextCaptured: ((String, Int) -> Void)?
    var onImageCaptured: ((CapturedClipboardImage, Int) -> Void)?
    var onFilesCaptured: ((CapturedClipboardFiles, Int) -> Void)?

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markSelfWrite(token: String, from startChangeCount: Int, through endChangeCount: Int) {
        let lowerBound = min(startChangeCount, endChangeCount)
        let upperBound = max(startChangeCount, endChangeCount)
        for changeCount in lowerBound...upperBound {
            ignoredChangeCounts.insert(changeCount)
        }
        ignoredSelfWriteTokens.insert(token)
        trimIgnoredMarkers()
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if shouldIgnoreSelfWrite(pasteboard: pasteboard, changeCount: changeCount) {
            return
        }

        if let files = CapturedClipboardFiles.read(from: pasteboard) {
            onFilesCaptured?(files, changeCount)
            return
        }

        if let image = CapturedClipboardImage.read(from: pasteboard) {
            onImageCaptured?(image, changeCount)
            return
        }

        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return
        }

        onTextCaptured?(text, changeCount)
    }

    private func shouldIgnoreSelfWrite(pasteboard: NSPasteboard, changeCount: Int) -> Bool {
        let token = pasteboard.string(forType: Self.selfWriteTokenPasteboardType)
        if ignoredChangeCounts.remove(changeCount) != nil {
            if let token {
                ignoredSelfWriteTokens.remove(token)
            }
            return true
        }

        if let token, ignoredSelfWriteTokens.remove(token) != nil {
            return true
        }

        return false
    }

    private func trimIgnoredMarkers() {
        let maximumMarkerCount = 32
        if ignoredChangeCounts.count > maximumMarkerCount {
            ignoredChangeCounts = Set(ignoredChangeCounts.sorted().suffix(maximumMarkerCount))
        }

        if ignoredSelfWriteTokens.count > maximumMarkerCount {
            ignoredSelfWriteTokens.removeAll()
        }
    }
}

private enum ClipboardItemMutationRequest: Sendable {
    case setPinned(itemID: String, isPinned: Bool)
    case delete(itemID: String)
    case clear(itemType: String?, sourceAppID: String?, normalizedSearch: String)
}

private actor ClipboardDatabaseWorker {
    func listItems(
        client: RustCoreClient,
        appSupportURL: URL,
        itemType: String?,
        sourceAppID: String?,
        normalizedSearch: String
    ) -> Result<RustCoreListResult, RustCoreError> {
        client.listItems(
            appSupportDirectory: appSupportURL,
            limit: 50,
            offset: 0,
            itemType: itemType,
            sourceAppId: sourceAppID,
            searchText: normalizedSearch.isEmpty ? nil : normalizedSearch
        )
    }

    func performMutation(
        client: RustCoreClient,
        appSupportURL: URL,
        mutation: ClipboardItemMutationRequest
    ) -> Result<RustItemManagementResult, RustCoreError> {
        switch mutation {
        case .setPinned(let itemID, let isPinned):
            client.setItemPinned(
                appSupportDirectory: appSupportURL,
                itemId: itemID,
                isPinned: isPinned
            )

        case .delete(let itemID):
            client.deleteItem(appSupportDirectory: appSupportURL, itemId: itemID)

        case .clear(let itemType, let sourceAppID, let normalizedSearch):
            client.clearItems(
                appSupportDirectory: appSupportURL,
                itemType: itemType,
                sourceAppId: sourceAppID,
                searchText: normalizedSearch.isEmpty ? nil : normalizedSearch
            )
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum PasteWriteResult {
        case success(changeCount: Int)
        case failure(message: String)
    }

    private let panelController = FloatingPanelController()
    private let preferencesController = PreferencesWindowController()
    private let rustCoreClient = RustCoreClient()
    private let launchAtLoginController = LaunchAtLoginController()
    private let accessibilityPermissionController = AccessibilityPermissionController()
    private let sourceApplicationTracker = SourceApplicationTracker()
    private let clipboardMonitor = ClipboardMonitor()
    private let databaseWorker = ClipboardDatabaseWorker()
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyAvailable = false
    private var storageStatusText = "存储：未初始化"
    private var appSupportURL: URL?
    private var iconProvider: SourceAppIconProvider?
    private var imageAssetProvider: ClipboardImageAssetProvider?
    private var fileSnapshotProvider: ClipboardFileSnapshotProvider?
    private var currentSearchText = ""
    private var currentItemType: String?
    private var currentSourceAppID: String?
    private var currentPreferences = RustPreferencesDocument()
    private var listRefreshGeneration = 0
    private var pendingListRefreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        configureStatusItem()
        configurePanelCallbacks()
        configureClipboardCapture()
        sourceApplicationTracker.start()
        bootstrapLocalStorage()
        clipboardMonitor.start()
        registerGlobalHotKey()
        refreshStatusText()

        panelController.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        sourceApplicationTracker.stop()
        unregisterGlobalHotKey()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAccessibilityPermissionState()
    }

    @objc private func togglePanel(_ sender: Any?) {
        panelController.toggle()
    }

    @objc private func showPanel(_ sender: Any?) {
        panelController.show()
    }

    @objc private func hidePanel(_ sender: Any?) {
        panelController.hide()
    }

    @objc private func repositionPanel(_ sender: Any?) {
        panelController.positionOverDock()
        panelController.show()
    }

    @objc private func cyclePanelLevel(_ sender: Any?) {
        panelController.cycleLevel()
        refreshStatusText()
    }

    @objc func showPreferences(_ sender: Any?) {
        refreshAccessibilityPermissionState()
        preferencesController.showPreferences()
    }

    private func configurePanelCallbacks() {
        panelController.onRequestHide = { [weak self] in self?.hidePanel(nil) }
        panelController.onQueryChanged = { [weak self] searchText, itemType, sourceAppID in
            self?.updateQuery(searchText: searchText, itemType: itemType, sourceAppID: sourceAppID)
        }
        panelController.onCopyRequested = { [weak self] item in
            self?.copySelectedItemToPasteboard(item)
        }
        panelController.onPinRequested = { [weak self] item, isPinned in
            self?.setItemPinned(item, isPinned: isPinned)
        }
        panelController.onDeleteRequested = { [weak self] item in
            self?.deleteItem(item)
        }
        panelController.onClearRequested = { [weak self] searchText, itemType, sourceAppID in
            self?.clearItems(searchText: searchText, itemType: itemType, sourceAppID: sourceAppID)
        }
        preferencesController.onPreferencesChanged = { [weak self] preferences in
            self?.persistPreferences(preferences)
        }
        preferencesController.onAccessibilityPermissionRequested = { [weak self] in
            self?.openAccessibilitySettingsFromPreferences()
        }
    }

    private func setItemPinned(_ item: RustClipboardItemSummary, isPinned: Bool) {
        guard let appSupportURL else {
            storageStatusText = "条目：存储未初始化"
            refreshStatusText()
            return
        }

        performItemMutation(
            appSupportURL: appSupportURL,
            mutation: .setPinned(itemID: item.id, isPinned: isPinned)
        )
    }

    private func deleteItem(_ item: RustClipboardItemSummary) {
        guard let appSupportURL else {
            storageStatusText = "条目：存储未初始化"
            refreshStatusText()
            return
        }

        performItemMutation(appSupportURL: appSupportURL, mutation: .delete(itemID: item.id))
    }

    private func clearItems(searchText: String, itemType: String?, sourceAppID: String?) {
        guard let appSupportURL else {
            storageStatusText = "条目：存储未初始化"
            refreshStatusText()
            return
        }

        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        performItemMutation(
            appSupportURL: appSupportURL,
            mutation: .clear(
                itemType: itemType,
                sourceAppID: sourceAppID,
                normalizedSearch: normalizedSearch
            )
        )
    }

    private func performItemMutation(
        appSupportURL: URL,
        mutation: ClipboardItemMutationRequest
    ) {
        let client = rustCoreClient
        let databaseWorker = databaseWorker
        cancelPendingListRefreshForMutation()

        Task { [weak self, client, appSupportURL, databaseWorker, mutation] in
            let result = await databaseWorker.performMutation(
                client: client,
                appSupportURL: appSupportURL,
                mutation: mutation
            )
            guard let self else { return }

            switch result {
            case .success(let mutationResult):
                let mutationStatusText = self.statusText(for: mutation, result: mutationResult)
                self.refreshClipboardList()
                self.storageStatusText = mutationStatusText
                self.refreshStatusText()

            case .failure(let error):
                self.storageStatusText = "条目：\(error.code)"
                self.refreshStatusText()
            }
        }
    }

    private func cancelPendingListRefreshForMutation() {
        listRefreshGeneration += 1
        pendingListRefreshTask?.cancel()
        pendingListRefreshTask = nil
    }

    private func statusText(
        for mutation: ClipboardItemMutationRequest,
        result: RustItemManagementResult
    ) -> String {
        switch mutation {
        case .setPinned(_, let isPinned):
            return result.affectedCount > 0
                ? (isPinned ? "条目：已固定" : "条目：已取消固定")
                : "条目：未找到"

        case .delete:
            return result.affectedCount > 0 ? "条目：已删除" : "条目：未找到"

        case .clear:
            return result.affectedCount > 0
                ? "条目：已清理 \(result.affectedCount) 条"
                : "条目：没有可清理条目"
        }
    }

    private func copySelectedItemToPasteboard(_ item: RustClipboardItemSummary) {
        guard let appSupportURL else {
            storageStatusText = "复制：存储未初始化"
            refreshStatusText()
            return
        }

        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: appSupportURL
        )
        let token = "self-\(UUID().uuidString)"
        let startChangeCount = NSPasteboard.general.changeCount + 1

        switch writePastePayload(payload, token: token) {
        case .success(let changeCount):
            clipboardMonitor.markSelfWrite(
                token: token,
                from: startChangeCount,
                through: changeCount
            )
            storageStatusText = "复制：已写入剪贴板"
            refreshStatusText()
            panelController.hide()

        case .failure(let message):
            storageStatusText = "复制：\(message)"
            refreshStatusText()
        }
    }

    private func writePastePayload(_ payload: ClipboardPastePayload, token: String) -> PasteWriteResult {
        let pasteboard = NSPasteboard.general

        let didWrite: Bool
        switch payload {
        case .text(let text):
            pasteboard.clearContents()
            didWrite = pasteboard.setString(text, forType: .string)

        case .imageFile(let url):
            guard let image = NSImage(contentsOf: url) else {
                return .failure(message: "图片文件无法读取")
            }

            let pngData = image.pngRepresentation() ?? (try? Data(contentsOf: url))
            let tiffData = image.tiffRepresentation
            guard pngData != nil || tiffData != nil else {
                return .failure(message: "图片数据无法写入")
            }

            pasteboard.clearContents()
            var wroteImage = false
            if let pngData {
                wroteImage = pasteboard.setData(pngData, forType: .png) || wroteImage
                wroteImage = pasteboard.setData(
                    pngData,
                    forType: NSPasteboard.PasteboardType("public.png")
                ) || wroteImage
            }

            if let tiffData {
                wroteImage = pasteboard.setData(tiffData, forType: .tiff) || wroteImage
            }
            didWrite = wroteImage

        case .fileURLs(let urls):
            guard !urls.isEmpty else {
                return .failure(message: "文件路径为空")
            }

            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects(urls as [NSURL])
            if didWrite {
                _ = pasteboard.setPropertyList(
                    urls.map(\.path),
                    forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
                )
            }

        case .unsupported(let reason):
            return .failure(message: pasteUnsupportedReasonText(reason))
        }

        guard didWrite else {
            return .failure(message: "系统剪贴板写入失败")
        }

        _ = pasteboard.setString(token, forType: ClipboardMonitor.selfWriteTokenPasteboardType)
        return .success(changeCount: pasteboard.changeCount)
    }

    private func pasteUnsupportedReasonText(_ reason: String) -> String {
        switch reason {
        case "empty_text":
            return "文本内容为空"
        case "missing_image_asset":
            return "图片资产不存在"
        case "missing_file_url":
            return "文件路径不存在"
        case "unsupported_type":
            return "当前类型暂不支持"
        default:
            return "当前条目暂不支持"
        }
    }

    private func bootstrapLocalStorage() {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first?
        .appendingPathComponent("ClipboardWorkbench", isDirectory: true)

        guard let appSupportURL else {
            storageStatusText = "存储：无法定位 Application Support"
            return
        }
        self.appSupportURL = appSupportURL
        iconProvider = SourceAppIconProvider(appSupportURL: appSupportURL)
        imageAssetProvider = ClipboardImageAssetProvider(appSupportURL: appSupportURL)
        fileSnapshotProvider = ClipboardFileSnapshotProvider(appSupportURL: appSupportURL)
        panelController.setAppSupportDirectory(appSupportURL)

        switch rustCoreClient.open(appSupportDirectory: appSupportURL) {
        case .success(let result):
            storageStatusText = "存储：已连接（\(result.itemCount) 条）"
            loadPreferences()
            let maintenanceResult = runLocalMaintenance()
            refreshSourceApps()
            if currentSearchText.isEmpty, currentItemType == nil, currentSourceAppID == nil {
                panelController.updateStorageState(.success(result))
            } else {
                refreshClipboardList()
            }
            if let maintenanceResult, hasMaintenanceChanges(maintenanceResult) {
                storageStatusText = maintenanceStatusText(maintenanceResult)
                refreshStatusText()
            }
        case .failure(let error):
            storageStatusText = "存储：\(error.code)"
            panelController.updateStorageState(.failure(error))
        }
    }

    private func runLocalMaintenance() -> RustMaintenanceResult? {
        guard let appSupportURL else { return nil }

        switch rustCoreClient.runMaintenance(appSupportDirectory: appSupportURL) {
        case .success(let result):
            return result
        case .failure(let error):
            storageStatusText = "维护：\(error.code)"
            refreshStatusText()
            return nil
        }
    }

    private func hasMaintenanceChanges(_ result: RustMaintenanceResult) -> Bool {
        MaintenanceStatusPresenter.hasChanges(result)
    }

    private func maintenanceStatusText(_ result: RustMaintenanceResult) -> String {
        MaintenanceStatusPresenter.statusText(result)
    }

    private func loadPreferences() {
        guard let appSupportURL else { return }

        switch rustCoreClient.getPreferences(appSupportDirectory: appSupportURL) {
        case .success(let result):
            let reconciliation = reconcileLaunchAtLoginPreference(
                result.preferences,
                applyRequestedChange: false
            )
            if reconciliation.preferences != result.preferences {
                _ = rustCoreClient.updatePreferences(
                    appSupportDirectory: appSupportURL,
                    preferences: reconciliation.preferences
                )
            }

            applyPreferences(reconciliation.preferences)
            preferencesController.updatePreferences(reconciliation.preferences)
            if let statusText = reconciliation.statusText {
                storageStatusText = statusText
                refreshStatusText()
            }
        case .failure(let error):
            storageStatusText = "偏好：\(error.code)"
        }
    }

    private func persistPreferences(_ preferences: RustPreferencesDocument) -> RustPreferencesDocument? {
        guard let appSupportURL else {
            storageStatusText = "偏好：存储未初始化"
            refreshStatusText()
            return nil
        }

        let launchAtLoginChanged = preferences.general.launchAtLogin != currentPreferences.general.launchAtLogin
        let reconciliation = reconcileLaunchAtLoginPreference(
            preferences,
            applyRequestedChange: launchAtLoginChanged
        )

        switch rustCoreClient.updatePreferences(
            appSupportDirectory: appSupportURL,
            preferences: reconciliation.preferences
        ) {
        case .success(let result):
            applyPreferences(result.preferences)
            refreshClipboardList()
            storageStatusText = reconciliation.statusText ?? "偏好：已保存"
            refreshStatusText()
            return result.preferences
        case .failure(let error):
            storageStatusText = "偏好：\(error.code)"
            refreshStatusText()
            return nil
        }
    }

    private func applyPreferences(_ preferences: RustPreferencesDocument) {
        currentPreferences = preferences
        panelController.setPreferredHeight(CGFloat(preferences.general.defaultPanelHeight))
        panelController.setPreviewPopoverEnabled(preferences.appearance.previewPopoverEnabled)
        statusItem?.isVisible = preferences.general.showMenuBarItem
        preferencesController.updateLaunchAtLoginState(launchAtLoginController.currentState())
        refreshAccessibilityPermissionState()
        refreshStatusText()
    }

    private func refreshAccessibilityPermissionState() {
        preferencesController.updateAccessibilityPermissionState(
            accessibilityPermissionController.currentState()
        )
    }

    private func openAccessibilitySettingsFromPreferences() {
        let state = accessibilityPermissionController.currentState()
        if !state.isTrusted {
            accessibilityPermissionController.openAccessibilitySettings()
            storageStatusText = "权限：已打开辅助功能设置"
        } else {
            storageStatusText = "权限：辅助功能已允许"
        }
        refreshAccessibilityPermissionState()
        refreshStatusText()
    }

    private func reconcileLaunchAtLoginPreference(
        _ preferences: RustPreferencesDocument,
        applyRequestedChange: Bool
    ) -> (preferences: RustPreferencesDocument, statusText: String?) {
        var resolvedPreferences = preferences
        let currentState = launchAtLoginController.currentState()

        guard applyRequestedChange else {
            resolvedPreferences.general.launchAtLogin = currentState.isOn
            preferencesController.updateLaunchAtLoginState(currentState)
            if preferences.general.launchAtLogin != currentState.isOn {
                return (resolvedPreferences, "登录项：\(currentState.detail)")
            }
            return (resolvedPreferences, nil)
        }

        guard currentState.canChange else {
            resolvedPreferences.general.launchAtLogin = currentState.isOn
            preferencesController.updateLaunchAtLoginState(currentState)
            return (resolvedPreferences, "登录项：\(currentState.detail)")
        }

        switch launchAtLoginController.setEnabled(preferences.general.launchAtLogin) {
        case .success(let state):
            resolvedPreferences.general.launchAtLogin = state.isOn
            preferencesController.updateLaunchAtLoginState(state)
            return (resolvedPreferences, "登录项：\(state.detail)")

        case .failure(let error):
            let fallbackState = launchAtLoginController.currentState()
            resolvedPreferences.general.launchAtLogin = fallbackState.isOn
            preferencesController.updateLaunchAtLoginState(fallbackState)
            return (resolvedPreferences, "登录项：\(error.localizedDescription)")
        }
    }

    private func updateQuery(searchText: String, itemType: String?, sourceAppID: String?) {
        currentSearchText = searchText
        currentItemType = itemType
        currentSourceAppID = sourceAppID
        refreshClipboardList(debounce: true)
    }

    private func refreshClipboardList(debounce: Bool = false) {
        guard let appSupportURL else { return }

        let normalizedSearch = currentSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemType = currentItemType
        let sourceAppID = currentSourceAppID
        let isFiltered = itemType != nil || sourceAppID != nil || !normalizedSearch.isEmpty
        let client = rustCoreClient
        let databaseWorker = databaseWorker

        listRefreshGeneration += 1
        let generation = listRefreshGeneration
        pendingListRefreshTask?.cancel()

        let task = Task { [weak self, client, appSupportURL, databaseWorker, itemType, sourceAppID, normalizedSearch, isFiltered, generation] in
            if debounce {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
            }

            let result = await databaseWorker.listItems(
                client: client,
                appSupportURL: appSupportURL,
                itemType: itemType,
                sourceAppID: sourceAppID,
                normalizedSearch: normalizedSearch
            )

            guard !Task.isCancelled else { return }
            guard let self, generation == self.listRefreshGeneration else { return }
            self.applyClipboardListResult(result, isFiltered: isFiltered)
        }

        pendingListRefreshTask = task
    }

    private func applyClipboardListResult(
        _ result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool
    ) {
        switch result {
        case .success(let list):
            storageStatusText = "存储：已连接（\(list.totalCount) 条）"
            panelController.updateListState(.success(list), isFiltered: isFiltered)
        case .failure(let error):
            storageStatusText = "查询：\(error.code)"
            panelController.updateListState(.failure(error), isFiltered: false)
        }

        refreshStatusText()
    }

    private func refreshSourceApps() {
        // 主面板当前不展示来源筛选入口；避免每次列表刷新额外做一次来源分组查询。
    }

    private func configureClipboardCapture() {
        clipboardMonitor.onTextCaptured = { [weak self] text, changeCount in
            self?.captureClipboardText(text, changeCount: changeCount)
        }
        clipboardMonitor.onImageCaptured = { [weak self] image, changeCount in
            self?.captureClipboardImage(image, changeCount: changeCount)
        }
        clipboardMonitor.onFilesCaptured = { [weak self] files, changeCount in
            self?.captureClipboardFiles(files, changeCount: changeCount)
        }
    }

    private func shouldSkipCapture(from source: CapturedSourceApplication?) -> Bool {
        let ruleSource = source.map {
            ClipboardIgnoreRuleSource(
                bundleId: $0.bundleId,
                appName: $0.name,
                bundlePath: $0.bundlePath
            )
        }
        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: ruleSource,
            windowTitle: source?.windowTitle,
            preferences: currentPreferences.ignoreList
        )

        guard decision.shouldSkip else {
            return false
        }

        storageStatusText = captureSkipStatusText(for: decision)
        refreshStatusText()
        return true
    }

    private func captureSkipStatusText(for decision: ClipboardIgnoreRuleDecision) -> String {
        switch decision.reason {
        case .unknownSource:
            return "捕获：已跳过未知来源"
        case .sourceApplication:
            if let matchedRule = decision.matchedRule, !matchedRule.isEmpty {
                return "捕获：已忽略 \(matchedRule)"
            }
            return "捕获：已按应用规则跳过"
        case .windowTitle:
            if let matchedRule = decision.matchedRule, !matchedRule.isEmpty {
                return "捕获：标题命中 \(matchedRule)"
            }
            return "捕获：已按标题规则跳过"
        case nil:
            return "捕获：已按忽略规则跳过"
        }
    }

    private func captureClipboardText(_ text: String, changeCount: Int) {
        guard let appSupportURL else { return }

        let source = sourceApplicationTracker.currentSource()
        guard !shouldSkipCapture(from: source) else {
            return
        }

        let iconRelativePath = iconProvider?.cacheIcon(for: source)
        let request = RustCaptureTextRequest(
            text: text,
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.name,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: iconRelativePath,
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch rustCoreClient.captureText(appSupportDirectory: appSupportURL, request: request) {
        case .success:
            refreshClipboardList()
        case .failure(let error):
            storageStatusText = "捕获：\(error.code)"
            panelController.updateStorageState(.failure(error))
        }

        refreshStatusText()
    }

    private func captureClipboardImage(_ image: CapturedClipboardImage, changeCount: Int) {
        guard currentPreferences.history.recordImages else {
            storageStatusText = "捕获：图片记录已关闭"
            refreshStatusText()
            return
        }

        guard let appSupportURL else {
            storageStatusText = "捕获：图片资产写入失败"
            refreshStatusText()
            return
        }

        let source = sourceApplicationTracker.currentSource()
        guard !shouldSkipCapture(from: source) else {
            return
        }

        guard let storedImage = imageAssetProvider?.cacheImage(image, changeCount: changeCount) else {
            storageStatusText = "捕获：图片资产写入失败"
            refreshStatusText()
            return
        }

        let iconRelativePath = iconProvider?.cacheIcon(for: source)
        let request = RustCaptureImageRequest(
            payloadRelativePath: storedImage.payloadRelativePath,
            previewRelativePath: storedImage.previewRelativePath,
            mimeType: storedImage.mimeType,
            width: Int64(storedImage.width),
            height: Int64(storedImage.height),
            byteCount: Int64(storedImage.byteCount),
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.name,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: iconRelativePath,
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch rustCoreClient.captureImage(appSupportDirectory: appSupportURL, request: request) {
        case .success:
            refreshClipboardList()
        case .failure(let error):
            storageStatusText = "捕获：\(error.code)"
            panelController.updateStorageState(.failure(error))
        }

        refreshStatusText()
    }

    private func captureClipboardFiles(_ files: CapturedClipboardFiles, changeCount: Int) {
        guard currentPreferences.history.recordFiles else {
            storageStatusText = "捕获：文件记录已关闭"
            refreshStatusText()
            return
        }

        guard let appSupportURL else {
            storageStatusText = "捕获：文件快照写入失败"
            refreshStatusText()
            return
        }

        let source = sourceApplicationTracker.currentSource()
        guard !shouldSkipCapture(from: source) else {
            return
        }

        guard let snapshot = fileSnapshotProvider?.cacheFiles(files, changeCount: changeCount) else {
            storageStatusText = "捕获：文件快照写入失败"
            refreshStatusText()
            return
        }

        let iconRelativePath = iconProvider?.cacheIcon(for: source)
        let request = RustCaptureFilesRequest(
            filePaths: files.paths,
            snapshotRelativePath: snapshot.relativePath,
            snapshotByteCount: Int64(snapshot.byteCount),
            sourceBundleId: source?.bundleId,
            sourceAppName: source?.name,
            sourceBundlePath: source?.bundlePath,
            sourceIconRelativePath: iconRelativePath,
            sourceConfidence: source == nil ? "unknown" : "high",
            pasteboardChangeCount: Int64(changeCount)
        )

        switch rustCoreClient.captureFiles(appSupportDirectory: appSupportURL, request: request) {
        case .success:
            refreshClipboardList()
        case .failure(let error):
            storageStatusText = "捕获：\(error.code)"
            panelController.updateStorageState(.failure(error))
        }

        refreshStatusText()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "剪贴板工作台")

        appMenu.addItem(makeMenuItem(title: "显示/隐藏面板", action: #selector(togglePanel(_:)), key: "v", modifiers: [.command, .shift]))
        appMenu.addItem(makeMenuItem(title: "偏好设置…", action: #selector(showPreferences(_:)), key: ",", modifiers: [.command]))
        appMenu.addItem(makeMenuItem(title: "切换窗口层级", action: #selector(cyclePanelLevel(_:)), key: "l", modifiers: [.command, .shift]))
        appMenu.addItem(.separator())
        appMenu.addItem(makeMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), key: "q", modifiers: [.command]))

        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "剪贴板工作台")
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.title = ""

        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "显示面板", action: #selector(showPanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: "隐藏面板", action: #selector(hidePanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: "回到 Dock 区域", action: #selector(repositionPanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: "切换窗口层级", action: #selector(cyclePanelLevel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: "偏好设置…", action: #selector(showPreferences(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), key: "", modifiers: []))
        statusItem?.menu = menu
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }

                MainActor.assumeIsolated {
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    delegate.togglePanel(nil)
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            hotKeyAvailable = false
            return
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("PSTD"), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey) | UInt32(shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        hotKeyAvailable = hotKeyStatus == noErr
    }

    private func unregisterGlobalHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func refreshStatusText() {
        panelController.updateStatus(dockIconVisible: false, hotKeyAvailable: hotKeyAvailable)
        statusItem?.button?.toolTip = "层级：\(panelController.levelMode.title)\n\(storageStatusText)"
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { result, character in
        (result << 8) + OSType(character)
    }
}

private enum PanelSnapshotCommand {
    private static let flag = "--render-panel-snapshot"

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
    static func render(to outputURL: URL) throws {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 320)
        let view = FloatingPanelContentView(frame: frame)
        let previewURL = try makePreviewImageURL(outputDirectory: outputURL.deletingLastPathComponent())
        let sampleItems = makeSampleItems(imagePath: previewURL.path)
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
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()

        let bitmap = try bitmapImage(for: view)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)
    }

    @MainActor
    private static func bitmapImage(for view: NSView) throws -> NSBitmapImageRep {
        let width = Int(view.bounds.width.rounded())
        let height = Int(view.bounds.height.rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        view.displayIgnoringOpacity(view.bounds, in: graphicsContext)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    @MainActor
    private static func makePreviewImageURL(outputDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 420, height: 260))
        image.lockFocus()
        NSColor.systemTeal.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 420, height: 260), xRadius: 18, yRadius: 18).fill()
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: 270, y: 120, width: 92, height: 92)).fill()
        NSBezierPath(roundedRect: NSRect(x: 44, y: 54, width: 190, height: 26), xRadius: 13, yRadius: 13).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = outputDirectory.appendingPathComponent("panel-runtime-sample-image.png")
        try pngData.write(to: url, options: .atomic)
        return url
    }

    private static func makeSampleItems(imagePath: String) -> [RustClipboardItemSummary] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return [
            makeItem(
                id: "snapshot-text",
                itemType: "text",
                summary: "多行文本内容会在真实卡片中换行展示，避免只剩一行。",
                primaryText: "多行文本内容会在真实卡片中换行展示，避免只剩一行。",
                sourceAppName: "备忘录",
                timestamp: now,
                sizeBytes: 68
            ),
            makeItem(
                id: "snapshot-image",
                itemType: "image",
                summary: "图片 420 x 260",
                primaryText: nil,
                sourceAppName: "预览",
                timestamp: now - 120_000,
                previewAssetPath: imagePath,
                payloadAssetPath: imagePath,
                sizeBytes: 184_000
            ),
            makeItem(
                id: "snapshot-file",
                itemType: "file",
                summary: "report.pdf",
                primaryText: "/Users/evan/Downloads/report.pdf",
                sourceAppName: "Finder",
                timestamp: now - 240_000,
                sizeBytes: 2048
            ),
            makeItem(
                id: "snapshot-link",
                itemType: "link",
                summary: "example.com",
                primaryText: "https://example.com/docs/production-ui?from=clipboard",
                sourceAppName: "Safari",
                timestamp: now - 360_000,
                sizeBytes: 56
            ),
            makeItem(
                id: "snapshot-terminal",
                itemType: "text",
                summary: "git push --set-upstream origin main",
                primaryText: "git push --set-upstream origin main",
                sourceAppName: "终端",
                timestamp: now - 1_620_000,
                sizeBytes: 35
            ),
            makeItem(
                id: "snapshot-hash",
                itemType: "text",
                summary: "f7543c5e99",
                primaryText: "f7543c5e99",
                sourceAppName: "Xcode",
                timestamp: now - 50_400_000,
                sizeBytes: 10
            )
        ]
    }

    private static func makeItem(
        id: String,
        itemType: String,
        summary: String,
        primaryText: String?,
        sourceAppName: String,
        timestamp: Int64,
        previewAssetPath: String? = nil,
        payloadAssetPath: String? = nil,
        sizeBytes: Int64
    ) -> RustClipboardItemSummary {
        RustClipboardItemSummary(
            id: id,
            itemType: itemType,
            summary: summary,
            primaryText: primaryText,
            contentHash: "snapshot-\(id)",
            sourceAppId: nil,
            sourceAppName: sourceAppName,
            sourceAppIconPath: nil,
            previewAssetPath: previewAssetPath,
            payloadAssetPath: payloadAssetPath,
            sourceConfidence: "high",
            firstCopiedAtMs: timestamp,
            lastCopiedAtMs: timestamp,
            copyCount: 1,
            isPinned: false,
            sizeBytes: sizeBytes,
            previewState: "ready"
        )
    }
}

private enum PreferencesSnapshotCommand {
    private static let flag = "--render-preferences-snapshot"

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
    static func render(to outputURL: URL) throws {
        let controller = PreferencesWindowController()
        var preferences = RustPreferencesDocument()
        preferences.general.launchAtLogin = true
        preferences.general.defaultPanelHeight = 360
        preferences.history.recordFiles = true
        preferences.ignoreList.ignoredAppIdentifiers = [
            "com.apple.Terminal",
            "Xcode"
        ]
        preferences.ignoreList.windowTitleKeywords = [
            "验证码",
            "Private"
        ]
        preferences.appearance.itemDensity = "standard"

        controller.updatePreferences(preferences)
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

        let bitmap = try bitmapImage(for: rootView)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)
    }

    @MainActor
    private static func bitmapImage(for view: NSView) throws -> NSBitmapImageRep {
        let width = Int(view.bounds.width.rounded())
        let height = Int(view.bounds.height.rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        view.displayIgnoringOpacity(view.bounds, in: graphicsContext)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}

private enum PreferencesSmokeCommand {
    private static let flag = "--exercise-preferences"
    private static let sidebarTitles = Set(PreferenceSection.allCases.map(\.title))

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

        guard let rootView = controller.window?.contentView else { return }
        _ = exerciseCurrentPage(in: rootView)

        for title in PreferenceSection.allCases.map(\.title) {
            guard let button = navigationButton(titled: title, in: rootView) else { continue }
            if let button = button as? PreferenceNavigationButton {
                button.triggerPress()
            } else {
                button.performClick(nil)
            }
            drainMainRunLoop()
            _ = exerciseCurrentPage(in: rootView)
        }
    }

    @MainActor
    private static func exerciseCurrentPage(in rootView: NSView) -> Bool {
        for control in allSubviews(of: rootView) {
            if let button = control as? PreferenceCheckboxButton {
                button.triggerForSmoke()
                drainMainRunLoop()
                return true
            }

            if let control = control as? PreferenceSwitch, control.isEnabled {
                control.triggerForSmoke()
                drainMainRunLoop()
                return true
            }

            if let control = control as? PreferenceSegmentedControl, control.segmentCount > 0 {
                control.triggerForSmoke()
                drainMainRunLoop()
                return true
            }

            if let stepper = control as? PreferenceStepper {
                stepper.triggerForSmoke()
                drainMainRunLoop()
                return true
            }
        }

        return false
    }

    @MainActor
    private static func navigationButton(titled title: String, in rootView: NSView) -> NSButton? {
        allSubviews(of: rootView)
            .compactMap { $0 as? NSButton }
            .first { $0.title == title }
    }

    @MainActor
    private static func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(of:))
    }

    @MainActor
    private static func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

private enum PanelInteractionSmokeCommand {
    private static let flag = "--exercise-panel-interactions"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    @MainActor
    static func run() throws {
        _ = NSApplication.shared

        let appSupportURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("panel-interaction-smoke", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let imageURL = try makeSmokeImageURL(outputDirectory: appSupportURL)
        let controller = FloatingPanelController()
        let sampleItems = makeSampleItems(imagePath: imageURL.path)
        var queries: [(searchText: String, itemType: String?, sourceAppID: String?)] = []
        var copiedItemID: String?
        var pinRequest: (itemID: String, isPinned: Bool)?
        var deletedItemID: String?
        var clearRequest: (searchText: String, itemType: String?, sourceAppID: String?)?
        var hideCount = 0

        controller.onQueryChanged = { searchText, itemType, sourceAppID in
            queries.append((searchText, itemType, sourceAppID))
        }
        controller.onCopyRequested = { item in
            copiedItemID = item.id
            controller.hide()
        }
        controller.onPinRequested = { item, isPinned in
            pinRequest = (item.id, isPinned)
        }
        controller.onDeleteRequested = { item in
            deletedItemID = item.id
        }
        controller.onClearRequested = { searchText, itemType, sourceAppID in
            clearRequest = (searchText, itemType, sourceAppID)
        }
        controller.onRequestHide = {
            hideCount += 1
            controller.hide()
        }

        controller.setAppSupportDirectory(appSupportURL)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: sampleItems,
                totalCount: Int64(sampleItems.count),
                hasMore: false
            )),
            isFiltered: false
        )
        drainMainRunLoop()

        let contentView = controller.smokeContentView
        contentView.layoutSubtreeIfNeeded()

        let cards = contentView.smokeCardBoxes()
        try require(cards.count >= 5, "真实面板未渲染足够的条目卡片")
        try require(contentView.smokeSelectedItemID == "panel-smoke-text", "初始选中项不正确")

        sendMouseDown(to: cards[1], clickCount: 1)
        drainMainRunLoop()
        try require(contentView.smokeSelectedItemID == "panel-smoke-image", "单击条目未立即选中")

        sendSpace(to: contentView)
        drainMainRunLoop()
        try require(contentView.smokeIsPreviewShown, "Space 未打开当前选中条目的预览")
        try require(contentView.smokeClosePreviewWithSpaceFromPopoverFocus(), "预览焦点下的 Space 未被预览控制器接管")
        drainMainRunLoop()
        try require(!contentView.smokeIsPreviewShown, "预览显示后再次 Space 未关闭预览")

        try require(contentView.smokeCommandHintTexts().isEmpty, "Command 提示默认应隐藏")
        sendCommandModifier(down: true, to: contentView)
        drainMainRunLoop()
        try require(
            Array(contentView.smokeCommandHintTexts().prefix(3)) == ["1", "2", "3"],
            "Command 按下后未按完整可见条目从 1 开始编号"
        )
        sendCommandModifier(down: false, to: contentView)
        drainMainRunLoop()
        try require(contentView.smokeCommandHintTexts().isEmpty, "Command 松开后提示应隐藏")

        if let imageChip = contentView.smokeTypeFilterButton(itemType: "image") {
            sendMouseDown(to: imageChip, clickCount: 1)
            drainMainRunLoop()
        }
        try require(queries.last?.itemType == "image", "类型 chip 未触发 image 筛选")

        contentView.smokeSearchField.stringValue = "report"
        contentView.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: contentView.smokeSearchField
        ))
        drainMainRunLoop()
        try require(queries.last?.searchText == "report", "搜索输入未触发查询回调")

        if let scrollView = contentView.smokeHorizontalScrollView(),
           let documentView = scrollView.documentView,
           documentView.frame.width > scrollView.contentView.bounds.width + 1 {
            let initialX = scrollView.contentView.bounds.origin.x
            sendVerticalScrollWheel(to: scrollView, deltaY: -180)
            drainMainRunLoop()
            var scrolledX = scrollView.contentView.bounds.origin.x
            if abs(scrolledX - initialX) < 1 {
                sendVerticalScrollWheel(to: scrollView, deltaY: 180)
                drainMainRunLoop()
                scrolledX = scrollView.contentView.bounds.origin.x
            }
            try require(abs(scrolledX - initialX) >= 1, "纵向滚轮未投射为横向滚动")
        }

        try require(
            contentView.smokePerformManagementAction(itemID: "panel-smoke-file", title: "固定条目"),
            "未找到固定条目菜单动作"
        )
        try require(pinRequest?.itemID == "panel-smoke-file" && pinRequest?.isPinned == true, "固定菜单动作未触发回调")

        try require(
            contentView.smokePerformManagementAction(itemID: "panel-smoke-file", title: "删除条目"),
            "未找到删除条目菜单动作"
        )
        try require(deletedItemID == "panel-smoke-file", "删除菜单动作未触发回调")

        try require(
            contentView.smokePerformManagementAction(itemID: "panel-smoke-file", title: "清空当前结果"),
            "未找到清空当前结果菜单动作"
        )
        try require(
            clearRequest?.searchText == "report" && clearRequest?.itemType == "image",
            "清空菜单动作未携带当前筛选范围"
        )

        sendEscape(to: contentView)
        drainMainRunLoop()
        try require(queries.last?.searchText == "", "Escape 未先清空搜索")

        sendEscape(to: contentView)
        drainMainRunLoop()
        try require(hideCount == 1 && !controller.isVisible, "搜索为空时 Escape 未隐藏面板")

        controller.show()
        drainMainRunLoop()
        let refreshedCards = contentView.smokeCardBoxes()
        try require(refreshedCards.count >= 1, "面板重新显示后未保留条目卡片")
        sendMouseDown(to: refreshedCards[0], clickCount: 2)
        drainMainRunLoop()
        try require(copiedItemID == "panel-smoke-text", "双击条目未触发复制回调")
        let doubleClickCopiedItemID = copiedItemID
        try require(!controller.isVisible, "双击复制后面板未隐藏")

        copiedItemID = nil
        controller.show()
        drainMainRunLoop()
        if let scrollView = contentView.smokeHorizontalScrollView() {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        sendCommandModifier(down: true, to: contentView)
        sendCommandNumber(3, to: contentView)
        drainMainRunLoop()
        try require(copiedItemID == "panel-smoke-file", "Command+3 未直接复制第三个完整可见条目")
        try require(!controller.isVisible, "Command+数字复制后面板未隐藏")

        print("panelInteractions=ok")
        print("singleClick=panel-smoke-image")
        print("commandHints=1,2,3")
        print("command3Copy=panel-smoke-file")
        print("typeFilter=\(queries.first { $0.itemType == "image" }?.itemType ?? "none")")
        print("search=\(queries.first { $0.searchText == "report" }?.searchText ?? "none")")
        print("menuPin=\(pinRequest.map { "\($0.itemID):\($0.isPinned)" } ?? "none")")
        print("menuDelete=\(deletedItemID ?? "none")")
        print("clearScope=\(clearRequest.map { "\($0.searchText)|\($0.itemType ?? "all")" } ?? "none")")
        print("escapeHide=\(hideCount)")
        print("doubleClickCopy=\(doubleClickCopiedItemID ?? "none")")
    }

    @MainActor
    private static func sendMouseDown(to view: NSView, clickCount: Int) {
        let localPoint = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        let windowPoint = view.convert(localPoint, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ) else {
            return
        }

        view.mouseDown(with: event)
    }

    @MainActor
    private static func sendCommandNumber(_ number: Int, to view: NSView) {
        let keyCode: Int
        switch number {
        case 1:
            keyCode = kVK_ANSI_1
        case 2:
            keyCode = kVK_ANSI_2
        case 3:
            keyCode = kVK_ANSI_3
        case 4:
            keyCode = kVK_ANSI_4
        case 5:
            keyCode = kVK_ANSI_5
        case 6:
            keyCode = kVK_ANSI_6
        case 7:
            keyCode = kVK_ANSI_7
        case 8:
            keyCode = kVK_ANSI_8
        case 9:
            keyCode = kVK_ANSI_9
        default:
            return
        }

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: "\(number)",
            charactersIgnoringModifiers: "\(number)",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    private static func sendSpace(to view: NSView) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: UInt16(kVK_Space)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    private static func sendCommandModifier(down: Bool, to view: NSView) {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: down ? [.command] : [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Command)
        ) else {
            return
        }

        view.flagsChanged(with: event)
    }

    @MainActor
    private static func sendEscape(to view: NSView) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    private static func sendVerticalScrollWheel(to scrollView: NSScrollView, deltaY: Int32) {
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(deltaY))
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)

        guard let event = NSEvent(cgEvent: cgEvent) else { return }
        scrollView.scrollWheel(with: event)
    }

    @MainActor
    private static func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw SmokeError(message: message)
        }
    }

    private static func makeSampleItems(imagePath: String) -> [RustClipboardItemSummary] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var items = [
            makeItem(
                id: "panel-smoke-text",
                itemType: "text",
                summary: "真实窗口交互 smoke 文本",
                primaryText: "真实窗口交互 smoke 文本",
                sourceAppName: "备忘录",
                timestamp: now,
                sizeBytes: 34
            ),
            makeItem(
                id: "panel-smoke-image",
                itemType: "image",
                summary: "图片 360 x 220",
                primaryText: nil,
                sourceAppName: "预览",
                timestamp: now - 60_000,
                previewAssetPath: imagePath,
                payloadAssetPath: imagePath,
                sizeBytes: 124_000
            ),
            makeItem(
                id: "panel-smoke-file",
                itemType: "file",
                summary: "2 个文件 · report.pdf",
                primaryText: nil,
                sourceAppName: "Finder",
                timestamp: now - 120_000,
                sizeBytes: 2048
            ),
            makeItem(
                id: "panel-smoke-link",
                itemType: "link",
                summary: "example.com",
                primaryText: "https://example.com",
                sourceAppName: "Safari",
                timestamp: now - 180_000,
                sizeBytes: 19
            )
        ]

        for index in 5...16 {
            items.append(makeItem(
                id: "panel-smoke-extra-\(index)",
                itemType: "text",
                summary: "横向滚动填充条目 \(index)",
                primaryText: "横向滚动填充条目 \(index)",
                sourceAppName: "终端",
                timestamp: now - Int64(index * 60_000),
                sizeBytes: 28
            ))
        }

        return items
    }

    private static func makeItem(
        id: String,
        itemType: String,
        summary: String,
        primaryText: String?,
        sourceAppName: String,
        timestamp: Int64,
        previewAssetPath: String? = nil,
        payloadAssetPath: String? = nil,
        sizeBytes: Int64
    ) -> RustClipboardItemSummary {
        RustClipboardItemSummary(
            id: id,
            itemType: itemType,
            summary: summary,
            primaryText: primaryText,
            contentHash: "panel-smoke-\(id)",
            sourceAppId: nil,
            sourceAppName: sourceAppName,
            sourceAppIconPath: nil,
            previewAssetPath: previewAssetPath,
            payloadAssetPath: payloadAssetPath,
            sourceConfidence: "high",
            firstCopiedAtMs: timestamp,
            lastCopiedAtMs: timestamp,
            copyCount: 1,
            isPinned: false,
            sizeBytes: sizeBytes,
            previewState: "ready"
        )
    }

    @MainActor
    private static func makeSmokeImageURL(outputDirectory: URL) throws -> URL {
        let image = NSImage(size: NSSize(width: 360, height: 220))
        image.lockFocus()
        NSColor.systemBlue.withAlphaComponent(0.74).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 360, height: 220), xRadius: 18, yRadius: 18).fill()
        NSColor.systemTeal.withAlphaComponent(0.42).setFill()
        NSBezierPath(ovalIn: NSRect(x: 220, y: 108, width: 86, height: 86)).fill()
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: 42, y: 52, width: 160, height: 24), xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = outputDirectory.appendingPathComponent("panel-interaction-smoke-image.png")
        try pngData.write(to: url, options: .atomic)
        return url
    }

    private struct SmokeError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }
}

private enum UIDiagnosticsCommand {
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

@main
private enum ClipboardWorkbenchDemoApp {
    @MainActor
    static func main() {
        if PreferencesSmokeCommand.shouldRun(arguments: CommandLine.arguments) {
            PreferencesSmokeCommand.run()
            return
        }

        if PanelInteractionSmokeCommand.shouldRun(arguments: CommandLine.arguments) {
            do {
                try PanelInteractionSmokeCommand.run()
            } catch {
                FileHandle.standardError.write(Data("panel interaction smoke failed: \(error.localizedDescription)\n".utf8))
                Darwin.exit(1)
            }
            return
        }

        if UIDiagnosticsCommand.shouldRun(arguments: CommandLine.arguments) {
            UIDiagnosticsCommand.run()
            return
        }

        if let snapshotURL = PanelSnapshotCommand.outputURL(arguments: CommandLine.arguments) {
            do {
                try PanelSnapshotCommand.render(to: snapshotURL)
            } catch {
                FileHandle.standardError.write(Data("panel snapshot failed: \(error)\n".utf8))
                Darwin.exit(1)
            }
            return
        }

        if let preferencesSnapshotURL = PreferencesSnapshotCommand.outputURL(arguments: CommandLine.arguments) {
            do {
                try PreferencesSnapshotCommand.render(to: preferencesSnapshotURL)
            } catch {
                FileHandle.standardError.write(Data("preferences snapshot failed: \(error)\n".utf8))
                Darwin.exit(1)
            }
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
