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

public struct RustCorePinboardsResult: Equatable, Sendable {
    public let pinboards: [RustPinboardSummary]
    public let totalCount: Int64

    public init(pinboards: [RustPinboardSummary], totalCount: Int64) {
        self.pinboards = pinboards
        self.totalCount = totalCount
    }
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
    public var shortcuts: RustShortcutsPreferences
    public var ignoreList: RustIgnoreListPreferences

    public init(
        general: RustGeneralPreferences = RustGeneralPreferences(),
        history: RustHistoryPreferences = RustHistoryPreferences(),
        appearance: RustAppearancePreferences = RustAppearancePreferences(),
        shortcuts: RustShortcutsPreferences = RustShortcutsPreferences(),
        ignoreList: RustIgnoreListPreferences = RustIgnoreListPreferences()
    ) {
        self.general = general
        self.history = history
        self.appearance = appearance
        self.shortcuts = shortcuts
        self.ignoreList = ignoreList
    }

    private enum CodingKeys: String, CodingKey {
        case general
        case history
        case appearance
        case shortcuts
        case ignoreList = "ignore_list"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.general = try container.decodeIfPresent(RustGeneralPreferences.self, forKey: .general) ?? RustGeneralPreferences()
        self.history = try container.decodeIfPresent(RustHistoryPreferences.self, forKey: .history) ?? RustHistoryPreferences()
        self.appearance = try container.decodeIfPresent(RustAppearancePreferences.self, forKey: .appearance) ?? RustAppearancePreferences()
        self.shortcuts = try container.decodeIfPresent(RustShortcutsPreferences.self, forKey: .shortcuts) ?? RustShortcutsPreferences()
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
        defaultPanelHeight: Int64 = 302
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

public struct RustShortcutsPreferences: Equatable, Codable, Sendable {
    public var openPanel: RustKeyboardShortcut

    public init(openPanel: RustKeyboardShortcut = RustKeyboardShortcut()) {
        self.openPanel = openPanel
    }

    private enum CodingKeys: String, CodingKey {
        case openPanel = "open_panel"
    }
}

public struct RustKeyboardShortcut: Equatable, Codable, Sendable {
    public var keyCode: Int64
    public var modifiers: [String]

    public init(
        keyCode: Int64 = 9,
        modifiers: [String] = ["command", "shift"]
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case modifiers
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

public struct RustPinboardSummary: Equatable, Decodable, Sendable {
    public let id: String
    public let title: String
    public let colorCode: Int64
    public let sortOrder: Int64
    public let itemCount: Int64
    public let createdAtMs: Int64
    public let updatedAtMs: Int64

    public init(
        id: String,
        title: String,
        colorCode: Int64 = 0,
        sortOrder: Int64 = 0,
        itemCount: Int64,
        createdAtMs: Int64,
        updatedAtMs: Int64
    ) {
        self.id = id
        self.title = title
        self.colorCode = colorCode
        self.sortOrder = sortOrder
        self.itemCount = itemCount
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case colorCode = "color_code"
        case sortOrder = "sort_order"
        case itemCount = "item_count"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
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

public struct RustCoreClient: Sendable {
    public init() {}

    public func open(appSupportDirectory: URL) -> Result<RustCoreOpenResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = open_core(appSupportPath)

            guard result.ok else {
                return .failure(Self.makeError(
                    code: result.error_code.toString(),
                    messageKey: result.message_key.toString()
                ))
            }

            switch listItemsBridge(appSupportPath: appSupportPath) {
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
    }

    public func runMaintenance(
        appSupportDirectory: URL
    ) -> Result<RustMaintenanceResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = run_maintenance(appSupportPath)
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
    }

    public func listItems(
        appSupportDirectory: URL,
        limit: Int64 = 50,
        offset: Int64 = 0,
        sourceAppId: String? = nil,
        pinboardId: String? = nil,
        searchText: String? = nil
    ) -> Result<RustCoreListResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            listItemsBridge(
                appSupportPath: appSupportPath,
                limit: limit,
                offset: offset,
                sourceAppId: sourceAppId,
                pinboardId: pinboardId,
                searchText: searchText
            )
        }
    }

    public func listSourceApps(
        appSupportDirectory: URL,
        limit: Int64 = 12,
        offset: Int64 = 0
    ) -> Result<RustCoreSourceAppsResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = list_source_apps(appSupportPath, limit, offset)

            guard result.ok else {
                return .failure(Self.makeError(
                    code: result.error_code.toString(),
                    messageKey: result.message_key.toString()
                ))
            }

            switch Self.decodeBridgeJSON(
                result.apps_json.toString(),
                as: [RustSourceAppSummary].self
            ) {
            case .success(let apps):
                return .success(
                    RustCoreSourceAppsResult(
                        apps: apps,
                        totalCount: result.total_count,
                        hasMore: result.has_more
                    )
                )
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    public func listPinboards(
        appSupportDirectory: URL
    ) -> Result<RustCorePinboardsResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = list_pinboards(appSupportPath)

            guard result.ok else {
                return .failure(Self.makeError(
                    code: result.error_code.toString(),
                    messageKey: result.message_key.toString()
                ))
            }

            switch Self.decodeBridgeJSON(
                result.pinboards_json.toString(),
                as: [RustPinboardSummary].self
            ) {
            case .success(let pinboards):
                return .success(
                    RustCorePinboardsResult(
                        pinboards: pinboards,
                        totalCount: result.total_count
                    )
                )
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    public func setItemPinboardMembership(
        appSupportDirectory: URL,
        itemId: String,
        pinboardId: String,
        isMember: Bool
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = set_item_pinboard_membership(appSupportPath, itemId, pinboardId, isMember)
            return decodeItemManagementResult(result)
        }
    }

    public func createPinboard(
        appSupportDirectory: URL,
        title: String,
        colorCode: Int64 = 0
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = create_pinboard(appSupportPath, title, colorCode)
            return decodeItemManagementResult(result)
        }
    }

    public func renamePinboard(
        appSupportDirectory: URL,
        pinboardId: String,
        title: String
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = rename_pinboard(appSupportPath, pinboardId, title)
            return decodeItemManagementResult(result)
        }
    }

