import Foundation

public protocol SyncServerHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: SyncServerHTTPClient {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

public enum SyncServerClientError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int, String)
    case missingToken
}

public struct SyncCreateResult: Equatable, Sendable {
    public let syncID: String
    public let pairingCode: String
    public let pairingExpiresAtMs: Int64
    public let deviceID: String
    public let token: String
}

public struct SyncJoinResult: Equatable, Sendable {
    public let syncID: String
    public let deviceID: String
    public let token: String
}

public struct SyncInviteResult: Equatable, Sendable {
    public let syncID: String
    public let pairingCode: String
    public let pairingExpiresAtMs: Int64
}

public struct SyncInfoResult: Equatable, Sendable {
    public let syncID: String
    public let deviceID: String
    public let deviceName: String
    public let p2pEnabled: Bool
    public let p2pTransport: String
}

public struct SyncEndpointReportResult: Equatable, Sendable {
    public let deviceID: String
    public let endpointID: String
    public let expiresAtMs: Int64
}

public struct SyncP2PDeviceResult: Equatable, Sendable {
    public let deviceID: String
    public let deviceName: String
    public let endpointID: String
    public let relayURL: String?
    public let directAddresses: [String]
}

public struct SyncP2PAssetProviderResult: Equatable, Sendable {
    public let deviceID: String
    public let deviceName: String
    public let kind: String
    public let byteCount: Int64?
    public let mimeType: String?
    public let availability: String
    public let blobTicket: String?
    public let endpointID: String?
    public let relayURL: String?
    public let directAddresses: [String]
}

public struct SyncP2PAssetProvidersResult: Equatable, Sendable {
    public let assetID: String
    public let providers: [SyncP2PAssetProviderResult]
}

public struct SyncP2PDeleteProviderResult: Equatable, Sendable {
    public let assetID: String
    public let removed: Bool
}

public struct SyncUploadedAssetResult: Equatable, Sendable {
    public let digest: String
    public let kind: String
    public let mimeType: String
    public let sizeBytes: Int64
    public let width: Int64
    public let height: Int64
    public let alreadyExists: Bool
}

public struct SyncPushEvent: Equatable, Encodable, Sendable {
    public let clientEventId: String
    public let eventType: String
    public let contentHash: String
    public let itemType: String?
    public let payload: [String: SyncEventPayloadValue]?
    public let copyCountDelta: Int64?

    public init(
        clientEventId: String,
        eventType: String,
        contentHash: String,
        itemType: String?,
        payload: [String: SyncEventPayloadValue]?,
        copyCountDelta: Int64?
    ) {
        self.clientEventId = clientEventId
        self.eventType = eventType
        self.contentHash = contentHash
        self.itemType = itemType
        self.payload = payload
        self.copyCountDelta = copyCountDelta
    }

    private enum CodingKeys: String, CodingKey {
        case clientEventId = "client_event_id"
        case eventType = "type"
        case contentHash = "content_hash"
        case itemType = "item_type"
        case payload
        case copyCountDelta = "copy_count_delta"
    }
}

public struct SyncPushedEventResult: Equatable, Sendable {
    public let clientEventId: String
    public let serverSeq: Int64
    public let duplicate: Bool
}

public struct SyncPushEventsResult: Equatable, Sendable {
    public let events: [SyncPushedEventResult]
    public let nextCursor: Int64
}

public struct SyncPulledEventRecord: Equatable, Decodable, Sendable {
    public let serverSeq: Int64
    public let deviceID: String
    public let clientEventID: String
    public let eventType: String
    public let contentHash: String
    public let itemType: String?
    public let payload: [String: SyncEventPayloadValue]?
    public let copyCountDelta: Int64?
    public let createdAtMs: Int64

    private enum CodingKeys: String, CodingKey {
        case serverSeq = "server_seq"
        case deviceID = "device_id"
        case clientEventID = "client_event_id"
        case eventType = "type"
        case contentHash = "content_hash"
        case itemType = "item_type"
        case payload
        case copyCountDelta = "copy_count_delta"
        case createdAtMs = "created_at_ms"
    }

