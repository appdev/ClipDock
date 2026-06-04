import Foundation

public struct SyncInboundConfiguration: Equatable, Sendable {
    public let serverURL: String
    public let token: String
    public let syncID: String
    public let deviceID: String
    public let appSupportURL: URL

    public init(
        serverURL: String,
        token: String,
        syncID: String,
        deviceID: String,
        appSupportURL: URL
    ) {
        self.serverURL = serverURL
        self.token = token
        self.syncID = syncID
        self.deviceID = deviceID
        self.appSupportURL = appSupportURL
    }

    public var signature: String {
        [
            normalizedServerURL(serverURL),
            Self.tokenFingerprint(token),
            syncID,
            deviceID,
            appSupportURL.standardizedFileURL.path
        ].joined(separator: "|")
    }

    private static func tokenFingerprint(_ token: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in token.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

public enum SyncInboundTiming {
    public static let fallbackPollNanoseconds: UInt64 = 30_000_000_000

    public static func reconnectDelayNanoseconds(attempt: Int, jitterRatio: Double = 0) -> UInt64 {
        let clampedAttempt = max(0, min(attempt, 6))
        let baseSeconds = min(300.0, 5.0 * pow(2.0, Double(clampedAttempt)))
        let jitter = max(-0.25, min(0.25, jitterRatio))
        return UInt64((baseSeconds * (1 + jitter) * 1_000_000_000).rounded())
    }
}

public enum SyncInboundCoordinatorError: Error, Equatable, Sendable {
    case rust(String)
    case staleSignature
}

public protocol SyncInboundRustCoreClient: Sendable {
    func getSyncProgress(
        appSupportDirectory: URL,
        syncID: String,
        deviceID: String
    ) -> Result<RustSyncProgressResult, RustCoreError>

    func applySyncEvents(
        appSupportDirectory: URL,
        request: RustSyncApplyEventsRequest
    ) -> Result<RustSyncApplyResult, RustCoreError>

    func applySyncSnapshot(
        appSupportDirectory: URL,
        request: RustSyncApplySnapshotRequest
    ) -> Result<RustSyncApplyResult, RustCoreError>

    func markSyncLocalPending(
        appSupportDirectory: URL,
        request: RustSyncLocalPendingRequest
    ) -> Result<RustItemManagementResult, RustCoreError>
}

extension RustCoreClient: SyncInboundRustCoreClient {}

public protocol SyncInboundServerClient: Sendable {
    func pullEvents(
        serverURL: String,
        token: String,
        afterSeq: Int64,
        limit: Int64
    ) async throws -> SyncPullEventsResult

    func snapshot(
        serverURL: String,
        token: String
    ) async throws -> SyncSnapshotResult

    func webSocketURL(serverURL: String, cursor: Int64) throws -> URL
}

public extension SyncInboundServerClient {
    func pullEvents(
        serverURL: String,
        token: String,
        afterSeq: Int64
    ) async throws -> SyncPullEventsResult {
        try await pullEvents(serverURL: serverURL, token: token, afterSeq: afterSeq, limit: 500)
    }
}

extension SyncServerClient: SyncInboundServerClient {}

@MainActor
public final class SyncInboundCoordinator {
    private let rustClient: any SyncInboundRustCoreClient
    private let syncClient: any SyncInboundServerClient
    private let urlSession: URLSession
    private let onItemsChanged: @MainActor @Sendable ([String]) -> Void
    private let ackSender: (@MainActor @Sendable (String) async throws -> Void)?

    private var activeConfiguration: SyncInboundConfiguration?
    private var activeSignature: String?
    private var startupTask: Task<Void, Never>?
    private var readerTask: Task<Void, Never>?
    private var fallbackPollTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var socketTask: URLSessionWebSocketTask?
    private var isCatchingUp = false
    private var bufferedBatches: [SyncWebSocketEventBatch] = []
    private var unknownMessageCount = 0
    private var reconnectAttempt = 0
    private var deltaFailuresByCursor: [Int64: Int] = [:]

    public init(
        rustClient: any SyncInboundRustCoreClient,
        syncClient: any SyncInboundServerClient,
        urlSession: URLSession = .shared,
        ackSender: (@MainActor @Sendable (String) async throws -> Void)? = nil,
        onItemsChanged: @escaping @MainActor @Sendable ([String]) -> Void
    ) {
        self.rustClient = rustClient
        self.syncClient = syncClient
        self.urlSession = urlSession
        self.ackSender = ackSender
        self.onItemsChanged = onItemsChanged
    }

    public func start(configuration: SyncInboundConfiguration) {
        guard activeSignature != configuration.signature else { return }
        stop()
        activeConfiguration = configuration
        activeSignature = configuration.signature
        startupTask = Task { @MainActor [weak self] in
            await self?.startLiveSync(configuration: configuration, signature: configuration.signature)
        }
    }

    public func stop() {
        startupTask?.cancel()
        readerTask?.cancel()
        fallbackPollTask?.cancel()
        reconnectTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        startupTask = nil
        readerTask = nil
        fallbackPollTask = nil
        reconnectTask = nil
        socketTask = nil
        activeConfiguration = nil
        activeSignature = nil
        bufferedBatches.removeAll()
        unknownMessageCount = 0
        reconnectAttempt = 0
        deltaFailuresByCursor.removeAll()
        isCatchingUp = false
    }

    public func backfillPendingOutbox(
        _ events: [SyncOutboxEvent],
        configuration: SyncInboundConfiguration
    ) {
        for event in events {
            guard event.type == "item_upsert" || event.type == "item_delete" else { continue }
            _ = rustClient.markSyncLocalPending(
                appSupportDirectory: configuration.appSupportURL,
                request: RustSyncLocalPendingRequest(
                    syncID: configuration.syncID,
                    contentHash: event.contentHash,
                    itemID: nil,
                    clientEventID: event.clientEventId
                )
            )
        }
    }

    private func startLiveSync(
        configuration: SyncInboundConfiguration,
        signature: String
    ) async {
        do {
            let progress = try readProgress(configuration: configuration)
            try assertActive(signature)
            openSocket(configuration: configuration, cursor: progress.cursor, signature: signature)
            isCatchingUp = true
            try await catchUpOrCorrectSnapshot(configuration: configuration, signature: signature)
            isCatchingUp = false
            try await replayBufferedBatches(configuration: configuration, signature: signature)
            reconnectAttempt = 0
            startFallbackPoll(configuration: configuration, signature: signature)
        } catch {
            isCatchingUp = false
            recover(configuration: configuration, signature: signature)
        }
    }

    private func openSocket(
        configuration: SyncInboundConfiguration,
        cursor: Int64,
        signature: String
    ) {
        do {
            var request = URLRequest(url: try syncClient.webSocketURL(serverURL: configuration.serverURL, cursor: cursor))
            request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
            request.setValue("ClipDock macOS Sync", forHTTPHeaderField: "User-Agent")
            let task = urlSession.webSocketTask(with: request)
            socketTask = task
            unknownMessageCount = 0
            task.resume()
            readerTask = Task { @MainActor [weak self] in
                await self?.readSocket(configuration: configuration, signature: signature)
            }
        } catch {
            recover(configuration: configuration, signature: signature)
        }
    }

    private func readSocket(
        configuration: SyncInboundConfiguration,
        signature: String
    ) async {
        guard let socketTask else { return }
        while !Task.isCancelled && activeSignature == signature {
            do {
                let message = try await socketTask.receive()
                let text: String
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    guard let value = String(data: data, encoding: .utf8) else {
                        recover(configuration: configuration, signature: signature)
                        return
                    }
                    text = value
                @unknown default:
                    continue
                }
                try await handleSocketText(text, configuration: configuration, signature: signature)
            } catch {
                recover(configuration: configuration, signature: signature)
                return
            }
        }
    }

    private func handleSocketText(
        _ text: String,
        configuration: SyncInboundConfiguration,
        signature: String
    ) async throws {
        try assertActive(signature)
        let message = try SyncWebSocketMessage(text: text)

        switch message {
        case .hello:
            unknownMessageCount = 0
        case .catchupRequired:
            try await catchUpOrCorrectSnapshot(configuration: configuration, signature: signature)
        case .eventBatch(let batch):
            if isCatchingUp {
                bufferedBatches.append(batch)
            } else {
                let result = try applyEvents(
                    batch.events,
                    nextCursor: batch.toSeq,
                    configuration: configuration,
                    signature: signature
                )
                try await sendAck(result.cursor, signature: signature)
            }
        case .error:
            recover(configuration: configuration, signature: signature)
        case .unknown:
            unknownMessageCount += 1
            if unknownMessageCount >= 3 {
                recover(configuration: configuration, signature: signature)
            }
        }
    }

    private func catchUpOrCorrectSnapshot(
        configuration: SyncInboundConfiguration,
        signature: String
    ) async throws {
        do {
            try await catchUp(configuration: configuration, signature: signature)
        } catch {
            if shouldRunSnapshotCorrection(for: error, configuration: configuration) {
                try await correctFromSnapshot(configuration: configuration, signature: signature)
            } else {
                throw error
            }
        }
    }

    private func catchUp(
        configuration: SyncInboundConfiguration,
        signature: String
    ) async throws {
        var progress = try readProgress(configuration: configuration)
        while !Task.isCancelled {
            try assertActive(signature)
            let pulled = try await syncClient.pullEvents(
                serverURL: configuration.serverURL,
                token: configuration.token,
                afterSeq: progress.cursor
            )
            let result = try applyEvents(
                pulled.events,
                nextCursor: pulled.nextCursor,
                configuration: configuration,
                signature: signature
            )
            deltaFailuresByCursor[progress.cursor] = nil
            progress = RustSyncProgressResult(cursor: result.cursor, snapshotSeq: result.snapshotSeq)
            guard pulled.events.count >= 500 else { return }
        }
    }

    private func correctFromSnapshot(
        configuration: SyncInboundConfiguration,
        signature: String
    ) async throws {
        try assertActive(signature)
        let snapshot = try await syncClient.snapshot(
            serverURL: configuration.serverURL,
            token: configuration.token
        )
        let result = try rustResult(rustClient.applySyncSnapshot(
            appSupportDirectory: configuration.appSupportURL,
            request: RustSyncApplySnapshotRequest(
                syncID: configuration.syncID,
                deviceID: configuration.deviceID,
                snapshotSeq: snapshot.snapshotSeq,
                items: snapshot.items.map { $0.rustRecord() },
                tombstones: snapshot.tombstones.map { $0.rustRecord() }
            )
        ))
        try assertActive(signature)
        notifyChangedItems(result.changedItemIds)

        let postSnapshot = try await syncClient.pullEvents(
            serverURL: configuration.serverURL,
            token: configuration.token,
            afterSeq: result.cursor
        )
        _ = try applyEvents(
            postSnapshot.events,
            nextCursor: postSnapshot.nextCursor,
            configuration: configuration,
            signature: signature
        )
    }

    private func replayBufferedBatches(
        configuration: SyncInboundConfiguration,
        signature: String
    ) async throws {
        let batches = bufferedBatches.sorted { $0.fromSeq < $1.fromSeq }
        bufferedBatches.removeAll()
        for batch in batches {
            try assertActive(signature)
            let result = try applyEvents(
                batch.events,
                nextCursor: batch.toSeq,
                configuration: configuration,
                signature: signature
            )
            try await sendAck(result.cursor, signature: signature)
        }
    }

    private func applyEvents(
        _ events: [SyncPulledEventRecord],
        nextCursor: Int64,
        configuration: SyncInboundConfiguration,
        signature: String
    ) throws -> RustSyncApplyResult {
        try assertActive(signature)
        let result = try rustResult(rustClient.applySyncEvents(
            appSupportDirectory: configuration.appSupportURL,
            request: RustSyncApplyEventsRequest(
                syncID: configuration.syncID,
                deviceID: configuration.deviceID,
                events: events.map { $0.rustRecord() },
                nextCursor: nextCursor
            )
        ))
        try assertActive(signature)
        notifyChangedItems(result.changedItemIds)
        return result
    }

    private func notifyChangedItems(_ itemIDs: [String]) {
        guard !itemIDs.isEmpty else { return }
        onItemsChanged(itemIDs)
    }

    private func sendAck(_ cursor: Int64, signature: String) async throws {
        try assertActive(signature)
        let payload = #"{"type":"ack","server_seq":\#(cursor)}"#
        if let ackSender {
            try await ackSender(payload)
            return
        }
        try await socketTask?.send(.string(payload))
    }

    private func startFallbackPoll(
        configuration: SyncInboundConfiguration,
        signature: String
    ) {
        fallbackPollTask?.cancel()
        fallbackPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: SyncInboundTiming.fallbackPollNanoseconds)
                guard !Task.isCancelled else { return }
                do {
                    try await self?.catchUpOrCorrectSnapshot(configuration: configuration, signature: signature)
                } catch {
                    self?.recover(configuration: configuration, signature: signature)
                    return
                }
            }
        }
    }

    private func recover(
        configuration: SyncInboundConfiguration,
        signature: String
    ) {
        guard activeSignature == signature else { return }
        closeLocalSocketState()
        reconnectTask?.cancel()
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        let delay = SyncInboundTiming.reconnectDelayNanoseconds(
            attempt: attempt,
            jitterRatio: Double.random(in: -0.2...0.2)
        )
        reconnectTask = Task { @MainActor [weak self] in
            guard let self, self.activeSignature == signature else { return }
            do {
                try await self.catchUpOrCorrectSnapshot(configuration: configuration, signature: signature)
            } catch {
                guard self.activeSignature == signature else { return }
            }
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard self.activeSignature == signature else { return }
            await self.startLiveSync(configuration: configuration, signature: signature)
        }
    }

    private func closeLocalSocketState() {
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        readerTask?.cancel()
        readerTask = nil
    }

    private func shouldRunSnapshotCorrection(
        for error: Error,
        configuration: SyncInboundConfiguration
    ) -> Bool {
        if let clientError = error as? SyncServerClientError,
           case .httpStatus(_, let code) = clientError {
            return code == "invalid_cursor"
        }
        guard let rustError = error as? RustCoreError else { return false }
        if rustError.code == "cursor_regression" ||
            rustError.code == "ordering_regression" ||
            rustError.code == "invalid_sync_event" ||
            rustError.code == "sync_identity_mismatch" {
            let cursor = (try? readProgress(configuration: configuration).cursor) ?? -1
            let failures = (deltaFailuresByCursor[cursor] ?? 0) + 1
            deltaFailuresByCursor[cursor] = failures
            return failures >= 3 || rustError.code == "cursor_regression" || rustError.code == "sync_identity_mismatch"
        }
        return false
    }

    private func readProgress(configuration: SyncInboundConfiguration) throws -> RustSyncProgressResult {
        try rustResult(rustClient.getSyncProgress(
            appSupportDirectory: configuration.appSupportURL,
            syncID: configuration.syncID,
            deviceID: configuration.deviceID
        ))
    }

    private func rustResult<T>(_ result: Result<T, RustCoreError>) throws -> T {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    private func assertActive(_ signature: String) throws {
        guard activeSignature == signature else {
            throw SyncInboundCoordinatorError.staleSignature
        }
    }

    func activateForTesting(configuration: SyncInboundConfiguration) {
        stop()
        activeConfiguration = configuration
        activeSignature = configuration.signature
    }

    func handleSocketTextForTesting(
        _ text: String,
        configuration: SyncInboundConfiguration
    ) async throws {
        let signature = configuration.signature
        do {
            try await handleSocketText(text, configuration: configuration, signature: signature)
        } catch {
            recover(configuration: configuration, signature: signature)
            throw error
        }
    }
}

private enum SyncWebSocketMessage {
    case hello
    case catchupRequired
    case eventBatch(SyncWebSocketEventBatch)
    case error(String)
    case unknown

    init(text: String) throws {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        let base = try decoder.decode(SyncWebSocketBaseMessage.self, from: data)
        switch base.type {
        case "hello":
            self = .hello
        case "catchup_required":
            self = .catchupRequired
        case "event_batch":
            self = .eventBatch(try decoder.decode(SyncWebSocketEventBatch.self, from: data))
        case "error":
            self = .error((try? decoder.decode(SyncWebSocketErrorMessage.self, from: data).code) ?? "unknown")
        default:
            self = .unknown
        }
    }
}

private struct SyncWebSocketBaseMessage: Decodable {
    let type: String
}

private struct SyncWebSocketErrorMessage: Decodable {
    let code: String
}

private struct SyncWebSocketEventBatch: Decodable {
    let batchID: String
    let fromSeq: Int64
    let toSeq: Int64
    let events: [SyncPulledEventRecord]

    private enum CodingKeys: String, CodingKey {
        case batchID = "batch_id"
        case fromSeq = "from_seq"
        case toSeq = "to_seq"
        case events
    }
}

private func normalizedServerURL(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        .lowercased()
}
