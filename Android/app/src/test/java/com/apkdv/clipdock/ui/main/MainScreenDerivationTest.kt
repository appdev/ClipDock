package com.apkdv.clipdock.ui.main

import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.TransferState
import com.apkdv.clipdock.ui.components.ClipDockTone
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import org.junit.Test

class MainScreenDerivationTest {
  @Test
  fun historyActionLabel_preservesCopyDownloadTransferLabels() {
    assertEquals("复制", historyActionLabel(sampleItem(localUri = "content://ready")))
    assertEquals("下载", historyActionLabel(sampleItem(localUri = null)))
    assertEquals("取回", historyActionLabel(sampleItem(localUri = null, type = ClipItemType.Image)))
    assertEquals("查找", historyActionLabel(sampleItem(localUri = null, transferState = TransferState.DiscoveringPeer)))
    assertEquals("下载中", historyActionLabel(sampleItem(localUri = null, transferState = TransferState.Downloading)))
    assertEquals("重试", historyActionLabel(sampleItem(localUri = null, transferState = TransferState.Failed)))
  }

  @Test
  fun fileActionState_mapsRemotePayloadStates() {
    val remote = sampleItem(localUri = null, assetId = "asset")

    assertEquals("取回", fileActionState(remote, p2pEnabled = true, wifiOnlyBlocked = false).primaryLabel)
    assertEquals("查找", fileActionState(remote.copy(transferState = TransferState.DiscoveringPeer), true, false).primaryLabel)
    assertEquals("下载中", fileActionState(remote.copy(transferState = TransferState.Downloading), true, false).primaryLabel)
    assertEquals("重试", fileActionState(remote.copy(transferState = TransferState.Failed), true, false).primaryLabel)
    assertEquals("打开", fileActionState(remote.copy(localUri = "content://ready", payloadState = PayloadState.Ready), true, false).primaryLabel)
  }

  @Test
  fun fileActionState_reportsExplicitBlockedReasons() {
    val missingAsset = sampleItem(localUri = null, assetId = null)
    val remote = sampleItem(localUri = null, assetId = "asset")

    val missingState = fileActionState(missingAsset, p2pEnabled = true, wifiOnlyBlocked = false)
    assertFalse(missingState.primaryEnabled)
    assertTrue(missingState.message.contains("assetId"))

    val p2pDisabled = fileActionState(remote, p2pEnabled = false, wifiOnlyBlocked = false)
    assertFalse(p2pDisabled.primaryEnabled)
    assertTrue(p2pDisabled.message.contains("P2P"))

    val wifiBlocked = fileActionState(remote, p2pEnabled = true, wifiOnlyBlocked = true)
    assertFalse(wifiBlocked.primaryEnabled)
    assertEquals(ClipDockTone.Amber, wifiBlocked.tone)
    assertTrue(wifiBlocked.message.contains("Wi-Fi"))
  }

  @Test
  fun historyDetailSheetActions_enableReadyLocalCopyTypes() {
    listOf(
      ClipItemType.Text,
      ClipItemType.Link,
      ClipItemType.RichText,
      ClipItemType.Color,
      ClipItemType.Image,
      ClipItemType.File,
    ).forEach { type ->
      val item = sampleItem(localUri = if (type == ClipItemType.Image || type == ClipItemType.File) "content://ready" else null, type = type, payloadState = PayloadState.Ready)

      val actions = historyDetailSheetActions(item, p2pEnabled = false, wifiOnlyBlocked = true)

      assertEquals(HistoryDetailSheetActionKind.Copy, actions.primary.kind)
      assertEquals("复制", actions.primary.label)
      assertTrue(actions.primary.enabled)
      assertTrue(actions.primary.invokesUseItem)
      assertEquals(actions.primary, actions.tiles.first())
      assertTrue(actions.visibleTiles.isEmpty())
    }
  }

  @Test
  fun historyDetailSheetActions_enableRemoteRetrieveWhenConstraintsAllow() {
    val item = sampleItem(localUri = null, type = ClipItemType.Image, assetId = "asset")

    val actions = historyDetailSheetActions(item, p2pEnabled = true, wifiOnlyBlocked = false)

    assertEquals(HistoryDetailSheetActionKind.Retrieve, actions.primary.kind)
    assertEquals("取回", actions.primary.label)
    assertTrue(actions.primary.enabled)
    assertTrue(actions.primary.invokesUseItem)
    assertTrue(actions.visibleTiles.isEmpty())
  }

