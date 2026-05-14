import Foundation

public struct PanelItemCardPresentation: Equatable, Sendable {
    public let symbolName: String
    public let displayType: String
    public let summaryText: String
    public let footnoteText: String
    public let linkHost: String?
    public let linkDetail: String?
    public let linkTitle: String?
    public let fileTitle: String?
    public let fileDetail: String?

    public init(
        symbolName: String,
        displayType: String,
        summaryText: String,
        footnoteText: String,
        linkHost: String? = nil,
        linkDetail: String? = nil,
        linkTitle: String? = nil,
        fileTitle: String? = nil,
        fileDetail: String? = nil
    ) {
        self.symbolName = symbolName
        self.displayType = displayType
        self.summaryText = summaryText
        self.footnoteText = footnoteText
        self.linkHost = linkHost
        self.linkDetail = linkDetail
        self.linkTitle = linkTitle
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
                linkMetadata: linkMetadata
            ),
            footnoteText: footnoteText(
                for: item,
                linkMetadata: linkMetadata,
                fileMetadata: fileMetadata,
                byteCountFormatter: byteCountFormatter
            ),
            linkHost: item.itemType == "link" ? linkMetadata.host : nil,
            linkDetail: item.itemType == "link" ? linkMetadata.detail : nil,
            linkTitle: item.itemType == "link" ? linkMetadata.title : nil,
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

        return baseType
    }

    private static func summaryText(
        for item: RustClipboardItemSummary,
        linkMetadata: (host: String, detail: String, title: String?)
    ) -> String {
        switch item.itemType {
        case "file":
            return ""
        case "link":
            return ""
        case "image":
            return ""
        default:
            return item.primaryText ?? item.summary
        }
    }

    private static func footnoteText(
        for item: RustClipboardItemSummary,
        linkMetadata: (host: String, detail: String, title: String?),
        fileMetadata: (title: String, detail: String),
        byteCountFormatter: (Int64) -> String
    ) -> String {
        switch item.itemType {
        case "image":
            return imageResolutionText(from: item.summary)
        case "link":
            return linkMetadata.title == nil
                ? compactLinkDisplayText(from: linkMetadata.detail)
                : linkMetadata.host
        case "file":
            return fileMetadata.detail
        default:
            return contentFootnote(for: item.primaryText ?? item.summary)
        }
    }

    private static func imageResolutionText(from summary: String) -> String {
        let pattern = #"(\d+)\s*[xX×]\s*(\d+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: summary,
                range: NSRange(summary.startIndex..<summary.endIndex, in: summary)
              ),
              match.numberOfRanges == 3,
              let widthRange = Range(match.range(at: 1), in: summary),
              let heightRange = Range(match.range(at: 2), in: summary)
        else {
            return ""
        }

        return "\(summary[widthRange]) × \(summary[heightRange])"
    }

    private static func linkPresentation(for item: RustClipboardItemSummary) -> (host: String, detail: String, title: String?) {
        if let metadata = item.linkMetadata {
            let host = metadata.host.isEmpty ? "网页链接" : metadata.host
            let detail = metadata.displayURL.isEmpty ? metadata.canonicalURL : metadata.displayURL
            return (
                host: host,
                detail: detail.isEmpty ? host : detail,
                title: nonEmptyText(metadata.title)
            )
        }

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
            detail: detail ?? (rawText.isEmpty ? "网页链接" : rawText),
            title: nil
        )
    }

    private static func normalizedURL(from text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.host != nil {
            return url
        }

        return URL(string: "https://\(text)").flatMap { $0.host == nil ? nil : $0 }
    }

    private static func compactLinkDisplayText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.replacingOccurrences(of: "www.", with: "")
        else {
            return trimmed.isEmpty ? "网页链接" : trimmed
        }

        let path = url.path == "/" ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let fragment = url.fragment.map { "#\($0)" } ?? ""
        return "\(host)\(path)\(query)\(fragment)"
    }

    private static func filePresentation(for item: RustClipboardItemSummary) -> (title: String, detail: String) {
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryPathText = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            let detail = nonEmptyText(primaryPathText) ?? "本地文件路径"
            return ("文件", detail)
        }

        if let separatorRange = summary.range(of: " · ") {
            let title = String(summary[..<separatorRange.lowerBound])
            let detail = String(summary[separatorRange.upperBound...])
            if let primaryPathText = nonEmptyText(primaryPathText) {
                return (title, primaryPathText)
            }
            if isPathLikeText(detail) {
                return (title, detail)
            }
            return (title, "本地文件路径")
        }

        let detail = nonEmptyText(primaryPathText) ?? (isPathLikeText(summary) ? summary : "本地文件路径")
        return (summary, detail)
    }

    private static func nonEmptyText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func isPathLikeText(_ text: String) -> Bool {
        text.hasPrefix("~") || text.contains("/") || text.contains("\\")
    }
}
