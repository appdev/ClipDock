import AppKit
import Testing
@testable import ClipDock

struct PanelPreviewRichTextStylerTests {
    @Test
    func mapsMissingAndLikelyDefaultColorsToTheme() {
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
        #expect(display.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor == bodyColor)
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
    func keepsInlineCodeBackgroundInline() {
        let source = NSMutableAttributedString(string: "text displayRTF plain text")
        source.addAttribute(
            .backgroundColor,
            value: NSColor(calibratedRed: 1, green: 0.96, blue: 0.82, alpha: 1),
            range: NSRange(location: 0, length: 4)
        )
        source.addAttribute(
            .backgroundColor,
            value: NSColor(calibratedRed: 1, green: 0.96, blue: 0.82, alpha: 1),
            range: NSRange(location: 5, length: 10)
        )

        let plan = ClipboardRichTextPreviewStyler.displayPlan(
            source,
            bodyColor: .black,
            surfaceColor: .white
        )

        #expect(plan.promotedBackgroundColor == nil)
        #expect(plan.attributedString.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
    }
}
