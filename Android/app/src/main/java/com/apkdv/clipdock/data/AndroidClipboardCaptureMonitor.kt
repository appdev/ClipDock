package com.apkdv.clipdock.data

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

internal const val CLIPDOCK_CLIP_EXTRA_SOURCE = "com.apkdv.clipdock.SOURCE"
internal const val CLIPDOCK_CLIP_EXTRA_CONTENT_HASH = "com.apkdv.clipdock.CONTENT_HASH"
internal const val CLIPDOCK_CLIP_SOURCE = "clipdock"

internal class AndroidClipboardCaptureMonitor(
  context: Context,
  private val scope: CoroutineScope,
  private val upload: suspend (ClipHistoryItem) -> LocalSyncPushResult,
  private val logger: SyncEventLogger = AndroidSyncEventLogger,
) {
  private val clipboard = context.applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
  private var started = false
  private val listener = ClipboardManager.OnPrimaryClipChangedListener { capturePrimaryClip() }

  fun start() {
    if (started) return
    started = true
    clipboard.addPrimaryClipChangedListener(listener)
    logger.log("local_clipboard_capture_started")
  }

  fun stop() {
    if (!started) return
    started = false
    clipboard.removePrimaryClipChangedListener(listener)
    logger.log("local_clipboard_capture_stopped")
  }

  private fun capturePrimaryClip() {
    val clip =
      runCatching { clipboard.primaryClip }
        .onFailure { logger.log("local_clipboard_capture_read_failed error=${it.toSyncLogErrorLabel()}") }
        .getOrNull()
        ?: return
    if (clip.description.isClipDockSelfCopy()) {
      logger.log("local_clipboard_capture_ignored reason=self_copy")
      return
    }
    val item = clip.toLocalClipboardHistoryItem(System.currentTimeMillis())
    if (item == null) {
      logger.log("local_clipboard_capture_ignored reason=unsupported_clip")
      return
    }
    logger.log("local_clipboard_capture_upload_start type=${item.type.wireName}")
    scope.launch {
      runCatching { upload(item) }
        .onSuccess { result ->
          logger.log("local_clipboard_capture_upload_success content_hash=${result.contentHash}")
        }
        .onFailure { throwable ->
          logger.log("local_clipboard_capture_upload_failed error=${throwable.toSyncLogErrorLabel()}")
        }
    }
  }
}

internal fun ClipDescription.isClipDockSelfCopy(): Boolean =
  extras?.getString(CLIPDOCK_CLIP_EXTRA_SOURCE) == CLIPDOCK_CLIP_SOURCE ||
    !extras?.getString(CLIPDOCK_CLIP_EXTRA_CONTENT_HASH).isNullOrBlank()

internal fun ClipData.toLocalClipboardHistoryItem(copiedAtMillis: Long): ClipHistoryItem? {
  val firstItem = if (itemCount > 0) getItemAt(0) else null
  val text = firstItem?.text?.toString()?.takeIf(String::isNotBlank)
  val uri = firstItem?.uri?.toString()?.takeIf { it.startsWith("http://") || it.startsWith("https://") }
  return localClipboardTextItem(text ?: uri, copiedAtMillis)
}

internal fun localClipboardTextItem(rawText: String?, copiedAtMillis: Long): ClipHistoryItem? {
  val normalizedText = rawText?.trim()?.takeIf(String::isNotBlank) ?: return null
  val itemType = classifyLocalClipboardText(normalizedText)
  return ClipHistoryItem(
    stableId = "local-android-clipboard-$copiedAtMillis",
    contentHash = "",
    type = itemType,
    title = normalizedText.lineSequence().firstOrNull()?.take(80).orEmpty(),
    body = normalizedText,
    detail = itemType.label,
    sourceName = "Android",
    assetId = null,
    thumbnailUri = null,
    localUri = null,
    payloadState = PayloadState.Ready,
    transferState = TransferState.Ready,
    copiedAtMillis = copiedAtMillis,
    copyCount = 1,
  )
}

private fun classifyLocalClipboardText(text: String): ClipItemType =
  when {
    text.matches(Regex("^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")) -> ClipItemType.Color
    text.startsWith("http://") || text.startsWith("https://") -> ClipItemType.Link
    else -> ClipItemType.Text
  }
