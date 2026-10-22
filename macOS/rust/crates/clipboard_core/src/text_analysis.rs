//! Text identity is deliberately compatible with the original capture path.
//! Do not replace its URL handling with a parser that reserializes identity.
use crate::{
    CaptureDetectedLink, ClipboardItemType, CoreError, CoreErrorCode, LinkMetadataState, Result,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureTextAnalysis {
    pub item_type: ClipboardItemType,
    pub primary_text: String,
    pub summary: String,
    pub content_hash: String,
    /// Deterministic ID for a new insertion. Dedup may reuse a legacy DB ID.
    pub item_id: String,
    pub detected_link: Option<CaptureDetectedLink>,
}

pub fn analyze_capture_text(
    text: &str,
    native_link_hint: Option<CaptureDetectedLink>,
) -> Result<CaptureTextAnalysis> {
    let normalized_text = normalize_text(text);
    if normalized_text.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "text capture cannot be empty",
        ));
    }
    let detected_link = normalized_detected_link(&normalized_text, native_link_hint);
    let normalized_color = detected_link
        .is_none()
        .then(|| normalize_hex_color(&normalized_text))
        .flatten();
    let item_type = detected_link
        .as_ref()
        .map(|_| ClipboardItemType::Link)
        .unwrap_or_else(|| {
            if normalized_color.is_some() {
                ClipboardItemType::Color
            } else {
                classify_text(&normalized_text)
            }
        });
    let summary = detected_link
        .as_ref()
        .map(|link| link.display_url.clone())
        .or_else(|| normalized_color.clone())
        .unwrap_or_else(|| summarize_text(&normalized_text));
    let primary_text = normalized_color.unwrap_or(normalized_text);
    let hash_input = detected_link
        .as_ref()
        .map(|link| format!("link:{}", link.canonical_url))
        .unwrap_or_else(|| format!("{}:{primary_text}", item_type.as_str()));
    let content_hash = blake3::hash(hash_input.as_bytes()).to_hex().to_string();
    let item_id = make_item_id(&content_hash);
    Ok(CaptureTextAnalysis {
        item_type,
        primary_text,
        summary,
        content_hash,
        item_id,
        detected_link,
    })
}

pub(crate) fn normalize_text(text: &str) -> String {
    text.trim_matches(|character: char| character == '\0')
        .trim()
        .to_string()
}

fn classify_text(text: &str) -> ClipboardItemType {
    let lower = text.to_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        ClipboardItemType::Link
    } else if normalize_hex_color(text).is_some() {
        ClipboardItemType::Color
    } else {
        ClipboardItemType::Text
    }
}

fn normalize_hex_color(text: &str) -> Option<String> {
    let hex = text.strip_prefix('#').unwrap_or(text);
    if hex.len() != 6 || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    Some(format!("#{}", hex.to_ascii_uppercase()))
}

pub(crate) fn summarize_text(text: &str) -> String {
    const MAX_CHARS: usize = 180;
    let collapsed = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut summary = collapsed.chars().take(MAX_CHARS).collect::<String>();
    if collapsed.chars().count() > MAX_CHARS {
        summary.push('…');
    }
    summary
}

pub(crate) fn make_item_id(content_hash: &str) -> String {
    format!("item_{}", &content_hash[..24])
}

fn normalized_detected_link(
    normalized_text: &str,
    detected_link: Option<CaptureDetectedLink>,
) -> Option<CaptureDetectedLink> {
    match detected_link {
        Some(link) if is_valid_detected_link(&link) => Some(CaptureDetectedLink {
            original_text: non_empty_or(link.original_text, normalized_text),
            canonical_url: link.canonical_url.trim().to_string(),
            display_url: non_empty_or(link.display_url, normalized_text),
            host: link.host.trim().to_ascii_lowercase(),
            metadata_state: link.metadata_state,
        }),
        _ => fallback_detected_link(normalized_text),
    }
}

fn is_valid_detected_link(link: &CaptureDetectedLink) -> bool {
    let canonical_url = link.canonical_url.trim().to_ascii_lowercase();
    let host = link.host.trim();
    !host.is_empty()
        && (canonical_url.starts_with("https://") || canonical_url.starts_with("http://"))
}

fn fallback_detected_link(normalized_text: &str) -> Option<CaptureDetectedLink> {
    let lower = normalized_text.to_ascii_lowercase();
    if !(lower.starts_with("https://") || lower.starts_with("http://")) {
        return None;
    }
    let scheme_separator = normalized_text.find("://")?;
    let after_scheme = &normalized_text[scheme_separator + 3..];
    let host_end = after_scheme
        .find(|character| matches!(character, '/' | '?' | '#'))
        .unwrap_or(after_scheme.len());
    let host = after_scheme[..host_end].trim().trim_matches('.');
    if host.is_empty() {
        return None;
    }
    Some(CaptureDetectedLink {
        original_text: normalized_text.into(),
        canonical_url: normalized_text.into(),
        display_url: normalized_text.into(),
        host: host.to_ascii_lowercase(),
        metadata_state: LinkMetadataState::Pending,
    })
}

