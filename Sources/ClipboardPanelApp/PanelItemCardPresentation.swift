import Foundation

public struct PanelItemCardPresentation: Equatable, Sendable {
    public let symbolName: String
    public let displayType: String
    public let summaryText: String
    public let footnoteText: String
    public let linkHost: String?
    public let linkDetail: String?
    public let fileTitle: String?
    public let fileDetail: String?

    public init(
        symbolName: String,
        displayType: String,
        summaryText: String,
        footnoteText: String,
        linkHost: String? = nil,
        linkDetail: String? = nil,
        fileTitle: String? = nil,
        fileDetail: String? = nil
    ) {
        self.symbolName = symbolName
        self.displayType = displayType
        self.summaryText = summaryText
        self.footnoteText = footnoteText
        self.linkHost = linkHost
        self.linkDetail = linkDetail
        self.fileTitle = fileTitle
        self.fileDetail = fileDetail
    }
}

public enum PanelItemCardPresenter {
    public static func presentation(
        for item: RustClipboardItemSummary,
        byteCountFormatter: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    ) -> PanelItemCardPresentation {
        let displayType = displayType(for: item)
        let linkMetadata = linkPresentation(for: item)
        let fileMetadata = filePresentation(for: item)

        return PanelItemCardPresentation(
            symbolName: symbolName(forItemType: item.itemType),
            displayType: displayType,
            summaryText: summaryText(
                for: item,
                linkMetadata: linkMetadata,
                fileMetadata: fileMetadata,
                byteCountFormatter: byteCountFormatter
            ),
            footnoteText: footnoteText(
                for: item,
                linkMetadata: linkMetadata,
                byteCountFormatter: byteCountFormatter
            ),
            linkHost: item.itemType == "link" ? linkMetadata.host : nil,
            linkDetail: item.itemType == "link" ? linkMetadata.detail : nil,
            fileTitle: item.itemType == "file" ? fileMetadata.title : nil,
            fileDetail: item.itemType == "file" ? fileMetadata.detail : nil
        )
    }

    public static func contentFootnote(for summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        return count > 0 ? "\(count) 个字符" : ""
    }

    private static func symbolName(forItemType itemType: String) -> String {
        switch itemType {
        case "link":
            return "link"
        case "image":
            return "photo"
        case "file":
            return "folder"
        case "color":
            return "paintpalette"
        case "rich_text":
            return "doc.richtext"
        default:
            return "doc.text"
        }
    }

    private static func displayType(for item: RustClipboardItemSummary) -> String {
        let baseType: String
        switch item.itemType {
        case "link":
            baseType = "链接"
        case "image":
            baseType = "图片"
        case "file":
            baseType = "文件"
        case "color":
            baseType = "颜色"
        case "rich_text":
            baseType = "富文本"
        default:
            baseType = "文本"
        }

        return item.isPinned ? "固定 · \(baseType)" : baseType
    }

    private static func summaryText(
        for item: RustClipboardItemSummary,
        linkMetadata: (host: String, detail: String),
        fileMetadata: (title: String, detail: String),
        byteCountFormatter: (Int64) -> String
    ) -> String {
        switch item.itemType {
        case "file":
            let copyText = item.copyCount > 1 ? " · \(item.copyCount) 次复制" : ""
            return "\(fileMetadata.title)\(copyText)"
        case "link":
            if item.summary.trimmingCharacters(in: .whitespacesAndNewlines) == linkMetadata.host {
                return linkMetadata.detail
            }
            return item.primaryText ?? item.summary
        case "image":
            let sizeText = byteCountFormatter(item.sizeBytes)
            let copyText = item.copyCount > 1 ? " · \(item.copyCount) 次复制" : ""
            return "PNG · \(sizeText)\(copyText)"
        default:
            return item.primaryText ?? item.summary
        }
    }

    private static func footnoteText(
        for item: RustClipboardItemSummary,
        linkMetadata: (host: String, detail: String),
        byteCountFormatter: (Int64) -> String
    ) -> String {
        switch item.itemType {
        case "image":
            return byteCountFormatter(item.sizeBytes)
        case "link":
            return linkMetadata.host
        case "file":
            return item.copyCount > 1 ? "\(item.copyCount) 次复制" : ""
        default:
            return contentFootnote(for: item.primaryText ?? item.summary)
        }
    }

    private static func linkPresentation(for item: RustClipboardItemSummary) -> (host: String, detail: String) {
        let rawText = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = normalizedURL(from: rawText)
        let host = url?.host?.replacingOccurrences(of: "www.", with: "") ?? rawText
        let detail = url.map { url -> String in
            let path = url.path.isEmpty ? "/" : url.path
            let query = url.query.map { "?\($0)" } ?? ""
            return "\(url.scheme ?? "https")://\(url.host ?? host)\(path)\(query)"
        }

        return (
            host: host.isEmpty ? "网页链接" : host,
            detail: detail ?? (rawText.isEmpty ? "网页链接" : rawText)
        )
    }

    private static func normalizedURL(from text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.host != nil {
            return url
        }

        return URL(string: "https://\(text)").flatMap { $0.host == nil ? nil : $0 }
    }

    private static func filePresentation(for item: RustClipboardItemSummary) -> (title: String, detail: String) {
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            return ("文件", "本地文件路径")
        }

        if let separatorRange = summary.range(of: " · ") {
            let title = String(summary[..<separatorRange.lowerBound])
            let detail = String(summary[separatorRange.upperBound...])
            return (title, detail.isEmpty ? summary : detail)
        }

        let detail = item.copyCount > 1 ? "\(item.copyCount) 次复制" : summary
        return (summary, detail)
    }
}
