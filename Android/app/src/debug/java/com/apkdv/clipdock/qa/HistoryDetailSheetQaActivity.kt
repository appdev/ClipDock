package com.apkdv.clipdock.qa

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.apkdv.clipdock.MainDestination
import com.apkdv.clipdock.SettingsDetailDestination
import com.apkdv.clipdock.data.ClipDockUiState
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.OverlayClickAction
import com.apkdv.clipdock.data.OverlaySnapEdge
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.TransferState
import com.apkdv.clipdock.theme.ClipDockTheme
import com.apkdv.clipdock.ui.main.ClipDockApp

class HistoryDetailSheetQaActivity : ComponentActivity() {
  var useCount: Int = 0
    private set
  var lastUsedStableId: String? = null
    private set

  private var selectedDestination by mutableStateOf(MainDestination.History)
  private var settingsDetail by mutableStateOf<SettingsDetailDestination?>(null)
  private var uiState by mutableStateOf(sampleState())

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    setContent {
      ClipDockTheme {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
          ClipDockApp(
            state = uiState,
            selectedDestination = selectedDestination,
            settingsDetail = settingsDetail,
            onDestinationSelected = {
              selectedDestination = it
              settingsDetail = null
            },
            onBackFromDetail = { settingsDetail = null },
            onServerUrlChange = {},
            onDeviceNameChange = {},
            onSyncNow = {},
            onCheckHealth = {},
            onCreateSyncSpace = {},
            onJoinSyncSpace = {},
            onCreateInvite = {},
            onRefreshInfo = {},
            onUseItem = { item ->
              useCount += 1
              lastUsedStableId = item.stableId
            },
            onP2pEnabledChange = { uiState = uiState.copy(p2pEnabled = it) },
            onWifiOnlyChange = { uiState = uiState.copy(wifiOnly = it) },
            onOverlayEnabledChange = { uiState = uiState.copy(overlayEnabled = it) },
            onOverlayClickActionChange = { uiState = uiState.copy(overlayClickAction = it) },
            onOverlaySnapEdgeChange = { uiState = uiState.copy(overlaySnapEdge = it) },
            onOverlaySizeChange = { uiState = uiState.copy(overlaySizeDp = it) },
            onOverlayIdleOpacityChange = { uiState = uiState.copy(overlayIdleOpacityPercent = it) },
            onOverlayVerticalFractionChange = { uiState = uiState.copy(overlayVerticalFraction = it) },
            onEncryptionEnabledChange = { uiState = uiState.copy(encryptionEnabled = it) },
            onOpenSettingsDetail = { settingsDetail = it },
          )
        }
      }
    }
  }

  fun removeHistoryItem(stableId: String) {
    uiState = uiState.copy(items = uiState.items.filterNot { it.stableId == stableId })
  }

  private fun sampleState(): ClipDockUiState =
    ClipDockUiState(
      tokenPresent = true,
      connectionStatus = "已加入",
      p2pEnabled = true,
      wifiOnly = false,
      items =
        listOf(
          sampleItem(
            stableId = READY_TEXT_ID,
            type = ClipItemType.Text,
            title = "发布说明：Android 端新增远端取回入口",
            body = "从 macOS 复制后自动同步到手机",
            sourceName = "MacBook Pro",
            payloadState = PayloadState.Ready,
          ),
          sampleItem(
            stableId = REMOTE_IMAGE_ID,
            type = ClipItemType.Image,
            title = "UI-review-screenshot.png",
            body = "image/png",
            detail = "1.2 MB",
            sourceName = "MacBook Pro",
            assetId = "asset-image",
            payloadState = PayloadState.RemoteOnly,
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
          ),
        ),
    )

  private fun sampleItem(
    stableId: String,
    type: ClipItemType,
    title: String,
    body: String,
    detail: String = type.label,
    sourceName: String?,
    assetId: String? = null,
    payloadState: PayloadState,
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
      thumbnailUri = null,
      localUri = null,
      payloadState = payloadState,
      transferState = TransferState.Idle,
      copiedAtMillis = System.currentTimeMillis(),
      copyCount = 1,
    )

  companion object {
    const val READY_TEXT_ID = "qa-ready-text"
    const val REMOTE_IMAGE_ID = "qa-remote-image"
    const val MISSING_ASSET_ID = "qa-missing-asset"
  }
}
