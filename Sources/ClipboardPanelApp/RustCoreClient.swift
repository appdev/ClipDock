import ClipboardCoreBridge
import Foundation

public struct RustCoreOpenResult: Equatable, Sendable {
    public let databasePath: String
    public let schemaVersion: Int64
    public let itemCount: Int64
    public let items: [RustClipboardItemSummary]
}

public struct RustMaintenanceResult: Equatable, Sendable {
    public let purgedItemCount: Int64
    public let deletedAssetRowCount: Int64
    public let deletedAssetFileCount: Int64
    public let deletedOrphanFileCount: Int64
    public let reclaimedBytes: Int64

    public init(
        purgedItemCount: Int64,
        deletedAssetRowCount: Int64,
        deletedAssetFileCount: Int64,
        deletedOrphanFileCount: Int64,
        reclaimedBytes: Int64
    ) {
        self.purgedItemCount = purgedItemCount
        self.deletedAssetRowCount = deletedAssetRowCount
        self.deletedAssetFileCount = deletedAssetFileCount
        self.deletedOrphanFileCount = deletedOrphanFileCount
        self.reclaimedBytes = reclaimedBytes
    }
}

public struct RustCoreListResult: Equatable, Sendable {
    public let items: [RustClipboardItemSummary]
    public let totalCount: Int64
    public let hasMore: Bool

    public init(items: [RustClipboardItemSummary], totalCount: Int64, hasMore: Bool) {
        self.items = items
        self.totalCount = totalCount
        self.hasMore = hasMore
    }
}

public struct RustCoreSourceAppsResult: Equatable, Sendable {
    public let apps: [RustSourceAppSummary]
    public let totalCount: Int64
    public let hasMore: Bool
}

public struct RustItemManagementResult: Equatable, Sendable {
    public let affectedCount: Int64
}

public struct RustPreferencesResult: Equatable, Sendable {
    public let schemaVersion: Int64
    public let preferences: RustPreferencesDocument
}

public struct RustPreferencesDocument: Equatable, Codable, Sendable {
    public var general: RustGeneralPreferences
    public var history: RustHistoryPreferences
    public var appearance: RustAppearancePreferences
    public var ignoreList: RustIgnoreListPreferences

    public init(
        general: RustGeneralPreferences = RustGeneralPreferences(),
        history: RustHistoryPreferences = RustHistoryPreferences(),
        appearance: RustAppearancePreferences = RustAppearancePreferences(),
        ignoreList: RustIgnoreListPreferences = RustIgnoreListPreferences()
    ) {
        self.general = general
        self.history = history
        self.appearance = appearance
        self.ignoreList = ignoreList
    }

    private enum CodingKeys: String, CodingKey {
        case general
        case history
        case appearance
        case ignoreList = "ignore_list"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.general = try container.decodeIfPresent(RustGeneralPreferences.self, forKey: .general) ?? RustGeneralPreferences()
        self.history = try container.decodeIfPresent(RustHistoryPreferences.self, forKey: .history) ?? RustHistoryPreferences()
        self.appearance = try container.decodeIfPresent(RustAppearancePreferences.self, forKey: .appearance) ?? RustAppearancePreferences()
        self.ignoreList = try container.decodeIfPresent(RustIgnoreListPreferences.self, forKey: .ignoreList) ?? RustIgnoreListPreferences()
    }
}

public struct RustGeneralPreferences: Equatable, Codable, Sendable {
    public var launchAtLogin: Bool
    public var showMenuBarItem: Bool
    public var defaultPanelHeight: Int64

    public init(
        launchAtLogin: Bool = false,
        showMenuBarItem: Bool = true,
        defaultPanelHeight: Int64 = 320
    ) {
        self.launchAtLogin = launchAtLogin
        self.showMenuBarItem = showMenuBarItem
        self.defaultPanelHeight = defaultPanelHeight
    }

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin = "launch_at_login"
        case showMenuBarItem = "show_menu_bar_item"
        case defaultPanelHeight = "default_panel_height"
    }
}

public struct RustHistoryPreferences: Equatable, Codable, Sendable {
    public var maxItems: Int64
    public var retentionDays: Int64
    public var recordImages: Bool
    public var recordFiles: Bool

    public init(
        maxItems: Int64 = 500,
        retentionDays: Int64 = 30,
        recordImages: Bool = true,
        recordFiles: Bool = false
    ) {
        self.maxItems = maxItems
        self.retentionDays = retentionDays
        self.recordImages = recordImages
        self.recordFiles = recordFiles
    }

