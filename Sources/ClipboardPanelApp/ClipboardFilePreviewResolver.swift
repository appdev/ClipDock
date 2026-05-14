import Foundation

public enum ClipboardFilePreviewResolver {
    public static func fileURLs(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        fileURLsFromMetadata(
            item.fileItems,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
        .nonEmpty ?? fileURLs(
            previewAssetPath: item.previewAssetPath,
            payloadAssetPath: item.payloadAssetPath,
            primaryText: item.primaryText,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    public static func fileURLs(
        previewAssetPath: String?,
        payloadAssetPath: String?,
        primaryText: String?,
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let primaryPaths = pathStrings(fromPrimaryText: primaryText)
        let paths = primaryPaths.isEmpty
            ? snapshotFilePaths(
                previewAssetPath: previewAssetPath,
                payloadAssetPath: payloadAssetPath,
                appSupportDirectory: appSupportDirectory
            ) ?? []
            : primaryPaths

        return existingFileURLs(
            from: paths,
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    public static func fileURLsFromPrimaryText(
        _ primaryText: String?,
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        existingFileURLs(
            from: pathStrings(fromPrimaryText: primaryText),
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    public static func fileURLsFromMetadata(
        _ fileItems: [RustClipboardFileItemSummary],
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        existingFileURLs(
            from: fileItems.map(\.path),
            appSupportDirectory: appSupportDirectory,
            fileManager: fileManager
        )
    }

    static func pathStrings(fromPrimaryText primaryText: String?) -> [String] {
        primaryText?
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func snapshotFilePaths(
        previewAssetPath: String?,
        payloadAssetPath: String?,
        appSupportDirectory: URL
    ) -> [String]? {
        for path in ClipboardAssetPathResolver.normalizedPaths(
            from: [payloadAssetPath, previewAssetPath]
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

    private static func existingFileURLs(
        from paths: [String],
        appSupportDirectory: URL,
        fileManager: FileManager
    ) -> [URL] {
        var seenPaths = Set<String>()
        return paths.compactMap { path -> URL? in
            let url = ClipboardAssetPathResolver
                .resolvedURL(for: path, appSupportDirectory: appSupportDirectory)
                .standardizedFileURL
            guard fileManager.fileExists(atPath: url.path),
                  seenPaths.insert(url.path).inserted
            else {
                return nil
            }
            return url
        }
    }

    private struct FileSnapshotDocument: Decodable {
        let paths: [String]
    }
}

private extension Array {
    var nonEmpty: Self? {
        isEmpty ? nil : self
    }
}
