package com.apkdv.clipdock

import android.content.Intent
import android.os.ParcelFileDescriptor
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.overlay.FloatingOverlayService
import java.io.FileInputStream
import java.util.UUID
import java.util.concurrent.TimeUnit
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.apache.commons.codec.digest.Blake3
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackgroundSyncAndOverlayInstrumentedTest {
  private val httpClient =
    OkHttpClient.Builder()
      .connectTimeout(5, TimeUnit.SECONDS)
      .readTimeout(15, TimeUnit.SECONDS)
      .build()

  @Test
  fun backgroundSyncCapturesClipboardAndFloatingBallCopiesLatest() {
    runBlocking {
      val args = InstrumentationRegistry.getArguments()
      val serverUrl = args.getString("serverUrl").orEmpty()
      val pairingCode = args.getString("pairingCode").orEmpty()
      val sourceToken = args.getString("sourceToken").orEmpty()
      assumeTrue(
        "Background sync E2E requires serverUrl, pairingCode, and sourceToken.",
        listOf(serverUrl, pairingCode, sourceToken).all(String::isNotBlank),
      )

      val app = ApplicationProvider.getApplicationContext<ClipDockApplication>()
      val repository = app.repository
      repository.setServerUrl(serverUrl)
      repository.setDeviceName("Android background E2E ${UUID.randomUUID().toString().take(6)}")
      repository.setP2pEnabled(true)
      repository.setWifiOnly(false)
      repository.setOverlayEnabled(true)
      repository.setOverlaySizeDp(64)
      repository.setOverlayVerticalFraction(0.35f)
      repository.joinSyncSpace(pairingCode)
      repository.startLocalClipboardCapture()

      ActivityScenario.launch(MainActivity::class.java).use { scenario ->
        scenario.moveToState(Lifecycle.State.RESUMED)
        app.startService(Intent(app, FloatingOverlayService::class.java))
        waitFor("foreground floating overlay window") { overlayWindowVisible(app.packageName).takeIf { it } }
        shell("input keyevent KEYCODE_HOME")
        waitFor("app to leave foreground") { (!foregroundWindow().contains(app.packageName)).takeIf { it } }
        waitFor("background floating overlay window") { overlayWindowVisible(app.packageName).takeIf { it } }

        val backgroundText = "ClipDock_BackgroundRealtime_${UUID.randomUUID()}"
        val backgroundHash = pushTextUpsert(serverUrl, sourceToken, backgroundText)
        val backgroundItem =
          waitFor("background realtime item") {
            repository.state.value.items.firstOrNull { item ->
              item.contentHash == backgroundHash &&
                item.type == ClipItemType.Text &&
                item.body == backgroundText
            }
          }
        assertEquals(backgroundText, backgroundItem.body)

        val beforeClipboardCursor = latestCursor(serverUrl, sourceToken)
        val capturedText = "ClipDock_BackgroundClipboard_${UUID.randomUUID()}"
        copyFromForegroundSource(capturedText)
        assertFalse(
          "Android denies passive clipboard reads to ClipDock while the app is backgrounded.",
          waitForServerText(serverUrl, sourceToken, beforeClipboardCursor, capturedText, timeoutMillis = 6_000),
        )
        shell("input keyevent KEYCODE_HOME")
        waitFor("background floating overlay window after source copy") { overlayWindowVisible(app.packageName).takeIf { it } }

        val overlayText = "ClipDock_OverlayQuickCopy_${UUID.randomUUID()}"
        val overlayHash = pushTextUpsert(serverUrl, sourceToken, overlayText)
        waitFor("overlay target item") {
          repository.state.value.items.firstOrNull { it.contentHash == overlayHash && it.body == overlayText }
        }

        val beforeOverlayCursor = latestCursor(serverUrl, sourceToken)
        try {
          delay(750)
          tapFloatingBall()
          delay(5_000)
          assertFalse(
            "Floating ball self-copy should not upload a duplicate Android event.",
            waitForAndroidServerText(serverUrl, sourceToken, beforeOverlayCursor, overlayText, timeoutMillis = 5_000),
          )
        } finally {
          app.stopService(Intent(app, FloatingOverlayService::class.java))
        }
      }
    }
  }

  private suspend fun pushTextUpsert(serverUrl: String, token: String, text: String): String {
    val hash = contentHash(text)
    request(
      serverUrl = serverUrl,
      path = "/v2/events",
      token = token,
      body =
        JSONObject()
          .put(
            "events",
            JSONArray().put(
              JSONObject()
                .put("client_event_id", "background-e2e-${UUID.randomUUID()}")
                .put("type", "item_upsert")
                .put("content_hash", hash)
                .put("item_type", "text")
                .put("payload", JSONObject().put("text", text).put("source_app_name", "macOS Background E2E"))
                .put("copy_count_delta", 1),
            ),
          ),
    )
    return hash
  }

  private suspend fun latestCursor(serverUrl: String, token: String): Long =
    request(
      serverUrl = serverUrl,
      path = "/v2/events?after_seq=0&limit=50",
      token = token,
      method = "GET",
    ).optLong("next_cursor")

  private suspend fun waitForServerText(
    serverUrl: String,
    token: String,
    cursor: Long,
    text: String,
    timeoutMillis: Long = 30_000,
  ): Boolean {
    var afterSeq = cursor
    val deadline = System.currentTimeMillis() + timeoutMillis
    while (System.currentTimeMillis() < deadline) {
      val data =
        request(
          serverUrl = serverUrl,
          path = "/v2/events?after_seq=$afterSeq&limit=100",
          token = token,
          method = "GET",
        )
      val events = data.optJSONArray("events") ?: JSONArray()
      for (index in 0 until events.length()) {
        val event = events.optJSONObject(index) ?: continue
        val payload = event.optJSONObject("payload") ?: continue
        if (event.optString("item_type") == "text" && payload.optString("text") == text) {
          return true
        }
      }
      afterSeq = data.optLong("next_cursor", afterSeq)
      delay(500)
    }
    return false
  }

  private suspend fun waitForAndroidServerText(
    serverUrl: String,
    token: String,
    cursor: Long,
    text: String,
    timeoutMillis: Long,
  ): Boolean {
    var afterSeq = cursor
    val deadline = System.currentTimeMillis() + timeoutMillis
    while (System.currentTimeMillis() < deadline) {
      val data =
        request(
          serverUrl = serverUrl,
          path = "/v2/events?after_seq=$afterSeq&limit=100",
          token = token,
          method = "GET",
        )
      val events = data.optJSONArray("events") ?: JSONArray()
      for (index in 0 until events.length()) {
        val event = events.optJSONObject(index) ?: continue
        val payload = event.optJSONObject("payload") ?: continue
        if (
          event.optString("item_type") == "text" &&
          payload.optString("text") == text &&
          payload.optString("source_platform") == "android"
        ) {
          return true
        }
      }
      afterSeq = data.optLong("next_cursor", afterSeq)
      delay(500)
    }
    return false
  }

  private suspend fun request(
    serverUrl: String,
    path: String,
    token: String,
    method: String = "POST",
    body: JSONObject? = null,
  ): JSONObject =
    withContext(Dispatchers.IO) {
      val builder =
        Request.Builder()
          .url(serverUrl.trimEnd('/') + path)
          .header("Accept", "application/json")
          .header("Authorization", "Bearer $token")
      val request =
        if (method == "GET") {
          builder.get().build()
        } else {
          builder.post((body ?: JSONObject()).toString().toRequestBody(JSON_MEDIA_TYPE)).build()
        }
      httpClient.newCall(request).execute().use { response ->
        val responseText = response.body.string()
        val envelope = if (responseText.isBlank()) JSONObject() else JSONObject(responseText)
        if (!response.isSuccessful || envelope.has("error")) {
          throw AssertionError("HTTP ${response.code} $responseText")
        }
        envelope.optJSONObject("data") ?: JSONObject()
      }
    }

  private suspend fun <T : Any> waitFor(label: String, block: suspend () -> T?): T {
    val deadline = System.currentTimeMillis() + TimeUnit.SECONDS.toMillis(45)
    while (System.currentTimeMillis() < deadline) {
      block()?.let { return it }
      delay(500)
    }
    throw AssertionError("Timed out waiting for $label")
  }

  private fun tapFloatingBall() {
    val size = shell("wm size")
    val match = Regex("(?:Override|Physical) size: (\\d+)x(\\d+)").findAll(size).lastOrNull()
      ?: throw AssertionError("Cannot read display size: $size")
    val width = match.groupValues[1].toInt()
    val height = match.groupValues[2].toInt()
    val x = width - 44
    val y = ((height - 64) * 0.35f + 32).toInt()
    shell("input tap $x $y")
  }

  private fun copyFromForegroundSource(text: String) {
    shell(
      "am start -n com.apkdv.clipdock.test/com.apkdv.clipdock.ForegroundClipboardSourceActivity " +
        "--es text ${shellQuote(text)}",
    )
  }

  private fun foregroundWindow(): String = shell("dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' || true")

  private fun overlayWindowVisible(packageName: String): Boolean =
    shell("dumpsys window | grep -E 'package=$packageName appop=SYSTEM_ALERT_WINDOW' || true").isNotBlank()

  private fun shell(command: String): String {
    val descriptor: ParcelFileDescriptor = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
    return descriptor.use { pfd ->
      FileInputStream(pfd.fileDescriptor).bufferedReader().use { it.readText() }
    }
  }

  private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"

  private fun contentHash(value: String): String {
    val digest = Blake3.hash(value.toByteArray(Charsets.UTF_8))
    return "blake3:" + digest.joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
  }

  private companion object {
    val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
  }
}
