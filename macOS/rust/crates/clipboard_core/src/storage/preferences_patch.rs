use super::preferences::parse_preferences_document;
use super::ClipboardCore;
use crate::domain::PreferencesDocument;
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use rusqlite::{params, TransactionBehavior};
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeSet;

// Omission means keep; a present null is invalid. Shortcut clearing is explicit.
fn present<'de, D, T>(deserializer: D) -> std::result::Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    T::deserialize(deserializer).map(Some)
}

macro_rules! patch_fields {
    ($name:ident { $($field:ident : $ty:ty),* $(,)? }) => {
        #[derive(Debug, Clone, Default, Serialize, Deserialize)]
        #[serde(deny_unknown_fields)]
        pub struct $name {
            $(#[serde(default, deserialize_with = "present", skip_serializing_if = "Option::is_none")]
            pub $field: Option<$ty>,)*
        }
    };
}

patch_fields!(PreferencesPatch {
    general: GeneralPreferencesPatch,
    history: HistoryPreferencesPatch,
    appearance: AppearancePreferencesPatch,
    link_preview: LinkPreviewPreferencesPatch,
    shortcuts: ShortcutsPreferencesPatch,
    ignore_list: IgnoreListPreferencesPatch,
});
patch_fields!(GeneralPreferencesPatch {
    launch_at_login: bool,
    show_menu_bar_item: bool,
    copy_completion_hud_enabled: bool,
    external_copy_sound_enabled: bool,
    default_panel_height: i64,
});
patch_fields!(HistoryPreferencesPatch {
    retention_days: i64,
    retention_forever: bool
});
patch_fields!(AppearancePreferencesPatch {
    mode: String,
    item_density: String,
    preview_popover_enabled: bool,
});
patch_fields!(LinkPreviewPreferencesPatch {
    web_preview_enabled: bool
});
patch_fields!(IgnoreListPreferencesPatch {
    ignored_app_identifiers: Vec<String>,
    window_title_keywords: Vec<String>,
    skip_unknown_source: bool,
});
patch_fields!(ShortcutsPreferencesPatch {
    open_panel: ShortcutPatch,
    previous_pinboard: ShortcutPatch,
    next_pinboard: ShortcutPatch,
    quick_paste_modifier: String,
    plain_text_modifier: String,
    paste_directly_to_target: bool,
    always_paste_as_plain_text: bool,
});

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum ShortcutPatch {
    Set { value: ShortcutPatchValue },
    Clear,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ShortcutPatchValue {
    pub key_code: i64,
    pub modifiers: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PreferencesMaintenanceStatus {
    NotNeeded,
    Applied,
    Warning,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreferencesMaintenance {
    pub status: PreferencesMaintenanceStatus,
    pub stage: Option<String>,
    pub code: Option<String>,
    pub may_have_changed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreferencesPatchResult {
    pub document: PreferencesDocument,
    pub changed_sections: Vec<String>,
    pub maintenance: PreferencesMaintenance,
}

struct LeafChange {
    section: &'static str,
    field: &'static str,
    value: Value,
}

fn invalid(message: impl Into<String>) -> CoreError {
    CoreError::new(CoreErrorCode::InvalidInput, message)
}

fn add<T: Serialize>(
    changes: &mut Vec<LeafChange>,
    section: &'static str,
    field: &'static str,
    value: Option<T>,
) -> Result<()> {
    if let Some(value) = value {
        changes.push(LeafChange {
            section,
            field,
            value: serde_json::to_value(value).map_err(|e| invalid(e.to_string()))?,
        });
    }
    Ok(())
}

fn choice(value: String, allowed: &[&str]) -> Result<String> {
    let value = value.trim();
    if allowed.contains(&value) {
        Ok(value.to_string())
    } else {
        Err(invalid("unsupported preference value"))
    }
}

fn modifier(value: &str) -> Result<&'static str> {
    match value.trim().to_ascii_lowercase().as_str() {
        "command" | "cmd" | "meta" => Ok("command"),
        "option" | "alt" => Ok("option"),
        "control" | "ctrl" => Ok("control"),
        "shift" => Ok("shift"),
        _ => Err(invalid("unsupported shortcut modifier")),
    }
}

fn normalize_rules(rules: Vec<String>, max_length: usize) -> Result<Vec<String>> {
    if rules.len() > 64 || rules.iter().any(|r| r.chars().count() > max_length) {
        return Err(invalid("preference rule limit exceeded"));
    }
    let mut result: Vec<String> = Vec::new();
    for rule in rules {
        let rule = rule.trim_matches('\0').trim();
        if !rule.is_empty() && !result.iter().any(|r| r.eq_ignore_ascii_case(rule)) {
            result.push(rule.to_string());
        }
    }
    Ok(result)
}

fn shortcut_value(patch: ShortcutPatch) -> Result<Value> {
    match patch {
        ShortcutPatch::Clear => Ok(Value::Null),
        ShortcutPatch::Set { value } => {
            if !(0..=127).contains(&value.key_code) {
                return Err(invalid("shortcut key code must be in 0...127"));
            }
            let modifiers = value
                .modifiers
                .iter()
                .map(|v| modifier(v))
                .collect::<Result<Vec<_>>>()?;
            if !modifiers
                .iter()
                .any(|v| ["command", "control", "option"].contains(v))
            {
                return Err(invalid("shortcut requires command, control or option"));
            }
            let ordered: Vec<_> = ["command", "option", "control", "shift"]
                .into_iter()
                .filter(|v| modifiers.contains(v))
                .collect();
            Ok(serde_json::json!({"key_code": value.key_code, "modifiers": ordered}))
        }
    }
}

impl PreferencesPatch {
    fn changes(self) -> Result<Vec<LeafChange>> {
        let mut c = Vec::new();
        if let Some(p) = self.general {
            if p.default_panel_height.is_some_and(|height| height < 260) {
                return Err(invalid("default panel height must be at least 260"));
            }
            add(&mut c, "general", "launch_at_login", p.launch_at_login)?;
            add(
                &mut c,
                "general",
                "show_menu_bar_item",
                p.show_menu_bar_item,
            )?;
            add(
                &mut c,
                "general",
                "copy_completion_hud_enabled",
                p.copy_completion_hud_enabled,
            )?;
            add(
                &mut c,
                "general",
                "external_copy_sound_enabled",
                p.external_copy_sound_enabled,
            )?;
            add(
                &mut c,
                "general",
                "default_panel_height",
                p.default_panel_height,
            )?;
        }
        if let Some(p) = self.history {
            if p.retention_days
                .is_some_and(|days| !(1..=365).contains(&days))
            {
                return Err(invalid("retention days must be in 1...365"));
            }
            add(&mut c, "history", "retention_days", p.retention_days)?;
            add(&mut c, "history", "retention_forever", p.retention_forever)?;
        }
        if let Some(p) = self.appearance {
            add(
                &mut c,
                "appearance",
                "mode",
                p.mode
                    .map(|v| choice(v, &["light", "dark", "system"]))
                    .transpose()?,
            )?;
            add(
                &mut c,
                "appearance",
                "item_density",
                p.item_density
                    .map(|v| choice(v, &["compact", "standard"]))
                    .transpose()?,
            )?;
            add(
                &mut c,
                "appearance",
                "preview_popover_enabled",
                p.preview_popover_enabled,
            )?;
        }
        if let Some(p) = self.link_preview {
            add(
                &mut c,
                "link_preview",
                "web_preview_enabled",
                p.web_preview_enabled,
            )?;
        }
        if let Some(p) = self.ignore_list {
            add(
                &mut c,
                "ignore_list",
                "ignored_app_identifiers",
                p.ignored_app_identifiers
                    .map(|v| normalize_rules(v, 120))
                    .transpose()?,
            )?;
            add(
                &mut c,
                "ignore_list",
                "window_title_keywords",
                p.window_title_keywords
                    .map(|v| normalize_rules(v, 80))
                    .transpose()?,
            )?;
            add(
                &mut c,
                "ignore_list",
                "skip_unknown_source",
                p.skip_unknown_source,
            )?;
        }
        if let Some(p) = self.shortcuts {
            add(
                &mut c,
                "shortcuts",
                "open_panel",
                p.open_panel.map(shortcut_value).transpose()?,
            )?;
            add(
                &mut c,
                "shortcuts",
                "previous_pinboard",
                p.previous_pinboard.map(shortcut_value).transpose()?,
            )?;
            add(
                &mut c,
                "shortcuts",
                "next_pinboard",
                p.next_pinboard.map(shortcut_value).transpose()?,
            )?;
            let quick = p
                .quick_paste_modifier
                .map(|v| {
                    modifier(&v).and_then(|v| choice(v.into(), &["command", "option", "control"]))
                })
                .transpose()?;
            let plain = p
                .plain_text_modifier
                .map(|v| modifier(&v).map(str::to_string))
                .transpose()?;
            add(&mut c, "shortcuts", "quick_paste_modifier", quick)?;
            add(&mut c, "shortcuts", "plain_text_modifier", plain)?;
            add(
                &mut c,
                "shortcuts",
                "paste_directly_to_target",
                p.paste_directly_to_target,
            )?;
            add(
                &mut c,
                "shortcuts",
                "always_paste_as_plain_text",
                p.always_paste_as_plain_text,
            )?;
        }
        Ok(c)
    }
}

impl ClipboardCore {
    /// Read/merge/write are atomic across connections. Only requested leaves are
    /// persisted; normalization of the returned view must not rewrite other data.
    pub fn patch_preferences(&mut self, patch: PreferencesPatch) -> Result<PreferencesPatchResult> {
        let changes = patch.changes()?;
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let raw: String = transaction.query_row(
            "SELECT value_json FROM preference_documents WHERE id = 'current'",
            [],
            |r| r.get(0),
        )?;
        let previous = parse_preferences_document(&raw)?;
        let effective = serde_json::to_value(&previous).map_err(|e| invalid(e.to_string()))?;
        let mut document: Value = serde_json::from_str(&raw).map_err(|e| invalid(e.to_string()))?;
        let object = document
            .as_object_mut()
            .ok_or_else(|| invalid("preferences must be an object"))?;
        let mut changed_sections = BTreeSet::new();
        for change in changes {
            let old = object
                .get(change.section)
                .and_then(|v| v.get(change.field))
                .or_else(|| {
                    effective
                        .get(change.section)
                        .and_then(|v| v.get(change.field))
                });
            // Preserve future shortcut fields when replacing its known leaves.
            let mut value = change.value;
            if change.section == "shortcuts" && value.is_object() {
                if let Some(Value::Object(existing)) = old {
                    let mut merged = existing.clone();
                    merged.extend(value.as_object().expect("object checked").clone());
                    value = Value::Object(merged);
                }
            }
            if old == Some(&value) {
                continue;
            }
            let section = object
                .entry(change.section)
                .or_insert_with(|| Value::Object(Map::new()));
            let section = section
                .as_object_mut()
                .ok_or_else(|| invalid("preference section must be an object"))?;
            section.insert(change.field.to_string(), value);
            changed_sections.insert(change.section.to_string());
        }
        let saved_json = serde_json::to_string(&document).map_err(|e| invalid(e.to_string()))?;
        let saved = parse_preferences_document(&saved_json)?;
        if !changed_sections.is_empty() {
            transaction.execute(
                "UPDATE preference_documents SET value_json = ?1, updated_at_ms = ?2 WHERE id = 'current'",
                params![saved_json, now_ms()],
            )?;
        }
        transaction.commit()?;
        let history_changed = previous.history.retention_days != saved.history.retention_days
            || previous.history.retention_forever != saved.history.retention_forever;
        let maintenance = if history_changed {
            match self.apply_history_preferences(&saved) {
                Ok(_) => PreferencesMaintenance {
                    status: PreferencesMaintenanceStatus::Applied,
                    stage: None,
                    code: None,
                    may_have_changed: true,
                },
                Err(error) => PreferencesMaintenance {
                    status: PreferencesMaintenanceStatus::Warning,
                    stage: Some("history_policy".into()),
                    code: Some(error.code.as_str().into()),
                    may_have_changed: true,
                },
            }
        } else {
            PreferencesMaintenance {
                status: PreferencesMaintenanceStatus::NotNeeded,
                stage: None,
                code: None,
                may_have_changed: false,
            }
        };
        Ok(PreferencesPatchResult {
            document: saved,
            changed_sections: changed_sections.into_iter().collect(),
            maintenance,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn patch(value: Value) -> PreferencesPatch {
        serde_json::from_value(value).unwrap()
    }
    fn raw(core: &ClipboardCore) -> Value {
        let text: String = core
            .connection
            .query_row(
                "SELECT value_json FROM preference_documents WHERE id='current'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        serde_json::from_str(&text).unwrap()
    }

    #[test]
    fn patch_preserves_unmodified_and_unknown_fields_and_clear_is_explicit() {
        let dir = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(dir.path()).unwrap();
        let mut before = raw(&core);
        before["future"] = json!({"version": 3});
        before["general"]["future_flag"] = json!(true);
        before["history"]["max_items"] = json!(713);
        before["history"]["record_images"] = json!(false);
        before["shortcuts"]["open_panel"]["future_key"] = json!("retain");
        core.connection
            .execute(
                "UPDATE preference_documents SET value_json=?1",
                [before.to_string()],
            )
            .unwrap();
        let result = core
            .patch_preferences(patch(json!({"appearance":{"mode":"dark"}})))
            .unwrap();
        let mut expected = before;
        expected["appearance"]["mode"] = json!("dark");
        assert_eq!(raw(&core), expected);
        assert_eq!(result.changed_sections, ["appearance"]);
        assert_eq!(
            result.maintenance.status,
            PreferencesMaintenanceStatus::NotNeeded
        );
        core.patch_preferences(patch(json!({"shortcuts":{"open_panel":{"op":"set","value":{"key_code":9,"modifiers":["cmd"]}}}}))).unwrap();
        assert_eq!(
            raw(&core)["shortcuts"]["open_panel"]["future_key"],
            "retain"
        );
        core.patch_preferences(patch(json!({"shortcuts":{"open_panel":{"op":"clear"}}})))
            .unwrap();
        assert!(core
            .get_preferences()
            .unwrap()
            .shortcuts
            .open_panel
            .is_none());
        assert!(raw(&core)["shortcuts"]["open_panel"].is_null());
    }

    #[test]
    fn invalid_patch_is_rejected_before_writing_any_field() {
        let dir = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(dir.path()).unwrap();
        let before = raw(&core);
        assert!(core
            .patch_preferences(patch(
                json!({"appearance":{"mode":"dark"},"history":{"retention_days":0}})
            ))
            .is_err());
        assert_eq!(raw(&core), before);
        for input in [
            json!({"history":null}),
            json!({"history":{"retention_days":null}}),
            json!({"history":{"max_items":3}}),
            json!({"shortcuts":{"open_panel":null}}),
        ] {
            assert!(serde_json::from_value::<PreferencesPatch>(input).is_err());
        }
        assert!(core
            .patch_preferences(patch(
                json!({"ignore_list":{"ignored_app_identifiers": vec!["long";65]}})
            ))
            .is_err());
    }

    #[test]
    fn empty_or_equivalent_patch_does_not_write_or_run_history_policy() {
        let dir = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(dir.path()).unwrap();
        core.connection
            .execute("UPDATE preference_documents SET updated_at_ms=7", [])
            .unwrap();
        // Any accidental maintenance attempt would fail, even with no items.
        core.connection
            .execute_batch("ALTER TABLE clipboard_items RENAME TO unavailable_items;")
            .unwrap();
        for input in [
            json!({}),
            json!({"history":{"retention_days":30}}),
            json!({"appearance":{"mode":"dark"}}),
        ] {
            let r = core.patch_preferences(patch(input)).unwrap();
            assert_eq!(
                r.maintenance.status,
                PreferencesMaintenanceStatus::NotNeeded
            );
            if r.changed_sections.is_empty() {
                let time: i64 = core
                    .connection
                    .query_row("SELECT updated_at_ms FROM preference_documents", [], |r| {
                        r.get(0)
                    })
                    .unwrap();
                assert_eq!(time, 7);
            }
        }
    }

    #[test]
    fn committed_preferences_survive_followup_maintenance_failure() {
        let dir = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(dir.path()).unwrap();
        core.connection
            .execute_batch("ALTER TABLE clipboard_items RENAME TO unavailable_items;")
            .unwrap();
        let result = core
            .patch_preferences(patch(json!({"history":{"retention_days":7}})))
            .unwrap();
        assert_eq!(result.document.history.retention_days, 7);
        assert_eq!(
            result.maintenance.status,
            PreferencesMaintenanceStatus::Warning
        );
        assert_eq!(core.get_preferences().unwrap().history.retention_days, 7);
    }

    #[test]
    fn different_connections_merge_current_fields_without_lost_update() {
        let dir = tempfile::tempdir().unwrap();
        let mut first = ClipboardCore::open(dir.path()).unwrap();
        let mut second = ClipboardCore::open(dir.path()).unwrap();
        first
            .patch_preferences(patch(json!({"appearance":{"mode":"dark"}})))
            .unwrap();
        second
            .patch_preferences(patch(json!({"ignore_list":{"skip_unknown_source":true}})))
            .unwrap();
        let saved = first.get_preferences().unwrap();
        assert_eq!(saved.appearance.mode, "dark");
        assert!(saved.ignore_list.skip_unknown_source);
    }

    #[test]
    fn cold_start_can_repair_preferences_when_history_maintenance_fails() {
        let dir = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(dir.path()).unwrap();
        let request = serde_json::from_value(serde_json::json!({
            "text":"cold start fixture", "display_rtf_byte_count":0,
            "source_confidence":"unknown", "pasteboard_change_count":1
        }))
        .unwrap();
        core.capture_text(request).unwrap();
        core.connection
            .execute(
                "UPDATE clipboard_items SET last_copied_at_ms=?1",
                [now_ms() - 2 * 24 * 60 * 60 * 1000],
            )
            .unwrap();
        let mut preferences = raw(&core);
        preferences["history"]["retention_days"] = json!(1);
        core.connection
            .execute(
                "UPDATE preference_documents SET value_json=?1",
                [preferences.to_string()],
            )
            .unwrap();
        core.connection.execute_batch("CREATE TRIGGER fixture_retention_failure BEFORE UPDATE OF deleted_at_ms ON clipboard_items BEGIN SELECT RAISE(FAIL, 'fixture maintenance failure'); END;").unwrap();
        drop(core);
        assert!(ClipboardCore::open(dir.path()).is_err());
        let mut recovered = ClipboardCore::open_without_history_maintenance(dir.path()).unwrap();
        assert_eq!(
            recovered.get_preferences().unwrap().history.retention_days,
            1
        );
        let result = recovered
            .patch_preferences(patch(json!({"history":{"retention_forever":true}})))
            .unwrap();
        assert!(result.document.history.retention_forever);
        assert_eq!(
            result.maintenance.status,
            PreferencesMaintenanceStatus::Applied
        );
        assert!(ClipboardCore::open(dir.path()).is_ok());
    }

    #[test]
    fn simultaneous_connections_keep_both_disjoint_edits() {
        let dir = tempfile::tempdir().unwrap();
        let first = ClipboardCore::open(dir.path()).unwrap();
        let second = ClipboardCore::open(dir.path()).unwrap();
        let gate = std::sync::Arc::new(std::sync::Barrier::new(2));
        let gate2 = gate.clone();
        let a = std::thread::spawn(move || {
            let mut core = first;
            gate.wait();
            core.patch_preferences(patch(json!({"appearance":{"mode":"dark"}})))
                .unwrap();
        });
        let b = std::thread::spawn(move || {
            let mut core = second;
            gate2.wait();
            core.patch_preferences(patch(json!({"general":{"show_menu_bar_item":false}})))
                .unwrap();
        });
        a.join().unwrap();
        b.join().unwrap();
        let saved = ClipboardCore::open(dir.path())
            .unwrap()
            .get_preferences()
            .unwrap();
        assert_eq!(saved.appearance.mode, "dark");
        assert!(!saved.general.show_menu_bar_item);
    }
}
