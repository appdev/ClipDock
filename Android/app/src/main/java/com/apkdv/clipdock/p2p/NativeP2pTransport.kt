package com.apkdv.clipdock.p2p

import android.content.Context
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

class P2pException(val code: String, message: String) : Exception(message)

data class P2pEndpointInfo(
  val endpointId: String,
  val relayUrl: String?,
  val directAddresses: List<String>,
)

data class P2pImportResult(
  val assetId: String,
  val ticket: String,
  val hash: String,
  val byteCount: Long,
  val endpoint: P2pEndpointInfo,
)

data class P2pDownloadResult(
  val outputPath: String,
  val byteCount: Long,
  val downloadedBytes: Long,
  val localBytes: Long,
  val elapsedMillis: Long,
)

class NativeP2pTransport(context: Context) {
  private val appContext = context.applicationContext

  fun isAvailable(): Boolean = NativeP2pBridge.loadError == null

  suspend fun startNode(): P2pEndpointInfo =
    withContext(Dispatchers.IO) {
      NativeP2pBridge.ensureLoaded()
      NativeP2pBridge
        .nativeStartNode(JSONObject().put("addr_timeout_ms", 3_000).toString())
        .parseNativeEnvelope()
        .toEndpointInfo()
    }

  suspend fun endpointInfo(): P2pEndpointInfo =
    withContext(Dispatchers.IO) {
      NativeP2pBridge.ensureLoaded()
      NativeP2pBridge.nativeEndpointInfo().parseNativeEnvelope().toEndpointInfo()
    }

  suspend fun importBlob(file: File): P2pImportResult =
    withContext(Dispatchers.IO) {
      NativeP2pBridge.ensureLoaded()
      NativeP2pBridge.nativeImportBlob(file.absolutePath).parseNativeEnvelope().toImportResult()
    }

  suspend fun downloadBlob(ticket: String, outputFile: File): P2pDownloadResult =
    withContext(Dispatchers.IO) {
      NativeP2pBridge.ensureLoaded()
      outputFile.parentFile?.mkdirs()
      NativeP2pBridge
        .nativeDownloadBlob(ticket, outputFile.absolutePath)
        .parseNativeEnvelope()
        .toDownloadResult()
    }

  suspend fun shutdown() =
    withContext(Dispatchers.IO) {
      NativeP2pBridge.ensureLoaded()
      NativeP2pBridge.nativeShutdown().parseNativeEnvelope()
    }

  fun defaultPayloadDir(): File = File(appContext.filesDir, "p2p-payloads")
}

object NativeP2pBridge {
  val loadError: Throwable?

  init {
    loadError =
      runCatching { System.loadLibrary("clipdock_p2p_jni") }
        .exceptionOrNull()
  }

  fun ensureLoaded() {
    loadError?.let { throw P2pException("native_unavailable", it.message ?: "P2P native library is unavailable") }
  }

  @JvmStatic external fun nativeStartNode(configJson: String): String

  @JvmStatic external fun nativeEndpointInfo(): String

  @JvmStatic external fun nativeImportBlob(path: String): String

  @JvmStatic external fun nativeDownloadBlob(ticket: String, outputPath: String): String

  @JvmStatic external fun nativeShutdown(): String
}

private fun String.parseNativeEnvelope(): JSONObject {
  val root = JSONObject(this)
  if (!root.optBoolean("ok")) {
    throw P2pException(
      root.optString("error_code").ifBlank { "p2p_error" },
      root.optString("message").ifBlank { "P2P 请求失败" },
    )
  }
  return root.optJSONObject("data") ?: JSONObject()
}

private fun JSONObject.toEndpointInfo(): P2pEndpointInfo =
  P2pEndpointInfo(
    endpointId = optString("endpoint_id"),
    relayUrl = optNullableString("relay_url"),
    directAddresses = optJSONArray("direct_addresses").stringList(),
  )

private fun JSONObject.toImportResult(): P2pImportResult =
  P2pImportResult(
    assetId = optString("asset_id"),
    ticket = optString("ticket"),
    hash = optString("hash"),
    byteCount = optLong("byte_count"),
    endpoint = optJSONObject("endpoint")?.toEndpointInfo() ?: P2pEndpointInfo("", null, emptyList()),
  )

private fun JSONObject.toDownloadResult(): P2pDownloadResult =
  P2pDownloadResult(
    outputPath = optString("output_path"),
    byteCount = optLong("byte_count"),
    downloadedBytes = optLong("downloaded_bytes"),
    localBytes = optLong("local_bytes"),
    elapsedMillis = optLong("elapsed_ms"),
  )

private fun JSONObject.optNullableString(name: String): String? =
  if (has(name) && !isNull(name)) optString(name).takeIf { it.isNotBlank() } else null

private fun JSONArray?.stringList(): List<String> {
  if (this == null) return emptyList()
  return (0 until length()).mapNotNull { optString(it).takeIf(String::isNotBlank) }
}
