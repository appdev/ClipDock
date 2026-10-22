import Testing
@testable import ClipboardPanelApp

struct ClipboardIgnoreRuleEvaluatorTests {
    @Test
    func preservesCanonicalEqualityAndFirstRuleIndex() {
        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: .init(appName: "CAFÉ"),
            preferences: .init(ignoredAppIdentifiers: ["", "  cafe\u{301}  ", "café"]))
        #expect(decision.reason == .sourceApplication)
        #expect(decision.matchedRule == "cafe\u{301}")
    }

    @Test
    func preservesFoundationTitleMatchingAndApplicationPriority() {
        let titleOnly = ClipboardIgnoreRuleEvaluator.decision(
            for: .init(appName: "Browser"), windowTitle: "CAFÉ Password",
            preferences: .init(ignoredAppIdentifiers: [], windowTitleKeywords: ["", "cafe", "password"]))
        #expect(titleOnly.reason == .windowTitle)
        #expect(titleOnly.matchedRule == "cafe")
        let application = ClipboardIgnoreRuleEvaluator.decision(
            for: .init(appName: "Browser"), windowTitle: "CAFÉ Password",
            preferences: .init(ignoredAppIdentifiers: ["Browser"], windowTitleKeywords: ["cafe"]))
        #expect(application.reason == .sourceApplication)
    }

    @Test
    func invalidPolicyEvidenceFailsClosed() {
        let result = RustCapturePolicyBridge.evaluate(.init(profile: "mac_os_v1",
            sourceCandidateKeys: ["browser"], applicationRuleKeys: [], skipUnknownSource: false,
            sourceConfidence: "high", hasOwner: false, titleMatchIndex: 1, titleRuleCount: 1))
        let decision = ClipboardIgnoreRuleEvaluator.resolvePolicyDecision(result, preferences: .init())
        #expect(decision.shouldSkip)
        #expect(decision.reason == .evaluationFailed)
        let malformed = ClipboardIgnoreRuleEvaluator.resolvePolicyDecision(
            .success(.init(skip: true, reason: "source_application", matchedRuleIndex: 9)),
            preferences: .init(ignoredAppIdentifiers: ["Browser"]))
        #expect(malformed.shouldSkip)
        #expect(malformed.reason == .evaluationFailed)
    }

    @Test
    func skipsByBundleIdentifier() {
        let preferences = RustIgnoreListPreferences(
            ignoredAppIdentifiers: ["com.apple.Terminal"]
        )
        let source = ClipboardIgnoreRuleSource(
            bundleId: "com.apple.terminal",
            appName: "Terminal",
            bundlePath: "/System/Applications/Utilities/Terminal.app"
        )

        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: source,
            preferences: preferences
        )

        #expect(decision.shouldSkip)
        #expect(decision.reason == .sourceApplication)
        #expect(decision.matchedRule == "com.apple.Terminal")
    }

    @Test
    func skipsByApplicationNameOrBundlePathComponent() {
        let preferences = RustIgnoreListPreferences(
            ignoredAppIdentifiers: ["keychain access", "Terminal.app"]
        )
        let source = ClipboardIgnoreRuleSource(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            bundlePath: "/System/Applications/Utilities/Terminal.app"
        )

        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: source,
            preferences: preferences
        )

        #expect(decision.shouldSkip)
        #expect(decision.reason == .sourceApplication)
        #expect(decision.matchedRule == "Terminal.app")
    }

    @Test
    func skipsUnknownSourceWhenEnabled() {
        let preferences = RustIgnoreListPreferences(skipUnknownSource: true)

        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: nil,
            preferences: preferences
        )

        #expect(decision.shouldSkip)
        #expect(decision.reason == .unknownSource)
    }

    @Test
    func skipsByWindowTitleKeywordWhenTitleIsProvided() {
        let preferences = RustIgnoreListPreferences(
            windowTitleKeywords: ["验证码", "密码"]
        )

        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: ClipboardIgnoreRuleSource(appName: "Safari"),
            windowTitle: "登录验证码 - Safari",
            preferences: preferences
        )

        #expect(decision.shouldSkip)
        #expect(decision.reason == .windowTitle)
        #expect(decision.matchedRule == "验证码")
    }

    @Test
    func doesNotSkipByWindowTitleKeywordWithoutCollectedTitle() {
        let preferences = RustIgnoreListPreferences(
            windowTitleKeywords: ["验证码", "密码"]
        )

        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: ClipboardIgnoreRuleSource(appName: "Safari"),
            windowTitle: nil,
            preferences: preferences
        )

        #expect(!decision.shouldSkip)
        #expect(decision.reason == nil)
    }

    @Test
    func capturesWhenNoRuleMatches() {
        let preferences = RustIgnoreListPreferences(
            ignoredAppIdentifiers: ["com.apple.Terminal"],
            windowTitleKeywords: ["密码"],
            skipUnknownSource: true
        )

        let decision = ClipboardIgnoreRuleEvaluator.decision(
            for: ClipboardIgnoreRuleSource(
                bundleId: "com.apple.TextEdit",
                appName: "TextEdit",
                bundlePath: "/System/Applications/TextEdit.app"
            ),
            windowTitle: "Untitled",
            preferences: preferences
        )

        #expect(!decision.shouldSkip)
        #expect(decision.reason == nil)
    }
}
