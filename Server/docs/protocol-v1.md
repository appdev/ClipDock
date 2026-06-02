# ClipDock Sync Protocol v1

Date: 2026-06-01
Author: Codex

This protocol belongs to the ClipDock self-hosted sync server under the `Server/` subproject. It is not part of the macOS app package.

## Envelopes

Every JSON API response uses `protocol_version: 1`.

Success:

```json
{
  "protocol_version": 1,
  "data": {}
}
```

Error:

```json
{
  "protocol_version": 1,
  "error": {
    "code": "invalid_cursor",
    "message": "invalid_cursor"
  }
}
```

Asset downloads return raw bytes instead of a JSON envelope.

## Authentication

`GET /health` is unauthenticated.

The pairing endpoints below are unauthenticated:

- `POST /v1/sync/create`
- `POST /v1/sync/join`

All other `/v1/*` endpoints require:

```http
Authorization: Bearer cds_<device-token>
```

Device tokens are generated from 32 CSPRNG bytes, prefixed with `cds_`, and stored as hashes only. Revoked devices receive `403 revoked_device`.

Sync data is scoped by sync space. Devices in one sync space cannot read events, snapshots, or assets from another sync space.

Pairing codes are 5-character uppercase alphanumeric short-lived invitations. They are single-use and stored as hashes only. A joined device can create another pairing code with `POST /v1/sync/invites`.

## Endpoints

### GET /health

Unauthenticated health check.

### GET /v1/info

Authenticated server capabilities. Returns the authenticated device's `sync_id`, `device_id`, `device_name`, supported event types, asset kinds, MIME types, max asset size, and P2P coordination capabilities.

### POST /v1/sync/create

Create a new sync space and register the calling device as the first member.

Request:

```json
{
  "device_name": "MacBook"
}
```

Response data:

```json
{
  "sync_id": "sync_...",
  "pairing_code": "A1B2C",
  "pairing_expires_at_ms": 1780320000000,
  "device_id": "dev_...",
  "token": "cds_..."
}
```

### POST /v1/sync/join

Join an existing sync space with a pairing code.

Request:

```json
{
  "pairing_code": "A1B2C",
  "device_name": "Android Phone"
}
```

Response data:

```json
{
  "sync_id": "sync_...",
  "device_id": "dev_...",
  "token": "cds_..."
}
```

Invalid, expired, or already consumed pairing codes return `403 invalid_pairing_code`.

### POST /v1/sync/invites

Authenticated endpoint to create a fresh pairing code for the authenticated device's sync space.

Response data:

```json
{
  "sync_id": "sync_...",
  "pairing_code": "9Z8Y7",
  "pairing_expires_at_ms": 1780320000000
}
```

### POST /v1/events

Authenticated batch push. Supported event types are `item_upsert` and `item_delete`.

`item_upsert`:

```json
{
  "events": [
    {
      "client_event_id": "local-uuid",
      "type": "item_upsert",
      "content_hash": "sha256:<64 lowercase hex>",
      "item_type": "text",
      "payload": {"text": "hello"},
      "copy_count_delta": 1
    }
  ]
}
```

`copy_count_delta` must be from `1` through `100`. Active items are deduped by `(sync_id, content_hash)`. Replaying the same `(device_id, client_event_id)` is idempotent and does not increment `copy_count` again.

`item_delete`:

```json
{
  "events": [
    {
      "client_event_id": "local-delete-uuid",
      "type": "item_delete",
      "content_hash": "sha256:<64 lowercase hex>"
    }
  ]
}
```

Delete wins within a sync space. After a content hash has a tombstone in that sync space, a later upsert for the same content hash returns `409 item_deleted`.

### GET /v1/events?after_seq&limit

Authenticated event pull for the authenticated device's sync space. `after_seq` is exclusive and defaults to `0`. `limit` defaults to `500` and is capped at `1000`.

- Negative, non-integer, or overflowing `after_seq` returns `400 invalid_cursor`.
- `limit <= 0` returns `400 invalid_limit`.
- Pulling after the latest event returns an empty event list and `next_cursor` equal to the latest server sequence.

### GET /v1/snapshot

Authenticated materialized snapshot for the authenticated device's sync space. The server reads a transaction, sets `snapshot_seq = max(sync_events.server_seq)` in that sync space, and returns active items plus tombstones with `last_server_seq <= snapshot_seq`. Clients should then pull `/v1/events?after_seq=<snapshot_seq>`.

### PUT /v1/assets/{digest}

Authenticated raw asset upload. The server authenticates before checking asset existence.

Supported headers:

```http
Content-Type: image/png
X-ClipDock-Asset-Kind: thumbnail
```

Allowed kinds: `thumbnail`, `source_icon`, `link_preview`.

Allowed MIME types: `image/png`, `image/jpeg`, `image/webp`.

Digest format: `sha256:<64 lowercase hex>`.

The server computes SHA-256 over the request body and rejects mismatches with `400 bad_digest`. The default max upload size is `2 MiB`. Uploads are written to staging and atomically promoted inside the authenticated sync space. Duplicate upload with the same metadata in the same sync space returns `200` with `already_exists: true`; metadata conflict returns `409 metadata_conflict`.

### GET /v1/assets/{digest}

