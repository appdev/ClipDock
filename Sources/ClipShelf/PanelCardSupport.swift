import AppKit
import ClipboardPanelApp
import CoreImage
import QuickLookThumbnailing

struct PanelCardResolvedItem {
    let sourceIconImage: NSImage?
    let sourceColorKey: String?
    let sourceIconColor: NSColor?
}

struct SourceAppIconHeaderColorWriteRequest: Hashable, Sendable {
    let sourceAppID: String
    let sourceAppIconPath: String
    let headerColorARGB: Int64
}

typealias SourceAppIconHeaderColorWriter =
    @Sendable (SourceAppIconHeaderColorWriteRequest) async -> Void

private struct SourceColorWriteKey: Hashable {
    let sourceAppID: String
    let sourceAppIconPath: String
    let cacheVersion: Int64
}

private enum SourceIconHeaderColorARGB {
    static let minimum: Int64 = 4_278_190_080
    static let maximum: Int64 = 4_294_967_295
}

struct PanelCardPreviewImageState {
    let paths: [String]
    let image: NSImage?
    let tooltip: String
    let fallbackText: String
}

struct PanelFilePreviewThumbnailToken: Sendable {
    let cacheKey: String
    let callbackID: UUID
}

struct PanelPreviewImageLoadToken: Sendable {
    let callbackID: UUID
}

private struct LoadedPreviewImage: @unchecked Sendable {
    let image: NSImage
}

@MainActor
final class PanelCardAssetResolver {
    private static let imageCache = NSCache<NSString, NSImage>()
    private static let fileThumbnailCache = NSCache<NSString, NSImage>()
    private static var fileThumbnailInFlight: [String: FileThumbnailInFlight] = [:]
    static var fileThumbnailGenerationDelayForSmoke: Duration?
    private static var previewImageLoadTasks: [UUID: Task<Void, Never>] = [:]
    static var previewImageLoadDelayForSmoke: Duration?

    static func previewImageLoadIsActiveForSmoke(_ token: PanelPreviewImageLoadToken) -> Bool {
        previewImageLoadTasks[token.callbackID] != nil
    }

    static func primePreviewImageCacheForSmoke(paths: [String]) {
        for path in paths {
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else { continue }
            let key = trimmedPath as NSString
            guard imageCache.object(forKey: key) == nil else { continue }
            let url = URL(fileURLWithPath: trimmedPath)
            let image = NSImage(contentsOf: url)
                ?? ((try? Data(contentsOf: url)).flatMap(NSImage.init(data:)))
            if let image {
                imageCache.setObject(image, forKey: key)
            }
        }
    }

    private static let sourceColorCache = NSCache<NSString, NSColor>()
    private static var sourceColorWriteInFlight: Set<SourceColorWriteKey> = []
    private static let sourceColorContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    private let appSupportDirectory: URL?
    private let sourceIconHeaderColorWriter: SourceAppIconHeaderColorWriter?
    private let sourceIconImageLoader: @MainActor (String) -> NSImage?
    private let dominantHeaderColorProvider: @MainActor (NSImage, String?, String?) -> NSColor?
    private let loadSourceIconsSynchronously: Bool

    init(
        appSupportDirectory: URL?,
        sourceIconHeaderColorWriter: SourceAppIconHeaderColorWriter? = nil,
        sourceIconImageLoader: (@MainActor (String) -> NSImage?)? = nil,
        dominantHeaderColorProvider: (@MainActor (NSImage, String?, String?) -> NSColor?)? = nil,
        loadSourceIconsSynchronously: Bool = true
    ) {
        self.appSupportDirectory = appSupportDirectory
        self.sourceIconHeaderColorWriter = sourceIconHeaderColorWriter
        self.sourceIconImageLoader = sourceIconImageLoader ?? PanelCardAssetResolver.loadCachedImage(path:)
        self.dominantHeaderColorProvider = dominantHeaderColorProvider
            ?? PanelCardAssetResolver.dominantHeaderColor(for:cacheKey:fallbackCacheKey:)
        self.loadSourceIconsSynchronously = loadSourceIconsSynchronously
    }

