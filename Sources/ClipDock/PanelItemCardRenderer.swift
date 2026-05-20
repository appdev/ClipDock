import AppKit
import ClipboardPanelApp

struct PanelItemCardRendererMetrics {
    let defaultItemSide: CGFloat
    let cardCornerRadius: CGFloat
    let innerCornerRadius: CGFloat
    let cardHeaderHeight: CGFloat
    let cardInset: CGFloat
    let cardFooterHeight: CGFloat
    let sourceIconSize: CGFloat
    let linkPreviewHeight: CGFloat
    let theme: ClipDockThemePalette
}

struct PanelItemCardRenderArtifacts {
    let itemWidthConstraint: NSLayoutConstraint
    let itemHeightConstraint: NSLayoutConstraint
    let previewHeightConstraints: [NSLayoutConstraint]
    let previewWidthConstraints: [NSLayoutConstraint]
    let imagePreviewViews: [NSImageView]
    let footnoteBadgeViews: [NSView]
    let bodyLabels: [PanelItemCardBodyTextView]
    let linkPreviewViews: [NSView]
    let linkIconViews: [NSImageView]
    let sourceIconViews: [NSImageView]

    @MainActor
    func prepareForRemoval() {
        for imageView in imagePreviewViews + linkIconViews + sourceIconViews {
            imageView.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)
            (imageView as? PanelCardAsyncWorkCancellable)?.cancelPanelCardAsyncWork()
        }
    }

    @MainActor
    func previewImageLoadTokensForSmoke() -> [PanelPreviewImageLoadToken] {
        (imagePreviewViews + linkIconViews).compactMap {
            ($0 as? PanelCardPreviewImageLoadTokenProviding)?.previewImageLoadToken
        }
    }

    @MainActor
    func filePreviewThumbnailTokensForSmoke() -> [PanelFilePreviewThumbnailToken] {
        imagePreviewViews.compactMap {
            ($0 as? PanelCardFilePreviewThumbnailTokenProviding)?.thumbnailToken
        }
    }
}

struct PanelRenderedItemCard {
    let state: PanelItemCardViewState
    let view: NSView
    let cardView: ClipboardItemCardBox
    let artifacts: PanelItemCardRenderArtifacts
}

@MainActor
final class PanelItemCardShadowHostView: NSView {
    let cardView: ClipboardItemCardBox
    var visualCardSide: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    var shadowOutset: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }
    var cardCornerRadius: CGFloat {
        didSet {
            updateShadowPath()
        }
    }

    init(
        cardView: ClipboardItemCardBox,
        visualCardSide: CGFloat,
        shadowOutset: CGFloat,
        cardCornerRadius: CGFloat,
        shadowOpacity: Float,
        shadowRadius: CGFloat,
        shadowOffset: CGSize,
        backingScaleFactor: CGFloat
    ) {
        self.cardView = cardView
        self.visualCardSide = visualCardSide
        self.shadowOutset = shadowOutset
        self.cardCornerRadius = cardCornerRadius
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = shadowRadius
        layer?.shadowOffset = shadowOffset
        layer?.contentsScale = backingScaleFactor
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardView.frame = cardFrameInHost
        updateShadowPath()
        CATransaction.commit()
    }

    override var intrinsicContentSize: NSSize {
        let hostSide = visualCardSide + 2 * shadowOutset
        return NSSize(width: hostSide, height: hostSide)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBackingScaleAndShadowPath()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshBackingScaleAndShadowPath()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard cardFrameInHost.contains(point) else { return nil }
        return super.hitTest(point)
    }

    private var cardFrameInHost: NSRect {
        bounds.insetBy(dx: shadowOutset, dy: shadowOutset)
    }

    private func refreshBackingScaleAndShadowPath() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        cardView.layer?.contentsScale = scale
        cardView.contentView?.layer?.contentsScale = scale
        updateShadowPath()
    }

    private func updateShadowPath() {
        guard !bounds.isEmpty else {
            layer?.shadowPath = nil
            return
        }
        layer?.shadowPath = CGPath(
            roundedRect: cardFrameInHost,
            cornerWidth: cardCornerRadius,
            cornerHeight: cardCornerRadius,
            transform: nil
        )
    }
}

@MainActor
final class PanelItemCardRenderer {
    private let cardAssetResolver: PanelCardAssetResolver
    private let metrics: PanelItemCardRendererMetrics
    private let backingScaleFactor: CGFloat

    init(
        cardAssetResolver: PanelCardAssetResolver,
        metrics: PanelItemCardRendererMetrics,
        backingScaleFactor: CGFloat
    ) {
        self.cardAssetResolver = cardAssetResolver
        self.metrics = metrics
        self.backingScaleFactor = backingScaleFactor
    }

