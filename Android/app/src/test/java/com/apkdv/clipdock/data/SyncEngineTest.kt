package com.apkdv.clipdock.data

import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.json.JSONObject
import org.junit.Test

class SyncEngineTest {
  @Test
  fun emptyCursorUsesSnapshotCorrection() = runTest {
    val store = FakeStore(SyncProgress(emptyList(), cursor = 0, snapshotSeq = 0))
    val api = FakeApi(snapshot = snapshotJson(seq = 5, contentHash = hash("snapshot")))
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    assertTrue(result.usedSnapshot)
    assertEquals("empty_cursor", result.recoveryReason)
    assertEquals(5, result.cursor)
    assertEquals(5, store.progress.cursor)
    assertEquals(1, result.items.size)
  }

  @Test
  fun deltaAppliesEventsTombstonesAndPreservesDownloadedPayload() = runTest {
    val contentHash = hash("downloaded")
    val downloaded =
      item(contentHash)
        .copy(
          type = ClipItemType.File,
          localUri = "content://downloaded/file.txt",
          payloadState = PayloadState.Ready,
          transferState = TransferState.Ready,
          copyCount = 3,
        )
    val deleted = item(hash("deleted"))
    val store = FakeStore(SyncProgress(listOf(downloaded, deleted), cursor = 5, snapshotSeq = 5))
    val api =
      FakeApi(
        events =
          restEventsJson(
            nextCursor = 9,
            events =
              listOf(
                upsertEvent(7, contentHash, itemType = "file", text = "remote file", copyDelta = 2),
                deleteEvent(9, deleted.contentHash),
              ),
          ),
      )
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    assertFalse(result.usedSnapshot)
    assertEquals(9, result.cursor)
    assertEquals(1, result.items.size)
    assertEquals(contentHash, result.items[0].contentHash)
    assertEquals("content://downloaded/file.txt", result.items[0].localUri)
    assertEquals(5, result.items[0].copyCount)
  }

  @Test
  fun payloadAssetUpdateMergesImageAssetWithoutChangingOrderOrCopyCount() = runTest {
    val contentHash = hash("image-follow-up")
    val store = FakeStore(SyncProgress(emptyList(), cursor = 5, snapshotSeq = 5))
    val api =
      FakeApi(
        events =
          restEventsJson(
            nextCursor = 8,
            events =
              listOf(
                upsertEvent(6, contentHash, itemType = "image", text = "screen.webp", copyDelta = 1),
                payloadAssetUpdateEvent(8, contentHash, "blake3:${"a".repeat(64)}"),
              ),
          ),
      )
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    val item = result.items.single()
    assertEquals(contentHash, item.contentHash)
    assertEquals(ClipItemType.Image, item.type)
    assertEquals("blake3:${"a".repeat(64)}", item.assetId)
    assertEquals(1L, item.copyCount)
    assertEquals(6L, item.copiedAtMillis)
    assertEquals(8L, result.cursor)
  }

  @Test
  fun invalidPayloadAssetUpdateFallsBackToSnapshot() = runTest {
    val contentHash = hash("image-follow-up-invalid")
    val store = FakeStore(SyncProgress(emptyList(), cursor = 5, snapshotSeq = 5))
    val api =
      FakeApi(
        events =
          restEventsJson(
            nextCursor = 8,
            events =
              listOf(
                upsertEvent(6, contentHash, itemType = "image", text = "screen.webp", copyDelta = 1),
                payloadAssetUpdateEvent(8, contentHash, "blake3:invalid"),
              ),
          ),
        snapshot = snapshotJson(seq = 9, contentHash = hash("corrected-after-invalid-payload-update")),
      )
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    assertTrue(result.usedSnapshot)
    assertEquals("invalid_payload_asset_update_payload", result.recoveryReason)
    assertEquals(hash("corrected-after-invalid-payload-update"), result.items.single().contentHash)
  }

