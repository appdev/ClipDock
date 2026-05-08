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
    pub preview_asset_path: Option<String>,
    pub payload_asset_path: Option<String>,
    pub source_confidence: SourceConfidence,
    pub first_copied_at_ms: i64,
    pub last_copied_at_ms: i64,
    pub copy_count: i64,
    pub is_pinned: bool,
    pub size_bytes: i64,
    pub preview_state: PreviewState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceAppSummary {
    pub id: String,
    pub bundle_id: Option<String>,
    pub name: String,
    pub icon_path: Option<String>,
    pub item_count: i64,
    pub last_copied_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceAppPage {
    pub apps: Vec<SourceAppSummary>,
    pub total_count: i64,
    pub has_more: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemQuery {
    pub item_type: Option<ClipboardItemType>,
    pub source_app_id: Option<String>,
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
    pub source_bundle_id: Option<String>,
    pub source_app_name: Option<String>,
    pub source_bundle_path: Option<String>,
    pub source_icon_relative_path: Option<String>,
    pub source_confidence: SourceConfidence,
    pub pasteboard_change_count: i64,
    pub self_write_token: Option<String>,
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
pub struct CaptureFilesRequest {
    pub file_paths: Vec<String>,
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
    pub ignore_list: IgnoreListPreferences,
}

impl Default for PreferencesDocument {
    fn default() -> Self {
        Self {
            general: GeneralPreferences::default(),
            history: HistoryPreferences::default(),
            appearance: AppearancePreferences::default(),
            ignore_list: IgnoreListPreferences::default(),
        }
    }
}

impl PreferencesDocument {
    pub fn normalized(mut self) -> Self {
        self.general.default_panel_height = self.general.default_panel_height.clamp(260, 560);
        self.history.max_items = self.history.max_items.clamp(50, 5000);
        self.history.retention_days = self.history.retention_days.clamp(1, 365);
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
    #[serde(default)]
    pub record_files: bool,
}

impl Default for HistoryPreferences {
    fn default() -> Self {
        Self {
            max_items: default_max_items(),
            retention_days: default_retention_days(),
            record_images: true,
            record_files: false,
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct IgnoreListPreferences {
    #[serde(default)]
    pub ignored_app_identifiers: Vec<String>,
    #[serde(default)]
    pub window_title_keywords: Vec<String>,
    #[serde(default)]
    pub skip_unknown_source: bool,
}

fn default_true() -> bool {
    true
}

fn default_panel_height() -> i64 {
    320
}

fn default_max_items() -> i64 {
    500
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
