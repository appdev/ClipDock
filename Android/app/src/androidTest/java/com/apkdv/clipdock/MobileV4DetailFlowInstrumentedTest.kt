package com.apkdv.clipdock

import android.net.Uri
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.qa.MobileV4InteractionQaActivity
import com.apkdv.clipdock.qa.MobileV4QaFixtures
import com.apkdv.clipdock.ui.main.isAllowedClipDockAsset
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject

@RunWith(AndroidJUnit4::class)
class MobileV4DetailFlowInstrumentedTest {
  @get:Rule val activityRule = ActivityScenarioRule(MobileV4InteractionQaActivity::class.java)

  @Test
  fun hostLaunchesProductionWebViewRoute() {
    lateinit var webView: WebView
    activityRule.scenario.onActivity { activity ->
      webView = activity.webView
      assertEquals(0, activity.useCount)
    }
    waitForScreen(webView)
    assertTrue(evalBoolean(webView, "location.href.includes('/assets/clipdock-mobile-v4/index.html')"))
    assertTrue(evalBoolean(webView, "Boolean(document.querySelector('.clipdock-visual-layer'))"))
  }

  @Test
  fun bridgeFakeDispatcherReceivesEveryDomainAction() {
    lateinit var webView: WebView
    activityRule.scenario.onActivity { activity ->
      webView = activity.webView
    }
    waitForScreen(webView)
    tapHotzone(webView, "openItemDetail:${MobileV4QaFixtures.READY_TEXT_ID}")
    assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'item_detail_text' && Boolean(document.querySelector('[data-action-id=\"copyItem:${MobileV4QaFixtures.READY_TEXT_ID}\"]'))"))
    tapHotzone(webView, "copyItem:${MobileV4QaFixtures.READY_TEXT_ID}")
    activityRule.scenario.onActivity { activity ->
      assertEquals(1, activity.copyCount)
      assertEquals(MobileV4QaFixtures.READY_TEXT_ID, activity.lastActionStableId)
    }

    eval(webView, "window.__clipdockQaRender('remote_asset_sheet', undefined, '${MobileV4QaFixtures.REMOTE_IMAGE_ID}')")
    assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'remote_asset_sheet' && Boolean(document.querySelector('[data-action-id=\"downloadAndCopy:${MobileV4QaFixtures.REMOTE_IMAGE_ID}\"]'))"))
    tapHotzone(webView, "downloadAndCopy:${MobileV4QaFixtures.REMOTE_IMAGE_ID}")
    tapHotzone(webView, "downloadToCache:${MobileV4QaFixtures.REMOTE_IMAGE_ID}")
    tapHotzone(webView, "copyThumbnail:${MobileV4QaFixtures.REMOTE_IMAGE_ID}")
    activityRule.scenario.onActivity { activity ->
      assertEquals(1, activity.downloadAndCopyCount)
      assertEquals(1, activity.downloadToCacheCount)
      assertEquals(1, activity.copyThumbnailCount)
    }
  }

  @Test
  fun selectedHistoryItemsDriveStableSpecificDetailActions() {
    lateinit var webView: WebView
    activityRule.scenario.onActivity { activity ->
      webView = activity.webView
    }
    waitForScreen(webView)

    listOf(
      MobileV4QaFixtures.READY_LINK_ID,
      MobileV4QaFixtures.READY_COLOR_ID,
      MobileV4QaFixtures.READY_FILE_ID,
    ).forEach { stableId ->
      tapHotzone(webView, "openItemDetail:$stableId")
      assertTrue(
        waitForCondition(
          webView,
          "window.__clipdockQaDumpSemantics().screen_id === 'item_detail_text' && window.__clipdockQaDumpSemantics().selected_stable_id === '$stableId' && Boolean(document.querySelector('[data-action-id=\"copyItem:$stableId\"]'))",
        ),
      )
      tapHotzone(webView, "copyItem:$stableId")
      activityRule.scenario.onActivity { activity ->
        assertEquals(stableId, activity.lastActionStableId)
      }
      tapHotzone(webView, "showDeleteConfirm:$stableId")
      assertTrue(
        waitForCondition(
          webView,
          "window.__clipdockQaDumpSemantics().screen_id === 'delete_confirm' && window.__clipdockQaDumpSemantics().selected_stable_id === '$stableId' && Boolean(document.querySelector('[data-action-id=\"deleteSyncRecord:$stableId\"]'))",
        ),
      )
      tapHotzone(webView, "hideDeleteConfirm")
      assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'item_detail_text'"))
      tapHotzone(webView, "closeDetail")
      assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'history'"))
    }
  }