    public func updatePinboardColor(
        appSupportDirectory: URL,
        pinboardId: String,
        colorCode: Int64
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = update_pinboard_color(appSupportPath, pinboardId, colorCode)
            return decodeItemManagementResult(result)
        }
    }

    public func deletePinboard(
        appSupportDirectory: URL,
        pinboardId: String
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = delete_pinboard(appSupportPath, pinboardId)
            return decodeItemManagementResult(result)
        }
    }

    public func deleteItem(
        appSupportDirectory: URL,
        itemId: String
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = delete_item(appSupportPath, itemId)
            return decodeItemManagementResult(result)
        }
    }

    public func clearItems(
        appSupportDirectory: URL,
        sourceAppId: String? = nil,
        searchText: String? = nil
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = clear_items(
                appSupportPath,
                "",
                sourceAppId ?? "",
                searchText ?? ""
            )
            return decodeItemManagementResult(result)
        }
    }

    public func getPreferences(
        appSupportDirectory: URL
    ) -> Result<RustPreferencesResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = get_preferences(appSupportPath)
            return decodePreferencesResult(result)
        }
    }

    public func updatePreferences(
        appSupportDirectory: URL,
        preferences: RustPreferencesDocument
    ) -> Result<RustPreferencesResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            switch Self.encodeBridgeJSON(preferences) {
            case .success(let json):
                let result = update_preferences(appSupportPath, json)
                return decodePreferencesResult(result)
            case .failure(let error):
                return .failure(error)
            }
        }
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

        switch Self.decodeBridgeJSON(
            result.preferences_json.toString(),
            as: RustPreferencesDocument.self
        ) {
        case .success(let preferences):
            return .success(
                RustPreferencesResult(
                    schemaVersion: result.schema_version,
                    preferences: preferences
                )
            )
        case .failure(let error):
            return .failure(error)
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

    private static func makeBridgeDecodeError(_ error: Error) -> RustCoreError {
        RustCoreError(
            code: "bridge_decode_failed",
            messageKey: "clipboard.error.bridge_decode_failed",
            recoverable: true,
            message: error.localizedDescription
        )
    }

    private static func makeBridgeEncodeError(_ error: Error) -> RustCoreError {
        RustCoreError(
            code: "bridge_encode_failed",
            messageKey: "clipboard.error.bridge_encode_failed",
            recoverable: true,
            message: error.localizedDescription
        )
    }

    private func withPreparedAppSupportDirectory<T>(
        _ appSupportDirectory: URL,
        perform: (String) -> Result<T, RustCoreError>
    ) -> Result<T, RustCoreError> {
        do {
            try FileManager.default.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
            return perform(appSupportDirectory.path)
        } catch {
            return .failure(Self.makeIOError(error))
        }
    }

    private func listItemsBridge(
        appSupportPath: String,
        limit: Int64 = 50,
        offset: Int64 = 0,
        sourceAppId: String? = nil,
        pinboardId: String? = nil,
        searchText: String? = nil
    ) -> Result<RustCoreListResult, RustCoreError> {
        let result = list_items(
            appSupportPath,
            limit,
            offset,
            "",
            sourceAppId ?? "",
            pinboardId ?? "",
            searchText ?? ""
        )

        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        switch Self.decodeBridgeJSON(
            result.items_json.toString(),
            as: [RustClipboardItemSummary].self
        ) {
        case .success(let items):
            return .success(
                RustCoreListResult(
                    items: items,
                    totalCount: result.total_count,
                    hasMore: result.has_more
                )
            )
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func decodeBridgeJSON<T: Decodable>(
        _ value: String,
        as type: T.Type
    ) -> Result<T, RustCoreError> {
        do {
            guard let data = value.data(using: .utf8) else {
                return .failure(makeBridgeDecodeError(BridgePayloadEncodingError.invalidUTF8))
            }
            let decoder = JSONDecoder()
            return .success(try decoder.decode(T.self, from: data))
        } catch {
            return .failure(makeBridgeDecodeError(error))
        }
    }

    private static func encodeBridgeJSON<T: Encodable>(
        _ value: T
    ) -> Result<String, RustCoreError> {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            guard let json = String(data: data, encoding: .utf8) else {
                return .failure(makeBridgeEncodeError(BridgePayloadEncodingError.invalidUTF8))
            }
            return .success(json)
        } catch {
            return .failure(makeBridgeEncodeError(error))
        }
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
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = capture_text(
                appSupportPath,
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
    }

    public func captureImage(
        appSupportDirectory: URL,
        request: RustCaptureImageRequest
    ) -> Result<RustCaptureImageResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = capture_image(
                appSupportPath,
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
    }

    public func captureFiles(
        appSupportDirectory: URL,
        request: RustCaptureFilesRequest
    ) -> Result<RustCaptureFilesResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            switch Self.encodeBridgeJSON(request.filePaths) {
            case .success(let filesJSON):
                let result = capture_files(
                    appSupportPath,
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
            case .failure(let error):
                return .failure(error)
            }
        }
    }
}

private enum BridgePayloadEncodingError: LocalizedError {
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "bridge payload is not valid UTF-8"
        }
    }
}
