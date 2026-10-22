import Foundation

/// The wire list projection is distinct from a complete item even when its
/// metadata happens to share the full-item JSON keys.
public struct RustClipboardListEntry: Decodable, Sendable {
    public let item: RustClipboardItemSummary

    private enum CodingKeys: String, CodingKey {
        case textPreview = "text_preview"
        case previewTruncated = "preview_truncated"
        case trimmedGraphemeCount = "trimmed_grapheme_count"
        case scalarCount = "scalar_count"
    }

    public init(from decoder: Decoder) throws {
        let metadata = try RustClipboardItemSummary(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let projectsText = metadata.itemType == "text" || metadata.itemType == "rich_text"
        item = RustClipboardItemSummary(
            id: metadata.id, itemType: metadata.itemType, summary: metadata.summary,
            primaryText: projectsText ? nil : metadata.primaryText, contentHash: metadata.contentHash,
            sourceAppId: metadata.sourceAppId, sourceAppName: metadata.sourceAppName,
            sourceAppIconPath: metadata.sourceAppIconPath,
            sourceAppIconHeaderColor: metadata.sourceAppIconHeaderColor,
            previewAssetPath: metadata.previewAssetPath, payloadAssetPath: metadata.payloadAssetPath,
            sourceConfidence: metadata.sourceConfidence, firstCopiedAtMs: metadata.firstCopiedAtMs,
            lastCopiedAtMs: metadata.lastCopiedAtMs, copyCount: metadata.copyCount,
            isPinned: metadata.isPinned, sizeBytes: metadata.sizeBytes,
            previewState: metadata.previewState, payloadState: metadata.payloadState,
            fileItems: metadata.fileItems, linkMetadata: metadata.linkMetadata,
            pinboardIDs: metadata.pinboardIDs,
            textPreview: try container.decodeIfPresent(String.self, forKey: .textPreview),
            previewTruncated: try container.decode(Bool.self, forKey: .previewTruncated),
            trimmedGraphemeCount: try container.decodeIfPresent(Int64.self, forKey: .trimmedGraphemeCount),
            scalarCount: try container.decodeIfPresent(Int64.self, forKey: .scalarCount),
            isContentComplete: !projectsText,
            customTitle: metadata.customTitle
        )
    }
}

public struct RustClipboardItemLookup: Decodable, Sendable {
    public let itemID: String
    public let item: RustClipboardItemSummary?
    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case item
    }
}

public typealias ClipboardFullItemsLoader =
    @Sendable ([String]) async -> Result<[RustClipboardItemSummary], RustCoreError>

public enum ClipboardCopyMode: Equatable, Sendable {
    case original
    case preferPlainText
    case explicitPlainText
}

public struct ClipboardCopyIntent: Equatable, Sendable {
    public let token: UUID
    public let itemIDs: [String]
    public let mode: ClipboardCopyMode
    public let pasteDirectlyToTarget: Bool
    public let targetProcessIdentifier: Int32?
}

/// Every await is followed by an intent check before a writer may run. The
/// token remains valid after a successful write for the delayed native paste.
@MainActor
public final class ClipboardCopyIntentCoordinator {
    private var currentToken: UUID?

    public init() {}

    public func begin(
        itemIDs: [String], mode: ClipboardCopyMode,
        pasteDirectlyToTarget: Bool, targetProcessIdentifier: Int32?
    ) -> ClipboardCopyIntent {
        let intent = ClipboardCopyIntent(
            token: UUID(), itemIDs: itemIDs, mode: mode,
            pasteDirectlyToTarget: pasteDirectlyToTarget,
            targetProcessIdentifier: targetProcessIdentifier
        )
        currentToken = intent.token
        return intent
    }

    public func cancel() { currentToken = nil }

    public func isCurrent(_ intent: ClipboardCopyIntent) -> Bool {
        currentToken == intent.token
    }

    public func resolve(
        _ intent: ClipboardCopyIntent, loader: ClipboardFullItemsLoader
    ) async -> Result<[RustClipboardItemSummary], RustCoreError>? {
        guard isCurrent(intent), !Task.isCancelled else { return nil }
        let result = await loader(intent.itemIDs)
        guard isCurrent(intent), !Task.isCancelled else { return nil }
        return result.flatMap { items in
            guard items.map(\.id) == intent.itemIDs,
                  items.allSatisfy(\.isContentComplete) else {
                return .failure(RustCoreError(
                    code: "missing_item", messageKey: "clipboard.error.missing_item",
                    recoverable: true, message: "Selected content is no longer available"
                ))
            }
            return .success(items)
        }
    }
}

/// Tracks the intent independently of whether a popover has been created yet.
public struct ClipboardDetailIntent: Equatable, Sendable {
    public let token = UUID()
    public let itemID: String
    public init(itemID: String) { self.itemID = itemID }
}

public struct RustItemMutationError: Decodable, Sendable {
    public let code: String
    public let messageKey: String
    public let recoverable: Bool
    public let message: String
    init(coreError: RustCoreError) {
        code = coreError.code
        messageKey = coreError.messageKey
        recoverable = coreError.recoverable
        message = coreError.message
    }
    public var coreError: RustCoreError {
        RustCoreError(code: code, messageKey: messageKey, recoverable: recoverable, message: message)
    }
    private enum CodingKeys: String, CodingKey {
        case code, recoverable, message
        case messageKey = "message_key"
    }
}

public struct RustItemMutationOutcome: Decodable, Sendable {
    public let requestIndex: Int
    public let status: String
    public let affectedCount: Int64
    public let error: RustItemMutationError?
    public let requiresRefresh: Bool
    public let committed: Bool?
    private enum CodingKeys: String, CodingKey {
        case requestIndex = "request_index"
        case status, error, committed
        case affectedCount = "affected_count"
        case requiresRefresh = "requires_refresh"
    }
}

public struct RustItemBatchMutationResult: Decodable, Sendable {
    public let outcomes: [RustItemMutationOutcome]
    public let sessionFault: Bool
    public let terminationReason: RustItemMutationError?
    private enum CodingKeys: String, CodingKey {
        case outcomes
        case sessionFault = "session_fault"
        case terminationReason = "termination_reason"
    }
}