  @Test
  fun deleteConfirmSupportsCancelLocalCacheAndSyncDelete() {
    lateinit var webView: WebView
    activityRule.scenario.onActivity { activity ->
      webView = activity.webView
    }
    waitForScreen(webView)
    eval(webView, "window.__clipdockQaRender('delete_confirm')")
    assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'delete_confirm' && Boolean(document.querySelector('[data-action-id=\"removeLocalCache:${MobileV4QaFixtures.READY_TEXT_ID}\"]'))"))
    assertTrue(evalBoolean(webView, "document.querySelector('[data-action-id=\"removeLocalCache:${MobileV4QaFixtures.READY_TEXT_ID}\"]').disabled"))
    tapHotzone(webView, "deleteSyncRecord:${MobileV4QaFixtures.READY_TEXT_ID}")
    activityRule.scenario.onActivity { activity ->
      assertEquals(1, activity.deleteSyncRecordCount)
    }
  }

  @Test
  fun backNavigationHidesWebDetailBeforeActivityExit() {
    lateinit var webView: WebView
    activityRule.scenario.onActivity { activity -> webView = activity.webView }
    waitForScreen(webView)
    tapHotzone(webView, "openItemDetail:${MobileV4QaFixtures.READY_TEXT_ID}")
    assertTrue(evalBoolean(webView, "window.__clipdockQaDumpSemantics().screen_id === 'item_detail_text'"))
    InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
    assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'history'"))
  }

  @Test
  fun domSemanticExportContainsRevision4Fields() {
    lateinit var webView: WebView
    activityRule.scenario.onActivity { activity -> webView = activity.webView }
    waitForScreen(webView)
    val json = eval(webView, "JSON.stringify(window.__clipdockQaDumpSemantics())")
    assertTrue(json.contains("\\\"screen_id\\\""))
    assertTrue(json.contains("\\\"bridge_action_ids\\\""))
    assertTrue(json.contains("\\\"touch_targets_px\\\""))
    assertTrue(json.contains("\\\"source_sha256\\\""))
    assertTrue(json.contains("\\\"runtime_asset_sha256\\\""))
    assertTrue(json.contains("\\\"visual_png_sha256\\\""))
    assertTrue(json.contains("\\\"hotzones_sha256\\\""))
    assertTrue(json.contains("\\\"fallback\\\":false"))
  }

  @Test
  fun bottomNavAndSettingsDetailHotzonesUseNativeOkBeforeRouteChange() {
    lateinit var webView: WebView
    activityRule.scenario.onActivity { activity -> webView = activity.webView }
    waitForScreen(webView)
    tapHotzone(webView, "selectDestination:settings")
    assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'settings'"))
    tapHotzone(webView, "openSettingsDetail:keep_alive")
    assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'keep_alive'"))
    activityRule.scenario.onActivity { activity ->
      assertEquals(1, activity.openSettingsDetailCount)
      assertEquals(com.apkdv.clipdock.SettingsDetailDestination.KeepAlive, activity.lastSettingsDetail)
    }
    tapHotzone(webView, "closeSettingsDetail")
    assertTrue(waitForCondition(webView, "window.__clipdockQaDumpSemantics().screen_id === 'settings'"))
    activityRule.scenario.onActivity { activity ->
      assertEquals(1, activity.closeSettingsDetailCount)
    }
  }

