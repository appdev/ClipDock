package com.apkdv.clipdock.data

import junit.framework.TestCase.assertEquals
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test

class P2pDeviceInfoTest {
  @Test
  fun toP2pDevices_parsesFreshEndpointResponse() {
    val devices =
      JSONArray()
        .put(
          JSONObject()
            .put("device_id", "dev_mac")
            .put("device_name", "MacBook Pro")
            .put(
              "endpoint",
              JSONObject()
                .put("endpoint_id", "iroh-node")
                .put("relay_url", "https://relay.example")
                .put("direct_addresses", JSONArray().put("192.168.1.2:1234"))
                .put("capabilities", JSONObject().put("blob_transfer", true))
                .put("updated_at_ms", 10L)
                .put("expires_at_ms", 20L),
            ),
        )
        .toP2pDevices()

    assertEquals(1, devices.size)
    assertEquals("dev_mac", devices[0].deviceId)
    assertEquals("MacBook Pro", devices[0].deviceName)
    assertEquals("iroh-node", devices[0].endpoint.endpointId)
    assertEquals(listOf("192.168.1.2:1234"), devices[0].endpoint.directAddresses)
  }

  @Test
  fun overlayPreferenceSanitizersClampApprovedRanges() {
    assertEquals(52, sanitizeOverlaySizeDp(12))
    assertEquals(72, sanitizeOverlaySizeDp(99))
    assertEquals(64, sanitizeOverlaySizeDp(64))
    assertEquals(45, sanitizeOverlayIdleOpacityPercent(1))
    assertEquals(100, sanitizeOverlayIdleOpacityPercent(120))
    assertEquals(0f, sanitizeOverlayVerticalFraction(-1f))
    assertEquals(1f, sanitizeOverlayVerticalFraction(2f))
  }
}
