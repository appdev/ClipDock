import Foundation
import Testing
@testable import ClipboardPanelApp

struct SyncEventOutboxTests {
    @Test
    func normalizesBareBLAKE3HashForServerWhileKeepingLocalStatusLookup() async throws {
        let outbox = SyncEventOutbox(fileURL: try temporaryOutboxURL())
        let bareHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let event = SyncOutboxEvent(
            clientEventId: "macos-a",
            type: "item_upsert",
            contentHash: bareHash,
            itemType: "text",
            payload: ["text": .string("hello")],
            copyCountDelta: 1,
            createdAt: 1_000,
            nextAttemptAt: 1_000
        )

        await outbox.enqueue(event)
        let due = await outbox.dueBatch(nowMs: 1_000)
        #expect(due.map(\.contentHash) == ["blake3:\(bareHash)"])

        await outbox.fail(clientEventIds: ["macos-a"], nowMs: 2_000)
        let statuses = await outbox.itemStatusesByContentHash()
        #expect(statuses[bareHash] == .failed)
        #expect(statuses["blake3:\(bareHash)"] == .failed)

        #expect(await outbox.forceRetryUpserts(contentHash: bareHash, nowMs: 2_500))
        #expect(await outbox.allEvents()[0].nextAttemptAt == 2_500)
    }

    @Test
    func persistsEventsAndRestoresSendingEventsAsDuePendingWork() async throws {
        let fileURL = try temporaryOutboxURL()
        let outbox = SyncEventOutbox(fileURL: fileURL)
        let event = SyncOutboxEvent(
            clientEventId: "macos-a",
            type: "item_upsert",
            contentHash: "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            itemType: "text",
            payload: ["text": .string("hello")],
            copyCountDelta: 1,
            createdAt: 1_000,
            nextAttemptAt: 1_250
        )

        await outbox.enqueue(event)
        #expect(await outbox.dueBatch(nowMs: 1_249).isEmpty)
        let due = await outbox.dueBatch(nowMs: 1_250)
        #expect(due.map(\.clientEventId) == ["macos-a"])

        let restored = SyncEventOutbox(fileURL: fileURL)
        let loaded = await restored.load(nowMs: 2_000)

        #expect(loaded.count == 1)
        #expect(loaded[0].status == .pending)
        #expect(loaded[0].nextAttemptAt == 1_250)
    }

    @Test
    func failureBackoffUsesPlannedIntervalsAndForceRetryBypassesSchedule() async throws {
        let outbox = SyncEventOutbox(fileURL: try temporaryOutboxURL())
        let event = SyncOutboxEvent(
            clientEventId: "macos-a",
            type: "item_upsert",
            contentHash: "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            itemType: "text",
            payload: ["text": .string("hello")],
            copyCountDelta: 1,
            createdAt: 1_000,
            nextAttemptAt: 1_000
        )
        await outbox.enqueue(event)

        _ = await outbox.dueBatch(nowMs: 1_000)
        await outbox.fail(clientEventIds: ["macos-a"], nowMs: 2_000)
        var events = await outbox.allEvents()
        #expect(events[0].attemptCount == 1)
        #expect(events[0].status == .failed)
        #expect(events[0].nextAttemptAt == 7_000)
        #expect(await outbox.itemStatusesByContentHash()[event.contentHash] == .failed)

        await outbox.forceRetryUpserts(contentHash: event.contentHash, nowMs: 2_500)
        events = await outbox.allEvents()
        #expect(events[0].status == .pending)
        #expect(events[0].nextAttemptAt == 2_500)

        _ = await outbox.dueBatch(nowMs: 2_500)
        await outbox.fail(clientEventIds: ["macos-a"], nowMs: 3_000)
        events = await outbox.allEvents()
        #expect(events[0].attemptCount == 2)
        #expect(events[0].nextAttemptAt == 18_000)

        _ = await outbox.dueBatch(nowMs: 18_000)
        await outbox.fail(clientEventIds: ["macos-a"], nowMs: 18_000)
        events = await outbox.allEvents()
        #expect(events[0].attemptCount == 3)
        #expect(events[0].nextAttemptAt == 78_000)

        _ = await outbox.dueBatch(nowMs: 78_000)
        await outbox.fail(clientEventIds: ["macos-a"], nowMs: 78_000)
        events = await outbox.allEvents()
        #expect(events[0].attemptCount == 4)
        #expect(events[0].nextAttemptAt == 378_000)
    }

    @Test
    func completeRemovesSucceededEventsAndClearsItemStatus() async throws {
        let outbox = SyncEventOutbox(fileURL: try temporaryOutboxURL())
        let event = SyncOutboxEvent(
            clientEventId: "macos-a",
            type: "item_upsert",
            contentHash: "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            itemType: "text",
            payload: ["text": .string("hello")],
            copyCountDelta: 1,
            createdAt: 1_000,
            nextAttemptAt: 1_000
        )

        await outbox.enqueue(event)
        _ = await outbox.dueBatch(nowMs: 1_000)
        await outbox.complete(clientEventIds: ["macos-a"])

        #expect(await outbox.allEvents().isEmpty)
        #expect(await outbox.itemStatusesByContentHash().isEmpty)
    }

    private func temporaryOutboxURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipdock-sync-outbox-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sync-outbox.json", isDirectory: false)
    }
}
