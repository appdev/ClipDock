package com.apkdv.clipdock.data

import android.content.Context
import android.net.Uri
import java.io.File
import java.net.URL
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

internal data class AndroidResolvedLinkMetadata(
  val iconUri: String?,
  val previewUri: String?,
  val siteName: String?,
  val title: String?,
)

internal class AndroidLinkMetadataResolver(
  context: Context,
  private val httpClient: OkHttpClient =
    OkHttpClient.Builder()
      .connectTimeout(5, TimeUnit.SECONDS)
      .readTimeout(10, TimeUnit.SECONDS)
      .followRedirects(true)
      .followSslRedirects(true)
      .build(),
) {
  private val appContext = context.applicationContext

  suspend fun resolve(item: ClipHistoryItem): AndroidResolvedLinkMetadata? =
    withContext(Dispatchers.IO) {
      if (item.type != ClipItemType.Link) return@withContext null
      val pageUrl = item.linkURL() ?: return@withContext null
      if (!isSupportedPublicURL(pageUrl)) return@withContext null
      val html = fetchHTML(pageUrl) ?: return@withContext null
      val document = Jsoup.parse(html, pageUrl)
      val siteName = document.metaContent("og:site_name")
      val title = document.metaContent("og:title") ?: document.title().trim().takeIf(String::isNotBlank)
      val iconUri =
        item.linkIconUri?.takeIf(::isLocalImageUri)
          ?: downloadFirstImage(document.iconCandidates(pageUrl), "icon", maxBytes = MAX_ICON_BYTES)
      val previewUri =
        item.linkPreviewUri?.takeIf(::isLocalImageUri)
          ?: downloadFirstImage(document.previewCandidates(pageUrl), "preview", maxBytes = MAX_PREVIEW_BYTES)
      AndroidResolvedLinkMetadata(
        iconUri = iconUri,
        previewUri = previewUri,
        siteName = siteName,
        title = title,
      ).takeIf { it.iconUri != null || it.previewUri != null || it.siteName != null || it.title != null }
    }

  private fun fetchHTML(pageUrl: String): String? {
    val request =
      Request.Builder()
        .url(pageUrl)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("User-Agent", USER_AGENT)
        .build()
    return runCatching {
      httpClient.newCall(request).execute().use { response ->
        if (!response.isSuccessful) return null
        val body = response.body
        val contentType = body.contentType()
        val mimeType = contentType?.let { "${it.type}/${it.subtype}".lowercase(Locale.US) }
        if (contentType != null && mimeType !in HTML_MIME_TYPES) return null
        if (body.contentLength() > MAX_HTML_BYTES) return null
        val bytes = body.bytes()
        if (bytes.size > MAX_HTML_BYTES) return null
        val charset = contentType?.charset(Charsets.UTF_8) ?: Charsets.UTF_8
        bytes.toString(charset)
      }
    }.getOrNull()
  }

  private fun downloadFirstImage(candidates: List<String>, kind: String, maxBytes: Int): String? {
    for (candidate in candidates) {
      if (!isSupportedPublicURL(candidate)) continue
      val cached = downloadImage(candidate, kind, maxBytes)
      if (cached != null) return cached
    }
    return null
  }

  private fun downloadImage(url: String, kind: String, maxBytes: Int): String? {
    val request =
      Request.Builder()
        .url(url)
        .header("Accept", "image/avif,image/webp,image/png,image/jpeg,image/gif,image/x-icon,*/*;q=0.4")
        .header("User-Agent", USER_AGENT)
        .build()
    return runCatching {
      httpClient.newCall(request).execute().use { response ->
        if (!response.isSuccessful) return null
        val body = response.body
        val mimeType = body.contentType()?.let { "${it.type}/${it.subtype}".lowercase(Locale.US) }
        if (mimeType != null && !mimeType.startsWith("image/")) return null
        if (mimeType == "image/svg+xml") return null
        if (body.contentLength() > maxBytes) return null
        val bytes = body.bytes()
        if (bytes.isEmpty() || bytes.size > maxBytes) return null
        val extension = imageExtension(mimeType, url)
        val digest = canonicalBlake3Digest((url + "\n" + kind).toByteArray(Charsets.UTF_8)).removePrefix("blake3:")
        val directory = File(appContext.filesDir, "link-metadata/$kind")
        directory.mkdirs()
        val file = File(directory, "$digest.$extension")
        writeBytesAtomically(file, bytes)
        Uri.fromFile(file).toString()
      }
    }.getOrNull()
  }

  private fun Document.previewCandidates(pageUrl: String): List<String> =
    listOf(
      metaContent("og:image"),
      metaContent("og:image:url"),
      metaContent("twitter:image"),
      metaContent("twitter:image:src"),
    ).mapNotNull { it?.resolveAgainst(pageUrl) }.distinct()

  private fun Document.iconCandidates(pageUrl: String): List<String> {
    val declared =
      select("link[rel]").mapNotNull { element ->
        val rel = element.attr("rel").lowercase(Locale.US)
        if (!rel.contains("icon")) return@mapNotNull null
        element.attr("href").takeIf(String::isNotBlank)?.resolveAgainst(pageUrl)
      }
    return (declared + listOf("/favicon.ico".resolveAgainst(pageUrl), "/favicon.png".resolveAgainst(pageUrl)))
      .filterNotNull()
      .distinct()
  }

  private fun Document.metaContent(name: String): String? =
    selectFirst("meta[property='$name'], meta[name='$name']")
      ?.attr("content")
      ?.trim()
      ?.takeIf(String::isNotBlank)

  private fun String.resolveAgainst(baseUrl: String): String? =
    runCatching { URL(URL(baseUrl), this).toURI().normalize().toURL().toString() }.getOrNull()

  private fun ClipHistoryItem.linkURL(): String? =
    listOf(body, title)
      .map(String::trim)
      .mapNotNull { value ->
        when {
          value.startsWith("https://", ignoreCase = true) || value.startsWith("http://", ignoreCase = true) -> value
          value.looksLikeSchemeLessPublicURL() -> "https://$value"
          else -> null
        }
      }
      .firstOrNull()

  private fun isLocalImageUri(value: String): Boolean =
    value.startsWith("file://") || value.startsWith("content://")

  private fun isSupportedPublicURL(value: String): Boolean {
    val url = runCatching { URL(value) }.getOrNull() ?: return false
    val scheme = url.protocol.lowercase(Locale.US)
    if (scheme != "http" && scheme != "https") return false
    val host = url.host.lowercase(Locale.US).trim('[', ']')
    if (host.isBlank() || host == "localhost" || host.endsWith(".local")) return false
    if (host == "::1" || host.startsWith("fc") || host.startsWith("fd") || host.startsWith("fe80")) return false
    val octets = host.split('.').mapNotNull { it.toIntOrNull() }
    if (octets.size == 4) {
      if (octets[0] == 10 || octets[0] == 127 || octets[0] == 0) return false
      if (octets[0] == 192 && octets[1] == 168) return false
      if (octets[0] == 172 && octets[1] in 16..31) return false
      if (octets[0] == 169 && octets[1] == 254) return false
    }
    return true
  }

  private fun imageExtension(mimeType: String?, url: String): String {
    val fromUrl = url.substringBefore('?').substringAfterLast('.', "").lowercase(Locale.US)
    if (fromUrl in setOf("png", "jpg", "jpeg", "webp", "gif", "ico")) return fromUrl
    return when (mimeType) {
      "image/png" -> "png"
      "image/jpeg" -> "jpg"
      "image/webp" -> "webp"
      "image/gif" -> "gif"
      "image/x-icon",
      "image/vnd.microsoft.icon" -> "ico"
      else -> "img"
    }
  }

  private fun String.looksLikeSchemeLessPublicURL(): Boolean {
    if (isBlank() || any(Char::isWhitespace) || contains("://")) return false
    val host = substringBefore('/').substringBefore('?').substringBefore('#')
    return host.contains('.') && host.any(Char::isLetter)
  }

  private fun writeBytesAtomically(file: File, bytes: ByteArray) {
    file.parentFile?.mkdirs()
    val temp = File(file.parentFile, "${file.name}.tmp")
    temp.writeBytes(bytes)
    if (!temp.renameTo(file)) {
      temp.delete()
      error("Unable to move ${temp.name} into link metadata cache")
    }
  }

  private companion object {
    const val MAX_HTML_BYTES = 1_048_576
    const val MAX_ICON_BYTES = 512 * 1_024
    const val MAX_PREVIEW_BYTES = 2 * 1_024 * 1_024
    const val USER_AGENT = "ClipDock-Android/1.0 LinkPreview"
    val HTML_MIME_TYPES = setOf("text/html", "application/xhtml+xml")
  }
}
