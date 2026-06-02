import Foundation
import Testing
@testable import ClipboardPanelApp

struct SyncServerClientTests {
    @Test
    func createSyncPostsDeviceNameAndDecodesPairingResponse() async throws {
        let httpClient = MockSyncServerHTTPClient(responseBody: """
        {
          "protocol_version": 1,
          "data": {
            "sync_id": "sync_a",
            "pairing_code": "A1B2C",
            "pairing_expires_at_ms": 12345,
            "device_id": "dev_a",
            "token": "cds_token"
          }
        }
        """)
        let client = SyncServerClient(httpClient: httpClient)

        let result = try await client.createSync(
            serverURL: " http://127.0.0.1:8787 ",
            deviceName: "MacBook"
        )

        #expect(result == SyncCreateResult(
            syncID: "sync_a",
            pairingCode: "A1B2C",
            pairingExpiresAtMs: 12345,
            deviceID: "dev_a",
            token: "cds_token"
        ))
        let request = try #require(httpClient.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:8787/v1/sync/create")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        let body = try requestJSONBody(request)
        #expect(body["device_name"] as? String == "MacBook")
    }

    @Test
    func infoUsesBearerTokenAndDecodesAuthenticatedDeviceIdentity() async throws {
        let httpClient = MockSyncServerHTTPClient(responseBody: """
        {
          "protocol_version": 1,
          "data": {
            "sync_id": "sync_a",
            "device_id": "dev_a",
            "device_name": "MacBook",
            "p2p": {
              "enabled": true,
              "transport": "iroh-blobs"
            }
          }
        }
        """)
        let client = SyncServerClient(httpClient: httpClient)

        let result = try await client.info(
            serverURL: "https://clipdock.example.com",
            token: "cds_token"
        )

        #expect(result == SyncInfoResult(
            syncID: "sync_a",
            deviceID: "dev_a",
            deviceName: "MacBook",
            p2pEnabled: true,
            p2pTransport: "iroh-blobs"
        ))
        let request = try #require(httpClient.requests.first)
        #expect(request.url?.absoluteString == "https://clipdock.example.com/v1/info")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cds_token")
        #expect(request.httpBody == nil)
    }

    @Test
    func reportEndpointSendsP2PMetadata() async throws {
        let httpClient = MockSyncServerHTTPClient(responseBody: """
        {
          "protocol_version": 1,
          "data": {
            "device_id": "dev_a",
            "endpoint": {
              "endpoint_id": "endpoint_a",
              "expires_at_ms": 54321
            }
          }
        }
        """)
        let client = SyncServerClient(httpClient: httpClient)

        let result = try await client.reportEndpoint(
            serverURL: "http://127.0.0.1:8787",
            token: "cds_token",
            endpointID: "endpoint_a",
            relayURL: "https://relay.example.com",
            directAddresses: ["127.0.0.1:12345"],
            pathType: "available",
            rttMs: 12
        )

        #expect(result == SyncEndpointReportResult(
            deviceID: "dev_a",
            endpointID: "endpoint_a",
            expiresAtMs: 54321
        ))
        let request = try #require(httpClient.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:8787/v1/p2p/endpoint")
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cds_token")

        let body = try requestJSONBody(request)
        #expect(body["endpoint_id"] as? String == "endpoint_a")
        #expect(body["relay_url"] as? String == "https://relay.example.com")
        #expect(body["direct_addresses"] as? [String] == ["127.0.0.1:12345"])
        let capabilities = try #require(body["capabilities"] as? [String: Any])
        #expect(capabilities["transport"] as? String == "iroh-blobs")
        #expect(capabilities["blob_transfer"] as? Bool == true)
        #expect(capabilities["macos_client"] as? Bool == true)
        let quality = try #require(body["quality"] as? [String: Any])
        #expect(quality["path_type"] as? String == "available")
        #expect(quality["rtt_ms"] as? Int == 12)
    }

    @Test
    func upsertAssetProviderSendsBlobTicketAndDecodesEndpoint() async throws {
        let assetID = "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let httpClient = MockSyncServerHTTPClient(responseBody: """
        {
          "protocol_version": 1,
          "data": {
            "asset_id": "\(assetID)",
            "provider": {
              "device_id": "dev_a",
              "device_name": "MacBook",
              "kind": "file_payload",
              "byte_count": 1024,
              "mime_type": "application/octet-stream",
              "availability": "online",
              "quality": {
                "transport": "iroh-blobs",
                "blob_ticket": "blobabc"
              },
              "updated_at_ms": 1,
              "expires_at_ms": 2,
              "endpoint": {
                "endpoint_id": "node_a",
                "relay_url": null,
                "direct_addresses": ["127.0.0.1:12345"],
                "capabilities": {},
                "quality": {},
                "updated_at_ms": 1,
                "expires_at_ms": 2
              }
            }
          }
        }
        """)
        let client = SyncServerClient(httpClient: httpClient)

        let result = try await client.upsertAssetProvider(
            serverURL: "http://127.0.0.1:8787",
            token: "cds_token",
            assetID: assetID,
            kind: "file_payload",
            byteCount: 1024,
            mimeType: "application/octet-stream",
            blobTicket: "blobabc"
        )

        #expect(result == SyncP2PAssetProviderResult(
            deviceID: "dev_a",
            deviceName: "MacBook",
            kind: "file_payload",
            byteCount: 1024,
            mimeType: "application/octet-stream",
            availability: "online",
            blobTicket: "blobabc",
            endpointID: "node_a",
            relayURL: nil,
            directAddresses: ["127.0.0.1:12345"]
        ))
        let request = try #require(httpClient.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:8787/v1/p2p/assets/\(assetID)/providers/me")
        #expect(request.httpMethod == "PUT")
        let body = try requestJSONBody(request)
        #expect(body["kind"] as? String == "file_payload")
        #expect(body["byte_count"] as? Int == 1024)
        let quality = try #require(body["quality"] as? [String: Any])
        #expect(quality["transport"] as? String == "iroh-blobs")
        #expect(quality["blob_ticket"] as? String == "blobabc")
    }

    @Test
    func serverErrorsExposeStatusAndCode() async {
        let httpClient = MockSyncServerHTTPClient(
            statusCode: 403,
            responseBody: """
            {
              "protocol_version": 1,
              "error": {
                "code": "invalid_pairing_code",
                "message": "invalid pairing code"
              }
            }
            """
        )
        let client = SyncServerClient(httpClient: httpClient)

        await #expect(throws: SyncServerClientError.httpStatus(403, "invalid_pairing_code")) {
            _ = try await client.joinSync(
                serverURL: "http://127.0.0.1:8787",
                pairingCode: "A1B2C",
                deviceName: "MacBook"
            )
        }
    }
}

private final class MockSyncServerHTTPClient: SyncServerHTTPClient, @unchecked Sendable {
    private let statusCode: Int
    private let responseBody: String
    private(set) var requests: [URLRequest] = []

    init(statusCode: Int = 200, responseBody: String) {
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(responseBody.utf8), response)
    }
}

private func requestJSONBody(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
