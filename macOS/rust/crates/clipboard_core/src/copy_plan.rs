//! Pure copy selection and composition policy. File IO, clipboard encoders and
//! the authoritative ID lookup belong to the native adapter. Asset references
//! are opaque keys into that request's native URL table, never filesystem paths.
use crate::{ClipboardItemType, CoreError, CoreErrorCode, PayloadState, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CopyMode {
    Original,
    PreferPlainText,
    ExplicitPlainText,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CopyCapabilities {
    #[serde(rename = "mac_os_v1")]
    MacOsV1,
    #[serde(rename = "windows_v1")]
    WindowsV1,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CopyAssetKind {
    ManagedAsset,
    ExternalFile,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CopyAssetRef {
    pub kind: CopyAssetKind,
    pub key: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CopyFileCandidate {
    pub asset: CopyAssetRef,
    pub is_image: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CopyInputItem {
    pub item_id: String,
    pub content_hash: String,
    pub item_type: ClipboardItemType,
    pub primary_text: Option<String>,
    pub summary: String,
    pub payload_state: PayloadState,
    pub canonical_url: Option<String>,
    /// Windows' existing file-to-text fallback. This is never an asset path.
    pub first_file_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CopyNativeFileFacts {
    pub item_id: String,
    pub content_hash: String,
    pub payload_asset: Option<CopyAssetRef>,
    pub file_candidates: Vec<CopyFileCandidate>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CopyPlanRequest {
    pub ordered_ids: Vec<String>,
    pub mode: CopyMode,
    pub capabilities: CopyCapabilities,
    pub items: Vec<CopyInputItem>,
    pub file_facts: Vec<CopyNativeFileFacts>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CopyComposition {
    Single,
    FileUrls,
    SeparateItems,
    CompositeText,
    JoinedPlainText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum CopyRepresentation {
    Text { text: String },
    Rtf { asset: CopyAssetRef },
    Image { asset: CopyAssetRef },
    File { asset: CopyAssetRef },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CopyPlannedItem {
    pub source_item_ids: Vec<String>,
    pub representations: Vec<CopyRepresentation>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CopySkippedItem {
    pub request_index: usize,
    pub item_id: String,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum CopyPlan {
    Ready {
        composition: CopyComposition,
        items: Vec<CopyPlannedItem>,
        included_ids: Vec<String>,
        skipped: Vec<CopySkippedItem>,
    },
    Unsupported {
        reason: String,
        skipped: Vec<CopySkippedItem>,
    },
}

struct Entry {
    index: usize,
    item: CopyInputItem,
    facts: CopyNativeFileFacts,
}

/// This consumes bodies rather than cloning them. The 200-row DB read limit
/// does not apply: composition needs the complete hydrated selection.
pub fn plan_copy(request: CopyPlanRequest) -> Result<CopyPlan> {
    validate(&request)?;
    let mode = request.mode;
    let capabilities = request.capabilities;
    let mut entries: Vec<_> = request
        .items
        .into_iter()
        .zip(request.file_facts)
        .enumerate()
        .map(|(index, (item, facts))| Entry { index, item, facts })
        .collect();
    if entries.is_empty() {
        return Ok(unsupported("empty_selection", vec![]));
    }
    if capabilities == CopyCapabilities::WindowsV1 {
        if entries.len() != 1 {
            return Ok(unsupported("unsupported_selection", vec![]));
        }
        return Ok(windows_single(entries.remove(0), mode));
    }
    if entries.len() == 1 {
        let entry = entries.remove(0);
        if mode == CopyMode::ExplicitPlainText {
            if !matches!(
                entry.item.item_type,
                ClipboardItemType::Text | ClipboardItemType::RichText
            ) {
                return Ok(unsupported("unsupported_type", vec![]));
            }
            return Ok(match plain_fragment(entry) {
                Some(item) => ready(CopyComposition::Single, vec![item], vec![]),
                None => unsupported("empty_text", vec![]),
            });
        }
        if mode == CopyMode::PreferPlainText && text_like(entry.item.item_type) {
            let reason = if entry.item.item_type == ClipboardItemType::Color {
                "invalid_color"
            } else {
                "empty_text"
            };
            return Ok(match plain_fragment(entry) {
                Some(item) => ready(CopyComposition::Single, vec![item], vec![]),
                None => unsupported(reason, vec![]),
            });
        }
        return Ok(match original(entry) {
            Ok(items) => {
                let composition = if items.iter().all(file_only) {
                    CopyComposition::FileUrls
                } else if items.len() == 1 {
                    CopyComposition::Single
                } else {
                    CopyComposition::SeparateItems
                };
                ready(composition, items, vec![])
            }
            Err(reason) => unsupported(reason, vec![]),
        });
    }

    let mut skipped = Vec::new();
    if mode != CopyMode::Original {
        let mut items = Vec::new();
        for entry in entries {
            let skip = skipped_entry(
                &entry,
                if text_like(entry.item.item_type) {
                    "empty_or_invalid_text"
                } else {
                    "plain_text_media_omitted"
                },
            );
            match plain_fragment(entry) {
                Some(item) => items.push(item),
                None => skipped.push(skip),
            }
        }
        return Ok(if items.is_empty() {
            unsupported("unsupported_type", skipped)
        } else {
            ready(CopyComposition::JoinedPlainText, items, skipped)
        });
    }
    if entries
        .iter()
        .all(|entry| entry.item.item_type == ClipboardItemType::File)
    {
        let mut items = Vec::new();
        for entry in entries {
            if entry.facts.file_candidates.is_empty() {
                skipped.push(skipped_entry(&entry, "missing_file_url"));
            } else {
                items.extend(file_items(entry));
            }
        }
        return Ok(if items.is_empty() {
            unsupported("missing_file_url", skipped)
        } else {
            let composition = if items.iter().all(file_only) {
                CopyComposition::FileUrls
            } else {
                CopyComposition::SeparateItems
            };
            ready(composition, items, skipped)
        });
    }
    // This incorporates the writer's former second text/image filter. Files
    // with image candidates are image-like, including mixed image/document sets.
    let text_only = entries.iter().any(image_like)
        && entries.iter().any(|entry| text_like(entry.item.item_type));
    let mut items = Vec::new();
    for entry in entries {
        if text_only && !text_like(entry.item.item_type) {
            skipped.push(skipped_entry(&entry, "mixed_media_omitted"));
            continue;
        }
        match original(entry) {
            Ok(planned) => items.extend(planned),
            Err(reason) => return Ok(unsupported(reason, skipped)),
        }
    }
    let composition = if items.len() > 1 && items.iter().all(text_only_item) {
        CopyComposition::CompositeText
    } else {
        CopyComposition::SeparateItems
    };
    Ok(ready(composition, items, skipped))
}

fn validate(request: &CopyPlanRequest) -> Result<()> {
    if request.items.len() != request.ordered_ids.len()
        || request.items.len() != request.file_facts.len()
    {
        return Err(invalid(
            "copy items and file facts must match the ordered selection",
        ));
    }
    for ((id, item), facts) in request
        .ordered_ids
        .iter()
        .zip(&request.items)
        .zip(&request.file_facts)
    {
        if id != &item.item_id || id != &facts.item_id || item.content_hash != facts.content_hash {
            return Err(invalid("copy item identity or file facts are stale"));
        }
        if facts
            .payload_asset
            .as_ref()
            .is_some_and(|asset| asset.kind != CopyAssetKind::ManagedAsset || asset.key.is_empty())
            || facts.file_candidates.iter().any(|candidate| {
                candidate.asset.kind != CopyAssetKind::ExternalFile
                    || candidate.asset.key.is_empty()
            })
        {
            return Err(invalid("copy asset references have invalid provenance"));
        }
    }
    Ok(())
}
fn invalid(message: &str) -> CoreError {
    CoreError::new(CoreErrorCode::InvalidInput, message)
}
fn text_like(kind: ClipboardItemType) -> bool {
    matches!(
        kind,
        ClipboardItemType::Text
            | ClipboardItemType::RichText
            | ClipboardItemType::Link
            | ClipboardItemType::Color
    )
}
fn image_like(entry: &Entry) -> bool {
    entry.item.item_type == ClipboardItemType::Image
        || (entry.item.item_type == ClipboardItemType::File
            && entry
                .facts
                .file_candidates
                .iter()
                .any(|candidate| candidate.is_image))
}
fn file_only(item: &CopyPlannedItem) -> bool {
    item.representations
        .iter()
        .all(|value| matches!(value, CopyRepresentation::File { .. }))
}
fn text_only_item(item: &CopyPlannedItem) -> bool {
    item.representations.iter().all(|value| {
        matches!(
            value,
            CopyRepresentation::Text { .. } | CopyRepresentation::Rtf { .. }
        )
    })
}
fn trim(text: &str) -> &str {
    text.trim_matches(|ch: char| ch.is_whitespace() || ch == '\u{200b}')
}
fn color(item: &CopyInputItem) -> Option<String> {
    item.primary_text
        .iter()
        .map(String::as_str)
        .chain(std::iter::once(item.summary.as_str()))
        .find_map(|text| {
            let text = trim(text);
            (text.len() == 7
                && text.starts_with('#')
                && text.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit))
            .then(|| text.to_ascii_uppercase())
        })
}
fn plain_fragment(entry: Entry) -> Option<CopyPlannedItem> {
    if !text_like(entry.item.item_type) {
        return None;
    }
    let text = if entry.item.item_type == ClipboardItemType::Color {
        color(&entry.item)?
    } else {
        entry.item.primary_text.unwrap_or(entry.item.summary)
    };
    if trim(&text).is_empty() {
        return None;
    }
    Some(CopyPlannedItem {
        source_item_ids: vec![entry.item.item_id],
        representations: vec![CopyRepresentation::Text { text }],
    })
}
fn original(entry: Entry) -> std::result::Result<Vec<CopyPlannedItem>, &'static str> {
    if entry.item.item_type == ClipboardItemType::File {
        return if entry.facts.file_candidates.is_empty() {
            Err("missing_file_url")
        } else {
            Ok(file_items(entry))
        };
    }
    let representations = match entry.item.item_type {
        ClipboardItemType::Text | ClipboardItemType::Link | ClipboardItemType::RichText => {
            let text = entry.item.primary_text.unwrap_or(entry.item.summary);
            if trim(&text).is_empty() {
                return Err("empty_text");
            }
            let mut representations = Vec::new();
            if entry.item.item_type == ClipboardItemType::RichText {
                if let Some(asset) = entry.facts.payload_asset {
                    representations.push(CopyRepresentation::Rtf { asset });
                }
            }
            representations.push(CopyRepresentation::Text { text });
            representations
        }
        ClipboardItemType::Color => vec![CopyRepresentation::Text {
            text: color(&entry.item).ok_or("invalid_color")?,
        }],
        ClipboardItemType::Image => {
            if entry.item.payload_state != PayloadState::Ready {
                return Err("missing_image_asset");
            }
            vec![CopyRepresentation::Image {
                asset: entry.facts.payload_asset.ok_or("missing_image_asset")?,
            }]
        }
        _ => return Err("unsupported_type"),
    };
    Ok(vec![CopyPlannedItem {
        source_item_ids: vec![entry.item.item_id],
        representations,
    }])
}
fn file_items(entry: Entry) -> Vec<CopyPlannedItem> {
    entry
        .facts
        .file_candidates
        .into_iter()
        .map(|candidate| CopyPlannedItem {
            source_item_ids: vec![entry.item.item_id.clone()],
            representations: vec![if candidate.is_image {
                CopyRepresentation::Image {
                    asset: candidate.asset,
                }
            } else {
                CopyRepresentation::File {
                    asset: candidate.asset,
                }
            }],
        })
        .collect()
}
fn windows_single(entry: Entry, mode: CopyMode) -> CopyPlan {
    let item = entry.item;
    let representation = if item.item_type == ClipboardItemType::Image {
        if mode == CopyMode::ExplicitPlainText {
            return unsupported("unsupported_type", vec![]);
        }
        if item.payload_state != PayloadState::Ready {
            return unsupported("missing_image_asset", vec![]);
        }
        let Some(asset) = entry.facts.payload_asset else {
            return unsupported("missing_image_asset", vec![]);
        };
        CopyRepresentation::Image { asset }
    } else {
        let text = match item.item_type {
            ClipboardItemType::Link => item
                .canonical_url
                .or(item.primary_text)
                .unwrap_or(item.summary),
            ClipboardItemType::File => item.first_file_path.unwrap_or(item.summary),
            ClipboardItemType::Color => item.summary,
            _ => item.primary_text.unwrap_or(item.summary),
        };
        CopyRepresentation::Text { text }
    };
    ready(
        CopyComposition::Single,
        vec![CopyPlannedItem {
            source_item_ids: vec![item.item_id],
            representations: vec![representation],
        }],
        vec![],
    )
}
fn skipped_entry(entry: &Entry, reason: &str) -> CopySkippedItem {
    CopySkippedItem {
        request_index: entry.index,
        item_id: entry.item.item_id.clone(),
        reason: reason.into(),
    }
}
fn unsupported(reason: &str, skipped: Vec<CopySkippedItem>) -> CopyPlan {
    CopyPlan::Unsupported {
        reason: reason.into(),
        skipped,
    }
}
fn ready(
    composition: CopyComposition,
    items: Vec<CopyPlannedItem>,
    skipped: Vec<CopySkippedItem>,
) -> CopyPlan {
    let mut seen = HashSet::new();
    let included_ids = items
        .iter()
        .flat_map(|item| &item.source_item_ids)
        .filter(|id| seen.insert((*id).clone()))
        .cloned()
        .collect();
    CopyPlan::Ready {
        composition,
        items,
        included_ids,
        skipped,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(kinds: &[ClipboardItemType], mode: CopyMode) -> CopyPlanRequest {
        let items: Vec<_> = kinds
            .iter()
            .enumerate()
            .map(|(index, kind)| CopyInputItem {
                item_id: format!("item-{index}"),
                content_hash: format!("hash-{index}"),
                item_type: *kind,
                primary_text: Some(if *kind == ClipboardItemType::Color {
                    "#aabbcc".into()
                } else {
                    format!("body-{index}")
                }),
                summary: format!("summary-{index}"),
                payload_state: PayloadState::Ready,
                canonical_url: Some("https://canonical.example/".into()),
                first_file_path: Some("/external/first.txt".into()),
            })
            .collect();
        let file_facts = items
            .iter()
            .map(|item| CopyNativeFileFacts {
                item_id: item.item_id.clone(),
                content_hash: item.content_hash.clone(),
                payload_asset: Some(CopyAssetRef {
                    kind: CopyAssetKind::ManagedAsset,
                    key: format!("{}-payload", item.item_id),
                }),
                file_candidates: if item.item_type == ClipboardItemType::File {
                    vec![CopyFileCandidate {
                        asset: CopyAssetRef {
                            kind: CopyAssetKind::ExternalFile,
                            key: format!("{}-file", item.item_id),
                        },
                        is_image: false,
                    }]
                } else {
                    vec![]
                },
            })
            .collect();
        CopyPlanRequest {
            ordered_ids: items.iter().map(|item| item.item_id.clone()).collect(),
            items,
            file_facts,
            mode,
            capabilities: CopyCapabilities::MacOsV1,
        }
    }

    fn parts(
        plan: CopyPlan,
    ) -> (
        CopyComposition,
        Vec<CopyPlannedItem>,
        Vec<String>,
        Vec<CopySkippedItem>,
    ) {
        match plan {
            CopyPlan::Ready {
                composition,
                items,
                included_ids,
                skipped,
            } => (composition, items, included_ids, skipped),
            other => panic!("expected ready: {other:?}"),
        }
    }

    #[test]
    fn explicit_and_global_plain_keep_their_single_and_multiple_scope() {
        use ClipboardItemType::*;
        for kind in [Link, Color, Image, File] {
            assert!(matches!(
                plan_copy(request(&[kind], CopyMode::ExplicitPlainText)).unwrap(),
                CopyPlan::Unsupported { .. }
            ));
            let (_, items, ids, _) =
                parts(plan_copy(request(&[kind], CopyMode::PreferPlainText)).unwrap());
            assert_eq!(ids, ["item-0"]);
            assert!(!items.is_empty());
        }
        for mode in [CopyMode::PreferPlainText, CopyMode::ExplicitPlainText] {
            let (composition, items, ids, skipped) =
                parts(plan_copy(request(&[Image, Link, File, Color, RichText], mode)).unwrap());
            assert_eq!(composition, CopyComposition::JoinedPlainText);
            assert_eq!(ids, ["item-1", "item-3", "item-4"]);
            assert_eq!(
                skipped
                    .iter()
                    .map(|item| item.request_index)
                    .collect::<Vec<_>>(),
                [0, 2]
            );
            assert!(items.iter().all(|item| item
                .representations
                .iter()
                .all(|rep| matches!(rep, CopyRepresentation::Text { .. }))));
        }
        assert!(
            matches!(plan_copy(request(&[Image, Image], CopyMode::PreferPlainText)).unwrap(), CopyPlan::Unsupported { reason, .. } if reason == "unsupported_type")
        );
    }

    #[test]
    fn mixed_image_and_text_omits_media_but_images_and_files_remain_separate() {
        use ClipboardItemType::*;
        let mut mixed = request(&[Image, RichText, File, Text], CopyMode::Original);
        mixed.items[0].payload_state = PayloadState::Pending; // Omitted media must not block text.
        let (composition, _, ids, skipped) = parts(plan_copy(mixed).unwrap());
        assert_eq!(composition, CopyComposition::CompositeText);
        assert_eq!(ids, ["item-1", "item-3"]);
        assert_eq!(skipped.len(), 2);
        let (composition, items, ids, _) =
            parts(plan_copy(request(&[Image, File], CopyMode::Original)).unwrap());
        assert_eq!(composition, CopyComposition::SeparateItems);
        assert_eq!(ids, ["item-0", "item-1"]);
        assert!(matches!(
            items[1].representations[0],
            CopyRepresentation::File { .. }
        ));
    }

    #[test]
    fn all_file_partial_availability_returns_actual_owners_and_image_files() {
        let mut input = request(&[ClipboardItemType::File; 3], CopyMode::Original);
        input.file_facts[1].file_candidates.clear();
        let (composition, _, ids, skipped) = parts(plan_copy(input.clone()).unwrap());
        assert_eq!(composition, CopyComposition::FileUrls);
        assert_eq!(ids, ["item-0", "item-2"]);
        assert_eq!(skipped[0].item_id, "item-1");
        input.file_facts[2].file_candidates[0].is_image = true;
        let (composition, _, ids, _) = parts(plan_copy(input).unwrap());
        assert_eq!(composition, CopyComposition::SeparateItems);
        assert_eq!(ids, ["item-0", "item-2"]);
    }

    #[test]
    fn rtf_fallback_and_empty_text_preserve_body_and_color_rules() {
        let mut input = request(&[ClipboardItemType::RichText], CopyMode::Original);
        input.file_facts[0].payload_asset = None;
        input.items[0].primary_text = Some("  full text\n".into());
        let (_, items, _, _) = parts(plan_copy(input.clone()).unwrap());
        assert_eq!(
            items[0].representations,
            [CopyRepresentation::Text {
                text: "  full text\n".into()
            }]
        );
        input.items[0].primary_text = Some("\u{200b}\r\n".into());
        assert!(
            matches!(plan_copy(input).unwrap(), CopyPlan::Unsupported { reason, .. } if reason == "empty_text")
        );
        let (_, items, _, _) =
            parts(plan_copy(request(&[ClipboardItemType::Color], CopyMode::Original)).unwrap());
        assert_eq!(
            items[0].representations,
            [CopyRepresentation::Text {
                text: "#AABBCC".into()
            }]
        );
    }

    #[test]
    fn missing_or_pending_images_never_use_a_preview_fallback() {
        let mut input = request(&[ClipboardItemType::Image], CopyMode::Original);
        input.file_facts[0].payload_asset = None;
        assert!(
            matches!(plan_copy(input.clone()).unwrap(), CopyPlan::Unsupported { reason, .. } if reason == "missing_image_asset")
        );
        input.file_facts[0].payload_asset = Some(CopyAssetRef {
            kind: CopyAssetKind::ManagedAsset,
            key: "payload".into(),
        });
        input.items[0].payload_state = PayloadState::Pending;
        assert!(matches!(
            plan_copy(input).unwrap(),
            CopyPlan::Unsupported { .. }
        ));
    }

    #[test]
    fn selection_order_duplicates_and_large_selection_are_not_truncated() {
        let mut input = request(&[ClipboardItemType::Text; 450], CopyMode::Original);
        input.ordered_ids[1] = input.ordered_ids[0].clone();
        input.items[1] = input.items[0].clone();
        input.file_facts[1] = input.file_facts[0].clone();
        let (_, items, ids, _) = parts(plan_copy(input).unwrap());
        assert_eq!(items.len(), 450);
        assert_eq!(ids.len(), 449);
        assert_eq!(items[0], items[1]);
        assert_eq!(ids[0], "item-0");
        assert_eq!(ids[1], "item-2");
    }

    #[test]
    fn stale_hash_missing_item_and_wrong_reference_provenance_are_invalid_input() {
        let mut input = request(&[ClipboardItemType::Image], CopyMode::Original);
        input.file_facts[0].content_hash = "stale".into();
        assert!(plan_copy(input).is_err());
        let mut input = request(&[ClipboardItemType::Image], CopyMode::Original);
        input.items.clear();
        assert!(plan_copy(input).is_err());
        let mut input = request(&[ClipboardItemType::Image], CopyMode::Original);
        input.file_facts[0].payload_asset.as_mut().unwrap().kind = CopyAssetKind::ExternalFile;
        assert!(plan_copy(input).is_err());
    }

    #[test]
    fn windows_keeps_existing_text_degradation_and_does_not_gain_rtf_or_file_writes() {
        for (kind, expected) in [
            (ClipboardItemType::Link, "https://canonical.example/"),
            (ClipboardItemType::Color, "summary-0"),
            (ClipboardItemType::File, "/external/first.txt"),
            (ClipboardItemType::RichText, "body-0"),
        ] {
            let mut input = request(&[kind], CopyMode::Original);
            input.capabilities = CopyCapabilities::WindowsV1;
            let (composition, items, _, _) = parts(plan_copy(input).unwrap());
            assert_eq!(composition, CopyComposition::Single);
            assert_eq!(
                items[0].representations,
                [CopyRepresentation::Text {
                    text: expected.into()
                }]
            );
        }
        let mut input = request(&[ClipboardItemType::Image], CopyMode::Original);
        input.capabilities = CopyCapabilities::WindowsV1;
        let (_, items, _, _) = parts(plan_copy(input).unwrap());
        assert!(matches!(
            items[0].representations[0],
            CopyRepresentation::Image { .. }
        ));
    }

    #[test]
    fn serde_contract_is_tagged_and_contains_opaque_refs_only() {
        let input = request(&[ClipboardItemType::Image], CopyMode::Original);
        let json = serde_json::to_string(&input).unwrap();
        assert!(json.contains("\"capabilities\":\"mac_os_v1\""));
        let output = plan_copy(serde_json::from_str(&json).unwrap()).unwrap();
        let value = serde_json::to_value(output).unwrap();
        assert_eq!(value["status"], "ready");
        assert_eq!(value["composition"], "single");
        assert_eq!(
            value["items"][0]["representations"][0]["asset"]["kind"],
            "managed_asset"
        );
        assert!(value["items"][0]["representations"][0]["asset"]
            .get("path")
            .is_none());
    }
}
