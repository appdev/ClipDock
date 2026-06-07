use image::{DynamicImage, ImageFormat};
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::HashSet,
    fs,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};
use tauri::{AppHandle, Manager};
use url::Url;

const SOURCE_ICON_SIZE: u32 = 256;
const LINK_ICON_SIZE: u32 = 128;
const LINK_PREVIEW_SIZE: u32 = 640;
const MAX_HTML_BYTES: usize = 512 * 1024;
const MAX_IMAGE_BYTES: usize = 5 * 1024 * 1024;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PanelNativeAssetRequest {
    item_id: String,
    source_name: String,
    source_kind: String,
    source_path_hints: Option<PlatformPathHints>,
    link_url: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlatformPathHints {
    #[cfg_attr(not(target_os = "macos"), allow(dead_code))]
    macos: Option<Vec<String>>,
    #[cfg_attr(not(target_os = "windows"), allow(dead_code))]
    windows: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PanelNativeAssetResolution {
    items: Vec<PanelNativeAsset>,
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PanelNativeAsset {
    item_id: String,
    source_icon_path: Option<String>,
    source_icon_header_color: Option<String>,
    source_icon_error: Option<String>,
    link_icon_path: Option<String>,
    link_preview_path: Option<String>,
    link_title: Option<String>,
    link_domain: Option<String>,
    link_error: Option<String>,
}

#[derive(Debug, Default)]
struct LinkMetadataAssets {
    icon_path: Option<PathBuf>,
    preview_path: Option<PathBuf>,
    title: Option<String>,
    domain: Option<String>,
}

#[derive(Debug, Default, PartialEq, Eq)]
struct LinkImageCandidates {
    icon_urls: Vec<Url>,
    preview_urls: Vec<Url>,
}

#[tauri::command]
pub async fn resolve_panel_native_assets(
    app: AppHandle,
    requests: Vec<PanelNativeAssetRequest>,
) -> Result<PanelNativeAssetResolution, String> {
    let root = app
        .path()
        .app_local_data_dir()
        .map_err(|error| error.to_string())?
        .join("native-assets");
    fs::create_dir_all(&root).map_err(|error| error.to_string())?;

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .user_agent("ClipDock-Tauri-Panel/0.1")
        .build()
        .map_err(|error| error.to_string())?;

    let mut items = Vec::with_capacity(requests.len());
    for request in requests {
        let mut item = PanelNativeAsset {
            item_id: request.item_id.clone(),
            ..PanelNativeAsset::default()
        };

        match resolve_source_icon(&request, &root) {
            Ok(Some(path)) => {
                item.source_icon_header_color = average_icon_color(&path);
                item.source_icon_path = Some(path.display().to_string());
            }
            Ok(None) => {}
            Err(error) => item.source_icon_error = Some(error),
        }

        if let Some(link_url) = request.link_url.as_deref() {
            match fetch_link_metadata(&client, link_url, &root).await {
                Ok(metadata) => {
                    item.link_icon_path = metadata.icon_path.map(|path| path.display().to_string());
                    item.link_preview_path =
                        metadata.preview_path.map(|path| path.display().to_string());
                    item.link_title = metadata.title;
                    item.link_domain = metadata.domain;
                }
                Err(error) => item.link_error = Some(error),
            }
        }

        items.push(item);
    }

    Ok(PanelNativeAssetResolution { items })
}

fn resolve_source_icon(
    request: &PanelNativeAssetRequest,
    root: &Path,
) -> Result<Option<PathBuf>, String> {
    let Some(source_path) = first_existing_source_path(request) else {
        return Ok(None);
    };

    let output_dir = root.join("source-app-icons");
    fs::create_dir_all(&output_dir).map_err(|error| error.to_string())?;
    let output = output_dir.join(cache_file_name(
        "source",
        &format!(
            "{}:{}:{}",
            request.source_kind,
            request.source_name,
            source_path.display()
        ),
        "png",
    ));
    if !output.exists() {
        extract_source_icon_png(&source_path, &output)?;
    }
    Ok(Some(output))
}

fn first_existing_source_path(request: &PanelNativeAssetRequest) -> Option<PathBuf> {
    source_path_candidates(request)
        .into_iter()
        .find(|path| path.is_file() || path.is_dir())
}

#[cfg(target_os = "macos")]
fn source_path_candidates(request: &PanelNativeAssetRequest) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(hints) = request.source_path_hints.as_ref() {
        paths.extend(
            hints
                .macos
                .iter()
                .flatten()
                .map(PathBuf::from)
                .collect::<Vec<_>>(),
        );
    }
    paths.extend(default_macos_source_paths(
        &request.source_kind,
        &request.source_name,
    ));
    paths
}

#[cfg(target_os = "windows")]
fn source_path_candidates(request: &PanelNativeAssetRequest) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(hints) = request.source_path_hints.as_ref() {
        paths.extend(
            hints
                .windows
                .iter()
                .flatten()
                .map(expand_windows_path_hint)
                .collect::<Vec<_>>(),
        );
    }
    paths.extend(default_windows_source_paths(
        &request.source_kind,
        &request.source_name,
    ));
    paths
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn source_path_candidates(_request: &PanelNativeAssetRequest) -> Vec<PathBuf> {
    Vec::new()
}

#[cfg(target_os = "macos")]
fn default_macos_source_paths(source_kind: &str, source_name: &str) -> Vec<PathBuf> {
    let normalized = source_name.to_ascii_lowercase();
    let mut paths = match source_kind {
        "chrome" => vec!["/Applications/Google Chrome.app"],
        "safari" => vec!["/Applications/Safari.app"],
        "photos" => vec!["/System/Applications/Photos.app"],
        "finder" => vec!["/System/Library/CoreServices/Finder.app"],
        "xcode" => vec!["/Applications/Xcode.app"],
        "terminal" => vec!["/System/Applications/Utilities/Terminal.app"],
        "textedit" => vec!["/System/Applications/TextEdit.app"],
        "color" => vec!["/System/Applications/Utilities/Digital Color Meter.app"],
        "notes" => vec!["/System/Applications/Notes.app"],
        _ => Vec::new(),
    };
    if normalized.contains("digital color meter")
        && !paths
            .iter()
            .any(|path| path.contains("Digital Color Meter"))
    {
        paths.push("/System/Applications/Utilities/Digital Color Meter.app");
    }
    paths.into_iter().map(PathBuf::from).collect()
}

#[cfg(target_os = "windows")]
fn default_windows_source_paths(source_kind: &str, source_name: &str) -> Vec<PathBuf> {
    let normalized = source_name.to_ascii_lowercase();
    let program_files =
        std::env::var("ProgramFiles").unwrap_or_else(|_| String::from(r"C:\Program Files"));
    let local_app_data = std::env::var("LOCALAPPDATA").unwrap_or_default();
    let windir = std::env::var("WINDIR").unwrap_or_else(|_| String::from(r"C:\Windows"));

    let mut paths = match source_kind {
        "chrome" => vec![
            PathBuf::from(format!(
                r"{program_files}\Google\Chrome\Application\chrome.exe"
            )),
            PathBuf::from(format!(
                r"{local_app_data}\Google\Chrome\Application\chrome.exe"
            )),
        ],
        "finder" => vec![PathBuf::from(format!(r"{windir}\explorer.exe"))],
        "terminal" => vec![
            PathBuf::from(format!(r"{local_app_data}\Microsoft\WindowsApps\wt.exe")),
            PathBuf::from(format!(r"{windir}\System32\cmd.exe")),
        ],
        "textedit" => vec![PathBuf::from(format!(r"{windir}\System32\notepad.exe"))],
        "color" => vec![PathBuf::from(format!(r"{windir}\System32\mspaint.exe"))],
        _ => Vec::new(),
    };

    if normalized.contains("visual studio code") || normalized.contains("xcode") {
        paths.push(PathBuf::from(format!(
            r"{local_app_data}\Programs\Microsoft VS Code\Code.exe"
        )));
        paths.push(PathBuf::from(format!(
            r"{program_files}\Microsoft VS Code\Code.exe"
        )));
    }
    paths
}

#[cfg(target_os = "windows")]
fn expand_windows_path_hint(value: &String) -> PathBuf {
    let mut expanded = value.clone();
    for (key, replacement) in [
        ("{ProgramFiles}", std::env::var("ProgramFiles").ok()),
        ("{LOCALAPPDATA}", std::env::var("LOCALAPPDATA").ok()),
        ("{WINDIR}", std::env::var("WINDIR").ok()),
    ] {
        if let Some(replacement) = replacement {
            expanded = expanded.replace(key, &replacement);
        }
    }
    PathBuf::from(expanded)
}

#[cfg(target_os = "macos")]
fn extract_source_icon_png(source_path: &Path, output: &Path) -> Result<(), String> {
    let icon_path = find_macos_icns(source_path)?;
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let output_status = Command::new("/usr/bin/sips")
        .arg("-s")
        .arg("format")
        .arg("png")
        .arg("-z")
        .arg(SOURCE_ICON_SIZE.to_string())
        .arg(SOURCE_ICON_SIZE.to_string())
        .arg(&icon_path)
        .arg("--out")
        .arg(output)
        .output()
        .map_err(|error| error.to_string())?;
    if output_status.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output_status.stderr)
            .trim()
            .to_string())
    }
}

