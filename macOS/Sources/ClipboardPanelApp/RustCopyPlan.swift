import ClipboardCoreBridge
import Foundation
import UniformTypeIdentifiers

public enum ClipboardCopyComposition: String, Decodable, Sendable {
    case single
    case fileURLs = "file_urls"
    case separateItems = "separate_items"
    case compositeText = "composite_text"
    case joinedPlainText = "joined_plain_text"
}

public struct ClipboardCopySkippedItem: Equatable, Decodable, Sendable {
    public let requestIndex: Int
    public let itemID: String
    public let reason: String
    private enum CodingKeys: String, CodingKey {
        case requestIndex = "request_index", itemID = "item_id", reason
    }
}

public struct ClipboardCopyPlan: Equatable, Sendable {
    public let payload: ClipboardPastePayload
    public let composition: ClipboardCopyComposition
    public let includedIDs: [String]
    public let skipped: [ClipboardCopySkippedItem]
    private let managedAssetURLs: Set<URL>
    private let appSupportDirectory: URL?

    fileprivate init(payload: ClipboardPastePayload, composition: ClipboardCopyComposition,
        includedIDs: [String], skipped: [ClipboardCopySkippedItem], managedAssetURLs: Set<URL>, appSupportDirectory: URL?) {
        self.payload = payload
        self.composition = composition
        self.includedIDs = includedIDs
        self.skipped = skipped
        self.managedAssetURLs = managedAssetURLs
        self.appSupportDirectory = appSupportDirectory
    }

    /// Revalidate transient filesystem facts before encoding. A lost RTF keeps
    /// its explicit full-text fallback; other lost assets fail the entire write.
    /// This does not promise an atomic filesystem snapshot or a no-follow open.
    public func payloadForWriting(fileManager: FileManager = .default) -> ClipboardPastePayload {
        func available(_ url: URL) -> Bool {
            if managedAssetURLs.contains(url) {
                guard let appSupportDirectory else { return false }
                return RustCopyPlan.managedAssetURL(path: url.path, root: appSupportDirectory, fileManager: fileManager) == url
            }
            return fileManager.fileExists(atPath: url.path)
        }
        switch payload {
        case .richText(let rtf, let text): return .richText(rtfURL: rtf.flatMap { available($0) ? $0 : nil }, fallbackText: text)
        case .imageFile(let url): return available(url) ? payload : .unsupported(reason: "missing_image_asset")
        case .fileURLs(let urls): return urls.allSatisfy(available) ? payload : .unsupported(reason: "missing_file_url")
        case .pasteboardItems(let items):
            var validated: [ClipboardPasteboardItemPayload] = []
            for item in items {
                var representations: [ClipboardPasteboardItemRepresentation] = []
                for representation in item.representations {
                    switch representation {
                    case .rtf(let url): if available(url) { representations.append(representation) }
                    case .imageFile(let url):
                        guard available(url) else { return .unsupported(reason: "missing_image_asset") }
                        representations.append(representation)
                    case .fileURL(let url):
                        guard available(url) else { return .unsupported(reason: "missing_file_url") }
                        representations.append(representation)
                    case .string: representations.append(representation)
                    }
                }
                validated.append(ClipboardPasteboardItemPayload(sourceItemIDs: item.sourceItemIDs, representations: representations))
            }
            return .pasteboardItems(validated)
        case .text, .unsupported: return payload
        }
    }
}

/// File probing, request encoding and the pure Rust planner run outside the UI
/// executor and outside the database worker/session critical section.
public actor ClipboardCopyPlanWorker {
    public init() {}
    public func plan(items: [RustClipboardItemSummary], mode: ClipboardCopyMode, appSupportDirectory: URL) -> Result<ClipboardCopyPlan, RustCoreError> {
        RustCopyPlan.plan(items: items, mode: mode, appSupportDirectory: appSupportDirectory)
    }
}

