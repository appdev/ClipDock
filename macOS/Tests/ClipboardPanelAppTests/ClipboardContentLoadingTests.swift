import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardContentLoadingTests {
    @Test
    func rustProjectionKeepsFullTextOutOfCardsAndLoadsItOnDemand() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = RustCoreClient()
        let text = "\u{200B}\n" + String(repeating: "a", count: 497) + "👨‍👩‍👧‍👦e\u{301}\r\nTAIL_SEARCH_TOKEN\u{200B}"
        _ = try client.captureText(appSupportDirectory: root, request: RustCaptureTextRequest(
            text: text, sourceBundleId: "test.projection", sourceAppName: "Fixture",
            sourceBundlePath: nil, sourceIconRelativePath: nil, sourceConfidence: "high",
            pasteboardChangeCount: 1
        )).get()
        let fullList = try client.listItems(appSupportDirectory: root).get()
        let projectedList = try client.listEntries(appSupportDirectory: root).get()
        let projected = try #require(projectedList.items.first)
        #expect(projectedList.items.map(\.id) == fullList.items.map(\.id))
        #expect(projectedList.totalCount == fullList.totalCount)
        #expect(projectedList.hasMore == fullList.hasMore)
        #expect(projected.primaryText == nil)
        #expect(!projected.isContentComplete)
        #expect(projected.previewTruncated)
        #expect((try #require(projected.textPreview) as NSString).length <= 500)
        #expect(projected.trimmedGraphemeCount == Int64(text.trimmingCharacters(in: .whitespacesAndNewlines).count))
        #expect(projected.scalarCount == Int64(text.unicodeScalars.count))
        #expect(PanelItemCardPresenter.presentation(for: projected).summaryText == projected.textPreview)
        #expect(ClipboardPastePayloadPlanner.payload(for: projected, appSupportDirectory: root) == .unsupported(reason: "content_not_loaded"))
        let searched = try client.listEntries(appSupportDirectory: root, searchText: "TAIL_SEARCH_TOKEN").get()
        #expect(searched.items.map(\.id) == [projected.id])

        let full = try #require(try client.getItem(appSupportDirectory: root, itemID: projected.id).get())
        #expect(full.isContentComplete)
        #expect(full.primaryText == text)
        #expect(ClipboardPastePayloadPlanner.plainTextPayload(for: full) == .text(text))
        #expect(ClipboardPreviewContentPlanner.preview(for: full, appSupportDirectory: root).body == text)
        let lookups = try client.getItems(appSupportDirectory: root, orderedIDs: [full.id, "missing", full.id]).get()
        #expect(lookups.map(\.itemID) == [full.id, "missing", full.id])
        #expect(lookups[1].item == nil)
        let worker = ClipboardCoreDatabaseWorker()
        let repeated = try await worker.loadCompleteItems(client: client, appSupportURL: root,
            orderedIDs: Array(repeating: full.id, count: 205)).get()
        #expect(repeated.count == 205)
        #expect(repeated.allSatisfy { $0.primaryText == text })
        let missing = await worker.loadCompleteItems(client: client, appSupportURL: root, orderedIDs: [full.id, "missing"])
        if case .failure(let error) = missing { #expect(error.code == "missing_item") }
        else { Issue.record("A missing selected item must fail the complete selection") }
    }

    @Test
    @MainActor
    func latestCopyWinsAndFreezesModeTargetAndOrder() async throws {
        let coordinator = ClipboardCopyIntentCoordinator()
        let loader = DeferredContentLoader()
        var writes: [[String]] = []
        let first = coordinator.begin(itemIDs: ["A"], mode: .original,
            pasteDirectlyToTarget: true, targetProcessIdentifier: 10)
        let firstTask = Task { @MainActor in
            if let result = await coordinator.resolve(first, loader: { await loader.load($0) }),
               case .success(let items) = result { writes.append(items.map(\.id)) }
        }
        #expect(await waitForContentCondition { await loader.hasPending("A") })
        let second = coordinator.begin(itemIDs: ["B", "B"], mode: .explicitPlainText,
            pasteDirectlyToTarget: false, targetProcessIdentifier: 20)
        let secondTask = Task { @MainActor in
            if let result = await coordinator.resolve(second, loader: { await loader.load($0) }),
               case .success(let items) = result { writes.append(items.map(\.id)) }
        }
        #expect(await waitForContentCondition { await loader.hasPending("B") })
        await loader.finish("B", items: [contentFixture("B"), contentFixture("B")])
        await secondTask.value
        await loader.finish("A", items: [contentFixture("A")])
        await firstTask.value
        #expect(writes == [["B", "B"]])
        #expect(second.mode == .explicitPlainText)
        #expect(second.targetProcessIdentifier == 20)
        #expect(!second.pasteDirectlyToTarget)
        #expect(coordinator.isCurrent(second)) // Auto-hide must leave delayed-paste intent alive.
        coordinator.cancel() // Explicit hide, path copy, or shutdown invalidates it.
        #expect(!coordinator.isCurrent(second))
    }

    @Test
    @MainActor
    func closingOrReceivingIncompleteContentNeverCallsWriter() async {
        let coordinator = ClipboardCopyIntentCoordinator()
        let loader = DeferredContentLoader()
        let intent = coordinator.begin(itemIDs: ["A"], mode: .original,
            pasteDirectlyToTarget: false, targetProcessIdentifier: nil)
        let pending = Task { await coordinator.resolve(intent, loader: { await loader.load($0) }) }
        #expect(await waitForContentCondition { await loader.hasPending("A") })
        coordinator.cancel()
        await loader.finish("A", items: [contentFixture("A")])
        #expect(await pending.value == nil)
        for items in [[], [contentFixture("wrong")], [contentFixture("A", complete: false)]] {
            let next = coordinator.begin(itemIDs: ["A"], mode: .original,
                pasteDirectlyToTarget: false, targetProcessIdentifier: nil)
            let result = await coordinator.resolve(next, loader: { _ in .success(items) })
            if case .failure(let error) = result { #expect(error.code == "missing_item") }
            else { Issue.record("Only a complete ordered selection may reach a writer") }
        }
    }

    @Test
    func mutationChunksPreserveDuplicatesAndStopWithoutRetryAfterFault() {
        let requests = (0..<450).map { _ in ClipboardItemMutationRequest.recordCopied(itemID: "same") }
        var sizes: [Int] = []
        let error = RustItemMutationError(coreError: contentError())
        let result = ClipboardCoreDatabaseWorker.performMutationChunks(requests) { chunk in
            sizes.append(chunk.count)
            let failedChunk = sizes.count == 2
            return .success(RustItemBatchMutationResult(outcomes: chunk.indices.map { index in
                let status = !failedChunk || index < 2 ? "applied" : index == 2 ? "failed" : "not_attempted"
                return RustItemMutationOutcome(requestIndex: index, status: status,
                    affectedCount: status == "applied" ? 1 : 0, error: status == "applied" ? nil : error,
                    requiresRefresh: status != "not_attempted", committed: status == "applied" ? true : nil)
            }, sessionFault: failedChunk, terminationReason: failedChunk ? error : nil))
        }
        #expect(sizes == [200, 200])
        #expect(result.outcomes.map(\.requestIndex) == Array(0..<450))
        #expect(result.outcomes.filter { $0.status == "applied" }.count == 202)
        #expect(result.outcomes.last?.status == "not_attempted")
        #expect(result.sessionFault)
    }

    @Test
    func malformedMutationResponseDoesNotClaimNoCommitOrRetry() {
        let requests = (0..<250).map { _ in ClipboardItemMutationRequest.recordCopied(itemID: "same") }
        var calls = 0
        let result = ClipboardCoreDatabaseWorker.performMutationChunks(requests) { _ in
            calls += 1
            return .success(RustItemBatchMutationResult(outcomes: [], sessionFault: false, terminationReason: nil))
        }
        #expect(calls == 1)
        #expect(result.outcomes.count == 250)
        #expect(result.outcomes[0].status == "failed")
        #expect(result.outcomes[0].committed == nil)
        #expect(result.outcomes[0].requiresRefresh)
        #expect(result.outcomes[200].status == "not_attempted")
    }

    @Test
    func mutationDecodeFailureIsAnUnknownCommitAndStopsLaterChunks() {
        let requests = (0..<250).map { _ in ClipboardItemMutationRequest.recordCopied(itemID: "same") }
        var calls = 0
        let result = ClipboardCoreDatabaseWorker.performMutationChunks(requests) { _ in
            calls += 1
            return .failure(RustCoreError(code: "bridge_decode_failed", messageKey: "fixture",
                recoverable: true, message: "Malformed response after native mutation"))
        }
        #expect(calls == 1)
        #expect(result.outcomes[0].status == "failed")
        #expect(result.outcomes[0].committed == nil)
        #expect(result.outcomes[0].requiresRefresh)
        #expect(result.outcomes[200].status == "not_attempted")
        #expect(result.outcomes[200].committed == false)
    }

    @Test
    @MainActor
    func committedCleanupFailureUsesBatchAndStillRefreshes() async {
        var batches: [ClipboardItemBatchMutationResult] = []
        var updates = 0
        let coordinator = ClipboardListCoordinator(
            pageLoader: { _ in .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false)) },
            mutationPerformer: { _ in
                Issue.record("Configured batch path must not replay single mutations")
                return .failure(contentError())
            },
            batchMutationPerformer: { requests in
                #expect(requests.count == 1)
                return RustItemBatchMutationResult(outcomes: [RustItemMutationOutcome(
                    requestIndex: 0, status: "failed", affectedCount: 0,
                    error: RustItemMutationError(coreError: contentError()), requiresRefresh: true, committed: true
                )], sessionFault: false, terminationReason: nil)
            }
        )
        coordinator.onBatchMutationCompleted = { batches.append($0) }
        coordinator.onListUpdate = { _ in updates += 1 }
        coordinator.performBatchMutation([.delete(itemID: "A", pinboardID: nil)], summaryKind: .delete(pinboardID: nil))
        #expect(await waitForContentCondition { batches.count == 1 && updates == 1 })
        #expect(batches.first?.affectedCount == 0)
        #expect(batches.first?.requiresRefresh == true)
        #expect(batches.first?.erroredRequests.count == 1)
    }

    @Test
    func sameScopeRefreshFailurePreservesRowsButNewScopeFailureDoesNot() {
        let state = PanelListViewState(presentation: .items([contentFixture("A")]), totalCount: 1)
        let same = PanelListViewStateAdapter.listUpdate(current: state, result: .failure(contentError()),
            isFiltered: false, append: false)
        #expect(same.state.items.map(\.id) == ["A"])
        #expect(same.state.refreshError != nil)
        let changed = PanelListViewStateAdapter.listUpdate(current: state, result: .failure(contentError()),
            isFiltered: true, append: false, preservesItemsOnFailure: false)
        #expect(changed.state.presentation == .databaseError)
    }
}

