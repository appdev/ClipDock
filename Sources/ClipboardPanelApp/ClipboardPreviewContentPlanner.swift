import Foundation

public struct ClipboardPreviewContent: Equatable, Sendable {
    public let itemID: String
    public let itemType: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let metadata: String
    public let sourceAppName: String
    public let sourceAppIconPath: String?
    public let imageURL: URL?
    public let copiedAtMilliseconds: Int64
}

public enum ClipboardPreviewContentPlanner {
    public static func preview(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> ClipboardPreviewContent {
        let body = previewBody(for: item)
        let imageURL = previewImageURL(
            for: item,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )

        return ClipboardPreviewContent(
            itemID: item.id,
            itemType: item.itemType,
            title: previewTitle(for: item),
            subtitle: previewSubtitle(for: item),
            body: body,
            metadata: previewMetadata(for: item),
            sourceAppName: item.sourceAppName ?? "未知来源",
            sourceAppIconPath: item.sourceAppIconPath,
            imageURL: imageURL,
            copiedAtMilliseconds: item.lastCopiedAtMs
        )
    }

    private static func previewTitle(for item: RustClipboardItemSummary) -> String {
        switch item.itemType {
        case "link":
            return item.primaryText.flatMap(hostName) ?? item.summary
        case "image":
            return item.summary
        default:
            return item.summary
        }
    }

    private static func previewSubtitle(for item: RustClipboardItemSummary) -> String {
        let typeText: String
        switch item.itemType {
        case "link":
            typeText = "链接"
        case "image":
            typeText = "图片"
        case "file":
            typeText = "文件"
        case "color":
            typeText = "颜色"
        case "rich_text":
            typeText = "富文本"
        default:
            typeText = "文本"
        }

        let copyText = item.copyCount > 1 ? " · \(item.copyCount) 次复制" : ""
        return "\(typeText)\(copyText)"
    }

    private static func previewBody(for item: RustClipboardItemSummary) -> String {
        switch item.itemType {
        case "text", "link", "rich_text":
            return item.primaryText ?? item.summary
        case "image":
            return item.summary
        default:
            return item.primaryText ?? item.summary
        }
    }

    private static func previewMetadata(for item: RustClipboardItemSummary) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file

        switch item.itemType {
        case "image":
            let sizeText = formatter.string(fromByteCount: item.sizeBytes)
            return item.sizeBytes > 0 ? "PNG · \(sizeText)" : "PNG"
        case "link":
            return item.primaryText ?? item.summary
        default:
            let sizeText = formatter.string(fromByteCount: item.sizeBytes)
            return item.sizeBytes > 0 ? sizeText : item.sourceConfidence
        }
    }

    private static func previewImageURL(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        guard item.itemType == "image" else { return nil }

        return ClipboardAssetPathResolver.firstExistingURL(
            for: [item.previewAssetPath, item.payloadAssetPath],
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    private static func hostName(from text: String) -> String? {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host
    }
}
