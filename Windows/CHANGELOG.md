# ClipDock Windows Panel — Changelog

## 0.2.4

- Import and export clipboard history as a single `.clipdock` backup using the shared Rust core. Merge records, deduplicate content and preserve pinboards without changing application settings.
- Restore stored images and rich-text resources; external file entries retain their original paths. Existing retention settings still apply.
- Keep clipboard capture responsive during backup resource I/O and preserve local pin state in search and pinboard views.
- Refresh preferences styling with native window effects, theme support and keyboard focus indicators.

## 0.2.3

- Rename cards inline from the context menu, F2 or Ctrl+R. Enter or blur saves; Escape cancels; a blank name restores the default label.
- Keep the new title visible while saving, serialize consecutive edits, and restore the last saved name if persistence fails. Chinese IME candidate confirmation does not submit the edit.
- Preserve names across restarts and repeated captures; search custom titles in Chinese or full pinyin without altering clipboard payloads.
- Attach persisted database ids to newly captured cards so renaming works immediately. Keep title text clear of the source icon.
- Uses the existing schema 18; no additional database migration.

## 0.2.2

- Update the shared storage core to schema 18, preserving custom card titles in clipboard history and making them searchable.
- Keep the existing Windows panel interactions. Inline card renaming is currently available only in the macOS app.
- Opening an existing database upgrades it automatically; restoring an older app requires a pre-upgrade database backup.

## 0.2.1

- Remove cross-device sync and P2P transfer, including preferences and tray actions. Clipboard history remains local; existing local records and downloaded files are preserved.

## 0.2.0

The Windows panel graduates from a local-only UI shell into a persistent,
syncing clipboard client built on the shared `clipboard_core` engine.

### Added
- **Local persistence** — captured clipboard items (text and images) are
  stored in SQLite (schema v15, identical to macOS) and survive restarts.
- **Bidirectional sync** — create or join a sync space from Preferences; text
  captures push to the server and remote changes apply locally. Outbound and
  inbound both verified end to end against the real sync server.
- **Realtime delivery** — a `/v2/ws` WebSocket connection applies remote events
  within seconds, backed by a 15s HTTP poll loop as a safety net.
- **Image thumbnail sync** — captured images generate an adaptive WebP
  thumbnail that uploads to the server and propagates as an image event.
- **P2P discovery** — the device registers its endpoint with the server and can
  list peers in the sync space (direct iroh blob transfer is a later step).
- **System tray menu** — show/hide panel, sync now, preferences, copy
  diagnostics, and quit.

### Changed
- Backend now depends directly on `clipboard_core` rather than a bespoke
  storage schema, guaranteeing cross-platform parity.
- Preferences (including sync credentials) persist in the core database.

### Added (completing the sync feature set)
- **Live UI refresh on sync** — the panel reloads automatically when remote
  changes arrive, so synced items appear without a restart.
- **Inbound thumbnail display** — thumbnails for synced remote images are
  downloaded and shown as previews.
- **Full-resolution P2P image transfer** — full images transfer directly
  between devices over iroh-blobs. The transport now lives in the shared
  `clipdock_p2p` crate used by both macOS and Windows, and devices register
  their real iroh endpoint (reachable addresses) for discovery.
- **Accurate copy counts** — outbound events send the per-upload increment, so
  remote copy counts no longer drift on re-copy (schema v16).

### Known limitations
- A clean Windows `.exe`/`.msi` must be produced on a Windows machine/CI
  (cannot cross-build from macOS).
