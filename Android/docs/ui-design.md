# ClipDock Android UI Design

Date: 2026-06-02
Author: Codex

## Scope

This document defines the first Android UI direction for ClipDock. It covers:

- Main app history list for server-synced clipboard items.
- Settings and permission configuration.
- Global floating ball and compact recent-history panel.

The Android directory now contains the Kotlin + Compose client implementation created after design review moved into implementation.

## Source Context

Local implementation references:

- `macOS/Sources/ClipboardPanelApp/PanelItemCardPresentation.swift`: item type mapping and display text rules.
- `macOS/Sources/ClipboardPanelApp/PanelItemCardViewState.swift`: card state, preview state, asset request fields.
- `macOS/Sources/ClipDock/PanelItemCardRenderer.swift`: visual hierarchy for card header, source icon, preview body, footer metadata.
- `macOS/Sources/ClipDock/PreferencesUI.swift`: grouped settings layout and permission row pattern.
- `macOS/rust/crates/clipboard_core/src/domain.rs`: item types and item summary fields.
- `macOS/rust/crates/clipboard_core/src/storage/queries.rs`: current summary query fields.
- `Server/docs/protocol-v2.md`: sync event, snapshot, asset upload/download contract.
- `Server/src/assets.rs`: server-side asset kinds and MIME constraints.

External platform references:

- Android Jetpack Compose lazy lists: https://developer.android.com/develop/ui/compose/lists
- Compose Material 3 release/API surface: https://developer.android.com/jetpack/androidx/releases/compose-material3
- Overlay permission API: https://developer.android.com/reference/android/provider/Settings.html#canDrawOverlays(android.content.Context)
- Doze/App Standby guidance: https://developer.android.com/training/monitoring-device-state/doze-standby
- Android clipboard privacy guidance: https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling

## Current Data Contract Constraints

The macOS Rust core exposes item summaries with:

- `item_type`: `text`, `link`, `image`, `file`, `color`, `rich_text`, `unknown`.
- `summary`, `primary_text`, `content_hash`.
- source app fields: `source_app_id`, `source_app_name`, `source_app_icon_path`, `source_app_icon_header_color`.
- asset fields: `preview_asset_path`, `payload_asset_path`, `preview_state`, `payload_state`.
- file details: `file_items[]` with `path`, `file_name`, `file_extension`, `byte_count`, `is_directory`, optional dimensions and content type.
- link metadata: canonical URL, display URL, host, title, site name, icon asset, image asset, fetch state.

The server v2 stores generic JSON payloads for `item_upsert`, supports BLAKE3-addressed preview assets for `thumbnail`, `source_icon`, and `link_preview` images, and exposes P2P coordination metadata for full image/file payload transfer. Android UI should model payload retrieval as an on-demand transport state that can be backed by P2P without changing the visible hierarchy.

Current server sync contract:

- `GET /health` is unauthenticated.
- `POST /v2/sync/create` creates a new sync space and returns `sync_id`, a 5-character `pairing_code`, `pairing_expires_at_ms`, `device_id`, and `token`.
- `POST /v2/sync/join` joins an existing sync space with `pairing_code` and `device_name`, returning `sync_id`, `device_id`, and `token`.
- `POST /v2/sync/invites` is authenticated and creates a fresh pairing code for the current sync space.
- `GET /v2/info` is authenticated and returns `sync_id`, supported event types, asset kinds, asset MIME types, and max asset size.
- `POST /v2/events`, `GET /v2/events`, and `GET /v2/snapshot` are authenticated and scoped to the current sync space.
- `PUT/GET /v2/assets/{digest}` are authenticated and scoped to the current sync space.
- Device tokens use the `cds_` prefix and are never shown again after create/join except as a local secure-storage state.
- Pairing codes are single-use, short-lived, uppercase alphanumeric invitations; invalid, expired, or consumed codes surface as `invalid_pairing_code`.

## Product Structure

Use Jetpack Compose and Material 3. The main app should be calm, dense, and utility-focused rather than a marketing surface.

Top-level destinations:

- `History`: recent synced clipboard records.
- `Settings`: server, download, encryption, permissions, cache.

