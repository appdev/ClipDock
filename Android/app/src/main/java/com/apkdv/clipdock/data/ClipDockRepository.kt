package com.apkdv.clipdock.data

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.PersistableBundle
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.apkdv.clipdock.p2p.NativeP2pTransport
import com.apkdv.clipdock.p2p.P2pImportResult
import com.apkdv.clipdock.p2p.P2pProviderCandidate
import com.apkdv.clipdock.p2p.P2pProviderSelector
import java.io.File
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.JsonObject
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

class ClipDockRepository(private val context: Context) {
  private val appContext = context.applicationContext
  private val preferences = appContext.getSharedPreferences("clipdock", Context.MODE_PRIVATE)
  private val api = ClipDockApiClient()
  private val p2pTransport = NativeP2pTransport(appContext)
  private val localImagePreparer = AndroidLocalImagePreparer(appContext, p2pTransport)
  private val syncStore = SharedPreferencesSyncStore(preferences)
  private val syncEngine = SyncEngine(
    syncStore,
    api,
    AndroidSyncThumbnailCache(api, appContext.filesDir),
  )
  private val syncScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
  private val clipboardCaptureMonitor =
    AndroidClipboardCaptureMonitor(
      context = appContext,
      scope = syncScope,
      upload = { clip, copiedAtMillis -> uploadLocalClipboardClip(clip, copiedAtMillis) },
    )
  private var fallbackPollJob: Job? = null
  private var realtimeReconnectJob: Job? = null
  private val realtimeReconnectLock = Any()
  private val realtimeReconnectBackoff = RealtimeReconnectBackoff()
  private val realtimeClient =
    SyncRealtimeClient(
      socketConnector = api,
      engine = syncEngine,
      scope = syncScope,
      onState = { status ->
        if (status == "socket_live") {
          resetRealtimeReconnectBackoff()
        }
        _state.update { it.copy(connectionStatus = status) }
      },
      onRecoveryRequired = {
        AndroidSyncEventLogger.log("recovery_requested enqueue_work=true")
        ClipDockSyncScheduler.enqueueRecovery(appContext)
        scheduleRealtimeReconnect()
      },
      onSyncResult = { result ->
        applySyncResult(result)
        AndroidSyncEventLogger.log(
          "realtime_state_applied cursor=${result.cursor} snapshot_seq=${result.snapshotSeq} " +
            "used_snapshot=${result.usedSnapshot} reason=${result.recoveryReason ?: "none"} items=${result.items.size}",
        )
      },
      logger = AndroidSyncEventLogger,
    )
  private val setupMutex = Mutex()
  private val _state = MutableStateFlow(loadState())

  val state: StateFlow<ClipDockUiState> = _state

  fun setServerUrl(value: String) {
    preferences.edit().putString(KEY_SERVER_URL, value).apply()
    _state.update { it.copy(serverUrl = value) }
  }

  fun setDeviceName(value: String) {
    preferences.edit().putString(KEY_DEVICE_NAME, value).apply()
    _state.update { it.copy(deviceName = value) }
  }

  fun setFilter(filter: HistoryFilter) {
    _state.update { it.copy(selectedFilter = filter) }
  }

  fun setP2pEnabled(enabled: Boolean) {
    preferences.edit().putBoolean(KEY_P2P_ENABLED, enabled).apply()
    _state.update { it.copy(p2pEnabled = enabled) }
  }

  fun setWifiOnly(enabled: Boolean) {
    preferences.edit().putBoolean(KEY_WIFI_ONLY, enabled).apply()
    _state.update { it.copy(wifiOnly = enabled) }
  }

  fun setOverlayEnabled(enabled: Boolean) {
    preferences.edit().putBoolean(KEY_OVERLAY_ENABLED, enabled).apply()
    _state.update { it.copy(overlayEnabled = enabled) }
  }

  fun setOverlayClickAction(action: OverlayClickAction) {
    preferences.edit().putString(KEY_OVERLAY_CLICK_ACTION, action.name).apply()
    _state.update { it.copy(overlayClickAction = action) }
  }

  fun setOverlaySnapEdge(edge: OverlaySnapEdge) {
    preferences.edit().putString(KEY_OVERLAY_SNAP_EDGE, edge.name).apply()
    _state.update { it.copy(overlaySnapEdge = edge) }
  }

  fun setOverlaySizeDp(value: Int) {
    val sanitized = sanitizeOverlaySizeDp(value)
    preferences.edit().putInt(KEY_OVERLAY_SIZE_DP, sanitized).apply()
    _state.update { it.copy(overlaySizeDp = sanitized) }
  }

  fun setOverlayIdleOpacityPercent(value: Int) {
    val sanitized = sanitizeOverlayIdleOpacityPercent(value)
    preferences.edit().putInt(KEY_OVERLAY_IDLE_OPACITY_PERCENT, sanitized).apply()
    _state.update { it.copy(overlayIdleOpacityPercent = sanitized) }
  }

