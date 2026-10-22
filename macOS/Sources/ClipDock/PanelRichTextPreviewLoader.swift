import AppKit

/// Immutable, independently copied text. The worker never mutates the string or its
/// attributes after handing it to the main actor; attachment previews are not cached.
struct LoadedRichTextPreview: @unchecked Sendable {
    let attributedString: NSAttributedString
}

/// A synchronous actor operation keeps expensive RTF import serial. Views, text
/// layout, theme adaptation and HTML import never run on this worker.
actor PanelRichTextPreviewLoader {
    static let shared = PanelRichTextPreviewLoader()
    static let maximumInputBytes = 5 * 1024 * 1024
    static let maximumPreviewUTF16Length = 500

    struct Statistics: Sendable {
        let parseCount: Int
        let cacheEntryCount: Int
        let cachedUTF16Length: Int
        let lastParseWasOnMainThread: Bool
    }

    private struct Key: Hashable {
        let path: String
        let length: Int
    }

    private struct Fingerprint: Equatable {
        let size: UInt64
        let modified: Date
        let fileNumber: UInt64
        let volumeNumber: UInt64
    }

    private struct CachedPreview {
        let fingerprint: Fingerprint?
        let value: LoadedRichTextPreview?
        let retryAfter: Date?
        let cost: Int
    }

    private let maximumEntries: Int
    private let maximumCost: Int
    private var cache: [Key: CachedPreview] = [:]
    private var accessOrder: [Key] = []
    private var cachedCost = 0
    private var parseCount = 0
    private var lastParseWasOnMainThread = false

    init(maximumEntries: Int = 64, maximumCost: Int = 4 * 1024 * 1024) {
        self.maximumEntries = max(0, maximumEntries)
        self.maximumCost = max(0, maximumCost)
    }

    func load(url: URL, maximumUTF16Length: Int) throws -> LoadedRichTextPreview? {
        try Task.checkCancellation()
        let length = min(Self.maximumPreviewUTF16Length, max(0, maximumUTF16Length))
        guard length > 0 else { return nil }
        let key = Key(path: url.standardizedFileURL.path, length: length)
        let fingerprint = Self.fingerprint(of: url)
        if let cached = cache[key], cached.fingerprint == fingerprint,
           cached.retryAfter.map({ Date() < $0 }) ?? true {
            touch(key)
            return cached.value
        }
        remove(key)

        guard let fingerprint, fingerprint.size > 0,
              fingerprint.size <= Self.maximumInputBytes
        else {
            store(nil, fingerprint: fingerprint, for: key)
            return nil
        }

        let data: Data
        do {
            data = try Self.readBoundedData(from: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            store(nil, fingerprint: fingerprint, for: key)
            return nil
        }
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= Self.maximumInputBytes else {
            store(nil, fingerprint: fingerprint, for: key)
            return nil
        }

        parseCount += 1
        lastParseWasOnMainThread = Thread.isMainThread
        let preview = autoreleasepool {
            guard let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else { return nil as LoadedRichTextPreview? }
            return Self.boundedPreview(attributed, maximumUTF16Length: length)
        }
        try Task.checkCancellation()
        // Do not label bytes read during a replacement with the newer file version.
        guard Self.fingerprint(of: url) == fingerprint else { return nil }
        store(preview, fingerprint: fingerprint, for: key)
        return preview
    }

    func statistics() -> Statistics {
        Statistics(
            parseCount: parseCount,
            cacheEntryCount: cache.count,
            cachedUTF16Length: cache.values.reduce(0) { $0 + ($1.value?.attributedString.length ?? 0) },
            lastParseWasOnMainThread: lastParseWasOnMainThread
        )
    }

    private nonisolated static func fingerprint(of url: URL) -> Fingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return Fingerprint(
            size: size.uint64Value,
            modified: modified,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            volumeNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }

    private nonisolated static func readBoundedData(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumInputBytes {
            try Task.checkCancellation()
            let remaining = maximumInputBytes + 1 - data.count
            let chunk = try handle.read(upToCount: min(64 * 1024, remaining)) ?? Data()
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }

    nonisolated static func boundedPreview(
        _ attributed: NSAttributedString,
        maximumUTF16Length: Int
    ) -> LoadedRichTextPreview? {
        let text = attributed.string
        let limit = min(maximumPreviewUTF16Length, max(0, maximumUTF16Length))
        var length = 0
        for character in text {
            let nextLength = length + character.utf16.count
            guard nextLength <= limit else { break }
            length = nextLength
        }
        guard length > 0 else { return nil }
        let range = NSRange(location: 0, length: length)
        // Copy only the prefix and its attributes, without retaining the full input
        // or re-encoding as RTF (which would discard attachment attributes).
        let prefix = NSMutableAttributedString(string: (text as NSString).substring(with: range))
        attributed.enumerateAttributes(in: range) { attributes, range, _ in
            var copiedAttributes = attributes
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
                copiedAttributes[.paragraphStyle] = paragraph.copy()
            }
            prefix.setAttributes(copiedAttributes, range: range)
        }
        return LoadedRichTextPreview(attributedString: NSAttributedString(attributedString: prefix))
    }

    private func store(_ value: LoadedRichTextPreview?, fingerprint: Fingerprint?, for key: Key) {
        var containsAttachment = false
        var runCount = 0
        if let attributed = value?.attributedString {
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, _, _ in
                containsAttachment = containsAttachment || attributes[.attachment] != nil
                runCount += 1
            }
        }
        // Attachment sizes can be much larger than their compressed input. Keep
        // those previews owned by visible cells instead of the shared cache.
        guard !containsAttachment else { return }
        let cost = 256 + (value?.attributedString.length ?? 0) * 16 + runCount * 128
        guard maximumEntries > 0, cost <= maximumCost else { return }
        remove(key)
        cache[key] = CachedPreview(
            fingerprint: fingerprint,
            value: value,
            retryAfter: value == nil ? Date().addingTimeInterval(2) : nil,
            cost: cost
        )
        cachedCost += cost
        touch(key)
        while cache.count > maximumEntries || cachedCost > maximumCost {
            guard let oldest = accessOrder.first else { break }
            remove(oldest)
        }
    }

    private func touch(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func remove(_ key: Key) {
        if let cached = cache.removeValue(forKey: key) {
            cachedCost -= cached.cost
        }
        accessOrder.removeAll { $0 == key }
    }
}
