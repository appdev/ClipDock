import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipboardPanelApp
import Darwin
import ServiceManagement

final class FloatingPanelContentView: NSVisualEffectView, NSSearchFieldDelegate {
    var onRuntimeAction: ((PanelRuntimeAction) -> Void)?
    var onHeightResizeBegan: (() -> Void)?
    var onHeightResizeChanged: ((CGFloat) -> Void)?

    private enum Layout {
        static let padding: CGFloat = 22
        static let resizeHandleHeight: CGFloat = 16
        static let controlBarHeight: CGFloat = 44
        static let sectionSpacing: CGFloat = 0
        static let defaultItemSide: CGFloat = 218
        static let compactItemSide: CGFloat = 156
        static let imagePreviewMinHeight: CGFloat = 78
        static let imagePreviewMaxHeight: CGFloat = 116
        static let scrollEdgeInset: CGFloat = 2
        static let panelCornerRadius: CGFloat = 18
        static let cardCornerRadius: CGFloat = 10
        static let innerCornerRadius: CGFloat = 8
        static let chipCornerRadius: CGFloat = 6
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
        PinboardColorOption(title: "黄色", colorCode: 4_294_620_928),
        PinboardColorOption(title: "紫色", colorCode: 4_290_925_536),
        PinboardColorOption(title: "绿色", colorCode: 4_279_606_035),
        PinboardColorOption(title: "蓝色", colorCode: 4_283_973_119),
        PinboardColorOption(title: "橙色", colorCode: 4_293_088_528),
        PinboardColorOption(title: "灰色", colorCode: 4_284_242_835)
    ]

    private struct PinboardFilterEntry: Equatable {
        let id: String
        let title: String
        let colorCode: Int64
        let itemCount: Int64
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
    private var pinboardFilters = [
        PinboardFilterEntry(
            id: DefaultPinboard.defaultID,
            title: DefaultPinboard.defaultTitle,
            colorCode: 4_293_940_557,
            itemCount: 0
        )
    ]
    private var searchFieldWidthConstraint: NSLayoutConstraint?
    private weak var filterRow: NSStackView?
    private var appSupportDirectory: URL?
    private let interactionController = PanelInteractionController()
    private var commandHintMonitor: Any?
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

    func updateStorageState(_ result: Result<RustCoreOpenResult, RustCoreError>) {
        applyRenderPlan(interactionController.updateStorageState(result))
    }

    func updateAppSupportDirectory(_ url: URL) {
        appSupportDirectory = url
    }

    func updatePinboards(_ pinboards: [RustPinboardSummary]) {
        let nextFilters = pinboards.map { pinboard in
            PinboardFilterEntry(
                id: pinboard.id,
                title: pinboard.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "未命名"
                    : pinboard.title,
                colorCode: pinboard.colorCode,
                itemCount: pinboard.itemCount
            )
        }
        guard nextFilters != pinboardFilters else { return }

        pinboardFilters = nextFilters
        rebuildFilterChips()
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
            panelHeight - Layout.resizeHandleHeight - Layout.controlBarHeight - Layout.sectionSpacing - Layout.padding
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
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Layout.panelCornerRadius
        layer?.masksToBounds = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        applyTheme()
    }

    private func applyTheme() {
        let theme = theme
        layer?.backgroundColor = theme.panel.backgroundColor.cgColor
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
            controlBar.topAnchor.constraint(equalTo: resizeHandle.bottomAnchor),
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
        row.spacing = 13
        row.userInterfaceLayoutDirection = NSUserInterfaceLayoutDirection.leftToRight
        row.translatesAutoresizingMaskIntoConstraints = false
        filterRow = row

        let moreButton = makeToolbarIconButton(
            symbolName: "ellipsis",
            accessibilityLabel: "管理 Pinboard"
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
            searchField.heightAnchor.constraint(equalToConstant: 28),

            moreButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            moreButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
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
        menu.addItem(ActionMenuItem(title: "创建 Pinboard…", imageName: "plus") { [weak self] in
            self?.showCreatePinboardDialog()
        })

        let selectedPinboard = selectedPinboardEntry()
        let renameItem = ActionMenuItem(title: "重命名 Pinboard…", imageName: "pencil") { [weak self] in
            self?.showRenamePinboardDialog()
        }
        renameItem.isEnabled = selectedPinboard != nil
        menu.addItem(renameItem)

        let colorItem = NSMenuItem(title: "颜色", action: nil, keyEquivalent: "")
        colorItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "颜色")
        colorItem.submenu = makePinboardColorMenu(for: selectedPinboard)
        colorItem.isEnabled = selectedPinboard != nil
        menu.addItem(colorItem)

        let deleteItem = ActionMenuItem(title: "删除 Pinboard…", imageName: "trash") { [weak self] in
            self?.confirmDeleteSelectedPinboard()
        }
        deleteItem.isEnabled = selectedPinboard != nil
        menu.addItem(deleteItem)
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

    private func makePinboardColorMenu(for pinboard: PinboardFilterEntry?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for option in Self.pinboardColorOptions {
            let item = ActionMenuItem(title: option.title) { [weak self] in
                guard let pinboard else { return }
                self?.onRuntimeAction?(.updatePinboardColor(
                    pinboardID: pinboard.id,
                    colorCode: option.colorCode
                ))
            }
            item.image = pinboardMenuDotImage(colorCode: option.colorCode)
            item.state = pinboard?.colorCode == option.colorCode ? .on : .off
            item.isEnabled = pinboard != nil
            menu.addItem(item)
        }
        return menu
    }

    private func makePinboardChipManagementMenu(for pinboard: PinboardFilterEntry) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: "重命名 Pinboard…", imageName: "pencil") { [weak self] in
            self?.showRenamePinboardDialog(for: pinboard)
        })