  fun setOverlayVerticalFraction(value: Float) {
    val sanitized = sanitizeOverlayVerticalFraction(value)
    preferences.edit().putFloat(KEY_OVERLAY_VERTICAL_FRACTION, sanitized).apply()
    _state.update { it.copy(overlayVerticalFraction = sanitized) }
  }

  fun setEncryptionEnabled(enabled: Boolean) {
    preferences.edit().putBoolean(KEY_ENCRYPTION_ENABLED, enabled).apply()
    _state.update { it.copy(encryptionEnabled = enabled) }
  }

  fun startLocalClipboardCapture() {
    clipboardCaptureMonitor.start()
  }

  suspend fun checkHealth() =
    runNetwork("检查连接失败") {
      val serverUrl = current.serverUrl
      api.health(serverUrl)
      _state.update { it.copy(connectionStatus = "可连接", diagnostics = it.diagnostics.copy(lastError = null)) }
    }

  suspend fun createSyncSpace() =
    setupMutex.withLock {
      if (current.hasSyncRegistration()) {
        _state.update {
          it.copy(
            connectionStatus = "已加入",
            diagnostics = it.diagnostics.copy(lastError = "已创建同步空间，请先断开当前同步"),
          )
        }
        return@withLock
      }
      runSyncSetup("创建同步空间失败") {
        val serverUrl = current.serverUrl
        val deviceName = current.deviceName
        val data = api.createSync(serverUrl, deviceName).toJSONObject()
        persistAuth(data)
        _state.update {
          it.copy(
            connectionStatus = "已加入",
            pairingCode = data.optString("pairing_code"),
            pairingExpiresAtMillis = data.optLong("pairing_expires_at_ms"),
            diagnostics = it.diagnostics.copy(lastError = null),
          )
        }
        refreshInfo()
        syncNow()
        startRealtime()
      }
    }

  suspend fun joinSyncSpace(pairingCode: String) =
    setupMutex.withLock {
      runSyncSetup("加入同步空间失败") {
        val serverUrl = current.serverUrl
        val deviceName = current.deviceName
        val normalizedCode = pairingCode.trim().uppercase()
        val data = api.joinSync(serverUrl, normalizedCode, deviceName).toJSONObject()
        persistAuth(data)
        _state.update { it.copy(connectionStatus = "已加入", pairingCode = null, pairingExpiresAtMillis = null) }
        refreshInfo()
        syncNow()
        startRealtime()
      }
    }

  suspend fun createInvite() =
    setupMutex.withLock {
      runSyncSetup("生成配对码失败") {
        val token = requireToken()
        val serverUrl = current.serverUrl
        val data = api.createInvite(serverUrl, token).toJSONObject()
        _state.update {
          it.copy(
            pairingCode = data.optString("pairing_code"),
            pairingExpiresAtMillis = data.optLong("pairing_expires_at_ms"),
            diagnostics = it.diagnostics.copy(lastError = null),
          )
        }
      }
    }

  suspend fun refreshInfo() =
    runNetwork("获取服务器能力失败") {
      val token = requireToken()
      val serverUrl = current.serverUrl
      val data = api.info(serverUrl, token).toJSONObject()
      val capabilities =
        ServerCapabilities(
          protocolVersion = data.optInt("protocol_version", 2),
          eventTypes = data.optJSONArray("event_types").stringList(),
          assetKinds = data.optJSONArray("asset_kinds").stringList(),
          assetMimeTypes = data.optJSONArray("asset_mime_types").stringList(),
          maxAssetBytes = data.optLong("max_asset_bytes"),
          p2p = data.optJSONObject("p2p")?.toString() ?: "未获取",
        )
      preferences
        .edit()
        .putString(KEY_SYNC_ID, data.optString("sync_id"))
        .putString(KEY_DEVICE_ID, data.optString("device_id"))
        .apply()
      _state.update {
        it.copy(
          syncId = data.optString("sync_id"),
          deviceId = data.optString("device_id"),
          connectionStatus = "已加入",
          capabilities = capabilities,
          diagnostics = it.diagnostics.copy(lastError = null),
        )
      }
      if (current.p2pEnabled) {
        runCatching { reportP2pEndpoint(token) }.onFailure { recordP2pFailure("P2P endpoint 上报失败", it) }
        runCatching { refreshP2pDevices(token) }.onFailure { recordP2pFailure("P2P 设备刷新失败", it) }
      }
    }

