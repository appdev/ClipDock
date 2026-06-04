import Foundation
import Testing
@testable import ClipboardPanelApp

struct SyncInboundCoordinatorTests {
    @Test
    func reconnectBackoffCapsAtFiveMinutes() {
        #expect(SyncInboundTiming.reconnectDelayNanoseconds(attempt: 0, jitterRatio: 0) == 5_000_000_000)
        #expect(SyncInboundTiming.reconnectDelayNanoseconds(attempt: 1, jitterRatio: 0) == 10_000_000_000)
        #expect(SyncInboundTiming.reconnectDelayNanoseconds(attempt: 10, jitterRatio: 0) == 300_000_000_000)
    }

    @Test
    func configurationSignatureNormalizesURLAndDoesNotExposeToken() {
        let appSupportURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClipDockSyncSignature", isDirectory: true)
        let configuration = SyncInboundConfiguration(
            serverURL: "HTTPS://ClipDock.example.com/",
            token: "cds_secret_token",
            syncID: "sync_a",
            deviceID: "dev_a",
            appSupportURL: appSupportURL
        )

        #expect(configuration.signature.contains("https://clipdock.example.com"))
        #expect(!configuration.signature.contains("cds_secret_token"))
        #expect(configuration.signature.contains("sync_a"))
        #expect(configuration.signature.contains("dev_a"))
    }

    @MainActor
    @Test
    func malformedMessageTriggersImmediateHTTPCatchUp() async throws {
        let rust = MockInboundRustCoreClient(cursor: 5)
        let server = MockInboundServerClient()
        var ackPayloads: [String] = []
        let coordinator = SyncInboundCoordinator(
            rustClient: rust,
            syncClient: server,
            ackSender: { payload in ackPayloads.append(payload) },
            onItemsChanged: { _ in }
        )
        let configuration = testConfiguration()
        coordinator.activateForTesting(configuration: configuration)

        await #expect(throws: Error.self) {
            try await coordinator.handleSocketTextForTesting("{", configuration: configuration)
        }
        await waitUntil { server.pulledAfterSeqs == [5] && rust.appliedEventCounts == [0] }

        #expect(server.pulledAfterSeqs == [5])
        #expect(rust.appliedEventCounts == [0])
        #expect(ackPayloads.isEmpty)
    }

    @MainActor
    @Test
    func applyFailureDoesNotAckAndTriggersImmediateHTTPCatchUp() async throws {
        let rust = MockInboundRustCoreClient(cursor: 7)
        rust.failNextNonEmptyApply = true
        let server = MockInboundServerClient()
        var ackPayloads: [String] = []
        let coordinator = SyncInboundCoordinator(
            rustClient: rust,
            syncClient: server,
            ackSender: { payload in ackPayloads.append(payload) },
            onItemsChanged: { _ in }
        )
        let configuration = testConfiguration()
        coordinator.activateForTesting(configuration: configuration)

        await #expect(throws: Error.self) {
            try await coordinator.handleSocketTextForTesting(eventBatchJSON(seq: 8), configuration: configuration)
        }
        await waitUntil { server.pulledAfterSeqs == [7] && rust.appliedEventCounts == [1, 0] }

        #expect(ackPayloads.isEmpty)
        #expect(server.pulledAfterSeqs == [7])
        #expect(rust.appliedEventCounts == [1, 0])
    }

    @MainActor
    @Test
    func eventBatchAcksOnlyAfterSuccessfulApply() async throws {
        let rust = MockInboundRustCoreClient(cursor: 10)
        let server = MockInboundServerClient()
        var ackPayloads: [String] = []
        let coordinator = SyncInboundCoordinator(
            rustClient: rust,
            syncClient: server,
            ackSender: { payload in ackPayloads.append(payload) },
            onItemsChanged: { _ in }
        )
        let configuration = testConfiguration()
        coordinator.activateForTesting(configuration: configuration)

        try await coordinator.handleSocketTextForTesting(eventBatchJSON(seq: 11), configuration: configuration)

        #expect(rust.appliedEventCounts == [1])
        #expect(ackPayloads == [#"{"type":"ack","server_seq":11}"#])
        #expect(server.pulledAfterSeqs.isEmpty)
    }
}

