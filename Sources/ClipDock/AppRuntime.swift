import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipboardPanelApp
import Darwin
import QuickLookUI
import ServiceManagement
import WebKit

@MainActor
func makeFloatingPanelHostView(contentView: FloatingPanelContentView) -> NSView {
    let tintColor = ClipDockTheme.current(for: contentView).panel.backgroundColor
    let hostView: NSView

    if let glassView = makeSystemGlassPanelHostView(contentView: contentView) {
        hostView = glassView
        contentView.updateBackgroundHostState(.systemGlass)
    } else {
        let effectView = NSVisualEffectView(frame: contentView.frame)
        effectView.material = .popover
        effectView.blendingMode = .withinWindow
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

@MainActor
private func makeSystemGlassPanelHostView(
    contentView: FloatingPanelContentView
) -> NSView? {
    guard #available(macOS 26.0, *),
          let glassViewClass = NSClassFromString("NSGlassEffectView") as? NSView.Type
    else {
        return nil
    }

    let glassView = glassViewClass.init(frame: contentView.frame)
    setSystemGlassValue(NSNumber(value: 0), key: "style", on: glassView)
    setSystemGlassValue(
        NSNumber(value: Double(FloatingPanelContentView.panelBackgroundCornerRadius)),
        key: "cornerRadius",
        on: glassView
    )
    // A tinted NSGlassEffectView visibly changes when a keyable panel loses focus.
    // Leave tintColor unset so the panel keeps the stable no-tint glass appearance.

    if glassView.responds(to: Selector(("setContentView:"))) {
        glassView.setValue(contentView, forKey: "contentView")
    } else {
        glassView.addSubview(contentView)
    }

    return glassView
}

private func setSystemGlassValue(_ value: Any, key: String, on view: NSView) {
    let setterPrefix = String(key.prefix(1)).uppercased() + key.dropFirst()
    guard view.responds(to: Selector(("set\(setterPrefix):"))) else {
        return
    }

    view.setValue(value, forKey: key)
}

enum PanelTypeToSearchKeyPlanner {
    static func initialSearchText(for event: NSEvent) -> String? {
        initialSearchText(
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    static func initialSearchText(
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            return nil
        }

        guard let classificationText = charactersIgnoringModifiers,
              classificationText.isSinglePrintableNonSpaceGrapheme,
              let seedText = characters,
              seedText.isSinglePrintableNonSpaceGrapheme
        else {
            return nil
        }

        return seedText
    }
}

private extension String {
    var isSinglePrintableNonSpaceGrapheme: Bool {
        guard count == 1,
              !unicodeScalars.isEmpty
        else {
            return false
        }

        return unicodeScalars.allSatisfy { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
                && !(0xF700...0xF8FF).contains(Int(scalar.value))
        }
    }
}

final class PanelSearchField: NSSearchField {
    var onCancelButtonMouseDown: (() -> Bool)?
    var onCancelButtonClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let shouldHandleCancel = event.type == .leftMouseDown
            && isCancelButtonHit(event)
            && (onCancelButtonMouseDown?() ?? false)

        super.mouseDown(with: event)

        if shouldHandleCancel {
            onCancelButtonClick?()
        }
    }

    func isCancelButtonHit(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return cancelButtonBounds.contains(point)
    }

    func cancelButtonCenterInWindowForSmoke() -> NSPoint? {
        guard window != nil else { return nil }
        let rect = cancelButtonBounds
        guard !rect.isEmpty else { return nil }
        return convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    }
}

private final class SearchToolbarButton: PanelActionButton {
    var allowsSearchHitTesting = true

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard allowsSearchHitTesting,
              isEnabled,
              !isHidden,
              alphaValue > 0.01
        else {
            return nil
        }

        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard allowsSearchHitTesting else { return }
        super.mouseDown(with: event)
    }
}

private final class PanelSearchClearButton: NSButton {
    var onPress: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden,
              isEnabled,
              alphaValue > 0.01
        else {
            return nil
        }

        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onPress?()
    }
}

private final class PanelSearchBarView: NSView {
    private enum Metrics {
        static let leadingInset: CGFloat = 13
        static let iconSide: CGFloat = 17
        static let textLeading: CGFloat = 38
        static let textTrailing: CGFloat = 38
        static let textFieldHeight: CGFloat = 22
        static let clearSide: CGFloat = 18
        static let clearTrailing: CGFloat = 10
    }

    let searchField: PanelSearchField
    let leadingIconView = NSImageView()
    let clearButton = PanelSearchClearButton()
    var onActivateSearchField: (() -> Void)?
    var onClear: (() -> Void)?

    init(searchField: PanelSearchField) {
        self.searchField = searchField
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onActivateSearchField?()
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        leadingIconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        leadingIconView.imageScaling = .scaleProportionallyDown
        leadingIconView.translatesAutoresizingMaskIntoConstraints = false
        leadingIconView.setAccessibilityElement(false)

        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: AppLocalization.text("search.clear", defaultValue: "清除搜索")
        )?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.target = nil
        clearButton.action = nil
        clearButton.focusRingType = .none
        clearButton.toolTip = AppLocalization.text("search.clear", defaultValue: "清除搜索")
        clearButton.setAccessibilityLabel(AppLocalization.text("search.clear", defaultValue: "清除搜索"))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.onPress = { [weak self] in
            self?.onClear?()
        }

        addSubview(leadingIconView)
        addSubview(searchField)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            leadingIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.leadingInset),
            leadingIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingIconView.widthAnchor.constraint(equalToConstant: Metrics.iconSide),
            leadingIconView.heightAnchor.constraint(equalToConstant: Metrics.iconSide),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.clearTrailing),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: Metrics.clearSide),
            clearButton.heightAnchor.constraint(equalToConstant: Metrics.clearSide),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.textLeading),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.textTrailing),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: Metrics.textFieldHeight)
        ])
    }

    func applyTheme(_ theme: ClipDockThemePalette, isActive: Bool = false) {
        layer?.cornerRadius = 16
        layer?.backgroundColor = theme.panel.toolbarSelectedBackgroundColor
            .withAlphaComponent(theme.scheme == .dark ? 0.18 : 0.30)
            .cgColor
        if isActive {
            layer?.borderWidth = 2.5
            layer?.borderColor = NSColor.systemBlue.withAlphaComponent(theme.scheme == .dark ? 0.70 : 0.62).cgColor
        } else {
            layer?.borderWidth = 1
            layer?.borderColor = theme.panel.toolbarSelectedBorderColor
                .withAlphaComponent(theme.scheme == .dark ? 0.16 : 0.12)
                .cgColor
        }
        leadingIconView.contentTintColor = theme.panel.toolbarIconColor.withAlphaComponent(0.62)
        clearButton.contentTintColor = theme.panel.toolbarIconColor.withAlphaComponent(0.55)
    }

    func updateClearButton(hasText: Bool) {
        clearButton.isHidden = !hasText
        clearButton.isEnabled = hasText
        clearButton.alphaValue = hasText ? 1 : 0
    }

    var smokeCornerRadius: CGFloat {
        layer?.cornerRadius ?? 0
    }

    var smokeBackgroundAlpha: CGFloat {
        layer?.backgroundColor?.alpha ?? 0
    }

    var smokeBorderAlpha: CGFloat {
        layer?.borderColor?.alpha ?? 0
    }
}

final class FloatingPanelContentView: NSView, NSSearchFieldDelegate {
    static let panelBackgroundCornerRadius: CGFloat = 26

    enum BackgroundHostState {
        case none
        case systemGlass
        case legacyVisualEffect(tintAlpha: CGFloat)
    }

    var onRuntimeAction: ((PanelRuntimeAction) -> Void)?
    var onHeightResizeBegan: (() -> Void)?
    var onHeightResizeChanged: ((CGFloat) -> Void)?
    var onHeightResizeEnded: (() -> Void)?

    private enum Layout {
        static let padding: CGFloat = 22
        static let resizeHandleHeight: CGFloat = 16
        static let controlBarHeight: CGFloat = 52
        static let sectionSpacing: CGFloat = 12
        static let searchFieldWidth: CGFloat = 330
        static let searchSlotClosedWidth: CGFloat = 28
        static let searchFieldHeight: CGFloat = 32
        static let searchFieldAnimationDuration: TimeInterval = 0.15
        static let horizontalContentInset: CGFloat = 22
        static let defaultItemSide: CGFloat = 218
        static let compactItemSide: CGFloat = 156
        static let imagePreviewMinHeight: CGFloat = 78
        static let imagePreviewMaxHeight: CGFloat = 116
        static let panelCornerRadius: CGFloat = 18
        static let cardCornerRadius: CGFloat = 15
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
        static let defaultTitle = AppLocalization.text("pinboard.defaultTitle", defaultValue: "固定")
    }

    private struct PinboardColorOption: Equatable {
        let title: String
        let colorCode: Int64
    }

    private static let pinboardColorOptions: [PinboardColorOption] = [
        PinboardColorOption(title: AppLocalization.text("color.red", defaultValue: "红色"), colorCode: 4_293_940_557),
        PinboardColorOption(title: AppLocalization.text("color.orange", defaultValue: "橙色"), colorCode: 4_293_088_528),
        PinboardColorOption(title: AppLocalization.text("color.yellow", defaultValue: "黄色"), colorCode: 4_294_620_928),
        PinboardColorOption(title: AppLocalization.text("color.green", defaultValue: "绿色"), colorCode: 4_279_606_035),
        PinboardColorOption(title: AppLocalization.text("color.blue", defaultValue: "蓝色"), colorCode: 4_283_973_119),
        PinboardColorOption(title: AppLocalization.text("color.purple", defaultValue: "紫色"), colorCode: 4_290_925_536),
        PinboardColorOption(title: AppLocalization.text("color.pink", defaultValue: "粉色"), colorCode: 4_294_913_365),
        PinboardColorOption(title: AppLocalization.text("color.gray", defaultValue: "灰色"), colorCode: 9_408_403)
    ]

    private struct PinboardFilterEntry: Equatable {
        let id: String
        let title: String
        let colorCode: Int64
        let itemCount: Int64
    }

    private typealias ListPageSurface = PanelItemCollectionSurface

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
        private let iconView = NSImageView()
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
            iconView.image = MenuIcon.image(named: "paintpalette", title: AppLocalization.itemTypeTitle("color"))
            iconView.imageScaling = .scaleProportionallyDown
            addSubview(iconView)
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
            let iconSide: CGFloat = 16
            iconView.frame = NSRect(
                x: 16,
                y: (bounds.height - iconSide) / 2,
                width: iconSide,
                height: iconSide
            )

            let leadingIconColumnWidth: CGFloat = 42
            let trailingInset: CGFloat = 12
            let buttonGroupWidth = CGFloat(buttons.count) * buttonSide + CGFloat(max(buttons.count - 1, 0)) * spacing
            let availableWidth = max(0, bounds.width - leadingIconColumnWidth - trailingInset)
            var x = leadingIconColumnWidth + max(0, (availableWidth - buttonGroupWidth) / 2)
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

    private struct PendingEmptySearchClose {
        let generation: Int
        let locationInWindow: NSPoint
        let windowNumber: Int
        let blockingGeneration: Int
    }

