package com.apkdv.clipdock

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import org.junit.Rule
import org.junit.Test

class MainActivityTest {
  @get:Rule val composeRule = createAndroidComposeRule<MainActivity>()

  @Test
  fun launchesHistoryScreen() {
    composeRule.onNodeWithText("ClipDock").assertIsDisplayed()
    composeRule.onNodeWithText("全部").assertIsDisplayed()
    composeRule.onNodeWithText("链接").assertIsDisplayed()
    composeRule.onNodeWithText("重要").assertIsDisplayed()
    composeRule.onNodeWithText("图片").assertIsDisplayed()
    composeRule.onNodeWithText("历史").assertIsDisplayed()
  }
}
