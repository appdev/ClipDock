import AppKit
import AVFoundation
import ClipboardPanelApp
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
protocol SourceAppIconCaching {
    func cacheIcon(for source: ClipboardCaptureSource?) -> String?
}

protocol ClipboardImageAssetCaching {
    func cacheImage(_ capturedImage: ClipboardCapturedImage, changeCount: Int) -> ClipboardStoredImageAsset?
}

@MainActor
protocol ClipboardFileSnapshotCaching {
    func cacheFiles(_ files: ClipboardCapturedFiles, changeCount: Int) -> ClipboardStoredFileSnapshot?
}

struct PlatformAssetDirectories {
    let appSupportURL: URL
    let iconCacheDirectoryURL: URL
    let imagePayloadDirectoryURL: URL
    let imageThumbnailDirectoryURL: URL
    let fileSnapshotDirectoryURL: URL

    init(appSupportURL: URL) {
        self.appSupportURL = appSupportURL
        self.iconCacheDirectoryURL = appSupportURL.appendingPathComponent("app-icons", isDirectory: true)
        self.imagePayloadDirectoryURL = appSupportURL.appendingPathComponent("assets", isDirectory: true)
        self.imageThumbnailDirectoryURL = appSupportURL.appendingPathComponent("thumbnails", isDirectory: true)
        self.fileSnapshotDirectoryURL = appSupportURL
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("file-snapshots", isDirectory: true)
    }
}

struct PlatformAssetFileStemFactory {
    private let timestampProvider: () -> Int64
    private let uuidProvider: () -> UUID

    init(
        timestampProvider: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1000)
        },
        uuidProvider: @escaping () -> UUID = {
            UUID()
        }
    ) {
        self.timestampProvider = timestampProvider
        self.uuidProvider = uuidProvider
    }

    func makeFileStem(prefix: String, changeCount: Int) -> String {
        "\(prefix)-\(changeCount)-\(timestampProvider())-\(uuidProvider().uuidString)"
    }
}

@MainActor
final class SourceAppIconProvider: SourceAppIconCaching {
    private static let iconPixelSize = 512
    private static let iconFileExtension = "png"

    private let directories: PlatformAssetDirectories
    private let fileManager: FileManager

    init(appSupportURL: URL, fileManager: FileManager = .default) {
        self.directories = PlatformAssetDirectories(appSupportURL: appSupportURL)
        self.fileManager = fileManager
    }