    private let searchSlotView = NSView()
    private let searchFieldRevealView = NSView()
    private let searchField = PanelSearchField()
    private var searchBarView: PanelSearchBarView?
    private let previewPopoverController = ClipboardPreviewPopoverController()
    private let itemBandContainerView = NSView()
    private static let maxRetainedPinboardListPages = 3
    private var currentListScope: ClipboardListScope = .clipboard
    private var listPageSurfaces: [ClipboardListScope: ListPageSurface] = [:]
    private var listPageAccessOrder: [ClipboardListScope] = [.clipboard]
    private var listScopeCache = PanelListScopeCache()
    private var suppressedLoadMoreLoadedCountByScope: [ClipboardListScope: Int] = [:]
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
    private var searchSlotWidthConstraint: NSLayoutConstraint?
    private var searchFieldVisibilityTarget = false
    private var searchFieldVisibilityGeneration = 0
    private var searchCancelButtonClickArmed = false
    private var searchCancelTextChangeSuppressionDepth = 0
    private var emptySearchClickAwayGeneration = 0
    private var pendingEmptySearchClose: PendingEmptySearchClose?
    private var menuTrackingDepth = 0
    private var blockingPanelOperationGeneration = 0
    private weak var filterRow: NSStackView?
    private weak var createPinboardButton: PanelActionButton?
    private var toolbarSearchButton: PanelActionButton?
    private var toolbarSearchButtonDefaultImage: NSImage?
    private var appSupportDirectory: URL?
    private var sourceIconHeaderColorWriter: SourceAppIconHeaderColorWriter?
    private var linkWebPreviewEnabled = true
    private let interactionController = PanelInteractionController()
    private var commandHintMonitor: Any?
    private var backgroundHostState: BackgroundHostState = .none
    private var blockingPanelOperationDepth = 0
    private var cardAssetResolver: PanelCardAssetResolver {
        PanelCardAssetResolver(
            appSupportDirectory: appSupportDirectory,
            sourceIconHeaderColorWriter: sourceIconHeaderColorWriter,
            loadSourceIconsSynchronously: false
        )
    }
    private var theme: ClipDockThemePalette {
        ClipDockTheme.current(for: self)
    }
    private var activeListPage: ListPageSurface {
        pageSurface(for: currentListScope)
    }
    private var itemBandDocumentView: NSView {
        activeListPage.collectionView
    }
    private var itemBandScrollView: HorizontalWheelScrollView? {
        activeListPage.scrollView
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
        for (scope, page) in listPageSurfaces where scope != currentListScope {
            page.hasRenderedContent = false
        }
        renderCurrentItems(scrollSelectedItem: false, preserveScrollPosition: true)
    }

    func updateBackgroundHostState(_ state: BackgroundHostState) {
        backgroundHostState = state
        applyTheme()
    }

    var hasBlockingPanelOperation: Bool {
        blockingPanelOperationDepth > 0
    }

    func updateStorageState(_ result: Result<RustCoreOpenResult, RustCoreError>) {
        applyRenderPlan(interactionController.updateStorageState(result))
        if case .success(let openResult) = result {
            listScopeCache[.clipboard] = PanelCachedListScopeState(
                result: RustCoreListResult(
                    items: openResult.items,
                    totalCount: openResult.itemCount,
                    hasMore: Int64(openResult.items.count) < openResult.itemCount
                ),
                isFiltered: false,
                selectionSnapshot: interactionController.selectionSnapshot()
            )
        }
    }

    func updateAppSupportDirectory(_ url: URL) {
        appSupportDirectory = url
    }

    func updateSourceIconHeaderColorWriter(_ writer: SourceAppIconHeaderColorWriter?) {
        sourceIconHeaderColorWriter = writer
    }

    func updatePinboards(_ pinboards: [RustPinboardSummary]) {
        let nextFilters = pinboards.compactMap { pinboard -> PinboardFilterEntry? in
            if pinboard.id == DefaultPinboard.defaultID && pinboard.itemCount == 0 {
                return nil
            }
            return PinboardFilterEntry(
                id: pinboard.id,
                title: pinboard.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? AppLocalization.text("pinboard.untitled", defaultValue: "未命名")
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
                beginInlinePinboardRenameAfterCreation(pinboardID: createdPinboardID)
            }
        }

        pruneCachedPinboardPages(validPinboardIDs: Set(nextFilters.map(\.id)))
    }

    func setPreviewPopoverEnabled(_ enabled: Bool) {
        interactionController.setPreviewPopoverEnabled(enabled)
        if !enabled {
            previewPopoverController.close()
        }
    }

    func setLinkWebPreviewEnabled(_ enabled: Bool) {
        linkWebPreviewEnabled = enabled
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
        switchListPage(to: .clipboard)
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
        switchListPage(to: .clipboard)
        removeCachedPinboardPages(pinboardID: deletedPinboardID)
    }

    func invalidateCachedListPages() {
        let currentScope = currentListScope
        listScopeCache.keepOnly(currentScope)
        let removableScopes = listPageSurfaces.keys.filter { $0 != currentScope }
        for scope in removableScopes {
            if let page = listPageSurfaces.removeValue(forKey: scope) {
                removeListPageSurface(page)
            }
        }
        listPageAccessOrder.removeAll { $0 != currentScope }
    }

    func invalidateCachedPinboardListPages(pinboardID: String) {
        removeCachedPinboardPages(pinboardID: pinboardID)
    }

    private func removeCachedPinboardPages(pinboardID: String) {
        let removableScopes = listPageSurfaces.keys.filter {
            $0.pinboardID == pinboardID && $0 != currentListScope
        }
        for scope in removableScopes {
            if let page = listPageSurfaces.removeValue(forKey: scope) {
                removeListPageSurface(page)
            }
        }
        listPageAccessOrder.removeAll { $0.pinboardID == pinboardID && $0 != currentListScope }
        listScopeCache.removePinboard(pinboardID, keeping: currentListScope)
    }

    private func pruneCachedPinboardPages(validPinboardIDs: Set<String>) {
        let removableScopes = listPageSurfaces.keys.filter { scope in
            guard let pinboardID = scope.pinboardID else { return false }
            return !validPinboardIDs.contains(pinboardID) && scope != currentListScope
        }
        for scope in removableScopes {
            if let page = listPageSurfaces.removeValue(forKey: scope) {
                removeListPageSurface(page)
            }
        }
        listPageAccessOrder.removeAll { scope in
            guard let pinboardID = scope.pinboardID else { return false }
            return !validPinboardIDs.contains(pinboardID) && scope != currentListScope
        }
        listScopeCache.pruneInvalidPinboards(
            validPinboardIDs: validPinboardIDs,
            keeping: currentListScope
        )
    }

