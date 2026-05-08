import AppKit
import Testing
@testable import ClipboardPanelApp

@MainActor
struct PanelVisualSnapshotTests {
    @Test
    func rendersBottomPanelSnapshotWithStableVisualAnchors() throws {
        let screenFrame = CGRect(x: 0, y: 0, width: 960, height: 720)
        let panelFrame = BottomPanelGeometryPlanner.frame(
            screenFrame: screenFrame,
            preferredHeight: BottomPanelGeometryPlanner.defaultHeight
        )
        let view = PanelSnapshotFixtureView(frame: NSRect(origin: .zero, size: panelFrame.size))

        let bitmap = try render(view)
        let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
        let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("panel-visual-regression.png")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)

        #expect(bitmap.pixelsWide == 960)
        #expect(bitmap.pixelsHigh == 320)
        #expect(pngData.count > 12_000)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        assertColor(
            bitmap.colorAt(x: 480, y: 10),
            isCloseTo: PanelSnapshotFixtureView.resizeHandleColor,
            tolerance: 0.05
        )
        assertColor(
            bitmap.colorAt(x: 40, y: 89),
            isCloseTo: PanelSnapshotFixtureView.selectedHeaderColor,
            tolerance: 0.05
        )
        assertColor(
            bitmap.colorAt(x: 72, y: 154),
            isCloseTo: PanelSnapshotFixtureView.cardBodyColor,
            tolerance: 0.06
        )
        assertColor(
            bitmap.colorAt(x: 300, y: 180),
            isCloseTo: PanelSnapshotFixtureView.imagePreviewColor,
            tolerance: 0.06
        )
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.wantsLayer = true
        view.layoutSubtreeIfNeeded()
        let width = Int(view.bounds.width.rounded())
        let height = Int(view.bounds.height.rounded())
        let bitmap = try #require(NSBitmapImageRep(
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
        ))
        let graphicsContext = try #require(NSGraphicsContext(bitmapImageRep: bitmap))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        view.displayIgnoringOpacity(view.bounds, in: graphicsContext)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func assertColor(
        _ color: NSColor?,
        isCloseTo expected: NSColor,
        tolerance: CGFloat,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let sampled = color?.usingColorSpace(.deviceRGB),
              let expected = expected.usingColorSpace(.deviceRGB)
        else {
            Issue.record("expected a sampleable device RGB color", sourceLocation: sourceLocation)
            return
        }

        #expect(abs(sampled.redComponent - expected.redComponent) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(sampled.greenComponent - expected.greenComponent) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(sampled.blueComponent - expected.blueComponent) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(sampled.alphaComponent - expected.alphaComponent) <= tolerance, sourceLocation: sourceLocation)
    }
}

