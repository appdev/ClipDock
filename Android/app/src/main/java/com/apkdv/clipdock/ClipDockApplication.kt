package com.apkdv.clipdock

import android.app.Application
import com.apkdv.clipdock.data.ClipDockRepository
import com.apkdv.clipdock.data.ConnectivityRecoveryMonitor

class ClipDockApplication : Application() {
  val repository: ClipDockRepository by lazy { ClipDockRepository(this) }

  override fun onCreate() {
    super.onCreate()
    ConnectivityRecoveryMonitor(this).start()
    repository.startLocalClipboardCapture()
    repository.startRealtime()
  }
}
