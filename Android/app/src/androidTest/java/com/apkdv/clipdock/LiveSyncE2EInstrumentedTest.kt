package com.apkdv.clipdock

import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.QuickCopyResult
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertNotNull
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiveSyncE2EInstrumentedTest {
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

    val fileCopy = repository.quickSyncAndCopy(timeoutMillis = 30_000)
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

    val imageCopy = repository.quickSyncAndCopy(timeoutMillis = 30_000)
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

  private fun pushUpsert(
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

  private fun pushDelete(serverUrl: String, token: String, contentHash: String) {
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

  private fun pushEvent(serverUrl: String, token: String, event: JSONObject) {
    request(
      serverUrl = serverUrl,
      path = "/v1/events",
      method = "POST",
      token = token,
      body = JSONObject().put("events", JSONArray().put(event)),
    )
  }

  private fun request(
    serverUrl: String,
    path: String,
    method: String,
    token: String,
    body: JSONObject,
  ): JSONObject {
    val connection = URL(serverUrl.trimEnd('/') + path).openConnection() as HttpURLConnection
    connection.requestMethod = method
    connection.connectTimeout = 5_000
    connection.readTimeout = 15_000
    connection.setRequestProperty("Accept", "application/json")
    connection.setRequestProperty("Authorization", "Bearer $token")
    val bytes = body.toString().toByteArray(Charsets.UTF_8)
    connection.doOutput = true
    connection.setRequestProperty("Content-Type", "application/json")
    connection.setRequestProperty("Content-Length", bytes.size.toString())
    connection.outputStream.use { it.write(bytes) }

    val status = connection.responseCode
    val responseText =
      (if (status in 200..299) connection.inputStream else connection.errorStream)
        ?.use { stream -> BufferedReader(InputStreamReader(stream)).readText() }
        .orEmpty()
    val envelope = if (responseText.isBlank()) JSONObject() else JSONObject(responseText)
    if (status !in 200..299 || envelope.has("error")) {
      throw AssertionError("HTTP $status $responseText")
    }
    return envelope.optJSONObject("data") ?: JSONObject()
  }

  private fun contentHash(value: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
    return "sha256:" + digest.joinToString("") { byte -> "%02x".format(byte) }
  }

  private fun readContentUri(context: Context, uri: String): ByteArray =
    context.contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
      ?: throw AssertionError("Cannot open downloaded URI: $uri")
}
