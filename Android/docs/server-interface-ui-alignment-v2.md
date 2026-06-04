# Server Interface Alignment For Android UI v2

Date: 2026-06-01
Author: Codex
Status: Design input

## Server Interface Summary

Current server routes read from `server/src/api.rs`:

- `GET /health`
- `GET /v2/info`
- `POST /v2/sync/create`
- `POST /v2/sync/join`
- `POST /v2/sync/invites`
- `POST /v2/events`
- `GET /v2/events?after_seq&limit`
- `GET /v2/snapshot`
- `PUT /v2/assets/{digest}`
- `GET /v2/assets/{digest}`

## Authentication And Pairing

The current server no longer uses a setup token registration UI.

Android must support:

- Create new sync space with `device_name`.
- Join existing sync space with a 5-character pairing code and `device_name`.
- Store returned `cds_` device token locally.
- Show `sync_id` and `device_id` after pairing.
- Generate a fresh pairing code from an authenticated device.
- Surface pairing-code expiration and single-use behavior.

Important error states:

- `unauthorized`: local token missing or invalid.
- `revoked_device`: token exists but device was revoked server-side.
- `invalid_pairing_code`: code malformed, expired, already consumed, or not found.

## Sync

The UI should show sync as a space-scoped event log:

- Initial sync: `GET /v2/snapshot`.
- Incremental sync: `GET /v2/events?after_seq&limit`.
- Push local changes: `POST /v2/events`.
- Cursor state: `next_cursor`.
- Conflict/tombstone state: `item_deleted`.

Settings should expose a diagnostics row for current cursor and last sync result. This is more useful than a generic "connected" switch because the server is event-log based.

## Assets

Server assets are not full clipboard payload storage.

Allowed server asset kinds:

- `thumbnail`
- `source_icon`
- `link_preview`

Allowed MIME types:

- `image/png`
- `image/jpeg`
- `image/webp`

UI implication:

- Main list may use server preview assets when available.
- Image/file/rich payload usage still needs an on-demand payload transfer state.
- P2P settings should be labeled as full payload transfer, separate from server preview asset sync.

## Settings Changes From v1 Design

Replace:

- `设置令牌`
- Generic `注册状态`

With:

- `创建同步空间`
- `加入同步空间`
- `生成配对码`
- `同步空间 ID`
- `本机设备 ID`
- `令牌状态`
- `服务器能力`
- `事件游标`

## Revised Settings Information Architecture

Recommended settings groups:

- `服务器`: server address, health check, protocol status.
- `同步空间`: create/join, sync ID, device ID, invite code, token state.
- `同步诊断`: snapshot, event cursor, last sync, last error.
- `预览资产`: asset kinds, MIME types, max asset size, cache.
- `完整下载`: P2P payload download, Wi-Fi-only, download address, transfer cache.
- `加密`: optional key state.
- `系统权限`: overlay, background, battery, notifications, clipboard privacy.
