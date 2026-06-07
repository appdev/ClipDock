package com.apkdv.clipdock.qa

import com.apkdv.clipdock.MainDestination
import com.apkdv.clipdock.SettingsDetailDestination
import com.apkdv.clipdock.data.ClipDockUiState
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.OverlayClickAction
import com.apkdv.clipdock.data.OverlaySnapEdge
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.P2pDeviceInfo
import com.apkdv.clipdock.data.P2pEndpointInfo
import com.apkdv.clipdock.data.SyncDiagnostics
import com.apkdv.clipdock.data.TransferState
import com.apkdv.clipdock.ui.main.MobileV4InitialSheet

internal object MobileV4QaFixtures {
  const val READY_TEXT_ID = "qa-ready-text"
  const val REMOTE_IMAGE_ID = "qa-remote-image"
  const val READY_FILE_ID = "qa-ready-file"
  const val READY_LINK_ID = "qa-link"
  const val READY_COLOR_ID = "qa-color"
  const val MISSING_ASSET_ID = "qa-missing-asset"

  fun state(): ClipDockUiState =
    ClipDockUiState(
      serverUrl = "https://sync.example.com",
      deviceName = "Pixel 9 Pro",
      syncId = "clipdock-home",
      deviceId = "android-pixel",
      tokenPresent = true,
      connectionStatus = "实时已连接",
      diagnostics = SyncDiagnostics(snapshotSeq = 40, nextCursor = 40, lastSyncAtMillis = System.currentTimeMillis() - 2_000),
      p2pEnabled = true,
      wifiOnly = false,
      overlayEnabled = true,
      overlayClickAction = OverlayClickAction.QuickSyncCopy,
      overlaySnapEdge = OverlaySnapEdge.Right,
      overlaySizeDp = 64,
      overlayIdleOpacityPercent = 78,
      overlayVerticalFraction = 0.35f,
      p2pDevices =
        listOf(
          P2pDeviceInfo(
            deviceId = "macbook-pro",
            deviceName = "MacBook Pro",
            endpoint =
              P2pEndpointInfo(
                endpointId = "mac-endpoint",
                relayUrl = null,
                directAddresses = emptyList(),
                capabilities = "{}",
                updatedAtMillis = System.currentTimeMillis() - 2_000,
                expiresAtMillis = System.currentTimeMillis() + 60_000,
              ),
          ),
          P2pDeviceInfo(
            deviceId = "ipad",
            deviceName = "iPad",
            endpoint =
              P2pEndpointInfo(
                endpointId = "ipad-endpoint",
                relayUrl = null,
                directAddresses = emptyList(),
                capabilities = "{}",
                updatedAtMillis = System.currentTimeMillis() - 18 * 60_000,
                expiresAtMillis = System.currentTimeMillis() - 1_000,
              ),
          ),
        ),
      items =
        listOf(
          sampleItem(
            stableId = READY_TEXT_ID,
            type = ClipItemType.Text,
            title = "发布说明：Android 端新增远端取回入口",
            body = "从 macOS 复制后自动同步到手机。点击详情不立即覆盖系统剪贴板，用户通过底部主按钮复制。",
            detail = "sync_policy: text_auto, asset_on_demand\nsource_device: MacBook Pro\ncreated_at: 2026-06-04 09:38",
            sourceName = "MacBook Pro",
            payloadState = PayloadState.Ready,
            copiedAtMillis = System.currentTimeMillis() - 180_000,
          ),
          sampleItem(
            stableId = REMOTE_IMAGE_ID,
            type = ClipItemType.Image,
            title = "UI-review-screenshot.png",
            body = "image/png",
            detail = "1.2 MB",
            sourceName = "MacBook Pro",
            assetId = "blake3:${"b".repeat(64)}",
            thumbnailUri = "file:///data/data/com.apkdv.clipdock/files/clipdock-thumbnails/qa/thumb.webp",
            payloadState = PayloadState.RemoteOnly,
            copiedAtMillis = System.currentTimeMillis() - 9 * 60_000,
          ),
          sampleItem(
            stableId = READY_LINK_ID,
            type = ClipItemType.Link,
            title = "docs.clipdock.app/server/setup",
            body = "自托管服务端部署与配对说明",
            detail = "链接",
            sourceName = "MacBook Pro",
            payloadState = PayloadState.Ready,
            copiedAtMillis = System.currentTimeMillis() - 47 * 60_000,
          ),
          sampleItem(
            stableId = READY_FILE_ID,
            type = ClipItemType.File,
            title = "Server-config.txt",
            body = "text/plain",
            detail = "12 KB",
            sourceName = "MacBook Pro",
            assetId = "blake3:${"c".repeat(64)}",
            localUri = "content://com.apkdv.clipdock.files/p2p_payloads/Server-config.txt",
            payloadState = PayloadState.Ready,
            copiedAtMillis = System.currentTimeMillis() - 68 * 60_000,
          ),
          sampleItem(
            stableId = READY_COLOR_ID,
            type = ClipItemType.Color,
            title = "#7C3AED",
            body = "RGB 124,58,237 · Android accent",
            detail = "颜色",
            sourceName = "MacBook Pro",
            payloadState = PayloadState.Ready,
            copiedAtMillis = System.currentTimeMillis() - 86 * 60_000,
          ),
          sampleItem(
            stableId = MISSING_ASSET_ID,
            type = ClipItemType.File,
            title = "missing-asset.pdf",
            body = "application/pdf",
            detail = "PDF",
            sourceName = "MacBook Pro",
            assetId = null,
            payloadState = PayloadState.RemoteOnly,
            copiedAtMillis = System.currentTimeMillis() - 85 * 60_000,
          ),
        ),
    )