    func render(
        _ state: PanelItemCardViewState,
        toolTip: String? = nil,
        onSelect: ((NSEvent) -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onContextMenu: ((NSEvent) -> Void)? = nil
    ) -> PanelRenderedItemCard {
        let resolvedItem = cardAssetResolver.resolvedItem(for: state.assetRequest)
        let isTextLikeItem = state.symbolName == "doc.text" || state.symbolName == "doc.richtext"
        let cardBackgroundColor = isTextLikeItem
            ? metrics.theme.card.textItemBackgroundColor
            : metrics.theme.card.backgroundColor

        let iconView = SourceIconImageView()
        iconView.image = resolvedItem.sourceIconImage

        let previewBundle = makePreviewBundle(
            state.preview,
            assetRequest: state.assetRequest
        )

        let container = ClipboardItemCardBox()
        container.boxType = .custom
        container.borderColor = .clear
        container.borderWidth = 0
        container.fillColor = cardBackgroundColor
        container.cornerRadius = metrics.cardCornerRadius
        container.contentViewMargins = .zero
        container.wantsLayer = true
        container.layer?.cornerRadius = metrics.cardCornerRadius
        container.layer?.masksToBounds = true
        container.layer?.contentsScale = backingScaleFactor
        container.contentView?.wantsLayer = true
        container.contentView?.layer?.masksToBounds = true
        container.contentView?.layer?.contentsScale = backingScaleFactor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.toolTip = toolTip
        container.itemID = state.itemID
        container.onSelect = onSelect
        container.onDoubleClick = onDoubleClick
        container.onContextMenu = onContextMenu

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = metrics.innerCornerRadius
        iconView.layer?.masksToBounds = true
        iconView.layer?.backgroundColor = metrics.theme.card.sourceIconBackgroundColor.cgColor
        iconView.layer?.borderWidth = 0
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOpacity = 0.14
        iconView.layer?.shadowRadius = 3
        iconView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        iconView.layer?.contentsScale = backingScaleFactor
        iconView.toolTip = state.sourceAppName
        iconView.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)
        if resolvedItem.sourceIconImage == nil,
           let sourceIconPath = state.assetRequest.sourceAppIconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceIconPath.isEmpty {
            let loadIdentifier = iconView.identifier
            iconView.previewImageLoadToken = PanelCardAssetResolver.loadPreviewImageAsync(paths: [sourceIconPath]) { [weak iconView] image in
                guard iconView?.identifier == loadIdentifier,
                      let image
                else { return }
                iconView?.previewImageLoadToken = nil
                iconView?.image = image
            }
        }

        let typeHeaderLabel = NSTextField(labelWithString: state.typeText)
        typeHeaderLabel.identifier = NSUserInterfaceItemIdentifier("PanelCardTypeLabel")
        typeHeaderLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        typeHeaderLabel.textColor = headerTextColor(isSelected: state.isSelected)
        typeHeaderLabel.lineBreakMode = .byTruncatingTail
        typeHeaderLabel.maximumNumberOfLines = 1
        configureLeftToRightText(typeHeaderLabel)

        let timeLabel = NSTextField(labelWithString: state.relativeTimeText)
        timeLabel.identifier = NSUserInterfaceItemIdentifier("PanelCardTimeLabel")
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = headerSecondaryTextColor(isSelected: state.isSelected)
        timeLabel.lineBreakMode = .byTruncatingTail
        timeLabel.maximumNumberOfLines = 1
        configureLeftToRightText(timeLabel)

        let headerTextStack = NSStackView(views: [typeHeaderLabel, timeLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 2
        headerTextStack.userInterfaceLayoutDirection = .leftToRight

        let headerView = NSView()
        headerView.identifier = NSUserInterfaceItemIdentifier("PanelCardHeader")
        headerView.userInterfaceLayoutDirection = .leftToRight
        headerView.wantsLayer = true
        let unselectedHeaderColor = cardAssetResolver.headerColor(
            forTypeText: state.typeText,
            sourceColorKey: resolvedItem.sourceColorKey,
            sourceIconColor: resolvedItem.sourceIconColor,
            isSelected: false
        )
        headerView.layer?.backgroundColor = cardAssetResolver.headerColor(
            forTypeText: state.typeText,
            sourceColorKey: resolvedItem.sourceColorKey,
            sourceIconColor: resolvedItem.sourceIconColor,
            isSelected: state.isSelected
        ).cgColor
        headerView.layer?.cornerRadius = metrics.cardCornerRadius
        headerView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        headerView.layer?.masksToBounds = true
        headerView.layer?.contentsScale = backingScaleFactor
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerTextStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerTextStack)
        headerView.addSubview(iconView)
        container.configureSelectionAppearance(
            headerView: headerView,
            typeHeaderLabel: typeHeaderLabel,
            timeLabel: timeLabel,
            unselectedHeaderColor: unselectedHeaderColor,
            selectionBorderColor: metrics.theme.card.selectionBorderColor,
            headerTextColor: metrics.theme.card.headerTextColor,
            headerSecondaryTextColor: metrics.theme.card.headerSecondaryTextColor,
            isSelected: state.isSelected
        )

        let isImageCard: Bool
        if case .image = state.preview {
            isImageCard = true
        } else {
            isImageCard = false
        }
        let isLinkCard: Bool
        if case .link = state.preview {
            isLinkCard = true
        } else {
            isLinkCard = false
        }
        let isColorCard: Bool
        if case .color = state.preview {
            isColorCard = true
        } else {
            isColorCard = false
        }
        let isTextBodyCard = !isImageCard
            && !isLinkCard
            && !isColorCard
            && isTextLikeItem
            && !state.summaryText.isEmpty

        let summaryLabel = makeBodyLabel(
            state.summaryText,
            assetRequest: state.assetRequest,
            usesRichTextPreview: isTextLikeItem
        )
        let contentFillsAvailableArea = isImageCard || isLinkCard || isColorCard
        let contentContainer = makeCardContentContainer(
            previewView: previewBundle.view,
            summaryLabel: summaryLabel,
            fillsAvailableArea: contentFillsAvailableArea,
            showsSummary: !isColorCard
        )
        let isFileCard: Bool
        if case .file = state.preview {
            isFileCard = true
        } else {
            isFileCard = false
        }
        let linkFooterTitle: String?
        if case .link(let title, _, _, _, _, _) = state.preview {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            linkFooterTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        } else {
            linkFooterTitle = nil
        }

        let indexLabel = NSTextField(labelWithString: "")
        indexLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        indexLabel.textColor = self.colorSurfaceForegroundColor(for: state.preview) ?? .tertiaryLabelColor
        indexLabel.lineBreakMode = .byTruncatingTail
        indexLabel.identifier = NSUserInterfaceItemIdentifier(
            isColorCard ? "ColorCardCommandIndexLabel" : "PanelCardCommandIndexLabel"
        )
        configureLeftToRightText(indexLabel, alignment: .right)
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)
        indexLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        indexLabel.stringValue = state.commandIndexText ?? ""
        indexLabel.isHidden = state.commandIndexText == nil

        let countLabel = NSTextField(labelWithString: state.footnoteText)
        countLabel.font = isImageCard
            ? .systemFont(ofSize: 12.5, weight: .medium)
            : (isLinkCard
                ? .systemFont(ofSize: linkFooterTitle == nil ? 13.5 : 12.5, weight: .regular)
                : .systemFont(ofSize: 10.5, weight: .medium))
        countLabel.textColor = isImageCard
            ? metrics.theme.card.imageFootnoteTextColor
            : (isLinkCard ? metrics.theme.card.secondaryTextColor : metrics.theme.card.footerTextColor)
        countLabel.lineBreakMode = isFileCard ? .byTruncatingMiddle : .byTruncatingTail
        countLabel.maximumNumberOfLines = isFileCard ? 2 : 1
        countLabel.preferredMaxLayoutWidth = metrics.defaultItemSide - metrics.cardInset * 2 - 26
        countLabel.cell?.wraps = isFileCard
        countLabel.cell?.isScrollable = false
        countLabel.cell?.lineBreakMode = countLabel.lineBreakMode
        configureLeftToRightText(countLabel, alignment: isLinkCard ? .left : .center)
        countLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.isHidden = isColorCard

        let linkTitleLabel = linkFooterTitle.map { title in
            let label = NSTextField(labelWithString: leftToRightDisplayText(title))
            label.font = .systemFont(ofSize: 14.5, weight: .semibold)
            label.textColor = metrics.theme.card.primaryTextColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            configureLeftToRightText(label, alignment: .left)
            return label
        }
        let linkFooterStack = linkTitleLabel.map { titleLabel in
            let stack = NSStackView(views: [titleLabel, countLabel])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            stack.userInterfaceLayoutDirection = .leftToRight
            stack.translatesAutoresizingMaskIntoConstraints = false
            return stack
        }
        let countBadgeView = makeImageFootnoteBadgeView(isHidden: !isImageCard || state.footnoteText.isEmpty)
        let footnoteView: NSView = isImageCard ? countBadgeView : (linkFooterStack ?? countLabel)
        let linkFooterBackgroundView = makeLinkFooterBackgroundView(isHidden: !isLinkCard)
        let textBodyFadeView = makeTextBodyFadeView(isHidden: !isTextBodyCard)
        let footerRow = NSView()
        footerRow.userInterfaceLayoutDirection = .leftToRight
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        if isImageCard {
            countBadgeView.addSubview(countLabel)
            footerRow.addSubview(countBadgeView)
            NSLayoutConstraint.activate([
                countLabel.leadingAnchor.constraint(equalTo: countBadgeView.leadingAnchor, constant: 10),
                countLabel.trailingAnchor.constraint(equalTo: countBadgeView.trailingAnchor, constant: -10),
                countLabel.topAnchor.constraint(equalTo: countBadgeView.topAnchor, constant: 3),
                countLabel.bottomAnchor.constraint(equalTo: countBadgeView.bottomAnchor, constant: -3),
                countBadgeView.heightAnchor.constraint(greaterThanOrEqualToConstant: 22)
            ])
        } else if let linkFooterStack {
            footerRow.addSubview(linkFooterStack)
        } else {
            footerRow.addSubview(countLabel)
        }
        footerRow.addSubview(indexLabel)
        container.configureCommandIndexLabel(indexLabel)
        container.setCommandIndexText(state.commandIndexText)
        let centeredCountConstraint = footnoteView.centerXAnchor.constraint(equalTo: footerRow.centerXAnchor)
        centeredCountConstraint.priority = isLinkCard ? .fittingSizeCompression : .defaultHigh
        let linkFooterHeight: CGFloat = linkFooterTitle == nil ? 32 : 50
        let footerHeight = isFileCard
            ? max(metrics.cardFooterHeight, 30)
            : (isImageCard ? max(metrics.cardFooterHeight, 24) : (isLinkCard ? linkFooterHeight : metrics.cardFooterHeight))

        container.contentView?.addSubview(contentContainer)
        container.contentView?.addSubview(headerView)
        container.contentView?.addSubview(linkFooterBackgroundView)
        container.contentView?.addSubview(textBodyFadeView)
        container.contentView?.addSubview(footerRow)

        let widthConstraint = container.widthAnchor.constraint(equalToConstant: metrics.defaultItemSide)
        let heightConstraint = container.heightAnchor.constraint(equalToConstant: metrics.defaultItemSide)

        let contentLeadingConstraint = contentFillsAvailableArea
            ? contentContainer.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor)
            : contentContainer.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor, constant: metrics.cardInset)
        let contentTrailingConstraint = contentFillsAvailableArea
            ? contentContainer.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor)
            : contentContainer.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor, constant: -metrics.cardInset)
        let contentTopConstraint = contentFillsAvailableArea
            ? contentContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor)
            : contentContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10)
        let contentBottomConstraint: NSLayoutConstraint
        if isImageCard {
            contentBottomConstraint = contentContainer.bottomAnchor.constraint(equalTo: container.contentView!.bottomAnchor)
        } else if isColorCard {
            contentBottomConstraint = contentContainer.bottomAnchor.constraint(equalTo: container.contentView!.bottomAnchor)
        } else if isLinkCard {
            contentBottomConstraint = contentContainer.bottomAnchor.constraint(equalTo: footerRow.topAnchor)
        } else if isTextBodyCard {
            contentBottomConstraint = contentContainer.bottomAnchor.constraint(equalTo: container.contentView!.bottomAnchor)
        } else {
            contentBottomConstraint = contentContainer.bottomAnchor.constraint(lessThanOrEqualTo: footerRow.topAnchor, constant: -5)
        }
        let contentHeightConstraint = contentContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 1)
        let textFadeHeight = max(footerHeight + 58, 76)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,

            headerView.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: container.contentView!.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: metrics.cardHeaderHeight),

            headerTextStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: metrics.cardInset),
            headerTextStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor, constant: -1),
            headerTextStack.trailingAnchor.constraint(lessThanOrEqualTo: iconView.leadingAnchor, constant: -10),

            iconView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -7),
            iconView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 5),
            iconView.widthAnchor.constraint(equalToConstant: metrics.sourceIconSize),
            iconView.heightAnchor.constraint(equalToConstant: metrics.sourceIconSize),

            contentLeadingConstraint,
            contentTrailingConstraint,
            contentTopConstraint,
            contentHeightConstraint,
            contentBottomConstraint,

            linkFooterBackgroundView.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor),
            linkFooterBackgroundView.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor),
            linkFooterBackgroundView.topAnchor.constraint(equalTo: footerRow.topAnchor),
            linkFooterBackgroundView.bottomAnchor.constraint(equalTo: container.contentView!.bottomAnchor),

            textBodyFadeView.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor),
            textBodyFadeView.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor),
            textBodyFadeView.bottomAnchor.constraint(equalTo: container.contentView!.bottomAnchor),
            textBodyFadeView.heightAnchor.constraint(equalToConstant: textFadeHeight),

            footerRow.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor, constant: metrics.cardInset),
            footerRow.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor, constant: -metrics.cardInset),
            footerRow.bottomAnchor.constraint(equalTo: container.contentView!.bottomAnchor, constant: isLinkCard ? 0 : -13),
            footerRow.heightAnchor.constraint(equalToConstant: footerHeight),

            isLinkCard
                ? footnoteView.leadingAnchor.constraint(equalTo: footerRow.leadingAnchor)
                : footnoteView.leadingAnchor.constraint(greaterThanOrEqualTo: footerRow.leadingAnchor),
            centeredCountConstraint,
            isLinkCard
                ? footnoteView.centerYAnchor.constraint(equalTo: footerRow.centerYAnchor)
                : footnoteView.bottomAnchor.constraint(equalTo: footerRow.bottomAnchor),
            footnoteView.topAnchor.constraint(greaterThanOrEqualTo: footerRow.topAnchor),
            footnoteView.trailingAnchor.constraint(lessThanOrEqualTo: indexLabel.leadingAnchor, constant: -8),

            indexLabel.trailingAnchor.constraint(equalTo: footerRow.trailingAnchor),
            indexLabel.bottomAnchor.constraint(equalTo: footerRow.bottomAnchor, constant: isLinkCard ? -13 : 0),
            indexLabel.topAnchor.constraint(greaterThanOrEqualTo: footerRow.topAnchor),
            indexLabel.leadingAnchor.constraint(greaterThanOrEqualTo: footnoteView.trailingAnchor, constant: 8)
        ])

        let shadowHost = PanelItemCardShadowHostView(
            cardView: container,
            visualCardSide: metrics.defaultItemSide,
            shadowOutset: metrics.theme.card.cardShadowOutset,
            cardCornerRadius: metrics.cardCornerRadius,
            shadowOpacity: metrics.theme.card.cardShadowOpacity,
            shadowRadius: metrics.theme.card.cardShadowRadius,
            shadowOffset: metrics.theme.card.cardShadowOffset,
            backingScaleFactor: backingScaleFactor
        )

        return PanelRenderedItemCard(
            state: state,
            view: shadowHost,
            cardView: container,
            artifacts: PanelItemCardRenderArtifacts(
                itemWidthConstraint: widthConstraint,
                itemHeightConstraint: heightConstraint,
                previewHeightConstraints: previewBundle.previewHeightConstraints,
                previewWidthConstraints: previewBundle.previewWidthConstraints,
                imagePreviewViews: previewBundle.imagePreviewViews,
                footnoteBadgeViews: isImageCard ? [countBadgeView] : [],
                bodyLabels: [summaryLabel],
                linkPreviewViews: previewBundle.linkPreviewViews,
                linkIconViews: previewBundle.linkIconViews,
                sourceIconViews: [iconView]
            )
        )
    }

    private func makeCardContentContainer(
        previewView: NSView?,
        summaryLabel: PanelItemCardBodyTextView,
        fillsAvailableArea: Bool,
        showsSummary: Bool = true
    ) -> NSView {
        let container = NSView()
        container.userInterfaceLayoutDirection = .leftToRight
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        if let previewView, fillsAvailableArea {
            summaryLabel.isHidden = true
            previewView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(previewView)

            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                previewView.topAnchor.constraint(equalTo: container.topAnchor),
                previewView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else if let previewView, !showsSummary {
            summaryLabel.isHidden = true
            previewView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(previewView)

            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                previewView.topAnchor.constraint(equalTo: container.topAnchor),
                previewView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else if let previewView {
            previewView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(previewView)
            container.addSubview(summaryLabel)

            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                previewView.topAnchor.constraint(equalTo: container.topAnchor),

                summaryLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                summaryLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                summaryLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 7),
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

        return container
    }

    private func makeBodyLabel(
        _ text: String,
        assetRequest: PanelCardAssetRequest,
        usesRichTextPreview: Bool
    ) -> PanelItemCardBodyTextView {
        let font = NSFont.systemFont(ofSize: 12.5)
        let textColor = metrics.theme.card.primaryTextColor
        let label: PanelItemCardBodyTextView
        if usesRichTextPreview,
           let attributedText = richTextBodyPreview(
            fallbackText: text,
            assetRequest: assetRequest
           ) {
            label = PanelItemCardBodyTextView(
                attributedString: attributedText,
                fallbackFont: font,
                fallbackTextColor: textColor
            )
        } else {
            label = PanelItemCardBodyTextView(
                text: leftToRightDisplayText(text),
                font: font,
                textColor: textColor
            )
        }
        label.preferredTextWidth = metrics.defaultItemSide - metrics.cardInset * 2 - 4
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func richTextBodyPreview(
        fallbackText: String,
        assetRequest: PanelCardAssetRequest
    ) -> NSAttributedString? {
        guard let attributed = cardAssetResolver.richTextPreviewAttributedString(for: assetRequest),
              attributed.length > 0,
              !fallbackText.isEmpty
        else {
            return nil
        }

        let fallbackLength = (fallbackText as NSString).length
        let boundedLength = min(attributed.length, fallbackLength)
        guard boundedLength > 0 else {
            return nil
        }

        let preview = NSMutableAttributedString(string: "\u{200E}")
        preview.append(attributed.attributedSubstring(from: NSRange(location: 0, length: boundedLength)))
        return preview
    }

    private func makeImageFootnoteBadgeView(isHidden: Bool) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = metrics.theme.card.imageFootnoteBadgeBackgroundColor.cgColor
        view.layer?.cornerRadius = 7
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = metrics.theme.card.imageFootnoteBadgeBorderColor.cgColor
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = metrics.theme.card.imageFootnoteBadgeShadowOpacity
        view.layer?.shadowRadius = 4
        view.layer?.shadowOffset = CGSize(width: 0, height: -1)
        view.layer?.contentsScale = backingScaleFactor
        view.isHidden = isHidden
        return view
    }

    private func makeLinkFooterBackgroundView(isHidden: Bool) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("LinkFooterBackground")
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = metrics.theme.card.linkFooterBackgroundColor.cgColor
        view.layer?.contentsScale = backingScaleFactor
        view.isHidden = isHidden
        return view
    }

    private func makeTextBodyFadeView(isHidden: Bool) -> NSView {
        let view = PanelTextBodyFadeView(
            topColor: metrics.theme.card.textBodyFadeTopColor,
            middleColor: metrics.theme.card.textBodyFadeMiddleColor,
            footerColor: metrics.theme.card.textBodyFadeFooterColor,
            bottomColor: metrics.theme.card.textBodyFadeBottomColor
        )
        view.identifier = NSUserInterfaceItemIdentifier("TextBodyBottomFade")
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = isHidden
        return view
    }

    private func makePreviewBundle(
        _ previewState: PanelCardPreviewState,
        assetRequest: PanelCardAssetRequest
    ) -> PreviewBundle {
        switch previewState {
        case .none:
            return PreviewBundle()
        case .image(let previewPath, _, _):
            return makeImagePreview(previewPath: previewPath)
        case .link(let title, _, _, let iconPath, let imagePath, let accessibilityLabel):
            return makeLinkPreview(
                title: title,
                iconPath: iconPath,
                imagePath: imagePath,
                accessibilityLabel: accessibilityLabel
            )
        case .file:
            return makeFilePreview(
                accessibilityLabel: assetRequest.sourceAppName ?? AppLocalization.itemTypeTitle("file"),
                assetRequest: assetRequest
            )
        case .color(let colorValue):
            return makeColorPreview(colorValue)
        }
    }

    private func makeColorPreview(_ colorValue: ClipboardColorValue) -> PreviewBundle {
        let container = ColorCardSurfaceView(
            colorValue: colorValue,
            foregroundColor: colorSurfaceForegroundColor(for: colorValue)
        )
        let hexLabel = container.hexLabel
        configureLeftToRightText(hexLabel, alignment: .center)

        NSLayoutConstraint.activate([
            hexLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hexLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            hexLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 14),
            hexLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14)
        ])

        return PreviewBundle(view: container)
    }

    private func colorSurfaceForegroundColor(for previewState: PanelCardPreviewState) -> NSColor? {
        guard case .color(let colorValue) = previewState else { return nil }
        return colorSurfaceForegroundColor(for: colorValue)
    }

    private func colorSurfaceForegroundColor(for colorValue: ClipboardColorValue) -> NSColor {
        switch colorValue.surfaceForegroundStyle {
        case .light:
            return .white
        case .dark:
            return .black
        }
    }

    private func makeImagePreview(previewPath: String?) -> PreviewBundle {
        let container = CheckerboardImagePreviewContainerView(
            checkerboardBackgroundColor: metrics.theme.card.imagePreviewCheckerboardBackgroundColor,
            checkerboardAlternateColor: metrics.theme.card.imagePreviewCheckerboardAlternateColor
        )
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = ProportionalDownImagePreviewView(
            checkerboardBackgroundColor: metrics.theme.card.imagePreviewCheckerboardBackgroundColor,
            checkerboardAlternateColor: metrics.theme.card.imagePreviewCheckerboardAlternateColor
        )
        let previewState = cardAssetResolver.previewImageState(
            previewPath: previewPath,
            payloadPath: nil
        )
        imageView.image = previewState.image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 0
        imageView.layer?.masksToBounds = true
        imageView.toolTip = previewState.tooltip
        imageView.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)
        container.addSubview(imageView)

        let fallbackLabel = NSTextField(labelWithString: previewState.fallbackText)
        fallbackLabel.font = .systemFont(ofSize: 12, weight: .medium)
        fallbackLabel.textColor = metrics.theme.card.secondaryTextColor
        fallbackLabel.alignment = .center
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.isHidden = previewState.image != nil
        container.addSubview(fallbackLabel)

        NSLayoutConstraint.activate([
            fallbackLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        if previewState.image == nil, !previewState.paths.isEmpty {
            let loadIdentifier = imageView.identifier
            imageView.previewImageLoadToken = PanelCardAssetResolver.loadPreviewImageAsync(paths: previewState.paths) { [weak imageView, weak fallbackLabel] image in
                guard imageView?.identifier == loadIdentifier else { return }
                imageView?.previewImageLoadToken = nil
                imageView?.image = image
                fallbackLabel?.stringValue = image == nil
                    ? AppLocalization.text("preview.unavailable", defaultValue: "预览不可用")
                    : ""
                fallbackLabel?.isHidden = image != nil
            }
        }

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return PreviewBundle(
            view: container,
            imagePreviewViews: [imageView]
        )
    }

    private func makeLinkPreview(
        title: String,
        iconPath: String?,
        imagePath: String?,
        accessibilityLabel: String
    ) -> PreviewBundle {
        let container = LinkPreviewBlockView()
        container.wantsLayer = true
        container.layer?.backgroundColor = metrics.theme.card.linkPreviewBackgroundColor.cgColor
        container.layer?.cornerRadius = 0
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let imagePreviewState = cardAssetResolver.previewImageState(
            previewPath: imagePath,
            payloadPath: nil
        )
        let iconPreviewState = cardAssetResolver.previewImageState(
            previewPath: iconPath,
            payloadPath: nil
        )
        let backgroundImageView = AspectFillImagePreviewView(
            checkerboardBackgroundColor: metrics.theme.card.imagePreviewCheckerboardBackgroundColor,
            checkerboardAlternateColor: metrics.theme.card.imagePreviewCheckerboardAlternateColor
        )
        backgroundImageView.image = imagePreviewState.image
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundImageView.wantsLayer = true
        backgroundImageView.layer?.masksToBounds = true
        backgroundImageView.isHidden = imagePreviewState.image == nil
        backgroundImageView.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)

        let overlayView = NSView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.wantsLayer = true
        let overlayLayer = CAGradientLayer()
        overlayLayer.colors = [
            metrics.theme.card.linkPreviewOverlayStartColor.cgColor,
            metrics.theme.card.linkPreviewOverlayEndColor.cgColor
        ]
        overlayLayer.startPoint = CGPoint(x: 0.5, y: 0.2)
        overlayLayer.endPoint = CGPoint(x: 0.5, y: 1)
        overlayView.layer = overlayLayer
        overlayView.isHidden = imagePreviewState.image == nil

        let usesDefaultBrowserIcon = iconPreviewState.image == nil
        let iconView = makeLinkIconTile(
            image: iconPreviewState.image ?? defaultLinkBrowserIcon(),
            accessibilityLabel: title.isEmpty ? accessibilityLabel : title,
            usesDefaultBrowserIcon: usesDefaultBrowserIcon
        )
        iconView.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)

        container.addSubview(backgroundImageView)
        container.addSubview(overlayView)
        container.addSubview(iconView)
        container.iconView = iconView
        container.overlayView = overlayView
        container.hasBackgroundImage = imagePreviewState.image != nil

        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: container.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: container.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        if imagePreviewState.image == nil, !imagePreviewState.paths.isEmpty {
            let loadIdentifier = backgroundImageView.identifier
            backgroundImageView.previewImageLoadToken = PanelCardAssetResolver.loadPreviewImageAsync(paths: imagePreviewState.paths) { [weak backgroundImageView, weak container] image in
                guard backgroundImageView?.identifier == loadIdentifier else { return }
                backgroundImageView?.previewImageLoadToken = nil
                backgroundImageView?.image = image
                backgroundImageView?.isHidden = image == nil
                container?.hasBackgroundImage = image != nil
            }
        }

        if iconPreviewState.image == nil, !iconPreviewState.paths.isEmpty {
            let loadIdentifier = iconView.identifier
            (iconView as? LinkIconImagePreviewView)?.previewImageLoadToken = PanelCardAssetResolver.loadPreviewImageAsync(paths: iconPreviewState.paths) { [weak iconView] image in
                guard iconView?.identifier == loadIdentifier,
                      let image
                else { return }
                (iconView as? LinkIconImagePreviewView)?.previewImageLoadToken = nil
                self.configureLinkIconAppearance(iconView, usesDefaultBrowserIcon: false)
                iconView?.image = image
            }
        }

        return PreviewBundle(
            view: container,
            imagePreviewViews: [backgroundImageView],
            linkPreviewViews: [container],
            linkIconViews: [iconView]
        )
    }

    private func makeFilePreview(
        accessibilityLabel: String,
        assetRequest: PanelCardAssetRequest
    ) -> PreviewBundle {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let maximumPreviewSize = NSSize(width: metrics.defaultItemSide - 72, height: 132)
        let filePreviewURLs = cardAssetResolver.filePreviewURLs(for: assetRequest)
        let imageView = FilePreviewImageView()
        imageView.image = cardAssetResolver.filePreviewImage(
            for: assetRequest,
            maximumSize: maximumPreviewSize,
            scale: backingScaleFactor
        )
            ?? NSImage(systemSymbolName: "doc", accessibilityDescription: accessibilityLabel)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.identifier = NSUserInterfaceItemIdentifier(UUID().uuidString)
        container.addSubview(imageView)

        let loadIdentifier = imageView.identifier
        imageView.thumbnailToken = PanelCardAssetResolver.loadFilePreviewImageAsync(
            urls: filePreviewURLs,
            maximumSize: maximumPreviewSize,
            scale: backingScaleFactor
        ) { [weak imageView] image in
            guard imageView?.identifier == loadIdentifier,
                  let image
            else {
                return
            }
            imageView?.image = image
        }

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: 92)
        heightConstraint.priority = .defaultHigh
        let widthConstraint = imageView.widthAnchor.constraint(lessThanOrEqualToConstant: metrics.defaultItemSide - 72)
        NSLayoutConstraint.activate([
            heightConstraint,
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            widthConstraint,
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 132),
            imageView.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])

        return PreviewBundle(
            view: container,
            previewHeightConstraints: [heightConstraint],
            previewWidthConstraints: [widthConstraint],
            imagePreviewViews: [imageView]
        )
    }

    private func makeAppIconTile(image: NSImage?, accessibilityLabel: String) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = metrics.theme.card.appIconTileBackgroundColor.cgColor
        imageView.toolTip = accessibilityLabel
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 42),
            imageView.heightAnchor.constraint(equalToConstant: 42)
        ])
        return imageView
    }

    private func makeLinkIconTile(
        image: NSImage?,
        accessibilityLabel: String,
        usesDefaultBrowserIcon: Bool
    ) -> NSImageView {
        let imageView = LinkIconImagePreviewView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 11
        imageView.layer?.masksToBounds = true
        imageView.toolTip = accessibilityLabel
        configureLinkIconAppearance(imageView, usesDefaultBrowserIcon: usesDefaultBrowserIcon)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 46),
            imageView.heightAnchor.constraint(equalToConstant: 46)
        ])
        return imageView
    }

    private func defaultLinkBrowserIcon() -> NSImage? {
        let image = NSImage(systemSymbolName: "safari", accessibilityDescription: AppLocalization.text("browser.safari", defaultValue: "Safari 浏览器"))
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: AppLocalization.text("browser.generic", defaultValue: "浏览器"))
        image?.isTemplate = true
        return image
    }

    private func configureLinkIconAppearance(
        _ imageView: NSImageView?,
        usesDefaultBrowserIcon: Bool
    ) {
        guard let imageView else { return }
        imageView.layer?.contentsScale = backingScaleFactor
        if usesDefaultBrowserIcon {
            imageView.image?.isTemplate = true
            imageView.contentTintColor = metrics.theme.card.linkDefaultIconTintColor
            imageView.layer?.backgroundColor = NSColor.clear.cgColor
            imageView.layer?.borderWidth = 0
            imageView.layer?.borderColor = NSColor.clear.cgColor
        } else {
            imageView.contentTintColor = nil
            imageView.layer?.backgroundColor = metrics.theme.card.appIconTileBackgroundColor.cgColor
            imageView.layer?.borderWidth = 0.5
            imageView.layer?.borderColor = metrics.theme.card.linkResolvedIconBorderColor.cgColor
        }
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

    private func headerTextColor(isSelected: Bool) -> NSColor {
        metrics.theme.card.headerTextColor
    }

    private func headerSecondaryTextColor(isSelected: Bool) -> NSColor {
        metrics.theme.card.headerSecondaryTextColor
    }

    private struct PreviewBundle {
        var view: NSView?
        var previewHeightConstraints: [NSLayoutConstraint] = []
        var previewWidthConstraints: [NSLayoutConstraint] = []
        var imagePreviewViews: [NSImageView] = []
        var linkPreviewViews: [NSView] = []
        var linkIconViews: [NSImageView] = []
    }
}

