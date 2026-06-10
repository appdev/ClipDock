package com.apkdv.clipdock

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import junit.framework.TestCase.assertFalse
import org.junit.Rule
import org.junit.Test

class MainActivityTest {
  @get:Rule val composeRule = createAndroidComposeRule<MainActivity>()

  @Test
  fun launchesRealDataComposeSurfaceWithoutReferenceWebView() {
    composeRule.onNodeWithText("剪贴板").assertIsDisplayed()
    composeRule.onNodeWithContentDescription("历史").assertIsDisplayed()
    composeRule.onNodeWithContentDescription("设备").assertIsDisplayed()
    composeRule.onNodeWithContentDescription("文件").assertIsDisplayed()
    composeRule.onNodeWithContentDescription("设置").assertIsDisplayed()
    composeRule.onNodeWithText("链接").assertIsDisplayed()
    composeRule.onNodeWithText("待上传").assertIsDisplayed()
    composeRule.runOnIdle {
      assertFalse(hasWebView(composeRule.activity.window.decorView))
    }
  }

  @Test
  fun bottomNavigationUsesRealDataPages() {
    composeRule.onNodeWithContentDescription("设备").performClick()
    composeRule.onNodeWithText("最近传输").assertIsDisplayed()

    composeRule.onNodeWithContentDescription("文件").performClick()
    composeRule.onNodeWithText("按需下载").assertIsDisplayed()
    composeRule.onNodeWithText("远程资产状态").assertIsDisplayed()

    composeRule.onNodeWithContentDescription("设置").performClick()
    composeRule.onNodeWithText("同步服务运行中", substring = true).assertIsDisplayed()

    composeRule.onNodeWithContentDescription("历史").performClick()
    composeRule.onNodeWithText("剪贴板").assertIsDisplayed()
  }

  private fun hasWebView(view: View): Boolean {
    if (view is WebView) return true
    val group = view as? ViewGroup ?: return false
    for (index in 0 until group.childCount) {
      if (hasWebView(group.getChildAt(index))) return true
    }
    return false
  }
}
