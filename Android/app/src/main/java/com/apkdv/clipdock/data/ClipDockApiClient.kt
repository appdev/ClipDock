package com.apkdv.clipdock.data

import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

class ClipDockApiException(val code: String, message: String = code) : Exception(message)

interface ClipDockSyncApi {
  suspend fun snapshot(serverUrl: String, token: String): JsonObject

  suspend fun events(serverUrl: String, token: String, afterSeq: Long, limit: Int = 500): JsonObject

  suspend fun pushEvents(serverUrl: String, token: String, events: List<SyncPushEventRequest>): JsonObject
}

interface ClipDockRealtimeSocketConnector {
  fun openRealtimeSocket(
    serverUrl: String,
    token: String,
    cursor: Long,
    listener: WebSocketListener,
  ): WebSocket
}

data class DownloadedSyncAsset(
  val bytes: ByteArray,
  val contentType: String?,
  val byteCount: Long,
  val kind: String?,
  val width: Int?,
  val height: Int?,
) {
  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (other !is DownloadedSyncAsset) return false
    return bytes.contentEquals(other.bytes) &&
      contentType == other.contentType &&
      byteCount == other.byteCount &&
      kind == other.kind &&
      width == other.width &&
      height == other.height
  }

  override fun hashCode(): Int {
    var result = bytes.contentHashCode()
    result = 31 * result + (contentType?.hashCode() ?: 0)
    result = 31 * result + byteCount.hashCode()
    result = 31 * result + (kind?.hashCode() ?: 0)
    result = 31 * result + (width ?: 0)
    result = 31 * result + (height ?: 0)
    return result
  }
}

data class UploadedSyncAsset(
  val digest: String,
  val kind: String,
  val mimeType: String,
  val byteCount: Long,
  val width: Int,
  val height: Int,
  val alreadyExists: Boolean,
)

interface ClipDockRawAssetApi {
  suspend fun downloadAsset(serverUrl: String, token: String, digest: String): DownloadedSyncAsset

  suspend fun uploadAsset(
    serverUrl: String,
    token: String,
    digest: String,
    kind: String,
    mimeType: String,
    width: Int,
    height: Int,
    bytes: ByteArray,
  ): UploadedSyncAsset
}

