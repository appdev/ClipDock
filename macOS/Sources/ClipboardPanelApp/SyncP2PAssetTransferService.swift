import Foundation
import UniformTypeIdentifiers

public protocol SyncP2PRustClient: Sendable {
    func startP2PNode(
        appSupportDirectory: URL,
        timeoutMs: Int64
    ) -> Result<RustP2PNodeResult, RustCoreError>

    func provideP2PFile(
        appSupportDirectory: URL,
        fileURL: URL,
        timeoutMs: Int64
    ) -> Result<RustP2PProvideResult, RustCoreError>

    func downloadP2PFile(
        appSupportDirectory: URL,
        blobTicket: String,
        outputURL: URL,
        timeoutMs: Int64
    ) -> Result<RustP2PDownloadResult, RustCoreError>

    func probeP2PTicket(
        appSupportDirectory: URL,
        blobTicket: String,
        timeoutMs: Int64
    ) -> Result<RustP2PProbeResult, RustCoreError>
}

extension RustCoreClient: SyncP2PRustClient {}

public protocol SyncP2PMetadataClient: Sendable {
    func reportEndpoint(
        serverURL: String,
        token: String,
        endpointID: String,
        relayURL: String?,
        directAddresses: [String],
        pathType: String,
        rttMs: Int64?
    ) async throws -> SyncEndpointReportResult

    func upsertAssetProvider(
        serverURL: String,
        token: String,
        assetID: String,
        kind: String,
        byteCount: Int64?,
        mimeType: String?,
        blobTicket: String,
        availability: String
    ) async throws -> SyncP2PAssetProviderResult

    func listAssetProviders(
        serverURL: String,
        token: String,
        assetID: String
    ) async throws -> SyncP2PAssetProvidersResult
}

extension SyncServerClient: SyncP2PMetadataClient {}

public enum SyncP2PAssetKind: String, Equatable, Sendable {
    case imagePayload = "image_payload"
    case filePayload = "file_payload"
    case thumbnail
}

public struct SyncP2PTransferConfiguration: Equatable, Sendable {
    public let serverURL: String
    public let token: String
    public let currentDeviceID: String?
    public let appSupportDirectory: URL
    public let p2pEnabled: Bool

    public init(
        serverURL: String,
        token: String,
        currentDeviceID: String?,
        appSupportDirectory: URL,
        p2pEnabled: Bool
    ) {
        self.serverURL = serverURL
        self.token = token
        self.currentDeviceID = currentDeviceID
        self.appSupportDirectory = appSupportDirectory
        self.p2pEnabled = p2pEnabled
    }
}

public struct SyncP2PProviderCandidate: Equatable, Sendable {
    public let ticket: String
    public let deviceID: String
    public let deviceName: String
    public let kind: String
    public let mimeType: String?
    public let byteCount: Int64?
    public let endpointID: String?
    public let relayURL: String?
    public let directAddresses: [String]

    public init(
        ticket: String,
        deviceID: String,
        deviceName: String,
        kind: String,
        mimeType: String?,
        byteCount: Int64?,
        endpointID: String?,
        relayURL: String?,
        directAddresses: [String]
    ) {
        self.ticket = ticket
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.kind = kind
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.endpointID = endpointID
        self.relayURL = relayURL
        self.directAddresses = directAddresses
    }
}

public enum SyncP2PProviderSelector {
    public static func selectDownloadCandidate(
        providers: [SyncP2PAssetProviderResult],
        currentDeviceID: String?
    ) -> SyncP2PProviderCandidate? {
        providers
            .compactMap { provider -> (score: Int, candidate: SyncP2PProviderCandidate)? in
                guard let ticket = provider.blobTicket?.nonEmptyString else { return nil }
                let score = [
                    provider.availability == "online" ? 8 : 0,
                    provider.endpointID?.nonEmptyString == nil ? 0 : 4,
                    provider.deviceID == currentDeviceID ? 0 : 2
                ].reduce(0, +)
                return (
                    score,
                    SyncP2PProviderCandidate(
                        ticket: ticket,
                        deviceID: provider.deviceID,
                        deviceName: provider.deviceName,
                        kind: provider.kind,
                        mimeType: provider.mimeType,
                        byteCount: provider.byteCount,
                        endpointID: provider.endpointID,
                        relayURL: provider.relayURL,
                        directAddresses: provider.directAddresses
                    )
                )
            }
            .max { lhs, rhs in lhs.score < rhs.score }?
            .candidate
    }
}

