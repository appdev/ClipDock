package com.apkdv.clipdock.data

import org.json.JSONArray
import org.json.JSONObject

enum class ClipItemType(val wireName: String, val label: String) {
  Text("text", "文字"),
  Link("link", "链接"),
  Image("image", "图片"),
  File("file", "文件"),
  Color("color", "颜色"),
  RichText("rich_text", "富文本"),
  Unknown("unknown", "未知")
}

enum class PayloadState {
  Ready,
  RemoteOnly,
  Failed
}

enum class TransferState {
  Idle,
  DiscoveringPeer,
  Downloading,
  Ready,
  Failed
}

enum class HistoryFilter(val label: String) {
  All("全部"),
  Text("文字"),
  Link("链接"),
  Image("图片"),
  File("文件"),
  Color("颜色")
}

enum class OverlayClickAction {
  QuickSyncCopy
}

enum class OverlaySnapEdge {
  Left,
  Right
}

data class P2pEndpointInfo(
  val endpointId: String,
  val relayUrl: String?,
  val directAddresses: List<String>,
  val capabilities: String,
  val updatedAtMillis: Long,
  val expiresAtMillis: Long,
)

data class P2pDeviceInfo(
  val deviceId: String,
  val deviceName: String,
  val endpoint: P2pEndpointInfo,
) {
  companion object {
    fun fromJson(json: JSONObject): P2pDeviceInfo? {
      val endpointJson = json.optJSONObject("endpoint") ?: return null
      val endpointId = endpointJson.optString("endpoint_id").takeIf(String::isNotBlank) ?: return null
      val deviceId = json.optString("device_id").takeIf(String::isNotBlank) ?: return null
      return P2pDeviceInfo(
        deviceId = deviceId,
        deviceName = json.optString("device_name").ifBlank { "未命名设备" },
        endpoint =
          P2pEndpointInfo(
            endpointId = endpointId,
            relayUrl = endpointJson.optNullableString("relay_url"),
            directAddresses = endpointJson.optJSONArray("direct_addresses").stringList(),
            capabilities = endpointJson.optJSONObject("capabilities")?.toString() ?: "{}",
            updatedAtMillis = endpointJson.optLong("updated_at_ms"),
            expiresAtMillis = endpointJson.optLong("expires_at_ms"),
          ),
      )
    }
  }
}

fun JSONArray?.toP2pDevices(): List<P2pDeviceInfo> {
  if (this == null) return emptyList()
  return (0 until length()).mapNotNull { index -> optJSONObject(index)?.let(P2pDeviceInfo::fromJson) }
}

internal fun sanitizeOverlaySizeDp(value: Int): Int = value.coerceIn(52, 72)

internal fun sanitizeOverlayIdleOpacityPercent(value: Int): Int = value.coerceIn(45, 100)

internal fun sanitizeOverlayVerticalFraction(value: Float): Float = value.coerceIn(0f, 1f)

