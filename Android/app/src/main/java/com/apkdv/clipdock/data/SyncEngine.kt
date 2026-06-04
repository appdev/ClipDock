package com.apkdv.clipdock.data

import android.content.SharedPreferences
import java.util.Locale
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.apache.commons.codec.digest.Blake3
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

internal const val KEY_ITEMS_JSON = "itemsJson"
internal const val KEY_CURSOR = "cursor"
internal const val KEY_SNAPSHOT_SEQ = "snapshotSeq"

class SyncRecoveryRequired(val reason: String) : Exception(reason)

data class SyncProgress(
  val items: List<ClipHistoryItem>,
  val cursor: Long,
  val snapshotSeq: Long,
)

data class SyncResult(
  val items: List<ClipHistoryItem>,
  val cursor: Long,
  val snapshotSeq: Long,
  val usedSnapshot: Boolean,
  val recoveryReason: String? = null,
)

data class LocalSyncPushResult(
  val contentHash: String,
  val clientEventId: String,
  val nextCursor: Long,
  val serverSeq: Long?,
  val duplicate: Boolean,
)

interface SyncStore {
  fun loadProgress(): SyncProgress

  fun persistProgress(items: List<ClipHistoryItem>, cursor: Long, snapshotSeq: Long): Boolean
}

class SharedPreferencesSyncStore(private val preferences: SharedPreferences) : SyncStore {
  override fun loadProgress(): SyncProgress =
    synchronized(persistenceLock) {
      try {
        val items = JSONArray(preferences.getString(KEY_ITEMS_JSON, "[]")).toClipItems()
        SyncProgress(
          items = items.sortedByDescending { it.copiedAtMillis },
          cursor = preferences.getLong(KEY_CURSOR, 0),
          snapshotSeq = preferences.getLong(KEY_SNAPSHOT_SEQ, 0),
        )
      } catch (exception: JSONException) {
        throw SyncRecoveryRequired("items_parse_corruption")
      }
    }

  override fun persistProgress(items: List<ClipHistoryItem>, cursor: Long, snapshotSeq: Long): Boolean =
    synchronized(persistenceLock) {
      val currentCursor = preferences.getLong(KEY_CURSOR, 0)
      if (cursor < currentCursor) {
        return@synchronized false
      }
      preferences
        .edit()
        .putString(KEY_ITEMS_JSON, items.toJsonArray().toString())
        .putLong(KEY_CURSOR, cursor)
        .putLong(KEY_SNAPSHOT_SEQ, snapshotSeq)
        .commit()
    }

  private companion object {
    val persistenceLock = Any()
  }
}

