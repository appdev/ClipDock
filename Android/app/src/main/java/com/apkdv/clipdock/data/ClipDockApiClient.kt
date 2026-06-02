package com.apkdv.clipdock.data

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONArray
import org.json.JSONObject

class ClipDockApiException(val code: String, message: String = code) : Exception(message)

class ClipDockApiClient {
  fun health(serverUrl: String): JSONObject = request(serverUrl, "/health", Method.Get, token = null)

  fun info(serverUrl: String, token: String): JSONObject = request(serverUrl, "/v1/info", Method.Get, token)

  fun createSync(serverUrl: String, deviceName: String): JSONObject =
    request(
      serverUrl,
      "/v1/sync/create",
      Method.Post,
      token = null,
      body = JSONObject().put("device_name", deviceName),
    )

  fun joinSync(serverUrl: String, pairingCode: String, deviceName: String): JSONObject =
    request(
      serverUrl,
      "/v1/sync/join",
      Method.Post,
      token = null,
      body = JSONObject().put("pairing_code", pairingCode).put("device_name", deviceName),
    )

  fun createInvite(serverUrl: String, token: String): JSONObject =
    request(serverUrl, "/v1/sync/invites", Method.Post, token)

  fun snapshot(serverUrl: String, token: String): JSONObject = request(serverUrl, "/v1/snapshot", Method.Get, token)

  fun events(serverUrl: String, token: String, afterSeq: Long, limit: Int = 500): JSONObject =
    request(serverUrl, "/v1/events?after_seq=$afterSeq&limit=$limit", Method.Get, token)

  fun p2pProviders(serverUrl: String, token: String, assetId: String): JSONObject =
    request(serverUrl, "/v1/p2p/assets/${assetId.encodePathSegment()}/providers", Method.Get, token)

  fun reportP2pEndpoint(
    serverUrl: String,
    token: String,
    endpointId: String,
    relayUrl: String?,
    directAddresses: List<String>,
  ): JSONObject =
    request(
      serverUrl,
      "/v1/p2p/endpoint",
      Method.Put,
      token,
      body =
        JSONObject()
          .put("endpoint_id", endpointId)
          .put("relay_url", relayUrl ?: JSONObject.NULL)
          .put("direct_addresses", JSONArray(directAddresses))
          .put(
            "capabilities",
            JSONObject()
              .put("transport", "iroh-blobs")
              .put("blob_transfer", true)
              .put("android_client", true),
          )
          .put("quality", JSONObject().put("path_type", "unknown")),
    )

  fun upsertP2pProvider(
    serverUrl: String,
    token: String,
    assetId: String,
    kind: String,
    byteCount: Long,
    mimeType: String?,
    ticket: String,
  ): JSONObject =
    request(
      serverUrl,
      "/v1/p2p/assets/${assetId.encodePathSegment()}/providers/me",
      Method.Put,
      token,
      body =
        JSONObject()
          .put("kind", kind)
          .put("byte_count", byteCount)
          .put("mime_type", mimeType ?: JSONObject.NULL)
          .put("availability", "online")
          .put(
            "quality",
            JSONObject()
              .put("transport", "iroh-blobs")
              .put("blob_ticket", ticket),
          ),
    )

  fun deleteP2pProvider(serverUrl: String, token: String, assetId: String): JSONObject =
    request(
      serverUrl,
      "/v1/p2p/assets/${assetId.encodePathSegment()}/providers/me",
      Method.Delete,
      token,
    )

  private fun request(
    serverUrl: String,
    path: String,
    method: Method,
    token: String?,
    body: JSONObject? = null,
  ): JSONObject {
    val connection = URL(serverUrl.trimEnd('/') + path).openConnection() as HttpURLConnection
    connection.requestMethod = method.value
    connection.connectTimeout = 5_000
    connection.readTimeout = 12_000
    connection.setRequestProperty("Accept", "application/json")
    token?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
    if (body != null) {
      val bytes = body.toString().toByteArray(Charsets.UTF_8)
      connection.doOutput = true
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("Content-Length", bytes.size.toString())
      connection.outputStream.use { it.write(bytes) }
    }

    val status = connection.responseCode
    val responseText =
      (if (status in 200..299) connection.inputStream else connection.errorStream)
        ?.use { stream -> BufferedReader(InputStreamReader(stream)).readText() }
        .orEmpty()
    if (responseText.isBlank()) {
      if (status in 200..299) return JSONObject()
      throw ClipDockApiException("http_$status")
    }

    val envelope = JSONObject(responseText)
    if (status !in 200..299 || envelope.has("error")) {
      val error = envelope.optJSONObject("error")
      throw ClipDockApiException(error?.optString("code").orEmpty().ifBlank { "http_$status" }, error?.optString("message").orEmpty())
    }
    return envelope.optJSONObject("data") ?: JSONObject()
  }
}

private enum class Method(val value: String) {
  Get("GET"),
  Post("POST"),
  Put("PUT"),
  Delete("DELETE")
}

private fun String.encodePathSegment(): String =
  replace(":", "%3A").replace("/", "%2F").replace(" ", "%20")