    func cacheIcon(for source: ClipboardCaptureSource?) -> String? {
        guard let source else { return nil }

        let fileName = "\(safeCacheKey(for: source)).\(Self.iconFileExtension)"
        let fileURL = directories.iconCacheDirectoryURL.appendingPathComponent(fileName)
        let relativePath = "app-icons/\(fileName)"
        if fileManager.fileExists(atPath: fileURL.path) {
            return relativePath
        }

        guard let image = iconImage(for: source),
              let data = Self.normalizedPNGData(for: image)
        else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: directories.iconCacheDirectoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return relativePath
        } catch {
            return nil
        }
    }

    private func iconImage(for source: ClipboardCaptureSource) -> NSImage? {
        if let iconTIFFData = source.iconTIFFData,
           let image = NSImage(data: iconTIFFData) {
            return image
        }

        return source.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
    }

    private static func normalizedPNGData(for image: NSImage) -> Data? {
        let pixelSize = iconPixelSize
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
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
        bitmap.size = NSSize(width: CGFloat(pixelSize), height: CGFloat(pixelSize))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(pixelSize), height: CGFloat(pixelSize)).fill()
        image.draw(
            in: aspectFitRect(for: image, pixelSize: pixelSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func aspectFitRect(for image: NSImage, pixelSize: Int) -> NSRect {
        let targetLength = CGFloat(pixelSize)
        let fallbackSize = NSSize(width: targetLength, height: targetLength)
        let imageSize = image.size.width > 0 && image.size.height > 0 ? image.size : fallbackSize
        let bounds = NSRect(x: 0, y: 0, width: targetLength, height: targetLength)
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = NSSize(
            width: floor(imageSize.width * scale),
            height: floor(imageSize.height * scale)
        )
        return NSRect(
            x: floor(bounds.midX - drawSize.width / 2),
            y: floor(bounds.midY - drawSize.height / 2),
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private func safeCacheKey(for source: ClipboardCaptureSource) -> String {
        let rawValue = source.bundleId ?? source.bundlePath ?? source.appName ?? "unknown"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = rawValue.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return value.isEmpty ? "unknown" : value
    }
}

struct CapturedClipboardFiles: Sendable {
    let urls: [URL]
    let fileItems: [ClipboardCapturedFileMetadata]
    let preview: ClipboardStoredFilePreview?

    init(
        urls: [URL],
        fileItems: [ClipboardCapturedFileMetadata] = [],
        preview: ClipboardStoredFilePreview? = nil
    ) {
        self.urls = urls
        self.fileItems = fileItems
        self.preview = preview
    }

    var paths: [String] {
        urls.map(\.path)
    }

    static func read(from pasteboard: NSPasteboard) -> CapturedClipboardFiles? {
        var urls: [URL] = []

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let objectURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] {
            urls.append(contentsOf: objectURLs)
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let fileURL = URL(string: fileURLString) {
            urls.append(fileURL)
        }

        if let filenames = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            urls.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
        }

        var seenPaths = Set<String>()
        let fileURLs = urls.compactMap(normalizedFileURL).filter { url in
            seenPaths.insert(url.path).inserted
        }

        return fileURLs.isEmpty ? nil : CapturedClipboardFiles(urls: fileURLs)
    }

    func collectingMetadata() async -> CapturedClipboardFiles {
        await Self.collectingMetadata(for: urls)
    }

    static func collectingMetadata(for urls: [URL]) async -> CapturedClipboardFiles {
        var fileItems: [ClipboardCapturedFileMetadata?] = Array(repeating: nil, count: urls.count)

        await withTaskGroup(of: (Int, ClipboardCapturedFileMetadata).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    (index, await fileMetadata(for: url))
                }
            }

            for await (index, item) in group {
                fileItems[index] = item
            }
        }

        return CapturedClipboardFiles(
            urls: urls,
            fileItems: fileItems.compactMap { $0 },
            preview: nil
        )
    }

    func withPreview(_ preview: ClipboardStoredFilePreview?) -> CapturedClipboardFiles {
        CapturedClipboardFiles(urls: urls, fileItems: fileItems, preview: preview)
    }

    private static func normalizedFileURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        return URL(fileURLWithPath: url.path).standardizedFileURL
    }

    private static func fileMetadata(for url: URL) async -> ClipboardCapturedFileMetadata {
        let resourceKeys: Set<URLResourceKey> = [
            .nameKey,
            .fileSizeKey,
            .isDirectoryKey,
            .contentTypeKey
        ]
        let values = try? url.resourceValues(forKeys: resourceKeys)
        let isDirectory = values?.isDirectory ?? false
        let imageSize = imagePixelSize(for: url, contentType: values?.contentType)
        let videoSize = imageSize == nil
            ? await videoPixelSize(for: url, contentType: values?.contentType)
            : nil
        let resolvedSize = imageSize ?? videoSize

        return ClipboardCapturedFileMetadata(
            path: url.path,
            fileName: values?.name ?? url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            byteCount: isDirectory ? 0 : Int64(values?.fileSize ?? 0),
            isDirectory: isDirectory,
            width: resolvedSize.map { Int64($0.width.rounded()) },
            height: resolvedSize.map { Int64($0.height.rounded()) },
            contentType: values?.contentType?.identifier
        )
    }

    private static func imagePixelSize(for url: URL, contentType: UTType?) -> CGSize? {
        guard contentType?.conforms(to: .image) == true
        else {
            return nil
        }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                imageSource,
                0,
                options
              ) as? [CFString: Any],
              let width = pixelDimension(properties[kCGImagePropertyPixelWidth]),
              let height = pixelDimension(properties[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0
        else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private static func videoPixelSize(for url: URL, contentType: UTType?) async -> CGSize? {
        guard contentType?.conforms(to: .movie) == true
                || contentType?.conforms(to: .video) == true
        else {
            return nil
        }
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let naturalSize = try? await track.load(.naturalSize)
        else {
            return nil
        }
        let preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        let transformedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let size = CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )

        guard size.width > 0, size.height > 0 else {
            return nil
        }
        return size
    }

    private static func pixelDimension(_ value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            return CGFloat(truncating: number)
        case let value as CGFloat:
            return value
        case let value as Double:
            return CGFloat(value)
        case let value as Int:
            return CGFloat(value)
        default:
            return nil
        }
    }
}