Use a bottom navigation bar on phones. On tablets or foldables, use a navigation rail. The first screen after launch is `History`, not an onboarding page. If critical setup is incomplete, show an inline setup banner at the top of `History` and an action that jumps to `Settings`.

## Visual Direction

Carry over macOS visual hierarchy, adapted to Android:

- Neutral surfaces with dynamic color support.
- Per-type accents for quick scanning, but avoid a single-hue UI.
- Type badge and source identity are always visible.
- Metadata is secondary and compact.
- Image/file payloads are never eagerly downloaded for the list. Thumbnails are allowed when available.

Recommended type accents:

- Text and rich text: neutral surface, document icon.
- Link: blue accent, host-first presentation.
- Image: teal/green accent, thumbnail or image placeholder.
- File: amber accent, filename-first presentation.
- Color: swatch-first presentation with hex value.
- Unknown: neutral warning treatment, no destructive actions.

## History List

Use `Scaffold` with:

- Top app bar: `ClipDock`, sync state chip, search icon, settings icon.
- Optional filter row: `全部`, `文字`, `链接`, `图片`, `文件`, `颜色`.
- `LazyColumn` with stable item keys from `content_hash` or local item ID.
- Paging-ready data flow, since the server event stream and local Rust list can grow without a hard item limit.

### Row Anatomy

Each history row is a single card-like list item with stable height:

- Leading block: source app icon if available, otherwise type icon in a tinted circle.
- Header row: type label, source name, relative time.
- Body: type-specific primary content.
- Footer: copy count, payload state, file size/resolution/host where useful.
- Trailing block: thumbnail or placeholder for image/file/link preview.

Do not nest cards inside cards. Each item is one row surface with a maximum 8dp corner radius.

### Type Presentation

Text:

- Body uses up to 3 lines of `primary_text` or `summary`.
- Footer shows approximate character count.
- Tap copies text. Long press opens actions.

Rich text:

- Body shows plain-text summary.
- Type label says `富文本`.
- Footer shows rich text state and size when available.
- Tap retrieves rich payload if needed, then writes rich data where supported; fallback action is `复制为纯文本`.

Link:

- Primary line is `link_metadata.title` when present, otherwise host.
- Secondary line is display URL.
- Trailing thumbnail is link preview image if synced; otherwise favicon/icon if synced; otherwise link icon.
- Tap copies URL. Secondary action opens browser.

Color:

- Leading or trailing block is a color swatch.
- Primary line is normalized hex.
- Secondary line can show source/time.
- Tap copies hex value.

Image:

- If `preview_state=ready` and a thumbnail is present, show the thumbnail.
- If no thumbnail is present, show an image icon or loading/skeleton tile; do not use a Chinese text placeholder such as `[图片]` in the main history list.
- Do not show the original full image in the list.
- Show an explicit row action for remote payloads: `下载` or `取回`. Tapping the row or this action starts on-demand payload retrieval. During transfer show inline progress/state, then copy/share after ready.

File:

- Primary line is first filename from `file_items`, otherwise parsed summary.
- Secondary line shows count, extension, size, or directory indicator.
- Trailing block shows file thumbnail if a synced thumbnail exists; otherwise file/folder icon.
- For compact text-only surfaces, show the filename only; truncate middle for long names.
- Show an explicit `下载` or `取回` row action when the full payload is remote-only. Tap starts on-demand payload retrieval through P2P when needed.

Unknown:

- Show `未知类型`, summary text, and a disabled or cautious action state.

### States

History screen states:

- `Needs setup`: no device token or server URL; show top setup banner.
- `Syncing`: inline progress in top app bar, list remains usable.
- `Empty`: concise empty state with setup/sync action.
- `Offline`: keep cached list, show reconnect banner.
- `Error`: retry banner with error code, no modal unless user action failed.
- `Loading more`: bottom row progress.
- `Payload pending`: row-level transfer chip; the item remains visible and selectable.

## Settings

Use grouped settings sections, mirroring the macOS `PreferencesUI` pattern: section title, rounded group surface, rows with title/detail/control. Keep all critical setup on one screen for early builds; later split into destinations when the list grows.

### Server And Sync Space

Rows:

