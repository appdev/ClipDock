package com.apkdv.clipdock.data

import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test

class ClipHistoryItemTest {
  @Test
  fun compactText_usesImagePlaceholder() {
    val item = sampleItem(type = ClipItemType.Image, title = "[图片]", localUri = null)

    assertEquals("[图片]", item.compactText)
    assertTrue(item.needsRemotePayload)
  }

  @Test
  fun compactText_usesFilenameForFile() {
    val item = sampleItem(type = ClipItemType.File, title = "meeting_notes_20250528.pdf", localUri = "content://local/file")

    assertEquals("meeting_notes_20250528.pdf", item.compactText)
    assertFalse(item.needsRemotePayload)
  }

  @Test
  fun clipType_mapsKnownAndUnknownWireNames() {
    assertEquals(ClipItemType.RichText, clipType("rich_text"))
    assertEquals(ClipItemType.Unknown, clipType("anything_else"))
  }

  @Test
  fun preservingDownloadedPayload_keepsLocalUriAfterRemoteRefresh() {
    val remote = sampleItem(type = ClipItemType.File, title = "e2e-file.txt", localUri = null)
    val downloaded =
      remote.copy(
        localUri = "content://com.apkdv.clipdock.files/p2p-payloads/e2e-file.txt",
        payloadState = PayloadState.Ready,
        transferState = TransferState.Ready,
      )

    val merged = remote.preservingDownloadedPayload(downloaded)

    assertEquals(downloaded.localUri, merged.localUri)
    assertEquals(PayloadState.Ready, merged.payloadState)
    assertEquals(TransferState.Ready, merged.transferState)
  }

  @Test
  fun eventItems_removeTombstoneWhenLaterUpsertRestoresContent() {
    val contentHash = "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    val tombstones = mutableSetOf(contentHash)
    val events =
      JSONArray()
        .put(JSONObject().put("type", "item_delete").put("content_hash", contentHash))
        .put(
          JSONObject()
            .put("type", "item_upsert")
            .put("content_hash", contentHash)
            .put("item_type", "text")
            .put("copy_count_delta", 1L)
            .put("created_at_ms", 123L)
            .put("payload", JSONObject().put("text", "restored").put("summary", "restored")),
        )

    val items = events.toEventItems(tombstones)

    assertTrue(tombstones.isEmpty())
    assertEquals(1, items.size)
    assertEquals(contentHash, items[0].contentHash)
    assertEquals("restored", items[0].title)
  }

  @Test
  fun fromServerEvent_mapsLinkMetadataPreviewFields() {
    val contentHash = "blake3:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    val event =
      JSONObject()
        .put("type", "item_upsert")
        .put("content_hash", contentHash)
        .put("item_type", "link")
        .put("copy_count_delta", 1L)
        .put("created_at_ms", 123L)
        .put(
          "payload",
          JSONObject()
            .put("url", "https://example.com/article")
            .put("display_url", "https://example.com/article")
            .put("title", "Example article")
            .put("site_name", "Example")
            .put("icon_uri", "file:///icon.png")
            .put("image_uri", "file:///preview.jpg")
            .put("metadata_state", "ready"),
        )

    val item = ClipHistoryItem.fromServerEvent(event)!!

    assertEquals(ClipItemType.Link, item.type)
    assertEquals("https://example.com/article", item.body)
    assertEquals("file:///icon.png", item.linkIconUri)
    assertEquals("file:///preview.jpg", item.linkPreviewUri)
    assertEquals("Example", item.linkSiteName)
    assertEquals("ready", item.linkMetadataState)
  }

  @Test
  fun fromJson_restoresLinkMetadataPreviewFields() {
    val item =
      sampleItem(type = ClipItemType.Link, title = "Example", localUri = null)
        .copy(
          body = "https://example.com/article",
          linkIconUri = "file:///icon.png",
          linkPreviewUri = "file:///preview.jpg",
          linkSiteName = "Example",
          linkMetadataState = "ready",
        )

    val restored = ClipHistoryItem.fromJson(item.toJson())

    assertEquals(item.linkIconUri, restored.linkIconUri)
    assertEquals(item.linkPreviewUri, restored.linkPreviewUri)
    assertEquals(item.linkSiteName, restored.linkSiteName)
    assertEquals(item.linkMetadataState, restored.linkMetadataState)
  }

  @Test
  fun fromJson_resetsInFlightTransferStateAfterProcessRestart() {
    val item =
      sampleItem(type = ClipItemType.File, title = "remote.txt", localUri = null)
        .copy(transferState = TransferState.Downloading)

    val restored = ClipHistoryItem.fromJson(item.toJson())

    assertEquals(PayloadState.RemoteOnly, restored.payloadState)
    assertEquals(TransferState.Failed, restored.transferState)
  }
}

private fun sampleItem(type: ClipItemType, title: String, localUri: String?): ClipHistoryItem =
  ClipHistoryItem(
    stableId = "stable",
    contentHash = "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    type = type,
    title = title,
    body = "",
    detail = "",
    sourceName = null,
    assetId = null,
    thumbnailUri = null,
    thumbnailDigest = null,
    thumbnailMimeType = null,
    thumbnailByteCount = null,
    thumbnailWidth = null,
    thumbnailHeight = null,
    localUri = localUri,
    payloadState = if (localUri == null && (type == ClipItemType.Image || type == ClipItemType.File)) PayloadState.RemoteOnly else PayloadState.Ready,
    transferState = TransferState.Idle,
    copiedAtMillis = 1,
    copyCount = 1,
  )
