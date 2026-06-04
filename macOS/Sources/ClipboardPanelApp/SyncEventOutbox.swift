import Foundation

public enum SyncEventPayloadValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int64)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .int(try container.decode(Int64.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

public enum SyncOutboxEventStatus: String, Codable, Equatable, Sendable {
    case pending
    case sending
    case failed
}

public enum PanelItemSyncStatus: String, Codable, Equatable, Sendable {
    case none
    case sending
    case failed
}

public struct SyncOutboxAssetRegistration: Codable, Equatable, Sendable {
    public let filePath: String
    public let kind: String
    public let mimeType: String?

    public init(filePath: String, kind: String, mimeType: String?) {
        self.filePath = filePath
        self.kind = kind
        self.mimeType = mimeType
    }
}

public struct SyncOutboxEvent: Codable, Equatable, Sendable {
    public let clientEventId: String
    public let type: String
    public var contentHash: String
    public let itemType: String?
    public var payload: [String: SyncEventPayloadValue]?
    public let copyCountDelta: Int64?
    public let createdAt: Int64
    public var attemptCount: Int
    public var nextAttemptAt: Int64
    public var status: SyncOutboxEventStatus
    public let assetRegistration: SyncOutboxAssetRegistration?

    public init(
        clientEventId: String = "macos-\(UUID().uuidString.lowercased())",
        type: String,
        contentHash: String,
        itemType: String?,
        payload: [String: SyncEventPayloadValue]?,
        copyCountDelta: Int64?,
        createdAt: Int64,
        attemptCount: Int = 0,
        nextAttemptAt: Int64,
        status: SyncOutboxEventStatus = .pending,
        assetRegistration: SyncOutboxAssetRegistration? = nil
    ) {
        self.clientEventId = clientEventId
        self.type = type
        self.contentHash = Self.normalizedServerContentHash(contentHash)
        self.itemType = itemType
        self.payload = payload
        self.copyCountDelta = copyCountDelta
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.status = status
        self.assetRegistration = assetRegistration
    }

    public static func normalizedServerContentHash(_ contentHash: String) -> String {
        let trimmed = contentHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let rawHash = trimmed.removingPrefix("blake3:") {
            return rawHash.isLowercaseBLAKE3Hex ? "blake3:\(rawHash)" : trimmed
        }
        return trimmed.isLowercaseBLAKE3Hex ? "blake3:\(trimmed)" : trimmed
    }

    public static func localContentHashKey(_ contentHash: String) -> String {
        let normalized = normalizedServerContentHash(contentHash)
        return normalized.removingPrefix("blake3:") ?? normalized
    }
}

public enum SyncOutboxTiming {
    public static let initialAttemptDelayMs: Int64 = 250
    public static let startupScanDelayMs: UInt64 = 1_000_000_000
    public static let retryAfterItemDeletedConflictMs: Int64 = 60_000

    public static func retryDelayMs(afterFailureCount failureCount: Int) -> Int64 {
        switch failureCount {
        case ..<1:
            return 5_000
        case 1:
            return 5_000
        case 2:
            return 15_000
        case 3:
            return 60_000
        default:
            return 300_000
        }
    }
}

public actor SyncEventOutbox {
    private struct Snapshot: Codable {
        var events: [SyncOutboxEvent]
    }

    private let fileURL: URL
    private var events: [SyncOutboxEvent] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    @discardableResult
    public func load(nowMs: Int64) -> [SyncOutboxEvent] {
        guard let data = try? Data(contentsOf: fileURL) else {
            events = []
            return events
        }

        let decoder = JSONDecoder()
        let loaded = (try? decoder.decode(Snapshot.self, from: data))?.events ?? []
        events = loaded.map { event in
            var next = event
            next.contentHash = SyncOutboxEvent.normalizedServerContentHash(next.contentHash)
            if next.status == .sending {
                next.status = .pending
                next.nextAttemptAt = min(next.nextAttemptAt, nowMs)
            }
            return next
        }
        persist()
        return events
    }

    @discardableResult
    public func enqueue(_ event: SyncOutboxEvent) -> [SyncOutboxEvent] {
        events.append(event)
        events.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                lhs.clientEventId < rhs.clientEventId
            } else {
                lhs.createdAt < rhs.createdAt
            }
        }
        persist()
        return events
    }

    public func dueBatch(nowMs: Int64, maxBatchSize: Int = 50) -> [SyncOutboxEvent] {
        let dueIDs = events
            .filter { event in
                event.status != .sending && event.nextAttemptAt <= nowMs
            }
            .prefix(max(1, maxBatchSize))
            .map(\.clientEventId)
        guard !dueIDs.isEmpty else { return [] }

        let dueIDSet = Set(dueIDs)
        for index in events.indices where dueIDSet.contains(events[index].clientEventId) {
            events[index].status = .sending
        }
        persist()
        return events.filter { dueIDSet.contains($0.clientEventId) }
    }

    public func updatePayload(clientEventId: String, payload: [String: SyncEventPayloadValue]) {
        guard let index = events.firstIndex(where: { $0.clientEventId == clientEventId }) else {
            return
        }
        events[index].payload = payload
        persist()
    }

    public func complete(clientEventIds: Set<String>) {
        guard !clientEventIds.isEmpty else { return }
        events.removeAll { clientEventIds.contains($0.clientEventId) }
        persist()
    }

    public func fail(
        clientEventIds: Set<String>,
        nowMs: Int64,
        retryDelayOverrideMs: Int64? = nil
    ) {
        guard !clientEventIds.isEmpty else { return }
        for index in events.indices where clientEventIds.contains(events[index].clientEventId) {
            events[index].attemptCount += 1
            events[index].status = .failed
            let delay = retryDelayOverrideMs
                ?? SyncOutboxTiming.retryDelayMs(afterFailureCount: events[index].attemptCount)
            events[index].nextAttemptAt = nowMs + delay
        }
        persist()
    }

    @discardableResult
    public func forceRetryUpserts(contentHash: String, nowMs: Int64) -> Bool {
        let retryKeys = Set([
            SyncOutboxEvent.normalizedServerContentHash(contentHash),
            SyncOutboxEvent.localContentHashKey(contentHash)
        ])
        var changed = false
        for index in events.indices where events[index].type == "item_upsert"
            && retryKeys.contains(events[index].contentHash)
            && events[index].status != .sending {
            events[index].status = .pending
            events[index].nextAttemptAt = nowMs
            changed = true
        }
        if changed {
            persist()
        }
        return changed
    }

    public func clearAll() {
        events.removeAll()
        persist()
    }

    public func nextDelayNanoseconds(nowMs: Int64) -> UInt64? {
        let nextAttempt = events
            .filter { $0.status != .sending }
            .map(\.nextAttemptAt)
            .min()
        guard let nextAttempt else { return nil }
        let delayMs = max(0, nextAttempt - nowMs)
        return UInt64(delayMs) * 1_000_000
    }

    public func allEvents() -> [SyncOutboxEvent] {
        events
    }

    public func itemStatusesByContentHash() -> [String: PanelItemSyncStatus] {
        var statuses: [String: PanelItemSyncStatus] = [:]
        for event in events where event.type == "item_upsert" {
            switch event.status {
            case .sending:
                setItemStatus(.sending, for: event.contentHash, in: &statuses)
            case .failed:
                setItemStatusIfNotSending(.failed, for: event.contentHash, in: &statuses)
            case .pending:
                break
            }
        }
        return statuses
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Snapshot(events: events))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // The in-memory queue remains authoritative for this app run.
        }
    }

    private func setItemStatus(
        _ status: PanelItemSyncStatus,
        for contentHash: String,
        in statuses: inout [String: PanelItemSyncStatus]
    ) {
        for key in statusContentHashKeys(for: contentHash) {
            statuses[key] = status
        }
    }

    private func setItemStatusIfNotSending(
        _ status: PanelItemSyncStatus,
        for contentHash: String,
        in statuses: inout [String: PanelItemSyncStatus]
    ) {
        for key in statusContentHashKeys(for: contentHash) where statuses[key] != .sending {
            statuses[key] = status
        }
    }

    private func statusContentHashKeys(for contentHash: String) -> Set<String> {
        let serverHash = SyncOutboxEvent.normalizedServerContentHash(contentHash)
        let localHash = SyncOutboxEvent.localContentHashKey(serverHash)
        return [serverHash, localHash]
    }
}

public enum SyncOutboxClock {
    public static func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }

    var isLowercaseBLAKE3Hex: Bool {
        count == 64 && allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }
    }
}
