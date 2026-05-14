import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp
import QuickLookUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class ClipboardPreviewPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var shownItemID: String?
    private var keyDownMonitor: Any?
    private weak var returnFocusView: NSView?
    private var linkWebPreviewEnabled = true

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
        linkWebPreviewEnabled: Bool = true,
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
            linkWebPreviewEnabled: linkWebPreviewEnabled,
            relativeTo: anchorView,
            returnFocusTo: focusView
        )
    }

    func show(
        item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        linkWebPreviewEnabled: Bool = true,
        relativeTo anchorView: NSView,
        returnFocusTo focusView: NSView
    ) {
        close(restoresFocus: false)
        self.linkWebPreviewEnabled = linkWebPreviewEnabled

        let content = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: appSupportDirectory
        )
        let viewController = ClipboardPreviewViewController(
            content: content,
            linkWebPreviewEnabled: linkWebPreviewEnabled
        )
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
        (popover.contentViewController as? ClipboardPreviewViewController)?.prepareForClose()
        popover.contentViewController = nil
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
        static let minMediaContentWidth: CGFloat = 420
        static let minMediaContentHeight: CGFloat = 180
        static let minDocumentWidth: CGFloat = 520
        static let minDocumentContentHeight: CGFloat = 360
        static let minLinkPreviewWidth: CGFloat = 640
        static let minLinkPreviewContentHeight: CGFloat = 420
        static let maxTextWidth: CGFloat = 720
        static let maxContentHeight: CGFloat = 560
        static let headerHeight: CGFloat = 34
        static let footerHeight: CGFloat = 36
        static let previewHorizontalInset: CGFloat = 0
        static let imagePreviewHorizontalInset: CGFloat = 0
        static let previewMaximumScreenFraction: CGFloat = 0.5
        static let previewShellExtraWidth: CGFloat = 10
        static let previewShellExtraHeight: CGFloat = 76
        static let minCompactPreviewShellWidth: CGFloat = 112
        static let minTextPreviewShellWidth: CGFloat = 390
        static let minTextPreviewContentHeight: CGFloat = 240
        static let textPreviewExtraHorizontalPadding: CGFloat = 20
        static let textHorizontalPadding: CGFloat = 8
        static let textVerticalPadding: CGFloat = 10
        static let textLineFragmentPadding: CGFloat = 5
        static let windowCornerRadius: CGFloat = 20
        static let chromeHorizontalInset: CGFloat = 16
        static let closeButtonSize: CGFloat = 16
        static let textPreviewMeasurementLimit = 2_000
        static let chromeHeight: CGFloat = headerHeight + footerHeight
        static var previewTextFont: NSFont {
            NSFont(name: "HelveticaNeue", size: 13) ?? .systemFont(ofSize: 13)
        }
    }

    private let content: ClipboardPreviewContent
    private let linkWebPreviewEnabled: Bool
    var onClose: (() -> Void)?
    private var quickLookPreviewView: QLPreviewView?
    private var linkWebView: WKWebView?
    private var linkNavigationDelegate: LinkPreviewNavigationDelegate?
    private var theme: PasteThemePalette {
        isViewLoaded ? PasteTheme.current(for: view) : PasteTheme.current(for: NSApp.effectiveAppearance)
    }

    init(content: ClipboardPreviewContent, linkWebPreviewEnabled: Bool = true) {
        self.content = content
        self.linkWebPreviewEnabled = linkWebPreviewEnabled
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.preferredSize(
            for: content,
            linkWebPreviewEnabled: linkWebPreviewEnabled
        )
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
        root.layer?.backgroundColor = theme.panel.backgroundColor.cgColor
        root.layer?.cornerRadius = Layout.windowCornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.layer?.borderColor = previewOuterBorderColor().cgColor
        root.layer?.borderWidth = 0.5

        let header = makeHeader()
        let preview = makePreview()
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

    fileprivate static func preferredSize(
        for content: ClipboardPreviewContent,
        linkWebPreviewEnabled: Bool = true
    ) -> NSSize {
        if content.itemType == "link",
           linkWebPreviewEnabled,
           content.linkURL != nil {
            return preferredLinkPreviewSize()
        }

        if content.itemType == "image",
           let image = content.imageURL.flatMap(NSImage.init(contentsOf:)) {
            let pixelSize = imagePixelSize(for: image) ?? image.size
            return preferredImagePreviewSize(for: pixelSize)
        }

        if content.itemType == "file",
           let fileURL = content.fileURLs.first,
           FileManager.default.fileExists(atPath: fileURL.path) {
            return preferredFilePreviewSize(for: fileURL, fileCount: content.fileURLs.count)
        }

        return preferredTextPreviewSize(for: content.body)
    }

    private func makeHeader() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let closeButton = PreviewCloseButton()
        closeButton.configure(
            backgroundColor: previewCloseButtonBackgroundColor(),
            tintColor: previewCloseButtonTintColor()
        )
        closeButton.target = nil
        closeButton.action = nil
        closeButton.onPress = { [weak self] in
            self?.onClose?()
        }
        closeButton.toolTip = "关闭预览"
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: displayTypeTitle())
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
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
            closeButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.chromeHorizontalInset),
            closeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Layout.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Layout.closeButtonSize),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -Layout.chromeHorizontalInset),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }

    private func makePreview() -> NSView {
        if content.itemType == "image" {
            return makeImagePreview()
        }

        if content.itemType == "file", !content.fileURLs.isEmpty {
            return makeFilePreview() ?? makeTextPreview()
        }

        if content.itemType == "link",
           linkWebPreviewEnabled,
           content.linkURL != nil {
            return makeLinkWebPreview()
        }

        return makeTextPreview()
    }

    private func makeLinkWebPreview() -> NSView {
        guard let linkURL = content.linkURL else {
            return makeTextPreview()
        }

        let container = makePreviewSurface(backgroundAlpha: 0.76)
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigationDelegate = LinkPreviewNavigationDelegate()
        webView.navigationDelegate = navigationDelegate
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        linkWebView = webView
        linkNavigationDelegate = navigationDelegate

        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let request = URLRequest(
            url: linkURL,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 60
        )
        webView.load(request)
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
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = theme.preview.bodyTextColor
        textView.font = Layout.previewTextFont
        textView.textContainerInset = NSSize(
            width: Layout.textHorizontalPadding,
            height: Layout.textVerticalPadding
        )
        textView.textContainer?.lineFragmentPadding = Layout.textLineFragmentPadding
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
        textView.textStorage?.setAttributedString(Self.previewTextAttributedString(
            for: content.body,
            foregroundColor: theme.preview.bodyTextColor
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

    private func makeFilePreview() -> NSView? {
        guard let url = content.fileURLs.first,
              FileManager.default.fileExists(atPath: url.path),
              let quickLookView = FocusPreservingQLPreviewView(frame: .zero, style: .normal)
        else {
            return nil
        }

        let container = makePreviewSurface(backgroundAlpha: 0.76)
        quickLookView.translatesAutoresizingMaskIntoConstraints = false
        quickLookView.previewItem = FilePreviewItem(url: url)
        quickLookPreviewView = quickLookView

        container.addSubview(quickLookView)
        NSLayoutConstraint.activate([
            quickLookView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            quickLookView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            quickLookView.topAnchor.constraint(equalTo: container.topAnchor),
            quickLookView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makePreviewSurface(backgroundAlpha _: CGFloat) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = 0
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.clear.cgColor
        container.layer?.borderWidth = 0
        return container
    }

    private func makeFooter() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let metadataStack = NSStackView()
        metadataStack.orientation = .horizontal
        metadataStack.alignment = .firstBaseline
        metadataStack.spacing = 10
        metadataStack.translatesAutoresizingMaskIntoConstraints = false

        footerComponents().enumerated().forEach { index, component in
            if index > 0 {
                metadataStack.addArrangedSubview(makeFooterLabel("·", isDimmed: true))
            }
            metadataStack.addArrangedSubview(makeFooterLabel(component, isDimmed: false))
        }

        container.addSubview(metadataStack)
        NSLayoutConstraint.activate([
            metadataStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.chromeHorizontalInset),
            metadataStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -Layout.chromeHorizontalInset),
            metadataStack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -1),
            metadataStack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 8),
            metadataStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -9)
        ])
        return container
    }

    private func makeFooterLabel(_ text: String, isDimmed: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = isDimmed ? theme.preview.footerDimTextColor : theme.preview.footerTextColor
        label.lineBreakMode = content.itemType == "file" ? .byTruncatingMiddle : .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func previewOuterBorderColor() -> NSColor {
        switch theme.scheme {
        case .light:
            return NSColor.black.withAlphaComponent(0.08)
        case .dark:
            return NSColor.white.withAlphaComponent(0.10)
        }
    }

    private func previewCloseButtonBackgroundColor() -> NSColor {
        switch theme.scheme {
        case .light:
            return NSColor.black.withAlphaComponent(0.07)
        case .dark:
            return NSColor.white.withAlphaComponent(0.11)
        }
    }

    private func previewCloseButtonTintColor() -> NSColor {
        switch theme.scheme {
        case .light:
            return NSColor.black.withAlphaComponent(0.58)
        case .dark:
            return NSColor.white.withAlphaComponent(0.70)
        }
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

        if content.itemType == "file", !content.fileURLs.isEmpty {
            if content.fileURLs.count > 1 {
                return ["\(content.fileURLs.count) 个文件", content.fileURLs[0].path]
            }
            return [content.fileURLs[0].path]
        }

        if content.itemType == "text" || content.itemType == "rich_text" || content.itemType == "link" {
            if content.itemType == "link", let displayURL = content.linkDisplayURL {
                return [displayURL]
            }
            let text = content.body
            let characterCount = text.count
            let lineCount = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
            return [
                "\(Self.decimalString(characterCount)) 个字符",
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
        if text.count > Layout.textPreviewMeasurementLimit {
            return approximateTextDocumentHeight(for: text, documentWidth: documentWidth, font: font)
        }

        let textWidth = max(
            40,
            documentWidth
                - Layout.textHorizontalPadding * 2
                - Layout.textLineFragmentPadding * 2
        )
        let measured = (text.isEmpty ? " " : text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(measured.height) + Layout.textVerticalPadding * 2 + 2
    }

    private static func approximateTextDocumentHeight(for text: String, documentWidth: CGFloat, font: NSFont) -> CGFloat {
        let textWidth = max(
            40,
            documentWidth
                - Layout.textHorizontalPadding * 2
                - Layout.textLineFragmentPadding * 2
        )
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

    private static func preferredFilePreviewSize(for url: URL, fileCount: Int) -> NSSize {
        guard fileCount == 1 else {
            return preferredDocumentFilePreviewSize()
        }

        if isImageFileURL(url),
           let image = NSImage(contentsOf: url) {
            let pixelSize = imagePixelSize(for: image) ?? image.size
            return preferredMediaPreviewSize(for: pixelSize)
        }

        if isVideoFileURL(url) {
            return preferredDocumentFilePreviewSize()
        }

        return preferredDocumentFilePreviewSize()
    }

    private static func preferredDocumentFilePreviewSize() -> NSSize {
        let screenFrame = documentPreviewScreenFrame()
        let contentSize = NSSize(
            width: floor(max(1, screenFrame.width * Layout.previewMaximumScreenFraction)),
            height: floor(max(1, screenFrame.height * Layout.previewMaximumScreenFraction))
        )
        return previewShellSize(for: contentSize)
    }

    private static func preferredLinkPreviewSize() -> NSSize {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
        let width = bounded(
            screenFrame.width * 0.56,
            minimum: min(Layout.minLinkPreviewWidth, max(Layout.minWidth, screenFrame.width - 96)),
            maximum: max(Layout.minWidth, screenFrame.width - 96)
        )
        let contentHeight = bounded(
            screenFrame.height * 0.58,
            minimum: min(Layout.minLinkPreviewContentHeight, max(Layout.minContentHeight, screenFrame.height - 156 - Layout.chromeHeight)),
            maximum: max(Layout.minContentHeight, screenFrame.height - 156 - Layout.chromeHeight)
        )
        return NSSize(width: width, height: contentHeight + Layout.chromeHeight)
    }

    private static func preferredMediaPreviewSize(for mediaSize: NSSize) -> NSSize {
        let contentSize = fittedMediaPreviewSize(for: mediaSize)
        return previewShellSize(for: contentSize)
    }

    private static func fittedMediaPreviewSize(for mediaSize: NSSize) -> NSSize {
        guard mediaSize.width > 0, mediaSize.height > 0 else {
            return NSSize(width: Layout.minMediaContentWidth, height: Layout.minMediaContentHeight)
        }

        let maximumContentWidth = availableMaximumWidth()
        let maximumContentHeight = availableMaximumContentHeight()
        let minimumContentWidth = min(Layout.minMediaContentWidth, maximumContentWidth)
        let minimumContentHeight = min(Layout.minMediaContentHeight, maximumContentHeight)
        let aspectRatio = mediaSize.width / mediaSize.height
        var fittedWidth = floor(mediaSize.width)
        var fittedHeight = floor(mediaSize.height)

        let downscale = min(maximumContentWidth / fittedWidth, maximumContentHeight / fittedHeight, 1)
        fittedWidth = floor(fittedWidth * downscale)
        fittedHeight = floor(fittedHeight * downscale)

        if fittedWidth < minimumContentWidth {
            fittedWidth = minimumContentWidth
            fittedHeight = floor(fittedWidth / aspectRatio)
        }

        if fittedHeight < minimumContentHeight {
            fittedHeight = minimumContentHeight
            fittedWidth = floor(fittedHeight * aspectRatio)
        }

        if fittedWidth > maximumContentWidth {
            fittedWidth = maximumContentWidth
            fittedHeight = floor(fittedWidth / aspectRatio)
        }

        if fittedHeight > maximumContentHeight {
            fittedHeight = maximumContentHeight
            fittedWidth = floor(fittedHeight * aspectRatio)
        }

        fittedWidth = bounded(fittedWidth, minimum: minimumContentWidth, maximum: maximumContentWidth)
        fittedHeight = bounded(fittedHeight, minimum: minimumContentHeight, maximum: maximumContentHeight)
        return NSSize(width: fittedWidth, height: fittedHeight)
    }

    private static func preferredTextPreviewSize(
        for text: String,
        maximumContentSize: NSSize = textPreviewMaximumContentSize()
    ) -> NSSize {
        let measuredText = previewTextAttributedString(for: text)
        let measured = attributedMeasurementPrefix(from: measuredText).boundingRect(
            with: maximumContentSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let contentSize = NSSize(
            width: min(
                maximumContentSize.width,
                ceil(measured.width)
                    + Layout.textHorizontalPadding * 2
                    + Layout.textPreviewExtraHorizontalPadding
            ),
            height: min(
                maximumContentSize.height,
                ceil(measured.height) + Layout.textVerticalPadding * 2
            )
        )
        return previewShellSize(
            for: contentSize,
            minimumWidth: Layout.minTextPreviewShellWidth,
            minimumContentHeight: Layout.minTextPreviewContentHeight
        )
    }

    private static func previewTextAttributedString(
        for text: String,
        foregroundColor: NSColor? = nil
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.lineSpacing = 0

        var attributes: [NSAttributedString.Key: Any] = [
            .font: Layout.previewTextFont,
            .paragraphStyle: paragraphStyle
        ]
        if let foregroundColor {
            attributes[.foregroundColor] = foregroundColor
        }

        return NSAttributedString(
            string: text.isEmpty ? " " : text,
            attributes: attributes
        )
    }

    private static func attributedMeasurementPrefix(from text: NSAttributedString) -> NSAttributedString {
        guard text.length >= Layout.textPreviewMeasurementLimit + 1 else {
            return text
        }

        return text.attributedSubstring(
            from: NSRange(location: 0, length: Layout.textPreviewMeasurementLimit)
        )
    }

    private static func isImageFileURL(_ url: URL) -> Bool {
        fileType(for: url)?.conforms(to: .image) == true
    }

    private static func isVideoFileURL(_ url: URL) -> Bool {
        guard let fileType = fileType(for: url) else { return false }
        return fileType.conforms(to: .movie)
            || ["mp4", "m4v", "mov", "avi", "mkv", "webm"].contains(url.pathExtension.lowercased())
    }

    private static func fileType(for url: URL) -> UTType? {
        UTType(filenameExtension: url.pathExtension)
    }

    private static func preferredImagePreviewSize(
        for imageSize: NSSize,
        screenFrame: NSRect = imagePreviewScreenFrame()
    ) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return previewShellSize(
                for: NSSize(width: Layout.minWidth, height: Layout.minContentHeight),
                minimumWidth: Layout.minCompactPreviewShellWidth
            )
        }

        let imageContentSize = fittedImagePreviewSize(for: imageSize, screenFrame: screenFrame)
        return previewShellSize(
            for: imageContentSize,
            minimumWidth: Layout.minCompactPreviewShellWidth
        )
    }

    private static func fittedImagePreviewSize(
        for imageSize: NSSize,
        screenFrame: NSRect = imagePreviewScreenFrame()
    ) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: Layout.minWidth - Layout.previewHorizontalInset * 2, height: Layout.minContentHeight)
        }

        // 图片预览遵循 Paste 的窗口策略：小图保持原尺寸，大图只按主屏半幅等比缩小。
        let maximumContentWidth = max(1, screenFrame.width * Layout.previewMaximumScreenFraction)
        let maximumContentHeight = max(1, screenFrame.height * Layout.previewMaximumScreenFraction)
        let scale = (imageSize.width > maximumContentWidth || imageSize.height > maximumContentHeight)
            ? min(maximumContentWidth / imageSize.width, maximumContentHeight / imageSize.height)
            : 1
        return NSSize(
            width: floor(imageSize.width * scale),
            height: floor(imageSize.height * scale)
        )
    }

    private static func imagePreviewScreenFrame() -> NSRect {
        NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
    }

    private static func documentPreviewScreenFrame() -> NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
    }

    private static func textPreviewMaximumContentSize() -> NSSize {
        guard let screenFrame = NSScreen.main?.frame else {
            return NSSize(width: 1_000, height: 1_000)
        }

        return NSSize(
            width: floor(max(1, screenFrame.width * Layout.previewMaximumScreenFraction)),
            height: floor(max(1, screenFrame.height * Layout.previewMaximumScreenFraction))
        )
    }

    private static func previewShellSize(
        for contentSize: NSSize,
        minimumWidth: CGFloat = 0,
        minimumContentHeight: CGFloat = 0
    ) -> NSSize {
        NSSize(
            width: max(
                floor(contentSize.width + Layout.previewShellExtraWidth),
                minimumWidth
            ),
            height: floor(max(contentSize.height, minimumContentHeight) + Layout.previewShellExtraHeight)
        )
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        clearLinkWebPreview()
        clearQuickLookPreview()
    }

    func prepareForClose() {
        clearLinkWebPreview()
        clearQuickLookPreview()
    }

    private func clearLinkWebPreview() {
        linkWebView?.stopLoading()
        linkWebView?.navigationDelegate = nil
        linkWebView?.uiDelegate = nil
        linkWebView?.removeFromSuperview()
        linkWebView = nil
        linkNavigationDelegate = nil
    }

    private func clearQuickLookPreview() {
        quickLookPreviewView?.previewItem = nil
        quickLookPreviewView = nil
    }
}

