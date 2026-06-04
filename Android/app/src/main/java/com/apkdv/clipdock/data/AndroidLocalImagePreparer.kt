package com.apkdv.clipdock.data

import android.content.ClipData
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.apkdv.clipdock.p2p.NativeP2pTransport
import java.io.File
import java.util.Locale

internal const val SYNC_THUMBNAIL_MIME_TYPE = "image/webp"
internal const val SYNC_THUMBNAIL_NORMAL_TARGET_BYTES = 262_144
internal const val SYNC_THUMBNAIL_DETAIL_TARGET_BYTES = 393_216
internal const val SYNC_THUMBNAIL_MAX_BYTES = 786_432
private const val MAX_IMAGE_DIMENSION = 8192
private const val MAX_IMAGE_PIXELS = 16_777_216

internal data class AndroidPreparedLocalImage(
  val item: ClipHistoryItem,
  val payloadFile: File,
  val payloadMimeType: String,
  val payloadByteCount: Long,
  val width: Int,
  val height: Int,
  val thumbnail: AndroidPreparedSyncThumbnail?,
)

internal data class AndroidPreparedSyncThumbnail(
  val bytes: ByteArray,
  val digest: String,
  val mimeType: String,
  val byteCount: Long,
  val width: Int,
  val height: Int,
  val localUri: String,
) {
  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (other !is AndroidPreparedSyncThumbnail) return false
    return bytes.contentEquals(other.bytes) &&
      digest == other.digest &&
      mimeType == other.mimeType &&
      byteCount == other.byteCount &&
      width == other.width &&
      height == other.height &&
      localUri == other.localUri
  }

  override fun hashCode(): Int {
    var result = bytes.contentHashCode()
    result = 31 * result + digest.hashCode()
    result = 31 * result + mimeType.hashCode()
    result = 31 * result + byteCount.hashCode()
    result = 31 * result + width
    result = 31 * result + height
    result = 31 * result + localUri.hashCode()
    return result
  }
}

internal class AndroidLocalImagePreparer(
  context: Context,
  private val nativeTransport: NativeP2pTransport,
) {
  private val appContext = context.applicationContext
  private val resolver = appContext.contentResolver

  suspend fun prepare(clip: ClipData, copiedAtMillis: Long): AndroidPreparedLocalImage? {
    val imageUri = clip.firstImageUri(appContext) ?: return null
    val payloadBytes = resolver.openInputStream(imageUri)?.use { it.readBytes() } ?: return null
    if (payloadBytes.isEmpty()) return null
    val payloadDigest = canonicalBlake3Digest(payloadBytes)
    val payloadHex = payloadDigest.removePrefix("blake3:")
    val decoded = decodeImage(payloadBytes) ?: return null
    validateImageBounds(decoded.width, decoded.height) ?: return null
    val payloadMimeType = decoded.mimeType ?: imageUri.mimeType(appContext) ?: "image/png"
    val payloadExtension = extensionForMimeType(payloadMimeType)
    val payloadFile = File(appContext.filesDir, "p2p-payloads/android-captures/$payloadHex.$payloadExtension")
    payloadFile.writeBytesAtomically(payloadBytes)

    val thumbnail =
      runCatching {
        val rgba = decoded.bitmap.toRgbaBytes()
        val encoded =
          nativeTransport.encodeAdaptiveThumbnailWebp(
            rgba = rgba,
            width = decoded.width,
            height = decoded.height,
            normalTargetBytes = SYNC_THUMBNAIL_NORMAL_TARGET_BYTES,
            detailTargetBytes = SYNC_THUMBNAIL_DETAIL_TARGET_BYTES,
            maxBytes = SYNC_THUMBNAIL_MAX_BYTES,
          )
        val thumbnailDigest = canonicalBlake3Digest(encoded.bytes)
        val thumbnailHex = thumbnailDigest.removePrefix("blake3:")
        val thumbnailFile = File(appContext.filesDir, "clipdock-thumbnails/local-upload/$thumbnailHex.webp")
        thumbnailFile.writeBytesAtomically(encoded.bytes)
        AndroidPreparedSyncThumbnail(
          bytes = encoded.bytes,
          digest = thumbnailDigest,
          mimeType = SYNC_THUMBNAIL_MIME_TYPE,
          byteCount = encoded.bytes.size.toLong(),
          width = encoded.width,
          height = encoded.height,
          localUri = Uri.fromFile(thumbnailFile).toString(),
        )
      }.getOrNull()
    decoded.bitmap.recycle()

    val fileName = imageUri.displayName(appContext) ?: "android-image-$payloadHex.$payloadExtension"
    val payloadUri =
      FileProvider
        .getUriForFile(appContext, "${appContext.packageName}.files", payloadFile)
        .toString()
    val item =
      ClipHistoryItem(
        stableId = payloadDigest,
        contentHash = payloadDigest,
        type = ClipItemType.Image,
        title = fileName,
        body = payloadMimeType,
        detail = "${payloadBytes.size} bytes",
        sourceName = "Android",
        assetId = null,
        thumbnailUri = thumbnail?.localUri,
        thumbnailDigest = thumbnail?.digest,
        thumbnailMimeType = thumbnail?.mimeType,
        thumbnailByteCount = thumbnail?.byteCount,
        thumbnailWidth = thumbnail?.width,
        thumbnailHeight = thumbnail?.height,
        localUri = payloadUri,
        payloadState = PayloadState.Ready,
        transferState = TransferState.Ready,
        copiedAtMillis = copiedAtMillis,
        copyCount = 1,
      )
    return AndroidPreparedLocalImage(
      item = item,
      payloadFile = payloadFile,
      payloadMimeType = payloadMimeType,
      payloadByteCount = payloadBytes.size.toLong(),
      width = decoded.width,
      height = decoded.height,
      thumbnail = thumbnail,
    )
  }

  private fun decodeImage(bytes: ByteArray): DecodedAndroidImage? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    val width = bounds.outWidth
    val height = bounds.outHeight
    validateImageBounds(width, height) ?: return null
    val bitmap =
      BitmapFactory.decodeByteArray(
        bytes,
        0,
        bytes.size,
        BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 },
      ) ?: return null
    val rgbaBitmap =
      if (bitmap.config == Bitmap.Config.ARGB_8888) {
        bitmap
      } else {
        bitmap.copy(Bitmap.Config.ARGB_8888, false).also { bitmap.recycle() }
      }
    return DecodedAndroidImage(
      bitmap = rgbaBitmap,
      width = rgbaBitmap.width,
      height = rgbaBitmap.height,
      mimeType = bounds.outMimeType?.lowercase(Locale.US),
    )
  }

  private data class DecodedAndroidImage(
    val bitmap: Bitmap,
    val width: Int,
    val height: Int,
    val mimeType: String?,
  )

}

