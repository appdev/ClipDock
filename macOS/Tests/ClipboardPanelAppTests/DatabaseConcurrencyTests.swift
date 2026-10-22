import Foundation
import Testing
@testable import ClipboardPanelApp

struct DatabaseConcurrencyTests {
    @Test
    @MainActor
    func workerLeavesMainActorResponsiveAndSkipsCancelledQueuedQuery() async {
        let worker = ClipboardCoreDatabaseWorker()
        let (started, signalStarted) = AsyncStream<Void>.makeStream()
        let finish = DispatchSemaphore(value: 0)
        let blocked = Task {
            await worker.perform {
                signalStarted.yield(())
                signalStarted.finish()
                finish.wait()
                return Thread.isMainThread
            }
        }
        defer { finish.signal() }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        let unusedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cancelledQuery = Task {
            await worker.listItems(
                client: RustCoreClient(), appSupportURL: unusedDirectory,
                query: ClipboardListQuery(limit: 50, offset: 0, sourceAppID: nil, pinboardID: nil, normalizedSearch: "")
            )
        }
        cancelledQuery.cancel()
        // This executes on MainActor while the synchronous database worker is blocked.
        let heartbeat = Task { @MainActor in true }
        #expect(await heartbeat.value)
        finish.signal()
        #expect(await blocked.value == false)
        let result = await cancelledQuery.value
        if case .failure(let error) = result {
            #expect(error.code == "cancelled")
        } else {
            Issue.record("cancelled query must not enter the FFI")
        }
        #expect(!FileManager.default.fileExists(atPath: unusedDirectory.path))
    }

    @Test
    @MainActor
    func preferenceWritesRemainOrderedAcrossSuspension() async throws {
        let gate = PreferenceSaveGate()
        var saves: [Int64] = []
        let coordinator = PreferencesCoordinator(
            loadPreferencesOperation: { .success(RustPreferencesResult(schemaVersion: 17, preferences: RustPreferencesDocument())) },
            savePreferencesOperation: { preferences in
                saves.append(preferences.history.retentionDays)
                if preferences.history.retentionDays == 7 { await gate.wait() }
                return .success(RustPreferencesResult(schemaVersion: 17, preferences: preferences))
            },
            currentLaunchAtLoginState: { LaunchAtLoginPresentation(isOn: false, canChange: true, detail: "test") },
            setLaunchAtLoginEnabled: { enabled in .success(LaunchAtLoginPresentation(isOn: enabled, canChange: true, detail: "test")) },
            currentAccessibilityPermissionState: { AccessibilityPermissionPresentation(isTrusted: false, detail: "test", actionTitle: "test", canOpenSettings: false) },
            openAccessibilitySettings: {}
        )
        let first = Task { await coordinator.persist(RustPreferencesDocument(history: RustHistoryPreferences(retentionDays: 7))) }
        for _ in 0..<200 {
            if await gate.isWaiting { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate.isWaiting)
        let second = Task { await coordinator.persist(RustPreferencesDocument(history: RustHistoryPreferences(retentionDays: 90, retentionForever: true))) }
        await Task.yield()
        #expect(saves == [7])
        await gate.release()
        _ = try await first.value.get()
        _ = try await second.value.get()
        #expect(saves == [7, 90])
        #expect(coordinator.currentPreferences.history.retentionDays == 90)
        #expect(coordinator.currentPreferences.history.retentionForever)
    }

    @Test
    func historyPreferencesPreserveForeverAndDecodeOlderDocuments() throws {
        let decoder = JSONDecoder()
        let old = try decoder.decode(RustHistoryPreferences.self, from: Data("{\"retention_days\":30}".utf8))
        #expect(!old.retentionForever)
        let value = RustHistoryPreferences(retentionDays: 30, retentionForever: true)
        let decoded = try decoder.decode(RustHistoryPreferences.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        var selection = old
        selection.retentionSelection = Int64.max
        #expect(selection.retentionForever)
        #expect(selection.retentionDays == 30)
        #expect(selection.retentionSelection == Int64.max)
        selection.retentionSelection = 7
        #expect(!selection.retentionForever)
        #expect(selection.retentionDays == 7)
    }
}

private actor PreferenceSaveGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isWaiting = true
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
