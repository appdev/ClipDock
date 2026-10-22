use clipboard_core::metadata::{
    metadata_limits, metadata_url_policy, parse_metadata_html, MetadataCompatibilityProfile,
    MetadataURLFacts,
};
use image::{DynamicImage, ImageFormat};
use std::{
    fs,
    path::{Path, PathBuf},
    time::Duration,
};
use url::Url;

#[path = "metadata_attempt.rs"]
mod attempt;
#[path = "metadata_transport.rs"]
mod transport;
use attempt::MetadataAttempt;
pub(super) use transport::MetadataTransport;

const LINK_ICON_SIZE: u32 = 128;
const LINK_PREVIEW_SIZE: u32 = 640;
const PROFILE: MetadataCompatibilityProfile = MetadataCompatibilityProfile::WindowsV1;

#[derive(Debug, Default)]
pub(super) struct LinkMetadataAssets {
    pub icon_path: Option<PathBuf>,
    pub preview_path: Option<PathBuf>,
    pub title: Option<String>,
    pub domain: Option<String>,
}

pub(super) fn transport() -> Result<MetadataTransport, String> {
    let limits = metadata_limits(PROFILE);
    MetadataTransport::new(
        Duration::from_millis(limits.page_timeout_ms),
        Duration::from_millis(limits.image_timeout_ms),
        limits.max_redirects,
    )
}

fn ensure_url_allowed(url: &Url) -> Result<(), String> {
    let decision = metadata_url_policy(&MetadataURLFacts {
        scheme: Some(url.scheme().to_owned()),
        host: url.host_str().map(str::to_owned),
        query_names: url
            .query_pairs()
            .map(|(name, _)| name.into_owned())
            .collect(),
    });
    if !decision.supported {
        return Err("only http and https links with a host are supported".into());
    }
    if decision.privacy_sensitive {
        return Err("metadata URL contains a sensitive query name".into());
    }
    Ok(())
}

pub(super) async fn fetch_link_metadata(
    client: &MetadataTransport,
    value: &str,
    root: &Path,
) -> Result<LinkMetadataAssets, String> {
    let url = Url::parse(value).map_err(|_| "metadata URL is invalid")?;
    let limits = metadata_limits(PROFILE);
    let response = client
        .get(
            url.clone(),
            limits.max_html_bytes,
            false,
            ensure_url_allowed,
        )
        .await?;
    let html = String::from_utf8_lossy(&response.bytes);
    // The resolved URL is only the base for fetching resources, never item identity.
    let candidates = parse_metadata_html(&html, response.final_url.as_str(), PROFILE);
    let attempt = MetadataAttempt::create(root)?;
    let icon_path = download_first_image(
        client,
        &candidates.icon_urls,
        limits.max_icon_candidates,
        limits.max_image_bytes,
        LINK_ICON_SIZE,
        attempt.path(),
        "icon",
    )
    .await;
    let preview_path = download_first_image(
        client,
        &candidates.preview_urls,
        limits.max_preview_candidates,
        limits.max_image_bytes,
        LINK_PREVIEW_SIZE,
        attempt.path(),
        "preview",
    )
    .await;
    if icon_path.is_some() || preview_path.is_some() {
        attempt.retain();
    }
    Ok(LinkMetadataAssets {
        icon_path,
        preview_path,
        title: candidates.title,
        domain: url.domain().map(ToOwned::to_owned),
    })
}

async fn download_first_image(
    client: &MetadataTransport,
    urls: &[String],
    candidate_limit: usize,
    byte_limit: usize,
    max_pixel_size: u32,
    output_dir: &Path,
    prefix: &str,
) -> Option<PathBuf> {
    for (index, value) in urls.iter().take(candidate_limit).enumerate() {
        let Ok(url) = Url::parse(value) else {
            continue;
        };
        let Ok(response) = client.get(url, byte_limit, true, ensure_url_allowed).await else {
            continue;
        };
        let svg = response.content_type.contains("svg")
            || response
                .final_url
                .path()
                .rsplit('.')
                .next()
                .is_some_and(|extension| extension.eq_ignore_ascii_case("svg"));
        let output = output_dir.join(format!(
            "{prefix}-{index}.{}",
            if svg { "svg" } else { "png" }
        ));
        if svg {
            if fs::write(&output, &response.bytes).is_ok() {
                return Some(output);
            }
        } else if let Ok(image) = image::load_from_memory(&response.bytes) {
            if write_resized_png(image, max_pixel_size, &output).is_ok() {
                return Some(output);
            }
        }
        let _ = fs::remove_file(output);
    }
    None
}