  suspend fun syncNow(): List<ClipHistoryItem> =
    runNetwork("同步失败") {
      val token = requireToken()
      val startCursor = current.diagnostics.nextCursor
      AndroidSyncEventLogger.log("rest_sync_start cursor=$startCursor")
      _state.update { it.copy(isSyncing = true, diagnostics = it.diagnostics.copy(lastError = null)) }
      try {
        if (current.p2pEnabled) {
          runCatching { reportP2pEndpoint(token) }.onFailure { recordP2pFailure("P2P endpoint 上报失败", it) }
          runCatching { refreshP2pDevices(token) }.onFailure { recordP2pFailure("P2P 设备刷新失败", it) }
        }
        val result = syncEngine.syncFromStoredCursor(current.serverUrl, token)
        AndroidSyncEventLogger.log(
          "rest_sync_success cursor=${result.cursor} snapshot_seq=${result.snapshotSeq} " +
            "used_snapshot=${result.usedSnapshot} reason=${result.recoveryReason ?: "none"} items=${result.items.size}",
        )
        applySyncResult(result, isSyncing = false, connectionStatus = "已加入")
        result.items
      } catch (throwable: Throwable) {
        AndroidSyncEventLogger.log("rest_sync_failed cursor=$startCursor error=${throwable.toSyncLogErrorLabel()}")
        _state.update {
          it.copy(
            isSyncing = false,
            diagnostics = it.diagnostics.copy(lastError = throwable.userMessage()),
          )
        }
        throw throwable
      }
    }

  suspend fun uploadLocalItem(item: ClipHistoryItem): LocalSyncPushResult =
    runNetwork("上传本地剪贴板失败") {
      val token = requireToken()
      val deviceId = current.deviceId?.takeIf(String::isNotBlank) ?: throw ClipDockApiException("missing_device_id", "缺少本机同步设备 ID")
      val pushResult = syncEngine.pushLocalItem(current.serverUrl, token, deviceId, item)
      val reconcileResult = syncEngine.syncFromStoredCursor(current.serverUrl, token)
      applySyncResult(reconcileResult, isSyncing = false, connectionStatus = "已加入")
      pushResult
    }

  private suspend fun uploadLocalClipboardClip(
    clip: ClipData,
    copiedAtMillis: Long,
  ): LocalSyncPushResult? {
    clip.toLocalClipboardHistoryItem(copiedAtMillis)?.let { item ->
      return uploadLocalItem(item)
    }
    val preparedImage = localImagePreparer.prepare(clip, copiedAtMillis) ?: return null
    return uploadLocalImage(preparedImage)
  }

  private suspend fun uploadLocalImage(preparedImage: AndroidPreparedLocalImage): LocalSyncPushResult =
    runNetwork("上传本地图片失败") {
      val token = requireToken()
      val deviceId = current.deviceId?.takeIf(String::isNotBlank) ?: throw ClipDockApiException("missing_device_id", "缺少本机同步设备 ID")
      val imported = registerLocalPayloadProvider(preparedImage.payloadFile, preparedImage.payloadMimeType, kind = "image_payload")
      preparedImage.thumbnail?.let { thumbnail ->
        val uploaded =
          api.uploadAsset(
            current.serverUrl,
            token,
            thumbnail.digest,
            kind = "thumbnail",
            mimeType = thumbnail.mimeType,
            width = thumbnail.width,
            height = thumbnail.height,
            bytes = thumbnail.bytes,
          )
        if (uploaded.digest != thumbnail.digest ||
          uploaded.kind != "thumbnail" ||
          uploaded.mimeType != thumbnail.mimeType ||
          uploaded.byteCount != thumbnail.byteCount ||
          uploaded.width != thumbnail.width ||
          uploaded.height != thumbnail.height
        ) {
          throw ClipDockApiException("thumbnail_metadata_mismatch", "缩略图上传元数据不匹配")
        }
      }

      val event = preparedImage.toImageSyncPushEventRequest(deviceId, imported.assetId)
      val data = api.pushEvents(current.serverUrl, token, listOf(event)).toJSONObject()
      val pushedEvent =
        data
          .optJSONArray("events")
          ?.let { events -> (0 until events.length()).mapNotNull { events.optJSONObject(it) } }
          ?.firstOrNull { it.optString("client_event_id") == event.clientEventId }
      val reconcileResult = syncEngine.syncFromStoredCursor(current.serverUrl, token)
      applySyncResult(reconcileResult, isSyncing = false, connectionStatus = "已加入")
      preserveLocalImagePayload(preparedImage.item.copy(assetId = imported.assetId))
      LocalSyncPushResult(
        contentHash = event.contentHash,
        clientEventId = event.clientEventId,
        nextCursor = data.optLong("next_cursor"),
        serverSeq = pushedEvent?.optLong("server_seq"),
        duplicate = pushedEvent?.optBoolean("duplicate") ?: false,
      )
    }