    private func beginInlinePinboardRenameAfterCreation(pinboardID: String) {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }),
              let button = pinboardButtons.first(where: { $0.pinboardID == pinboardID })
        else { return }

        layoutSubtreeIfNeeded()
        beginInlinePinboardRename(pinboard, in: button)
    }

    func containsPreviewSurface(eventWindow: NSWindow?, mouseLocation: CGPoint) -> Bool {
        guard previewPopoverController.isShown else { return false }

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

        if canStartSearchFromPrintableKey(),
           let initialText = PanelTypeToSearchKeyPlanner.initialSearchText(for: event) {
            clearCommandHintMode()
            applyInteractionAction(.startSearch(initialText: initialText))
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

    private func canStartSearchFromPrintableKey() -> Bool {
        guard !hasBlockingPanelOperation,
              !previewPopoverController.isShown,
              activeRenameField == nil
        else {
            return false
        }

        guard let firstResponder = window?.firstResponder else {
            return true
        }

        if firstResponder === self {
            return true
        }

        if firstResponder === searchField || firstResponder === activeRenameField {
            return false
        }

        if firstResponder is NSTextView
            || firstResponder is NSTextField
            || firstResponder is NSSearchField {
            return false
        }

        return false
    }

    func updatePanelHeight(_ panelHeight: CGFloat) {
        currentPanelHeight = panelHeight
        let itemSide = itemSideLength(for: panelHeight)
        activeListPage.updatePanelHeight(itemSide)
    }

    private func itemSideLength(for panelHeight: CGFloat) -> CGFloat {
        max(
            Layout.compactItemSide,
            panelHeight - Layout.controlBarHeight - Layout.sectionSpacing - Layout.padding
        )
    }

    private func itemBandBottomPadding(shadowOutset: CGFloat) -> CGFloat {
        max(12, Layout.padding - (2 * shadowOutset - 1))
    }

    private func handleItemBandScrollDidChange() {
        activeListPage.savedScrollOrigin = activeListPage.saveScrollOrigin()
        let reachedLoadMoreThreshold = activeListPage.hasReachedLoadMoreThreshold()
        guard reachedLoadMoreThreshold || panelViewState().isCommandHintModeEnabled else {
            return
        }

        let shouldEmitLoadMore = shouldEmitLoadMoreForCurrentThreshold(
            reachedLoadMoreThreshold: reachedLoadMoreThreshold
        )
        applyInteractionAction(.didScroll(
            visibleCommandItemIDs: fullyVisibleCommandItemIDs(),
            reachedLoadMoreThreshold: shouldEmitLoadMore
        ))
    }

    private func configureAppearance() {
        userInterfaceLayoutDirection = .leftToRight
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        applyTheme()
    }

    private func applyTheme() {
        let theme = theme
        layer?.backgroundColor = panelStableBackgroundColor(theme: theme).cgColor
        toolbarIconButtons.forEach { button in
            button.contentTintColor = theme.panel.toolbarIconColor
        }
        searchBarView?.applyTheme(theme, isActive: panelViewState().toolbar.isSearchVisible)
        updatePinboardChipAppearance()
    }

    private func panelStableBackgroundColor(theme: ClipDockThemePalette) -> NSColor {
        switch backgroundHostState {
        case .systemGlass, .legacyVisualEffect:
            return .clear
        case .none:
            break
        }

        let tint = theme.panel.backgroundColor.usingColorSpace(.deviceRGB) ?? theme.panel.backgroundColor
        return tint.withAlphaComponent(max(tint.alphaComponent, 0.28))
    }

    private func pageSurface(for scope: ClipboardListScope) -> ListPageSurface {
        if let page = listPageSurfaces[scope] {
            return page
        }

        let page = ListPageSurface(
            metrics: itemCollectionLayoutMetrics(),
            rendererProvider: { [weak self] in
                guard let self else {
                    return PanelItemCardRenderer(
                        cardAssetResolver: PanelCardAssetResolver(
                            appSupportDirectory: nil,
                            sourceIconHeaderColorWriter: nil,
                            loadSourceIconsSynchronously: false
                        ),
                        metrics: PanelItemCardRendererMetrics(
                            defaultItemSide: Layout.defaultItemSide,
                            cardCornerRadius: Layout.cardCornerRadius,
                            innerCornerRadius: Layout.innerCornerRadius,
                            cardHeaderHeight: Layout.cardHeaderHeight,
                            cardInset: Layout.cardInset,
                            cardFooterHeight: Layout.cardFooterHeight,
                            sourceIconSize: Layout.sourceIconSize,
                            linkPreviewHeight: Layout.linkPreviewHeight,
                            theme: ClipDockTheme.current(for: NSView())
                        ),
                        backingScaleFactor: NSScreen.main?.backingScaleFactor ?? 2
                    )
                }
                return self.cardRenderer()
            },
            onScrollDidChange: { [weak self] in
                self?.handleItemBandScrollDidChange()
            },
            onTailPrefetch: { [weak self] in
                self?.handleItemBandScrollDidChange()
            }
        )
        listPageSurfaces[scope] = page
        return page
    }

    private func itemCollectionLayoutMetrics() -> PanelItemCollectionLayoutMetrics {
        let shadowOutset = ClipDockTheme.current(for: self).card.cardShadowOutset
        return PanelItemCollectionLayoutMetrics(
            itemSide: itemSideLength(for: currentPanelHeight),
            itemSpacing: 22,
            horizontalContentInset: Layout.horizontalContentInset,
            imagePreviewMinHeight: Layout.imagePreviewMinHeight,
            imagePreviewMaxHeight: Layout.imagePreviewMaxHeight,
            cardInset: Layout.cardInset,
            shadowOutset: shadowOutset
        )
    }

    private func attachListPage(_ page: ListPageSurface) {
        for cachedPage in listPageSurfaces.values {
            cachedPage.savedScrollOrigin = cachedPage.saveScrollOrigin()
            cachedPage.scrollView.isHidden = cachedPage !== page
        }

        page.attach(to: itemBandContainerView)
    }

    private func removeListPageSurface(_ page: ListPageSurface) {
        page.detach()
    }

    private func recordListPageAccess(_ scope: ClipboardListScope) {
        listPageAccessOrder.removeAll { $0 == scope }
        listPageAccessOrder.append(scope)
        pruneRetainedListPagesIfNeeded()
    }

    private func pruneRetainedListPagesIfNeeded() {
        let nonRetainedScopes = listPageSurfaces.keys.filter {
            $0 != .clipboard
                && $0 != currentListScope
                && $0.sourceAppID != nil
        }
        for scope in nonRetainedScopes {
            if let page = listPageSurfaces.removeValue(forKey: scope) {
                removeListPageSurface(page)
            }
            listScopeCache.remove(scope)
            listPageAccessOrder.removeAll { $0 == scope }
        }

        let retainedPinboardPages = listPageSurfaces.keys.filter {
            $0.pinboardID != nil && $0 != currentListScope
        }
        guard retainedPinboardPages.count > Self.maxRetainedPinboardListPages else { return }

        for scope in Array(listPageAccessOrder) {
            guard scope != .clipboard,
                  scope != currentListScope,
                  scope.pinboardID != nil,
                  let page = listPageSurfaces.removeValue(forKey: scope)
            else {
                continue
            }
            removeListPageSurface(page)
            listPageAccessOrder.removeAll { $0 == scope }
            if listPageSurfaces.keys.filter({ $0.pinboardID != nil && $0 != currentListScope }).count
                <= Self.maxRetainedPinboardListPages {
                break
            }
        }
    }

    private func configureLayout() {
        let resizeHandle = HeightResizeHandleView(frame: .zero)
        resizeHandle.onDragBegan = { [weak self] in self?.onHeightResizeBegan?() }
        resizeHandle.onDragChanged = { [weak self] deltaY in self?.onHeightResizeChanged?(deltaY) }
        resizeHandle.onDragEnded = { [weak self] in self?.onHeightResizeEnded?() }
        resizeHandle.toolTip = AppLocalization.text("panel.resizeHandle.tooltip", defaultValue: "拖动调整高度")
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

            itemBand.leadingAnchor.constraint(equalTo: leadingAnchor),
            itemBand.trailingAnchor.constraint(equalTo: trailingAnchor),
            itemBand.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: Layout.sectionSpacing),
            itemBand.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -itemBandBottomPadding(shadowOutset: itemCollectionLayoutMetrics().shadowOutset)
            )
        ])

        renderItemEntries([])
        updatePanelHeight(currentPanelHeight)
    }

    private func makeControlBar() -> NSView {
        let container = NSView()

        let searchTextFont = NSFont.systemFont(ofSize: 15, weight: .regular)
        searchField.controlSize = .regular
        searchField.font = searchTextFont
        searchField.textColor = .labelColor
        searchField.placeholderAttributedString = NSAttributedString(
            string: AppLocalization.text("search.placeholder", defaultValue: "搜索"),
            attributes: [
                .font: searchTextFont,
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
        searchField.focusRingType = .none
        searchField.isBezeled = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.backgroundColor = .clear
        searchField.setAccessibilityLabel(AppLocalization.text("search.accessibility", defaultValue: "搜索剪贴板内容或来源应用"))
        searchField.setAccessibilityHelp(AppLocalization.text("search.accessibility", defaultValue: "搜索剪贴板内容或来源应用"))
        searchField.delegate = self
        searchField.target = nil
        searchField.action = nil
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.controlSize = .regular
            cell.font = searchField.font
            cell.alignment = .left
            cell.isBezeled = false
            cell.isBordered = false
            cell.drawsBackground = false
            cell.backgroundColor = .clear
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byTruncatingTail
            cell.isScrollable = true
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        searchField.onCancelButtonMouseDown = { [weak self] in
            self?.armSearchCancelButtonClick() ?? false
        }
        searchField.onCancelButtonClick = { [weak self] in
            self?.handleSearchCancelButtonClick()
        }
        searchField.isHidden = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let searchBar = PanelSearchBarView(searchField: searchField)
        searchBar.onActivateSearchField = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.searchField)
        }
        searchBar.onClear = { [weak self] in
            self?.handleCustomSearchClearButtonClick()
        }
        searchBar.applyTheme(theme)
        searchBar.updateClearButton(hasText: false)
        searchBarView = searchBar

        searchSlotView.wantsLayer = true
        searchSlotView.layer?.masksToBounds = true
        searchSlotView.translatesAutoresizingMaskIntoConstraints = false

        searchFieldRevealView.wantsLayer = true
        searchFieldRevealView.layer?.masksToBounds = true
        searchFieldRevealView.isHidden = true
        searchFieldRevealView.alphaValue = 0
        searchFieldRevealView.translatesAutoresizingMaskIntoConstraints = false
        searchFieldRevealView.addSubview(searchBar)

        let searchButton = makeToolbarIconButton(
            symbolName: "magnifyingglass",
            accessibilityLabel: AppLocalization.text("search.placeholder", defaultValue: "搜索"),
            button: SearchToolbarButton()
        ) { [weak self] in
            self?.toggleSearchField()
        }
        toolbarSearchButton = searchButton
        toolbarSearchButtonDefaultImage = searchButton.image
        setToolbarSearchButtonHitTesting(true)
        searchSlotView.addSubview(searchButton)
        searchSlotView.addSubview(searchFieldRevealView)

        let chips = makeFilterChips()
        pinboardButtons = chips
        updatePinboardChipAppearance()

        let addButton = makeToolbarIconButton(
            symbolName: "plus",
            accessibilityLabel: AppLocalization.text("pinboard.create", defaultValue: "创建 Pinboard")
        ) { [weak self] in
            self?.showCreatePinboardDialog()
        }
        createPinboardButton = addButton
        let moreButton = makeToolbarIconButton(
            symbolName: "ellipsis.circle",
            accessibilityLabel: AppLocalization.text("panel.more", defaultValue: "更多功能")
        ) {}
        moreButton.onPress = { [weak self, weak moreButton] in
            guard let moreButton else { return }
            self?.showPanelOverflowMenu(from: moreButton)
        }

        let row = NSStackView(views: [searchSlotView] + chips + [addButton])
        row.orientation = NSUserInterfaceLayoutOrientation.horizontal
        row.alignment = NSLayoutConstraint.Attribute.centerY
        row.spacing = 9
        row.userInterfaceLayoutDirection = NSUserInterfaceLayoutDirection.leftToRight
        row.translatesAutoresizingMaskIntoConstraints = false
        filterRow = row

        container.addSubview(row)
        searchSlotWidthConstraint = searchSlotView.widthAnchor.constraint(equalToConstant: Layout.searchSlotClosedWidth)
        searchSlotWidthConstraint?.isActive = true

        let leadingConstraint = row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor)
        leadingConstraint.priority = .defaultLow
        let centerXConstraint = row.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        centerXConstraint.priority = .defaultHigh

        container.addSubview(moreButton)
        NSLayoutConstraint.activate([
            centerXConstraint,
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leadingConstraint,
            row.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -Layout.sectionSpacing),
            searchSlotView.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight),
            searchButton.leadingAnchor.constraint(equalTo: searchSlotView.leadingAnchor),
            searchButton.centerYAnchor.constraint(equalTo: searchSlotView.centerYAnchor),
            searchFieldRevealView.heightAnchor.constraint(equalToConstant: Layout.searchFieldHeight),
            searchFieldRevealView.widthAnchor.constraint(equalToConstant: Layout.searchFieldWidth),
            searchFieldRevealView.leadingAnchor.constraint(equalTo: searchSlotView.leadingAnchor),
            searchFieldRevealView.centerYAnchor.constraint(equalTo: searchSlotView.centerYAnchor),
            searchBar.leadingAnchor.constraint(equalTo: searchFieldRevealView.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: searchFieldRevealView.trailingAnchor),
            searchBar.topAnchor.constraint(equalTo: searchFieldRevealView.topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: searchFieldRevealView.bottomAnchor),
            moreButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            moreButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeFilterChips() -> [PinboardChipButton] {
        [
            makePinboardChip(title: AppLocalization.text("clipboard.title", defaultValue: "剪贴板"), pinboardID: nil, itemType: nil, symbolName: "clock.arrow.circlepath", dotColor: .clear)
        ]
            + pinboardFilters.map { pinboard in
                makePinboardChip(
                    title: pinboard.title,
                    pinboardID: pinboard.id,
                    itemType: nil,
                    symbolName: nil,
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
        let insertionIndex = createPinboardButton
            .flatMap { button in filterRow.arrangedSubviews.firstIndex { $0 === button } }
            ?? filterRow.arrangedSubviews.count
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

    private func showPanelOverflowMenu(from sourceView: NSView) {
        let menu = makePanelOverflowMenu()
        withPanelMenuTracking {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: sourceView.bounds.midX, y: sourceView.bounds.minY),
                in: sourceView
            )
        }
    }

    private func makePanelOverflowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(ActionMenuItem(title: AppLocalization.text("menu.hidePanel", defaultValue: "隐藏面板"), imageName: "eye.slash") { [weak self] in
            self?.applyInteractionAction(.hidePanel)
        })
        menu.addItem(ActionMenuItem(title: AppLocalization.text("menu.preferences", defaultValue: "偏好设置"), imageName: "gearshape") { [weak self] in
            self?.onRuntimeAction?(.showPreferences)
        })

        return menu
    }

    private func selectedPinboardEntry() -> PinboardFilterEntry? {
        guard let selectedPinboardID = panelViewState().toolbar.selectedPinboardID else { return nil }
        return pinboardFilters.first { $0.id == selectedPinboardID }
    }

    private func makePinboardColorRowMenuItem(for pinboard: PinboardFilterEntry) -> NSMenuItem {
        let item = NSMenuItem(title: AppLocalization.itemTypeTitle("color"), action: nil, keyEquivalent: "")
        item.image = MenuIcon.image(named: "paintpalette", title: AppLocalization.itemTypeTitle("color"))
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
        menu.addItem(ActionMenuItem(title: AppLocalization.text("action.rename", defaultValue: "重命名"), imageName: "pencil") { [weak self] in
            self?.showRenamePinboardDialog(for: pinboard)
        })

        menu.addItem(ActionMenuItem(title: AppLocalization.text("action.deleteEllipsis", defaultValue: "删除..."), imageName: "trash") { [weak self] in
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
        onRuntimeAction?(.createPinboard(title: AppLocalization.text("pinboard.untitled", defaultValue: "未命名"), colorCode: colorOption.colorCode))
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
        AppLocalization.text("pinboard.untitled", defaultValue: "未命名")
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
        alert.messageText = AppLocalization.text("pinboard.share.title", defaultValue: "共享 Pinboard")
        alert.informativeText = AppLocalization.text("pinboard.share.unavailable", defaultValue: "共享 Pinboard 尚未接入。")
        alert.addButton(withTitle: AppLocalization.text("action.ok", defaultValue: "确定"))
        _ = runBlockingPanelModal {
            alert.runModal()
        }
    }

    private func confirmDeleteSelectedPinboard() {
        guard let pinboard = selectedPinboardEntry() else { return }
        confirmDeletePinboard(pinboard)
    }

    private func confirmDeletePinboard(_ pinboard: PinboardFilterEntry) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalization.format("pinboard.delete.confirmTitle", defaultValue: "删除“%@”？", pinboard.title)
        alert.informativeText = AppLocalization.text("pinboard.delete.warning", defaultValue: "删除 Pinboard 及其所有内容将无法恢复。")
        alert.addButton(withTitle: AppLocalization.text("action.delete", defaultValue: "删除"))
        alert.addButton(withTitle: AppLocalization.text("action.cancel", defaultValue: "取消"))

        let response = runBlockingPanelModal {
            alert.runModal()
        }
        guard response == .alertFirstButtonReturn else { return }
        onRuntimeAction?(.deletePinboard(pinboardID: pinboard.id))
    }

    @discardableResult
    private func runBlockingPanelModal(_ modal: () -> NSApplication.ModalResponse) -> NSApplication.ModalResponse {
        blockingPanelOperationDepth += 1
        blockingPanelOperationGeneration += 1
        pendingEmptySearchClose = nil
        defer {
            blockingPanelOperationDepth -= 1
        }
        return modal()
    }

    private func withPanelMenuTracking(_ body: () -> Void) {
        menuTrackingDepth += 1
        defer {
            menuTrackingDepth -= 1
            processPendingEmptySearchCloseAfterMenuTracking()
        }
        body()
    }

    private func processPendingEmptySearchCloseAfterMenuTracking() {
        guard menuTrackingDepth == 0,
              pendingEmptySearchClose != nil
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.processPendingEmptySearchClose()
        }
    }

    private func pinboardDeletionRequiresConfirmation(_ pinboard: PinboardFilterEntry) -> Bool {
        true
    }

    private func makeItemBand() -> NSView {
        attachListPage(activeListPage)
        return itemBandContainerView
    }

    func updateListState(
        _ result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool = false,
        scope: ClipboardListScope? = nil
    ) {
        let updateScope = scope ?? currentListScope
        let loadedCountBeforeUpdate = currentItems().count
        if updateScope != currentListScope {
            let activeQueryScope = ClipboardListScope(
                searchText: panelViewState().toolbar.searchText,
                itemType: panelViewState().toolbar.selectedItemType,
                sourceAppID: nil,
                pinboardID: panelViewState().toolbar.selectedPinboardID
            )
            guard updateScope == activeQueryScope else {
                cacheListState(result, isFiltered: isFiltered, append: append, scope: updateScope)
                return
            }
            switchListPage(to: updateScope)
        }

        let shouldReuseRenderedPage = shouldReuseRenderedPage(
            for: result,
            append: append,
            scope: updateScope
        )
        if shouldReuseRenderedPage {
            ClipDockPerformanceLog.event("list.render.reuse", detail: "scope=\(updateScope)")
            updateLoadMoreSuppressionAfterListUpdate(
                result: result,
                append: append,
                scope: updateScope,
                loadedCountBeforeUpdate: loadedCountBeforeUpdate
            )
            updateVisibleSelection(scrollIntoView: false)
            restoreScrollOriginIfNeeded(activeListPage.savedScrollOrigin)
            refreshVisibleCommandHints()
            return
        }

        let plan = interactionController.updateListState(result, isFiltered: isFiltered, append: append)
        cacheListState(result, isFiltered: isFiltered, append: append, scope: updateScope)
        updateLoadMoreSuppressionAfterListUpdate(
            result: result,
            append: append,
            scope: updateScope,
            loadedCountBeforeUpdate: loadedCountBeforeUpdate
        )

        applyRenderPlan(plan)
    }

    func updateLoadingMoreState(_ isLoading: Bool) {
        let wasLoading = interactionController.isLoadingMoreItems
        interactionController.updateLoadingMoreState(isLoading)
        if wasLoading, !isLoading {
            suppressedLoadMoreLoadedCountByScope.removeValue(forKey: currentListScope)
        }
    }

    private func shouldEmitLoadMoreForCurrentThreshold(reachedLoadMoreThreshold: Bool) -> Bool {
        guard reachedLoadMoreThreshold else { return false }
        let viewState = panelViewState()
        let loadedItemCount = currentItems().count
        guard viewState.list.hasMoreItems,
              !viewState.list.isLoadingMoreItems,
              loadedItemCount > 0,
              suppressedLoadMoreLoadedCountByScope[currentListScope] != loadedItemCount
        else {
            return false
        }

        suppressedLoadMoreLoadedCountByScope[currentListScope] = loadedItemCount
        return true
    }

    private func updateLoadMoreSuppressionAfterListUpdate(
        result: Result<RustCoreListResult, RustCoreError>,
        append: Bool,
        scope: ClipboardListScope,
        loadedCountBeforeUpdate: Int
    ) {
        guard append else {
            suppressedLoadMoreLoadedCountByScope.removeValue(forKey: scope)
            return
        }

        switch result {
        case .success:
            let loadedCountAfterUpdate = scope == currentListScope
                ? currentItems().count
                : (listScopeCache[scope]?.result.items.count ?? loadedCountBeforeUpdate)
            if loadedCountAfterUpdate > loadedCountBeforeUpdate || !panelViewState().list.hasMoreItems {
                suppressedLoadMoreLoadedCountByScope.removeValue(forKey: scope)
            }
        case .failure:
            suppressedLoadMoreLoadedCountByScope.removeValue(forKey: scope)
        }
    }

    private func shouldReuseRenderedPage(
        for result: Result<RustCoreListResult, RustCoreError>,
        append: Bool,
        scope: ClipboardListScope
    ) -> Bool {
        guard !append,
              activeListPage.hasRenderedContent,
              let cachedState = listScopeCache[scope],
              case .success(let listResult) = result
        else {
            return false
        }

        return cachedState.result == listResult
    }

    private func cacheListState(
        _ result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool,
        scope: ClipboardListScope
    ) {
        listScopeCache.store(
            result,
            isFiltered: isFiltered,
            append: append,
            selectedItemID: panelViewState().selectedItemID,
            selectionSnapshot: interactionController.selectionSnapshot(),
            scope: scope
        )
    }

    private func saveCurrentListPageState() {
        activeListPage.savedScrollOrigin = activeListPage.saveScrollOrigin()
        listScopeCache.updateSelectionSnapshot(interactionController.selectionSnapshot(), for: currentListScope)
    }

    private func restoreCachedListState(for scope: ClipboardListScope) {
        guard let cachedState = listScopeCache[scope] else { return }
        let plan = interactionController.updateListState(
            .success(cachedState.result),
            isFiltered: cachedState.isFiltered,
            append: false
        )
        if !activeListPage.hasRenderedContent {
            applyRenderPlan(plan)
        }
        applyInteractionResult(interactionController.restoreSelectionSnapshot(cachedState.selectionSnapshot))
        updateVisibleSelection(scrollIntoView: false)
    }

    private func restoreScrollOriginIfNeeded(_ origin: NSPoint) {
        if window?.isVisible == true {
            layoutSubtreeIfNeeded()
            itemBandDocumentView.layoutSubtreeIfNeeded()
        }
        activeListPage.restoreScrollOrigin(origin)
    }

    private func restoreInitialHorizontalScrollOriginIfNeeded() {
        activeListPage.scrollToLeadingEdge()
    }

    private func switchListPage(to scope: ClipboardListScope) {
        guard scope != currentListScope else { return }

        saveCurrentListPageState()
        suppressedLoadMoreLoadedCountByScope.removeValue(forKey: scope)
        currentListScope = scope
        let page = activeListPage
        attachListPage(page)
        recordListPageAccess(scope)
        updatePanelHeight(currentPanelHeight)
        if listScopeCache[scope] != nil {
            restoreCachedListState(for: scope)
        } else if !page.hasRenderedContent {
            let emptyResult = RustCoreListResult(items: [], totalCount: 0, hasMore: false)
            applyRenderPlan(interactionController.updateListState(
                .success(emptyResult),
                isFiltered: scope.isFiltered,
                append: false
            ))
        }
        restoreScrollOriginIfNeeded(page.savedScrollOrigin)
        refreshVisibleCommandHints()
    }

    private func renderCurrentItems(
        scrollSelectedItem: Bool = true,
        preserveScrollPosition: Bool = false
    ) {
        let preservedOrigin = itemBandScrollView?.contentView.bounds.origin
        switch panelViewState().list.presentation {
        case .emptyHistory, .filteredEmpty:
            ClipDockPerformanceLog.measure("list.render.empty") {
                renderItemEntries([])
            }
            return
        case .databaseError:
            ClipDockPerformanceLog.measure("list.render.databaseError") {
                renderItemEntries([])
            }
            return
        case .items(let items):
            let entries = ClipDockPerformanceLog.measure("list.makeItemEntries", detail: "count=\(items.count)") {
                items.map(makeItemEntry)
            }
            ClipDockPerformanceLog.measure("list.renderItemEntries", detail: "count=\(entries.count)") {
                renderItemEntries(entries)
            }
        }
        if preserveScrollPosition, let preservedOrigin {
            restoreScrollOriginIfNeeded(preservedOrigin)
        } else {
            restoreInitialHorizontalScrollOriginIfNeeded()
        }

        if !preserveScrollPosition, scrollSelectedItem {
            scrollSelectedItemIntoView()
        }
    }

    private func applyRenderPlan(_ plan: PanelContentRenderPlan) {
        if plan.previewClosePolicy == .close {
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
        case .reconcileItems(let items, let scrollSelectedItem, let preserveScrollPosition):
            reconcileRenderedList(
                items,
                scrollSelectedItem: scrollSelectedItem,
                preserveScrollPosition: preserveScrollPosition,
                previewClosePolicy: plan.previewClosePolicy
            )
        case .noVisualChange:
            break
        }
    }

    private func reconcileRenderedList(
        _ items: [RustClipboardItemSummary],
        scrollSelectedItem: Bool,
        preserveScrollPosition: Bool,
        previewClosePolicy: PanelPreviewClosePolicy
    ) {
        let preservedOrigin = itemBandScrollView?.contentView.bounds.origin
        let previewedItemID = previewPopoverController.previewedItemID
        let entries = ClipDockPerformanceLog.measure("list.reconcile.makeEntries", detail: "count=\(items.count)") {
            items.map(makeItemEntry)
        }
        ClipDockPerformanceLog.measure("list.reconcile.collection", detail: "count=\(entries.count)") {
            activeListPage.reconcile(entries: entries)
            refreshItemBandLayout(preservedOrigin: preservedOrigin, preserveScrollPosition: preserveScrollPosition)
        }
        if !preserveScrollPosition, scrollSelectedItem {
            scrollSelectedItemIntoView()
        }
        updatePreviewAfterReconcile(
            previewedItemID: previewedItemID,
            validItemIDs: Set(items.map(\.id)),
            closePolicy: previewClosePolicy
        )
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

        activeListPage.append(entries: items.map(makeItemEntry))
        refreshItemBandLayout(preservedOrigin: preservedOrigin, preserveScrollPosition: preserveScrollPosition)
    }

    private func refreshItemBandLayout(
        preservedOrigin: NSPoint?,
        preserveScrollPosition: Bool
    ) {
        let itemSide = itemSideLength(for: currentPanelHeight)
        activeListPage.updatePanelHeight(itemSide)

        if preserveScrollPosition, let preservedOrigin {
            restoreScrollOriginIfNeeded(preservedOrigin)
        } else {
            restoreInitialHorizontalScrollOriginIfNeeded()
        }

        refreshVisibleCommandHints()
    }

    private func handleKeyboardCommand(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandPressed = modifiers.contains(.command)
        let shiftPressed = modifiers.contains(.shift)

        if commandPressed,
           let character = event.charactersIgnoringModifiers?.lowercased() {
            if character == "c" {
                applyInteractionAction(.copySelectedItem)
                return true
            }

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
            applyInteractionAction(shiftPressed ? .selection(.extendByOffset(1)) : .selectOffset(1))
            return true
        case kVK_LeftArrow:
            clearCommandHintModeIfCommandIsNotPressed(in: event)
            applyInteractionAction(shiftPressed ? .selection(.extendByOffset(-1)) : .selectOffset(-1))
            return true
        case kVK_Delete, kVK_ForwardDelete:
            clearCommandHintMode()
            applyInteractionAction(.deleteSelectedItem)
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
        if searchField.stringValue != viewState.toolbar.searchText {
            searchField.stringValue = viewState.toolbar.searchText
        }
        updateSearchChromeState()
        setSearchFieldVisible(viewState.toolbar.isSearchVisible, animated: true)
        updatePinboardChipAppearance()
    }

    private func setSearchFieldVisible(_ visible: Bool, animated: Bool) {
        guard searchFieldVisibilityTarget != visible else {
            applySearchFieldVisibilityFinalState(visible)
            return
        }

        searchFieldVisibilityTarget = visible
        searchFieldVisibilityGeneration += 1
        let generation = searchFieldVisibilityGeneration

        setToolbarSearchButtonHitTesting(false)
        toolbarSearchButton?.image = toolbarSearchButtonDefaultImage
        if visible {
            searchFieldRevealView.isHidden = false
            searchField.isHidden = false
        } else if !searchFieldRevealView.isHidden {
            searchField.isHidden = false
        }

        let targetWidth = visible ? Layout.searchFieldWidth : Layout.searchSlotClosedWidth
        let targetAlpha: CGFloat = visible ? 1 : 0
        let targetButtonAlpha: CGFloat = visible ? 0 : 1
        guard animated, window != nil else {
            applySearchFieldVisibilityFinalState(visible)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.searchFieldAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)
            searchSlotWidthConstraint?.animator().constant = targetWidth
            searchFieldRevealView.animator().alphaValue = targetAlpha
            toolbarSearchButton?.animator().alphaValue = targetButtonAlpha
            filterRow?.layoutSubtreeIfNeeded()
            filterRow?.superview?.layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.searchFieldVisibilityGeneration == generation,
                      self.searchFieldVisibilityTarget == visible
                else {
                    return
                }

                self.applySearchFieldVisibilityFinalState(visible)
            }
        }
        scheduleSearchFieldVisibilityFinalState(visible, generation: generation)
    }

    private func applySearchFieldVisibilityFinalState(_ visible: Bool) {
        let targetWidth = visible ? Layout.searchFieldWidth : Layout.searchSlotClosedWidth
        searchSlotWidthConstraint?.constant = targetWidth
        searchFieldRevealView.alphaValue = visible ? 1 : 0
        searchFieldRevealView.isHidden = !visible
        searchField.isHidden = !visible
        toolbarSearchButton?.image = toolbarSearchButtonDefaultImage
        toolbarSearchButton?.alphaValue = visible ? 0 : 1
        setToolbarSearchButtonHitTesting(!visible)
        let firstResponder = window?.firstResponder
        if !visible,
           (firstResponder === searchField || firstResponder === searchField.currentEditor()) {
            window?.makeFirstResponder(self)
        }
        filterRow?.layoutSubtreeIfNeeded()
        filterRow?.superview?.layoutSubtreeIfNeeded()
    }

    private func scheduleSearchFieldVisibilityFinalState(_ visible: Bool, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.searchFieldAnimationDuration + 0.03) { [weak self] in
            guard let self,
                  self.searchFieldVisibilityGeneration == generation,
                  self.searchFieldVisibilityTarget == visible
            else {
                return
            }

            self.applySearchFieldVisibilityFinalState(visible)
        }
    }

    private func setToolbarSearchButtonHitTesting(_ enabled: Bool) {
        guard let toolbarSearchButton else { return }
        toolbarSearchButton.isEnabled = enabled
        if let searchButton = toolbarSearchButton as? SearchToolbarButton {
            searchButton.allowsSearchHitTesting = enabled
        }
        toolbarSearchButton.needsDisplay = true
    }

    private func updateSearchChromeState() {
        searchBarView?.updateClearButton(hasText: !searchField.stringValue.isEmpty)
        searchBarView?.applyTheme(theme, isActive: panelViewState().toolbar.isSearchVisible)
    }

    private func emitRuntimeAction(_ action: PanelExternalAction) {
        switch action {
        case .queryChanged(let searchText, let itemType, let sourceAppID, let pinboardID, let debounce):
            let scope = ClipboardListScope(
                searchText: searchText,
                itemType: itemType,
                sourceAppID: sourceAppID,
                pinboardID: pinboardID
            )
            if !debounce {
                switchListPage(to: scope)
            }
            onRuntimeAction?(.queryChanged(
                searchText: searchText,
                itemType: itemType,
                sourceAppID: sourceAppID,
                pinboardID: pinboardID,
                debounce: debounce
            ))
        case .copyItem(let itemID):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.copyItem(item))
        case .copyItemAsPlainText(let itemID):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.copyItemAsPlainText(item))
        case .setPinboardMembership(let itemID, let pinboardID, let isMember):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.setPinboardMembership(
                item,
                pinboardID: pinboardID,
                isMember: isMember
            ))
        case .setPinboardMembershipBatch(let itemIDs, let pinboardID, let isMember):
            let items = resolvedItems(for: itemIDs)
            guard !items.isEmpty else { return }
            onRuntimeAction?(.setPinboardMembershipBatch(
                items,
                pinboardID: pinboardID,
                isMember: isMember
            ))
        case .deleteItem(let itemID, let pinboardID):
            guard let item = interactionController.item(withID: itemID) else { return }
            onRuntimeAction?(.deleteItem(item, pinboardID: pinboardID))
        case .deleteItems(let itemIDs, let pinboardID):
            let items = resolvedItems(for: itemIDs)
            guard !items.isEmpty else { return }
            onRuntimeAction?(.deleteItems(items, pinboardID: pinboardID))
        case .hidePanel:
            onRuntimeAction?(.hidePanel)
        case .loadMore:
            onRuntimeAction?(.loadMore)
        }
    }

    private func resolvedItems(for orderedItemIDs: [String]) -> [RustClipboardItemSummary] {
        let itemByID = Dictionary(uniqueKeysWithValues: interactionController.currentItems.map { ($0.id, $0) })
        return orderedItemIDs.compactMap { itemByID[$0] }
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
              let item = interactionController.item(withID: itemID)
        else {
            return
        }

        guard let cardView = itemBandCardView(forItemID: itemID) else {
            activeListPage.scrollItemIntoView(itemID: itemID) { [weak self] in
                guard let self,
                      let cardView = self.itemBandCardView(forItemID: itemID)
                else {
                    self?.previewPopoverController.close()
                    return
                }
                self.previewPopoverController.toggle(
                    item: item,
                    appSupportDirectory: appSupportDirectory,
                    linkWebPreviewEnabled: self.linkWebPreviewEnabled,
                    relativeTo: cardView,
                    returnFocusTo: self
                )
            }
            return
        }

        previewPopoverController.toggle(
            item: item,
            appSupportDirectory: appSupportDirectory,
            linkWebPreviewEnabled: linkWebPreviewEnabled,
            relativeTo: cardView,
            returnFocusTo: self
        )
    }

    private func showPreview(forItemID itemID: String) {
        guard let item = interactionController.item(withID: itemID)
        else {
            return
        }

        guard let cardView = itemBandCardView(forItemID: itemID) else {
            activeListPage.scrollItemIntoView(itemID: itemID) { [weak self] in
                guard let self,
                      let cardView = self.itemBandCardView(forItemID: itemID)
                else {
                    self?.previewPopoverController.close()
                    return
                }
                self.previewPopoverController.show(
                    item: item,
                    appSupportDirectory: self.appSupportDirectory ?? URL(fileURLWithPath: NSHomeDirectory()),
                    linkWebPreviewEnabled: self.linkWebPreviewEnabled,
                    relativeTo: cardView,
                    returnFocusTo: self
                )
            }
            return
        }

        previewPopoverController.show(
            item: item,
            appSupportDirectory: appSupportDirectory ?? URL(fileURLWithPath: NSHomeDirectory()),
            linkWebPreviewEnabled: linkWebPreviewEnabled,
            relativeTo: cardView,
            returnFocusTo: self
        )
    }

    private func updatePreviewAfterReconcile(
        previewedItemID: String?,
        validItemIDs: Set<String>,
        closePolicy: PanelPreviewClosePolicy
    ) {
        guard let previewedItemID else { return }
        if closePolicy == .closeIfPreviewedItemRemoved, !validItemIDs.contains(previewedItemID) {
            previewPopoverController.close()
            return
        }
        guard validItemIDs.contains(previewedItemID),
              previewPopoverController.isShown
        else {
            return
        }
        guard activeListPage.itemIsFullyVisible(previewedItemID) else {
            previewPopoverController.close()
            return
        }
        guard let item = interactionController.item(withID: previewedItemID),
              let cardView = itemBandCardView(forItemID: previewedItemID)
        else {
            previewPopoverController.close()
            return
        }
        previewPopoverController.show(
            item: item,
            appSupportDirectory: appSupportDirectory ?? URL(fileURLWithPath: NSHomeDirectory()),
            linkWebPreviewEnabled: linkWebPreviewEnabled,
            relativeTo: cardView,
            returnFocusTo: self
        )
    }

    private func showManagementMenu(for item: RustClipboardItemSummary, event: NSEvent) {
        applyInteractionAction(.prepareManagementMenu(itemID: item.id))

        guard let cardView = itemBandCardView(forItemID: item.id)
        else { return }

        let menu = makeManagementMenu(for: item)
        withPanelMenuTracking {
            NSMenu.popUpContextMenu(menu, with: event, for: cardView)
        }
    }

    private func makeManagementMenu(for item: RustClipboardItemSummary) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(title: AppLocalization.text("action.copy", defaultValue: "复制"), imageName: "doc.on.doc", keyEquivalent: "c", modifierMask: [.command]) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .copy))
        })
        if item.supportsPlainTextCopyAction {
            menu.addItem(ActionMenuItem(title: AppLocalization.text("action.copyAsPlainText", defaultValue: "复制为纯文本"), imageName: "text.alignleft") { [weak self] in
                self?.applyInteractionAction(.management(itemID: item.id, action: .copyAsPlainText))
            })
        }
        if let pathText = originalImagePathText(for: item) {
            menu.addItem(ActionMenuItem(title: AppLocalization.text("action.copyPath", defaultValue: "复制路径"), imageName: "folder") { [weak self] in
                self?.onRuntimeAction?(.copyPath(pathText))
            })
        }
        menu.addItem(ActionMenuItem(title: AppLocalization.text("action.delete", defaultValue: "删除"), imageName: "trash", keyEquivalent: "\u{8}", modifierMask: []) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .delete))
        })
        menu.addItem(.separator())
        menu.addItem(makePinboardMenuItem(for: item))
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: AppLocalization.text("action.preview", defaultValue: "预览"), imageName: "eye", keyEquivalent: " ", modifierMask: []) { [weak self] in
            self?.applyInteractionAction(.management(itemID: item.id, action: .preview))
        })
        return menu
    }

    private func originalImagePathText(for item: RustClipboardItemSummary) -> String? {
        let paths = ClipboardOriginalImagePathResolver.originalImagePaths(
            for: item,
            appSupportDirectory: appSupportDirectory
        )
        guard !paths.isEmpty else { return nil }
        return paths.joined(separator: "\n")
    }

    private func makePinboardMenuItem(for item: RustClipboardItemSummary) -> NSMenuItem {
        let menuItem = NSMenuItem(title: AppLocalization.text("pinboard.pin", defaultValue: "固定"), action: nil, keyEquivalent: "")
        menuItem.image = MenuIcon.image(named: "pin", title: AppLocalization.text("pinboard.pin", defaultValue: "固定"))

        let submenu = NSMenu()
        let selectedPinboardID = panelViewState().toolbar.selectedPinboardID
        let targetItems = selectedItemsForManagementAction(containing: item)
        for pinboard in pinboardFilters {
            let membershipState = pinboardMembershipMenuState(
                items: targetItems,
                pinboardID: pinboard.id,
                selectedPinboardID: selectedPinboardID
            )
            let pinboardItem = ActionMenuItem(title: pinboard.title) { [weak self] in
                self?.applyInteractionAction(.management(
                    itemID: item.id,
                    action: .setPinboardMembership(
                        pinboardID: pinboard.id,
                        isMember: membershipState.actionAddsMembership
                    )
                ))
            }
            pinboardItem.state = membershipState.controlState
            pinboardItem.image = pinboardMenuDotImage(colorCode: pinboard.colorCode)
            submenu.addItem(pinboardItem)
        }
        if !pinboardFilters.isEmpty {
            submenu.addItem(.separator())
        }
        submenu.addItem(ActionMenuItem(title: AppLocalization.text("pinboard.createEllipsis", defaultValue: "创建 Pinboard..."), imageName: "plus") { [weak self] in
            self?.showCreatePinboardDialog()
        })

        menuItem.submenu = submenu
        menuItem.isEnabled = true
        return menuItem
    }

    private func selectedItemsForManagementAction(
        containing item: RustClipboardItemSummary
    ) -> [RustClipboardItemSummary] {
        guard panelViewState().selectedItemIDs.contains(item.id) else {
            return [item]
        }
        let itemByID = Dictionary(uniqueKeysWithValues: currentItems().map { ($0.id, $0) })
        return activeListPage.activeOrderedIDs().compactMap { itemByID[$0] }.filter {
            panelViewState().selectedItemIDs.contains($0.id)
        }
    }

    private func pinboardMembershipMenuState(
        items: [RustClipboardItemSummary],
        pinboardID: String,
        selectedPinboardID: String?
    ) -> (controlState: NSControl.StateValue, actionAddsMembership: Bool) {
        let knownMemberships = items.map {
            knownPinboardMembership(item: $0, pinboardID: pinboardID, selectedPinboardID: selectedPinboardID)
        }

        if knownMemberships.allSatisfy({ $0 == true }) {
            return (.on, false)
        }
        if knownMemberships.allSatisfy({ $0 == false }) {
            return (.off, true)
        }
        return (.mixed, true)
    }

    private func knownPinboardMembership(
        item: RustClipboardItemSummary,
        pinboardID: String,
        selectedPinboardID: String?
    ) -> Bool? {
        if !item.isPinned {
            return false
        }
        if selectedPinboardID == pinboardID {
            return true
        }
        if pinboardFilters.count == 1, pinboardID == DefaultPinboard.defaultID {
            return true
        }
        return nil
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
        listScopeCache.updateSelectionSnapshot(interactionController.selectionSnapshot(), for: currentListScope)
        activeListPage.updateSelection(selectedItemIDs: panelViewState().selectedItemIDs)

        if scrollIntoView {
            scrollSelectedItemIntoView()
        }

        refreshVisibleCommandHints()
    }

    private func scrollSelectedItemIntoView() {
        let viewState = panelViewState()
        guard let selectedItemID = viewState.selectedItemID
        else {
            return
        }
        activeListPage.scrollItemIntoView(itemID: selectedItemID)
    }

    private func startCommandHintMonitor() {
        guard commandHintMonitor == nil else { return }
        commandHintMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
                if event.type == .leftMouseDown {
                    self.scheduleEmptySearchCloseIfNeeded(for: event)
                }
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

    @discardableResult
    private func scheduleEmptySearchCloseIfNeeded(for event: NSEvent) -> Bool {
        guard shouldScheduleEmptySearchClose(for: event) else { return false }

        emptySearchClickAwayGeneration += 1
        pendingEmptySearchClose = PendingEmptySearchClose(
            generation: emptySearchClickAwayGeneration,
            locationInWindow: event.locationInWindow,
            windowNumber: event.window?.windowNumber ?? 0,
            blockingGeneration: blockingPanelOperationGeneration
        )

        DispatchQueue.main.async { [weak self] in
            self?.processPendingEmptySearchClose()
        }
        return true
    }

    private func shouldScheduleEmptySearchClose(for event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown,
              eventMatchesPanelWindow(event),
              panelViewState().toolbar.isSearchVisible,
              panelViewState().toolbar.searchText.isEmpty,
              activeRenameField == nil,
              !hasBlockingPanelOperation,
              !previewPopoverController.isShown,
              menuTrackingDepth == 0,
              !eventLocationIsInsideSearchControls(event)
        else {
            return false
        }

        return true
    }

    private func processPendingEmptySearchClose() {
        guard let pending = pendingEmptySearchClose else { return }

        if menuTrackingDepth > 0 {
            return
        }

        guard pending.generation == emptySearchClickAwayGeneration,
              pending.blockingGeneration == blockingPanelOperationGeneration,
              let window,
              window.isVisible,
              window.windowNumber == pending.windowNumber,
              panelViewState().toolbar.isSearchVisible,
              panelViewState().toolbar.searchText.isEmpty,
              activeRenameField == nil,
              !hasBlockingPanelOperation,
              !previewPopoverController.isShown
        else {
            pendingEmptySearchClose = nil
            return
        }

        if pointInWindowIsInsideSearchControls(pending.locationInWindow) {
            pendingEmptySearchClose = nil
            return
        }

        pendingEmptySearchClose = nil
        applyInteractionAction(.escape(isPreviewShown: false))
    }

    private func commitInlinePinboardRenameBeforePanelMouseDown(_ event: NSEvent) {
        guard let activeRenameField,
              event.window === window
        else { return }

        let fieldPoint = activeRenameField.convert(event.locationInWindow, from: nil)
        guard !activeRenameField.bounds.contains(fieldPoint) else { return }
        finishInlinePinboardRename(commit: true)
    }

    private func eventLocation(_ event: NSEvent, isInside view: NSView) -> Bool {
        guard event.window === view.window
                || (event.window == nil && event.windowNumber == view.window?.windowNumber)
        else { return false }
        return pointInWindow(event.locationInWindow, isInside: view)
    }

    private func eventMatchesPanelWindow(_ event: NSEvent) -> Bool {
        event.window === window
            || (event.window == nil && event.windowNumber == window?.windowNumber)
    }

    private func eventLocationIsInsideSearchControls(_ event: NSEvent) -> Bool {
        eventLocation(event, isInside: searchSlotView)
            || eventLocation(event, isInside: searchFieldRevealView)
            || searchBarView.map { eventLocation(event, isInside: $0) } == true
    }

    private func pointInWindowIsInsideSearchControls(_ point: NSPoint) -> Bool {
        pointInWindow(point, isInside: searchSlotView)
            || pointInWindow(point, isInside: searchFieldRevealView)
            || searchBarView.map { pointInWindow(point, isInside: $0) } == true
    }

    private func pointInWindow(_ pointInWindow: NSPoint, isInside view: NSView) -> Bool {
        guard view.window === window,
              !view.isHidden,
              view.alphaValue > 0.01
        else { return false }
        let point = view.convert(pointInWindow, from: nil)
        return view.bounds.contains(point)
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
        activeListPage.applyCommandHintTexts(commandNumbersByID)
    }

    private func fullyVisibleCommandItemIDs(limit: Int = 9) -> [String] {
        activeListPage.visibleCommandItemIDs(limit: limit)
    }

    private func refreshVisibleCommandHints() {
        applyInteractionAction(.visibleCommandItemsChanged(fullyVisibleCommandItemIDs()))
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

    private func armSearchCancelButtonClick() -> Bool {
        guard panelViewState().toolbar.isSearchVisible,
              !searchFieldRevealView.isHidden,
              !searchField.isHidden,
              !searchField.stringValue.isEmpty
        else {
            searchCancelButtonClickArmed = false
            return false
        }

        searchCancelButtonClickArmed = true
        return true
    }

    private func handleSearchCancelButtonClick() {
        guard searchCancelButtonClickArmed else { return }
        searchCancelButtonClickArmed = false
        searchCancelTextChangeSuppressionDepth += 1
        applyInteractionAction(.clearSearchText)
        updateSearchChromeState()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.searchCancelTextChangeSuppressionDepth = max(0, self.searchCancelTextChangeSuppressionDepth - 1)
        }
    }

    private func handleCustomSearchClearButtonClick() {
        guard panelViewState().toolbar.isSearchVisible else { return }
        applyInteractionAction(.clearSearchText)
        window?.makeFirstResponder(searchField)
        updateSearchChromeState()
    }

    private func shouldSuppressSearchTextChangeForCancelButton() -> Bool {
        guard searchField.stringValue.isEmpty else { return false }
        return searchCancelButtonClickArmed || searchCancelTextChangeSuppressionDepth > 0
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === searchField {
            if shouldSuppressSearchTextChangeForCancelButton() {
                return
            }
            applyInteractionAction(.setSearchText(searchField.stringValue))
            updateSearchChromeState()
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
        if control === searchField,
           commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            applyInteractionAction(.escape(isPreviewShown: previewPopoverController.isShown))
            return true
        }

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
        if sender.itemType != nil {
            applyInteractionAction(.setItemTypeFilter(sender.itemType))
        } else if sender.pinboardID == nil {
            applyInteractionAction(.setScopeFilters(itemType: nil, pinboardID: nil))
        } else {
            applyInteractionAction(.setPinboardFilter(sender.pinboardID))
        }
    }

    private func toggleSearchField() {
        applyInteractionAction(.toggleSearch)
    }

    private func renderItemEntries(_ entries: [PanelItemCollectionEntry]) {
        activeListPage.reload(entries: entries)
        ClipDockPerformanceLog.measure("list.updatePanelHeightAfterRender", detail: "count=\(entries.count)") {
            updatePanelHeight(currentPanelHeight)
        }
        ClipDockPerformanceLog.measure("list.refreshHintsAfterRender", detail: "count=\(entries.count)") {
            refreshVisibleCommandHints()
        }
    }

    private func makeDatabaseErrorEntry() -> PanelItemCollectionEntry {
        PanelItemCollectionEntry(
            id: "__clipdock_database_error__",
            state: statusCardState(
                itemID: "__clipdock_database_error__",
                sourceAppName: AppLocalization.text("database.unavailable", defaultValue: "数据库不可用"),
                relativeTimeText: AppLocalization.text("action.retryAvailable", defaultValue: "可重试"),
                symbolName: "exclamationmark.triangle",
                typeText: AppLocalization.text("status.error", defaultValue: "错误"),
                summaryText: AppLocalization.text("database.historyReadFailed", defaultValue: "本地历史暂时无法读取")
            ),
            callbacks: PanelItemCollectionCallbacks(
                toolTip: nil,
                onSelect: nil,
                onDoubleClick: nil,
                onContextMenu: nil
            )
        )
    }

    private func makeItemEntry(_ item: RustClipboardItemSummary) -> PanelItemCollectionEntry {
        let state = makeItemCardState(item)
        let callbacks = makeItemCardCallbacks(for: item)
        return PanelItemCollectionEntry(
            id: item.id,
            state: state,
            callbacks: PanelItemCollectionCallbacks(
                toolTip: callbacks.toolTip,
                onSelect: callbacks.onSelect,
                onDoubleClick: callbacks.onDoubleClick,
                onContextMenu: callbacks.onContextMenu
            )
        )
    }

    private func makeItemCardState(_ item: RustClipboardItemSummary) -> PanelItemCardViewState {
        PanelItemCardViewStateAdapter.makeViewState(
            for: item,
            selectedItemID: panelViewState().selectedItemID,
            selectedItemIDs: panelViewState().selectedItemIDs
        )
    }

    private func makeItemCardCallbacks(
        for item: RustClipboardItemSummary
    ) -> (
        toolTip: String?,
        onSelect: (NSEvent) -> Void,
        onDoubleClick: () -> Void,
        onContextMenu: (NSEvent) -> Void
    ) {
        (
            toolTip: nil,
            onSelect: { [weak self] event in
                self?.applySelectionFromCardMouseDown(itemID: item.id, event: event)
            },
            onDoubleClick: { [weak self] in
                self?.applyInteractionAction(.copyItem(itemID: item.id))
            },
            onContextMenu: { [weak self] event in
                self?.showManagementMenu(for: item, event: event)
            }
        )
    }

    private func applySelectionFromCardMouseDown(itemID: String, event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift) {
            applyInteractionAction(.selection(.range(toItemID: itemID)))
        } else if modifiers.contains(.command) {
            applyInteractionAction(.selection(.toggle(itemID: itemID)))
        } else {
            applyInteractionAction(.selection(.replace(itemID: itemID, scrollIntoView: true)))
        }
    }

    private func itemBandCardViews() -> [ClipboardItemCardBox] {
        activeListPage.visibleCards()
    }

    private func itemBandCardView(forItemID itemID: String) -> ClipboardItemCardBox? {
        activeListPage.visibleCardView(for: itemID)
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
        button: PanelActionButton = PanelActionButton(),
        onPress: @escaping () -> Void
    ) -> PanelActionButton {
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
        button.setAccessibilityLabel(accessibilityLabel)
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
        itemType: String? = nil,
        symbolName: String? = nil,
        dotColor: NSColor
    ) -> PinboardChipButton {
        let button = PinboardChipButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.target = nil
        button.action = nil
        button.pinboardID = pinboardID
        button.itemType = itemType
        button.chipTitleText = title
        button.chipDotColor = dotColor
        button.chipSymbolName = symbolName
        button.chipDrawsSelectionPill = true
        button.chipHeight = 28
        button.chipFontSize = 14
        button.chipDotDiameter = 11
        button.chipIconSide = 16
        button.chipMarkerTextSpacing = 6
        button.chipHorizontalPadding = (pinboardID == nil || itemType != nil) ? 11 : 9
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
            self.withPanelMenuTracking {
                NSMenu.popUpContextMenu(menu, with: event, for: button)
            }
        }
        button.toolTip = pinboardID != nil
            ? AppLocalization.text("pinboard.chip.tooltip", defaultValue: "查看固定内容，右键管理")
            : AppLocalization.text("clipboard.history", defaultValue: "剪贴板历史")
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
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: (pinboardID == nil || itemType != nil) ? 64 : 40)
        ])

        return button
    }

    private func updatePinboardChipAppearance() {
        let selectedPinboardID = panelViewState().toolbar.selectedPinboardID
        let selectedItemType = panelViewState().toolbar.selectedItemType
        pinboardButtons.forEach { button in
            let isSelected: Bool
            if let itemType = button.itemType {
                isSelected = itemType == selectedItemType
            } else if button.pinboardID != nil {
                isSelected = button.pinboardID == selectedPinboardID
            } else {
                isSelected = selectedItemType == nil && selectedPinboardID == nil
            }
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderWidth = 0
            button.layer?.shadowOpacity = 0
            button.chipIsSelected = isSelected
            button.chipTextColor = theme.panel.toolbarTextColor
            button.chipSelectedTextColor = theme.panel.toolbarSelectedTextColor
            button.chipSelectedBackgroundColor = theme.panel.toolbarSelectedBackgroundColor
            button.chipSelectedBorderColor = theme.panel.toolbarSelectedBorderColor
            button.chipSelectedBorderWidth = 1
            button.needsDisplay = true
        }
    }

}