@MainActor
final class PanelItemCardBodyTextView: NSView {
    private static let lineSpacing: CGFloat = 2

    private let textStorage: NSTextStorage
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private let font: NSFont
    private let textColor: NSColor

    var preferredTextWidth: CGFloat {
        didSet {
            invalidateTextContainer()
        }
    }

    init(text: String, font: NSFont, textColor: NSColor) {
        self.font = font
        self.textColor = textColor
        self.preferredTextWidth = 0
        textStorage = NSTextStorage(attributedString: Self.normalizedAttributedString(
            NSAttributedString(string: text),
            fallbackFont: font,
            fallbackTextColor: textColor
        ))
        super.init(frame: .zero)
        configureTextLayout()
    }

    init(attributedString: NSAttributedString, fallbackFont: NSFont, fallbackTextColor: NSColor) {
        self.font = fallbackFont
        self.textColor = fallbackTextColor
        self.preferredTextWidth = 0
        textStorage = NSTextStorage(attributedString: Self.normalizedAttributedString(
            attributedString,
            fallbackFont: fallbackFont,
            fallbackTextColor: fallbackTextColor
        ))
        super.init(frame: .zero)
        configureTextLayout()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        invalidateTextContainer()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !bounds.isEmpty else { return }
        invalidateTextContainer()
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }

