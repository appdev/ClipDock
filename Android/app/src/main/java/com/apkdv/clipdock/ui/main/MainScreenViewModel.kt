package com.apkdv.clipdock.ui.main

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.apkdv.clipdock.ClipDockApplication
import com.apkdv.clipdock.data.HistoryFilter
import kotlinx.coroutines.launch

class MainScreenViewModel(application: Application) : AndroidViewModel(application) {
  private val repository = (application as ClipDockApplication).repository
  val uiState = repository.state

  fun setServerUrl(value: String) = repository.setServerUrl(value)

  fun setDeviceName(value: String) = repository.setDeviceName(value)

  fun setFilter(filter: HistoryFilter) = repository.setFilter(filter)

  fun setP2pEnabled(enabled: Boolean) = repository.setP2pEnabled(enabled)

  fun setWifiOnly(enabled: Boolean) = repository.setWifiOnly(enabled)

  fun setOverlayEnabled(enabled: Boolean) = repository.setOverlayEnabled(enabled)

  fun setEncryptionEnabled(enabled: Boolean) = repository.setEncryptionEnabled(enabled)

  fun checkHealth() = viewModelScope.launch { runCatching { repository.checkHealth() } }

  fun syncNow() = viewModelScope.launch { runCatching { repository.syncNow() } }

  fun createSyncSpace() = viewModelScope.launch { runCatching { repository.createSyncSpace() } }

  fun joinSyncSpace(pairingCode: String) = viewModelScope.launch { runCatching { repository.joinSyncSpace(pairingCode) } }

  fun createInvite() = viewModelScope.launch { runCatching { repository.createInvite() } }

  fun refreshInfo() = viewModelScope.launch { runCatching { repository.refreshInfo() } }
}