@MainActor
extension FloatingPanelContentView {
    var smokeSelectedItemID: String? {
        panelViewState().selectedItemID
    }

    var smokeActiveListScope: ClipboardListScope {
        currentListScope
    }

    func smokePanelUsesLightBlurredBackground() -> Bool {
        switch backgroundHostState {
        case .systemGlass:
            return true
        case .legacyVisualEffect(let tintAlpha):
            return tintAlpha >= 0.30
        case .none:
            return false
        }
    }

    func smokePanelUsesWindowLocalBackdropBlend() -> Bool {
        switch backgroundHostState {
        case .systemGlass:
            return true
        case .legacyVisualEffect:
            guard let effectView = superview as? NSVisualEffectView else { return false }
            return effectView.blendingMode == .withinWindow && effectView.state == .active
        case .none:
            return false
        }
    }

    var smokePanelContentBackgroundAlpha: CGFloat {
        layer?.backgroundColor?.alpha ?? 0
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

    var smokeFirstResponderIsSearchField: Bool {
        window?.firstResponder === searchField
            || window?.firstResponder === searchField.currentEditor()
    }

    var smokeIsSearchVisible: Bool {
        panelViewState().toolbar.isSearchVisible
            && !searchSlotView.isHidden
            && !searchFieldRevealView.isHidden
            && !searchField.isHidden
    }

    var smokeSearchText: String {
        panelViewState().toolbar.searchText
    }

    var smokeSearchFieldWidth: CGFloat {
        searchSlotWidthConstraint?.constant ?? searchSlotView.frame.width
    }

    var smokeSearchFieldHeight: CGFloat {
        searchFieldRevealView.frame.height
    }

    var smokeSearchInputFieldHeight: CGFloat {
        searchField.frame.height
    }

    var smokeSearchInputFieldVerticalCenterOffset: CGFloat {
        guard let searchBarView else { return .greatestFiniteMagnitude }
        let inputMidY = searchField.convert(searchField.bounds, to: searchBarView).midY
        return inputMidY - searchBarView.bounds.midY
    }

    var smokeSearchFieldFontWeight: CGFloat {
        guard
            let font = searchField.font,
            let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
            let weight = traits[.weight]
        else {
            return .greatestFiniteMagnitude
        }
        if let number = weight as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        return weight as? CGFloat ?? .greatestFiniteMagnitude
    }

    var smokeSearchFieldInnerWidth: CGFloat {
        searchBarView?.frame.width ?? searchFieldRevealView.frame.width
    }

    var smokeSearchFieldAlpha: CGFloat {
        searchFieldRevealView.alphaValue
    }

    var smokeSearchFieldIsHidden: Bool {
        searchFieldRevealView.isHidden || searchField.isHidden
    }

    var smokeToolbarSearchButtonIsHidden: Bool {
        guard let toolbarSearchButton else { return false }
        return toolbarSearchButton.isHidden || toolbarSearchButton.alphaValue < 0.01
    }

    var smokeToolbarSearchButtonAllowsHitTesting: Bool {
        guard let toolbarSearchButton else { return false }
        return toolbarSearchButton.hitTest(NSPoint(x: toolbarSearchButton.bounds.midX, y: toolbarSearchButton.bounds.midY)) != nil
    }

    var smokeSearchClearButtonIsVisible: Bool {
        guard let clearButton = searchBarView?.clearButton else { return false }
        return !clearButton.isHidden && clearButton.isEnabled && clearButton.alphaValue > 0.01
    }

    var smokeSearchClearButtonAccessibilityLabel: String? {
        searchBarView?.clearButton.accessibilityLabel()
    }

    var smokeSearchFieldAccessibilityLabel: String? {
        searchField.accessibilityLabel()
    }

    var smokeToolbarSearchButtonAccessibilityLabel: String? {
        toolbarSearchButton?.accessibilityLabel()
    }

    var smokeSearchChromeCornerRadius: CGFloat {
        searchBarView?.smokeCornerRadius ?? 0
    }

    var smokeSearchChromeBackgroundAlpha: CGFloat {
        searchBarView?.smokeBackgroundAlpha ?? 0
    }

    var smokeSearchChromeBorderAlpha: CGFloat {
        searchBarView?.smokeBorderAlpha ?? 0
    }

    var smokeSearchLeadingIconIsVisible: Bool {
        guard let icon = searchBarView?.leadingIconView else { return false }
        return !icon.isHidden && icon.image != nil && icon.alphaValue > 0.01
    }

    var smokeSearchClickAwayDiagnostic: String {
        let toolbar = panelViewState().toolbar
        return "visible=\(toolbar.isSearchVisible) text=\(toolbar.searchText.debugDescription) fieldHidden=\(searchFieldRevealView.isHidden || searchField.isHidden) rename=\(activeRenameField != nil) blocking=\(hasBlockingPanelOperation) preview=\(previewPopoverController.isShown) menuDepth=\(menuTrackingDepth) window=\(window?.windowNumber ?? 0)"
    }

    func smokeOpenSearch(text: String) {
        applyInteractionAction(.focusSearch)
        applySearchFieldVisibilityFinalState(true)
        searchField.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        updateSearchChromeState()
        layoutSubtreeIfNeeded()
    }

    @discardableResult
    func smokeClickLeadingSearchChrome() -> Bool {
        guard let searchBarView,
              let window = searchBarView.window
        else { return false }
        let localPoint = NSPoint(x: 18, y: searchBarView.bounds.midY)
        let windowPoint = searchBarView.convert(localPoint, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else { return false }
        searchBarView.mouseDown(with: event)
        return true
    }

    @discardableResult
    func smokeClickCustomSearchClearButton() -> Bool {
        guard let clearButton = searchBarView?.clearButton,
              !clearButton.isHidden,
              clearButton.isEnabled,
              let event = smokeMouseDownEvent(centeredIn: clearButton)
        else { return false }
        clearButton.mouseDown(with: event)
        return true
    }

    @discardableResult
    func smokeToggleSearchFromToolbarButton() -> Bool {
        guard let toolbarSearchButton,
              let event = smokeMouseDownEvent(centeredIn: toolbarSearchButton)
        else { return false }
        toolbarSearchButton.mouseDown(with: event)
        return true
    }

    func smokeClearFilters() {
        applyInteractionAction(.clearFilters)
    }

    @discardableResult
    func smokeNativeSearchCancelTextChangeBeforeAction() -> Bool {
        guard smokeArmSearchCancelButtonClick() else { return false }
        searchField.stringValue = ""
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        handleSearchCancelButtonClick()
        return true
    }

    @discardableResult
    func smokeNativeSearchCancelActionBeforeTextChange() -> Bool {
        guard smokeArmSearchCancelButtonClick() else { return false }
        handleSearchCancelButtonClick()
        searchField.stringValue = ""
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        return true
    }

    @discardableResult
    func smokeClickNativeSearchCancelButton() -> Bool {
        guard let event = smokeSearchCancelMouseDownEvent() else { return false }
        searchField.mouseDown(with: event)
        return true
    }

    private func smokeArmSearchCancelButtonClick() -> Bool {
        guard let event = smokeSearchCancelMouseDownEvent(),
              searchField.isCancelButtonHit(event)
        else { return false }
        return armSearchCancelButtonClick()
    }

    private func smokeSearchCancelMouseDownEvent() -> NSEvent? {
        guard let windowPoint = searchField.cancelButtonCenterInWindowForSmoke() else { return nil }
        return NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: searchField.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    @discardableResult
    func smokeCancelSearchOperation() -> Bool {
        control(
            searchField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        )
    }

    @discardableResult
    func smokeClickCardWithSearchClickAway(itemID: String) -> Bool {
        guard let card = smokeOrderedCardBoxes().first(where: { $0.itemID == itemID }),
              let event = smokeMouseDownEvent(centeredIn: card)
        else { return false }
        let didSchedule = scheduleEmptySearchCloseIfNeeded(for: event)
        card.mouseDown(with: event)
        return didSchedule
    }

    func smokeClickFirstCardWithSearchClickAway() -> String? {
        guard let card = smokeOrderedCardBoxes().first,
              let event = smokeMouseDownEvent(centeredIn: card)
        else { return nil }
        guard scheduleEmptySearchCloseIfNeeded(for: event) else { return nil }
        card.mouseDown(with: event)
        return card.itemID
    }

    @discardableResult
    func smokeClickPinboardFilterWithSearchClickAway(pinboardID: String?) -> Bool {
        guard let button = smokePinboardFilterButton(pinboardID: pinboardID),
              let event = smokeMouseDownEvent(centeredIn: button)
        else { return false }
        let didSchedule = scheduleEmptySearchCloseIfNeeded(for: event)
        button.mouseDown(with: event)
        return didSchedule
    }

    func smokeMenuTrackingDefersEmptySearchClickAway(
        makeSearchNonEmptyBeforeExit: Bool
    ) -> (pendingDuringTracking: Bool, searchVisibleDuringTracking: Bool) {
        guard let sourceView = toolbarIconButtons.first(where: { $0.toolTip == AppLocalization.text("panel.more", defaultValue: "更多功能") }),
              let event = smokeMouseDownEvent(centeredIn: sourceView)
        else {
            return (pendingDuringTracking: false, searchVisibleDuringTracking: smokeIsSearchVisible)
        }

        scheduleEmptySearchCloseIfNeeded(for: event)
        var result = (pendingDuringTracking: false, searchVisibleDuringTracking: false)
        withPanelMenuTracking {
            result.pendingDuringTracking = pendingEmptySearchClose != nil
            result.searchVisibleDuringTracking = smokeIsSearchVisible
            if makeSearchNonEmptyBeforeExit {
                searchField.stringValue = "menu"
                controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
            }
        }
        return result
    }

    private func smokeMouseDownEvent(
        centeredIn view: NSView,
        type: NSEvent.EventType = .leftMouseDown,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        let localPoint = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        let windowPoint = view.convert(localPoint, to: nil)
        return NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    func smokeCardBoxes() -> [ClipboardItemCardBox] {
        activeListPage.visibleCards()
    }

    func smokeOrderedCardBoxes() -> [ClipboardItemCardBox] {
        activeListPage.visibleCards()
    }

    var smokeSelectedItemIDs: Set<String> {
        panelViewState().selectedItemIDs
    }

    func smokeSelectedCardIDs() -> [String] {
        smokeOrderedCardBoxes().compactMap { card in
            guard let itemID = card.itemID,
                  panelViewState().selectedItemIDs.contains(itemID)
            else { return nil }
            return itemID
        }
    }

    func smokeClickCard(itemID: String, modifiers: NSEvent.ModifierFlags = []) {
        guard let card = smokeOrderedCardBoxes().first(where: { $0.itemID == itemID }),
              let event = smokeMouseDownEvent(centeredIn: card, modifierFlags: modifiers)
        else { return }
        card.mouseDown(with: event)
    }

    func smokeRightClickCard(itemID: String) {
        guard let card = smokeOrderedCardBoxes().first(where: { $0.itemID == itemID }),
              let event = smokeMouseDownEvent(centeredIn: card, type: .rightMouseDown)
        else { return }
        card.rightMouseDown(with: event)
    }

    func smokePrepareManagementMenu(itemID: String) {
        applyInteractionAction(.prepareManagementMenu(itemID: itemID))
    }

    func smokeSendArrow(_ direction: PanelQAHarness.ArrowDirection, modifiers: NSEvent.ModifierFlags = []) {
        let character: String
        let keyCode: Int
        switch direction {
        case .left:
            character = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
            keyCode = kVK_LeftArrow
        case .right:
            character = String(UnicodeScalar(NSRightArrowFunctionKey)!)
            keyCode = kVK_RightArrow
        }

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ) else { return }

        keyDown(with: event)
    }

    func smokeOrderedCardItemIDs() -> [String] {
        activeListPage.activeOrderedIDs()
    }

    func smokeCardsContainWebView() -> Bool {
        smokeCardBoxes().contains { card in
            allSmokeSubviews(of: card).contains { $0 is WKWebView }
        }
    }

    func smokeCardBoxObjectIdentifiers() -> [ObjectIdentifier] {
        smokeOrderedCardBoxes().map { ObjectIdentifier($0) }
    }

    var smokeRenderedCardTrackingIsConsistent: Bool {
        let orderedIDs = smokeOrderedCardItemIDs()
        return Set(orderedIDs).count == orderedIDs.count
    }

    var smokeRetainedCollectionSurfaceCount: Int {
        activeListPage.totalRetainedReusableCellOrHostedCardCount()
    }

    var smokeCollectionRetainedCellBound: Int {
        let viewportWidth = itemBandScrollView?.contentView.bounds.width ?? bounds.width
        let metrics = itemCollectionLayoutMetrics()
        let hostSide = PanelItemCollectionGeometry.hostSide(
            for: metrics.itemSide,
            shadowOutset: metrics.shadowOutset
        )
        let effectiveSpacing = PanelItemCollectionGeometry.effectiveItemSpacing(
            itemSpacing: metrics.itemSpacing,
            shadowOutset: metrics.shadowOutset
        )
        return Int(ceil((viewportWidth + effectiveSpacing) / (hostSide + effectiveSpacing))) + 8
    }

    func smokeVisibleCommandItemIDs(limit: Int = 9) -> [String] {
        fullyVisibleCommandItemIDs(limit: limit)
    }

    func smokePinboardFilterButton(pinboardID: String?) -> PinboardChipButton? {
        pinboardButtons.first { $0.pinboardID == pinboardID }
    }

    func smokeItemTypeFilterButton(itemType: String) -> PinboardChipButton? {
        pinboardButtons.first { $0.itemType == itemType }
    }

    var smokeCreatePinboardButtonFollowsPinboardChipsInToolbarOrder: Bool {
        guard let filterRow,
              let createPinboardButton,
              let createIndex = filterRow.arrangedSubviews.firstIndex(where: { $0 === createPinboardButton })
        else { return false }

        return pinboardButtons.allSatisfy { button in
            guard let chipIndex = filterRow.arrangedSubviews.firstIndex(where: { $0 === button }) else {
                return false
            }
            return chipIndex < createIndex
        }
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
        let maxX = activeListPage.horizontalScrollRange().upperBound
        scrollView.contentView.scroll(to: NSPoint(x: maxX, y: scrollView.contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        handleItemBandScrollDidChange()
    }

    var smokeScrollOriginX: CGFloat {
        itemBandScrollView?.contentView.bounds.origin.x ?? 0
    }

    var smokeScrollOrigin: NSPoint {
        itemBandScrollView?.contentView.bounds.origin ?? .zero
    }

    func smokeSelectItem(id: String, scrollIntoView: Bool = true) {
        applyInteractionAction(.selectItem(id: id, scrollIntoView: scrollIntoView))
    }

    func smokeClickCard(itemID: String) {
        guard let card = smokeOrderedCardBoxes().first(where: { $0.itemID == itemID }) else { return }
        let localPoint = NSPoint(x: card.bounds.midX, y: card.bounds.midY)
        let windowPoint = card.convert(localPoint, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: card.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            return
        }
        card.mouseDown(with: event)
    }

    var smokeScrollEdgeOverlayState: (leadingVisible: Bool, trailingVisible: Bool, leadingHitTestNil: Bool, trailingHitTestNil: Bool) {
        (leadingVisible: false, trailingVisible: false, leadingHitTestNil: true, trailingHitTestNil: true)
    }

    var smokeItemBandLayoutMetrics: (
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        verticalEdgeInsets: (CGFloat, CGFloat),
        scrollOriginX: CGFloat,
        viewportWidth: CGFloat,
        trailingContentEdgeOriginX: CGFloat?,
        firstCardVisibleMinX: CGFloat?,
        lastCardVisibleMaxXAtTrailingEdge: CGFloat?,
        firstCardDocumentMinX: CGFloat?,
        lastCardDocumentTrailingInset: CGFloat?,
        itemBandHeight: CGFloat,
        collectionDocumentHeight: CGFloat,
        itemBandBottomPadding: CGFloat,
        shadowOutset: CGFloat
    ) {
        layoutSubtreeIfNeeded()
        itemBandDocumentView.layoutSubtreeIfNeeded()

        let metrics = itemCollectionLayoutMetrics()
        let bandFrame = itemBandContainerView.frame
        let scrollView = itemBandScrollView
        let scrollOriginX = scrollView?.contentView.bounds.origin.x ?? 0
        let viewportWidth = scrollView?.contentView.bounds.width ?? 0
        let trailingContentEdgeOriginX = scrollView.map { scrollView in
            activeListPage.collectionDocumentWidth() - scrollView.contentView.bounds.width
        }
        let firstCardMinX = activeListPage.firstItemFrame()?.minX
        let firstCardVisibleMinX = firstCardMinX.map { $0 - scrollOriginX }
        let lastFrame = activeListPage.lastItemFrame()
        let lastCardTrailingInset = lastFrame.map { activeListPage.collectionDocumentWidth() - $0.maxX }
        let lastCardVisibleMaxXAtTrailingEdge = scrollView.flatMap { scrollView in
            lastFrame.map { $0.maxX - scrollOriginX }
        }

        return (
            leadingInset: bandFrame.minX,
            trailingInset: bounds.width - bandFrame.maxX,
            verticalEdgeInsets: (bandFrame.minY, bounds.height - bandFrame.maxY),
            scrollOriginX: scrollOriginX,
            viewportWidth: viewportWidth,
            trailingContentEdgeOriginX: trailingContentEdgeOriginX,
            firstCardVisibleMinX: firstCardVisibleMinX,
            lastCardVisibleMaxXAtTrailingEdge: lastCardVisibleMaxXAtTrailingEdge,
            firstCardDocumentMinX: firstCardMinX,
            lastCardDocumentTrailingInset: lastCardTrailingInset,
            itemBandHeight: bandFrame.height,
            collectionDocumentHeight: itemBandDocumentView.frame.height,
            itemBandBottomPadding: itemBandBottomPadding(shadowOutset: metrics.shadowOutset),
            shadowOutset: metrics.shadowOutset
        )
    }

    func smokeScrollToX(_ x: CGFloat) {
        guard let scrollView = itemBandScrollView else { return }
        layoutSubtreeIfNeeded()
        itemBandDocumentView.layoutSubtreeIfNeeded()
        let range = activeListPage.horizontalScrollRange()
        scrollView.contentView.scroll(to: NSPoint(
            x: min(max(range.lowerBound, x), range.upperBound),
            y: scrollView.contentView.bounds.origin.y
        ))
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

    func smokePreviewRootBackgroundColor() -> NSColor? {
        previewPopoverController.contentRootViewForSmoke?
            .layer?
            .backgroundColor
            .flatMap(NSColor.init(cgColor:))
    }

    func smokePreviewDirectSubviewBackgroundColors() -> [NSColor] {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return [] }
        return rootView.subviews.compactMap { subview in
            subview.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        }
    }

    func smokePreviewActionButtonToolTips() -> [String] {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return [] }
        return allSmokeSubviews(of: rootView)
            .compactMap { $0 as? NSButton }
            .compactMap(\.toolTip)
    }

    func smokePreviewContainsQuickLookView() -> Bool {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return false }
        return allSmokeSubviews(of: rootView).contains { $0 is QLPreviewView }
    }

    func smokePreviewContainsWebView() -> Bool {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return false }
        return allSmokeSubviews(of: rootView).contains { $0 is WKWebView }
    }

    func smokePreviewWebViewURLString() -> String? {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return nil }
        let webView = allSmokeSubviews(of: rootView)
            .compactMap { $0 as? WKWebView }
            .first
        return webView?.url?.absoluteString
            ?? webView?.backForwardList.currentItem?.url.absoluteString
    }

    func smokePreviewQuickLookAcceptsFirstResponder() -> Bool? {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return nil }
        return allSmokeSubviews(of: rootView)
            .compactMap { $0 as? QLPreviewView }
            .first?
            .acceptsFirstResponder
    }

