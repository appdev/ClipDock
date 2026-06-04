package com.apkdv.clipdock.data

import android.util.Log
import java.net.URI

internal fun interface SyncEventLogger {
  fun log(message: String)
}

internal object NoOpSyncEventLogger : SyncEventLogger {
  override fun log(message: String) = Unit
}

internal object AndroidSyncEventLogger : SyncEventLogger {
  private const val TAG = "ClipDockSync"

  override fun log(message: String) {
    Log.d(TAG, message)
  }
}

internal fun String.toSyncLogServerLabel(): String =
  runCatching {
    val uri = URI(this)
    val scheme = uri.scheme?.takeIf { it.isNotBlank() } ?: "unknown"
    val host = uri.host?.takeIf { it.isNotBlank() } ?: "unknown"
    val port = if (uri.port >= 0) ":${uri.port}" else ""
    "$scheme://$host$port"
  }.getOrElse { "invalid_server_url" }

internal fun Throwable.toSyncLogErrorLabel(): String =
  javaClass.simpleName.takeIf { it.isNotBlank() } ?: "Throwable"
