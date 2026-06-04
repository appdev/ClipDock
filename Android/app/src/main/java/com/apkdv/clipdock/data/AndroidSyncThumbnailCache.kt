package com.apkdv.clipdock.data

import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.util.Locale

class AndroidSyncThumbnailCache(
  private val api: ClipDockRawAssetApi,
  private val filesDir: File,
) : SyncThumbnailCache {
  override suspend fun cacheThumbnail(serverUrl: String, token: String, item: ClipHistoryItem): String? {
    val digest = item.thumbnailDigest?.takeIf(::isCanonicalBlake3Digest) ?: return null
    val mimeType = item.thumbnailMimeType?.lowercase(Locale.US)?.substringBefore(';') ?: return null
    val byteCount = item.thumbnailByteCount?.takeIf { it > 0 } ?: return null
    val width = item.thumbnailWidth?.takeIf { it > 0 } ?: return null
    val height = item.thumbnailHeight?.takeIf { it > 0 } ?: return null
    val asset = runCatching { api.downloadAsset(serverUrl, token, digest) }.getOrNull() ?: return null
    if (asset.kind != "thumbnail") return null
    if (asset.contentType?.lowercase(Locale.US) != mimeType) return null
    if (asset.byteCount != byteCount || asset.bytes.size.toLong() != byteCount) return null
    if (asset.width != width || asset.height != height) return null
    if (canonicalBlake3Digest(asset.bytes) != digest) return null
    if (!decodedImageMatches(asset.bytes, mimeType, width, height)) return null

    val hex = digest.removePrefix("blake3:")
    val extension = extensionForMimeType(mimeType)
    val directory = File(filesDir, "clipdock-thumbnails/${hex.take(2)}")
    val finalFile = File(directory, "$hex.$extension")
    val stagingFile = File(directory, "$hex.tmp")
    return runCatching {
      directory.mkdirs()
      stagingFile.writeBytes(asset.bytes)
      if (finalFile.exists()) finalFile.delete()
      check(stagingFile.renameTo(finalFile))
      Uri.fromFile(finalFile).toString()
    }.getOrNull()
  }

  private fun decodedImageMatches(bytes: ByteArray, mimeType: String, width: Int, height: Int): Boolean {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    val decodedMime = options.outMimeType?.lowercase(Locale.US)
    return options.outWidth == width &&
      options.outHeight == height &&
      decodedMime == mimeType
  }

  private fun extensionForMimeType(mimeType: String): String =
    when (mimeType) {
      "image/png" -> "png"
      "image/jpeg" -> "jpg"
      "image/webp" -> "webp"
      else -> "img"
    }
}