    private enum CodingKeys: String, CodingKey {
        case maxItems = "max_items"
        case retentionDays = "retention_days"
        case recordImages = "record_images"
        case recordFiles = "record_files"
    }
}

public struct RustAppearancePreferences: Equatable, Codable, Sendable {
    public var mode: String
    public var itemDensity: String
    public var previewPopoverEnabled: Bool

    public init(
        mode: String = "system",
        itemDensity: String = "standard",
        previewPopoverEnabled: Bool = true
    ) {
        self.mode = mode
        self.itemDensity = itemDensity
        self.previewPopoverEnabled = previewPopoverEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case itemDensity = "item_density"
        case previewPopoverEnabled = "preview_popover_enabled"
    }
}

public struct RustIgnoreListPreferences: Equatable, Codable, Sendable {
    public var ignoredAppIdentifiers: [String]
    public var windowTitleKeywords: [String]
    public var skipUnknownSource: Bool

    public init(
        ignoredAppIdentifiers: [String] = [],
        windowTitleKeywords: [String] = [],
        skipUnknownSource: Bool = false
    ) {
        self.ignoredAppIdentifiers = ignoredAppIdentifiers
        self.windowTitleKeywords = windowTitleKeywords
        self.skipUnknownSource = skipUnknownSource
    }

    private enum CodingKeys: String, CodingKey {
        case ignoredAppIdentifiers = "ignored_app_identifiers"
        case windowTitleKeywords = "window_title_keywords"
        case skipUnknownSource = "skip_unknown_source"
    }
}

public struct RustClipboardItemSummary: Equatable, Decodable, Sendable {
    public let id: String
    public let itemType: String
    public let summary: String
    public let primaryText: String?
    public let contentHash: String
    public let sourceAppId: String?
    public let sourceAppName: String?
    public let sourceAppIconPath: String?
    public let previewAssetPath: String?
    public let payloadAssetPath: String?
    public let sourceConfidence: String
    public let firstCopiedAtMs: Int64
    public let lastCopiedAtMs: Int64
    public let copyCount: Int64
    public let isPinned: Bool
    public let sizeBytes: Int64
    public let previewState: String

    public init(
        id: String,
        itemType: String,
        summary: String,
        primaryText: String?,
        contentHash: String,
        sourceAppId: String?,
        sourceAppName: String?,
        sourceAppIconPath: String?,
        previewAssetPath: String?,
        payloadAssetPath: String?,
        sourceConfidence: String,
        firstCopiedAtMs: Int64,
        lastCopiedAtMs: Int64,
        copyCount: Int64,
        isPinned: Bool,
        sizeBytes: Int64,
        previewState: String
    ) {
        self.id = id
        self.itemType = itemType
        self.summary = summary
        self.primaryText = primaryText
        self.contentHash = contentHash
        self.sourceAppId = sourceAppId
        self.sourceAppName = sourceAppName
        self.sourceAppIconPath = sourceAppIconPath
        self.previewAssetPath = previewAssetPath
        self.payloadAssetPath = payloadAssetPath
        self.sourceConfidence = sourceConfidence
        self.firstCopiedAtMs = firstCopiedAtMs
        self.lastCopiedAtMs = lastCopiedAtMs
        self.copyCount = copyCount
        self.isPinned = isPinned
        self.sizeBytes = sizeBytes
        self.previewState = previewState
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case itemType = "item_type"
        case summary
        case primaryText = "primary_text"
        case contentHash = "content_hash"
        case sourceAppId = "source_app_id"
        case sourceAppName = "source_app_name"
        case sourceAppIconPath = "source_app_icon_path"
        case previewAssetPath = "preview_asset_path"
        case payloadAssetPath = "payload_asset_path"
        case sourceConfidence = "source_confidence"
        case firstCopiedAtMs = "first_copied_at_ms"
        case lastCopiedAtMs = "last_copied_at_ms"
        case copyCount = "copy_count"
        case isPinned = "is_pinned"
        case sizeBytes = "size_bytes"
        case previewState = "preview_state"
    }
}

public struct RustSourceAppSummary: Equatable, Decodable, Sendable {
    public let id: String
    public let bundleId: String?
    public let name: String
    public let iconPath: String?
    public let itemCount: Int64
    public let lastCopiedAtMs: Int64

    private enum CodingKeys: String, CodingKey {
        case id
        case bundleId = "bundle_id"
        case name
        case iconPath = "icon_path"
        case itemCount = "item_count"
        case lastCopiedAtMs = "last_copied_at_ms"
    }
}

public struct RustCaptureTextRequest: Equatable, Sendable {
    public let text: String
    public let sourceBundleId: String?
    public let sourceAppName: String?
    public let sourceBundlePath: String?
    public let sourceIconRelativePath: String?
    public let sourceConfidence: String
    public let pasteboardChangeCount: Int64
    public let selfWriteToken: String?

