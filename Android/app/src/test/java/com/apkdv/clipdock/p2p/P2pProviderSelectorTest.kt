package com.apkdv.clipdock.p2p

import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertNull
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test

class P2pProviderSelectorTest {
  @Test
  fun selectDownloadCandidate_prefersOnlineProviderWithTicket() {
    val response =
      JSONObject()
        .put(
          "providers",
          JSONArray()
            .put(
              JSONObject()
                .put("device_id", "stale-device")
                .put("availability", "last_seen")
                .put("quality", JSONObject().put("blob_ticket", "stale-ticket")),
            )
            .put(
              JSONObject()
                .put("device_id", "provider-device")
                .put("device_name", "MacBook")
                .put("kind", "file_payload")
                .put("mime_type", "application/pdf")
                .put("byte_count", 1024)
                .put("availability", "online")
                .put("endpoint", JSONObject().put("endpoint_id", "node-a"))
                .put("quality", JSONObject().put("blob_ticket", "fresh-ticket")),
            ),
        )

    val candidate = P2pProviderSelector.selectDownloadCandidate(response, currentDeviceId = "android-device")

    assertEquals("fresh-ticket", candidate?.ticket)
    assertEquals("provider-device", candidate?.deviceId)
    assertEquals("application/pdf", candidate?.mimeType)
    assertEquals(1024L, candidate?.byteCount)
  }

  @Test
  fun selectDownloadCandidate_returnsNullWithoutTicket() {
    val response =
      JSONObject()
        .put(
          "providers",
          JSONArray()
            .put(
              JSONObject()
                .put("device_id", "provider-device")
                .put("availability", "online")
                .put("quality", JSONObject().put("throughput_bytes_per_sec", 12000)),
            ),
        )

    assertNull(P2pProviderSelector.selectDownloadCandidate(response))
  }
}