Authenticated raw asset download from the authenticated device's sync space. Returns the stored bytes with `Content-Type` and `X-ClipDock-Asset-Kind`.

## P2P Coordination Metadata

The server does not transfer real large image/file payloads through these P2P endpoints. It only coordinates metadata so clients in the same sync space can discover peers and decide whether to download through direct P2P, relay, or a future server-cache fallback.

The intended data plane is client-side `iroh-blobs`. The server stores opaque endpoint IDs, provider records, and optional quality reports. Clients should keep reporting fresh endpoint/provider state while they are available to serve blobs.

### PUT /v1/p2p/endpoint

Authenticated endpoint report for the calling device.

Request:

```json
{
  "endpoint_id": "iroh-node-id-or-client-opaque-id",
  "relay_url": "https://relay.example.com",
  "direct_addresses": ["/ip4/192.168.1.10/udp/4433/quic-v1"],
  "capabilities": {
    "transport": "iroh-blobs",
    "blob_transfer": true
  },
  "quality": {
    "path_type": "direct",
    "rtt_ms": 14,
    "throughput_bytes_per_sec": 8000000
  },
  "ttl_ms": 120000
}
```

`capabilities` and `quality` must be JSON objects. `ttl_ms` defaults to the server capability value and is capped at 30 minutes.

Response data:

```json
{
  "device_id": "dev_...",
  "endpoint": {
    "endpoint_id": "iroh-node-id-or-client-opaque-id",
    "relay_url": "https://relay.example.com",
    "direct_addresses": ["/ip4/192.168.1.10/udp/4433/quic-v1"],
    "capabilities": {"transport": "iroh-blobs", "blob_transfer": true},
    "quality": {"path_type": "direct", "rtt_ms": 14},
    "updated_at_ms": 1780320000000,
    "expires_at_ms": 1780320120000
  }
}
```

### GET /v1/p2p/devices

Authenticated discovery for fresh P2P endpoints in the authenticated device's sync space. Expired endpoints and revoked devices are not returned.

Response data:

```json
{
  "devices": [
    {
      "device_id": "dev_...",
      "device_name": "MacBook",
      "endpoint": {
        "endpoint_id": "iroh-node-id",
        "relay_url": "https://relay.example.com",
        "direct_addresses": [],
        "capabilities": {"blob_transfer": true},
        "quality": {"path_type": "relay"},
        "updated_at_ms": 1780320000000,
        "expires_at_ms": 1780320120000
      }
    }
  ]
}
```

### PUT /v1/p2p/assets/{asset_id}/providers/me

Authenticated provider registration for the calling device. This says "my device can serve this blob"; it does not upload the blob to the server.

Supported `asset_id` formats:

- `sha256:<64 lowercase hex>`
- `blake3:<64 lowercase hex>`
- `blake3:<52 lowercase RFC4648 base32 chars>` for native `iroh-blobs` hash strings

Request:

```json
{
  "kind": "file_payload",
  "byte_count": 7340032,
  "mime_type": "application/pdf",
  "availability": "online",
  "quality": {
    "last_probe_path": "direct",
    "throughput_bytes_per_sec": 12000000
  },
  "ttl_ms": 300000
}
```

Allowed provider kinds: `image_payload`, `file_payload`, `thumbnail`.

Allowed availability values: `online`, `last_seen`, `offline`. Missing availability defaults to `online`. `quality` must be a JSON object.

### DELETE /v1/p2p/assets/{asset_id}/providers/me

Marks the calling device's provider record as offline for that asset.

Response data:

```json
{
  "asset_id": "blake3:<52 lowercase RFC4648 base32 chars>",
  "removed": true
}
```

### GET /v1/p2p/assets/{asset_id}/providers

Authenticated provider lookup in the caller's sync space. Active non-offline provider rows are returned. If the provider is still fresh but its endpoint report expired, `availability` is returned as `last_seen` and `endpoint` is `null`.

Response data:

```json
{
  "asset_id": "blake3:<52 lowercase RFC4648 base32 chars>",
  "providers": [
    {
      "device_id": "dev_...",
      "device_name": "MacBook",
      "kind": "file_payload",
      "byte_count": 7340032,
      "mime_type": "application/pdf",
      "availability": "online",
      "quality": {"throughput_bytes_per_sec": 12000000},
      "updated_at_ms": 1780320000000,
      "expires_at_ms": 1780320300000,
      "endpoint": {
        "endpoint_id": "iroh-node-id",
        "relay_url": "https://relay.example.com",
        "direct_addresses": [],
        "capabilities": {"blob_transfer": true},
        "quality": {"path_type": "direct"},
        "updated_at_ms": 1780320000000,
        "expires_at_ms": 1780320120000
      }
    }
  ]
}
```

Clients should compare their own measured direct P2P, relay, and server-cache throughput. The server only stores reported metrics; it does not make path-switching decisions.

## SQLite Schema

The v1 schema includes:

- `sync_schema_migrations`
- `sync_groups`
- `pairing_codes`
- `devices`
- `sync_items`
- `sync_events`
- `sync_assets`
- `sync_item_assets`
- `device_p2p_endpoints`
- `asset_providers`
- `sync_file_items`
- `sync_link_metadata`

SQLite runs with WAL, foreign keys enabled, and a busy timeout.