fn non_empty_or(value: String, fallback: &str) -> String {
    let value = value.trim();
    if value.is_empty() {
        fallback.to_owned()
    } else {
        value.to_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn golden_text_type_normalization_summary_hash_and_id_remain_compatible() {
        // The identity input is explicit, independent of the analyzed type/body.
        for (input, kind, primary, summary, hash_input, host) in [
            (
                "\0 \nhello\tworld\n\0",
                ClipboardItemType::Text,
                "hello\tworld",
                "hello world",
                "text:hello\tworld",
                None,
            ),
            (
                "#ff00aa",
                ClipboardItemType::Color,
                "#FF00AA",
                "#FF00AA",
                "color:#FF00AA",
                None,
            ),
            (
                "  ff00AA\n",
                ClipboardItemType::Color,
                "#FF00AA",
                "#FF00AA",
                "color:#FF00AA",
                None,
            ),
            (
                "#FFF",
                ClipboardItemType::Text,
                "#FFF",
                "#FFF",
                "text:#FFF",
                None,
            ),
            (
                "\u{200b}hello\u{200b}",
                ClipboardItemType::Text,
                "\u{200b}hello\u{200b}",
                "\u{200b}hello\u{200b}",
                "text:\u{200b}hello\u{200b}",
                None,
            ),
            (
                " \0hello\0 ",
                ClipboardItemType::Text,
                "\0hello\0",
                "\0hello\0",
                "text:\0hello\0",
                None,
            ),
            (
                "HTTPS://Example.COM:443/a?x=1#f",
                ClipboardItemType::Link,
                "HTTPS://Example.COM:443/a?x=1#f",
                "HTTPS://Example.COM:443/a?x=1#f",
                "link:HTTPS://Example.COM:443/a?x=1#f",
                Some("example.com:443"),
            ),
            (
                "http:///#f",
                ClipboardItemType::Link,
                "http:///#f",
                "http:///#f",
                "link:http:///#f",
                None,
            ),
        ] {
            let actual = analyze_capture_text(input, None).unwrap();
            let expected_hash = blake3::hash(hash_input.as_bytes()).to_hex().to_string();
            assert_eq!(actual.item_type, kind, "{input:?}");
            assert_eq!(actual.primary_text, primary);
            assert_eq!(actual.summary, summary);
            assert_eq!(actual.content_hash, expected_hash);
            assert_eq!(actual.item_id, format!("item_{}", &expected_hash[..24]));
            assert_eq!(
                actual.detected_link.as_ref().map(|link| link.host.as_str()),
                host
            );
            if let Some(link) = actual.detected_link {
                assert_eq!(link.canonical_url, primary);
            }
        }
        assert_eq!(
            analyze_capture_text("\0 \r\n\0", None).unwrap_err().code,
            CoreErrorCode::InvalidInput
        );
        let long = "中".repeat(181);
        assert_eq!(
            analyze_capture_text(&long, None).unwrap().summary,
            format!("{}…", "中".repeat(180))
        );
    }

    #[test]
    fn native_link_wins_over_color_and_nil_or_invalid_hint_keeps_fallback() {
        let hint = CaptureDetectedLink {
            original_text: " ".into(),
            canonical_url: " HTTPS://EXAMPLE.test:443/a ".into(),
            display_url: "\n".into(),
            host: " EXAMPLE.test ".into(),
            metadata_state: LinkMetadataState::Ready,
        };
        let result = analyze_capture_text("#ff00aa", Some(hint.clone())).unwrap();
        assert_eq!(result.item_type, ClipboardItemType::Link);
        assert_eq!(result.primary_text, "#ff00aa");
        assert_eq!(result.summary, "#ff00aa");
        assert_eq!(
            result.content_hash,
            blake3::hash(b"link:HTTPS://EXAMPLE.test:443/a")
                .to_hex()
                .to_string()
        );
        let link = result.detected_link.unwrap();
        assert_eq!(link.original_text, "#ff00aa");
        assert_eq!(link.host, "example.test");
        assert_eq!(link.metadata_state, LinkMetadataState::Ready);
        let fallback = analyze_capture_text("https://Example.test/path", None).unwrap();
        let mut invalid_hint = hint;
        invalid_hint.canonical_url = "ftp://bad.test".into();
        assert_eq!(
            analyze_capture_text("https://Example.test/path", Some(invalid_hint)).unwrap(),
            fallback
        );
    }

    #[test]
    fn persisted_capture_uses_analysis_without_replacing_an_existing_identity() {
        use crate::{CaptureTextRequest, ClipboardCore, SourceConfidence};
        let root = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(root.path()).unwrap();
        for text in [
            "text body",
            "#aabbcc",
            "https://Example.test/Path",
            "http:///#f",
        ] {
            let expected = analyze_capture_text(text, None).unwrap();
            let request = || CaptureTextRequest {
                text: text.into(),
                detected_link: None,
                display_rtf_relative_path: None,
                display_rtf_mime_type: None,
                display_rtf_byte_count: 0,
                source_bundle_id: None,
                source_app_name: None,
                source_bundle_path: None,
                source_icon_relative_path: None,
                source_confidence: SourceConfidence::Unknown,
                pasteboard_change_count: 1,
                self_write_token: None,
            };
            let first = core.capture_text(request()).unwrap();
            let repeated = core.capture_text(request()).unwrap();
            assert_eq!(first.item_id, expected.item_id);
            assert_eq!(first.content_hash, expected.content_hash);
            assert!(!repeated.inserted);
            assert_eq!(repeated.item_id, first.item_id);
            let stored = core.get_item(&first.item_id).unwrap().unwrap();
            assert_eq!(stored.item_type, expected.item_type);
            assert_eq!(
                stored.primary_text.as_deref(),
                Some(expected.primary_text.as_str())
            );
            assert_eq!(stored.summary, expected.summary);
        }
    }
}
