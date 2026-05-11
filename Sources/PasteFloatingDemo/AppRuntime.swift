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
    private var typeFilterButtons: [TypeFilterChipButton] = []
    private var toolbarIconButtons: [PanelActionButton] = []
    private var searchFieldWidthConstraint: NSLayoutConstraint?
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
        updateTypeFilterChipAppearance()
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
            self?.applyInteractionAction(.clearFilters)
        }

        let row = NSStackView(views: [searchButton, searchField] + chips + [addButton])
        row.orientation = NSUserInterfaceLayoutOrientation.horizontal
        row.alignment = NSLayoutConstraint.Attribute.centerY
        row.spacing = 13
        row.userInterfaceLayoutDirection = NSUserInterfaceLayoutDirection.leftToRight
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
            searchField.heightAnchor.constraint(equalToConstant: 28),

            moreButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            moreButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func showPanelOverflowMenu() {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "偏好设置…", imageName: "gearshape") { [weak self] in
            self?.onRuntimeAction?(.showPreferences)
        })
        menu.addItem(ActionMenuItem(title: "隐藏面板", imageName: "eye.slash") { [weak self] in
            self?.applyInteractionAction(.hidePanel)
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
        updateTypeFilterChipAppearance()
    }

    private func emitRuntimeAction(_ action: PanelExternalAction) {
        switch action {
        case .queryChanged(let searchText, let itemType, let sourceAppID):
            onRuntimeAction?(.queryChanged(
                searchText: searchText,
                itemType: itemType,
                sourceAppID: sourceAppID
            ))
        case .copyItem(let itemID):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.copyItem(item))
        case .setPinned(let itemID, let isPinned):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.setPinned(item, isPinned: isPinned))
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
        menu.addItem(ActionMenuItem(title: "复制", keyEquivalent: "c", modifierMask: [.command]) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .copy))
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "删除", keyEquivalent: "\u{8}", modifierMask: []) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .delete))
        })
        menu.addItem(.separator())
        let pinTitle = item.isPinned ? "取消固定" : "固定"
        menu.addItem(ActionMenuItem(title: pinTitle) { [weak self] in
            self?.applyInteractionAction(.management(
                itemID: item.id,
                action: .togglePinned(isCurrentlyPinned: item.isPinned)
            ))
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "预览", keyEquivalent: " ", modifierMask: []) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .preview))
        })
        return menu
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

    private func typeFilterChipPressed(_ sender: TypeFilterChipButton) {
        applyInteractionAction(.setTypeFilter(sender.itemType))
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
                summaryText: "换个关键词或切回全部类型"
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
        button.chipTitleText = title
        button.chipDotColor = dotColor
        button.onPress = { [weak self, weak button] in
            guard let button else { return }
            self?.typeFilterChipPressed(button)
        }
        button.toolTip = itemType == nil ? "全部类型" : "仅显示\(title)"
        button.alignment = .center
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = Layout.chipCornerRadius
        button.layer?.borderWidth = 0
        button.setButtonType(.momentaryChange)
        button.attributedTitle = chipTitle(title, dotColor: dotColor)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: itemType == nil ? 28 : 24),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: itemType == nil ? 70 : 45)
        ])

        return button
    }

    private func updateTypeFilterChipAppearance() {
        let selectedItemType = panelViewState().toolbar.selectedItemType
        typeFilterButtons.forEach { button in
            let isSelected = button.itemType == selectedItemType
            button.layer?.backgroundColor = isSelected && button.itemType == nil
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

    func smokeTypeFilterButton(itemType: String?) -> TypeFilterChipButton? {
        typeFilterButtons.first { $0.itemType == itemType }
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
        guard let actionItem = menu.items
            .compactMap({ $0 as? ActionMenuItem })
            .first(where: { $0.title == title })
        else {
            return false
        }

        actionItem.triggerForSmoke()
        return true
    }

    func smokeManagementMenuItems(itemID: String) -> [(title: String, keyEquivalent: String, modifiers: NSEvent.ModifierFlags, hasImage: Bool)] {
        guard let item = currentItems().first(where: { $0.id == itemID }) else { return [] }
        return makeManagementMenu(for: item).items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                keyEquivalent: menuItem.keyEquivalent,
                modifiers: menuItem.keyEquivalentModifierMask,
                hasImage: menuItem.image != nil
            )
        }
    }

    private func allSmokeSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSmokeSubviews(of:))
    }
}
