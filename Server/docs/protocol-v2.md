# ClipDock Sync Protocol v2

Date: 2026-06-04
Author: Codex

This protocol belongs to the ClipDock self-hosted sync server under the `Server/` subproject. It is not part of the macOS app package.

## Envelopes

Every JSON API response uses `protocol_version: 2`.

Success:

```json
{
  "protocol_version": 2,
  "data": {}
}
```

Error:

```json
{
  "protocol_version": 2,
  "error": {
    "code": "invalid_cursor",
    "message": "invalid_cursor"
  }
}
```

Asset downloads return raw bytes instead of a JSON envelope.

Protocol v1 is retired. Any `/v1/*` REST request and `/v1/ws` receives `426 Upgrade Required` with `protocol_v1_retired`; these gates do not authenticate, read or write sync data, touch asset storage, or upgrade WebSocket connections.

## Authentication

`GET /health` is unauthenticated.

The pairing endpoints below are unauthenticated:

- `POST /v2/sync/create`
- `POST /v2/sync/join`

All other `/v2/*` endpoints require:

```http
Authorization: Bearer cds_<device-token>
```

Device tokens are generated from 32 CSPRNG bytes, prefixed with `cds_`, and stored as hashes only. Revoked devices receive `403 revoked_device`.

Sync data is scoped by sync space. Devices in one sync space cannot read events, snapshots, or assets from another sync space.

Pairing codes are 5-character uppercase alphanumeric short-lived invitations. They are single-use and stored as hashes only. A joined device can create another pairing code with `POST /v2/sync/invites`.

The server treats a sync space as empty when it has no devices with `revoked_at_ms IS NULL`. It records the first empty timestamp in `sync_groups.empty_since_ms`, clears that marker when an active device exists again, and deletes spaces that remain empty for more than 10 days. Deletion removes the sync space, devices, pairing codes, events, materialized items, metadata rows, P2P records, realtime sync state, stored asset rows, and asset objects under the space's asset directory.

## Endpoints

### GET /health

Unauthenticated health check.

### GET /v2/info

Authenticated server capabilities. Returns the authenticated device's `sync_id`, `device_id`, `device_name`, supported event types, asset kinds, MIME types, BLAKE3-only `content_hash_algorithms` and `asset_digest_algorithms`, max asset size, and P2P coordination capabilities.

### POST /v2/sync/create

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

### POST /v2/sync/join

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

### POST /v2/sync/invites

Authenticated endpoint to create a fresh pairing code for the authenticated device's sync space.

Response data:

```json
{
  "sync_id": "sync_...",
  "pairing_code": "9Z8Y7",
  "pairing_expires_at_ms": 1780320000000
}
```

### POST /v2/events

Authenticated batch push. Supported event types are `item_upsert` and `item_delete`.

`item_upsert`:

```json
{
  "events": [
    {
      "client_event_id": "local-uuid",
      "type": "item_upsert",
      "content_hash": "blake3:<64 lowercase hex>",
      "item_type": "text",
      "payload": {"text": "hello"},
      "copy_count_delta": 1
    }
  ]
}
```

`copy_count_delta` must be from `1` through `100`. Active items are deduped by `(sync_id, content_hash)`. Replaying the same `(device_id, client_event_id)` is idempotent and does not increment `copy_count` again.
Clipboard payloads may include `source_app_name`, `source_bundle_id`, and `source_platform`.
`source_platform` is optional; Android-originated clipboard content should send `"source_platform": "android"`
so macOS can render an Android platform source icon instead of treating the device as a macOS application.

`item_delete`:

```json
{
  "events": [
    {
      "client_event_id": "local-delete-uuid",
      "type": "item_delete",
      "content_hash": "blake3:<64 lowercase hex>"
    }
  ]
}
```

Deletes create tombstones within a sync space. A later `item_upsert` for the same content hash clears the tombstone and restores the item as active content.

### GET /v2/events?after_seq&limit

Authenticated event pull for the authenticated device's sync space. `after_seq` is exclusive and defaults to `0`. `limit` defaults to `500` and is capped at `1000`.

- Negative, non-integer, or overflowing `after_seq` returns `400 invalid_cursor`.
- `limit <= 0` returns `400 invalid_limit`.
- Pulling after the latest event returns an empty event list and `next_cursor` equal to the latest server sequence.

### GET /v2/snapshot

Authenticated materialized snapshot for the authenticated device's sync space. The server reads a transaction, sets `snapshot_seq = max(sync_events.server_seq)` in that sync space, and returns active items plus tombstones with `last_server_seq <= snapshot_seq`. Clients should then pull `/v2/events?after_seq=<snapshot_seq>`.

### GET /v2/ws

Authenticated realtime WebSocket stream for the authenticated device's sync space.

Connection URL:

```text
/v2/ws?cursor=<last-applied-server-seq>&protocol_version=2
```

The WebSocket upgrade request uses the same bearer token as authenticated REST endpoints:

```http
Authorization: Bearer cds_<device-token>
```

