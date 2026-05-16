import Testing
@testable import ClipboardPanelApp

struct ClipboardColorValueTests {
    @Test
    func parsesNormalizedHexAndFormatsDerivedValues() throws {
        let color = try #require(ClipboardColorValue(normalizedHex: "#ff00aa"))

        #expect(color.normalizedHex == "#FF00AA")
        #expect(color.red == 255)
        #expect(color.green == 0)
        #expect(color.blue == 170)
        #expect(color.rgbText == "RGB 255, 0, 170")
        #expect(color.hslText == "HSL 320°, 100%, 50%")
        #expect(color.hsbText == "HSB 320°, 100%, 100%")
    }

    @Test
    func rejectsUnsupportedColorSyntax() {
        let rejected = [
            "FF00AA",
            "#FFF",
            "#FF00AAAA",
            "0xFF00AA",
            "rgb(255,0,170)",
            "red",
            "#FF00AG"
        ]

        for value in rejected {
            #expect(ClipboardColorValue(normalizedHex: value) == nil)
        }
    }

    @Test
    func choosesReadableSurfaceForegroundByWcagContrast() throws {
        let cases: [(hex: String, foreground: ClipboardColorSurfaceForegroundStyle)] = [
            ("#FDF6E3", .dark),
            ("#000000", .light),
            ("#FFFFFF", .dark),
            ("#FF00AA", .dark),
            ("#777777", .dark),
            ("#666666", .light)
        ]

        for testCase in cases {
            let color = try #require(ClipboardColorValue(normalizedHex: testCase.hex))
            #expect(color.surfaceForegroundStyle == testCase.foreground)
        }
    }
}