private struct ClipboardFileSnapshotDocument: Codable {
    let paths: [String]
}

@MainActor
final class ClipboardFileSnapshotProvider: ClipboardFileSnapshotCaching {
    private let directories: PlatformAssetDirectories
    private let fileManager: FileManager
    private let fileStemFactory: PlatformAssetFileStemFactory

    init(
        appSupportURL: URL,
        fileManager: FileManager = .default,
        fileStemFactory: PlatformAssetFileStemFactory = PlatformAssetFileStemFactory()
    ) {
        self.directories = PlatformAssetDirectories(appSupportURL: appSupportURL)
        self.fileManager = fileManager
        self.fileStemFactory = fileStemFactory
    }

    func cacheFiles(_ files: ClipboardCapturedFiles, changeCount: Int) -> ClipboardStoredFileSnapshot? {
        let fileStem = fileStemFactory.makeFileStem(prefix: "files", changeCount: changeCount)
        let snapshotURL = directories.fileSnapshotDirectoryURL.appendingPathComponent("\(fileStem).json")
        let document = ClipboardFileSnapshotDocument(paths: files.paths)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            try fileManager.createDirectory(
                at: directories.fileSnapshotDirectoryURL,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(document)
            try data.write(to: snapshotURL, options: .atomic)
            return ClipboardStoredFileSnapshot(
                relativePath: "assets/file-snapshots/\(fileStem).json",
                byteCount: data.count
            )
        } catch {
            return nil
        }
    }
}

@MainActor
final class ClipboardFilePreviewProvider {
    private enum Layout {
        static let thumbnailPointSize = NSSize(width: 640, height: 640)
        static let fallbackIconPixelSize = 512
    }

    private let directories: PlatformAssetDirectories
    private let fileManager: FileManager
    private let fileStemFactory: PlatformAssetFileStemFactory
    private let scaleProvider: @MainActor () -> CGFloat

    init(
        appSupportURL: URL,
        fileManager: FileManager = .default,
        fileStemFactory: PlatformAssetFileStemFactory = PlatformAssetFileStemFactory(),
        scaleProvider: @escaping @MainActor () -> CGFloat = {
            NSScreen.main?.backingScaleFactor ?? 2
        }
    ) {
        self.directories = PlatformAssetDirectories(appSupportURL: appSupportURL)
        self.fileManager = fileManager
        self.fileStemFactory = fileStemFactory
        self.scaleProvider = scaleProvider
    }

    func cachePreview(
        for files: CapturedClipboardFiles,
        changeCount: Int
    ) async -> ClipboardStoredFilePreview? {
        guard let sourceURL = files.urls.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }

        let scale = scaleProvider()
        let image = await quickLookThumbnail(for: sourceURL, scale: scale)
            ?? fallbackIcon(for: sourceURL)
        guard let pngData = image.pngRepresentation(),
              !pngData.isEmpty
        else {
            return nil
        }

        let fileStem = fileStemFactory.makeFileStem(prefix: "file-thumbnail", changeCount: changeCount)
        let thumbnailURL = directories.imageThumbnailDirectoryURL.appendingPathComponent("\(fileStem).png")
        let stagingDirectoryURL = directories.appSupportURL
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent("file-thumbnails", isDirectory: true)
        let stagingURL = stagingDirectoryURL.appendingPathComponent("\(fileStem).png")

        do {
            try fileManager.createDirectory(
                at: directories.imageThumbnailDirectoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: stagingDirectoryURL,
                withIntermediateDirectories: true
            )
            try pngData.write(to: stagingURL, options: .atomic)
            try fileManager.moveItem(at: stagingURL, to: thumbnailURL)
        } catch {
            removeFileIfExists(thumbnailURL)
            removeFileIfExists(stagingURL)
            return nil
        }

