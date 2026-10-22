import ClipboardCoreBridge
import Foundation

private enum PreferenceValue: Equatable, Codable, Sendable {
    case bool(Bool), integer(Int64), string(String), array([PreferenceValue])
    case object([String: PreferenceValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([PreferenceValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: PreferenceValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// Captures a user's edited fields at the time of the edit, before any await.
/// Fixed history limits and permission/runtime state are deliberately excluded.
public struct RustPreferencesPatch: Equatable, Encodable, Sendable {
    private var fields: [String: [String: PreferenceValue]] = [:]

    public init() {}
    public var isEmpty: Bool { fields.isEmpty }
    public var changesLaunchAtLogin: Bool { fields["general"]?["launch_at_login"] != nil }

    public init(previous: RustPreferencesDocument, next: RustPreferencesDocument, launchAtLoginIntent: Bool? = nil) {
        func changed<T: Equatable>(_ before: T, _ after: T, _ value: PreferenceValue,
                                   _ section: String, _ field: String) {
            if before != after { fields[section, default: [:]][field] = value }
        }
        let g = previous.general, ng = next.general
        changed(g.launchAtLogin, ng.launchAtLogin, .bool(ng.launchAtLogin), "general", "launch_at_login")
        changed(g.showMenuBarItem, ng.showMenuBarItem, .bool(ng.showMenuBarItem), "general", "show_menu_bar_item")
        changed(g.copyCompletionHUDEnabled, ng.copyCompletionHUDEnabled, .bool(ng.copyCompletionHUDEnabled), "general", "copy_completion_hud_enabled")
        changed(g.externalCopySoundEnabled, ng.externalCopySoundEnabled, .bool(ng.externalCopySoundEnabled), "general", "external_copy_sound_enabled")
        changed(g.defaultPanelHeight, ng.defaultPanelHeight, .integer(ng.defaultPanelHeight), "general", "default_panel_height")
        changed(previous.history.retentionDays, next.history.retentionDays, .integer(next.history.retentionDays), "history", "retention_days")
        changed(previous.history.retentionForever, next.history.retentionForever, .bool(next.history.retentionForever), "history", "retention_forever")
        changed(previous.appearance.mode, next.appearance.mode, .string(next.appearance.mode), "appearance", "mode")
        changed(previous.appearance.itemDensity, next.appearance.itemDensity, .string(next.appearance.itemDensity), "appearance", "item_density")
        changed(previous.appearance.previewPopoverEnabled, next.appearance.previewPopoverEnabled, .bool(next.appearance.previewPopoverEnabled), "appearance", "preview_popover_enabled")
        changed(previous.linkPreview.webPreviewEnabled, next.linkPreview.webPreviewEnabled, .bool(next.linkPreview.webPreviewEnabled), "link_preview", "web_preview_enabled")
        changed(previous.ignoreList.ignoredAppIdentifiers, next.ignoreList.ignoredAppIdentifiers, .array(next.ignoreList.ignoredAppIdentifiers.map(PreferenceValue.string)), "ignore_list", "ignored_app_identifiers")
        changed(previous.ignoreList.windowTitleKeywords, next.ignoreList.windowTitleKeywords, .array(next.ignoreList.windowTitleKeywords.map(PreferenceValue.string)), "ignore_list", "window_title_keywords")
        changed(previous.ignoreList.skipUnknownSource, next.ignoreList.skipUnknownSource, .bool(next.ignoreList.skipUnknownSource), "ignore_list", "skip_unknown_source")
        let s = previous.shortcuts, ns = next.shortcuts
        changed(s.openPanel, ns.openPanel, Self.shortcut(ns.openPanel), "shortcuts", "open_panel")
        changed(s.previousPinboard, ns.previousPinboard, Self.shortcut(ns.previousPinboard), "shortcuts", "previous_pinboard")
        changed(s.nextPinboard, ns.nextPinboard, Self.shortcut(ns.nextPinboard), "shortcuts", "next_pinboard")
        changed(s.quickPasteModifier, ns.quickPasteModifier, .string(ns.quickPasteModifier), "shortcuts", "quick_paste_modifier")
        changed(s.plainTextModifier, ns.plainTextModifier, .string(ns.plainTextModifier), "shortcuts", "plain_text_modifier")
        changed(s.pasteDirectlyToTarget, ns.pasteDirectlyToTarget, .bool(ns.pasteDirectlyToTarget), "shortcuts", "paste_directly_to_target")
        changed(s.alwaysPasteAsPlainText, ns.alwaysPasteAsPlainText, .bool(ns.alwaysPasteAsPlainText), "shortcuts", "always_paste_as_plain_text")
        // The system login item can change even when saving the document fails.
        // Preserve an explicit toggle intent independently of the confirmed DB value.
        if let launchAtLoginIntent {
            fields["general", default: [:]]["launch_at_login"] = .bool(launchAtLoginIntent)
        }
    }

    private static func shortcut(_ value: RustKeyboardShortcut?) -> PreferenceValue {
        guard let value else { return .object(["op": .string("clear")]) }
        return .object(["op": .string("set"), "value": .object([
            "key_code": .integer(value.keyCode), "modifiers": .array(value.modifiers.map(PreferenceValue.string))
        ])])
    }

    public func settingLaunchAtLogin(_ enabled: Bool) -> Self {
        var patch = self
        patch.fields["general", default: [:]]["launch_at_login"] = .bool(enabled)
        return patch
    }

    public func applying(to document: RustPreferencesDocument) throws -> RustPreferencesDocument {
        let encoder = JSONEncoder()
        var value = try JSONDecoder().decode([String: [String: PreferenceValue]].self, from: encoder.encode(document))
        for (section, edits) in fields {
            for (key, edit) in edits {
                if section == "shortcuts", case .object(let action) = edit {
                    value[section, default: [:]][key] = action["op"] == .string("clear") ? .null : action["value"]
                } else {
                    value[section, default: [:]][key] = edit
                }
            }
        }
        return try JSONDecoder().decode(RustPreferencesDocument.self, from: encoder.encode(value))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }
}

public struct RustPreferencesMaintenance: Equatable, Decodable, Sendable {
    public let status: String
    public let stage: String?
    public let code: String?
    public let mayHaveChanged: Bool

    enum CodingKeys: String, CodingKey {
        case status, stage, code
        case mayHaveChanged = "may_have_changed"
    }
}

public struct RustPreferencesPatchResult: Equatable, Decodable, Sendable {
    public let document: RustPreferencesDocument
    public let changedSections: [String]
    public let maintenance: RustPreferencesMaintenance

    enum CodingKeys: String, CodingKey {
        case document, maintenance
        case changedSections = "changed_sections"
    }

    public var warningText: String? {
        guard maintenance.status == "warning" else { return nil }
        return AppLocalization.format("preferences.saved.maintenanceWarning", defaultValue: "偏好已保存；历史清理未完成：%@", maintenance.code ?? "unknown")
    }
}

public extension RustCoreClient {
    /// Bootstrap/configuration recovery must not be blocked by failed cleanup.
    func openWithoutHistoryMaintenance(appSupportDirectory: URL) -> Result<RustCoreOpenResult, RustCoreError> {
        preferenceBridge(appSupportDirectory) { path in
            let result = open_core_without_maintenance(path)
            guard result.ok else { throw preferenceBridgeError(result.error_code.toString(), result.message_key.toString()) }
            return RustCoreOpenResult(databasePath: result.database_path.toString(), schemaVersion: result.schema_version,
                                      itemCount: result.item_count, items: [])
        }
    }

    func getPreferencesWithoutHistoryMaintenance(appSupportDirectory: URL) -> Result<RustPreferencesResult, RustCoreError> {
        preferenceBridge(appSupportDirectory) { path in
            let result = get_preferences_without_maintenance(path)
            guard result.ok else { throw preferenceBridgeError(result.error_code.toString(), result.message_key.toString()) }
            let document = try JSONDecoder().decode(RustPreferencesDocument.self, from: Data(result.preferences_json.toString().utf8))
            return RustPreferencesResult(schemaVersion: result.schema_version, preferences: document)
        }
    }

    func patchPreferences(appSupportDirectory: URL, patch: RustPreferencesPatch) -> Result<RustPreferencesPatchResult, RustCoreError> {
        preferenceBridge(appSupportDirectory) { path in
            let json = String(decoding: try JSONEncoder().encode(patch), as: UTF8.self)
            let result = patch_preferences(path, json)
            guard result.ok else { throw preferenceBridgeError(result.error_code.toString(), result.message_key.toString()) }
            return try JSONDecoder().decode(RustPreferencesPatchResult.self, from: Data(result.result_json.toString().utf8))
        }
    }
}

private func preferenceBridge<T>(_ directory: URL, _ operation: (String) throws -> T) -> Result<T, RustCoreError> {
    do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    catch { return .failure(preferenceBridgeError("io_failed", "clipboard.error.io_failed")) }
    do {
        return .success(try operation(directory.path))
    } catch let error as RustCoreError { return .failure(error) }
    catch { return .failure(preferenceBridgeError("invalid_input", "clipboard.error.invalid_input")) }
}

private func preferenceBridgeError(_ code: String, _ messageKey: String) -> RustCoreError {
    RustCoreError(code: code, messageKey: messageKey, recoverable: code != "invalid_input", message: code)
}