public enum RustCopyPlan {
    public static func plan(items: [RustClipboardItemSummary], mode: ClipboardCopyMode,
        appSupportDirectory: URL?, fileManager: FileManager = .default) -> Result<ClipboardCopyPlan, RustCoreError> {
        guard items.allSatisfy(\.isContentComplete) else { return .failure(error("content_not_loaded")) }
        var urls: [AssetRef: URL] = [:]
        let facts = items.enumerated().map { index, item -> FileFacts in
            var asset: AssetRef?
            if let root = appSupportDirectory, ["image", "rich_text"].contains(item.itemType),
               let path = item.payloadAssetPath,
               let url = managedAssetURL(path: path, root: root, fileManager: fileManager) {
                let reference = AssetRef(kind: "managed_asset", key: "\(index):payload")
                urls[reference] = url
                asset = reference
            }
            let candidates: [Candidate]
            if item.itemType == "file", let root = appSupportDirectory {
                candidates = fileURLs(item: item, root: root, fileManager: fileManager).enumerated().map { fileIndex, url in
                    let reference = AssetRef(kind: "external_file", key: "\(index):file:\(fileIndex)")
                    urls[reference] = url
                    return Candidate(asset: reference, isImage: isImage(url))
                }
            } else { candidates = [] }
            return FileFacts(itemID: item.id, contentHash: item.contentHash, payloadAsset: asset, fileCandidates: candidates)
        }
        let request = Request(orderedIDs: items.map(\.id), mode: mode.wireValue, capabilities: "mac_os_v1",
            items: items.map(InputItem.init), fileFacts: facts)
        let encoded: String
        do { encoded = String(decoding: try JSONEncoder().encode(request), as: UTF8.self) }
        catch { return .failure(Self.error("bridge_encode_failed")) }
        let response = plan_copy_json(encoded)
        guard response.ok else {
            return .failure(RustCoreError(code: response.error_code.toString(), messageKey: response.message_key.toString(), recoverable: true, message: response.message_key.toString()))
        }
        do {
            let plan = try JSONDecoder().decode(WirePlan.self, from: Data(response.result_json.toString().utf8))
            if plan.status == "unsupported" {
                guard let reason = plan.reason else { throw MappingError.invalidResponse }
                return .success(ClipboardCopyPlan(payload: .unsupported(reason: reason), composition: .separateItems,
                    includedIDs: [], skipped: plan.skipped, managedAssetURLs: [], appSupportDirectory: appSupportDirectory))
            }
            guard plan.status == "ready", let composition = plan.composition,
                  let plannedItems = plan.items, let includedIDs = plan.includedIDs else { throw MappingError.invalidResponse }
            let resolved = try plannedItems.map { item in
                ClipboardPasteboardItemPayload(sourceItemIDs: item.sourceItemIDs, representations: try item.representations.map { representation in
                    if representation.kind == "text", let text = representation.text { return .string(text) }
                    guard let asset = representation.asset, let url = urls[asset] else { throw MappingError.invalidReference }
                    switch representation.kind {
                    case "rtf": return .rtf(url)
                    case "image": return .imageFile(url)
                    case "file": return .fileURL(url)
                    default: throw MappingError.invalidResponse
                    }
                })
            }
            let payload: ClipboardPastePayload
            switch composition {
            case .joinedPlainText:
                payload = .pasteboardItems([ClipboardPasteboardItemPayload(sourceItemIDs: includedIDs,
                    representations: [.string(resolved.flatMap(\.representations).compactMap { if case .string(let text) = $0 { text } else { nil } }.joined(separator: "\n"))])])
            case .fileURLs:
                payload = .fileURLs(resolved.flatMap(\.representations).compactMap { if case .fileURL(let url) = $0 { url } else { nil } })
            case .single:
                guard resolved.count == 1, let item = resolved.first else { throw MappingError.invalidResponse }
                let text = item.representations.compactMap { if case .string(let text) = $0 { text } else { nil } }.first
                if items.first?.itemType == "rich_text", mode == .original, let text {
                    let rtf = item.representations.compactMap { if case .rtf(let url) = $0 { url } else { nil } }.first
                    payload = .richText(rtfURL: rtf, fallbackText: text)
                } else if let text { payload = .text(text) }
                else if item.representations.count == 1, case .imageFile(let url) = item.representations[0] { payload = .imageFile(url) }
                else { throw MappingError.invalidResponse }
            case .separateItems, .compositeText: payload = .pasteboardItems(resolved)
            }
            return .success(ClipboardCopyPlan(payload: payload, composition: composition, includedIDs: includedIDs,
                skipped: plan.skipped, managedAssetURLs: Set(urls.filter { $0.key.kind == "managed_asset" }.map(\.value)), appSupportDirectory: appSupportDirectory))
        } catch { return .failure(Self.error("bridge_decode_failed")) }
    }

    /// Legacy planner entry points now use the same pure policy. Tests can still
    /// compare the old payload shape while production consumes included IDs too.
    static func payload(items: [RustClipboardItemSummary], mode: ClipboardCopyMode,
        appSupportDirectory: URL?, fileManager: FileManager = .default) -> ClipboardPastePayload {
        switch plan(items: items, mode: mode, appSupportDirectory: appSupportDirectory, fileManager: fileManager) {
        case .success(let plan): return plan.payload
        case .failure(let error): return .unsupported(reason: error.code)
        }
    }

    static func managedAssetURL(path: String, root: URL, fileManager: FileManager) -> URL? {
        let originalCandidate = ClipboardAssetPathResolver.resolvedURL(for: path, appSupportDirectory: root)
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = originalCandidate.standardizedFileURL
        let canonical = candidate.resolvingSymlinksInPath()
        guard canonical.path.hasPrefix(root.path + "/"),
              fileManager.fileExists(atPath: canonical.path),
              (try? canonical.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        // Resolve aliases in the support-root ancestry (e.g. /var -> /private/var),
        // but reject symlink components inside the owned resource tree.
        let lexicalRoot = candidate.path.hasPrefix(root.path + "/") ? root : rootAlias(for: root, candidate: candidate)
        guard let lexicalRoot, candidate.path.hasPrefix(lexicalRoot.path + "/") else { return nil }
        var current = lexicalRoot
        for component in candidate.path.dropFirst(lexicalRoot.path.count + 1).split(separator: "/") {
            current.appendPathComponent(String(component))
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return nil }
        }
        // Canonicalization validates ownership; retain the native URL spelling.
        return originalCandidate
    }