    func resolvedItem(for request: PanelCardAssetRequest) -> PanelCardResolvedItem {
        let sourceIconImage = sourceIconImage(for: request)
        let sourceColorKey = sourceColorKey(for: request)
        let sourceColorCacheKey = sourceColorKey ?? request.sourceAppIconPath
        let sourceIconColor = Self.headerColor(fromOpaqueARGB: request.sourceAppIconHeaderColor)
            ?? sourceIconImage.flatMap {
                dominantHeaderColorProvider(
                    $0,
                    sourceColorCacheKey,
                    request.sourceAppIconPath
                )
            }

        if request.sourceAppIconHeaderColor == nil, let sourceIconColor {
            persistComputedHeaderColor(sourceIconColor, for: request)
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
        guard let path = request.sourceAppIconPath else { return nil }
        guard loadSourceIconsSynchronously else {
            return Self.cachedImageInMemory(path: path)
        }
        return sourceIconImageLoader(path)
    }

    private func persistComputedHeaderColor(_ color: NSColor, for request: PanelCardAssetRequest) {
        guard let sourceIconHeaderColorWriter,
              let sourceAppID = request.sourceAppId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceAppID.isEmpty,
              let sourceAppIconPath = request.sourceAppIconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceAppIconPath.isEmpty,
              let headerColorARGB = Self.opaqueARGB(from: color)
        else {
            return
        }

        let cacheVersion = RustCoreClient.activeSourceIconHeaderColorCacheVersion()
        let key = SourceColorWriteKey(
            sourceAppID: sourceAppID,
            sourceAppIconPath: sourceAppIconPath,
            cacheVersion: cacheVersion
        )
        guard !Self.sourceColorWriteInFlight.contains(key) else {
            return
        }
        Self.sourceColorWriteInFlight.insert(key)

        let writeRequest = SourceAppIconHeaderColorWriteRequest(
            sourceAppID: sourceAppID,
            sourceAppIconPath: sourceAppIconPath,
            headerColorARGB: headerColorARGB
        )
        Task { @MainActor in
            await sourceIconHeaderColorWriter(writeRequest)
            Self.sourceColorWriteInFlight.remove(key)
        }
    }

    func filePreviewImage(
        for request: PanelCardAssetRequest,
        maximumSize: NSSize = NSSize(width: 96, height: 96),
        scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    ) -> NSImage? {
        for path in existingPreviewImagePaths(paths: [request.previewAssetPath]) {
            if let image = Self.loadCachedImage(path: path) {
                return image
            }
        }

        let urls = filePreviewURLs(for: request)
        if let cachedThumbnail = Self.cachedFileThumbnail(
            urls: urls,
            maximumSize: maximumSize,
            scale: scale
        ) {
            return cachedThumbnail
        }

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 96, height: 96)
            return icon
        }

