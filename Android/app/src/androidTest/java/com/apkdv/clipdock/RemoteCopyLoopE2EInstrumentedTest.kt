package com.apkdv.clipdock

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.data.ClipItemType
import java.util.UUID
import java.util.concurrent.TimeUnit
import junit.framework.TestCase.assertEquals
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
class RemoteCopyLoopE2EInstrumentedTest {
  private val httpClient =
    OkHttpClient.Builder()
      .connectTimeout(5, TimeUnit.SECONDS)
      .readTimeout(15, TimeUnit.SECONDS)
      .build()

  @Test
  fun copyingRemoteMacItemDoesNotUploadSelfCopyBackToServer() = runBlocking {
    val args = InstrumentationRegistry.getArguments()
    val serverUrl = args.getString("serverUrl").orEmpty()
    val pairingCode = args.getString("pairingCode").orEmpty()
    val sourceToken = args.getString("sourceToken").orEmpty()
    val sourceContentHash = args.getString("sourceContentHash").orEmpty()
    assumeTrue(
      "Remote copy loop E2E requires serverUrl, pairingCode, sourceToken, and sourceContentHash.",
      listOf(serverUrl, pairingCode, sourceToken, sourceContentHash).all(String::isNotBlank),
    )

    val app = ApplicationProvider.getApplicationContext<ClipDockApplication>()
    val repository = app.repository
    repository.setServerUrl(serverUrl)
    repository.setDeviceName("Android loop E2E ${UUID.randomUUID().toString().take(6)}")
    repository.setP2pEnabled(true)
    repository.setWifiOnly(false)
    repository.joinSyncSpace(pairingCode)
    repository.startLocalClipboardCapture()

    val remoteItem = repository.syncNow().first { it.contentHash == sourceContentHash }
    assertEquals(ClipItemType.Text, remoteItem.type)
    val beforeCursor = latestCursor(serverUrl, sourceToken)

    assertTrue(repository.copyItem(remoteItem))
    delay(3_000)

    val eventsAfterCopy = eventsAfter(serverUrl, sourceToken, beforeCursor)
    assertEquals(0, eventsAfterCopy)
  }

  private suspend fun latestCursor(serverUrl: String, token: String): Long =
    eventsEnvelope(serverUrl, token, afterSeq = 0).getJSONObject("data").optLong("next_cursor")

  private suspend fun eventsAfter(serverUrl: String, token: String, afterSeq: Long): Int =
    eventsEnvelope(serverUrl, token, afterSeq).getJSONObject("data").getJSONArray("events").length()

  private suspend fun eventsEnvelope(serverUrl: String, token: String, afterSeq: Long): JSONObject =
    withContext(Dispatchers.IO) {
      val request =
        Request.Builder()
          .url(serverUrl.trimEnd('/') + "/v2/events?after_seq=$afterSeq&limit=50")
          .header("Accept", "application/json")
          .header("Authorization", "Bearer $token")
          .build()
      httpClient.newCall(request).execute().use { response ->
        val body = response.body.string()
        if (!response.isSuccessful) throw AssertionError("HTTP ${response.code} $body")
        JSONObject(body)
      }
    }
}
