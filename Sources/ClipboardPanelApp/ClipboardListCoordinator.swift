import Foundation

public struct ClipboardListQuery: Equatable, Sendable {
    public let limit: Int64
    public let offset: Int64
    public let itemType: String?
    public let sourceAppID: String?
    public let normalizedSearch: String

    public init(
        limit: Int64,
        offset: Int64,
        itemType: String?,
        sourceAppID: String?,
        normalizedSearch: String
    ) {
        self.limit = limit
        self.offset = offset
        self.itemType = itemType
        self.sourceAppID = sourceAppID
        self.normalizedSearch = normalizedSearch
    }

    public var isFiltered: Bool {
        itemType != nil || sourceAppID != nil || !normalizedSearch.isEmpty
    }
}

public struct ClipboardListUpdate: Sendable {
    public let result: Result<RustCoreListResult, RustCoreError>
    public let isFiltered: Bool
    public let append: Bool

    public init(
        result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool
    ) {
        self.result = result
        self.isFiltered = isFiltered
        self.append = append
    }
}

public enum ClipboardItemMutationRequest: Sendable, Equatable {
    case setPinned(itemID: String, isPinned: Bool)
    case delete(itemID: String)
    case clear(itemType: String?, sourceAppID: String?, normalizedSearch: String)
}

public typealias ClipboardListPageLoader =
    @Sendable (ClipboardListQuery) async -> Result<RustCoreListResult, RustCoreError>
public typealias ClipboardItemMutationPerformer =
    @Sendable (ClipboardItemMutationRequest) async -> Result<RustItemManagementResult, RustCoreError>

public actor ClipboardCoreDatabaseWorker {
    public init() {}

    public func listItems(
        client: RustCoreClient,
        appSupportURL: URL,
        query: ClipboardListQuery
    ) -> Result<RustCoreListResult, RustCoreError> {
        client.listItems(
            appSupportDirectory: appSupportURL,
            limit: query.limit,
            offset: query.offset,
            itemType: query.itemType,
            sourceAppId: query.sourceAppID,
            searchText: query.normalizedSearch.isEmpty ? nil : query.normalizedSearch
        )
    }

    public func performMutation(
        client: RustCoreClient,
        appSupportURL: URL,
        mutation: ClipboardItemMutationRequest
    ) -> Result<RustItemManagementResult, RustCoreError> {
        switch mutation {
        case .setPinned(let itemID, let isPinned):
            client.setItemPinned(
                appSupportDirectory: appSupportURL,
                itemId: itemID,
                isPinned: isPinned
            )

        case .delete(let itemID):
            client.deleteItem(appSupportDirectory: appSupportURL, itemId: itemID)

        case .clear(let itemType, let sourceAppID, let normalizedSearch):
            client.clearItems(
                appSupportDirectory: appSupportURL,
                itemType: itemType,
                sourceAppId: sourceAppID,
                searchText: normalizedSearch.isEmpty ? nil : normalizedSearch
            )
        }
    }
}

@MainActor
public final class ClipboardListCoordinator {
    private struct PrefetchedPage {
        let generation: Int
        let offset: Int64
        let result: Result<RustCoreListResult, RustCoreError>
    }

    public var onListUpdate: ((ClipboardListUpdate) -> Void)?
    public var onLoadingMoreChanged: ((Bool) -> Void)?
    public var onStatusTextChanged: ((String) -> Void)?

    private let pageSize: Int64
    private let debounceNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let pageLoader: ClipboardListPageLoader
    private let mutationPerformer: ClipboardItemMutationPerformer

    private var currentSearchText = ""
    private var currentItemType: String?
    private var currentSourceAppID: String?
    private var listRefreshGeneration = 0
    private var pendingListRefreshTask: Task<Void, Never>?
    private var pendingPrefetchTask: Task<Void, Never>?
    private var prefetchedPage: PrefetchedPage?
    private var prefetchingOffset: Int64?
    private var loadedItemCountStorage: Int64 = 0
    private var hasMoreItems = false
    private var isLoadingMoreStorage = false

