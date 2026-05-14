import AppKit

struct ClipShelfThemePalette {
    let scheme: ClipShelfTheme.Scheme
    let panel: ClipShelfPanelTheme
    let card: ClipShelfCardTheme
    let preferences: ClipShelfPreferencesTheme
    let preview: ClipShelfPreviewTheme
}

struct ClipShelfPanelTheme {
    let backgroundColor: NSColor
    let toolbarIconColor: NSColor
    let toolbarTextColor: NSColor
    let toolbarSelectedBackgroundColor: NSColor
    let toolbarSelectedBorderColor: NSColor
    let toolbarSelectedTextColor: NSColor
    let resizeHandleColor: NSColor
}

struct ClipShelfCardTheme {
    let backgroundColor: NSColor
    let borderColor: NSColor
    let selectionBorderColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let footerTextColor: NSColor
    let headerTextColor: NSColor
    let headerSecondaryTextColor: NSColor
    let sourceIconBackgroundColor: NSColor
    let linkPreviewBackgroundColor: NSColor
    let appIconTileBackgroundColor: NSColor
}

struct ClipShelfPreferencesTheme {
    let windowBackgroundColor: NSColor
    let contentBackgroundColor: NSColor
    let sidebarBackgroundColor: NSColor
    let borderColor: NSColor
    let cardBackgroundColor: NSColor
    let cardBorderColor: NSColor
    let navigationSelectedBackgroundColor: NSColor
    let navigationSelectedTextColor: NSColor
    let navigationTextColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let separatorColor: NSColor
    let controlBackgroundColor: NSColor
}

struct ClipShelfPreviewTheme {
    let backgroundColor: NSColor
    let borderColor: NSColor
    let chromeBackgroundColor: NSColor
    let titleTextColor: NSColor
    let bodyTextColor: NSColor
    let footerTextColor: NSColor
    let footerDimTextColor: NSColor
    let surfaceBackgroundColor: NSColor
    let imageSurfaceBackgroundColor: NSColor
    let surfaceBorderColor: NSColor
    let closeButtonColor: NSColor
}

@MainActor
enum ClipShelfTheme {
    enum Scheme {
        case light
        case dark
    }

