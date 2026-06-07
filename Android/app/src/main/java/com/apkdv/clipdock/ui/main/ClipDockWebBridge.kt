package com.apkdv.clipdock.ui.main

import com.apkdv.clipdock.MainDestination
import com.apkdv.clipdock.SettingsDetailDestination
import com.apkdv.clipdock.data.ClipDockUiState
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.OverlaySnapEdge
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.floatOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

private const val CLIPDOCK_WEB_SCHEMA_VERSION = 1
private const val MAX_REQUEST_ID_LENGTH = 80
private const val MAX_STABLE_ID_LENGTH = 96

private val forbiddenBridgeKeys =
  setOf(
    "token",
    "deviceToken",
    "serverUrl",
    "url",
    "uri",
    "file",
    "path",
    "payload",
    "payloadBytes",
    "item",
    "items",
    "repository",
  )

internal val clipDockWebJson =
  Json {
    ignoreUnknownKeys = false
    explicitNulls = false
    encodeDefaults = true
  }

@Serializable
internal data class ClipDockWebRequest(
  val version: Int,
  val requestId: String,
  val action: ClipDockWebAction,
  val stableId: String? = null,
  val route: ClipDockWebRoute? = null,
  val sheet: ClipDockWebSheet? = null,
  val setting: ClipDockWebSetting? = null,
  val value: JsonElement? = null,
)

@Serializable
internal enum class ClipDockWebAction {
  @SerialName("selectDestination")
  SelectDestination,

  @SerialName("openItemDetail")
  OpenItemDetail,

  @SerialName("closeDetail")
  CloseDetail,

  @SerialName("showRemoteRetrieval")
  ShowRemoteRetrieval,

  @SerialName("hideRemoteRetrieval")
  HideRemoteRetrieval,

  @SerialName("showDeleteConfirm")
  ShowDeleteConfirm,

  @SerialName("hideDeleteConfirm")
  HideDeleteConfirm,

  @SerialName("copyItem")
  CopyItem,

  @SerialName("downloadAndCopy")
  DownloadAndCopy,

  @SerialName("downloadToCache")
  DownloadToCache,

  @SerialName("copyThumbnail")
  CopyThumbnail,

  @SerialName("removeLocalCache")
  RemoveLocalCache,

  @SerialName("deleteSyncRecord")
  DeleteSyncRecord,

  @SerialName("syncNow")
  SyncNow,

  @SerialName("setP2pEnabled")
  SetP2pEnabled,

  @SerialName("setWifiOnly")
  SetWifiOnly,

  @SerialName("setOverlayEnabled")
  SetOverlayEnabled,

  @SerialName("setOverlaySize")
  SetOverlaySize,

  @SerialName("setOverlayOpacity")
  SetOverlayOpacity,

  @SerialName("setOverlayVerticalFraction")
  SetOverlayVerticalFraction,

  @SerialName("setOverlaySnapEdge")
  SetOverlaySnapEdge,

  @SerialName("openSettingsDetail")
  OpenSettingsDetail,

  @SerialName("closeSettingsDetail")
  CloseSettingsDetail,
}

@Serializable
internal enum class ClipDockWebRoute {
  @SerialName("history")
  History,

  @SerialName("devices")
  Devices,

  @SerialName("files")
  Files,

  @SerialName("settings")
  Settings,

  @SerialName("keep_alive")
  KeepAlive,

  @SerialName("floating_ball")
  FloatingBall,

  @SerialName("item_detail_text")
  ItemDetailText,

  @SerialName("remote_asset_sheet")
  RemoteAssetSheet,

  @SerialName("delete_confirm")
  DeleteConfirm,
}

@Serializable
internal enum class ClipDockWebSheet {
  @SerialName("remote_retrieval")
  RemoteRetrieval,

  @SerialName("delete_confirm")
  DeleteConfirm,
}

@Serializable
internal enum class ClipDockWebSetting {
  @SerialName("p2p_enabled")
  P2pEnabled,

  @SerialName("wifi_only")
  WifiOnly,

  @SerialName("overlay_enabled")
  OverlayEnabled,

  @SerialName("overlay_size")
  OverlaySize,

  @SerialName("overlay_opacity")
  OverlayOpacity,

  @SerialName("overlay_vertical_fraction")
  OverlayVerticalFraction,

