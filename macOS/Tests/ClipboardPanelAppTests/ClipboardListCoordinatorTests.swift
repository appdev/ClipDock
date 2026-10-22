import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardListCoordinatorTests {
    @Test(arguments: [WindowRefreshFixture.Change.insert, .reorder, .continuousReorder])
    @MainActor
    fileprivate func refreshRestartsOverlappingPagesAndBoundsRetries(change: WindowRefreshFixture.Change) async {
        let fixture = WindowRefreshFixture(count: 350, changeBetweenPages: change)
        var updates: [ClipboardListUpdate] = []
        let coordinator = ClipboardListCoordinator(
            pageSize: 200, debounceNanoseconds: 0,
            pageLoader: { await fixture.load($0) },
            mutationPerformer: { _ in
                await fixture.mutate()
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onListUpdate = { updates.append($0) }
        coordinator.updateQuery(searchText: "term", sourceAppID: nil, debounce: false)
        #expect(await waitUntil { coordinator.loadedItemCount == 200 })
        coordinator.loadMore()
        #expect(await waitUntil { coordinator.loadedItemCount == 350 })
        let before = updates.count
        coordinator.performMutation(.recordCopied(itemID: "item-349"))
        #expect(await waitUntil { updates.count == before + 1 })
        if change == .continuousReorder {
            if case .failure(let error) = updates.last?.result {
                #expect(error.code == "query_changed")
                #expect(error.recoverable)
            } else {
                Issue.record("continually changing pages must not publish partial or duplicate items")
            }
            #expect(await fixture.refreshQueries.count == 6)
        } else {
            let result = try? updates.last?.result.get()
            let ids = result?.items.map(\.id) ?? []
            let expectedIDs = await fixture.firstIDs(350)
            #expect(ids == expectedIDs)
            #expect(ids.count == 350)
            #expect(Set(ids).count == ids.count)
            // The inserted 351st row may trigger the normal post-refresh prefetch.
            let refreshOffsets = await fixture.refreshQueries.map(\.offset).filter { $0 < 350 }
            #expect(refreshOffsets == [0, 200, 0, 200])
        }
        #expect(coordinator.loadedItemCount == 350)
    }

    @Test(arguments: [250, 350, 450])
    @MainActor
    func mutationRefreshPreservesWindowsLargerThanCorePageLimit(count: Int) async {
        let fixture = WindowRefreshFixture(count: count)
        var updates: [ClipboardListUpdate] = []
        let coordinator = ClipboardListCoordinator(
            pageSize: 100,
            debounceNanoseconds: 0,
            pageLoader: { await fixture.load($0) },
            mutationPerformer: { _ in
                await fixture.mutate()
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onListUpdate = { updates.append($0) }
        coordinator.updateQuery(searchText: "term", itemType: "text", sourceAppID: "source", pinboardID: "board", debounce: false)
        #expect(await waitUntil { coordinator.loadedItemCount == 100 })
        while coordinator.loadedItemCount < count {
            let expected = min(Int64(count), coordinator.loadedItemCount + 100)
            coordinator.loadMore()
            guard await waitUntil({ coordinator.loadedItemCount == expected }) else {
                Issue.record("initial pagination did not finish")
                return
            }
        }
        let before = updates.count
        coordinator.performMutation(.recordCopied(itemID: "item-\(count - 1)"))
        #expect(await waitUntil { updates.count == before + 1 })
        let result = try? updates.last?.result.get()
        #expect(result?.items.map(\.id) == ["item-\(count - 1)"] + (0..<(count - 1)).map { "item-\($0)" })
        #expect(coordinator.loadedItemCount == count)
        #expect(updates.last?.preserveScrollPositionOnStructuralChange == true)
        let refreshQueries = await fixture.refreshQueries
        #expect(refreshQueries.map(\.offset) == stride(from: 0, to: count, by: 200).map(Int64.init))
        #expect(refreshQueries.allSatisfy { $0.limit <= 200 && $0.scope == ClipboardListScope(itemType: "text", sourceAppID: "source", pinboardID: "board", normalizedSearch: "term") })
    }

    @Test(arguments: [false, true])
    @MainActor
    func interruptedWindowRefreshNeverPublishesPartialSuccess(failSecondPage: Bool) async {
        let fixture = WindowRefreshFixture(count: 350, pausesSecondPage: true, failsSecondPage: failSecondPage)
        var updates: [ClipboardListUpdate] = []
        let coordinator = ClipboardListCoordinator(
            pageSize: 200, debounceNanoseconds: 0,
            pageLoader: { await fixture.load($0) },
            mutationPerformer: { _ in
                await fixture.mutate()
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onListUpdate = { updates.append($0) }
        coordinator.updateQuery(searchText: "term", sourceAppID: nil, debounce: false)
        #expect(await waitUntil { coordinator.loadedItemCount == 200 })
        coordinator.loadMore()
        #expect(await waitUntil { coordinator.loadedItemCount == 350 })
        let before = updates.count
        coordinator.performMutation(.recordCopied(itemID: "item-349"))
        #expect(await waitUntil { await fixture.isPaused })
        coordinator.loadMore()
        await Task.yield()
        #expect(await fixture.refreshQueries.count == 2)
        #expect(updates.count == before)
        if !failSecondPage {
            coordinator.updateQuery(searchText: "new", sourceAppID: nil, debounce: false)
            #expect(await waitUntil { updates.count == before + 1 })
        }
        await fixture.release()
        if failSecondPage {
            #expect(await waitUntil { updates.count == before + 1 })
            if case .success = updates.last?.result { Issue.record("partial refresh must not succeed") }
            #expect(coordinator.loadedItemCount == 350)
        } else {
            #expect(await waitUntil { await fixture.secondPageFinished })
            await Task.yield()
            #expect(updates.count == before + 1)
            #expect(updates.last?.scope.normalizedSearch == "new")
        }
    }

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
    func updateQueryCarriesItemTypeWithSearchAndPinboard() async {
        let requests = QueryRecorder()
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await requests.record(query)
                return .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false))
            },
            mutationPerformer: { _ in
                .success(RustItemManagementResult(affectedCount: 0))
            }
        )

        coordinator.updateQuery(
            searchText: " #FF00AA ",
            itemType: "color",
            sourceAppID: "source-app",
            pinboardID: "board",
            debounce: false
        )

        #expect(await waitUntil { await requests.values().count == 1 })
        let query = await requests.values()[0]
        #expect(query.itemType == "color")
        #expect(query.sourceAppID == "source-app")
        #expect(query.pinboardID == "board")
        #expect(query.normalizedSearch == "#FF00AA")
        #expect(query.scope == ClipboardListScope(
            itemType: "color",
            sourceAppID: "source-app",
            pinboardID: "board",
            normalizedSearch: "#FF00AA"
        ))
        #expect(query.isFiltered)
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
    func pinboardMembershipMutationDoesNotRefreshClipboardScopeAfterLoadMore() async {
        let requests = QueryRecorder()
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
            mutationPerformer: { mutation in
                #expect(mutation == .setPinboardMembership(
                    itemID: "c",
                    pinboardID: "default",
                    isMember: true
                ))
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )

        coordinator.refresh()
        #expect(await waitUntil { await requests.values().count == 2 })

        coordinator.loadMore()
        #expect(await waitUntil { coordinator.loadedItemCount == 3 })

        coordinator.performMutation(.setPinboardMembership(
            itemID: "c",
            pinboardID: "default",
            isMember: true
        ))

        await Task.yield()
        #expect(await requests.values().count == 2)
        #expect(coordinator.loadedItemCount == 3)
    }

    @Test
    @MainActor
    func pinboardMembershipMutationRefreshesCurrentPinboardScopeLoadedWindow() async {
        let requests = QueryRecorder()
        let firstPage = [
            makeItem(id: "a"),
            makeItem(id: "b")
        ]
        let secondPage = [
            makeItem(id: "c")
        ]
        let refreshedPinboardWindow = [
            makeItem(id: "a"),
            makeItem(id: "b"),
            makeItem(id: "c")
        ]
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await requests.record(query)
                if query.limit == 3 {
                    return .success(RustCoreListResult(
                        items: refreshedPinboardWindow,
                        totalCount: 3,
                        hasMore: false
                    ))
                }
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
            mutationPerformer: { mutation in
                #expect(mutation == .setPinboardMembership(
                    itemID: "c",
                    pinboardID: "default",
                    isMember: false
                ))
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )

        coordinator.updateQuery(
            searchText: "",
            sourceAppID: nil,
            pinboardID: "default",
            debounce: false
        )
        #expect(await waitUntil { await requests.values().count == 2 })

        coordinator.loadMore()
        #expect(await waitUntil { coordinator.loadedItemCount == 3 })

        coordinator.performMutation(.setPinboardMembership(
            itemID: "c",
            pinboardID: "default",
            isMember: false
        ))

        #expect(await waitUntil { await requests.values().count == 3 })
        let mutationRefreshQuery = await requests.values()[2]
        #expect(mutationRefreshQuery.pinboardID == "default")
        #expect(mutationRefreshQuery.offset == 0)
        #expect(mutationRefreshQuery.limit == 3)
        #expect(coordinator.loadedItemCount == 3)
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
                #expect(mutation == .delete(itemID: "item-1", pinboardID: nil))
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onStatusTextChanged = { statusTexts.append($0) }

        coordinator.performMutation(.delete(itemID: "item-1", pinboardID: nil))

        #expect(await waitUntil {
            statusTexts.contains("条目：已删除")
                && statusTexts.contains("存储：已连接（1 条）")
        })
        #expect(await requests.values().count == 1)
        #expect(await requests.values()[0].offset == 0)
    }

    @Test
    @MainActor
    func batchMutationSerializesRequestsReportsSuccessAndRefreshesOnce() async {
        var statusTexts: [String] = []
        var batchResults: [ClipboardItemBatchMutationResult] = []
        let requests = QueryRecorder()
        let mutations = MutationRecorder()
        let coordinator = ClipboardListCoordinator(
            pageSize: 3,
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
                await mutations.record(mutation)
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onStatusTextChanged = { statusTexts.append($0) }
        coordinator.onBatchMutationCompleted = { batchResults.append($0) }

        coordinator.performBatchMutation(
            [
                .delete(itemID: "a", pinboardID: nil),
                .delete(itemID: "b", pinboardID: nil)
            ],
            summaryKind: .delete(pinboardID: nil)
        )

        #expect(await waitUntil {
            let requestCount = await requests.values().count
            return batchResults.count == 1
                && statusTexts.contains("条目：已删除 2 项")
                && requestCount == 1
        })
        #expect(await mutations.values() == [
            .delete(itemID: "a", pinboardID: nil),
            .delete(itemID: "b", pinboardID: nil)
        ])
        #expect(batchResults[0].outcome == .success)
        #expect(batchResults[0].successfulRequests.count == 2)
        #expect(batchResults[0].failedRequests.isEmpty)
    }

    @Test
    @MainActor
    func batchMutationReportsPartialAndAllFailureWithoutSuccessfulRefresh() async {
        var partialResults: [ClipboardItemBatchMutationResult] = []
        var failureResults: [ClipboardItemBatchMutationResult] = []
        let partialRequests = QueryRecorder()
        let failureRequests = QueryRecorder()
        let partialCoordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await partialRequests.record(query)
                return .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false))
            },
            mutationPerformer: { mutation in
                if mutation == .delete(itemID: "b", pinboardID: nil) {
                    return .failure(RustCoreError(code: "missing", messageKey: "missing", recoverable: false, message: "missing"))
                }
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        partialCoordinator.onBatchMutationCompleted = { partialResults.append($0) }

        partialCoordinator.performBatchMutation(
            [
                .delete(itemID: "a", pinboardID: nil),
                .delete(itemID: "b", pinboardID: nil)
            ],
            summaryKind: .delete(pinboardID: nil)
        )

        #expect(await waitUntil {
            let requestCount = await partialRequests.values().count
            return partialResults.count == 1 && requestCount == 1
        })
        #expect(partialResults[0].outcome == .partialFailure)
        #expect(partialResults[0].successfulRequests == [.delete(itemID: "a", pinboardID: nil)])
        #expect(partialResults[0].failedRequests == [.delete(itemID: "b", pinboardID: nil)])

        let failureCoordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await failureRequests.record(query)
                return .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false))
            },
            mutationPerformer: { _ in
                .failure(RustCoreError(code: "db", messageKey: "db", recoverable: true, message: "db"))
            }
        )
        failureCoordinator.onBatchMutationCompleted = { failureResults.append($0) }

        failureCoordinator.performBatchMutation(
            [.delete(itemID: "a", pinboardID: nil)],
            summaryKind: .delete(pinboardID: nil)
        )

        #expect(await waitUntil { failureResults.count == 1 })
        #expect(failureResults[0].outcome == .failure)
        #expect(await failureRequests.values().isEmpty)
    }

    @Test
    @MainActor
    func batchMutationTreatsZeroAffectedSuccessAsPartialFailure() async {
        var statusTexts: [String] = []
        var batchResults: [ClipboardItemBatchMutationResult] = []
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
                if mutation == .delete(itemID: "missing", pinboardID: nil) {
                    return .success(RustItemManagementResult(affectedCount: 0))
                }
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onStatusTextChanged = { statusTexts.append($0) }
        coordinator.onBatchMutationCompleted = { batchResults.append($0) }

        coordinator.performBatchMutation(
            [
                .delete(itemID: "affected", pinboardID: nil),
                .delete(itemID: "missing", pinboardID: nil)
            ],
            summaryKind: .delete(pinboardID: nil)
        )

        #expect(await waitUntil {
            let requestCount = await requests.values().count
            return batchResults.count == 1
                && statusTexts.contains("条目：已处理 1/2 项")
                && requestCount == 1
        })
        #expect(batchResults[0].outcome == .partialFailure)
        #expect(batchResults[0].affectedCount == 1)
        #expect(batchResults[0].successfulRequests == [.delete(itemID: "affected", pinboardID: nil)])
        #expect(batchResults[0].failedRequests == [.delete(itemID: "missing", pinboardID: nil)])
        #expect(batchResults[0].zeroAffectedRequests == [.delete(itemID: "missing", pinboardID: nil)])
        #expect(batchResults[0].erroredRequests.isEmpty)
    }

    @Test
    @MainActor
    func batchMutationTreatsAllZeroAffectedSuccessesAsNotFoundWithoutRefresh() async {
        var statusTexts: [String] = []
        var batchResults: [ClipboardItemBatchMutationResult] = []
        let requests = QueryRecorder()
        let coordinator = ClipboardListCoordinator(
            pageSize: 2,
            debounceNanoseconds: 0,
            pageLoader: { query in
                await requests.record(query)
                return .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false))
            },
            mutationPerformer: { _ in
                .success(RustItemManagementResult(affectedCount: 0))
            }
        )
        coordinator.onStatusTextChanged = { statusTexts.append($0) }
        coordinator.onBatchMutationCompleted = { batchResults.append($0) }

        coordinator.performBatchMutation(
            [
                .delete(itemID: "missing-a", pinboardID: nil),
                .delete(itemID: "missing-b", pinboardID: nil)
            ],
            summaryKind: .delete(pinboardID: nil)
        )

        #expect(await waitUntil {
            batchResults.count == 1
                && statusTexts.contains("条目：未找到")
        })
        #expect(batchResults[0].outcome == .failure)
        #expect(batchResults[0].affectedCount == 0)
        #expect(batchResults[0].successfulRequests.isEmpty)
        #expect(batchResults[0].failedRequests == [
            .delete(itemID: "missing-a", pinboardID: nil),
            .delete(itemID: "missing-b", pinboardID: nil)
        ])
        #expect(batchResults[0].zeroAffectedRequests == [
            .delete(itemID: "missing-a", pinboardID: nil),
            .delete(itemID: "missing-b", pinboardID: nil)
        ])
        #expect(await requests.values().isEmpty)
    }

    @Test
    @MainActor
    func scopedDeleteReportsPinboardRemovalAndRefreshesCurrentPinboardScope() async {
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
                #expect(mutation == .delete(itemID: "item-1", pinboardID: "board-a"))
                return .success(RustItemManagementResult(affectedCount: 1))
            }
        )
        coordinator.onStatusTextChanged = { statusTexts.append($0) }

        coordinator.updateQuery(
            searchText: "",
            sourceAppID: nil,
            pinboardID: "board-a",
            debounce: false
        )
        #expect(await waitUntil { await requests.values().count == 1 })
        let initialRequestCount = await requests.values().count
        statusTexts.removeAll()

        coordinator.performMutation(.delete(itemID: "item-1", pinboardID: "board-a"))

        #expect(await waitUntil {
            let requestCount = await requests.values().count
            return statusTexts.contains("Pinboard：已移除")
                && requestCount > initialRequestCount
        })
        let mutationRefreshQuery = await requests.values().last
        #expect(mutationRefreshQuery?.pinboardID == "board-a")
        #expect(mutationRefreshQuery?.offset == 0)
    }

    @Test
    @MainActor
    func recordCopiedMutationReportsStatusAndRefreshesList() async {
        var statusTexts: [String] = []
        var listUpdates: [ClipboardListUpdate] = []
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
        coordinator.onListUpdate = { listUpdates.append($0) }

        coordinator.performMutation(.recordCopied(itemID: "item-1"))

        #expect(await waitUntil {
            statusTexts.contains("复制：已更新最近时间")
                && statusTexts.contains("存储：已连接（1 条）")
        })
        #expect(await requests.values().count == 1)
        #expect(await requests.values()[0].offset == 0)
        #expect(listUpdates.first?.preserveScrollPositionOnStructuralChange == true)
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