#[cfg(target_os = "macos")]
fn find_macos_icns(app_path: &Path) -> Result<PathBuf, String> {
    let resources = app_path.join("Contents").join("Resources");
    let info_plist = app_path.join("Contents").join("Info.plist");
    if let Ok(value) = plist::Value::from_file(&info_plist) {
        if let Some(icon_name) = value
            .as_dictionary()
            .and_then(|dictionary| dictionary.get("CFBundleIconFile"))
            .and_then(|value| value.as_string())
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let direct = resources.join(icon_name);
            if direct.exists() {
                return Ok(direct);
            }
            let icns = resources.join(format!("{icon_name}.icns"));
            if icns.exists() {
                return Ok(icns);
            }
        }
    }

    fs::read_dir(&resources)
        .map_err(|error| error.to_string())?
        .flatten()
        .map(|entry| entry.path())
        .find(|path| {
            path.extension()
                .and_then(|extension| extension.to_str())
                .map(|extension| extension.eq_ignore_ascii_case("icns"))
                .unwrap_or(false)
        })
        .ok_or_else(|| format!("no .icns found under {}", resources.display()))
}

#[cfg(target_os = "windows")]
fn extract_source_icon_png(source_path: &Path, output: &Path) -> Result<(), String> {
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }

    let script_path = std::env::temp_dir().join("clipdock_extract_associated_icon.ps1");
    fs::write(
        &script_path,
        r#"param([string]$Path, [string]$Out)
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
if ($null -eq $icon) { exit 2 }
$bitmap = $icon.ToBitmap()
$bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()
$icon.Dispose()
"#,
    )
    .map_err(|error| error.to_string())?;

    let mut last_error = None;
    for executable in ["powershell.exe", "pwsh.exe"] {
        match Command::new(executable)
            .arg("-NoProfile")
            .arg("-NonInteractive")
            .arg("-ExecutionPolicy")
            .arg("Bypass")
            .arg("-File")
            .arg(&script_path)
            .arg("-Path")
            .arg(source_path)
            .arg("-Out")
            .arg(output)
            .output()
        {
            Ok(result) if result.status.success() => return Ok(()),
            Ok(result) => {
                last_error = Some(String::from_utf8_lossy(&result.stderr).trim().to_string());
            }
            Err(error) => last_error = Some(error.to_string()),
        }
    }
    Err(last_error.unwrap_or_else(|| String::from("failed to run PowerShell icon extractor")))
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn extract_source_icon_png(_source_path: &Path, _output: &Path) -> Result<(), String> {
    Err(String::from(
        "source icon extraction is not implemented on this platform",
    ))
}

