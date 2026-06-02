import Foundation

public struct ClipboardIgnoreRuleSource: Equatable, Sendable {
    public var bundleId: String?
    public var appName: String?
    public var bundlePath: String?

    public init(bundleId: String? = nil, appName: String? = nil, bundlePath: String? = nil) {
        self.bundleId = bundleId
        self.appName = appName
        self.bundlePath = bundlePath
    }
}

public enum ClipboardIgnoreRuleReason: String, Equatable, Sendable {
    case unknownSource = "unknown_source"
    case sourceApplication = "source_application"
    case windowTitle = "window_title"
}

public struct ClipboardIgnoreRuleDecision: Equatable, Sendable {
    public let shouldSkip: Bool
    public let reason: ClipboardIgnoreRuleReason?
    public let matchedRule: String?

    public static let capture = ClipboardIgnoreRuleDecision(
        shouldSkip: false,
        reason: nil,
        matchedRule: nil
    )

    public init(
        shouldSkip: Bool,
        reason: ClipboardIgnoreRuleReason?,
        matchedRule: String?
    ) {
        self.shouldSkip = shouldSkip
        self.reason = reason
        self.matchedRule = matchedRule
    }
}

public enum ClipboardIgnoreRuleEvaluator {
    public static func decision(
        for source: ClipboardIgnoreRuleSource?,
        windowTitle: String? = nil,
        preferences: RustIgnoreListPreferences
    ) -> ClipboardIgnoreRuleDecision {
        let sourceCandidates = normalizedSourceCandidates(source)

        if preferences.skipUnknownSource, sourceCandidates.isEmpty {
            return ClipboardIgnoreRuleDecision(
                shouldSkip: true,
                reason: .unknownSource,
                matchedRule: nil
            )
        }

        if let matchedIdentifier = firstMatchedAppIdentifier(
            rules: preferences.ignoredAppIdentifiers,
            sourceCandidates: sourceCandidates
        ) {
            return ClipboardIgnoreRuleDecision(
                shouldSkip: true,
                reason: .sourceApplication,
                matchedRule: matchedIdentifier
            )
        }

        if let matchedKeyword = firstMatchedWindowTitleKeyword(
            rules: preferences.windowTitleKeywords,
            windowTitle: windowTitle
        ) {
            return ClipboardIgnoreRuleDecision(
                shouldSkip: true,
                reason: .windowTitle,
                matchedRule: matchedKeyword
            )
        }

        return .capture
    }

    private static func firstMatchedAppIdentifier(
        rules: [String],
        sourceCandidates: Set<String>
    ) -> String? {
        rules.first { rule in
            let normalizedRule = normalized(rule)
            return !normalizedRule.isEmpty && sourceCandidates.contains(normalizedRule)
        }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatchedWindowTitleKeyword(
        rules: [String],
        windowTitle: String?
    ) -> String? {
        let normalizedTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedTitle.isEmpty else {
            return nil
        }

        return rules.first { rule in
            let normalizedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedRule.isEmpty else {
                return false
            }

            return normalizedTitle.range(
                of: normalizedRule,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: .current
            ) != nil
        }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedSourceCandidates(_ source: ClipboardIgnoreRuleSource?) -> Set<String> {
        guard let source else {
            return []
        }

        var candidates = Set<String>()
        appendCandidate(source.bundleId, to: &candidates)
        appendCandidate(source.appName, to: &candidates)

        if let bundlePath = source.bundlePath {
            appendCandidate(bundlePath, to: &candidates)

            let url = URL(fileURLWithPath: bundlePath)
            appendCandidate(url.lastPathComponent, to: &candidates)
            appendCandidate(url.deletingPathExtension().lastPathComponent, to: &candidates)
        }

        return candidates
    }

    private static func appendCandidate(_ value: String?, to candidates: inout Set<String>) {
        let normalizedValue = normalized(value)
        if !normalizedValue.isEmpty {
            candidates.insert(normalizedValue)
        }
    }

    private static func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""
    }
}