private actor WindowRefreshFixture {
    enum Change: Sendable { case insert, reorder, continuousReorder }
    private var items: [RustClipboardItemSummary]
    private var didMutate = false
    private let pausesSecondPage: Bool
    private let failsSecondPage: Bool
    private let changeBetweenPages: Change?
    private var didChangeBetweenPages = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var refreshQueries: [ClipboardListQuery] = []
    private(set) var isPaused = false
    private(set) var secondPageFinished = false

    init(count: Int, pausesSecondPage: Bool = false, failsSecondPage: Bool = false, changeBetweenPages: Change? = nil) {
        items = (0..<count).map { makeItem(id: "item-\($0)") }
        self.pausesSecondPage = pausesSecondPage
        self.failsSecondPage = failsSecondPage
        self.changeBetweenPages = changeBetweenPages
    }

    func mutate() {
        didMutate = true
        items.insert(items.removeLast(), at: 0)
    }

    func load(_ query: ClipboardListQuery) async -> Result<RustCoreListResult, RustCoreError> {
        if didMutate, query.normalizedSearch == "term" {
            refreshQueries.append(query)
            if query.offset == 200, let changeBetweenPages,
               !didChangeBetweenPages || changeBetweenPages == .continuousReorder {
                didChangeBetweenPages = true
                switch changeBetweenPages {
                case .insert: items.insert(makeItem(id: "new-item"), at: 0)
                case .reorder, .continuousReorder: items.insert(items.remove(at: 250), at: 0)
                }
            }
            if query.offset == 200, pausesSecondPage {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    isPaused = true
                }
                secondPageFinished = true
                if failsSecondPage {
                    return .failure(RustCoreError(code: "test_failure", messageKey: "test_failure", recoverable: true, message: "second page failed"))
                }
            }
        }
        let start = min(items.count, Int(query.offset))
        let end = min(items.count, start + Int(min(200, query.limit)))
        return .success(RustCoreListResult(items: Array(items[start..<end]), totalCount: Int64(items.count), hasMore: end < items.count))
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func firstIDs(_ count: Int) -> [String] { items.prefix(count).map(\.id) }
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

private actor MutationRecorder {
    private var mutations: [ClipboardItemMutationRequest] = []

    func record(_ mutation: ClipboardItemMutationRequest) {
        mutations.append(mutation)
    }

    func values() -> [ClipboardItemMutationRequest] {
        mutations
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