        let dimensions = NSImage(data: pngData)?.pixelDimensions ?? image.pixelDimensions
        return ClipboardStoredFilePreview(
            relativePath: "thumbnails/\(fileStem).png",
            mimeType: "image/png",
            width: dimensions.width,
            height: dimensions.height,
            byteCount: pngData.count
        )
    }

    private func quickLookThumbnail(for url: URL, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: Layout.thumbnailPointSize,
            scale: scale,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    private func fallbackIcon(for url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(
            width: Layout.fallbackIconPixelSize,
            height: Layout.fallbackIconPixelSize
        )
        return icon
    }

    private func removeFileIfExists(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}

struct ClipboardCGImageSnapshot: @unchecked Sendable {
    let image: CGImage
}

enum ClipboardBitmapImageSource: Sendable {
    case encodedData(Data, typeIdentifier: String)
    case cgImage(ClipboardCGImageSnapshot)
}

struct CapturedClipboardImage: Sendable {
    let source: ClipboardBitmapImageSource

    static func read(from pasteboard: NSPasteboard, skipFileURLCheck: Bool = false) -> CapturedClipboardImage? {
        guard skipFileURLCheck || CapturedClipboardFiles.read(from: pasteboard) == nil else {
            return nil
        }

        for candidate in pasteboardBitmapDataTypes {
            if let data = pasteboard.data(forType: candidate.pasteboardType), !data.isEmpty {
                return CapturedClipboardImage(
                    source: .encodedData(data, typeIdentifier: candidate.typeIdentifier)
                )
            }
        }

        let images = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        ) as? [NSImage]
        if let image = images?.first,
           let snapshot = snapshot(from: image) {
            return snapshot
        }

        return nil
    }

    static func snapshot(from image: NSImage) -> CapturedClipboardImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return CapturedClipboardImage(
            source: .cgImage(ClipboardCGImageSnapshot(image: cgImage))
        )
    }

    private static let pasteboardBitmapDataTypes: [(pasteboardType: NSPasteboard.PasteboardType, typeIdentifier: String)] = [
        (.png, UTType.png.identifier),
        (NSPasteboard.PasteboardType("public.png"), UTType.png.identifier),
        (.tiff, UTType.tiff.identifier),
        (NSPasteboard.PasteboardType("public.tiff"), UTType.tiff.identifier),
        (NSPasteboard.PasteboardType("public.jpeg"), UTType.jpeg.identifier),
        (NSPasteboard.PasteboardType("public.heic"), UTType.heic.identifier)
    ]
}

extension CapturedClipboardFiles {
    var clipboardCapturedFiles: ClipboardCapturedFiles {
        ClipboardCapturedFiles(paths: paths, fileItems: fileItems, preview: preview)
    }
}

final class ClipboardImageAssetProvider: ClipboardImageAssetCaching, @unchecked Sendable {
    enum FinalizationError: Error, Equatable {
        case imageDecodeFailed
        case rgbaRenderFailed
        case webPEncodingFailed
        case assetWriteFailed
    }

    struct PreparedImageAsset: Sendable {
        let storedImage: ClipboardStoredImageAsset
        fileprivate let payloadURL: URL
        fileprivate let thumbnailURL: URL
        fileprivate let stagingPayloadURL: URL
        fileprivate let stagingThumbnailURL: URL
    }

    private let directories: PlatformAssetDirectories
    private let fileManager: FileManager
    private let fileStemFactory: PlatformAssetFileStemFactory
    private let encoder: ClipboardWebPEncoding

    init(
        appSupportURL: URL,
        fileManager: FileManager = .default,
        fileStemFactory: PlatformAssetFileStemFactory = PlatformAssetFileStemFactory(),
        encoder: ClipboardWebPEncoding = RustClipboardWebPEncoder()
    ) {
        self.directories = PlatformAssetDirectories(appSupportURL: appSupportURL)
        self.fileManager = fileManager
        self.fileStemFactory = fileStemFactory
        self.encoder = encoder
    }

