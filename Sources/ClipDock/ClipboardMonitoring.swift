import AppKit
import ClipboardPanelApp

@MainActor
protocol ClipboardMonitoring: AnyObject {
    var onTextCaptured: ((String, ClipboardCapturedRichText?, Int) -> Void)? { get set }
    var onRichTextCaptured: ((ClipboardCapturedRichText, Int) -> Void)? { get set }
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
    case text(String, displayRichText: ClipboardCapturedRichText? = nil)
    case richText(ClipboardCapturedRichText)
    case image(CapturedClipboardImage)
    case files(CapturedClipboardFiles)
}

struct ClipboardPayloadReader: ClipboardContentReading {
    private enum Limits {
        static let maxRTFBytes = 5 * 1024 * 1024
        static let maxHTMLBytes = 2 * 1024 * 1024
        static let maxStoredPlainTextBytes = 1024 * 1024
        static let captureBudget: TimeInterval = 0.250
    }

    func readContent(from pasteboard: NSPasteboard) -> ClipboardPayloadSnapshot? {
        if let files = CapturedClipboardFiles.read(from: pasteboard) {
            return .files(files)
        }

        let image = CapturedClipboardImage.read(from: pasteboard, skipFileURLCheck: true)

        if let image {
            return .image(image)
        }

        let html = htmlString(from: pasteboard)
        let htmlBacked = html != nil
        let richText = readBestRichText(from: pasteboard, htmlBacked: htmlBacked)

        if let text = normalizedPlainText(from: pasteboard.string(forType: .string)) {
            if let richText {
                if plainTextAppearsAuthoritative(in: pasteboard),
                   richTextMatchesPlainText(richText, text) {
                    return .text(text, displayRichText: richText)
                }
                return .richText(richText)
            }
            return .text(text)
        }

        if let richText {
            return .richText(richText)
        }

        if image == nil,
           let text = readHTMLPlainText(from: pasteboard) {
            return .text(text)
        }

        return nil
    }

    private func readBestRichText(
        from pasteboard: NSPasteboard,
        htmlBacked: Bool
    ) -> ClipboardCapturedRichText? {
        if let richText = readFlatRTF(from: pasteboard, htmlBacked: htmlBacked) {
            return richText
        }

        if let richText = readRTFDAsFlatRTF(from: pasteboard, htmlBacked: htmlBacked) {
            return richText
        }

        return readHTMLAsFlatRTF(from: pasteboard)
    }

    private func readFlatRTF(
        from pasteboard: NSPasteboard,
        htmlBacked: Bool
    ) -> ClipboardCapturedRichText? {
        for pasteboardType in [NSPasteboard.PasteboardType.rtf, NSPasteboard.PasteboardType("public.rtf")] {
            guard let data = boundedData(for: pasteboardType, from: pasteboard, byteLimit: Limits.maxRTFBytes) else {
                continue
            }
            let start = Date()
            guard let attributed = attributedString(from: data, documentType: .rtf),
                  Date().timeIntervalSince(start) <= Limits.captureBudget,
                  hasRichEvidence(in: attributed, sourceData: data, htmlBacked: htmlBacked),
                  let text = normalizedPlainText(from: attributed)
            else {
                continue
            }
            return ClipboardCapturedRichText(text: text, rtfData: data)
        }
        return nil
    }

    private func readRTFDAsFlatRTF(
        from pasteboard: NSPasteboard,
        htmlBacked: Bool
    ) -> ClipboardCapturedRichText? {
        for pasteboardType in [NSPasteboard.PasteboardType.rtfd, NSPasteboard.PasteboardType("com.apple.rtfd")] {
            guard let data = boundedData(for: pasteboardType, from: pasteboard, byteLimit: Limits.maxRTFBytes) else {
                continue
            }
            let start = Date()
            guard let attributed = attributedString(from: data, documentType: .rtfd),
                  Date().timeIntervalSince(start) <= Limits.captureBudget,
                  hasRichEvidence(in: attributed, sourceData: nil, htmlBacked: htmlBacked),
                  let text = normalizedPlainText(from: attributed),
                  let rtfData = flatRTFData(from: attributed),
                  rtfData.count <= Limits.maxRTFBytes
            else {
                continue
            }
            return ClipboardCapturedRichText(text: text, rtfData: rtfData)
        }
        return nil
    }

