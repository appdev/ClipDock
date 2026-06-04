package com.apkdv.clipdock.data

import java.io.File
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

  @Test
  fun preparedLocalImageBuildsImageUploadEventWithThumbnailFields() {
    val prepared =
      AndroidPreparedLocalImage(
        item =
          ClipHistoryItem(
            stableId = "blake3:${"a".repeat(64)}",
            contentHash = "blake3:${"a".repeat(64)}",
            type = ClipItemType.Image,
            title = "screen.webp",
            body = "image/png",
            detail = "16 bytes",
            sourceName = "Android",
            assetId = null,
            thumbnailUri = "file:///thumb.webp",
            thumbnailDigest = "blake3:${"b".repeat(64)}",
            thumbnailMimeType = "image/webp",
            thumbnailByteCount = 8,
            thumbnailWidth = 2,
            thumbnailHeight = 2,
            localUri = "content://payload",
            payloadState = PayloadState.Ready,
            transferState = TransferState.Ready,
            copiedAtMillis = 1234,
            copyCount = 1,
          ),
        payloadFile = File("/tmp/payload.png"),
        payloadMimeType = "image/png",
        payloadByteCount = 16,
        width = 4,
        height = 4,
        thumbnail =
          AndroidPreparedSyncThumbnail(
            bytes = byteArrayOf(1, 2, 3),
            digest = "blake3:${"b".repeat(64)}",
            mimeType = "image/webp",
            byteCount = 8,
            width = 2,
            height = 2,
            localUri = "file:///thumb.webp",
          ),
      )

    val event = prepared.toImageSyncPushEventRequest("dev_android", "blake3:${"c".repeat(64)}")

    assertEquals("item_upsert", event.type)
    assertEquals("image", event.itemType)
    assertEquals(prepared.item.contentHash, event.contentHash)
    assertEquals("android", event.payload?.get("source_platform")?.jsonPrimitive?.content)
    assertEquals("blake3:${"c".repeat(64)}", event.payload?.get("payload_asset_id")?.jsonPrimitive?.content)
    assertEquals("blake3:${"b".repeat(64)}", event.payload?.get("thumbnail_digest")?.jsonPrimitive?.content)
    assertEquals("image/webp", event.payload?.get("thumbnail_mime_type")?.jsonPrimitive?.content)
  }
}