`cursor` is required and must be a non-negative integer. `protocol_version=2` is required. Bad auth fails before the upgrade with the normal HTTP error envelope. Invalid cursor returns `400 invalid_cursor`; a missing or non-2 protocol version returns `400 unsupported_protocol_version`.

After a successful upgrade, messages are JSON objects with a top-level `type`.

Server `hello`:

```json
{
  "type": "hello",
  "protocol_version": 2,
  "sync_id": "sync_...",
  "device_id": "dev_...",
  "latest_seq": 42,
  "cursor": 40
}
```

If the supplied cursor is behind the current sync-space sequence, the server sends `catchup_required` immediately after `hello`:

```json
{
  "type": "catchup_required",
  "after_seq": 40,
  "latest_seq": 42,
  "reason": "cursor_behind"
}
```

Clients receiving `catchup_required` should pull `/v2/events?after_seq=<after_seq>` or, when the local store cannot reconcile the gap, use `/v2/snapshot` and then pull from the returned snapshot cursor. WebSocket delivery remains an acceleration path; HTTP catch-up and snapshot correction are the authoritative recovery paths.

Server `event_batch`:

```json
{
  "type": "event_batch",
  "batch_id": "sync_...:41:42",
  "from_seq": 41,
  "to_seq": 42,
  "events": []
}
```

`events` uses the same event shape returned by `GET /v2/events`. Clients must apply the batch durably before acknowledging it. Acknowledgement is client-to-server:

```json
{
  "type": "ack",
  "server_seq": 42
}
```

The server stores the largest acknowledged sequence per device and ignores stale duplicate acknowledgements. Negative acknowledgements return `error` code `invalid_ack`; acknowledgements above the current sync-space latest sequence return `error` code `future_ack`.

Server `error`:

```json
{
  "type": "error",
  "code": "malformed_json",
  "message": "malformed_json"
}
```

Malformed client JSON causes `error` code `malformed_json` and the server closes the socket. Unknown client messages return `error` code `unknown_message`. If the server drops a subscriber because its realtime channel overflows, the socket receives `error` code `slow_consumer` and closes. Clients must not acknowledge unapplied or malformed data; after malformed input, protocol errors that close the socket, or `slow_consumer`, they should close any local WebSocket state, run HTTP catch-up or snapshot correction from the last durably applied cursor, then reconnect with backoff using `protocol_version=2`.

Protocol v1 has no realtime compatibility mode. `/v1/ws` returns `426 Upgrade Required` with `protocol_v1_retired`, performs no authentication or sync-data side effects, and never upgrades to a WebSocket. Clients must move to `/v2/ws` and `protocol_version=2`; the server does not dual-write, auto-upgrade, or translate v1 realtime connections.

### PUT /v2/assets/{digest}

Authenticated raw asset upload. The server authenticates before checking asset existence.

Supported headers:

```http
Content-Type: image/png
X-ClipDock-Asset-Kind: thumbnail
```

Allowed kinds: `thumbnail`, `source_icon`, `link_preview`.

Allowed MIME types: `image/png`, `image/jpeg`, `image/webp`.

Digest format: `blake3:<64 lowercase hex>`.

The server computes BLAKE3 over the request body and rejects mismatches with `400 bad_digest`. The default max upload size is `2 MiB`. Uploads are written to staging and atomically promoted inside the authenticated sync space. Duplicate upload with the same metadata in the same sync space returns `200` with `already_exists: true`; metadata conflict returns `409 metadata_conflict`.

### GET /v2/assets/{digest}

Authenticated raw asset download from the authenticated device's sync space. Returns the stored bytes with `Content-Type` and `X-ClipDock-Asset-Kind`.

## P2P Coordination Metadata

The server does not transfer real large image/file payloads through these P2P endpoints. It only coordinates metadata so clients in the same sync space can discover peers and decide whether to download through direct P2P, relay, or a future server-cache fallback.

The intended data plane is client-side `iroh-blobs`. The server stores opaque endpoint IDs, provider records, and optional quality reports. Clients should keep reporting fresh endpoint/provider state while they are available to serve blobs.

### PUT /v2/p2p/endpoint

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

### GET /v2/p2p/devices

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

### PUT /v2/p2p/assets/{asset_id}/providers/me

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

### DELETE /v2/p2p/assets/{asset_id}/providers/me

Marks the calling device's provider record as offline for that asset.

Response data:

```json
{
  "asset_id": "blake3:<52 lowercase RFC4648 base32 chars>",
  "removed": true
}
```

### GET /v2/p2p/assets/{asset_id}/providers

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

The current schema includes:

- `sync_schema_migrations`
- `sync_groups` with `empty_since_ms` for empty-space retention cleanup
- `pairing_codes`
- `devices`
- `sync_items`
- `sync_events`
- `sync_assets`
- `sync_item_assets`
- `device_p2p_endpoints`
- `asset_providers`
- `device_sync_state`
- `sync_file_items`
- `sync_link_metadata`

SQLite runs with WAL, foreign keys enabled, and a busy timeout.
