import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp

@MainActor
final class ClipboardPreviewPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var shownItemID: String?
    private var keyDownMonitor: Any?
    private weak var returnFocusView: NSView?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    var isShown: Bool {
        popover.isShown
    }

    var contentRootViewForSmoke: NSView? {
        popover.contentViewController?.view
    }

    var contentWindow: NSWindow? {
        popover.contentViewController?.view.window
    }

    var screenFrame: NSRect? {
        contentWindow?.frame
    }

    func toggle(
        item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        relativeTo anchorView: NSView,
        returnFocusTo focusView: NSView
    ) {
        if popover.isShown, shownItemID == item.id {
            close()
            return
        }

        show(
            item: item,
            appSupportDirectory: appSupportDirectory,
            relativeTo: anchorView,
            returnFocusTo: focusView
        )
    }

    func show(
        item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        relativeTo anchorView: NSView,
        returnFocusTo focusView: NSView
    ) {
        close(restoresFocus: false)

        let content = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: appSupportDirectory
        )
        let viewController = ClipboardPreviewViewController(content: content)
        viewController.onClose = { [weak self] in
            self?.close()
        }
        popover.contentViewController = viewController
        popover.contentSize = viewController.preferredContentSize
        shownItemID = item.id
        returnFocusView = focusView
        startKeyDownMonitor()
        popover.show(
            relativeTo: anchorView.bounds.insetBy(dx: 10, dy: 10),
            of: anchorView,
            preferredEdge: .maxY
        )
        focusView.window?.makeFirstResponder(focusView)
    }

    func close() {
        close(restoresFocus: true)
    }

    private func close(restoresFocus: Bool) {
        if popover.isShown {
            popover.performClose(nil)
            popover.close()
        }
        finishClosing(restoresFocus: restoresFocus)
    }

    func popoverDidClose(_ notification: Notification) {
        guard !popover.isShown else { return }
        finishClosing(restoresFocus: true)
    }

    private func finishClosing(restoresFocus: Bool) {
        stopKeyDownMonitor()
        shownItemID = nil
        if restoresFocus {
            returnFocusView?.window?.makeFirstResponder(returnFocusView)
        }
        returnFocusView = nil
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
        static let minWidth: CGFloat = 320
        static let maxWidth: CGFloat = 820
        static let minContentHeight: CGFloat = 96
        static let minTextContentHeight: CGFloat = 58
        static let maxTextWidth: CGFloat = 720
        static let maxContentHeight: CGFloat = 560
        static let headerHeight: CGFloat = 48
        static let footerHeight: CGFloat = 50
        static let previewHorizontalInset: CGFloat = 5
        static let imagePreviewHorizontalInset: CGFloat = 2
        static let textHorizontalPadding: CGFloat = 12
        static let textVerticalPadding: CGFloat = 13
        static let preciseTextMeasurementLimit = 1_800
        static let chromeHeight: CGFloat = headerHeight + footerHeight
        static var previewTextFont: NSFont {
            .systemFont(ofSize: 12.5)
        }
    }

    private let content: ClipboardPreviewContent
    var onClose: (() -> Void)?
    private var theme: PasteThemePalette {
        isViewLoaded ? PasteTheme.current(for: view) : PasteTheme.current(for: NSApp.effectiveAppearance)
    }

    init(content: ClipboardPreviewContent) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.preferredSize(for: content)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let previewTheme = theme.preview
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.backgroundColor = previewTheme.backgroundColor.cgColor
        root.layer?.cornerRadius = 11
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.layer?.borderColor = previewTheme.borderColor.cgColor
        root.layer?.borderWidth = 0.8

        let header = makeHeader()
        let preview = content.itemType == "image" ? makeImagePreview() : makeTextPreview()
        let footer = makeFooter()
        let previewInset = content.itemType == "image"
            ? Layout.imagePreviewHorizontalInset
            : Layout.previewHorizontalInset

        root.addSubview(header)
        root.addSubview(preview)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: Layout.headerHeight),

            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: previewInset),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -previewInset),
            preview.topAnchor.constraint(equalTo: header.bottomAnchor),
            preview.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: Layout.footerHeight),

            root.widthAnchor.constraint(equalToConstant: preferredContentSize.width),
            root.heightAnchor.constraint(equalToConstant: preferredContentSize.height)
        ])

        view = root
    }

    private static func preferredSize(for content: ClipboardPreviewContent) -> NSSize {
        if content.itemType == "image",
           let image = content.imageURL.flatMap(NSImage.init(contentsOf:)) {
            let pixelSize = imagePixelSize(for: image) ?? image.size
            let visibleSize = visiblePixelBounds(for: image)?.size ?? pixelSize
            let previewSize = fittedImagePreviewSize(for: visibleSize)
            let width = previewSize.width + Layout.imagePreviewHorizontalInset * 2
            let contentHeight = previewSize.height
            return NSSize(width: width, height: contentHeight + Layout.chromeHeight)
        }

        let textMetrics = estimatedTextMetrics(for: content.body)
        let width = bounded(
            textMetrics.preferredWidth,
            minimum: Layout.minWidth,
            maximum: availableMaximumWidth()
        )
        let contentHeight = bounded(
            textMetrics.preferredHeight,
            minimum: Layout.minTextContentHeight,
            maximum: availableMaximumContentHeight()
        )
        return NSSize(width: width, height: contentHeight + Layout.chromeHeight)
    }

    private func makeHeader() -> NSView {
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .withinWindow
        container.state = .active
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = theme.preview.chromeBackgroundColor.cgColor

        let closeButton = PanelActionButton()
        closeButton.bezelStyle = .texturedRounded
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭预览")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = theme.preview.closeButtonColor
        closeButton.target = nil
        closeButton.action = nil
        closeButton.onPress = { [weak self] in
            self?.onClose?()
        }
        closeButton.toolTip = "关闭预览"
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: displayTypeTitle())
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = theme.preview.titleTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.clear.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(closeButton)
        container.addSubview(titleLabel)
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            closeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }

    private func makeImagePreview() -> NSView {
        let container = makePreviewSurface(backgroundAlpha: 0.50)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let image = content.imageURL.flatMap(NSImage.init(contentsOf:))
        let viewportSize = NSSize(
            width: preferredContentSize.width,
            height: preferredContentSize.height - Layout.chromeHeight
        )
        let documentView = PreviewImageDocumentView(image: image, viewportSize: viewportSize)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor)
        ])

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeTextPreview() -> NSView {
        let container = makePreviewSurface(backgroundAlpha: 0.76)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentWidth = preferredContentSize.width - Layout.previewHorizontalInset * 2
        let viewportHeight = max(
            preferredContentSize.height - Layout.chromeHeight,
            Layout.minTextContentHeight
        )
        let documentHeight = Self.estimatedTextDocumentHeight(
            for: content.body,
            documentWidth: documentWidth,
            font: Layout.previewTextFont
        )

        let textView = NSTextView(frame: NSRect(
            x: 0,
            y: 0,
            width: documentWidth,
            height: max(viewportHeight, documentHeight)
        ))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.lineSpacing = 0
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = theme.preview.bodyTextColor
        textView.font = Layout.previewTextFont
        textView.textContainerInset = NSSize(
            width: Layout.textHorizontalPadding,
            height: Layout.textVerticalPadding
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.textContainer?.containerSize = NSSize(
            width: documentWidth - Layout.textHorizontalPadding * 2,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: documentWidth, height: viewportHeight)
        textView.maxSize = NSSize(width: documentWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: content.body,
            attributes: [
                .font: Layout.previewTextFont,
                .foregroundColor: theme.preview.bodyTextColor,
                .paragraphStyle: paragraphStyle
            ]
        ))
        textView.translatesAutoresizingMaskIntoConstraints = true

        scrollView.documentView = textView

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        DispatchQueue.main.async {
            scrollView.layoutSubtreeIfNeeded()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        return container
    }

    private func makePreviewSurface(backgroundAlpha: CGFloat) -> NSVisualEffectView {
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .withinWindow
        container.state = .active
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        let surfaceColor = backgroundAlpha < 0.60
            ? theme.preview.imageSurfaceBackgroundColor
            : theme.preview.surfaceBackgroundColor
        container.layer?.backgroundColor = surfaceColor.cgColor
        container.layer?.cornerRadius = 5
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderColor = theme.preview.surfaceBorderColor.cgColor
        container.layer?.borderWidth = 0.5
        return container
    }

    private func makeFooter() -> NSView {
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .withinWindow
        container.state = .active
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = theme.preview.chromeBackgroundColor.cgColor

        let metadataStack = NSStackView()
        metadataStack.orientation = .horizontal
        metadataStack.alignment = .firstBaseline
        metadataStack.spacing = 13
        metadataStack.translatesAutoresizingMaskIntoConstraints = false

        footerComponents().enumerated().forEach { index, component in
            if index > 0 {
                metadataStack.addArrangedSubview(makeFooterLabel("·", isDimmed: true))
            }
            metadataStack.addArrangedSubview(makeFooterLabel(component, isDimmed: false))
        }

        container.addSubview(metadataStack)
        NSLayoutConstraint.activate([
            metadataStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 25),
            metadataStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            metadataStack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -1),
            metadataStack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 13),
            metadataStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -15)
        ])
        return container
    }

    private func makeFooterLabel(_ text: String, isDimmed: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13.5, weight: .medium)
        label.textColor = isDimmed ? theme.preview.footerDimTextColor : theme.preview.footerTextColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func displayTypeTitle() -> String {
        switch content.itemType {
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

    private func footerComponents() -> [String] {
        if content.itemType == "image",
           let image = content.imageURL.flatMap(NSImage.init(contentsOf:)),
           let size = Self.imagePixelSize(for: image) {
            return ["\(Int(size.width)) × \(Int(size.height))"]
        }

        if content.itemType == "text" || content.itemType == "rich_text" || content.itemType == "link" {
            let text = content.body
            let characterCount = text.count
            let wordCount = text
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .count
            let lineCount = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
            return [
                "\(Self.decimalString(characterCount)) 个字符",
                "\(Self.decimalString(wordCount)) 单词",
                "\(Self.decimalString(lineCount)) 行"
            ]
        }

        return [content.metadata]
    }

    private static func estimatedTextMetrics(for text: String) -> (preferredWidth: CGFloat, preferredHeight: CGFloat) {
        let font = Layout.previewTextFont
        let longestLineLength = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(\.count)
            .max() ?? 0
        let averageGlyphWidth = max(7.2, ceil(("剪贴板" as NSString).size(withAttributes: [.font: font]).width / 3))
        let longestLineWidth = CGFloat(min(max(longestLineLength, 18), 54)) * averageGlyphWidth
        let preferredWidth = bounded(
            longestLineWidth + Layout.textHorizontalPadding * 2 + Layout.previewHorizontalInset * 2 + 24,
            minimum: Layout.minWidth,
            maximum: availableMaximumTextWidth()
        )
        let documentWidth = preferredWidth - Layout.previewHorizontalInset * 2
        let preferredHeight = estimatedTextDocumentHeight(for: text, documentWidth: documentWidth, font: font)
        return (preferredWidth, preferredHeight)
    }

    private static func estimatedTextDocumentHeight(for text: String, documentWidth: CGFloat, font: NSFont) -> CGFloat {
        if text.count > Layout.preciseTextMeasurementLimit {
            return approximateTextDocumentHeight(for: text, documentWidth: documentWidth, font: font)
        }

        let textWidth = max(40, documentWidth - Layout.textHorizontalPadding * 2)
        let measured = (text.isEmpty ? " " : text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(measured.height) + Layout.textVerticalPadding * 2 + 2
    }

    private static func approximateTextDocumentHeight(for text: String, documentWidth: CGFloat, font: NSFont) -> CGFloat {
        let textWidth = max(40, documentWidth - Layout.textHorizontalPadding * 2)
        let averageGlyphWidth = max(7.2, ceil(("剪贴板" as NSString).size(withAttributes: [.font: font]).width / 3))
        let charactersPerLine = max(1, Int(floor(textWidth / averageGlyphWidth)))
        var visualLineCount = 1
        var currentLineLength = 0

        for character in text {
            if character.isNewline {
                visualLineCount += 1
                currentLineLength = 0
                continue
            }

            currentLineLength += 1
            if currentLineLength >= charactersPerLine {
                visualLineCount += 1
                currentLineLength = 0
            }
        }

        let lineHeight = ceil(font.boundingRectForFont.height + 3)
        return CGFloat(visualLineCount) * lineHeight + Layout.textVerticalPadding * 2 + 2
    }

    static func imagePixelSize(for image: NSImage) -> NSSize? {
        if let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        return image.size.width > 0 && image.size.height > 0 ? image.size : nil
    }

    static func visiblePixelBounds(for image: NSImage) -> NSRect? {
        guard let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) })
        else {
            return nil
        }

        guard bitmap.hasAlpha else {
            return NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = -1
        var maxY = -1
        let alphaThreshold: CGFloat = 0.03

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y),
                      color.alphaComponent > alphaThreshold
                else {
                    continue
                }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        return NSRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private static func decimalString(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func bounded(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }

    private static func availableMaximumWidth() -> CGFloat {
        min(Layout.maxWidth, (NSScreen.main?.visibleFrame.width ?? 1200) - 96)
    }

    private static func availableMaximumTextWidth() -> CGFloat {
        min(Layout.maxTextWidth, (NSScreen.main?.visibleFrame.width ?? 1200) - 128)
    }

    private static func availableMaximumContentHeight() -> CGFloat {
        min(Layout.maxContentHeight, (NSScreen.main?.visibleFrame.height ?? 820) - 156 - Layout.chromeHeight)
    }

    private static func fittedImagePreviewSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: Layout.minWidth - Layout.previewHorizontalInset * 2, height: Layout.minContentHeight)
        }

        let maximumContentWidth = availableMaximumWidth() - Layout.imagePreviewHorizontalInset * 2
        let maximumContentHeight = availableMaximumContentHeight()
        let minimumContentWidth = Layout.minWidth - Layout.imagePreviewHorizontalInset * 2
        let imageAspectRatio = imageSize.width / imageSize.height
        let boundedScale = min(
            maximumContentWidth / imageSize.width,
            maximumContentHeight / imageSize.height,
            1
        )

        var fittedWidth = floor(imageSize.width * boundedScale)
        var fittedHeight = floor(imageSize.height * boundedScale)
        if fittedWidth < minimumContentWidth {
            fittedWidth = minimumContentWidth
            fittedHeight = floor(fittedWidth / imageAspectRatio)
        }

        if fittedHeight > maximumContentHeight {
            fittedHeight = maximumContentHeight
            fittedWidth = floor(fittedHeight * imageAspectRatio)
        }

        if fittedHeight < Layout.minContentHeight {
            fittedHeight = Layout.minContentHeight
            fittedWidth = floor(fittedHeight * imageAspectRatio)
        }

        fittedWidth = bounded(fittedWidth, minimum: minimumContentWidth, maximum: maximumContentWidth)
        fittedHeight = bounded(fittedHeight, minimum: Layout.minContentHeight, maximum: maximumContentHeight)
        return NSSize(width: fittedWidth, height: fittedHeight)
    }
}