data class ClipHistoryItem(
  val stableId: String,
  val contentHash: String,
  val type: ClipItemType,
  val title: String,
  val body: String,
  val detail: String,
  val sourceName: String?,
  val assetId: String?,
  val thumbnailUri: String?,
  val thumbnailDigest: String?,
  val thumbnailMimeType: String?,
  val thumbnailByteCount: Long?,
  val thumbnailWidth: Int?,
  val thumbnailHeight: Int?,
  val localUri: String?,
  val payloadState: PayloadState,
  val transferState: TransferState,
  val copiedAtMillis: Long,
  val copyCount: Long,
) {
  val compactText: String
    get() =
      when (type) {
        ClipItemType.Image -> "[图片]"
        ClipItemType.File -> title
        else -> title.ifBlank { body }
      }

  val needsRemotePayload: Boolean
    get() = (type == ClipItemType.Image || type == ClipItemType.File) && localUri.isNullOrBlank()

  fun toJson(): JSONObject =
    JSONObject()
      .put("stableId", stableId)
      .put("contentHash", contentHash)
      .put("type", type.wireName)
      .put("title", title)
      .put("body", body)
      .put("detail", detail)
      .put("sourceName", sourceName)
      .put("assetId", assetId)
      .put("thumbnailUri", thumbnailUri)
      .put("thumbnailDigest", thumbnailDigest)
      .put("thumbnailMimeType", thumbnailMimeType)
      .put("thumbnailByteCount", thumbnailByteCount)
      .put("thumbnailWidth", thumbnailWidth)
      .put("thumbnailHeight", thumbnailHeight)
      .put("localUri", localUri)
      .put("payloadState", payloadState.name)
      .put("transferState", transferState.name)
      .put("copiedAtMillis", copiedAtMillis)
      .put("copyCount", copyCount)

  companion object {
    fun fromJson(json: JSONObject): ClipHistoryItem {
      val payloadState = enumValueOrDefault(json.optString("payloadState"), PayloadState.Ready)
      val transferState =
        restoredTransferState(
          enumValueOrDefault(json.optString("transferState"), TransferState.Idle),
          payloadState,
        )
      return ClipHistoryItem(
        stableId = json.optString("stableId"),
        contentHash = json.optString("contentHash"),
        type = clipType(json.optString("type")),
        title = json.optString("title"),
        body = json.optString("body"),
        detail = json.optString("detail"),
        sourceName = json.optNullableString("sourceName"),
        assetId = json.optNullableString("assetId"),
        thumbnailUri = json.optNullableString("thumbnailUri"),
        thumbnailDigest = json.optNullableString("thumbnailDigest"),
        thumbnailMimeType = json.optNullableString("thumbnailMimeType"),
        thumbnailByteCount = json.optNullableLong("thumbnailByteCount"),
        thumbnailWidth = json.optNullableInt("thumbnailWidth"),
        thumbnailHeight = json.optNullableInt("thumbnailHeight"),
        localUri = json.optNullableString("localUri"),
        payloadState = payloadState,
        transferState = transferState,
        copiedAtMillis = json.optLong("copiedAtMillis"),
        copyCount = json.optLong("copyCount"),
      )
    }

    private fun restoredTransferState(transferState: TransferState, payloadState: PayloadState): TransferState =
      when (transferState) {
        TransferState.DiscoveringPeer,
        TransferState.Downloading -> if (payloadState == PayloadState.Ready) TransferState.Ready else TransferState.Failed
        else -> transferState
      }

    fun fromServerSnapshot(json: JSONObject): ClipHistoryItem {
      val contentHash = json.optString("content_hash")
      val itemType = clipType(json.optString("item_type"))
      val payload = json.optJSONObject("payload") ?: JSONObject()
      return fromServerPayload(
        contentHash = contentHash,
        itemType = itemType,
        payload = payload,
        copyCount = json.optLong("copy_count"),
        updatedAtMillis = json.optLong("updated_at_ms"),
      )
    }

    fun fromServerEvent(json: JSONObject): ClipHistoryItem? {
      if (json.optString("type") != "item_upsert") return null
      val contentHash = json.optString("content_hash")
      val itemType = clipType(json.optString("item_type"))
      val payload = json.optJSONObject("payload") ?: return null
      return fromServerPayload(
        contentHash = contentHash,
        itemType = itemType,
        payload = payload,
        copyCount = json.optLong("copy_count_delta"),
        updatedAtMillis = json.optLong("created_at_ms"),
      )
    }

    private fun fromServerPayload(
      contentHash: String,
      itemType: ClipItemType,
      payload: JSONObject,
      copyCount: Long,
      updatedAtMillis: Long,
    ): ClipHistoryItem {
      val sourceName = payload.optNullableString("source_app_name") ?: payload.optNullableString("source")
      val assetId =
        payload.optNullableString("asset_id")
          ?: payload.optNullableString("payload_asset_id")
          ?: payload.optNullableString("p2p_asset_id")
          ?: payload.optNullableString("digest")
      val localUri = payload.optNullableString("local_uri") ?: payload.optNullableString("local_path")
      val thumbnailUri =
        payload.optNullableString("thumbnail_uri")
          ?: payload.optNullableString("preview_uri")
          ?: payload.optNullableString("preview_local_uri")
          ?: payload.optNullableString("thumbnail_path")
          ?: payload.optNullableString("preview_path")
      val title =
        when (itemType) {
          ClipItemType.Text -> payload.firstText("title", "text", "primary_text", "summary").linePreview()
          ClipItemType.RichText -> payload.firstText("title", "plain_text", "text", "summary").linePreview()
          ClipItemType.Link -> payload.firstText("title", "host", "url", "display_url").linePreview()
          ClipItemType.Color -> payload.firstText("hex", "color", "summary").ifBlank { "#000000" }
          ClipItemType.Image -> payload.firstText("file_name", "filename", "name", "title", "summary").linePreview().ifBlank { "图片内容" }
          ClipItemType.File -> payload.fileName().linePreview().ifBlank { "文件" }
          ClipItemType.Unknown -> payload.firstText("title", "summary", "text").linePreview().ifBlank { "未知类型" }
        }
      val body =
        when (itemType) {
          ClipItemType.Link -> payload.firstText("display_url", "url", "canonical_url")
          ClipItemType.File -> payload.firstText("mime_type", "content_type", "summary")
          ClipItemType.Image -> payload.firstText("summary", "mime_type", "content_type")
          ClipItemType.Color -> payload.firstText("name", "source_app_name")
          else -> payload.firstText("summary", "text", "plain_text", "primary_text").linePreview(max = 120)
        }
      val detail =
        payload.firstText("detail", "byte_count", "size", "host").ifBlank {
          when {
            sourceName != null -> sourceName
            copyCount > 0 -> "复制 $copyCount 次"
            else -> itemType.label
          }
        }
      val payloadState =
        if ((itemType == ClipItemType.Image || itemType == ClipItemType.File) && localUri.isNullOrBlank()) {
          PayloadState.RemoteOnly
        } else {
          PayloadState.Ready
        }
      return ClipHistoryItem(
        stableId = contentHash.ifBlank { "item-$updatedAtMillis" },
        contentHash = contentHash,
        type = itemType,
        title = title,
        body = body,
        detail = detail,
        sourceName = sourceName,
        assetId = assetId,
        thumbnailUri = thumbnailUri,
        thumbnailDigest = payload.optNullableString("thumbnail_digest"),
        thumbnailMimeType = payload.optNullableString("thumbnail_mime_type"),
        thumbnailByteCount = payload.optNullableLong("thumbnail_byte_count"),
        thumbnailWidth = payload.optNullableInt("thumbnail_width"),
        thumbnailHeight = payload.optNullableInt("thumbnail_height"),
        localUri = localUri,
        payloadState = payloadState,
        transferState = TransferState.Idle,
        copiedAtMillis = updatedAtMillis,
        copyCount = copyCount,
      )
    }
  }
}

