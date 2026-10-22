import ClipboardCoreBridge
import Foundation

struct RustCapturePolicyInput: Encodable, Sendable {
    let profile: String
    let sourceCandidateKeys: [String]
    let applicationRuleKeys: [String]
    let skipUnknownSource: Bool
    let sourceConfidence: String
    let hasOwner: Bool
    let titleMatchIndex: Int?
    let titleRuleCount: Int

    private enum CodingKeys: String, CodingKey {
        case profile
        case sourceCandidateKeys = "source_candidate_keys"
        case applicationRuleKeys = "application_rule_keys"
        case skipUnknownSource = "skip_unknown_source"
        case sourceConfidence = "source_confidence"
        case hasOwner = "has_owner"
        case titleMatchIndex = "title_match_index"
        case titleRuleCount = "title_rule_count"
    }
}

struct RustCapturePolicyDecision: Decodable, Sendable {
    let skip: Bool
    let reason: String?
    let matchedRuleIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case skip, reason
        case matchedRuleIndex = "matched_rule_index"
    }
}

enum RustCapturePolicyBridge {
    /// Pure FFI: capture privacy checks never open storage or acquire its session.
    static func evaluate(_ input: RustCapturePolicyInput) -> Result<RustCapturePolicyDecision, RustCoreError> {
        let json: String
        do { json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self) }
        catch { return .failure(Self.error(code: "bridge_encode_failed")) }
        let result = evaluate_capture_policy_json(json)
        guard result.ok else {
            return .failure(RustCoreError(code: result.error_code.toString(),
                messageKey: result.message_key.toString(), recoverable: true,
                message: "Capture policy could not be evaluated"))
        }
        do {
            return .success(try JSONDecoder().decode(RustCapturePolicyDecision.self,
                from: Data(result.result_json.toString().utf8)))
        } catch { return .failure(Self.error(code: "bridge_decode_failed")) }
    }

    private static func error(code: String) -> RustCoreError {
        RustCoreError(code: code, messageKey: "clipboard.error.\(code)",
            recoverable: true, message: "Capture policy could not be evaluated")
    }
}
