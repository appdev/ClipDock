package com.apkdv.clipdock

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.RemoteAssetActionResult
import java.util.concurrent.TimeUnit
import junit.framework.TestCase.assertNotNull
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidDownloadRemoteImageInstrumentedTest {
  @Test
  fun downloadsRemoteImageToLocalCache() = runBlocking {
    val contentHash = InstrumentationRegistry.getArguments().getString("contentHash").orEmpty()
    assumeTrue("Remote image download E2E requires contentHash.", contentHash.isNotBlank())

    val app = ApplicationProvider.getApplicationContext<ClipDockApplication>()
    val repository = app.repository
    repository.setP2pEnabled(true)
    repository.setWifiOnly(false)

    val item =
      waitFor("remote image item") {
        repository.syncNow().firstOrNull { candidate ->
          candidate.type == ClipItemType.Image &&
            candidate.contentHash.removePrefix("blake3:") == contentHash.removePrefix("blake3:")
        }
      }
    assertNotNull(item.thumbnailUri)
    assertNotNull(item.assetId)

    val downloaded =
      if (item.payloadState == PayloadState.Ready) {
        item
      } else {
        val result = repository.downloadToCache(item, timeoutMillis = 30_000)
        assertTrue(result is RemoteAssetActionResult.Cached)
        (result as RemoteAssetActionResult.Cached).item
      }
    assertTrue(downloaded.payloadState == PayloadState.Ready)
    assertNotNull(downloaded.localUri)
    val bytes = readContentUri(app, downloaded.localUri!!)
    assertTrue(bytes.size >= 8)
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    assertNotNull(bitmap)
    assertTrue(bitmap.width > 0)
    assertTrue(bitmap.height > 0)
  }

  private suspend fun <T : Any> waitFor(label: String, block: suspend () -> T?): T {
    val deadline = System.currentTimeMillis() + TimeUnit.SECONDS.toMillis(45)
    while (System.currentTimeMillis() < deadline) {
      block()?.let { return it }
      delay(500)
    }
    throw AssertionError("Timed out waiting for $label")
  }

  private fun readContentUri(context: Context, uri: String): ByteArray =
    context.contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
      ?: throw AssertionError("Cannot open downloaded URI: $uri")
}
