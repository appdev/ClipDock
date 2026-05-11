import Foundation

public enum ClipboardPastePayload: Equatable, Sendable {
    case text(String)
    case imageFile(URL)
    case fileURLs([URL])
    case unsupported(reason: String)
}

public enum ClipboardPastePayloadPlanner {
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
            let urls = fileURLs(
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
        ClipboardAssetPathResolver.firstExistingURL(
            for: [item.payloadAssetPath, item.previewAssetPath],
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    private static func fileURLs(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> [URL] {
        let paths = snapshotFilePaths(
            for: item,
            appSupportDirectory: appSupportDirectory
        ) ?? item.primaryText?
            .split(whereSeparator: \.isNewline)
            .map(String.init) ?? []

        return paths
            .map {
                ClipboardAssetPathResolver.resolvedURL(
                    for: $0,
                    appSupportDirectory: appSupportDirectory
                )
            }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func snapshotFilePaths(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL
    ) -> [String]? {
        for path in ClipboardAssetPathResolver.normalizedPaths(
            from: [item.payloadAssetPath, item.previewAssetPath]
        ) {
            let url = ClipboardAssetPathResolver.resolvedURL(
                for: path,
                appSupportDirectory: appSupportDirectory
            )
            guard let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(FileSnapshotDocument.self, from: data),
                  !document.paths.isEmpty
            else {
                continue
            }
            return document.paths
        }

        return nil
    }
}

private struct FileSnapshotDocument: Decodable {
    let paths: [String]
}
