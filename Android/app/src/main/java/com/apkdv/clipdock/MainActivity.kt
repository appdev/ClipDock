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
import com.apkdv.clipdock.overlay.FloatingOverlayService
import com.apkdv.clipdock.theme.ClipDockTheme

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    enableEdgeToEdge()
    maybeStartFloatingOverlay()
    setContent {
      ClipDockTheme { Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { MainNavigation() } }
    }
  }

  private fun maybeStartFloatingOverlay() {
    val repository = (application as ClipDockApplication).repository
    if (repository.state.value.overlayEnabled && Settings.canDrawOverlays(this)) {
      startService(Intent(this, FloatingOverlayService::class.java))
    }
  }
}