  @Test
  fun payloadAssetUpdateWithNonImageEventTypeFallsBackToSnapshot() = runTest {
    val contentHash = hash("image-follow-up-wrong-event-type")
    val store = FakeStore(SyncProgress(emptyList(), cursor = 5, snapshotSeq = 5))
    val invalidUpdate =
      payloadAssetUpdateEvent(8, contentHash, "blake3:${"a".repeat(64)}")
        .put("item_type", "text")
    val api =
      FakeApi(
        events =
          restEventsJson(
            nextCursor = 8,
            events =
              listOf(
                upsertEvent(6, contentHash, itemType = "image", text = "screen.webp", copyDelta = 1),
                invalidUpdate,
              ),
          ),
        snapshot = snapshotJson(seq = 9, contentHash = hash("corrected-after-invalid-event-type")),
      )
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    assertTrue(result.usedSnapshot)
    assertEquals("payload_asset_update_invalid_item_type", result.recoveryReason)
    assertEquals(hash("corrected-after-invalid-event-type"), result.items.single().contentHash)
  }

  @Test
  fun invalidThumbnailUpsertFallsBackToSnapshot() = runTest {
    val contentHash = hash("image-invalid-thumbnail")
    val invalidUpsert = upsertEvent(6, contentHash, itemType = "image", text = "screen.webp")
    invalidUpsert.getJSONObject("payload")
      .put("thumbnail_digest", "blake3:${"1".repeat(64)}")
    val store = FakeStore(SyncProgress(emptyList(), cursor = 5, snapshotSeq = 5))
    val api =
      FakeApi(
        events = restEventsJson(nextCursor = 6, events = listOf(invalidUpsert)),
        snapshot = snapshotJson(seq = 9, contentHash = hash("corrected-after-invalid-thumbnail")),
      )
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    assertTrue(result.usedSnapshot)
    assertEquals("invalid_thumbnail_payload", result.recoveryReason)
    assertEquals(hash("corrected-after-invalid-thumbnail"), result.items.single().contentHash)
  }

  @Test
  fun invalidThumbnailSnapshotIsRejectedWithoutPersisting() = runTest {
    val contentHash = hash("snapshot-invalid-thumbnail")
    val snapshotItem =
      JSONObject()
        .put("content_hash", contentHash)
        .put("item_type", "text")
        .put(
          "payload",
          JSONObject()
            .put("text", "bad snapshot")
            .put("thumbnail_digest", "blake3:${"1".repeat(64)}")
            .put("thumbnail_mime_type", "image/webp")
            .put("thumbnail_byte_count", 24000)
            .put("thumbnail_width", 320)
            .put("thumbnail_height", 180),
        )
        .put("copy_count", 1)
        .put("updated_at_ms", 8)
        .put("last_server_seq", 8)
    val store = FakeStore(SyncProgress(emptyList(), cursor = 0, snapshotSeq = 0))
    val api = FakeApi(snapshot = snapshotJson(seq = 8, items = listOf(snapshotItem)))
    val engine = SyncEngine(store, api)

    try {
      engine.syncFromStoredCursor("http://server", "token")
      error("Expected invalid thumbnail snapshot rejection")
    } catch (recovery: SyncRecoveryRequired) {
      assertEquals("invalid_thumbnail_payload", recovery.reason)
    }
    assertEquals(0L, store.progress.cursor)
    assertTrue(store.progress.items.isEmpty())
  }

  @Test
  fun invalidCursorFallsBackToSnapshot() = runTest {
    val store = FakeStore(SyncProgress(listOf(item(hash("old"))), cursor = 30, snapshotSeq = 20))
    val api =
      FakeApi(
        eventsFailure = ClipDockApiException("invalid_cursor", "invalid_cursor"),
        snapshot = snapshotJson(seq = 12, contentHash = hash("corrected")),
      )
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    assertTrue(result.usedSnapshot)
    assertEquals("invalid_cursor", result.recoveryReason)
    assertEquals(12, result.cursor)
    assertEquals(hash("corrected"), result.items.single().contentHash)
  }

  @Test
  fun parseCorruptionFallsBackToSnapshot() = runTest {
    val store = FakeStore(SyncProgress(emptyList(), cursor = 10, snapshotSeq = 10), loadFailure = SyncRecoveryRequired("items_parse_corruption"))
    val api = FakeApi(snapshot = snapshotJson(seq = 11, contentHash = hash("after-corruption")))
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    assertTrue(result.usedSnapshot)
    assertEquals("items_parse_corruption", result.recoveryReason)
    assertEquals(11, store.progress.cursor)
  }