private final class PreviewCloseButton: PanelActionButton {
    private var circleColor = NSColor.clear
    private var symbolColor = NSColor.labelColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureButton()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height)
        let circleRect = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let fillColor = isHighlighted
            ? circleColor.withAlphaComponent(min(circleColor.alphaComponent + 0.08, 1))
            : circleColor
        fillColor.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        let iconInset = diameter * 0.32
        let iconRect = circleRect.insetBy(dx: iconInset, dy: iconInset)
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: iconRect.minX, y: iconRect.minY))
        path.line(to: NSPoint(x: iconRect.maxX, y: iconRect.maxY))
        path.move(to: NSPoint(x: iconRect.minX, y: iconRect.maxY))
        path.line(to: NSPoint(x: iconRect.maxX, y: iconRect.minY))
        symbolColor.setStroke()
        path.stroke()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    func configure(backgroundColor: NSColor, tintColor: NSColor) {
        circleColor = backgroundColor
        symbolColor = tintColor
        needsDisplay = true
    }

    private func configureButton() {
        bezelStyle = .regularSquare
        isBordered = false
        title = ""
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class LinkPreviewNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame != false,
              let scheme = navigationAction.request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        guard let scheme = navigationResponse.response.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

private final class FocusPreservingQLPreviewView: QLPreviewView {
    override var acceptsFirstResponder: Bool { false }
}

private final class FilePreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL) {
        previewItemURL = url
        previewItemTitle = url.lastPathComponent
        super.init()
    }
}

@MainActor
func smokePreferredClipboardPreviewSize(for content: ClipboardPreviewContent) -> NSSize {
    ClipboardPreviewViewController.preferredSize(for: content)
}

private final class PreviewImageDocumentView: NSView {
    private let image: NSImage?
    private let imageSize: NSSize
    private let checkerLight = NSColor(calibratedWhite: 0.72, alpha: 0.22)
    private let checkerDark = NSColor(calibratedWhite: 0.18, alpha: 0.18)

    init(image: NSImage?, viewportSize: NSSize) {
        self.image = image
        self.imageSize = image.flatMap(ClipboardPreviewViewController.imagePixelSize(for:))
            ?? NSSize(width: 320, height: 220)
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

        let imageRect = aspectFitRect(for: imageSize, in: bounds)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: imageRect)
    }

    private func aspectFitRect(for imageSize: NSSize, in bounds: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height, 1)
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
