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

public struct RustSvgRasterizeResult: Equatable, Sendable {
    public let pngData: Data
    public let width: Int
    public let height: Int
}

public struct RustPreferencesResult: Equatable, Sendable {
    public let schemaVersion: Int64
    public let preferences: RustPreferencesDocument
}

public struct RustPreferencesDocument: Equatable, Codable, Sendable {
    public var general: RustGeneralPreferences
    public var history: RustHistoryPreferences
    public var appearance: RustAppearancePreferences
    public var linkPreview: RustLinkPreviewPreferences
    public var shortcuts: RustShortcutsPreferences
    public var ignoreList: RustIgnoreListPreferences

    public init(
        general: RustGeneralPreferences = RustGeneralPreferences(),
        history: RustHistoryPreferences = RustHistoryPreferences(),
        appearance: RustAppearancePreferences = RustAppearancePreferences(),
        linkPreview: RustLinkPreviewPreferences = RustLinkPreviewPreferences(),
        shortcuts: RustShortcutsPreferences = RustShortcutsPreferences(),
        ignoreList: RustIgnoreListPreferences = RustIgnoreListPreferences()
    ) {
        self.general = general
        self.history = history
        self.appearance = appearance
        self.linkPreview = linkPreview
        self.shortcuts = shortcuts
        self.ignoreList = ignoreList
    }

    private enum CodingKeys: String, CodingKey {
        case general
        case history
        case appearance
        case linkPreview = "link_preview"
        case shortcuts
        case ignoreList = "ignore_list"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.general = try container.decodeIfPresent(RustGeneralPreferences.self, forKey: .general) ?? RustGeneralPreferences()
        self.history = try container.decodeIfPresent(RustHistoryPreferences.self, forKey: .history) ?? RustHistoryPreferences()
        self.appearance = try container.decodeIfPresent(RustAppearancePreferences.self, forKey: .appearance) ?? RustAppearancePreferences()
        self.linkPreview = try container.decodeIfPresent(RustLinkPreviewPreferences.self, forKey: .linkPreview) ?? RustLinkPreviewPreferences()
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
        maxItems: Int64 = 5000,
        retentionDays: Int64 = 30,
        recordImages: Bool = true,
        recordFiles: Bool = true
    ) {
        self.maxItems = 5000
        self.retentionDays = retentionDays
        self.recordImages = true
        self.recordFiles = true
    }

    private enum CodingKeys: String, CodingKey {
        case maxItems = "max_items"
        case retentionDays = "retention_days"
        case recordImages = "record_images"
        case recordFiles = "record_files"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(Int64.self, forKey: .maxItems)
        self.maxItems = 5000
        self.retentionDays = try container.decodeIfPresent(Int64.self, forKey: .retentionDays) ?? 30
        self.recordImages = true
        self.recordFiles = true
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
    public var pasteDirectlyToTarget: Bool

    public init(
        openPanel: RustKeyboardShortcut = RustKeyboardShortcut(),
        pasteDirectlyToTarget: Bool = false
    ) {
        self.openPanel = openPanel
        self.pasteDirectlyToTarget = pasteDirectlyToTarget
    }

    private enum CodingKeys: String, CodingKey {
        case openPanel = "open_panel"
        case pasteDirectlyToTarget = "paste_directly_to_target"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.openPanel = try container.decodeIfPresent(
            RustKeyboardShortcut.self,
            forKey: .openPanel
        ) ?? RustKeyboardShortcut()
        self.pasteDirectlyToTarget = try container.decodeIfPresent(
            Bool.self,
            forKey: .pasteDirectlyToTarget
        ) ?? false
    }
}

public struct RustLinkPreviewPreferences: Equatable, Codable, Sendable {
    public var webPreviewEnabled: Bool

    public init(
        webPreviewEnabled: Bool = true
    ) {
        self.webPreviewEnabled = webPreviewEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case webPreviewEnabled = "web_preview_enabled"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.webPreviewEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .webPreviewEnabled
        ) ?? true
    }
}