    public func rustRecord() -> RustSyncEventRecord {
        RustSyncEventRecord(
            serverSeq: serverSeq,
            deviceID: deviceID,
            clientEventID: clientEventID,
            eventType: eventType,
            contentHash: contentHash,
            itemType: itemType,
            payload: payload,
            copyCountDelta: copyCountDelta,
            createdAtMs: createdAtMs
        )
    }
}

public struct SyncPullEventsResult: Equatable, Sendable {
    public let events: [SyncPulledEventRecord]
    public let nextCursor: Int64
}

public struct SyncSnapshotItemRecord: Equatable, Decodable, Sendable {
    public let contentHash: String
    public let itemType: String
    public let payload: [String: SyncEventPayloadValue]
    public let copyCount: Int64
    public let updatedAtMs: Int64
    public let lastServerSeq: Int64

    private enum CodingKeys: String, CodingKey {
        case contentHash = "content_hash"
        case itemType = "item_type"
        case payload
        case copyCount = "copy_count"
        case updatedAtMs = "updated_at_ms"
        case lastServerSeq = "last_server_seq"
    }

    public func rustRecord() -> RustSyncSnapshotItemRecord {
        RustSyncSnapshotItemRecord(
            contentHash: contentHash,
            itemType: itemType,
            payload: payload,
            copyCount: copyCount,
            updatedAtMs: updatedAtMs,
            lastServerSeq: lastServerSeq
        )
    }
}

public struct SyncSnapshotTombstoneRecord: Equatable, Decodable, Sendable {
    public let contentHash: String
    public let deletedAtMs: Int64
    public let lastServerSeq: Int64

    private enum CodingKeys: String, CodingKey {
        case contentHash = "content_hash"
        case deletedAtMs = "deleted_at_ms"
        case lastServerSeq = "last_server_seq"
    }

    public func rustRecord() -> RustSyncSnapshotTombstoneRecord {
        RustSyncSnapshotTombstoneRecord(
            contentHash: contentHash,
            deletedAtMs: deletedAtMs,
            lastServerSeq: lastServerSeq
        )
    }
}

public struct SyncSnapshotResult: Equatable, Sendable {
    public let snapshotSeq: Int64
    public let items: [SyncSnapshotItemRecord]
    public let tombstones: [SyncSnapshotTombstoneRecord]
}

public struct SyncServerClient: Sendable {
    private let httpClient: SyncServerHTTPClient

    public init(httpClient: SyncServerHTTPClient = URLSession.shared) {
        self.httpClient = httpClient
    }

