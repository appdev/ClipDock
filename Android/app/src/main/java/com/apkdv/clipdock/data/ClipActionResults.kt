package com.apkdv.clipdock.data

sealed interface RemoteAssetActionResult {
  data class Copied(val item: ClipHistoryItem) : RemoteAssetActionResult
  data class Cached(val item: ClipHistoryItem) : RemoteAssetActionResult
  data class ThumbnailCopied(val item: ClipHistoryItem) : RemoteAssetActionResult
  data class Failed(val item: ClipHistoryItem?, val message: String) : RemoteAssetActionResult
}

sealed interface DeleteRecordResult {
  data class Deleted(
    val item: ClipHistoryItem,
    val clientEventId: String,
    val nextCursor: Long,
    val serverSeq: Long?,
  ) : DeleteRecordResult

  data class Failed(val item: ClipHistoryItem?, val message: String) : DeleteRecordResult
}

sealed interface LocalCacheRemovalResult {
  data class Removed(
    val item: ClipHistoryItem,
    val providerDeleteMessage: String?,
  ) : LocalCacheRemovalResult

  data class Failed(val item: ClipHistoryItem?, val message: String) : LocalCacheRemovalResult
}

internal fun stableAndroidDeleteEventId(
  deviceId: String,
  contentHash: String,
  requestedAtMillis: Long,
): String {
  val hashPart = contentHash.removePrefix("blake3:").ifBlank { contentHash }
  return "android-delete:$deviceId:$hashPart:$requestedAtMillis"
}