public struct RustKeyboardShortcut: Equatable, Codable, Sendable {
    public var keyCode: Int64
    public var modifiers: [String]

    public init(
        keyCode: Int64 = 7,
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
        ignoredAppIdentifiers: [String] = Self.defaultIgnoredAppIdentifiers,
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ignoredAppIdentifiers = try container.decodeIfPresent([String].self, forKey: .ignoredAppIdentifiers)
            ?? Self.defaultIgnoredAppIdentifiers
        self.windowTitleKeywords = try container.decodeIfPresent([String].self, forKey: .windowTitleKeywords) ?? []
        self.skipUnknownSource = try container.decodeIfPresent(Bool.self, forKey: .skipUnknownSource) ?? false
    }

    public static let defaultIgnoredAppIdentifiers = [
        "com.apple.Passwords",
        "com.apple.keychainaccess"
    ]
}

public struct RustLinkMetadataSummary: Equatable, Decodable, Sendable {
    public let canonicalURL: String
    public let displayURL: String
    public let host: String
    public let title: String?
    public let siteName: String?
    public let iconAssetPath: String?
    public let imageAssetPath: String?
    public let metadataState: String
    public let fetchedAtMs: Int64?

    public init(
        canonicalURL: String,
        displayURL: String,
        host: String,
        title: String? = nil,
        siteName: String? = nil,
        iconAssetPath: String? = nil,
        imageAssetPath: String? = nil,
        metadataState: String = "pending",
        fetchedAtMs: Int64? = nil
    ) {
        self.canonicalURL = canonicalURL
        self.displayURL = displayURL
        self.host = host
        self.title = title
        self.siteName = siteName
        self.iconAssetPath = iconAssetPath
        self.imageAssetPath = imageAssetPath
        self.metadataState = metadataState
        self.fetchedAtMs = fetchedAtMs
    }

    private enum CodingKeys: String, CodingKey {
        case canonicalURL = "canonical_url"
        case displayURL = "display_url"
        case host
        case title
        case siteName = "site_name"
        case iconAssetPath = "icon_asset_path"
        case imageAssetPath = "image_asset_path"
        case metadataState = "metadata_state"
        case fetchedAtMs = "fetched_at_ms"
    }
}

public struct RustClipboardFileItemSummary: Equatable, Decodable, Sendable {
    public let path: String
    public let fileName: String
    public let fileExtension: String?
    public let byteCount: Int64
    public let isDirectory: Bool
    public let width: Int64?
    public let height: Int64?
    public let contentType: String?

    public init(
        path: String,
        fileName: String,
        fileExtension: String?,
        byteCount: Int64,
        isDirectory: Bool,
        width: Int64?,
        height: Int64?,
        contentType: String?
    ) {
        self.path = path
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.isDirectory = isDirectory
        self.width = width
        self.height = height
        self.contentType = contentType
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case fileName = "file_name"
        case fileExtension = "file_extension"
        case byteCount = "byte_count"
        case isDirectory = "is_directory"
        case width
        case height
        case contentType = "content_type"
    }
}

public struct RustLinkMetadataFetchCandidate: Equatable, Decodable, Sendable {
    public let itemId: String
    public let canonicalURL: String
    public let displayURL: String
    public let host: String
    public let fetchAttempts: Int64
    public let leaseStartedAtMs: Int64

    public init(
        itemId: String,
        canonicalURL: String,
        displayURL: String,
        host: String,
        fetchAttempts: Int64,
        leaseStartedAtMs: Int64
    ) {
        self.itemId = itemId
        self.canonicalURL = canonicalURL
        self.displayURL = displayURL
        self.host = host
        self.fetchAttempts = fetchAttempts
        self.leaseStartedAtMs = leaseStartedAtMs
    }

    private enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case canonicalURL = "canonical_url"
        case displayURL = "display_url"
        case host
        case fetchAttempts = "fetch_attempts"
        case leaseStartedAtMs = "lease_started_at_ms"
    }
}

