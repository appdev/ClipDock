import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp

enum PanelQASamples {
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

    static func makePanelSnapshotItems(imagePath: String) -> [RustClipboardItemSummary] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return [
            makeItem(
                id: "snapshot-text",
                itemType: "text",
                summary: "多行文本内容会在真实卡片中换行展示，避免只剩一行。",
                primaryText: "多行文本内容会在真实卡片中换行展示，避免只剩一行。",
                sourceAppName: "备忘录",
                timestamp: now,
                contentHash: "snapshot-snapshot-text",
                sizeBytes: 68
            ),
            makeItem(
                id: "snapshot-image",
                itemType: "image",
                summary: "图片 420 x 260",
                primaryText: nil,
                sourceAppName: "预览",
                timestamp: now - 120_000,
                contentHash: "snapshot-snapshot-image",
                previewAssetPath: imagePath,
                payloadAssetPath: imagePath,
                sizeBytes: 184_000
            ),
            makeItem(
                id: "snapshot-file",
                itemType: "file",
                summary: "report.pdf",
                primaryText: "/Users/evan/Downloads/report.pdf",
                sourceAppName: "Finder",
                timestamp: now - 240_000,
                contentHash: "snapshot-snapshot-file",
                sizeBytes: 2048
            ),
            makeItem(
                id: "snapshot-link",
                itemType: "link",
                summary: "example.com",
                primaryText: "https://example.com/docs/production-ui?from=clipboard",
                sourceAppName: "Safari",
                timestamp: now - 360_000,
                contentHash: "snapshot-snapshot-link",
                sizeBytes: 56
            ),
            makeItem(
                id: "snapshot-terminal",
                itemType: "text",
                summary: "git push --set-upstream origin main",
                primaryText: "git push --set-upstream origin main",
                sourceAppName: "终端",
                timestamp: now - 1_620_000,
                contentHash: "snapshot-snapshot-terminal",
                sizeBytes: 35
            ),
            makeItem(
                id: "snapshot-hash",
                itemType: "text",
                summary: "f7543c5e99",
                primaryText: "f7543c5e99",
                sourceAppName: "Xcode",
                timestamp: now - 50_400_000,
                contentHash: "snapshot-snapshot-hash",
                sizeBytes: 10
            )
        ]
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

    static func makePanelInteractionItems(imagePath: String) -> [RustClipboardItemSummary] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var items = [
            makeItem(
                id: "panel-smoke-text",
                itemType: "text",
                summary: "真实窗口交互 smoke 文本",
                primaryText: "真实窗口交互 smoke 文本",
                sourceAppName: "备忘录",
                timestamp: now,
                contentHash: "panel-smoke-panel-smoke-text",
                sizeBytes: 34
            ),
            makeItem(
                id: "panel-smoke-image",
                itemType: "image",
                summary: "图片 360 x 220",
                primaryText: nil,
                sourceAppName: "预览",
                timestamp: now - 60_000,
                contentHash: "panel-smoke-panel-smoke-image",
                previewAssetPath: imagePath,
                payloadAssetPath: imagePath,
                sizeBytes: 124_000
            ),
            makeItem(
                id: "panel-smoke-file",
                itemType: "file",
                summary: "2 个文件 · report.pdf",
                primaryText: nil,
                sourceAppName: "Finder",
                timestamp: now - 120_000,
                contentHash: "panel-smoke-panel-smoke-file",
                sizeBytes: 2048
            ),
            makeItem(
                id: "panel-smoke-link",
                itemType: "link",
                summary: "example.com",
                primaryText: "https://example.com",
                sourceAppName: "Safari",
                timestamp: now - 180_000,
                contentHash: "panel-smoke-panel-smoke-link",
                sizeBytes: 19
            )
        ]