private fun ClipData.firstImageUri(context: Context): Uri? {
  val description = description
  for (index in 0 until itemCount) {
    val uri = getItemAt(index).uri ?: continue
    val mimeType = uri.mimeType(context)
    if (mimeType?.startsWith("image/") == true || description.hasMimeType("image/*")) {
      return uri
    }
  }
  return null
}

private fun Uri.mimeType(context: Context): String? =
  context.contentResolver.getType(this)?.substringBefore(';')?.trim()?.lowercase(Locale.US)

private fun Uri.displayName(context: Context): String? =
  runCatching {
    context.contentResolver.query(this, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
      ?.use { cursor ->
        if (cursor.moveToFirst()) {
          cursor.getString(0)?.takeIf(String::isNotBlank)
        } else {
          null
        }
      }
  }.getOrNull() ?: lastPathSegment?.substringAfterLast('/')?.takeIf(String::isNotBlank)

private fun validateImageBounds(width: Int, height: Int): Unit? {
  if (width !in 1..MAX_IMAGE_DIMENSION) return null
  if (height !in 1..MAX_IMAGE_DIMENSION) return null
  if (width.toLong() * height.toLong() > MAX_IMAGE_PIXELS) return null
  return Unit
}

private fun Bitmap.toRgbaBytes(): ByteArray {
  val pixels = IntArray(width * height)
  getPixels(pixels, 0, width, 0, 0, width, height)
  val rgba = ByteArray(pixels.size * 4)
  pixels.forEachIndexed { index, pixel ->
    val output = index * 4
    rgba[output] = ((pixel ushr 16) and 0xff).toByte()
    rgba[output + 1] = ((pixel ushr 8) and 0xff).toByte()
    rgba[output + 2] = (pixel and 0xff).toByte()
    rgba[output + 3] = ((pixel ushr 24) and 0xff).toByte()
  }
  return rgba
}

private fun File.writeBytesAtomically(bytes: ByteArray) {
  parentFile?.mkdirs()
  val staging = File(parentFile, "$name.tmp")
  staging.writeBytes(bytes)
  if (exists()) delete()
  check(staging.renameTo(this))
}

private fun extensionForMimeType(mimeType: String): String =
  MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
    ?.takeIf { it.length in 1..8 && it.all(Char::isLetterOrDigit) }
    ?: when (mimeType) {
      "image/png" -> "png"
      "image/jpeg" -> "jpg"
      "image/webp" -> "webp"
      else -> "img"
    }
