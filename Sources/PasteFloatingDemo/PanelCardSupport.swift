import AppKit
import ClipboardPanelApp
import CoreImage

struct PanelCardResolvedItem {
    let sourceIconImage: NSImage?
    let sourceColorKey: String?
    let sourceIconColor: NSColor?
}

struct PanelCardPreviewImageState {
    let paths: [String]
    let image: NSImage?
    let tooltip: String
    let fallbackText: String
}

@MainActor
final class PanelCardAssetResolver {
    private static let imageCache = NSCache<NSString, NSImage>()
    private static let sourceColorCache = NSCache<NSString, NSColor>()
    private static let sourceColorContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    private let appSupportDirectory: URL?

    init(appSupportDirectory: URL?) {
        self.appSupportDirectory = appSupportDirectory
    }

    func resolvedItem(for request: PanelCardAssetRequest) -> PanelCardResolvedItem {
        let sourceIconImage = sourceIconImage(for: request)
        let sourceColorKey = sourceColorKey(for: request)
        let sourceColorCacheKey = sourceColorKey ?? request.sourceAppIconPath
        let sourceIconColor = sourceIconImage.flatMap {
            Self.dominantHeaderColor(
                for: $0,
                cacheKey: sourceColorCacheKey,
                fallbackCacheKey: request.sourceAppIconPath
            )
        }

        return PanelCardResolvedItem(
            sourceIconImage: sourceIconImage,
            sourceColorKey: sourceColorKey,
            sourceIconColor: sourceIconColor
        )
    }

    func previewImageState(previewPath: String?, payloadPath: String?) -> PanelCardPreviewImageState {
        let paths = existingPreviewImagePaths(paths: [previewPath, payloadPath])
        return PanelCardPreviewImageState(
            paths: paths,
            image: Self.cachedPreviewImage(paths: paths),
            tooltip: [previewPath, payloadPath].compactMap { $0 }.joined(separator: "\n"),
            fallbackText: paths.isEmpty ? "预览不可用" : "载入预览"
        )
    }

    func sourceIconImage(for request: PanelCardAssetRequest) -> NSImage? {
        request.sourceAppIconPath.flatMap(Self.loadCachedImage(path:))
    }