  @Test
  fun realtimeEventsIgnoreDuplicatesAndAllowGlobalSeqGaps() = runTest {
    val store = FakeStore(SyncProgress(listOf(item(hash("existing"))), cursor = 10, snapshotSeq = 8))
    val engine = SyncEngine(store, FakeApi())

    val result =
      engine.applyRealtimeEvents(
        listOf(
          upsertEvent(10, hash("duplicate")),
          upsertEvent(14, hash("new-gap"), text = "new gap"),
        ),
      )

    assertEquals(14, result.cursor)
    assertEquals(2, result.items.size)
    assertEquals(14, store.progress.cursor)
    assertTrue(result.items.any { it.contentHash == hash("new-gap") })
  }

  @Test
  fun restOrderingRegressionFallsBackToSnapshot() = runTest {
    val store = FakeStore(SyncProgress(listOf(item(hash("old"))), cursor = 5, snapshotSeq = 5))
    val api =
      FakeApi(
        events =
          restEventsJson(
            nextCursor = 8,
            events =
              listOf(
                upsertEvent(8, hash("later")),
                upsertEvent(7, hash("regressed")),
              ),
          ),
        snapshot = snapshotJson(seq = 9, contentHash = hash("snapshot-after-regression")),
      )
    val engine = SyncEngine(store, api)

    val result = engine.syncFromStoredCursor("http://server", "token")

    assertTrue(result.usedSnapshot)
    assertEquals("ordering_regression", result.recoveryReason)
    assertEquals(9, result.cursor)
    assertEquals(hash("snapshot-after-regression"), result.items.single().contentHash)
  }

  @Test
  fun realtimeOrderingRegressionFallsBackToSnapshotWhenContextIsProvided() = runTest {
    val store = FakeStore(SyncProgress(listOf(item(hash("old"))), cursor = 5, snapshotSeq = 5))
    val api = FakeApi(snapshot = snapshotJson(seq = 11, contentHash = hash("realtime-snapshot")))
    val engine = SyncEngine(store, api)

    val result =
      engine.applyRealtimeEvents(
        listOf(
          upsertEvent(9, hash("later")),
          upsertEvent(8, hash("regressed")),
        ),
        serverUrl = "http://server",
        token = "token",
      )

    assertTrue(result.usedSnapshot)
    assertEquals("ordering_regression", result.recoveryReason)
    assertEquals(11, result.cursor)
    assertEquals(hash("realtime-snapshot"), result.items.single().contentHash)
  }

  @Test
  fun persistenceFailureDoesNotAdvanceCursor() = runTest {
    val store = FakeStore(SyncProgress(emptyList(), cursor = 5, snapshotSeq = 5), persistSucceeds = false)
    val api = FakeApi(events = restEventsJson(nextCursor = 6, events = listOf(upsertEvent(6, hash("new")))))
    val engine = SyncEngine(store, api)

    try {
      engine.syncFromStoredCursor("http://server", "token")
      error("Expected persistence failure")
    } catch (recovery: SyncRecoveryRequired) {
      assertEquals("persistence_failure", recovery.reason)
      assertEquals(5, store.progress.cursor)
    }
  }