        return NSImage(systemSymbolName: "folder", accessibilityDescription: "文件")
    }

    func filePreviewURLs(for request: PanelCardAssetRequest) -> [URL] {
        ClipboardFilePreviewResolver.fileURLsFromPrimaryText(
            request.primaryText,
            appSupportDirectory: appSupportDirectory ?? defaultAppSupportDirectory()
        )
    }

    @discardableResult
    static func loadFilePreviewImageAsync(
        urls: [URL],
        maximumSize: NSSize,
        scale: CGFloat,
        completion: @escaping @MainActor (NSImage?) -> Void
    ) -> PanelFilePreviewThumbnailToken? {
        guard let requestInfo = fileThumbnailRequestInfo(
            urls: urls,
            maximumSize: maximumSize,
            scale: scale
        ) else {
            completion(nil)
            return nil
        }

        let callbackID = UUID()
        let token = PanelFilePreviewThumbnailToken(
            cacheKey: requestInfo.cacheKey,
            callbackID: callbackID
        )
        if let cachedImage = fileThumbnailCache.object(forKey: requestInfo.cacheKey as NSString) {
            completion(cachedImage)
            return token
        }

        if var inFlight = fileThumbnailInFlight[requestInfo.cacheKey] {
            inFlight.completions[callbackID] = completion
            fileThumbnailInFlight[requestInfo.cacheKey] = inFlight
            return token
        }

        let thumbnailRequest = QLThumbnailGenerator.Request(
            fileAt: requestInfo.url,
            size: maximumSize,
            scale: scale,
            representationTypes: .thumbnail
        )
        fileThumbnailInFlight[requestInfo.cacheKey] = FileThumbnailInFlight(
            request: thumbnailRequest,
            completions: [callbackID: completion]
        )
        if let delay = fileThumbnailGenerationDelayForSmoke {
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard fileThumbnailInFlight[requestInfo.cacheKey] != nil else { return }
                generateFileThumbnail(requestInfo: requestInfo, thumbnailRequest: thumbnailRequest)
            }
            return token
        }
        generateFileThumbnail(requestInfo: requestInfo, thumbnailRequest: thumbnailRequest)
        return token
    }

    nonisolated private static func generateFileThumbnail(
        requestInfo: FileThumbnailRequestInfo,
        thumbnailRequest: QLThumbnailGenerator.Request
    ) {
        QuickLookFileThumbnailBridge.generateBestRepresentation(for: thumbnailRequest) { imageData in
            Task { @MainActor in
                let image = imageData.flatMap(NSImage.init(data:))
                if let image {
                    fileThumbnailCache.setObject(image, forKey: requestInfo.cacheKey as NSString)
                }
                guard let inFlight = fileThumbnailInFlight.removeValue(forKey: requestInfo.cacheKey) else {
                    return
                }
                inFlight.completions.values.forEach { $0(image) }
            }
        }
    }

    static func cancelFilePreviewImageRequest(_ token: PanelFilePreviewThumbnailToken?) {
        guard let token,
              var inFlight = fileThumbnailInFlight[token.cacheKey]
        else {
            return
        }

        inFlight.completions[token.callbackID] = nil
        if inFlight.completions.isEmpty {
            QuickLookFileThumbnailBridge.cancel(inFlight.request)
            fileThumbnailInFlight[token.cacheKey] = nil
        } else {
            fileThumbnailInFlight[token.cacheKey] = inFlight
        }
    }

    static func filePreviewImageRequestIsActiveForSmoke(_ token: PanelFilePreviewThumbnailToken) -> Bool {
        fileThumbnailInFlight[token.cacheKey]?.completions[token.callbackID] != nil
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
            return sourceIconColor.withAlphaComponent(isSelected ? 1 : 0.96)
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

    @discardableResult
    static func loadPreviewImageAsync(
        paths: [String],
        completion: @escaping @MainActor @Sendable (NSImage?) -> Void
    ) -> PanelPreviewImageLoadToken? {
        guard !paths.isEmpty else {
            completion(nil)
            return nil
        }

        let callbackID = UUID()
        let token = PanelPreviewImageLoadToken(callbackID: callbackID)
        let task = Task.detached(priority: .userInitiated) {
            if let delay = await MainActor.run(body: { previewImageLoadDelayForSmoke }) {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }

            let loadedImage: (String, LoadedPreviewImage)?
            do {
                loadedImage = try Self.loadPreviewImage(paths: paths)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let currentTask = previewImageLoadTasks.removeValue(forKey: callbackID),
                      !currentTask.isCancelled
                else {
                    return
                }

                guard let (path, loadedImage) = loadedImage else {
                    completion(nil)
                    return
                }

                let image = loadedImage.image
                imageCache.setObject(image, forKey: path as NSString)
                completion(image)
            }
        }
        previewImageLoadTasks[callbackID] = task
        return token
    }

    static func cancelPreviewImageLoad(_ token: PanelPreviewImageLoadToken?) {
        guard let token,
              let task = previewImageLoadTasks.removeValue(forKey: token.callbackID)
        else {
            return
        }
        task.cancel()
    }

    private nonisolated static func loadPreviewImage(
        paths: [String]
    ) throws -> (String, LoadedPreviewImage)? {
        for path in paths {
            guard !Task.isCancelled else { throw CancellationError() }
            let url = URL(fileURLWithPath: path)
            if let data = try? cancellableData(contentsOf: url),
               let image = NSImage(data: data) {
                return (path, LoadedPreviewImage(image: image))
            }
        }
        return nil
    }

    private nonisolated static func cancellableData(contentsOf url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var data = Data()
        while true {
            guard !Task.isCancelled else { throw CancellationError() }
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
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

    private static func cachedImageInMemory(path: String) -> NSImage? {
        imageCache.object(forKey: path as NSString)
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

    private static func headerColor(fromOpaqueARGB argb: Int64?) -> NSColor? {
        guard let argb,
              (SourceIconHeaderColorARGB.minimum...SourceIconHeaderColorARGB.maximum).contains(argb)
        else {
            return nil
        }

        let red = CGFloat((argb >> 16) & 0xFF) / 255
        let green = CGFloat((argb >> 8) & 0xFF) / 255
        let blue = CGFloat(argb & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    private static func opaqueARGB(from color: NSColor) -> Int64? {
        guard let color = color.usingColorSpace(.sRGB) else {
            return nil
        }

        func byte(_ value: CGFloat) -> Int64 {
            Int64(min(max((value * 255).rounded(), 0), 255))
        }

        let red = byte(color.redComponent)
        let green = byte(color.greenComponent)
        let blue = byte(color.blueComponent)
        return 0xFF00_0000 + (red << 16) + (green << 8) + blue
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
              let selectedBucket = buckets.max(by: {
                  let lhsScore = $0.weight * (0.65 + ($0.weight > 0 ? $0.saturation / $0.weight : 0) * 0.35)
                  let rhsScore = $1.weight * (0.65 + ($1.weight > 0 ? $1.saturation / $1.weight : 0) * 0.35)
                  return lhsScore < rhsScore
              }),
              selectedBucket.weight > 0,
              selectedBucket.saturation / selectedBucket.weight >= 0.32,
              (selectedBucket.weight / totalWeight >= 0.035 || chromaWeight / totalWeight >= 0.08)
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
            saturation: min(max(saturation, 0.78), 0.86),
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
        .appendingPathComponent("ClipShelf", isDirectory: true)
        ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private static func cachedFileThumbnail(
        urls: [URL],
        maximumSize: NSSize,
        scale: CGFloat
    ) -> NSImage? {
        guard let requestInfo = fileThumbnailRequestInfo(
            urls: urls,
            maximumSize: maximumSize,
            scale: scale
        ) else {
            return nil
        }

        return fileThumbnailCache.object(forKey: requestInfo.cacheKey as NSString)
    }

    private static func fileThumbnailRequestInfo(
        urls: [URL],
        maximumSize: NSSize,
        scale: CGFloat
    ) -> FileThumbnailRequestInfo? {
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardizedURL.path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: standardizedURL.path)
            else {
                continue
            }

            let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let cacheKey = [
                standardizedURL.path,
                "mtime=\(modifiedAt)",
                "size=\(size)",
                "width=\(Int(maximumSize.width.rounded()))",
                "height=\(Int(maximumSize.height.rounded()))",
                "scale=\(scale)",
                "representation=thumbnail"
            ].joined(separator: "|")
            return FileThumbnailRequestInfo(url: standardizedURL, cacheKey: cacheKey)
        }

        return nil
    }
}

private enum QuickLookFileThumbnailBridge {
    nonisolated static func generateBestRepresentation(
        for request: QLThumbnailGenerator.Request,
        completion: @escaping @Sendable (Data?) -> Void
    ) {
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            completion(representation?.nsImage.tiffRepresentation)
        }
    }

    nonisolated static func cancel(_ request: QLThumbnailGenerator.Request) {
        QLThumbnailGenerator.shared.cancel(request)
    }
}

private struct FileThumbnailRequestInfo: Sendable {
    let url: URL
    let cacheKey: String
}

private struct FileThumbnailInFlight {
    let request: QLThumbnailGenerator.Request
    var completions: [UUID: @MainActor (NSImage?) -> Void]
}
