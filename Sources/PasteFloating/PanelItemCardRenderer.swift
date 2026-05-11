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
    let theme: PasteThemePalette
}

struct PanelItemCardRenderArtifacts {
    let itemWidthConstraint: NSLayoutConstraint
    let itemHeightConstraint: NSLayoutConstraint
    let previewHeightConstraints: [NSLayoutConstraint]
    let previewWidthConstraints: [NSLayoutConstraint]
    let imagePreviewViews: [NSImageView]
    let bodyLabels: [NSTextField]
}

struct PanelRenderedItemCard {
    let view: NSView
    let artifacts: PanelItemCardRenderArtifacts
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
        onSelect: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onContextMenu: ((NSEvent) -> Void)? = nil
    ) -> PanelRenderedItemCard {
        let resolvedItem = cardAssetResolver.resolvedItem(for: state.assetRequest)

        let iconView = NSImageView()
        iconView.image = resolvedItem.sourceIconImage
            ?? NSImage(
                systemSymbolName: state.symbolName,
                accessibilityDescription: state.sourceAppName
            )

        let previewBundle = makePreviewBundle(
            state.preview,
            assetRequest: state.assetRequest
        )

        let container = ClipboardItemCardBox()
        container.boxType = .custom
        container.borderColor = metrics.theme.card.borderColor
        container.borderWidth = 0.5
        container.fillColor = metrics.theme.card.backgroundColor
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

        let typeHeaderLabel = NSTextField(labelWithString: state.typeText)
        typeHeaderLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        typeHeaderLabel.textColor = headerTextColor(isSelected: state.isSelected)
        typeHeaderLabel.lineBreakMode = .byTruncatingTail
        typeHeaderLabel.maximumNumberOfLines = 1
        configureLeftToRightText(typeHeaderLabel)

        let timeLabel = NSTextField(labelWithString: state.relativeTimeText)
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
            borderColor: metrics.theme.card.borderColor,
            selectionBorderColor: metrics.theme.card.selectionBorderColor,
            headerTextColor: metrics.theme.card.headerTextColor,
            headerSecondaryTextColor: metrics.theme.card.headerSecondaryTextColor,
            isSelected: state.isSelected
        )

        let summaryLabel = makeBodyLabel(state.summaryText)
        let contentContainer = makeCardContentContainer(
            previewView: previewBundle.view,
            summaryLabel: summaryLabel
        )

        let indexLabel = NSTextField(labelWithString: "")
        indexLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        indexLabel.textColor = .tertiaryLabelColor
        indexLabel.lineBreakMode = .byTruncatingTail
        configureLeftToRightText(indexLabel, alignment: .right)
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)
        indexLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        indexLabel.stringValue = state.commandIndexText ?? ""
        indexLabel.isHidden = state.commandIndexText == nil

        let countLabel = NSTextField(labelWithString: state.footnoteText)
        countLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        countLabel.textColor = metrics.theme.card.footerTextColor
        countLabel.lineBreakMode = .byTruncatingTail
        configureLeftToRightText(countLabel, alignment: .center)
        countLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let footerRow = NSView()
        footerRow.userInterfaceLayoutDirection = .leftToRight
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        footerRow.addSubview(countLabel)
        footerRow.addSubview(indexLabel)
        container.configureCommandIndexLabel(indexLabel)
        let centeredCountConstraint = countLabel.centerXAnchor.constraint(equalTo: footerRow.centerXAnchor)
        centeredCountConstraint.priority = .defaultHigh

        container.contentView?.addSubview(headerView)
        container.contentView?.addSubview(contentContainer)
        container.contentView?.addSubview(footerRow)

        let widthConstraint = container.widthAnchor.constraint(equalToConstant: metrics.defaultItemSide)
        let heightConstraint = container.heightAnchor.constraint(equalToConstant: metrics.defaultItemSide)

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

            contentContainer.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor, constant: metrics.cardInset),
            contentContainer.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor, constant: -metrics.cardInset),
            contentContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10),
            contentContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 1),
            contentContainer.bottomAnchor.constraint(lessThanOrEqualTo: footerRow.topAnchor, constant: -5),

            footerRow.leadingAnchor.constraint(equalTo: container.contentView!.leadingAnchor, constant: metrics.cardInset),
            footerRow.trailingAnchor.constraint(equalTo: container.contentView!.trailingAnchor, constant: -metrics.cardInset),
            footerRow.bottomAnchor.constraint(equalTo: container.contentView!.bottomAnchor, constant: -13),
            footerRow.heightAnchor.constraint(equalToConstant: metrics.cardFooterHeight),

            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: footerRow.leadingAnchor),
            centeredCountConstraint,
            countLabel.bottomAnchor.constraint(equalTo: footerRow.bottomAnchor),
            countLabel.topAnchor.constraint(greaterThanOrEqualTo: footerRow.topAnchor),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: indexLabel.leadingAnchor, constant: -8),

            indexLabel.trailingAnchor.constraint(equalTo: footerRow.trailingAnchor),
            indexLabel.bottomAnchor.constraint(equalTo: footerRow.bottomAnchor),
            indexLabel.topAnchor.constraint(greaterThanOrEqualTo: footerRow.topAnchor),
            indexLabel.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 8)
        ])

        return PanelRenderedItemCard(
            view: container,
            artifacts: PanelItemCardRenderArtifacts(
                itemWidthConstraint: widthConstraint,
                itemHeightConstraint: heightConstraint,
                previewHeightConstraints: previewBundle.previewHeightConstraints,
                previewWidthConstraints: previewBundle.previewWidthConstraints,
                imagePreviewViews: previewBundle.imagePreviewViews,
                bodyLabels: [summaryLabel]
            )
        )
    }

    private func makeCardContentContainer(
        previewView: NSView?,
        summaryLabel: NSTextField
    ) -> NSView {
        let container = NSView()
        container.userInterfaceLayoutDirection = .leftToRight
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

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

    private func makeBodyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: leftToRightDisplayText(text))
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = metrics.theme.card.primaryTextColor
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = metrics.defaultItemSide - metrics.cardInset * 2 - 4
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.cell?.lineBreakMode = .byWordWrapping
        configureLeftToRightText(label, lineSpacing: 2)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makePreviewBundle(
        _ previewState: PanelCardPreviewState,
        assetRequest: PanelCardAssetRequest
    ) -> PreviewBundle {
        switch previewState {
        case .none:
            return PreviewBundle()
        case .image(let previewPath, let payloadPath, _):
            return makeImagePreview(previewPath: previewPath, payloadPath: payloadPath)
        case .link(let host, let detail, let accessibilityLabel):
            return makeLinkPreview(
                host: host,
                detail: detail,
                accessibilityLabel: accessibilityLabel,
                assetRequest: assetRequest
            )
        case .file:
            return makeFilePreview(
                accessibilityLabel: assetRequest.sourceAppName ?? "文件",
                assetRequest: assetRequest
            )
        }
    }

    private func makeImagePreview(previewPath: String?, payloadPath: String?) -> PreviewBundle {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = 0
        container.layer?.masksToBounds = false
        container.layer?.borderWidth = 0
        container.layer?.contentsScale = backingScaleFactor
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        let previewState = cardAssetResolver.previewImageState(
            previewPath: previewPath,
            payloadPath: payloadPath
        )
        imageView.image = previewState.image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 7
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
            PanelCardAssetResolver.loadPreviewImageAsync(paths: previewState.paths) { [weak imageView, weak fallbackLabel] image in
                guard imageView?.identifier == loadIdentifier else { return }
                imageView?.image = image
                fallbackLabel?.stringValue = image == nil ? "预览不可用" : ""
                fallbackLabel?.isHidden = image != nil
            }
        }

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: 92)
        heightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            heightConstraint,
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 18),
            imageView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])

        return PreviewBundle(
            view: container,
            previewHeightConstraints: [heightConstraint],
            imagePreviewViews: [imageView]
        )
    }

    private func makeLinkPreview(
        host: String,
        detail: String,
        accessibilityLabel: String,
        assetRequest: PanelCardAssetRequest
    ) -> PreviewBundle {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = metrics.theme.card.linkPreviewBackgroundColor.cgColor
        container.layer?.cornerRadius = 0
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let sourceImage = cardAssetResolver.sourceIconImage(for: assetRequest)
        let iconView = makeAppIconTile(
            image: sourceImage ?? NSImage(systemSymbolName: "link", accessibilityDescription: "链接"),
            accessibilityLabel: accessibilityLabel
        )

        let titleLabel = NSTextField(labelWithString: host)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = metrics.theme.card.primaryTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        configureLeftToRightText(titleLabel)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
        detailLabel.textColor = metrics.theme.card.secondaryTextColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        configureLeftToRightText(detailLabel)

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.userInterfaceLayoutDirection = .leftToRight
        textStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(textStack)

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: metrics.linkPreviewHeight)
        heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            heightConstraint,
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -10),

            textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])

        return PreviewBundle(
            view: container,
            previewHeightConstraints: [heightConstraint]
        )
    }

    private func makeFilePreview(
        accessibilityLabel: String,
        assetRequest: PanelCardAssetRequest
    ) -> PreviewBundle {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = cardAssetResolver.filePreviewImage(for: assetRequest)
            ?? NSImage(systemSymbolName: "doc", accessibilityDescription: accessibilityLabel)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        let heightConstraint = container.heightAnchor.constraint(equalToConstant: 92)
        heightConstraint.priority = .defaultHigh
        let widthConstraint = imageView.widthAnchor.constraint(lessThanOrEqualToConstant: metrics.defaultItemSide - 72)
        NSLayoutConstraint.activate([
            heightConstraint,
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            widthConstraint,
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 76),
            imageView.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])

        return PreviewBundle(
            view: container,
            previewHeightConstraints: [heightConstraint],
            previewWidthConstraints: [widthConstraint]
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
    }
}
