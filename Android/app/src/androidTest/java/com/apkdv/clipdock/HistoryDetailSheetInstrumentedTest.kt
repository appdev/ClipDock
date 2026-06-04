package com.apkdv.clipdock

import android.view.KeyEvent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.click
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.apkdv.clipdock.qa.HistoryDetailSheetQaActivity
import junit.framework.TestCase.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HistoryDetailSheetInstrumentedTest {
  @get:Rule val composeRule = createAndroidComposeRule<HistoryDetailSheetQaActivity>()

  @Test
  fun cardClickOpensSheetWithoutUsingItem() {
    openSheet(HistoryDetailSheetQaActivity.READY_TEXT_ID)

    composeRule.onNodeWithTag(SHEET_TAG).assertIsDisplayed()
    composeRule.runOnIdle { assertEquals(0, composeRule.activity.useCount) }
  }

  @Test
  fun bottomPrimaryCopyUsesItemOnce() {
    openSheet(HistoryDetailSheetQaActivity.READY_TEXT_ID)

    composeRule.onNodeWithTag(PRIMARY_BUTTON_TAG).performClick()

    composeRule.runOnIdle {
      assertEquals(1, composeRule.activity.useCount)
      assertEquals(HistoryDetailSheetQaActivity.READY_TEXT_ID, composeRule.activity.lastUsedStableId)
    }
  }

  @Test
  fun bottomPrimaryRetrieveUsesItemOnce() {
    openSheet(HistoryDetailSheetQaActivity.REMOTE_IMAGE_ID)

    composeRule.onNodeWithTag(PRIMARY_BUTTON_TAG).performClick()

    composeRule.runOnIdle {
      assertEquals(1, composeRule.activity.useCount)
      assertEquals(HistoryDetailSheetQaActivity.REMOTE_IMAGE_ID, composeRule.activity.lastUsedStableId)
    }
  }

  @Test
  fun unavailableAndProtocollessActionsAreHiddenAndDoNotUseItem() {
    openSheet(HistoryDetailSheetQaActivity.MISSING_ASSET_ID)

    composeRule.onNodeWithTag(PRIMARY_BUTTON_TAG).assertIsNotEnabled()
    composeRule.onAllNodesWithTag(PRIMARY_TILE_TAG).assertCountEquals(0)
    composeRule.onAllNodesWithTag(SHARE_TILE_TAG).assertCountEquals(0)
    composeRule.onAllNodesWithTag(PIN_TILE_TAG).assertCountEquals(0)
    composeRule.runOnIdle { assertEquals(0, composeRule.activity.useCount) }
  }

  @Test
  fun closeButtonDismissesSheet() {
    openSheet(HistoryDetailSheetQaActivity.READY_TEXT_ID)

    composeRule.onNodeWithTag(CLOSE_TAG).performClick()

    waitUntilSheetGone()
  }

  @Test
  fun backDismissesSheet() {
    openSheet(HistoryDetailSheetQaActivity.READY_TEXT_ID)

    InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)

    waitUntilSheetGone()
  }

  @Test
  fun scrimDismissesSheet() {
    openSheet(HistoryDetailSheetQaActivity.READY_TEXT_ID)

    composeRule.onAllNodes(isRoot())[1].performTouchInput {
      click(Offset(center.x, 24f))
    }

    waitUntilSheetGone()
  }

  @Test
  fun selectedItemRemovalDismissesSheet() {
    openSheet(HistoryDetailSheetQaActivity.REMOTE_IMAGE_ID)

    composeRule.activityRule.scenario.onActivity { activity ->
      activity.removeHistoryItem(HistoryDetailSheetQaActivity.REMOTE_IMAGE_ID)
    }

    waitUntilSheetGone()
  }

  private fun openSheet(stableId: String) {
    composeRule.onNodeWithTag("history-card-$stableId").performClick()
    composeRule.onNodeWithTag(SHEET_TAG).assertIsDisplayed()
    composeRule.runOnIdle { assertEquals(0, composeRule.activity.useCount) }
  }

  private fun waitUntilSheetGone() {
    composeRule.waitUntil(timeoutMillis = 5_000) {
      composeRule.onAllNodesWithTag(SHEET_TAG).fetchSemanticsNodes().isEmpty()
    }
  }

  private companion object {
    const val SHEET_TAG = "history-detail-sheet"
    const val CLOSE_TAG = "history-detail-close"
    const val PRIMARY_BUTTON_TAG = "history-detail-primary-button"
    const val PRIMARY_TILE_TAG = "history-detail-action-primary"
    const val SHARE_TILE_TAG = "history-detail-action-share"
    const val PIN_TILE_TAG = "history-detail-action-pin"
  }
}