private final class MockInboundRustCoreClient: SyncInboundRustCoreClient, @unchecked Sendable {
    var cursor: Int64
    var failNextNonEmptyApply = false
    var appliedEventCounts: [Int] = []

    init(cursor: Int64) {
        self.cursor = cursor
    }

    func getSyncProgress(
        appSupportDirectory: URL,
        syncID: String,
        deviceID: String
    ) -> Result<RustSyncProgressResult, RustCoreError> {
        .success(RustSyncProgressResult(cursor: cursor, snapshotSeq: 0))
    }

    func applySyncEvents(
        appSupportDirectory: URL,
        request: RustSyncApplyEventsRequest
    ) -> Result<RustSyncApplyResult, RustCoreError> {
        appliedEventCounts.append(request.events.count)
        if failNextNonEmptyApply && !request.events.isEmpty {
            failNextNonEmptyApply = false
            return .failure(RustCoreError(
                code: "invalid_sync_event",
                messageKey: "clipboard.error.sync_invalid_event",
                recoverable: true,
                message: "invalid_sync_event"
            ))
        }
        cursor = max(cursor, request.nextCursor)
        return .success(RustSyncApplyResult(
            cursor: request.nextCursor,
            snapshotSeq: 0,
            changedItemIds: request.events.isEmpty ? [] : ["item_changed"]
        ))
    }

    func applySyncSnapshot(
        appSupportDirectory: URL,
        request: RustSyncApplySnapshotRequest
    ) -> Result<RustSyncApplyResult, RustCoreError> {
        cursor = request.snapshotSeq
        return .success(RustSyncApplyResult(cursor: request.snapshotSeq, snapshotSeq: request.snapshotSeq, changedItemIds: []))
    }

    func markSyncLocalPending(
        appSupportDirectory: URL,
        request: RustSyncLocalPendingRequest
    ) -> Result<RustItemManagementResult, RustCoreError> {
        .success(RustItemManagementResult(affectedCount: 1))
    }
}

private final class MockInboundServerClient: SyncInboundServerClient, @unchecked Sendable {
    var pulledAfterSeqs: [Int64] = []
    var snapshotsRequested = 0

    func pullEvents(
        serverURL: String,
        token: String,
        afterSeq: Int64,
        limit: Int64
    ) async throws -> SyncPullEventsResult {
        pulledAfterSeqs.append(afterSeq)
        return SyncPullEventsResult(events: [], nextCursor: afterSeq)
    }

    func snapshot(
        serverURL: String,
        token: String
    ) async throws -> SyncSnapshotResult {
        snapshotsRequested += 1
        return SyncSnapshotResult(snapshotSeq: 1, items: [], tombstones: [])
    }

    func webSocketURL(serverURL: String, cursor: Int64) throws -> URL {
        URL(string: "ws://clipdock.test/v2/ws?cursor=\(cursor)&protocol_version=2")!
    }
}

private func testConfiguration() -> SyncInboundConfiguration {
    SyncInboundConfiguration(
        serverURL: "http://clipdock.test",
        token: "cds_test",
        syncID: "sync_a",
        deviceID: "dev_a",
        appSupportURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
}

private func eventBatchJSON(seq: Int64) -> String {
    """
    {
      "type": "event_batch",
      "batch_id": "sync_a:\(seq):\(seq)",
      "from_seq": \(seq),
      "to_seq": \(seq),
      "events": [
        {
          "server_seq": \(seq),
          "device_id": "dev_android",
          "client_event_id": "android-\(seq)",
          "type": "item_upsert",
          "content_hash": "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "item_type": "text",
          "payload": {"text": "hello", "source_platform": "android"},
          "copy_count_delta": 1,
          "created_at_ms": 1000
        }
      ]
    }
    """
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 500_000_000,
    predicate: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if predicate() { return }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