    public init(
        pageSize: Int64 = 50,
        debounceNanoseconds: UInt64 = 120_000_000,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        pageLoader: @escaping ClipboardListPageLoader,
        mutationPerformer: @escaping ClipboardItemMutationPerformer
    ) {
        self.pageSize = pageSize
        self.debounceNanoseconds = debounceNanoseconds
        self.sleep = sleep
        self.pageLoader = pageLoader
        self.mutationPerformer = mutationPerformer
    }

    public var loadedItemCount: Int64 {
        loadedItemCountStorage
    }

    public var isLoadingMore: Bool {
        isLoadingMoreStorage
    }

    public func updateQuery(
        searchText: String,
        itemType: String?,
        sourceAppID: String?,
        debounce: Bool = true
    ) {
        currentSearchText = searchText
        currentItemType = itemType
        currentSourceAppID = sourceAppID
        refresh(debounce: debounce)
    }

    public func refresh(debounce: Bool = false) {
        guard pageSize > 0 else {
            setLoadingMore(false)
            return
        }

        listRefreshGeneration += 1
        let generation = listRefreshGeneration
        let query = makeQuery(limit: pageSize, offset: 0)
        let debounceNanoseconds = self.debounceNanoseconds
        let sleep = self.sleep
        let pageLoader = self.pageLoader

        pendingListRefreshTask?.cancel()
        pendingListRefreshTask = nil
        cancelPrefetch()
        loadedItemCountStorage = 0
        hasMoreItems = false
        setLoadingMore(false)

        pendingListRefreshTask = Task { [weak self, query, generation, debounce, debounceNanoseconds, sleep, pageLoader] in
            if debounce {
                try? await sleep(debounceNanoseconds)
                guard !Task.isCancelled else { return }
            }

            let result = await pageLoader(query)

            guard !Task.isCancelled,
                  let self,
                  generation == self.listRefreshGeneration
            else {
                return
            }

            self.pendingListRefreshTask = nil
            self.applyListResult(result, isFiltered: query.isFiltered, append: false)
        }
    }

    public func loadMore() {
        guard hasMoreItems, !isLoadingMoreStorage else {
            setLoadingMore(false)
            return
        }

        if consumePrefetchedPageIfAvailable() {
            return
        }

        guard pageSize > 0 else {
            setLoadingMore(false)
            return
        }

        let generation = listRefreshGeneration
        let query = makeQuery(limit: pageSize, offset: loadedItemCountStorage)
        let pageLoader = self.pageLoader

        setLoadingMore(true)

        if prefetchingOffset == query.offset {
            return
        }

        Task { [weak self, generation, query, pageLoader] in
            let result = await pageLoader(query)

            guard let self,
                  generation == self.listRefreshGeneration
            else {
                return
            }

            self.setLoadingMore(false)
            self.applyListResult(result, isFiltered: query.isFiltered, append: true)
        }
    }

    public func performMutation(_ mutation: ClipboardItemMutationRequest) {
        let mutationPerformer = self.mutationPerformer

        listRefreshGeneration += 1
        pendingListRefreshTask?.cancel()
        pendingListRefreshTask = nil
        cancelPrefetch()
        setLoadingMore(false)

        Task { [weak self, mutation, mutationPerformer] in
            let result = await mutationPerformer(mutation)
            guard let self else { return }

            switch result {
            case .success(let mutationResult):
                self.onStatusTextChanged?(self.statusText(for: mutation, result: mutationResult))
                self.refresh()

            case .failure(let error):
                self.onStatusTextChanged?("条目：\(error.code)")
            }
        }
    }

    public func seedPrefetchedLoadMoreForSmoke(
        firstPage: [RustClipboardItemSummary],
        prefetchedPage: [RustClipboardItemSummary],
        totalCount: Int64
    ) {
        currentSearchText = ""
        currentItemType = nil
        currentSourceAppID = nil
        listRefreshGeneration += 1
        pendingListRefreshTask?.cancel()
        pendingListRefreshTask = nil
        cancelPrefetch()
        loadedItemCountStorage = Int64(firstPage.count)
        hasMoreItems = true
        setLoadingMore(false)

        let firstResult = RustCoreListResult(
            items: firstPage,
            totalCount: totalCount,
            hasMore: true
        )
        onStatusTextChanged?("存储：已连接（\(totalCount) 条）")
        onListUpdate?(ClipboardListUpdate(
            result: .success(firstResult),
            isFiltered: false,
            append: false
        ))

        self.prefetchedPage = PrefetchedPage(
            generation: listRefreshGeneration,
            offset: Int64(firstPage.count),
            result: .success(RustCoreListResult(
                items: prefetchedPage,
                totalCount: totalCount,
                hasMore: false
            ))
        )
    }

