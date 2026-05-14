import Foundation

public struct ClipboardDetectedLink: Equatable, Sendable {
    public let originalText: String
    public let canonicalURL: String
    public let displayURL: String
    public let host: String

    public init(
        originalText: String,
        canonicalURL: String,
        displayURL: String,
        host: String
    ) {
        self.originalText = originalText
        self.canonicalURL = canonicalURL
        self.displayURL = displayURL
        self.host = host
    }
}

public struct ClipboardLinkDetector: Sendable {
    private enum Limits {
        static let maximumLength = 2_048
    }

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    public init() {}

    public func detectPureLink(in text: String) -> ClipboardDetectedLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAcceptableCandidate(trimmed),
              trimmed.contains("://")
        else { return nil }

        if let detectedURL = detectSystemURL(in: trimmed),
           let normalized = normalize(url: detectedURL, originalText: trimmed) {
            return normalized
        }

        return nil
    }

    private func detectSystemURL(in text: String) -> URL? {
        guard let detector = Self.detector else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              match.resultType == .link,
              match.range.location == 0,
              match.range.length == range.length
        else {
            return nil
        }

        return match.url
    }

    private func normalize(url: URL, originalText: String) -> ClipboardDetectedLink? {
        let resolvedURL = url.scheme == nil ? URL(string: "https://\(url.absoluteString)") : url
        guard let resolvedURL,
              let components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty
        else {
            return nil
        }

        var normalizedComponents = components
        normalizedComponents.scheme = scheme
        normalizedComponents.host = host.lowercased()
        normalizedComponents.fragment = components.fragment

        guard let canonicalURL = normalizedComponents.string,
              canonicalURL.lowercased().hasPrefix("\(scheme)://")
        else {
            return nil
        }

        return ClipboardDetectedLink(
            originalText: originalText,
            canonicalURL: canonicalURL,
            displayURL: canonicalURL,
            host: host.lowercased()
        )
    }

    private func isAcceptableCandidate(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= Limits.maximumLength else { return false }
        return !text.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control && scalar != "\n" && scalar != "\t"
        }
    }
}
