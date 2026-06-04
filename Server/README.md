# ClipDock Sync Server

Self-hosted ClipDock sync server v2. This Rust subproject lives under `Server/` in the ClipDock workspace and is separate from the macOS app package.

## Features

- Rust HTTP server with Axum.
- SQLite persistence with WAL, foreign keys, busy timeout, and checksummed migrations.
- Sync spaces created from clients, with 5-character pairing codes for joining another device.
- Device-token authentication after pairing; device tokens are stored as hashes only.
- Event-log/cursor sync for `item_upsert` and `item_delete`, scoped to each sync space.
- Idempotent event replay by `(device_id, client_event_id)`.
- Snapshot reads for active items and tombstones.
- Local filesystem asset storage with server-side BLAKE3 verification, atomic promotion, and sync-space isolation.
- P2P coordination metadata for device endpoint discovery, asset provider lookup, and reported path quality. The server stores metadata only; real large payload transfer remains client-to-client.
- Empty sync-space retention cleanup: spaces with no active devices are marked and deleted with their data after 10 days.

## Run

```bash
cd /Volumes/extendData/Data/IdeaProjects/ClipDock/Server
cargo run
```

Optional configuration:

```bash
cargo run -- \
  --bind 127.0.0.1:8787 \
  --database data/clipdock-sync.sqlite \
  --assets data/assets \
  --max-asset-bytes 2097152
```

Environment variables with the same meaning are also supported:

- `CLIPDOCK_BIND_ADDR`
- `CLIPDOCK_DATABASE`
- `CLIPDOCK_ASSET_DIR`
- `CLIPDOCK_MAX_ASSET_BYTES`

## Deployment Boundary

This v2 server is for self-hosted sync. Run it on localhost, a private network, or behind an HTTPS reverse proxy for real use. Do not expose it directly over the public internet without TLS, request-size limits, backups, and normal host hardening.

Device tokens are generated as `cds_` tokens from 32 CSPRNG bytes. Only SHA-256 token hashes are stored. Pairing codes are 5-character uppercase alphanumeric short-lived invitations and are stored as hashes only. Pairing codes are for joining a sync space; they are not long-term passwords.

The server URL alone does not grant access to existing data. A client must either create a new sync space or join an existing one with a valid pairing code. After joining, that client can read and write all data in that sync space.

P2P endpoints and asset providers are also scoped to the sync space. A device in another sync space cannot discover those endpoints or provider records even if it knows the server URL or an asset id.

The current P2P layer is a coordination layer. Clients report an `iroh-blobs` compatible endpoint id, optional relay/direct address hints, provider records for large payload assets, and optional quality metrics. The server does not run Iroh, does not perform NAT traversal itself, and does not relay file bytes in this step.

A sync space with no active devices is marked empty. If it remains empty for more than 10 days, the server deletes the space, its database rows, and stored asset objects for that space.

## API

See [docs/protocol-v2.md](docs/protocol-v2.md).

## Package

Server release archives use the repository release version from
`../version.properties` unless `--version` is provided explicitly.

Package the current host target:

```bash
scripts/package-server.sh
```

Package a specific target:

```bash
scripts/package-server.sh \
  --target x86_64-unknown-linux-gnu \
  --version 0.1.9 \
  --output-dir ../.codex/artifacts/server/0.1.9
```

Supported release targets:

- `x86_64-unknown-linux-gnu` -> Linux x86_64 `.tar.gz`
- `aarch64-unknown-linux-gnu` -> Linux arm64 `.tar.gz`
- `x86_64-apple-darwin` -> macOS x86_64 `.tar.gz`
- `aarch64-apple-darwin` -> macOS arm64 `.tar.gz`
- `x86_64-pc-windows-msvc` -> Windows x86_64 `.zip`
- `aarch64-pc-windows-msvc` -> Windows arm64 `.zip`

## Verification

```bash
cargo fmt --check
cargo test
cargo clippy --all-targets -- -D warnings
```

Run a live two-device pairing/sync/P2P-metadata probe against a temporary local server:

```bash
python3 tools/sync_flow_probe.py
```

Run the same probe against an already running server:

```bash
python3 tools/sync_flow_probe.py --base-url http://127.0.0.1:8787
```
