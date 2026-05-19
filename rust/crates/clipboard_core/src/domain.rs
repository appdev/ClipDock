use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClipboardItemType {
    Text,
    Link,
    Image,
    File,
    Color,
    RichText,
    Unknown,
}

impl ClipboardItemType {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Text => "text",
            Self::Link => "link",
            Self::Image => "image",
            Self::File => "file",
            Self::Color => "color",
            Self::RichText => "rich_text",
            Self::Unknown => "unknown",
        }
    }

    pub fn from_storage(value: &str) -> Self {
        match value {
            "text" => Self::Text,
            "link" => Self::Link,
            "image" => Self::Image,
            "file" => Self::File,
            "color" => Self::Color,
            "rich_text" => Self::RichText,
            _ => Self::Unknown,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceConfidence {
    High,
    Medium,
    Low,
    Unknown,
}

impl SourceConfidence {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::High => "high",
            Self::Medium => "medium",
            Self::Low => "low",
            Self::Unknown => "unknown",
        }
    }

    pub fn from_storage(value: &str) -> Self {
        match value {
            "high" => Self::High,
            "medium" => Self::Medium,
            "low" => Self::Low,
            _ => Self::Unknown,
        }
    }
}

impl Default for SourceConfidence {
    fn default() -> Self {
        Self::Unknown
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PreviewState {
    Ready,
    Deferred,
    TooLarge,
    MissingSource,
    Failed,
}

impl PreviewState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Deferred => "deferred",
            Self::TooLarge => "too_large",
            Self::MissingSource => "missing_source",
            Self::Failed => "failed",
        }
    }

    pub fn from_storage(value: &str) -> Self {
        match value {
            "ready" => Self::Ready,
            "deferred" => Self::Deferred,
            "too_large" => Self::TooLarge,
            "missing_source" => Self::MissingSource,
            "failed" => Self::Failed,
            _ => Self::Failed,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PayloadState {
    Pending,
    Ready,
    Failed,
}

impl PayloadState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Ready => "ready",
            Self::Failed => "failed",
        }
    }

    pub fn from_storage(value: &str) -> Self {
        match value {
            "pending" => Self::Pending,
            "ready" => Self::Ready,
            "failed" => Self::Failed,
            _ => Self::Ready,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LinkMetadataState {
    Pending,
    Fetching,
    Ready,
    Failed,
    Stale,
}

impl LinkMetadataState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Fetching => "fetching",
            Self::Ready => "ready",
            Self::Failed => "failed",
            Self::Stale => "stale",
        }
    }

    pub fn from_storage(value: &str) -> Self {
        match value {
            "pending" => Self::Pending,
            "fetching" => Self::Fetching,
            "ready" => Self::Ready,
            "failed" => Self::Failed,
            "stale" => Self::Stale,
            _ => Self::Failed,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkMetadataSummary {
    pub canonical_url: String,
    pub display_url: String,
    pub host: String,
    pub title: Option<String>,
    pub site_name: Option<String>,
    pub icon_asset_path: Option<String>,
    pub image_asset_path: Option<String>,
    pub metadata_state: LinkMetadataState,
    pub fetched_at_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkMetadataFetchCandidate {
    pub item_id: String,
    pub canonical_url: String,
    pub display_url: String,
    pub host: String,
    pub fetch_attempts: i64,
    pub lease_started_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompleteLinkMetadataFetchRequest {
    pub item_id: String,
    pub lease_started_at_ms: i64,
    pub canonical_url: String,
    pub display_url: String,
    pub host: String,
    pub title: Option<String>,
    pub site_name: Option<String>,
    pub icon_relative_path: Option<String>,
    pub image_relative_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipboardFileItemSummary {
    pub path: String,
    pub file_name: String,
    pub file_extension: Option<String>,
    pub byte_count: i64,
    pub is_directory: bool,
    pub width: Option<i64>,
    pub height: Option<i64>,
    pub content_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipboardItemSummary {
    pub id: String,
    pub item_type: ClipboardItemType,
    pub summary: String,
    pub primary_text: Option<String>,
    pub content_hash: String,
    pub source_app_id: Option<String>,
    pub source_app_name: Option<String>,
    pub source_app_icon_path: Option<String>,
    pub source_app_icon_header_color: Option<i64>,
    pub preview_asset_path: Option<String>,
    pub payload_asset_path: Option<String>,
    pub source_confidence: SourceConfidence,
    pub first_copied_at_ms: i64,
    pub last_copied_at_ms: i64,
    pub copy_count: i64,
    pub is_pinned: bool,
    pub size_bytes: i64,
    pub preview_state: PreviewState,
    pub payload_state: PayloadState,
    pub file_items: Vec<ClipboardFileItemSummary>,
    pub link_metadata: Option<LinkMetadataSummary>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceAppSummary {
    pub id: String,
    pub bundle_id: Option<String>,
    pub name: String,
    pub icon_path: Option<String>,
    pub icon_header_color: Option<i64>,
    pub item_count: i64,
    pub last_copied_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceAppPage {
    pub apps: Vec<SourceAppSummary>,
    pub total_count: i64,
    pub has_more: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PinboardSummary {
    pub id: String,
    pub title: String,
    pub color_code: i64,
    pub sort_order: i64,
    pub item_count: i64,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PinboardPage {
    pub pinboards: Vec<PinboardSummary>,
    pub total_count: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemQuery {
    pub item_type: Option<ClipboardItemType>,
    pub source_app_id: Option<String>,
    pub pinboard_id: Option<String>,
    pub search_text: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PageRequest {
    pub limit: i64,
    pub offset: i64,
}

impl Default for PageRequest {
    fn default() -> Self {
        Self {
            limit: 50,
            offset: 0,
        }
    }
}

impl PageRequest {
    pub fn normalized(self) -> Self {
        Self {
            limit: self.limit.clamp(1, 200),
            offset: self.offset.max(0),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemPage {
    pub items: Vec<ClipboardItemSummary>,
    pub total_count: i64,
    pub has_more: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreInfo {
    pub database_path: String,
    pub schema_version: i64,
    pub item_count: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct MaintenanceResult {
    pub purged_item_count: i64,
    pub deleted_asset_row_count: i64,
    pub deleted_asset_file_count: i64,
    pub deleted_orphan_file_count: i64,
    pub reclaimed_bytes: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ItemManagementResult {
    pub affected_count: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureTextRequest {
    pub text: String,
    pub detected_link: Option<CaptureDetectedLink>,
    pub display_rtf_relative_path: Option<String>,
    pub display_rtf_mime_type: Option<String>,
    pub display_rtf_byte_count: i64,
    pub source_bundle_id: Option<String>,
    pub source_app_name: Option<String>,
    pub source_bundle_path: Option<String>,
    pub source_icon_relative_path: Option<String>,
    pub source_confidence: SourceConfidence,
    pub pasteboard_change_count: i64,
    pub self_write_token: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureRichTextRequest {
    pub text: String,
    pub rtf_relative_path: String,
    pub mime_type: Option<String>,
    pub byte_count: i64,
    pub content_hash: Option<String>,
    pub source_bundle_id: Option<String>,
    pub source_app_name: Option<String>,
    pub source_bundle_path: Option<String>,
    pub source_icon_relative_path: Option<String>,
    pub source_confidence: SourceConfidence,
    pub pasteboard_change_count: i64,
    pub self_write_token: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureDetectedLink {
    pub original_text: String,
    pub canonical_url: String,
    pub display_url: String,
    pub host: String,
    pub metadata_state: LinkMetadataState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureImageRequest {
    pub payload_relative_path: String,
    pub preview_relative_path: Option<String>,
    pub mime_type: Option<String>,
    pub width: i64,
    pub height: i64,
    pub byte_count: i64,
    pub source_bundle_id: Option<String>,
    pub source_app_name: Option<String>,
    pub source_bundle_path: Option<String>,
    pub source_icon_relative_path: Option<String>,
    pub source_confidence: SourceConfidence,
    pub pasteboard_change_count: i64,
    pub self_write_token: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapturePendingImageRequest {
    pub owner_session_id: String,
    pub thumbnail_relative_path: String,
    pub reserved_payload_relative_path: String,
    pub staged_payload_relative_path: String,
    pub mime_type: String,
    pub width: i64,
    pub height: i64,
    pub thumbnail_width: i64,
    pub thumbnail_height: i64,
    pub thumbnail_byte_count: i64,
    pub source_bundle_id: Option<String>,
    pub source_app_name: Option<String>,
    pub source_bundle_path: Option<String>,
    pub source_icon_relative_path: Option<String>,
    pub source_confidence: SourceConfidence,
    pub pasteboard_change_count: i64,
    pub self_write_token: Option<String>,
    pub lease_duration_ms: Option<i64>,
    pub cleanup_after_duration_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingImageCaptureResult {
    pub job_id: String,
    pub item_id: String,
    pub content_hash: String,
    pub copy_count: i64,
    pub inserted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompletePendingImagePayloadRequest {
    pub job_id: String,
    pub staged_payload_relative_path: String,
    pub mime_type: String,
    pub width: i64,
    pub height: i64,
    pub byte_count: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FailPendingImagePayloadRequest {
    pub job_id: String,
    pub staged_payload_relative_path: Option<String>,
    pub failure_code: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecoverPendingImagesRequest {
    pub owner_session_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingImageCompletionResult {
    pub status: String,
    pub job_id: Option<String>,
    pub item_id: Option<String>,
    pub effective_item_id: Option<String>,
    pub content_hash: Option<String>,
    pub cleaned_relative_paths: Vec<String>,
    pub affected_count: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureFilesRequest {
    pub file_paths: Vec<String>,
    pub file_items: Vec<CapturedFileMetadata>,
    pub preview_relative_path: Option<String>,
    pub preview_mime_type: Option<String>,
    pub preview_width: Option<i64>,
    pub preview_height: Option<i64>,
    pub preview_byte_count: i64,
    pub snapshot_relative_path: Option<String>,
    pub snapshot_byte_count: i64,
    pub source_bundle_id: Option<String>,
    pub source_app_name: Option<String>,
    pub source_bundle_path: Option<String>,
    pub source_icon_relative_path: Option<String>,
    pub source_confidence: SourceConfidence,
    pub pasteboard_change_count: i64,
    pub self_write_token: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapturedFileMetadata {
    pub path: String,
    pub file_name: String,
    pub file_extension: Option<String>,
    pub byte_count: i64,
    pub is_directory: bool,
    pub width: Option<i64>,
    pub height: Option<i64>,
    pub content_type: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureResult {
    pub item_id: String,
    pub content_hash: String,
    pub copy_count: i64,
    pub inserted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PreferencesDocument {
    #[serde(default)]
    pub general: GeneralPreferences,
    #[serde(default)]
    pub history: HistoryPreferences,
    #[serde(default)]
    pub appearance: AppearancePreferences,
    #[serde(default)]
    pub link_preview: LinkPreviewPreferences,
    #[serde(default)]
    pub shortcuts: ShortcutsPreferences,
    #[serde(default)]
    pub ignore_list: IgnoreListPreferences,
}

impl Default for PreferencesDocument {
    fn default() -> Self {
        Self {
            general: GeneralPreferences::default(),
            history: HistoryPreferences::default(),
            appearance: AppearancePreferences::default(),
            link_preview: LinkPreviewPreferences::default(),
            shortcuts: ShortcutsPreferences::default(),
            ignore_list: IgnoreListPreferences::default(),
        }
    }
}

impl PreferencesDocument {
    pub fn normalized(mut self) -> Self {
        self.general.default_panel_height = self.general.default_panel_height.clamp(260, 560);
        self.history.max_items = default_max_items();
        self.history.retention_days = self.history.retention_days.clamp(1, 365);
        self.history.record_images = true;
        self.history.record_files = true;
        self.appearance.mode = normalized_choice(
            &self.appearance.mode,
            &["light", "dark", "system"],
            "system",
        );
        self.appearance.item_density = normalized_choice(
            &self.appearance.item_density,
            &["compact", "standard"],
            "standard",
        );
        self.shortcuts.open_panel = normalize_keyboard_shortcut(self.shortcuts.open_panel);
        self.ignore_list.ignored_app_identifiers =
            normalize_string_list(self.ignore_list.ignored_app_identifiers, 64, 120);
        self.ignore_list.window_title_keywords =
            normalize_string_list(self.ignore_list.window_title_keywords, 64, 80);
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GeneralPreferences {
    #[serde(default)]
    pub launch_at_login: bool,
    #[serde(default = "default_true")]
    pub show_menu_bar_item: bool,
    #[serde(default = "default_panel_height")]
    pub default_panel_height: i64,
}

impl Default for GeneralPreferences {
    fn default() -> Self {
        Self {
            launch_at_login: false,
            show_menu_bar_item: true,
            default_panel_height: default_panel_height(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoryPreferences {
    #[serde(default = "default_max_items")]
    pub max_items: i64,
    #[serde(default = "default_retention_days")]
    pub retention_days: i64,
    #[serde(default = "default_true")]
    pub record_images: bool,
    #[serde(default = "default_true")]
    pub record_files: bool,
}

impl Default for HistoryPreferences {
    fn default() -> Self {
        Self {
            max_items: default_max_items(),
            retention_days: default_retention_days(),
            record_images: true,
            record_files: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppearancePreferences {
    #[serde(default = "default_appearance_mode")]
    pub mode: String,
    #[serde(default = "default_item_density")]
    pub item_density: String,
    #[serde(default = "default_true")]
    pub preview_popover_enabled: bool,
}

impl Default for AppearancePreferences {
    fn default() -> Self {
        Self {
            mode: default_appearance_mode(),
            item_density: default_item_density(),
            preview_popover_enabled: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShortcutsPreferences {
    #[serde(default = "default_open_panel_shortcut")]
    pub open_panel: KeyboardShortcut,
    #[serde(default)]
    pub paste_directly_to_target: bool,
    #[serde(default)]
    pub always_paste_as_plain_text: bool,
}

impl Default for ShortcutsPreferences {
    fn default() -> Self {
        Self {
            open_panel: default_open_panel_shortcut(),
            paste_directly_to_target: false,
            always_paste_as_plain_text: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeyboardShortcut {
    #[serde(default = "default_open_panel_key_code")]
    pub key_code: i64,
    #[serde(default = "default_open_panel_modifiers")]
    pub modifiers: Vec<String>,
}

impl Default for KeyboardShortcut {
    fn default() -> Self {
        default_open_panel_shortcut()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkPreviewPreferences {
    #[serde(default = "default_true")]
    pub web_preview_enabled: bool,
}

impl Default for LinkPreviewPreferences {
    fn default() -> Self {
        Self {
            web_preview_enabled: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IgnoreListPreferences {
    #[serde(default = "default_ignored_app_identifiers")]
    pub ignored_app_identifiers: Vec<String>,
    #[serde(default)]
    pub window_title_keywords: Vec<String>,
    #[serde(default)]
    pub skip_unknown_source: bool,
}

impl Default for IgnoreListPreferences {
    fn default() -> Self {
        Self {
            ignored_app_identifiers: default_ignored_app_identifiers(),
            window_title_keywords: Vec::new(),
            skip_unknown_source: false,
        }
    }
}

fn default_ignored_app_identifiers() -> Vec<String> {
    vec![
        "com.apple.Passwords".to_string(),
        "com.apple.keychainaccess".to_string(),
    ]
}

fn default_true() -> bool {
    true
}

fn default_panel_height() -> i64 {
    320
}

fn default_max_items() -> i64 {
    5000
}

fn default_retention_days() -> i64 {
    30
}

fn default_appearance_mode() -> String {
    "system".to_string()
}

fn default_item_density() -> String {
    "standard".to_string()
}

fn default_open_panel_shortcut() -> KeyboardShortcut {
    KeyboardShortcut {
        key_code: default_open_panel_key_code(),
        modifiers: default_open_panel_modifiers(),
    }
}

fn default_open_panel_key_code() -> i64 {
    7
}

fn default_open_panel_modifiers() -> Vec<String> {
    vec!["command".to_string(), "shift".to_string()]
}

fn normalize_keyboard_shortcut(shortcut: KeyboardShortcut) -> KeyboardShortcut {
    if !(0..=127).contains(&shortcut.key_code) {
        return default_open_panel_shortcut();
    }

    let modifiers = normalize_shortcut_modifiers(shortcut.modifiers);
    let has_required_modifier = modifiers
        .iter()
        .any(|modifier| matches!(modifier.as_str(), "command" | "option" | "control"));
    if !has_required_modifier {
        return default_open_panel_shortcut();
    }

    KeyboardShortcut {
        key_code: shortcut.key_code,
        modifiers,
    }
}

fn normalize_shortcut_modifiers(modifiers: Vec<String>) -> Vec<String> {
    let mut normalized = Vec::new();
    for canonical in ["command", "option", "control", "shift"] {
        if modifiers
            .iter()
            .filter_map(|modifier| canonical_shortcut_modifier(modifier))
            .any(|modifier| modifier == canonical)
        {
            normalized.push(canonical.to_string());
        }
    }
    normalized
}

fn canonical_shortcut_modifier(modifier: &str) -> Option<&'static str> {
    match modifier.trim().to_ascii_lowercase().as_str() {
        "command" | "cmd" | "meta" => Some("command"),
        "option" | "alt" => Some("option"),
        "control" | "ctrl" => Some("control"),
        "shift" => Some("shift"),
        _ => None,
    }
}

fn normalized_choice(value: &str, allowed: &[&str], fallback: &str) -> String {
    let value = value.trim();
    if allowed.contains(&value) {
        value.to_string()
    } else {
        fallback.to_string()
    }
}

fn normalize_string_list(
    values: Vec<String>,
    maximum_count: usize,
    maximum_length: usize,
) -> Vec<String> {
    let mut normalized_values = Vec::new();
    for value in values {
        let normalized = value
            .trim_matches(|character: char| character == '\0')
            .trim()
            .chars()
            .take(maximum_length)
            .collect::<String>();
        if normalized.is_empty() {
            continue;
        }

        if normalized_values
            .iter()
            .any(|existing: &String| existing.eq_ignore_ascii_case(&normalized))
        {
            continue;
        }

        normalized_values.push(normalized);
        if normalized_values.len() >= maximum_count {
            break;
        }
    }

    normalized_values
}
