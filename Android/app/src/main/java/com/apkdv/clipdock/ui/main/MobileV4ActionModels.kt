package com.apkdv.clipdock.ui.main

import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.TransferState
import com.apkdv.clipdock.ui.components.ClipDockIconKind
import com.apkdv.clipdock.ui.components.ClipDockTone

enum class MobileV4ActionKind {
  Copy,
  ShowRemoteRetrieval,
  DownloadToCache,
  CopyThumbnail,
  RemoveLocalCache,
  DeleteSyncRecord,
}

enum class MobileV4InitialSheet {
  RemoteRetrieval,
  DeleteConfirm,
}

object MobileV4Tags {
  const val ItemDetailScreen = "item-detail-screen"
  const val DetailPrimaryAction = "item-detail-primary-action"
  const val DetailTrashAction = "item-detail-trash-action"
  const val RemoteRetrievalSheet = "remote-retrieval-sheet"
  const val RemoteDownloadToCache = "remote-download-to-cache"
  const val RemoteCopyThumbnail = "remote-copy-thumbnail"
  const val DeleteConfirmSheet = "delete-confirm-sheet"
  const val DeleteRemoveLocalCache = "delete-remove-local-cache"
  const val DeleteSyncRecord = "delete-sync-record"
  const val DeleteCancel = "delete-cancel"
}

data class MobileV4ActionState(
  val inFlight: Map<String, Set<MobileV4ActionKind>> = emptyMap(),
) {
  fun isInFlight(stableId: String, kind: MobileV4ActionKind): Boolean =
    inFlight[stableId]?.contains(kind) == true

  fun inFlightKinds(stableId: String): Set<MobileV4ActionKind> =
    inFlight[stableId].orEmpty()
}

internal data class MobileV4DetailAction(
  val kind: MobileV4ActionKind,
  val label: String,
  val icon: ClipDockIconKind,
  val enabled: Boolean,
  val tone: ClipDockTone,
  val message: String,
)

internal data class MobileV4DetailActions(
  val primary: MobileV4DetailAction,
  val downloadToCache: MobileV4DetailAction,
  val copyThumbnail: MobileV4DetailAction,
  val removeLocalCache: MobileV4DetailAction,
  val deleteSyncRecord: MobileV4DetailAction,
)

