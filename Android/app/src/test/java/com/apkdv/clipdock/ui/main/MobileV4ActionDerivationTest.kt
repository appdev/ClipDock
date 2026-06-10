package com.apkdv.clipdock.ui.main

import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.ClipDockUiState
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.TransferState
import com.apkdv.clipdock.ui.components.ClipDockTone
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import org.junit.Test

class MobileV4ActionDerivationTest {
  @Test
  fun primaryAction_copiesReadyLocalItems() {
    listOf(
      ClipItemType.Text,
      ClipItemType.Link,
      ClipItemType.RichText,
      ClipItemType.Color,
      ClipItemType.Image,
      ClipItemType.File,
    ).forEach { type ->
      val item =
        sampleItem(
          type = type,
          localUri = if (type == ClipItemType.Image || type == ClipItemType.File) "content://ready" else null,
          payloadState = PayloadState.Ready,
        )

      val actions = mobileV4DetailActions(item, p2pEnabled = false, wifiOnlyBlocked = true)

      assertEquals(MobileV4ActionKind.Copy, actions.primary.kind)
      assertEquals("复制", actions.primary.label)
      assertTrue(actions.primary.enabled)
    }
  }

  @Test
  fun remotePrimary_downloadsToCacheWhenAllowed() {
    val item = sampleItem(type = ClipItemType.Image, localUri = null, assetId = "asset")

    val actions = mobileV4DetailActions(item, p2pEnabled = true, wifiOnlyBlocked = false)

    assertEquals(MobileV4ActionKind.ShowRemoteRetrieval, actions.primary.kind)
    assertEquals("取回", actions.primary.label)
    assertTrue(actions.primary.enabled)
    assertEquals("取回", actions.downloadToCache.label)
    assertTrue(actions.downloadToCache.enabled)
  }

  @Test
  fun remoteActions_disableMissingAssetP2pWifiAndInFlightStates() {
    val remote = sampleItem(type = ClipItemType.File, localUri = null, assetId = "asset")

    val missingAsset = mobileV4DetailActions(remote.copy(assetId = null), p2pEnabled = true, wifiOnlyBlocked = false)
    assertFalse(missingAsset.primary.enabled)
    assertTrue(missingAsset.primary.message.contains("assetId"))

    val p2pDisabled = mobileV4DetailActions(remote, p2pEnabled = false, wifiOnlyBlocked = false)
    assertFalse(p2pDisabled.primary.enabled)
    assertTrue(p2pDisabled.primary.message.contains("P2P"))

    val wifiBlocked = mobileV4DetailActions(remote, p2pEnabled = true, wifiOnlyBlocked = true)
    assertFalse(wifiBlocked.primary.enabled)
    assertEquals(ClipDockTone.Amber, wifiBlocked.primary.tone)
    assertTrue(wifiBlocked.primary.message.contains("Wi-Fi"))

    val discovering = mobileV4DetailActions(remote.copy(transferState = TransferState.DiscoveringPeer), true, false)
    assertFalse(discovering.primary.enabled)
    assertTrue(discovering.primary.message.contains("查找"))

    val downloading = mobileV4DetailActions(remote.copy(transferState = TransferState.Downloading), true, false)
    assertFalse(downloading.primary.enabled)
    assertTrue(downloading.primary.message.contains("下载"))

    val inFlight = mobileV4DetailActions(remote, true, false, setOf(MobileV4ActionKind.DownloadToCache))
    assertEquals("取回中", inFlight.primary.label)
    assertFalse(inFlight.primary.enabled)
    assertFalse(inFlight.downloadToCache.enabled)
  }

  @Test
  fun remoteActions_followThumbnailAndCacheAvailability() {
    val remoteWithThumbnail =
      sampleItem(
        type = ClipItemType.Image,
        localUri = null,
        assetId = "asset",
        thumbnailUri = "file:///app/clipdock-thumbnails/thumb.webp",
      )

    val actions = mobileV4DetailActions(remoteWithThumbnail, p2pEnabled = true, wifiOnlyBlocked = false)

    assertTrue(actions.downloadToCache.enabled)
    assertEquals("取回", actions.downloadToCache.label)
    assertTrue(actions.copyThumbnail.enabled)
    assertFalse(actions.removeLocalCache.enabled)
  }

  @Test
  fun deleteConfirmActions_distinguishLocalCacheAndSyncDelete() {
    val cached = sampleItem(type = ClipItemType.File, localUri = "content://ready", payloadState = PayloadState.Ready)

    val actions = mobileV4DetailActions(cached, p2pEnabled = true, wifiOnlyBlocked = false)

    assertTrue(actions.removeLocalCache.enabled)
    assertEquals("仅移除本机缓存", actions.removeLocalCache.label)
    assertTrue(actions.deleteSyncRecord.enabled)
    assertEquals("删除同步记录", actions.deleteSyncRecord.label)
  }

  @Test
  fun fileActionState_preservesListShortcutLabelsWithoutDirectV4Download() {
    val remote = sampleItem(type = ClipItemType.File, localUri = null, assetId = "asset")

    assertEquals("取回", fileActionState(remote, p2pEnabled = true, wifiOnlyBlocked = false).primaryLabel)
    assertEquals("查找", fileActionState(remote.copy(transferState = TransferState.DiscoveringPeer), true, false).primaryLabel)
    assertEquals("下载中", fileActionState(remote.copy(transferState = TransferState.Downloading), true, false).primaryLabel)
    assertEquals("重试", fileActionState(remote.copy(transferState = TransferState.Failed), true, false).primaryLabel)
    assertEquals("打开", fileActionState(remote.copy(localUri = "content://ready", payloadState = PayloadState.Ready), true, false).primaryLabel)
  }

  @Test
  fun resolveMobileV4Item_doesNotSynthesizeReferenceItems() {
    assertEquals(null, resolveMobileV4Item(ClipDockUiState(deviceName = "Android"), "qa-ready-text"))

    val realItem = sampleItem(type = ClipItemType.Text, localUri = null, payloadState = PayloadState.Ready).copy(stableId = "qa-ready-text")
    assertEquals(realItem, resolveMobileV4Item(ClipDockUiState(deviceName = "Android", items = listOf(realItem)), "qa-ready-text"))
  }

  private fun sampleItem(
    type: ClipItemType = ClipItemType.File,
    localUri: String?,
    transferState: TransferState = TransferState.Idle,
    assetId: String? = "asset",
    thumbnailUri: String? = null,
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
      thumbnailUri = thumbnailUri,
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
