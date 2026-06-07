package com.apkdv.clipdock.qa

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.apkdv.clipdock.MainDestination
import com.apkdv.clipdock.SettingsDetailDestination
import com.apkdv.clipdock.data.ClipDockUiState
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.OverlaySnapEdge
import com.apkdv.clipdock.theme.ClipDockTheme
import com.apkdv.clipdock.ui.main.ClipDockWebActionDispatcher
import com.apkdv.clipdock.ui.main.ClipDockWebBridge
import com.apkdv.clipdock.ui.main.ClipDockWebSurface
import com.apkdv.clipdock.ui.main.clipDockWebStateJson

class MobileV4InteractionQaActivity : ComponentActivity() {
  var copyCount: Int = 0
    private set
  var downloadAndCopyCount: Int = 0
    private set
  var downloadToCacheCount: Int = 0
    private set
  var copyThumbnailCount: Int = 0
    private set
  var deleteSyncRecordCount: Int = 0
    private set
  var removeLocalCacheCount: Int = 0
    private set
  var useCount: Int = 0
    private set
  var openSettingsDetailCount: Int = 0
    private set
  var closeSettingsDetailCount: Int = 0
    private set
  var lastActionStableId: String? = null
    private set
  var lastSettingsDetail: SettingsDetailDestination? = null
    private set

  private var screenId by mutableStateOf("history")
  private var selectedStableId by mutableStateOf<String?>(null)
  private var uiState by mutableStateOf(MobileV4QaFixtures.state())
  lateinit var webView: WebView
    private set

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    screenId = intent.getStringExtra(EXTRA_SCREEN_ID) ?: "history"
    setContent {
      ClipDockTheme {
        ClipDockWebSurface(
          screenId = screenId,
          selectedStableId = selectedStableId,
          stateJson = clipDockWebStateJson(uiState, selectedStableId = selectedStableId).toString(),
          bridge = ClipDockWebBridge({ uiState }, dispatcher = fakeDispatcher()),
          onBackFromWeb = { screenId = "history" },
          modifier = Modifier.fillMaxSize(),
          onWebViewCreated = { webView = it },
        )
      }
    }
  }

  fun removeHistoryItem(stableId: String) {
    uiState = uiState.copy(items = uiState.items.filterNot { it.stableId == stableId })
  }

  private fun recordUse(item: ClipHistoryItem) {
    useCount += 1
    lastActionStableId = item.stableId
  }

  private fun recordAction(item: ClipHistoryItem, increment: () -> Unit) {
    increment()
    lastActionStableId = item.stableId
  }

  private fun fakeDispatcher(): ClipDockWebActionDispatcher =
    object : ClipDockWebActionDispatcher {
      override suspend fun selectDestination(destination: MainDestination) {
        selectedStableId = null
        screenId =
          when (destination) {
            MainDestination.History -> "history"
            MainDestination.Devices -> "devices"
            MainDestination.Files -> "files"
            MainDestination.Settings -> "settings"
          }
      }

      override suspend fun openItemDetail(stableId: String) {
        selectedStableId = stableId
        val item = uiState.items.firstOrNull { it.stableId == stableId }
        screenId = if (item?.needsRemotePayload == true) "remote_asset_sheet" else "item_detail_text"
      }

      override suspend fun closeDetail() {
        selectedStableId = null
        screenId = "history"
      }

      override suspend fun showRemoteRetrieval(stableId: String) {
        selectedStableId = stableId
        screenId = "remote_asset_sheet"
      }

      override suspend fun hideRemoteRetrieval() {
        selectedStableId = null
        screenId = "history"
      }

      override suspend fun showDeleteConfirm(stableId: String) {
        selectedStableId = stableId
        screenId = "delete_confirm"
      }

      override suspend fun hideDeleteConfirm() {
        screenId = "item_detail_text"
      }

      override suspend fun copyItem(item: ClipHistoryItem) = recordAction(item) { copyCount += 1 }
      override suspend fun downloadAndCopy(item: ClipHistoryItem) = recordAction(item) { downloadAndCopyCount += 1 }
      override suspend fun downloadToCache(item: ClipHistoryItem) = recordAction(item) { downloadToCacheCount += 1 }
      override suspend fun copyThumbnail(item: ClipHistoryItem) = recordAction(item) { copyThumbnailCount += 1 }
      override suspend fun removeLocalCache(item: ClipHistoryItem) {
        recordAction(item) { removeLocalCacheCount += 1 }
        uiState = uiState.copy(items = uiState.items.map { if (it.stableId == item.stableId) it.copy(localUri = null) else it })
      }
      override suspend fun deleteSyncRecord(item: ClipHistoryItem) {
        recordAction(item) { deleteSyncRecordCount += 1 }
        removeHistoryItem(item.stableId)
      }
      override suspend fun syncNow() = Unit
      override suspend fun setP2pEnabled(enabled: Boolean) {
        uiState = uiState.copy(p2pEnabled = enabled)
      }
      override suspend fun setWifiOnly(enabled: Boolean) {
        uiState = uiState.copy(wifiOnly = enabled)
      }
      override suspend fun setOverlayEnabled(enabled: Boolean) {
        uiState = uiState.copy(overlayEnabled = enabled)
      }
      override suspend fun setOverlaySize(value: Int) {
        uiState = uiState.copy(overlaySizeDp = value)
      }
      override suspend fun setOverlayOpacity(value: Int) {
        uiState = uiState.copy(overlayIdleOpacityPercent = value)
      }
      override suspend fun setOverlayVerticalFraction(value: Float) {
        uiState = uiState.copy(overlayVerticalFraction = value)
      }
      override suspend fun setOverlaySnapEdge(edge: OverlaySnapEdge) {
        uiState = uiState.copy(overlaySnapEdge = edge)
      }

      override suspend fun openSettingsDetail(detail: SettingsDetailDestination) {
        openSettingsDetailCount += 1
        lastSettingsDetail = detail
        screenId =
          when (detail) {
            SettingsDetailDestination.KeepAlive -> "keep_alive"
            SettingsDetailDestination.FloatingBall -> "floating_ball"
          }
      }

      override suspend fun closeSettingsDetail() {
        closeSettingsDetailCount += 1
        screenId = "settings"
      }
    }

  companion object {
    const val EXTRA_SCREEN_ID = "screen_id"
  }
}
