package com.apkdv.clipdock.qa

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
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
import java.io.File
import org.json.JSONTokener

class MobileV4PixelQaActivity : ComponentActivity() {
  private var screenId by mutableStateOf("history")
  private var darkTheme by mutableStateOf(false)
  private var selectedStableId by mutableStateOf<String?>(null)
  private var uiState by mutableStateOf<ClipDockUiState>(MobileV4QaFixtures.state())
  private val handler = Handler(Looper.getMainLooper())
  lateinit var webView: WebView
    private set

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    WindowCompat.setDecorFitsSystemWindows(window, false)
    WindowInsetsControllerCompat(window, window.decorView).apply {
      hide(WindowInsetsCompat.Type.systemBars())
      systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }
    applyPixelIntent(intent)
    setContent {
      key(screenId, darkTheme) {
        ClipDockTheme(darkTheme = darkTheme, dynamicColor = false) {
          val dispatcher = noopDispatcher()
          ClipDockWebSurface(
            screenId = screenId,
            theme = if (darkTheme) "dark" else "light",
            selectedStableId = selectedStableId,
            stateJson = clipDockWebStateJson(uiState, selectedStableId = selectedStableId).toString(),
            bridge = ClipDockWebBridge({ uiState }, dispatcher = dispatcher),
            onBackFromWeb = {},
            modifier = Modifier.fillMaxSize(),
            onWebViewCreated = {
              webView = it
              scheduleSemanticDump()
            },
          )
        }
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    applyPixelIntent(intent)
  }

  private fun applyPixelIntent(intent: Intent) {
    screenId = intent.getStringExtra(EXTRA_SCREEN_ID) ?: "history"
    darkTheme = intent.getStringExtra(EXTRA_THEME) == "dark"
    selectedStableId = MobileV4QaFixtures.selectedStableIdForScreen(screenId)
    if (::webView.isInitialized) {
      scheduleSemanticDump()
    }
  }

  private fun scheduleSemanticDump() {
    handler.removeCallbacksAndMessages(null)
    handler.postDelayed({ writeSemanticDump() }, 1_200)
    handler.postDelayed({ writeSemanticDump() }, 2_400)
    handler.postDelayed({ writeWebViewPng() }, 2_400)
    handler.postDelayed({ writeWebViewPng() }, 4_000)
  }

  private fun writeSemanticDump() {
    if (!::webView.isInitialized) return
    webView.evaluateJavascript("JSON.stringify(window.__clipdockQaDumpSemantics && window.__clipdockQaDumpSemantics())") { raw ->
      val json =
        runCatching {
          val value = JSONTokener(raw).nextValue()
          if (value is String) value else value.toString()
        }.getOrElse { "{}" }
      val theme = if (darkTheme) "dark" else "light"
      val path = File(cacheDir, "mobile-v4-semantics/$theme/$screenId.json")
      path.parentFile?.mkdirs()
      path.writeText(json + "\n")
    }
  }

  private fun writeWebViewPng() {
    if (!::webView.isInitialized || webView.width <= 0 || webView.height <= 0) return
    val theme = if (darkTheme) "dark" else "light"
    val path = File(cacheDir, "mobile-v4-screens/$theme/$screenId.png")
    path.parentFile?.mkdirs()
    val bitmap = Bitmap.createBitmap(webView.width, webView.height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    webView.draw(canvas)
    path.outputStream().use { output -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, output) }
    bitmap.recycle()
  }

  private fun noopDispatcher(): ClipDockWebActionDispatcher =
    object : ClipDockWebActionDispatcher {
      override suspend fun selectDestination(destination: MainDestination) = Unit
      override suspend fun openItemDetail(stableId: String) = Unit
      override suspend fun closeDetail() = Unit
      override suspend fun showRemoteRetrieval(stableId: String) = Unit
      override suspend fun hideRemoteRetrieval() = Unit
      override suspend fun showDeleteConfirm(stableId: String) = Unit
      override suspend fun hideDeleteConfirm() = Unit
      override suspend fun copyItem(item: ClipHistoryItem) = Unit
      override suspend fun downloadAndCopy(item: ClipHistoryItem) = Unit
      override suspend fun downloadToCache(item: ClipHistoryItem) = Unit
      override suspend fun copyThumbnail(item: ClipHistoryItem) = Unit
      override suspend fun removeLocalCache(item: ClipHistoryItem) = Unit
      override suspend fun deleteSyncRecord(item: ClipHistoryItem) = Unit
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
      override suspend fun openSettingsDetail(detail: SettingsDetailDestination) = Unit
      override suspend fun closeSettingsDetail() = Unit
    }

  companion object {
    const val EXTRA_SCREEN_ID = "screen_id"
    const val EXTRA_THEME = "theme"
  }
}