    static func applyAppearanceMode(_ mode: String) {
        switch mode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    static func current(for view: NSView?) -> ClipShelfThemePalette {
        current(for: view?.effectiveAppearance)
    }

    static func current(for window: NSWindow?) -> ClipShelfThemePalette {
        current(for: window?.effectiveAppearance)
    }

    static func current(for appearance: NSAppearance?) -> ClipShelfThemePalette {
        let scheme: Scheme = isDark(appearance) ? .dark : .light
        switch scheme {
        case .light:
            return lightPalette
        case .dark:
            return darkPalette
        }
    }

    static func isDark(_ appearance: NSAppearance?) -> Bool {
        let appearance = appearance ?? NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    private static let lightPalette = ClipShelfThemePalette(
        scheme: .light,
        panel: ClipShelfPanelTheme(
            backgroundColor: NSColor.white.withAlphaComponent(0.32),
            toolbarIconColor: NSColor(calibratedWhite: 0.08, alpha: 0.94),
            toolbarTextColor: NSColor(calibratedWhite: 0.08, alpha: 0.94),
            toolbarSelectedBackgroundColor: NSColor.white.withAlphaComponent(0.72),
            toolbarSelectedBorderColor: NSColor.black.withAlphaComponent(0.08),
            toolbarSelectedTextColor: NSColor(calibratedWhite: 0.04, alpha: 0.98),
            resizeHandleColor: NSColor(calibratedWhite: 0.26, alpha: 0.22)
        ),
        card: ClipShelfCardTheme(
            backgroundColor: NSColor(calibratedWhite: 0.98, alpha: 0.98),
            borderColor: NSColor(calibratedWhite: 0.0, alpha: 0.13),
            selectionBorderColor: .systemBlue,
            primaryTextColor: NSColor(calibratedWhite: 0.08, alpha: 0.96),
            secondaryTextColor: NSColor(calibratedWhite: 0.28, alpha: 0.78),
            footerTextColor: NSColor(calibratedWhite: 0.32, alpha: 0.72),
            headerTextColor: NSColor.white.withAlphaComponent(0.96),
            headerSecondaryTextColor: NSColor.white.withAlphaComponent(0.82),
            sourceIconBackgroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.72),
            linkPreviewBackgroundColor: NSColor(calibratedWhite: 0.91, alpha: 0.94),
            appIconTileBackgroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.92)
        ),
        preferences: ClipShelfPreferencesTheme(
            windowBackgroundColor: NSColor(calibratedWhite: 0.93, alpha: 1),
            contentBackgroundColor: NSColor(calibratedWhite: 0.94, alpha: 1),
            sidebarBackgroundColor: NSColor(calibratedWhite: 0.88, alpha: 1),
            borderColor: NSColor(calibratedWhite: 0.0, alpha: 0.16),
            cardBackgroundColor: NSColor(calibratedWhite: 0.985, alpha: 1),
            cardBorderColor: NSColor(calibratedWhite: 0.0, alpha: 0.13),
            navigationSelectedBackgroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.70),
            navigationSelectedTextColor: NSColor(calibratedWhite: 0.08, alpha: 0.92),
            navigationTextColor: NSColor(calibratedWhite: 0.20, alpha: 0.70),
            primaryTextColor: NSColor(calibratedWhite: 0.08, alpha: 0.95),
            secondaryTextColor: NSColor(calibratedWhite: 0.30, alpha: 0.70),
            separatorColor: NSColor(calibratedWhite: 0.0, alpha: 0.16),
            controlBackgroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.92)
        ),
        preview: ClipShelfPreviewTheme(
            backgroundColor: NSColor(calibratedWhite: 0.96, alpha: 0.94),
            borderColor: NSColor(calibratedWhite: 0.0, alpha: 0.16),
            chromeBackgroundColor: NSColor(calibratedWhite: 0.88, alpha: 0.46),
            titleTextColor: NSColor(calibratedWhite: 0.11, alpha: 0.88),
            bodyTextColor: NSColor(calibratedWhite: 0.10, alpha: 0.94),
            footerTextColor: NSColor(calibratedWhite: 0.18, alpha: 0.70),
            footerDimTextColor: NSColor(calibratedWhite: 0.28, alpha: 0.52),
            surfaceBackgroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.72),
            imageSurfaceBackgroundColor: NSColor(calibratedWhite: 0.94, alpha: 0.58),
            surfaceBorderColor: NSColor(calibratedWhite: 0.0, alpha: 0.08),
            closeButtonColor: NSColor(calibratedWhite: 0.16, alpha: 0.55)
        )
    )

    private static let darkPalette = ClipShelfThemePalette(
        scheme: .dark,
        panel: ClipShelfPanelTheme(
            backgroundColor: NSColor.white.withAlphaComponent(0.32),
            toolbarIconColor: NSColor.white.withAlphaComponent(0.72),
            toolbarTextColor: NSColor.white.withAlphaComponent(0.72),
            toolbarSelectedBackgroundColor: NSColor.white.withAlphaComponent(0.18),
            toolbarSelectedBorderColor: NSColor.white.withAlphaComponent(0.10),
            toolbarSelectedTextColor: NSColor.white.withAlphaComponent(0.90),
            resizeHandleColor: NSColor.white.withAlphaComponent(0.18)
        ),
        card: ClipShelfCardTheme(
            backgroundColor: NSColor(calibratedWhite: 0.075, alpha: 0.98),
            borderColor: NSColor.black.withAlphaComponent(0.14),
            selectionBorderColor: .systemBlue,
            primaryTextColor: NSColor.white.withAlphaComponent(0.92),
            secondaryTextColor: NSColor.white.withAlphaComponent(0.58),
            footerTextColor: NSColor.white.withAlphaComponent(0.38),
            headerTextColor: NSColor.white,
            headerSecondaryTextColor: NSColor.white.withAlphaComponent(0.80),
            sourceIconBackgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.66),
            linkPreviewBackgroundColor: NSColor.white.withAlphaComponent(0.08),
            appIconTileBackgroundColor: NSColor.white.withAlphaComponent(0.90)
        ),
        preferences: ClipShelfPreferencesTheme(
            windowBackgroundColor: NSColor(calibratedWhite: 0.16, alpha: 1),
            contentBackgroundColor: NSColor(calibratedWhite: 0.16, alpha: 1),
            sidebarBackgroundColor: NSColor(calibratedWhite: 0.145, alpha: 1),
            borderColor: NSColor(calibratedWhite: 0.30, alpha: 1),
            cardBackgroundColor: NSColor(calibratedWhite: 0.132, alpha: 1),
            cardBorderColor: NSColor(calibratedWhite: 0.28, alpha: 1),
            navigationSelectedBackgroundColor: NSColor(calibratedWhite: 0.34, alpha: 1),
            navigationSelectedTextColor: NSColor.white.withAlphaComponent(0.88),
            navigationTextColor: NSColor.white.withAlphaComponent(0.58),
            primaryTextColor: NSColor.white.withAlphaComponent(0.90),
            secondaryTextColor: NSColor.white.withAlphaComponent(0.62),
            separatorColor: NSColor.separatorColor.withAlphaComponent(0.36),
            controlBackgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.90)
        ),
        preview: ClipShelfPreviewTheme(
            backgroundColor: NSColor(calibratedWhite: 0.07, alpha: 0.84),
            borderColor: NSColor.white.withAlphaComponent(0.13),
            chromeBackgroundColor: NSColor(calibratedWhite: 0.06, alpha: 0.18),
            titleTextColor: NSColor.white.withAlphaComponent(0.82),
            bodyTextColor: NSColor.white.withAlphaComponent(0.93),
            footerTextColor: NSColor.white.withAlphaComponent(0.58),
            footerDimTextColor: NSColor.white.withAlphaComponent(0.48),
            surfaceBackgroundColor: NSColor(calibratedWhite: 0.025, alpha: 0.76),
            imageSurfaceBackgroundColor: NSColor(calibratedWhite: 0.025, alpha: 0.50),
            surfaceBorderColor: NSColor.white.withAlphaComponent(0.045),
            closeButtonColor: NSColor.white.withAlphaComponent(0.62)
        )
    )
}