  suspend fun uploadLocalText(
    text: String,
    type: ClipItemType = ClipItemType.Text,
    copiedAtMillis: Long = System.currentTimeMillis(),
  ): LocalSyncPushResult {
    val normalizedText = text.trim()
    val item =
      ClipHistoryItem(
        stableId = "local-android-$copiedAtMillis",
        contentHash = "",
        type = type,
        title = normalizedText.lineSequence().firstOrNull()?.take(80).orEmpty(),
        body = normalizedText,
        detail = type.label,
        sourceName = "Android",
        assetId = null,
        thumbnailUri = null,
        thumbnailDigest = null,
        thumbnailMimeType = null,
        thumbnailByteCount = null,
        thumbnailWidth = null,
        thumbnailHeight = null,
        localUri = null,
        payloadState = PayloadState.Ready,
        transferState = TransferState.Ready,
        copiedAtMillis = copiedAtMillis,
        copyCount = 1,
      )
    return uploadLocalItem(item)
  }

  suspend fun quickSyncAndCopy(timeoutMillis: Long = 8_000): QuickCopyResult {
    return try {
      withTimeout(timeoutMillis) {
        val items = syncNow()
        val latest = items.firstOrNull()
        when {
          latest == null -> QuickCopyResult.Failed(null, "没有可复制的记录")
          latest.needsRemotePayload -> {
            val downloaded = downloadRemotePayload(latest)
            if (copyItem(downloaded)) {
              QuickCopyResult.Copied(downloaded)
            } else {
              QuickCopyResult.Failed(downloaded, "P2P 已下载，但该类型暂时无法写入剪贴板")
            }
          }
          copyItem(latest) -> QuickCopyResult.Copied(latest)
          else -> QuickCopyResult.Failed(latest, "该类型暂时无法写入剪贴板")
        }
      }
    } catch (timeout: TimeoutCancellationException) {
      QuickCopyResult.Timeout(current.items.firstOrNull(), "同步或下载超时，剪贴板未更改")
    } catch (throwable: Throwable) {
      QuickCopyResult.Failed(current.items.firstOrNull(), throwable.userMessage())
    }
  }

  suspend fun useItem(item: ClipHistoryItem, timeoutMillis: Long = 30_000): QuickCopyResult {
    return try {
      withTimeout(timeoutMillis) {
        val readyItem =
          if (item.needsRemotePayload) {
            downloadRemotePayload(item)
          } else {
            item
          }
        if (copyItem(readyItem)) {
          QuickCopyResult.Copied(readyItem)
        } else {
          QuickCopyResult.Failed(readyItem, "该类型暂时无法写入剪贴板")
        }
      }
    } catch (timeout: TimeoutCancellationException) {
      QuickCopyResult.Timeout(item, "下载超时，剪贴板未更改")
    } catch (throwable: Throwable) {
      QuickCopyResult.Failed(item, throwable.userMessage())
    }
  }

  fun copyItem(item: ClipHistoryItem): Boolean {
    if (item.needsRemotePayload) return false
    val clipboard = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip =
      when (item.type) {
        ClipItemType.Text, ClipItemType.RichText -> ClipData.newPlainText("ClipDock", item.body.ifBlank { item.title })
        ClipItemType.Link -> ClipData.newPlainText("ClipDock link", item.body.ifBlank { item.title })
        ClipItemType.Color -> ClipData.newPlainText("ClipDock color", item.title)
        ClipItemType.Image, ClipItemType.File ->
          item.localUri?.let { ClipData.newUri(appContext.contentResolver, item.title, Uri.parse(it)) }
        ClipItemType.Unknown -> null
      }
    clip ?: return false
    clip.description.extras =
      PersistableBundle().apply {
        putBoolean("android.content.extra.IS_SENSITIVE", false)
        putString(CLIPDOCK_CLIP_EXTRA_SOURCE, CLIPDOCK_CLIP_SOURCE)
        if (item.contentHash.isNotBlank()) {
          putString(CLIPDOCK_CLIP_EXTRA_CONTENT_HASH, item.contentHash)
        }
      }
    clipboardCaptureMonitor.ignoreSelfCopy(clip)
    clipboard.setPrimaryClip(clip)
    return true
  }

  suspend fun registerLocalPayloadProvider(
    file: File,
    mimeType: String?,
    kind: String = "file_payload",
  ): P2pImportResult {
    val token = requireToken()
    if (!current.p2pEnabled) throw ClipDockApiException("p2p_disabled", "P2P 下载未开启")
    reportP2pEndpoint(token)
    val imported = p2pTransport.importBlob(file)
    api.upsertP2pProvider(
      current.serverUrl,
      token,
      imported.assetId,
      kind,
      imported.byteCount,
      mimeType,
      imported.ticket,
    )
    return imported
  }

  private suspend fun reportP2pEndpoint(token: String) {
    val endpoint = p2pTransport.startNode()
    api.reportP2pEndpoint(
      current.serverUrl,
      token,
      endpoint.endpointId,
      endpoint.relayUrl,
      endpoint.directAddresses,
    )
  }

  private suspend fun lookupP2pProviders(assetId: String): JSONObject {
    val token = requireToken()
    return api.p2pProviders(current.serverUrl, token, assetId).toJSONObject()
  }

