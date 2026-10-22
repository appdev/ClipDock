import ClipboardCoreBridge
import Foundation

public struct RustAssetReservation: Codable, Equatable, Sendable {
    public let reservationID: String
    public let relativePath: String
    public let stagedRelativePath: String
    public let byteCount: Int64
    public let contentHash: String?

    private enum CodingKeys: String, CodingKey {
        case reservationID = "reservation_id"
        case relativePath = "relative_path"
        case stagedRelativePath = "staged_relative_path"
        case byteCount = "byte_count"
        case contentHash = "content_hash"
    }
}

/// A receipt's native lease protects publication until Rust registers or
/// abandons its paths. No root or database lock is held between these calls.
public struct RustAssetStore: Sendable {
    public static let maximumPixels = 64 * 1024 * 1024
    public static let maximumEncodedBytes = 256 * 1024 * 1024
    public static let maximumThumbnailBytes = 16 * 1024 * 1024
    public static let maximumWebPDimension = 16_383
    public let appSupportDirectory: URL

    public init(appSupportDirectory: URL) { self.appSupportDirectory = appSupportDirectory }

    public func reserve(relativePath: String, stagedRelativePath: String? = nil) -> Result<RustAssetReservation, RustCoreError> {
        decode(reserve_asset(appSupportDirectory.path, relativePath, stagedRelativePath ?? ""))
    }

    public func reserveExisting(relativePath: String) -> Result<RustAssetReservation, RustCoreError> {
        decode(reserve_existing_asset(appSupportDirectory.path, relativePath))
    }

    public func stage(data: Data, reservation: RustAssetReservation) -> Result<RustAssetReservation, RustCoreError> {
        encode(reservation).flatMap { json in
            data.withUnsafeBytes { raw in
                decode(stage_reserved_asset(appSupportDirectory.path, json,
                    raw.bindMemory(to: UInt8.self)))
            }
        }
    }

    public func publish(reservation: RustAssetReservation) -> Result<RustAssetReservation, RustCoreError> {
        encode(reservation).flatMap { decode(publish_reserved_asset(appSupportDirectory.path, $0)) }
    }

    public func write(data: Data, relativePath: String) -> Result<RustAssetReservation, RustCoreError> {
        let reservation: RustAssetReservation
        switch reserve(relativePath: relativePath) {
        case .success(let value): reservation = value
        case .failure(let error): return .failure(error)
        }
        let result = stage(data: data, reservation: reservation).flatMap { publish(reservation: $0) }
        if case .failure = result { _ = cleanupUncommitted(relativePaths: [relativePath]) }
        return result
    }

    public func encodeLosslessToStaging(
        rgbaData: Data, width: Int, height: Int, reservation: RustAssetReservation,
        maximumBytes: Int = Self.maximumEncodedBytes
    ) -> Result<RustAssetReservation, RustCoreError> {
        guard Self.acceptsLosslessDimensions(width: width, height: height),
              rgbaData.count == width * height * 4,
              maximumBytes > 0, maximumBytes <= Self.maximumEncodedBytes else {
            return .failure(Self.error("invalid_input"))
        }
        return encode(reservation).flatMap { json in
            rgbaData.withUnsafeBytes { raw in
                decode(encode_lossless_webp_to_staging(appSupportDirectory.path, json,
                    raw.bindMemory(to: UInt8.self), Int64(width), Int64(height), Int64(maximumBytes)))
            }
        }
    }

    public static func acceptsLosslessDimensions(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, width <= maximumWebPDimension, height <= maximumWebPDimension else { return false }
        let pixels = width.multipliedReportingOverflow(by: height)
        return !pixels.overflow && pixels.partialValue <= maximumPixels
    }

    @discardableResult
    public func cleanupUncommitted(relativePaths: [String]) -> Result<RustItemManagementResult, RustCoreError> {
        let result: Result<CleanupResponse, RustCoreError> = encode(relativePaths).flatMap {
            decode(cleanup_uncommitted_assets(appSupportDirectory.path, $0))
        }
        return result.map { RustItemManagementResult(affectedCount: $0.affectedCount) }
    }

    private struct CleanupResponse: Decodable {
        let affectedCount: Int64
        enum CodingKeys: String, CodingKey { case affectedCount = "affected_count" }
    }

    private func encode<T: Encodable>(_ value: T) -> Result<String, RustCoreError> {
        do { return .success(String(decoding: try JSONEncoder().encode(value), as: UTF8.self)) }
        catch { return .failure(Self.error("bridge_encode_failed")) }
    }

    private func decode<T: Decodable>(_ result: CoreJSONResult) -> Result<T, RustCoreError> {
        guard result.ok else {
            return .failure(RustCoreError(code: result.error_code.toString(),
                messageKey: result.message_key.toString(), recoverable: true,
                message: "Managed asset operation failed"))
        }
        do { return .success(try JSONDecoder().decode(T.self, from: Data(result.result_json.toString().utf8))) }
        catch { return .failure(Self.error("bridge_decode_failed")) }
    }

    private static func error(_ code: String) -> RustCoreError {
        RustCoreError(code: code, messageKey: "clipboard.error.\(code)", recoverable: true,
            message: "Managed asset operation failed")
    }
}
