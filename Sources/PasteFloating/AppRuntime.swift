import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipboardPanelApp
import Darwin
import ServiceManagement

@MainActor
func makeFloatingPanelHostView(contentView: FloatingPanelContentView) -> NSView {
    let tintColor = PasteTheme.current(for: contentView).panel.backgroundColor
    let hostView: NSView

    if #available(macOS 26.0, *) {
        let glassView = NSGlassEffectView(frame: contentView.frame)
        glassView.cornerRadius = FloatingPanelContentView.panelBackgroundCornerRadius
        glassView.tintColor = tintColor
        glassView.style = .regular
        glassView.contentView = contentView
        hostView = glassView
        contentView.updateBackgroundHostState(.systemGlass(tintAlpha: tintColor.alphaComponent))
    } else {
        let effectView = NSVisualEffectView(frame: contentView.frame)
        effectView.appearance = NSAppearance(named: .aqua)
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = FloatingPanelContentView.panelBackgroundCornerRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.backgroundColor = tintColor.cgColor
        effectView.addSubview(contentView)
        hostView = effectView
        contentView.updateBackgroundHostState(.legacyVisualEffect(tintAlpha: tintColor.alphaComponent))
    }

    hostView.wantsLayer = true
    contentView.frame = hostView.bounds
    contentView.autoresizingMask = [.width, .height]
    return hostView
}

final class FloatingPanelContentView: NSView, NSSearchFieldDelegate {
    static let panelBackgroundCornerRadius: CGFloat = 18

    enum BackgroundHostState {
        case none
        case systemGlass(tintAlpha: CGFloat)
        case legacyVisualEffect(tintAlpha: CGFloat)
    }

    var onRuntimeAction: ((PanelRuntimeAction) -> Void)?
    var onHeightResizeBegan: (() -> Void)?
    var onHeightResizeChanged: ((CGFloat) -> Void)?

    private enum Layout {
        static let padding: CGFloat = 22
        static let resizeHandleHeight: CGFloat = 16
        static let controlBarHeight: CGFloat = 52
        static let sectionSpacing: CGFloat = 12
        static let defaultItemSide: CGFloat = 218
        static let compactItemSide: CGFloat = 156
        static let imagePreviewMinHeight: CGFloat = 78
        static let imagePreviewMaxHeight: CGFloat = 116
        static let scrollEdgeInset: CGFloat = 2
        static let panelCornerRadius: CGFloat = 18
        static let cardCornerRadius: CGFloat = 10
        static let innerCornerRadius: CGFloat = 8
        static let chipCornerRadius: CGFloat = 15
        static let cardHeaderHeight: CGFloat = 48
        static let cardInset: CGFloat = 12
        static let cardFooterHeight: CGFloat = 17
        static let sourceIconSize: CGFloat = 54
        static let linkPreviewHeight: CGFloat = 84
        static let filePreviewHeight: CGFloat = 58
        static let hairlineWidth: CGFloat = 1
    }

    private enum DefaultPinboard {
        static let defaultID = "default"
        static let defaultTitle = "固定"
    }

    private struct PinboardColorOption: Equatable {
        let title: String
        let colorCode: Int64
    }

    private static let pinboardColorOptions: [PinboardColorOption] = [
        PinboardColorOption(title: "红色", colorCode: 4_293_940_557),
        PinboardColorOption(title: "橙色", colorCode: 4_293_088_528),
        PinboardColorOption(title: "黄色", colorCode: 4_294_620_928),
        PinboardColorOption(title: "绿色", colorCode: 4_279_606_035),
        PinboardColorOption(title: "蓝色", colorCode: 4_283_973_119),
        PinboardColorOption(title: "紫色", colorCode: 4_290_925_536),
        PinboardColorOption(title: "粉色", colorCode: 4_294_913_365),
        PinboardColorOption(title: "灰色", colorCode: 9_408_403)
    ]

    private struct PinboardFilterEntry: Equatable {
        let id: String
        let title: String
        let colorCode: Int64
        let itemCount: Int64
    }

    private final class PinboardColorSwatchButton: NSButton {
        let colorCode: Int64
        private let swatchColor: NSColor
        let selectedSwatch: Bool

        init(colorCode: Int64, color: NSColor, selected: Bool) {
            self.colorCode = colorCode
            self.swatchColor = color
            self.selectedSwatch = selected
            super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
            isBordered = false
            imagePosition = .noImage
            title = ""
            setButtonType(.momentaryChange)
            focusRingType = .none
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            NSBezierPath(rect: bounds).fill()

            let outerRect = bounds.insetBy(dx: 1, dy: 1)
            if selectedSwatch {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: outerRect).fill()
                NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
                let ring = NSBezierPath(ovalIn: outerRect.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1
                ring.stroke()
            }

            let colorInset: CGFloat = selectedSwatch ? 5 : 3
            let colorPath = NSBezierPath(ovalIn: bounds.insetBy(dx: colorInset, dy: colorInset))
            swatchColor.setFill()
            colorPath.fill()
            NSColor.black.withAlphaComponent(0.16).setStroke()
            colorPath.lineWidth = 1
            colorPath.stroke()
        }
    }

    private final class PinboardColorSwatchRowView: NSView {
        private let onSelect: (Int64) -> Void
        private var buttons: [PinboardColorSwatchButton] = []
        private var titlesByColorCode: [Int64: String] = [:]

        init(
            options: [PinboardColorOption],
            selectedColorCode: Int64,
            colorProvider: (Int64) -> NSColor,
            onSelect: @escaping (Int64) -> Void
        ) {
            self.onSelect = onSelect
            super.init(frame: NSRect(x: 0, y: 0, width: 252, height: 38))
            titlesByColorCode = Dictionary(uniqueKeysWithValues: options.map { ($0.colorCode, $0.title) })
            buttons = options.map { option in
                PinboardColorSwatchButton(
                    colorCode: option.colorCode,
                    color: colorProvider(option.colorCode),
                    selected: option.colorCode == selectedColorCode
                )
            }
            for button in buttons {
                button.target = self
                button.action = #selector(colorPressed(_:))
                addSubview(button)
            }
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: 252, height: 38)
        }

        override func layout() {
            super.layout()
            let buttonSide: CGFloat = 24
            let spacing: CGFloat = 7
            var x = (bounds.width - CGFloat(buttons.count) * buttonSide - CGFloat(max(buttons.count - 1, 0)) * spacing) / 2
            let y = (bounds.height - buttonSide) / 2
            for button in buttons {
                button.frame = NSRect(x: x, y: y, width: buttonSide, height: buttonSide)
                x += buttonSide + spacing
            }
        }

        @objc private func colorPressed(_ sender: PinboardColorSwatchButton) {
            onSelect(sender.colorCode)
            enclosingMenuItem?.menu?.cancelTracking()
        }