    private func readHTMLAsFlatRTF(from pasteboard: NSPasteboard) -> ClipboardCapturedRichText? {
        for pasteboardType in [NSPasteboard.PasteboardType.html, NSPasteboard.PasteboardType("public.html")] {
            guard let data = boundedData(for: pasteboardType, from: pasteboard, byteLimit: Limits.maxHTMLBytes),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
                  hasStrongRichHTMLEvidence(html),
                  !isImageOnlyHTMLMetadata(html)
            else {
                continue
            }

            let start = Date()
            guard let attributed = attributedString(from: data, documentType: .html),
                  Date().timeIntervalSince(start) <= Limits.captureBudget,
                  let text = normalizedPlainText(from: attributed),
                  let rtfData = flatRTFData(from: attributed),
                  rtfData.count <= Limits.maxRTFBytes
            else {
                continue
            }
            return ClipboardCapturedRichText(text: text, rtfData: rtfData)
        }
        return nil
    }

    private func readHTMLPlainText(from pasteboard: NSPasteboard) -> String? {
        for pasteboardType in [NSPasteboard.PasteboardType.html, NSPasteboard.PasteboardType("public.html")] {
            guard let data = boundedData(for: pasteboardType, from: pasteboard, byteLimit: Limits.maxHTMLBytes) else {
                continue
            }

            let start = Date()
            guard let attributed = attributedString(from: data, documentType: .html),
                  Date().timeIntervalSince(start) <= Limits.captureBudget,
                  let text = normalizedPlainText(from: attributed)
            else {
                continue
            }
            return text
        }
        return nil
    }

    private func boundedData(
        for pasteboardType: NSPasteboard.PasteboardType,
        from pasteboard: NSPasteboard,
        byteLimit: Int
    ) -> Data? {
        if let data = pasteboard.data(forType: pasteboardType),
           !data.isEmpty,
           data.count <= byteLimit {
            return data
        }

        guard let text = pasteboard.string(forType: pasteboardType),
              let data = text.data(using: .utf8),
              !data.isEmpty,
              data.count <= byteLimit
        else {
            return nil
        }
        return data
    }