- `服务端地址`: URL text field, validate scheme and host; `检查连接` calls `/health`.
- `同步空间`: shows current `sync_id` after authentication.
- `本机设备`: editable `device_name`; after pairing also shows local `device_id`.
- `连接状态`: `未设置`, `可连接`, `已加入`, `令牌失效`, `设备已撤销`, `服务器不可达`.
- `创建同步空间`: calls `/v2/sync/create`; show returned 5-character pairing code and expiration countdown for inviting another device.
- `加入同步空间`: 5-character pairing code field plus device name; calls `/v2/sync/join`.
- `生成配对码`: authenticated action using `/v2/sync/invites`.
- `服务器能力`: after `/v2/info`, show protocol version, asset kinds, MIME types, and max asset size.
- `立即同步`: fetch snapshot, then pull events from current cursor.

The setup-token concept should not appear in Android UI because the current server does not expose a setup-token registration endpoint.

### Sync Diagnostics

Rows:

- `事件游标`: shows current `after_seq` / `next_cursor`.
- `快照同步`: action for `/v2/snapshot`.
- `增量同步`: action for `/v2/events?after_seq&limit`.
- `最后错误`: maps protocol errors such as `unauthorized`, `revoked_device`, `invalid_pairing_code`, `invalid_cursor`, and `item_deleted`.

### Download And P2P

Rows:

- `下载地址`: default storage/cache root or download destination label.
- `服务端预览资产`: status for `thumbnail`, `source_icon`, and `link_preview`.
- `P2P 下载`: enabled switch, with current peer availability state.
- `仅 Wi-Fi 下载`: switch.
- `缓存上限`: selector.
- `清理缓存`: action row.

UI contract:

- Server assets are preview assets only, with allowed MIME types `image/png`, `image/jpeg`, and `image/webp`.
- Server-reported max asset size should be displayed from `/v2/info`, currently defaulting to 2 MiB in the server.
- P2P is an implementation detail until it fails.
- Remote image/file rows must expose a visible action entry, not just a passive state chip. The primary label may be `下载`, `取回`, or `下载并复制` depending on space.
- On item use, show `查找设备`, `下载中`, `已就绪`, or `下载失败`.
- If a server fallback is later added, expose it as secondary text, not as a separate primary action.

### Encryption

Rows:

- `加密密钥`: optional key/passphrase setup.
- `密钥状态`: `未启用`, `已启用`, `需要输入`, `不匹配`.
- `更换密钥`: destructive-confirmed flow.

Do not display raw key material after entry. Store through Android secure storage once implementation starts.

### Permissions

Rows:

- `全局悬浮窗`: checks `Settings.canDrawOverlays(context)` and opens `ACTION_MANAGE_OVERLAY_PERMISSION`.
- `后台运行`: explains current foreground/background sync state; use notification/foreground-service design when sync is active.
- `电池优化`: checks `PowerManager.isIgnoringBatteryOptimizations()`. Prefer opening battery optimization settings; direct exemption requests should be reserved for cases where the core feature is broken by Doze/App Standby.
- `通知`: required if a foreground service or visible sync status notification is used.
- `剪贴板隐私`: use sensitive clipboard flags when writing sensitive or encrypted payloads.

Permission rows must be status-first. Use action buttons only when the current state is insufficient.

## Floating Ball

The floating ball is a system overlay, not a normal in-app FAB.

### Resting State

- Size: 52-56dp touch target.
- Shape: circle with ClipDock glyph or clipboard icon.
- Resting position: snapped to left or right screen edge.
- Inactive visual: slightly reduced alpha and a small visible handle at the edge; never fully hidden.
- Respect display cutouts, gesture navigation, keyboard, and status/nav bars.

### Drag Behavior

- Finger drag moves the overlay in screen coordinates.
- Movement is bounded to safe screen insets.
- On release, snap to the nearest horizontal edge while preserving vertical position.
- Store normalized edge and vertical offset, not raw pixels, so rotation and display-size changes recover cleanly.
- Add short spring/ease-out animation. Avoid bounce that crosses system gesture areas.

### Tap Behavior

Tap is a quick sync-and-copy action, not a panel opener. A single tap immediately starts one foreground sync pass and then writes the most recent usable item into the Android system clipboard. During the loading phase, do not show any compact panel. The floating ball itself is the only visible progress surface until the operation completes or times out.

Tap sequence:

