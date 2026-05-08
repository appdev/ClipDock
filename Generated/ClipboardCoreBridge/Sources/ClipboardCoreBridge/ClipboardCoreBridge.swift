import RustXcframework
public func open_core<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString) -> CoreOpenResult {
    __swift_bridge__$open_core({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func run_maintenance<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString) -> CoreMaintenanceResult {
    __swift_bridge__$run_maintenance({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func get_preferences<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString) -> CorePreferencesResult {
    __swift_bridge__$get_preferences({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func update_preferences<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ preferences_json: GenericIntoRustString) -> CorePreferencesResult {
    __swift_bridge__$update_preferences({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = preferences_json.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func list_items<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ limit: Int64, _ offset: Int64, _ item_type: GenericIntoRustString, _ source_app_id: GenericIntoRustString, _ search_text: GenericIntoRustString) -> CoreListResult {
    __swift_bridge__$list_items({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), limit, offset, { let rustString = item_type.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_app_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = search_text.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func list_source_apps<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ limit: Int64, _ offset: Int64) -> CoreSourceAppsResult {
    __swift_bridge__$list_source_apps({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), limit, offset).intoSwiftRepr()
}
public func set_item_pinned<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ item_id: GenericIntoRustString, _ is_pinned: Bool) -> CoreItemManagementResult {
    __swift_bridge__$set_item_pinned({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = item_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), is_pinned).intoSwiftRepr()
}
public func delete_item<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ item_id: GenericIntoRustString) -> CoreItemManagementResult {
    __swift_bridge__$delete_item({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = item_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func clear_items<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ item_type: GenericIntoRustString, _ source_app_id: GenericIntoRustString, _ search_text: GenericIntoRustString) -> CoreItemManagementResult {
    __swift_bridge__$clear_items({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = item_type.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_app_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = search_text.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func capture_text<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ text: GenericIntoRustString, _ source_bundle_id: GenericIntoRustString, _ source_app_name: GenericIntoRustString, _ source_bundle_path: GenericIntoRustString, _ source_icon_relative_path: GenericIntoRustString, _ source_confidence: GenericIntoRustString, _ pasteboard_change_count: Int64, _ self_write_token: GenericIntoRustString) -> CoreCaptureResult {
    __swift_bridge__$capture_text({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = text.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_bundle_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_app_name.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_bundle_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_icon_relative_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_confidence.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), pasteboard_change_count, { let rustString = self_write_token.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func capture_image<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ payload_relative_path: GenericIntoRustString, _ preview_relative_path: GenericIntoRustString, _ mime_type: GenericIntoRustString, _ width: Int64, _ height: Int64, _ byte_count: Int64, _ source_bundle_id: GenericIntoRustString, _ source_app_name: GenericIntoRustString, _ source_bundle_path: GenericIntoRustString, _ source_icon_relative_path: GenericIntoRustString, _ source_confidence: GenericIntoRustString, _ pasteboard_change_count: Int64, _ self_write_token: GenericIntoRustString) -> CoreCaptureResult {
    __swift_bridge__$capture_image({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = payload_relative_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = preview_relative_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = mime_type.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), width, height, byte_count, { let rustString = source_bundle_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_app_name.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_bundle_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_icon_relative_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_confidence.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), pasteboard_change_count, { let rustString = self_write_token.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func capture_files<GenericIntoRustString: IntoRustString>(_ app_support_dir: GenericIntoRustString, _ files_json: GenericIntoRustString, _ snapshot_relative_path: GenericIntoRustString, _ snapshot_byte_count: Int64, _ source_bundle_id: GenericIntoRustString, _ source_app_name: GenericIntoRustString, _ source_bundle_path: GenericIntoRustString, _ source_icon_relative_path: GenericIntoRustString, _ source_confidence: GenericIntoRustString, _ pasteboard_change_count: Int64, _ self_write_token: GenericIntoRustString) -> CoreCaptureResult {
    __swift_bridge__$capture_files({ let rustString = app_support_dir.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = files_json.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = snapshot_relative_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), snapshot_byte_count, { let rustString = source_bundle_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_app_name.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_bundle_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_icon_relative_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = source_confidence.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), pasteboard_change_count, { let rustString = self_write_token.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public struct CoreOpenResult {
    public var ok: Bool
    public var database_path: RustString
    public var schema_version: Int64
    public var item_count: Int64
    public var error_code: RustString
    public var message_key: RustString

    public init(ok: Bool,database_path: RustString,schema_version: Int64,item_count: Int64,error_code: RustString,message_key: RustString) {
        self.ok = ok
        self.database_path = database_path
        self.schema_version = schema_version
        self.item_count = item_count
        self.error_code = error_code
        self.message_key = message_key
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$CoreOpenResult {
        { let val = self; return __swift_bridge__$CoreOpenResult(ok: val.ok, database_path: { let rustString = val.database_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), schema_version: val.schema_version, item_count: val.item_count, error_code: { let rustString = val.error_code.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), message_key: { let rustString = val.message_key.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$CoreOpenResult {
    @inline(__always)
    func intoSwiftRepr() -> CoreOpenResult {
        { let val = self; return CoreOpenResult(ok: val.ok, database_path: RustString(ptr: val.database_path), schema_version: val.schema_version, item_count: val.item_count, error_code: RustString(ptr: val.error_code), message_key: RustString(ptr: val.message_key)); }()
    }
}
extension __swift_bridge__$Option$CoreOpenResult {
    @inline(__always)
    func intoSwiftRepr() -> Optional<CoreOpenResult> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<CoreOpenResult>) -> __swift_bridge__$Option$CoreOpenResult {
        if let v = val {
            return __swift_bridge__$Option$CoreOpenResult(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$CoreOpenResult(is_some: false, val: __swift_bridge__$CoreOpenResult())
        }
    }
}
public struct CoreListResult {
    public var ok: Bool
    public var total_count: Int64
    public var has_more: Bool
    public var items_json: RustString
    public var error_code: RustString
    public var message_key: RustString

    public init(ok: Bool,total_count: Int64,has_more: Bool,items_json: RustString,error_code: RustString,message_key: RustString) {
        self.ok = ok
        self.total_count = total_count
        self.has_more = has_more
        self.items_json = items_json
        self.error_code = error_code
        self.message_key = message_key
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$CoreListResult {
        { let val = self; return __swift_bridge__$CoreListResult(ok: val.ok, total_count: val.total_count, has_more: val.has_more, items_json: { let rustString = val.items_json.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), error_code: { let rustString = val.error_code.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), message_key: { let rustString = val.message_key.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$CoreListResult {
    @inline(__always)
    func intoSwiftRepr() -> CoreListResult {
        { let val = self; return CoreListResult(ok: val.ok, total_count: val.total_count, has_more: val.has_more, items_json: RustString(ptr: val.items_json), error_code: RustString(ptr: val.error_code), message_key: RustString(ptr: val.message_key)); }()
    }
}
extension __swift_bridge__$Option$CoreListResult {
    @inline(__always)
    func intoSwiftRepr() -> Optional<CoreListResult> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<CoreListResult>) -> __swift_bridge__$Option$CoreListResult {
        if let v = val {
            return __swift_bridge__$Option$CoreListResult(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$CoreListResult(is_some: false, val: __swift_bridge__$CoreListResult())
        }
    }
}
public struct CoreSourceAppsResult {
    public var ok: Bool
    public var total_count: Int64
    public var has_more: Bool
    public var apps_json: RustString
    public var error_code: RustString
    public var message_key: RustString

    public init(ok: Bool,total_count: Int64,has_more: Bool,apps_json: RustString,error_code: RustString,message_key: RustString) {
        self.ok = ok
        self.total_count = total_count
        self.has_more = has_more
        self.apps_json = apps_json
        self.error_code = error_code
        self.message_key = message_key
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$CoreSourceAppsResult {
        { let val = self; return __swift_bridge__$CoreSourceAppsResult(ok: val.ok, total_count: val.total_count, has_more: val.has_more, apps_json: { let rustString = val.apps_json.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), error_code: { let rustString = val.error_code.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), message_key: { let rustString = val.message_key.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$CoreSourceAppsResult {
    @inline(__always)
    func intoSwiftRepr() -> CoreSourceAppsResult {
        { let val = self; return CoreSourceAppsResult(ok: val.ok, total_count: val.total_count, has_more: val.has_more, apps_json: RustString(ptr: val.apps_json), error_code: RustString(ptr: val.error_code), message_key: RustString(ptr: val.message_key)); }()
    }
}
extension __swift_bridge__$Option$CoreSourceAppsResult {
    @inline(__always)
    func intoSwiftRepr() -> Optional<CoreSourceAppsResult> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<CoreSourceAppsResult>) -> __swift_bridge__$Option$CoreSourceAppsResult {
        if let v = val {
            return __swift_bridge__$Option$CoreSourceAppsResult(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$CoreSourceAppsResult(is_some: false, val: __swift_bridge__$CoreSourceAppsResult())
        }
    }
}
public struct CoreCaptureResult {
    public var ok: Bool
    public var item_id: RustString
    public var content_hash: RustString
    public var copy_count: Int64
    public var inserted: Bool
    public var error_code: RustString
    public var message_key: RustString

    public init(ok: Bool,item_id: RustString,content_hash: RustString,copy_count: Int64,inserted: Bool,error_code: RustString,message_key: RustString) {
        self.ok = ok
        self.item_id = item_id
        self.content_hash = content_hash
        self.copy_count = copy_count
        self.inserted = inserted
        self.error_code = error_code
        self.message_key = message_key
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$CoreCaptureResult {
        { let val = self; return __swift_bridge__$CoreCaptureResult(ok: val.ok, item_id: { let rustString = val.item_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), content_hash: { let rustString = val.content_hash.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), copy_count: val.copy_count, inserted: val.inserted, error_code: { let rustString = val.error_code.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), message_key: { let rustString = val.message_key.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$CoreCaptureResult {
    @inline(__always)
    func intoSwiftRepr() -> CoreCaptureResult {
        { let val = self; return CoreCaptureResult(ok: val.ok, item_id: RustString(ptr: val.item_id), content_hash: RustString(ptr: val.content_hash), copy_count: val.copy_count, inserted: val.inserted, error_code: RustString(ptr: val.error_code), message_key: RustString(ptr: val.message_key)); }()
    }
}
extension __swift_bridge__$Option$CoreCaptureResult {
    @inline(__always)
    func intoSwiftRepr() -> Optional<CoreCaptureResult> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<CoreCaptureResult>) -> __swift_bridge__$Option$CoreCaptureResult {
        if let v = val {
            return __swift_bridge__$Option$CoreCaptureResult(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$CoreCaptureResult(is_some: false, val: __swift_bridge__$CoreCaptureResult())
        }
    }
}
public struct CorePreferencesResult {
    public var ok: Bool
    public var schema_version: Int64
    public var preferences_json: RustString
    public var error_code: RustString
    public var message_key: RustString

    public init(ok: Bool,schema_version: Int64,preferences_json: RustString,error_code: RustString,message_key: RustString) {
        self.ok = ok
        self.schema_version = schema_version
        self.preferences_json = preferences_json
        self.error_code = error_code
        self.message_key = message_key
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$CorePreferencesResult {
        { let val = self; return __swift_bridge__$CorePreferencesResult(ok: val.ok, schema_version: val.schema_version, preferences_json: { let rustString = val.preferences_json.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), error_code: { let rustString = val.error_code.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), message_key: { let rustString = val.message_key.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$CorePreferencesResult {
    @inline(__always)
    func intoSwiftRepr() -> CorePreferencesResult {
        { let val = self; return CorePreferencesResult(ok: val.ok, schema_version: val.schema_version, preferences_json: RustString(ptr: val.preferences_json), error_code: RustString(ptr: val.error_code), message_key: RustString(ptr: val.message_key)); }()
    }
}
extension __swift_bridge__$Option$CorePreferencesResult {
    @inline(__always)
    func intoSwiftRepr() -> Optional<CorePreferencesResult> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<CorePreferencesResult>) -> __swift_bridge__$Option$CorePreferencesResult {
        if let v = val {
            return __swift_bridge__$Option$CorePreferencesResult(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$CorePreferencesResult(is_some: false, val: __swift_bridge__$CorePreferencesResult())
        }
    }
}
public struct CoreMaintenanceResult {
    public var ok: Bool
    public var purged_item_count: Int64
    public var deleted_asset_row_count: Int64
    public var deleted_asset_file_count: Int64
    public var deleted_orphan_file_count: Int64
    public var reclaimed_bytes: Int64
    public var error_code: RustString
    public var message_key: RustString

    public init(ok: Bool,purged_item_count: Int64,deleted_asset_row_count: Int64,deleted_asset_file_count: Int64,deleted_orphan_file_count: Int64,reclaimed_bytes: Int64,error_code: RustString,message_key: RustString) {
        self.ok = ok
        self.purged_item_count = purged_item_count
        self.deleted_asset_row_count = deleted_asset_row_count
        self.deleted_asset_file_count = deleted_asset_file_count
        self.deleted_orphan_file_count = deleted_orphan_file_count
        self.reclaimed_bytes = reclaimed_bytes
        self.error_code = error_code
        self.message_key = message_key
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$CoreMaintenanceResult {
        { let val = self; return __swift_bridge__$CoreMaintenanceResult(ok: val.ok, purged_item_count: val.purged_item_count, deleted_asset_row_count: val.deleted_asset_row_count, deleted_asset_file_count: val.deleted_asset_file_count, deleted_orphan_file_count: val.deleted_orphan_file_count, reclaimed_bytes: val.reclaimed_bytes, error_code: { let rustString = val.error_code.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), message_key: { let rustString = val.message_key.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$CoreMaintenanceResult {
    @inline(__always)
    func intoSwiftRepr() -> CoreMaintenanceResult {
        { let val = self; return CoreMaintenanceResult(ok: val.ok, purged_item_count: val.purged_item_count, deleted_asset_row_count: val.deleted_asset_row_count, deleted_asset_file_count: val.deleted_asset_file_count, deleted_orphan_file_count: val.deleted_orphan_file_count, reclaimed_bytes: val.reclaimed_bytes, error_code: RustString(ptr: val.error_code), message_key: RustString(ptr: val.message_key)); }()
    }
}
extension __swift_bridge__$Option$CoreMaintenanceResult {
    @inline(__always)
    func intoSwiftRepr() -> Optional<CoreMaintenanceResult> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<CoreMaintenanceResult>) -> __swift_bridge__$Option$CoreMaintenanceResult {
        if let v = val {
            return __swift_bridge__$Option$CoreMaintenanceResult(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$CoreMaintenanceResult(is_some: false, val: __swift_bridge__$CoreMaintenanceResult())
        }
    }
}
public struct CoreItemManagementResult {
    public var ok: Bool
    public var affected_count: Int64
    public var error_code: RustString
    public var message_key: RustString

    public init(ok: Bool,affected_count: Int64,error_code: RustString,message_key: RustString) {
        self.ok = ok
        self.affected_count = affected_count
        self.error_code = error_code
        self.message_key = message_key
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$CoreItemManagementResult {
        { let val = self; return __swift_bridge__$CoreItemManagementResult(ok: val.ok, affected_count: val.affected_count, error_code: { let rustString = val.error_code.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), message_key: { let rustString = val.message_key.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$CoreItemManagementResult {
    @inline(__always)
    func intoSwiftRepr() -> CoreItemManagementResult {
        { let val = self; return CoreItemManagementResult(ok: val.ok, affected_count: val.affected_count, error_code: RustString(ptr: val.error_code), message_key: RustString(ptr: val.message_key)); }()
    }
}
extension __swift_bridge__$Option$CoreItemManagementResult {
    @inline(__always)
    func intoSwiftRepr() -> Optional<CoreItemManagementResult> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<CoreItemManagementResult>) -> __swift_bridge__$Option$CoreItemManagementResult {
        if let v = val {
            return __swift_bridge__$Option$CoreItemManagementResult(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$CoreItemManagementResult(is_some: false, val: __swift_bridge__$CoreItemManagementResult())
        }
    }
}