  @SerialName("overlay_snap_edge")
  OverlaySnapEdge,
}

@Serializable
internal data class ClipDockWebResult(
  val version: Int = CLIPDOCK_WEB_SCHEMA_VERSION,
  val requestId: String,
  val status: ClipDockWebStatus,
  val errorCode: String? = null,
  val message: String? = null,
  val statePatch: JsonObject? = null,
)

@Serializable
internal enum class ClipDockWebStatus {
  @SerialName("ok")
  Ok,

  @SerialName("error")
  Error,
}

internal interface ClipDockWebActionDispatcher {
  suspend fun selectDestination(destination: MainDestination)

  suspend fun openItemDetail(stableId: String)

  suspend fun closeDetail()

  suspend fun showRemoteRetrieval(stableId: String)

  suspend fun hideRemoteRetrieval()

  suspend fun showDeleteConfirm(stableId: String)

  suspend fun hideDeleteConfirm()

  suspend fun copyItem(item: ClipHistoryItem)

  suspend fun downloadAndCopy(item: ClipHistoryItem)

  suspend fun downloadToCache(item: ClipHistoryItem)

  suspend fun copyThumbnail(item: ClipHistoryItem)

  suspend fun removeLocalCache(item: ClipHistoryItem)

  suspend fun deleteSyncRecord(item: ClipHistoryItem)

  suspend fun syncNow()

  suspend fun setP2pEnabled(enabled: Boolean)

  suspend fun setWifiOnly(enabled: Boolean)

  suspend fun setOverlayEnabled(enabled: Boolean)

  suspend fun setOverlaySize(value: Int)

  suspend fun setOverlayOpacity(value: Int)

  suspend fun setOverlayVerticalFraction(value: Float)

  suspend fun setOverlaySnapEdge(edge: OverlaySnapEdge)

  suspend fun openSettingsDetail(detail: SettingsDetailDestination)

  suspend fun closeSettingsDetail()
}

