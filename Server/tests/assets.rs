mod common;

use axum::http::{header, Method, StatusCode};

use common::{asset_digest, png_1x1, TestServer};

fn thumbnail_headers(mime_type: &'static str) -> [(&'static str, &'static str); 4] {
    [
        ("content-type", mime_type),
        ("x-clipdock-asset-kind", "thumbnail"),
        ("x-clipdock-asset-width", "1"),
        ("x-clipdock-asset-height", "1"),
    ]
}

#[tokio::test]
async fn asset_upload_download_and_duplicate_upload() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let bytes = png_1x1();
    let digest = asset_digest(&bytes);
    let uri = format!("/v2/assets/{digest}");

    let upload = server
        .raw(
            Method::PUT,
            &uri,
            Some(&device.token),
            bytes.clone(),
            &thumbnail_headers("image/png"),
        )
        .await;
    assert_eq!(upload.status, StatusCode::OK, "{:?}", upload.body);

    let duplicate = server
        .raw(
            Method::PUT,
            &uri,
            Some(&device.token),
            bytes.clone(),
            &thumbnail_headers("image/png"),
        )
        .await;
    assert_eq!(duplicate.status, StatusCode::OK, "{:?}", duplicate.body);
    let duplicate_body: serde_json::Value =
        serde_json::from_slice(&duplicate.body).expect("duplicate json");
    assert_eq!(duplicate_body["data"]["already_exists"], true);

    let download = server
        .raw(Method::GET, &uri, Some(&device.token), Vec::new(), &[])
        .await;
    assert_eq!(download.status, StatusCode::OK);
    assert_eq!(download.body, bytes);
    assert_eq!(
        download.headers.get(header::CONTENT_TYPE).unwrap(),
        "image/png"
    );
    assert_eq!(download.headers.get("x-clipdock-asset-width").unwrap(), "1");
    assert_eq!(
        download.headers.get("x-clipdock-asset-height").unwrap(),
        "1"
    );
}

#[tokio::test]
async fn asset_download_is_scoped_to_the_authenticated_sync_space() {
    let server = TestServer::new().await;
    let first = server.create_sync().await;
    let second = server.create_sync().await;
    let bytes = png_1x1();
    let digest = asset_digest(&bytes);
    let uri = format!("/v2/assets/{digest}");

    let upload = server
        .raw(
            Method::PUT,
            &uri,
            Some(&first.device.token),
            bytes,
            &thumbnail_headers("image/png"),
        )
        .await;
    assert_eq!(upload.status, StatusCode::OK);

    let download_from_other_space = server
        .raw(
            Method::GET,
            &uri,
            Some(&second.device.token),
            Vec::new(),
            &[],
        )
        .await;
    assert_eq!(download_from_other_space.status, StatusCode::BAD_REQUEST);
    let body: serde_json::Value = serde_json::from_slice(&download_from_other_space.body).unwrap();
    assert_eq!(body["error"]["code"], "asset_not_found");
}

#[tokio::test]
async fn asset_auth_runs_before_existence_reveal() {
    let server = TestServer::new().await;
    let digest = asset_digest(b"not uploaded");
    let uri = format!("/v2/assets/{digest}");
    let response = server.raw(Method::GET, &uri, None, Vec::new(), &[]).await;
    assert_eq!(response.status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn asset_upload_rejects_bad_digest_oversized_and_unsupported_metadata() {
    let server = TestServer::new().await;
    let device = server.register().await;

    let sha256_digest = server
        .raw(
            Method::PUT,
            "/v2/assets/sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            Some(&device.token),
            b"not matching".to_vec(),
            &thumbnail_headers("image/png"),
        )
        .await;
    assert_eq!(sha256_digest.status, StatusCode::BAD_REQUEST);
    let sha_body: serde_json::Value = serde_json::from_slice(&sha256_digest.body).unwrap();
    assert_eq!(sha_body["error"]["code"], "invalid_digest");

    let bad_digest = server
        .raw(
            Method::PUT,
            &format!("/v2/assets/{}", "blake3:".to_string() + &"a".repeat(64)),
            Some(&device.token),
            b"not matching".to_vec(),
            &thumbnail_headers("image/png"),
        )
        .await;
    assert_eq!(bad_digest.status, StatusCode::BAD_REQUEST);
    let bad_body: serde_json::Value = serde_json::from_slice(&bad_digest.body).unwrap();
    assert_eq!(bad_body["error"]["code"], "bad_digest");

    let oversized_bytes = vec![7_u8; 2 * 1024 * 1024 + 1];
    let oversized_digest = asset_digest(&oversized_bytes);
    let oversized_uri = format!("/v2/assets/{oversized_digest}");
    let oversized = server
        .raw(
            Method::PUT,
            &oversized_uri,
            Some(&device.token),
            oversized_bytes,
            &thumbnail_headers("image/png"),
        )
        .await;
    assert_eq!(oversized.status, StatusCode::PAYLOAD_TOO_LARGE);

    let unsupported_mime = server
        .raw(
            Method::PUT,
            &format!("/v2/assets/{}", asset_digest(b"x")),
            Some(&device.token),
            b"x".to_vec(),
            &[
                ("content-type", "application/octet-stream"),
                ("x-clipdock-asset-kind", "thumbnail"),
                ("x-clipdock-asset-width", "1"),
                ("x-clipdock-asset-height", "1"),
            ],
        )
        .await;
    assert_eq!(unsupported_mime.status, StatusCode::BAD_REQUEST);

    let unsupported_kind = server
        .raw(
            Method::PUT,
            &format!("/v2/assets/{}", asset_digest(b"y")),
            Some(&device.token),
            b"y".to_vec(),
            &[
                ("content-type", "image/png"),
                ("x-clipdock-asset-kind", "avatar"),
                ("x-clipdock-asset-width", "1"),
                ("x-clipdock-asset-height", "1"),
            ],
        )
        .await;
    assert_eq!(unsupported_kind.status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn asset_upload_rejects_traversal_malformed_digest_and_metadata_conflict() {
    let server = TestServer::new().await;
    let device = server.register().await;

    let malformed = server
        .raw(
            Method::PUT,
            "/v2/assets/..%2Fsecret",
            Some(&device.token),
            b"x".to_vec(),
            &thumbnail_headers("image/png"),
        )
        .await;
    assert_eq!(malformed.status, StatusCode::BAD_REQUEST);

    let bytes = png_1x1();
    let digest = asset_digest(&bytes);
    let uri = format!("/v2/assets/{digest}");
    let ok = server
        .raw(
            Method::PUT,
            &uri,
            Some(&device.token),
            bytes.clone(),
            &thumbnail_headers("image/png"),
        )
        .await;
    assert_eq!(ok.status, StatusCode::OK);

    let conflict = server
        .raw(
            Method::PUT,
            &uri,
            Some(&device.token),
            bytes,
            &thumbnail_headers("image/jpeg"),
        )
        .await;
    assert_eq!(conflict.status, StatusCode::CONFLICT);
    let body: serde_json::Value = serde_json::from_slice(&conflict.body).unwrap();
    assert_eq!(body["error"]["code"], "metadata_conflict");
}
