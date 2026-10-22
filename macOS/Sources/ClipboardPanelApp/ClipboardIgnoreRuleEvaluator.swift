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
    case evaluationFailed = "evaluation_failed"
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
        let input = RustCapturePolicyInput(
            profile: "mac_os_v1", sourceCandidateKeys: Array(normalizedSourceCandidates(source)),
            applicationRuleKeys: preferences.ignoredAppIdentifiers.map { normalized($0) },
            skipUnknownSource: preferences.skipUnknownSource,
            sourceConfidence: source == nil ? "unknown" : "high",
            hasOwner: false, // Foreground-app inference is not a clipboard-owner guarantee.
            titleMatchIndex: firstMatchedWindowTitleIndex(rules: preferences.windowTitleKeywords, windowTitle: windowTitle),
            titleRuleCount: preferences.windowTitleKeywords.count
        )
        return resolvePolicyDecision(RustCapturePolicyBridge.evaluate(input), preferences: preferences)
    }

    static func resolvePolicyDecision(
        _ result: Result<RustCapturePolicyDecision, RustCoreError>,
        preferences: RustIgnoreListPreferences
    ) -> ClipboardIgnoreRuleDecision {
        guard case .success(let decision) = result else {
            return .init(shouldSkip: true, reason: .evaluationFailed, matchedRule: nil)
        }
        guard decision.skip else { return .capture }
        let reason = decision.reason.flatMap(ClipboardIgnoreRuleReason.init(rawValue:))
        let rules: [String]
        switch reason {
        case .unknownSource:
            return .init(shouldSkip: true, reason: .unknownSource, matchedRule: nil)
        case .sourceApplication: rules = preferences.ignoredAppIdentifiers
        case .windowTitle: rules = preferences.windowTitleKeywords
        default: return .init(shouldSkip: true, reason: .evaluationFailed, matchedRule: nil)
        }
        guard let index = decision.matchedRuleIndex, rules.indices.contains(index) else {
            return .init(shouldSkip: true, reason: .evaluationFailed, matchedRule: nil)
        }
        return .init(shouldSkip: true, reason: reason,
            matchedRule: rules[index].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func firstMatchedWindowTitleIndex(
        rules: [String],
        windowTitle: String?
    ) -> Int? {
        let normalizedTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedTitle.isEmpty else {
            return nil
        }

        return rules.firstIndex { rule in
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
        }
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
            .precomposedStringWithCanonicalMapping
            ?? ""
    }
}
