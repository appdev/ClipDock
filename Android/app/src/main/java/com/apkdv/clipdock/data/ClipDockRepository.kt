package com.apkdv.clipdock.data

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject

class ClipDockRepository(private val context: Context) {
  private val appContext = context.applicationContext
  private val preferences = appContext.getSharedPreferences("clipdock", Context.MODE_PRIVATE)
  private val api = ClipDockApiClient()
  private val p2pTransport = NativeP2pTransport(appContext)
  private val syncMutex = Mutex()
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

  fun setEncryptionEnabled(enabled: Boolean) {
    preferences.edit().putBoolean(KEY_ENCRYPTION_ENABLED, enabled).apply()
    _state.update { it.copy(encryptionEnabled = enabled) }
  }

  suspend fun checkHealth() =
    runNetwork("检查连接失败") {
      api.health(current.serverUrl)
      _state.update { it.copy(connectionStatus = "可连接", diagnostics = it.diagnostics.copy(lastError = null)) }
    }

  suspend fun createSyncSpace() =
    runNetwork("创建同步空间失败") {
      val data = api.createSync(current.serverUrl, current.deviceName)
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
    }

  suspend fun joinSyncSpace(pairingCode: String) =
    runNetwork("加入同步空间失败") {
      val data = api.joinSync(current.serverUrl, pairingCode.trim().uppercase(), current.deviceName)
      persistAuth(data)
      _state.update { it.copy(connectionStatus = "已加入", pairingCode = null, pairingExpiresAtMillis = null) }
      refreshInfo()
      syncNow()
    }

  suspend fun createInvite() =
    runNetwork("生成配对码失败") {
      val token = requireToken()
      val data = api.createInvite(current.serverUrl, token)
      _state.update {
        it.copy(
          pairingCode = data.optString("pairing_code"),
          pairingExpiresAtMillis = data.optLong("pairing_expires_at_ms"),
          diagnostics = it.diagnostics.copy(lastError = null),
        )
      }
    }

  suspend fun refreshInfo() =
    runNetwork("获取服务器能力失败") {
      val token = requireToken()
      val data = api.info(current.serverUrl, token)
      val capabilities =
        ServerCapabilities(
          protocolVersion = data.optInt("protocol_version", 1),
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
      }
    }

  suspend fun syncNow(): List<ClipHistoryItem> =
    syncMutex.withLock {
      val token = requireToken()
      _state.update { it.copy(isSyncing = true, diagnostics = it.diagnostics.copy(lastError = null)) }
      try {
        if (current.p2pEnabled) {
          runCatching { reportP2pEndpoint(token) }.onFailure { recordP2pFailure("P2P endpoint 上报失败", it) }
        }
        val snapshot = withContext(Dispatchers.IO) { api.snapshot(current.serverUrl, token) }
        val snapshotSeq = snapshot.optLong("snapshot_seq")
        val snapshotItems = snapshot.optJSONArray("items").toSnapshotItems()
        val tombstones = snapshot.optJSONArray("tombstones").contentHashes().toMutableSet()
        val events = withContext(Dispatchers.IO) { api.events(current.serverUrl, token, snapshotSeq) }
        val eventItems = events.optJSONArray("events").toEventItems(tombstones)
        val previousItemsByHash = current.items.associateBy { it.contentHash }
        val merged =
          (snapshotItems + eventItems)
            .filterNot { tombstones.contains(it.contentHash) }
            .distinctBy { it.contentHash }
            .map { item -> item.preservingDownloadedPayload(previousItemsByHash[item.contentHash]) }
            .sortedByDescending { it.copiedAtMillis }
        val nextCursor = events.optLong("next_cursor", snapshotSeq)
        persistItems(merged)
        preferences.edit().putLong(KEY_CURSOR, nextCursor).putLong(KEY_SNAPSHOT_SEQ, snapshotSeq).apply()
        _state.update {
          it.copy(
            items = merged,
            isSyncing = false,
            connectionStatus = "已加入",
            diagnostics =
              it.diagnostics.copy(
                snapshotSeq = snapshotSeq,
                nextCursor = nextCursor,
                lastSyncAtMillis = System.currentTimeMillis(),
                lastError = null,
              ),
          )
        }
        merged
      } catch (throwable: Throwable) {
        _state.update {
          it.copy(
            isSyncing = false,
            diagnostics = it.diagnostics.copy(lastError = throwable.userMessage()),
          )
        }
        throw throwable
      }
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
    clip.description.extras = PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", false) }
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
    withContext(Dispatchers.IO) {
      api.upsertP2pProvider(
        current.serverUrl,
        token,
        imported.assetId,
        kind,
        imported.byteCount,
        mimeType,
        imported.ticket,
      )
    }
    return imported
  }

