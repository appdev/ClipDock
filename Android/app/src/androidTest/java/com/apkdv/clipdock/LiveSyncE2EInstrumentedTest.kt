package com.apkdv.clipdock

import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.QuickCopyResult
import java.util.concurrent.TimeUnit
import java.util.UUID
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertNotNull
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import org.apache.commons.codec.digest.Blake3
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiveSyncE2EInstrumentedTest {
  private val httpClient =
    OkHttpClient.Builder()
      .connectTimeout(5, TimeUnit.SECONDS)
      .readTimeout(15, TimeUnit.SECONDS)
      .build()

  @Test
  fun syncsTextDownloadsImageAndFileThenAppliesDelete() = runBlocking {
    val args = InstrumentationRegistry.getArguments()
    val serverUrl = args.getString("serverUrl").orEmpty()
    val pairingCode = args.getString("pairingCode").orEmpty()
    val sourceToken = args.getString("sourceToken").orEmpty()
    val imageAssetId = args.getString("imageAssetId").orEmpty()
    val fileAssetId = args.getString("fileAssetId").orEmpty()
    assumeTrue(
      "Live sync E2E requires serverUrl, pairingCode, sourceToken, imageAssetId, and fileAssetId.",
      listOf(serverUrl, pairingCode, sourceToken, imageAssetId, fileAssetId).all(String::isNotBlank),
    )

    val app = ApplicationProvider.getApplicationContext<ClipDockApplication>()
    val repository = app.repository
    repository.setServerUrl(serverUrl)
    repository.setDeviceName("Android E2E ${UUID.randomUUID().toString().take(6)}")
    repository.setP2pEnabled(true)
    repository.setWifiOnly(false)
    repository.joinSyncSpace(pairingCode)

    val namespace = UUID.randomUUID().toString()
    val textHash = contentHash("$namespace:text")
    val textValue = "ClipDock E2E text $namespace"
    pushUpsert(
      serverUrl = serverUrl,
      token = sourceToken,
      contentHash = textHash,
      itemType = "text",
      payload = JSONObject().put("text", textValue).put("source_app_name", "macOS E2E"),
    )

    var items = repository.syncNow()
    val textItem = items.first { it.contentHash == textHash }
    assertEquals(ClipItemType.Text, textItem.type)
    assertEquals(textValue, textItem.body)
    assertTrue(repository.copyItem(textItem))

    val fileHash = contentHash("$namespace:file")
    pushUpsert(
      serverUrl = serverUrl,
      token = sourceToken,
      contentHash = fileHash,
      itemType = "file",
      payload =
        JSONObject()
          .put("file_name", "e2e-file.txt")
          .put("mime_type", "text/plain")
          .put("byte_count", 52)
          .put("payload_asset_id", fileAssetId)
          .put("source_app_name", "macOS E2E"),
    )

    items = repository.syncNow()
    val remoteFile = items.first { it.contentHash == fileHash }
    val fileCopy = repository.useItem(remoteFile, timeoutMillis = 30_000)
    assertTrue(fileCopy is QuickCopyResult.Copied)
    val fileItem = (fileCopy as QuickCopyResult.Copied).item
    assertEquals(fileHash, fileItem.contentHash)
    assertEquals(ClipItemType.File, fileItem.type)
    assertEquals(PayloadState.Ready, fileItem.payloadState)
    assertNotNull(fileItem.localUri)
    assertTrue(readContentUri(app, fileItem.localUri!!).decodeToString().contains("ClipDock E2E file payload"))

    val imageHash = contentHash("$namespace:image")
    pushUpsert(
      serverUrl = serverUrl,
      token = sourceToken,
      contentHash = imageHash,
      itemType = "image",
      payload =
        JSONObject()
          .put("file_name", "e2e-image.png")
          .put("mime_type", "image/png")
          .put("byte_count", 70)
          .put("payload_asset_id", imageAssetId)
          .put("source_app_name", "macOS E2E"),
    )

    items = repository.syncNow()
    val remoteImage = items.first { it.contentHash == imageHash }
    val imageCopy = repository.useItem(remoteImage, timeoutMillis = 30_000)
    assertTrue(imageCopy is QuickCopyResult.Copied)
    val imageItem = (imageCopy as QuickCopyResult.Copied).item
    assertEquals(imageHash, imageItem.contentHash)
    assertEquals(ClipItemType.Image, imageItem.type)
    assertEquals(PayloadState.Ready, imageItem.payloadState)
    assertNotNull(imageItem.localUri)
    val imageBytes = readContentUri(app, imageItem.localUri!!)
    assertTrue(imageBytes.size >= 8)
    assertEquals(0x89.toByte(), imageBytes[0])
    assertEquals('P'.code.toByte(), imageBytes[1])
    assertEquals('N'.code.toByte(), imageBytes[2])
    assertEquals('G'.code.toByte(), imageBytes[3])

    pushDelete(serverUrl, sourceToken, textHash)
    items = repository.syncNow()
    assertFalse(items.any { it.contentHash == textHash })
    assertTrue(items.any { it.contentHash == fileHash && it.payloadState == PayloadState.Ready })
    assertTrue(items.any { it.contentHash == imageHash && it.payloadState == PayloadState.Ready })
  }

  private suspend fun pushUpsert(
    serverUrl: String,
    token: String,
    contentHash: String,
    itemType: String,
    payload: JSONObject,
  ) {
    pushEvent(
      serverUrl = serverUrl,
      token = token,
      event =
        JSONObject()
          .put("client_event_id", "e2e-${UUID.randomUUID()}")
          .put("type", "item_upsert")
          .put("content_hash", contentHash)
          .put("item_type", itemType)
          .put("payload", payload)
          .put("copy_count_delta", 1),
    )
  }

  private suspend fun pushDelete(serverUrl: String, token: String, contentHash: String) {
    pushEvent(
      serverUrl = serverUrl,
      token = token,
      event =
        JSONObject()
          .put("client_event_id", "e2e-${UUID.randomUUID()}")
          .put("type", "item_delete")
          .put("content_hash", contentHash),
    )
  }

  private suspend fun pushEvent(serverUrl: String, token: String, event: JSONObject) {
    request(
      serverUrl = serverUrl,
      path = "/v2/events",
      method = "POST",
      token = token,
      body = JSONObject().put("events", JSONArray().put(event)),
    )
  }

  private suspend fun request(
    serverUrl: String,
    path: String,
    method: String,
    token: String,
    body: JSONObject,
  ): JSONObject =
    withContext(Dispatchers.IO) {
      val request =
        Request.Builder()
          .url(serverUrl.trimEnd('/') + path)
          .header("Accept", "application/json")
          .header("Authorization", "Bearer $token")
          .method(method, body.toString().toRequestBody(JSON_MEDIA_TYPE))
          .build()

      httpClient.newCall(request).execute().use { response ->
        val responseText = response.body.string()
        val envelope = if (responseText.isBlank()) JSONObject() else JSONObject(responseText)
        if (!response.isSuccessful || envelope.has("error")) {
          throw AssertionError("HTTP ${response.code} $responseText")
        }
        envelope.optJSONObject("data") ?: JSONObject()
      }
    }

  private fun contentHash(value: String): String {
    val digest = Blake3.hash(value.toByteArray(Charsets.UTF_8))
    return "blake3:" + digest.joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
  }

  private fun readContentUri(context: Context, uri: String): ByteArray =
    context.contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
      ?: throw AssertionError("Cannot open downloaded URI: $uri")

  private companion object {
    val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
  }
}