    func smokePreviewTextContent() -> String {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return "" }
        return allSmokeSubviews(of: rootView)
            .compactMap { $0 as? NSTextView }
            .map(\.string)
            .joined(separator: "\n")
    }

    func smokePreviewLabelTexts() -> [String] {
        guard let rootView = previewPopoverController.contentRootViewForSmoke else { return [] }
        return allSmokeSubviews(of: rootView)
            .compactMap { $0 as? NSTextField }
            .map(\.stringValue)
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

    func smokeManagementSubmenuItems(itemID: String, title: String) -> [
        (title: String, isEnabled: Bool, isSelected: Bool, hasImage: Bool)
    ] {
        guard let item = currentItems().first(where: { $0.id == itemID }) else { return [] }
        guard let submenu = makeManagementMenu(for: item).items.first(where: { $0.title == title })?.submenu else {
            return []
        }

        return submenu.items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                isEnabled: menuItem.isEnabled,
                isSelected: menuItem.state == .on,
                hasImage: menuItem.image != nil
            )
        }
    }

    func smokeManagementPinboardMenuWithNoPinboards(itemID: String) -> (
        isEnabled: Bool,
        titles: [String],
        allItemsHaveImages: Bool
    )? {
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
        let allItemsHaveImages = pinboardMenuItem.submenu?.items.allSatisfy { item in
            item.isSeparatorItem || item.image != nil
        } ?? true
        return (isEnabled: pinboardMenuItem.isEnabled, titles: titles, allItemsHaveImages: allItemsHaveImages)
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
        let keptCurrentSelection = panelViewState().toolbar.selectedPinboardID == previousSelectedPinboardID

        cancelInlinePinboardRename()
        updatePinboards(previousSummaries)
        pendingCreatedPinboardSourceIDs = previousPendingIDs
        applyInteractionAction(.setPinboardFilter(previousSelectedPinboardID))
        onRuntimeAction = previousAction
        return isInline && keptCurrentSelection
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

        let menu = makePinboardChipManagementMenu(for: pinboard)
        withPanelMenuTracking {
            menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.midX, y: button.bounds.midY), in: button)
        }
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

    var smokeHasBlockingPanelOperation: Bool {
        hasBlockingPanelOperation
    }

    func smokeWithBlockingPanelOperation(_ body: () -> Void) {
        _ = runBlockingPanelModal {
            body()
            return .alertFirstButtonReturn
        }
    }

    func smokeBlockingPanelModalProbe() -> (
        outerDuring: Bool,
        nestedDuring: Bool,
        afterNested: Bool,
        afterOuter: Bool,
        responses: [NSApplication.ModalResponse]
    ) {
        var outerDuring = false
        var nestedDuring = false
        var afterNested = false
        var responses: [NSApplication.ModalResponse] = []

        let outerResponse = runBlockingPanelModal {
            outerDuring = hasBlockingPanelOperation
            let nestedResponse = runBlockingPanelModal {
                nestedDuring = hasBlockingPanelOperation
                return .alertSecondButtonReturn
            }
            responses.append(nestedResponse)
            afterNested = hasBlockingPanelOperation
            return .alertFirstButtonReturn
        }
        responses.append(outerResponse)

        let cancelResponse = runBlockingPanelModal {
            .alertSecondButtonReturn
        }
        responses.append(cancelResponse)

        return (
            outerDuring: outerDuring,
            nestedDuring: nestedDuring,
            afterNested: afterNested,
            afterOuter: hasBlockingPanelOperation,
            responses: responses
        )
    }

    func smokeToolbarButtonToolTips() -> [String] {
        allSmokeSubviews(of: self)
            .compactMap { ($0 as? PanelActionButton)?.toolTip }
    }

    func smokePanelOverflowMenuItems() -> [
        (title: String, isEnabled: Bool, hasSubmenu: Bool, hasCustomView: Bool, hasImage: Bool)
    ] {
        makePanelOverflowMenu().items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                isEnabled: menuItem.isEnabled,
                hasSubmenu: menuItem.submenu != nil,
                hasCustomView: menuItem.view != nil,
                hasImage: menuItem.image != nil
            )
        }
    }

    func smokePerformPanelOverflowAction(title: String) -> Bool {
        guard let item = actionMenuItem(in: makePanelOverflowMenu(), title: title) else { return false }
        item.triggerForSmoke()
        return true
    }

    func smokePinboardChipMenuItems(pinboardID: String) -> [
        (title: String, isEnabled: Bool, hasSubmenu: Bool, hasCustomView: Bool, hasImage: Bool)
    ] {
        guard let pinboard = pinboardFilters.first(where: { $0.id == pinboardID }) else { return [] }
        return makePinboardChipManagementMenu(for: pinboard).items.compactMap { menuItem in
            guard !menuItem.isSeparatorItem else { return nil }
            return (
                title: menuItem.title,
                isEnabled: menuItem.isEnabled,
                hasSubmenu: menuItem.submenu != nil,
                hasCustomView: menuItem.view != nil,
                hasImage: menuItem.image != nil
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

private extension RustClipboardItemSummary {
    var supportsPlainTextCopyAction: Bool {
        switch itemType {
        case "text", "rich_text":
            let text = primaryText ?? summary
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }
}