public struct RustCompleteLinkMetadataFetchRequest: Equatable, Encodable, Sendable {
    public let itemId: String
    public let leaseStartedAtMs: Int64
    public let canonicalURL: String
    public let displayURL: String
    public let host: String
    public let title: String?
    public let siteName: String?
    public let iconRelativePath: String?
    public let imageRelativePath: String?

    public init(
        itemId: String,
        leaseStartedAtMs: Int64,
        canonicalURL: String,
        displayURL: String,
        host: String,
        title: String? = nil,
        siteName: String? = nil,
        iconRelativePath: String? = nil,
        imageRelativePath: String? = nil
    ) {
        self.itemId = itemId
        self.leaseStartedAtMs = leaseStartedAtMs
        self.canonicalURL = canonicalURL
        self.displayURL = displayURL
        self.host = host
        self.title = title
        self.siteName = siteName
        self.iconRelativePath = iconRelativePath
        self.imageRelativePath = imageRelativePath
    }

    private enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case leaseStartedAtMs = "lease_started_at_ms"
        case canonicalURL = "canonical_url"
        case displayURL = "display_url"
        case host
        case title
        case siteName = "site_name"
        case iconRelativePath = "icon_relative_path"
        case imageRelativePath = "image_relative_path"
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
    public let sourceAppIconHeaderColor: Int64?
    public let previewAssetPath: String?
    public let payloadAssetPath: String?
    public let sourceConfidence: String
    public let firstCopiedAtMs: Int64
    public let lastCopiedAtMs: Int64
    public let copyCount: Int64
    public let isPinned: Bool
    public let sizeBytes: Int64
    public let previewState: String
    public let payloadState: String
    public let fileItems: [RustClipboardFileItemSummary]
    public let linkMetadata: RustLinkMetadataSummary?

    public init(
        id: String,
        itemType: String,
        summary: String,
        primaryText: String?,
        contentHash: String,
        sourceAppId: String?,
        sourceAppName: String?,
        sourceAppIconPath: String?,
        sourceAppIconHeaderColor: Int64? = nil,
        previewAssetPath: String?,
        payloadAssetPath: String?,
        sourceConfidence: String,
        firstCopiedAtMs: Int64,
        lastCopiedAtMs: Int64,
        copyCount: Int64,
        isPinned: Bool,
        sizeBytes: Int64,
        previewState: String,
        payloadState: String = "ready",
        fileItems: [RustClipboardFileItemSummary] = [],
        linkMetadata: RustLinkMetadataSummary? = nil
    ) {
        self.id = id
        self.itemType = itemType
        self.summary = summary
        self.primaryText = primaryText
        self.contentHash = contentHash
        self.sourceAppId = sourceAppId
        self.sourceAppName = sourceAppName
        self.sourceAppIconPath = sourceAppIconPath
        self.sourceAppIconHeaderColor = sourceAppIconHeaderColor
        self.previewAssetPath = previewAssetPath
        self.payloadAssetPath = payloadAssetPath
        self.sourceConfidence = sourceConfidence
        self.firstCopiedAtMs = firstCopiedAtMs
        self.lastCopiedAtMs = lastCopiedAtMs
        self.copyCount = copyCount
        self.isPinned = isPinned
        self.sizeBytes = sizeBytes
        self.previewState = previewState
        self.payloadState = payloadState
        self.fileItems = fileItems
        self.linkMetadata = linkMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            itemType: try container.decode(String.self, forKey: .itemType),
            summary: try container.decode(String.self, forKey: .summary),
            primaryText: try container.decodeIfPresent(String.self, forKey: .primaryText),
            contentHash: try container.decode(String.self, forKey: .contentHash),
            sourceAppId: try container.decodeIfPresent(String.self, forKey: .sourceAppId),
            sourceAppName: try container.decodeIfPresent(String.self, forKey: .sourceAppName),
            sourceAppIconPath: try container.decodeIfPresent(String.self, forKey: .sourceAppIconPath),
            sourceAppIconHeaderColor: try container.decodeIfPresent(Int64.self, forKey: .sourceAppIconHeaderColor),
            previewAssetPath: try container.decodeIfPresent(String.self, forKey: .previewAssetPath),
            payloadAssetPath: try container.decodeIfPresent(String.self, forKey: .payloadAssetPath),
            sourceConfidence: try container.decode(String.self, forKey: .sourceConfidence),
            firstCopiedAtMs: try container.decode(Int64.self, forKey: .firstCopiedAtMs),
            lastCopiedAtMs: try container.decode(Int64.self, forKey: .lastCopiedAtMs),
            copyCount: try container.decode(Int64.self, forKey: .copyCount),
            isPinned: try container.decode(Bool.self, forKey: .isPinned),
            sizeBytes: try container.decode(Int64.self, forKey: .sizeBytes),
            previewState: try container.decode(String.self, forKey: .previewState),
            payloadState: try container.decodeIfPresent(String.self, forKey: .payloadState) ?? "ready",
            fileItems: try container.decodeIfPresent(
                [RustClipboardFileItemSummary].self,
                forKey: .fileItems
            ) ?? [],
            linkMetadata: try container.decodeIfPresent(RustLinkMetadataSummary.self, forKey: .linkMetadata)
        )
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
        case sourceAppIconHeaderColor = "source_app_icon_header_color"
        case previewAssetPath = "preview_asset_path"
        case payloadAssetPath = "payload_asset_path"
        case sourceConfidence = "source_confidence"
        case firstCopiedAtMs = "first_copied_at_ms"
        case lastCopiedAtMs = "last_copied_at_ms"
        case copyCount = "copy_count"
        case isPinned = "is_pinned"
        case sizeBytes = "size_bytes"
        case previewState = "preview_state"
        case payloadState = "payload_state"
        case fileItems = "file_items"
        case linkMetadata = "link_metadata"
    }
}

