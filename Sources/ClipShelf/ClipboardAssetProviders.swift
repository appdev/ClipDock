import AppKit
import AVFoundation
import ClipboardPanelApp
import ImageIO
import UniformTypeIdentifiers

@MainActor
protocol SourceAppIconCaching {
    func cacheIcon(for source: ClipboardCaptureSource?) -> String?
}

@MainActor
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

    init(urls: [URL], fileItems: [ClipboardCapturedFileMetadata] = []) {
        self.urls = urls
        self.fileItems = fileItems
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
            fileItems: fileItems.compactMap { $0 }
        )
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

struct CapturedClipboardImage {
    let image: NSImage
    let data: Data
    let mimeType: String
    let fileExtension: String
    let width: Int
    let height: Int

    static func read(from pasteboard: NSPasteboard, skipFileURLCheck: Bool = false) -> CapturedClipboardImage? {
        guard skipFileURLCheck || CapturedClipboardFiles.read(from: pasteboard) == nil else {
            return nil
        }

        for type in [
            NSPasteboard.PasteboardType.png,
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType.tiff,
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic")
        ] {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data),
               let encodedImage = image.preferredClipboardAssetRepresentation() {
                return make(image: image, encodedImage: encodedImage)
            }
        }

        let images = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        ) as? [NSImage]
        if let image = images?.first,
           let encodedImage = image.preferredClipboardAssetRepresentation() {
            return make(image: image, encodedImage: encodedImage)
        }

        return nil
    }

    private static func make(image: NSImage, encodedImage: ClipboardImageRepresentation) -> CapturedClipboardImage {
        let dimensions = image.pixelDimensions
        return CapturedClipboardImage(
            image: image,
            data: encodedImage.data,
            mimeType: encodedImage.mimeType,
            fileExtension: encodedImage.fileExtension,
            width: dimensions.width,
            height: dimensions.height
        )
    }

}

extension CapturedClipboardFiles {
    var clipboardCapturedFiles: ClipboardCapturedFiles {
        ClipboardCapturedFiles(paths: paths, fileItems: fileItems)
    }
}

extension CapturedClipboardImage {
    var clipboardCapturedImage: ClipboardCapturedImage {
        let thumbnail = image.preferredClipboardAssetRepresentation(maxPixelDimension: 420)
        return ClipboardCapturedImage(
            data: data,
            thumbnailData: thumbnail?.mimeType == mimeType ? thumbnail?.data ?? data : data,
            mimeType: mimeType,
            fileExtension: fileExtension,
            width: width,
            height: height
        )
    }
}

@MainActor
final class ClipboardImageAssetProvider: ClipboardImageAssetCaching {
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

    func cacheImage(_ capturedImage: ClipboardCapturedImage, changeCount: Int) -> ClipboardStoredImageAsset? {
        let fileStem = fileStemFactory.makeFileStem(prefix: "image", changeCount: changeCount)
        let fileExtension = capturedImage.normalizedImageFileExtension
        let payloadURL = directories.imagePayloadDirectoryURL.appendingPathComponent("\(fileStem).\(fileExtension)")
        let thumbnailURL = directories.imageThumbnailDirectoryURL.appendingPathComponent("\(fileStem).\(fileExtension)")
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
            try capturedImage.data.write(to: payloadURL, options: .atomic)
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
        } catch {
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
}

fileprivate struct ClipboardImageRepresentation {
    let data: Data
    let mimeType: String
    let fileExtension: String
}

fileprivate struct ClipboardImageEncodingCandidate {
    let typeIdentifier: String
    let mimeType: String
    let fileExtension: String
    let quality: CGFloat?
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
        let candidates = [
            ClipboardImageEncodingCandidate(
                typeIdentifier: UTType.heic.identifier,
                mimeType: "image/heic",
                fileExtension: "heic",
                quality: 0.88
            ),
            ClipboardImageEncodingCandidate(
                typeIdentifier: UTType.jpeg.identifier,
                mimeType: "image/jpeg",
                fileExtension: "jpg",
                quality: 0.90
            ),
            ClipboardImageEncodingCandidate(
                typeIdentifier: UTType.png.identifier,
                mimeType: "image/png",
                fileExtension: "png",
                quality: nil
            )
        ]

        for candidate in candidates {
            if let representation = encodedRepresentation(
                typeIdentifier: candidate.typeIdentifier,
                mimeType: candidate.mimeType,
                fileExtension: candidate.fileExtension,
                quality: candidate.quality,
                maxPixelDimension: maxPixelDimension
            ) {
                return representation
            }
        }

        return nil
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
}