    public func createSync(
        serverURL: String,
        deviceName: String
    ) async throws -> SyncCreateResult {
        let response: SuccessEnvelope<CreateSyncResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/sync/create",
            method: "POST",
            token: nil,
            body: DeviceNameRequest(deviceName: deviceName)
        )
        return SyncCreateResult(
            syncID: response.data.syncID,
            pairingCode: response.data.pairingCode,
            pairingExpiresAtMs: response.data.pairingExpiresAtMs,
            deviceID: response.data.deviceID,
            token: response.data.token
        )
    }

    public func joinSync(
        serverURL: String,
        pairingCode: String,
        deviceName: String
    ) async throws -> SyncJoinResult {
        let response: SuccessEnvelope<JoinSyncResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/sync/join",
            method: "POST",
            token: nil,
            body: JoinSyncRequest(pairingCode: pairingCode, deviceName: deviceName)
        )
        return SyncJoinResult(
            syncID: response.data.syncID,
            deviceID: response.data.deviceID,
            token: response.data.token
        )
    }

    public func createInvite(
        serverURL: String,
        token: String
    ) async throws -> SyncInviteResult {
        let response: SuccessEnvelope<CreateInviteResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/sync/invites",
            method: "POST",
            token: token,
            body: EmptyBody?.none
        )
        return SyncInviteResult(
            syncID: response.data.syncID,
            pairingCode: response.data.pairingCode,
            pairingExpiresAtMs: response.data.pairingExpiresAtMs
        )
    }

    public func info(
        serverURL: String,
        token: String
    ) async throws -> SyncInfoResult {
        let response: SuccessEnvelope<InfoResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/info",
            method: "GET",
            token: token,
            body: EmptyBody?.none
        )
        return SyncInfoResult(
            syncID: response.data.syncID,
            deviceID: response.data.deviceID,
            deviceName: response.data.deviceName,
            p2pEnabled: response.data.p2p.enabled,
            p2pTransport: response.data.p2p.transport
        )
    }

    public func reportEndpoint(
        serverURL: String,
        token: String,
        endpointID: String,
        relayURL: String? = nil,
        directAddresses: [String] = [],
        pathType: String = "unknown",
        rttMs: Int64? = nil
    ) async throws -> SyncEndpointReportResult {
        var quality: [String: SyncJSONValue] = [
            "path_type": .string(pathType)
        ]
        if let rttMs {
            quality["rtt_ms"] = .int(rttMs)
        }
        let response: SuccessEnvelope<EndpointReportResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/p2p/endpoint",
            method: "PUT",
            token: token,
            body: EndpointReportRequest(
                endpointID: endpointID,
                relayURL: relayURL,
                directAddresses: directAddresses,
                capabilities: [
                    "transport": .string("iroh-blobs"),
                    "blob_transfer": .bool(true),
                    "macos_client": .bool(true)
                ],
                quality: quality
            )
        )
        return SyncEndpointReportResult(
            deviceID: response.data.deviceID,
            endpointID: response.data.endpoint.endpointID,
            expiresAtMs: response.data.endpoint.expiresAtMs
        )
    }

    public func listP2PDevices(
        serverURL: String,
        token: String
    ) async throws -> [SyncP2PDeviceResult] {
        let response: SuccessEnvelope<ListDevicesResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/p2p/devices",
            method: "GET",
            token: token,
            body: EmptyBody?.none
        )
        return response.data.devices.map { device in
            SyncP2PDeviceResult(
                deviceID: device.deviceID,
                deviceName: device.deviceName,
                endpointID: device.endpoint.endpointID,
                relayURL: device.endpoint.relayURL,
                directAddresses: device.endpoint.directAddresses
            )
        }
    }

    public func upsertAssetProvider(
        serverURL: String,
        token: String,
        assetID: String,
        kind: String,
        byteCount: Int64?,
        mimeType: String?,
        blobTicket: String,
        availability: String = "online"
    ) async throws -> SyncP2PAssetProviderResult {
        let response: SuccessEnvelope<UpsertAssetProviderResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/p2p/assets/\(assetID)/providers/me",
            method: "PUT",
            token: token,
            body: UpsertAssetProviderRequest(
                kind: kind,
                byteCount: byteCount,
                mimeType: mimeType,
                availability: availability,
                quality: [
                    "transport": .string("iroh-blobs"),
                    "blob_ticket": .string(blobTicket)
                ]
            )
        )
        return response.data.provider.asResult()
    }

    public func deleteAssetProvider(
        serverURL: String,
        token: String,
        assetID: String
    ) async throws -> SyncP2PDeleteProviderResult {
        let response: SuccessEnvelope<DeleteAssetProviderResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/p2p/assets/\(assetID)/providers/me",
            method: "DELETE",
            token: token,
            body: EmptyBody?.none
        )
        return SyncP2PDeleteProviderResult(
            assetID: response.data.assetID,
            removed: response.data.removed
        )
    }

    public func listAssetProviders(
        serverURL: String,
        token: String,
        assetID: String
    ) async throws -> SyncP2PAssetProvidersResult {
        let response: SuccessEnvelope<ListAssetProvidersResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/p2p/assets/\(assetID)/providers",
            method: "GET",
            token: token,
            body: EmptyBody?.none
        )
        return SyncP2PAssetProvidersResult(
            assetID: response.data.assetID,
            providers: response.data.providers.map { $0.asResult() }
        )
    }

    public func uploadAsset(
        serverURL: String,
        token: String,
        digest: String,
        kind: String,
        mimeType: String,
        width: Int,
        height: Int,
        bytes: Data
    ) async throws -> SyncUploadedAssetResult {
        let baseURL = try normalizedBaseURL(serverURL)
        let pathURL = baseURL.appendingPathComponent("v2/assets/\(digest)")
        var request = URLRequest(url: pathURL)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.httpBody = bytes
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClipDock macOS Sync", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(kind, forHTTPHeaderField: "X-ClipDock-Asset-Kind")
        request.setValue("\(width)", forHTTPHeaderField: "X-ClipDock-Asset-Width")
        request.setValue("\(height)", forHTTPHeaderField: "X-ClipDock-Asset-Height")

        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncServerClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let decoder = JSONDecoder()
            let error = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw SyncServerClientError.httpStatus(
                httpResponse.statusCode,
                error?.error.code ?? "http_error"
            )
        }
        let responseEnvelope = try JSONDecoder().decode(SuccessEnvelope<UploadAssetResponse>.self, from: data)
        return SyncUploadedAssetResult(
            digest: responseEnvelope.data.digest,
            kind: responseEnvelope.data.kind,
            mimeType: responseEnvelope.data.mimeType,
            sizeBytes: responseEnvelope.data.sizeBytes,
            width: responseEnvelope.data.width,
            height: responseEnvelope.data.height,
            alreadyExists: responseEnvelope.data.alreadyExists
        )
    }

    public func pushEvents(
        serverURL: String,
        token: String,
        events: [SyncPushEvent]
    ) async throws -> SyncPushEventsResult {
        let response: SuccessEnvelope<PushEventsResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/events",
            method: "POST",
            token: token,
            body: PushEventsRequest(events: events),
            timeoutInterval: 12
        )
        return SyncPushEventsResult(
            events: response.data.events.map {
                SyncPushedEventResult(
                    clientEventId: $0.clientEventId,
                    serverSeq: $0.serverSeq,
                    duplicate: $0.duplicate
                )
            },
            nextCursor: response.data.nextCursor
        )
    }

    public func pullEvents(
        serverURL: String,
        token: String,
        afterSeq: Int64,
        limit: Int64 = 500
    ) async throws -> SyncPullEventsResult {
        let response: SuccessEnvelope<PullEventsResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/events",
            method: "GET",
            token: token,
            body: EmptyBody?.none,
            queryItems: [
                URLQueryItem(name: "after_seq", value: "\(afterSeq)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ],
            timeoutInterval: 12
        )
        return SyncPullEventsResult(
            events: response.data.events,
            nextCursor: response.data.nextCursor
        )
    }

    public func snapshot(
        serverURL: String,
        token: String
    ) async throws -> SyncSnapshotResult {
        let response: SuccessEnvelope<SnapshotResponse> = try await sendJSON(
            serverURL: serverURL,
            path: "/v2/snapshot",
            method: "GET",
            token: token,
            body: EmptyBody?.none,
            timeoutInterval: 20
        )
        return SyncSnapshotResult(
            snapshotSeq: response.data.snapshotSeq,
            items: response.data.items,
            tombstones: response.data.tombstones
        )
    }

    public func webSocketURL(serverURL: String, cursor: Int64) throws -> URL {
        let baseURL = try normalizedBaseURL(serverURL)
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v2/ws"),
            resolvingAgainstBaseURL: false
        )
        components?.scheme = switch baseURL.scheme?.lowercased() {
        case "https":
            "wss"
        default:
            "ws"
        }
        components?.queryItems = [
            URLQueryItem(name: "cursor", value: "\(cursor)"),
            URLQueryItem(name: "protocol_version", value: "2")
        ]
        guard let url = components?.url else {
            throw SyncServerClientError.invalidBaseURL
        }
        return url
    }

    private func sendJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        serverURL: String,
        path: String,
        method: String,
        token: String?,
        body: RequestBody?,
        queryItems: [URLQueryItem] = [],
        timeoutInterval: TimeInterval? = nil
    ) async throws -> ResponseBody {
        let baseURL = try normalizedBaseURL(serverURL)
        let pathURL = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let url: URL
        if queryItems.isEmpty {
            url = pathURL
        } else {
            var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
            components?.queryItems = queryItems
            guard let queryURL = components?.url else {
                throw SyncServerClientError.invalidBaseURL
            }
            url = queryURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClipDock macOS Sync", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncServerClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let decoder = JSONDecoder()
            let error = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw SyncServerClientError.httpStatus(
                httpResponse.statusCode,
                error?.error.code ?? "http_error"
            )
        }
        let decoder = JSONDecoder()
        return try decoder.decode(ResponseBody.self, from: data)
    }

    private func normalizedBaseURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw SyncServerClientError.invalidBaseURL
        }
        return url
    }
}