    func cacheImage(_ capturedImage: ClipboardCapturedImage, changeCount: Int) -> ClipboardStoredImageAsset? {
        let fileStem = fileStemFactory.makeFileStem(prefix: "image", changeCount: changeCount)
        let fileExtension = capturedImage.normalizedImageFileExtension
        let payloadURL = directories.imagePayloadDirectoryURL.appendingPathComponent("\(fileStem).\(fileExtension)")
        let thumbnailURL = directories.imageThumbnailDirectoryURL.appendingPathComponent("\(fileStem).\(fileExtension)")
        let stagingDirectoryURL = directories.appSupportURL
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent("image-captures", isDirectory: true)
        let stagingPayloadURL = stagingDirectoryURL.appendingPathComponent("\(fileStem)-payload.\(fileExtension)")
        let stagingThumbnailURL = stagingDirectoryURL.appendingPathComponent("\(fileStem)-thumbnail.\(fileExtension)")
        let thumbnailData = capturedImage.thumbnailData

        do {
            try fileManager.createDirectory(
                at: directories.imagePayloadDirectoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: directories.imageThumbnailDirectoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: stagingDirectoryURL,
                withIntermediateDirectories: true
            )
            try capturedImage.data.write(to: stagingPayloadURL, options: .atomic)
            try thumbnailData.write(to: stagingThumbnailURL, options: .atomic)
            try fileManager.moveItem(at: stagingPayloadURL, to: payloadURL)
            do {
                try fileManager.moveItem(at: stagingThumbnailURL, to: thumbnailURL)
            } catch {
                removeFileIfExists(payloadURL)
                throw error
            }
        } catch {
            removeFileIfExists(payloadURL)
            removeFileIfExists(thumbnailURL)
            removeFileIfExists(stagingPayloadURL)
            removeFileIfExists(stagingThumbnailURL)
            return nil
        }

        return ClipboardStoredImageAsset(
            payloadRelativePath: "assets/\(fileStem).\(fileExtension)",
            previewRelativePath: "thumbnails/\(fileStem).\(fileExtension)",
            mimeType: capturedImage.mimeType,
            width: capturedImage.width,
            height: capturedImage.height,
            byteCount: capturedImage.data.count
        )
    }

    func prepareImage(
        _ capturedImage: CapturedClipboardImage,
        changeCount: Int
    ) -> Result<PreparedImageAsset, FinalizationError> {
        let fileStem = fileStemFactory.makeFileStem(prefix: "image", changeCount: changeCount)
        let payloadURL = directories.imagePayloadDirectoryURL.appendingPathComponent("\(fileStem).webp")
        let thumbnailURL = directories.imageThumbnailDirectoryURL.appendingPathComponent("\(fileStem).webp")
        let stagingDirectoryURL = directories.appSupportURL
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent("image-captures", isDirectory: true)
        let stagingPayloadURL = stagingDirectoryURL.appendingPathComponent("\(fileStem)-payload.webp")
        let stagingThumbnailURL = stagingDirectoryURL.appendingPathComponent("\(fileStem)-thumbnail.webp")
        let prepared = PreparedImageAsset(
            storedImage: ClipboardStoredImageAsset(
                payloadRelativePath: "assets/\(fileStem).webp",
                previewRelativePath: "thumbnails/\(fileStem).webp",
                mimeType: "image/webp",
                width: 0,
                height: 0,
                byteCount: 0
            ),
            payloadURL: payloadURL,
            thumbnailURL: thumbnailURL,
            stagingPayloadURL: stagingPayloadURL,
            stagingThumbnailURL: stagingThumbnailURL
        )

        do {
            try fileManager.createDirectory(
                at: directories.imagePayloadDirectoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: directories.imageThumbnailDirectoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: stagingDirectoryURL,
                withIntermediateDirectories: true
            )

            let fullImage = try renderFullSizeRGBA(from: capturedImage.source)
            guard let payloadData = encoder.encodeLosslessRGBA(
                fullImage.data,
                width: fullImage.width,
                height: fullImage.height
            ), !payloadData.isEmpty else {
                throw FinalizationError.webPEncodingFailed
            }

            let thumbnailImage = try renderThumbnailRGBA(from: capturedImage.source)
            guard let thumbnailData = encoder.encodeLosslessRGBA(
                thumbnailImage.data,
                width: thumbnailImage.width,
                height: thumbnailImage.height
            ), !thumbnailData.isEmpty else {
                throw FinalizationError.webPEncodingFailed
            }

            try payloadData.write(to: stagingPayloadURL, options: .atomic)
            try thumbnailData.write(to: stagingThumbnailURL, options: .atomic)
            try fileManager.moveItem(at: stagingPayloadURL, to: payloadURL)
            do {
                try fileManager.moveItem(at: stagingThumbnailURL, to: thumbnailURL)
            } catch {
                removeFileIfExists(payloadURL)
                throw error
            }

            return .success(PreparedImageAsset(
                storedImage: ClipboardStoredImageAsset(
                    payloadRelativePath: "assets/\(fileStem).webp",
                    previewRelativePath: "thumbnails/\(fileStem).webp",
                    mimeType: "image/webp",
                    width: fullImage.width,
                    height: fullImage.height,
                    byteCount: payloadData.count
                ),
                payloadURL: payloadURL,
                thumbnailURL: thumbnailURL,
                stagingPayloadURL: stagingPayloadURL,
                stagingThumbnailURL: stagingThumbnailURL
            ))
        } catch let error as FinalizationError {
            removePreparedImage(prepared)
            return .failure(error)
        } catch {
            removePreparedImage(prepared)
            return .failure(.assetWriteFailed)
        }
    }