class SyncEngine(
  private val store: SyncStore,
  private val api: ClipDockSyncApi,
) {
  private val writerMutex = Mutex()
  private val deltaFailuresByCursor = mutableMapOf<Long, Int>()

  suspend fun syncFromStoredCursor(serverUrl: String, token: String): SyncResult =
    writerMutex.withLock {
      val progress =
        try {
          store.loadProgress()
        } catch (recovery: SyncRecoveryRequired) {
          return@withLock snapshotCorrection(serverUrl, token, emptyList(), recovery.reason)
        }
      if (progress.cursor <= 0) {
        return@withLock snapshotCorrection(serverUrl, token, progress.items, "empty_cursor")
      }
      runCatching { applyDeltaLocked(serverUrl, token, progress) }
        .getOrElse { throwable ->
          val apiError = throwable as? ClipDockApiException
          val recovery = throwable as? SyncRecoveryRequired
          if (recovery?.reason == "persistence_failure") {
            throw throwable
          }
          if (recovery != null) {
            return@withLock snapshotCorrection(serverUrl, token, progress.items, recovery.reason)
          }
          val failureCount = deltaFailuresByCursor.merge(progress.cursor, 1, Int::plus) ?: 1
          if (apiError?.code == "invalid_cursor" || failureCount >= 3) {
            snapshotCorrection(serverUrl, token, progress.items, apiError?.code ?: "repeated_delta_failure")
          } else {
            throw throwable
          }
        }
    }

  suspend fun applyRealtimeEvents(
    events: List<JSONObject>,
    serverUrl: String? = null,
    token: String? = null,
  ): SyncResult =
    writerMutex.withLock {
      val progress = store.loadProgress()
      try {
        validateEventOrder(events)
      } catch (recovery: SyncRecoveryRequired) {
        if (recovery.reason == "ordering_regression" && serverUrl != null && token != null) {
          return@withLock snapshotCorrection(serverUrl, token, progress.items, recovery.reason)
        }
        throw recovery
      }
      val applicable = events.filter { it.optLong("server_seq", -1) > progress.cursor }
      if (applicable.isEmpty()) {
        return@withLock SyncResult(progress.items, progress.cursor, progress.snapshotSeq, usedSnapshot = false)
      }
      val nextCursor = applicable.maxOf { it.optLong("server_seq") }
      val merged = applyEvents(progress.items, applicable)
      requirePersist(store.persistProgress(merged, nextCursor, progress.snapshotSeq))
      SyncResult(merged, nextCursor, progress.snapshotSeq, usedSnapshot = false)
    }

  suspend fun pushLocalItem(
    serverUrl: String,
    token: String,
    deviceId: String,
    item: ClipHistoryItem,
  ): LocalSyncPushResult =
    writerMutex.withLock {
      val event = item.toSyncPushEventRequest(deviceId)
      val data = api.pushEvents(serverUrl, token, listOf(event)).toJSONObject()
      val pushedEvent =
        data
          .optJSONArray("events")
          ?.let { events -> (0 until events.length()).mapNotNull { events.optJSONObject(it) } }
          ?.firstOrNull { it.optString("client_event_id") == event.clientEventId }

      LocalSyncPushResult(
        contentHash = event.contentHash,
        clientEventId = event.clientEventId,
        nextCursor = data.optLong("next_cursor"),
        serverSeq = pushedEvent?.optLong("server_seq"),
        duplicate = pushedEvent?.optBoolean("duplicate") ?: false,
      )
    }

  private suspend fun applyDeltaLocked(serverUrl: String, token: String, progress: SyncProgress): SyncResult {
    val data = api.events(serverUrl, token, progress.cursor).toJSONObject()
    val nextCursor = data.optLong("next_cursor", progress.cursor)
    if (nextCursor < progress.cursor) {
      return snapshotCorrection(serverUrl, token, progress.items, "cursor_regression")
    }
    val events = data.optJSONArray("events").eventObjects()
    validateEventOrder(events)
    val merged = applyEvents(progress.items, events.filter { it.optLong("server_seq", -1) > progress.cursor })
    requirePersist(store.persistProgress(merged, nextCursor, progress.snapshotSeq))
    deltaFailuresByCursor.remove(progress.cursor)
    return SyncResult(merged, nextCursor, progress.snapshotSeq, usedSnapshot = false)
  }

  private suspend fun snapshotCorrection(
    serverUrl: String,
    token: String,
    previousItems: List<ClipHistoryItem>,
    reason: String,
  ): SyncResult {
    val snapshot = api.snapshot(serverUrl, token).toJSONObject()
    val snapshotSeq = snapshot.optLong("snapshot_seq")
    val snapshotItems = snapshot.optJSONArray("items").toSnapshotItems()
    val tombstones = snapshot.optJSONArray("tombstones").contentHashes()
    val previousItemsByHash = previousItems.associateBy { it.contentHash }
    val merged =
      snapshotItems
        .filterNot { tombstones.contains(it.contentHash) }
        .distinctBy { it.contentHash }
        .map { item -> item.preservingDownloadedPayload(previousItemsByHash[item.contentHash]) }
        .sortedByDescending { it.copiedAtMillis }
    requirePersist(store.persistProgress(merged, snapshotSeq, snapshotSeq))
    deltaFailuresByCursor.clear()
    return SyncResult(merged, snapshotSeq, snapshotSeq, usedSnapshot = true, recoveryReason = reason)
  }

  private fun applyEvents(previousItems: List<ClipHistoryItem>, events: List<JSONObject>): List<ClipHistoryItem> {
    val itemsByHash = previousItems.associateBy { it.contentHash }.toMutableMap()
    for (event in events) {
      val serverSeq = event.optLong("server_seq", -1)
      if (serverSeq < 0) throw SyncRecoveryRequired("missing_server_seq")
      when (event.optString("type")) {
        "item_delete" -> itemsByHash.remove(event.optString("content_hash"))
        "item_upsert" -> {
          val payload = event.optJSONObject("payload") ?: throw SyncRecoveryRequired("missing_payload")
          if (payload.length() == 0) throw SyncRecoveryRequired("missing_payload")
          val incoming = ClipHistoryItem.fromServerEvent(event) ?: throw SyncRecoveryRequired("malformed_payload")
          val previous = itemsByHash[incoming.contentHash]
          val merged =
            incoming
              .copy(copyCount = (previous?.copyCount ?: 0) + incoming.copyCount)
              .preservingDownloadedPayload(previous)
          itemsByHash[incoming.contentHash] = merged
        }
        else -> throw SyncRecoveryRequired("unknown_event_type")
      }
    }
    return itemsByHash.values.sortedByDescending { it.copiedAtMillis }
  }

  private fun validateEventOrder(events: List<JSONObject>) {
    var previousSeq = -1L
    for (event in events) {
      val serverSeq = event.optLong("server_seq", -1)
      if (serverSeq < 0) throw SyncRecoveryRequired("missing_server_seq")
      if (serverSeq < previousSeq) throw SyncRecoveryRequired("ordering_regression")
      previousSeq = serverSeq
    }
  }

  private fun requirePersist(success: Boolean) {
    if (!success) throw SyncRecoveryRequired("persistence_failure")
  }
}