public enum SyncP2PAssetTransferError: Error, Equatable, Sendable {
    case p2pDisabled
    case noProviders
    case noUsableProvider
    case rustFailure(code: String, message: String)
}

public struct SyncP2PAssetRegistrationResult: Equatable, Sendable {
    public let node: RustP2PNodeResult
    public let provided: RustP2PProvideResult
    public let provider: SyncP2PAssetProviderResult
}

public struct SyncP2PPeerProbeResult: Equatable, Sendable {
    public let assetID: String
    public let candidate: SyncP2PProviderCandidate
    public let probe: RustP2PProbeResult
}

public struct SyncP2PPayloadDownloadResult: Equatable, Sendable {
    public let assetID: String
    public let candidate: SyncP2PProviderCandidate
    public let probe: RustP2PProbeResult?
    public let download: RustP2PDownloadResult
    public let outputURL: URL
}

public struct SyncP2PAssetTransferService: Sendable {
    private let rustClient: any SyncP2PRustClient
    private let metadataClient: any SyncP2PMetadataClient

    public init(
        rustClient: any SyncP2PRustClient,
        metadataClient: any SyncP2PMetadataClient
    ) {
        self.rustClient = rustClient
        self.metadataClient = metadataClient
    }

    public func registerLocalProvider(
        configuration: SyncP2PTransferConfiguration,
        fileURL: URL,
        kind: SyncP2PAssetKind,
        mimeType: String?,
        timeoutMs: Int64 = 10_000
    ) async throws -> SyncP2PAssetRegistrationResult {
        guard configuration.p2pEnabled else {
            throw SyncP2PAssetTransferError.p2pDisabled
        }

        let node = try await startNode(configuration: configuration, timeoutMs: timeoutMs)
        _ = try await metadataClient.reportEndpoint(
            serverURL: configuration.serverURL,
            token: configuration.token,
            endpointID: node.endpointID,
            relayURL: node.relayURL,
            directAddresses: node.directAddresses,
            pathType: "available",
            rttMs: nil
        )
        let provided = try await provideFile(
            configuration: configuration,
            fileURL: fileURL,
            timeoutMs: timeoutMs
        )
        let provider = try await metadataClient.upsertAssetProvider(
            serverURL: configuration.serverURL,
            token: configuration.token,
            assetID: provided.assetID,
            kind: kind.rawValue,
            byteCount: provided.byteCount,
            mimeType: mimeType,
            blobTicket: provided.blobTicket,
            availability: "online"
        )
        return SyncP2PAssetRegistrationResult(
            node: node,
            provided: provided,
            provider: provider
        )
    }

    public func probeBestProvider(
        configuration: SyncP2PTransferConfiguration,
        assetID: String,
        timeoutMs: Int64 = 5_000
    ) async throws -> SyncP2PPeerProbeResult {
        guard configuration.p2pEnabled else {
            throw SyncP2PAssetTransferError.p2pDisabled
        }

        _ = try await startNode(configuration: configuration, timeoutMs: timeoutMs)
        let providers = try await metadataClient.listAssetProviders(
            serverURL: configuration.serverURL,
            token: configuration.token,
            assetID: assetID
        )
        guard !providers.providers.isEmpty else {
            throw SyncP2PAssetTransferError.noProviders
        }
        guard let candidate = SyncP2PProviderSelector.selectDownloadCandidate(
            providers: providers.providers,
            currentDeviceID: configuration.currentDeviceID
        ) else {
            throw SyncP2PAssetTransferError.noUsableProvider
        }

        let probe = try await probeTicket(
            configuration: configuration,
            ticket: candidate.ticket,
            timeoutMs: timeoutMs
        )
        return SyncP2PPeerProbeResult(
            assetID: assetID,
            candidate: candidate,
            probe: probe
        )
    }

