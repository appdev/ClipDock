import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardListCoordinatorTests {
    @Test
    @MainActor
    func updateQueryDebouncesBeforeLoading() async {
        let sleepGate = SleepGate()
        let requests = QueryRecorder()
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 1,
            sleep: { _ in await sleepGate.wait() },
            pageLoader: { query in
                await requests.record(query)
                return .success(RustCoreListResult(
                    items: [],
                    totalCount: 0,
                    hasMore: false
                ))
            },
            mutationPerformer: { _ in
                .success(RustItemManagementResult(affectedCount: 0))
            }
        )

        coordinator.updateQuery(searchText: "report", itemType: "file", sourceAppID: nil)
        await Task.yield()
        #expect(await requests.values().isEmpty)

        await sleepGate.release()
        #expect(await waitUntil { await requests.values().count == 1 })
        #expect(await requests.values()[0] == ClipboardListQuery(
            limit: 2,
            offset: 0,
            itemType: "file",
            sourceAppID: nil,
            normalizedSearch: "report"
        ))
    }

    @Test
    @MainActor
    func refreshPrefetchesNextPageAndLoadMoreConsumesIt() async {
        let requests = QueryRecorder()
        var updates: [ClipboardListUpdate] = []
        let firstPage = [
            makeItem(id: "a"),
            makeItem(id: "b")
        ]
        let secondPage = [
            makeItem(id: "c")
        ]

        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await requests.record(query)
                if query.offset == 0 {
                    return .success(RustCoreListResult(
                        items: firstPage,
                        totalCount: 3,
                        hasMore: true
                    ))
                }

                return .success(RustCoreListResult(
                    items: secondPage,
                    totalCount: 3,
                    hasMore: false
                ))
            },
            mutationPerformer: { _ in
                .success(RustItemManagementResult(affectedCount: 0))
            }
        )
        coordinator.onListUpdate = { updates.append($0) }

        coordinator.refresh()

        #expect(await waitUntil { await requests.values().count == 2 })
        #expect(updates.count == 1)
        #expect(await requests.values().map(\.offset) == [0, 2])
        #expect(coordinator.loadedItemCount == 2)

        coordinator.loadMore()

        #expect(await waitUntil { updates.count == 2 })
        #expect(await requests.values().map(\.offset) == [0, 2])
        #expect(coordinator.loadedItemCount == 3)
        #expect(coordinator.isLoadingMore == false)

        guard case .success(let appendedPage) = updates[1].result else {
            Issue.record("expected appended success result")
            return
        }
        #expect(updates[1].append)
        #expect(appendedPage.items.map(\.id) == ["c"])
    }

    @Test
    @MainActor
    func newerRefreshIgnoresOlderInFlightResult() async {
        let gate = QueryResultGate()
        var updates: [ClipboardListUpdate] = []
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await gate.wait(for: "\(query.offset)|\(query.normalizedSearch)")
            },
            mutationPerformer: { _ in
                .success(RustItemManagementResult(affectedCount: 0))
            }
        )
        coordinator.onListUpdate = { updates.append($0) }

        coordinator.updateQuery(searchText: "first", itemType: nil, sourceAppID: nil)
        let registeredFirst = await waitUntil { await gate.registeredCount() == 1 }
        #expect(registeredFirst)
        guard registeredFirst else { return }

        coordinator.updateQuery(searchText: "second", itemType: nil, sourceAppID: nil)

        let registeredSecond = await waitUntil { await gate.registeredCount() == 2 }
        #expect(registeredSecond)
        guard registeredSecond else { return }

        await gate.release(
            key: "0|second",
            result: .success(RustCoreListResult(
                items: [makeItem(id: "second")],
                totalCount: 1,
                hasMore: false
            ))
        )

        let didApplyLatest = await waitUntil { updates.count == 1 }
        #expect(didApplyLatest)
        guard didApplyLatest else { return }
        guard case .success(let firstAppliedResult) = updates[0].result else {
            Issue.record("expected success result for latest query")
            return
        }
        #expect(firstAppliedResult.items.map(\.id) == ["second"])

        await gate.release(
            key: "0|first",
            result: .success(RustCoreListResult(
                items: [makeItem(id: "first")],
                totalCount: 1,
                hasMore: false
            ))
        )

        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(updates.count == 1)
    }

    @Test
    @MainActor
    func performMutationReportsStatusAndRefreshesList() async {
        var statusTexts: [String] = []
        let requests = QueryRecorder()
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await requests.record(query)
                return .success(RustCoreListResult(
                    items: [makeItem(id: "remaining")],
                    totalCount: 1,
                    hasMore: false
                ))
            },
            mutationPerformer: { mutation in
                #expect(mutation == .delete(itemID: "item-1"))
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onStatusTextChanged = { statusTexts.append($0) }

        coordinator.performMutation(.delete(itemID: "item-1"))

        #expect(await waitUntil {
            statusTexts.contains("条目：已删除")
                && statusTexts.contains("存储：已连接（1 条）")
        })
        #expect(await requests.values().count == 1)
        #expect(await requests.values()[0].offset == 0)
    }
}

private actor QueryRecorder {
    private var queries: [ClipboardListQuery] = []

    func record(_ query: ClipboardListQuery) {
        queries.append(query)
    }

    func values() -> [ClipboardListQuery] {
        queries
    }
}

private actor QueryResultGate {
    private var continuations: [String: CheckedContinuation<Result<RustCoreListResult, RustCoreError>, Never>] = [:]

    func wait(for key: String) async -> Result<RustCoreListResult, RustCoreError> {
        await withCheckedContinuation { continuation in
            continuations[key] = continuation
        }
    }

    func registeredCount() -> Int {
        continuations.count
    }

    func release(
        key: String,
        result: Result<RustCoreListResult, RustCoreError>
    ) {
        continuations.removeValue(forKey: key)?.resume(returning: result)
    }
}

private actor SleepGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func waitUntil(
    attempts: Int = 80,
    _ condition: @escaping @MainActor () async -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await condition()
}

private func makeItem(id: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "text",
        summary: id,
        primaryText: id,
        contentHash: "hash-\(id)",
        sourceAppId: nil,
        sourceAppName: nil,
        sourceAppIconPath: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 1,
        previewState: "ready"
    )
}