public struct RustSourceAppSummary: Equatable, Decodable, Sendable {
    public let id: String
    public let bundleId: String?
    public let name: String
    public let iconPath: String?
    public let iconHeaderColor: Int64?
    public let itemCount: Int64
    public let lastCopiedAtMs: Int64

    private enum CodingKeys: String, CodingKey {
        case id
        case bundleId = "bundle_id"
        case name
        case iconPath = "icon_path"
        case iconHeaderColor = "icon_header_color"
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
    public let detectedLink: RustDetectedLink?
    public let sourceBundleId: String?
    public let sourceAppName: String?
    public let sourceBundlePath: String?
    public let sourceIconRelativePath: String?
    public let sourceConfidence: String
    public let pasteboardChangeCount: Int64
    public let selfWriteToken: String?

    public init(
        text: String,
        detectedLink: RustDetectedLink? = nil,
        sourceBundleId: String?,
        sourceAppName: String?,
        sourceBundlePath: String?,
        sourceIconRelativePath: String?,
        sourceConfidence: String,
        pasteboardChangeCount: Int64,
        selfWriteToken: String? = nil
    ) {
        self.text = text
        self.detectedLink = detectedLink
        self.sourceBundleId = sourceBundleId
        self.sourceAppName = sourceAppName
        self.sourceBundlePath = sourceBundlePath
        self.sourceIconRelativePath = sourceIconRelativePath
        self.sourceConfidence = sourceConfidence
        self.pasteboardChangeCount = pasteboardChangeCount
        self.selfWriteToken = selfWriteToken
    }
}

public struct RustDetectedLink: Equatable, Sendable {
    public let originalText: String
    public let canonicalURL: String
    public let displayURL: String
    public let host: String
    public let metadataState: String