internal fun JsonObject.toJSONObject(): JSONObject = JSONObject(toString())

internal fun JSONArray?.toSnapshotItems(): List<ClipHistoryItem> =
  if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it)?.let(ClipHistoryItem::fromServerSnapshot) }

internal fun JSONArray?.contentHashes(): Set<String> {
  if (this == null) return emptySet()
  return (0 until length()).mapNotNull { optJSONObject(it)?.optString("content_hash")?.takeIf(String::isNotBlank) }.toSet()
}

private fun JSONArray?.eventObjects(): List<JSONObject> {
  if (this == null) return emptyList()
  return (0 until length()).mapNotNull { optJSONObject(it) }
}

internal fun ClipHistoryItem.toSyncPushEventRequest(deviceId: String): SyncPushEventRequest {
  val itemType =
    when (type) {
      ClipItemType.Text,
      ClipItemType.Link,
      ClipItemType.Color,
      ClipItemType.RichText -> type
      ClipItemType.Image,
      ClipItemType.File,
      ClipItemType.Unknown -> throw ClipDockApiException("unsupported_upload_type", "Only text-like local items can be uploaded")
    }
  val payload = syncPushPayload(itemType)
  val normalizedContentHash =
    contentHash
      .takeIf(::isCanonicalBlake3ContentHash)
      ?: blake3ContentHash("${itemType.wireName}\n$payload")
  val eventId = stableAndroidClientEventId(deviceId, normalizedContentHash, copiedAtMillis)
  return SyncPushEventRequest(
    clientEventId = eventId,
    type = "item_upsert",
    contentHash = normalizedContentHash,
    itemType = itemType.wireName,
    payload = payload,
    copyCountDelta = copyCount.coerceIn(1, 100),
  )
}

private fun ClipHistoryItem.syncPushPayload(itemType: ClipItemType): JsonObject {
  val primaryText = body.ifBlank { title }.trim()
  val summary = title.ifBlank { body }.trim()
  return buildJsonObject {
    put("source_platform", JsonPrimitive("android"))
    put("source_app_name", JsonPrimitive(sourceName?.takeIf(String::isNotBlank) ?: "Android"))
    if (summary.isNotBlank()) put("summary", JsonPrimitive(summary))
    when (itemType) {
      ClipItemType.Text -> {
        put("text", JsonPrimitive(primaryText))
      }
      ClipItemType.RichText -> {
        put("plain_text", JsonPrimitive(primaryText))
        put("text", JsonPrimitive(primaryText))
      }
      ClipItemType.Link -> {
        val url = body.ifBlank { title }.trim()
        put("url", JsonPrimitive(url))
        put("display_url", JsonPrimitive(url))
        if (title.isNotBlank()) put("title", JsonPrimitive(title))
        if (primaryText.isNotBlank()) put("text", JsonPrimitive(primaryText))
      }
      ClipItemType.Color -> {
        val color = title.ifBlank { body }.trim()
        put("color", JsonPrimitive(color))
        put("hex", JsonPrimitive(color))
      }
      ClipItemType.Image,
      ClipItemType.File,
      ClipItemType.Unknown -> Unit
    }
  }
}

private fun stableAndroidClientEventId(deviceId: String, contentHash: String, copiedAtMillis: Long): String {
  val digest = blake3Hex("$deviceId|$contentHash|$copiedAtMillis")
  return "android-upsert-${digest.take(32)}"
}

internal fun blake3ContentHash(value: String): String = "blake3:${blake3Hex(value)}"

private fun blake3Hex(value: String): String =
  Blake3
    .hash(value.toByteArray(Charsets.UTF_8))
    .joinToString("") { byte -> "%02x".format(Locale.US, byte.toInt() and 0xff) }

private fun isCanonicalBlake3ContentHash(value: String): Boolean {
  val hex = value.removePrefix("blake3:")
  return value.startsWith("blake3:") &&
    hex.length == 64 &&
    hex.all { character -> character in '0'..'9' || character in 'a'..'f' }
}
