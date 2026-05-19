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
    public let linkURL: URL?
    public let linkDisplayURL: String?
    public let linkTitle: String?
    public let colorValue: ClipboardColorValue?
    public let fileURLs: [URL]
    public let richTextURL: URL?
    public let copiedAtMilliseconds: Int64

    public init(
        itemID: String,
        itemType: String,
        title: String,
        subtitle: String,
        body: String,
        metadata: String,
        sourceAppName: String,
        sourceAppIconPath: String?,
        imageURL: URL?,
        linkURL: URL?,
        linkDisplayURL: String?,
        linkTitle: String?,
        colorValue: ClipboardColorValue?,
        fileURLs: [URL],
        richTextURL: URL? = nil,
        copiedAtMilliseconds: Int64
    ) {
        self.itemID = itemID
        self.itemType = itemType
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.metadata = metadata
        self.sourceAppName = sourceAppName
        self.sourceAppIconPath = sourceAppIconPath
        self.imageURL = imageURL
        self.linkURL = linkURL
        self.linkDisplayURL = linkDisplayURL
        self.linkTitle = linkTitle
        self.colorValue = colorValue
        self.fileURLs = fileURLs
        self.richTextURL = richTextURL
        self.copiedAtMilliseconds = copiedAtMilliseconds
    }
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
        let fileURLs = previewFileURLs(
            for: item,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
        let richTextURL = previewRichTextURL(
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
            sourceAppName: item.sourceAppName ?? AppLocalization.text("source.unknown", defaultValue: "未知来源"),
            sourceAppIconPath: item.sourceAppIconPath,
            imageURL: imageURL,
            linkURL: previewLinkURL(for: item),
            linkDisplayURL: item.linkMetadata?.displayURL,
            linkTitle: item.linkMetadata?.title,
            colorValue: previewColorValue(for: item),
            fileURLs: fileURLs,
            richTextURL: richTextURL,
            copiedAtMilliseconds: item.lastCopiedAtMs
        )
    }

    private static func previewTitle(for item: RustClipboardItemSummary) -> String {
        switch item.itemType {
        case "link":
            return item.linkMetadata?.title
                ?? item.linkMetadata?.host
                ?? item.primaryText.flatMap(hostName)
                ?? item.summary
        case "image":
            return item.summary
        case "color":
            return previewColorValue(for: item)?.normalizedHex ?? item.summary
        default:
            return item.summary
        }
    }

    private static func previewSubtitle(for item: RustClipboardItemSummary) -> String {
        let typeText = AppLocalization.itemTypeTitle(item.itemType)

        let copyText = item.copyCount > 1
            ? AppLocalization.format("preview.copyCountSuffix", defaultValue: " · %lld 次复制", item.copyCount)
            : ""
        return "\(typeText)\(copyText)"
    }

    private static func previewBody(for item: RustClipboardItemSummary) -> String {
        switch item.itemType {
        case "text", "link", "rich_text":
            return item.primaryText ?? item.summary
        case "image":
            return item.summary
        case "color":
            return previewColorValue(for: item)?.previewMetadataText
                ?? (item.primaryText ?? item.summary)
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
            return item.linkMetadata?.displayURL ?? item.primaryText ?? item.summary
        case "color":
            return previewColorValue(for: item)?.previewMetadataText
                ?? AppLocalization.text("color.format.unavailable", defaultValue: "颜色格式不可用")
        default:
            let sizeText = formatter.string(fromByteCount: item.sizeBytes)
            return item.sizeBytes > 0 ? sizeText : item.sourceConfidence
        }
    }

    private static func previewLinkURL(for item: RustClipboardItemSummary) -> URL? {
        guard item.itemType == "link" else { return nil }

        return [
            item.linkMetadata?.canonicalURL,
            item.primaryText,
            item.summary
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .lazy
        .compactMap(normalizedHTTPURL(from:))
        .first
    }

    private static func previewImageURL(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        switch item.itemType {
        case "image":
            guard item.payloadState == "ready" else {
                return nil
            }
            return ClipboardAssetPathResolver.firstExistingURL(
                for: [item.payloadAssetPath],
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )

        case "file":
            return ClipboardAssetPathResolver.firstExistingURL(
                for: [item.previewAssetPath],
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )

        default:
            return nil
        }
    }

    private static func previewFileURLs(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> [URL] {
        guard item.itemType == "file" else { return [] }

        return ClipboardFilePreviewResolver.fileURLs(
            for: item,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    private static func previewRichTextURL(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        guard item.itemType == "rich_text" else { return nil }

        return ClipboardAssetPathResolver.firstExistingURL(
            for: [item.payloadAssetPath],
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    private static func previewColorValue(for item: RustClipboardItemSummary) -> ClipboardColorValue? {
        guard item.itemType == "color" else { return nil }
        return [
            item.primaryText,
            item.summary
        ]
        .compactMap { $0 }
        .lazy
        .compactMap { ClipboardColorValue(normalizedHex: $0) }
        .first
    }

    private static func hostName(from text: String) -> String? {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host
    }

    private static func normalizedHTTPURL(from text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        let candidate = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return nil
        }
        return url
    }
}
