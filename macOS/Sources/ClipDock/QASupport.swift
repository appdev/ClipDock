import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp

enum PanelQASamples {
    struct RealGitHubSampleAssets {
        let imageURL: URL
        let linkMetadata: RustLinkMetadataSummary
    }

    private struct SourceAppIconFixture {
        let key: String
        let fileStem: String
        let appPaths: [String]
    }

    private struct OpenGraphMetadata {
        let title: String
        let imageURL: URL
    }

    private static let terminalRichTextSampleText = """
    Last login: Sat May 23
    16:07:44 on ttys006
    ~/IdeaProjects
    git clone https://github.com/appdev/siyuan-unlock.git
    Cloning into 'siyuan-unlock'...
    """

    private static let sourceAppIconFixtures: [SourceAppIconFixture] = [
        SourceAppIconFixture(
            key: "Chrome",
            fileStem: "chrome",
            appPaths: ["/Applications/Google Chrome.app", "/Applications/Safari.app"]
        ),
        SourceAppIconFixture(
            key: "Safari",
            fileStem: "safari",
            appPaths: ["/Applications/Safari.app", "/System/Applications/Safari.app"]
        ),
        SourceAppIconFixture(
            key: "Finder",
            fileStem: "finder",
            appPaths: ["/System/Library/CoreServices/Finder.app"]
        ),
        SourceAppIconFixture(
            key: "Preview",
            fileStem: "preview",
            appPaths: ["/System/Applications/Preview.app"]
        ),
        SourceAppIconFixture(
            key: "Notes",
            fileStem: "notes",
            appPaths: ["/System/Applications/Notes.app"]
        ),
        SourceAppIconFixture(
            key: "Xcode",
            fileStem: "xcode",
            appPaths: ["/Applications/Xcode.app"]
        ),
        SourceAppIconFixture(
            key: "TextEdit",
            fileStem: "textedit",
            appPaths: ["/System/Applications/TextEdit.app"]
        ),
        SourceAppIconFixture(
            key: "Terminal",
            fileStem: "terminal",
            appPaths: ["/System/Applications/Utilities/Terminal.app"]
        ),
        SourceAppIconFixture(
            key: "Digital Color Meter",
            fileStem: "digital-color-meter",
            appPaths: ["/System/Applications/Utilities/Digital Color Meter.app"]
        )
    ]

    @MainActor
    static func makeSourceAppIconPaths(outputDirectory: URL) throws -> [String: String] {
        let iconDirectory = outputDirectory.appendingPathComponent("source-app-icons", isDirectory: true)
        try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)