private actor DeferredContentLoader {
    private var pending: [String: CheckedContinuation<Result<[RustClipboardItemSummary], RustCoreError>, Never>] = [:]
    func load(_ ids: [String]) async -> Result<[RustClipboardItemSummary], RustCoreError> {
        await withCheckedContinuation { pending[ids[0]] = $0 }
    }
    func hasPending(_ id: String) -> Bool { pending[id] != nil }
    func finish(_ id: String, items: [RustClipboardItemSummary]) {
        pending.removeValue(forKey: id)?.resume(returning: .success(items))
    }
}

@MainActor
private func waitForContentCondition(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

private func contentError() -> RustCoreError {
    RustCoreError(code: "fixture", messageKey: "fixture", recoverable: true, message: "Fixture error")
}

private func contentFixture(_ id: String, complete: Bool = true) -> RustClipboardItemSummary {
    RustClipboardItemSummary(id: id, itemType: "text", summary: id,
        primaryText: complete ? "full-\(id)" : nil, contentHash: id,
        sourceAppId: nil, sourceAppName: nil, sourceAppIconPath: nil,
        previewAssetPath: nil, payloadAssetPath: nil, sourceConfidence: "high",
        firstCopiedAtMs: 1, lastCopiedAtMs: 1, copyCount: 1, isPinned: false,
        sizeBytes: 6, previewState: "ready", textPreview: complete ? nil : "preview",
        previewTruncated: !complete, isContentComplete: complete)
}
