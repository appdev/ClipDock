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

        coordinator.updateQuery(searchText: "report", sourceAppID: nil)
        await Task.yield()
        #expect(await requests.values().isEmpty)

        await sleepGate.release()
        #expect(await waitUntil { await requests.values().count == 1 })
        #expect(await requests.values()[0] == ClipboardListQuery(
            limit: 2,
            offset: 0,
            sourceAppID: nil,
            pinboardID: nil,
            normalizedSearch: "report"
        ))
    }

    @Test
    @MainActor
    func updateQueryCarriesPinboardID() async {
        let requests = QueryRecorder()
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
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

        coordinator.updateQuery(
            searchText: "",
            sourceAppID: nil,
            pinboardID: "default",
            debounce: false
        )

        #expect(await waitUntil { await requests.values().count == 1 })
        #expect(await requests.values()[0].pinboardID == "default")
        #expect(await requests.values()[0].isFiltered)
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
        let requests = QueryRecorder()
        let completedRequests = QueryRecorder()
        let firstRequestGate = SleepGate()
        var updates: [ClipboardListUpdate] = []
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await requests.record(query)
                if query.normalizedSearch == "first" {
                    await firstRequestGate.wait()
                }
                await completedRequests.record(query)

                return .success(RustCoreListResult(
                    items: [makeItem(id: query.normalizedSearch)],
                    totalCount: 1,
                    hasMore: false
                ))
            },
            mutationPerformer: { _ in
                .success(RustItemManagementResult(affectedCount: 0))
            }
        )
        coordinator.onListUpdate = { updates.append($0) }

        coordinator.updateQuery(searchText: "first", sourceAppID: nil, debounce: false)
        #expect(await waitUntil { await requests.values().count == 1 })

        coordinator.updateQuery(searchText: "second", sourceAppID: nil, debounce: false)
        #expect(await waitUntil(attempts: 400) { await requests.values().count == 2 })

        let didApplyLatest = await waitUntil(attempts: 400) { updates.count == 1 }
        #expect(didApplyLatest)
        guard didApplyLatest else {
            await firstRequestGate.release()
            return
        }
        guard case .success(let firstAppliedResult) = updates[0].result else {
            Issue.record("expected success result for latest query")
            await firstRequestGate.release()
            return
        }
        #expect(firstAppliedResult.items.map(\.id) == ["second"])

        await firstRequestGate.release()
        #expect(await waitUntil(attempts: 400) { await completedRequests.values().count == 2 })
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

    @Test
    @MainActor
    func recordCopiedMutationReportsStatusAndRefreshesList() async {
        var statusTexts: [String] = []
        let requests = QueryRecorder()
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await requests.record(query)
                return .success(RustCoreListResult(
                    items: [makeItem(id: "item-1")],
                    totalCount: 1,
                    hasMore: false
                ))
            },
            mutationPerformer: { mutation in
                #expect(mutation == .recordCopied(itemID: "item-1"))
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onStatusTextChanged = { statusTexts.append($0) }

        coordinator.performMutation(.recordCopied(itemID: "item-1"))

        #expect(await waitUntil {
            statusTexts.contains("复制：已更新最近时间")
                && statusTexts.contains("存储：已连接（1 条）")
        })
        #expect(await requests.values().count == 1)
        #expect(await requests.values()[0].offset == 0)
    }
}

struct PinboardCoordinatorTests {
    @Test
    @MainActor
    func deleteStatusAvoidsZeroItemCountForEmptyPinboard() async {
        var statusTexts: [String] = []
        let coordinator = PinboardCoordinator { mutation in
            #expect(mutation == .delete(pinboardID: "board-1"))
            return .success(RustItemManagementResult(affectedCount: 0))
        }
        coordinator.onStatusTextChanged = { statusTexts.append($0) }

        coordinator.performMutation(.delete(pinboardID: "board-1"))

        #expect(await waitUntil {
            statusTexts.contains("Pinboard：已删除")
        })
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

private actor SleepGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation(isolation: self) { continuation in
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