        func smokeColorItems() -> [(title: String, isSelected: Bool)] {
            buttons.map { button in
                (
                    title: titlesByColorCode[button.colorCode] ?? "",
                    isSelected: button.selectedSwatch
                )
            }
        }
    }

    private let searchField = NSSearchField()
    private let previewPopoverController = ClipboardPreviewPopoverController()
    private let itemBandDocumentView = NSView()
    private let itemBandStack = NSStackView()
    private weak var itemBandScrollView: HorizontalWheelScrollView?
    private var itemWidthConstraints: [NSLayoutConstraint] = []
    private var itemHeightConstraints: [NSLayoutConstraint] = []
    private var itemPreviewHeightConstraints: [NSLayoutConstraint] = []
    private var itemPreviewWidthConstraints: [NSLayoutConstraint] = []
    private var itemImagePreviewViews: [NSImageView] = []
    private var itemBodyLabels: [NSTextField] = []
    private var renderedCardStatesByID: [String: PanelItemCardViewState] = [:]
    private var currentPanelHeight: CGFloat = BottomPanelGeometryPlanner.defaultHeight
    private var pinboardButtons: [PinboardChipButton] = []
    private var toolbarIconButtons: [PanelActionButton] = []
    private var pinboardFilters: [PinboardFilterEntry] = []
    private var pendingCreatedPinboardSourceIDs: Set<String>?
    private weak var activeRenameField: NSTextField?
    private weak var activeRenameButton: PinboardChipButton?
    private var activeRenamePinboardID: String?
    private var activeRenameOriginalTitle: String?
    private var isInstallingRenameField = false
    private var searchFieldWidthConstraint: NSLayoutConstraint?
    private weak var filterRow: NSStackView?
    private var appSupportDirectory: URL?
    private let interactionController = PanelInteractionController()
    private var commandHintMonitor: Any?
    private var backgroundHostState: BackgroundHostState = .none
    private var cardAssetResolver: PanelCardAssetResolver {
        PanelCardAssetResolver(appSupportDirectory: appSupportDirectory)
    }
    private var theme: PasteThemePalette {
        PasteTheme.current(for: self)
    }

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
            stopCommandHintMonitor()
            clearCommandHintMode()
        } else {
            applyTheme()
            startCommandHintMonitor()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
        renderCurrentItems(scrollSelectedItem: false, preserveScrollPosition: true)
    }

    func updateBackgroundHostState(_ state: BackgroundHostState) {
        backgroundHostState = state
    }

    func updateStorageState(_ result: Result<RustCoreOpenResult, RustCoreError>) {
        applyRenderPlan(interactionController.updateStorageState(result))
    }

    func updateAppSupportDirectory(_ url: URL) {
        appSupportDirectory = url
    }

    func updatePinboards(_ pinboards: [RustPinboardSummary]) {
        let nextFilters = pinboards.compactMap { pinboard -> PinboardFilterEntry? in
            if pinboard.id == DefaultPinboard.defaultID && pinboard.itemCount == 0 {
                return nil
            }
            return PinboardFilterEntry(
                id: pinboard.id,
                title: pinboard.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "未命名"
                    : pinboard.title,
                colorCode: pinboard.colorCode,
                itemCount: pinboard.itemCount
            )
        }

        let previousPinboardIDs = pendingCreatedPinboardSourceIDs
        let didChangeFilters = nextFilters != pinboardFilters
        pinboardFilters = nextFilters
        if didChangeFilters {
            rebuildFilterChips()
        }

        if let previousPinboardIDs {
            pendingCreatedPinboardSourceIDs = nil
            let createdPinboardID = nextFilters.first { !previousPinboardIDs.contains($0.id) }?.id
                ?? (nextFilters.count > previousPinboardIDs.count ? nextFilters.last?.id : nil)
            if let createdPinboardID {
                selectPinboardAfterCreation(pinboardID: createdPinboardID)
            }
        }
    }

    func setPreviewPopoverEnabled(_ enabled: Bool) {
        interactionController.setPreviewPopoverEnabled(enabled)
        if !enabled {
            previewPopoverController.close()
        }
    }

    func closePreviewPopover() {
        previewPopoverController.close()
    }

    func resetFiltersForCapturedItem() {
        let result = interactionController.dispatch(.clearFilters)
        let localEffects = result.effects.filter { effect in
            if case .external(.queryChanged) = effect {
                return false
            }
            return true
        }
        applyInteractionResult(PanelInteractionResult(
            viewState: result.viewState,
            effects: localEffects,
            shouldSyncToolbar: result.shouldSyncToolbar
        ))
    }

    func clearPinboardSelectionIfNeeded(deletedPinboardID: String) {
        guard panelViewState().toolbar.selectedPinboardID == deletedPinboardID else { return }
        let result = interactionController.dispatch(.setPinboardFilter(nil))
        let localEffects = result.effects.filter { effect in
            if case .external(.queryChanged) = effect {
                return false
            }
            return true
        }
        applyInteractionResult(PanelInteractionResult(
            viewState: result.viewState,
            effects: localEffects,
            shouldSyncToolbar: result.shouldSyncToolbar
        ))
    }

    private func selectPinboardAfterCreation(pinboardID: String) {
        if panelViewState().toolbar.selectedPinboardID != pinboardID {
            applyInteractionAction(.setPinboardFilter(pinboardID))
        }
        beginInlinePinboardRenameAfterCreation(pinboardID: pinboardID)
    }

    private func beginInlinePinboardRenameAfterCreation(pinboardID: String) {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }),
              let button = pinboardButtons.first(where: { $0.pinboardID == pinboardID })
        else { return }

        layoutSubtreeIfNeeded()
        beginInlinePinboardRename(pinboard, in: button)
    }

    func containsPreviewSurface(eventWindow: NSWindow?, mouseLocation: CGPoint) -> Bool {
        if let previewWindow = previewPopoverController.contentWindow,
           eventWindow === previewWindow {
            return true
        }

        return previewPopoverController.screenFrame?.contains(mouseLocation) ?? false
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
        let itemSide = itemSideLength(for: panelHeight)
        let previewHeight = min(
            Layout.imagePreviewMaxHeight,
            max(Layout.imagePreviewMinHeight, itemSide * 0.48)
        )
        let bodyTextWidth = max(80, itemSide - Layout.cardInset * 2 - 4)

        itemWidthConstraints.forEach { $0.constant = itemSide }
        itemHeightConstraints.forEach { $0.constant = itemSide }
        itemPreviewHeightConstraints.forEach { $0.constant = previewHeight }
        itemPreviewWidthConstraints.forEach { $0.constant = max(54, itemSide - 72) }
        itemBodyLabels.forEach { label in
            label.preferredMaxLayoutWidth = bodyTextWidth
        }
        itemImagePreviewViews.forEach { imageView in
            imageView.needsLayout = true
        }
        itemBandDocumentView.setFrameSize(
            NSSize(width: itemBandDocumentWidth(itemSide: itemSide), height: itemSide)
        )
        itemBandDocumentView.needsLayout = true
    }

    private func itemSideLength(for panelHeight: CGFloat) -> CGFloat {
        max(
            Layout.compactItemSide,
            panelHeight - Layout.controlBarHeight - Layout.sectionSpacing - Layout.padding
        )
    }

    private func itemBandDocumentWidth(itemSide: CGFloat) -> CGFloat {
        let cardCount = max(itemBandStack.arrangedSubviews.count, 1)
        return CGFloat(cardCount) * itemSide
            + CGFloat(max(cardCount - 1, 0)) * itemBandStack.spacing
            + Layout.scrollEdgeInset * 2
    }

    private func handleItemBandScrollDidChange() {
        applyInteractionAction(.didScroll(
            visibleCommandItemIDs: fullyVisibleCommandItemIDs(),
            reachedLoadMoreThreshold: hasReachedLoadMoreThreshold()
        ))
    }

    private func configureAppearance() {
        userInterfaceLayoutDirection = .leftToRight
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        applyTheme()
    }

    private func applyTheme() {
        let theme = theme
        layer?.backgroundColor = NSColor.clear.cgColor
        toolbarIconButtons.forEach { button in
            button.contentTintColor = theme.panel.toolbarIconColor
        }
        updatePinboardChipAppearance()
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
            controlBar.topAnchor.constraint(equalTo: topAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: Layout.controlBarHeight),

            itemBand.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.padding),
            itemBand.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.padding),
            itemBand.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: Layout.sectionSpacing),
            itemBand.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.padding)
        ])

        resetItemLayoutTracking()
        renderItemCards([makeEmptyHistoryCard()])
        updatePanelHeight(currentPanelHeight)
    }

    private func makeControlBar() -> NSView {
        let container = NSView()

        searchField.placeholderString = "搜索剪贴板内容或来源应用"
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

        let chips = makeFilterChips()
        pinboardButtons = chips
        updatePinboardChipAppearance()

        let addButton = makeToolbarIconButton(
            symbolName: "plus",
            accessibilityLabel: "创建 Pinboard"
        ) { [weak self] in
            self?.showCreatePinboardDialog()
        }

        let row = NSStackView(views: [searchButton, searchField] + chips + [addButton])
        row.orientation = NSUserInterfaceLayoutOrientation.horizontal
        row.alignment = NSLayoutConstraint.Attribute.centerY
        row.spacing = 18
        row.userInterfaceLayoutDirection = NSUserInterfaceLayoutDirection.leftToRight
        row.translatesAutoresizingMaskIntoConstraints = false
        filterRow = row

        container.addSubview(row)
        searchFieldWidthConstraint = searchField.widthAnchor.constraint(equalToConstant: 220)
        searchFieldWidthConstraint?.isActive = true

        let leadingConstraint = row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor)
        leadingConstraint.priority = .defaultLow
        let trailingConstraint = row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
        trailingConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leadingConstraint,
            trailingConstraint,
            searchField.heightAnchor.constraint(equalToConstant: 28)
        ])

        return container
    }

    private func makeFilterChips() -> [PinboardChipButton] {
        [makePinboardChip(title: "剪贴板", pinboardID: nil, dotColor: .clear)]
            + pinboardFilters.map { pinboard in
                makePinboardChip(
                    title: pinboard.title,
                    pinboardID: pinboard.id,
                    dotColor: pinboardDotColor(colorCode: pinboard.colorCode)
                )
            }
    }

    private func rebuildFilterChips() {
        guard let filterRow else { return }

        cancelInlinePinboardRename()
        let oldButtons = pinboardButtons
        let newButtons = makeFilterChips()
        for oldButton in oldButtons {
            filterRow.removeArrangedSubview(oldButton)
            oldButton.removeFromSuperview()
        }
        let insertionIndex = max(filterRow.arrangedSubviews.count - 1, 2)
        for (offset, newButton) in newButtons.enumerated() {
            filterRow.insertArrangedSubview(newButton, at: insertionIndex + offset)
        }
        pinboardButtons = newButtons
        updatePinboardChipAppearance()
    }

    private func pinboardDotColor(colorCode: Int64) -> NSColor {
        guard colorCode > 0 else { return NSColor.systemRed }
        let value = UInt64(colorCode)
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        let alphaByte = (value >> 24) & 0xFF
        let alpha = alphaByte == 0 ? CGFloat(1) : CGFloat(alphaByte) / 255
        return NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
    }

    private func showPanelOverflowMenu() {
        let menu = makePanelOverflowMenu()
        guard let event = NSApp.currentEvent else { return }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    private func makePanelOverflowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let selectedPinboard = selectedPinboardEntry()
        let renameItem = ActionMenuItem(title: "重命名", imageName: "pencil") { [weak self] in
            self?.showRenamePinboardDialog()
        }
        renameItem.isEnabled = selectedPinboard != nil
        menu.addItem(renameItem)

        let shareItem = ActionMenuItem(title: "共享 Pinboard", imageName: "square.and.arrow.up") { [weak self] in
            self?.showShareUnavailableAlert()
        }
        shareItem.isEnabled = selectedPinboard != nil
        menu.addItem(shareItem)

        let deleteItem = ActionMenuItem(title: "删除...", imageName: "trash") { [weak self] in
            self?.confirmDeleteSelectedPinboard()
        }
        deleteItem.isEnabled = selectedPinboard != nil
        menu.addItem(deleteItem)
        if let selectedPinboard {
            menu.addItem(.separator())
            menu.addItem(makePinboardColorRowMenuItem(for: selectedPinboard))
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "偏好设置…", imageName: "gearshape") { [weak self] in
            self?.onRuntimeAction?(.showPreferences)
        })
        menu.addItem(ActionMenuItem(title: "隐藏面板", imageName: "eye.slash") { [weak self] in
            self?.applyInteractionAction(.hidePanel)
        })

        return menu
    }

    private func selectedPinboardEntry() -> PinboardFilterEntry? {
        guard let selectedPinboardID = panelViewState().toolbar.selectedPinboardID else { return nil }
        return pinboardFilters.first { $0.id == selectedPinboardID }
    }

    private func makePinboardColorRowMenuItem(for pinboard: PinboardFilterEntry) -> NSMenuItem {
        let item = NSMenuItem(title: "颜色", action: nil, keyEquivalent: "")
        item.view = PinboardColorSwatchRowView(
            options: Self.pinboardColorOptions,
            selectedColorCode: pinboard.colorCode,
            colorProvider: { [weak self] colorCode in
                self?.pinboardDotColor(colorCode: colorCode) ?? .systemRed
            },
            onSelect: { [weak self] colorCode in
                self?.onRuntimeAction?(.updatePinboardColor(
                    pinboardID: pinboard.id,
                    colorCode: colorCode
                ))
            }
        )
        return item
    }

    private func makePinboardChipManagementMenu(for pinboard: PinboardFilterEntry) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: "重命名", imageName: "pencil") { [weak self] in
            self?.showRenamePinboardDialog(for: pinboard)
        })

        menu.addItem(ActionMenuItem(title: "共享 Pinboard", imageName: "square.and.arrow.up") { [weak self] in
            self?.showShareUnavailableAlert()
        })

        menu.addItem(ActionMenuItem(title: "删除...", imageName: "trash") { [weak self] in
            self?.confirmDeletePinboard(pinboard)
        })
        menu.addItem(.separator())
        menu.addItem(makePinboardColorRowMenuItem(for: pinboard))
        return menu
    }

    private func showCreatePinboardDialog() {
        createPinboardDirectly()
    }

    private func createPinboardDirectly() {
        let colorOption = Self.pinboardColorOptions.randomElement() ?? Self.pinboardColorOptions[0]
        pendingCreatedPinboardSourceIDs = Set(pinboardFilters.map(\.id))
        onRuntimeAction?(.createPinboard(title: "未命名", colorCode: colorOption.colorCode))
    }

    private func showRenamePinboardDialog(for explicitPinboard: PinboardFilterEntry? = nil) {
        guard let pinboard = explicitPinboard ?? selectedPinboardEntry(),
              let button = pinboardButtons.first(where: { $0.pinboardID == pinboard.id })
        else { return }
        beginInlinePinboardRename(pinboard, in: button)
    }

    private func beginInlinePinboardRename(
        _ pinboard: PinboardFilterEntry,
        in button: PinboardChipButton
    ) {
        cancelInlinePinboardRename()

        let textField = NSTextField(frame: inlineRenameFieldFrame(in: button))
        textField.placeholderString = placeholder
        textField.stringValue = pinboard.title
        textField.font = .systemFont(ofSize: button.chipFontSize, weight: .medium)
        textField.textColor = theme.panel.toolbarSelectedTextColor
        textField.backgroundColor = .clear
        textField.drawsBackground = false
        textField.isBordered = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.delegate = self

        button.chipIsRenaming = true
        button.addSubview(textField)
        activeRenameField = textField
        activeRenameButton = button
        activeRenamePinboardID = pinboard.id
        activeRenameOriginalTitle = pinboard.title
        updateInlinePinboardRenameLayout()
        isInstallingRenameField = true
        window?.makeFirstResponder(textField)
        textField.selectText(nil)
        DispatchQueue.main.async { [weak self, weak textField] in
            guard let self else { return }
            defer { self.isInstallingRenameField = false }
            guard let textField else { return }
            textField.selectText(nil)
            textField.currentEditor()?.selectedRange = NSRange(location: 0, length: textField.stringValue.utf16.count)
        }
    }

    private var placeholder: String {
        "未命名"
    }

    private func inlineRenameFieldFrame(in button: PinboardChipButton) -> NSRect {
        button.layoutSubtreeIfNeeded()
        let markerWidth = button.chipSymbolName == nil ? button.chipDotDiameter : button.chipIconSide
        let x = button.chipHorizontalPadding + markerWidth + button.chipMarkerTextSpacing - 2
        let fieldHeight: CGFloat = 20
        let width = max(44, button.bounds.width - x - button.chipHorizontalPadding + 4)
        return NSRect(
            x: x,
            y: (button.bounds.height - fieldHeight) / 2,
            width: width,
            height: fieldHeight
        )
    }

    private func updateInlinePinboardRenameLayout() {
        guard let textField = activeRenameField,
              let button = activeRenameButton
        else { return }

        let sizingTitle = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? placeholder
            : textField.stringValue
        button.chipTitleText = sizingTitle
        button.invalidateIntrinsicContentSize()
        button.superview?.needsLayout = true
        button.superview?.layoutSubtreeIfNeeded()
        button.layoutSubtreeIfNeeded()
        textField.frame = inlineRenameFieldFrame(in: button)
    }

    private func finishInlinePinboardRename(commit: Bool) {
        guard let textField = activeRenameField else { return }
        let button = activeRenameButton
        let pinboardID = activeRenamePinboardID
        let nextTitle = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = nextTitle.isEmpty ? placeholder : nextTitle

        textField.delegate = nil
        textField.removeFromSuperview()
        activeRenameField = nil
        button?.chipIsRenaming = false
        button?.chipTitleText = commit ? normalizedTitle : (activeRenameOriginalTitle ?? normalizedTitle)
        button?.invalidateIntrinsicContentSize()
        button?.superview?.needsLayout = true
        button?.superview?.layoutSubtreeIfNeeded()
        activeRenameButton = nil
        activeRenamePinboardID = nil
        activeRenameOriginalTitle = nil
        window?.makeFirstResponder(self)

        if commit, let pinboardID {
            onRuntimeAction?(.renamePinboard(pinboardID: pinboardID, title: normalizedTitle))
        }
    }

    private func cancelInlinePinboardRename() {
        finishInlinePinboardRename(commit: false)
    }

    private func showShareUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "共享 Pinboard"
        alert.informativeText = "共享 Pinboard 尚未接入。"
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    private func confirmDeleteSelectedPinboard() {
        guard let pinboard = selectedPinboardEntry() else { return }
        confirmDeletePinboard(pinboard)
    }

    private func confirmDeletePinboard(_ pinboard: PinboardFilterEntry) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除“\(pinboard.title)”？"
        alert.informativeText = "删除 Pinboard 及其所有内容将无法恢复。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onRuntimeAction?(.deletePinboard(pinboardID: pinboard.id))
    }

    private func pinboardDeletionRequiresConfirmation(_ pinboard: PinboardFilterEntry) -> Bool {
        true
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
            self?.handleItemBandScrollDidChange()
        }

        itemBandStack.orientation = .horizontal
        itemBandStack.alignment = .top
        itemBandStack.spacing = 22
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

    func updateListState(_ result: Result<RustCoreListResult, RustCoreError>, isFiltered: Bool, append: Bool = false) {
        applyRenderPlan(interactionController.updateListState(result, isFiltered: isFiltered, append: append))
    }

    func updateLoadingMoreState(_ isLoading: Bool) {
        interactionController.updateLoadingMoreState(isLoading)
    }

    private func renderCurrentItems(
        scrollSelectedItem: Bool = true,
        preserveScrollPosition: Bool = false
    ) {
        let preservedOrigin = itemBandScrollView?.contentView.bounds.origin
        resetItemLayoutTracking()
        switch panelViewState().list.presentation {
        case .emptyHistory:
            renderItemCards([makeEmptyHistoryCard()])
            return
        case .filteredEmpty:
            renderItemCards([makeNoResultsCard()])
            return
        case .databaseError:
            renderItemCards([makeDatabaseErrorCard()])
            return
        case .items(let items):
            renderItemCards(items.map(makeItemCard))
        }
        if preserveScrollPosition, let preservedOrigin, let scrollView = itemBandScrollView {
            scrollView.contentView.scroll(to: preservedOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else if scrollSelectedItem {
            scrollSelectedItemIntoView()
        }
    }

    private func applyRenderPlan(_ plan: PanelContentRenderPlan) {
        if plan.shouldClosePreview {
            previewPopoverController.close()
        }

        switch plan.instruction {
        case .reloadAll(let scrollSelectedItem, let preserveScrollPosition):
            renderCurrentItems(
                scrollSelectedItem: scrollSelectedItem,
                preserveScrollPosition: preserveScrollPosition
            )
        case .appendItems(let items, let preserveScrollPosition):
            appendItemsToRenderedList(items, preserveScrollPosition: preserveScrollPosition)
        case .noVisualChange:
            break
        }
    }

    private func appendItemsToRenderedList(
        _ items: [RustClipboardItemSummary],
        preserveScrollPosition: Bool
    ) {
        let preservedOrigin = itemBandScrollView?.contentView.bounds.origin

        if items.isEmpty {
            refreshItemBandLayout(preservedOrigin: preservedOrigin, preserveScrollPosition: preserveScrollPosition)
            return
        }

        items.map(makeItemCard).forEach { itemBandStack.addArrangedSubview($0) }
        refreshItemBandLayout(preservedOrigin: preservedOrigin, preserveScrollPosition: preserveScrollPosition)
    }

    private func refreshItemBandLayout(
        preservedOrigin: NSPoint?,
        preserveScrollPosition: Bool
    ) {
        let itemSide = itemSideLength(for: currentPanelHeight)
        itemBandDocumentView.frame = NSRect(
            x: 0,
            y: 0,
            width: itemBandDocumentWidth(itemSide: itemSide),
            height: itemSide
        )
        updatePanelHeight(currentPanelHeight)

        if preserveScrollPosition, let preservedOrigin, let scrollView = itemBandScrollView {
            scrollView.contentView.scroll(to: preservedOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        refreshVisibleCommandHints()
    }

    private func handleKeyboardCommand(_ event: NSEvent) -> Bool {
        let commandPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)

        if commandPressed,
           let character = event.charactersIgnoringModifiers?.lowercased() {
            if character == "f" {
                applyInteractionAction(.focusSearch)
                return true
            }

            if let segment = Int(character), (1...9).contains(segment) {
                applyInteractionAction(.copyCommandItem(
                    number: segment,
                    visibleItemIDs: fullyVisibleCommandItemIDs()
                ))
                return true
            }
        }

        switch Int(event.keyCode) {
        case kVK_Space:
            clearCommandHintModeIfCommandIsNotPressed(in: event)
            applyInteractionAction(.activateSelectedPreview)
            return true
        case kVK_RightArrow:
            clearCommandHintModeIfCommandIsNotPressed(in: event)
            applyInteractionAction(.selectOffset(1))
            return true
        case kVK_LeftArrow:
            clearCommandHintModeIfCommandIsNotPressed(in: event)
            applyInteractionAction(.selectOffset(-1))
            return true
        case kVK_Escape:
            clearCommandHintMode()
            applyInteractionAction(.escape(isPreviewShown: previewPopoverController.isShown))
            return true
        default:
            return false
        }
    }

    private func applyInteractionAction(_ action: PanelInteractionAction) {
        applyInteractionResult(interactionController.dispatch(action))
    }

    private func applyInteractionResult(_ result: PanelInteractionResult) {
        if result.shouldSyncToolbar {
            syncToolbarFromViewState()
        }

        for effect in result.effects {
            switch effect {
            case .external(let action):
                emitRuntimeAction(action)
            case .focus(let target):
                focus(target)
            case .selectionChanged(let scrollIntoView):
                updateVisibleSelection(scrollIntoView: scrollIntoView)
            case .preview(let request):
                applyPreviewRequest(request)
            case .commandHints(let textsByItemID):
                applyCommandHintTexts(textsByItemID)
            }
        }
    }

    private func syncToolbarFromViewState() {
        let viewState = panelViewState()
        searchField.stringValue = viewState.toolbar.searchText
        searchField.isHidden = !viewState.toolbar.isSearchVisible
        updatePinboardChipAppearance()
    }

    private func emitRuntimeAction(_ action: PanelExternalAction) {
        switch action {
        case .queryChanged(let searchText, let sourceAppID, let pinboardID):
            onRuntimeAction?(.queryChanged(
                searchText: searchText,
                sourceAppID: sourceAppID,
                pinboardID: pinboardID
            ))
        case .copyItem(let itemID):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.copyItem(item))
        case .setPinboardMembership(let itemID, let pinboardID, let isMember):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.setPinboardMembership(
                item,
                pinboardID: pinboardID,
                isMember: isMember
            ))
        case .deleteItem(let itemID):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.deleteItem(item))
        case .hidePanel:
            onRuntimeAction?(.hidePanel)
        case .loadMore:
            onRuntimeAction?(.loadMore)
        }
    }

    private func focus(_ target: PanelFocusTarget) {
        switch target {
        case .searchField:
            window?.makeFirstResponder(searchField)
        case .panel:
            window?.makeFirstResponder(self)
        }
    }

    private func applyPreviewRequest(_ request: PanelPreviewRequest) {
        switch request {
        case .close:
            previewPopoverController.close()
        case .toggle(let itemID):
            togglePreview(forItemID: itemID)
        case .show(let itemID):
            showPreview(forItemID: itemID)
        }
    }

    private func togglePreview(forItemID itemID: String) {
        guard let appSupportDirectory,
              let item = interactionController.item(withID: itemID),
              let index = currentItems().firstIndex(where: { $0.id == itemID }),
              index < itemBandStack.arrangedSubviews.count
        else {
            return
        }

        previewPopoverController.toggle(
            item: item,
            appSupportDirectory: appSupportDirectory,
            relativeTo: itemBandStack.arrangedSubviews[index]
        )
    }

    private func showPreview(forItemID itemID: String) {
        guard let item = interactionController.item(withID: itemID),
              let index = currentItems().firstIndex(where: { $0.id == itemID }),
              index < itemBandStack.arrangedSubviews.count
        else {
            return
        }

        previewPopoverController.show(
            item: item,
            appSupportDirectory: appSupportDirectory ?? URL(fileURLWithPath: NSHomeDirectory()),
            relativeTo: itemBandStack.arrangedSubviews[index]
        )
    }

    private func showManagementMenu(for item: RustClipboardItemSummary, event: NSEvent) {
        applyInteractionAction(.prepareManagementMenu(itemID: item.id))

        guard let index = currentItems().firstIndex(where: { $0.id == item.id }),
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
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: "复制", keyEquivalent: "c", modifierMask: [.command]) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .copy))
        })
        menu.addItem(ActionMenuItem(title: "删除", keyEquivalent: "\u{8}", modifierMask: []) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .delete))
        })
        menu.addItem(.separator())
        menu.addItem(makePinboardMenuItem(for: item))
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "预览", keyEquivalent: " ", modifierMask: []) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .preview))
        })
        return menu
    }

    private func makePinboardMenuItem(for item: RustClipboardItemSummary) -> NSMenuItem {
        let menuItem = NSMenuItem(title: "固定", action: nil, keyEquivalent: "")
        menuItem.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "固定")

        let submenu = NSMenu()
        let selectedPinboardID = panelViewState().toolbar.selectedPinboardID
        for pinboard in pinboardFilters {
            let membershipIsKnown = item.isPinned && (
                selectedPinboardID == pinboard.id
                    || (pinboardFilters.count == 1 && pinboard.id == DefaultPinboard.defaultID)
            )
            let pinboardItem = ActionMenuItem(title: pinboard.title) { [weak self] in
                self?.applyInteractionAction(.management(
                    itemID: item.id,
                    action: .setPinboardMembership(
                        pinboardID: pinboard.id,
                        isMember: !membershipIsKnown
                    )
                ))
            }
            pinboardItem.state = membershipIsKnown ? .on : .off
            pinboardItem.image = pinboardMenuDotImage(colorCode: pinboard.colorCode)
            submenu.addItem(pinboardItem)
        }
        if !pinboardFilters.isEmpty {
            submenu.addItem(.separator())
        }
        submenu.addItem(ActionMenuItem(title: "创建 Pinboard...") { [weak self] in
            self?.showCreatePinboardDialog()
        })

        menuItem.submenu = submenu
        menuItem.isEnabled = true
        return menuItem
    }

    private func pinboardMenuDotImage(colorCode: Int64) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let dotPath = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10))
        pinboardDotColor(colorCode: colorCode).setFill()
        dotPath.fill()
        NSColor.black.withAlphaComponent(0.16).setStroke()
        dotPath.lineWidth = 1
        dotPath.stroke()
        image.unlockFocus()
        return image
    }

    private func updateVisibleSelection(scrollIntoView: Bool = true) {
        let selectedItemID = panelViewState().selectedItemID
        for view in itemBandStack.arrangedSubviews {
            guard let card = view as? ClipboardItemCardBox else { continue }
            card.applySelection(card.itemID == selectedItemID)
        }

        if scrollIntoView {
            scrollSelectedItemIntoView()
        }

        refreshVisibleCommandHints()
    }

    private func scrollSelectedItemIntoView() {
        let viewState = panelViewState()
        guard let selectedItemID = viewState.selectedItemID,
              let index = currentItems().firstIndex(where: { $0.id == selectedItemID }),
              index < itemBandStack.arrangedSubviews.count
        else {
            return
        }

        let selectedView = itemBandStack.arrangedSubviews[index]
        itemBandDocumentView.scrollToVisible(selectedView.frame.insetBy(dx: -24, dy: 0))
    }

    private func startCommandHintMonitor() {
        guard commandHintMonitor == nil else { return }
        commandHintMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
                self.commitInlinePinboardRenameBeforePanelMouseDown(event)
            }
            let commandPressed = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .contains(.command)

            if event.type == .flagsChanged {
                self.updateCommandHintMode(commandPressed)
            } else if !commandPressed {
                self.clearCommandHintMode()
            }

            return event
        }
    }

    private func commitInlinePinboardRenameBeforePanelMouseDown(_ event: NSEvent) {
        guard let activeRenameField,
              event.window === window
        else { return }

        let fieldPoint = activeRenameField.convert(event.locationInWindow, from: nil)
        guard !activeRenameField.bounds.contains(fieldPoint) else { return }
        finishInlinePinboardRename(commit: true)
    }

    private func stopCommandHintMonitor() {
        if let commandHintMonitor {
            NSEvent.removeMonitor(commandHintMonitor)
        }
        commandHintMonitor = nil
    }

    private func updateCommandHintMode(_ enabled: Bool) {
        if panelViewState().isCommandHintModeEnabled == enabled, !enabled {
            return
        }

        applyInteractionAction(.setCommandHintMode(
            enabled: enabled,
            visibleItemIDs: enabled ? fullyVisibleCommandItemIDs() : []
        ))
    }

    private func clearCommandHintMode() {
        updateCommandHintMode(false)
    }

    private func clearCommandHintModeIfCommandIsNotPressed(in event: NSEvent) {
        let commandPressed = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command)
        if !commandPressed {
            clearCommandHintMode()
        }
    }

    private func applyCommandHintTexts(_ commandNumbersByID: [String: String]) {
        for view in itemBandStack.arrangedSubviews {
            guard let card = view as? ClipboardItemCardBox else { continue }
            let commandIndexText = card.itemID.flatMap { commandNumbersByID[$0] }
            if let itemID = card.itemID,
               let state = renderedCardStatesByID[itemID] {
                renderedCardStatesByID[itemID] = PanelItemCardViewStateAdapter.stateBySettingCommandIndexText(
                    state,
                    commandIndexText: commandIndexText
                )
            }
            card.setCommandIndexText(commandIndexText)
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

    private func refreshVisibleCommandHints() {
        applyInteractionAction(.visibleCommandItemsChanged(fullyVisibleCommandItemIDs()))
    }

    private func hasReachedLoadMoreThreshold() -> Bool {
        guard let scrollView = itemBandScrollView else { return false }
        let visibleRect = scrollView.contentView.bounds
        let documentWidth = itemBandDocumentView.frame.width
        let threshold = max(itemSideLength(for: currentPanelHeight) * 4, visibleRect.width * 1.2)
        return visibleRect.maxX >= documentWidth - threshold
    }

    private func currentItems() -> [RustClipboardItemSummary] {
        interactionController.currentItems
    }

    private func currentItemIDs() -> [String] {
        interactionController.currentItemIDs
    }

    private func panelViewState() -> PanelViewState {
        interactionController.viewState
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === searchField {
            applyInteractionAction(.setSearchText(searchField.stringValue))
            return
        }

        guard obj.object as? NSTextField === activeRenameField else { return }
        updateInlinePinboardRenameLayout()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === activeRenameField else { return }
        guard !isInstallingRenameField else { return }
        finishInlinePinboardRename(commit: true)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === activeRenameField else { return false }

        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            finishInlinePinboardRename(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelInlinePinboardRename()
            return true
        default:
            return false
        }
    }

    private func pinboardChipPressed(_ sender: PinboardChipButton) {
        applyInteractionAction(.setPinboardFilter(sender.pinboardID))
    }

    private func toggleSearchField() {
        applyInteractionAction(.toggleSearch)
    }

    private func resetItemLayoutTracking() {
        itemWidthConstraints.removeAll()
        itemHeightConstraints.removeAll()
        itemPreviewHeightConstraints.removeAll()
        itemPreviewWidthConstraints.removeAll()
        itemImagePreviewViews.removeAll()
        itemBodyLabels.removeAll()
    }

    private func renderItemCards(_ cards: [NSView]) {
        renderedCardStatesByID.removeAll()
        itemBandStack.arrangedSubviews.forEach { view in
            itemBandStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        cards.forEach { itemBandStack.addArrangedSubview($0) }

        let itemSide = itemSideLength(for: currentPanelHeight)
        itemBandDocumentView.frame = NSRect(
            x: 0,
            y: 0,
            width: itemBandDocumentWidth(itemSide: itemSide),
            height: itemSide
        )
        updatePanelHeight(currentPanelHeight)
        refreshVisibleCommandHints()
    }

    private func makeEmptyHistoryCard() -> NSView {
        renderCard(
            statusCardState(
                sourceAppName: "暂无剪贴板记录",
                symbolName: "tray",
                typeText: "空态",
                summaryText: "复制内容后会显示在这里"
            )
        )
    }

    private func makeDatabaseErrorCard() -> NSView {
        renderCard(
            statusCardState(
                sourceAppName: "数据库不可用",
                relativeTimeText: "可重试",
                symbolName: "exclamationmark.triangle",
                typeText: "错误",
                summaryText: "本地历史暂时无法读取"
            )
        )
    }

    private func makeNoResultsCard() -> NSView {
        renderCard(
            statusCardState(
                sourceAppName: "没有匹配结果",
                symbolName: "magnifyingglass",
                typeText: "空态",
                summaryText: "换个关键词或回到剪贴板"
            )
        )
    }

    private func makeItemCard(_ item: RustClipboardItemSummary) -> NSView {
        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: panelViewState().selectedItemID
        )
        return renderCard(
            state,
            toolTip: "单击选中，双击复制到剪贴板，右键管理",
            onSelect: { [weak self] in
                self?.applyInteractionAction(.selectItem(id: item.id, scrollIntoView: true))
            },
            onDoubleClick: { [weak self] in
                self?.applyInteractionAction(.copyItem(itemID: item.id))
            },
            onContextMenu: { [weak self] event in
                self?.showManagementMenu(for: item, event: event)
            }
        )
    }

    private func renderCard(
        _ state: PanelItemCardViewState,
        toolTip: String? = nil,
        onSelect: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onContextMenu: ((NSEvent) -> Void)? = nil
    ) -> NSView {
        if let itemID = state.itemID {
            renderedCardStatesByID[itemID] = state
        }
        let renderedCard = cardRenderer().render(
            state,
            toolTip: toolTip,
            onSelect: onSelect,
            onDoubleClick: onDoubleClick,
            onContextMenu: onContextMenu
        )
        registerRenderedCardArtifacts(renderedCard.artifacts)
        return renderedCard.view
    }

    private func registerRenderedCardArtifacts(_ artifacts: PanelItemCardRenderArtifacts) {
        itemWidthConstraints.append(artifacts.itemWidthConstraint)
        itemHeightConstraints.append(artifacts.itemHeightConstraint)
        itemPreviewHeightConstraints.append(contentsOf: artifacts.previewHeightConstraints)
        itemPreviewWidthConstraints.append(contentsOf: artifacts.previewWidthConstraints)
        itemImagePreviewViews.append(contentsOf: artifacts.imagePreviewViews)
        itemBodyLabels.append(contentsOf: artifacts.bodyLabels)
    }

    private func cardRenderer() -> PanelItemCardRenderer {
        PanelItemCardRenderer(
            cardAssetResolver: cardAssetResolver,
            metrics: PanelItemCardRendererMetrics(
                defaultItemSide: Layout.defaultItemSide,
                cardCornerRadius: Layout.cardCornerRadius,
                innerCornerRadius: Layout.innerCornerRadius,
                cardHeaderHeight: Layout.cardHeaderHeight,
                cardInset: Layout.cardInset,
                cardFooterHeight: Layout.cardFooterHeight,
                sourceIconSize: Layout.sourceIconSize,
                linkPreviewHeight: Layout.linkPreviewHeight,
                theme: theme
            ),
            backingScaleFactor: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        )
    }

    private func statusCardState(
        itemID: String? = nil,
        sourceAppName: String,
        relativeTimeText: String = "",
        symbolName: String,
        typeText: String,
        summaryText: String
    ) -> PanelItemCardViewState {
        PanelItemCardViewState(
            itemID: itemID,
            sourceAppName: sourceAppName,
            relativeTimeText: relativeTimeText,
            symbolName: symbolName,
            typeText: typeText,
            summaryText: summaryText,
            footnoteText: "",
            isSelected: true,
            preview: .none,
            assetRequest: PanelCardAssetRequest()
        )
    }

    private func makeToolbarIconButton(
        symbolName: String,
        accessibilityLabel: String,
        onPress: @escaping () -> Void
    ) -> PanelActionButton {
        let button = PanelActionButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: symbolName == "plus" ? 18 : 16,
                weight: .regular
            ))
        button.imageScaling = .scaleProportionallyDown
        button.target = nil
        button.action = nil
        button.onPress = onPress
        button.toolTip = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.contentTintColor = theme.panel.toolbarIconColor
        button.layer?.cornerRadius = 14
        button.layer?.backgroundColor = NSColor.clear.cgColor
        toolbarIconButtons.append(button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])

        return button
    }

    private func makePinboardChip(
        title: String,
        pinboardID: String? = nil,
        dotColor: NSColor
    ) -> PinboardChipButton {
        let button = PinboardChipButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.target = nil
        button.action = nil
        button.pinboardID = pinboardID
        button.chipTitleText = title
        button.chipDotColor = dotColor
        button.chipSymbolName = pinboardID == nil ? "clock.arrow.circlepath" : nil
        button.chipDrawsSelectionPill = true
        button.chipHeight = 28
        button.chipFontSize = 14
        button.chipDotDiameter = 11
        button.chipIconSide = 16
        button.chipMarkerTextSpacing = 6
        button.chipHorizontalPadding = pinboardID == nil ? 11 : 9
        button.onPress = { [weak self, weak button] in
            guard let button else { return }
            self?.pinboardChipPressed(button)
        }
        button.onContextMenu = { [weak self, weak button] event in
            guard let self,
                  let button,
                  let pinboardID = button.pinboardID,
                  let pinboard = self.pinboardFilters.first(where: { $0.id == pinboardID })
            else { return }
            let menu = self.makePinboardChipManagementMenu(for: pinboard)
            menu.popUp(
                positioning: nil,
                at: button.convert(event.locationInWindow, from: nil),
                in: button
            )
        }
        button.toolTip = pinboardID != nil
            ? "查看固定内容，右键管理"
            : "剪贴板历史"
        button.alignment = .center
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = Layout.chipCornerRadius
        button.layer?.borderWidth = 0
        button.setButtonType(.momentaryChange)
        button.attributedTitle = NSAttributedString(string: "")
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: pinboardID == nil ? 88 : 40)
        ])

        return button
    }

    private func updatePinboardChipAppearance() {
        let selectedPinboardID = panelViewState().toolbar.selectedPinboardID
        pinboardButtons.forEach { button in
            let isSelected = button.pinboardID != nil
                ? button.pinboardID == selectedPinboardID
                : selectedPinboardID == nil
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderWidth = 0
            button.layer?.shadowOpacity = 0
            button.chipIsSelected = isSelected
            button.chipTextColor = theme.panel.toolbarTextColor
            button.chipSelectedTextColor = theme.panel.toolbarSelectedTextColor
            button.chipSelectedBackgroundColor = theme.panel.toolbarSelectedBackgroundColor
            button.needsDisplay = true
        }
    }

}