private struct EmptyBody: Encodable {}

private struct SuccessEnvelope<T: Decodable>: Decodable {
    let protocolVersion: Int
    let data: T

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case data
    }
}

private struct ErrorEnvelope: Decodable {
    let protocolVersion: Int
    let error: ErrorBody

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case error
    }
}

private struct ErrorBody: Decodable {
    let code: String
    let message: String
}

private struct DeviceNameRequest: Encodable {
    let deviceName: String

    private enum CodingKeys: String, CodingKey {
        case deviceName = "device_name"
    }
}

private struct JoinSyncRequest: Encodable {
    let pairingCode: String
    let deviceName: String

    private enum CodingKeys: String, CodingKey {
        case pairingCode = "pairing_code"
        case deviceName = "device_name"
    }
}

private struct CreateSyncResponse: Decodable {
    let syncID: String
    let pairingCode: String
    let pairingExpiresAtMs: Int64
    let deviceID: String
    let token: String

    private enum CodingKeys: String, CodingKey {
        case syncID = "sync_id"
        case pairingCode = "pairing_code"
        case pairingExpiresAtMs = "pairing_expires_at_ms"
        case deviceID = "device_id"
        case token
    }
}

private struct JoinSyncResponse: Decodable {
    let syncID: String
    let deviceID: String
    let token: String

