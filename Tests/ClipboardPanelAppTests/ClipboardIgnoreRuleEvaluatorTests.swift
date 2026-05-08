import Testing
@testable import ClipboardPanelApp

struct ClipboardIgnoreRuleEvaluatorTests {
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
