import ClipboardCoreBridge
import Foundation

public struct RustMetadataURLDecision: Decodable, Sendable {
    public let supported: Bool
    public let privacySensitive: Bool
}

public struct RustMetadataLimits: Decodable, Sendable {
    public let maxHtmlBytes: Int
    public let maxImageBytes: Int
    public let maxIconCandidates: Int
    public let maxPreviewCandidates: Int
    public let pageTimeoutMs: UInt64
    public let imageTimeoutMs: UInt64
    public let maxRedirects: Int
}

public struct RustMetadataHTMLResult: Decodable, Sendable {
    public let title: String?
    public let iconUrls: [String]
    public let previewUrls: [String]
}

/// Shared pure rules; native URLComponents supplies query names, never query values.
public enum RustMetadataPolicy {
    public static func decision(for url: URL) throws -> RustMetadataURLDecision {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw bridgeError("invalid_url")
        }
        let request = URLFacts(scheme: components.scheme, host: components.host,
            queryNames: (components.queryItems ?? []).map(\.name))
        return try decode(metadata_url_policy_json(try encode(request)))
    }

    public static func limits() throws -> RustMetadataLimits {
        try decode(metadata_limits_json(try encode("mac_os_v1")))
    }

    public static func retryAtMs(fetchAttempts: Int64, nowMs: Int64) throws -> Int64 {
        try decode(metadata_retry_at_json(try encode(RetryRequest(fetchAttempts: fetchAttempts, nowMs: nowMs))))
    }

    public static func parse(html: String, baseURL: URL) throws -> RustMetadataHTMLResult {
        try decode(parse_metadata_html_json(try encode(HTMLRequest(html: html,
            baseUrl: baseURL.absoluteString, profile: "mac_os_v1"))))
    }

    private static func encode<T: Encodable>(_ request: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: try encoder.encode(request), as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ response: CoreJSONResult) throws -> T {
        guard response.ok else { throw bridgeError(response.error_code.toString()) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(response.result_json.toString().utf8))
    }

    private static func bridgeError(_ code: String) -> RustCoreError {
        RustCoreError(code: code, messageKey: code, recoverable: true, message: code)
    }

    private struct URLFacts: Encodable { let scheme: String?; let host: String?; let queryNames: [String] }
    private struct RetryRequest: Encodable { let fetchAttempts: Int64; let nowMs: Int64 }
    private struct HTMLRequest: Encodable { let html: String; let baseUrl: String; let profile: String }
}