data class ServerCapabilities(
  val protocolVersion: Int = 1,
  val eventTypes: List<String> = emptyList(),
  val assetKinds: List<String> = emptyList(),
  val assetMimeTypes: List<String> = emptyList(),
  val maxAssetBytes: Long = 0,
  val p2p: String = "未获取",
)

data class SyncDiagnostics(
  val snapshotSeq: Long = 0,
  val nextCursor: Long = 0,
  val lastSyncAtMillis: Long = 0,
  val lastError: String? = null,
)

data class ClipDockUiState(
  val serverUrl: String = "http://10.0.2.2:9001",
  val deviceName: String = android.os.Build.MODEL.ifBlank { "Android" },
  val syncId: String? = null,
  val deviceId: String? = null,
  val tokenPresent: Boolean = false,
  val connectionStatus: String = "未设置",
  val pairingCode: String? = null,
  val pairingExpiresAtMillis: Long? = null,
  val capabilities: ServerCapabilities = ServerCapabilities(),
  val diagnostics: SyncDiagnostics = SyncDiagnostics(),
  val selectedFilter: HistoryFilter = HistoryFilter.All,
  val items: List<ClipHistoryItem> = emptyList(),
  val isSyncing: Boolean = false,
  val isSyncSetupInFlight: Boolean = false,
  val p2pEnabled: Boolean = true,
  val wifiOnly: Boolean = true,
  val overlayEnabled: Boolean = true,
  val overlayClickAction: OverlayClickAction = OverlayClickAction.QuickSyncCopy,
  val overlaySnapEdge: OverlaySnapEdge = OverlaySnapEdge.Right,
  val overlaySizeDp: Int = 64,
  val overlayIdleOpacityPercent: Int = 78,
  val overlayVerticalFraction: Float = 0.35f,
  val encryptionEnabled: Boolean = false,
  val p2pDevices: List<P2pDeviceInfo> = emptyList(),
  val p2pDevicesLastRefreshMillis: Long = 0,
)

