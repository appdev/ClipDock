import AppKit
import Testing
@testable import ClipDock

struct ClipDockThemeTests {
    @Test
    @MainActor
    func resolvesSeparateLightAndDarkPalettes() throws {
        let light = ClipDockTheme.current(for: NSAppearance(named: .aqua))
        let dark = ClipDockTheme.current(for: NSAppearance(named: .darkAqua))

        #expect(light.scheme == .light)
        #expect(dark.scheme == .dark)
        #expect(colorDistance(light.card.backgroundColor, dark.card.backgroundColor) > 0.2)
        #expect(colorDistance(light.card.textItemBackgroundColor, dark.card.textItemBackgroundColor) > 0.2)
        #expect(colorDistance(light.card.linkFooterBackgroundColor, dark.card.linkFooterBackgroundColor) > 0.2)
        #expect(colorDistance(
            light.card.imagePreviewCheckerboardBackgroundColor,
            dark.card.imagePreviewCheckerboardBackgroundColor
        ) > 0.2)
        #expect(colorDistance(light.preferences.contentBackgroundColor, dark.preferences.contentBackgroundColor) > 0.2)
        #expect(colorDistance(light.preview.bodyTextColor, dark.preview.bodyTextColor) > 0.2)
    }

    @Test
    @MainActor
    func appliesStoredAppearanceModeToApplicationAppearance() throws {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { NSApp.appearance = originalAppearance }

        ClipDockTheme.applyAppearanceMode("dark")
        #expect(app.appearance?.name == .darkAqua)

        ClipDockTheme.applyAppearanceMode("light")
        #expect(app.appearance?.name == .aqua)

        ClipDockTheme.applyAppearanceMode("system")
        #expect(app.appearance == nil)
    }

    @Test
    @MainActor
    func coreSurfacesKeepReadableContrastInBothSchemes() throws {
        let palettes = [
            ClipDockTheme.current(for: NSAppearance(named: .aqua)),
            ClipDockTheme.current(for: NSAppearance(named: .darkAqua))
        ]

        for palette in palettes {
            #expect(contrastRatio(palette.card.primaryTextColor, palette.card.backgroundColor) >= 4.5)
            #expect(contrastRatio(palette.card.primaryTextColor, palette.card.textItemBackgroundColor) >= 4.5)
            #expect(contrastRatio(palette.card.primaryTextColor, palette.card.linkFooterBackgroundColor) >= 4.5)
            #expect(contrastRatio(palette.preferences.primaryTextColor, palette.preferences.contentBackgroundColor) >= 4.5)
            #expect(contrastRatio(palette.preview.bodyTextColor, palette.preview.surfaceBackgroundColor) >= 4.5)
        }
    }

    @Test
    @MainActor
    func textBodyFadeUsesSemanticThemeRampForTextItemSurface() throws {
        let palettes = [
            ClipDockTheme.current(for: NSAppearance(named: .aqua)),
            ClipDockTheme.current(for: NSAppearance(named: .darkAqua))
        ]

        for palette in palettes {
            let backgroundAlpha = palette.card.textItemBackgroundColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0
            let topAlpha = palette.card.textBodyFadeTopColor.usingColorSpace(.sRGB)?.alphaComponent ?? 1
            let middleAlpha = palette.card.textBodyFadeMiddleColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0
            let footerAlpha = palette.card.textBodyFadeFooterColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0
            let bottomAlpha = palette.card.textBodyFadeBottomColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0

            #expect(colorDistance(palette.card.textBodyFadeTopColor, palette.card.textItemBackgroundColor) < 0.001)
            #expect(colorDistance(palette.card.textBodyFadeMiddleColor, palette.card.textItemBackgroundColor) < 0.001)
            #expect(colorDistance(palette.card.textBodyFadeFooterColor, palette.card.textItemBackgroundColor) < 0.001)
            #expect(colorDistance(palette.card.textBodyFadeBottomColor, palette.card.textItemBackgroundColor) < 0.001)
            #expect(topAlpha == 0)
            #expect(middleAlpha > topAlpha)
            #expect(footerAlpha > middleAlpha)
            #expect(bottomAlpha > footerAlpha)
            #expect(bottomAlpha < backgroundAlpha)
        }
    }

    @Test
    @MainActor
    func textItemBackgroundUsesPureWhiteAndReferenceDarkGray() throws {
        let light = ClipDockTheme.current(for: NSAppearance(named: .aqua)).card
        let dark = ClipDockTheme.current(for: NSAppearance(named: .darkAqua)).card

        #expect(colorAndAlphaDistance(light.textItemBackgroundColor, NSColor.white) < 0.001)
        #expect(colorAndAlphaDistance(
            dark.textItemBackgroundColor,
            NSColor(srgbRed: 20.0 / 255.0, green: 20.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
        ) < 0.001)
    }

    @Test
    @MainActor
    func darkLinkCardSurfacesStayInReferenceGrayRange() throws {
        let card = ClipDockTheme.current(for: NSAppearance(named: .darkAqua)).card
        let previewLuminance = relativeLuminance(card.linkPreviewBackgroundColor)
        let footerLuminance = relativeLuminance(card.linkFooterBackgroundColor)

        #expect(previewLuminance >= 0.012)
        #expect(previewLuminance <= 0.020)
        #expect(footerLuminance >= 0.025)
        #expect(footerLuminance <= 0.040)
        #expect(footerLuminance > previewLuminance)
    }

    @Test
    @MainActor
    func panelTintStaysLightAndTranslucent() throws {
        let palettes = [
            ClipDockTheme.current(for: NSAppearance(named: .aqua)),
            ClipDockTheme.current(for: NSAppearance(named: .darkAqua))
        ]

        for palette in palettes {
            let alpha = palette.panel.backgroundColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0

            #expect(alpha >= 0.30)
            #expect(alpha <= 0.34)
        }
    }

    @Test
    @MainActor
    func toolbarIconsUseToolbarTextColorInBothSchemes() throws {
        let palettes = [
            ClipDockTheme.current(for: NSAppearance(named: .aqua)),
            ClipDockTheme.current(for: NSAppearance(named: .darkAqua))
        ]

        for palette in palettes {
            #expect(colorAndAlphaDistance(palette.panel.toolbarIconColor, palette.panel.toolbarTextColor) < 0.001)
        }
    }

    @Test
    @MainActor
    func aboutWindowUsesReadableThemeInBothSchemes() throws {
        let app = NSApplication.shared
        let originalAppearance = app.appearance
        defer { app.appearance = originalAppearance }

        app.appearance = NSAppearance(named: .aqua)
        let lightController = AboutWindowController()
        let lightBackground = try #require(layerBackgroundColor(for: lightController))
        let lightTitleColor = try #require(largestLabel(in: lightController.window?.contentView)?.textColor)

        app.appearance = NSAppearance(named: .darkAqua)
        let darkController = AboutWindowController()
        defer {
            lightController.close()
            darkController.close()
        }
        let darkBackground = try #require(layerBackgroundColor(for: darkController))
        let darkTitleColor = try #require(largestLabel(in: darkController.window?.contentView)?.textColor)

        #expect(colorDistance(lightBackground, darkBackground) > 0.2)
        #expect(contrastRatio(lightTitleColor, lightBackground) >= 4.5)
        #expect(contrastRatio(darkTitleColor, darkBackground) >= 4.5)
    }

    @Test
    @MainActor
    func aboutWindowAppIconDoesNotExposeCheckerboardCorners() throws {
        let controller = AboutWindowController()
        defer { controller.close() }
        let imageView = try #require(firstImageView(in: controller.window?.contentView))
        let image = try #require(imageView.image)
        let bitmap = try #require(renderedBitmap(for: image, size: NSSize(width: 128, height: 128)))
        let alpha = bitmap.colorAt(x: 2, y: 2)?.alphaComponent ?? 1

        #expect(alpha < 0.05)
    }

    @Test
    @MainActor
    func aboutWindowDoesNotExposeLocalDocumentationControls() throws {
        let controller = AboutWindowController()
        defer { controller.close() }
        let contentView = try #require(controller.window?.contentView)

        for toolTip in ["文档首页", "架构说明", "UI QA", "发布说明"] {
            #expect(view(withToolTip: toolTip, in: contentView) == nil)
        }

        let buttonTitles = Set(allSubviews(of: contentView)
            .compactMap { ($0 as? NSButton)?.title })
        #expect(buttonTitles.isDisjoint(with: ["项目文档", "发布说明"]))
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

    private func colorAndAlphaDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        guard let lhs = lhs.usingColorSpace(.sRGB),
              let rhs = rhs.usingColorSpace(.sRGB)
        else {
            return 0
        }

        return colorDistance(lhs, rhs) + abs(lhs.alphaComponent - rhs.alphaComponent)
    }

    @MainActor
    private func layerBackgroundColor(for controller: AboutWindowController) -> NSColor? {
        guard let backgroundColor = controller.window?.contentView?.layer?.backgroundColor else {
            return nil
        }

        return NSColor(cgColor: backgroundColor)
    }

    @MainActor
    private func largestLabel(in view: NSView?) -> NSTextField? {
        allSubviews(of: view)
            .compactMap { $0 as? NSTextField }
            .max { ($0.font?.pointSize ?? 0) < ($1.font?.pointSize ?? 0) }
    }

    @MainActor
    private func firstImageView(in view: NSView?) -> NSImageView? {
        allSubviews(of: view)
            .compactMap { $0 as? NSImageView }
            .first
    }

    @MainActor
    private func view(withToolTip toolTip: String, in view: NSView?) -> NSView? {
        allSubviews(of: view)
            .first { $0.toolTip == toolTip }
    }

    @MainActor
    private func allSubviews(of view: NSView?) -> [NSView] {
        guard let view else { return [] }

        return view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func renderedBitmap(for image: NSImage, size: NSSize) -> NSBitmapImageRep? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let bitmap else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }
}