        for index in 5...16 {
            items.append(makeItem(
                id: "panel-smoke-extra-\(index)",
                itemType: "text",
                summary: "横向滚动填充条目 \(index)",
                primaryText: "横向滚动填充条目 \(index)",
                sourceAppName: "终端",
                timestamp: now - Int64(index * 60_000),
                contentHash: "panel-smoke-panel-smoke-extra-\(index)",
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

    static func makePreviewItem(isLongText: Bool) -> RustClipboardItemSummary {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let body = isLongText
            ? Array(repeating: """
                Paste 预览窗口需要根据内容自动调整尺寸。短文本不应该撑成固定大盒子，长文本则应该在最大高度内自动换行，并通过滚动继续阅读后续内容。

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
            sourceAppName: "设置",
            sourceAppIconPath: nil,
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
    static func makePreviewImageItem(outputDirectory: URL) throws -> RustClipboardItemSummary {
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
            sourceAppIconPath: nil,
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
        previewAssetPath: String? = nil,
        payloadAssetPath: String? = nil,
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
            sourceAppIconPath: nil,
            previewAssetPath: previewAssetPath,
            payloadAssetPath: payloadAssetPath,
            sourceConfidence: "high",
            firstCopiedAtMs: timestamp,
            lastCopiedAtMs: timestamp,
            copyCount: 1,
            isPinned: false,
            sizeBytes: sizeBytes,
            previewState: "ready"
        )
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
    static func sendArrow(_ direction: ArrowDirection, to view: NSView) {
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
            modifierFlags: [],
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
            modifierFlags: [.command],
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
            if let button = control as? PreferenceCheckboxButton {
                button.triggerForSmoke()
                PanelQAHarness.drainMainRunLoop()
                return true
            }

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

        let copyText = "Paste QA real copy \(UUID().uuidString)"
        let deleteText = "Paste QA delete target \(UUID().uuidString)"

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
        try verifyFilteringAndSearch(in: contentView, probe: probe)
        try verifyPinboardManagementEntrypoints(in: contentView)
        try verifyScrolling(in: contentView)
        let menuPreviewShown = try verifyManagementMenu(in: contentView, probe: probe)
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

        contentView.smokeSearchField.stringValue = "report"
        contentView.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: contentView.smokeSearchField
        ))
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(probe.lastQuery?.searchText == "report", "搜索输入未触发查询回调")
    }

    private static func verifyPinboardManagementEntrypoints(in contentView: FloatingPanelContentView) throws {
        try PanelQAHarness.require(
            contentView.smokeToolbarButtonToolTips().contains("创建 Pinboard"),
            "工具栏加号应直接暴露创建 Pinboard 入口"
        )
        try PanelQAHarness.require(
            contentView.smokeCreatePinboardAction()?.title == "未命名",
            "工具栏加号应按 Paste 实拍直接创建未命名 Pinboard，而不是打开命名弹窗"
        )
        try PanelQAHarness.require(
            contentView.smokeCreatedPinboardStartsInlineRename(),
            "新建 Pinboard chip 应立即进入内联编辑态，但不能自动切换当前列表"
        )
        try PanelQAHarness.require(
            contentView.smokePanelUsesLightBlurredBackground(),
            "面板根背景应使用 Paste 式浅色毛玻璃承载面，不能完全裸露桌面"
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
            Array(overflowItems.prefix(4).map(\.title)) == [
                "重命名",
                "共享 Pinboard",
                "删除...",
                "颜色"
            ],
            "更多菜单未按 Paste 样式展示 Pinboard 重命名、共享、删除和颜色入口"
        )
        try PanelQAHarness.require(
            overflowItems.first(where: { $0.title == "重命名" })?.isEnabled == true
                && overflowItems.first(where: { $0.title == "共享 Pinboard" })?.isEnabled == true
                && overflowItems.first(where: { $0.title == "删除..." })?.isEnabled == true
                && overflowItems.first(where: { $0.title == "颜色" })?.hasCustomView == true,
            "选择 Pinboard 后更多菜单中的管理项应可用"
        )

        let pinboardMenuItems = contentView.smokePinboardChipMenuItems(pinboardID: "default")
        try PanelQAHarness.require(
            pinboardMenuItems.map(\.title) == ["重命名", "删除...", "颜色"],
            "Pinboard chip 右键菜单未按 Paste 样式展示重命名、删除和颜色入口"
        )
        try PanelQAHarness.require(
            contentView.smokePinboardRenameUsesInlineEditor(pinboardID: "default"),
            "Pinboard 重命名应使用 Paste 式 chip 内联编辑态"
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
            "Pinboard chip 右键颜色行缺少 Paste 风格颜色选项"
        )
        try PanelQAHarness.require(
            contentView.smokePinboardDeleteRequiresConfirmation(pinboardID: "default") == true
                && contentView.smokeNonEmptyPinboardDeleteRequiresConfirmation() == true,
            "Pinboard 删除应按 Paste 实拍总是二次确认"
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
            "右键菜单应使用 Paste 风格的固定子菜单"
        )
        try PanelQAHarness.require(
            managementMenuItems.first(where: { $0.title == "固定" })?.hasSubmenu == true,
            "固定菜单项应展开 Pinboard 列表"
        )
        try PanelQAHarness.require(
            contentView.smokeManagementSubmenuItems(itemID: "panel-smoke-file", title: "固定")
                .map(\.title) == ["固定", "创建 Pinboard..."],
            "固定子菜单应展示默认 Pinboard 和创建入口"
        )
        let emptyPinboardMenu = contentView.smokeManagementPinboardMenuWithNoPinboards(itemID: "panel-smoke-file")
        try PanelQAHarness.require(
            emptyPinboardMenu?.isEnabled == true
                && emptyPinboardMenu?.titles == ["创建 Pinboard..."],
            "不存在任何 Pinboard 时固定子菜单仍应可点击并展示创建入口"
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
        PanelQAHarness.sendEscape(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        try PanelQAHarness.require(probe.lastQuery?.searchText == "", "Escape 未先清空搜索")

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
        guard let firstPagedCardBeforeAppend = contentView.smokeCardBoxes().first else {
            throw PanelQAHarness.SmokeError(message: "第一页未渲染可检查的条目卡片")
        }
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
            contentView.smokeCardBoxes().first === firstPagedCardBeforeAppend,
            "加载更多后不应重建第一页已有卡片"
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
    }

    private(set) var queries: [Query] = []
    var copiedItemID: String?
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
            case .queryChanged(let searchText, let sourceAppID, let pinboardID, _):
                self?.queries.append(Query(
                    searchText: searchText,
                    sourceAppID: sourceAppID,
                    pinboardID: pinboardID
                ))
            case .copyItem(let item):
                self?.copiedItemID = item.id
                controller?.hide()
            case .setPinboardMembership(let item, let pinboardID, let isMember):
                self?.pinboardRequest = (item.id, pinboardID, isMember)
            case .createPinboard, .renamePinboard, .updatePinboardColor, .deletePinboard:
                break
            case .deleteItem(let item):
                self?.deletedItemID = item.id
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
