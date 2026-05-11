import AppKit
import ClipboardPanelApp

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
    private let directories: PlatformAssetDirectories
    private let fileManager: FileManager

    init(appSupportURL: URL, fileManager: FileManager = .default) {
        self.directories = PlatformAssetDirectories(appSupportURL: appSupportURL)
        self.fileManager = fileManager
    }

    func cacheIcon(for source: ClipboardCaptureSource?) -> String? {
        guard let source else { return nil }
        let data = source.iconTIFFData
            ?? source.bundlePath
            .flatMap { NSWorkspace.shared.icon(forFile: $0).tiffRepresentation }
        guard let data else { return nil }

        do {
            try fileManager.createDirectory(at: directories.iconCacheDirectoryURL, withIntermediateDirectories: true)
            let fileName = "\(safeCacheKey(for: source)).tiff"
            let fileURL = directories.iconCacheDirectoryURL.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            return "app-icons/\(fileName)"
        } catch {
            return nil
        }
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

struct CapturedClipboardFiles {
    let urls: [URL]

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

    private static func normalizedFileURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        return URL(fileURLWithPath: url.path).standardizedFileURL
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
    let pngData: Data
    let width: Int
    let height: Int

    static func read(from pasteboard: NSPasteboard) -> CapturedClipboardImage? {
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
               let pngData = type == .png || type.rawValue == "public.png"
                ? data
                : image.pngRepresentation() {
                return make(image: image, pngData: pngData)
            }
        }

        let images = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        ) as? [NSImage]
        if let image = images?.first,
           let pngData = image.pngRepresentation() {
            return make(image: image, pngData: pngData)
        }

        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: nil
        ) as? [URL]
        for url in urls ?? [] where isImageFile(url) {
            if let image = NSImage(contentsOf: url),
               let pngData = image.pngRepresentation() {
                return make(image: image, pngData: pngData)
            }
        }

        return nil
    }

    private static func make(image: NSImage, pngData: Data) -> CapturedClipboardImage {
        let dimensions = image.pixelDimensions
        return CapturedClipboardImage(
            image: image,
            pngData: pngData,
            width: dimensions.width,
            height: dimensions.height
        )
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp", "gif"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
}

extension CapturedClipboardFiles {
    var clipboardCapturedFiles: ClipboardCapturedFiles {
        ClipboardCapturedFiles(paths: paths)
    }
}

extension CapturedClipboardImage {
    var clipboardCapturedImage: ClipboardCapturedImage {
        ClipboardCapturedImage(
            pngData: pngData,
            thumbnailPNGData: image.pngRepresentation(maxPixelDimension: 420) ?? pngData,
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
        let payloadURL = directories.imagePayloadDirectoryURL.appendingPathComponent("\(fileStem).png")
        let thumbnailURL = directories.imageThumbnailDirectoryURL.appendingPathComponent("\(fileStem).png")
        let thumbnailData = capturedImage.thumbnailPNGData

        do {
            try fileManager.createDirectory(
                at: directories.imagePayloadDirectoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: directories.imageThumbnailDirectoryURL,
                withIntermediateDirectories: true
            )
            try capturedImage.pngData.write(to: payloadURL, options: .atomic)
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
        } catch {
            return nil
        }

        return ClipboardStoredImageAsset(
            payloadRelativePath: "assets/\(fileStem).png",
            previewRelativePath: "thumbnails/\(fileStem).png",
            mimeType: "image/png",
            width: capturedImage.width,
            height: capturedImage.height,
            byteCount: capturedImage.pngData.count
        )
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

    func pngRepresentation(maxPixelDimension: CGFloat? = nil) -> Data? {
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

        return bitmap.representation(using: .png, properties: [:])
    }
}
