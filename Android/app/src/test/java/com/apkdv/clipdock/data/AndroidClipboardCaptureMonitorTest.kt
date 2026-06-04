package com.apkdv.clipdock.data

import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertNotNull
import junit.framework.TestCase.assertTrue
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class AndroidClipboardCaptureMonitorTest {
  @Test
  fun localClipboardTextItemBuildsBlake3UploadEventForAndroidGeneratedLink() {
    val item = localClipboardTextItem("https://example.com/from-android", copiedAtMillis = 1234)

    assertNotNull(item)
    item!!
    assertEquals("", item.contentHash)
    assertEquals(ClipItemType.Link, item.type)
    assertEquals("Android", item.sourceName)

    val event = item.toSyncPushEventRequest("dev_android")

    assertEquals("item_upsert", event.type)
    assertEquals("link", event.itemType)
    assertTrue(event.contentHash.matches(Regex("^blake3:[0-9a-f]{64}$")))
    assertEquals(blake3ContentHash("${event.itemType}\n${event.payload}"), event.contentHash)
    assertEquals("android", event.payload?.get("source_platform")?.jsonPrimitive?.content)
    assertEquals("Android", event.payload?.get("source_app_name")?.jsonPrimitive?.content)
    assertEquals("https://example.com/from-android", event.payload?.get("url")?.jsonPrimitive?.content)
  }

  @Test
  fun localClipboardTextItemClassifiesColorAndIgnoresBlankText() {
    val color = localClipboardTextItem("#AABBCC", copiedAtMillis = 1234)

    assertNotNull(color)
    assertEquals(ClipItemType.Color, color!!.type)
    assertEquals(null, localClipboardTextItem("   ", copiedAtMillis = 1234))
  }
}