  private suspend fun reportP2pEndpoint(token: String) {
    val endpoint = p2pTransport.startNode()
    withContext(Dispatchers.IO) {
      api.reportP2pEndpoint(
        current.serverUrl,
        token,
        endpoint.endpointId,
        endpoint.relayUrl,
        endpoint.directAddresses,
      )
    }
  }

  private suspend fun lookupP2pProviders(assetId: String): JSONObject {
    val token = requireToken()
    return withContext(Dispatchers.IO) { api.p2pProviders(current.serverUrl, token, assetId) }
  }

  private suspend fun downloadRemotePayload(item: ClipHistoryItem): ClipHistoryItem {
    return try {
      if (!current.p2pEnabled) throw ClipDockApiException("p2p_disabled", "P2P 下载未开启")
      val assetId = item.assetId ?: throw ClipDockApiException("missing_asset_id", "远程内容缺少 P2P asset id")
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

  private fun recordP2pFailure(prefix: String, throwable: Throwable) {
    _state.update {
      it.copy(diagnostics = it.diagnostics.copy(lastError = "$prefix: ${throwable.userMessage()}"))
    }
  }

  private suspend fun runNetwork(errorPrefix: String, block: suspend () -> Unit) {
    try {
      block()
    } catch (throwable: Throwable) {
      _state.update { it.copy(diagnostics = it.diagnostics.copy(lastError = "$errorPrefix: ${throwable.userMessage()}")) }
      throw throwable
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
    preferences.edit().putString(KEY_ITEMS_JSON, items.toJsonArray().toString()).apply()
  }

  private fun loadState(): ClipDockUiState {
    val items = JSONArray(preferences.getString(KEY_ITEMS_JSON, "[]")).toClipItems()
    val token = preferences.getString(KEY_TOKEN, null)
    val snapshotSeq = preferences.getLong(KEY_SNAPSHOT_SEQ, 0)
    val cursor = preferences.getLong(KEY_CURSOR, 0)
    return ClipDockUiState(
      serverUrl = preferences.getString(KEY_SERVER_URL, null) ?: "http://10.0.2.2:9001",
      deviceName = preferences.getString(KEY_DEVICE_NAME, null) ?: android.os.Build.MODEL.ifBlank { "Android" },
      syncId = preferences.getString(KEY_SYNC_ID, null),
      deviceId = preferences.getString(KEY_DEVICE_ID, null),
      tokenPresent = !token.isNullOrBlank(),
      connectionStatus = if (token.isNullOrBlank()) "未设置" else "已加入",
      diagnostics = SyncDiagnostics(snapshotSeq = snapshotSeq, nextCursor = cursor),
      items = items.sortedByDescending { it.copiedAtMillis },
      p2pEnabled = preferences.getBoolean(KEY_P2P_ENABLED, true),
      wifiOnly = preferences.getBoolean(KEY_WIFI_ONLY, true),
      overlayEnabled = preferences.getBoolean(KEY_OVERLAY_ENABLED, true),
      encryptionEnabled = preferences.getBoolean(KEY_ENCRYPTION_ENABLED, false),
    )
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
    private const val KEY_ENCRYPTION_ENABLED = "encryptionEnabled"
  }
}

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

internal fun ClipHistoryItem.preservingDownloadedPayload(previous: ClipHistoryItem?): ClipHistoryItem {
  if (previous == null) return this
  if (contentHash != previous.contentHash || type != previous.type) return this
  if (type != ClipItemType.Image && type != ClipItemType.File) return this
  if (!localUri.isNullOrBlank()) return this
  if (previous.localUri.isNullOrBlank() || previous.payloadState != PayloadState.Ready) return this
  return copy(
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

private fun JSONArray?.toSnapshotItems(): List<ClipHistoryItem> =
  if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it)?.let(ClipHistoryItem::fromServerSnapshot) }

private fun JSONArray?.toEventItems(tombstones: MutableSet<String>): List<ClipHistoryItem> {
  if (this == null) return emptyList()
  val items = mutableListOf<ClipHistoryItem>()
  for (index in 0 until length()) {
    val event = optJSONObject(index) ?: continue
    if (event.optString("type") == "item_delete") {
      tombstones += event.optString("content_hash")
    } else {
      ClipHistoryItem.fromServerEvent(event)?.let(items::add)
    }
  }
  return items
}

private fun JSONArray?.contentHashes(): Set<String> {
  if (this == null) return emptySet()
  return (0 until length()).mapNotNull { optJSONObject(it)?.optString("content_hash")?.takeIf(String::isNotBlank) }.toSet()
}

private fun JSONArray?.stringList(): List<String> {
  if (this == null) return emptyList()
  return (0 until length()).mapNotNull { optString(it).takeIf(String::isNotBlank) }
}

private fun Throwable.userMessage(): String =
  when (this) {
    is ClipDockApiException -> code.ifBlank { message ?: "请求失败" }
    else -> message ?: javaClass.simpleName
  }