    func removePreparedImage(_ preparedImage: PreparedImageAsset) {
        removeFileIfExists(preparedImage.payloadURL)
        removeFileIfExists(preparedImage.thumbnailURL)
        removeFileIfExists(preparedImage.stagingPayloadURL)
        removeFileIfExists(preparedImage.stagingThumbnailURL)
    }

    private func removeFileIfExists(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func renderFullSizeRGBA(
        from source: ClipboardBitmapImageSource
    ) throws -> RenderedClipboardRGBAImage {
        switch source {
        case .encodedData(let data, _):
            let cgImage = try transformedImage(from: data, maxPixelDimension: nil)
            return try Self.renderRGBA(from: cgImage)

        case .cgImage(let snapshot):
            return try Self.renderRGBA(from: snapshot.image)
        }
    }

    private func renderThumbnailRGBA(
        from source: ClipboardBitmapImageSource
    ) throws -> RenderedClipboardRGBAImage {
        switch source {
        case .encodedData(let data, _):
            let cgImage = try transformedImage(from: data, maxPixelDimension: 420)
            return try Self.renderRGBA(from: cgImage)

        case .cgImage(let snapshot):
            return try Self.renderRGBA(from: snapshot.image, maxPixelDimension: 420)
        }
    }

    private func transformedImage(
        from data: Data,
        maxPixelDimension: Int?
    ) throws -> CGImage {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw FinalizationError.imageDecodeFailed
        }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]
        if let maxPixelDimension {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelDimension
        }

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary
        ) else {
            throw FinalizationError.imageDecodeFailed
        }
        return image
    }

    private struct RenderedClipboardRGBAImage {
        let data: Data
        let width: Int
        let height: Int
    }

    private static func renderRGBA(
        from cgImage: CGImage,
        maxPixelDimension: Int? = nil
    ) throws -> RenderedClipboardRGBAImage {
        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw FinalizationError.rgbaRenderFailed
        }

        let targetSize = targetPixelSize(
            width: sourceWidth,
            height: sourceHeight,
            maxPixelDimension: maxPixelDimension
        )
        let rowByteCount = targetSize.width.multipliedReportingOverflow(by: 4)
        guard !rowByteCount.overflow else {
            throw FinalizationError.rgbaRenderFailed
        }
        let bytesPerRow = rowByteCount.partialValue
        let byteCount = bytesPerRow.multipliedReportingOverflow(by: targetSize.height)
        guard !byteCount.overflow else {
            throw FinalizationError.rgbaRenderFailed
        }
        var data = Data(count: byteCount.partialValue)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let rendered = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: targetSize.width,
                    height: targetSize.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  )
            else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(
                cgImage,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: targetSize.width,
                    height: targetSize.height
                )
            )
            return true
        }

        guard rendered else {
            throw FinalizationError.rgbaRenderFailed
        }
        return RenderedClipboardRGBAImage(
            data: data,
            width: targetSize.width,
            height: targetSize.height
        )
    }

    private static func targetPixelSize(
        width: Int,
        height: Int,
        maxPixelDimension: Int?
    ) -> (width: Int, height: Int) {
        guard let maxPixelDimension,
              max(width, height) > maxPixelDimension
        else {
            return (width, height)
        }

        let scale = Double(maxPixelDimension) / Double(max(width, height))
        return (
            max(Int(Double(width) * scale), 1),
            max(Int(Double(height) * scale), 1)
        )
    }
}

fileprivate struct ClipboardImageRepresentation {
    let data: Data
    let mimeType: String
    let fileExtension: String
}

protocol ClipboardWebPEncoding: Sendable {
    func encodeLosslessRGBA(_ rgbaData: Data, width: Int, height: Int) -> Data?
}

