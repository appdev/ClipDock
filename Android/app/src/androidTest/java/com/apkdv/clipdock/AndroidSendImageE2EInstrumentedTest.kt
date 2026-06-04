package com.apkdv.clipdock

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.PayloadState
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.TimeUnit
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertNotNull
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidSendImageE2EInstrumentedTest {
  private val httpClient =
    OkHttpClient.Builder()
      .connectTimeout(5, TimeUnit.SECONDS)
      .readTimeout(15, TimeUnit.SECONDS)
      .build()

  @Test
  fun capturesClipboardImageUploadsThumbnailAndPayloadProvider() = runBlocking {
    val args = InstrumentationRegistry.getArguments()
    val serverUrl = args.getString("serverUrl").orEmpty()
    val pairingCode = args.getString("pairingCode").orEmpty()
    val keepAliveMillis = args.getString("keepAliveMillis")?.toLongOrNull()?.coerceAtLeast(0) ?: 0
    assumeTrue(
      "Android image send E2E requires serverUrl and pairingCode.",
      serverUrl.isNotBlank() && pairingCode.isNotBlank(),
    )

    val app = ApplicationProvider.getApplicationContext<ClipDockApplication>()
    val repository = app.repository
    repository.setServerUrl(serverUrl)
    repository.setDeviceName("Android image E2E ${UUID.randomUUID().toString().take(6)}")
    repository.setP2pEnabled(true)
    repository.setWifiOnly(false)
    repository.joinSyncSpace(pairingCode)

    ActivityScenario.launch(MainActivity::class.java).use { scenario ->
      scenario.moveToState(Lifecycle.State.RESUMED)
      repository.startLocalClipboardCapture()

      val imageFile = createClipboardPng(app)
      val imageUri = FileProvider.getUriForFile(app, "${app.packageName}.files", imageFile)
      val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
      val clip =
        ClipData(
          ClipDescription(imageFile.name, arrayOf("image/png")),
          ClipData.Item(imageUri),
        )
      clipboard.setPrimaryClip(clip)

      val uploaded =
        waitFor("uploaded image item") {
          repository.syncNow().firstOrNull { item ->
            item.type == ClipItemType.Image &&
              item.sourceName == "Android" &&
              item.title == imageFile.name &&
              item.payloadState == PayloadState.Ready &&
              item.assetId?.isNotBlank() == true
          }
        }

      assertEquals(ClipItemType.Image, uploaded.type)
      assertEquals("Android", uploaded.sourceName)
      assertNotNull(uploaded.localUri)
      assertNotNull(uploaded.assetId)
      assertNotNull(uploaded.thumbnailDigest)
      assertEquals("image/webp", uploaded.thumbnailMimeType)
      assertTrue((uploaded.thumbnailByteCount ?: 0) > 0)
      assertTrue((uploaded.thumbnailWidth ?: 0) > 0)
      assertTrue((uploaded.thumbnailHeight ?: 0) > 0)

      val token = app.getSharedPreferences("clipdock", Context.MODE_PRIVATE).getString("token", null)
        ?: throw AssertionError("Missing Android sync token")
      val event = serverEventForContentHash(serverUrl, token, uploaded.contentHash)
      assertEquals("item_upsert", event.optString("type"))
      assertEquals("image", event.optString("item_type"))
      val payload = event.getJSONObject("payload")
      assertEquals("android", payload.optString("source_platform"))
      assertEquals(uploaded.assetId, payload.optString("payload_asset_id"))
      assertEquals(uploaded.assetId, payload.optString("asset_id"))
      assertEquals(uploaded.thumbnailDigest, payload.optString("thumbnail_digest"))
      assertEquals(uploaded.thumbnailMimeType, payload.optString("thumbnail_mime_type"))
      assertEquals(uploaded.thumbnailByteCount, payload.optLong("thumbnail_byte_count"))
      assertEquals(uploaded.thumbnailWidth, payload.optInt("thumbnail_width"))
      assertEquals(uploaded.thumbnailHeight, payload.optInt("thumbnail_height"))
      if (keepAliveMillis > 0) {
        delay(keepAliveMillis)
      }
    }
  }

  private fun createClipboardPng(context: Context): File {
    val fileName = "android-send-image-${UUID.randomUUID()}.png"
    val file = File(context.filesDir, "p2p-payloads/e2e-source/$fileName")
    file.parentFile?.mkdirs()
    val bitmap = Bitmap.createBitmap(16, 12, Bitmap.Config.ARGB_8888)
    for (y in 0 until bitmap.height) {
      for (x in 0 until bitmap.width) {
        val color =
          when {
            x < 5 -> Color.rgb(214, 64, 69)
            y < 6 -> Color.rgb(41, 128, 185)
            else -> Color.rgb(39, 174, 96)
          }
        bitmap.setPixel(x, y, color)
      }
    }
    FileOutputStream(file).use { output ->
      check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
    }
    bitmap.recycle()
    return file
  }

  private suspend fun serverEventForContentHash(
    serverUrl: String,
    token: String,
    contentHash: String,
  ): JSONObject =
    withContext(Dispatchers.IO) {
      val request =
        Request.Builder()
          .url(serverUrl.trimEnd('/') + "/v2/events?after_seq=0&limit=200")
          .header("Accept", "application/json")
          .header("Authorization", "Bearer $token")
          .build()
      httpClient.newCall(request).execute().use { response ->
        val body = response.body.string()
        if (!response.isSuccessful) throw AssertionError("HTTP ${response.code} $body")
        val events = JSONObject(body).getJSONObject("data").getJSONArray("events")
        for (index in 0 until events.length()) {
          val event = events.getJSONObject(index)
          if (event.optString("content_hash") == contentHash) return@withContext event
        }
        throw AssertionError("Missing server event for $contentHash: $body")
      }
    }

  private suspend fun <T : Any> waitFor(label: String, block: suspend () -> T?): T {
    val deadline = System.currentTimeMillis() + 30_000
    var lastError: Throwable? = null
    while (System.currentTimeMillis() < deadline) {
      try {
        block()?.let { return it }
      } catch (throwable: Throwable) {
        lastError = throwable
      }
      delay(500)
    }
    throw AssertionError("Timed out waiting for $label", lastError)
  }
}
