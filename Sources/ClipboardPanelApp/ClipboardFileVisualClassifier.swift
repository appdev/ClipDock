import Foundation

public struct ClipboardSingleImageFileVisual: Equatable, Sendable {
    public let previewPath: String?
    public let resolutionText: String

    public init(previewPath: String?, resolutionText: String) {
        self.previewPath = previewPath
        self.resolutionText = resolutionText
    }
}

public enum ClipboardFileVisualClassifier {
    public static func fileCount(for item: RustClipboardItemSummary) -> Int {
        guard item.itemType == "file" else { return 0 }

        if !item.fileItems.isEmpty {
            return item.fileItems.count
        }

        let primaryPathCount = ClipboardFilePreviewResolver.pathStrings(fromPrimaryText: item.primaryText).count
        if primaryPathCount > 0 {
            return primaryPathCount
        }

        return summaryFileCount(from: item.summary) ?? 0
    }

    public static func singleImageFileVisual(
        for item: RustClipboardItemSummary,
        appSupportDirectory: URL? = nil
    ) -> ClipboardSingleImageFileVisual? {
        guard item.itemType == "file",
              fileCount(for: item) == 1
        else {
            return nil
        }

        let metadataImage = item.fileItems.first(where: ClipboardOriginalImagePathResolver.isImageFileItem)
        let resolvedImagePath = ClipboardOriginalImagePathResolver
            .originalImagePaths(for: item, appSupportDirectory: appSupportDirectory)
            .first
        let imageAssetPath = [item.previewAssetPath, item.payloadAssetPath]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && ClipboardOriginalImagePathResolver.isImagePath($0) }
        let fallbackImagePath = metadataImage?.path ?? ClipboardFilePreviewResolver
            .pathStrings(fromPrimaryText: item.primaryText)
            .first(where: ClipboardOriginalImagePathResolver.isImagePath)
        let previewPath = resolvedImagePath
            ?? imageAssetPath
            ?? fallbackImagePath

        guard metadataImage != nil || resolvedImagePath != nil || fallbackImagePath != nil else {
            return nil
        }

        return ClipboardSingleImageFileVisual(
            previewPath: previewPath,
            resolutionText: metadataImage.flatMap(resolutionText) ?? imageResolutionText(from: item.summary)
        )
    }

    private static func summaryFileCount(from summary: String) -> Int? {
        let pattern = #"^\s*(\d+)\s*(?:个文件|files?)\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: summary,
                range: NSRange(summary.startIndex..<summary.endIndex, in: summary)
              ),
              match.numberOfRanges == 2,
              let countRange = Range(match.range(at: 1), in: summary)
        else {
            return nil
        }
        return Int(summary[countRange])
    }

    private static func resolutionText(for fileItem: RustClipboardFileItemSummary) -> String? {
        guard let width = fileItem.width,
              let height = fileItem.height,
              width > 0,
              height > 0
        else {
            return nil
        }

        return "\(width) × \(height)"
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
}
