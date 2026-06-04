package com.apkdv.clipdock

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.data.ClipItemType
import java.util.UUID
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidSendTextE2EInstrumentedTest {
  @Test
  fun uploadsLocalTextThroughRepository() = runBlocking {
    val args = InstrumentationRegistry.getArguments()
    val serverUrl = args.getString("serverUrl").orEmpty()
    val pairingCode = args.getString("pairingCode").orEmpty()
    val text =
      args.getString("text")
        ?.takeIf(String::isNotBlank)
        ?: "ClipDock Android runtime sent text ${UUID.randomUUID()}"
    assumeTrue(
      "Android send E2E requires serverUrl and pairingCode.",
      serverUrl.isNotBlank() && pairingCode.isNotBlank(),
    )

    val app = ApplicationProvider.getApplicationContext<ClipDockApplication>()
    val repository = app.repository
    repository.setServerUrl(serverUrl)
    repository.setDeviceName("Android sender E2E ${UUID.randomUUID().toString().take(6)}")
    repository.setP2pEnabled(true)
    repository.setWifiOnly(false)
    repository.joinSyncSpace(pairingCode)

    val push = repository.uploadLocalText(text, type = ClipItemType.Text)
    assertTrue(push.contentHash.startsWith("blake3:"))
    val items = repository.syncNow()
    val uploaded = items.first { it.contentHash == push.contentHash }
    assertEquals(ClipItemType.Text, uploaded.type)
    assertEquals(text, uploaded.body)
  }
}