  private suspend fun refreshP2pDevices(token: String) {
    val data = api.p2pDevices(current.serverUrl, token).toJSONObject()
    _state.update {
      it.copy(
        p2pDevices = data.optJSONArray("devices").toP2pDevices(),
        p2pDevicesLastRefreshMillis = System.currentTimeMillis(),
      )
    }
  }

  private suspend fun downloadRemotePayload(item: ClipHistoryItem): ClipHistoryItem {
    return try {
      if (!current.p2pEnabled) throw ClipDockApiException("p2p_disabled", "P2P 下载未开启")
      val assetId = item.assetId ?: throw ClipDockApiException("missing_asset_id", "远程内容缺少 P2P asset id")
      if (current.wifiOnly && !isWifiConnected()) throw ClipDockApiException("wifi_only_blocked", "仅 Wi-Fi 下载已开启，当前网络不可取回")
      updateTransferState(item, PayloadState.RemoteOnly, TransferState.DiscoveringPeer)
      val providers = lookupP2pProviders(assetId)
      val candidate =
        P2pProviderSelector.selectDownloadCandidate(providers, current.deviceId)
          ?: throw ClipDockApiException("p2p_provider_unavailable", "没有可用的 P2P 提供方")
      updateTransferState(item, PayloadState.RemoteOnly, TransferState.Downloading)
      val targetFile = p2pPayloadFile(item, candidate)
      val result = p2pTransport.downloadBlob(candidate.ticket, targetFile)
      val outputFile = File(result.outputPath)
      val localUri =
        FileProvider.getUriForFile(
            appContext,
            "${appContext.packageName}.files",
            outputFile,
          )
          .toString()
      val downloaded =
        item.copy(
          localUri = localUri,
          payloadState = PayloadState.Ready,
          transferState = TransferState.Ready,
          detail = item.detail.ifBlank { "${result.byteCount} bytes" },
        )
      replaceItem(downloaded)
      downloaded
    } catch (throwable: Throwable) {
      updateTransferState(item, PayloadState.RemoteOnly, TransferState.Failed)
      throw throwable
    }
  }

  private fun p2pPayloadFile(item: ClipHistoryItem, candidate: P2pProviderCandidate): File {
    val baseName =
      listOf(item.contentHash.safeFilePart(), item.title.safeFilePart())
        .filter(String::isNotBlank)
        .joinToString("-")
        .ifBlank { item.stableId.safeFilePart().ifBlank { "payload" } }
    val extension = item.payloadExtension(candidate)
    return File(p2pTransport.defaultPayloadDir(), "$baseName$extension")
  }

  private fun updateTransferState(
    item: ClipHistoryItem,
    payloadState: PayloadState,
    transferState: TransferState,
  ) {
    replaceItem(item.copy(payloadState = payloadState, transferState = transferState))
  }

  private fun replaceItem(item: ClipHistoryItem) {
    val merged = current.items.map { existing -> if (existing.stableId == item.stableId) item else existing }
    persistItems(merged)
    _state.update { it.copy(items = merged) }
  }

  private fun preserveLocalImagePayload(localItem: ClipHistoryItem) {
    var found = false
    val mergedItems =
      current.items.map { existing ->
        if (existing.contentHash == localItem.contentHash && existing.type == ClipItemType.Image) {
          found = true
          existing.copy(
            assetId = existing.assetId ?: localItem.assetId,
            thumbnailUri = existing.thumbnailUri ?: localItem.thumbnailUri,
            localUri = localItem.localUri,
            payloadState = PayloadState.Ready,
            transferState = TransferState.Ready,
          )
        } else {
          existing
        }
      }
    val merged = if (found) mergedItems else (mergedItems + localItem).sortedByDescending { it.copiedAtMillis }
    persistItems(merged)
    _state.update { it.copy(items = merged) }
  }

  private fun recordP2pFailure(prefix: String, throwable: Throwable) {
    _state.update {
      it.copy(diagnostics = it.diagnostics.copy(lastError = "$prefix: ${throwable.userMessage()}"))
    }
  }

  private suspend fun <T> runNetwork(errorPrefix: String, block: suspend () -> T): T {
    try {
      return block()
    } catch (throwable: Throwable) {
      _state.update { it.copy(diagnostics = it.diagnostics.copy(lastError = "$errorPrefix: ${throwable.userMessage()}")) }
      throw throwable
    }
  }

  private suspend fun runSyncSetup(errorPrefix: String, block: suspend () -> Unit) {
    _state.update {
      it.copy(
        isSyncSetupInFlight = true,
        connectionStatus = "连接中",
        diagnostics = it.diagnostics.copy(lastError = null),
      )
    }
    try {
      runNetwork(errorPrefix, block)
    } finally {
      _state.update { state ->
        state.copy(
          isSyncSetupInFlight = false,
          connectionStatus = if (!state.tokenPresent && state.connectionStatus == "连接中") "未设置" else state.connectionStatus,
        )
      }
    }
  }