class ClipDockApiClient(
  private val client: OkHttpClient = defaultClient,
  private val json: Json = defaultJson,
) : ClipDockSyncApi, ClipDockRealtimeSocketConnector, ClipDockRawAssetApi {
  suspend fun health(serverUrl: String): JsonObject = request(serverUrl, "/health", Method.Get, token = null)

  suspend fun info(serverUrl: String, token: String): JsonObject = request(serverUrl, "/v2/info", Method.Get, token)

  suspend fun createSync(serverUrl: String, deviceName: String): JsonObject =
    request(
      serverUrl,
      "/v2/sync/create",
      Method.Post,
      token = null,
      body = DeviceNameRequest(deviceName),
    )

  suspend fun joinSync(serverUrl: String, pairingCode: String, deviceName: String): JsonObject =
    request(
      serverUrl,
      "/v2/sync/join",
      Method.Post,
      token = null,
      body = JoinSyncRequest(pairingCode, deviceName),
    )

  suspend fun createInvite(serverUrl: String, token: String): JsonObject =
    request(serverUrl, "/v2/sync/invites", Method.Post, token)

  override suspend fun snapshot(serverUrl: String, token: String): JsonObject = request(serverUrl, "/v2/snapshot", Method.Get, token)

  override suspend fun events(serverUrl: String, token: String, afterSeq: Long, limit: Int): JsonObject =
    request(serverUrl, "/v2/events?after_seq=$afterSeq&limit=$limit", Method.Get, token)

  override suspend fun pushEvents(serverUrl: String, token: String, events: List<SyncPushEventRequest>): JsonObject =
    request(
      serverUrl,
      "/v2/events",
      Method.Post,
      token,
      body = PushEventsRequest(events),
    )

  override fun openRealtimeSocket(
    serverUrl: String,
    token: String,
    cursor: Long,
    listener: WebSocketListener,
  ): WebSocket {
    val wsUrl = serverUrl.toRealtimeUrl(cursor)
    val request =
      Request.Builder()
        .url(wsUrl)
        .header("Authorization", "Bearer $token")
        .build()
    return client.newWebSocket(request, listener)
  }

  suspend fun p2pProviders(serverUrl: String, token: String, assetId: String): JsonObject =
    request(serverUrl, "/v2/p2p/assets/${assetId.encodePathSegment()}/providers", Method.Get, token)

  suspend fun p2pDevices(serverUrl: String, token: String): JsonObject =
    request(serverUrl, "/v2/p2p/devices", Method.Get, token)

  suspend fun reportP2pEndpoint(
    serverUrl: String,
    token: String,
    endpointId: String,
    relayUrl: String?,
    directAddresses: List<String>,
  ): JsonObject =
    request(
      serverUrl,
      "/v2/p2p/endpoint",
      Method.Put,
      token,
      body =
        ReportP2pEndpointRequest(
          endpointId = endpointId,
          relayUrl = relayUrl,
          directAddresses = directAddresses,
          capabilities = P2pEndpointCapabilities(),
          quality = P2pEndpointQuality(),
        ),
    )

  suspend fun upsertP2pProvider(
    serverUrl: String,
    token: String,
    assetId: String,
    kind: String,
    byteCount: Long,
    mimeType: String?,
    ticket: String,
  ): JsonObject =
    request(
      serverUrl,
      "/v2/p2p/assets/${assetId.encodePathSegment()}/providers/me",
      Method.Put,
      token,
      body =
        UpsertP2pProviderRequest(
          kind = kind,
          byteCount = byteCount,
          mimeType = mimeType,
          availability = "online",
          quality = P2pProviderQuality(ticket),
        ),
    )

  suspend fun deleteP2pProvider(serverUrl: String, token: String, assetId: String): JsonObject =
    request(
      serverUrl,
      "/v2/p2p/assets/${assetId.encodePathSegment()}/providers/me",
      Method.Delete,
      token,
    )

  override suspend fun downloadAsset(serverUrl: String, token: String, digest: String): DownloadedSyncAsset {
    val request =
      Request.Builder()
        .url(serverUrl.trimEnd('/') + "/v2/assets/${digest.encodePathSegment()}")
        .header("Accept", "image/webp,image/png,image/jpeg")
        .header("Authorization", "Bearer $token")
        .build()
    val response = client.newCall(request).awaitBytes()
    if (!response.isSuccessful) {
      throw ClipDockApiException("http_${response.code}")
    }
    return DownloadedSyncAsset(
      bytes = response.bytes,
      contentType = response.headers["content-type"]?.substringBefore(';')?.trim(),
      byteCount = response.headers["content-length"]?.toLongOrNull() ?: response.bytes.size.toLong(),
      kind = response.headers["x-clipdock-asset-kind"],
      width = response.headers["x-clipdock-asset-width"]?.toIntOrNull(),
      height = response.headers["x-clipdock-asset-height"]?.toIntOrNull(),
    )
  }

  override suspend fun uploadAsset(
    serverUrl: String,
    token: String,
    digest: String,
    kind: String,
    mimeType: String,
    width: Int,
    height: Int,
    bytes: ByteArray,
  ): UploadedSyncAsset {
    val request =
      Request.Builder()
        .url(serverUrl.trimEnd('/') + "/v2/assets/${digest.encodePathSegment()}")
        .header("Accept", "application/json")
        .header("Authorization", "Bearer $token")
        .header("Content-Type", mimeType)
        .header("X-ClipDock-Asset-Kind", kind)
        .header("X-ClipDock-Asset-Width", width.toString())
        .header("X-ClipDock-Asset-Height", height.toString())
        .put(bytes.toRequestBody(mimeType.toMediaType()))
        .build()
    val response = client.newCall(request).awaitBody()
    val responseText = response.bodyText
    if (responseText.isBlank()) {
      throw ClipDockApiException("http_${response.code}")
    }
    val envelope = json.decodeFromString<ApiEnvelope>(responseText)
    if (!response.isSuccessful || envelope.error != null) {
      val error = envelope.error
      throw ClipDockApiException(error?.code.orEmpty().ifBlank { "http_${response.code}" }, error?.message.orEmpty())
    }
    val data = JSONObject(envelope.data?.toString() ?: "{}")
    return UploadedSyncAsset(
      digest = data.optString("digest"),
      kind = data.optString("kind"),
      mimeType = data.optString("mime_type"),
      byteCount = data.optLong("size_bytes"),
      width = data.optInt("width_px"),
      height = data.optInt("height_px"),
      alreadyExists = data.optBoolean("already_exists"),
    )
  }

  private suspend inline fun <reified T> request(
    serverUrl: String,
    path: String,
    method: Method,
    token: String?,
    body: T,
  ): JsonObject =
    request(serverUrl, path, method, token, json.encodeToString(body))

  private suspend fun request(
    serverUrl: String,
    path: String,
    method: Method,
    token: String?,
    bodyJson: String? = null,
  ): JsonObject {
    val requestBody =
      when {
        bodyJson != null -> bodyJson.toRequestBody(JSON_MEDIA_TYPE)
        method.requiresRequestBody -> ByteArray(0).toRequestBody()
        else -> null
      }
    val request =
      Request.Builder()
        .url(serverUrl.trimEnd('/') + path)
        .header("Accept", "application/json")
        .apply {
          token?.let { header("Authorization", "Bearer $it") }
          method(method.value, requestBody)
        }
        .build()

    val response = client.newCall(request).awaitBody()
    val responseText = response.bodyText
    if (responseText.isBlank()) {
      if (response.isSuccessful) return buildJsonObject {}
      throw ClipDockApiException("http_${response.code}")
    }

    val envelope = json.decodeFromString<ApiEnvelope>(responseText)
    if (!response.isSuccessful || envelope.error != null) {
      val error = envelope.error
      throw ClipDockApiException(error?.code.orEmpty().ifBlank { "http_${response.code}" }, error?.message.orEmpty())
    }
    return envelope.data ?: buildJsonObject {}
  }

  private companion object {
    val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    val defaultClient: OkHttpClient =
      OkHttpClient.Builder()
        .connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(12, java.util.concurrent.TimeUnit.SECONDS)
        .build()
    val defaultJson: Json = Json { ignoreUnknownKeys = true }
  }
}