async fn fetch_link_metadata(
    client: &reqwest::Client,
    value: &str,
    root: &Path,
) -> Result<LinkMetadataAssets, String> {
    let url = Url::parse(value).map_err(|error| error.to_string())?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err(String::from("only http and https links are supported"));
    }

    let response = client
        .get(url.clone())
        .send()
        .await
        .map_err(|error| error.to_string())?;
    if !response.status().is_success() {
        return Err(format!("metadata request returned {}", response.status()));
    }
    if response.content_length().unwrap_or(0) > MAX_HTML_BYTES as u64 {
        return Err(String::from("metadata HTML is too large"));
    }
    let bytes = response.bytes().await.map_err(|error| error.to_string())?;
    let html = String::from_utf8_lossy(&bytes[..bytes.len().min(MAX_HTML_BYTES)]).into_owned();

    let title = metadata_title(&html);
    let candidates = html_image_candidates(&html, &url);
    let icon_path = download_first_image(
        client,
        &candidates.icon_urls,
        4,
        LINK_ICON_SIZE,
        &root.join("link-icons"),
        "link-icon",
    )
    .await;
    let preview_path = download_first_image(
        client,
        &candidates.preview_urls,
        4,
        LINK_PREVIEW_SIZE,
        &root.join("link-previews"),
        "link-preview",
    )
    .await;

    Ok(LinkMetadataAssets {
        icon_path,
        preview_path,
        title,
        domain: url.domain().map(ToOwned::to_owned),
    })
}

