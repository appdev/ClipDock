package com.apkdv.clipdock.data

import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

internal class SyncRealtimeClient(
  private val socketConnector: ClipDockRealtimeSocketConnector,
  private val engine: SyncEngine,
  private val scope: CoroutineScope,
  private val onState: (String) -> Unit,
  private val onRecoveryRequired: () -> Unit,
  private val onSyncResult: (SyncResult) -> Unit = {},
  private val logger: SyncEventLogger = NoOpSyncEventLogger,
) {
  private val socketRef = AtomicReference<WebSocket?>()

  fun connect(serverUrl: String, token: String, cursor: Long) {
    logger.log("ws_connect_start server=${serverUrl.toSyncLogServerLabel()} cursor=$cursor")
    close()
    val listener = Listener(serverUrl, token, cursor)
    socketRef.set(socketConnector.openRealtimeSocket(serverUrl, token, cursor, listener))
  }

  fun close() {
    logger.log("ws_close_requested code=$CLIENT_RECONNECT_CLOSE_CODE reason=$CLIENT_RECONNECT_REASON")
    socketRef.getAndSet(null)?.close(CLIENT_RECONNECT_CLOSE_CODE, CLIENT_RECONNECT_REASON)
  }

  private inner class Listener(
    private val serverUrl: String,
    private val token: String,
    private val startCursor: Long,
  ) : WebSocketListener() {
    private val bufferedBatches = mutableListOf<List<JSONObject>>()
    private var live = false
    private var catchUpStarted = false
    private var overflowed = false
    private var catchupReason: String? = null
    private var catchupLatestSeq: Long = 0

    override fun onOpen(webSocket: WebSocket, response: Response) {
      logger.log("ws_open http_code=${response.code} cursor=$startCursor")
      onState("socket_connecting")
    }

    override fun onMessage(webSocket: WebSocket, text: String) {
      val message =
        runCatching { JSONObject(text) }
          .getOrElse {
            logger.log("ws_message_malformed error=${it.toSyncLogErrorLabel()}")
            webSocket.close(1002, "malformed_json")
            onRecoveryRequired()
            return
          }
      when (message.optString("type")) {
        "hello" -> {
          logger.log(
            "ws_hello protocol=${message.optInt("protocol_version", -1)} " +
              "server_cursor=${message.optLong("cursor", -1)} latest_seq=${message.optLong("latest_seq", -1)} " +
              "client_cursor=$startCursor",
          )
          startCatchUp(webSocket)
        }
        "catchup_required" -> {
          catchupReason = message.optString("reason").takeIf { it.isNotBlank() }
          catchupLatestSeq = message.optLong("latest_seq", 0)
          logger.log(
            "ws_catchup_required reason=${catchupReason ?: "unknown"} " +
              "latest_seq=$catchupLatestSeq after_seq=${message.optLong("after_seq", -1)}",
          )
          onState("socket_catchup_required")
        }
        "event_batch" -> handleEventBatch(webSocket, message)
        "error" -> {
          logger.log("ws_error code=${message.optString("code").ifBlank { "unknown" }}")
          if (message.optString("code") == "slow_consumer") {
            onRecoveryRequired()
          }
        }
        else -> logger.log("ws_message_ignored type=${message.optString("type").ifBlank { "unknown" }}")
      }
    }

    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
      logger.log("ws_failure http_code=${response?.code ?: -1} error=${t.toSyncLogErrorLabel()}")
      onState("socket_disconnected")
      onRecoveryRequired()
    }

    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
      logger.log("ws_closed code=$code reason=${reason.ifBlank { "empty" }}")
      onState("socket_closed")
      if (code != CLIENT_RECONNECT_CLOSE_CODE || reason != CLIENT_RECONNECT_REASON) {
        onRecoveryRequired()
      }
    }

    private fun startCatchUp(webSocket: WebSocket) {
      if (catchUpStarted) return
      catchUpStarted = true
      live = false
      logger.log("ws_catchup_start cursor=$startCursor")
      onState("socket_catching_up")
      scope.launch {
        try {
          var result = engine.syncFromStoredCursor(serverUrl, token)
          val replay = bufferedBatches.flatten()
          bufferedBatches.clear()
          logger.log(
            "ws_catchup_rest_done cursor=${result.cursor} snapshot=${result.usedSnapshot} " +
              "reason=${result.recoveryReason ?: "none"} replay_events=${replay.size} overflowed=$overflowed",
          )
          if (!overflowed && replay.isNotEmpty()) {
            result = engine.applyRealtimeEvents(replay, serverUrl, token)
            ack(webSocket, result.cursor)
          }
          if (overflowed) {
            logger.log("ws_catchup_failed reason=buffer_overflow")
            webSocket.close(1008, "buffer_overflow")
            onRecoveryRequired()
          } else {
            live = true
            onSyncResult(result)
            logger.log("ws_live cursor=${result.cursor}")
            onState("socket_live")
          }
        } catch (throwable: Throwable) {
          logger.log("ws_catchup_failed error=${throwable.toSyncLogErrorLabel()}")
          webSocket.close(1011, "catchup_failed")
          onRecoveryRequired()
        }
      }
    }

    private fun handleEventBatch(webSocket: WebSocket, message: JSONObject) {
      val events = message.optJSONArray("events").eventObjects()
      val fromSeq = message.optLong("from_seq", -1)
      val toSeq = message.optLong("to_seq", -1)
      if (!live) {
        if (bufferedBatches.size >= BUFFER_CAPACITY) {
          overflowed = true
          bufferedBatches.clear()
          logger.log("ws_event_batch_overflow capacity=$BUFFER_CAPACITY count=${events.size} from_seq=$fromSeq to_seq=$toSeq")
          webSocket.close(1008, "buffer_overflow")
          onRecoveryRequired()
          return
        }
        bufferedBatches += events
        logger.log(
          "ws_event_batch_buffered count=${events.size} from_seq=$fromSeq to_seq=$toSeq " +
            "buffered_batches=${bufferedBatches.size}",
        )
        return
      }
      logger.log("ws_event_batch_apply_start count=${events.size} from_seq=$fromSeq to_seq=$toSeq")
      scope.launch {
        try {
          val result = engine.applyRealtimeEvents(events, serverUrl, token)
          logger.log("ws_event_batch_apply_done cursor=${result.cursor} count=${events.size}")
          onSyncResult(result)
          ack(webSocket, result.cursor)
        } catch (throwable: Throwable) {
          logger.log("ws_event_batch_apply_failed error=${throwable.toSyncLogErrorLabel()} count=${events.size}")
          webSocket.close(1011, "apply_failed")
          onRecoveryRequired()
        }
      }
    }

    private fun ack(webSocket: WebSocket, serverSeq: Long) {
      if (serverSeq > 0) {
        val sent = webSocket.send(JSONObject().put("type", "ack").put("server_seq", serverSeq).toString())
        logger.log("ws_ack server_seq=$serverSeq sent=$sent")
      }
    }
  }

  private companion object {
    const val BUFFER_CAPACITY = 64
    const val CLIENT_RECONNECT_CLOSE_CODE = 1000
    const val CLIENT_RECONNECT_REASON = "reconnect"
  }
}

private fun org.json.JSONArray?.eventObjects(): List<JSONObject> {
  if (this == null) return emptyList()
  return (0 until length()).mapNotNull { optJSONObject(it) }
}
