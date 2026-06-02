import Foundation

public enum LinkDisplayURLFormatter {
    private enum Limits {
        static let queryCharacters = 80
    }

    public static func displayURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed).flatMap(displayURL(from:))
    }

    public static func displayURL(from url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        let displayHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var display = displayHost
        if shouldShowScheme(scheme: scheme, port: components.port) {
            display = "\(scheme)://\(display)"
        }
        if let port = components.port {
            display += ":\(port)"
        }

        let path = components.percentEncodedPath
        if !path.isEmpty, path != "/" {
            display += path
        }

        if let query = components.percentEncodedQuery, !query.isEmpty {
            display += "?\(middleTruncated(query, limit: Limits.queryCharacters))"
        }

        return display
    }

    private static func shouldShowScheme(scheme: String, port: Int?) -> Bool {
        if scheme == "http" {
            return true
        }
        guard let port else { return false }
        return port != 443
    }

    private static func middleTruncated(_ value: String, limit: Int) -> String {
        guard value.count > limit, limit > 1 else { return value }
        let headCount = max(1, (limit - 1) / 2)
        let tailCount = max(1, limit - 1 - headCount)
        let head = value.prefix(headCount)
        let tail = value.suffix(tailCount)
        return "\(head)…\(tail)"
    }
}
