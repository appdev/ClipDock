package com.apkdv.clipdock.data

import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import okhttp3.Request
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test

class SyncRealtimeClientTest {
  @OptIn(ExperimentalCoroutinesApi::class)
  @Test
  fun closedSocketRequestsRecoveryUnlessItWasClientReconnectClose() = runTest {
    val restCatchup = CompletableDeferred<JsonObject>()
    val store = RealtimeFakeStore(SyncProgress(emptyList(), cursor = 3, snapshotSeq = 3))
    val api = DeferredEventsApi(restCatchup)
    val engine = SyncEngine(store, api)
    val connector = FakeRealtimeConnector()
    val clientReconnectStates = mutableListOf<String>()
    var recoveries = 0
    val client =
      SyncRealtimeClient(
        socketConnector = connector,
        engine = engine,
        scope = this,
        onState = clientReconnectStates::add,
        onRecoveryRequired = { recoveries += 1 },
      )

    client.connect("http://server", "token", cursor = 3)

    connector.listener.onClosed(connector.socket, 1000, "server_shutdown")
    assertEquals(1, recoveries)
    assertEquals("socket_closed", clientReconnectStates.last())

    connector.listener.onClosed(connector.socket, 1000, "reconnect")
    assertEquals(1, recoveries)
  }

  @OptIn(ExperimentalCoroutinesApi::class)
  @Test
  fun catchupRequiredKeepsSocketAndBuffersUntilRestCatchupThenAcks() = runTest {
    val restCatchup = CompletableDeferred<JsonObject>()
    val store = RealtimeFakeStore(SyncProgress(emptyList(), cursor = 3, snapshotSeq = 3))
    val api = DeferredEventsApi(restCatchup)
    val engine = SyncEngine(store, api)
    val connector = FakeRealtimeConnector()
    val states = mutableListOf<String>()
    val appliedResults = mutableListOf<SyncResult>()
    var recoveries = 0
    val client =
      SyncRealtimeClient(
        socketConnector = connector,
        engine = engine,
        scope = this,
        onState = states::add,
        onRecoveryRequired = { recoveries += 1 },
        onSyncResult = appliedResults::add,
      )

    client.connect("http://server", "token", cursor = 3)
    val listener = connector.listener
    val socket = connector.socket

    listener.onMessage(
      socket,
      JSONObject()
        .put("type", "hello")
        .put("protocol_version", 2)
        .put("sync_id", "sync")
        .put("device_id", "dev")
        .put("latest_seq", 5)
        .put("cursor", 3)
        .toString(),
    )
    listener.onMessage(
      socket,
      JSONObject()
        .put("type", "catchup_required")
        .put("after_seq", 3)
        .put("latest_seq", 5)
        .put("reason", "cursor_behind")
        .toString(),
    )
    listener.onMessage(
      socket,
      JSONObject()
        .put("type", "event_batch")
        .put("batch_id", "b1")
        .put("from_seq", 6)
        .put("to_seq", 6)
        .put("events", JSONArray().put(upsertEventJson(6, hashForRealtime("buffered"))))
        .toString(),
    )

    assertTrue("catchup_required must not close the socket", socket.closeCalls.isEmpty())
    assertEquals(0, recoveries)

    restCatchup.complete(JSONObject().put("next_cursor", 5).put("events", JSONArray()).toJsonObject())
    advanceUntilIdle()

    assertTrue(socket.closeCalls.isEmpty())
    assertEquals(0, recoveries)
    assertEquals(6, store.progress.cursor)
    assertTrue(store.progress.items.any { it.contentHash == hashForRealtime("buffered") })
    assertEquals(6, appliedResults.single().cursor)
    assertTrue(states.contains("socket_catchup_required"))
    assertEquals("socket_live", states.last())
    assertEquals("""{"type":"ack","server_seq":6}""", socket.sentTexts.single())
  }

  private class FakeRealtimeConnector : ClipDockRealtimeSocketConnector {
    val socket = FakeWebSocket()
    lateinit var listener: WebSocketListener

    override fun openRealtimeSocket(
      serverUrl: String,
      token: String,
      cursor: Long,
      listener: WebSocketListener,
    ): WebSocket {
      this.listener = listener
      return socket
    }
  }

  private class FakeWebSocket : WebSocket {
    val sentTexts = mutableListOf<String>()
    val closeCalls = mutableListOf<Pair<Int, String?>>()

    override fun request(): Request = Request.Builder().url("ws://server/v2/ws").build()

    override fun queueSize(): Long = 0

    override fun send(text: String): Boolean {
      sentTexts += text
      return true
    }

    override fun send(bytes: ByteString): Boolean = true

    override fun close(code: Int, reason: String?): Boolean {
      closeCalls += code to reason
      return true
    }

    override fun cancel() {}
  }

  private class RealtimeFakeStore(initial: SyncProgress) : SyncStore {
    var progress = initial

    override fun loadProgress(): SyncProgress = progress

    override fun persistProgress(items: List<ClipHistoryItem>, cursor: Long, snapshotSeq: Long): Boolean {
      progress = SyncProgress(items, cursor, snapshotSeq)
      return true
    }
  }

  private class DeferredEventsApi(
    private val eventsResult: CompletableDeferred<JsonObject>,
  ) : ClipDockSyncApi {
    override suspend fun snapshot(serverUrl: String, token: String): JsonObject =
      JSONObject().put("snapshot_seq", 0).put("items", JSONArray()).put("tombstones", JSONArray()).toJsonObject()

    override suspend fun events(serverUrl: String, token: String, afterSeq: Long, limit: Int): JsonObject =
      eventsResult.await()

    override suspend fun pushEvents(serverUrl: String, token: String, events: List<SyncPushEventRequest>): JsonObject =
      JSONObject().put("events", JSONArray()).put("next_cursor", 0).toJsonObject()
  }
}

private fun upsertEventJson(serverSeq: Long, contentHash: String): JSONObject =
  JSONObject()
    .put("server_seq", serverSeq)
    .put("device_id", "dev")
    .put("client_event_id", "event-$serverSeq")
    .put("type", "item_upsert")
    .put("content_hash", contentHash)
    .put("item_type", "text")
    .put("payload", JSONObject().put("text", "buffered"))
    .put("copy_count_delta", 1)
    .put("created_at_ms", serverSeq)

private fun JSONObject.toJsonObject(): JsonObject = Json.parseToJsonElement(toString()) as JsonObject

private fun hashForRealtime(label: String): String =
  "blake3:" + label.encodeToByteArray().joinToString("") { "%02x".format(it.toInt() and 0xff) }.padEnd(64, '0').take(64)
