import Foundation

public enum ClipboardPastePayload: Equatable, Sendable {
    case text(String)
    case richText(rtfURL: URL?, fallbackText: String)
    case imageFile(URL)
    case fileURLs([URL])
    case pasteboardItems([ClipboardPasteboardItemPayload])
    case unsupported(reason: String)

    public var sourceItemIDs: [String] {
        switch self {
        case .pasteboardItems(let items):
            return items.flatMap(\.sourceItemIDs).deduplicatedPreservingOrder()
        default:
            return []
        }
    }
}

public struct ClipboardPasteboardItemPayload: Equatable, Sendable {
    public let sourceItemIDs: [String]
    public let representations: [ClipboardPasteboardItemRepresentation]

    public init(
        sourceItemIDs: [String],
        representations: [ClipboardPasteboardItemRepresentation]
    ) {
        self.sourceItemIDs = sourceItemIDs
        self.representations = representations
    }
}

public enum ClipboardPasteboardItemRepresentation: Equatable, Sendable {
    case string(String)
    case rtf(URL)
    case imageFile(URL)
    case fileURL(URL)
}

public enum ClipboardPastePayloadPlanner {
    public static func plainTextPayload(for item: RustClipboardItemSummary) -> ClipboardPastePayload {
        RustCopyPlan.payload(items: [item], mode: .explicitPlainText, appSupportDirectory: nil)
    }

    public static func payload(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager = .default,
        alwaysPasteAsPlainText: Bool = false
    ) -> ClipboardPastePayload {
        payload(for: [item], appSupportDirectory: appSupportDirectory,
            fileManager: fileManager, alwaysPasteAsPlainText: alwaysPasteAsPlainText)
    }

    public static func payload(
        for items: [RustClipboardItemSummary],
        appSupportDirectory: URL,
        fileManager: FileManager = .default,
        alwaysPasteAsPlainText: Bool = false
    ) -> ClipboardPastePayload {
        RustCopyPlan.payload(items: items, mode: alwaysPasteAsPlainText ? .preferPlainText : .original,
            appSupportDirectory: appSupportDirectory, fileManager: fileManager)
    }
}

private extension Array where Element == String {
    func deduplicatedPreservingOrder() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in self where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
