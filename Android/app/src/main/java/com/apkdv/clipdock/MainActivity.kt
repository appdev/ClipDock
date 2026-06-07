package com.apkdv.clipdock

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.apkdv.clipdock.overlay.FloatingOverlayService
import com.apkdv.clipdock.theme.ClipDockTheme

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    enableEdgeToEdge()
    applyMobileV4WindowInsets()
    maybeStartFloatingOverlay()
    setContent {
      ClipDockTheme { Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { MainNavigation() } }
    }
  }

  override fun onResume() {
    super.onResume()
    captureCurrentClipboardAfterFocus()
  }

  override fun onWindowFocusChanged(hasFocus: Boolean) {
    super.onWindowFocusChanged(hasFocus)
    if (hasFocus) {
      captureCurrentClipboardAfterFocus()
    }
  }

  private fun maybeStartFloatingOverlay() {
    val repository = (application as ClipDockApplication).repository
    if (repository.state.value.overlayEnabled && Settings.canDrawOverlays(this)) {
      startService(Intent(this, FloatingOverlayService::class.java))
    }
  }

  private fun captureCurrentClipboardAfterFocus() {
    window.decorView.post {
      (application as ClipDockApplication).repository.captureCurrentClipboard()
    }
  }

  private fun applyMobileV4WindowInsets() {
    WindowCompat.setDecorFitsSystemWindows(window, false)
    WindowInsetsControllerCompat(window, window.decorView).apply {
      hide(WindowInsetsCompat.Type.systemBars())
      systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }
  }
}