internal class ClipDockWebBridge(
  private val stateProvider: () -> ClipDockUiState,
  private val actionStateProvider: () -> MobileV4ActionState = { MobileV4ActionState() },
  private val dispatcher: ClipDockWebActionDispatcher,
) {
  private val mutex = Mutex()
  private val recentRequestIds = ArrayDeque<String>()
  private val recentRequestIdSet = mutableSetOf<String>()
  private val inFlight = mutableSetOf<String>()

  suspend fun handle(raw: String?): ClipDockWebResult =
    mutex.withLock {
      val parsed = parseRequest(raw) ?: return@withLock errorResult("<invalid>", "invalid_json", "Malformed bridge request")
      val request = parsed.request
      val basicError = validateBasic(parsed.raw, request)
      if (basicError != null) return@withLock basicError
      if (!rememberRequestId(request.requestId)) {
        return@withLock errorResult(request.requestId, "duplicate_request", "Duplicate requestId")
      }
      val actionKey = "${request.action}:${request.stableId.orEmpty()}"
      if (request.action.requiresInFlightGuard() && !inFlight.add(actionKey)) {
        return@withLock errorResult(request.requestId, "already_in_flight", "Action is already in flight")
      }
      try {
        dispatch(request)
      } finally {
        if (request.action.requiresInFlightGuard()) {
          inFlight.remove(actionKey)
        }
      }
    }

  private data class ParsedRequest(val raw: JsonObject, val request: ClipDockWebRequest)

  private fun parseRequest(raw: String?): ParsedRequest? =
    try {
      val text = raw?.takeIf { it.length <= 4096 } ?: return null
      val element = clipDockWebJson.parseToJsonElement(text)
      val obj = element.jsonObject
      val request = clipDockWebJson.decodeFromJsonElement(ClipDockWebRequest.serializer(), obj)
      ParsedRequest(obj, request)
    } catch (_: IllegalArgumentException) {
      null
    } catch (_: SerializationException) {
      null
    }

  private fun validateBasic(raw: JsonObject, request: ClipDockWebRequest): ClipDockWebResult? {
    if (request.version != CLIPDOCK_WEB_SCHEMA_VERSION) {
      return errorResult(request.requestId, "unsupported_version", "Unsupported bridge version")
    }
    if (request.requestId.isBlank() || request.requestId.length > MAX_REQUEST_ID_LENGTH) {
      return errorResult(request.requestId.ifBlank { "<blank>" }, "invalid_request_id", "Invalid requestId")
    }
    if (request.stableId != null && (request.stableId.isBlank() || request.stableId.length > MAX_STABLE_ID_LENGTH)) {
      return errorResult(request.requestId, "invalid_stable_id", "Invalid stableId")
    }
    val forbidden = raw.keys.firstOrNull { it in forbiddenBridgeKeys }
    if (forbidden != null) {
      return errorResult(request.requestId, "forbidden_payload", "Forbidden bridge field: $forbidden")
    }
    return null
  }

  private fun rememberRequestId(requestId: String): Boolean {
    if (!recentRequestIdSet.add(requestId)) return false
    recentRequestIds.addLast(requestId)
    while (recentRequestIds.size > 96) {
      recentRequestIdSet.remove(recentRequestIds.removeFirst())
    }
    return true
  }

  private suspend fun dispatch(request: ClipDockWebRequest): ClipDockWebResult {
    val state = stateProvider()
    fun item(): ClipHistoryItem? = request.stableId?.let { stableId -> resolveMobileV4Item(state, stableId) }
    when (request.action) {
      ClipDockWebAction.SelectDestination -> dispatcher.selectDestination(request.route?.toDestination() ?: return errorResult(request.requestId, "invalid_route", "Missing destination route"))
      ClipDockWebAction.OpenItemDetail -> {
        val stableId = request.stableId ?: return errorResult(request.requestId, "missing_item", "Missing stableId")
        val target = item() ?: return errorResult(request.requestId, "missing_item", "Item not found")
        dispatcher.openItemDetail(stableId)
        return okResult(
          request,
          nextRoute = target.mobileV4DetailScreenId(),
          selectedStableId = target.stableId,
        )
      }
      ClipDockWebAction.CloseDetail -> {
        dispatcher.closeDetail()
        return okResult(request, nextRoute = "history", selectedStableId = "")
      }
      ClipDockWebAction.ShowRemoteRetrieval -> {
        val target = item() ?: return errorResult(request.requestId, "missing_item", "Item not found")
        val actions = actionsFor(target, state)
        if (actions.primary.kind != MobileV4ActionKind.ShowRemoteRetrieval || !actions.primary.enabled) {
          return errorResult(request.requestId, "disabled_action", actions.primary.message)
        }
        dispatcher.showRemoteRetrieval(target.stableId)
        return okResult(request, nextRoute = "remote_asset_sheet", selectedStableId = target.stableId)
      }
      ClipDockWebAction.HideRemoteRetrieval -> {
        dispatcher.hideRemoteRetrieval()
        return okResult(request, nextRoute = "history", selectedStableId = "")
      }
      ClipDockWebAction.ShowDeleteConfirm -> {
        val target = item() ?: return errorResult(request.requestId, "missing_item", "Item not found")
        if (!actionsFor(target, state).deleteSyncRecord.enabled) {
          return errorResult(request.requestId, "disabled_action", "Delete is disabled")
        }
        dispatcher.showDeleteConfirm(target.stableId)
        return okResult(request, nextRoute = "delete_confirm", selectedStableId = target.stableId)
      }
      ClipDockWebAction.HideDeleteConfirm -> {
        dispatcher.hideDeleteConfirm()
        return okResult(request, nextRoute = "item_detail_text")
      }
      ClipDockWebAction.CopyItem -> dispatchItem(request, ::item, state) { dispatcher.copyItem(it) }
      ClipDockWebAction.DownloadAndCopy -> dispatchItem(request, ::item, state) { dispatcher.downloadAndCopy(it) }
      ClipDockWebAction.DownloadToCache -> dispatchItem(request, ::item, state) { dispatcher.downloadToCache(it) }
      ClipDockWebAction.CopyThumbnail -> dispatchItem(request, ::item, state) { dispatcher.copyThumbnail(it) }
      ClipDockWebAction.RemoveLocalCache -> dispatchItem(request, ::item, state) { dispatcher.removeLocalCache(it) }
      ClipDockWebAction.DeleteSyncRecord -> dispatchItem(request, ::item, state) { dispatcher.deleteSyncRecord(it) }
      ClipDockWebAction.SyncNow -> dispatcher.syncNow()
      ClipDockWebAction.SetP2pEnabled -> dispatcher.setP2pEnabled(request.booleanValue() ?: return errorResult(request.requestId, "invalid_value", "Expected boolean"))
      ClipDockWebAction.SetWifiOnly -> dispatcher.setWifiOnly(request.booleanValue() ?: return errorResult(request.requestId, "invalid_value", "Expected boolean"))
      ClipDockWebAction.SetOverlayEnabled -> dispatcher.setOverlayEnabled(request.booleanValue() ?: return errorResult(request.requestId, "invalid_value", "Expected boolean"))
      ClipDockWebAction.SetOverlaySize -> dispatcher.setOverlaySize(request.intValue() ?: return errorResult(request.requestId, "invalid_value", "Expected integer"))
      ClipDockWebAction.SetOverlayOpacity -> dispatcher.setOverlayOpacity(request.intValue() ?: return errorResult(request.requestId, "invalid_value", "Expected integer"))
      ClipDockWebAction.SetOverlayVerticalFraction -> dispatcher.setOverlayVerticalFraction(request.floatValue() ?: return errorResult(request.requestId, "invalid_value", "Expected number"))
      ClipDockWebAction.SetOverlaySnapEdge -> dispatcher.setOverlaySnapEdge(request.snapEdgeValue() ?: return errorResult(request.requestId, "invalid_value", "Expected snap edge"))
      ClipDockWebAction.OpenSettingsDetail ->
        dispatcher.openSettingsDetail(
          request.route?.toSettingsDetail()
            ?: return errorResult(request.requestId, "invalid_route", "Missing settings detail route")
        )
      ClipDockWebAction.CloseSettingsDetail -> dispatcher.closeSettingsDetail()
    }
    return okResult(request)
  }

  private suspend fun dispatchItem(
    request: ClipDockWebRequest,
    itemProvider: () -> ClipHistoryItem?,
    state: ClipDockUiState,
    block: suspend (ClipHistoryItem) -> Unit,
  ): ClipDockWebResult {
    val target = itemProvider() ?: return errorResult(request.requestId, "missing_item", "Item not found")
    if (!isActionEnabled(request.action, target, state)) {
      return errorResult(request.requestId, "disabled_action", "Action is disabled")
    }
    block(target)
    return okResult(request)
  }

  private fun actionsFor(item: ClipHistoryItem, state: ClipDockUiState): MobileV4DetailActions =
    mobileV4DetailActions(
      item = item,
      p2pEnabled = state.p2pEnabled,
      wifiOnlyBlocked = state.wifiOnly,
      inFlightKinds = actionStateProvider().inFlightKinds(item.stableId),
    )

  private fun isActionEnabled(action: ClipDockWebAction, item: ClipHistoryItem, state: ClipDockUiState): Boolean {
    val actions = actionsFor(item, state)
    return when (action) {
      ClipDockWebAction.CopyItem -> actions.primary.kind == MobileV4ActionKind.Copy && actions.primary.enabled
      ClipDockWebAction.DownloadAndCopy -> actions.downloadAndCopy.enabled
      ClipDockWebAction.DownloadToCache -> actions.downloadToCache.enabled
      ClipDockWebAction.CopyThumbnail -> actions.copyThumbnail.enabled
      ClipDockWebAction.RemoveLocalCache -> actions.removeLocalCache.enabled
      ClipDockWebAction.DeleteSyncRecord -> actions.deleteSyncRecord.enabled
      else -> true
    }
  }
}

