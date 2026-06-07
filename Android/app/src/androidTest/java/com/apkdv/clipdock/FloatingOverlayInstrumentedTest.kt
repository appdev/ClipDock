package com.apkdv.clipdock

import android.content.Intent
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.apkdv.clipdock.overlay.FloatingOverlayService
import junit.framework.TestCase.assertNotNull
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FloatingOverlayInstrumentedTest {
  @Test
  fun overlayPermissionAndServiceStartAreAvailable() {
    runBlocking {
      val app = ApplicationProvider.getApplicationContext<ClipDockApplication>()
      assertTrue("SYSTEM_ALERT_WINDOW must be allowed before this smoke test.", Settings.canDrawOverlays(app))
      app.repository.setOverlayEnabled(true)
      assertTrue("Overlay preference should be enabled for the floating-ball smoke test.", app.repository.state.value.overlayEnabled)

      val component = app.startService(Intent(app, FloatingOverlayService::class.java))
      assertNotNull(component)
      delay(1_000)
      app.stopService(Intent(app, FloatingOverlayService::class.java))
    }
  }
}