sealed interface QuickCopyResult {
  data class Copied(val item: ClipHistoryItem) : QuickCopyResult
  data class Timeout(val latest: ClipHistoryItem?, val message: String) : QuickCopyResult
  data class Failed(val latest: ClipHistoryItem?, val message: String) : QuickCopyResult
}

fun List<ClipHistoryItem>.toJsonArray(): JSONArray {
  val array = JSONArray()
  forEach { array.put(it.toJson()) }
  return array
}

fun JSONArray.toClipItems(): List<ClipHistoryItem> =
  (0 until length()).mapNotNull { index -> optJSONObject(index)?.let(ClipHistoryItem::fromJson) }

fun clipType(value: String?): ClipItemType =
  ClipItemType.entries.firstOrNull { it.wireName == value } ?: ClipItemType.Unknown

private fun JSONArray?.stringList(): List<String> {
  if (this == null) return emptyList()
  return (0 until length()).mapNotNull { index -> optString(index).takeIf(String::isNotBlank) }
}

private fun JSONObject.optNullableString(name: String): String? =
  if (has(name) && !isNull(name)) optString(name).takeIf { it.isNotBlank() } else null

private fun JSONObject.optNullableLong(name: String): Long? =
  if (has(name) && !isNull(name)) optLong(name).takeIf { it > 0 } else null

private fun JSONObject.optNullableInt(name: String): Int? =
  if (has(name) && !isNull(name)) optInt(name).takeIf { it > 0 } else null

private fun JSONObject.firstText(vararg names: String): String =
  names.firstNotNullOfOrNull { name ->
    val value = opt(name)
    when {
      !has(name) || isNull(name) -> null
      value is Number -> value.toString()
      else -> optString(name).takeIf { it.isNotBlank() }
    }
  } ?: ""

private fun JSONObject.fileName(): String {
  firstText("file_name", "filename", "name", "path").takeIf { it.isNotBlank() }?.let { return it.substringAfterLast('/') }
  val fileItems = optJSONArray("file_items") ?: optJSONArray("files")
  val first = fileItems?.optJSONObject(0) ?: return ""
  return first.firstText("file_name", "filename", "name", "path").substringAfterLast('/')
}

private fun String.linePreview(max: Int = 80): String {
  val oneLine = replace(Regex("\\s+"), " ").trim()
  return if (oneLine.length <= max) oneLine else oneLine.take(max - 1) + "..."
}

private inline fun <reified T : Enum<T>> enumValueOrDefault(value: String, default: T): T =
  enumValues<T>().firstOrNull { it.name == value } ?: default
