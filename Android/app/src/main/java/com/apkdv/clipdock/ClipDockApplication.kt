package com.apkdv.clipdock

import android.app.Application
import com.apkdv.clipdock.data.ClipDockRepository

class ClipDockApplication : Application() {
  val repository: ClipDockRepository by lazy { ClipDockRepository(this) }
}