  @Test
  fun pushLocalItemUploadsTextLikeItemWithBlake3HashAndAndroidPayload() = runTest {
    val store = FakeStore(SyncProgress(emptyList(), cursor = 5, snapshotSeq = 5))
    val api = FakeApi(pushNextCursor = 19, pushServerSeq = 19)
    val engine = SyncEngine(store, api)
    val localItem =
      item("local-placeholder")
        .copy(
          type = ClipItemType.Link,
          title = "Example",
          body = "https://example.com/path",
          sourceName = null,
          copiedAtMillis = 1234,
          copyCount = 2,
        )

    val result = engine.pushLocalItem("http://server", "token", "dev_android", localItem)

    val pushed = api.pushedEvents.single()
    assertEquals("item_upsert", pushed.type)
    assertEquals("link", pushed.itemType)
    assertTrue(pushed.contentHash.matches(Regex("^blake3:[0-9a-f]{64}$")))
    assertEquals(blake3ContentHash("${pushed.itemType}\n${pushed.payload}"), pushed.contentHash)
    assertEquals("android", pushed.payload?.get("source_platform")?.jsonPrimitive?.content)
    assertEquals("Android", pushed.payload?.get("source_app_name")?.jsonPrimitive?.content)
    assertEquals("https://example.com/path", pushed.payload?.get("url")?.jsonPrimitive?.content)
    assertEquals(2L, pushed.copyCountDelta)
    assertEquals(localItem.toSyncPushEventRequest("dev_android").clientEventId, pushed.clientEventId)
    assertEquals(pushed.contentHash, result.contentHash)
    assertEquals(19L, result.nextCursor)
    assertEquals(19L, result.serverSeq)
    assertFalse(result.duplicate)
    assertEquals(5L, store.progress.cursor)
  }

  @Test
  fun pushLocalItemThenOwnEchoDeltaAppliesOnceAndAdvancesCursor() = runTest {
    val store = FakeStore(SyncProgress(emptyList(), cursor = 5, snapshotSeq = 5))
    val api = FakeApi(pushNextCursor = 19, pushServerSeq = 19)
    val engine = SyncEngine(store, api)
    val localItem =
      item("local-placeholder")
        .copy(
          type = ClipItemType.Text,
          title = "Local hello",
          body = "Local hello",
          sourceName = "Android",
          copiedAtMillis = 1234,
          copyCount = 2,
        )
    val pushEvent = localItem.toSyncPushEventRequest("dev_android")

    val pushResult = engine.pushLocalItem("http://server", "token", "dev_android", localItem)
    api.events = restEventsJson(
      nextCursor = 19,
      events = listOf(echoUpsertEvent(serverSeq = 19, deviceId = "dev_android", event = pushEvent)),
    )
    val reconcile = engine.syncFromStoredCursor("http://server", "token")

    assertEquals(pushEvent.contentHash, pushResult.contentHash)
    assertEquals(5L, api.eventsAfterSeqs.single())
    assertEquals(19L, reconcile.cursor)
    assertEquals(19L, store.progress.cursor)
    assertEquals(1, reconcile.items.size)
    assertEquals(pushEvent.contentHash, reconcile.items.single().contentHash)
    assertEquals(2L, reconcile.items.single().copyCount)
  }

  private class FakeStore(
    initial: SyncProgress,
    private val persistSucceeds: Boolean = true,
    private val loadFailure: SyncRecoveryRequired? = null,
  ) : SyncStore {
    var progress = initial

    override fun loadProgress(): SyncProgress {
      loadFailure?.let { throw it }
      return progress
    }

    override fun persistProgress(items: List<ClipHistoryItem>, cursor: Long, snapshotSeq: Long): Boolean {
      if (!persistSucceeds) return false
      progress = SyncProgress(items, cursor, snapshotSeq)
      return true
    }
  }

  private class FakeApi(
    private val snapshot: JsonObject = snapshotJson(seq = 0, contentHash = hash("empty")),
    var events: JsonObject = restEventsJson(nextCursor = 0, events = emptyList()),
    private val eventsFailure: Throwable? = null,
    private val pushNextCursor: Long = 0,
    private val pushServerSeq: Long = 0,
  ) : ClipDockSyncApi {
    val pushedEvents = mutableListOf<SyncPushEventRequest>()
    val eventsAfterSeqs = mutableListOf<Long>()

    override suspend fun snapshot(serverUrl: String, token: String): JsonObject = snapshot

    override suspend fun events(serverUrl: String, token: String, afterSeq: Long, limit: Int): JsonObject {
      eventsFailure?.let { throw it }
      eventsAfterSeqs += afterSeq
      return events
    }

    override suspend fun pushEvents(serverUrl: String, token: String, events: List<SyncPushEventRequest>): JsonObject {
      pushedEvents += events
      val pushed =
        org.json.JSONArray(
          events.map { event ->
            JSONObject()
              .put("client_event_id", event.clientEventId)
              .put("server_seq", pushServerSeq)
              .put("duplicate", false)
          },
        )
      return jsonObject(JSONObject().put("events", pushed).put("next_cursor", pushNextCursor).toString())
    }
  }
}