1. Start one sync pass using the current authenticated sync space.
2. Switch the floating ball into loading state with an inline progress ring.
3. Pull and apply the latest snapshot/events according to the local cursor state.
4. Select the newest non-deleted usable item after sync.
5. Write that item to the system clipboard.
6. Show a compact panel only after the operation completes or the timeout is reached.

Failure rules:

- If sync fails before a fresh newest item is resolved, do not overwrite the current clipboard automatically; show the error and offer the cached latest item as a manual row action.
- If the newest item is text, link, color, or plain rich-text fallback, write it as soon as sync completes.
- If the newest item is an image or file and the full payload is already local, write the corresponding `ClipData` / content URI.
- If the newest item is an image or file and the payload is remote-only, continue showing only the floating-ball loading state while P2P retrieval is within the timeout window, then write to clipboard after the payload is ready.
- If the timeout is reached before sync or P2P retrieval completes, show the compact timeout panel and leave the current clipboard unchanged.
- If sync or P2P fails before timeout, treat that as loading completion and show the compact result panel with retry/open-main-app actions.

Panel rules:

- Width: 280-320dp on phones, constrained by safe bounds.
- Max height: min(360dp, 40% screen height).
- Panel is not visible while loading.
- Panel becomes visible only when loading completes or timeout is reached.
- Top state row shows one of `已复制最新内容`, `同步失败`, `下载失败`, or `同步超时`.
- Shows the latest 5-7 synced records as fallback choices.
- No image thumbnails in compact panel.
- Image row text is `[图片]`.
- File row text is filename only, middle-truncated if long.
- Text/link rows are single-line or two-line max.
- After the panel is visible, tapping a row copies/uses that specific item; if payload is not local, start on-demand transfer and keep the compact panel open with progress.
- Long press opens main app on the selected item.
- Outside tap closes the panel.

Compact row anatomy:

- Type icon.
- Primary text.
- Secondary tiny metadata: type/time or transfer state.
- Optional progress ring for active download.

### Accessibility

- Floating ball content description: `同步并复制最新内容`.
- Compact panel rows include type and action, for example `图片，点击下载并复制`.
- Minimum touch target remains 48dp.
- Provide a settings option to disable the overlay.

## Android UI Model

Initial UI model should be independent from macOS-specific path assumptions:

```kotlin
data class ClipHistoryItemUi(
    val stableId: String,
    val contentHash: String,
    val type: ClipItemType,
    val title: String,
    val body: String,
    val detail: String,
    val sourceName: String?,
    val sourceIconRef: AssetRef?,
    val thumbnailRef: AssetRef?,
    val payloadRef: PayloadRef?,
    val previewState: PreviewState,
    val payloadState: PayloadState,
    val transferState: TransferState,
    val copiedAtMillis: Long,
    val copyCount: Long,
)
```

```kotlin
enum class ClipItemType { Text, Link, Image, File, Color, RichText, Unknown }
enum class PreviewState { Ready, Deferred, TooLarge, MissingSource, Failed }
enum class PayloadState { Pending, Ready, Failed, RemoteOnly }
enum class TransferState { Idle, DiscoveringPeer, Downloading, Ready, Failed }
```

`RemoteOnly` is an Android-side extension for synced metadata whose full payload has not been downloaded. If the Rust protocol later adds a first-class state, map it there.

## Implementation Notes For The Next Step

- Create a native Android project under `Android/` with Kotlin, Compose, Material 3, Room or SQLDelight for local cache, and a sync module that maps server payload JSON into UI models.
- Keep the main history list local-first: read cached items immediately, then apply server snapshot/events.
- Do not block list rendering on thumbnails or payload downloads.
- Treat P2P download as a repository/use-case layer invoked by item actions, not by composables.
- Add emulator QA early for overlay permission, edge snapping, compact panel bounds, rotation, and Doze recovery.

## Open Protocol Questions

- What exact server payload JSON will represent text, rich text, color, link metadata, image thumbnail digest, file metadata, and P2P payload references?
- Will full payloads ever be uploaded to the server as fallback, or is P2P mandatory for image/file/rich text payloads?
- How should encrypted payload metadata be advertised without leaking filenames, dimensions, or link titles when encryption is enabled?
- Should Android write copied remote content back into its local Rust-compatible store, or maintain an Android-native cache schema?