    public func downloadBestProvider(
        configuration: SyncP2PTransferConfiguration,
        assetID: String,
        outputURL: URL? = nil,
        probesBeforeDownload: Bool = true,
        timeoutMs: Int64 = 30_000
    ) async throws -> SyncP2PPayloadDownloadResult {
        guard configuration.p2pEnabled else {
            throw SyncP2PAssetTransferError.p2pDisabled
        }

        let providers = try await metadataClient.listAssetProviders(
            serverURL: configuration.serverURL,
            token: configuration.token,
            assetID: assetID
        )
        guard !providers.providers.isEmpty else {
            throw SyncP2PAssetTransferError.noProviders
        }
        guard let candidate = SyncP2PProviderSelector.selectDownloadCandidate(
            providers: providers.providers,
            currentDeviceID: configuration.currentDeviceID
        ) else {
            throw SyncP2PAssetTransferError.noUsableProvider
        }

        let probe = probesBeforeDownload
            ? try await probeTicket(configuration: configuration, ticket: candidate.ticket, timeoutMs: min(timeoutMs, 5_000))
            : nil
        let resolvedOutputURL = outputURL ?? defaultOutputURL(
            assetID: assetID,
            candidate: candidate,
            appSupportDirectory: configuration.appSupportDirectory
        )
        let download = try await downloadFile(
            configuration: configuration,
            ticket: candidate.ticket,
            outputURL: resolvedOutputURL,
            timeoutMs: timeoutMs
        )
        return SyncP2PPayloadDownloadResult(
            assetID: assetID,
            candidate: candidate,
            probe: probe,
            download: download,
            outputURL: resolvedOutputURL
        )
    }

    private func startNode(
        configuration: SyncP2PTransferConfiguration,
        timeoutMs: Int64
    ) async throws -> RustP2PNodeResult {
        guard configuration.p2pEnabled else {
            throw SyncP2PAssetTransferError.p2pDisabled
        }

        let rustClient = rustClient
        return try await Task.detached(priority: .utility) {
            try Self.unwrap(rustClient.startP2PNode(
                appSupportDirectory: configuration.appSupportDirectory,
                timeoutMs: timeoutMs
            ))
        }.value
    }

    private func provideFile(
        configuration: SyncP2PTransferConfiguration,
        fileURL: URL,
        timeoutMs: Int64
    ) async throws -> RustP2PProvideResult {
        let rustClient = rustClient
        return try await Task.detached(priority: .utility) {
            try Self.unwrap(rustClient.provideP2PFile(
                appSupportDirectory: configuration.appSupportDirectory,
                fileURL: fileURL,
                timeoutMs: timeoutMs
            ))
        }.value
    }

    private func probeTicket(
        configuration: SyncP2PTransferConfiguration,
        ticket: String,
        timeoutMs: Int64
    ) async throws -> RustP2PProbeResult {
        let rustClient = rustClient
        return try await Task.detached(priority: .utility) {
            try Self.unwrap(rustClient.probeP2PTicket(
                appSupportDirectory: configuration.appSupportDirectory,
                blobTicket: ticket,
                timeoutMs: timeoutMs
            ))
        }.value
    }

    private func downloadFile(
        configuration: SyncP2PTransferConfiguration,
        ticket: String,
        outputURL: URL,
        timeoutMs: Int64
    ) async throws -> RustP2PDownloadResult {
        let rustClient = rustClient
        return try await Task.detached(priority: .utility) {
            try Self.unwrap(rustClient.downloadP2PFile(
                appSupportDirectory: configuration.appSupportDirectory,
                blobTicket: ticket,
                outputURL: outputURL,
                timeoutMs: timeoutMs
            ))
        }.value
    }

    private func defaultOutputURL(
        assetID: String,
        candidate: SyncP2PProviderCandidate,
        appSupportDirectory: URL
    ) -> URL {
        let directory = appSupportDirectory.appendingPathComponent("p2p-downloads", isDirectory: true)
        let fileStem = Self.safeFileStem(for: assetID)
        let fileExtension = Self.fileExtension(for: candidate.mimeType)
        let fileName = fileExtension.isEmpty ? fileStem : "\(fileStem).\(fileExtension)"
        return directory.appendingPathComponent(fileName)
    }

    private static func unwrap<T>(_ result: Result<T, RustCoreError>) throws -> T {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw SyncP2PAssetTransferError.rustFailure(
                code: error.code,
                message: error.messageKey.isEmpty ? error.message : error.messageKey
            )
        }
    }

    private static func safeFileStem(for assetID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = assetID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let trimmed = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return trimmed.isEmpty ? "payload" : trimmed
    }

    private static func fileExtension(for mimeType: String?) -> String {
        guard let mimeType = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mimeType.isEmpty else {
            return ""
        }
        switch mimeType.lowercased() {
        case "image/jpeg":
            return "jpg"
        case "application/pdf":
            return "pdf"
        case "text/plain":
            return "txt"
        default:
            return UTType(mimeType: mimeType)?.preferredFilenameExtension ?? ""
        }
    }
}

private extension String {
    var nonEmptyString: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