private fun item(contentHash: String): ClipHistoryItem =
  ClipHistoryItem(
    stableId = contentHash,
    contentHash = contentHash,
    type = ClipItemType.Text,
    title = "title",
    body = "body",
    detail = "",
    sourceName = null,
    assetId = null,
    thumbnailUri = null,
    thumbnailDigest = null,
    thumbnailMimeType = null,
    thumbnailByteCount = null,
    thumbnailWidth = null,
    thumbnailHeight = null,
    localUri = null,
    payloadState = PayloadState.Ready,
    transferState = TransferState.Idle,
    copiedAtMillis = 1,
    copyCount = 1,
  )

private fun snapshotJson(seq: Long, contentHash: String): JsonObject =
  jsonObject(
    """
      {
        "snapshot_seq": $seq,
        "items": [
          {
            "content_hash": "$contentHash",
            "item_type": "text",
            "payload": {"text": "snapshot"},
            "copy_count": 1,
            "updated_at_ms": $seq,
            "last_server_seq": $seq
          }
        ],
        "tombstones": []
      }
    """.trimIndent(),
  )

private fun snapshotJson(seq: Long, items: List<JSONObject>): JsonObject =
  jsonObject(
    JSONObject()
      .put("snapshot_seq", seq)
      .put("items", org.json.JSONArray(items))
      .put("tombstones", org.json.JSONArray())
      .toString(),
  )

private fun restEventsJson(nextCursor: Long, events: List<JSONObject>): JsonObject =
  jsonObject(JSONObject().put("next_cursor", nextCursor).put("events", org.json.JSONArray(events)).toString())

private fun upsertEvent(
  serverSeq: Long,
  contentHash: String,
  itemType: String = "text",
  text: String = "text",
  copyDelta: Long = 1,
): JSONObject =
  JSONObject()
    .put("server_seq", serverSeq)
    .put("device_id", "dev")
    .put("client_event_id", "event-$serverSeq")
    .put("type", "item_upsert")
    .put("content_hash", contentHash)
    .put("item_type", itemType)
    .put("payload", JSONObject().put("text", text).put("file_name", "file.txt"))
    .put("copy_count_delta", copyDelta)
    .put("created_at_ms", serverSeq)

private fun echoUpsertEvent(serverSeq: Long, deviceId: String, event: SyncPushEventRequest): JSONObject =
  JSONObject()
    .put("server_seq", serverSeq)
    .put("device_id", deviceId)
    .put("client_event_id", event.clientEventId)
    .put("type", event.type)
    .put("content_hash", event.contentHash)
    .put("item_type", event.itemType)
    .put("payload", JSONObject(event.payload.toString()))
    .put("copy_count_delta", event.copyCountDelta)
    .put("created_at_ms", serverSeq)

private fun deleteEvent(serverSeq: Long, contentHash: String): JSONObject =
  JSONObject()
    .put("server_seq", serverSeq)
    .put("device_id", "dev")
    .put("client_event_id", "delete-$serverSeq")
    .put("type", "item_delete")
    .put("content_hash", contentHash)
    .put("created_at_ms", serverSeq)

private fun payloadAssetUpdateEvent(serverSeq: Long, contentHash: String, assetId: String): JSONObject =
  JSONObject()
    .put("server_seq", serverSeq)
    .put("device_id", "dev")
    .put("client_event_id", "asset-update-$serverSeq")
    .put("type", "item_payload_asset_update")
    .put("content_hash", contentHash)
    .put("item_type", "image")
    .put("payload", JSONObject().put("payload_asset_id", assetId).put("asset_id", assetId))
    .put("created_at_ms", serverSeq)

private fun jsonObject(value: String): JsonObject = Json.parseToJsonElement(value) as JsonObject

private fun hash(label: String): String =
  "blake3:" + label.encodeToByteArray().joinToString("") { "%02x".format(it.toInt() and 0xff) }.padEnd(64, '0').take(64)
