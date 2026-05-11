import Foundation

enum ClipboardAssetPathResolver {
    static func resolvedURL(for path: String, appSupportDirectory: URL) -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedPath.hasPrefix("/") {
            return URL(fileURLWithPath: trimmedPath)
        }

        if trimmedPath.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: trimmedPath).expandingTildeInPath)
        }

        return appSupportDirectory.appendingPathComponent(trimmedPath)
    }

    static func firstExistingURL(
        for candidatePaths: [String?],
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        for path in normalizedPaths(from: candidatePaths) {
            let url = resolvedURL(for: path, appSupportDirectory: appSupportDirectory)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    static func normalizedPaths(from candidatePaths: [String?]) -> [String] {
        candidatePaths.compactMap { value in
            let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedValue.isEmpty ? nil : trimmedValue
        }
    }
}
