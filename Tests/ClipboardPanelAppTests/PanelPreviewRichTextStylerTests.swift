import AppKit
import Testing
@testable import ClipDock

struct PanelPreviewRichTextStylerTests {
    @Test
    func fillsMissingColorAndPreservesExplicitDefaultColor() {
        let bodyColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        let darkSurface = NSColor(calibratedWhite: 0.08, alpha: 1)
        let source = NSMutableAttributedString(string: "Default Explicit")
        source.addAttribute(
            .foregroundColor,
            value: NSColor.black,
            range: NSRange(location: 8, length: 8)
        )

        let display = ClipboardRichTextPreviewStyler.displayAttributedString(
            source,
            bodyColor: bodyColor,
            surfaceColor: darkSurface
        )

        #expect(display.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == bodyColor)
        #expect(display.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor == NSColor.black)
        #expect(source.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(source.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor == NSColor.black)
    }

    @Test
    func preservesReadableExplicitColor() {
        let source = NSAttributedString(
            string: "Blue",
            attributes: [.foregroundColor: NSColor.systemBlue]
        )

        let display = ClipboardRichTextPreviewStyler.displayAttributedString(
            source,
            bodyColor: .labelColor,
            surfaceColor: .white
        )

        #expect(display.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.systemBlue)
    }

    @Test
    func inlineSurfaceSuppressesNearWhiteDefaultBackgroundOnDarkSurface() {
        let bodyColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        let darkSurface = NSColor(calibratedWhite: 0.08, alpha: 1)
        let source = NSMutableAttributedString(
            string: "Default Highlight",
            attributes: [
                .foregroundColor: NSColor.black,
                .backgroundColor: NSColor(calibratedWhite: 0.98, alpha: 1)
            ]
        )

        let plan = ClipboardRichTextPreviewStyler.inlineSurfaceDisplayPlan(
            source,
            bodyColor: bodyColor,
            surfaceColor: darkSurface
        )

        #expect(plan.promotedBackgroundColor == nil)
        #expect(plan.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == bodyColor)
        #expect(plan.attributedString.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor == bodyColor)
        #expect(plan.attributedString.attribute(.backgroundColor, at: 8, effectiveRange: nil) == nil)
        #expect(source.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.black)
        #expect(source.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
    }

    @Test
    func suppressingDefaultBackgroundPreservesSyntaxColorsAndMapsDefaultLinks() {
        let bodyColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        let linkColor = NSColor.systemBlue
        let darkSurface = NSColor(calibratedWhite: 0.08, alpha: 1)
        let source = NSMutableAttributedString(
            string: "Default Syntax Link",
            attributes: [
                .foregroundColor: NSColor.black,
                .backgroundColor: NSColor.white
            ]
        )
        let syntaxRange = (source.string as NSString).range(of: "Syntax")
        let linkRange = (source.string as NSString).range(of: "Link")
        source.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: syntaxRange)
        source.addAttribute(.foregroundColor, value: NSColor.darkGray, range: linkRange)
        source.addAttribute(.link, value: URL(string: "https://example.com")!, range: linkRange)

        let plan = ClipboardRichTextPreviewStyler.displayPlan(
            source,
            bodyColor: bodyColor,
            surfaceColor: darkSurface,
            linkColor: linkColor
        )

        #expect(plan.promotedBackgroundColor == nil)
        #expect(plan.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == bodyColor)
        #expect(
            plan.attributedString.attribute(.foregroundColor, at: syntaxRange.location, effectiveRange: nil) as? NSColor
                == NSColor.systemPurple
        )
        #expect(
            plan.attributedString.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? NSColor
                == linkColor
        )
        #expect(plan.attributedString.attribute(.backgroundColor, at: syntaxRange.location, effectiveRange: nil) == nil)
    }

    @Test
    func promotesDominantBackgroundToContentSurface() throws {
        let source = NSMutableAttributedString(
            string: "2026-05-19 11:26:01 ClipDock log line\nsecond log line",
            attributes: [
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.darkGray
            ]
        )
        source.addAttribute(
            .backgroundColor,
            value: NSColor.systemYellow,
            range: NSRange(location: 0, length: 4)
        )

        let plan = ClipboardRichTextPreviewStyler.displayPlan(
            source,
            bodyColor: .black,
            surfaceColor: .white
        )
        let promoted = try #require(plan.promotedBackgroundColor?.usingColorSpace(.deviceRGB))
        let expected = try #require(NSColor.darkGray.usingColorSpace(.deviceRGB))

        #expect(abs(promoted.redComponent - expected.redComponent) < 0.03)
        #expect(plan.attributedString.attribute(.backgroundColor, at: 10, effectiveRange: nil) == nil)
        #expect(plan.attributedString.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor == NSColor.white)
    }

    @Test
    func promotesAnyVisibleRichTextBackgroundToContentSurface() throws {
        let source = NSMutableAttributedString(string: "text displayRTF plain text")
        let sourceBackground = NSColor(calibratedRed: 1, green: 0.985, blue: 0.90, alpha: 1)
        source.addAttribute(
            .backgroundColor,
            value: sourceBackground,
            range: NSRange(location: 0, length: 4)
        )
        source.addAttribute(
            .backgroundColor,
            value: sourceBackground,
            range: NSRange(location: 5, length: 10)
        )

        let plan = ClipboardRichTextPreviewStyler.displayPlan(
            source,
            bodyColor: .black,
            surfaceColor: .white
        )
        let promoted = try #require(plan.promotedBackgroundColor)

        #expect(colorAndAlphaDistance(promoted, sourceBackground) < 0.01)
        #expect(plan.attributedString.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test
    func preservesMeaningfulBackgroundsOnDarkSurface() throws {
        let darkSurface = NSColor(calibratedWhite: 0.08, alpha: 1)
        let backgrounds = [
            NSColor(calibratedRed: 1, green: 0.985, blue: 0.90, alpha: 1),
            NSColor.darkGray,
            NSColor.systemYellow
        ]

        for background in backgrounds {
            let source = NSAttributedString(
                string: "Meaningful background",
                attributes: [
                    .foregroundColor: NSColor.black,
                    .backgroundColor: background
                ]
            )

            let plan = ClipboardRichTextPreviewStyler.displayPlan(
                source,
                bodyColor: .white,
                surfaceColor: darkSurface
            )
            let promoted = try #require(plan.promotedBackgroundColor)

            #expect(colorAndAlphaDistance(promoted, background) < 0.05)
            #expect(plan.attributedString.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        }
    }
}

private func colorAndAlphaDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
    guard let lhs = lhs.usingColorSpace(.sRGB),
          let rhs = rhs.usingColorSpace(.sRGB)
    else {
        return .greatestFiniteMagnitude
    }

    return abs(lhs.redComponent - rhs.redComponent)
        + abs(lhs.greenComponent - rhs.greenComponent)
        + abs(lhs.blueComponent - rhs.blueComponent)
        + abs(lhs.alphaComponent - rhs.alphaComponent)
}
