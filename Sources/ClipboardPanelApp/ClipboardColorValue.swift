import Foundation

public struct ClipboardColorValue: Equatable, Sendable {
    public let normalizedHex: String
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init?(normalizedHex text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 7, value.first == "#" else { return nil }

        let hexStart = value.index(after: value.startIndex)
        let hex = String(value[hexStart...])
        guard hex.count == 6,
              hex.utf8.allSatisfy({ $0.isASCIIHexDigit }),
              let rawValue = UInt32(hex, radix: 16)
        else {
            return nil
        }

        self.normalizedHex = "#\(hex.uppercased())"
        self.red = UInt8((rawValue >> 16) & 0xFF)
        self.green = UInt8((rawValue >> 8) & 0xFF)
        self.blue = UInt8(rawValue & 0xFF)
    }

    public var rgbText: String {
        "RGB \(red), \(green), \(blue)"
    }

    public var hslText: String {
        let hsl = hslComponents()
        return "HSL \(hsl.hue)°, \(hsl.saturation)%, \(hsl.lightness)%"
    }

    public var hsbText: String {
        let hsb = hsbComponents()
        return "HSB \(hsb.hue)°, \(hsb.saturation)%, \(hsb.brightness)%"
    }

    public var previewMetadataText: String {
        [normalizedHex, rgbText, hslText, hsbText].joined(separator: " · ")
    }

    public var surfaceForegroundStyle: ClipboardColorSurfaceForegroundStyle {
        let luminance = relativeLuminance()
        let contrastWithBlack = (luminance + 0.05) / 0.05
        let contrastWithWhite = 1.05 / (luminance + 0.05)
        return contrastWithWhite >= contrastWithBlack ? .light : .dark
    }

    private func hsbComponents() -> (hue: Int, saturation: Int, brightness: Int) {
        let red = Double(red) / 255
        let green = Double(green) / 255
        let blue = Double(blue) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        let hue = hueDegrees(red: red, green: green, blue: blue, maximum: maximum, delta: delta)
        let saturation = maximum == 0 ? 0 : delta / maximum
        return (
            hue: roundedPercent(hue),
            saturation: roundedPercent(saturation * 100),
            brightness: roundedPercent(maximum * 100)
        )
    }

    private func hslComponents() -> (hue: Int, saturation: Int, lightness: Int) {
        let red = Double(red) / 255
        let green = Double(green) / 255
        let blue = Double(blue) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2

        let hue = hueDegrees(red: red, green: green, blue: blue, maximum: maximum, delta: delta)
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        return (
            hue: roundedPercent(hue),
            saturation: roundedPercent(saturation * 100),
            lightness: roundedPercent(lightness * 100)
        )
    }

    private func hueDegrees(
        red: Double,
        green: Double,
        blue: Double,
        maximum: Double,
        delta: Double
    ) -> Double {
        guard delta != 0 else { return 0 }

        let hue: Double
        if maximum == red {
            hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
        } else if maximum == green {
            hue = 60 * (((blue - red) / delta) + 2)
        } else {
            hue = 60 * (((red - green) / delta) + 4)
        }

        return hue < 0 ? hue + 360 : hue
    }

    private func roundedPercent(_ value: Double) -> Int {
        Int(value.rounded())
    }

    private func relativeLuminance() -> Double {
        let components = [red, green, blue].map { component in
            let normalized = Double(component) / 255
            if normalized <= 0.03928 {
                return normalized / 12.92
            }
            return pow((normalized + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}

public enum ClipboardColorSurfaceForegroundStyle: Equatable, Sendable {
    case light
    case dark
}

private extension UInt8 {
    var isASCIIHexDigit: Bool {
        (48...57).contains(self)
            || (65...70).contains(self)
            || (97...102).contains(self)
    }
}