  private fun persistAuth(data: JSONObject) {
    preferences
      .edit()
      .putString(KEY_SYNC_ID, data.optString("sync_id"))
      .putString(KEY_DEVICE_ID, data.optString("device_id"))
      .putString(KEY_TOKEN, data.optString("token"))
      .apply()
    _state.update {
      it.copy(
        syncId = data.optString("sync_id"),
        deviceId = data.optString("device_id"),
        tokenPresent = data.optString("token").isNotBlank(),
      )
    }
  }

  private fun requireToken(): String =
    preferences.getString(KEY_TOKEN, null)?.takeIf { it.isNotBlank() } ?: throw ClipDockApiException("unauthorized", "尚未加入同步空间")

  private fun persistItems(items: List<ClipHistoryItem>) {
    preferences.edit().putString(KEY_ITEMS_JSON, items.toJsonArray().toString()).commit()
  }

  private fun loadState(): ClipDockUiState {
    val progress = runCatching { syncStore.loadProgress() }.getOrElse { SyncProgress(emptyList(), 0, 0) }
    val token = preferences.getString(KEY_TOKEN, null)
    return ClipDockUiState(
      serverUrl = preferences.getString(KEY_SERVER_URL, null) ?: "http://10.0.2.2:9001",
      deviceName = preferences.getString(KEY_DEVICE_NAME, null) ?: android.os.Build.MODEL.ifBlank { "Android" },
      syncId = preferences.getString(KEY_SYNC_ID, null),
      deviceId = preferences.getString(KEY_DEVICE_ID, null),
      tokenPresent = !token.isNullOrBlank(),
      connectionStatus = if (token.isNullOrBlank()) "未设置" else "已加入",
      diagnostics = SyncDiagnostics(snapshotSeq = progress.snapshotSeq, nextCursor = progress.cursor),
      items = progress.items.sortedByDescending { it.copiedAtMillis },
      p2pEnabled = preferences.getBoolean(KEY_P2P_ENABLED, true),
      wifiOnly = preferences.getBoolean(KEY_WIFI_ONLY, true),
      overlayEnabled = preferences.getBoolean(KEY_OVERLAY_ENABLED, true),
      overlayClickAction = enumPreference(KEY_OVERLAY_CLICK_ACTION, OverlayClickAction.QuickSyncCopy),
      overlaySnapEdge = enumPreference(KEY_OVERLAY_SNAP_EDGE, OverlaySnapEdge.Right),
      overlaySizeDp = sanitizeOverlaySizeDp(preferences.getInt(KEY_OVERLAY_SIZE_DP, 64)),
      overlayIdleOpacityPercent = sanitizeOverlayIdleOpacityPercent(preferences.getInt(KEY_OVERLAY_IDLE_OPACITY_PERCENT, 78)),
      overlayVerticalFraction = sanitizeOverlayVerticalFraction(preferences.getFloat(KEY_OVERLAY_VERTICAL_FRACTION, 0.35f)),
      encryptionEnabled = preferences.getBoolean(KEY_ENCRYPTION_ENABLED, false),
    )
  }

  private inline fun <reified T : Enum<T>> enumPreference(key: String, default: T): T {
    val raw = preferences.getString(key, null) ?: return default
    return enumValues<T>().firstOrNull { it.name == raw } ?: default
  }

  private fun isWifiConnected(): Boolean {
    val connectivityManager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val network = connectivityManager.activeNetwork ?: return false
    val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
    return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
  }

  fun startRealtime() {
    val token =
      preferences.getString(KEY_TOKEN, null)?.takeIf { it.isNotBlank() }
        ?: run {
          AndroidSyncEventLogger.log("realtime_start_skipped reason=no_token")
          return
        }
    val cursor = current.diagnostics.nextCursor
    AndroidSyncEventLogger.log(
      "realtime_start server=${current.serverUrl.toSyncLogServerLabel()} cursor=$cursor " +
        "fallback_interval_ms=$REST_FALLBACK_POLL_INTERVAL_MS",
    )
    realtimeClient.connect(current.serverUrl, token, cursor)
    startFallbackPolling()
    syncScope.launch {
      AndroidSyncEventLogger.log("startup_rest_sync_start cursor=$cursor")
      runCatching { syncNow() }
        .onSuccess { AndroidSyncEventLogger.log("startup_rest_sync_success cursor=${current.diagnostics.nextCursor} items=${it.size}") }
        .onFailure { AndroidSyncEventLogger.log("startup_rest_sync_failed error=${it.toSyncLogErrorLabel()}") }
    }
  }

  private fun applySyncResult(
    result: SyncResult,
    isSyncing: Boolean? = null,
    connectionStatus: String? = null,
  ) {
    _state.update {
      it.copy(
        items = result.items,
        isSyncing = isSyncing ?: it.isSyncing,
        connectionStatus = connectionStatus ?: it.connectionStatus,
        diagnostics =
          it.diagnostics.copy(
            snapshotSeq = result.snapshotSeq,
            nextCursor = result.cursor,
            lastSyncAtMillis = System.currentTimeMillis(),
            lastError = null,
          ),
      )
    }
  }

