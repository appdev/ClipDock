import AppKit

@MainActor
protocol ClipboardMonitoring: AnyObject {
    var onTextCaptured: ((String, Int) -> Void)? { get set }
    var onImageCaptured: ((CapturedClipboardImage, Int) -> Void)? { get set }
    var onFilesCaptured: ((CapturedClipboardFiles, Int) -> Void)? { get set }

    func start()
    func stop()
    func markSelfWrite(token: String, from startChangeCount: Int, through endChangeCount: Int)
}

@MainActor
protocol ClipboardContentReading {
    func readContent(from pasteboard: NSPasteboard) -> ClipboardPayloadSnapshot?
}

enum ClipboardPayloadSnapshot {
    case text(String)
    case image(CapturedClipboardImage)
    case files(CapturedClipboardFiles)
}

struct ClipboardPayloadReader: ClipboardContentReading {
    func readContent(from pasteboard: NSPasteboard) -> ClipboardPayloadSnapshot? {
        if let files = CapturedClipboardFiles.read(from: pasteboard) {
            return .files(files)
        }

        if let image = CapturedClipboardImage.read(from: pasteboard, skipFileURLCheck: true) {
            return .image(image)
        }

        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return nil
        }

        return .text(text)
    }
}

@MainActor
final class ClipboardMonitor: ClipboardMonitoring {
    static let selfWriteTokenPasteboardType = NSPasteboard.PasteboardType("com.clipboardworkbench.self-write-token")

    private let pasteboard: NSPasteboard
    private let pollInterval: TimeInterval
    private let payloadReader: ClipboardContentReading
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCounts = Set<Int>()
    private var ignoredSelfWriteTokens = Set<String>()
    var onTextCaptured: ((String, Int) -> Void)?
    var onImageCaptured: ((CapturedClipboardImage, Int) -> Void)?
    var onFilesCaptured: ((CapturedClipboardFiles, Int) -> Void)?

    init(
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 0.45,
        payloadReader: ClipboardContentReading = ClipboardPayloadReader()
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.payloadReader = payloadReader
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markSelfWrite(token: String, from startChangeCount: Int, through endChangeCount: Int) {
        let lowerBound = min(startChangeCount, endChangeCount)
        let upperBound = max(startChangeCount, endChangeCount)
        for changeCount in lowerBound...upperBound {
            ignoredChangeCounts.insert(changeCount)
        }
        ignoredSelfWriteTokens.insert(token)
        trimIgnoredMarkers()
    }

    private func pollPasteboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if shouldIgnoreSelfWrite(pasteboard: pasteboard, changeCount: changeCount) {
            return
        }

        switch payloadReader.readContent(from: pasteboard) {
        case .files(let files):
            onFilesCaptured?(files, changeCount)

        case .image(let image):
            onImageCaptured?(image, changeCount)

        case .text(let text):
            onTextCaptured?(text, changeCount)

        case nil:
            return
        }
    }

    private func shouldIgnoreSelfWrite(pasteboard: NSPasteboard, changeCount: Int) -> Bool {
        let token = pasteboard.string(forType: Self.selfWriteTokenPasteboardType)
        if ignoredChangeCounts.remove(changeCount) != nil {
            if let token {
                ignoredSelfWriteTokens.remove(token)
            }
            return true
        }

        if let token, ignoredSelfWriteTokens.remove(token) != nil {
            return true
        }

        return false
    }

    private func trimIgnoredMarkers() {
        let maximumMarkerCount = 32
        if ignoredChangeCounts.count > maximumMarkerCount {
            ignoredChangeCounts = Set(ignoredChangeCounts.sorted().suffix(maximumMarkerCount))
        }

        if ignoredSelfWriteTokens.count > maximumMarkerCount {
            ignoredSelfWriteTokens.removeAll()
        }
    }
}