    private enum CodingKeys: String, CodingKey {
        case syncID = "sync_id"
        case deviceID = "device_id"
        case token
    }
}

private struct CreateInviteResponse: Decodable {
    let syncID: String
    let pairingCode: String
    let pairingExpiresAtMs: Int64

    private enum CodingKeys: String, CodingKey {
        case syncID = "sync_id"
        case pairingCode = "pairing_code"
        case pairingExpiresAtMs = "pairing_expires_at_ms"
    }
}

private struct InfoResponse: Decodable {
    let syncID: String
    let deviceID: String
    let deviceName: String
    let p2p: P2PCapabilities

    private enum CodingKeys: String, CodingKey {
        case syncID = "sync_id"
        case deviceID = "device_id"
        case deviceName = "device_name"
        case p2p
    }
}

private struct P2PCapabilities: Decodable {
    let enabled: Bool
    let transport: String
}

private struct EndpointReportRequest: Encodable {
    let endpointID: String
    let relayURL: String?
    let directAddresses: [String]
    let capabilities: [String: SyncJSONValue]
    let quality: [String: SyncJSONValue]

    init(
        endpointID: String,
        relayURL: String?,
        directAddresses: [String],
        capabilities: [String: SyncJSONValue],
        quality: [String: SyncJSONValue]
    ) {
        self.endpointID = endpointID
        self.relayURL = relayURL
        self.directAddresses = directAddresses
        self.capabilities = capabilities
        self.quality = quality
    }

    private enum CodingKeys: String, CodingKey {
        case endpointID = "endpoint_id"
        case relayURL = "relay_url"
        case directAddresses = "direct_addresses"
        case capabilities
        case quality
    }
}

private struct EndpointReportResponse: Decodable {
    let deviceID: String
    let endpoint: EndpointResponse

    private enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case endpoint
    }
}

private struct EndpointResponse: Decodable {
    let endpointID: String
    let relayURL: String?
    let directAddresses: [String]
    let expiresAtMs: Int64

    private enum CodingKeys: String, CodingKey {
        case endpointID = "endpoint_id"
        case relayURL = "relay_url"
        case directAddresses = "direct_addresses"
        case expiresAtMs = "expires_at_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.endpointID = try container.decode(String.self, forKey: .endpointID)
        self.relayURL = try container.decodeIfPresent(String.self, forKey: .relayURL)
        self.directAddresses = try container.decodeIfPresent([String].self, forKey: .directAddresses) ?? []
        self.expiresAtMs = try container.decode(Int64.self, forKey: .expiresAtMs)
    }
}