        let colorItem = NSMenuItem(title: "颜色", action: nil, keyEquivalent: "")
        colorItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "颜色")
        colorItem.submenu = makePinboardColorMenu(for: pinboard)
        menu.addItem(colorItem)

        menu.addItem(ActionMenuItem(title: "删除 Pinboard…", imageName: "trash") { [weak self] in
            self?.confirmDeletePinboard(pinboard)
        })
        return menu
    }

    private func showCreatePinboardDialog() {
        guard let window else { return }
        let colorOption = Self.pinboardColorOptions[pinboardFilters.count % Self.pinboardColorOptions.count]
        showPinboardTextDialog(
            title: "创建 Pinboard",
            informativeText: "输入新 Pinboard 名称。",
            placeholder: "未命名",
            initialValue: ""
        ) { [weak self] title in
            self?.onRuntimeAction?(.createPinboard(title: title, colorCode: colorOption.colorCode))
        }
        window.makeFirstResponder(self)
    }

    private func showRenamePinboardDialog(for explicitPinboard: PinboardFilterEntry? = nil) {
        guard let pinboard = explicitPinboard ?? selectedPinboardEntry(),
              let window
        else { return }
        showPinboardTextDialog(
            title: "重命名 Pinboard",
            informativeText: "输入新的 Pinboard 名称。",
            placeholder: "未命名",
            initialValue: pinboard.title
        ) { [weak self] title in
            self?.onRuntimeAction?(.renamePinboard(pinboardID: pinboard.id, title: title))
        }
        window.makeFirstResponder(self)
    }

    private func showPinboardTextDialog(
        title: String,
        informativeText: String,
        placeholder: String,
        initialValue: String,
        onConfirm: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informativeText
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = placeholder
        textField.stringValue = initialValue
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let normalizedTitle = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onConfirm(normalizedTitle.isEmpty ? placeholder : normalizedTitle)
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
        itemBandStack.spacing = 13
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

        menuItem.submenu = submenu
        menuItem.isEnabled = !pinboardFilters.isEmpty
        return menuItem
    }

    private func pinboardMenuDotImage(colorCode: Int64) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        pinboardDotColor(colorCode: colorCode).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10)).fill()
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
        applyInteractionAction(.setSearchText(searchField.stringValue))
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
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
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
            button.widthAnchor.constraint(equalToConstant: 25),
            button.heightAnchor.constraint(equalToConstant: 25)
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
        button.attributedTitle = chipTitle(title, dotColor: dotColor)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: pinboardID == nil ? 28 : 24),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: pinboardID == nil ? 70 : 45)
        ])

        return button
    }

    private func updatePinboardChipAppearance() {
        let selectedPinboardID = panelViewState().toolbar.selectedPinboardID
        pinboardButtons.forEach { button in
            let isSelected = button.pinboardID != nil
                ? button.pinboardID == selectedPinboardID
                : selectedPinboardID == nil
            button.layer?.backgroundColor = isSelected && button.pinboardID == nil
                ? theme.panel.toolbarSelectedBackgroundColor.cgColor
                : NSColor.clear.cgColor
            button.layer?.borderWidth = 0
            button.layer?.shadowOpacity = 0
            button.attributedTitle = chipTitle(
                button.chipTitleText,
                dotColor: button.chipDotColor,
                isSelected: isSelected
            )
        }
    }

    private func chipTitle(
        _ title: String,
        dotColor: NSColor,
        isSelected: Bool = false
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.baseWritingDirection = .leftToRight
        let selectedTextColor = dotColor == .clear
            ? theme.panel.toolbarSelectedTextColor
            : theme.panel.toolbarTextColor.withAlphaComponent(0.92)
        let textColor = isSelected ? selectedTextColor : theme.panel.toolbarTextColor
        if dotColor != .clear {
            result.append(NSAttributedString(
                string: "● ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold),
                    .foregroundColor: dotColor,
                    .paragraphStyle: paragraph
                ]
            ))
        }
        result.append(NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        ))
        return result
    }

}

@MainActor
extension FloatingPanelContentView {
    var smokeSelectedItemID: String? {
        panelViewState().selectedItemID
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

    func smokeToolbarButtonToolTips() -> [String] {
        allSmokeSubviews(of: self)
            .compactMap { ($0 as? PanelActionButton)?.toolTip }
    }

    func smokePanelOverflowMenuItems() -> [(title: String, isEnabled: Bool, hasSubmenu: Bool)] {
        makePanelOverflowMenu().items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                isEnabled: menuItem.isEnabled,
                hasSubmenu: menuItem.submenu != nil
            )
        }
    }

    func smokePinboardChipMenuItems(pinboardID: String) -> [(title: String, isEnabled: Bool, hasSubmenu: Bool)] {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }) else { return [] }
        return makePinboardChipManagementMenu(for: pinboard).items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                isEnabled: menuItem.isEnabled,
                hasSubmenu: menuItem.submenu != nil
            )
        }
    }

    func smokePinboardChipColorMenuItems(pinboardID: String) -> [(title: String, isEnabled: Bool, isSelected: Bool)] {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }),
              let submenu = makePinboardChipManagementMenu(for: pinboard)
                .items
                .first(where: { $0.title == "颜色" })?
                .submenu
        else {
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