async fn download_first_image(
    client: &reqwest::Client,
    urls: &[Url],
    limit: usize,
    max_pixel_size: u32,
    output_dir: &Path,
    prefix: &str,
) -> Option<PathBuf> {
    fs::create_dir_all(output_dir).ok()?;
    for url in urls.iter().take(limit) {
        let Ok(response) = client.get(url.clone()).send().await else {
            continue;
        };
        if !response.status().is_success() {
            continue;
        }
        if response.content_length().unwrap_or(0) > MAX_IMAGE_BYTES as u64 {
            continue;
        }

        let content_type = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .unwrap_or("")
            .to_ascii_lowercase();
        if !content_type.is_empty() && !content_type.starts_with("image/") {
            continue;
        }

        let Ok(bytes) = response.bytes().await else {
            continue;
        };
        if bytes.len() > MAX_IMAGE_BYTES {
            continue;
        }

        if content_type.contains("svg")
            || url
                .path()
                .rsplit('.')
                .next()
                .map(|extension| extension.eq_ignore_ascii_case("svg"))
                .unwrap_or(false)
        {
            let output = output_dir.join(cache_file_name(prefix, url.as_str(), "svg"));
            if fs::write(&output, &bytes).is_ok() {
                return Some(output);
            }
            continue;
        }

        if let Ok(image) = image::load_from_memory(&bytes) {
            let output = output_dir.join(cache_file_name(prefix, url.as_str(), "png"));
            if write_resized_png(image, max_pixel_size, &output).is_ok() {
                return Some(output);
            }
        }
    }
    None
}

fn write_resized_png(
    image: DynamicImage,
    max_pixel_size: u32,
    output: &Path,
) -> Result<(), String> {
    let resized = image.thumbnail(max_pixel_size, max_pixel_size);
    resized
        .save_with_format(output, ImageFormat::Png)
        .map_err(|error| error.to_string())
}

fn metadata_title(html: &str) -> Option<String> {
    let document = Html::parse_document(html);
    let meta_selector = Selector::parse("meta").ok()?;
    for element in document.select(&meta_selector) {
        let key = element
            .value()
            .attr("property")
            .or_else(|| element.value().attr("name"))
            .map(|value| value.to_ascii_lowercase());
        if matches!(key.as_deref(), Some("og:title" | "twitter:title")) {
            if let Some(value) = element.value().attr("content").and_then(non_empty) {
                return Some(value.to_string());
            }
        }
    }

    let title_selector = Selector::parse("title").ok()?;
    document
        .select(&title_selector)
        .next()
        .map(|element| element.text().collect::<String>())
        .as_deref()
        .and_then(non_empty)
        .map(ToOwned::to_owned)
}

