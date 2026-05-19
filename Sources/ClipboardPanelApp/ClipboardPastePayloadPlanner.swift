import Foundation

public enum ClipboardPastePayload: Equatable, Sendable {
    case text(String)
    case richText(rtfURL: URL?, fallbackText: String)
    case imageFile(URL)
    case fileURLs([URL])
    case unsupported(reason: String)
}

public enum ClipboardPastePayloadPlanner {
    public static func plainTextPayload(for item: RustClipboardItemSummary) -> ClipboardPastePayload {
        switch item.itemType {
        case "text", "rich_text":
            let text = item.primaryText ?? item.summary
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.isEmpty ? .unsupported(reason: "empty_text") : .text(text)

        default:
            return .unsupported(reason: "unsupported_type")
        }
    }

    public static func payload(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> ClipboardPastePayload {
        switch item.itemType {
        case "text", "link":
            let text = item.primaryText ?? item.summary
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.isEmpty ? .unsupported(reason: "empty_text") : .text(text)

        case "rich_text":
            let text = item.primaryText ?? item.summary
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                return .unsupported(reason: "empty_text")
            }
            let rtfURL = ClipboardAssetPathResolver.firstExistingURL(
                for: [item.payloadAssetPath],
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )
            return .richText(rtfURL: rtfURL, fallbackText: text)

        case "color":
            guard let colorValue = [
                item.primaryText,
                item.summary
            ]
                .compactMap({ $0 })
                .lazy
                .compactMap({ ClipboardColorValue(normalizedHex: $0) })
                .first
            else {
                return .unsupported(reason: "invalid_color")
            }
            return .text(colorValue.normalizedHex)

        case "image":
            guard let url = imageAssetURL(
                for: item,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            ) else {
                return .unsupported(reason: "missing_image_asset")
            }
            return .imageFile(url)

        case "file":
            let urls = ClipboardFilePreviewResolver.fileURLs(
                for: item,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )
            return urls.isEmpty ? .unsupported(reason: "missing_file_url") : .fileURLs(urls)

        default:
            return .unsupported(reason: "unsupported_type")
        }
    }

    private static func imageAssetURL(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        guard item.payloadState == "ready" else {
            return nil
        }

        return ClipboardAssetPathResolver.firstExistingURL(
            for: [item.payloadAssetPath],
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }
}
