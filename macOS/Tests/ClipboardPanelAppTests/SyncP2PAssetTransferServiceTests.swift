import Foundation
import Testing
@testable import ClipboardPanelApp

struct SyncP2PAssetTransferServiceTests {
    @Test
    func providerSelectorPrefersOnlineRemoteEndpointWithTicket() {
        let providers = [
            makeProvider(
                deviceID: "local",
                availability: "online",
                blobTicket: "local-ticket",
                endpointID: "local-node"
            ),
            makeProvider(
                deviceID: "remote",
                availability: "online",
                blobTicket: "remote-ticket",
                endpointID: "remote-node"
            ),
            makeProvider(
                deviceID: "stale",
                availability: "last_seen",
                blobTicket: nil,
                endpointID: nil
            )
        ]

        let candidate = SyncP2PProviderSelector.selectDownloadCandidate(
            providers: providers,
            currentDeviceID: "local"
        )

        #expect(candidate?.ticket == "remote-ticket")
        #expect(candidate?.deviceID == "remote")
        #expect(candidate?.endpointID == "remote-node")
    }

    @Test
    func registerLocalProviderStartsNodeReportsEndpointImportsBlobAndUpsertsProvider() async throws {
        let rust = MockP2PRustClient()
        let metadata = MockP2PMetadataClient()
        let service = SyncP2PAssetTransferService(rustClient: rust, metadataClient: metadata)
        let appSupportURL = URL(fileURLWithPath: "/tmp/ClipDockTests")
        let fileURL = appSupportURL.appendingPathComponent("assets/sample.webp")
        let configuration = SyncP2PTransferConfiguration(
            serverURL: "http://127.0.0.1:8787",
            token: "cds_token",
            currentDeviceID: "dev_local",
            appSupportDirectory: appSupportURL,
            p2pEnabled: true
        )

        let result = try await service.registerLocalProvider(
            configuration: configuration,
            fileURL: fileURL,
            kind: .imagePayload,
            mimeType: "image/webp"
        )

        #expect(result.provided.assetID == rust.provideResult.assetID)
        #expect(rust.startCalls == [appSupportURL])
        #expect(rust.provideCalls == [fileURL])
        #expect(metadata.reportedEndpointIDs == ["node_local"])
        #expect(metadata.upsertedAssetIDs == ["blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
        #expect(metadata.upsertedKinds == ["image_payload"])
        #expect(metadata.upsertedBlobTickets == ["blob-ticket-local"])
    }

    @Test
    func probeBestProviderUsesSelectedBlobTicket() async throws {
        let rust = MockP2PRustClient()
        let metadata = MockP2PMetadataClient()
        metadata.providers = [
            makeProvider(deviceID: "local", blobTicket: "local-ticket", endpointID: "local-node"),
            makeProvider(deviceID: "remote", blobTicket: "remote-ticket", endpointID: "remote-node")
        ]
        let service = SyncP2PAssetTransferService(rustClient: rust, metadataClient: metadata)

        let result = try await service.probeBestProvider(
            configuration: makeConfiguration(),
            assetID: "blake3:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        )

        #expect(result.candidate.deviceID == "remote")
        #expect(result.probe.reachable)
        #expect(rust.probeTickets == ["remote-ticket"])
    }

    @Test
    func downloadBestProviderBuildsStableDefaultOutputAndDownloadsSelectedTicket() async throws {
        let rust = MockP2PRustClient()
        let metadata = MockP2PMetadataClient()
        metadata.providers = [
            makeProvider(
                deviceID: "remote",
                kind: "file_payload",
                mimeType: "application/pdf",
                blobTicket: "remote-ticket",
                endpointID: "remote-node"
            )
        ]
        let service = SyncP2PAssetTransferService(rustClient: rust, metadataClient: metadata)
        let assetID = "blake3:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

        let result = try await service.downloadBestProvider(
            configuration: makeConfiguration(),
            assetID: assetID
        )

        #expect(result.candidate.ticket == "remote-ticket")
        #expect(rust.probeTickets == ["remote-ticket"])
        #expect(rust.downloadTickets == ["remote-ticket"])
        #expect(result.outputURL.path.hasSuffix(
            "p2p-downloads/blake3_cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.pdf"
        ))
    }

    @Test
    func disabledConfigurationRejectsP2POperations() async {
        let service = SyncP2PAssetTransferService(
            rustClient: MockP2PRustClient(),
            metadataClient: MockP2PMetadataClient()
        )
        var configuration = makeConfiguration()
        configuration = SyncP2PTransferConfiguration(
            serverURL: configuration.serverURL,
            token: configuration.token,
            currentDeviceID: configuration.currentDeviceID,
            appSupportDirectory: configuration.appSupportDirectory,
            p2pEnabled: false
        )

        await #expect(throws: SyncP2PAssetTransferError.p2pDisabled) {
            _ = try await service.probeBestProvider(
                configuration: configuration,
                assetID: "blake3:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
            )
        }
    }
}

