import Foundation

/// Facts and policy are captured once, before reading the business payload.
/// They remain unchanged while asynchronous asset work is queued.
public struct ClipboardCaptureEventContext: Equatable, Sendable {
    public let changeCount: Int
    public let preferences: RustPreferencesDocument
    public let source: ClipboardCaptureSource?
    public let decision: ClipboardIgnoreRuleDecision

    public init(changeCount: Int, preferences: RustPreferencesDocument,
                source: ClipboardCaptureSource?, decision: ClipboardIgnoreRuleDecision) {
        self.changeCount = changeCount
        self.preferences = preferences
        self.source = source
        self.decision = decision
    }
}