  private fun scheduleRealtimeReconnect() {
    synchronized(realtimeReconnectLock) {
      if (realtimeReconnectJob?.isActive == true) {
        AndroidSyncEventLogger.log("ws_reconnect_already_scheduled")
        return
      }
      val delayMillis = realtimeReconnectBackoff.nextDelayMillis()
      AndroidSyncEventLogger.log("ws_reconnect_scheduled delay_ms=$delayMillis")
      realtimeReconnectJob =
        syncScope.launch {
          delay(delayMillis)
          if (preferences.getString(KEY_TOKEN, null).isNullOrBlank()) {
            AndroidSyncEventLogger.log("ws_reconnect_skipped reason=no_token")
            return@launch
          }
          AndroidSyncEventLogger.log("ws_reconnect_start")
          startRealtime()
        }
    }
  }

  private fun resetRealtimeReconnectBackoff() {
    synchronized(realtimeReconnectLock) {
      realtimeReconnectBackoff.reset()
      AndroidSyncEventLogger.log("ws_reconnect_backoff_reset")
      if (realtimeReconnectJob?.isActive != true) {
        realtimeReconnectJob = null
      }
    }
  }

  private fun startFallbackPolling() {
    if (fallbackPollJob?.isActive == true) {
      AndroidSyncEventLogger.log("rest_fallback_already_running")
      return
    }
    AndroidSyncEventLogger.log("rest_fallback_started interval_ms=$REST_FALLBACK_POLL_INTERVAL_MS")
    fallbackPollJob =
      syncScope.launch {
        while (isActive) {
          delay(REST_FALLBACK_POLL_INTERVAL_MS)
          if (preferences.getString(KEY_TOKEN, null).isNullOrBlank()) return@launch
          val cursor = current.diagnostics.nextCursor
          AndroidSyncEventLogger.log("rest_fallback_tick cursor=$cursor")
          runCatching { syncNow() }
            .onSuccess { AndroidSyncEventLogger.log("rest_fallback_success cursor=${current.diagnostics.nextCursor} items=${it.size}") }
            .onFailure { AndroidSyncEventLogger.log("rest_fallback_failed cursor=$cursor error=${it.toSyncLogErrorLabel()}") }
        }
      }
  }

  private val current: ClipDockUiState
    get() = _state.value

  companion object {
    private const val KEY_SERVER_URL = "serverUrl"
    private const val KEY_DEVICE_NAME = "deviceName"
    private const val KEY_SYNC_ID = "syncId"
    private const val KEY_DEVICE_ID = "deviceId"
    private const val KEY_TOKEN = "token"
    private const val KEY_ITEMS_JSON = "itemsJson"
    private const val KEY_CURSOR = "cursor"
    private const val KEY_SNAPSHOT_SEQ = "snapshotSeq"
    private const val KEY_P2P_ENABLED = "p2pEnabled"
    private const val KEY_WIFI_ONLY = "wifiOnly"
    private const val KEY_OVERLAY_ENABLED = "overlayEnabled"
    private const val KEY_OVERLAY_CLICK_ACTION = "overlayClickAction"
    private const val KEY_OVERLAY_SNAP_EDGE = "overlaySnapEdge"
    private const val KEY_OVERLAY_SIZE_DP = "overlaySizeDp"
    private const val KEY_OVERLAY_IDLE_OPACITY_PERCENT = "overlayIdleOpacityPercent"
    private const val KEY_OVERLAY_VERTICAL_FRACTION = "overlayVerticalFraction"
    private const val KEY_ENCRYPTION_ENABLED = "encryptionEnabled"
    private const val REST_FALLBACK_POLL_INTERVAL_MS = 30_000L
  }
}

internal class RealtimeReconnectBackoff(
  private val initialDelayMillis: Long = 5_000L,
  private val maxDelayMillis: Long = 5 * 60 * 1_000L,
) {
  private var attempt = 0

  fun nextDelayMillis(): Long {
    val delay = (0 until attempt).fold(initialDelayMillis) { current, _ ->
      (current * 2).coerceAtMost(maxDelayMillis)
    }
    attempt += 1
    return delay.coerceAtMost(maxDelayMillis)
  }

  fun reset() {
    attempt = 0
  }
}

private fun ClipDockUiState.hasSyncRegistration(): Boolean =
  tokenPresent || !syncId.isNullOrBlank() || !deviceId.isNullOrBlank()