struct RustClipboardWebPEncoder: ClipboardWebPEncoding {
    private let client = RustCoreClient()

    func encodeLosslessRGBA(_ rgbaData: Data, width: Int, height: Int) -> Data? {
        switch client.encodeLosslessWebP(rgbaData: rgbaData, width: width, height: height) {
        case .success(let data):
            return data

        case .failure:
            return nil
        }
    }
}

private extension ClipboardCapturedImage {
    var normalizedImageFileExtension: String {
        let allowed = CharacterSet.alphanumerics
        let scalars = fileExtension
            .lowercased()
            .unicodeScalars
            .filter { allowed.contains($0) }
        let value = String(String.UnicodeScalarView(scalars))
        return value.isEmpty ? "heic" : value
    }
}

extension NSImage {
    private static let clipboardWebPMimeType = "image/webp"
    private static let clipboardWebPFileExtension = "webp"

    var pixelDimensions: (width: Int, height: Int) {
        if let bitmap = representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return (max(bitmap.pixelsWide, 1), max(bitmap.pixelsHigh, 1))
        }

        return (
            max(Int(size.width.rounded()), 1),
            max(Int(size.height.rounded()), 1)
        )
    }

    fileprivate func preferredClipboardAssetRepresentation(maxPixelDimension: CGFloat? = nil) -> ClipboardImageRepresentation? {
        losslessWebPRepresentation(maxPixelDimension: maxPixelDimension)
    }

    func pngRepresentation(maxPixelDimension: CGFloat? = nil) -> Data? {
        encodedRepresentation(
            typeIdentifier: UTType.png.identifier,
            mimeType: "image/png",
            fileExtension: "png",
            quality: nil,
            maxPixelDimension: maxPixelDimension
        )?.data
    }

    private func losslessWebPRepresentation(
        maxPixelDimension: CGFloat?,
        encoder: ClipboardWebPEncoding = RustClipboardWebPEncoder()
    ) -> ClipboardImageRepresentation? {
        guard let rgbaImage = renderedRGBAData(maxPixelDimension: maxPixelDimension),
              let data = encoder.encodeLosslessRGBA(
                rgbaImage.data,
                width: rgbaImage.width,
                height: rgbaImage.height
              ),
              !data.isEmpty
        else {
            return nil
        }

        return ClipboardImageRepresentation(
            data: data,
            mimeType: Self.clipboardWebPMimeType,
            fileExtension: Self.clipboardWebPFileExtension
        )
    }

    private func encodedRepresentation(
        typeIdentifier: String,
        mimeType: String,
        fileExtension: String,
        quality: CGFloat?,
        maxPixelDimension: CGFloat?
    ) -> ClipboardImageRepresentation? {
        guard let cgImage = renderedCGImage(maxPixelDimension: maxPixelDimension) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        var options: [CFString: Any] = [:]
        if let quality {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              !data.isEmpty
        else {
            return nil
        }

        return ClipboardImageRepresentation(
            data: data as Data,
            mimeType: mimeType,
            fileExtension: fileExtension
        )
    }

    private func renderedCGImage(maxPixelDimension: CGFloat? = nil) -> CGImage? {
        let sourceSize = size == .zero ? NSSize(width: 1, height: 1) : size
        let targetSize: NSSize

        if let maxPixelDimension {
            let scale = min(
                1,
                maxPixelDimension / max(sourceSize.width, sourceSize.height)
            )
            targetSize = NSSize(
                width: max(sourceSize.width * scale, 1),
                height: max(sourceSize.height * scale, 1)
            )
        } else {
            targetSize = sourceSize
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(Int(targetSize.width.rounded()), 1),
            pixelsHigh: max(Int(targetSize.height.rounded()), 1),
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

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.cgImage
    }

    private func renderedRGBAData(maxPixelDimension: CGFloat? = nil) -> (data: Data, width: Int, height: Int)? {
        guard let cgImage = renderedCGImage(maxPixelDimension: maxPixelDimension) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        let rowByteCount = width.multipliedReportingOverflow(by: 4)
        guard !rowByteCount.overflow else {
            return nil
        }
        let bytesPerRow = rowByteCount.partialValue
        let byteCount = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !byteCount.overflow else {
            return nil
        }
        var data = Data(count: byteCount.partialValue)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let rendered = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  )
            else {
                return false
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return rendered ? (data, width, height) : nil
    }
}