    public init(
        text: String,
        sourceBundleId: String?,
        sourceAppName: String?,
        sourceBundlePath: String?,
        sourceIconRelativePath: String?,
        sourceConfidence: String,
        pasteboardChangeCount: Int64,
        selfWriteToken: String? = nil
    ) {
        self.text = text
        self.sourceBundleId = sourceBundleId
        self.sourceAppName = sourceAppName
        self.sourceBundlePath = sourceBundlePath
        self.sourceIconRelativePath = sourceIconRelativePath
        self.sourceConfidence = sourceConfidence
        self.pasteboardChangeCount = pasteboardChangeCount
        self.selfWriteToken = selfWriteToken
    }
}

public struct RustCaptureTextResult: Equatable, Sendable {
    public let itemId: String
    public let contentHash: String
    public let copyCount: Int64
    public let inserted: Bool
}

public struct RustCaptureImageRequest: Equatable, Sendable {
    public let payloadRelativePath: String
    public let previewRelativePath: String?
    public let mimeType: String?
    public let width: Int64
    public let height: Int64
    public let byteCount: Int64
    public let sourceBundleId: String?
    public let sourceAppName: String?
    public let sourceBundlePath: String?
    public let sourceIconRelativePath: String?
    public let sourceConfidence: String
    public let pasteboardChangeCount: Int64
    public let selfWriteToken: String?

    public init(
        payloadRelativePath: String,
        previewRelativePath: String?,
        mimeType: String?,
        width: Int64,
        height: Int64,
        byteCount: Int64,
        sourceBundleId: String?,
        sourceAppName: String?,
        sourceBundlePath: String?,
        sourceIconRelativePath: String?,
        sourceConfidence: String,
        pasteboardChangeCount: Int64,
        selfWriteToken: String? = nil
    ) {
        self.payloadRelativePath = payloadRelativePath
        self.previewRelativePath = previewRelativePath
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.sourceBundleId = sourceBundleId
        self.sourceAppName = sourceAppName
        self.sourceBundlePath = sourceBundlePath
        self.sourceIconRelativePath = sourceIconRelativePath
        self.sourceConfidence = sourceConfidence
        self.pasteboardChangeCount = pasteboardChangeCount
        self.selfWriteToken = selfWriteToken
    }
}

public typealias RustCaptureImageResult = RustCaptureTextResult

public struct RustCaptureFilesRequest: Equatable, Sendable {
    public let filePaths: [String]
    public let snapshotRelativePath: String?
    public let snapshotByteCount: Int64
    public let sourceBundleId: String?
    public let sourceAppName: String?
    public let sourceBundlePath: String?
    public let sourceIconRelativePath: String?
    public let sourceConfidence: String
    public let pasteboardChangeCount: Int64
    public let selfWriteToken: String?

    public init(
        filePaths: [String],
        snapshotRelativePath: String?,
        snapshotByteCount: Int64,
        sourceBundleId: String?,
        sourceAppName: String?,
        sourceBundlePath: String?,
        sourceIconRelativePath: String?,
        sourceConfidence: String,
        pasteboardChangeCount: Int64,
        selfWriteToken: String? = nil
    ) {
        self.filePaths = filePaths
        self.snapshotRelativePath = snapshotRelativePath
        self.snapshotByteCount = snapshotByteCount
        self.sourceBundleId = sourceBundleId
        self.sourceAppName = sourceAppName
        self.sourceBundlePath = sourceBundlePath
        self.sourceIconRelativePath = sourceIconRelativePath
        self.sourceConfidence = sourceConfidence
        self.pasteboardChangeCount = pasteboardChangeCount
        self.selfWriteToken = selfWriteToken
    }
}

public typealias RustCaptureFilesResult = RustCaptureTextResult

public struct RustCoreError: Error, Equatable, Sendable {
    public let code: String
    public let messageKey: String
    public let recoverable: Bool
    public let message: String
}

