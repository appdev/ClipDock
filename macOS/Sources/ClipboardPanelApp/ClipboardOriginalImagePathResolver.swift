import Foundation
import UniformTypeIdentifiers

public enum ClipboardOriginalImagePathResolver {
    public static func originalImagePaths(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL?
    ) -> [String] {
        switch item.itemType {
        case "image":
            guard item.payloadState == "ready" else {
                return []
            }
            return uniqueResolvedPaths(
                from: [item.payloadAssetPath],
                appSupportDirectory: appSupportDirectory
            )

        case "file":
            return fileImagePaths(
                for: item,
                appSupportDirectory: appSupportDirectory
            )

        default:
            return []
        }
    }

    private static func fileImagePaths(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL?
    ) -> [String] {
        let metadataPaths = item.fileItems
            .filter(isImageFileItem)
            .map(\.path)
        let primaryTextPaths = ClipboardFilePreviewResolver
            .pathStrings(fromPrimaryText: item.primaryText)
            .filter(isImagePath)

        return uniqueResolvedPaths(
            from: metadataPaths + primaryTextPaths,
            appSupportDirectory: appSupportDirectory
        )
    }

    private static func uniqueResolvedPaths(
        from paths: [String?],
        appSupportDirectory: URL?
    ) -> [String] {
        var seenPaths = Set<String>()
        return paths.compactMap { path in
            guard let resolvedPath = resolvedPath(
                for: path,
                appSupportDirectory: appSupportDirectory
            ),
                  seenPaths.insert(resolvedPath).inserted
            else {
                return nil
            }

            return resolvedPath
        }
    }

    private static func resolvedPath(
        for path: String?,
        appSupportDirectory: URL?
    ) -> String? {
        let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPath.isEmpty else { return nil }

        if trimmedPath.hasPrefix("/") {
            return URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
        }

        if trimmedPath.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: trimmedPath).expandingTildeInPath)
                .standardizedFileURL
                .path
        }

        guard let appSupportDirectory else {
            return nil
        }

        return appSupportDirectory
            .appendingPathComponent(trimmedPath)
            .standardizedFileURL
            .path
    }

    public static func isImageFileItem(_ item: RustClipboardFileItemSummary) -> Bool {
        guard !item.isDirectory else { return false }

        if let contentType = item.contentType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !contentType.isEmpty,
           contentTypeConformsToImage(contentType) {
            return true
        }

        if let fileExtension = item.fileExtension,
           extensionConformsToImage(fileExtension) {
            return true
        }

        return isImagePath(item.path)
    }

    public static func isImagePath(_ path: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: path).pathExtension
        return extensionConformsToImage(fileExtension)
    }

    private static func contentTypeConformsToImage(_ contentType: String) -> Bool {
        if let uniformType = UTType(contentType),
           uniformType.conforms(to: .image) {
            return true
        }

        if let mimeType = UTType(mimeType: contentType),
           mimeType.conforms(to: .image) {
            return true
        }

        return contentType.lowercased().hasPrefix("image/")
    }

    private static func extensionConformsToImage(_ fileExtension: String) -> Bool {
        let normalizedExtension = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !normalizedExtension.isEmpty else { return false }

        if let uniformType = UTType(filenameExtension: normalizedExtension),
           uniformType.conforms(to: .image) {
            return true
        }

        return knownImageFileExtensions.contains(normalizedExtension)
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
