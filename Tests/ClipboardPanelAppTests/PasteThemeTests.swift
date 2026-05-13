import AppKit
import Testing
@testable import PasteFloating

struct PasteThemeTests {
    @Test
    @MainActor
    func resolvesSeparateLightAndDarkPalettes() throws {
        let light = PasteTheme.current(for: NSAppearance(named: .aqua))
        let dark = PasteTheme.current(for: NSAppearance(named: .darkAqua))

        #expect(light.scheme == .light)
        #expect(dark.scheme == .dark)
        #expect(colorDistance(light.card.backgroundColor, dark.card.backgroundColor) > 0.2)
        #expect(colorDistance(light.preferences.contentBackgroundColor, dark.preferences.contentBackgroundColor) > 0.2)
        #expect(colorDistance(light.preview.bodyTextColor, dark.preview.bodyTextColor) > 0.2)
    }

    @Test
    @MainActor
    func appliesStoredAppearanceModeToApplicationAppearance() throws {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { NSApp.appearance = originalAppearance }

        PasteTheme.applyAppearanceMode("dark")
        #expect(app.appearance?.name == .darkAqua)

        PasteTheme.applyAppearanceMode("light")
        #expect(app.appearance?.name == .aqua)

        PasteTheme.applyAppearanceMode("system")
        #expect(app.appearance == nil)
    }

    @Test
    @MainActor
    func coreSurfacesKeepReadableContrastInBothSchemes() throws {
        let palettes = [
            PasteTheme.current(for: NSAppearance(named: .aqua)),
            PasteTheme.current(for: NSAppearance(named: .darkAqua))
        ]

        for palette in palettes {
            #expect(contrastRatio(palette.card.primaryTextColor, palette.card.backgroundColor) >= 4.5)
            #expect(contrastRatio(palette.preferences.primaryTextColor, palette.preferences.contentBackgroundColor) >= 4.5)
            #expect(contrastRatio(palette.preview.bodyTextColor, palette.preview.surfaceBackgroundColor) >= 4.5)
        }
    }

    @Test
    @MainActor
    func panelTintStaysLightAndTranslucent() throws {
        let palettes = [
            PasteTheme.current(for: NSAppearance(named: .aqua)),
            PasteTheme.current(for: NSAppearance(named: .darkAqua))
        ]

        for palette in palettes {
            let alpha = palette.panel.backgroundColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0

            #expect(alpha >= 0.30)
            #expect(alpha <= 0.34)
        }
    }

    private func contrastRatio(_ foreground: NSColor, _ background: NSColor) -> CGFloat {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let color = color.usingColorSpace(.sRGB) else {
            return 0
        }

        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(color.redComponent)
            + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
    }

    private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        guard let lhs = lhs.usingColorSpace(.sRGB),
              let rhs = rhs.usingColorSpace(.sRGB)
        else {
            return 0
        }

        return abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }
}