fn write_resized_png(
    image: DynamicImage,
    max_pixel_size: u32,
    output: &Path,
) -> Result<(), String> {
    image
        .thumbnail(max_pixel_size, max_pixel_size)
        .save_with_format(output, ImageFormat::Png)
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_privacy_policy_blocks_initial_images_and_redirects_before_network() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let sensitive = format!(
            "http://{}/private?access_%74oken=fixture",
            listener.local_addr().unwrap()
        );
        let directory = tempfile::tempdir().unwrap();
        tauri::async_runtime::block_on(async {
            let client = transport().unwrap();
            assert!(matches!(
                fetch_link_metadata(&client, &sensitive, directory.path()).await,
                Err(error) if error.contains("sensitive query name")
            ));
            assert!(download_first_image(
                &client,
                &[sensitive],
                4,
                1024,
                LINK_ICON_SIZE,
                directory.path(),
                "icon",
            )
            .await
            .is_none());
            assert_eq!(
                listener.accept().unwrap_err().kind(),
                std::io::ErrorKind::WouldBlock
            );
            assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 0);

            let (url, worker) = transport::tests::server(vec![
                "HTTP/1.1 302 Found\r\nLocation: /private?session-id=fixture\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".into(),
            ]);
            assert!(matches!(
                fetch_link_metadata(&client, url.as_str(), directory.path()).await,
                Err(error) if error.contains("sensitive query name")
            ));
            assert_eq!(worker.join().unwrap().len(), 1);
        });
    }

    #[test]
    fn direct_helper_uses_attempt_scoped_assets_without_overwriting_previous_results() {
        let response = |content_type: &str, body: &str| {
            format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()
        )
        };
        let html = r#"<title>Fixture &amp; title</title><link rel="icon" href="/icon.svg"><meta property="og:image" content="/preview.svg">"#;
        let first_svg =
            r#"<svg xmlns="http://www.w3.org/2000/svg"><title>first fixture</title></svg>"#;
        let next_svg =
            r#"<svg xmlns="http://www.w3.org/2000/svg"><title>next fixture</title></svg>"#;
        let (url, worker) = transport::tests::server(vec![
            response("text/html", html),
            response("image/svg+xml", first_svg),
            response("image/svg+xml", first_svg),
            response("text/html", html),
            response("image/svg+xml", next_svg),
            response("image/svg+xml", next_svg),
        ]);
        let directory = tempfile::tempdir().unwrap();
        let (first, next) = tauri::async_runtime::block_on(async {
            let client = transport().unwrap();
            let first = fetch_link_metadata(&client, url.as_str(), directory.path())
                .await
                .unwrap();
            let next = fetch_link_metadata(&client, url.as_str(), directory.path())
                .await
                .unwrap();
            (first, next)
        });
        assert_eq!(worker.join().unwrap().len(), 6);
        assert_eq!(first.title.as_deref(), Some("Fixture & title"));
        let first_icon = first.icon_path.unwrap();
        let next_icon = next.icon_path.unwrap();
        assert_ne!(first_icon, next_icon);
        assert_eq!(fs::read(first_icon).unwrap(), first_svg.as_bytes());
        assert_eq!(fs::read(next_icon).unwrap(), next_svg.as_bytes());
        assert_ne!(first.preview_path, next.preview_path);
    }
    #[test]
    fn html_image_candidates_include_metadata_icons_and_fallbacks() {
        let candidates = parse_metadata_html(
            r#"
            <html>
              <head>
                <meta property="og:image" content="/preview.png">
                <meta name="twitter:image:src" content="https://cdn.example.com/card.jpg">
                <link rel="shortcut icon" href="/favicon-32.png">
                <link rel="apple-touch-icon" href="touch.png">
              </head>
            </html>
            "#,
            "https://example.com/path/page",
            PROFILE,
        );

        assert_eq!(
            candidates.preview_urls,
            vec![
                "https://example.com/preview.png",
                "https://cdn.example.com/card.jpg"
            ]
        );
        assert!(candidates
            .icon_urls
            .contains(&"https://example.com/favicon-32.png".to_owned()));
        assert!(candidates
            .icon_urls
            .contains(&"https://example.com/path/touch.png".to_owned()));
        assert!(candidates
            .icon_urls
            .contains(&"https://example.com/favicon.ico".to_owned()));
    }

    #[test]
    fn metadata_title_prefers_social_title() {
        let metadata = parse_metadata_html(
            r#"
            <html>
              <head>
                <title>Fallback title</title>
                <meta property="og:title" content="Open Graph title">
              </head>
            </html>
            "#,
            "https://example.com/page",
            PROFILE,
        );

        assert_eq!(metadata.title.as_deref(), Some("Open Graph title"));
    }
}