    private func attributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
    }

    private func flatRTFData(from attributed: NSAttributedString) -> Data? {
        guard attributed.length > 0 else { return nil }
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private func normalizedPlainText(from attributed: NSAttributedString) -> String? {
        normalizedPlainText(from: attributed.string)
    }

    private func normalizedPlainText(from string: String?) -> String? {
        let text = string?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        return text.utf8.count <= Limits.maxStoredPlainTextBytes
            ? text
            : String(decoding: text.utf8.prefix(Limits.maxStoredPlainTextBytes), as: UTF8.self)
    }

    private func richTextMatchesPlainText(_ richText: ClipboardCapturedRichText, _ plainText: String) -> Bool {
        normalizedPlainText(from: richText.text) == plainText
    }

    private func plainTextAppearsAuthoritative(in pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        guard !types.isEmpty else {
            return pasteboard.string(forType: .string) != nil
        }

        let firstPlainIndex = types.firstIndex(where: isPlainTextType)
        guard let firstPlainIndex else {
            return false
        }

        guard let firstRichIndex = types.firstIndex(where: isRichTextType) else {
            return true
        }

        return firstPlainIndex < firstRichIndex
    }

    private func isPlainTextType(_ type: NSPasteboard.PasteboardType) -> Bool {
        let rawValue = type.rawValue
        return rawValue == NSPasteboard.PasteboardType.string.rawValue
            || rawValue == "public.utf8-plain-text"
            || rawValue == "NSStringPboardType"
    }

    private func isRichTextType(_ type: NSPasteboard.PasteboardType) -> Bool {
        let rawValue = type.rawValue
        return rawValue == NSPasteboard.PasteboardType.rtf.rawValue
            || rawValue == NSPasteboard.PasteboardType.rtfd.rawValue
            || rawValue == NSPasteboard.PasteboardType.html.rawValue
            || rawValue == "public.rtf"
            || rawValue == "com.apple.rtfd"
            || rawValue == "public.html"
    }

    private func hasRichEvidence(
        in attributed: NSAttributedString,
        sourceData: Data?,
        htmlBacked: Bool
    ) -> Bool {
        var evidence = Set<String>()
        if let sourceData,
           let source = String(data: sourceData, encoding: .ascii)?.lowercased() {
            if source.range(of: #"\\(b|i)\b"#, options: .regularExpression) != nil {
                evidence.insert("fontTrait")
            }
            if source.range(of: #"\\(ul|strike)\b"#, options: .regularExpression) != nil {
                evidence.insert("decoration")
            }
            if source.range(of: #"\\(cf\d+|highlight\d+)\b"#, options: .regularExpression) != nil {
                evidence.insert("color")
            }
        }

        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { attributes, _, stop in
            if attributes[.link] != nil {
                evidence.insert("link")
            }
            if attributes[.foregroundColor] != nil || attributes[.backgroundColor] != nil {
                evidence.insert("color")
            }
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                evidence.insert("decoration")
            }
            if let strikethrough = attributes[.strikethroughStyle] as? Int, strikethrough != 0 {
                evidence.insert("decoration")
            }
            if let font = attributes[.font] as? NSFont,
               font.fontDescriptor.symbolicTraits.intersection([.bold, .italic]).isEmpty == false {
                evidence.insert("fontTrait")
            }
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle,
               !htmlBacked,
               style.alignment != .natural && style.alignment != .left {
                evidence.insert("paragraph")
            }
            if evidenceScore(evidence) >= (htmlBacked ? 2 : 1) {
                stop.pointee = true
            }
        }
        return evidenceScore(evidence) >= (htmlBacked ? 2 : 1)
    }

    private func evidenceScore(_ evidence: Set<String>) -> Int {
        evidence.reduce(0) { score, key in
            score + (key == "link" || key == "decoration" ? 2 : 1)
        }
    }

    private func hasStrongRichHTMLEvidence(_ html: String) -> Bool {
        let lower = html.lowercased()
        var score = 0
        if lower.range(of: #"<\s*(b|strong)\b"#, options: .regularExpression) != nil {
            score += 1
        }
        if lower.range(of: #"<\s*(i|em)\b"#, options: .regularExpression) != nil {
            score += 1
        }
        if lower.range(of: #"<\s*u\b"#, options: .regularExpression) != nil {
            score += 2
        }
        if lower.range(of: #"<\s*a\b"#, options: .regularExpression) != nil {
            score += 2
        }
        if score == 0, isCodePresentationOnlyHTML(lower) {
            return false
        }
        if lower.range(of: richHTMLStylePattern, options: .regularExpression) != nil {
            score += 2
        }
        return score >= 2
    }

    private func isCodePresentationOnlyHTML(_ lowercasedHTML: String) -> Bool {
        let hasCodeStructure = lowercasedHTML.range(
            of: #"<\s*(code|pre)\b|class\s*=\s*["'][^"']*(code|highlight|hljs|language-|markdown|prose)"#,
            options: .regularExpression
        ) != nil
        guard hasCodeStructure else {
            return false
        }

        return lowercasedHTML.range(
            of: #"<\s*(b|strong|i|em|u|a)\b|font-weight\s*:\s*(bold|[6-9]00)|font-style\s*:\s*italic|text-decoration\s*:\s*(underline|line-through)"#,
            options: .regularExpression
        ) == nil
    }

    private var richHTMLStylePattern: String {
        [
            #"style\s*=\s*["'][^"']*"#,
            #"("#,
            #"font-weight\s*:\s*(bold|[6-9]00)"#,
            #"|font-style\s*:\s*italic"#,
            #"|text-decoration\s*:\s*(underline|line-through)"#,
            #"|background(?:-color)?\s*:"#,
            #"|(?<!background-)color\s*:"#,
            #"|font-size\s*:"#,
            #"|font-family\s*:"#,
            #"|text-align\s*:\s*(center|right|justify)"#,
            #")"#
        ].joined()
    }

    private func htmlString(from pasteboard: NSPasteboard) -> String? {
        for pasteboardType in [NSPasteboard.PasteboardType.html, NSPasteboard.PasteboardType("public.html")] {
            if let data = boundedData(for: pasteboardType, from: pasteboard, byteLimit: Limits.maxHTMLBytes),
               let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                return html
            }
        }
        return nil
    }

    private func isImageOnlyHTMLMetadata(_ html: String) -> Bool {
        let lower = html.lowercased()
        let containsImage = lower.range(of: #"<\s*img\b"#, options: .regularExpression) != nil
        guard containsImage else { return false }

        let withoutScripts = lower.replacingOccurrences(
            of: #"<(script|style)\b[^>]*>.*?</\1>"#,
            with: "",
            options: [.regularExpression]
        )
        let withoutTags = withoutScripts.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: [.regularExpression]
        )
        let decoded = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nonWhitespaceCount = decoded.filter { !$0.isWhitespace }.count
        return nonWhitespaceCount < 8
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
    var onTextCaptured: ((String, ClipboardCapturedRichText?, Int) -> Void)?
    var onRichTextCaptured: ((ClipboardCapturedRichText, Int) -> Void)?
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

        case .richText(let richText):
            onRichTextCaptured?(richText, changeCount)

        case .image(let image):
            onImageCaptured?(image, changeCount)

        case .text(let text, let displayRichText):
            onTextCaptured?(text, displayRichText, changeCount)

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