    public init(
        originalText: String,
        canonicalURL: String,
        displayURL: String,
        host: String,
        metadataState: String
    ) {
        self.originalText = originalText
        self.canonicalURL = canonicalURL
        self.displayURL = displayURL
        self.host = host
        self.metadataState = metadataState
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

public struct RustCapturePendingImageRequest: Equatable, Encodable, Sendable {
    public let ownerSessionId: String
    public let thumbnailRelativePath: String
    public let reservedPayloadRelativePath: String
    public let stagedPayloadRelativePath: String
    public let mimeType: String
    public let width: Int64
    public let height: Int64
    public let thumbnailWidth: Int64
    public let thumbnailHeight: Int64
    public let thumbnailByteCount: Int64
    public let sourceBundleId: String?
    public let sourceAppName: String?
    public let sourceBundlePath: String?
    public let sourceIconRelativePath: String?
    public let sourceConfidence: String
    public let pasteboardChangeCount: Int64
    public let selfWriteToken: String?
    public let leaseDurationMs: Int64?
    public let cleanupAfterDurationMs: Int64?

    public init(
        ownerSessionId: String,
        thumbnailRelativePath: String,
        reservedPayloadRelativePath: String,
        stagedPayloadRelativePath: String,
        mimeType: String = "image/webp",
        width: Int64,
        height: Int64,
        thumbnailWidth: Int64,
        thumbnailHeight: Int64,
        thumbnailByteCount: Int64,
        sourceBundleId: String?,
        sourceAppName: String?,
        sourceBundlePath: String?,
        sourceIconRelativePath: String?,
        sourceConfidence: String,
        pasteboardChangeCount: Int64,
        selfWriteToken: String? = nil,
        leaseDurationMs: Int64? = nil,
        cleanupAfterDurationMs: Int64? = nil
    ) {
        self.ownerSessionId = ownerSessionId
        self.thumbnailRelativePath = thumbnailRelativePath
        self.reservedPayloadRelativePath = reservedPayloadRelativePath
        self.stagedPayloadRelativePath = stagedPayloadRelativePath
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.thumbnailWidth = thumbnailWidth
        self.thumbnailHeight = thumbnailHeight
        self.thumbnailByteCount = thumbnailByteCount
        self.sourceBundleId = sourceBundleId
        self.sourceAppName = sourceAppName
        self.sourceBundlePath = sourceBundlePath
        self.sourceIconRelativePath = sourceIconRelativePath
        self.sourceConfidence = sourceConfidence
        self.pasteboardChangeCount = pasteboardChangeCount
        self.selfWriteToken = selfWriteToken
        self.leaseDurationMs = leaseDurationMs
        self.cleanupAfterDurationMs = cleanupAfterDurationMs
    }

    private enum CodingKeys: String, CodingKey {
        case ownerSessionId = "owner_session_id"
        case thumbnailRelativePath = "thumbnail_relative_path"
        case reservedPayloadRelativePath = "reserved_payload_relative_path"
        case stagedPayloadRelativePath = "staged_payload_relative_path"
        case mimeType = "mime_type"
        case width
        case height
        case thumbnailWidth = "thumbnail_width"
        case thumbnailHeight = "thumbnail_height"
        case thumbnailByteCount = "thumbnail_byte_count"
        case sourceBundleId = "source_bundle_id"
        case sourceAppName = "source_app_name"
        case sourceBundlePath = "source_bundle_path"
        case sourceIconRelativePath = "source_icon_relative_path"
        case sourceConfidence = "source_confidence"
        case pasteboardChangeCount = "pasteboard_change_count"
        case selfWriteToken = "self_write_token"
        case leaseDurationMs = "lease_duration_ms"
        case cleanupAfterDurationMs = "cleanup_after_duration_ms"
    }
}

public struct RustPendingImageCaptureResult: Equatable, Decodable, Sendable {
    public let jobId: String
    public let itemId: String
    public let contentHash: String
    public let copyCount: Int64
    public let inserted: Bool

    private enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case itemId = "item_id"
        case contentHash = "content_hash"
        case copyCount = "copy_count"
        case inserted
    }
}

public struct RustCompletePendingImagePayloadRequest: Equatable, Encodable, Sendable {
    public let jobId: String
    public let stagedPayloadRelativePath: String
    public let mimeType: String
    public let width: Int64
    public let height: Int64
    public let byteCount: Int64