    func filePreviewImage(for request: PanelCardAssetRequest) -> NSImage? {
        for url in filePreviewURLs(for: request) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 96, height: 96)
            return icon
        }

        return NSImage(systemSymbolName: "folder", accessibilityDescription: "文件")
    }

    func headerColor(
        forTypeText typeText: String,
        sourceColorKey: String?,
        sourceIconColor: NSColor?,
        isSelected: Bool
    ) -> NSColor {
        if typeText.contains("错误") {
            return NSColor.systemRed.withAlphaComponent(isSelected ? 0.96 : 0.88)
        }

        if typeText.contains("空态") {
            return NSColor.systemGray.withAlphaComponent(isSelected ? 0.90 : 0.82)
        }

        if let sourceIconColor {
            return sourceIconColor.withAlphaComponent(isSelected ? 0.98 : 0.90)
        }

        if let sourceColorKey,
           !sourceColorKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceHeaderColor(for: sourceColorKey, isSelected: isSelected)
        }

        if typeText.contains("链接") {
            return NSColor.systemPurple.withAlphaComponent(isSelected ? 1 : 0.92)
        }

        if typeText.contains("图片") {
            return NSColor.systemBlue.withAlphaComponent(isSelected ? 1 : 0.86)
        }

        if typeText.contains("文件") {
            return NSColor.systemBlue.withAlphaComponent(isSelected ? 0.94 : 0.78)
        }

        return NSColor.systemBlue.withAlphaComponent(isSelected ? 1 : 0.92)
    }

    static func loadPreviewImageAsync(
        paths: [String],
        completion: @escaping @MainActor (NSImage?) -> Void
    ) {
        Task { @MainActor in
            let loadedData = await Task.detached(priority: .userInitiated) { () -> (String, Data)? in
                for path in paths {
                    let url = URL(fileURLWithPath: path)
                    if let data = try? Data(contentsOf: url) {
                        return (path, data)
                    }
                }
                return nil
            }.value

            guard let (path, data) = loadedData,
                  let image = NSImage(data: data)
            else {
                completion(nil)
                return
            }

            imageCache.setObject(image, forKey: path as NSString)
            completion(image)
        }
    }

    private func existingPreviewImagePaths(paths: [String?]) -> [String] {
        paths.compactMap { path in
            let path = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty else { return nil }
            let url = resolvedImageURL(for: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return url.path
        }
    }

    private static func cachedPreviewImage(paths: [String]) -> NSImage? {
        for path in paths {
            if let image = imageCache.object(forKey: path as NSString) {
                return image
            }
        }

        return nil
    }

    private static func loadCachedImage(path: String) -> NSImage? {
        let key = path as NSString
        if let cachedImage = imageCache.object(forKey: key) {
            return cachedImage
        }

        let url = URL(fileURLWithPath: path)
        let image = NSImage(contentsOf: url)
            ?? ((try? Data(contentsOf: url)).flatMap(NSImage.init(data:)))
        if let image {
            imageCache.setObject(image, forKey: key)
        }

        return image
    }

    private static func dominantHeaderColor(
        for image: NSImage,
        cacheKey: String?,
        fallbackCacheKey: String?
    ) -> NSColor? {
        let resolvedCacheKey = cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedCacheKey,
           !resolvedCacheKey.isEmpty,
           let cachedColor = sourceColorCache.object(forKey: resolvedCacheKey as NSString) {
            return cachedColor
        }

        let resolvedFallbackCacheKey = fallbackCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedFallbackCacheKey,
           !resolvedFallbackCacheKey.isEmpty,
           resolvedFallbackCacheKey != resolvedCacheKey,
           let cachedColor = sourceColorCache.object(forKey: resolvedFallbackCacheKey as NSString) {
            if let resolvedCacheKey, !resolvedCacheKey.isEmpty {
                sourceColorCache.setObject(cachedColor, forKey: resolvedCacheKey as NSString)
            }
            return cachedColor
        }

        guard let bitmap = sampledBitmap(for: image),
              let averagedColor = coreImageAverageColor(for: bitmap)
                ?? bitmapAverageColor(for: bitmap)
        else {
            return nil
        }

        let representativeColor = paletteRepresentativeColor(for: bitmap, fallbackColor: averagedColor)
            ?? averagedColor
        guard let normalizedColor = normalizedHeaderColor(representativeColor) else {
            return nil
        }

        if let resolvedCacheKey, !resolvedCacheKey.isEmpty {
            sourceColorCache.setObject(normalizedColor, forKey: resolvedCacheKey as NSString)
        }
        if let resolvedFallbackCacheKey,
           !resolvedFallbackCacheKey.isEmpty,
           resolvedFallbackCacheKey != resolvedCacheKey {
            sourceColorCache.setObject(normalizedColor, forKey: resolvedFallbackCacheKey as NSString)
        }

        return normalizedColor
    }

    private static func coreImageAverageColor(for bitmap: NSBitmapImageRep) -> NSColor? {
        guard let cgImage = bitmap.cgImage,
              let filter = CIFilter(name: "CIAreaAverage")
        else {
            return nil
        }

        let inputImage = CIImage(cgImage: cgImage)
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: inputImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var rgba = [UInt8](repeating: 0, count: 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        sourceColorContext.render(
            outputImage,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        guard rgba[3] > 0 else {
            return nil
        }

        return NSColor(
            srgbRed: CGFloat(rgba[0]) / 255,
            green: CGFloat(rgba[1]) / 255,
            blue: CGFloat(rgba[2]) / 255,
            alpha: 1
        )
    }

    private static func bitmapAverageColor(for bitmap: NSBitmapImageRep) -> NSColor? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var weight: CGFloat = 0
        let step = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 40)

        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }

                let alpha = color.alphaComponent
                guard alpha > 0.05 else { continue }

                red += color.redComponent * alpha
                green += color.greenComponent * alpha
                blue += color.blueComponent * alpha
                weight += alpha
            }
        }

        guard weight > 0 else {
            return nil
        }

        return NSColor(
            srgbRed: red / weight,
            green: green / weight,
            blue: blue / weight,
            alpha: 1
        )
    }

    private static func paletteRepresentativeColor(
        for bitmap: NSBitmapImageRep,
        fallbackColor: NSColor
    ) -> NSColor? {
        struct Bucket {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var saturation: CGFloat = 0
            var weight: CGFloat = 0
        }

        var buckets = Array(repeating: Bucket(), count: 24)
        var totalWeight: CGFloat = 0
        var chromaWeight: CGFloat = 0
        let step = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 80)

        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }

                let alpha = color.alphaComponent
                guard alpha > 0.08 else { continue }
                totalWeight += alpha

                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var colorAlpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &colorAlpha)

                guard saturation > 0.18,
                      brightness > 0.18,
                      !(brightness > 0.94 && saturation < 0.25)
                else {
                    continue
                }

                let bucketIndex = min(23, max(0, Int((hue * 24).rounded(.down))))
                let weight = alpha
                chromaWeight += weight
                buckets[bucketIndex].red += color.redComponent * weight
                buckets[bucketIndex].green += color.greenComponent * weight
                buckets[bucketIndex].blue += color.blueComponent * weight
                buckets[bucketIndex].saturation += saturation * weight
                buckets[bucketIndex].weight += weight
            }
        }

        guard totalWeight > 0,
              chromaWeight / totalWeight > 0.12,
              let selectedBucket = buckets.max(by: {
                  let lhsScore = $0.weight * (0.65 + ($0.weight > 0 ? $0.saturation / $0.weight : 0) * 0.35)
                  let rhsScore = $1.weight * (0.65 + ($1.weight > 0 ? $1.saturation / $1.weight : 0) * 0.35)
                  return lhsScore < rhsScore
              }),
              selectedBucket.weight > 0
        else {
            return fallbackColor
        }

        return NSColor(
            srgbRed: selectedBucket.red / selectedBucket.weight,
            green: selectedBucket.green / selectedBucket.weight,
            blue: selectedBucket.blue / selectedBucket.weight,
            alpha: 1
        )
    }

    private static func sampledBitmap(for image: NSImage) -> NSBitmapImageRep? {
        if let bitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return bitmap
        }

        let targetSize = NSSize(width: 48, height: 48)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func normalizedHeaderColor(_ color: NSColor) -> NSColor? {
        guard let color = color.usingColorSpace(.sRGB) else {
            return nil
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if saturation < 0.14 {
            return NSColor(
                calibratedWhite: min(max(brightness, 0.26), 0.62),
                alpha: 1
            )
        }

        return NSColor(
            calibratedHue: hue,
            saturation: min(max(saturation, 0.28), 0.74),
            brightness: min(max(brightness, 0.58), 0.88),
            alpha: 1
        )
    }

    private func resolvedImageURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }

        return (appSupportDirectory ?? defaultAppSupportDirectory())
            .appendingPathComponent(path)
    }

    private func filePreviewURLs(for request: PanelCardAssetRequest) -> [URL] {
        if let snapshotPaths = fileSnapshotPaths(for: request), !snapshotPaths.isEmpty {
            return snapshotPaths.map(resolvedFileURL(for:))
        }

        return request.primaryText?
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map(resolvedFileURL(for:)) ?? []
    }

    private func fileSnapshotPaths(for request: PanelCardAssetRequest) -> [String]? {
        for path in [request.payloadAssetPath, request.previewAssetPath]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !path.isEmpty {
            let url = resolvedFileURL(for: path)
            guard let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(FileSnapshotPreviewDocument.self, from: data),
                  !document.paths.isEmpty
            else {
                continue
            }
            return document.paths
        }

        return nil
    }

    private func resolvedFileURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }

        return (appSupportDirectory ?? defaultAppSupportDirectory())
            .appendingPathComponent(path)
    }

    private func sourceColorKey(for request: PanelCardAssetRequest) -> String? {
        if let sourceAppID = request.sourceAppId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceAppID.isEmpty {
            return sourceAppID
        }

        if let sourceAppName = request.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceAppName.isEmpty {
            return sourceAppName
        }

        return nil
    }

    private func sourceHeaderColor(for key: String, isSelected: Bool) -> NSColor {
        let palette: [NSColor] = [
            .systemBlue,
            .systemPurple,
            .systemGreen,
            .systemOrange,
            .systemTeal,
            .systemPink,
            .systemIndigo,
            .systemMint,
            .systemBrown
        ]
        let index = stableColorIndex(for: key, count: palette.count)
        return palette[index].withAlphaComponent(isSelected ? 0.98 : 0.90)
    }

    private func stableColorIndex(for key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }

        return Int(hash % UInt64(count))
    }

    private func defaultAppSupportDirectory() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first?
        .appendingPathComponent("ClipboardWorkbench", isDirectory: true)
        ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private struct FileSnapshotPreviewDocument: Decodable {
        let paths: [String]
    }
}