@MainActor
extension FloatingPanelContentView {
    var smokeSelectedItemID: String? {
        panelViewState().selectedItemID
    }

    func smokePanelUsesLightBlurredBackground() -> Bool {
        switch backgroundHostState {
        case .systemGlass(let tintAlpha), .legacyVisualEffect(let tintAlpha):
            return tintAlpha >= 0.30
        case .none:
            return false
        }
    }

    func smokePanelUsesSystemGlassWhenAvailable() -> Bool {
        if #available(macOS 26.0, *) {
            if case .systemGlass = backgroundHostState {
                return true
            }
            return false
        }
        return true
    }

    var smokeSearchField: NSSearchField {
        searchField
    }

    func smokeCardBoxes() -> [ClipboardItemCardBox] {
        allSmokeSubviews(of: self)
            .compactMap { $0 as? ClipboardItemCardBox }
            .filter { $0.itemID != nil }
    }

    func smokePinboardFilterButton(pinboardID: String) -> PinboardChipButton? {
        pinboardButtons.first { $0.pinboardID == pinboardID }
    }

    func smokePinboardChipAllowsLongIntrinsicWidth() -> Bool {
        let shortButton = makePinboardChip(title: "AI", pinboardID: "smoke-short-chip", dotColor: .systemRed)
        let longButton = makePinboardChip(
            title: "一个很长的 Pinboard 名称用于验证 chip 不截断",
            pinboardID: "smoke-long-chip",
            dotColor: .systemBlue
        )
        let widthConstraints = longButton.constraints.filter { constraint in
            constraint.firstAttribute == .width || constraint.secondAttribute == .width
        }

        return longButton.intrinsicContentSize.width > shortButton.intrinsicContentSize.width * 3
            && widthConstraints.allSatisfy { $0.relation == .greaterThanOrEqual }
    }

    func smokeEmptyDefaultPinboardIsHidden() -> Bool {
        let previousPinboards = pinboardFilters
        defer {
            pinboardFilters = previousPinboards
            rebuildFilterChips()
        }

        updatePinboards([
            RustPinboardSummary(
                id: DefaultPinboard.defaultID,
                title: DefaultPinboard.defaultTitle,
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 0,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])

        return pinboardFilters.isEmpty
            && pinboardButtons.allSatisfy { $0.pinboardID != DefaultPinboard.defaultID }
    }

    func smokeHorizontalScrollView() -> HorizontalWheelScrollView? {
        allSmokeSubviews(of: self)
            .compactMap { $0 as? HorizontalWheelScrollView }
            .first
    }

    var smokeCurrentItemCount: Int {
        currentItems().count
    }

    var smokeIsLoadingMoreActive: Bool {
        interactionController.isLoadingMoreItems
    }

    func smokeScrollToLoadMoreThreshold() {
        guard let scrollView = itemBandScrollView else { return }

        layoutSubtreeIfNeeded()
        itemBandDocumentView.layoutSubtreeIfNeeded()
        let maxX = max(0, itemBandDocumentView.frame.width - scrollView.contentView.bounds.width)
        scrollView.contentView.scroll(to: NSPoint(x: maxX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        handleItemBandScrollDidChange()
    }

    func smokeFirstCardSize(afterPanelHeight panelHeight: CGFloat) -> CGSize? {
        updatePanelHeight(panelHeight)
        layoutSubtreeIfNeeded()
        itemBandDocumentView.layoutSubtreeIfNeeded()
        return smokeCardBoxes().first?.frame.size
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

    var smokePreviewScreenFrame: NSRect? {
        previewPopoverController.screenFrame
    }

    func smokePreviewActionButtonToolTips() -> [String] {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return [] }
        return allSmokeSubviews(of: rootView)
            .compactMap { $0 as? NSButton }
            .compactMap(\.toolTip)
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
        guard let item = currentItems().first(where: { $0.id == itemID }) else { return false }
        let menu = makeManagementMenu(for: item)
        guard let actionItem = actionMenuItem(in: menu, title: title) else {
            return false
        }

        actionItem.triggerForSmoke()
        return true
    }

    func smokeManagementMenuItems(itemID: String) -> [
        (title: String, keyEquivalent: String, modifiers: NSEvent.ModifierFlags, hasImage: Bool, hasSubmenu: Bool, isEnabled: Bool)
    ] {
        guard let item = currentItems().first(where: { $0.id == itemID }) else { return [] }
        return makeManagementMenu(for: item).items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                keyEquivalent: menuItem.keyEquivalent,
                modifiers: menuItem.keyEquivalentModifierMask,
                hasImage: menuItem.image != nil,
                hasSubmenu: menuItem.submenu != nil,
                isEnabled: menuItem.isEnabled
            )
        }
    }

    func smokeManagementSubmenuItems(itemID: String, title: String) -> [(title: String, isEnabled: Bool, isSelected: Bool)] {
        guard let item = currentItems().first(where: { $0.id == itemID }) else { return [] }
        guard let submenu = makeManagementMenu(for: item).items.first(where: { $0.title == title })?.submenu else {
            return []
        }

        return submenu.items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                isEnabled: menuItem.isEnabled,
                isSelected: menuItem.state == .on
            )
        }
    }

    func smokeManagementPinboardMenuWithNoPinboards(itemID: String) -> (isEnabled: Bool, titles: [String])? {
        guard let item = currentItems().first(where: { $0.id == itemID }) else { return nil }
        let previousPinboards = pinboardFilters
        pinboardFilters = []
        defer { pinboardFilters = previousPinboards }

        guard let pinboardMenuItem = makeManagementMenu(for: item)
            .items
            .first(where: { $0.title == "固定" })
        else {
            return nil
        }

        let titles = pinboardMenuItem.submenu?.items.compactMap { item in
            item.isSeparatorItem ? nil : item.title
        } ?? []
        return (isEnabled: pinboardMenuItem.isEnabled, titles: titles)
    }

    func smokePinboardDeleteRequiresConfirmation(pinboardID: String) -> Bool? {
        pinboardFilters
            .first { $0.id == pinboardID }
            .map(pinboardDeletionRequiresConfirmation)
    }

    func smokeNonEmptyPinboardDeleteRequiresConfirmation() -> Bool {
        pinboardDeletionRequiresConfirmation(PinboardFilterEntry(
            id: "smoke-non-empty",
            title: "非空",
            colorCode: 4_293_940_557,
            itemCount: 1
        ))
    }

    func smokeCreatePinboardAction() -> (title: String, colorCode: Int64)? {
        let previousAction = onRuntimeAction
        let previousPendingIDs = pendingCreatedPinboardSourceIDs
        var capturedAction: PanelRuntimeAction?
        onRuntimeAction = { action in
            capturedAction = action
        }
        showCreatePinboardDialog()
        onRuntimeAction = previousAction
        pendingCreatedPinboardSourceIDs = previousPendingIDs

        guard case .createPinboard(let title, let colorCode) = capturedAction else {
            return nil
        }
        return (title, colorCode)
    }

    func smokeCreatedPinboardStartsInlineRename() -> Bool {
        let previousAction = onRuntimeAction
        let previousPendingIDs = pendingCreatedPinboardSourceIDs
        let previousSelectedPinboardID = panelViewState().toolbar.selectedPinboardID
        let previousSummaries = pinboardFilters.enumerated().map { index, pinboard in
            RustPinboardSummary(
                id: pinboard.id,
                title: pinboard.title,
                colorCode: pinboard.colorCode,
                sortOrder: Int64(index + 1),
                itemCount: pinboard.itemCount,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        }

        let createdPinboardID = "smoke-created-pinboard"
        var nextSummaries = previousSummaries
        nextSummaries.append(RustPinboardSummary(
            id: createdPinboardID,
            title: "未命名",
            colorCode: 4_279_606_035,
            sortOrder: Int64(nextSummaries.count + 1),
            itemCount: 0,
            createdAtMs: 0,
            updatedAtMs: 0
        ))

        onRuntimeAction = { _ in }
        cancelInlinePinboardRename()
        pendingCreatedPinboardSourceIDs = Set(pinboardFilters.map(\.id))
        updatePinboards(nextSummaries)

        let isInline = activeRenamePinboardID == createdPinboardID
            && activeRenameField?.superview != nil

        cancelInlinePinboardRename()
        updatePinboards(previousSummaries)
        pendingCreatedPinboardSourceIDs = previousPendingIDs
        applyInteractionAction(.setPinboardFilter(previousSelectedPinboardID))
        onRuntimeAction = previousAction
        return isInline
    }

    func smokePinboardRenameUsesInlineEditor(pinboardID: String) -> Bool {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }) else { return false }
        showRenamePinboardDialog(for: pinboard)
        let chipContainsEditor = pinboardButtons
            .first { $0.pinboardID == pinboardID }?
            .subviews
            .contains { $0 is NSTextField } == true
        let isInline = activeRenamePinboardID == pinboardID
            && (activeRenameField?.superview != nil || chipContainsEditor)
        cancelInlinePinboardRename()
        return isInline
    }

    func smokePinboardRenameCommitsOnFocusLoss(pinboardID: String) -> Bool {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }),
              let button = pinboardButtons.first(where: { $0.pinboardID == pinboardID })
        else { return false }

        let previousAction = onRuntimeAction
        let previousTitle = button.chipTitleText
        let nextTitle = "失焦自动保存"
        var capturedRename: (pinboardID: String, title: String)?
        onRuntimeAction = { action in
            if case .renamePinboard(let capturedPinboardID, let capturedTitle) = action {
                capturedRename = (capturedPinboardID, capturedTitle)
            }
        }
        defer {
            cancelInlinePinboardRename()
            button.chipTitleText = previousTitle
            button.invalidateIntrinsicContentSize()
            onRuntimeAction = previousAction
        }

        showRenamePinboardDialog(for: pinboard)
        guard let field = activeRenameField else { return false }
        isInstallingRenameField = false
        field.stringValue = nextTitle
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))

        return capturedRename?.pinboardID == pinboardID
            && capturedRename?.title == nextTitle
            && activeRenameField == nil
    }

    func smokePinboardRenameResizesWhileTyping(pinboardID: String) -> Bool {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }),
              let button = pinboardButtons.first(where: { $0.pinboardID == pinboardID })
        else { return false }

        showRenamePinboardDialog(for: pinboard)
        guard let field = activeRenameField else { return false }
        isInstallingRenameField = false

        field.stringValue = "一个很长的 Pinboard 输入中实时扩展"
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let longWidth = button.intrinsicContentSize.width

        field.stringValue = "短"
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let shortWidth = button.intrinsicContentSize.width

        cancelInlinePinboardRename()
        return longWidth > shortWidth + 120
            && shortWidth >= 40
    }

    func smokePinboardRenameCommitsBeforeInternalPanelClick(pinboardID: String) -> Bool {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }),
              let window
        else { return false }

        let previousAction = onRuntimeAction
        let nextTitle = "点击面板保存"
        var capturedRename: (pinboardID: String, title: String)?
        onRuntimeAction = { action in
            if case .renamePinboard(let capturedPinboardID, let capturedTitle) = action {
                capturedRename = (capturedPinboardID, capturedTitle)
            }
        }
        defer {
            cancelInlinePinboardRename()
            onRuntimeAction = previousAction
        }

        showRenamePinboardDialog(for: pinboard)
        guard let field = activeRenameField else { return false }
        isInstallingRenameField = false
        field.stringValue = nextTitle
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))

        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: bounds.midX, y: bounds.midY),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else { return false }

        commitInlinePinboardRenameBeforePanelMouseDown(event)
        return capturedRename?.pinboardID == pinboardID
            && capturedRename?.title == nextTitle
            && activeRenameField == nil
    }

    func smokeShowPinboardChipMenu(pinboardID: String) -> Bool {
        guard let button = pinboardButtons.first(where: { $0.pinboardID == pinboardID }),
              let pinboard = pinboardFilters.first(where: { $0.id == pinboardID })
        else { return false }

        makePinboardChipManagementMenu(for: pinboard)
            .popUp(positioning: nil, at: NSPoint(x: button.bounds.midX, y: button.bounds.midY), in: button)
        return true
    }

    func smokeBeginPinboardRenameForScreenshot(pinboardID: String) -> Bool {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }) else { return false }
        showRenamePinboardDialog(for: pinboard)
        return activeRenamePinboardID == pinboardID
            && activeRenameField?.superview != nil
    }

    func smokeSetActivePinboardRenameTextForScreenshot(_ text: String) -> Bool {
        guard let field = activeRenameField else { return false }
        field.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        return true
    }

    func smokeShowPinboardDeleteConfirmationForScreenshot(pinboardID: String) -> Bool {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }) else { return false }
        confirmDeletePinboard(pinboard)
        return true
    }

    func smokeToolbarButtonToolTips() -> [String] {
        allSmokeSubviews(of: self)
            .compactMap { ($0 as? PanelActionButton)?.toolTip }
    }

    func smokePanelOverflowMenuItems() -> [(title: String, isEnabled: Bool, hasSubmenu: Bool, hasCustomView: Bool)] {
        makePanelOverflowMenu().items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                isEnabled: menuItem.isEnabled,
                hasSubmenu: menuItem.submenu != nil,
                hasCustomView: menuItem.view != nil
            )
        }
    }

    func smokePinboardChipMenuItems(pinboardID: String) -> [(title: String, isEnabled: Bool, hasSubmenu: Bool, hasCustomView: Bool)] {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }) else { return [] }
        return makePinboardChipManagementMenu(for: pinboard).items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                isEnabled: menuItem.isEnabled,
                hasSubmenu: menuItem.submenu != nil,
                hasCustomView: menuItem.view != nil
            )
        }
    }

    func smokePinboardChipColorMenuItems(pinboardID: String) -> [(title: String, isEnabled: Bool, isSelected: Bool)] {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }),
              let colorRow = makePinboardChipManagementMenu(for: pinboard)
                .items
                .first(where: { $0.title == "颜色" })?
                .view as? PinboardColorSwatchRowView
        else {
            return []
        }

        return colorRow.smokeColorItems().map { item in
            return (
                title: item.title,
                isEnabled: true,
                isSelected: item.isSelected
            )
        }
    }

    private func actionMenuItem(in menu: NSMenu, title: String) -> ActionMenuItem? {
        for menuItem in menu.items {
            if let actionItem = menuItem as? ActionMenuItem, actionItem.title == title {
                return actionItem
            }
            if let submenu = menuItem.submenu,
               let actionItem = actionMenuItem(in: submenu, title: title) {
                return actionItem
            }
        }
        return nil
    }

    private func allSmokeSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSmokeSubviews(of:))
    }
}
