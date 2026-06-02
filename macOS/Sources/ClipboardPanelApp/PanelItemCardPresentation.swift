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
    public let colorValue: ClipboardColorValue?

    public init(
        symbolName: String,
        displayType: String,
        summaryText: String,
        footnoteText: String,
        linkHost: String? = nil,
        linkDetail: String? = nil,
        linkTitle: String? = nil,
        fileTitle: String? = nil,
        fileDetail: String? = nil,
        colorValue: ClipboardColorValue? = nil
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
        self.colorValue = colorValue
    }
}

public enum PanelItemCardPresenter {
    public static func presentation(
        for item: RustClipboardItemSummary,
        byteCountFormatter: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    ) -> PanelItemCardPresentation {
        let imageFileVisual = ClipboardFileVisualClassifier.singleImageFileVisual(for: item)
        let displayType = displayType(for: item, imageFileVisual: imageFileVisual)
        let linkMetadata = linkPresentation(for: item)
        let fileMetadata = filePresentation(for: item)
        let colorValue = colorPresentation(for: item)

        return PanelItemCardPresentation(
            symbolName: symbolName(forItemType: item.itemType, imageFileVisual: imageFileVisual),
            displayType: displayType,
            summaryText: summaryText(
                for: item,
                linkMetadata: linkMetadata
            ),
            footnoteText: footnoteText(
                for: item,
                linkMetadata: linkMetadata,
                fileMetadata: fileMetadata,
                imageFileVisual: imageFileVisual,
                colorValue: colorValue,
                byteCountFormatter: byteCountFormatter
            ),
            linkHost: item.itemType == "link" ? linkMetadata.host : nil,
            linkDetail: item.itemType == "link" ? linkMetadata.detail : nil,
            linkTitle: item.itemType == "link" ? linkMetadata.title : nil,
            fileTitle: item.itemType == "file" && imageFileVisual == nil ? fileMetadata.title : nil,
            fileDetail: item.itemType == "file" && imageFileVisual == nil ? fileMetadata.detail : nil,
            colorValue: item.itemType == "color" ? colorValue : nil
        )
    }

    public static func contentFootnote(for summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        return count > 0
            ? AppLocalization.format("item.footnote.characters", defaultValue: "%lld 个字符", Int64(count))
            : ""
    }

    private static func symbolName(
        forItemType itemType: String,
        imageFileVisual: ClipboardSingleImageFileVisual?
    ) -> String {
        if itemType == "file", imageFileVisual != nil {
            return "photo"
        }

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
            return "doc.text"
        default:
            return "doc.text"
        }
    }

    private static func displayType(
        for item: RustClipboardItemSummary,
        imageFileVisual: ClipboardSingleImageFileVisual?
    ) -> String {
        if item.itemType == "file" {
            if imageFileVisual != nil {
                return AppLocalization.itemTypeTitle("image")
            }

            let count = fileCount(for: item)
            if count > 1 {
                return multipleFileTitle(count: count)
            }
        }

        return AppLocalization.itemTypeTitle(item.itemType)
    }

    static func fileCount(for item: RustClipboardItemSummary) -> Int {
        ClipboardFileVisualClassifier.fileCount(for: item)
    }

    static func multipleFileTitle(count: Int) -> String {
        AppLocalization.format("preview.fileCount", defaultValue: "%lld 个文件", Int64(count))
    }

    static func multipleFilesLabel() -> String {
        AppLocalization.text("preview.multipleFiles", defaultValue: "多个文件")
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
        case "color":
            return colorPresentation(for: item)?.normalizedHex
                ?? item.primaryText
                ?? item.summary
        case "text", "rich_text":
            return boundedTextPreview(from: item.primaryText ?? item.summary)
        default:
            return item.primaryText ?? item.summary
        }
    }

    private static func boundedTextPreview(from text: String, limitUTF16Units: Int = 500) -> String {
        guard limitUTF16Units > 0 else { return "" }

        let utf16Length = (text as NSString).length
        guard utf16Length > limitUTF16Units else { return text }

        var boundedLength = limitUTF16Units
        while boundedLength > 0 {
            let range = NSRange(location: 0, length: boundedLength)
            if let swiftRange = Range(range, in: text) {
                return String(text[swiftRange])
            }
            boundedLength -= 1
        }

        return ""
    }

    private static func footnoteText(
        for item: RustClipboardItemSummary,
        linkMetadata: (host: String, detail: String, title: String?),
        fileMetadata: (title: String, detail: String),
        imageFileVisual: ClipboardSingleImageFileVisual?,
        colorValue: ClipboardColorValue?,
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
            if let imageFileVisual {
                return imageFileVisual.resolutionText
            }
            return fileMetadata.detail
        case "color":
            return colorValue == nil
                ? AppLocalization.text("color.format.unavailable", defaultValue: "颜色格式不可用")
                : ""
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
            let host = metadata.host.isEmpty
                ? AppLocalization.text("link.webpage", defaultValue: "网页链接")
                : metadata.host
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
        let detail = url.flatMap(LinkDisplayURLFormatter.displayURL(from:))

        return (
            host: host.isEmpty ? AppLocalization.text("link.webpage", defaultValue: "网页链接") : host,
            detail: detail ?? (rawText.isEmpty ? AppLocalization.text("link.webpage", defaultValue: "网页链接") : rawText),
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
              let displayURL = LinkDisplayURLFormatter.displayURL(from: trimmed)
        else {
            return trimmed.isEmpty ? AppLocalization.text("link.webpage", defaultValue: "网页链接") : trimmed
        }
        return displayURL
    }

    private static func filePresentation(for item: RustClipboardItemSummary) -> (title: String, detail: String) {
        let count = fileCount(for: item)
        if count > 1 {
            return (multipleFileTitle(count: count), multipleFilesLabel())
        }

        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryPathText = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            let detail = nonEmptyText(primaryPathText)
                ?? AppLocalization.text("file.localPath", defaultValue: "本地文件路径")
            return (AppLocalization.itemTypeTitle("file"), detail)
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
            return (title, AppLocalization.text("file.localPath", defaultValue: "本地文件路径"))
        }

        let detail = nonEmptyText(primaryPathText)
            ?? (isPathLikeText(summary) ? summary : AppLocalization.text("file.localPath", defaultValue: "本地文件路径"))
        return (summary, detail)
    }

    private static func colorPresentation(for item: RustClipboardItemSummary) -> ClipboardColorValue? {
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

    private static func nonEmptyText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func isPathLikeText(_ text: String) -> Bool {
        text.hasPrefix("~") || text.contains("/") || text.contains("\\")
    }
}
