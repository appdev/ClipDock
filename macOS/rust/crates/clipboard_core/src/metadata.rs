//! Pure metadata rules. Transport, platform URL facts and image encoding stay native.
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use url::Url;

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MetadataCompatibilityProfile {
    MacOsV1,
    WindowsV1,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct MetadataURLFacts {
    pub scheme: Option<String>,
    pub host: Option<String>,
    pub query_names: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct MetadataURLDecision {
    pub supported: bool,
    pub privacy_sensitive: bool,
}

pub fn metadata_url_policy(facts: &MetadataURLFacts) -> MetadataURLDecision {
    const KEYWORDS: &[&str] = &[
        "auth",
        "code",
        "jwt",
        "key",
        "otp",
        "password",
        "secret",
        "session",
        "signature",
        "token",
    ];
    MetadataURLDecision {
        supported: facts.scheme.as_deref().is_some_and(|scheme| {
            scheme.eq_ignore_ascii_case("http") || scheme.eq_ignore_ascii_case("https")
        }) && facts.host.as_deref().is_some_and(|host| !host.is_empty()),
        privacy_sensitive: facts.query_names.iter().any(|name| {
            let name = name.to_lowercase();
            KEYWORDS.iter().any(|keyword| {
                name == *keyword
                    || [
                        format!("_{keyword}"),
                        format!("{keyword}_"),
                        format!("-{keyword}"),
                        format!("{keyword}-"),
                    ]
                    .iter()
                    .any(|part| name.contains(part))
            })
        }),
    }
}

#[derive(Debug, Deserialize, Serialize)]
pub struct MetadataLimits {
    pub max_html_bytes: usize,
    pub max_image_bytes: usize,
    pub max_icon_candidates: usize,
    pub max_preview_candidates: usize,
    pub page_timeout_ms: u64,
    pub image_timeout_ms: u64,
    pub max_redirects: usize,
}

pub fn metadata_limits(profile: MetadataCompatibilityProfile) -> MetadataLimits {
    let (page_timeout_ms, image_timeout_ms) = match profile {
        MetadataCompatibilityProfile::MacOsV1 => (8_000, 6_000),
        MetadataCompatibilityProfile::WindowsV1 => (10_000, 10_000),
    };
    MetadataLimits {
        max_html_bytes: 512 * 1024,
        max_image_bytes: 5 * 1024 * 1024,
        max_icon_candidates: 4,
        max_preview_candidates: 4,
        page_timeout_ms,
        image_timeout_ms,
        max_redirects: 5,
    }
}

#[derive(Debug, Deserialize, Serialize)]
pub struct MetadataRetryRequest {
    /// Attempt count returned by claim, before that claim increments it.
    pub fetch_attempts: i64,
    pub now_ms: i64,
}

pub fn metadata_retry_at_ms(fetch_attempts: i64, now_ms: i64) -> i64 {
    const DELAYS: [i64; 4] = [300_000, 1_800_000, 21_600_000, 86_400_000];
    now_ms.saturating_add(DELAYS[fetch_attempts.clamp(0, 3) as usize])
}

#[derive(Debug, Deserialize, Serialize)]
pub struct MetadataHTMLRequest {
    pub html: String,
    pub base_url: String,
    pub profile: MetadataCompatibilityProfile,
}

#[derive(Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct MetadataHTMLResult {
    pub title: Option<String>,
    pub icon_urls: Vec<String>,
    pub preview_urls: Vec<String>,
}

pub fn parse_metadata_html(
    html: &str,
    base_url: &str,
    profile: MetadataCompatibilityProfile,
) -> MetadataHTMLResult {
    let Ok(base_url) = Url::parse(base_url) else {
        return MetadataHTMLResult::default();
    };
    if !allowed(&base_url) {
        return MetadataHTMLResult::default();
    }
    let document = Html::parse_document(html);
    let meta = Selector::parse("meta").expect("static selector");
    let link = Selector::parse("link").expect("static selector");
    let title = Selector::parse("title").expect("static selector");
    let mut result = MetadataHTMLResult::default();
    for element in document.select(&meta) {
        let key = element
            .value()
            .attr("property")
            .or_else(|| element.value().attr("name"))
            .map(str::to_ascii_lowercase);
        let content = element
            .value()
            .attr("content")
            .map(str::trim)
            .filter(|s| !s.is_empty());
        if matches!(key.as_deref(), Some("og:title" | "twitter:title")) && result.title.is_none() {
            result.title = content.map(str::to_owned);
        }
        if matches!(
            key.as_deref(),
            Some("og:image" | "og:image:url" | "twitter:image" | "twitter:image:src")
        ) {
            if let Some(url) = content.and_then(|value| resolve(&base_url, value)) {
                result.preview_urls.push(url);
            }
        }
    }
    if result.title.is_none() {
        result.title = document
            .select(&title)
            .next()
            .map(|element| element.text().collect::<String>())
            .map(|text| text.trim().to_owned())
            .filter(|text| !text.is_empty());
    }
    for element in document.select(&link) {
        let rel = element
            .value()
            .attr("rel")
            .unwrap_or_default()
            .to_ascii_lowercase();
        let is_icon = match profile {
            MetadataCompatibilityProfile::MacOsV1 => rel
                .split(' ')
                .any(|token| matches!(token, "icon" | "apple-touch-icon")),
            MetadataCompatibilityProfile::WindowsV1 => rel.split_whitespace().any(|token| {
                matches!(
                    token,
                    "icon" | "shortcut" | "apple-touch-icon" | "mask-icon"
                )
            }),
        };
        if is_icon {
            if let Some(url) = element
                .value()
                .attr("href")
                .and_then(|value| resolve(&base_url, value.trim()))
            {
                result.icon_urls.push(url);
            }
        }
    }
    for path in ["/favicon.ico", "/favicon.png", "/apple-touch-icon.png"] {
        if let Some(url) = resolve(&base_url, path) {
            result.icon_urls.push(url);
        }
    }
    unique(&mut result.icon_urls);
    unique(&mut result.preview_urls);
    result
}

fn allowed(url: &Url) -> bool {
    let policy = metadata_url_policy(&MetadataURLFacts {
        scheme: Some(url.scheme().to_owned()),
        host: url.host_str().map(str::to_owned),
        query_names: url
            .query_pairs()
            .map(|(name, _)| name.into_owned())
            .collect(),
    });
    policy.supported && !policy.privacy_sensitive
}

fn resolve(base: &Url, value: &str) -> Option<String> {
    let url = base.join(value).ok()?;
    allowed(&url).then(|| url.into())
}

fn unique(urls: &mut Vec<String>) {
    let mut seen = HashSet::new();
    urls.retain(|url| seen.insert(url.clone()));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn policy_preserves_local_hosts_and_checks_only_query_names() {
        for host in ["localhost", "127.0.0.1", "192.168.1.2", "[fd00::1]"] {
            let facts = MetadataURLFacts {
                scheme: Some("HTTP".into()),
                host: Some(host.into()),
                query_names: vec!["utm_source".into()],
            };
            assert_eq!(
                metadata_url_policy(&facts),
                MetadataURLDecision {
                    supported: true,
                    privacy_sensitive: false
                }
            );
        }
        for key in [
            "token",
            "ACCESS_TOKEN",
            "session-id",
            "auth_code",
            "my-password",
        ] {
            assert!(
                metadata_url_policy(&MetadataURLFacts {
                    scheme: Some("https".into()),
                    host: Some("example.com".into()),
                    query_names: vec![key.into()]
                })
                .privacy_sensitive
            );
        }
        assert!(
            !metadata_url_policy(&MetadataURLFacts {
                scheme: Some("file".into()),
                host: None,
                query_names: vec![]
            })
            .supported
        );
    }

    #[test]
    fn retry_uses_preclaim_count_and_saturates() {
        for (count, delay) in [
            (-1, 300_000),
            (0, 300_000),
            (1, 1_800_000),
            (2, 21_600_000),
            (3, 86_400_000),
            (i64::MAX, 86_400_000),
        ] {
            assert_eq!(metadata_retry_at_ms(count, 100), delay + 100);
        }
        assert_eq!(metadata_retry_at_ms(1, i64::MAX), i64::MAX);
    }

    #[test]
    fn parser_profiles_keep_order_and_decode_entities() {
        let html = r#"<title>fallback</title><meta name='twitter:title' content='First &amp; best'><meta property='og:title' content='second'>
            <meta property='og:image' content='../a.png?x=1&amp;y=2'><meta name='twitter:image' content='../a.png?x=1&amp;y=2'>
            <link rel='mask-icon' href='/mask.svg'><link rel='shortcut' href='/short.ico'><link rel='icon' href='/favicon.ico'>"#;
        let mac = parse_metadata_html(
            html,
            "https://example.com/docs/page",
            MetadataCompatibilityProfile::MacOsV1,
        );
        assert_eq!(mac.title.as_deref(), Some("First & best"));
        assert_eq!(mac.preview_urls, ["https://example.com/a.png?x=1&y=2"]);
        assert_eq!(
            mac.icon_urls,
            [
                "https://example.com/favicon.ico",
                "https://example.com/favicon.png",
                "https://example.com/apple-touch-icon.png"
            ]
        );
        let windows = parse_metadata_html(
            html,
            "https://example.com/docs/page",
            MetadataCompatibilityProfile::WindowsV1,
        );
        assert_eq!(
            &windows.icon_urls[..2],
            [
                "https://example.com/mask.svg",
                "https://example.com/short.ico"
            ]
        );
    }

    #[test]
    fn parser_handles_unquoted_broken_html_and_rejects_sensitive_candidates() {
        let parsed = parse_metadata_html("<title>A &amp; B</title><meta property=og:image content=/a.png><link rel=icon href='https://x.test/a?access_token=x'><meta property=og:image content='file:///secret'>", "http://localhost:8080/page", MetadataCompatibilityProfile::MacOsV1);
        assert_eq!(parsed.title.as_deref(), Some("A & B"));
        assert_eq!(parsed.preview_urls, ["http://localhost:8080/a.png"]);
        assert_eq!(parsed.icon_urls.len(), 3);
        assert_eq!(
            parse_metadata_html(
                "<title>x",
                "https://x.test/?token=x",
                MetadataCompatibilityProfile::MacOsV1
            ),
            MetadataHTMLResult::default()
        );
    }
}