private final class PreviewImageDocumentView: NSView {
    private let image: NSImage?
    private let imageSize: NSSize
    private let visiblePixelBounds: NSRect?
    private let checkerLight = NSColor(calibratedWhite: 0.72, alpha: 0.22)
    private let checkerDark = NSColor(calibratedWhite: 0.18, alpha: 0.18)

    init(image: NSImage?, viewportSize: NSSize) {
        self.image = image
        self.imageSize = image.flatMap(ClipboardPreviewViewController.imagePixelSize(for:))
            ?? NSSize(width: 320, height: 220)
        self.visiblePixelBounds = image.flatMap(ClipboardPreviewViewController.visiblePixelBounds(for:))
        super.init(frame: NSRect(origin: .zero, size: viewportSize))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawCheckerboard(in: dirtyRect)

        guard let image else {
            drawFallbackText()
            return
        }

        let visibleSize = visiblePixelBounds?.size ?? imageSize
        let imageRect = aspectFitRect(for: visibleSize, in: bounds)
        NSGraphicsContext.current?.imageInterpolation = .high
        if let visiblePixelBounds,
           let cropRect = imageRectForVisiblePixels(visiblePixelBounds, in: imageRect) {
            image.draw(in: cropRect)
        } else {
            image.draw(in: imageRect)
        }
    }

    private func aspectFitRect(for imageSize: NSSize, in bounds: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaledSize = NSSize(
            width: floor(imageSize.width * scale),
            height: floor(imageSize.height * scale)
        )
        return NSRect(
            x: floor(bounds.midX - scaledSize.width / 2),
            y: floor(bounds.midY - scaledSize.height / 2),
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    private func imageRectForVisiblePixels(_ visibleBounds: NSRect, in targetVisibleRect: NSRect) -> NSRect? {
        guard visibleBounds.width > 0, visibleBounds.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        let scale = targetVisibleRect.width / visibleBounds.width
        return NSRect(
            x: floor(targetVisibleRect.minX - visibleBounds.minX * scale),
            y: floor(targetVisibleRect.minY - visibleBounds.minY * scale),
            width: floor(imageSize.width * scale),
            height: floor(imageSize.height * scale)
        )
    }

    private func drawCheckerboard(in rect: NSRect) {
        NSColor(calibratedWhite: 0.06, alpha: 0.26).setFill()
        rect.fill()

        let square: CGFloat = 12
        checkerLight.setFill()
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

    private func drawFallbackText() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let text = NSString(string: "预览不可用")
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
