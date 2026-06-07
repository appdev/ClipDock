package com.apkdv.clipdock.ui.main

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.webkit.GeolocationPermissions
import android.webkit.SafeBrowsingResponse
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewCompat
import java.io.ByteArrayInputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

internal const val CLIPDOCK_WEB_ASSET_ORIGIN = "https://appassets.androidplatform.net"
internal const val CLIPDOCK_WEB_ASSET_PREFIX = "/assets/clipdock-mobile-v4"
internal const val CLIPDOCK_WEB_ENTRY_URL =
  "$CLIPDOCK_WEB_ASSET_ORIGIN$CLIPDOCK_WEB_ASSET_PREFIX/index.html"

@SuppressLint("SetJavaScriptEnabled")
@Composable
internal fun ClipDockWebSurface(
  screenId: String,
  theme: String? = null,
  selectedStableId: String? = null,
  stateJson: String,
  bridge: ClipDockWebBridge,
  onBackFromWeb: () -> Unit,
  modifier: Modifier = Modifier,
  onWebViewCreated: (WebView) -> Unit = {},
) {
  val scope = remember { CoroutineScope(Dispatchers.Main.immediate) }
  val webViewHolder = remember { arrayOfNulls<WebView>(1) }
  val url = remember(screenId, theme, selectedStableId) { clipDockWebEntryUrl(screenId, theme, selectedStableId) }
  BackHandler(enabled = screenId in setOf("item_detail_text", "remote_asset_sheet", "delete_confirm", "keep_alive", "floating_ball")) {
    val webView = webViewHolder[0]
    if (webView == null) {
      onBackFromWeb()
      return@BackHandler
    }
    webView.evaluateJavascript("Boolean(window.__clipdockBack && window.__clipdockBack())") { result ->
      if (result != "true") {
        onBackFromWeb()
      }
    }
  }
  AndroidView(
    modifier = modifier,
    factory = { context ->
      WebView(context).apply {
        configureClipDockWebView()
        val assetLoader =
          WebViewAssetLoader.Builder()
            .setDomain("appassets.androidplatform.net")
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
            .build()
        webViewClient = ClipDockWebViewClient(assetLoader)
        webChromeClient = ClipDockWebChromeClient()
        setDownloadListener { _, _, _, _, _ -> }
        WebViewCompat.addWebMessageListener(
          this,
          "clipdockBridge",
          setOf(CLIPDOCK_WEB_ASSET_ORIGIN),
        ) { _: WebView, message: WebMessageCompat, _: Uri, _: Boolean, replyProxy: JavaScriptReplyProxy ->
          scope.launch {
            val result = bridge.handle(message.data)
            val resultJson = clipDockWebJson.encodeToString(ClipDockWebResult.serializer(), result)
            replyProxy.postMessage(resultJson)
            post {
              evaluateJavascript("window.__clipdockReceiveBridgeResult && window.__clipdockReceiveBridgeResult(${JSONObject.quote(resultJson)})", null)
            }
          }
        }
        webViewHolder[0] = this
        onWebViewCreated(this)
        loadUrl(url)
      }
    },
    update = { webView ->
      if (webView.url?.substringBefore("#") != url) {
        webView.loadUrl(url)
      }
      webView.evaluateJavascript("window.__clipdockApplyNativeState && window.__clipdockApplyNativeState($stateJson)", null)
    },
  )
  LaunchedEffect(stateJson) {
    webViewHolder[0]?.evaluateJavascript("window.__clipdockApplyNativeState && window.__clipdockApplyNativeState($stateJson)", null)
  }
  DisposableEffect(Unit) {
    onDispose {
      webViewHolder[0]?.destroy()
      webViewHolder[0] = null
    }
  }
}

internal fun clipDockWebEntryUrl(
  screenId: String,
  theme: String? = null,
  selectedStableId: String? = null,
): String {
  val query =
    buildList {
      add("screen_id=${Uri.encode(screenId)}")
      theme?.takeIf { it == "light" || it == "dark" }?.let { add("theme=$it") }
      selectedStableId?.takeIf { it.isNotBlank() }?.let { add("selected_stable_id=${Uri.encode(it)}") }
    }.joinToString("&")
  return "$CLIPDOCK_WEB_ENTRY_URL?$query"
}

@SuppressLint("SetJavaScriptEnabled")
internal fun WebView.configureClipDockWebView() {
  settings.javaScriptEnabled = true
  settings.domStorageEnabled = false
  settings.databaseEnabled = false
  settings.allowFileAccess = false
  settings.allowContentAccess = false
  settings.allowFileAccessFromFileURLs = false
  settings.allowUniversalAccessFromFileURLs = false
  settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
  settings.safeBrowsingEnabled = true
  settings.textZoom = 100
  settings.javaScriptCanOpenWindowsAutomatically = false
  settings.setSupportMultipleWindows(false)
  settings.mediaPlaybackRequiresUserGesture = true
  settings.cacheMode = WebSettings.LOAD_NO_CACHE
  clearCache(true)
  isVerticalScrollBarEnabled = false
  isHorizontalScrollBarEnabled = false
}

internal class ClipDockWebViewClient(
  private val assetLoader: WebViewAssetLoader,
) : WebViewClient() {
  override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
    !isAllowedClipDockAsset(request.url)

  @Deprecated("Deprecated in Android framework")
  override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
    !isAllowedClipDockAsset(Uri.parse(url))

  override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
    val uri = request.url
    if (!isAllowedClipDockAsset(uri)) {
      return blockedResponse()
    }
    return assetLoader.shouldInterceptRequest(uri)
  }

  override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
    if (url != null && !isAllowedClipDockAsset(Uri.parse(url))) {
      view.stopLoading()
    }
  }

  override fun onSafeBrowsingHit(
    view: WebView,
    request: WebResourceRequest,
    threatType: Int,
    callback: SafeBrowsingResponse,
  ) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      callback.backToSafety(true)
    }
  }
}

internal class ClipDockWebChromeClient : WebChromeClient() {
  override fun onCreateWindow(
    view: WebView?,
    isDialog: Boolean,
    isUserGesture: Boolean,
    resultMsg: android.os.Message?,
  ): Boolean = false

  override fun onGeolocationPermissionsShowPrompt(
    origin: String?,
    callback: GeolocationPermissions.Callback?,
  ) {
    callback?.invoke(origin, false, false)
  }

  override fun onShowFileChooser(
    webView: WebView?,
    filePathCallback: ValueCallback<Array<Uri>>?,
    fileChooserParams: FileChooserParams?,
  ): Boolean {
    filePathCallback?.onReceiveValue(emptyArray())
    return true
  }
}

internal fun isAllowedClipDockAsset(uri: Uri): Boolean =
  uri.scheme == "https" &&
    uri.host == "appassets.androidplatform.net" &&
    (uri.encodedPath == CLIPDOCK_WEB_ASSET_PREFIX || uri.encodedPath.orEmpty().startsWith("$CLIPDOCK_WEB_ASSET_PREFIX/"))

private fun blockedResponse(): WebResourceResponse =
  WebResourceResponse(
    "text/plain",
    "UTF-8",
    403,
    "Forbidden",
    mapOf("Cache-Control" to "no-store"),
    ByteArrayInputStream(ByteArray(0)),
  )
