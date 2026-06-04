package com.apkdv.clipdock.qa

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.util.Log
import com.apkdv.clipdock.ClipDockApplication
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.QuickCopyResult
import java.util.concurrent.TimeUnit
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import org.apache.commons.codec.digest.Blake3

class LiveSyncQaActivity : Activity() {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val httpClient =
    OkHttpClient.Builder()
      .connectTimeout(5, TimeUnit.SECONDS)
      .readTimeout(15, TimeUnit.SECONDS)
      .build()

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    scope.launch {
      val result =
        runCatching { runScenario() }
          .fold(
            onSuccess = { it.put("ok", true) },
            onFailure = { throwable ->
              JSONObject()
                .put("ok", false)
                .put("error", throwable.javaClass.name)
                .put("message", throwable.message.orEmpty())
            },
          )
      writeResult(result)
      Log.i(TAG, "RESULT $result")
      finish()
    }
  }

  override fun onDestroy() {
    scope.cancel()
    super.onDestroy()
  }

  private suspend fun runScenario(): JSONObject {
    val serverUrl = requireExtra("serverUrl")
    val pairingCode = requireExtra("pairingCode")
    val sourceToken = requireExtra("sourceToken")
    val fileAssetId = requireExtra("fileAssetId")
    val imageAssetId = requireExtra("imageAssetId")
    val expectedFileNeedle = intent.getStringExtra("expectedFileNeedle") ?: "ClipDock"

    val repository = (application as ClipDockApplication).repository
    repository.setServerUrl(serverUrl)
    repository.setDeviceName("Android physical QA ${UUID.randomUUID().toString().take(6)}")
    repository.setP2pEnabled(true)
    repository.setWifiOnly(false)
    repository.joinSyncSpace(pairingCode)

    val namespace = UUID.randomUUID().toString()
    val textHash = contentHash("$namespace:text")
    val textValue = "ClipDock physical QA text $namespace"
    pushUpsert(
      serverUrl = serverUrl,
      token = sourceToken,
      contentHash = textHash,
      itemType = "text",
      payload = JSONObject().put("text", textValue).put("source_app_name", "macOS installed QA"),
    )

    val textItems = repository.syncNow()
    val textItem = textItems.first { it.contentHash == textHash }
    check(textItem.type == ClipItemType.Text) { "Expected text item, got ${textItem.type}" }
    check(repository.copyItem(textItem)) { "Failed to copy text item" }

    val fileHash = contentHash("$namespace:file")
    pushUpsert(
      serverUrl = serverUrl,
      token = sourceToken,
      contentHash = fileHash,
      itemType = "file",
      payload =
        JSONObject()
          .put("file_name", "physical-fixed-file.txt")
          .put("mime_type", "text/plain")
          .put("payload_asset_id", fileAssetId)
          .put("source_app_name", "macOS installed QA"),
    )

    val fileItems = repository.syncNow()
    val remoteFileItem = fileItems.first { it.contentHash == fileHash }
    val fileCopy = repository.useItem(remoteFileItem, timeoutMillis = 30_000)
    check(fileCopy is QuickCopyResult.Copied) { "File quick copy failed: $fileCopy" }
    val fileItem = fileCopy.item
    check(fileItem.contentHash == fileHash) { "Expected file hash $fileHash, got ${fileItem.contentHash}" }
    check(fileItem.type == ClipItemType.File) { "Expected file item, got ${fileItem.type}" }
    check(fileItem.payloadState == PayloadState.Ready) { "File payload not ready: ${fileItem.payloadState}" }
    val fileBytes = readContentUri(this, fileItem.localUri ?: error("File localUri missing"))
    val fileText = fileBytes.decodeToString()
    check(fileText.contains(expectedFileNeedle)) { "Downloaded file did not contain expected text" }

    val imageHash = contentHash("$namespace:image")
    pushUpsert(
      serverUrl = serverUrl,
      token = sourceToken,
      contentHash = imageHash,
      itemType = "image",
      payload =
        JSONObject()
          .put("file_name", "physical-fixed-image.png")
          .put("mime_type", "image/png")
          .put("payload_asset_id", imageAssetId)
          .put("source_app_name", "macOS installed QA"),
    )

    val imageItems = repository.syncNow()
    val remoteImageItem = imageItems.first { it.contentHash == imageHash }
    val imageCopy = repository.useItem(remoteImageItem, timeoutMillis = 30_000)
    check(imageCopy is QuickCopyResult.Copied) { "Image quick copy failed: $imageCopy" }
    val imageItem = imageCopy.item
    check(imageItem.contentHash == imageHash) { "Expected image hash $imageHash, got ${imageItem.contentHash}" }
    check(imageItem.type == ClipItemType.Image) { "Expected image item, got ${imageItem.type}" }
    check(imageItem.payloadState == PayloadState.Ready) { "Image payload not ready: ${imageItem.payloadState}" }
    val imageBytes = readContentUri(this, imageItem.localUri ?: error("Image localUri missing"))
    check(imageBytes.size >= 8) { "Downloaded image too small: ${imageBytes.size}" }
    val isPng =
      imageBytes[0] == 0x89.toByte() &&
        imageBytes[1] == 'P'.code.toByte() &&
        imageBytes[2] == 'N'.code.toByte() &&
        imageBytes[3] == 'G'.code.toByte()
    val isWebP =
      imageBytes.size >= 12 &&
        imageBytes[0] == 'R'.code.toByte() &&
        imageBytes[1] == 'I'.code.toByte() &&
        imageBytes[2] == 'F'.code.toByte() &&
        imageBytes[3] == 'F'.code.toByte() &&
        imageBytes[8] == 'W'.code.toByte() &&
        imageBytes[9] == 'E'.code.toByte() &&
        imageBytes[10] == 'B'.code.toByte() &&
        imageBytes[11] == 'P'.code.toByte()
    check(isPng || isWebP) { "Downloaded image is not PNG/WebP" }

    pushDelete(serverUrl, sourceToken, textHash)
    val finalItems = repository.syncNow()
    check(finalItems.none { it.contentHash == textHash }) { "Deleted text item still present" }
    check(finalItems.any { it.contentHash == fileHash && it.payloadState == PayloadState.Ready }) {
      "Downloaded file missing after delete sync"
    }
    check(finalItems.any { it.contentHash == imageHash && it.payloadState == PayloadState.Ready }) {
      "Downloaded image missing after delete sync"
    }

    return JSONObject()
      .put("serverUrl", serverUrl)
      .put("fileAssetId", fileAssetId)
      .put("imageAssetId", imageAssetId)
      .put("fileBytes", fileBytes.size)
      .put("imageBytes", imageBytes.size)
      .put("activeItems", finalItems.lengthForJson())
      .put("fileLocalUri", fileItem.localUri)
      .put("imageLocalUri", imageItem.localUri)
  }

  private fun requireExtra(name: String): String =
    intent.getStringExtra(name)?.takeIf { it.isNotBlank() } ?: error("Missing extra: $name")

  private fun writeResult(result: JSONObject) {
    openFileOutput(RESULT_FILE, Context.MODE_PRIVATE).use { output ->
      output.write(result.toString(2).toByteArray(Charsets.UTF_8))
    }
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
          .put("client_event_id", "debug-qa-${UUID.randomUUID()}")
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
          .put("client_event_id", "debug-qa-${UUID.randomUUID()}")
          .put("type", "item_delete")
          .put("content_hash", contentHash),
    )
  }

  private suspend fun pushEvent(serverUrl: String, token: String, event: JSONObject) {
    request(
      serverUrl = serverUrl,
      path = "/v2/events",
      token = token,
      body = JSONObject().put("events", JSONArray().put(event)),
    )
  }

  private suspend fun request(
    serverUrl: String,
    path: String,
    token: String,
    body: JSONObject,
  ): JSONObject =
    withContext(Dispatchers.IO) {
      val request =
        Request.Builder()
          .url(serverUrl.trimEnd('/') + path)
          .header("Accept", "application/json")
          .header("Authorization", "Bearer $token")
          .post(body.toString().toRequestBody(JSON_MEDIA_TYPE))
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
      ?: error("Cannot open downloaded URI: $uri")

  private fun List<*>.lengthForJson(): Int = size

  private companion object {
    const val TAG = "ClipDockLiveQa"
    const val RESULT_FILE = "live-sync-qa-result.json"
    val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
  }
}
