package com.apkdv.clipdock.ui.main

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.apkdv.clipdock.ClipDockApplication
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.HistoryFilter
import com.apkdv.clipdock.data.OverlayClickAction
import com.apkdv.clipdock.data.OverlaySnapEdge
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class MainScreenViewModel(application: Application) : AndroidViewModel(application) {
  private val repository = (application as ClipDockApplication).repository
  val uiState = repository.state
  private val _v4ActionState = MutableStateFlow(MobileV4ActionState())
  val v4ActionState: StateFlow<MobileV4ActionState> = _v4ActionState

  fun setServerUrl(value: String) = repository.setServerUrl(value)

  fun setDeviceName(value: String) = repository.setDeviceName(value)

  fun setFilter(filter: HistoryFilter) = repository.setFilter(filter)

  fun setP2pEnabled(enabled: Boolean) = repository.setP2pEnabled(enabled)

  fun setWifiOnly(enabled: Boolean) = repository.setWifiOnly(enabled)

  fun setOverlayEnabled(enabled: Boolean) = repository.setOverlayEnabled(enabled)

  fun setOverlayClickAction(action: OverlayClickAction) = repository.setOverlayClickAction(action)

  fun setOverlaySnapEdge(edge: OverlaySnapEdge) = repository.setOverlaySnapEdge(edge)

  fun setOverlaySizeDp(value: Int) = repository.setOverlaySizeDp(value)

  fun setOverlayIdleOpacityPercent(value: Int) = repository.setOverlayIdleOpacityPercent(value)

  fun setOverlayVerticalFraction(value: Float) = repository.setOverlayVerticalFraction(value)

  fun setEncryptionEnabled(enabled: Boolean) = repository.setEncryptionEnabled(enabled)

  fun checkHealth() = viewModelScope.launch { runCatching { repository.checkHealth() } }

  fun syncNow() = viewModelScope.launch { runCatching { repository.syncNow() } }

  fun createSyncSpace() = viewModelScope.launch { runCatching { repository.createSyncSpace() } }

  fun joinSyncSpace(pairingCode: String) = viewModelScope.launch { runCatching { repository.joinSyncSpace(pairingCode) } }

  fun createInvite() = viewModelScope.launch { runCatching { repository.createInvite() } }

  fun refreshInfo() = viewModelScope.launch { runCatching { repository.refreshInfo() } }

  fun useItem(item: ClipHistoryItem) = viewModelScope.launch { repository.useItem(item) }

  fun copyItem(item: ClipHistoryItem) =
    launchGuarded(item, MobileV4ActionKind.Copy) {
      repository.copyItem(item)
    }

  fun downloadAndCopy(item: ClipHistoryItem) =
    launchGuarded(item, MobileV4ActionKind.DownloadAndCopy) {
      repository.downloadAndCopy(item)
    }

  fun downloadToCache(item: ClipHistoryItem) =
    launchGuarded(item, MobileV4ActionKind.DownloadToCache) {
      repository.downloadToCache(item)
    }

  fun copyThumbnail(item: ClipHistoryItem) =
    launchGuarded(item, MobileV4ActionKind.CopyThumbnail) {
      repository.copyThumbnail(item)
    }

  fun deleteSyncRecord(item: ClipHistoryItem) =
    launchGuarded(item, MobileV4ActionKind.DeleteSyncRecord) {
      repository.deleteSyncRecord(item)
    }

  fun removeLocalCache(item: ClipHistoryItem) =
    launchGuarded(item, MobileV4ActionKind.RemoveLocalCache) {
      repository.removeLocalCache(item)
    }

  private fun launchGuarded(
    item: ClipHistoryItem,
    kind: MobileV4ActionKind,
    block: suspend () -> Unit,
  ) {
    if (!beginAction(item.stableId, kind)) return
    viewModelScope.launch {
      try {
        block()
      } finally {
        endAction(item.stableId, kind)
      }
    }
  }

  private fun beginAction(stableId: String, kind: MobileV4ActionKind): Boolean {
    var started = false
    _v4ActionState.update { state ->
      val currentKinds = state.inFlight[stableId].orEmpty()
      if (kind in currentKinds) return@update state
      started = true
      state.copy(inFlight = state.inFlight + (stableId to (currentKinds + kind)))
    }
    return started
  }

  private fun endAction(stableId: String, kind: MobileV4ActionKind) {
    _v4ActionState.update { state ->
      val currentKinds = state.inFlight[stableId].orEmpty()
      val nextKinds = currentKinds - kind
      state.copy(
        inFlight =
          if (nextKinds.isEmpty()) {
            state.inFlight - stableId
          } else {
            state.inFlight + (stableId to nextKinds)
          },
      )
    }
  }
}