  @Test
  fun historyDetailSheetActions_disableMissingAssetP2pWifiAndInFlightStates() {
    val remote = sampleItem(localUri = null, type = ClipItemType.File, assetId = "asset")

    val missingAsset = historyDetailSheetActions(remote.copy(assetId = null), p2pEnabled = true, wifiOnlyBlocked = false).primary
    assertFalse(missingAsset.enabled)
    assertTrue(missingAsset.message.contains("assetId"))

    val p2pDisabled = historyDetailSheetActions(remote, p2pEnabled = false, wifiOnlyBlocked = false).primary
    assertFalse(p2pDisabled.enabled)
    assertTrue(p2pDisabled.message.contains("P2P"))

    val wifiBlocked = historyDetailSheetActions(remote, p2pEnabled = true, wifiOnlyBlocked = true).primary
    assertFalse(wifiBlocked.enabled)
    assertEquals(ClipDockTone.Amber, wifiBlocked.tone)
    assertTrue(wifiBlocked.message.contains("Wi-Fi"))

    val discovering = historyDetailSheetActions(remote.copy(transferState = TransferState.DiscoveringPeer), p2pEnabled = true, wifiOnlyBlocked = false).primary
    assertFalse(discovering.enabled)
    assertEquals("查找", discovering.label)

    val downloading = historyDetailSheetActions(remote.copy(transferState = TransferState.Downloading), p2pEnabled = true, wifiOnlyBlocked = false).primary
    assertFalse(downloading.enabled)
    assertEquals("下载中", downloading.label)
  }

  @Test
  fun historyDetailSheetActions_enableFailedRetryOnlyWhenConstraintsAllow() {
    val failed = sampleItem(localUri = null, type = ClipItemType.Image, transferState = TransferState.Failed, assetId = "asset")

    val retry = historyDetailSheetActions(failed, p2pEnabled = true, wifiOnlyBlocked = false).primary
    assertEquals(HistoryDetailSheetActionKind.Retry, retry.kind)
    assertEquals("重试", retry.label)
    assertTrue(retry.enabled)
    assertTrue(retry.invokesUseItem)

    assertFalse(historyDetailSheetActions(failed.copy(assetId = null), p2pEnabled = true, wifiOnlyBlocked = false).primary.enabled)
    assertFalse(historyDetailSheetActions(failed, p2pEnabled = false, wifiOnlyBlocked = false).primary.enabled)
    assertFalse(historyDetailSheetActions(failed, p2pEnabled = true, wifiOnlyBlocked = true).primary.enabled)
  }

  @Test
  fun historyDetailSheetActions_disableUnknownTypeAndProtocollessTiles() {
    val unknown = sampleItem(localUri = "content://ready", type = ClipItemType.Unknown, payloadState = PayloadState.Ready)

    val actions = historyDetailSheetActions(unknown, p2pEnabled = true, wifiOnlyBlocked = false)

    assertFalse(actions.primary.enabled)
    assertEquals(HistoryDetailSheetActionKind.Unavailable, actions.primary.kind)
    assertFalse(actions.tiles.first { it.kind == HistoryDetailSheetActionKind.Share }.enabled)
    assertFalse(actions.tiles.first { it.kind == HistoryDetailSheetActionKind.Pin }.enabled)
    assertTrue(actions.visibleTiles.isEmpty())
  }

  @Test
  fun historyDetailSheetDisplay_derivesSourceContentAndStatusRows() {
    val remoteImage =
      sampleItem(localUri = null, type = ClipItemType.Image, assetId = "asset")
        .copy(title = "UI-review-screenshot.png", body = "image/png", sourceName = "MacBook Pro", copiedAtMillis = 0)

    val display = historyDetailSheetDisplay(remoteImage)

    assertEquals("UI-review-screenshot.png", display.title)
    assertEquals("MacBook Pro", display.source)
    assertEquals("PNG 图片", display.contentType)
    assertEquals("远端可取回", display.status)
    assertEquals("未同步", display.timeLabel)
    assertTrue(display.subtitle.contains("MacBook Pro"))
    assertTrue(display.metaRows.any { it.label == "来源设备" && it.value == "MacBook Pro" })
    assertTrue(display.metaRows.any { it.label == "内容类型" && it.value == "PNG 图片" })
    assertTrue(display.metaRows.any { it.label == "状态" && it.value == "远端可取回" })
  }

  private fun sampleItem(
    localUri: String?,
    type: ClipItemType = ClipItemType.File,
    transferState: TransferState = TransferState.Idle,
    assetId: String? = "asset",
    payloadState: PayloadState = if (localUri == null) PayloadState.RemoteOnly else PayloadState.Ready,
  ): ClipHistoryItem =
    ClipHistoryItem(
      stableId = "stable",
      contentHash = "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      type = type,
      title = "test.pdf",
      body = "application/pdf",
      detail = "PDF",
      sourceName = null,
      assetId = assetId,
      thumbnailUri = null,
      thumbnailDigest = null,
      thumbnailMimeType = null,
      thumbnailByteCount = null,
      thumbnailWidth = null,
      thumbnailHeight = null,
      localUri = localUri,
      payloadState = payloadState,
      transferState = transferState,
      copiedAtMillis = 1,
      copyCount = 1,
    )
}