  fun routeForScreen(screenId: String): QaRoute =
    when (screenId) {
      "devices" -> QaRoute(destination = MainDestination.Devices)
      "files" -> QaRoute(destination = MainDestination.Files)
      "settings" -> QaRoute(destination = MainDestination.Settings)
      "keep_alive" -> QaRoute(destination = MainDestination.Settings, settingsDetail = SettingsDetailDestination.KeepAlive)
      "floating_ball" -> QaRoute(destination = MainDestination.Settings, settingsDetail = SettingsDetailDestination.FloatingBall)
      "item_detail_text" -> QaRoute(destination = MainDestination.History, itemDetailStableId = READY_TEXT_ID)
      "remote_asset_sheet" -> QaRoute(destination = MainDestination.History, itemDetailStableId = REMOTE_IMAGE_ID, initialSheet = MobileV4InitialSheet.RemoteRetrieval)
      "delete_confirm" -> QaRoute(destination = MainDestination.History, itemDetailStableId = READY_TEXT_ID, initialSheet = MobileV4InitialSheet.DeleteConfirm)
      else -> QaRoute(destination = MainDestination.History)
    }

  fun selectedStableIdForScreen(screenId: String): String? =
    when (screenId) {
      "item_detail_text",
      "delete_confirm" -> READY_TEXT_ID
      "remote_asset_sheet" -> REMOTE_IMAGE_ID
      else -> null
    }

  private fun sampleItem(
    stableId: String,
    type: ClipItemType,
    title: String,
    body: String,
    detail: String,
    sourceName: String?,
    assetId: String? = null,
    thumbnailUri: String? = null,
    localUri: String? = null,
    payloadState: PayloadState,
    copiedAtMillis: Long,
  ): ClipHistoryItem =
    ClipHistoryItem(
      stableId = stableId,
      contentHash = "blake3:" + stableId.encodeToByteArray().joinToString("") { "%02x".format(it.toInt() and 0xff) }.padEnd(64, '0').take(64),
      type = type,
      title = title,
      body = body,
      detail = detail,
      sourceName = sourceName,
      assetId = assetId,
      thumbnailUri = thumbnailUri,
      thumbnailDigest = null,
      thumbnailMimeType = null,
      thumbnailByteCount = null,
      thumbnailWidth = null,
      thumbnailHeight = null,
      localUri = localUri,
      payloadState = payloadState,
      transferState = TransferState.Idle,
      copiedAtMillis = copiedAtMillis,
      copyCount = 1,
    )
}

internal data class QaRoute(
  val destination: MainDestination,
  val settingsDetail: SettingsDetailDestination? = null,
  val itemDetailStableId: String? = null,
  val initialSheet: MobileV4InitialSheet? = null,
)