private struct ListDevicesResponse: Decodable {
    let devices: [DeviceEndpointResponse]
}

private struct DeviceEndpointResponse: Decodable {
    let deviceID: String
    let deviceName: String
    let endpoint: EndpointResponse

    private enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case endpoint
    }
}

private struct UpsertAssetProviderRequest: Encodable {
    let kind: String
    let byteCount: Int64?
    let mimeType: String?
    let availability: String
    let quality: [String: SyncJSONValue]

    private enum CodingKeys: String, CodingKey {
        case kind
        case byteCount = "byte_count"
        case mimeType = "mime_type"
        case availability
        case quality
    }
}

private struct UpsertAssetProviderResponse: Decodable {
    let assetID: String
    let provider: AssetProviderResponse

    private enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case provider
    }
}

private struct DeleteAssetProviderResponse: Decodable {
    let assetID: String
    let removed: Bool

    private enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case removed
    }
}

private struct ListAssetProvidersResponse: Decodable {
    let assetID: String
    let providers: [AssetProviderResponse]

    private enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case providers
    }
}

private struct UploadAssetResponse: Decodable {
    let digest: String
    let kind: String
    let mimeType: String
    let sizeBytes: Int64
    let width: Int64
    let height: Int64
    let alreadyExists: Bool

    private enum CodingKeys: String, CodingKey {
        case digest
        case kind
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case width = "width_px"
        case height = "height_px"
        case alreadyExists = "already_exists"
    }
}

private struct PushEventsRequest: Encodable {
    let events: [SyncPushEvent]
}

private struct PushEventsResponse: Decodable {
    let events: [PushedEventResponse]
    let nextCursor: Int64

    private enum CodingKeys: String, CodingKey {
        case events
        case nextCursor = "next_cursor"
    }
}

private struct PushedEventResponse: Decodable {
    let clientEventId: String
    let serverSeq: Int64
    let duplicate: Bool

    private enum CodingKeys: String, CodingKey {
        case clientEventId = "client_event_id"
        case serverSeq = "server_seq"
        case duplicate
    }
}

private struct PullEventsResponse: Decodable {
    let events: [SyncPulledEventRecord]
    let nextCursor: Int64

    private enum CodingKeys: String, CodingKey {
        case events
        case nextCursor = "next_cursor"
    }
}

private struct SnapshotResponse: Decodable {
    let snapshotSeq: Int64
    let items: [SyncSnapshotItemRecord]
    let tombstones: [SyncSnapshotTombstoneRecord]

    private enum CodingKeys: String, CodingKey {
        case snapshotSeq = "snapshot_seq"
        case items
        case tombstones
    }
}

private struct AssetProviderResponse: Decodable {
    let deviceID: String
    let deviceName: String
    let kind: String
    let byteCount: Int64?
    let mimeType: String?
    let availability: String
    let quality: [String: SyncJSONDecodedValue]
    let endpoint: EndpointResponse?

    private enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case kind
        case byteCount = "byte_count"
        case mimeType = "mime_type"
        case availability
        case quality
        case endpoint
    }

    func asResult() -> SyncP2PAssetProviderResult {
        SyncP2PAssetProviderResult(
            deviceID: deviceID,
            deviceName: deviceName,
            kind: kind,
            byteCount: byteCount,
            mimeType: mimeType,
            availability: availability,
            blobTicket: quality["blob_ticket"]?.stringValue,
            endpointID: endpoint?.endpointID,
            relayURL: endpoint?.relayURL,
            directAddresses: endpoint?.directAddresses ?? []
        )
    }
}

private enum SyncJSONValue: Encodable, Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case bool(Bool)
    case int(Int64)

    init(stringLiteral value: String) {
        self = .string(value)
    }

    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
}

private enum SyncJSONDecodedValue: Decodable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int64)
    case double(Double)

    var stringValue: String? {
        if case .string(let value) = self {
            value
        } else {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string("")
        }
    }
}