private final class PanelSnapshotFixtureView: NSView {
    static let resizeHandleColor = NSColor(deviceRed: 0.76, green: 0.80, blue: 0.84, alpha: 1)
    static let selectedHeaderColor = NSColor(deviceRed: 0.23, green: 0.50, blue: 0.92, alpha: 1)
    static let cardBodyColor = NSColor(deviceRed: 0.95, green: 0.96, blue: 0.94, alpha: 1)
    static let imagePreviewColor = NSColor(deviceRed: 0.36, green: 0.68, blue: 0.74, alpha: 1)

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawPanelBackground()
        drawResizeHandle()
        drawControlBar()
        drawCards()
    }

    private func drawPanelBackground() {
        NSColor(deviceRed: 0.88, green: 0.92, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()

        NSColor(deviceRed: 0.88, green: 0.92, blue: 0.88, alpha: 0.86).setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0, dy: 0),
            xRadius: 16,
            yRadius: 16
        ).fill()

        NSColor(deviceWhite: 1, alpha: 0.18).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 1)).fill()
    }

    private func drawResizeHandle() {
        Self.resizeHandleColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: bounds.midX - 36, y: 8, width: 72, height: 4),
            xRadius: 2,
            yRadius: 2
        ).fill()
    }

    private func drawControlBar() {
        drawRoundedRect(NSRect(x: 390, y: 30, width: 30, height: 30), color: NSColor(deviceWhite: 1, alpha: 0.36), radius: 15)
        drawText("⌕", in: NSRect(x: 400, y: 35, width: 12, height: 16), size: 14, color: NSColor(deviceWhite: 0.16, alpha: 1), weight: .semibold)

        let chips: [(String, NSColor?)] = [
            ("剪贴板", nil),
            ("文本", NSColor(deviceRed: 0.23, green: 0.50, blue: 0.92, alpha: 1)),
            ("链接", NSColor(deviceRed: 0.58, green: 0.27, blue: 0.88, alpha: 1)),
            ("图片", NSColor(deviceRed: 0.18, green: 0.65, blue: 0.36, alpha: 1)),
            ("文件", NSColor(deviceRed: 0.95, green: 0.58, blue: 0.16, alpha: 1))
        ]
        var x: CGFloat = 432
        for (index, chip) in chips.enumerated() {
            let width: CGFloat = index == 0 ? 76 : 62
            drawRoundedRect(
                NSRect(x: x, y: 30, width: width, height: 30),
                color: index == 0 ? NSColor(deviceWhite: 1, alpha: 0.42) : NSColor(deviceWhite: 1, alpha: 0.26),
                radius: 15
            )
            if let dot = chip.1 {
                dot.setFill()
                NSBezierPath(ovalIn: NSRect(x: x + 10, y: 42, width: 7, height: 7)).fill()
                drawText(chip.0, in: NSRect(x: x + 22, y: 38, width: width - 28, height: 14), size: 11, color: NSColor(deviceWhite: 0.16, alpha: 1), weight: .semibold)
            } else {
                drawText(chip.0, in: NSRect(x: x + 12, y: 38, width: width - 20, height: 14), size: 11, color: NSColor(deviceWhite: 0.16, alpha: 1), weight: .semibold)
            }
            x += width + 8
        }
    }

    private func drawCards() {
        let cardY: CGFloat = 88
        let cardWidth: CGFloat = 190
        let cardHeight: CGFloat = 168
        let gap: CGFloat = 12
        let types = ["文本", "图片", "文件", "链接"]
        let summaries = [
            "多行文本内容会在卡片中换行展示，避免只剩一行。",
            "图片 420 x 260",
            "2 个文件 · report.pdf",
            "example.com"
        ]

        for index in 0..<4 {
            let x = 28 + CGFloat(index) * (cardWidth + gap)
            let cardRect = NSRect(x: x, y: cardY, width: cardWidth, height: cardHeight)
            drawRoundedRect(cardRect, color: Self.cardBodyColor, radius: 8)
            let headerColor = index == 0
                ? Self.selectedHeaderColor
                : [NSColor.systemTeal, NSColor.systemIndigo, NSColor.systemBlue][max(0, index - 1)]
            drawRoundedRect(NSRect(x: x, y: cardY, width: cardWidth, height: 50), color: headerColor, radius: 8)

            drawText(types[index], in: NSRect(x: x + 12, y: cardY + 10, width: 78, height: 16), size: 12, color: .white, weight: .bold)
            drawText("刚刚", in: NSRect(x: x + 12, y: cardY + 27, width: 60, height: 14), size: 10, color: NSColor.white.withAlphaComponent(0.78), weight: .regular)
            drawRoundedRect(NSRect(x: x + cardWidth - 44, y: cardY + 8, width: 34, height: 34), color: NSColor.white.withAlphaComponent(0.86), radius: 9)

            if index == 1 {
                drawRoundedRect(
                    NSRect(x: x + 12, y: cardY + 68, width: cardWidth - 24, height: 58),
                    color: Self.imagePreviewColor,
                    radius: 7
                )
            }

            drawText(summaries[index], in: NSRect(x: x + 12, y: cardY + 68, width: cardWidth - 24, height: 48), size: 12, color: NSColor(deviceWhite: 0.18, alpha: 1), weight: .regular)
            drawText("\(summaries[index].count) 个字符", in: NSRect(x: x + 12, y: cardY + 142, width: 86, height: 14), size: 10, color: NSColor(deviceWhite: 0.50, alpha: 1), weight: .medium)
        }
    }

    private func drawRoundedRect(_ rect: NSRect, color: NSColor, radius: CGFloat) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private func drawText(
        _ string: String,
        in rect: NSRect,
        size: CGFloat,
        color: NSColor,
        weight: NSFont.Weight
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        string.draw(in: rect, withAttributes: attributes)
    }
}