    private static func rootAlias(for root: URL, candidate: URL) -> URL? {
        var ancestor = candidate.deletingLastPathComponent()
        while ancestor.path != "/" {
            if ancestor.resolvingSymlinksInPath() == root { return ancestor }
            ancestor.deleteLastPathComponent()
        }
        return nil
    }

    private static func fileURLs(item: RustClipboardItemSummary, root: URL, fileManager: FileManager) -> [URL] {
        let metadata = ClipboardFilePreviewResolver.fileURLsFromMetadata(item.fileItems, appSupportDirectory: root, fileManager: fileManager)
        if !metadata.isEmpty { return metadata }
        let paths = ClipboardFilePreviewResolver.pathStrings(fromPrimaryText: item.primaryText)
        if !paths.isEmpty { return ClipboardFilePreviewResolver.fileURLsFromPrimaryText(item.primaryText, appSupportDirectory: root, fileManager: fileManager) }
        struct Snapshot: Decodable { let paths: [String] }
        for path in [item.payloadAssetPath, item.previewAssetPath].compactMap({ $0 }) {
            guard let url = managedAssetURL(path: path, root: root, fileManager: fileManager),
                  let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), !snapshot.paths.isEmpty else { continue }
            // Snapshot paths are captured external files; they are not confined to root.
            var seen = Set<String>()
            return snapshot.paths.compactMap { path in
                let url = ClipboardAssetPathResolver.resolvedURL(for: path, appSupportDirectory: root).standardizedFileURL
                return fileManager.fileExists(atPath: url.path) && seen.insert(url.path).inserted ? url : nil
            }
        }
        return []
    }

    private static func isImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return UTType(filenameExtension: ext)?.conforms(to: .image) == true || imageExtensions.contains(ext)
    }
    private static let imageExtensions: Set<String> = ["apng", "avif", "bmp", "gif", "heic", "heif", "icns", "ico", "jpeg", "jpg", "jxl", "png", "psd", "raw", "svg", "tif", "tiff", "webp"]
    private static func error(_ code: String) -> RustCoreError { RustCoreError(code: code, messageKey: "clipboard.error.\(code)", recoverable: true, message: code) }
    private enum MappingError: Error { case invalidResponse, invalidReference }
    private struct AssetRef: Codable, Hashable { let kind: String; let key: String }
    private struct Candidate: Encodable { let asset: AssetRef; let isImage: Bool; enum CodingKeys: String, CodingKey { case asset, isImage = "is_image" } }
    private struct FileFacts: Encodable {
        let itemID: String; let contentHash: String; let payloadAsset: AssetRef?; let fileCandidates: [Candidate]
        enum CodingKeys: String, CodingKey { case itemID = "item_id", contentHash = "content_hash", payloadAsset = "payload_asset", fileCandidates = "file_candidates" }
    }
    private struct InputItem: Encodable {
        let itemID: String; let contentHash: String; let itemType: String; let primaryText: String?; let summary: String
        let payloadState: String; let canonicalURL: String?; let firstFilePath: String?
        init(_ item: RustClipboardItemSummary) {
            itemID = item.id; contentHash = item.contentHash; itemType = item.itemType; primaryText = item.primaryText; summary = item.summary
            payloadState = item.payloadState; canonicalURL = item.linkMetadata?.canonicalURL; firstFilePath = item.fileItems.first?.path
        }
        enum CodingKeys: String, CodingKey { case itemID = "item_id", contentHash = "content_hash", itemType = "item_type", primaryText = "primary_text", summary, payloadState = "payload_state", canonicalURL = "canonical_url", firstFilePath = "first_file_path" }
    }
    private struct Request: Encodable {
        let orderedIDs: [String]; let mode: String; let capabilities: String; let items: [InputItem]; let fileFacts: [FileFacts]
        enum CodingKeys: String, CodingKey { case orderedIDs = "ordered_ids", mode, capabilities, items, fileFacts = "file_facts" }
    }
    private struct WireRepresentation: Decodable { let kind: String; let text: String?; let asset: AssetRef? }
    private struct WireItem: Decodable {
        let sourceItemIDs: [String]; let representations: [WireRepresentation]
        enum CodingKeys: String, CodingKey { case sourceItemIDs = "source_item_ids", representations }
    }
    private struct WirePlan: Decodable {
        let status: String; let composition: ClipboardCopyComposition?; let items: [WireItem]?; let includedIDs: [String]?; let skipped: [ClipboardCopySkippedItem]; let reason: String?
        enum CodingKeys: String, CodingKey { case status, composition, items, includedIDs = "included_ids", skipped, reason }
    }
}

private extension ClipboardCopyMode {
    var wireValue: String {
        switch self { case .original: "original"; case .preferPlainText: "prefer_plain_text"; case .explicitPlainText: "explicit_plain_text" }
    }
}