    var attributedStringForTesting: NSAttributedString {
        NSAttributedString(attributedString: textStorage)
    }

    private func configureTextLayout() {
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
    }

    private static func normalizedAttributedString(
        _ attributedString: NSAttributedString,
        fallbackFont: NSFont,
        fallbackTextColor: NSColor
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else {
            return mutable
        }

        var missingFontRanges: [NSRange] = []
        var missingColorRanges: [NSRange] = []
        var paragraphRanges: [(NSRange, NSParagraphStyle?)] = []

        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                missingFontRanges.append(range)
            }
        }
        mutable.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                missingColorRanges.append(range)
            }
        }
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            paragraphRanges.append((range, value as? NSParagraphStyle))
        }

        for range in missingFontRanges {
            mutable.addAttribute(.font, value: fallbackFont, range: range)
        }
        for range in missingColorRanges {
            mutable.addAttribute(.foregroundColor, value: fallbackTextColor, range: range)
        }
        for (range, style) in paragraphRanges {
            let paragraph = (style?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            paragraph.alignment = .left
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = Self.lineSpacing
            paragraph.baseWritingDirection = .leftToRight
            mutable.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }

        return mutable
    }

    private func invalidateTextContainer() {
        let width = max(0, min(bounds.width, preferredTextWidth == 0 ? bounds.width : preferredTextWidth))
        guard width > 0 else { return }
        let size = NSSize(width: width, height: max(0, bounds.height))
        guard textContainer.containerSize != size else { return }
        textContainer.containerSize = size
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage.length), actualCharacterRange: nil)
        needsDisplay = true
    }
}