fn html_image_candidates(html: &str, base_url: &Url) -> LinkImageCandidates {
    let document = Html::parse_document(html);
    let meta_selector = Selector::parse("meta").expect("valid meta selector");
    let link_selector = Selector::parse("link").expect("valid link selector");
    let mut preview_urls = Vec::new();
    let mut icon_urls = Vec::new();

    for element in document.select(&meta_selector) {
        let key = element
            .value()
            .attr("property")
            .or_else(|| element.value().attr("name"))
            .map(|value| value.to_ascii_lowercase());
        if matches!(
            key.as_deref(),
            Some("og:image" | "og:image:url" | "twitter:image" | "twitter:image:src")
        ) {
            if let Some(url) = element
                .value()
                .attr("content")
                .and_then(|value| base_url.join(value).ok())
            {
                preview_urls.push(url);
            }
        }
    }

    for element in document.select(&link_selector) {
        let rel_tokens = element
            .value()
            .attr("rel")
            .map(|value| value.to_ascii_lowercase())
            .unwrap_or_default();
        let is_icon = rel_tokens.split_whitespace().any(|token| {
            matches!(
                token,
                "icon" | "shortcut" | "apple-touch-icon" | "mask-icon"
            )
        });
        if is_icon {
            if let Some(url) = element
                .value()
                .attr("href")
                .and_then(|value| base_url.join(value).ok())
            {
                icon_urls.push(url);
            }
        }
    }

    for fallback in ["/favicon.ico", "/favicon.png", "/apple-touch-icon.png"] {
        if let Ok(url) = base_url.join(fallback) {
            icon_urls.push(url);
        }
    }

    LinkImageCandidates {
        icon_urls: unique_urls(icon_urls),
        preview_urls: unique_urls(preview_urls),
    }
}

fn non_empty(value: &str) -> Option<&str> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

fn unique_urls(urls: Vec<Url>) -> Vec<Url> {
    let mut seen = HashSet::new();
    let mut unique = Vec::new();
    for url in urls {
        if seen.insert(url.as_str().to_string()) {
            unique.push(url);
        }
    }
    unique
}

fn average_icon_color(path: &Path) -> Option<String> {
    let image = image::open(path).ok()?.to_rgba8();
    let mut red = 0_u64;
    let mut green = 0_u64;
    let mut blue = 0_u64;
    let mut weight = 0_u64;

    for pixel in image.pixels() {
        let [r, g, b, a] = pixel.0;
        if a < 64 || (r > 242 && g > 242 && b > 242) {
            continue;
        }
        let alpha = u64::from(a);
        red += u64::from(r) * alpha;
        green += u64::from(g) * alpha;
        blue += u64::from(b) * alpha;
        weight += alpha;
    }

    if weight == 0 {
        return None;
    }

    Some(format!(
        "#{:02x}{:02x}{:02x}",
        (red / weight) as u8,
        (green / weight) as u8,
        (blue / weight) as u8
    ))
}

fn cache_file_name(prefix: &str, key: &str, extension: &str) -> String {
    let digest = Sha256::digest(key.as_bytes());
    format!("{prefix}-{:x}.{extension}", digest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageBuffer, Rgba};

    #[test]
    fn html_image_candidates_include_metadata_icons_and_fallbacks() {
        let base = Url::parse("https://example.com/path/page").unwrap();
        let candidates = html_image_candidates(
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
            &base,
        );

        assert_eq!(
            candidates.preview_urls,
            vec![
                Url::parse("https://example.com/preview.png").unwrap(),
                Url::parse("https://cdn.example.com/card.jpg").unwrap()
            ]
        );
        assert!(candidates
            .icon_urls
            .contains(&Url::parse("https://example.com/favicon-32.png").unwrap()));
        assert!(candidates
            .icon_urls
            .contains(&Url::parse("https://example.com/path/touch.png").unwrap()));
        assert!(candidates
            .icon_urls
            .contains(&Url::parse("https://example.com/favicon.ico").unwrap()));
    }

    #[test]
    fn metadata_title_prefers_social_title() {
        let title = metadata_title(
            r#"
            <html>
              <head>
                <title>Fallback title</title>
                <meta property="og:title" content="Open Graph title">
              </head>
            </html>
            "#,
        );

        assert_eq!(title.as_deref(), Some("Open Graph title"));
    }

    #[test]
    fn average_icon_color_ignores_transparent_and_white_pixels() {
        let output =
            std::env::temp_dir().join(format!("clipdock-color-test-{}.png", std::process::id()));
        let mut image = ImageBuffer::<Rgba<u8>, Vec<u8>>::new(2, 2);
        image.put_pixel(0, 0, Rgba([255, 255, 255, 255]));
        image.put_pixel(1, 0, Rgba([0, 0, 0, 0]));
        image.put_pixel(0, 1, Rgba([20, 100, 200, 255]));
        image.put_pixel(1, 1, Rgba([20, 100, 200, 255]));
        image.save(&output).unwrap();

        assert_eq!(average_icon_color(&output).as_deref(), Some("#1464c8"));
        let _ = fs::remove_file(output);
    }
}