private data class NetworkResponse(
  val code: Int,
  val isSuccessful: Boolean,
  val bodyText: String,
)

private data class NetworkBytesResponse(
  val code: Int,
  val isSuccessful: Boolean,
  val headers: Map<String, String>,
  val bytes: ByteArray,
)

private suspend fun Call.awaitBody(): NetworkResponse =
  suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(
      object : Callback {
        override fun onFailure(call: Call, e: IOException) {
          if (!continuation.isCancelled) continuation.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
          response.use {
            try {
              val bodyText = it.body.string()
              if (!continuation.isCancelled) {
                continuation.resume(NetworkResponse(it.code, it.isSuccessful, bodyText))
              }
            } catch (throwable: Throwable) {
              if (!continuation.isCancelled) continuation.resumeWithException(throwable)
            }
          }
        }
      },
    )
  }

private suspend fun Call.awaitBytes(): NetworkBytesResponse =
  suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(
      object : Callback {
        override fun onFailure(call: Call, e: IOException) {
          if (!continuation.isCancelled) continuation.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
          response.use {
            try {
              val bytes = it.body.bytes()
              if (!continuation.isCancelled) {
                continuation.resume(
                  NetworkBytesResponse(
                    code = it.code,
                    isSuccessful = it.isSuccessful,
                    headers = it.headers.toMap().mapKeys { header -> header.key.lowercase() },
                    bytes = bytes,
                  ),
                )
              }
            } catch (throwable: Throwable) {
              if (!continuation.isCancelled) continuation.resumeWithException(throwable)
            }
          }
        }
      },
    )
  }

@Serializable
private data class ApiEnvelope(
  @SerialName("protocol_version") val protocolVersion: Int = 0,
  val data: JsonObject? = null,
  val error: ApiError? = null,
)

@Serializable
private data class ApiError(
  val code: String = "",
  val message: String = "",
)

@Serializable
private data class DeviceNameRequest(
  @SerialName("device_name") val deviceName: String,
)

@Serializable
private data class JoinSyncRequest(
  @SerialName("pairing_code") val pairingCode: String,
  @SerialName("device_name") val deviceName: String,
)

@Serializable
data class SyncPushEventRequest(
  @SerialName("client_event_id") val clientEventId: String,
  @SerialName("type") val type: String,
  @SerialName("content_hash") val contentHash: String,
  @SerialName("item_type") val itemType: String? = null,
  val payload: JsonObject? = null,
  @SerialName("copy_count_delta") val copyCountDelta: Long? = null,
)

@Serializable
private data class PushEventsRequest(
  val events: List<SyncPushEventRequest>,
)

@Serializable
private data class ReportP2pEndpointRequest(
  @SerialName("endpoint_id") val endpointId: String,
  @SerialName("relay_url") val relayUrl: String?,
  @SerialName("direct_addresses") val directAddresses: List<String>,
  val capabilities: P2pEndpointCapabilities,
  val quality: P2pEndpointQuality,
)

@Serializable
private data class P2pEndpointCapabilities(
  val transport: String = "iroh-blobs",
  @SerialName("blob_transfer") val blobTransfer: Boolean = true,
  @SerialName("android_client") val androidClient: Boolean = true,
)

@Serializable
private data class P2pEndpointQuality(
  @SerialName("path_type") val pathType: String = "unknown",
)

@Serializable
private data class UpsertP2pProviderRequest(
  val kind: String,
  @SerialName("byte_count") val byteCount: Long,
  @SerialName("mime_type") val mimeType: String?,
  val availability: String,
  val quality: P2pProviderQuality,
)

@Serializable
private data class P2pProviderQuality(
  @SerialName("blob_ticket") val blobTicket: String,
  val transport: String = "iroh-blobs",
)

private enum class Method(val value: String, val requiresRequestBody: Boolean = false) {
  Get("GET"),
  Post("POST", requiresRequestBody = true),
  Put("PUT", requiresRequestBody = true),
  Delete("DELETE")
}

private fun String.encodePathSegment(): String =
  replace(":", "%3A").replace("/", "%2F").replace(" ", "%20")

private fun String.toRealtimeUrl(cursor: Long): String {
  val trimmed = trimEnd('/')
  val base =
    when {
      trimmed.startsWith("https://") -> "wss://" + trimmed.removePrefix("https://")
      trimmed.startsWith("http://") -> "ws://" + trimmed.removePrefix("http://")
      else -> trimmed
    }
  return "$base/v2/ws?cursor=$cursor&protocol_version=2"
}