@MainActor
private final class PanelTextBodyFadeView: NSView {
    private let topColor: NSColor
    private let middleColor: NSColor
    private let footerColor: NSColor
    private let bottomColor: NSColor

    init(topColor: NSColor, middleColor: NSColor, footerColor: NSColor, bottomColor: NSColor) {
        self.topColor = topColor
        self.middleColor = middleColor
        self.footerColor = footerColor
        self.bottomColor = bottomColor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !bounds.isEmpty else { return }
        let colors = [
            topColor.cgColor,
            middleColor.cgColor,
            footerColor.cgColor,
            bottomColor.cgColor
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 0.42, 0.72, 1]
        ), let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.minY),
            end: CGPoint(x: bounds.midX, y: bounds.maxY),
            options: []
        )
    }
}

@MainActor
private final class ColorCardSurfaceView: NSView {
    let hexLabel: NSTextField

    init(colorValue: ClipboardColorValue, foregroundColor: NSColor) {
        let color = NSColor(
            srgbRed: CGFloat(colorValue.red) / 255,
            green: CGFloat(colorValue.green) / 255,
            blue: CGFloat(colorValue.blue) / 255,
            alpha: 1
        )
        hexLabel = NSTextField(labelWithString: colorValue.normalizedHex)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("ColorCardSurface")
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = color.cgColor
        toolTip = colorValue.normalizedHex

        hexLabel.identifier = NSUserInterfaceItemIdentifier("ColorCardHexLabel")
        hexLabel.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        hexLabel.textColor = foregroundColor
        hexLabel.alignment = .center
        hexLabel.lineBreakMode = .byClipping
        hexLabel.maximumNumberOfLines = 1
        hexLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hexLabel)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class ProportionalDownImagePreviewView: NSImageView {
    private var imageGeometry: ProportionalImageGeometry?
    private let checkerboardBackgroundColor: NSColor
    private let checkerboardAlternateColor: NSColor
    var previewImageLoadToken: PanelPreviewImageLoadToken? {
        didSet {
            PanelCardAssetResolver.cancelPreviewImageLoad(oldValue)
        }
    }

    init(checkerboardBackgroundColor: NSColor, checkerboardAlternateColor: NSColor) {
        self.checkerboardBackgroundColor = checkerboardBackgroundColor
        self.checkerboardAlternateColor = checkerboardAlternateColor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var image: NSImage? {
        didSet {
            imageGeometry = image.flatMap(Self.imageGeometry(for:))
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawCheckerboard(in: dirtyRect)

        guard let image,
              let imageGeometry,
              imageGeometry.size.width > 0,
              imageGeometry.size.height > 0,
              bounds.width > 0,
              bounds.height > 0
        else {
            return
        }

        let scale = min(
            bounds.width / imageGeometry.size.width,
            bounds.height / imageGeometry.size.height,
            1
        )
        let drawSize = NSSize(
            width: floor(imageGeometry.size.width * scale),
            height: floor(imageGeometry.size.height * scale)
        )
        let drawRect = NSRect(
            x: floor(bounds.midX - drawSize.width / 2),
            y: floor(bounds.midY - drawSize.height / 2),
            width: drawSize.width,
            height: drawSize.height
        )

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawCheckerboard(in rect: NSRect) {
        checkerboardBackgroundColor.setFill()
        rect.fill()

        let square: CGFloat = 10
        checkerboardAlternateColor.setFill()
        let minX = Int(floor(rect.minX / square))
        let maxX = Int(ceil(rect.maxX / square))
        let minY = Int(floor(rect.minY / square))
        let maxY = Int(ceil(rect.maxY / square))

        for x in minX...maxX {
            for y in minY...maxY where (x + y).isMultiple(of: 2) {
                NSRect(
                    x: CGFloat(x) * square,
                    y: CGFloat(y) * square,
                    width: square,
                    height: square
                ).fill()
            }
        }
    }

    private static func imageGeometry(for image: NSImage) -> ProportionalImageGeometry? {
        if let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return ProportionalImageGeometry(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        }

        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return ProportionalImageGeometry(size: image.size)
    }

    private struct ProportionalImageGeometry {
        let size: NSSize
    }
}

@MainActor
private final class CheckerboardImagePreviewContainerView: NSView {
    private let checkerboardBackgroundColor: NSColor
    private let checkerboardAlternateColor: NSColor

    init(checkerboardBackgroundColor: NSColor, checkerboardAlternateColor: NSColor) {
        self.checkerboardBackgroundColor = checkerboardBackgroundColor
        self.checkerboardAlternateColor = checkerboardAlternateColor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        checkerboardBackgroundColor.setFill()
        dirtyRect.fill()

        let square: CGFloat = 10
        checkerboardAlternateColor.setFill()
        let minX = Int(floor(dirtyRect.minX / square))
        let maxX = Int(ceil(dirtyRect.maxX / square))
        let minY = Int(floor(dirtyRect.minY / square))
        let maxY = Int(ceil(dirtyRect.maxY / square))

        for x in minX...maxX {
            for y in minY...maxY where (x + y).isMultiple(of: 2) {
                NSRect(
                    x: CGFloat(x) * square,
                    y: CGFloat(y) * square,
                    width: square,
                    height: square
                ).fill()
            }
        }
    }
}

@MainActor
private final class AspectFillImagePreviewView: NSImageView {
    private var imageGeometry: ImageGeometry?
    private let checkerboardBackgroundColor: NSColor
    private let checkerboardAlternateColor: NSColor
    var previewImageLoadToken: PanelPreviewImageLoadToken? {
        didSet {
            PanelCardAssetResolver.cancelPreviewImageLoad(oldValue)
        }
    }

    init(checkerboardBackgroundColor: NSColor, checkerboardAlternateColor: NSColor) {
        self.checkerboardBackgroundColor = checkerboardBackgroundColor
        self.checkerboardAlternateColor = checkerboardAlternateColor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var image: NSImage? {
        didSet {
            imageGeometry = image.flatMap(Self.imageGeometry(for:))
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawCheckerboard(in: dirtyRect)

        guard let image,
              let imageGeometry
        else {
            return
        }
        let imageSize = imageGeometry.imageSize
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawRect = NSRect(
            x: floor(bounds.midX - imageSize.width * scale / 2),
            y: floor(bounds.midY - imageSize.height * scale / 2),
            width: ceil(imageSize.width * scale),
            height: ceil(imageSize.height * scale)
        )

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawCheckerboard(in rect: NSRect) {
        checkerboardBackgroundColor.setFill()
        rect.fill()

        let square: CGFloat = 10
        checkerboardAlternateColor.setFill()
        let minX = Int(floor(rect.minX / square))
        let maxX = Int(ceil(rect.maxX / square))
        let minY = Int(floor(rect.minY / square))
        let maxY = Int(ceil(rect.maxY / square))

        for x in minX...maxX {
            for y in minY...maxY where (x + y).isMultiple(of: 2) {
                NSRect(
                    x: CGFloat(x) * square,
                    y: CGFloat(y) * square,
                    width: square,
                    height: square
                ).fill()
            }
        }
    }

    private static func imageGeometry(for image: NSImage) -> ImageGeometry? {
        if let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return ImageGeometry(imageSize: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        }

        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return ImageGeometry(imageSize: image.size)
    }

    private struct ImageGeometry {
        let imageSize: NSSize
    }
}

@MainActor
private final class LinkIconImagePreviewView: NSImageView {
    var previewImageLoadToken: PanelPreviewImageLoadToken? {
        didSet {
            PanelCardAssetResolver.cancelPreviewImageLoad(oldValue)
        }
    }
}

@MainActor
private final class SourceIconImageView: NSImageView {
    var previewImageLoadToken: PanelPreviewImageLoadToken? {
        didSet {
            PanelCardAssetResolver.cancelPreviewImageLoad(oldValue)
        }
    }
}

@MainActor
private final class LinkPreviewBlockView: NSView {
    weak var iconView: NSView? {
        didSet {
            updateResponsiveVisibility()
        }
    }

    weak var overlayView: NSView? {
        didSet {
            updateResponsiveVisibility()
        }
    }

    var hasBackgroundImage = false {
        didSet {
            updateResponsiveVisibility()
        }
    }

    override func layout() {
        super.layout()
        updateResponsiveVisibility()
    }

    private func updateResponsiveVisibility() {
        let height = bounds.height
        let isLaidOut = height > 0
        let compact = isLaidOut && height < 74
        iconView?.isHidden = hasBackgroundImage || compact
        overlayView?.isHidden = !hasBackgroundImage
    }
}

@MainActor
private final class FilePreviewImageView: NSImageView {
    var thumbnailToken: PanelFilePreviewThumbnailToken? {
        didSet {
            PanelCardAssetResolver.cancelFilePreviewImageRequest(oldValue)
        }
    }

    deinit {
        let token = thumbnailToken
        Task { @MainActor in
            PanelCardAssetResolver.cancelFilePreviewImageRequest(token)
        }
    }
}

@MainActor
private protocol PanelCardAsyncWorkCancellable: AnyObject {
    func cancelPanelCardAsyncWork()
}

@MainActor
private protocol PanelCardPreviewImageLoadTokenProviding: AnyObject {
    var previewImageLoadToken: PanelPreviewImageLoadToken? { get }
}

@MainActor
private protocol PanelCardFilePreviewThumbnailTokenProviding: AnyObject {
    var thumbnailToken: PanelFilePreviewThumbnailToken? { get }
}

extension ProportionalDownImagePreviewView: PanelCardPreviewImageLoadTokenProviding {}
extension AspectFillImagePreviewView: PanelCardPreviewImageLoadTokenProviding {}
extension LinkIconImagePreviewView: PanelCardPreviewImageLoadTokenProviding {}
extension SourceIconImageView: PanelCardPreviewImageLoadTokenProviding {}
extension FilePreviewImageView: PanelCardFilePreviewThumbnailTokenProviding {}

extension ProportionalDownImagePreviewView: PanelCardAsyncWorkCancellable {
    func cancelPanelCardAsyncWork() {
        previewImageLoadToken = nil
    }
}

extension AspectFillImagePreviewView: PanelCardAsyncWorkCancellable {
    func cancelPanelCardAsyncWork() {
        previewImageLoadToken = nil
    }
}

extension LinkIconImagePreviewView: PanelCardAsyncWorkCancellable {
    func cancelPanelCardAsyncWork() {
        previewImageLoadToken = nil
    }
}

extension SourceIconImageView: PanelCardAsyncWorkCancellable {
    func cancelPanelCardAsyncWork() {
        previewImageLoadToken = nil
    }
}

extension FilePreviewImageView: PanelCardAsyncWorkCancellable {
    func cancelPanelCardAsyncWork() {
        thumbnailToken = nil
    }
}
