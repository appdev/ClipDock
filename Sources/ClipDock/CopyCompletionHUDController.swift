import AppKit

@MainActor
final class CopyCompletionHUDController {
    private enum Layout {
        static let contentSize = NSSize(width: 198, height: 198)
        static let bottomOffset: CGFloat = 75
        static let shadowOutset: CGFloat = 28
        static let windowSize = NSSize(
            width: contentSize.width + shadowOutset * 2,
            height: contentSize.height + shadowOutset * 2
        )
        static let hideDelayNanoseconds: UInt64 = 900_000_000
        static let hideDuration: TimeInterval = 0.25
        static let cornerRadius: CGFloat = 28
    }

    private var panel: CopyCompletionHUDPanel?
    private var dismissalTask: Task<Void, Never>?
    private var animationGeneration = 0
    private(set) var lastEventID: String?

    var debugWindowIdentity: ObjectIdentifier? {
        panel.map(ObjectIdentifier.init)
    }

    var debugIsVisible: Bool {
        panel?.isVisible == true
    }

    var debugContentColors: CopyCompletionHUDDebugContentColors? {
        (panel?.contentView as? CopyCompletionHUDContentView)?.debugContentColors
    }

    func show(eventID: String) {
        lastEventID = eventID
        animationGeneration += 1
        let generation = animationGeneration
        dismissalTask?.cancel()

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let finalFrame = targetFrame(for: panel)
        panel.setFrame(finalFrame, display: true)
        (panel.contentView as? CopyCompletionHUDContentView)?.updateContentColors()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Layout.hideDelayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.hide(generation: generation)
        }
    }

    func hideImmediatelyForTesting() {
        dismissalTask?.cancel()
        panel?.orderOut(nil)
        panel?.alphaValue = 0
    }

    private func hide(generation: Int) {
        guard generation == animationGeneration,
              let panel,
              panel.isVisible else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self,
                      let panel,
                      generation == self.animationGeneration else {
                    return
                }
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel() -> CopyCompletionHUDPanel {
        let panel = CopyCompletionHUDPanel(
            contentRect: NSRect(origin: .zero, size: Layout.windowSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.contentView = makeContentView()
        return panel
    }

    private func makeContentView() -> NSView {
        let root = CopyCompletionHUDContentView(frame: NSRect(origin: .zero, size: Layout.windowSize))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        let shadowHostFrame = NSRect(
            x: Layout.shadowOutset,
            y: Layout.shadowOutset,
            width: Layout.contentSize.width,
            height: Layout.contentSize.height
        )
        let shadowHost = NSView(frame: shadowHostFrame)
        shadowHost.wantsLayer = true
        shadowHost.layer?.masksToBounds = false
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.12
        shadowHost.layer?.shadowRadius = 22
        shadowHost.layer?.shadowOffset = NSSize(width: 0, height: -8)
        shadowHost.layer?.shadowPath = CGPath(
            roundedRect: NSRect(origin: .zero, size: Layout.contentSize),
            cornerWidth: Layout.cornerRadius,
            cornerHeight: Layout.cornerRadius,
            transform: nil
        )
        root.addSubview(shadowHost)

        let card = CopyCompletionHUDCardView(
            frame: NSRect(origin: .zero, size: Layout.contentSize),
            cornerRadius: Layout.cornerRadius
        )
        shadowHost.addSubview(card)

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: AppLocalization.text("copy.completed", defaultValue: "已复制")
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 72, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: AppLocalization.text("copy.completed", defaultValue: "已复制"))
        label.font = .systemFont(ofSize: 22, weight: .regular)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 84),
            icon.heightAnchor.constraint(equalToConstant: 84),
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])

        root.bindContent(icon: icon, label: label)
        return root
    }

    private func targetFrame(for panel: NSPanel) -> NSRect {
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let origin = NSPoint(
            x: visibleFrame.midX - Layout.windowSize.width / 2,
            y: visibleFrame.minY + Layout.bottomOffset - Layout.shadowOutset
        )
        return NSRect(origin: origin, size: Layout.windowSize)
    }
}

struct CopyCompletionHUDDebugContentColors {
    let iconTintColor: NSColor?
    let labelTextColor: NSColor?
}

private final class CopyCompletionHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CopyCompletionHUDContentView: NSView {
    private weak var icon: NSImageView?
    private weak var label: NSTextField?

    var debugContentColors: CopyCompletionHUDDebugContentColors {
        CopyCompletionHUDDebugContentColors(
            iconTintColor: icon?.contentTintColor,
            labelTextColor: label?.textColor
        )
    }

    func bindContent(icon: NSImageView, label: NSTextField) {
        self.icon = icon
        self.label = label
        updateContentColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateContentColors()
    }

    func updateContentColors() {
        let foreground = CopyCompletionHUDPalette.resolve(for: effectiveAppearance).foreground
        icon?.contentTintColor = foreground
        label?.textColor = foreground
    }
}

private final class CopyCompletionHUDCardView: NSVisualEffectView {
    private let cardCornerRadius: CGFloat

    init(frame: NSRect, cornerRadius: CGFloat) {
        self.cardCornerRadius = cornerRadius
        super.init(frame: frame)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        updateLayerAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerAppearance()
    }

    private func updateLayerAppearance() {
        guard let layer else { return }
        layer.cornerRadius = cardCornerRadius
        layer.masksToBounds = true
        layer.borderWidth = 0
        layer.backgroundColor = NSColor.clear.cgColor
    }
}

enum CopyCompletionHUDPalette {
    static let foreground = NSColor(name: nil) { appearance in
        resolve(for: appearance).foreground
    }

    struct Resolved {
        let foreground: NSColor
    }

    static func resolve(for appearance: NSAppearance) -> Resolved {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return Resolved(
                foreground: NSColor(calibratedWhite: 0.98, alpha: 0.68)
            )
        }
        return Resolved(
            foreground: NSColor(calibratedWhite: 0.28, alpha: 0.68)
        )
    }
}