    public init(
        jobId: String,
        stagedPayloadRelativePath: String,
        mimeType: String = "image/webp",
        width: Int64,
        height: Int64,
        byteCount: Int64
    ) {
        self.jobId = jobId
        self.stagedPayloadRelativePath = stagedPayloadRelativePath
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }

    private enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case stagedPayloadRelativePath = "staged_payload_relative_path"
        case mimeType = "mime_type"
        case width
        case height
        case byteCount = "byte_count"
    }
}

public struct RustFailPendingImagePayloadRequest: Equatable, Encodable, Sendable {
    public let jobId: String
    public let stagedPayloadRelativePath: String?
    public let failureCode: String

    public init(
        jobId: String,
        stagedPayloadRelativePath: String?,
        failureCode: String
    ) {
        self.jobId = jobId
        self.stagedPayloadRelativePath = stagedPayloadRelativePath
        self.failureCode = failureCode
    }

    private enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case stagedPayloadRelativePath = "staged_payload_relative_path"
        case failureCode = "failure_code"
    }
}

public struct RustRecoverPendingImagesRequest: Equatable, Encodable, Sendable {
    public let ownerSessionId: String

    public init(ownerSessionId: String) {
        self.ownerSessionId = ownerSessionId
    }

    private enum CodingKeys: String, CodingKey {
        case ownerSessionId = "owner_session_id"
    }
}

public struct RustPendingImageCompletionResult: Equatable, Decodable, Sendable {
    public let status: String
    public let jobId: String?
    public let itemId: String?
    public let effectiveItemId: String?
    public let contentHash: String?
    public let cleanedRelativePaths: [String]
    public let affectedCount: Int64

    private enum CodingKeys: String, CodingKey {
        case status
        case jobId = "job_id"
        case itemId = "item_id"
        case effectiveItemId = "effective_item_id"
        case contentHash = "content_hash"
        case cleanedRelativePaths = "cleaned_relative_paths"
        case affectedCount = "affected_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(String.self, forKey: .status)
        self.jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
        self.itemId = try container.decodeIfPresent(String.self, forKey: .itemId)
        self.effectiveItemId = try container.decodeIfPresent(String.self, forKey: .effectiveItemId)
        self.contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        self.cleanedRelativePaths = try container.decodeIfPresent(
            [String].self,
            forKey: .cleanedRelativePaths
        ) ?? []
        self.affectedCount = try container.decode(Int64.self, forKey: .affectedCount)
    }
}

public struct RustCaptureFilesRequest: Equatable, Sendable {
    public let filePaths: [String]
    public let fileItems: [ClipboardCapturedFileMetadata]
    public let previewRelativePath: String?
    public let previewMimeType: String?
    public let previewWidth: Int64
    public let previewHeight: Int64
    public let previewByteCount: Int64
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
        fileItems: [ClipboardCapturedFileMetadata] = [],
        previewRelativePath: String? = nil,
        previewMimeType: String? = nil,
        previewWidth: Int64 = 0,
        previewHeight: Int64 = 0,
        previewByteCount: Int64 = 0,
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
        self.fileItems = fileItems
        self.previewRelativePath = previewRelativePath
        self.previewMimeType = previewMimeType
        self.previewWidth = previewWidth
        self.previewHeight = previewHeight
        self.previewByteCount = previewByteCount
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

    public static func activeSourceIconHeaderColorCacheVersion() -> Int64 {
        active_source_icon_header_color_cache_version()
    }