private fun ClipHistoryItem.payloadExtension(candidate: P2pProviderCandidate): String {
  title.substringAfterLast('.', "")
    .takeIf { it.length in 1..8 && it.all { character -> character.isLetterOrDigit() } }
    ?.let { return ".$it" }
  val mimeExtension = MimeTypeMap.getSingleton().getExtensionFromMimeType(candidate.mimeType.orEmpty())
  if (!mimeExtension.isNullOrBlank()) return ".$mimeExtension"
  return when (type) {
    ClipItemType.Image -> ".image"
    ClipItemType.File -> ".bin"
    else -> ".payload"
  }
}

internal fun AndroidPreparedLocalImage.toImageSyncPushEventRequest(
  deviceId: String,
  payloadAssetId: String,
): SyncPushEventRequest {
  val contentHash =
    item.contentHash
      .takeIf(::isCanonicalBlake3Digest)
      ?: throw ClipDockApiException("invalid_content_hash", "本地图片缺少 BLAKE3 内容标识")
  val payload =
    buildJsonObject {
      put("source_platform", JsonPrimitive("android"))
      put("source_app_name", JsonPrimitive(item.sourceName?.takeIf(String::isNotBlank) ?: "Android"))
      put("file_name", JsonPrimitive(item.title.ifBlank { "image" }))
      put("summary", JsonPrimitive(item.title.ifBlank { "image" }))
      put("mime_type", JsonPrimitive(payloadMimeType))
      put("byte_count", JsonPrimitive(payloadByteCount))
      put("width", JsonPrimitive(width))
      put("height", JsonPrimitive(height))
      put("payload_asset_id", JsonPrimitive(payloadAssetId))
      put("asset_id", JsonPrimitive(payloadAssetId))
      thumbnail?.let { thumbnail ->
        put("thumbnail_digest", JsonPrimitive(thumbnail.digest))
        put("thumbnail_mime_type", JsonPrimitive(thumbnail.mimeType))
        put("thumbnail_byte_count", JsonPrimitive(thumbnail.byteCount))
        put("thumbnail_width", JsonPrimitive(thumbnail.width))
        put("thumbnail_height", JsonPrimitive(thumbnail.height))
      }
    }
  return SyncPushEventRequest(
    clientEventId = stableAndroidClientEventId(deviceId, contentHash, item.copiedAtMillis),
    type = "item_upsert",
    contentHash = contentHash,
    itemType = ClipItemType.Image.wireName,
    payload = payload,
    copyCountDelta = item.copyCount.coerceIn(1, 100),
  )
}

internal fun ClipHistoryItem.preservingDownloadedPayload(previous: ClipHistoryItem?): ClipHistoryItem {
  if (previous == null) return this
  if (contentHash != previous.contentHash || type != previous.type) return this
  if (type != ClipItemType.Image && type != ClipItemType.File) return this
  val preservedThumbnailUri =
    thumbnailUri
      ?: previous.thumbnailUri.takeIf {
        thumbnailDigest != null && thumbnailDigest == previous.thumbnailDigest
      }
  if (!localUri.isNullOrBlank()) return copy(thumbnailUri = preservedThumbnailUri)
  if (previous.localUri.isNullOrBlank() || previous.payloadState != PayloadState.Ready) {
    return copy(thumbnailUri = preservedThumbnailUri)
  }
  return copy(
    thumbnailUri = preservedThumbnailUri,
    localUri = previous.localUri,
    payloadState = PayloadState.Ready,
    transferState = TransferState.Ready,
  )
}

private fun String.safeFilePart(): String =
  lowercase(Locale.US)
    .replace(Regex("[^a-z0-9._-]+"), "-")
    .trim('-', '.', '_')
    .take(80)

internal fun JSONArray?.toEventItems(tombstones: MutableSet<String>): List<ClipHistoryItem> {
  if (this == null) return emptyList()
  val items = mutableListOf<ClipHistoryItem>()
  for (index in 0 until length()) {
    val event = optJSONObject(index) ?: continue
    if (event.optString("type") == "item_delete") {
      tombstones += event.optString("content_hash")
    } else {
      ClipHistoryItem.fromServerEvent(event)?.let { item ->
        tombstones -= item.contentHash
        items += item
      }
    }
  }
  return items
}

private fun JSONArray?.stringList(): List<String> {
  if (this == null) return emptyList()
  return (0 until length()).mapNotNull { optString(it).takeIf(String::isNotBlank) }
}

private fun Throwable.userMessage(): String =
  when (this) {
    is ClipDockApiException -> apiUserMessage()
    is java.net.SocketTimeoutException -> "连接超时"
    is java.net.UnknownHostException -> "无法解析服务器地址"
    is java.net.ConnectException -> "无法连接服务器"
    else -> message ?: javaClass.simpleName
  }

private fun ClipDockApiException.apiUserMessage(): String =
  when (code) {
    "invalid_pairing_code" -> "配对码无效、已过期或已被使用"
    "invalid_device_name" -> "设备名称不能为空"
    "unauthorized" -> message ?: "尚未加入同步空间"
    else -> message?.takeIf { it.isNotBlank() } ?: code.ifBlank { "请求失败" }
  }
