package com.apkdv.clipdock.overlay

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.apkdv.clipdock.ClipDockApplication
import com.apkdv.clipdock.MainActivity
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.QuickCopyResult
import com.apkdv.clipdock.theme.ClipDockTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

class FloatingOverlayService : Service(), LifecycleOwner, SavedStateRegistryOwner {
  private val lifecycleRegistry = LifecycleRegistry(this)
  private val savedStateController = SavedStateRegistryController.create(this)
  private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

  private lateinit var windowManager: WindowManager
  private var composeView: ComposeView? = null
  private var params: WindowManager.LayoutParams? = null
  private var uiState = FloatingOverlayUiState()
  private var ballSizePx = 0

  override val lifecycle: Lifecycle
    get() = lifecycleRegistry

  override val savedStateRegistry: SavedStateRegistry
    get() = savedStateController.savedStateRegistry

  override fun onCreate() {
    super.onCreate()
    if (!Settings.canDrawOverlays(this)) {
      stopSelf()
      return
    }
    savedStateController.performAttach()
    savedStateController.performRestore(null)
    lifecycleRegistry.currentState = Lifecycle.State.CREATED
    lifecycleRegistry.currentState = Lifecycle.State.STARTED
    windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    ballSizePx = 56.dpToPx()
    addOverlay()
    observeRepository()
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onDestroy() {
    composeView?.let { windowManager.removeView(it) }
    composeView = null
    serviceScope.cancel()
    lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
    super.onDestroy()
  }

  private fun addOverlay() {
    val overlayType =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
      } else {
        @Suppress("DEPRECATION")
        WindowManager.LayoutParams.TYPE_PHONE
      }
    val layoutParams =
      WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        overlayType,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT,
      )
    layoutParams.gravity = Gravity.TOP or Gravity.START
    layoutParams.x = screenWidth() - ballSizePx - 12.dpToPx()
    layoutParams.y = 260.dpToPx()
    params = layoutParams

    composeView =
      ComposeView(this).apply {
        setViewTreeLifecycleOwner(this@FloatingOverlayService)
        setViewTreeSavedStateRegistryOwner(this@FloatingOverlayService)
        setContent {
          ClipDockTheme(dynamicColor = false) {
            FloatingOverlayContent(
              state = uiState,
              onBallClick = ::startQuickCopy,
              onDrag = ::moveBy,
              onDragEnd = ::snapToNearestEdge,
              onClosePanel = { updateUi(uiState.copy(panel = FloatingPanelState.Hidden)) },
              onRetry = ::startQuickCopy,
              onOpenApp = ::openApp,
              onCopyItem = ::copyFallbackItem,
            )
          }
        }
      }
    windowManager.addView(composeView, layoutParams)
  }

  private fun observeRepository() {
    val repository = (application as ClipDockApplication).repository
    serviceScope.launch {
      repository.state.collectLatest { state ->
        updateUi(uiState.copy(recentItems = state.items.take(5)))
      }
    }
  }

  private fun startQuickCopy() {
    if (uiState.loading) return
    val repository = (application as ClipDockApplication).repository
    updateUi(uiState.copy(loading = true, panel = FloatingPanelState.Hidden))
    serviceScope.launch {
      val result = repository.quickSyncAndCopy(timeoutMillis = 8_000)
      val panel =
        when (result) {
          is QuickCopyResult.Copied -> FloatingPanelState.Copied(result.item)
          is QuickCopyResult.Timeout -> FloatingPanelState.Timeout(result.latest, result.message)
          is QuickCopyResult.Failed -> FloatingPanelState.Failed(result.latest, result.message)
        }
      updateUi(uiState.copy(loading = false, panel = panel, recentItems = repository.state.value.items.take(5)))
    }
  }

  private fun copyFallbackItem(item: ClipHistoryItem) {
    val repository = (application as ClipDockApplication).repository
    if (repository.copyItem(item)) {
      updateUi(uiState.copy(panel = FloatingPanelState.Copied(item)))
    } else {
      updateUi(uiState.copy(panel = FloatingPanelState.Failed(item, "远程内容尚未下载，剪贴板未更改")))
    }
  }

  private fun openApp() {
    startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
  }

  private fun moveBy(dx: Float, dy: Float) {
    val layoutParams = params ?: return
    layoutParams.x = (layoutParams.x + dx.roundToInt()).coerceIn(0, screenWidth() - ballSizePx)
    layoutParams.y = (layoutParams.y + dy.roundToInt()).coerceIn(24.dpToPx(), screenHeight() - ballSizePx - 24.dpToPx())
    composeView?.let { windowManager.updateViewLayout(it, layoutParams) }
  }

  private fun snapToNearestEdge() {
    val layoutParams = params ?: return
    layoutParams.x = if (layoutParams.x + ballSizePx / 2 < screenWidth() / 2) 0 else screenWidth() - ballSizePx - 8.dpToPx()
    composeView?.let { windowManager.updateViewLayout(it, layoutParams) }
  }

  private fun updateUi(next: FloatingOverlayUiState) {
    uiState = next
    composeView?.setContent {
      ClipDockTheme(dynamicColor = false) {
        FloatingOverlayContent(
          state = uiState,
          onBallClick = ::startQuickCopy,
          onDrag = ::moveBy,
          onDragEnd = ::snapToNearestEdge,
          onClosePanel = { updateUi(uiState.copy(panel = FloatingPanelState.Hidden)) },
          onRetry = ::startQuickCopy,
          onOpenApp = ::openApp,
          onCopyItem = ::copyFallbackItem,
        )
      }
    }
  }

  private fun screenWidth(): Int =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      windowManager.currentWindowMetrics.bounds.width()
    } else {
      @Suppress("DEPRECATION")
      resources.displayMetrics.widthPixels
    }

  private fun screenHeight(): Int =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      windowManager.currentWindowMetrics.bounds.height()
    } else {
      @Suppress("DEPRECATION")
      resources.displayMetrics.heightPixels
    }

  private fun Int.dpToPx(): Int = (this * resources.displayMetrics.density).roundToInt()
}

data class FloatingOverlayUiState(
  val loading: Boolean = false,
  val panel: FloatingPanelState = FloatingPanelState.Hidden,
  val recentItems: List<ClipHistoryItem> = emptyList(),
)

sealed interface FloatingPanelState {
  data object Hidden : FloatingPanelState
  data class Copied(val item: ClipHistoryItem) : FloatingPanelState
  data class Timeout(val latest: ClipHistoryItem?, val message: String) : FloatingPanelState
  data class Failed(val latest: ClipHistoryItem?, val message: String) : FloatingPanelState
}