  @Test
  fun webViewSecuritySettingsAndAllowlistRejectRemoteSchemes() {
    activityRule.scenario.onActivity { activity ->
      val settings = activity.webView.settings
      assertTrue(settings.javaScriptEnabled)
      assertFalse(settings.domStorageEnabled)
      assertFalse(settings.databaseEnabled)
      assertFalse(settings.allowFileAccess)
      assertFalse(settings.allowContentAccess)
      assertFalse(settings.allowFileAccessFromFileURLs)
      assertFalse(settings.allowUniversalAccessFromFileURLs)
      assertEquals(WebSettings.MIXED_CONTENT_NEVER_ALLOW, settings.mixedContentMode)
      assertEquals(100, settings.textZoom)
      assertFalse(settings.javaScriptCanOpenWindowsAutomatically)
      assertFalse(isAllowedClipDockAsset(Uri.parse("https://example.com/assets/clipdock-mobile-v4/index.html")))
      assertFalse(isAllowedClipDockAsset(Uri.parse("file:///android_asset/clipdock-mobile-v4/index.html")))
      assertFalse(isAllowedClipDockAsset(Uri.parse("content://com.apkdv.clipdock/file")))
      assertFalse(isAllowedClipDockAsset(Uri.parse("data:text/html,blocked")))
      assertFalse(isAllowedClipDockAsset(Uri.parse("blob:https://appassets.androidplatform.net/id")))
      assertFalse(isAllowedClipDockAsset(Uri.parse("intent://blocked")))
      assertFalse(isAllowedClipDockAsset(Uri.parse("market://details?id=com.apkdv.clipdock")))
      assertFalse(isAllowedClipDockAsset(Uri.parse("javascript:alert(1)")))
      assertTrue(isAllowedClipDockAsset(Uri.parse("https://appassets.androidplatform.net/assets/clipdock-mobile-v4/index.html")))
    }
  }

  private fun waitForScreen(webView: WebView) {
    assertTrue(waitForCondition(webView, "Boolean(window.__clipdockQaDumpSemantics && document.querySelector('.clipdock-visual-layer'))"))
  }

  private fun waitForCondition(webView: WebView, expression: String): Boolean {
    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
    while (System.nanoTime() < deadline) {
      if (evalBoolean(webView, expression)) return true
      Thread.sleep(100)
    }
    return false
  }

  private fun tapHotzone(webView: WebView, actionId: String) {
    val boundsJson =
      eval(
        webView,
        """
        JSON.stringify((() => {
          const element = document.querySelector(`[data-action-id="${actionId}"]`);
          if (!element) return null;
          const rect = element.getBoundingClientRect();
          return {x: Math.round(rect.left), y: Math.round(rect.top), width: Math.round(rect.width), height: Math.round(rect.height)};
        })())
        """.trimIndent(),
      )
    val bounds = JSONObject(boundsJson.trim('"').replace("\\\"", "\""))
    val location = IntArray(2)
    activityRule.scenario.onActivity {
      webView.getLocationOnScreen(location)
    }
    val x = location[0] + bounds.getInt("x") + bounds.getInt("width") / 2f
    val y = location[1] + bounds.getInt("y") + bounds.getInt("height") / 2f
    val downTime = SystemClock.uptimeMillis()
    InstrumentationRegistry.getInstrumentation().sendPointerSync(
      MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, x, y, 0),
    )
    InstrumentationRegistry.getInstrumentation().sendPointerSync(
      MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, x, y, 0),
    )
    Thread.sleep(350)
  }

  private fun evalBoolean(webView: WebView, expression: String): Boolean = eval(webView, "Boolean($expression)") == "true"

  private fun eval(webView: WebView, expression: String): String {
    val latch = CountDownLatch(1)
    var result = "null"
    InstrumentationRegistry.getInstrumentation().runOnMainSync {
      webView.evaluateJavascript(expression) {
        result = it ?: "null"
        latch.countDown()
      }
    }
    assertTrue(latch.await(5, TimeUnit.SECONDS))
    return result
  }

  private fun String.jsString(): String = "'" + replace("\\", "\\\\").replace("'", "\\'") + "'"
}