private fun ClipDockWebAction.requiresInFlightGuard(): Boolean =
  this in
    setOf(
      ClipDockWebAction.CopyItem,
      ClipDockWebAction.DownloadAndCopy,
      ClipDockWebAction.DownloadToCache,
      ClipDockWebAction.CopyThumbnail,
      ClipDockWebAction.RemoveLocalCache,
    ClipDockWebAction.DeleteSyncRecord,
    ClipDockWebAction.SyncNow,
  )

private fun ClipDockWebRoute.toSettingsDetail(): SettingsDetailDestination? =
  when (this) {
    ClipDockWebRoute.KeepAlive -> SettingsDetailDestination.KeepAlive
    ClipDockWebRoute.FloatingBall -> SettingsDetailDestination.FloatingBall
    else -> null
  }

private fun ClipDockWebRequest.booleanValue(): Boolean? = value?.jsonPrimitive?.booleanOrNull

private fun ClipDockWebRequest.intValue(): Int? = value?.jsonPrimitive?.intOrNull

private fun ClipDockWebRequest.floatValue(): Float? = value?.jsonPrimitive?.floatOrNull

private fun ClipDockWebRequest.snapEdgeValue(): OverlaySnapEdge? =
  when (value?.jsonPrimitive?.contentOrNull?.lowercase()) {
    "left" -> OverlaySnapEdge.Left
    "right" -> OverlaySnapEdge.Right
    else -> null
  }

