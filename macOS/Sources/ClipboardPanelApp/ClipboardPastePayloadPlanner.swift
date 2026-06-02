import Foundation
import UniformTypeIdentifiers

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
    private enum PasteboardItemPayloadPlan {
        case success([ClipboardPasteboardItemPayload])
        case failure(reason: String)
    }

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
        fileManager: FileManager = .default,
        alwaysPasteAsPlainText: Bool = false
    ) -> ClipboardPastePayload {
        if alwaysPasteAsPlainText,
           let plainTextPayload = globalPlainTextPayload(for: item) {
            return plainTextPayload
        }

        return originalPayload(
            for: item,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    public static func payload(
        for items: [RustClipboardItemSummary],
        appSupportDirectory: URL,
        fileManager: FileManager = .default,
        alwaysPasteAsPlainText: Bool = false
    ) -> ClipboardPastePayload {
        guard !items.isEmpty else {
            return .unsupported(reason: "empty_selection")
        }

        if items.count == 1, let item = items.first {
            return payload(
                for: item,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager,
                alwaysPasteAsPlainText: alwaysPasteAsPlainText
            )
        }

        if alwaysPasteAsPlainText {
            return plainTextPayload(for: items)
        }

        if !alwaysPasteAsPlainText,
           items.allSatisfy({ $0.itemType == "file" }) {
            let itemPayloads = filePasteboardItemPayloads(
                for: items,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )
            if itemPayloads.contains(where: hasImageFileRepresentation) {
                return itemPayloads.isEmpty
                    ? .unsupported(reason: "missing_file_url")
                    : .pasteboardItems(itemPayloads)
            }

            let urls = itemPayloads.flatMap(fileURLRepresentations)
            return urls.isEmpty ? .unsupported(reason: "missing_file_url") : .fileURLs(urls)
        }

        if items.contains(where: { isImageLikeItem($0, appSupportDirectory: appSupportDirectory, fileManager: fileManager) }),
           !items.allSatisfy({ isImageLikeItem($0, appSupportDirectory: appSupportDirectory, fileManager: fileManager) }),
           items.contains(where: isTextLikeItem) {
            return textOnlyPasteboardPayload(
                for: items,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )
        }

        var itemPayloads: [ClipboardPasteboardItemPayload] = []
        for item in items {
            switch pasteboardItemPayload(
                for: item,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            ) {
            case .success(let payloads):
                itemPayloads.append(contentsOf: payloads)
            case .failure(let reason):
                return .unsupported(reason: reason)
            }
        }

        return itemPayloads.isEmpty
            ? .unsupported(reason: "empty_selection")
            : .pasteboardItems(itemPayloads)
    }

    private static func originalPayload(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
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
            let payloads = filePasteboardItemPayloads(
                for: item,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )
            guard !payloads.isEmpty else {
                return .unsupported(reason: "missing_file_url")
            }
            let imageURLs = payloads.flatMap(imageFileRepresentations)
            if imageURLs.count == 1,
               payloads.count == 1,
               payloads[0].representations.count == 1,
               let imageURL = imageURLs.first {
                return .imageFile(imageURL)
            }
            let fileURLs = payloads.flatMap(fileURLRepresentations)
            return imageURLs.isEmpty ? .fileURLs(fileURLs) : .pasteboardItems(payloads)

        default:
            return .unsupported(reason: "unsupported_type")
        }
    }

    private static func globalPlainTextPayload(for item: RustClipboardItemSummary) -> ClipboardPastePayload? {
        switch item.itemType {
        case "text", "rich_text", "link":
            let text = item.primaryText ?? item.summary
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.isEmpty ? .unsupported(reason: "empty_text") : .text(text)

        case "color":
            let colorValue = [
                item.primaryText,
                item.summary
            ]
                .compactMap { $0 }
                .lazy
                .compactMap { ClipboardColorValue(normalizedHex: $0) }
                .first
            return colorValue.map { .text($0.normalizedHex) }

        default:
            return nil
        }
    }

    private static func plainTextPayload(for items: [RustClipboardItemSummary]) -> ClipboardPastePayload {
        let fragments = items.compactMap(plainTextFragment)
        guard !fragments.isEmpty else {
            return .unsupported(reason: "unsupported_type")
        }

        return .pasteboardItems([
            ClipboardPasteboardItemPayload(
                sourceItemIDs: fragments.map(\.itemID),
                representations: [.string(fragments.map(\.text).joined(separator: "\n"))]
            )
        ])
    }

    private static func textOnlyPasteboardPayload(
        for items: [RustClipboardItemSummary],
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> ClipboardPastePayload {
        var itemPayloads: [ClipboardPasteboardItemPayload] = []
        for item in items where isTextLikeItem(item) {
            switch pasteboardItemPayload(
                for: item,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            ) {
            case .success(let payloads):
                itemPayloads.append(contentsOf: payloads)
            case .failure(let reason):
                return .unsupported(reason: reason)
            }
        }

        return itemPayloads.isEmpty
            ? .unsupported(reason: "unsupported_type")
            : .pasteboardItems(itemPayloads)
    }

    private static func pasteboardItemPayload(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> PasteboardItemPayloadPlan {
        switch item.itemType {
        case "text", "link":
            let text = item.primaryText ?? item.summary
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                return .failure(reason: "empty_text")
            }
            return .success([ClipboardPasteboardItemPayload(
                sourceItemIDs: [item.id],
                representations: [.string(text)]
            )])

        case "rich_text":
            let text = item.primaryText ?? item.summary
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                return .failure(reason: "empty_text")
            }
            var representations: [ClipboardPasteboardItemRepresentation] = []
            if let rtfURL = ClipboardAssetPathResolver.firstExistingURL(
                for: [item.payloadAssetPath],
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            ) {
                representations.append(.rtf(rtfURL))
            }
            representations.append(.string(text))
            return .success([ClipboardPasteboardItemPayload(
                sourceItemIDs: [item.id],
                representations: representations
            )])

        case "color":
            guard let colorValue = colorText(for: item) else {
                return .failure(reason: "invalid_color")
            }
            return .success([ClipboardPasteboardItemPayload(
                sourceItemIDs: [item.id],
                representations: [.string(colorValue)]
            )])

        case "image":
            guard let url = imageAssetURL(
                for: item,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            ) else {
                return .failure(reason: "missing_image_asset")
            }
            return .success([ClipboardPasteboardItemPayload(
                sourceItemIDs: [item.id],
                representations: [.imageFile(url)]
            )])

        case "file":
            let payloads = filePasteboardItemPayloads(
                for: item,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )
            guard !payloads.isEmpty else {
                return .failure(reason: "missing_file_url")
            }
            return .success(payloads)

        default:
            return .failure(reason: "unsupported_type")
        }
    }

    private static func plainTextFragment(for item: RustClipboardItemSummary) -> (itemID: String, text: String)? {
        let text: String?
        switch item.itemType {
        case "text", "rich_text", "link":
            text = item.primaryText ?? item.summary

        case "color":
            text = colorText(for: item)

        default:
            text = nil
        }

        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return (item.id, text)
    }

    private static func isTextLikeItem(_ item: RustClipboardItemSummary) -> Bool {
        switch item.itemType {
        case "text", "rich_text", "link", "color":
            true
        default:
            false
        }
    }

    private static func isImageLikeItem(
        _ item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> Bool {
        if item.itemType == "image" {
            return true
        }
        guard item.itemType == "file" else {
            return false
        }

        return fileURLs(
            for: item,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        ).contains(where: isImageFileURL)
    }

    private static func filePasteboardItemPayloads(
        for items: [RustClipboardItemSummary],
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> [ClipboardPasteboardItemPayload] {
        items.flatMap {
            filePasteboardItemPayloads(
                for: $0,
                appSupportDirectory: appSupportDirectory,
                fileManager: fileManager
            )
        }
    }

    private static func filePasteboardItemPayloads(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> [ClipboardPasteboardItemPayload] {
        fileURLs(
            for: item,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        ).map { url in
            ClipboardPasteboardItemPayload(
                sourceItemIDs: [item.id],
                representations: [fileRepresentation(for: url)]
            )
        }
    }

    private static func fileURLs(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> [URL] {
        ClipboardFilePreviewResolver.fileURLs(
            for: item,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    private static func fileRepresentation(for url: URL) -> ClipboardPasteboardItemRepresentation {
        isImageFileURL(url) ? .imageFile(url) : .fileURL(url)
    }

    private static func isImageFileURL(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !fileExtension.isEmpty else {
            return false
        }

        if let uniformType = UTType(filenameExtension: fileExtension),
           uniformType.conforms(to: .image) {
            return true
        }

        return knownImageFileExtensions.contains(fileExtension)
    }

    private static func hasImageFileRepresentation(_ payload: ClipboardPasteboardItemPayload) -> Bool {
        !imageFileRepresentations(payload).isEmpty
    }

    private static func imageFileRepresentations(_ payload: ClipboardPasteboardItemPayload) -> [URL] {
        payload.representations.compactMap { representation in
            guard case .imageFile(let url) = representation else {
                return nil
            }
            return url
        }
    }

    private static func fileURLRepresentations(_ payload: ClipboardPasteboardItemPayload) -> [URL] {
        payload.representations.compactMap { representation in
            guard case .fileURL(let url) = representation else {
                return nil
            }
            return url
        }
    }

    private static func colorText(for item: RustClipboardItemSummary) -> String? {
        [
            item.primaryText,
            item.summary
        ]
            .compactMap { $0 }
            .lazy
            .compactMap { ClipboardColorValue(normalizedHex: $0) }
            .first?
            .normalizedHex
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

    private static let knownImageFileExtensions: Set<String> = [
        "apng",
        "avif",
        "bmp",
        "gif",
        "heic",
        "heif",
        "icns",
        "ico",
        "jpeg",
        "jpg",
        "jxl",
        "png",
        "psd",
        "raw",
        "svg",
        "tif",
        "tiff",
        "webp"
    ]
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