private final class MockP2PRustClient: SyncP2PRustClient, @unchecked Sendable {
    var startCalls: [URL] = []
    var provideCalls: [URL] = []
    var probeTickets: [String] = []
    var downloadTickets: [String] = []

    let nodeResult = RustP2PNodeResult(
        endpointID: "node_local",
        relayURL: "https://relay.example.com",
        directAddresses: ["127.0.0.1:12345"]
    )
    let provideResult = RustP2PProvideResult(
        assetID: "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        blobHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        blobTicket: "blob-ticket-local",
        byteCount: 128
    )
    let probeResult = RustP2PProbeResult(
        reachable: true,
        remoteNodeID: "remote-node",
        pathType: "direct_or_relay",
        connectMs: 8,
        rttMs: 3
    )

    func startP2PNode(
        appSupportDirectory: URL,
        timeoutMs: Int64
    ) -> Result<RustP2PNodeResult, RustCoreError> {
        startCalls.append(appSupportDirectory)
        return .success(nodeResult)
    }

    func provideP2PFile(
        appSupportDirectory: URL,
        fileURL: URL,
        timeoutMs: Int64
    ) -> Result<RustP2PProvideResult, RustCoreError> {
        provideCalls.append(fileURL)
        return .success(provideResult)
    }

    func downloadP2PFile(
        appSupportDirectory: URL,
        blobTicket: String,
        outputURL: URL,
        timeoutMs: Int64
    ) -> Result<RustP2PDownloadResult, RustCoreError> {
        downloadTickets.append(blobTicket)
        return .success(RustP2PDownloadResult(
            outputPath: outputURL.path,
            blobHash: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            localBytes: 0,
            downloadedBytes: 4096,
            elapsedMs: 30
        ))
    }

    func probeP2PTicket(
        appSupportDirectory: URL,
        blobTicket: String,
        timeoutMs: Int64
    ) -> Result<RustP2PProbeResult, RustCoreError> {
        probeTickets.append(blobTicket)
        return .success(probeResult)
    }
}

private final class MockP2PMetadataClient: SyncP2PMetadataClient, @unchecked Sendable {
    var providers: [SyncP2PAssetProviderResult] = []
    var reportedEndpointIDs: [String] = []
    var upsertedAssetIDs: [String] = []
    var upsertedKinds: [String] = []
    var upsertedBlobTickets: [String] = []

    func reportEndpoint(
        serverURL: String,
        token: String,
        endpointID: String,
        relayURL: String?,
        directAddresses: [String],
        pathType: String,
        rttMs: Int64?
    ) async throws -> SyncEndpointReportResult {
        reportedEndpointIDs.append(endpointID)
        return SyncEndpointReportResult(
            deviceID: "dev_local",
            endpointID: endpointID,
            expiresAtMs: 1
        )
    }

    func upsertAssetProvider(
        serverURL: String,
        token: String,
        assetID: String,
        kind: String,
        byteCount: Int64?,
        mimeType: String?,
        blobTicket: String,
        availability: String
    ) async throws -> SyncP2PAssetProviderResult {
        upsertedAssetIDs.append(assetID)
        upsertedKinds.append(kind)
        upsertedBlobTickets.append(blobTicket)
        return makeProvider(
            deviceID: "dev_local",
            kind: kind,
            mimeType: mimeType,
            byteCount: byteCount,
            blobTicket: blobTicket,
            endpointID: "node_local"
        )
    }

    func listAssetProviders(
        serverURL: String,
        token: String,
        assetID: String
    ) async throws -> SyncP2PAssetProvidersResult {
        SyncP2PAssetProvidersResult(assetID: assetID, providers: providers)
    }
}

private func makeConfiguration() -> SyncP2PTransferConfiguration {
    SyncP2PTransferConfiguration(
        serverURL: "http://127.0.0.1:8787",
        token: "cds_token",
        currentDeviceID: "local",
        appSupportDirectory: URL(fileURLWithPath: "/tmp/ClipDockTests"),
        p2pEnabled: true
    )
}

private func makeProvider(
    deviceID: String,
    kind: String = "file_payload",
    mimeType: String? = "application/octet-stream",
    byteCount: Int64? = 256,
    availability: String = "online",
    blobTicket: String?,
    endpointID: String?
) -> SyncP2PAssetProviderResult {
    SyncP2PAssetProviderResult(
        deviceID: deviceID,
        deviceName: "\(deviceID)-name",
        kind: kind,
        byteCount: byteCount,
        mimeType: mimeType,
        availability: availability,
        blobTicket: blobTicket,
        endpointID: endpointID,
        relayURL: nil,
        directAddresses: endpointID == nil ? [] : ["127.0.0.1:12345"]
    )
}