public final class RustCoreClient: @unchecked Sendable {
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.fileManager = fileManager
        self.decoder = decoder
        self.encoder = encoder
    }

    public func open(appSupportDirectory: URL) -> Result<RustCoreOpenResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(
                RustCoreError(
                    code: "io_failed",
                    messageKey: "clipboard.error.io_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }

        let result = open_core(appSupportDirectory.path)

        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        switch listItems(appSupportDirectory: appSupportDirectory) {
        case .success(let list):
            return .success(
                RustCoreOpenResult(
                    databasePath: result.database_path.toString(),
                    schemaVersion: result.schema_version,
                    itemCount: result.item_count,
                    items: list.items
                )
            )
        case .failure(let error):
            return .failure(error)
        }
    }

    public func runMaintenance(
        appSupportDirectory: URL
    ) -> Result<RustMaintenanceResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(Self.makeIOError(error))
        }

        let result = run_maintenance(appSupportDirectory.path)
        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        return .success(
            RustMaintenanceResult(
                purgedItemCount: result.purged_item_count,
                deletedAssetRowCount: result.deleted_asset_row_count,
                deletedAssetFileCount: result.deleted_asset_file_count,
                deletedOrphanFileCount: result.deleted_orphan_file_count,
                reclaimedBytes: result.reclaimed_bytes
            )
        )
    }

    public func listItems(
        appSupportDirectory: URL,
        limit: Int64 = 50,
        offset: Int64 = 0,
        itemType: String? = nil,
        sourceAppId: String? = nil,
        searchText: String? = nil
    ) -> Result<RustCoreListResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(
                RustCoreError(
                    code: "io_failed",
                    messageKey: "clipboard.error.io_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }

        let result = list_items(
            appSupportDirectory.path,
            limit,
            offset,
            itemType ?? "",
            sourceAppId ?? "",
            searchText ?? ""
        )

        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        do {
            return .success(
                RustCoreListResult(
                    items: try Self.decodeItemsJSON(result.items_json.toString(), decoder: decoder),
                    totalCount: result.total_count,
                    hasMore: result.has_more
                )
            )
        } catch {
            return .failure(
                RustCoreError(
                    code: "bridge_decode_failed",
                    messageKey: "clipboard.error.bridge_decode_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }
    }

    public func listSourceApps(
        appSupportDirectory: URL,
        limit: Int64 = 12,
        offset: Int64 = 0
    ) -> Result<RustCoreSourceAppsResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(Self.makeIOError(error))
        }

        let result = list_source_apps(appSupportDirectory.path, limit, offset)

        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        do {
            return .success(
                RustCoreSourceAppsResult(
                    apps: try Self.decodeSourceAppsJSON(result.apps_json.toString(), decoder: decoder),
                    totalCount: result.total_count,
                    hasMore: result.has_more
                )
            )
        } catch {
            return .failure(
                RustCoreError(
                    code: "bridge_decode_failed",
                    messageKey: "clipboard.error.bridge_decode_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }
    }

    public func setItemPinned(
        appSupportDirectory: URL,
        itemId: String,
        isPinned: Bool
    ) -> Result<RustItemManagementResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(Self.makeIOError(error))
        }

        let result = set_item_pinned(appSupportDirectory.path, itemId, isPinned)
        return decodeItemManagementResult(result)
    }

    public func deleteItem(
        appSupportDirectory: URL,
        itemId: String
    ) -> Result<RustItemManagementResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(Self.makeIOError(error))
        }

        let result = delete_item(appSupportDirectory.path, itemId)
        return decodeItemManagementResult(result)
    }

    public func clearItems(
        appSupportDirectory: URL,
        itemType: String? = nil,
        sourceAppId: String? = nil,
        searchText: String? = nil
    ) -> Result<RustItemManagementResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(Self.makeIOError(error))
        }

        let result = clear_items(
            appSupportDirectory.path,
            itemType ?? "",
            sourceAppId ?? "",
            searchText ?? ""
        )
        return decodeItemManagementResult(result)
    }

    public func getPreferences(
        appSupportDirectory: URL
    ) -> Result<RustPreferencesResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(Self.makeIOError(error))
        }

        let result = get_preferences(appSupportDirectory.path)
        return decodePreferencesResult(result)
    }

    public func updatePreferences(
        appSupportDirectory: URL,
        preferences: RustPreferencesDocument
    ) -> Result<RustPreferencesResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(Self.makeIOError(error))
        }

        do {
            let data = try encoder.encode(preferences)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            let result = update_preferences(appSupportDirectory.path, json)
            return decodePreferencesResult(result)
        } catch {
            return .failure(
                RustCoreError(
                    code: "bridge_encode_failed",
                    messageKey: "clipboard.error.bridge_encode_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }
    }

    private static func decodeItemsJSON(_ value: String, decoder: JSONDecoder) throws -> [RustClipboardItemSummary] {
        guard let data = value.data(using: .utf8) else {
            return []
        }

        return try decoder.decode([RustClipboardItemSummary].self, from: data)
    }

    private static func decodeSourceAppsJSON(_ value: String, decoder: JSONDecoder) throws -> [RustSourceAppSummary] {
        guard let data = value.data(using: .utf8) else {
            return []
        }

        return try decoder.decode([RustSourceAppSummary].self, from: data)
    }

    private func decodePreferencesResult(
        _ result: CorePreferencesResult
    ) -> Result<RustPreferencesResult, RustCoreError> {
        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        do {
            let json = result.preferences_json.toString()
            let data = Data(json.utf8)
            return .success(
                RustPreferencesResult(
                    schemaVersion: result.schema_version,
                    preferences: try decoder.decode(RustPreferencesDocument.self, from: data)
                )
            )
        } catch {
            return .failure(
                RustCoreError(
                    code: "bridge_decode_failed",
                    messageKey: "clipboard.error.bridge_decode_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }
    }

    private static func makeError(code: String, messageKey: String) -> RustCoreError {
        RustCoreError(
            code: code,
            messageKey: messageKey,
            recoverable: true,
            message: messageKey
        )
    }

    private static func makeIOError(_ error: Error) -> RustCoreError {
        RustCoreError(
            code: "io_failed",
            messageKey: "clipboard.error.io_failed",
            recoverable: true,
            message: error.localizedDescription
        )
    }

    private func decodeItemManagementResult(
        _ result: CoreItemManagementResult
    ) -> Result<RustItemManagementResult, RustCoreError> {
        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        return .success(RustItemManagementResult(affectedCount: result.affected_count))
    }

    public func captureText(
        appSupportDirectory: URL,
        request: RustCaptureTextRequest
    ) -> Result<RustCaptureTextResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(
                RustCoreError(
                    code: "io_failed",
                    messageKey: "clipboard.error.io_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }

        let result = capture_text(
            appSupportDirectory.path,
            request.text,
            request.sourceBundleId ?? "",
            request.sourceAppName ?? "",
            request.sourceBundlePath ?? "",
            request.sourceIconRelativePath ?? "",
            request.sourceConfidence,
            request.pasteboardChangeCount,
            request.selfWriteToken ?? ""
        )

        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        return .success(
            RustCaptureTextResult(
                itemId: result.item_id.toString(),
                contentHash: result.content_hash.toString(),
                copyCount: result.copy_count,
                inserted: result.inserted
            )
        )
    }

    public func captureImage(
        appSupportDirectory: URL,
        request: RustCaptureImageRequest
    ) -> Result<RustCaptureImageResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(
                RustCoreError(
                    code: "io_failed",
                    messageKey: "clipboard.error.io_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }

        let result = capture_image(
            appSupportDirectory.path,
            request.payloadRelativePath,
            request.previewRelativePath ?? "",
            request.mimeType ?? "",
            request.width,
            request.height,
            request.byteCount,
            request.sourceBundleId ?? "",
            request.sourceAppName ?? "",
            request.sourceBundlePath ?? "",
            request.sourceIconRelativePath ?? "",
            request.sourceConfidence,
            request.pasteboardChangeCount,
            request.selfWriteToken ?? ""
        )

        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        return .success(
            RustCaptureImageResult(
                itemId: result.item_id.toString(),
                contentHash: result.content_hash.toString(),
                copyCount: result.copy_count,
                inserted: result.inserted
            )
        )
    }

    public func captureFiles(
        appSupportDirectory: URL,
        request: RustCaptureFilesRequest
    ) -> Result<RustCaptureFilesResult, RustCoreError> {
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(Self.makeIOError(error))
        }

        do {
            let data = try encoder.encode(request.filePaths)
            let filesJSON = String(data: data, encoding: .utf8) ?? "[]"
            let result = capture_files(
                appSupportDirectory.path,
                filesJSON,
                request.snapshotRelativePath ?? "",
                request.snapshotByteCount,
                request.sourceBundleId ?? "",
                request.sourceAppName ?? "",
                request.sourceBundlePath ?? "",
                request.sourceIconRelativePath ?? "",
                request.sourceConfidence,
                request.pasteboardChangeCount,
                request.selfWriteToken ?? ""
            )

            guard result.ok else {
                return .failure(Self.makeError(
                    code: result.error_code.toString(),
                    messageKey: result.message_key.toString()
                ))
            }

            return .success(
                RustCaptureFilesResult(
                    itemId: result.item_id.toString(),
                    contentHash: result.content_hash.toString(),
                    copyCount: result.copy_count,
                    inserted: result.inserted
                )
            )
        } catch {
            return .failure(
                RustCoreError(
                    code: "bridge_encode_failed",
                    messageKey: "clipboard.error.bridge_encode_failed",
                    recoverable: true,
                    message: error.localizedDescription
                )
            )
        }
    }
}