private fun ClipDockWebRoute.toDestination(): MainDestination? =
  when (this) {
    ClipDockWebRoute.History -> MainDestination.History
    ClipDockWebRoute.Devices -> MainDestination.Devices
    ClipDockWebRoute.Files -> MainDestination.Files
    ClipDockWebRoute.Settings,
    ClipDockWebRoute.KeepAlive,
    ClipDockWebRoute.FloatingBall -> MainDestination.Settings
    ClipDockWebRoute.ItemDetailText,
    ClipDockWebRoute.RemoteAssetSheet,
    ClipDockWebRoute.DeleteConfirm -> null
  }

internal fun mobileV4ScreenId(
  selectedDestination: MainDestination,
  settingsDetail: SettingsDetailDestination?,
  itemDetailStableId: String?,
  initialDetailSheet: MobileV4InitialSheet?,
  state: ClipDockUiState,
): String =
  when {
    initialDetailSheet == MobileV4InitialSheet.RemoteRetrieval -> "remote_asset_sheet"
    initialDetailSheet == MobileV4InitialSheet.DeleteConfirm -> "delete_confirm"
    itemDetailStableId != null -> {
      val item = resolveMobileV4Item(state, itemDetailStableId)
      item?.mobileV4DetailScreenId() ?: "item_detail_text"
    }
    settingsDetail == SettingsDetailDestination.KeepAlive -> "keep_alive"
    settingsDetail == SettingsDetailDestination.FloatingBall -> "floating_ball"
    selectedDestination == MainDestination.Devices -> "devices"
    selectedDestination == MainDestination.Files -> "files"
    selectedDestination == MainDestination.Settings -> "settings"
    else -> "history"
  }

internal fun clipDockWebStateJson(
  state: ClipDockUiState,
  selectedStableId: String? = null,
): JsonObject =
  buildJsonObject {
    put("connectionStatus", state.connectionStatus)
    put("syncId", state.syncId ?: "")
    put("deviceName", state.deviceName)
    put("tokenPresent", state.tokenPresent)
    put("p2pEnabled", state.p2pEnabled)
    put("wifiOnly", state.wifiOnly)
    put("overlayEnabled", state.overlayEnabled)
    put("overlaySize", state.overlaySizeDp)
    put("overlayOpacity", state.overlayIdleOpacityPercent)
    put("overlayVerticalFraction", state.overlayVerticalFraction)
    put("overlaySnapEdge", state.overlaySnapEdge.name.lowercase())
    put("itemCount", state.items.size)
    put("selectedStableId", selectedStableId ?: "")
    selectedStableId
      ?.let { resolveMobileV4Item(state, it) }
      ?.let { item ->
        put("selectedItemType", item.type.wireName)
        put("selectedDetailRoute", item.mobileV4DetailScreenId())
      }
  }

private fun okResult(
  request: ClipDockWebRequest,
  nextRoute: String? = null,
  selectedStableId: String? = null,
): ClipDockWebResult =
  ClipDockWebResult(
    requestId = request.requestId,
    status = ClipDockWebStatus.Ok,
    statePatch =
      buildJsonObject {
        put("acceptedAction", JsonPrimitive(request.action.name))
        if (nextRoute != null) put("nextRoute", nextRoute)
        if (selectedStableId != null) put("selectedStableId", selectedStableId)
      },
  )

private fun ClipHistoryItem.mobileV4DetailScreenId(): String =
  if ((type == ClipItemType.Image || type == ClipItemType.File) && needsRemotePayload) {
    "remote_asset_sheet"
  } else {
    "item_detail_text"
  }

private fun errorResult(requestId: String, code: String, message: String): ClipDockWebResult =
  ClipDockWebResult(
    requestId = requestId,
    status = ClipDockWebStatus.Error,
    errorCode = code,
    message = message,
  )