    public func encodeLosslessWebP(
        rgbaData: Data,
        width: Int,
        height: Int
    ) -> Result<Data, RustCoreError> {
        let expectedByteCount = width > 0 && height > 0
            ? width.multipliedReportingOverflow(by: height)
            : (partialValue: 0, overflow: true)
        let expectedRGBAByteCount = expectedByteCount.overflow
            ? (partialValue: 0, overflow: true)
            : expectedByteCount.partialValue.multipliedReportingOverflow(by: 4)
        guard !expectedRGBAByteCount.overflow,
              rgbaData.count == expectedRGBAByteCount.partialValue
        else {
            return .failure(Self.makeError(
                code: "invalid_input",
                messageKey: "clipboard.error.invalid_input"
            ))
        }

        return rgbaData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return .failure(Self.makeError(
                    code: "invalid_input",
                    messageKey: "clipboard.error.invalid_input"
                ))
            }

            let buffer = UnsafeBufferPointer(start: baseAddress, count: rgbaData.count)
            let result = encode_webp_lossless_rgba(buffer, Int64(width), Int64(height))
            guard result.ok else {
                return .failure(Self.makeError(
                    code: result.error_code.toString(),
                    messageKey: result.message_key.toString()
                ))
            }

            return .success(Data(bytes: result.bytes.as_ptr(), count: result.bytes.len()))
        }
    }

    public func rasterizeSVGToPNG(
        svgData: Data,
        maxWidth: Int,
        maxHeight: Int
    ) -> Result<RustSvgRasterizeResult, RustCoreError> {
        guard maxWidth > 0, maxHeight > 0, !svgData.isEmpty else {
            return .failure(Self.makeError(
                code: "invalid_input",
                messageKey: "clipboard.error.invalid_input"
            ))
        }

        return svgData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return .failure(Self.makeError(
                    code: "invalid_input",
                    messageKey: "clipboard.error.invalid_input"
                ))
            }

            let buffer = UnsafeBufferPointer(start: baseAddress, count: svgData.count)
            let result = rasterize_svg_to_png(buffer, Int64(maxWidth), Int64(maxHeight))
            guard result.ok else {
                return .failure(Self.makeError(
                    code: result.error_code.toString(),
                    messageKey: result.message_key.toString()
                ))
            }

            return .success(RustSvgRasterizeResult(
                pngData: Data(bytes: result.bytes.as_ptr(), count: result.bytes.len()),
                width: Int(result.width),
                height: Int(result.height)
            ))
        }
    }

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
        itemType: String? = nil,
        sourceAppId: String? = nil,
        pinboardId: String? = nil,
        searchText: String? = nil
    ) -> Result<RustCoreListResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            listItemsBridge(
                appSupportPath: appSupportPath,
                limit: limit,
                offset: offset,
                itemType: itemType,
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

    public func recordItemCopied(
        appSupportDirectory: URL,
        itemId: String
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = record_item_copied(appSupportPath, itemId)
            return decodeItemManagementResult(result)
        }
    }

    public func updateSourceAppIconHeaderColor(
        appSupportDirectory: URL,
        sourceAppId: String,
        sourceAppIconPath: String?,
        headerColorARGB: Int64,
        allowLatestWithoutPath: Bool = false
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = update_source_app_icon_header_color(
                appSupportPath,
                sourceAppId,
                sourceAppIconPath ?? "",
                headerColorARGB,
                allowLatestWithoutPath
            )
            return decodeItemManagementResult(result)
        }
    }

    public func clearItems(
        appSupportDirectory: URL,
        itemType: String? = nil,
        sourceAppId: String? = nil,
        searchText: String? = nil
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = clear_items(
                appSupportPath,
                itemType ?? "",
                sourceAppId ?? "",
                searchText ?? ""
            )
            return decodeItemManagementResult(result)
        }
    }

    public func claimLinkMetadataFetchBatch(
        appSupportDirectory: URL,
        limit: Int64 = 3,
        leaseTimeoutMs: Int64 = 60_000
    ) -> Result<[RustLinkMetadataFetchCandidate], RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = claim_link_metadata_fetch_batch(appSupportPath, limit, leaseTimeoutMs)
            guard result.ok else {
                return .failure(Self.makeError(
                    code: result.error_code.toString(),
                    messageKey: result.message_key.toString()
                ))
            }

            return Self.decodeBridgeJSON(
                result.candidates_json.toString(),
                as: [RustLinkMetadataFetchCandidate].self
            )
        }
    }

    public func completeLinkMetadataFetch(
        appSupportDirectory: URL,
        request: RustCompleteLinkMetadataFetchRequest
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            switch Self.encodeBridgeJSON(request) {
            case .success(let json):
                let result = complete_link_metadata_fetch(appSupportPath, json)
                return decodeItemManagementResult(result)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    public func failLinkMetadataFetch(
        appSupportDirectory: URL,
        itemId: String,
        leaseStartedAtMs: Int64,
        failureCode: String,
        nextRetryAtMs: Int64? = nil
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let result = fail_link_metadata_fetch(
                appSupportPath,
                itemId,
                leaseStartedAtMs,
                failureCode,
                nextRetryAtMs ?? 0
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
        itemType: String? = nil,
        sourceAppId: String? = nil,
        pinboardId: String? = nil,
        searchText: String? = nil
    ) -> Result<RustCoreListResult, RustCoreError> {
        let result = list_items(
            appSupportPath,
            limit,
            offset,
            itemType ?? "",
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
                request.detectedLink?.originalText ?? "",
                request.detectedLink?.canonicalURL ?? "",
                request.detectedLink?.displayURL ?? "",
                request.detectedLink?.host ?? "",
                request.detectedLink?.metadataState ?? "",
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

    public func capturePendingImage(
        appSupportDirectory: URL,
        request: RustCapturePendingImageRequest
    ) -> Result<RustPendingImageCaptureResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            switch Self.encodeBridgeJSON(request) {
            case .success(let json):
                let result = capture_pending_image(appSupportPath, json)
                return decodePendingImageResult(result, as: RustPendingImageCaptureResult.self)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    public func completePendingImagePayload(
        appSupportDirectory: URL,
        request: RustCompletePendingImagePayloadRequest
    ) -> Result<RustPendingImageCompletionResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            switch Self.encodeBridgeJSON(request) {
            case .success(let json):
                let result = complete_pending_image_payload(appSupportPath, json)
                return decodePendingImageResult(result, as: RustPendingImageCompletionResult.self)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    public func failPendingImagePayload(
        appSupportDirectory: URL,
        request: RustFailPendingImagePayloadRequest
    ) -> Result<RustPendingImageCompletionResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            switch Self.encodeBridgeJSON(request) {
            case .success(let json):
                let result = fail_pending_image_payload(appSupportPath, json)
                return decodePendingImageResult(result, as: RustPendingImageCompletionResult.self)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    public func recoverPendingImages(
        appSupportDirectory: URL,
        request: RustRecoverPendingImagesRequest
    ) -> Result<RustItemManagementResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            switch Self.encodeBridgeJSON(request) {
            case .success(let json):
                let result = recover_pending_images(appSupportPath, json)
                return decodeItemManagementResult(result)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    private func decodePendingImageResult<T: Decodable>(
        _ result: CorePendingImageResult,
        as type: T.Type
    ) -> Result<T, RustCoreError> {
        guard result.ok else {
            return .failure(Self.makeError(
                code: result.error_code.toString(),
                messageKey: result.message_key.toString()
            ))
        }

        return Self.decodeBridgeJSON(result.result_json.toString(), as: type)
    }

    public func captureFiles(
        appSupportDirectory: URL,
        request: RustCaptureFilesRequest
    ) -> Result<RustCaptureFilesResult, RustCoreError> {
        withPreparedAppSupportDirectory(appSupportDirectory) { appSupportPath in
            let encodedFiles = request.fileItems.isEmpty
                ? Self.encodeBridgeJSON(request.filePaths)
                : Self.encodeBridgeJSON(request.fileItems)
            switch encodedFiles {
            case .success(let filesJSON):
                let result = capture_files(
                    appSupportPath,
                    filesJSON,
                    request.previewRelativePath ?? "",
                    request.previewMimeType ?? "",
                    request.previewWidth,
                    request.previewHeight,
                    request.previewByteCount,
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
