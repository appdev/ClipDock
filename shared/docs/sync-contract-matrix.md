# ClipDock Sync Contract Matrix

Updated on 2026-06-04 by Codex.

This matrix defines the protocol facts that belong in `shared/rust/clipdock_sync_contract`.
Platform runtime behavior remains owned by Server, macOS, and Android.

| Protocol fact | Current owners | Shared API | Consumers | Fixture coverage |
| --- | --- | --- | --- | --- |
| Protocol version and v1 retired error | `Server/src/lib.rs`, `Server/src/api.rs`, `Server/src/errors.rs` | `PROTOCOL_VERSION`, `PROTOCOL_V1_RETIRED_ERROR` | Server envelopes/routes, client tests | `/v2/info` positive, `/v1/*` expected `426 protocol_v1_retired` |
| Event types | Server `api.rs/events.rs`, macOS Swift/Rust, Android Kotlin | `EVENT_TYPES`, per-event constants | `/v2/info`, Server validation, client apply/outbox tests | `item_upsert`, `item_delete`, `item_payload_asset_update` |
| `ContentHash` | Server `hashes.rs`, macOS hash key helpers, Android Kotlin mirrors | `ContentHash::parse_strict`, `ContentHash::normalize_client`, `local_key` | Server strict inbound, client outbound/local lookup | strict rejects bare/uppercase/wrong algorithm; client normalizes bare/uppercase |
| Raw asset digest | Server `hashes.rs/assets.rs`, Android thumbnail cache/upload | `AssetDigest::parse_strict`, `AssetDigest::from_bytes` | `/v2/assets/{digest}`, thumbnail upload/cache tests | strict `blake3:<64 lowercase hex>` only |
| P2P asset ID | Server `p2p.rs`, macOS/Android P2P payloads | `P2pAssetId::parse_strict` | P2P provider endpoints, payload asset update shape | `sha256:<64 hex>`, `blake3:<64 hex>`, `blake3:<52 base32>` |
| Asset kinds and image MIME types | Server `assets.rs/api.rs`, Android upload/cache | `ASSET_KINDS`, `IMAGE_ASSET_MIME_TYPES` | `/v2/info`, raw asset upload, clients | `thumbnail`, `source_icon`, `link_preview`; png/jpeg/webp |
| Thumbnail policy | Server `assets.rs/api.rs`, Android preparer, thumbnail codec | `THUMBNAIL_POLICY`, byte constants | Server caps, codec, Android preparer | normal `262144`, detail `393216`, max `786432` |
| Image asset dimensions | Server `assets.rs/api.rs`, Android preparer | `ASSET_MAX_DIMENSION_PX`, `ASSET_MAX_PIXELS` | Server decode validation, platform image preparers | max dimension `8192`, pixels `16777216` |
| Thumbnail payload shape | Server `events.rs`, macOS apply, Android models | `ThumbnailMetadata::parse_shape_strict` | Server precheck, fixture-locked client tests | all five fields together, image-only, positive numeric metadata |
| Payload asset update shape | Server `events.rs`, macOS/Android apply | `PayloadAssetUpdate::parse_shape_strict` | Server precheck, client apply tests | only `payload_asset_id` plus optional equal `asset_id` |
| P2P provider kinds | Server `p2p.rs/events.rs`, clients | `P2P_PROVIDER_KINDS`, per-kind constants | P2P provider registration, payload update provider checks | `image_payload`, `file_payload`, `thumbnail` |

Server-only behavior that must not move into the contract crate:
asset existence, stored metadata matching, provider ownership and kind lookup, image container/MIME/dimension decode, staging/promote, DB transactions, idempotency, lifecycle errors, and realtime broadcast.