    public func consumeLoadMoreForSmoke() {
        loadMore()
    }

    private func makeQuery(limit: Int64, offset: Int64) -> ClipboardListQuery {
        ClipboardListQuery(
            limit: limit,
            offset: offset,
            itemType: currentItemType,
            sourceAppID: currentSourceAppID,
            normalizedSearch: currentSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func consumePrefetchedPageIfAvailable() -> Bool {
        guard let prefetchedPage,
              prefetchedPage.generation == listRefreshGeneration,
              prefetchedPage.offset == loadedItemCountStorage
        else {
            return false
        }

        self.prefetchedPage = nil
        setLoadingMore(false)
        applyListResult(
            prefetchedPage.result,
            isFiltered: isCurrentListFiltered(),
            append: true
        )
        return true
    }

    private func prefetchNextPageIfNeeded() {
        guard hasMoreItems, !isLoadingMoreStorage, pageSize > 0 else {
            return
        }

        let query = makeQuery(limit: pageSize, offset: loadedItemCountStorage)
        guard prefetchedPage?.offset != query.offset,
              prefetchingOffset != query.offset
        else {
            return
        }

        let generation = listRefreshGeneration
        let pageLoader = self.pageLoader

        pendingPrefetchTask?.cancel()
        pendingPrefetchTask = nil
        prefetchedPage = nil
        prefetchingOffset = query.offset

        pendingPrefetchTask = Task { [weak self, generation, query, pageLoader] in
            let result = await pageLoader(query)

            guard let self,
                  generation == self.listRefreshGeneration,
                  !Task.isCancelled
            else {
                return
            }

            self.pendingPrefetchTask = nil
            self.prefetchingOffset = nil

            guard self.loadedItemCountStorage == query.offset else {
                return
            }

            if self.isLoadingMoreStorage {
                self.setLoadingMore(false)
                self.applyListResult(
                    result,
                    isFiltered: self.isCurrentListFiltered(),
                    append: true
                )
            } else {
                self.prefetchedPage = PrefetchedPage(
                    generation: generation,
                    offset: query.offset,
                    result: result
                )
            }
        }
    }

    private func cancelPrefetch() {
        pendingPrefetchTask?.cancel()
        pendingPrefetchTask = nil
        prefetchedPage = nil
        prefetchingOffset = nil
    }

    private func isCurrentListFiltered() -> Bool {
        currentItemType != nil
            || currentSourceAppID != nil
            || !currentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyListResult(
        _ result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool
    ) {
        switch result {
        case .success(let list):
            onStatusTextChanged?("存储：已连接（\(list.totalCount) 条）")
            loadedItemCountStorage = append
                ? loadedItemCountStorage + Int64(list.items.count)
                : Int64(list.items.count)
            hasMoreItems = list.hasMore
            onListUpdate?(ClipboardListUpdate(
                result: .success(list),
                isFiltered: isFiltered,
                append: append
            ))
            prefetchNextPageIfNeeded()

        case .failure(let error):
            setLoadingMore(false)
            onStatusTextChanged?("查询：\(error.code)")
            onListUpdate?(ClipboardListUpdate(
                result: .failure(error),
                isFiltered: false,
                append: append
            ))
        }
    }

    private func setLoadingMore(_ isLoading: Bool) {
        isLoadingMoreStorage = isLoading
        onLoadingMoreChanged?(isLoading)
    }

    private func statusText(
        for mutation: ClipboardItemMutationRequest,
        result: RustItemManagementResult
    ) -> String {
        switch mutation {
        case .setPinned(_, let isPinned):
            return result.affectedCount > 0
                ? (isPinned ? "条目：已固定" : "条目：已取消固定")
                : "条目：未找到"

        case .delete:
            return result.affectedCount > 0 ? "条目：已删除" : "条目：未找到"

        case .clear:
            return result.affectedCount > 0
                ? "条目：已清理 \(result.affectedCount) 条"
                : "条目：没有可清理条目"
        }
    }
}