        var pathsByKey: [String: String] = [:]
        for fixture in sourceAppIconFixtures {
            guard let appPath = fixture.appPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                continue
            }
            let outputURL = iconDirectory.appendingPathComponent("\(fixture.fileStem).png")
            try writeSourceAppIcon(fromAppAtPath: appPath, to: outputURL)
            pathsByKey[fixture.key] = outputURL.path
        }
        return pathsByKey
    }

    @MainActor
    private static func writeSourceAppIcon(fromAppAtPath appPath: String, to outputURL: URL) throws {
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        let pointSize = NSSize(width: 128, height: 128)
        let pixelSize = 256

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: pointSize).fill()
        icon.draw(
            in: NSRect(origin: .zero, size: pointSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: outputURL, options: .atomic)
    }

    static func makeRealSampleImageURL() throws -> URL {
        if let url = ClipDockResources.bundle.url(forResource: "AppIcon", withExtension: "png") {
            return url
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/ClipDock/Resources/AppIcon.png")
        guard FileManager.default.fileExists(atPath: fallbackURL.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return fallbackURL
    }

    static func validatedRealSampleImageURL(path: String?) throws -> URL {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw PreviewQAError(message: "真实截图需要通过 --qa-sample-image 指定图片文件")
        }

        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              NSImage(contentsOf: url) != nil
        else {
            throw PreviewQAError(message: "指定的真实图片文件不可读取：\(url.path)")
        }
        return url
    }

    static func makeCardFillingImagePreviewURL(sourceURL: URL, appSupportURL: URL) throws -> URL {
        guard let sourceImage = NSImage(contentsOf: sourceURL),
              let representation = sourceImage.representations
                .compactMap({ $0 as? NSBitmapImageRep })
                .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) })
        else {
            throw PreviewQAError(message: "无法读取真实图片预览：\(sourceURL.path)")
        }

        let targetPixelWidth = 1000
        let targetPixelHeight = 800
        let sourceWidth = CGFloat(representation.pixelsWide)
        let sourceHeight = CGFloat(representation.pixelsHigh)
        let targetAspect = CGFloat(targetPixelWidth) / CGFloat(targetPixelHeight)
        let sourceAspect = sourceWidth / sourceHeight
        let cropSize: NSSize
        if sourceAspect > targetAspect {
            cropSize = NSSize(width: floor(sourceHeight * targetAspect), height: sourceHeight)
        } else {
            cropSize = NSSize(width: sourceWidth, height: floor(sourceWidth / targetAspect))
        }
        let cropRect = NSRect(
            x: floor((sourceWidth - cropSize.width) / 2),
            y: floor((sourceHeight - cropSize.height) / 2),
            width: cropSize.width,
            height: cropSize.height
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetPixelWidth,
            pixelsHigh: targetPixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw PreviewQAError(message: "无法创建真实图片预览缓存")
        }
        bitmap.size = NSSize(width: targetPixelWidth, height: targetPixelHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: targetPixelWidth, height: targetPixelHeight).fill()
        sourceImage.draw(
            in: NSRect(x: 0, y: 0, width: targetPixelWidth, height: targetPixelHeight),
            from: cropRect,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
            throw PreviewQAError(message: "无法写入真实图片预览缓存")
        }

        let samplesDirectory = appSupportURL.appendingPathComponent("real-samples", isDirectory: true)
        try FileManager.default.createDirectory(at: samplesDirectory, withIntermediateDirectories: true)
        let outputURL = samplesDirectory.appendingPathComponent("pexels-card-preview.jpg")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    static func makeRealDocumentPreviewURL(filePaths: [String], appSupportURL: URL) throws -> URL {
        let existingFiles = filePaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingFiles.isEmpty else {
            throw PreviewQAError(message: "无法读取真实文件")
        }

        let canvasSize = NSSize(width: 720, height: 520)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        NSColor(calibratedWhite: 0.88, alpha: 1).setStroke()
        let pagePath = NSBezierPath(roundedRect: NSRect(x: 48, y: 36, width: 624, height: 448), xRadius: 18, yRadius: 18)
        pagePath.lineWidth = 2
        pagePath.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ]
        let metaAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.40, alpha: 1)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 19, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.24, alpha: 1)
        ]

        let primaryFile = existingFiles[0]
        let title = primaryFile.lastPathComponent as NSString
        title.draw(at: NSPoint(x: 78, y: 424), withAttributes: titleAttributes)

        let relativeNames = existingFiles
            .map { url in
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).path
                return url.path.replacingOccurrences(of: "\(cwd)/", with: "")
            }
            .joined(separator: "  +  ")
        (relativeNames as NSString).draw(at: NSPoint(x: 80, y: 386), withAttributes: metaAttributes)

        let body = try existingFiles
            .prefix(2)
            .map { url -> String in
                let text = try String(contentsOf: url, encoding: .utf8)
                let normalized = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .prefix(12)
                    .joined(separator: "\n")
                return normalized
            }
            .joined(separator: "\n\n")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 4
        var bodyDrawAttributes = bodyAttributes
        bodyDrawAttributes[.paragraphStyle] = paragraph
        (body as NSString).draw(
            with: NSRect(x: 80, y: 84, width: 560, height: 274),
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: bodyDrawAttributes
        )
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw PreviewQAError(message: "无法生成真实文件预览缓存")
        }

        let samplesDirectory = appSupportURL.appendingPathComponent("real-samples", isDirectory: true)
        try FileManager.default.createDirectory(at: samplesDirectory, withIntermediateDirectories: true)
        let outputURL = samplesDirectory.appendingPathComponent("repository-files-preview.png")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    static func realSampleFilePaths() -> [String] {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return [
            rootURL.appendingPathComponent("README.md").path,
            rootURL.appendingPathComponent("Package.swift").path
        ]
    }

    static func prepareRealGitHubSampleAssets(appSupportURL: URL) throws -> RealGitHubSampleAssets {
        let githubURL = URL(string: "https://github.com/")!
        let samplesDirectory = appSupportURL.appendingPathComponent("real-samples", isDirectory: true)
        try FileManager.default.createDirectory(at: samplesDirectory, withIntermediateDirectories: true)

        let openGraph = try fetchOpenGraphMetadata(from: githubURL)
        let imageURL = try downloadImage(
            from: openGraph.imageURL,
            to: samplesDirectory.appendingPathComponent("github-homepage-preview.png")
        )
        let fetchedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let metadata = RustLinkMetadataSummary(
            canonicalURL: githubURL.absoluteString,
            displayURL: "github.com",
            host: "github.com",
            title: openGraph.title,
            siteName: "GitHub",
            imageAssetPath: imageURL.path,
            metadataState: "ready",
            fetchedAtMs: fetchedAtMs
        )
        return RealGitHubSampleAssets(imageURL: imageURL, linkMetadata: metadata)
    }

    @MainActor
    static func makePanelSnapshotPreviewImageURL(outputDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 420, height: 260))
        image.lockFocus()
        NSColor.systemTeal.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 420, height: 260), xRadius: 18, yRadius: 18).fill()
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: 270, y: 120, width: 92, height: 92)).fill()
        NSBezierPath(roundedRect: NSRect(x: 44, y: 54, width: 190, height: 26), xRadius: 13, yRadius: 13).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = outputDirectory.appendingPathComponent("panel-runtime-sample-image.png")
        try pngData.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    static func makePanelSnapshotChromeIconURL(outputDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 160, height: 160))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 160, height: 160).fill()

        let center = NSPoint(x: 80, y: 80)
        let outerRadius: CGFloat = 68
        let innerRadius: CGFloat = 29
        let ring = NSBezierPath()
        ring.appendOval(in: NSRect(
            x: center.x - outerRadius,
            y: center.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))
        ring.appendOval(in: NSRect(
            x: center.x - innerRadius,
            y: center.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))
        ring.windingRule = .evenOdd
        NSColor.systemRed.setFill()
        ring.fill()

        NSColor.systemGreen.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 19, y: 61, width: 124, height: 70),
            xRadius: 35,
            yRadius: 35
        ).fill()

        NSColor.systemYellow.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 18, y: 28, width: 96, height: 62),
            xRadius: 31,
            yRadius: 31
        ).fill()

        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 43, y: 43, width: 74, height: 74)).fill()
        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: NSRect(x: 52, y: 52, width: 56, height: 56)).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = outputDirectory.appendingPathComponent("panel-runtime-chrome-icon.png")
        try pngData.write(to: url, options: .atomic)
        return url
    }

    static func makePanelSnapshotItems(
        imagePath: String,
        sourceIconPaths: [String: String] = [:],
        linkMetadata: RustLinkMetadataSummary? = nil,
        styledTextPreviewPath: String? = nil
    ) -> [RustClipboardItemSummary] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let text = styledTextPreviewPath == nil
            ? """
            ClipDock maintains a local clipboard history for macOS, with fast review, reuse, and organization directly from the shelf.
            """
            : """
            UgAdaptiveDialog(
                modifier = ugAdaptiveDialogModifier,
                visible = isShowScanDeviceDialog,
                dismissOnSwipeDown = false
            )
            """
        return [
            makeItem(
                id: "snapshot-text",
                itemType: "text",
                summary: text,
                primaryText: text,
                sourceAppName: "Chrome",
                timestamp: now - 79_200_000,
                contentHash: "snapshot-snapshot-text",
                sourceAppIconPath: sourceIconPaths["Chrome"],
                sourceAppIconHeaderColor: 0xFFF0C928,
                previewAssetPath: styledTextPreviewPath,
                sizeBytes: Int64(text.utf8.count)
            ),
            makeItem(
                id: "snapshot-color",
                itemType: "color",
                summary: "#FF00AA",
                primaryText: "#FF00AA",
                sourceAppName: "数码测色计",
                timestamp: now - 120_000,
                contentHash: "snapshot-snapshot-color",
                sourceAppIconPath: sourceIconPaths["Digital Color Meter"],
                sizeBytes: 7
            ),
            makeItem(
                id: "snapshot-rich-text",
                itemType: "rich_text",
                summary: "产品说明\n• 本地剪贴板历史\n• Pinboard 分类管理\n• 快速预览与回贴",
                primaryText: "产品说明\n• 本地剪贴板历史\n• Pinboard 分类管理\n• 快速预览与回贴",
                sourceAppName: "Xcode",
                timestamp: now - 240_000,
                contentHash: "snapshot-snapshot-rich-text",
                sourceAppIconPath: sourceIconPaths["Xcode"],
                sizeBytes: 64
            ),
            makeItem(
                id: "snapshot-image",
                itemType: "image",
                summary: "ClipDock AppIcon",
                primaryText: nil,
                sourceAppName: "预览",
                timestamp: now - 360_000,
                contentHash: "snapshot-snapshot-image",
                sourceAppIconPath: sourceIconPaths["Preview"],
                previewAssetPath: imagePath,
                payloadAssetPath: imagePath,
                sizeBytes: 184_000
            ),
            makeItem(
                id: "snapshot-file",
                itemType: "file",
                summary: "README.md",
                primaryText: realSampleFilePaths().joined(separator: "\n"),
                sourceAppName: "Finder",
                timestamp: now - 1_620_000,
                contentHash: "snapshot-snapshot-file",
                sourceAppIconPath: sourceIconPaths["Finder"],
                sizeBytes: 2048
            ),
            makeItem(
                id: "snapshot-link",
                itemType: "link",
                summary: "github.com",
                primaryText: "https://github.com/",
                sourceAppName: "Safari",
                timestamp: now - 50_400_000,
                contentHash: "snapshot-snapshot-link",
                sourceAppIconPath: sourceIconPaths["Safari"],
                linkMetadata: linkMetadata,
                sizeBytes: 19
            )
        ]
    }

    static func makeStyledCodeRTFPreviewURL(outputDirectory: URL) throws -> URL {
        let code = """
        UgAdaptiveDialog(
            modifier = ugAdaptiveDialogModifier,
            visible = isShowScanDeviceDialog,
            dismissOnSwipeDown = false
        )
        """
        let attributed = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(deviceWhite: 0.88, alpha: 1),
                .backgroundColor: NSColor(deviceWhite: 0.12, alpha: 1)
            ]
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemGreen,
            range: (code as NSString).range(of: "UgAdaptiveDialog")
        )
        for keyword in ["modifier", "visible", "dismissOnSwipeDown"] {
            attributed.addAttribute(
                .foregroundColor,
                value: NSColor.systemBlue,
                range: (code as NSString).range(of: keyword)
            )
        }

        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let directory = outputDirectory.appendingPathComponent("styled-text", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("paste-like-code.rtf")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func makeTerminalRichTextPreviewURL(outputDirectory: URL) throws -> URL {
        let attributed = NSMutableAttributedString(
            string: terminalRichTextSampleText,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor(deviceWhite: 0.24, alpha: 1)
            ]
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemGreen,
            range: (terminalRichTextSampleText as NSString).range(of: "git")
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemBlue,
            range: (terminalRichTextSampleText as NSString).range(of: "~/IdeaProjects")
        )

        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let directory = outputDirectory.appendingPathComponent("styled-text", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("terminal-paste.rtf")
        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    static func makePanelInteractionSmokeImageURL(outputDirectory: URL) throws -> URL {
        let image = NSImage(size: NSSize(width: 360, height: 220))
        image.lockFocus()
        NSColor.systemBlue.withAlphaComponent(0.74).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 360, height: 220), xRadius: 18, yRadius: 18).fill()
        NSColor.systemTeal.withAlphaComponent(0.42).setFill()
        NSBezierPath(ovalIn: NSRect(x: 220, y: 108, width: 86, height: 86)).fill()
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: 42, y: 52, width: 160, height: 24), xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = outputDirectory.appendingPathComponent("panel-interaction-smoke-image.png")
        try pngData.write(to: url, options: .atomic)
        return url
    }

    static func makePanelInteractionItems(
        imagePath: String,
        imagePayloadPath: String? = nil,
        filePreviewPath: String? = nil,
        linkMetadata: RustLinkMetadataSummary? = nil,
        sourceIconPaths: [String: String] = [:],
        terminalRichTextPreviewPath: String? = nil
    ) -> [RustClipboardItemSummary] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let firstText = terminalRichTextPreviewPath == nil
            ? "ClipDock 提供本地剪贴板历史、快速预览与 Pinboard 分类管理，适合高频跨应用工作流。"
            : terminalRichTextSampleText
        var items = [
            makeItem(
                id: "panel-smoke-text",
                itemType: "text",
                summary: firstText,
                primaryText: firstText,
                sourceAppName: terminalRichTextPreviewPath == nil ? "备忘录" : "终端",
                timestamp: now,
                contentHash: "panel-smoke-panel-smoke-text",
                sourceAppIconPath: terminalRichTextPreviewPath == nil
                    ? sourceIconPaths["Notes"]
                    : sourceIconPaths["Terminal"],
                previewAssetPath: terminalRichTextPreviewPath,
                sizeBytes: Int64(firstText.utf8.count)
            ),
            makeItem(
                id: "panel-smoke-image",
                itemType: "image",
                summary: "pexels-ing-do-2160128514-36552442.jpg",
                primaryText: nil,
                sourceAppName: "预览",
                timestamp: now - 60_000,
                contentHash: "panel-smoke-panel-smoke-image",
                sourceAppIconPath: sourceIconPaths["Preview"],
                previewAssetPath: imagePath,
                payloadAssetPath: imagePayloadPath ?? imagePath,
                sizeBytes: 124_000
            ),
            makeItem(
                id: "panel-smoke-file",
                itemType: "file",
                summary: "2 个真实文件 · README.md",
                primaryText: realSampleFilePaths().joined(separator: "\n"),
                sourceAppName: "Finder",
                timestamp: now - 120_000,
                contentHash: "panel-smoke-panel-smoke-file",
                sourceAppIconPath: sourceIconPaths["Finder"],
                previewAssetPath: filePreviewPath,
                sizeBytes: 2048
            ),
            makeItem(
                id: "panel-smoke-link",
                itemType: "link",
                summary: "github.com",
                primaryText: "https://github.com/",
                sourceAppName: "Safari",
                timestamp: now - 180_000,
                contentHash: "panel-smoke-panel-smoke-link",
                sourceAppIconPath: sourceIconPaths["Safari"],
                linkMetadata: linkMetadata,
                sizeBytes: 19
            ),
            makeItem(
                id: "panel-smoke-color",
                itemType: "color",
                summary: "#FF00AA",
                primaryText: "#FF00AA",
                sourceAppName: "数码测色计",
                timestamp: now - 240_000,
                contentHash: "panel-smoke-panel-smoke-color",
                sourceAppIconPath: sourceIconPaths["Digital Color Meter"],
                sizeBytes: 7
            ),
            makeItem(
                id: "panel-smoke-rich-text",
                itemType: "rich_text",
                summary: "产品说明\n• 本地历史记录\n• 分类固定内容\n• 快捷键快速取用",
                primaryText: "产品说明\n• 本地历史记录\n• 分类固定内容\n• 快捷键快速取用",
                sourceAppName: "文本编辑",
                timestamp: now - 300_000,
                contentHash: "panel-smoke-panel-smoke-rich-text",
                sourceAppIconPath: sourceIconPaths["TextEdit"],
                sizeBytes: 72
            )
        ]

        for index in 7...16 {
            items.append(makeItem(
                id: "panel-smoke-extra-\(index)",
                itemType: "text",
                summary: "产品资料条目 \(index)",
                primaryText: "产品资料条目 \(index)",
                sourceAppName: "终端",
                timestamp: now - Int64(index * 60_000),
                contentHash: "panel-smoke-panel-smoke-extra-\(index)",
                sourceAppIconPath: sourceIconPaths["Terminal"],
                sizeBytes: 28
            ))
        }

        return items
    }

    static func makePagedPanelItems(count: Int) -> [RustClipboardItemSummary] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return (1...count).map { index in
            makeItem(
                id: "panel-page-\(index)",
                itemType: index.isMultiple(of: 5) ? "link" : "text",
                summary: "分页历史条目 \(index)",
                primaryText: index.isMultiple(of: 5)
                    ? "https://example.com/page/\(index)"
                    : "分页历史条目 \(index)",
                sourceAppName: index.isMultiple(of: 3) ? "Safari" : "备忘录",
                timestamp: now - Int64(index * 30_000),
                contentHash: "panel-smoke-panel-page-\(index)",
                sizeBytes: 32
            )
        }
    }

    static func makePreviewItem(
        isLongText: Bool,
        sourceIconPaths: [String: String] = [:]
    ) -> RustClipboardItemSummary {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let body = isLongText
            ? Array(repeating: """
                ClipDock 预览窗口需要根据内容自动调整尺寸。短文本不应该撑成固定大盒子，长文本则应该在最大高度内自动换行，并通过滚动继续阅读后续内容。

                这是一段用于真实窗口 QA 的长文本。它会占用多行，帮助我们确认 NSTextView 的 text container 会跟随 popover 宽度换行，而不是横向溢出。

                当内容继续增加时，预览窗口不应无限变高。它应该保持一个合理的最大高度，底部元信息仍然可见，正文区域内部可以滚动。
                """, count: 10)
                .joined(separator: "\n\n")
            : "macOS 事件行为：浮窗焦点、全局快捷键、双击复制、横向滚动、Popover、外部点击关闭。"
        return RustClipboardItemSummary(
            id: "preview-real-qa-text",
            itemType: "text",
            summary: body,
            primaryText: body,
            contentHash: "preview-real-qa-text",
            sourceAppId: nil,
            sourceAppName: "备忘录",
            sourceAppIconPath: sourceIconPaths["Notes"],
            previewAssetPath: nil,
            payloadAssetPath: nil,
            sourceConfidence: "high",
            firstCopiedAtMs: now,
            lastCopiedAtMs: now,
            copyCount: 1,
            isPinned: false,
            sizeBytes: 18,
            previewState: "ready"
        )
    }

    @MainActor
    static func makePreviewImageItem(
        outputDirectory: URL,
        sourceIconPaths: [String: String] = [:]
    ) throws -> RustClipboardItemSummary {
        let imageURL = outputDirectory.appendingPathComponent("preview-real-qa-image.png")
        let imageWidth = 1096
        let imageHeight = 1262
        let imageSize = NSSize(width: imageWidth, height: imageHeight)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: imageWidth,
            pixelsHigh: imageHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaFirst],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw PreviewQAError(message: "无法生成图片预览样本")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: imageSize.width - 34, height: imageSize.height - 30).fill()
        NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 280, height: imageSize.height - 30).fill()
        NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
        for y in stride(from: CGFloat(0), through: imageSize.height - 30, by: 190) {
            let lineY = imageSize.height - 30 - y
            NSBezierPath.strokeLine(from: NSPoint(x: 0, y: lineY), to: NSPoint(x: imageSize.width - 34, y: lineY))
        }
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 52, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.86)
        ]
        func drawPreviewText(_ text: String, x: CGFloat, yFromTop: CGFloat, attributes: [NSAttributedString.Key: Any]) {
            let bounds = (text as NSString).boundingRect(
                with: NSSize(width: imageSize.width, height: imageSize.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            text.draw(
                at: NSPoint(x: x, y: imageSize.height - 30 - yFromTop - ceil(bounds.height)),
                withAttributes: attributes
            )
        }
        drawPreviewText("使用推荐", x: 58, yFromTop: 88, attributes: headerAttributes)
        drawPreviewText("1.25Gbps千兆\n台湾瑞昱芯片", x: 360, yFromTop: 64, attributes: headerAttributes)
        drawPreviewText("2.5Gbps千兆\n台湾瑞昱芯片", x: 720, yFromTop: 64, attributes: headerAttributes)
        drawPreviewText("产品", x: 96, yFromTop: 360, attributes: headerAttributes)
        drawPreviewText("封装形式", x: 58, yFromTop: 662, attributes: headerAttributes)
        drawPreviewText("SFP", x: 610, yFromTop: 674, attributes: bodyAttributes)
        drawPreviewText("自适应\n传输速率", x: 62, yFromTop: 922, attributes: headerAttributes)
        drawPreviewText("10Mbps\n100Mbps\n1000Mbps", x: 420, yFromTop: 922, attributes: bodyAttributes)
        drawPreviewText("100Mbps\n1000Mbps\n2.5Gbps", x: 760, yFromTop: 922, attributes: bodyAttributes)
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw PreviewQAError(message: "无法生成图片预览样本")
        }
        try pngData.write(to: imageURL, options: .atomic)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return RustClipboardItemSummary(
            id: "preview-real-qa-image",
            itemType: "image",
            summary: "图片 1096 × 1262",
            primaryText: nil,
            contentHash: "preview-real-qa-image",
            sourceAppId: nil,
            sourceAppName: "预览",
            sourceAppIconPath: sourceIconPaths["Preview"],
            previewAssetPath: imageURL.path,
            payloadAssetPath: imageURL.path,
            sourceConfidence: "high",
            firstCopiedAtMs: now,
            lastCopiedAtMs: now,
            copyCount: 1,
            isPinned: false,
            sizeBytes: Int64(pngData.count),
            previewState: "ready"
        )
    }

    private static func makeItem(
        id: String,
        itemType: String,
        summary: String,
        primaryText: String?,
        sourceAppName: String,
        timestamp: Int64,
        contentHash: String,
        sourceAppIconPath: String? = nil,
        sourceAppIconHeaderColor: Int64? = nil,
        previewAssetPath: String? = nil,
        payloadAssetPath: String? = nil,
        linkMetadata: RustLinkMetadataSummary? = nil,
        sizeBytes: Int64
    ) -> RustClipboardItemSummary {
        RustClipboardItemSummary(
            id: id,
            itemType: itemType,
            summary: summary,
            primaryText: primaryText,
            contentHash: contentHash,
            sourceAppId: nil,
            sourceAppName: sourceAppName,
            sourceAppIconPath: sourceAppIconPath,
            sourceAppIconHeaderColor: sourceAppIconHeaderColor,
            previewAssetPath: previewAssetPath,
            payloadAssetPath: payloadAssetPath,
            sourceConfidence: "high",
            firstCopiedAtMs: timestamp,
            lastCopiedAtMs: timestamp,
            copyCount: 1,
            isPinned: false,
            sizeBytes: sizeBytes,
            previewState: "ready",
            linkMetadata: linkMetadata
        )
    }

    private static func fetchOpenGraphMetadata(from url: URL) throws -> OpenGraphMetadata {
        let data = try Data(contentsOf: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw PreviewQAError(message: "GitHub 首页元数据不是 UTF-8 文本")
        }

        let metadata = metaTagValues(from: html)
        guard let title = nonEmptyHTMLText(metadata["og:title"]),
              let imageText = nonEmptyHTMLText(metadata["og:image"]),
              let imageURL = URL(string: imageText, relativeTo: url)?.absoluteURL
        else {
            throw PreviewQAError(message: "GitHub 首页缺少可用的 Open Graph 预览信息")
        }

        return OpenGraphMetadata(title: title, imageURL: imageURL)
    }

    private static func downloadImage(from sourceURL: URL, to outputURL: URL) throws -> URL {
        let data = try Data(contentsOf: sourceURL)
        guard NSImage(data: data) != nil
        else {
            throw PreviewQAError(message: "无法下载 GitHub 真实预览图片")
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private static func metaTagValues(from html: String) -> [String: String] {
        guard let tagExpression = try? NSRegularExpression(pattern: #"<meta\s+[^>]*>"#, options: [.caseInsensitive]),
              let attributeExpression = try? NSRegularExpression(
                pattern: #"([A-Za-z_:.-]+)\s*=\s*["']([^"']*)["']"#,
                options: [.caseInsensitive]
              )
        else {
            return [:]
        }

        var values: [String: String] = [:]
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        tagExpression.enumerateMatches(in: html, range: fullRange) { match, _, _ in
            guard let match else { return }
            let tag = nsHTML.substring(with: match.range)
            let nsTag = tag as NSString
            let tagRange = NSRange(location: 0, length: nsTag.length)
            var attributes: [String: String] = [:]
            attributeExpression.enumerateMatches(in: tag, range: tagRange) { attributeMatch, _, _ in
                guard let attributeMatch,
                      attributeMatch.numberOfRanges == 3
                else { return }
                let name = nsTag.substring(with: attributeMatch.range(at: 1)).lowercased()
                let value = nsTag.substring(with: attributeMatch.range(at: 2))
                attributes[name] = decodedHTMLText(value)
            }

            guard let key = attributes["property"] ?? attributes["name"],
                  let value = attributes["content"]
            else {
                return
            }
            values[key.lowercased()] = value
        }
        return values
    }

    private static func nonEmptyHTMLText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = decodedHTMLText(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodedHTMLText(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              )
        else {
            return value
        }
        return attributed.string
    }

    struct PreviewQAError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }
}

enum PanelQAHarness {
    enum ArrowDirection {
        case left
        case right
    }

    @MainActor
    static func sendArrow(
        _ direction: ArrowDirection,
        modifiers: NSEvent.ModifierFlags = [],
        to view: NSView
    ) {
        let character: String
        let keyCode: Int
        switch direction {
        case .left:
            character = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
            keyCode = kVK_LeftArrow
        case .right:
            character = String(UnicodeScalar(NSRightArrowFunctionKey)!)
            keyCode = kVK_RightArrow
        }

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    static func sendMouseDown(to view: NSView, clickCount: Int) {
        let localPoint = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        let windowPoint = view.convert(localPoint, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ) else {
            return
        }

        view.mouseDown(with: event)
    }

    @MainActor
    static func sendCommandNumber(_ number: Int, to view: NSView) {
        sendNumber(number, modifiers: [.command], to: view)
    }

    @MainActor
    static func sendNumber(
        _ number: Int,
        modifiers: NSEvent.ModifierFlags,
        to view: NSView
    ) {
        let keyCode: Int
        switch number {
        case 1:
            keyCode = kVK_ANSI_1
        case 2:
            keyCode = kVK_ANSI_2
        case 3:
            keyCode = kVK_ANSI_3
        case 4:
            keyCode = kVK_ANSI_4
        case 5:
            keyCode = kVK_ANSI_5
        case 6:
            keyCode = kVK_ANSI_6
        case 7:
            keyCode = kVK_ANSI_7
        case 8:
            keyCode = kVK_ANSI_8
        case 9:
            keyCode = kVK_ANSI_9
        default:
            return
        }

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: "\(number)",
            charactersIgnoringModifiers: "\(number)",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    static func sendCommandC(to view: NSView) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_C)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    static func sendDelete(to view: NSView) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: "\u{8}",
            charactersIgnoringModifiers: "\u{8}",
            isARepeat: false,
            keyCode: UInt16(kVK_Delete)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    static func sendSpace(to view: NSView) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: UInt16(kVK_Space)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    static func sendPrintable(
        characters: String,
        charactersIgnoringModifiers: String? = nil,
        modifiers: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = UInt16(kVK_ANSI_A),
        to view: NSView
    ) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    static func sendCommandModifier(down: Bool, to view: NSView) {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: down ? [.command] : [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Command)
        ) else {
            return
        }

        view.flagsChanged(with: event)
    }

    @MainActor
    static func sendEscape(to view: NSView) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ) else {
            return
        }

        view.keyDown(with: event)
    }

    @MainActor
    static func sendVerticalScrollWheel(to scrollView: NSScrollView, deltaY: Int32) {
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(deltaY))
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)

        guard let event = NSEvent(cgEvent: cgEvent) else { return }
        scrollView.scrollWheel(with: event)
    }

    @MainActor
    static func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    }

    @MainActor
    static func waitForPanelFocus(
        _ controller: FloatingPanelController,
        timeout: TimeInterval = 0.4
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if controller.smokeFirstResponderIsContentView,
               (!NSApp.isActive || controller.smokePanelIsKeyWindow) {
                return true
            }
            drainMainRunLoop()
        } while Date() < deadline

        return controller.smokeFirstResponderIsContentView
            && (!NSApp.isActive || controller.smokePanelIsKeyWindow)
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw SmokeError(message: message)
        }
    }

    struct SmokeError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }
}