internal fun mobileV4DetailActions(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
  inFlightKinds: Set<MobileV4ActionKind> = emptySet(),
): MobileV4DetailActions {
  val remoteEnabled = mobileV4RemoteActionEnabled(item, p2pEnabled, wifiOnlyBlocked, inFlightKinds)
  val remoteMessage = mobileV4RemoteActionMessage(item, p2pEnabled, wifiOnlyBlocked)
  val primary =
    when {
      inFlightKinds.contains(MobileV4ActionKind.Copy) ->
        MobileV4DetailAction(MobileV4ActionKind.Copy, "复制中", ClipDockIconKind.Copy, false, ClipDockTone.Green, "正在复制到剪贴板")
      inFlightKinds.contains(MobileV4ActionKind.DownloadToCache) ->
        MobileV4DetailAction(MobileV4ActionKind.ShowRemoteRetrieval, "取回中", ClipDockIconKind.Download, false, ClipDockTone.Blue, "远端内容正在处理")
      mobileV4HasLocalCopySemantics(item) ->
        MobileV4DetailAction(MobileV4ActionKind.Copy, "复制", ClipDockIconKind.Copy, true, ClipDockTone.Green, "复制到剪贴板")
      item.type == ClipItemType.Image || item.type == ClipItemType.File ->
        MobileV4DetailAction(
          MobileV4ActionKind.ShowRemoteRetrieval,
          if (item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed) "重试" else "取回",
          ClipDockIconKind.Download,
          remoteEnabled,
          if (wifiOnlyBlocked || item.transferState == TransferState.Failed) ClipDockTone.Amber else ClipDockTone.Blue,
          remoteMessage,
        )
      else ->
        MobileV4DetailAction(MobileV4ActionKind.Copy, "不可用", ClipDockIconKind.Alert, false, ClipDockTone.Neutral, "该内容暂不支持复制")
    }

  val downloadToCache =
    MobileV4DetailAction(
      MobileV4ActionKind.DownloadToCache,
      if (inFlightKinds.contains(MobileV4ActionKind.DownloadToCache)) "下载中" else "取回",
      ClipDockIconKind.Download,
      remoteEnabled && !inFlightKinds.contains(MobileV4ActionKind.DownloadToCache),
      ClipDockTone.Blue,
      remoteMessage,
    )
  val thumbnailEnabled =
    (item.type == ClipItemType.Image || item.type == ClipItemType.File) &&
      !item.thumbnailUri.isNullOrBlank() &&
      !inFlightKinds.contains(MobileV4ActionKind.CopyThumbnail)
  val copyThumbnail =
    MobileV4DetailAction(
      MobileV4ActionKind.CopyThumbnail,
      if (inFlightKinds.contains(MobileV4ActionKind.CopyThumbnail)) "复制中" else "复制缩略图",
      ClipDockIconKind.Image,
      thumbnailEnabled,
      ClipDockTone.Green,
      if (item.thumbnailUri.isNullOrBlank()) "没有可用缩略图" else "复制预览图，保留原图远端状态",
    )
  val removeLocalCache =
    MobileV4DetailAction(
      MobileV4ActionKind.RemoveLocalCache,
      if (inFlightKinds.contains(MobileV4ActionKind.RemoveLocalCache)) "移除中" else "仅移除本机缓存",
      ClipDockIconKind.Folder,
      (item.type == ClipItemType.Image || item.type == ClipItemType.File) &&
        !item.localUri.isNullOrBlank() &&
        !inFlightKinds.contains(MobileV4ActionKind.RemoveLocalCache),
      ClipDockTone.Amber,
      if (item.localUri.isNullOrBlank()) "没有本机缓存" else "保留同步记录和缩略图",
    )
  val deleteSyncRecord =
    MobileV4DetailAction(
      MobileV4ActionKind.DeleteSyncRecord,
      if (inFlightKinds.contains(MobileV4ActionKind.DeleteSyncRecord)) "删除中" else "删除同步记录",
      ClipDockIconKind.Trash,
      item.contentHash.isNotBlank() && !inFlightKinds.contains(MobileV4ActionKind.DeleteSyncRecord),
      ClipDockTone.Red,
      "从同步空间和所有设备历史中移除",
    )
  return MobileV4DetailActions(primary, downloadToCache, copyThumbnail, removeLocalCache, deleteSyncRecord)
}

internal fun mobileV4HasLocalCopySemantics(item: ClipHistoryItem): Boolean =
  when (item.type) {
    ClipItemType.Text,
    ClipItemType.Link,
    ClipItemType.RichText,
    ClipItemType.Color -> !item.needsRemotePayload
    ClipItemType.Image,
    ClipItemType.File -> item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank()
    ClipItemType.Unknown -> false
  }

private fun mobileV4RemoteActionEnabled(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
  inFlightKinds: Set<MobileV4ActionKind>,
): Boolean =
  (item.type == ClipItemType.Image || item.type == ClipItemType.File) &&
    item.payloadState != PayloadState.Ready &&
    !item.assetId.isNullOrBlank() &&
    p2pEnabled &&
    !wifiOnlyBlocked &&
    item.transferState != TransferState.DiscoveringPeer &&
    item.transferState != TransferState.Downloading &&
    !inFlightKinds.contains(MobileV4ActionKind.DownloadToCache)

private fun mobileV4RemoteActionMessage(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
): String =
  when {
    item.type != ClipItemType.Image && item.type != ClipItemType.File -> "该内容不是远端文件"
    item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() -> "已下载到本机"
    item.assetId.isNullOrBlank() -> "缺少 assetId，无法取回"
    !p2pEnabled -> "P2P 未开启，无法取回"
    wifiOnlyBlocked -> "仅 Wi-Fi 下载已开启，当前网络不可取回"
    item.transferState == TransferState.DiscoveringPeer -> "正在查找可用设备"
    item.transferState == TransferState.Downloading -> "正在下载"
    item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed -> "上次取回失败，可重试"
    else -> "点击取回后下载到本机缓存"
  }
