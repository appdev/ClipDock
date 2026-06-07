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
  private val upload: suspend (ClipData, Long) -> LocalSyncPushResult?,
  private val logger: SyncEventLogger = AndroidSyncEventLogger,
) {
  private val appContext = context.applicationContext
  private val clipboard = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
  private val preferences = appContext.getSharedPreferences("clipdock", Context.MODE_PRIVATE)
  private var started = false
  private val captureLock = Any()
  private val inFlightSignatureDigests = mutableSetOf<String>()
  private val listener = ClipboardManager.OnPrimaryClipChangedListener { capturePrimaryClip(trigger = "listener") }

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

  fun captureCurrentPrimaryClip() {
    capturePrimaryClip(trigger = "foreground")
  }

  fun ignoreSelfCopy(clip: ClipData) {
    persistLastSuccessfulSignatureDigest(clip.captureSignatureDigest())
  }

  private fun capturePrimaryClip(trigger: String) {
    val clip =
      runCatching { clipboard.primaryClip }
        .onFailure { logger.log("local_clipboard_capture_read_failed trigger=$trigger error=${it.toSyncLogErrorLabel()}") }
        .getOrNull()
        ?: run {
          logger.log("local_clipboard_capture_ignored trigger=$trigger reason=empty_clip")
          return
        }
    if (clip.description.isClipDockSelfCopy()) {
      logger.log("local_clipboard_capture_ignored trigger=$trigger reason=self_copy")
      return
    }
    val signatureDigest = clip.captureSignatureDigest()
    synchronized(captureLock) {
      when {
        signatureDigest == lastSuccessfulSignatureDigest() -> {
          logger.log("local_clipboard_capture_ignored trigger=$trigger reason=duplicate")
          return
        }
        !inFlightSignatureDigests.add(signatureDigest) -> {
          logger.log("local_clipboard_capture_ignored trigger=$trigger reason=in_flight")
          return
        }
      }
    }
    val copiedAtMillis = System.currentTimeMillis()
    logger.log("local_clipboard_capture_upload_start trigger=$trigger")
    scope.launch {
      try {
        val result = upload(clip, copiedAtMillis)
        if (result == null) {
          logger.log("local_clipboard_capture_ignored trigger=$trigger reason=unsupported_clip")
        } else {
          persistLastSuccessfulSignatureDigest(signatureDigest)
          logger.log("local_clipboard_capture_upload_success trigger=$trigger content_hash=${result.contentHash}")
        }
      } catch (throwable: Throwable) {
        logger.log("local_clipboard_capture_upload_failed trigger=$trigger error=${throwable.toSyncLogErrorLabel()}")
      } finally {
        synchronized(captureLock) {
          inFlightSignatureDigests.remove(signatureDigest)
        }
      }
    }
  }

  private fun lastSuccessfulSignatureDigest(): String? =
    preferences.getString(KEY_LAST_LOCAL_CLIPBOARD_SIGNATURE_DIGEST, null)

  private fun persistLastSuccessfulSignatureDigest(signatureDigest: String) {
    preferences.edit().putString(KEY_LAST_LOCAL_CLIPBOARD_SIGNATURE_DIGEST, signatureDigest).commit()
  }
}

private fun ClipData.captureSignatureDigest(): String =
  canonicalBlake3Digest(captureSignature().toByteArray(Charsets.UTF_8))

private fun ClipData.captureSignature(): String {
  val firstItem = if (itemCount > 0) getItemAt(0) else null
  val mimeTypes = (0 until description.mimeTypeCount).joinToString("|") { description.getMimeType(it) }
  return listOf(
    itemCount.toString(),
    mimeTypes,
    firstItem?.text?.toString().orEmpty(),
    firstItem?.htmlText.orEmpty(),
    firstItem?.uri?.toString().orEmpty(),
    firstItem?.intent?.toUri(0).orEmpty(),
  ).joinToString("\u001f")
}

private const val KEY_LAST_LOCAL_CLIPBOARD_SIGNATURE_DIGEST = "lastLocalClipboardSignatureDigest"

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
}

private fun classifyLocalClipboardText(text: String): ClipItemType =
  when {
    text.matches(Regex("^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")) -> ClipItemType.Color
    text.startsWith("http://") || text.startsWith("https://") -> ClipItemType.Link
    else -> ClipItemType.Text
  }
