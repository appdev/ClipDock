package com.apkdv.clipdock.p2p

import org.json.JSONObject

data class P2pProviderCandidate(
  val ticket: String,
  val deviceId: String?,
  val deviceName: String?,
  val kind: String?,
  val mimeType: String?,
  val byteCount: Long?,
)

object P2pProviderSelector {
  fun selectDownloadCandidate(response: JSONObject, currentDeviceId: String? = null): P2pProviderCandidate? {
    val providers = response.optJSONArray("providers") ?: return null
    val candidates = mutableListOf<Pair<Int, P2pProviderCandidate>>()
    for (index in 0 until providers.length()) {
      val provider = providers.optJSONObject(index) ?: continue
      val ticket = provider.extractTicket() ?: continue
      val deviceId = provider.optNullableString("device_id")
      val availability = provider.optString("availability")
      val endpoint = provider.optJSONObject("endpoint")
      val score =
        listOf(
            if (availability == "online") 8 else 0,
            if (endpoint != null) 4 else 0,
            if (deviceId != null && deviceId != currentDeviceId) 2 else 0,
          )
          .sum()
      candidates +=
        score to
          P2pProviderCandidate(
            ticket = ticket,
            deviceId = deviceId,
            deviceName = provider.optNullableString("device_name"),
            kind = provider.optNullableString("kind"),
            mimeType = provider.optNullableString("mime_type"),
            byteCount = provider.optLongOrNull("byte_count"),
          )
    }
    return candidates.maxByOrNull { it.first }?.second
  }
}

private fun JSONObject.extractTicket(): String? {
  directTicket()?.let { return it }
  optJSONObject("quality")?.directTicket()?.let { return it }
  optJSONObject("endpoint")?.optJSONObject("capabilities")?.directTicket()?.let { return it }
  return null
}

private fun JSONObject.directTicket(): String? =
  optNullableString("blob_ticket")
    ?: optNullableString("iroh_blob_ticket")
    ?: optNullableString("iroh_ticket")
    ?: optNullableString("ticket")

private fun JSONObject.optNullableString(name: String): String? =
  if (has(name) && !isNull(name)) optString(name).takeIf { it.isNotBlank() } else null

private fun JSONObject.optLongOrNull(name: String): Long? =
  if (has(name) && !isNull(name)) optLong(name) else null