enum ViewSnapshotRenderer {
    @MainActor
    static func render(view: NSView, to outputURL: URL) throws {
        let bitmap = try bitmapImage(for: view)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)
    }

    @MainActor
    private static func bitmapImage(for view: NSView) throws -> NSBitmapImageRep {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let width = Int(view.bounds.width.rounded())
        let height = Int(view.bounds.height.rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((CGFloat(width) * scale).rounded()),
            pixelsHigh: Int((CGFloat(height) * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = view.bounds.size

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        view.displayIgnoringOpacity(view.bounds, in: graphicsContext)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}

enum PreferencesQAHarness {
    @MainActor
    static func exerciseAllSections(in rootView: NSView) {
        _ = exerciseCurrentPage(in: rootView)

        for title in PreferenceSection.allCases.map(\.title) {
            guard let button = navigationButton(titled: title, in: rootView) else { continue }
            if let button = button as? PreferenceNavigationButton {
                button.triggerPress()
            } else {
                button.performClick(nil)
            }
            PanelQAHarness.drainMainRunLoop()
            _ = exerciseCurrentPage(in: rootView)
        }
    }

    @MainActor
    private static func exerciseCurrentPage(in rootView: NSView) -> Bool {
        for control in allSubviews(of: rootView) {
            if let recorder = control as? ShortcutRecorderButton {
                recorder.triggerForSmoke()
                PanelQAHarness.drainMainRunLoop()
                return true
            }

            if let control = control as? PreferenceSwitch, control.isEnabled {
                control.triggerForSmoke()
                PanelQAHarness.drainMainRunLoop()
                return true
            }

            if let control = control as? PreferenceSegmentedControl, control.segmentCount > 0 {
                control.triggerForSmoke()
                PanelQAHarness.drainMainRunLoop()
                return true
            }

            if let stepper = control as? PreferenceStepper {
                stepper.triggerForSmoke()
                PanelQAHarness.drainMainRunLoop()
                return true
            }
        }

        return false
    }

    @MainActor
    private static func navigationButton(titled title: String, in rootView: NSView) -> NSButton? {
        allSubviews(of: rootView)
            .compactMap { $0 as? NSButton }
            .first { $0.title == title }
    }

    @MainActor
    private static func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(of:))
    }
}

@MainActor
enum RealFunctionQAScenario {
    static func run() async throws -> RealFunctionQAReport {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let appSupportURL = try prepareArtifactsDirectory()
        let delegate = AppDelegate()
        delegate.smokePrepareRealFunctionQA(appSupportURL: appSupportURL)

        let copyText = "ClipDock QA real copy \(UUID().uuidString)"
        let deleteText = "ClipDock QA delete target \(UUID().uuidString)"

        delegate.smokeCaptureClipboardText(deleteText, changeCount: 10_001)
        delegate.smokeCaptureClipboardText(copyText, changeCount: 10_002)

        let addedItems = try await waitForStoredItems(delegate: delegate, expectedCount: 2)
        try PanelQAHarness.require(
            Set(addedItems.map { $0.primaryText ?? $0.summary }) == Set([copyText, deleteText]),
            "真实添加后的存储条目内容不正确"
        )

        let controller = delegate.smokePanelControllerForRealFunctionQA
        controller.show()
        try await waitForPanelItemCount(delegate: delegate, expectedCount: 2)
        let renderedItems = try delegate.smokeStoredItems()
        let contentView = controller.smokeContentView
        contentView.layoutSubtreeIfNeeded()
        try PanelQAHarness.require(
            PanelQAHarness.waitForPanelFocus(controller),
            "真实功能 QA 面板未获得键盘焦点: \(controller.smokeFocusDiagnostic)"
        )

        try PanelQAHarness.require(
            contentView.smokePerformManagementAction(itemID: renderedItems[0].id, title: "预览"),
            "真实捕获条目未找到预览菜单动作"
        )
        let previewShown = contentView.smokeIsPreviewShown
        try PanelQAHarness.require(previewShown, "真实捕获条目无法打开预览")
        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        let expectedCopiedText = renderedItems[0].primaryText ?? renderedItems[0].summary
        try verifyCommandShortcutCopy(contentView: contentView, expectedText: expectedCopiedText)

        let deleteItem = renderedItems.first { ($0.primaryText ?? $0.summary) == deleteText }
            ?? renderedItems[1]
        _ = try delegate.smokeRenderStoredItems()
        try PanelQAHarness.require(
            contentView.smokePerformManagementAction(itemID: deleteItem.id, title: "删除"),
            "真实删除菜单动作未找到"
        )
        let remainingItems: [RustClipboardItemSummary]
        do {
            remainingItems = try await waitForStoredItems(delegate: delegate, expectedCount: 1)
        } catch {
            throw PanelQAHarness.SmokeError(
                message: "\(error.localizedDescription); status=\(delegate.smokeStorageStatusTextForRealFunctionQA)"
            )
        }
        try PanelQAHarness.require(
            !remainingItems.contains(where: { $0.id == deleteItem.id }),
            "真实删除后存储仍包含目标条目"
        )

        return RealFunctionQAReport(
            artifactDirectory: appSupportURL.path,
            addedCount: addedItems.count,
            shortcut: "Command+1",
            preview: previewShown ? "shown" : "none",
            copiedText: NSPasteboard.general.string(forType: .string) ?? "",
            deletedText: deleteItem.primaryText ?? deleteItem.summary,
            remainingCount: remainingItems.count
        )
    }

    private static func prepareArtifactsDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("real-function-qa", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func verifyCommandShortcutCopy(
        contentView: FloatingPanelContentView,
        expectedText: String
    ) throws {
        NSPasteboard.general.clearContents()
        PanelQAHarness.sendCommandModifier(down: true, to: contentView)
        PanelQAHarness.sendCommandNumber(1, to: contentView)
        PanelQAHarness.drainMainRunLoop()

        try PanelQAHarness.require(
            NSPasteboard.general.string(forType: .string) == expectedText,
            "Command+1 未把目标条目真实写入系统剪贴板"
        )
    }

    private static func waitForStoredItems(
        delegate: AppDelegate,
        expectedCount: Int,
        timeout: TimeInterval = 1.4
    ) async throws -> [RustClipboardItemSummary] {
        let deadline = Date().addingTimeInterval(timeout)
        var latestItems = try delegate.smokeStoredItems()
        while Date() < deadline {
            if latestItems.count == expectedCount {
                return latestItems
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
            latestItems = try delegate.smokeStoredItems()
        }

        throw PanelQAHarness.SmokeError(
            message: "等待真实存储条目数量变为 \(expectedCount) 超时，当前为 \(latestItems.count)"
        )
    }

    private static func waitForPanelItemCount(
        delegate: AppDelegate,
        expectedCount: Int,
        timeout: TimeInterval = 1.4
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if delegate.smokePanelItemCount == expectedCount {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        throw PanelQAHarness.SmokeError(
            message: "等待真实捕获内容展示到面板超时，当前为 \(delegate.smokePanelItemCount)"
        )
    }
}

struct RealFunctionQAReport {
    let artifactDirectory: String
    let addedCount: Int
    let shortcut: String
    let preview: String
    let copiedText: String
    let deletedText: String
    let remainingCount: Int

    func emit() {
        print("realFunctions=ok")
        print("artifactDirectory=\(artifactDirectory)")
        print("addedCount=\(addedCount)")
        print("shortcutCopy=\(shortcut)")
        print("preview=\(preview)")
        print("pasteboardString=\(copiedText)")
        print("menuDelete=\(deletedText)")
        print("remainingCount=\(remainingCount)")
    }
}

@MainActor
enum PanelInteractionSmokeScenario {
    static func run() throws -> PanelInteractionSmokeReport {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let appSupportURL = try prepareArtifactsDirectory()
        let imageURL = try PanelQASamples.makePanelInteractionSmokeImageURL(outputDirectory: appSupportURL)
        let controller = FloatingPanelController()
        let sampleItems = PanelQASamples.makePanelInteractionItems(imagePath: imageURL.path)
        let probe = PanelInteractionSmokeProbe(controller: controller)

        controller.setAppSupportDirectory(appSupportURL)
        controller.show()
        controller.updatePinboards([
            RustPinboardSummary(
                id: "default",
                title: "固定",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])
        controller.updateListState(
            .success(RustCoreListResult(
                items: sampleItems,
                totalCount: Int64(sampleItems.count),
                hasMore: false
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        let contentView = controller.smokeContentView
        contentView.layoutSubtreeIfNeeded()
        try verifyCardLayout(in: contentView)
        try verifySelectionAndPreview(in: contentView)
        try verifyCommandHints(in: contentView)
        try verifyPinboardManagementEntrypoints(in: contentView)
        try verifyScrolling(in: contentView)
        let menuPreviewShown = try verifyManagementMenu(in: contentView, probe: probe)
        try verifyFilteringAndSearch(in: contentView, probe: probe)
        try verifySearchClearButton(in: contentView, probe: probe)
        try verifyEmptySearchClickAway(in: contentView)
        contentView.smokeOpenSearch(text: "report")
        PanelQAHarness.drainMainRunLoop()
        try verifyEscapeHide(in: contentView, controller: controller, probe: probe)
        let doubleClickCopiedItemID = try verifyCopyInteractions(in: contentView, controller: controller, probe: probe)
        let loadMoreCount = try verifyPaging(in: contentView, controller: controller, probe: probe)
        let prefetchedItemCount = try verifyPrefetchedLoadMore(appSupportURL: appSupportURL)

        return probe.makeReport(
            menuPreviewShown: menuPreviewShown,
            doubleClickCopiedItemID: doubleClickCopiedItemID,
            loadMoreCount: loadMoreCount,
            prefetchedItemCount: prefetchedItemCount
        )
    }

    private static func prepareArtifactsDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("panel-interaction-smoke", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func verifyCardLayout(in contentView: FloatingPanelContentView) throws {
        let cards = contentView.smokeCardBoxes()
        try PanelQAHarness.require(cards.count >= 5, "真实面板未渲染足够的条目卡片")
        try PanelQAHarness.require(contentView.smokeSelectedItemID == "panel-smoke-text", "初始选中项不正确")
        if let resizedCardSize = contentView.smokeFirstCardSize(afterPanelHeight: 420) {
            try PanelQAHarness.require(
                abs(resizedCardSize.width - resizedCardSize.height) < 0.5,
                "面板高度变化后条目卡片未保持 1:1"
            )
            try PanelQAHarness.require(
                resizedCardSize.width > BottomPanelGeometryPlanner.defaultHeight * 0.85,
                "面板高度变化后条目卡片宽度未跟随增长"
            )
            contentView.updatePanelHeight(BottomPanelGeometryPlanner.defaultHeight)
            contentView.layoutSubtreeIfNeeded()
        } else {
            try PanelQAHarness.require(false, "无法读取条目卡片尺寸")
        }
    }

    private static func verifySelectionAndPreview(in contentView: FloatingPanelContentView) throws {
        let cards = contentView.smokeCardBoxes()
        PanelQAHarness.sendMouseDown(to: cards[1], clickCount: 1)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(contentView.smokeSelectedItemID == "panel-smoke-image", "单击条目未立即选中")

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(contentView.smokeIsPreviewShown, "Space 未打开当前选中条目的预览")
        let previewButtonToolTips = contentView.smokePreviewActionButtonToolTips()
        try PanelQAHarness.require(previewButtonToolTips == ["关闭预览"], "预览浮层不应包含右侧编辑、分享或更多操作按钮")
        try PanelQAHarness.require(contentView.smokeClosePreviewWithSpaceFromPopoverFocus(), "预览焦点下的 Space 未被预览控制器接管")
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(!contentView.smokeIsPreviewShown, "预览显示后再次 Space 未关闭预览")
    }

    private static func verifyCommandHints(in contentView: FloatingPanelContentView) throws {
        try PanelQAHarness.require(contentView.smokeCommandHintTexts().isEmpty, "Command 提示默认应隐藏")
        PanelQAHarness.sendCommandModifier(down: true, to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(
            Array(contentView.smokeCommandHintTexts().prefix(3)) == ["1", "2", "3"],
            "Command 按下后未按完整可见条目从 1 开始编号"
        )
        PanelQAHarness.sendCommandModifier(down: false, to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(contentView.smokeCommandHintTexts().isEmpty, "Command 松开后提示应隐藏")
        PanelQAHarness.sendCommandModifier(down: true, to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(!contentView.smokeCommandHintTexts().isEmpty, "Command 再次按下未显示提示")
        PanelQAHarness.sendArrow(.right, to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(contentView.smokeCommandHintTexts().isEmpty, "未收到 Command 松开事件时，普通按键未清理提示")
    }

    private static func verifyFilteringAndSearch(
        in contentView: FloatingPanelContentView,
        probe: PanelInteractionSmokeProbe
    ) throws {
        if let pinboardChip = contentView.smokePinboardFilterButton(pinboardID: "default") {
            PanelQAHarness.sendMouseDown(to: pinboardChip, clickCount: 1)
            PanelQAHarness.drainMainRunLoop()
        }
        try PanelQAHarness.require(probe.lastQuery?.pinboardID == "default", "固定 chip 未触发默认 Pinboard 查询")

        contentView.smokeOpenSearch(text: "report")
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(contentView.smokeIsSearchVisible, "搜索输入前未打开可见搜索框")
        try PanelQAHarness.require(probe.lastQuery?.searchText == "report", "搜索输入未触发查询回调")
    }

    private static func verifySearchClearButton(
        in contentView: FloatingPanelContentView,
        probe: PanelInteractionSmokeProbe
    ) throws {
        let queryCountBeforeCancel = probe.queries.count
        try PanelQAHarness.require(
            contentView.smokeClickCustomSearchClearButton(),
            "搜索框自定义清除按钮未命中"
        )
        PanelQAHarness.drainMainRunLoop()

        let cancelQueries = Array(probe.queries.dropFirst(queryCountBeforeCancel))
        try PanelQAHarness.require(cancelQueries.count == 1, "搜索框自定义清除按钮应只触发一次查询")
        try PanelQAHarness.require(
            cancelQueries.first?.searchText == "" && cancelQueries.first?.debounce == false,
            "搜索框自定义清除按钮应触发一次立即空查询"
        )
        try PanelQAHarness.require(
            !cancelQueries.contains { $0.debounce },
            "搜索框自定义清除按钮不应额外触发 debounce 查询"
        )
        try PanelQAHarness.require(contentView.smokeIsSearchVisible, "搜索框自定义清除按钮不应关闭搜索框")
        try PanelQAHarness.require(contentView.smokeFirstResponderIsSearchField, "搜索框自定义清除按钮后焦点应保留在搜索框")
    }

    private static func verifyEmptySearchClickAway(in contentView: FloatingPanelContentView) throws {
        contentView.closePreviewPopover()
        contentView.smokeOpenSearch(text: "")
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(contentView.smokeIsSearchVisible, "空搜索点击外部前搜索框应保持可见")
        try PanelQAHarness.require(
            contentView.smokeClickPinboardFilterWithSearchClickAway(pinboardID: nil),
            "空搜索点击列表 chip 前未安排搜索框关闭: \(contentView.smokeSearchClickAwayDiagnostic)"
        )
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(!contentView.smokeIsSearchVisible, "空搜索点击列表 chip 后未关闭搜索框")
        try PanelQAHarness.require(contentView.smokeActiveListScope == .clipboard, "空搜索点击列表 chip 时原始点击未继续切换列表")
    }

    private static func verifyPinboardManagementEntrypoints(in contentView: FloatingPanelContentView) throws {
        try PanelQAHarness.require(
            contentView.smokeToolbarButtonToolTips().contains("创建 Pinboard"),
            "工具栏加号应直接暴露创建 Pinboard 入口"
        )
        try PanelQAHarness.require(
            contentView.smokeCreatePinboardAction()?.title == "未命名",
            "工具栏加号应按 ClipDock直接创建未命名 Pinboard，而不是打开命名弹窗"
        )
        try PanelQAHarness.require(
            contentView.smokeCreatedPinboardStartsInlineRename(),
            "新建 Pinboard chip 应立即进入内联编辑态，但不能自动切换当前列表"
        )
        try PanelQAHarness.require(
            contentView.smokePanelUsesLightBlurredBackground(),
            "面板根背景应使用 ClipDock浅色毛玻璃承载面，不能完全裸露桌面"
        )
        try PanelQAHarness.require(
            contentView.smokePanelUsesSystemGlassWhenAvailable(),
            "macOS 26 及以上应使用系统 NSGlassEffectView，而不是旧 NSVisualEffectView 近似方案"
        )
        try PanelQAHarness.require(
            contentView.smokePinboardChipAllowsLongIntrinsicWidth(),
            "Pinboard chip 应只保留最小宽度，不能限制长文本的最大显示长度"
        )

        let overflowItems = contentView.smokePanelOverflowMenuItems()
        try PanelQAHarness.require(
            overflowItems.map(\.title) == ["隐藏面板", "偏好设置"],
            "更多菜单应只展示隐藏面板和偏好设置"
        )
        try PanelQAHarness.require(
            overflowItems.allSatisfy { $0.isEnabled && !$0.hasSubmenu && !$0.hasCustomView },
            "更多菜单中的隐藏和偏好设置应为可直接触发的动作"
        )
        try PanelQAHarness.require(
            overflowItems.allSatisfy { $0.hasImage },
            "更多菜单中的动作应统一展示前置图标"
        )

        let pinboardMenuItems = contentView.smokePinboardChipMenuItems(pinboardID: "default")
        try PanelQAHarness.require(
            pinboardMenuItems.map(\.title) == ["重命名", "删除...", "颜色"],
            "Pinboard chip 右键菜单未按 ClipDock 样式展示重命名、删除和颜色入口"
        )
        try PanelQAHarness.require(
            pinboardMenuItems.allSatisfy { $0.hasImage },
            "Pinboard chip 右键菜单中的动作应统一展示前置图标"
        )
        try PanelQAHarness.require(
            contentView.smokePinboardRenameUsesInlineEditor(pinboardID: "default"),
            "Pinboard 重命名应使用 ClipDock chip 内联编辑态"
        )
        try PanelQAHarness.require(
            contentView.smokePinboardRenameCommitsOnFocusLoss(pinboardID: "default"),
            "Pinboard chip 内联重命名应在失去焦点时自动保存"
        )
        try PanelQAHarness.require(
            contentView.smokePinboardRenameResizesWhileTyping(pinboardID: "default"),
            "Pinboard chip 内联重命名应在输入过程中随文本实时扩展或缩小"
        )
        try PanelQAHarness.require(
            contentView.smokePinboardRenameCommitsBeforeInternalPanelClick(pinboardID: "default"),
            "Pinboard chip 内联重命名应在点击面板其他位置时先自动保存"
        )
        try PanelQAHarness.require(
            contentView.smokeEmptyDefaultPinboardIsHidden(),
            "空的默认固定分组不应作为默认数据出现在 Pinboard 列表中"
        )
        try PanelQAHarness.require(
            pinboardMenuItems.first(where: { $0.title == "颜色" })?.hasCustomView == true
                && contentView.smokePinboardChipColorMenuItems(pinboardID: "default").map(\.title)
                    == ["红色", "橙色", "黄色", "绿色", "蓝色", "紫色", "粉色", "灰色"],
            "Pinboard chip 右键颜色行缺少 ClipDock 风格颜色选项"
        )
        try PanelQAHarness.require(
            contentView.smokePinboardDeleteRequiresConfirmation(pinboardID: "default") == true
                && contentView.smokeNonEmptyPinboardDeleteRequiresConfirmation() == true,
            "Pinboard 删除应按 ClipDock总是二次确认"
        )
    }

    private static func verifyScrolling(in contentView: FloatingPanelContentView) throws {
        if let scrollView = contentView.smokeHorizontalScrollView(),
           let documentView = scrollView.documentView,
           documentView.frame.width > scrollView.contentView.bounds.width + 1 {
            let initialX = scrollView.contentView.bounds.origin.x
            PanelQAHarness.sendVerticalScrollWheel(to: scrollView, deltaY: -180)
            PanelQAHarness.drainMainRunLoop()
            var scrolledX = scrollView.contentView.bounds.origin.x
            if abs(scrolledX - initialX) < 1 {
                PanelQAHarness.sendVerticalScrollWheel(to: scrollView, deltaY: 180)
                PanelQAHarness.drainMainRunLoop()
                scrolledX = scrollView.contentView.bounds.origin.x
            }
            try PanelQAHarness.require(abs(scrolledX - initialX) >= 1, "纵向滚轮未投射为横向滚动")
        }
    }

    private static func verifyManagementMenu(
        in contentView: FloatingPanelContentView,
        probe: PanelInteractionSmokeProbe
    ) throws -> Bool {
        try PanelQAHarness.require(
            contentView.smokePerformManagementAction(itemID: "panel-smoke-file", title: "固定"),
            "未找到 Pinboard 固定菜单动作"
        )
        try PanelQAHarness.require(
            probe.pinboardRequest?.itemID == "panel-smoke-file"
                && probe.pinboardRequest?.pinboardID == "default"
                && probe.pinboardRequest?.isMember == true,
            "Pinboard 固定菜单动作未触发回调"
        )

        let managementMenuItems = contentView.smokeManagementMenuItems(itemID: "panel-smoke-file")
        try PanelQAHarness.require(
            managementMenuItems.map(\.title) == ["复制", "删除", "固定", "预览"],
            "右键菜单应使用 ClipDock 风格的固定子菜单"
        )
        try PanelQAHarness.require(
            managementMenuItems.allSatisfy { $0.hasImage },
            "右键菜单中的动作应统一展示前置图标"
        )
        try PanelQAHarness.require(
            managementMenuItems.first(where: { $0.title == "固定" })?.hasSubmenu == true,
            "固定菜单项应展开 Pinboard 列表"
        )
        let pinboardSubmenuItems = contentView.smokeManagementSubmenuItems(itemID: "panel-smoke-file", title: "固定")
        try PanelQAHarness.require(
            pinboardSubmenuItems.map(\.title) == ["固定", "创建 Pinboard..."],
            "固定子菜单应展示默认 Pinboard 和创建入口"
        )
        try PanelQAHarness.require(
            pinboardSubmenuItems.allSatisfy { $0.hasImage },
            "固定子菜单中的动作应统一展示前置图标"
        )
        let emptyPinboardMenu = contentView.smokeManagementPinboardMenuWithNoPinboards(itemID: "panel-smoke-file")
        try PanelQAHarness.require(
            emptyPinboardMenu?.isEnabled == true
                && emptyPinboardMenu?.titles == ["创建 Pinboard..."],
            "不存在任何 Pinboard 时固定子菜单仍应可点击并展示创建入口"
        )
        try PanelQAHarness.require(
            emptyPinboardMenu?.allItemsHaveImages == true,
            "不存在任何 Pinboard 时固定子菜单的创建入口仍应展示前置图标"
        )
        try PanelQAHarness.require(
            managementMenuItems.first(where: { $0.title == "复制" })?.keyEquivalent == "c",
            "复制菜单缺少 Command-C 快捷键提示"
        )
        try PanelQAHarness.require(
            managementMenuItems.first(where: { $0.title == "预览" })?.keyEquivalent == " ",
            "预览菜单缺少 Space 快捷键提示"
        )

        try PanelQAHarness.require(
            contentView.smokePerformManagementAction(itemID: "panel-smoke-file", title: "删除"),
            "未找到删除菜单动作"
        )
        try PanelQAHarness.require(probe.deletedItemID == "panel-smoke-file", "删除菜单动作未触发回调")

        try PanelQAHarness.require(
            contentView.smokePerformManagementAction(itemID: "panel-smoke-file", title: "预览"),
            "未找到预览菜单动作"
        )
        let menuPreviewShown = contentView.smokeIsPreviewShown
        try PanelQAHarness.require(menuPreviewShown, "预览菜单动作未打开预览浮层")
        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(!contentView.smokeIsPreviewShown, "右键预览打开后 Space 未关闭预览")
        return menuPreviewShown
    }

    private static func verifyEscapeHide(
        in contentView: FloatingPanelContentView,
        controller: FloatingPanelController,
        probe: PanelInteractionSmokeProbe
    ) throws {
        let queryCountBeforeClear = probe.queries.count
        PanelQAHarness.sendEscape(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(probe.lastQuery?.searchText == "", "Escape 未先清空搜索")
        try PanelQAHarness.require(
            probe.queries.count == queryCountBeforeClear + 1,
            "Escape 清空搜索应只发出一次空查询"
        )
        try PanelQAHarness.require(contentView.smokeIsSearchVisible, "Escape 清空非空搜索后搜索框应保持可见")
        try PanelQAHarness.require(controller.isVisible, "Escape 清空搜索时不应隐藏面板")

        if let clipboardChip = contentView.smokePinboardFilterButton(pinboardID: nil) {
            PanelQAHarness.sendMouseDown(to: clipboardChip, clickCount: 1)
            PanelQAHarness.drainMainRunLoop()
        }
        let queryCountBeforeClose = probe.queries.count

        PanelQAHarness.sendEscape(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(
            probe.queries.count == queryCountBeforeClose,
            "Escape 关闭空搜索框不应重复触发查询"
        )
        try PanelQAHarness.require(!contentView.smokeIsSearchVisible, "Escape 未关闭空搜索框")
        try PanelQAHarness.require(controller.isVisible, "Escape 关闭空搜索框时不应隐藏面板")
        try PanelQAHarness.require(
            controller.smokeFirstResponderIsContentView,
            "Escape 关闭空搜索框后未把焦点还给面板: \(controller.smokeFocusDiagnostic)"
        )

        PanelQAHarness.sendEscape(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(probe.hideCount == 1 && !controller.isVisible, "搜索为空时 Escape 未隐藏面板")
    }

    private static func verifyCopyInteractions(
        in contentView: FloatingPanelContentView,
        controller: FloatingPanelController,
        probe: PanelInteractionSmokeProbe
    ) throws -> String {
        controller.show()
        try PanelQAHarness.require(
            PanelQAHarness.waitForPanelFocus(controller),
            "快捷键显示面板后面板未进入可交互状态: \(controller.smokeFocusDiagnostic)"
        )
        try PanelQAHarness.require(
            controller.smokeFirstResponderIsContentView,
            "快捷键显示面板后 content view 未成为 first responder: \(controller.smokeFocusDiagnostic)"
        )

        let refreshedCards = contentView.smokeCardBoxes()
        try PanelQAHarness.require(refreshedCards.count >= 1, "面板重新显示后未保留条目卡片")
        PanelQAHarness.sendMouseDown(to: refreshedCards[0], clickCount: 2)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(probe.copiedItemID == "panel-smoke-text", "双击条目未触发复制回调")
        let doubleClickCopiedItemID = probe.copiedItemID
        try PanelQAHarness.require(!controller.isVisible, "双击复制后面板未隐藏")

        probe.copiedItemID = nil
        controller.show()
        PanelQAHarness.drainMainRunLoop()
        if let scrollView = contentView.smokeHorizontalScrollView() {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        PanelQAHarness.sendCommandModifier(down: true, to: contentView)
        PanelQAHarness.sendCommandNumber(3, to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(probe.copiedItemID == "panel-smoke-file", "Command+3 未直接复制第三个完整可见条目")
        try PanelQAHarness.require(!controller.isVisible, "Command+数字复制后面板未隐藏")
        return doubleClickCopiedItemID ?? "none"
    }

    private static func verifyPaging(
        in contentView: FloatingPanelContentView,
        controller: FloatingPanelController,
        probe: PanelInteractionSmokeProbe
    ) throws -> Int {
        let pagedItems = PanelQASamples.makePagedPanelItems(count: 75)
        let firstPage = Array(pagedItems.prefix(50))
        let secondPage = Array(pagedItems.dropFirst(50))
        let loadMoreCountBeforePaging = probe.loadMoreRequestCount
        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(
                items: firstPage,
                totalCount: Int64(pagedItems.count),
                hasMore: true
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(contentView.smokeCurrentItemCount == 50, "第一页分页条目数量不正确")
        try PanelQAHarness.require(
            contentView.smokeOrderedCardItemIDs() == firstPage.map(\.id),
            "第一页分页条目顺序不正确"
        )
        contentView.smokeScrollToLoadMoreThreshold()
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(
            probe.loadMoreRequestCount == loadMoreCountBeforePaging + 1,
            "横向滚动到末尾未触发加载更多请求"
        )
        try PanelQAHarness.require(contentView.smokeIsLoadingMoreActive, "加载更多请求后未进入加载状态")

        contentView.updateListState(
            .success(RustCoreListResult(
                items: secondPage,
                totalCount: Int64(pagedItems.count),
                hasMore: false
            )),
            isFiltered: false,
            append: true
        )
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(contentView.smokeCurrentItemCount == 75, "第二页追加后总条目数量不正确")
        try PanelQAHarness.require(!contentView.smokeIsLoadingMoreActive, "第二页追加完成后加载状态未清理")
        try PanelQAHarness.require(
            contentView.smokeOrderedCardItemIDs() == pagedItems.map(\.id),
            "加载更多后有序条目 ID 未保持分页拼接结果"
        )
        try PanelQAHarness.require(
            contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound,
            "加载更多后 collection surface 保留的 cell/card 数量超过可见窗口上界"
        )
        return probe.loadMoreRequestCount - loadMoreCountBeforePaging
    }

    private static func verifyPrefetchedLoadMore(appSupportURL: URL) throws -> Int {
        let pagedItems = PanelQASamples.makePagedPanelItems(count: 75)
        let firstPage = Array(pagedItems.prefix(50))
        let secondPage = Array(pagedItems.dropFirst(50))
        let delegate = AppDelegate()
        delegate.smokePreparePrefetchedLoadMore(
            appSupportURL: appSupportURL,
            firstPage: firstPage,
            prefetchedPage: secondPage,
            totalCount: Int64(pagedItems.count)
        )
        delegate.smokeConsumeLoadMore()
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(
            delegate.smokeLoadedClipboardItemCount == 75,
            "预取页命中后未立即推进已加载数量"
        )
        try PanelQAHarness.require(
            delegate.smokePanelItemCount == 75,
            "预取页命中后未立即追加到面板"
        )
        try PanelQAHarness.require(
            !delegate.smokeIsLoadingMoreClipboardItems,
            "预取页命中后不应进入等待加载状态"
        )
        return Int(delegate.smokeLoadedClipboardItemCount)
    }
}

@MainActor
final class PanelInteractionSmokeProbe {
    struct Query {
        let searchText: String
        let sourceAppID: String?
        let pinboardID: String?
        let debounce: Bool
    }

    private(set) var queries: [Query] = []
    var copiedItemID: String?
    var copiedItemIDs: [String] = []
    private(set) var pinboardRequest: (itemID: String, pinboardID: String, isMember: Bool)?
    private(set) var deletedItemID: String?
    private(set) var hideCount = 0
    private(set) var loadMoreRequestCount = 0

    var lastQuery: Query? {
        queries.last
    }

    init(controller: FloatingPanelController) {
        controller.onRuntimeAction = { [weak self, weak controller] action in
            switch action {
            case .showPreferences:
                break
            case .hidePanel:
                self?.hideCount += 1
                controller?.hide()
            case .queryChanged(let searchText, _, let sourceAppID, let pinboardID, let debounce):
                self?.queries.append(Query(
                    searchText: searchText,
                    sourceAppID: sourceAppID,
                    pinboardID: pinboardID,
                    debounce: debounce
                ))
            case .copyItem(let item):
                self?.copiedItemID = item.id
                self?.copiedItemIDs = [item.id]
                controller?.hideAfterCopyingSelection()
            case .copyItems(let items):
                self?.copiedItemID = items.first?.id
                self?.copiedItemIDs = items.map(\.id)
                controller?.hideAfterCopyingSelection()
            case .copyItemAsPlainText(let item):
                self?.copiedItemID = item.id
                self?.copiedItemIDs = [item.id]
                controller?.hideAfterCopyingSelection()
            case .copyItemsAsPlainText(let items):
                self?.copiedItemID = items.first?.id
                self?.copiedItemIDs = items.map(\.id)
                controller?.hideAfterCopyingSelection()
            case .copyPath:
                controller?.hideAfterCopyingSelection()
            case .setPinboardMembership(let item, let pinboardID, let isMember):
                self?.pinboardRequest = (item.id, pinboardID, isMember)
            case .setPinboardMembershipBatch(let items, let pinboardID, let isMember):
                self?.pinboardRequest = (items.first?.id ?? "", pinboardID, isMember)
            case .createPinboard, .renamePinboard, .updatePinboardColor, .deletePinboard:
                break
            case .deleteItem(let item, _):
                self?.deletedItemID = item.id
            case .deleteItems(let items, _):
                self?.deletedItemID = items.first?.id
            case .loadMore:
                self?.loadMoreRequestCount += 1
            }
        }
    }

    func makeReport(
        menuPreviewShown: Bool,
        doubleClickCopiedItemID: String,
        loadMoreCount: Int,
        prefetchedItemCount: Int
    ) -> PanelInteractionSmokeReport {
        PanelInteractionSmokeReport(
            singleClickItemID: "panel-smoke-image",
            commandHints: "1,2,3",
            commandNumberCopyItemID: "panel-smoke-file",
            categoryFilter: "removed",
            searchText: queries.first { $0.searchText == "report" }?.searchText ?? "none",
            menuPin: pinboardRequest.map { "\($0.itemID):\($0.pinboardID):\($0.isMember)" } ?? "none",
            menuDelete: deletedItemID ?? "none",
            menuPreview: menuPreviewShown ? "shown" : "none",
            escapeHideCount: hideCount,
            doubleClickCopyItemID: doubleClickCopiedItemID,
            loadMoreCount: loadMoreCount,
            prefetchedLoadMoreCount: prefetchedItemCount
        )
    }
}

struct PanelInteractionSmokeReport {
    let singleClickItemID: String
    let commandHints: String
    let commandNumberCopyItemID: String
    let categoryFilter: String
    let searchText: String
    let menuPin: String
    let menuDelete: String
    let menuPreview: String
    let escapeHideCount: Int
    let doubleClickCopyItemID: String
    let loadMoreCount: Int
    let prefetchedLoadMoreCount: Int

    func emit() {
        print("panelInteractions=ok")
        print("singleClick=\(singleClickItemID)")
        print("commandHints=\(commandHints)")
        print("command3Copy=\(commandNumberCopyItemID)")
        print("categoryFilter=\(categoryFilter)")
        print("search=\(searchText)")
        print("menuPin=\(menuPin)")
        print("menuDelete=\(menuDelete)")
        print("menuPreview=\(menuPreview)")
        print("escapeHide=\(escapeHideCount)")
        print("doubleClickCopy=\(doubleClickCopyItemID)")
        print("loadMore=\(loadMoreCount)")
        print("prefetchLoadMore=\(prefetchedLoadMoreCount)")
    }
}
