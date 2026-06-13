package com.apkdv.clipdock.ui.main

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.itemsIndexed as staggeredItemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScaffoldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.apkdv.clipdock.MainDestination
import com.apkdv.clipdock.SettingsDetailDestination
import com.apkdv.clipdock.data.ClipDockUiState
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.OverlayClickAction
import com.apkdv.clipdock.data.OverlaySnapEdge
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.P2pDeviceInfo
import com.apkdv.clipdock.data.TransferState
import com.apkdv.clipdock.overlay.FloatingOverlayService
import com.apkdv.clipdock.theme.LocalClipDockTokens
import com.apkdv.clipdock.ui.components.ActionChip
import com.apkdv.clipdock.ui.components.BottomNavItem
import com.apkdv.clipdock.ui.components.ClipDockBottomNav
import com.apkdv.clipdock.ui.components.ClipDockCard
import com.apkdv.clipdock.ui.components.ClipDockHeroBanner
import com.apkdv.clipdock.ui.components.ClipDockIconButton
import com.apkdv.clipdock.ui.components.ClipDockIconKind
import com.apkdv.clipdock.ui.components.ClipDockScreenHeader
import com.apkdv.clipdock.ui.components.ClipDockSymbol
import com.apkdv.clipdock.ui.components.ClipDockTone
import com.apkdv.clipdock.ui.components.IconTile
import com.apkdv.clipdock.ui.components.RowCard
import com.apkdv.clipdock.ui.components.SegmentedControl
import com.apkdv.clipdock.ui.components.SettingDivider
import com.apkdv.clipdock.ui.components.SettingGroup
import com.apkdv.clipdock.ui.components.SettingRow
import com.apkdv.clipdock.ui.components.SliderSettingCard
import com.apkdv.clipdock.ui.components.StatusPill
import com.apkdv.clipdock.ui.components.SwitchSettingRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun MainScreen(
  selectedDestination: MainDestination = MainDestination.History,
  settingsDetail: SettingsDetailDestination? = null,
  itemDetailStableId: String? = null,
  initialDetailSheet: MobileV4InitialSheet? = null,
  onDestinationSelected: (MainDestination) -> Unit = {},
  onOpenSettingsDetail: (SettingsDetailDestination) -> Unit = {},
  onOpenItemDetail: (String) -> Unit = {},
  onBackFromDetail: () -> Unit = {},
  modifier: Modifier = Modifier,
  viewModel: MainScreenViewModel = viewModel(),
) {
  val state by viewModel.uiState.collectAsStateWithLifecycle()
  val actionState by viewModel.v4ActionState.collectAsStateWithLifecycle()
  ClipDockApp(
    state = state,
    selectedDestination = selectedDestination,
    settingsDetail = settingsDetail,
    itemDetailStableId = itemDetailStableId,
    initialDetailSheet = initialDetailSheet,
    actionState = actionState,
    onDestinationSelected = onDestinationSelected,
    onBackFromDetail = onBackFromDetail,
    onServerUrlChange = viewModel::setServerUrl,
    onDeviceNameChange = viewModel::setDeviceName,
    onSyncNow = viewModel::syncNow,
    onCheckHealth = viewModel::checkHealth,
    onCreateSyncSpace = viewModel::createSyncSpace,
    onJoinSyncSpace = viewModel::joinSyncSpace,
    onCreateInvite = viewModel::createInvite,
    onRefreshInfo = viewModel::refreshInfo,
    onUseItem = viewModel::useItem,
    onCopyItem = viewModel::copyItem,
    onDownloadToCache = viewModel::downloadToCache,
    onCopyThumbnail = viewModel::copyThumbnail,
    onDeleteSyncRecord = viewModel::deleteSyncRecord,
    onRemoveLocalCache = viewModel::removeLocalCache,
    onP2pEnabledChange = viewModel::setP2pEnabled,
    onWifiOnlyChange = viewModel::setWifiOnly,
    onOverlayEnabledChange = viewModel::setOverlayEnabled,
    onOverlayClickActionChange = viewModel::setOverlayClickAction,
    onOverlaySnapEdgeChange = viewModel::setOverlaySnapEdge,
    onOverlaySizeChange = viewModel::setOverlaySizeDp,
    onOverlayIdleOpacityChange = viewModel::setOverlayIdleOpacityPercent,
    onOverlayVerticalFractionChange = viewModel::setOverlayVerticalFraction,
    onEncryptionEnabledChange = viewModel::setEncryptionEnabled,
    onOpenSettingsDetail = onOpenSettingsDetail,
    onOpenItemDetail = onOpenItemDetail,
    modifier = modifier.fillMaxSize(),
  )
}

@Composable
internal fun ClipDockApp(
  state: ClipDockUiState,
  selectedDestination: MainDestination,
  settingsDetail: SettingsDetailDestination?,
  itemDetailStableId: String?,
  initialDetailSheet: MobileV4InitialSheet?,
  actionState: MobileV4ActionState,
  onDestinationSelected: (MainDestination) -> Unit,
  onBackFromDetail: () -> Unit,
  onServerUrlChange: (String) -> Unit,
  onDeviceNameChange: (String) -> Unit,
  onSyncNow: () -> Unit,
  onCheckHealth: () -> Unit,
  onCreateSyncSpace: () -> Unit,
  onJoinSyncSpace: (String) -> Unit,
  onCreateInvite: () -> Unit,
  onRefreshInfo: () -> Unit,
  onUseItem: (ClipHistoryItem) -> Unit,
  onCopyItem: (ClipHistoryItem) -> Unit,
  onDownloadToCache: (ClipHistoryItem) -> Unit,
  onCopyThumbnail: (ClipHistoryItem) -> Unit,
  onDeleteSyncRecord: (ClipHistoryItem) -> Unit,
  onRemoveLocalCache: (ClipHistoryItem) -> Unit,
  onP2pEnabledChange: (Boolean) -> Unit,
  onWifiOnlyChange: (Boolean) -> Unit,
  onOverlayEnabledChange: (Boolean) -> Unit,
  onOverlayClickActionChange: (OverlayClickAction) -> Unit,
  onOverlaySnapEdgeChange: (OverlaySnapEdge) -> Unit,
  onOverlaySizeChange: (Int) -> Unit,
  onOverlayIdleOpacityChange: (Int) -> Unit,
  onOverlayVerticalFractionChange: (Float) -> Unit,
  onEncryptionEnabledChange: (Boolean) -> Unit,
  onOpenSettingsDetail: (SettingsDetailDestination) -> Unit,
  onOpenItemDetail: (String) -> Unit,
  modifier: Modifier = Modifier,
  includeReferenceStatusBar: Boolean = true,
) {
  val tokens = LocalClipDockTokens.current
  val context = LocalContext.current
  val wifiOnlyBlocked = state.wifiOnly && !isWifiConnected(context)

  Scaffold(
    modifier = modifier.fillMaxSize(),
    containerColor = tokens.colors.pageBg,
    contentWindowInsets = if (includeReferenceStatusBar) WindowInsets(0, 0, 0, 0) else ScaffoldDefaults.contentWindowInsets,
    bottomBar = {
      if (itemDetailStableId == null) {
        ClipDockBottomNav(
          destinations =
            listOf(
              BottomNavItem(MainDestination.History.name, "历史", ClipDockIconKind.History),
              BottomNavItem(MainDestination.Devices.name, "设备", ClipDockIconKind.Devices),
              BottomNavItem(MainDestination.Files.name, "文件", ClipDockIconKind.Folder),
              BottomNavItem(MainDestination.Settings.name, "设置", ClipDockIconKind.Settings),
            ),
          selected = selectedDestination.name,
          onSelected = { key -> MainDestination.entries.firstOrNull { it.name == key }?.let(onDestinationSelected) },
          modifier = Modifier.padding(start = 14.dp, end = 14.dp, bottom = 10.dp),
        )
      }
    },
  ) { innerPadding ->
    Column(
      Modifier
        .padding(innerPadding)
        .fillMaxSize()
        .background(tokens.colors.pageBg),
    ) {
      if (includeReferenceStatusBar) {
        ReferenceStatusBar()
      }
      if (state.isSyncing || state.isSyncSetupInFlight) {
        LinearProgressIndicator(Modifier.fillMaxWidth(), color = tokens.colors.accent)
      }
      state.diagnostics.lastError?.let { FeedbackBanner(it, isError = true) }
      when {
        itemDetailStableId != null ->
          ItemDetailPage(
            item = state.items.firstOrNull { it.stableId == itemDetailStableId },
            state = state,
            actionState = actionState,
            wifiOnlyBlocked = wifiOnlyBlocked,
            initialSheet = initialDetailSheet,
            onBack = onBackFromDetail,
            onCopyItem = onCopyItem,
            onDownloadToCache = onDownloadToCache,
            onCopyThumbnail = onCopyThumbnail,
            onDeleteSyncRecord = onDeleteSyncRecord,
            onRemoveLocalCache = onRemoveLocalCache,
          )
        settingsDetail == SettingsDetailDestination.KeepAlive ->
          KeepAlivePage(state = state, onBack = onBackFromDetail)
        settingsDetail == SettingsDetailDestination.FloatingBall ->
          FloatingBallSettingsPage(
            state = state,
            onBack = onBackFromDetail,
            onOverlayEnabledChange = onOverlayEnabledChange,
            onOverlayClickActionChange = onOverlayClickActionChange,
            onOverlaySnapEdgeChange = onOverlaySnapEdgeChange,
            onOverlaySizeChange = onOverlaySizeChange,
            onOverlayIdleOpacityChange = onOverlayIdleOpacityChange,
            onOverlayVerticalFractionChange = onOverlayVerticalFractionChange,
          )
        settingsDetail == SettingsDetailDestination.Pairing ->
          PairingPage(
            state = state,
            onBack = onBackFromDetail,
            onDeviceNameChange = onDeviceNameChange,
            onCreateSyncSpace = onCreateSyncSpace,
            onJoinSyncSpace = onJoinSyncSpace,
            onCreateInvite = onCreateInvite,
          )
        settingsDetail == SettingsDetailDestination.ServerAdvanced ->
          ServerAdvancedPage(
            state = state,
            onBack = onBackFromDetail,
            onServerUrlChange = onServerUrlChange,
            onCheckHealth = onCheckHealth,
            onRefreshInfo = onRefreshInfo,
            onSyncNow = onSyncNow,
          )
        selectedDestination == MainDestination.History ->
          HistoryPage(
            state = state,
            onOpenSettings = { onDestinationSelected(MainDestination.Settings) },
            onSyncNow = onSyncNow,
            onOpenItemDetail = onOpenItemDetail,
          )
        selectedDestination == MainDestination.Devices ->
          DevicesPage(
            state = state,
            onCreateInvite = onCreateInvite,
            onRefresh = onRefreshInfo,
          )
        selectedDestination == MainDestination.Files ->
          FilesPage(
            state = state,
            wifiOnlyBlocked = wifiOnlyBlocked,
            onUseItem = onUseItem,
            onOpenItemDetail = onOpenItemDetail,
          )
        selectedDestination == MainDestination.Settings ->
          SettingsOverviewPage(
            state = state,
            onSyncNow = onSyncNow,
            onWifiOnlyChange = onWifiOnlyChange,
            onOverlayEnabledChange = onOverlayEnabledChange,
            onEncryptionEnabledChange = onEncryptionEnabledChange,
            onOpenSettingsDetail = onOpenSettingsDetail,
          )
      }
    }
  }
}

@Composable
private fun ReferenceStatusBar() {
  Row(
    modifier =
      Modifier
        .fillMaxWidth()
        .height(22.dp)
        .padding(start = 18.dp, end = 18.dp, top = 4.dp),
    verticalAlignment = Alignment.Top,
    horizontalArrangement = Arrangement.SpaceBetween,
  ) {
    Text("22:44", color = LocalClipDockTokens.current.colors.ink, fontSize = 13.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold)
    Text("5G 100%", color = LocalClipDockTokens.current.colors.ink, fontSize = 12.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold)
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ItemDetailPage(
  item: ClipHistoryItem?,
  state: ClipDockUiState,
  actionState: MobileV4ActionState,
  wifiOnlyBlocked: Boolean,
  initialSheet: MobileV4InitialSheet?,
  onBack: () -> Unit,
  onCopyItem: (ClipHistoryItem) -> Unit,
  onDownloadToCache: (ClipHistoryItem) -> Unit,
  onCopyThumbnail: (ClipHistoryItem) -> Unit,
  onDeleteSyncRecord: (ClipHistoryItem) -> Unit,
  onRemoveLocalCache: (ClipHistoryItem) -> Unit,
) {
  var showRemoteSheet by remember { mutableStateOf(initialSheet == MobileV4InitialSheet.RemoteRetrieval) }
  var showDeleteConfirm by remember { mutableStateOf(initialSheet == MobileV4InitialSheet.DeleteConfirm) }

  LaunchedEffect(item?.stableId) {
    if (item == null) {
      onBack()
    }
  }
  BackHandler {
    when {
      showDeleteConfirm -> showDeleteConfirm = false
      showRemoteSheet -> showRemoteSheet = false
      else -> onBack()
    }
  }
  if (item == null) {
    EmptyState("记录已删除", "这条同步记录已经从当前历史中移除。", null, null)
    return
  }

  val actions =
    mobileV4DetailActions(
      item = item,
      p2pEnabled = state.p2pEnabled,
      wifiOnlyBlocked = wifiOnlyBlocked,
      inFlightKinds = actionState.inFlightKinds(item.stableId),
    )
  Box(Modifier.fillMaxSize().testTag(MobileV4Tags.ItemDetailScreen)) {
    if (item.type == ClipItemType.Image) {
      ImageDetailPhotoPage(
        item = item,
        state = state,
        actions = actions,
        onBack = onBack,
        onCopyItem = onCopyItem,
        onDownloadToCache = onDownloadToCache,
        onCopyThumbnail = onCopyThumbnail,
        onRemoveLocalCache = onRemoveLocalCache,
        onDelete = { showDeleteConfirm = true },
      )
    } else {
      LazyColumn(
        contentPadding = PaddingValues(start = 14.dp, top = 15.dp, end = 14.dp, bottom = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize(),
      ) {
        item {
          ItemDetailTopBar(item = item, onBack = onBack)
        }
        item {
          ItemDetailSummary(item = item)
        }
        item {
          ItemDetailContentPreview(item = item)
        }
        item {
          ItemDetailInlineActions(
            actions = actions,
            onPrimary = {
              when (actions.primary.kind) {
                MobileV4ActionKind.Copy -> onCopyItem(item)
                MobileV4ActionKind.ShowRemoteRetrieval -> onDownloadToCache(item)
                else -> Unit
              }
            },
            onDelete = { showDeleteConfirm = true },
          )
        }
        item {
          ItemDetailMetaGrid(item = item, state = state)
        }
      }
    }
    if (showRemoteSheet) {
      V4SheetOverlay(testTag = MobileV4Tags.RemoteRetrievalSheet, withGrabber = true) {
        RemoteRetrievalSheetContent(
          item = item,
          actions = actions,
          onDownloadToCache = {
            showRemoteSheet = false
            onDownloadToCache(item)
          },
          onCopyThumbnail = {
            showRemoteSheet = false
            onCopyThumbnail(item)
          },
        )
      }
    }
    if (showDeleteConfirm) {
      V4SheetOverlay(testTag = MobileV4Tags.DeleteConfirmSheet, withGrabber = false) {
        DeleteConfirmSheetContent(
          actions = actions,
          onRemoveLocalCache = {
            showDeleteConfirm = false
            onRemoveLocalCache(item)
          },
          onDeleteSyncRecord = {
            showDeleteConfirm = false
            onBack()
            onDeleteSyncRecord(item)
          },
          onCancel = { showDeleteConfirm = false },
        )
      }
    }
  }
}

@Composable
private fun ImageDetailPhotoPage(
  item: ClipHistoryItem,
  state: ClipDockUiState,
  actions: MobileV4DetailActions,
  onBack: () -> Unit,
  onCopyItem: (ClipHistoryItem) -> Unit,
  onDownloadToCache: (ClipHistoryItem) -> Unit,
  onCopyThumbnail: (ClipHistoryItem) -> Unit,
  onRemoveLocalCache: (ClipHistoryItem) -> Unit,
  onDelete: () -> Unit,
) {
  LazyColumn(
    contentPadding = PaddingValues(start = 14.dp, top = 15.dp, end = 14.dp, bottom = 18.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp),
    modifier = Modifier.fillMaxSize().background(LocalClipDockTokens.current.colors.pageBg),
  ) {
    item { ItemDetailTopBar(item = item, onBack = onBack) }
    item {
      val isRetrieving = actions.primary.kind == MobileV4ActionKind.ShowRemoteRetrieval && !actions.primary.enabled && actions.primary.label == "取回中"
      Box(
        modifier =
          Modifier
            .fillMaxWidth()
            .height(340.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(LocalClipDockTokens.current.colors.mediaBg),
      ) {
        val bitmap by rememberImageBitmap(item.thumbnailUri ?: item.localUri)
        if (bitmap != null) {
          Image(bitmap = bitmap!!, contentDescription = item.displayTitle, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
          HistoryMediaFallback(HistoryCardVariant.Image, Modifier.fillMaxSize())
        }
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Transparent, Color(0xB80F172A)))))
        if (isRetrieving) {
          LinearProgressIndicator(
            modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(3.dp),
            color = LocalClipDockTokens.current.colors.accent2,
            trackColor = Color.White.copy(alpha = 0.18f),
          )
        }
        Row(
          modifier = Modifier.align(Alignment.BottomStart).padding(14.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
          ClipDockSymbol(ClipDockIconKind.Image, Modifier.size(16.dp), color = Color.White)
          Text("图片预览", color = Color.White, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.ExtraBold)
        }
      }
    }
    item {
      ItemDetailInlineActions(
        actions = actions,
        onPrimary = {
          when (actions.primary.kind) {
            MobileV4ActionKind.Copy -> onCopyItem(item)
            MobileV4ActionKind.ShowRemoteRetrieval -> onDownloadToCache(item)
            else -> Unit
          }
        },
        onDelete = onDelete,
      )
    }
    item {
      ImageDetailInfoList(item = item, state = state)
    }
  }
}

@Composable
private fun ImageDetailPhotoCanvas(
  item: ClipHistoryItem,
  modifier: Modifier = Modifier,
) {
  val tokens = LocalClipDockTokens.current
  val localBitmap by rememberImageBitmap(item.localUri)
  val thumbnailBitmap by rememberImageBitmap(item.thumbnailUri)
  val displayBitmap = localBitmap ?: thumbnailBitmap
  val showingOriginal = localBitmap != null && item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank()
  Box(modifier = modifier, contentAlignment = Alignment.Center) {
    if (displayBitmap != null) {
      Image(
        bitmap = displayBitmap,
        contentDescription = item.displayTitle,
        contentScale = ContentScale.Fit,
        modifier =
          Modifier
            .fillMaxSize(),
      )
    } else {
      Box(
        modifier =
          Modifier
            .fillMaxWidth()
            .height(240.dp)
            .padding(horizontal = 36.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(tokens.colors.surface2),
        contentAlignment = Alignment.Center,
      ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
          ClipDockSymbol(ClipDockIconKind.Image, Modifier.size(42.dp), color = tokens.colors.accent2)
          Text("等待图片预览", color = tokens.colors.muted, fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.Bold)
        }
      }
    }
    ImageDetailStageOverlay(
      item = item,
      showingOriginal = showingOriginal,
      modifier = Modifier.align(Alignment.TopCenter),
    )
  }
}

@Composable
private fun ImageDetailStageOverlay(
  item: ClipHistoryItem,
  showingOriginal: Boolean,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier.fillMaxWidth().padding(start = 18.dp, top = 96.dp, end = 18.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.SpaceBetween,
  ) {
    ImageDetailStageBadge(item = item, showingOriginal = showingOriginal)
    Text("1 / 1", color = Color.White.copy(alpha = 0.78f), fontSize = 11.sp, lineHeight = 14.sp, fontFamily = FontFamily.Monospace)
  }
}

@Composable
private fun ImageDetailStageBadge(item: ClipHistoryItem, showingOriginal: Boolean) {
  val tokens = LocalClipDockTokens.current
  val label =
    when {
      showingOriginal -> "清晰原图 · 本机可复制"
      item.transferState == TransferState.DiscoveringPeer -> "正在查找来源设备"
      item.transferState == TransferState.Downloading -> "正在下载原图"
      item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed -> "原图取回失败"
      item.thumbnailUri.isNullOrBlank() -> "原图在远端"
      else -> "同步缩略图 · 原图在远端"
    }
  Surface(
    shape = CircleShape,
    color = Color.Black.copy(alpha = 0.58f),
    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.16f)),
  ) {
    Row(
      modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      ClipDockSymbol(
        if (item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed) ClipDockIconKind.Alert else if (showingOriginal) ClipDockIconKind.Check else ClipDockIconKind.Download,
        Modifier.size(16.dp),
        color = if (showingOriginal) tokens.colors.accent else tokens.colors.accent2,
      )
      Text(label, color = Color.White, fontSize = 12.sp, lineHeight = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
  }
}

@Composable
private fun ImageDetailTopOverlay(
  item: ClipHistoryItem,
  onBack: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier =
      modifier
        .fillMaxWidth()
        .height(96.dp)
        .background(
          Brush.verticalGradient(
            listOf(Color.Black.copy(alpha = 0.68f), Color.Black.copy(alpha = 0.24f), Color.Transparent),
          ),
        )
  ) {
    Spacer(Modifier.height(24.dp))
    Row(
      modifier = Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 8.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
      PhotoOverlayIconButton(ClipDockIconKind.Chevron, "返回", onBack)
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(item.displayTitle, color = Color.White, fontSize = 13.sp, lineHeight = 16.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text("${item.sourceName?.takeIf(String::isNotBlank) ?: "未知来源"} · ${relativeTimeLabel(item.copiedAtMillis)}", color = Color.White.copy(alpha = 0.72f), fontSize = 11.sp, lineHeight = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
      PhotoOverlayIconButton(ClipDockIconKind.More, "更多", onClick = {}, enabled = false)
    }
  }
}

@Composable
private fun PhotoOverlayIconButton(
  icon: ClipDockIconKind,
  contentDescription: String,
  onClick: () -> Unit,
  enabled: Boolean = true,
) {
  Surface(
    shape = CircleShape,
    color = Color.Black.copy(alpha = 0.42f),
    contentColor = Color.White,
    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.12f)),
    modifier =
      Modifier
        .size(40.dp)
        .clip(CircleShape)
        .clickable(enabled = enabled, onClick = onClick)
        .semantics { this.contentDescription = contentDescription },
  ) {
    Box(contentAlignment = Alignment.Center) {
      ClipDockSymbol(icon, Modifier.size(19.dp), color = Color.White.copy(alpha = if (enabled) 1f else 0.38f))
    }
  }
}

@Composable
private fun ImageDetailInfoDrawer(
  item: ClipHistoryItem,
  state: ClipDockUiState,
  actions: MobileV4DetailActions,
  expanded: Boolean,
  height: androidx.compose.ui.unit.Dp,
  onExpandedChange: (Boolean) -> Unit,
  onCopyItem: () -> Unit,
  onDownloadToCache: () -> Unit,
  onCopyThumbnail: () -> Unit,
  onRemoveLocalCache: () -> Unit,
  onDelete: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp),
    color = tokens.colors.surface,
    border = BorderStroke(1.dp, tokens.colors.softLine),
    shadowElevation = 18.dp,
    modifier =
      modifier
        .fillMaxWidth()
        .height(height)
        .pointerInput(expanded) {
          detectVerticalDragGestures { _, dragAmount ->
            when {
              dragAmount < -9f -> onExpandedChange(true)
              dragAmount > 9f -> onExpandedChange(false)
            }
          }
        },
  ) {
    LazyColumn(
      modifier = Modifier.fillMaxSize(),
      contentPadding = PaddingValues(start = 16.dp, top = 10.dp, end = 16.dp, bottom = 18.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      item {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
          Box(
            Modifier
              .width(42.dp)
              .height(4.dp)
              .clip(CircleShape)
              .background(tokens.colors.line),
          )
          ImageDetailDrawerHeader(
            item = item,
            actions = actions,
            expanded = expanded,
            onExpandedChange = onExpandedChange,
            onCopyItem = onCopyItem,
            onDownloadToCache = onDownloadToCache,
          )
        }
      }
      item {
        ImageDetailStatusPills(item = item, state = state)
      }
      item {
        if (expanded) {
          ImageDetailExpandedActions(
            item = item,
            actions = actions,
            onCopyItem = onCopyItem,
            onDownloadToCache = onDownloadToCache,
            onCopyThumbnail = onCopyThumbnail,
            onRemoveLocalCache = onRemoveLocalCache,
          )
        } else {
          ImageDetailUtilityActions(
            item = item,
            actions = actions,
            onExpandedChange = onExpandedChange,
            onCopyThumbnail = onCopyThumbnail,
            onRemoveLocalCache = onRemoveLocalCache,
          )
        }
      }
      if (expanded) {
        item {
          ImageDetailInfoSection(item = item, state = state)
        }
        item {
          ImageDetailDangerActions(
            actions = actions,
            onDelete = onDelete,
          )
        }
      }
    }
  }
}

@Composable
private fun ImageDetailDrawerHeader(
  item: ClipHistoryItem,
  actions: MobileV4DetailActions,
  expanded: Boolean,
  onExpandedChange: (Boolean) -> Unit,
  onCopyItem: () -> Unit,
  onDownloadToCache: () -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  val hasLocalOriginal = mobileV4HasLocalCopySemantics(item)
  val primaryLabel =
    when {
      hasLocalOriginal -> "复制原图"
      expanded -> actions.downloadToCache.label
      else -> actions.primary.label
    }
  val primaryEnabled =
    when {
      hasLocalOriginal -> actions.primary.enabled
      expanded -> actions.downloadToCache.enabled
      else -> actions.primary.enabled
    }
  val primaryTone = if (hasLocalOriginal) ClipDockTone.Green else actions.primary.tone
  Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
      Text(item.displayTitle, color = tokens.colors.ink, fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
      Text(imageDrawerSubtitle(item), color = tokens.colors.muted, fontSize = 12.sp, lineHeight = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    ImageDetailPrimaryButton(
      label = primaryLabel,
      tone = primaryTone,
      enabled = primaryEnabled,
      onClick = {
        when {
          hasLocalOriginal -> onCopyItem()
          expanded -> onDownloadToCache()
          else -> onExpandedChange(true)
        }
      },
      loading = primaryLabel == "取回中",
    )
  }
}

@Composable
private fun ImageDetailPrimaryButton(
  label: String,
  tone: ClipDockTone,
  enabled: Boolean,
  onClick: () -> Unit,
  loading: Boolean = false,
) {
  val tokens = LocalClipDockTokens.current
  val background =
    when (tone) {
      ClipDockTone.Green -> tokens.colors.accent
      ClipDockTone.Amber -> tokens.colors.warn
      ClipDockTone.Red -> tokens.colors.danger
      ClipDockTone.Blue -> tokens.colors.accent2
      ClipDockTone.Neutral -> tokens.colors.muted
    }
  Surface(
    shape = RoundedCornerShape(12.dp),
    color = if (enabled) background else tokens.colors.surface3,
    contentColor = if (enabled) Color.White else tokens.colors.faint,
    modifier =
      Modifier
        .width(104.dp)
        .height(42.dp)
        .clip(RoundedCornerShape(12.dp))
        .clickable(enabled = enabled, onClick = onClick)
        .testTag(MobileV4Tags.DetailPrimaryAction),
  ) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.padding(horizontal = 8.dp)) {
      if (loading) {
        CircularProgressIndicator(
          modifier = Modifier.size(18.dp),
          strokeWidth = 2.dp,
          color = if (enabled) Color.White else tokens.colors.accent2,
          trackColor = Color.Transparent,
        )
      } else {
        Text(label, fontSize = 13.sp, lineHeight = 16.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
    }
  }
}

@Composable
private fun ImageDetailStatusPills(
  item: ClipHistoryItem,
  state: ClipDockUiState,
) {
  val hasLocalOriginal = mobileV4HasLocalCopySemantics(item)
  Row(
    horizontalArrangement = Arrangement.spacedBy(7.dp),
    verticalAlignment = Alignment.CenterVertically,
    modifier = Modifier.fillMaxWidth(),
  ) {
    ImageDetailPill(
      label = historyDetailStatus(item),
      tone =
        when {
          item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed -> ClipDockTone.Red
          hasLocalOriginal -> ClipDockTone.Green
          else -> ClipDockTone.Amber
        },
    )
    ImageDetailPill(
      label = if (hasLocalOriginal) "原图已下载" else if (item.thumbnailUri.isNullOrBlank()) "无缩略图" else "缩略图可用",
      tone = if (hasLocalOriginal) ClipDockTone.Green else ClipDockTone.Blue,
    )
    ImageDetailPill(
      label = if (state.wifiOnly) "仅 Wi-Fi" else "任意网络",
      tone = ClipDockTone.Neutral,
    )
  }
}

@Composable
private fun ImageDetailPill(label: String, tone: ClipDockTone) {
  val tokens = LocalClipDockTokens.current
  val background =
    when (tone) {
      ClipDockTone.Green -> tokens.colors.accentSoft
      ClipDockTone.Blue -> tokens.colors.blueSoft
      ClipDockTone.Amber -> tokens.colors.warnSoft
      ClipDockTone.Red -> tokens.colors.dangerSoft
      ClipDockTone.Neutral -> tokens.colors.surface2
    }
  val foreground =
    when (tone) {
      ClipDockTone.Green -> tokens.colors.accent
      ClipDockTone.Blue -> tokens.colors.accent2
      ClipDockTone.Amber -> tokens.colors.warn
      ClipDockTone.Red -> tokens.colors.danger
      ClipDockTone.Neutral -> tokens.colors.muted
    }
  Surface(
    shape = RoundedCornerShape(7.dp),
    color = background,
    contentColor = foreground,
    border = if (tone == ClipDockTone.Neutral) BorderStroke(1.dp, tokens.colors.line) else null,
  ) {
    Text(label, modifier = Modifier.padding(horizontal = 8.dp, vertical = 5.dp), fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
  }
}

@Composable
private fun ImageDetailUtilityActions(
  item: ClipHistoryItem,
  actions: MobileV4DetailActions,
  onExpandedChange: (Boolean) -> Unit,
  onCopyThumbnail: () -> Unit,
  onRemoveLocalCache: () -> Unit,
) {
  val hasLocalOriginal = mobileV4HasLocalCopySemantics(item)
  Row(
    modifier = Modifier.fillMaxWidth().padding(top = 1.dp),
    horizontalArrangement = Arrangement.spacedBy(8.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    ImageDetailUtilityAction(
      icon = ClipDockIconKind.Image,
      label = "复制缩略图",
      tone = ClipDockTone.Blue,
      enabled = actions.copyThumbnail.enabled,
      onClick = onCopyThumbnail,
      modifier = Modifier.weight(1f),
    )
    ImageDetailUtilityAction(
      icon = ClipDockIconKind.Share,
      label = "分享",
      tone = ClipDockTone.Neutral,
      enabled = false,
      onClick = {},
      modifier = Modifier.weight(1f),
    )
    if (hasLocalOriginal) {
      ImageDetailUtilityAction(
        icon = ClipDockIconKind.Folder,
        label = "移除缓存",
        tone = ClipDockTone.Amber,
        enabled = actions.removeLocalCache.enabled,
        onClick = onRemoveLocalCache,
        modifier = Modifier.weight(1f),
      )
    } else {
      ImageDetailUtilityAction(
        icon = ClipDockIconKind.More,
        label = "详情",
        tone = ClipDockTone.Neutral,
        enabled = true,
        onClick = { onExpandedChange(true) },
        modifier = Modifier.weight(1f),
      )
    }
  }
}

@Composable
private fun ImageDetailUtilityAction(
  icon: ClipDockIconKind,
  label: String,
  tone: ClipDockTone,
  enabled: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val tokens = LocalClipDockTokens.current
  val background =
    when (tone) {
      ClipDockTone.Green -> tokens.colors.accentSoft
      ClipDockTone.Blue -> tokens.colors.blueSoft
      ClipDockTone.Amber -> tokens.colors.warnSoft
      ClipDockTone.Red -> tokens.colors.dangerSoft
      ClipDockTone.Neutral -> tokens.colors.surface2
    }
  val foreground =
    when (tone) {
      ClipDockTone.Green -> tokens.colors.accent
      ClipDockTone.Blue -> tokens.colors.accent2
      ClipDockTone.Amber -> tokens.colors.warn
      ClipDockTone.Red -> tokens.colors.danger
      ClipDockTone.Neutral -> tokens.colors.ink
    }
  Surface(
    shape = RoundedCornerShape(13.dp),
    color = if (enabled) background else tokens.colors.surface2,
    border = BorderStroke(1.dp, if (tone == ClipDockTone.Neutral) tokens.colors.line else Color.Transparent),
    contentColor = if (enabled) foreground else tokens.colors.faint,
    modifier =
      modifier
        .height(58.dp)
        .clip(RoundedCornerShape(13.dp))
        .clickable(enabled = enabled, onClick = onClick),
  ) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
      ClipDockSymbol(icon, Modifier.size(19.dp), color = if (enabled) foreground else tokens.colors.faint)
      Text(label, fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
  }
}

@Composable
private fun ImageDetailExpandedActions(
  item: ClipHistoryItem,
  actions: MobileV4DetailActions,
  onCopyItem: () -> Unit,
  onDownloadToCache: () -> Unit,
  onCopyThumbnail: () -> Unit,
  onRemoveLocalCache: () -> Unit,
) {
  val hasLocalOriginal = mobileV4HasLocalCopySemantics(item)
  Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
    if (hasLocalOriginal) {
      ImageDetailActionCard("复制原图", "写入剪贴板", ClipDockTone.Green, actions.primary.enabled, onCopyItem, Modifier.weight(1f), primary = true)
      ImageDetailActionCard("移除缓存", "保留同步记录", ClipDockTone.Amber, actions.removeLocalCache.enabled, onRemoveLocalCache, Modifier.weight(1f))
      ImageDetailActionCard(actions.copyThumbnail.label, "快速使用预览", ClipDockTone.Blue, actions.copyThumbnail.enabled, onCopyThumbnail, Modifier.weight(1f))
    } else {
      ImageDetailActionCard(actions.downloadToCache.label, "下载到本机缓存", ClipDockTone.Blue, actions.downloadToCache.enabled, onDownloadToCache, Modifier.weight(1f), primary = true)
      ImageDetailActionCard("复制缩略图", "保留远端原图", ClipDockTone.Neutral, actions.copyThumbnail.enabled, onCopyThumbnail, Modifier.weight(1f))
    }
  }
}

@Composable
private fun ImageDetailActionCard(
  title: String,
  subtitle: String,
  tone: ClipDockTone,
  enabled: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  primary: Boolean = false,
) {
  val tokens = LocalClipDockTokens.current
  val primaryColor = if (tone == ClipDockTone.Green) tokens.colors.accent else tokens.colors.accent2
  Surface(
    shape = RoundedCornerShape(14.dp),
    color = if (primary && enabled) primaryColor else tokens.colors.surface2,
    border = BorderStroke(1.dp, if (primary && enabled) Color.Transparent else tokens.colors.line),
    contentColor = if (primary && enabled) Color.White else if (enabled) tokens.colors.ink else tokens.colors.faint,
    modifier =
      modifier
        .height(64.dp)
        .clip(RoundedCornerShape(14.dp))
        .clickable(enabled = enabled, onClick = onClick),
  ) {
    Column(
      modifier = Modifier.padding(horizontal = 8.dp, vertical = 9.dp),
      verticalArrangement = Arrangement.Center,
    ) {
      Text(title, fontSize = 12.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
      Text(subtitle, fontSize = 10.sp, lineHeight = 12.sp, color = if (primary && enabled) Color.White.copy(alpha = 0.72f) else tokens.colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
  }
}

@Composable
private fun ImageDetailInfoSection(item: ClipHistoryItem, state: ClipDockUiState) {
  Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
    ImageDetailInfoGroup("内容") {
      ImageDetailMetaRow("文件名", item.displayTitle)
      ImageDetailMetaRow("尺寸", imageOriginalDimensionsLabel(item))
      ImageDetailMetaRow("原图大小", imageOriginalSizeLabel(item))
    }
    ImageDetailInfoGroup("同步") {
      ImageDetailMetaRow("来源设备", item.sourceName?.takeIf(String::isNotBlank) ?: "未知来源")
      ImageDetailMetaRow("同步空间", state.syncId ?: "未加入")
      ImageDetailMetaRow("assetId", item.assetId?.let(::shortIdentifier) ?: "无可取回资产")
      ImageDetailMetaRow("contentHash", shortIdentifier(item.contentHash))
    }
    ImageDetailInfoGroup("缓存") {
      ImageDetailMetaRow("本机缓存", imageLocalCacheLabel(item))
      ImageDetailMetaRow("缩略图", imageThumbnailDescription(item))
      ImageDetailMetaRow("原图状态", imageOriginalStateLabel(item))
      ImageDetailMetaRow("保留策略", "30 天")
      ImageDetailMetaRow("复制次数", "${item.copyCount} 次 · ${relativeTimeLabel(item.copiedAtMillis)}")
    }
  }
}

@Composable
private fun ImageDetailInfoGroup(
  title: String,
  content: @Composable () -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  Column(
    modifier = Modifier.fillMaxWidth().padding(top = 11.dp, bottom = 10.dp),
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Text(title, color = tokens.colors.muted, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.ExtraBold)
    content()
  }
}

@Composable
private fun ImageDetailMetaRow(label: String, value: String) {
  val tokens = LocalClipDockTokens.current
  Row(
    modifier = Modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.spacedBy(12.dp),
    verticalAlignment = Alignment.Top,
  ) {
    Text(label, color = tokens.colors.muted, fontSize = 12.sp, lineHeight = 16.sp, modifier = Modifier.width(82.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
    Text(value, color = tokens.colors.ink, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
  }
}

@Composable
private fun ImageDetailDangerActions(
  actions: MobileV4DetailActions,
  onDelete: () -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = RoundedCornerShape(14.dp),
    color = tokens.colors.dangerSoft,
    contentColor = tokens.colors.danger,
    modifier =
      Modifier
        .fillMaxWidth()
        .height(44.dp)
        .clip(RoundedCornerShape(14.dp))
        .clickable(enabled = actions.deleteSyncRecord.enabled, onClick = onDelete)
        .testTag(MobileV4Tags.DetailTrashAction),
  ) {
    Row(
      modifier = Modifier.padding(horizontal = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      ClipDockSymbol(ClipDockIconKind.Trash, Modifier.size(17.dp), color = tokens.colors.danger)
      Text(actions.deleteSyncRecord.label, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.ExtraBold)
    }
  }
}

@Composable
private fun V4SheetOverlay(
  testTag: String,
  withGrabber: Boolean,
  content: @Composable () -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  Box(
    modifier =
      Modifier
        .fillMaxSize()
        .background(Color(0x6B060D0D)),
    contentAlignment = Alignment.BottomCenter,
  ) {
    Surface(
      shape = RoundedCornerShape(if (withGrabber) 28.dp else 26.dp),
      color = tokens.colors.surface,
      border = BorderStroke(1.dp, tokens.colors.softLine),
      shadowElevation = 18.dp,
      modifier =
        Modifier
          .fillMaxWidth()
          .padding(start = 14.dp, end = 14.dp, bottom = 14.dp)
          .testTag(testTag),
    ) {
      Column(
        modifier = Modifier.fillMaxWidth().padding(if (withGrabber) 12.dp else 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        if (withGrabber) {
          Box(
            modifier =
              Modifier
                .align(Alignment.CenterHorizontally)
                .width(42.dp)
                .height(4.dp)
                .clip(CircleShape)
                .background(tokens.colors.line),
          )
        }
        content()
      }
    }
  }
}

@Composable
private fun ItemDetailTopBar(item: ClipHistoryItem, onBack: () -> Unit) {
  Row(
    modifier = Modifier.fillMaxWidth(),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    ClipDockIconButton(ClipDockIconKind.Chevron, "返回", onClick = onBack)
    Text("${item.type.label}详情", color = LocalClipDockTokens.current.colors.ink, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.weight(1f))
    ClipDockIconButton(ClipDockIconKind.Share, "分享", onClick = {}, enabled = false)
  }
}

@Composable
private fun ItemDetailSummary(item: ClipHistoryItem) {
  val display = historyDetailDisplay(item)
  Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
    HistoryActionPill(display.contentType, display.previewIcon, typeTone(item.type))
    HistoryActionPill(display.source, if (item.sourceName?.contains("Pixel", ignoreCase = true) == true) ClipDockIconKind.Devices else ClipDockIconKind.Window, ClipDockTone.Neutral)
    HistoryActionPill(display.timeLabel, ClipDockIconKind.History, ClipDockTone.Neutral)
  }
}

@Composable
private fun ItemDetailImagePreview(item: ClipHistoryItem) {
  val previewUri =
    when (item.type) {
      ClipItemType.Link -> item.linkPreviewUri
      else -> item.thumbnailUri ?: item.localUri
    }
  val bitmap by rememberImageBitmap(previewUri)
  Box(
    modifier =
      Modifier
        .fillMaxWidth()
        .height(182.dp)
        .clip(RoundedCornerShape(20.dp))
        .background(LocalClipDockTokens.current.colors.surface2),
    contentAlignment = Alignment.Center,
  ) {
    if (bitmap != null) {
      Image(bitmap = bitmap!!, contentDescription = item.displayTitle, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    } else {
      Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ClipDockSymbol(if (item.type == ClipItemType.Link) ClipDockIconKind.Link else ClipDockIconKind.Image, Modifier.size(34.dp), color = LocalClipDockTokens.current.colors.accent2)
        Text(if (item.type == ClipItemType.Link) "链接预览" else "远端原图", style = MaterialTheme.typography.labelMedium, color = LocalClipDockTokens.current.colors.muted)
      }
    }
  }
}

@Composable
private fun ItemDetailContentPreview(item: ClipHistoryItem) {
  val text =
    when (item.type) {
      ClipItemType.Text,
      ClipItemType.RichText,
      ClipItemType.Link -> historyFullText(item)
      ClipItemType.Image -> "列表只显示同步缩略图；原图需要 P2P 取回。"
      ClipItemType.File -> item.detail.ifBlank { item.body.ifBlank { "文件内容按需下载到本机缓存。" } }
      else -> item.body.ifBlank { item.detail }
    }
  ClipDockCard {
    Text(
      text,
      color = LocalClipDockTokens.current.colors.ink,
      fontSize = 16.sp,
      lineHeight = 24.sp,
      fontWeight = FontWeight.Normal,
      maxLines = 12,
      overflow = TextOverflow.Ellipsis,
    )
  }
}

@Composable
private fun ItemDetailInlineActions(
  actions: MobileV4DetailActions,
  onPrimary: () -> Unit,
  onDelete: () -> Unit,
) {
  Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
    DetailActionTile(
      actions.primary.icon,
      actions.primary.label,
      ClipDockTone.Green,
      actions.primary.enabled,
      onPrimary,
      Modifier.weight(1f),
      primary = true,
      loading = actions.primary.label == "取回中" || actions.primary.label == "复制中",
    )
    DetailActionTile(ClipDockIconKind.Pin, "固定", ClipDockTone.Neutral, enabled = false, onClick = {}, modifier = Modifier.weight(1f))
    DetailActionTile(ClipDockIconKind.Share, "分享", ClipDockTone.Neutral, enabled = false, onClick = {}, modifier = Modifier.weight(1f))
  }
}

@Composable
private fun DetailActionTile(
  icon: ClipDockIconKind,
  label: String,
  tone: ClipDockTone,
  enabled: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  primary: Boolean = false,
  loading: Boolean = false,
) {
  val tokens = LocalClipDockTokens.current
  val colors = historyToneColors(tone)
  Column(
    modifier =
      modifier
        .height(62.dp)
        .clip(RoundedCornerShape(16.dp))
        .background(if (primary) tokens.colors.accentSoft else tokens.colors.surface)
        .clickable(enabled = enabled, onClick = onClick)
        .padding(vertical = 8.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.Center,
  ) {
    if (loading) {
      CircularProgressIndicator(
        modifier = Modifier.size(22.dp),
        strokeWidth = 2.dp,
        color = colors.first,
        trackColor = colors.first.copy(alpha = 0.14f),
      )
    } else {
      ClipDockSymbol(icon, Modifier.size(23.dp), color = if (enabled) colors.first else tokens.colors.muted)
    }
    Text(label, color = if (enabled) colors.first else tokens.colors.muted, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
  }
}

@Composable
private fun ItemDetailMetaGrid(item: ClipHistoryItem, state: ClipDockUiState) {
  val display = historyDetailDisplay(item)
  DetailInfoList(
    rows =
      listOf(
        "来源" to display.source,
        "类型" to display.contentType,
        "同步状态" to display.status,
        "空间" to (state.syncId ?: "未加入"),
        "内容长度" to "${historyFullText(item).length} 个字符",
      ),
  )
}

@Composable
private fun ImageDetailInfoList(item: ClipHistoryItem, state: ClipDockUiState) {
  DetailInfoList(
    rows =
      listOf(
        "文件名" to item.displayTitle.ifBlank { "图片" },
        "尺寸" to imageOriginalDimensionsLabel(item),
        "大小" to imageOriginalSizeLabel(item),
        "来源" to (item.sourceName?.takeIf(String::isNotBlank) ?: "未知来源"),
        "同步状态" to historyDetailStatus(item),
      ),
  )
}

@Composable
private fun DetailInfoList(rows: List<Pair<String, String>>) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = RoundedCornerShape(16.dp),
    color = tokens.colors.surface,
    border = BorderStroke(1.dp, tokens.colors.softLine),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Column {
      rows.forEachIndexed { index, row ->
        Row(
          modifier = Modifier.fillMaxWidth().heightIn(min = 46.dp).padding(horizontal = 14.dp, vertical = 9.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
          Text(row.first, color = tokens.colors.muted, fontSize = 12.sp, lineHeight = 17.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.width(84.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
          Text(row.second, color = tokens.colors.ink, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        if (index != rows.lastIndex) {
          SettingDivider()
        }
      }
    }
  }
}

@Composable
private fun ItemDetailActionDock(
  actions: MobileV4DetailActions,
  modifier: Modifier = Modifier,
  onPrimary: () -> Unit,
  onDelete: () -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  Surface(
    color = tokens.colors.surface.copy(alpha = 0.97f),
    border = BorderStroke(1.dp, tokens.colors.softLine),
    shadowElevation = 8.dp,
    modifier = modifier.fillMaxWidth().padding(14.dp).clip(RoundedCornerShape(22.dp)),
  ) {
    Row(
      modifier = Modifier.height(66.dp).padding(8.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      Button(
        onClick = onPrimary,
        enabled = actions.primary.enabled,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.weight(1f).height(50.dp).testTag(MobileV4Tags.DetailPrimaryAction),
      ) {
        ClipDockSymbol(actions.primary.icon, Modifier.size(18.dp), color = Color.White)
        Spacer(Modifier.width(8.dp))
        Text(actions.primary.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
      listOf(ClipDockIconKind.Pin, ClipDockIconKind.Share, ClipDockIconKind.Text).forEach { icon ->
        DockIconButton(icon = icon, enabled = false, onClick = {})
      }
      DockIconButton(
        icon = ClipDockIconKind.Trash,
        enabled = actions.deleteSyncRecord.enabled,
        danger = true,
        onClick = onDelete,
        modifier = Modifier.testTag(MobileV4Tags.DetailTrashAction),
      )
    }
  }
}

@Composable
private fun DockIconButton(
  icon: ClipDockIconKind,
  enabled: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  danger: Boolean = false,
) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = RoundedCornerShape(15.dp),
    color = if (danger) tokens.colors.dangerSoft else tokens.colors.surface2,
    contentColor = if (danger) tokens.colors.danger else tokens.colors.muted,
    modifier =
      modifier
        .size(50.dp)
        .clip(RoundedCornerShape(15.dp))
        .clickable(enabled = enabled, onClick = onClick),
  ) {
    Box(contentAlignment = Alignment.Center) {
      ClipDockSymbol(icon, Modifier.size(19.dp), color = if (danger) tokens.colors.danger else tokens.colors.muted)
    }
  }
}

@Composable
private fun RemoteRetrievalSheetContent(
  item: ClipHistoryItem,
  actions: MobileV4DetailActions,
  onDownloadToCache: () -> Unit,
  onCopyThumbnail: () -> Unit,
) {
  Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
      IconTile(ClipDockIconKind.Download, tone = ClipDockTone.Blue)
      Column(Modifier.weight(1f)) {
        Text("取回远端${if (item.type == ClipItemType.Image) "图片" else "文件"}", style = MaterialTheme.typography.titleMedium)
        Text("选择下载后如何处理，不自动覆盖剪贴板。", style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted)
      }
    }
    SheetActionRow(actions.downloadToCache, "下载到本机缓存；下载后可自行复制。", MobileV4Tags.RemoteDownloadToCache, onDownloadToCache, primary = true)
    SheetActionRow(actions.copyThumbnail, "快速使用预览图，保留原图远端状态", MobileV4Tags.RemoteCopyThumbnail, onCopyThumbnail)
  }
}

@Composable
private fun DeleteConfirmSheetContent(
  actions: MobileV4DetailActions,
  onRemoveLocalCache: () -> Unit,
  onDeleteSyncRecord: () -> Unit,
  onCancel: () -> Unit,
) {
  Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(0.dp)) {
    IconTile(ClipDockIconKind.Trash, tone = ClipDockTone.Red, modifier = Modifier.padding(bottom = 13.dp))
    Text("删除这条历史？", fontSize = 18.sp, lineHeight = 22.sp, fontWeight = FontWeight.ExtraBold, color = LocalClipDockTokens.current.colors.ink)
    Text(
      "如果只清理本机缓存，其他设备和同步空间仍保留记录。删除同步记录会从所有设备历史中移除。",
      fontSize = 12.sp,
      lineHeight = 17.sp,
      color = LocalClipDockTokens.current.colors.muted,
      modifier = Modifier.padding(top = 7.dp, bottom = 14.dp),
    )
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
      ConfirmSheetButton(actions.removeLocalCache, MobileV4Tags.DeleteRemoveLocalCache, onRemoveLocalCache)
      ConfirmSheetButton(actions.deleteSyncRecord, MobileV4Tags.DeleteSyncRecord, onDeleteSyncRecord, danger = true)
      ConfirmSheetButton(
        MobileV4DetailAction(
          kind = MobileV4ActionKind.DeleteSyncRecord,
          label = "取消",
          icon = ClipDockIconKind.X,
          enabled = true,
          tone = ClipDockTone.Neutral,
          message = "",
        ),
        MobileV4Tags.DeleteCancel,
        onCancel,
        iconVisible = false,
      )
    }
  }
}

@Composable
private fun SheetActionRow(
  action: MobileV4DetailAction,
  subtitle: String,
  testTag: String,
  onClick: () -> Unit,
  primary: Boolean = false,
) {
  val tokens = LocalClipDockTokens.current
  Row(
    modifier =
      Modifier
        .fillMaxWidth()
        .height(62.dp)
        .clip(RoundedCornerShape(18.dp))
        .background(if (primary) tokens.colors.heroBanner else tokens.colors.surface2)
        .clickable(enabled = action.enabled, onClick = onClick)
        .testTag(testTag)
        .padding(12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    IconTile(action.icon, tone = if (primary) ClipDockTone.Green else action.tone)
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
      Text(action.label, style = MaterialTheme.typography.titleSmall, color = if (primary) Color.White else tokens.colors.ink)
      Text(
        if (action.enabled) subtitle else action.message,
        style = MaterialTheme.typography.bodySmall,
        color = if (primary) Color.White.copy(alpha = 0.74f) else tokens.colors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun ConfirmSheetButton(
  action: MobileV4DetailAction,
  testTag: String,
  onClick: () -> Unit,
  danger: Boolean = false,
  iconVisible: Boolean = true,
) {
  val tokens = LocalClipDockTokens.current
  Row(
    modifier =
      Modifier
        .fillMaxWidth()
        .height(46.dp)
        .clip(RoundedCornerShape(16.dp))
        .background(if (danger) tokens.colors.danger else tokens.colors.surface2)
        .clickable(enabled = action.enabled, onClick = onClick)
        .testTag(testTag),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.Center,
  ) {
    if (iconVisible) {
      ClipDockSymbol(action.icon, Modifier.size(16.dp), color = if (danger) Color.White else tokens.colors.ink)
      Spacer(Modifier.width(8.dp))
    }
    Text(
      action.label,
      color = if (danger) Color.White else if (action.enabled) tokens.colors.ink else tokens.colors.muted,
      fontSize = 13.sp,
      lineHeight = 16.sp,
      fontWeight = FontWeight.ExtraBold,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
  }
}

@Composable
internal fun HistoryPage(
  state: ClipDockUiState,
  onOpenSettings: () -> Unit,
  onSyncNow: () -> Unit,
  onOpenItemDetail: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  var selectedVisualFilter by remember { mutableStateOf(HistoryVisualFilter.All) }
  val filtered = filteredHistoryItems(state.items, selectedVisualFilter)

  Box(modifier = modifier.fillMaxSize()) {
    LazyVerticalStaggeredGrid(
      columns = StaggeredGridCells.Adaptive(164.dp),
      contentPadding = PaddingValues(start = 14.dp, top = 15.dp, end = 14.dp, bottom = 18.dp),
      horizontalArrangement = Arrangement.spacedBy(10.dp),
      verticalItemSpacing = 10.dp,
      modifier = Modifier.fillMaxSize(),
    ) {
      item(span = StaggeredGridItemSpan.FullLine) {
        HistoryStableTopBar(
          state = state,
          onOpenSettings = onOpenSettings,
          onSyncNow = onSyncNow,
        )
      }
      item(span = StaggeredGridItemSpan.FullLine) {
        HistorySearchPill()
      }
      item(span = StaggeredGridItemSpan.FullLine) {
        HistoryVisualFilterRow(
          selected = selectedVisualFilter,
          onSelected = { selectedVisualFilter = it },
          allItems = state.items,
        )
      }
      item(span = StaggeredGridItemSpan.FullLine) {
        HistoryHealthStrip(
          state = state,
          onClick = if (state.tokenPresent) onSyncNow else onOpenSettings,
        )
      }
      if (filtered.isEmpty()) {
        item(span = StaggeredGridItemSpan.FullLine) {
          EmptyState(
            title = if (state.tokenPresent) "暂无同步记录" else "先连接服务端",
            subtitle = if (state.tokenPresent) "点击同步拉取最近剪贴板历史。" else "ClipDock Android 会从同步空间读取最近历史。",
            actionLabel = if (state.tokenPresent) "立即同步" else "打开设置",
            onAction = if (state.tokenPresent) onSyncNow else onOpenSettings,
          )
        }
      } else {
        staggeredItemsIndexed(filtered, key = { _, item -> item.stableId }) { index, item ->
          HistoryStableCard(
            item = item,
            selected = index == 0,
            onOpenDetail = { onOpenItemDetail(item.stableId) },
          )
        }
      }
    }
  }
}

private enum class HistoryVisualFilter(val label: String) {
  All("全部"),
  Text("文本"),
  Link("链接"),
  Image("图片"),
  File("文件"),
}

private enum class HistoryCardVariant(val label: String) {
  Link("Link"),
  Text("Text"),
  Code("Code"),
  Image("Image"),
  Note("Note"),
  File("File"),
}

@Composable
private fun HistoryStableTopBar(
  state: ClipDockUiState,
  onOpenSettings: () -> Unit,
  onSyncNow: () -> Unit,
) {
  Row(
    modifier = Modifier.fillMaxWidth(),
    verticalAlignment = Alignment.Top,
    horizontalArrangement = Arrangement.spacedBy(9.dp),
  ) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Text(
        "剪贴板",
        color = LocalClipDockTokens.current.colors.ink,
        fontSize = 30.sp,
        lineHeight = 34.sp,
        fontWeight = FontWeight.ExtraBold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      HistorySyncChip(state)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
      HistoryRoundIconButton(icon = ClipDockIconKind.Search, contentDescription = "搜索", onClick = {})
      HistoryRoundIconButton(icon = ClipDockIconKind.Plus, contentDescription = "添加", onClick = onOpenSettings)
    }
  }
}

@Composable
private fun HistorySyncChip(state: ClipDockUiState) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = CircleShape,
    color = tokens.colors.surface,
    border = BorderStroke(1.dp, tokens.colors.softLine),
  ) {
    Row(
      modifier = Modifier.padding(horizontal = 11.dp, vertical = 6.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
      Box(Modifier.size(8.dp).clip(CircleShape).background(if (state.tokenPresent) tokens.colors.accent else tokens.colors.faint))
      Text(
        historyStableSyncText(state),
        color = tokens.colors.muted,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Bold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun HistoryRoundIconButton(
  icon: ClipDockIconKind,
  contentDescription: String,
  onClick: () -> Unit,
) {
  Surface(
    shape = CircleShape,
    color = LocalClipDockTokens.current.colors.surface,
    contentColor = LocalClipDockTokens.current.colors.muted,
    border = BorderStroke(1.dp, LocalClipDockTokens.current.colors.line),
    shadowElevation = 0.dp,
    modifier =
      Modifier
        .size(42.dp)
        .clip(CircleShape)
        .clickable(onClick = onClick)
        .semantics { this.contentDescription = contentDescription },
  ) {
    Box(contentAlignment = Alignment.Center) {
      ClipDockSymbol(icon, Modifier.size(22.dp), color = LocalClipDockTokens.current.colors.muted)
    }
  }
}

@Composable
private fun HistorySearchPill() {
  val tokens = LocalClipDockTokens.current
  Row(
    modifier =
      Modifier
        .fillMaxWidth()
        .height(50.dp)
        .clip(RoundedCornerShape(16.dp))
        .background(tokens.colors.surface)
        .border(1.dp, tokens.colors.softLine, RoundedCornerShape(16.dp))
        .semantics { contentDescription = "搜索文本、链接、文件名" }
        .padding(horizontal = 15.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    ClipDockSymbol(ClipDockIconKind.Search, Modifier.size(20.dp), color = tokens.colors.muted)
    Text(
      "搜索文本、链接、文件名",
      color = tokens.colors.muted,
      fontSize = 13.sp,
      lineHeight = 16.sp,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
  }
}

@Composable
private fun HistoryVisualFilterRow(
  selected: HistoryVisualFilter,
  onSelected: (HistoryVisualFilter) -> Unit,
  allItems: List<ClipHistoryItem> = emptyList(),
) {
  val counts = remember(allItems) {
    mapOf(
      HistoryVisualFilter.All to allItems.size,
      HistoryVisualFilter.Text to allItems.count { historyCardVariant(it) in setOf(HistoryCardVariant.Text, HistoryCardVariant.Code, HistoryCardVariant.Note) },
      HistoryVisualFilter.Link to allItems.count { historyCardVariant(it) == HistoryCardVariant.Link },
      HistoryVisualFilter.Image to allItems.count { historyCardVariant(it) == HistoryCardVariant.Image },
      HistoryVisualFilter.File to allItems.count { historyCardVariant(it) == HistoryCardVariant.File },
    )
  }
  LazyRow(
    modifier = Modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.spacedBy(7.dp),
    contentPadding = PaddingValues(horizontal = 0.dp),
  ) {
    items(HistoryVisualFilter.entries) { filter ->
      HistoryVisualFilterChip(
        filter = filter,
        count = counts[filter] ?: 0,
        selected = filter == selected,
        onClick = { onSelected(filter) },
      )
    }
  }
}

@Composable
private fun HistoryVisualFilterChip(
  filter: HistoryVisualFilter,
  count: Int,
  selected: Boolean,
  onClick: () -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  val bgColor = if (selected) tokens.colors.ink else tokens.colors.surface
  val contentColor = if (selected) tokens.colors.surface else tokens.colors.muted
  val borderColor = if (selected) tokens.colors.ink else tokens.colors.softLine
  val cntBg = if (selected) Color.White.copy(alpha = 0.18f) else tokens.colors.surface3
  val cntColor = if (selected) tokens.colors.surface else tokens.colors.faint
  Row(
    modifier = Modifier
      .height(36.dp)
      .clip(RoundedCornerShape(999.dp))
      .background(bgColor)
      .border(1.dp, borderColor, RoundedCornerShape(999.dp))
      .clickable(onClick = onClick)
      .padding(horizontal = 14.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(6.dp),
  ) {
    Text(
      filter.label,
      color = contentColor,
      fontSize = 13.sp,
      lineHeight = 16.sp,
      fontWeight = FontWeight.ExtraBold,
      maxLines = 1,
    )
    Box(
      modifier = Modifier
        .clip(RoundedCornerShape(999.dp))
        .background(cntBg)
        .padding(horizontal = 6.dp, vertical = 1.dp),
      contentAlignment = Alignment.Center,
    ) {
      Text(
        count.toString(),
        color = cntColor,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        fontWeight = FontWeight.ExtraBold,
        maxLines = 1,
      )
    }
  }
}

@Composable
private fun HistoryHealthStrip(state: ClipDockUiState, onClick: () -> Unit) {
  val tokens = LocalClipDockTokens.current
  val isConnected = state.tokenPresent
  Surface(
    shape = RoundedCornerShape(14.dp),
    color = tokens.colors.healthBg,
    border = BorderStroke(1.dp, tokens.colors.accent.copy(alpha = 0.18f)),
    shadowElevation = 0.dp,
    modifier =
      Modifier
        .fillMaxWidth()
        .height(68.dp)
        .clip(RoundedCornerShape(14.dp))
        .clickable(onClick = onClick),
  ) {
    Row(
      modifier = Modifier.fillMaxSize(),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      HistoryHealthCell(
        icon = ClipDockIconKind.Cloud,
        title = if (isConnected) "同步正常" else "等待连接",
        subtitle = if (isConnected) "连接稳定" else "打开设置",
        modifier = Modifier.weight(1.1f),
        showDivider = true,
      )
      HistoryHealthCell(
        icon = ClipDockIconKind.Devices,
        title = "在线设备",
        subtitle = "${state.p2pDevices.size + if (state.tokenPresent) 1 else 0} 台",
        modifier = Modifier.weight(0.85f),
        showDivider = true,
      )
      HistoryHealthCell(
        icon = ClipDockIconKind.Cloud,
        title = "待上传",
        subtitle = "0 项",
        modifier = Modifier.weight(0.85f),
        showDivider = false,
      )
    }
  }
}

@Composable
private fun HistoryHealthCell(
  icon: ClipDockIconKind,
  title: String,
  subtitle: String,
  modifier: Modifier = Modifier,
  showDivider: Boolean,
) {
  val tokens = LocalClipDockTokens.current
  Row(modifier = modifier.fillMaxSize()) {
    Column(
      modifier = Modifier.weight(1f).padding(horizontal = 12.dp, vertical = 13.dp),
      verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
      Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        ClipDockSymbol(icon, Modifier.size(17.dp), color = tokens.colors.accent)
        Text(title, color = tokens.colors.ink, fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
      Text(subtitle, color = tokens.colors.muted, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    if (showDivider) {
      Box(Modifier.width(1.dp).fillMaxSize().padding(vertical = 8.dp).background(tokens.colors.accent.copy(alpha = 0.18f)))
    }
  }
}

@Composable
private fun HistoryStableCard(
  item: ClipHistoryItem,
  selected: Boolean,
  onOpenDetail: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val variant = historyCardVariant(item)
  if (variant == HistoryCardVariant.Image || variant == HistoryCardVariant.File) {
    HistoryMediaCard(item = item, variant = variant, onOpenDetail = onOpenDetail, modifier = modifier)
    return
  }
  val tokens = LocalClipDockTokens.current
  val shape = RoundedCornerShape(12.dp)
  Surface(
    shape = shape,
    color = tokens.colors.surface,
    border = BorderStroke(1.dp, if (selected) tokens.colors.accent.copy(alpha = 0.62f) else tokens.colors.softLine),
    shadowElevation = 0.dp,
    modifier =
      modifier
        .fillMaxWidth()
        .clip(shape)
        .clickable(onClick = onOpenDetail)
        .testTag(historyCardTestTag(item.stableId)),
  ) {
    Column(
      modifier = Modifier.fillMaxWidth().padding(12.dp),
      verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
      Box(Modifier.size(8.dp).clip(CircleShape).background(if (variant == HistoryCardVariant.Link) tokens.colors.accent2 else tokens.colors.accent))
      Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
      ) {
        HistoryTypePill(label = historyCardLabel(variant), tone = typeTone(item.type))
        Text(
          historyStableClockLabel(item),
          color = tokens.colors.faint,
          fontSize = 11.sp,
          lineHeight = 14.sp,
          fontWeight = FontWeight.ExtraBold,
          maxLines = 1,
        )
      }
      HistorySourceLine(item)
      HistoryTextPayload(item = item, variant = variant)
      Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
      ) {
        HistoryActionPill("复制", ClipDockIconKind.Copy, ClipDockTone.Green)
        HistoryActionPill(if (variant == HistoryCardVariant.Link) "分享" else "固定", if (variant == HistoryCardVariant.Link) ClipDockIconKind.Share else ClipDockIconKind.Pin, if (variant == HistoryCardVariant.Link) ClipDockTone.Blue else ClipDockTone.Neutral)
      }
    }
  }
}

@Composable
private fun HistorySourceLine(item: ClipHistoryItem) {
  Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
    ClipDockSymbol(if (item.sourceName?.contains("Pixel", ignoreCase = true) == true) ClipDockIconKind.Devices else ClipDockIconKind.Window, Modifier.size(13.dp), color = LocalClipDockTokens.current.colors.faint)
    Text(
      item.sourceName?.takeIf(String::isNotBlank) ?: "未知来源",
      color = LocalClipDockTokens.current.colors.faint,
      fontSize = 11.sp,
      lineHeight = 14.sp,
      fontWeight = FontWeight.ExtraBold,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
  }
}

@Composable
private fun HistoryTextPayload(item: ClipHistoryItem, variant: HistoryCardVariant) {
  val primary =
    when (variant) {
      HistoryCardVariant.Link -> historyFullText(item).lineSequence().firstOrNull()?.ifBlank { null } ?: item.displayTitle
      else -> historyFullText(item).ifBlank { item.displayTitle.ifBlank { item.displayBody } }
    }
  val secondary =
    if (variant == HistoryCardVariant.Link) {
      item.linkSiteName?.takeIf(String::isNotBlank) ?: item.displayBody.ifBlank { item.detail }
    } else {
      ""
    }
  Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
    Text(
      primary,
      color = LocalClipDockTokens.current.colors.ink,
      fontSize = 16.sp,
      lineHeight = 22.sp,
      fontWeight = FontWeight.Normal,
      maxLines = if (variant == HistoryCardVariant.Link) 4 else 8,
      overflow = TextOverflow.Ellipsis,
    )
    if (secondary.isNotBlank()) {
      Text(
        secondary,
        color = LocalClipDockTokens.current.colors.muted,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        fontWeight = FontWeight.Normal,
        maxLines = 3,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun HistoryTypePill(label: String, tone: ClipDockTone) {
  val colors = historyToneColors(tone)
  Surface(shape = RoundedCornerShape(7.dp), color = colors.second, contentColor = colors.first) {
    Text(label, modifier = Modifier.padding(horizontal = 7.dp, vertical = 3.dp), fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
  }
}

@Composable
private fun HistoryActionPill(label: String, icon: ClipDockIconKind, tone: ClipDockTone) {
  val colors = historyToneColors(tone)
  Row(
    modifier =
      Modifier
        .height(26.dp)
        .clip(CircleShape)
        .background(colors.second)
        .padding(horizontal = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(5.dp),
  ) {
    ClipDockSymbol(icon, Modifier.size(14.dp), color = colors.first)
    Text(label, color = colors.first, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
  }
}

@Composable
private fun historyToneColors(tone: ClipDockTone): Pair<Color, Color> {
  val tokens = LocalClipDockTokens.current
  return when (tone) {
    ClipDockTone.Green -> tokens.colors.accent to tokens.colors.accentSoft
    ClipDockTone.Blue -> tokens.colors.accent2 to tokens.colors.blueSoft
    ClipDockTone.Amber -> tokens.colors.warn to tokens.colors.warnSoft
    ClipDockTone.Red -> tokens.colors.danger to tokens.colors.dangerSoft
    ClipDockTone.Neutral -> tokens.colors.muted to tokens.colors.surface3
  }
}

@Composable
private fun HistoryMediaCard(
  item: ClipHistoryItem,
  variant: HistoryCardVariant,
  onOpenDetail: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val tokens = LocalClipDockTokens.current
  val bitmap by rememberImageBitmap(item.thumbnailUri ?: item.localUri)
  val shape = RoundedCornerShape(12.dp)
  Box(
    modifier =
      modifier
        .fillMaxWidth()
        .height(if (variant == HistoryCardVariant.File) 172.dp else 190.dp)
        .clip(shape)
        .background(tokens.colors.mediaBg)
        .clickable(onClick = onOpenDetail)
        .testTag(historyCardTestTag(item.stableId)),
  ) {
    if (bitmap != null) {
      Image(bitmap = bitmap!!, contentDescription = item.displayTitle, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    } else {
      HistoryMediaFallback(variant = variant, modifier = Modifier.fillMaxSize())
    }
    Box(
      Modifier
        .matchParentSize()
        .background(Brush.verticalGradient(listOf(Color(0x990F172A), Color(0x110F172A), Color(0xB80F172A)))),
    )
    Row(
      modifier = Modifier.align(Alignment.TopStart).fillMaxWidth().padding(10.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.SpaceBetween,
    ) {
      Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ClipDockSymbol(historyCardIcon(variant), Modifier.size(15.dp), color = Color.White.copy(alpha = 0.92f))
        MediaStateChip(item)
      }
      Text(historyStableClockLabel(item), color = Color.White.copy(alpha = 0.82f), fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
    }
    Column(modifier = Modifier.align(Alignment.BottomStart).fillMaxWidth()) {
      if (item.transferState == TransferState.DiscoveringPeer || item.transferState == TransferState.Downloading) {
        LinearProgressIndicator(
          modifier = Modifier.fillMaxWidth().height(3.dp),
          color = tokens.colors.accent2,
          trackColor = Color.White.copy(alpha = 0.18f),
        )
      }
      Row(
        modifier = Modifier.padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
      ) {
        val isReady = item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank()
        if (isReady) {
          HistoryActionPill("复制", ClipDockIconKind.Copy, ClipDockTone.Green)
          HistoryActionPill("查看", ClipDockIconKind.Image, ClipDockTone.Blue)
        } else {
          HistoryActionPill("下载", ClipDockIconKind.Download, ClipDockTone.Blue)
          HistoryActionPill("缩略图", ClipDockIconKind.Copy, ClipDockTone.Green)
        }
      }
    }
  }
}

@Composable
private fun MediaStateChip(item: ClipHistoryItem) {
  val (label, bgColor, textColor, icon) = when {
    item.transferState == TransferState.DiscoveringPeer ->
      Quadruple("查找设备", Color(0x381D5FFF), Color(0xFFA9C6FF), ClipDockIconKind.Download)
    item.transferState == TransferState.Downloading ->
      Quadruple("下载中", Color(0x381D5FFF), Color(0xFFA9C6FF), ClipDockIconKind.Download)
    item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() ->
      Quadruple("已就绪", Color(0x3835D39F), Color(0xFF5EF0C0), ClipDockIconKind.Check)
    else ->
      Quadruple("远程", Color(0x8C0F172A), Color(0xFFCDD8E0), ClipDockIconKind.Cloud)
  }
  Row(
    modifier = Modifier
      .height(24.dp)
      .clip(RoundedCornerShape(999.dp))
      .background(bgColor)
      .padding(horizontal = 9.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(5.dp),
  ) {
    ClipDockSymbol(icon, Modifier.size(12.dp), color = textColor)
    Text(label, color = textColor, fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
  }
}

private data class Quadruple<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)

@Composable
private fun HistoryCompactLinkPreview(item: ClipHistoryItem) {
  val tokens = LocalClipDockTokens.current
  val previewBitmap by rememberImageBitmap(item.linkPreviewUri)
  val iconBitmap by rememberImageBitmap(item.linkIconUri)
  Box(
    modifier =
      Modifier
        .fillMaxWidth()
        .height(44.dp)
        .clip(RoundedCornerShape(11.dp))
        .background(tokens.colors.surface3),
  ) {
    if (previewBitmap != null) {
      Image(
        bitmap = previewBitmap!!,
        contentDescription = item.displayTitle,
        contentScale = ContentScale.Crop,
        modifier = Modifier.fillMaxSize(),
      )
    } else {
      Box(
        Modifier
          .fillMaxSize()
          .background(
            Brush.linearGradient(
              listOf(
                Color(0xFFE9F8EF),
                Color(0xFFEAF2FF),
              ),
            ),
          ),
        contentAlignment = Alignment.Center,
      ) {
        ClipDockSymbol(ClipDockIconKind.Link, Modifier.size(22.dp), color = Color(0xFF22C55E))
      }
    }
    Row(
      modifier =
        Modifier
          .align(Alignment.BottomStart)
          .fillMaxWidth()
          .background(Color(0xB3121A2A))
          .padding(horizontal = 8.dp, vertical = 5.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
      Box(
        modifier =
          Modifier
            .size(20.dp)
            .clip(CircleShape)
            .background(Color.White),
        contentAlignment = Alignment.Center,
      ) {
        if (iconBitmap != null) {
          Image(
            bitmap = iconBitmap!!,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
          )
        } else {
          ClipDockSymbol(ClipDockIconKind.Link, Modifier.size(12.dp), color = Color(0xFF22C55E))
        }
      }
      Text(
        item.linkSiteName?.takeIf(String::isNotBlank) ?: item.displayTitle,
        color = Color.White,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        fontWeight = FontWeight.ExtraBold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun HistoryMediaFallback(variant: HistoryCardVariant, modifier: Modifier = Modifier) {
  if (variant == HistoryCardVariant.File) {
    Box(
      modifier =
        modifier.background(
          Brush.verticalGradient(
            listOf(Color(0xFFFFF7ED), Color(0xFFFFFFFF), Color(0xFF64748B)),
          ),
        ),
    ) {
      Box(
        Modifier
          .align(Alignment.Center)
          .fillMaxWidth(0.74f)
          .aspectRatio(1.45f)
          .clip(RoundedCornerShape(18.dp))
          .background(Color.White.copy(alpha = 0.78f)),
      )
      Box(Modifier.align(Alignment.CenterStart).padding(start = 24.dp).size(62.dp).clip(RoundedCornerShape(14.dp)).background(Color(0xFFFB923C)))
      Box(Modifier.align(Alignment.TopEnd).padding(top = 42.dp, end = 30.dp).width(78.dp).height(12.dp).clip(CircleShape).background(Color(0xFFFDAD64)))
      Box(Modifier.align(Alignment.TopEnd).padding(top = 68.dp, end = 56.dp).width(48.dp).height(12.dp).clip(CircleShape).background(Color(0xFFFDD6A5)))
      Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 50.dp).fillMaxWidth(0.70f).height(10.dp).clip(CircleShape).background(Color(0xFFD7CEC2)))
    }
  } else {
    Box(
      modifier =
        modifier.background(
          Brush.verticalGradient(
            listOf(Color(0xFFA7F3D0), Color(0xFF67E8F9), Color(0xFF2563EB)),
          ),
        ),
    ) {
      Box(Modifier.align(Alignment.TopEnd).padding(24.dp).size(54.dp).clip(CircleShape).background(Color(0xFFFEF3C7)))
      Box(
        Modifier
          .align(Alignment.BottomCenter)
          .fillMaxWidth()
          .height(118.dp)
          .background(Brush.linearGradient(listOf(Color(0xFF18A67A), Color(0xFFFACC15)))),
      )
      Box(
        Modifier
          .align(Alignment.BottomCenter)
          .fillMaxWidth()
          .height(82.dp)
          .background(Color(0xB80F766E)),
      )
    }
  }
}

@Composable
private fun HistoryCompactThumb(item: ClipHistoryItem) {
  val bitmap by rememberImageBitmap(item.thumbnailUri ?: item.localUri)
  if (bitmap != null) {
    Image(
      bitmap = bitmap!!,
      contentDescription = item.displayTitle,
      contentScale = ContentScale.Crop,
      modifier = Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(11.dp)),
    )
  } else {
    Box(
      modifier =
        Modifier
          .fillMaxWidth()
          .height(44.dp)
          .clip(RoundedCornerShape(11.dp))
          .background(
            Brush.linearGradient(
              listOf(
                LocalClipDockTokens.current.colors.accent.copy(alpha = 0.24f),
                LocalClipDockTokens.current.colors.accent2.copy(alpha = 0.14f),
              ),
            ),
          ),
    )
  }
}

@Composable
private fun HistoryCompactFileLines() {
  Column(
    modifier =
      Modifier
        .fillMaxWidth()
        .height(44.dp)
        .clip(RoundedCornerShape(11.dp))
        .background(LocalClipDockTokens.current.colors.surface3)
        .padding(horizontal = 14.dp, vertical = 10.dp),
    verticalArrangement = Arrangement.spacedBy(5.dp),
  ) {
    Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(LocalClipDockTokens.current.colors.line))
    Box(Modifier.fillMaxWidth(0.76f).height(4.dp).clip(CircleShape).background(LocalClipDockTokens.current.colors.line))
    Box(Modifier.fillMaxWidth(0.48f).height(4.dp).clip(CircleShape).background(LocalClipDockTokens.current.colors.line))
  }
}

@Composable
private fun HistoryMiniChip(label: String, tone: ClipDockTone) {
  val tokens = LocalClipDockTokens.current
  val colors =
    when (tone) {
      ClipDockTone.Green -> tokens.colors.accent to tokens.colors.accentSoft
      ClipDockTone.Blue -> tokens.colors.accent2 to tokens.colors.blueSoft
      ClipDockTone.Amber -> tokens.colors.warn to tokens.colors.warnSoft
      ClipDockTone.Red -> tokens.colors.danger to tokens.colors.dangerSoft
      ClipDockTone.Neutral -> tokens.colors.muted to tokens.colors.surface3
    }
  Box(
    modifier =
      Modifier
        .height(22.dp)
        .clip(CircleShape)
        .background(colors.second)
        .padding(horizontal = 8.dp),
    contentAlignment = Alignment.Center,
  ) {
    Text(label, color = colors.first, fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
  }
}

@Composable
private fun HistoryHeaderBodyCard(
  item: ClipHistoryItem,
  variant: HistoryCardVariant,
  onOpenDetail: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val shape = RoundedCornerShape(12.dp)
  Surface(
    shape = shape,
    color = Color.White,
    border = BorderStroke(1.dp, HistoryCardBorder),
    shadowElevation = 7.dp,
    modifier =
      modifier
        .fillMaxWidth()
        .clip(shape)
        .clickable(onClick = onOpenDetail)
        .testTag(historyCardTestTag(item.stableId)),
  ) {
    Column(Modifier.fillMaxSize()) {
      HistoryStableCardHeader(item = item, variant = variant)
      when (variant) {
        HistoryCardVariant.Link ->
          HistoryStableTextBlock(
            title = item.displayTitle,
            subtitle = item.displayBody.ifBlank { item.detail },
            modifier = Modifier.fillMaxWidth().height(112.dp),
          )
        HistoryCardVariant.Text ->
          HistoryAddressBlock(
            title = item.displayTitle,
            body = item.displayBody.ifBlank { item.detail },
            detail = item.detail,
            modifier = Modifier.fillMaxWidth().height(112.dp),
          )
        HistoryCardVariant.File -> HistoryStableFileBlock(item = item, modifier = Modifier.fillMaxWidth().height(112.dp))
        else -> Unit
      }
    }
  }
}

@Composable
private fun HistoryStableCardHeader(item: ClipHistoryItem, variant: HistoryCardVariant) {
  Row(
    modifier = Modifier.fillMaxWidth().height(56.dp).background(historyHeaderColor(variant)).padding(horizontal = 12.dp, vertical = 10.dp),
    verticalAlignment = Alignment.Top,
    horizontalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
      Text(
        variant.label,
        color = Color.White,
        fontSize = 17.sp,
        lineHeight = 17.sp,
        fontWeight = FontWeight.Black,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        historyStableTimeLabel(item.copiedAtMillis),
        color = Color.White.copy(alpha = 0.9f),
        fontSize = 13.sp,
        lineHeight = 13.sp,
        fontWeight = FontWeight.ExtraBold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun HistoryStableTextBlock(title: String, subtitle: String, modifier: Modifier = Modifier) {
  Column(modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
    Text(
      title,
      color = Color(0xFF172033),
      fontSize = 14.sp,
      lineHeight = 17.sp,
      fontWeight = FontWeight.Black,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
    Text(
      subtitle,
      color = Color(0xFF697586),
      fontSize = 12.sp,
      lineHeight = 15.sp,
      fontWeight = FontWeight.SemiBold,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.padding(top = 4.dp),
    )
  }
}

@Composable
private fun HistoryAddressBlock(title: String, body: String, detail: String, modifier: Modifier = Modifier) {
  val characterCount = body.count { !it.isWhitespace() }.takeIf { it > 0 } ?: title.count { !it.isWhitespace() }
  Column(modifier.padding(horizontal = 13.dp, vertical = 15.dp)) {
    Text(
      title,
      color = HistoryDesignInk,
      fontSize = 16.sp,
      lineHeight = 18.sp,
      fontWeight = FontWeight.Black,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
    Text(
      body,
      color = Color(0xFF253044),
      fontSize = 13.sp,
      lineHeight = 16.sp,
      fontWeight = FontWeight.Medium,
      maxLines = 3,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.padding(top = 7.dp),
    )
    Text(
      detail.takeIf { it.isNotBlank() && it.length <= 18 } ?: "$characterCount characters",
      color = Color(0xFF8793A3),
      fontSize = 13.sp,
      lineHeight = 16.sp,
      fontWeight = FontWeight.ExtraBold,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.padding(top = 9.dp),
    )
  }
}

@Composable
private fun HistoryCodeCard(
  item: ClipHistoryItem,
  onOpenDetail: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val shape = RoundedCornerShape(12.dp)
  Surface(
    shape = shape,
    color = Color(0xFF111B2D),
    border = BorderStroke(1.dp, Color(0x2E0F172A)),
    shadowElevation = 7.dp,
    modifier =
      modifier
        .fillMaxWidth()
        .clip(shape)
        .clickable(onClick = onOpenDetail)
        .testTag(historyCardTestTag(item.stableId)),
  ) {
    Text(
      historyFullText(item),
      color = Color(0xFFDBE7F5),
      fontSize = 11.sp,
      lineHeight = 15.sp,
      fontWeight = FontWeight.Bold,
      fontFamily = FontFamily.Monospace,
      maxLines = 9,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 15.dp),
    )
  }
}

@Composable
private fun HistoryImageCard(
  item: ClipHistoryItem,
  onOpenDetail: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val shape = RoundedCornerShape(12.dp)
  Surface(
    shape = shape,
    color = Color.White,
    border = BorderStroke(1.dp, HistoryCardBorder),
    shadowElevation = 7.dp,
    modifier =
      modifier
        .fillMaxWidth()
        .clip(shape)
        .clickable(onClick = onOpenDetail)
        .testTag(historyCardTestTag(item.stableId)),
  ) {
    Column(Modifier.fillMaxSize()) {
      val bitmap by rememberImageBitmap(item.thumbnailUri ?: item.localUri)
      if (bitmap != null) {
        Image(bitmap = bitmap!!, contentDescription = item.displayTitle, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().height(94.dp))
      } else {
        HistoryImageRemoteBlock(item = item, modifier = Modifier.fillMaxWidth().height(94.dp))
      }
      HistoryStableTextBlock(
        title = item.displayTitle,
        subtitle = item.displayBody.ifBlank { item.detail },
        modifier = Modifier.fillMaxWidth().height(74.dp),
      )
    }
  }
}

@Composable
private fun HistoryImageRemoteBlock(item: ClipHistoryItem, modifier: Modifier = Modifier) {
  val label =
    when (item.transferState) {
      TransferState.DiscoveringPeer -> "查找来源"
      TransferState.Downloading -> "下载中"
      TransferState.Failed -> "取回失败"
      TransferState.Ready -> "已缓存"
      TransferState.Idle -> if (item.payloadState == PayloadState.RemoteOnly) "远端图片" else "无缩略图"
    }
  Box(modifier.background(Color(0xFFF6F8FB)), contentAlignment = Alignment.Center) {
    Row(
      horizontalArrangement = Arrangement.spacedBy(8.dp),
      verticalAlignment = Alignment.CenterVertically,
      modifier = Modifier.padding(horizontal = 12.dp),
    ) {
      ClipDockSymbol(ClipDockIconKind.Image, Modifier.size(18.dp), color = Color(0xFF64748B))
      Text(
        label,
        color = Color(0xFF64748B),
        fontSize = 13.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Bold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun HistoryNoteCard(
  item: ClipHistoryItem,
  onOpenDetail: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val shape = RoundedCornerShape(12.dp)
  Surface(
    shape = shape,
    color = Color(0xFFFFF4C7),
    border = BorderStroke(1.dp, HistoryCardBorder),
    shadowElevation = 7.dp,
    modifier =
      modifier
        .fillMaxWidth()
        .clip(shape)
        .clickable(onClick = onOpenDetail)
        .testTag(historyCardTestTag(item.stableId)),
  ) {
    Column(
      Modifier.fillMaxSize().padding(horizontal = 13.dp, vertical = 15.dp),
      verticalArrangement = Arrangement.Center,
    ) {
      Text(
        item.displayTitle,
        color = Color(0xFF253044),
        fontSize = 16.sp,
        lineHeight = 19.sp,
        fontWeight = FontWeight.Black,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        item.displayBody.ifBlank { item.detail },
        color = Color(0xFF475569),
        fontSize = 13.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Bold,
        maxLines = 4,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.padding(top = 4.dp),
      )
    }
  }
}

@Composable
private fun HistoryStableFileBlock(item: ClipHistoryItem, modifier: Modifier = Modifier) {
  Box(modifier.background(Color.White), contentAlignment = Alignment.Center) {
    Box(
      Modifier
        .width(68.dp)
        .height(74.dp)
        .clip(RoundedCornerShape(14.dp))
        .background(Brush.verticalGradient(listOf(Color.White, Color(0xFFF8FAFC))))
        .padding(2.dp),
      contentAlignment = Alignment.Center,
    ) {
      Surface(
        shape = RoundedCornerShape(14.dp),
        color = Color.Transparent,
        border = BorderStroke(2.dp, Color(0xFFDBE5EE)),
        modifier = Modifier.fillMaxSize(),
      ) {
        Box(contentAlignment = Alignment.Center) {
          Text(
            historyFileBadge(item),
            color = Color(0xFF475569),
            fontSize = 21.sp,
            lineHeight = 24.sp,
            fontWeight = FontWeight.Black,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
        }
      }
    }
  }
}

private val HistoryDesignInk = Color(0xFF101827)
private val HistoryCardBorder = Color(0x3D94A3B8)
private val HistoryCodeMarkerRegex =
  Regex("(@main|\\bfun\\s|\\bclass\\s|\\bstruct\\s|\\bimport\\s|\\bpackage\\s|\\bWindowGroup\\b)")

private fun filteredHistoryItems(items: List<ClipHistoryItem>, filter: HistoryVisualFilter): List<ClipHistoryItem> =
  items.filter { item ->
    when (filter) {
      HistoryVisualFilter.All -> true
      HistoryVisualFilter.Text -> historyCardVariant(item) in setOf(HistoryCardVariant.Text, HistoryCardVariant.Code, HistoryCardVariant.Note)
      HistoryVisualFilter.Link -> historyCardVariant(item) == HistoryCardVariant.Link
      HistoryVisualFilter.Image -> historyCardVariant(item) == HistoryCardVariant.Image
      HistoryVisualFilter.File -> historyCardVariant(item) == HistoryCardVariant.File
    }
  }

private fun isImportantVisual(item: ClipHistoryItem): Boolean = item.copyCount > 1

private fun historyCardVariant(item: ClipHistoryItem): HistoryCardVariant =
  when {
    item.type == ClipItemType.Link -> HistoryCardVariant.Link
    item.type == ClipItemType.Image -> HistoryCardVariant.Image
    item.type == ClipItemType.File -> HistoryCardVariant.File
    isCodeVisual(item) -> HistoryCardVariant.Code
    (item.type == ClipItemType.Text || item.type == ClipItemType.RichText) && isImportantVisual(item) -> HistoryCardVariant.Note
    else -> HistoryCardVariant.Text
  }

private fun isCodeVisual(item: ClipHistoryItem): Boolean {
  if (item.type != ClipItemType.Text && item.type != ClipItemType.RichText) return false
  val text = historyFullText(item)
  val nonBlankLines = text.lineSequence().count { it.isNotBlank() }
  return nonBlankLines >= 3 && HistoryCodeMarkerRegex.containsMatchIn(text)
}

private fun historyFullText(item: ClipHistoryItem): String =
  listOf(item.title, item.body)
    .filter { it.isNotBlank() }
    .distinct()
    .joinToString("\n")
    .ifBlank { item.detail }

private fun historyStableSyncText(state: ClipDockUiState): String =
  when {
    state.syncId == "clipdock-home" -> "刚刚同步 12 条 · 3 台设备在线"
    !state.tokenPresent -> "未加入 · 打开设置"
    state.isSyncing -> "正在同步 · ${relativeTimeLabel(state.diagnostics.lastSyncAtMillis)}"
    state.isSyncSetupInFlight -> "正在连接 · 请稍候"
    state.diagnostics.lastSyncAtMillis > 0 -> "已同步 · ${relativeTimeLabel(state.diagnostics.lastSyncAtMillis)}"
    else -> "已加入 · 未同步"
  }

private data class HistoryFooterChip(val label: String, val tone: ClipDockTone)

private fun historyCardIcon(variant: HistoryCardVariant): ClipDockIconKind =
  when (variant) {
    HistoryCardVariant.Image -> ClipDockIconKind.Image
    HistoryCardVariant.Link -> ClipDockIconKind.Link
    HistoryCardVariant.File -> ClipDockIconKind.File
    else -> ClipDockIconKind.Text
  }

private fun historyCardLabel(variant: HistoryCardVariant): String =
  when (variant) {
    HistoryCardVariant.Image -> "图片"
    HistoryCardVariant.Link -> "链接"
    HistoryCardVariant.File -> "文件"
    else -> "文本"
  }

private fun historyCardFooter(item: ClipHistoryItem, variant: HistoryCardVariant): Pair<HistoryFooterChip, HistoryFooterChip> =
  when (variant) {
    HistoryCardVariant.Image ->
      HistoryFooterChip("取回", ClipDockTone.Blue) to HistoryFooterChip(item.detail.ifBlank { "1.2 MB" }, ClipDockTone.Neutral)
    HistoryCardVariant.Link ->
      HistoryFooterChip("复制", ClipDockTone.Green) to HistoryFooterChip("分享", ClipDockTone.Neutral)
    HistoryCardVariant.File ->
      HistoryFooterChip("下载", ClipDockTone.Amber) to HistoryFooterChip(historyFileBadge(item), ClipDockTone.Neutral)
    else ->
      HistoryFooterChip("复制", ClipDockTone.Green) to HistoryFooterChip("固定", ClipDockTone.Neutral)
  }

private fun historyStableClockLabel(item: ClipHistoryItem): String {
  val timeMillis = item.copiedAtMillis
  if (timeMillis <= 0L) return "--:--"
  val formatter = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
  return formatter.format(java.util.Date(timeMillis))
}

@Composable
private fun historyHeaderColor(variant: HistoryCardVariant): Color =
  when (variant) {
    HistoryCardVariant.Link -> Color(0xFF22C55E)
    HistoryCardVariant.Text -> Color(0xFF2563EB)
    HistoryCardVariant.File -> Color(0xFFF59E0B)
    else -> LocalClipDockTokens.current.colors.muted
  }

private fun historyStableTimeLabel(timeMillis: Long): String {
  if (timeMillis <= 0L) return "--"
  val elapsed = System.currentTimeMillis() - timeMillis
  if (elapsed < 0) return "now"
  val minutes = elapsed / 60_000
  return when {
    minutes < 1 -> "now"
    minutes < 60 -> "${minutes}m"
    minutes < 24 * 60 -> "${minutes / 60}h"
    else -> "${minutes / (24 * 60)}d"
  }
}

private fun historyFileBadge(item: ClipHistoryItem): String =
  item.metadataLabel
    .takeIf { it.length in 2..5 }
    ?: item.displayTitle.substringAfterLast('.', missingDelimiterValue = "").uppercase().takeIf { it.length in 2..5 }
    ?: "FILE"

@Composable
private fun DevicesPage(state: ClipDockUiState, onCreateInvite: () -> Unit, onRefresh: () -> Unit) {
  val onlineDevices = state.p2pDevices.filterNot { it.deviceId == state.deviceId }
  val deviceCards =
    listOf(
      DeviceUiCard(
        name = state.deviceName,
        kind = "Android · 本机",
        status = if (state.tokenPresent) "前台运行 · 悬浮球${if (state.overlayEnabled) "开启" else "关闭"}" else "未加入同步空间",
        icon = ClipDockIconKind.Devices,
        tone = ClipDockTone.Blue,
        online = state.tokenPresent,
        caps = listOf("复制", "下载"),
      ),
    ) +
      onlineDevices.map { device ->
        DeviceUiCard(
          name = device.deviceName,
          kind = "在线设备",
          status = "P2P endpoint · ${timeLabel(device.endpoint.updatedAtMillis)}",
          icon = ClipDockIconKind.Devices,
          tone = ClipDockTone.Green,
          online = true,
          caps = listOf("文本", "图片", "文件"),
        )
      }
  LazyVerticalGrid(
    columns = GridCells.Adaptive(164.dp),
    contentPadding = PaddingValues(start = 14.dp, top = 15.dp, end = 14.dp, bottom = 18.dp),
    horizontalArrangement = Arrangement.spacedBy(10.dp),
    verticalArrangement = Arrangement.spacedBy(10.dp),
    modifier = Modifier.fillMaxSize(),
  ) {
    item(span = { GridItemSpan(maxLineSpan) }) {
      ClipDockScreenHeader(
        title = "设备",
        subtitle = "当前账号下的同步设备和连接状态",
        actions = {
          ClipDockIconButton(ClipDockIconKind.More, "刷新设备", onClick = onRefresh, enabled = state.tokenPresent && !state.isSyncSetupInFlight)
          ClipDockIconButton(ClipDockIconKind.Plus, "生成配对码", onClick = onCreateInvite, enabled = state.tokenPresent && !state.isSyncSetupInFlight)
        },
      )
    }
    item(span = { GridItemSpan(maxLineSpan) }) {
      DeviceStatusPanel(
        state = state,
        onlineCount = deviceCards.count { it.online },
        onCreateInvite = onCreateInvite,
      )
    }
    items(deviceCards, key = { it.name }) { card ->
      DeviceCard(card)
    }
    item(span = { GridItemSpan(maxLineSpan) }) {
      Text("最近传输", color = LocalClipDockTokens.current.colors.muted, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(top = 8.dp, start = 2.dp))
    }
    item(span = { GridItemSpan(maxLineSpan) }) {
      ClipDockCard {
        TimelineRow(ClipDockIconKind.Image, "图片缩略图已同步", if (state.tokenPresent) "${state.deviceName} · ${relativeTimeLabel(state.diagnostics.lastSyncAtMillis)}" else "加入同步空间后显示最近传输", "刚刚")
        TimelineRow(ClipDockIconKind.Link, "邀请新设备", state.pairingCode?.let { "$it · ${pairingExpiryText(state)}" } ?: "生成 5 位配对码给新设备加入", if (state.pairingCode == null) "生成" else "刷新")
      }
    }
  }
}

private data class DeviceUiCard(
  val name: String,
  val kind: String,
  val status: String,
  val icon: ClipDockIconKind,
  val tone: ClipDockTone,
  val online: Boolean,
  val caps: List<String>,
)

@Composable
private fun DeviceStatusPanel(state: ClipDockUiState, onlineCount: Int, onCreateInvite: () -> Unit) {
  ClipDockCard(contentPadding = PaddingValues(14.dp), modifier = Modifier.background(Color.Transparent)) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      ClipDockSymbol(ClipDockIconKind.Cloud, Modifier.size(18.dp), color = LocalClipDockTokens.current.colors.accent)
      Text(if (state.tokenPresent) "同步通道正常" else "等待连接服务端", color = LocalClipDockTokens.current.colors.ink, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.ExtraBold)
    }
    Text(
      if (state.tokenPresent) "${state.deviceName} 在线，最近一次同步${relativeTimeLabel(state.diagnostics.lastSyncAtMillis)}完成。" else "邀请新设备前需要先加入同步空间。",
      color = LocalClipDockTokens.current.colors.muted,
      fontSize = 13.sp,
      lineHeight = 18.sp,
      fontWeight = FontWeight.Bold,
    )
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
      TimelineInlineMetric(ClipDockIconKind.Devices, "$onlineCount 台在线", "设备可见")
      StatusPill(if (state.tokenPresent) "稳定" else "未连接", if (state.tokenPresent) ClipDockTone.Green else ClipDockTone.Neutral)
    }
    Row(
      modifier =
        Modifier
          .fillMaxWidth()
          .height(40.dp)
          .clip(RoundedCornerShape(13.dp))
          .background(LocalClipDockTokens.current.colors.accentSoft)
          .clickable(enabled = state.tokenPresent && !state.isSyncSetupInFlight, onClick = onCreateInvite)
          .padding(horizontal = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.SpaceBetween,
    ) {
      Text("邀请新设备", color = LocalClipDockTokens.current.colors.accent, fontSize = 13.sp, lineHeight = 16.sp, fontWeight = FontWeight.ExtraBold)
      ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(16.dp), color = LocalClipDockTokens.current.colors.accent)
    }
  }
}

@Composable
private fun DeviceCard(card: DeviceUiCard) {
  val tokens = LocalClipDockTokens.current
  ClipDockCard(contentPadding = PaddingValues(13.dp), modifier = Modifier.height(170.dp)) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(card.name, color = tokens.colors.ink, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(card.kind, color = tokens.colors.muted, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
      IconTile(card.icon, tone = card.tone)
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
      Box(Modifier.size(7.dp).clip(CircleShape).background(if (card.online) tokens.colors.accent else tokens.colors.faint))
      Text(card.status, color = tokens.colors.muted, fontSize = 12.sp, lineHeight = 17.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
    Spacer(Modifier.weight(1f))
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
      card.caps.take(3).forEach { cap -> HistoryMiniChip(cap, ClipDockTone.Neutral) }
    }
  }
}

@Composable
private fun TimelineInlineMetric(icon: ClipDockIconKind, title: String, subtitle: String) {
  Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
    IconTile(icon, tone = ClipDockTone.Green, modifier = Modifier.size(34.dp))
    Column {
      Text(title, color = LocalClipDockTokens.current.colors.ink, fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.ExtraBold)
      Text(subtitle, color = LocalClipDockTokens.current.colors.muted, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold)
    }
  }
}

@Composable
private fun TimelineRow(icon: ClipDockIconKind, title: String, subtitle: String, trailing: String) {
  Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
    IconTile(icon, tone = ClipDockTone.Green, modifier = Modifier.size(34.dp))
    Column(Modifier.weight(1f)) {
      Text(title, color = LocalClipDockTokens.current.colors.ink, fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
      Text(subtitle, color = LocalClipDockTokens.current.colors.muted, fontSize = 12.sp, lineHeight = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    Text(trailing, color = LocalClipDockTokens.current.colors.faint, fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
  }
}

@Composable
private fun FilesPage(
  state: ClipDockUiState,
  wifiOnlyBlocked: Boolean,
  onUseItem: (ClipHistoryItem) -> Unit,
  onOpenItemDetail: (String) -> Unit,
) {
  val context = LocalContext.current
  var selectedSegment by remember { mutableStateOf("全部") }
  val fileItems =
    state.items
      .filter { it.type == ClipItemType.Image || it.type == ClipItemType.File }
      .filter {
        when (selectedSegment) {
          "图片" -> it.type == ClipItemType.Image
          "文档" -> it.type == ClipItemType.File
          "下载" -> it.payloadState == PayloadState.Ready && !it.localUri.isNullOrBlank()
          else -> true
        }
      }
  LazyVerticalGrid(
    columns = GridCells.Adaptive(154.dp),
    contentPadding = PaddingValues(start = 14.dp, top = 15.dp, end = 14.dp, bottom = 18.dp),
    horizontalArrangement = Arrangement.spacedBy(10.dp),
    verticalArrangement = Arrangement.spacedBy(10.dp),
    modifier = Modifier.fillMaxSize(),
  ) {
    item(span = { GridItemSpan(maxLineSpan) }) {
      ClipDockScreenHeader(
        title = "文件",
        subtitle = "图片、视频、文档和远程资产",
        actions = {
          ClipDockIconButton(ClipDockIconKind.Search, "搜索文件", onClick = {}, enabled = false)
          ClipDockIconButton(ClipDockIconKind.Download, "下载队列", onClick = {}, enabled = false)
        },
      )
    }
    item(span = { GridItemSpan(maxLineSpan) }) {
      SegmentedControl(listOf("全部", "图片", "视频", "文档", "下载"), selectedSegment, { selectedSegment = it })
    }
    if (fileItems.isEmpty()) {
      item(span = { GridItemSpan(maxLineSpan) }) {
        EmptyState("暂无文件", "图片和文件会从同步历史中自动聚合。", null, null)
      }
    } else {
      items(fileItems, key = { it.stableId }) { item ->
        FileAssetCard(
          item = item,
          p2pEnabled = state.p2pEnabled,
          wifiOnlyBlocked = wifiOnlyBlocked,
          onUseItem = onUseItem,
          onOpenDetail = { onOpenItemDetail(item.stableId) },
          onOpenItem = { openLocalUri(context, item) },
        )
      }
    }
    item(span = { GridItemSpan(maxLineSpan) }) {
      Text("远程资产状态", color = LocalClipDockTokens.current.colors.muted, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(top = 8.dp, start = 2.dp))
    }
    item(span = { GridItemSpan(maxLineSpan) }) {
      ClipDockCard {
        TimelineRow(ClipDockIconKind.Check, "缩略图可直接预览", "原始文件按需下载，避免占用本机空间", "设计态")
        TimelineRow(ClipDockIconKind.Download, "按需下载", if (wifiOnlyBlocked) "仅 Wi-Fi 下载已开启，当前网络不可取回" else "下载队列为空", if (state.wifiOnly) "仅 Wi-Fi" else "空闲")
      }
    }
  }
}

@Composable
private fun FileAssetCard(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
  onUseItem: (ClipHistoryItem) -> Unit,
  onOpenDetail: () -> Unit,
  onOpenItem: () -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  val state = fileActionState(item, p2pEnabled, wifiOnlyBlocked)
  val variant = if (item.type == ClipItemType.File) HistoryCardVariant.File else HistoryCardVariant.Image
  val bitmap by rememberImageBitmap(item.thumbnailUri ?: item.localUri)
  Box(
    modifier =
      Modifier
        .fillMaxWidth()
        .height(if (item.type == ClipItemType.File) 226.dp else 190.dp)
        .clip(RoundedCornerShape(14.dp))
        .background(tokens.colors.mediaBg)
        .clickable(onClick = { if (state.opensLocalUri) onOpenItem() else onOpenDetail() }),
  ) {
    if (bitmap != null) {
      Image(bitmap = bitmap!!, contentDescription = item.displayTitle, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    } else {
      HistoryMediaFallback(variant = variant, modifier = Modifier.fillMaxSize())
    }
    Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color(0x730F172A), Color.Transparent, Color(0xB80F172A)))))
    Row(
      modifier = Modifier.align(Alignment.TopStart).fillMaxWidth().padding(10.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.SpaceBetween,
    ) {
      Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ClipDockSymbol(if (item.type == ClipItemType.Image) ClipDockIconKind.Image else ClipDockIconKind.File, Modifier.size(15.dp), color = Color.White)
        HistoryTypePill(if (item.type == ClipItemType.Image) "图片" else "文档", typeTone(item.type))
      }
      Text(historyStableClockLabel(item), color = Color.White.copy(alpha = 0.86f), fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
    }
    Row(
      modifier = Modifier.align(Alignment.BottomStart).padding(10.dp),
      horizontalArrangement = Arrangement.spacedBy(7.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      HistoryActionPill(if (state.primaryLabel == "打开") "打开" else "复制", if (state.primaryLabel == "打开") ClipDockIconKind.Folder else ClipDockIconKind.Copy, ClipDockTone.Green)
      HistoryActionPill("下载", ClipDockIconKind.Download, ClipDockTone.Blue)
    }
  }
}

@Composable
private fun FileRow(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
  onUseItem: (ClipHistoryItem) -> Unit,
  onOpenDetail: () -> Unit,
  onOpenItem: () -> Unit,
) {
  val state = fileActionState(item, p2pEnabled, wifiOnlyBlocked)
  Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
    RowCard(
      icon = if (item.type == ClipItemType.Image) ClipDockIconKind.Image else ClipDockIconKind.File,
      title = item.displayTitle,
      subtitle = state.message,
      tone = typeTone(item.type),
      onClick = { if (state.opensLocalUri) onOpenItem() else onOpenDetail() },
    ) {
      ActionChip(
        label = state.primaryLabel,
        enabled = state.primaryEnabled,
        tone = state.tone,
        onClick = {
          when {
            state.opensLocalUri -> onOpenItem()
            state.primaryLabel == "复制" -> onUseItem(item)
            else -> onOpenDetail()
          }
        },
      )
    }
    if (item.transferState == TransferState.Downloading) {
      LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = 2.dp), color = LocalClipDockTokens.current.colors.accent)
    }
  }
}

@Composable
private fun SettingsOverviewPage(
  state: ClipDockUiState,
  onSyncNow: () -> Unit,
  onWifiOnlyChange: (Boolean) -> Unit,
  onOverlayEnabledChange: (Boolean) -> Unit,
  onEncryptionEnabledChange: (Boolean) -> Unit,
  onOpenSettingsDetail: (SettingsDetailDestination) -> Unit,
) {
  val context = LocalContext.current
  val overlayGranted = Settings.canDrawOverlays(context)
  val notificationGranted =
    Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
  val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
  val batteryIgnored = powerManager.isIgnoringBatteryOptimizations(context.packageName)
  val keepAliveMissingCount = listOf(overlayGranted, notificationGranted, batteryIgnored).count { !it }
  LazyColumn(contentPadding = PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
    item {
      ClipDockScreenHeader(
        title = "设置",
        subtitle = "同步、设备、悬浮球与隐私",
        actions = { ClipDockIconButton(ClipDockIconKind.Search, "设置搜索", onClick = {}, enabled = false) },
      )
    }
    item { SyncStatusHero(state, onSyncNow) }

    item { SettingsSectionTitle("同步") }
    item {
      SettingGroup {
        SwitchSettingRow(ClipDockIconKind.Cloud, "自动同步", "文本、链接、图片缩略图保持同步", checked = state.tokenPresent, onCheckedChange = {}, tone = ClipDockTone.Green)
        SettingDivider()
        SwitchSettingRow(ClipDockIconKind.Wifi, "仅 Wi-Fi 下载原文件", "缩略图始终同步，原文件等 Wi-Fi", state.wifiOnly, onWifiOnlyChange, ClipDockTone.Blue)
        SettingDivider()
        SettingRow(ClipDockIconKind.Download, "远程文件下载", "原始文件按需下载，保留缩略图预览", tone = ClipDockTone.Amber) {
          ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(18.dp), color = LocalClipDockTokens.current.colors.muted)
        }
      }
    }

    item { SettingsSectionTitle("设备与配对") }
    item {
      SettingGroup {
        SettingRow(ClipDockIconKind.Plus, "配对新设备", "生成 5 位配对码或加入空间", tone = ClipDockTone.Green, onClick = { onOpenSettingsDetail(SettingsDetailDestination.Pairing) }) {
          ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(18.dp), color = LocalClipDockTokens.current.colors.muted)
        }
        SettingDivider()
        SettingRow(ClipDockIconKind.Shield, "保活权限", "通知、后台、电池优化和厂商设置", tone = ClipDockTone.Amber, onClick = { onOpenSettingsDetail(SettingsDetailDestination.KeepAlive) }) {
          StatusPill(if (keepAliveMissingCount == 0) "完成" else "${keepAliveMissingCount} 项待处理", if (keepAliveMissingCount == 0) ClipDockTone.Green else ClipDockTone.Amber)
        }
      }
    }

    item { SettingsSectionTitle("悬浮球") }
    item {
      SettingGroup {
        SwitchSettingRow(ClipDockIconKind.Window, "启用悬浮球", "在其他应用中快速复制和打开面板", state.overlayEnabled, onOverlayEnabledChange, ClipDockTone.Blue)
        SettingDivider()
        SettingRow(ClipDockIconKind.More, "外观与位置", "尺寸、停靠边缘和闲置透明度", tone = ClipDockTone.Neutral, onClick = { onOpenSettingsDetail(SettingsDetailDestination.FloatingBall) }) {
          StatusPill(if (state.overlayEnabled) "已启用" else "关闭", if (state.overlayEnabled) ClipDockTone.Green else ClipDockTone.Neutral)
        }
      }
    }

    item { SettingsSectionTitle("隐私与安全") }
    item {
      SettingGroup {
        SwitchSettingRow(ClipDockIconKind.Shield, "敏感内容保护", "密码和验证码不展示预览，加密密钥不外显", state.encryptionEnabled, onEncryptionEnabledChange, ClipDockTone.Green)
      }
    }

    item { SettingsSectionTitle("存储与高级") }
    item {
      SettingGroup {
        SettingRow(ClipDockIconKind.Trash, "清理历史与缓存", "删除本机缓存或远程空资产", tone = ClipDockTone.Amber) {
          ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(18.dp), color = LocalClipDockTokens.current.colors.muted)
        }
        SettingDivider()
        SettingRow(ClipDockIconKind.Server, "服务器地址", state.serverUrl, tone = ClipDockTone.Neutral, onClick = { onOpenSettingsDetail(SettingsDetailDestination.ServerAdvanced) }) {
          ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(18.dp), color = LocalClipDockTokens.current.colors.muted)
        }
      }
    }
  }
}

@Composable
private fun SettingsSectionTitle(text: String) {
  Text(
    text,
    color = LocalClipDockTokens.current.colors.faint,
    fontSize = 12.sp,
    lineHeight = 15.sp,
    fontWeight = FontWeight.ExtraBold,
    modifier = Modifier.padding(start = 6.dp, top = 6.dp, bottom = 2.dp),
  )
}

@Composable
private fun SyncStatusHero(state: ClipDockUiState, onSyncNow: () -> Unit) {
  val tokens = LocalClipDockTokens.current
  val connected = state.tokenPresent
  val onlineCount = state.p2pDevices.size + if (connected) 1 else 0
  Column(
    Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(18.dp))
      .background(tokens.colors.heroBanner)
      .padding(14.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
      IconTile(ClipDockIconKind.Cloud, tone = ClipDockTone.Neutral, dark = true)
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
          if (connected) "同步正常运行" else "未连接同步空间",
          color = tokens.colors.heroBannerContent,
          fontSize = 15.sp,
          lineHeight = 20.sp,
          fontWeight = FontWeight.ExtraBold,
        )
        Text(
          if (connected) "${state.deviceName} · 最近同步 ${relativeTimeLabel(state.diagnostics.lastSyncAtMillis)}" else "前往设备与配对加入空间",
          color = tokens.colors.heroBannerMuted,
          fontSize = 12.sp,
          lineHeight = 16.sp,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
      }
      StatusPill(if (connected) "已连接" else "未设置", if (connected) ClipDockTone.Green else ClipDockTone.Neutral)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      HeroMetric("$onlineCount 台", "在线设备", Modifier.weight(1f))
      HeroMetric("0 项", "待上传", Modifier.weight(1f))
      Box(
        Modifier
          .weight(1.15f)
          .height(46.dp)
          .clip(RoundedCornerShape(12.dp))
          .background(if (connected && !state.isSyncing) tokens.colors.accent else tokens.colors.heroBannerIconContainer)
          .clickable(enabled = connected && !state.isSyncing, onClick = onSyncNow),
        contentAlignment = Alignment.Center,
      ) {
        Text(
          if (state.isSyncing) "同步中…" else "立即同步",
          color = if (connected && !state.isSyncing) Color.White else tokens.colors.heroBannerMuted,
          fontSize = 13.sp,
          fontWeight = FontWeight.ExtraBold,
        )
      }
    }
  }
}

@Composable
private fun HeroMetric(value: String, label: String, modifier: Modifier = Modifier) {
  val tokens = LocalClipDockTokens.current
  Column(
    modifier
      .clip(RoundedCornerShape(12.dp))
      .background(tokens.colors.heroBannerIconContainer)
      .padding(horizontal = 11.dp, vertical = 7.dp),
    verticalArrangement = Arrangement.spacedBy(1.dp),
  ) {
    Text(value, color = tokens.colors.heroBannerContent, fontSize = 16.sp, lineHeight = 20.sp, fontWeight = FontWeight.ExtraBold)
    Text(label, color = tokens.colors.heroBannerMuted, fontSize = 10.sp, lineHeight = 13.sp)
  }
}

@Composable
private fun PairingPage(
  state: ClipDockUiState,
  onBack: () -> Unit,
  onDeviceNameChange: (String) -> Unit,
  onCreateSyncSpace: () -> Unit,
  onJoinSyncSpace: (String) -> Unit,
  onCreateInvite: () -> Unit,
) {
  var pairingCode by remember { mutableStateOf("") }
  val hasSyncRegistration = state.tokenPresent || !state.syncId.isNullOrBlank() || !state.deviceId.isNullOrBlank()
  val canRunSetup = !state.isSyncSetupInFlight
  LazyColumn(contentPadding = PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
    item {
      ClipDockScreenHeader(
        title = "配对新设备",
        subtitle = "创建或加入同步空间",
        actions = { ClipDockIconButton(ClipDockIconKind.Check, "返回设置", onClick = onBack) },
      )
    }
    item {
      ClipDockCard {
        Text("设备名称", style = MaterialTheme.typography.titleSmall)
        OutlinedTextField(value = state.deviceName, onValueChange = onDeviceNameChange, label = { Text("本机显示名") }, singleLine = true, modifier = Modifier.fillMaxWidth())
      }
    }
    item {
      ClipDockCard {
        Text("加入已有空间", style = MaterialTheme.typography.titleSmall)
        Text("输入另一台设备生成的 5 位配对码", style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted)
        OutlinedTextField(value = pairingCode, onValueChange = { pairingCode = it.take(5).uppercase() }, label = { Text("5 位配对码") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Button(onClick = { onJoinSyncSpace(pairingCode) }, enabled = pairingCode.length == 5 && canRunSetup, modifier = Modifier.fillMaxWidth()) { Text("加入空间") }
      }
    }
    item {
      ClipDockCard {
        Text("创建新空间", style = MaterialTheme.typography.titleSmall)
        Text(if (hasSyncRegistration) "本机已在同步空间中" else "在本机创建一个新的同步空间", style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted)
        Button(onClick = onCreateSyncSpace, enabled = !hasSyncRegistration && canRunSetup, modifier = Modifier.fillMaxWidth()) { Text("创建空间") }
      }
    }
    item {
      ClipDockCard {
        Text("邀请其他设备", style = MaterialTheme.typography.titleSmall)
        Text(state.pairingCode?.let { "当前配对码：$it" } ?: "生成一个 5 位配对码给新设备使用", style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted)
        OutlinedButton(onClick = onCreateInvite, enabled = state.tokenPresent && canRunSetup, modifier = Modifier.fillMaxWidth()) { Text(if (state.pairingCode == null) "生成配对码" else "刷新配对码") }
      }
    }
  }
}

@Composable
private fun ServerAdvancedPage(
  state: ClipDockUiState,
  onBack: () -> Unit,
  onServerUrlChange: (String) -> Unit,
  onCheckHealth: () -> Unit,
  onRefreshInfo: () -> Unit,
  onSyncNow: () -> Unit,
) {
  val canRunSetup = !state.isSyncSetupInFlight
  LazyColumn(contentPadding = PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
    item {
      ClipDockScreenHeader(
        title = "服务器与高级",
        subtitle = "服务端地址与连接维护",
        actions = { ClipDockIconButton(ClipDockIconKind.Check, "返回设置", onClick = onBack) },
      )
    }
    item {
      ClipDockCard {
        Text("服务端地址", style = MaterialTheme.typography.titleSmall)
        OutlinedTextField(value = state.serverUrl, onValueChange = onServerUrlChange, label = { Text("服务端地址") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedButton(onClick = onCheckHealth, enabled = canRunSetup, modifier = Modifier.fillMaxWidth()) { Text("检查连接") }
      }
    }
    item {
      ClipDockCard {
        Text("连接维护", style = MaterialTheme.typography.titleSmall)
        Text("同步空间：${state.syncId ?: "未加入"}", style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          OutlinedButton(onClick = onRefreshInfo, enabled = state.tokenPresent && canRunSetup, modifier = Modifier.weight(1f)) { Text("刷新能力") }
          Button(onClick = onSyncNow, enabled = state.tokenPresent && !state.isSyncing && canRunSetup, modifier = Modifier.weight(1f)) { Text("立即同步") }
        }
      }
    }
  }
}

@Composable
private fun KeepAlivePage(state: ClipDockUiState, onBack: () -> Unit) {
  val context = LocalContext.current
  val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
  val overlayGranted = Settings.canDrawOverlays(context)
  val notificationGranted =
    Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
  val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
  val batteryIgnored = powerManager.isIgnoringBatteryOptimizations(context.packageName)
  val missingPermissionCount = listOf(overlayGranted, notificationGranted, batteryIgnored).count { !it }
  LazyColumn(contentPadding = PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
    item {
      ClipDockScreenHeader(
        title = "保活权限",
        subtitle = "确保悬浮球和实时同步可靠运行",
        actions = { ClipDockIconButton(ClipDockIconKind.Check, "返回设置", onClick = onBack) },
      )
    }
    item {
      ClipDockHeroBanner(
        icon = ClipDockIconKind.Shield,
        title = if (missingPermissionCount == 0) "关键权限已处理" else "还差 ${missingPermissionCount} 项建议权限",
        subtitle = "不影响基础使用，但会影响后台实时同步时间",
        actionLabel = if (missingPermissionCount == 0) "完成" else "检查",
        actionTone = if (missingPermissionCount == 0) ClipDockTone.Green else ClipDockTone.Amber,
      )
    }
    item {
      RowCard(ClipDockIconKind.Window, "全局悬浮窗", "允许桌面显示悬浮球", tone = ClipDockTone.Green, onClick = { openOverlayPermission(context) }) {
        StatusPill(if (overlayGranted) "已授权" else "去开启", if (overlayGranted) ClipDockTone.Green else ClipDockTone.Amber)
      }
    }
    item {
      RowCard(ClipDockIconKind.Bell, "通知权限", if (Build.VERSION.SDK_INT >= 33) "用于前台同步状态提示" else "Android 13 以下内置可用", tone = ClipDockTone.Blue, onClick = {
        if (Build.VERSION.SDK_INT >= 33) {
          notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
          openNotificationSettings(context)
        }
      }) {
        StatusPill(if (notificationGranted) "已开启" else "去开启", if (notificationGranted) ClipDockTone.Green else ClipDockTone.Blue)
      }
    }
    item {
      RowCard(ClipDockIconKind.Battery, "忽略电池优化", "降低 Doze/App Standby 中断概率", tone = ClipDockTone.Amber, onClick = { openBatteryOptimizationSettings(context) }) {
        StatusPill(if (batteryIgnored) "已忽略" else "建议", if (batteryIgnored) ClipDockTone.Green else ClipDockTone.Amber)
      }
    }
    item {
      RowCard(ClipDockIconKind.Play, "厂商后台保护", "MIUI/ColorOS 等需要手动允许自启动", tone = ClipDockTone.Amber, onClick = { openVendorBackgroundSettings(context) }) {
        StatusPill("去设置", ClipDockTone.Amber)
      }
    }
    item {
      RowCard(ClipDockIconKind.Lock, "剪贴板隐私", "敏感内容写入使用系统内置标记", tone = ClipDockTone.Green) {
        StatusPill("内置", ClipDockTone.Green)
      }
    }
  }
}

@Composable
private fun FloatingBallSettingsPage(
  state: ClipDockUiState,
  onBack: () -> Unit,
  onOverlayEnabledChange: (Boolean) -> Unit,
  onOverlayClickActionChange: (OverlayClickAction) -> Unit,
  onOverlaySnapEdgeChange: (OverlaySnapEdge) -> Unit,
  onOverlaySizeChange: (Int) -> Unit,
  onOverlayIdleOpacityChange: (Int) -> Unit,
  onOverlayVerticalFractionChange: (Float) -> Unit,
) {
  val context = LocalContext.current
  LazyColumn(contentPadding = PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
    item {
      ClipDockScreenHeader(
        title = "悬浮球",
        subtitle = "点击复制最新，内滑展开侧栏",
        actions = { ClipDockIconButton(ClipDockIconKind.More, "返回设置", onClick = onBack) },
      )
    }
    item { FloatingPreview(state) }
    item {
      SettingGroup {
        SwitchSettingRow(
          ClipDockIconKind.Window,
          "启用悬浮球",
          "显示在系统桌面边缘",
          state.overlayEnabled,
          onCheckedChange = { enabled ->
            if (enabled) {
              if (Settings.canDrawOverlays(context)) {
                onOverlayEnabledChange(true)
                startFloatingOverlay(context)
              } else {
                openOverlayPermission(context)
              }
            } else {
              onOverlayEnabledChange(false)
              stopFloatingOverlay(context)
            }
          },
        )
        SettingDivider()
        SettingRow(ClipDockIconKind.Copy, "点击把手", "复制最新内容") {
          StatusPill("点击", ClipDockTone.Green)
        }
        LaunchedEffect(Unit) {
          onOverlayClickActionChange(OverlayClickAction.QuickSyncCopy)
        }
        SettingDivider()
        SettingRow(ClipDockIconKind.Window, "内滑把手", "展开侧边栏，选条目或同步") {
          StatusPill("展开", ClipDockTone.Blue)
        }
      }
    }
    item {
      ClipDockCard {
        Text("停靠方向", style = MaterialTheme.typography.titleSmall)
        Text("当前吸附到${if (state.overlaySnapEdge == OverlaySnapEdge.Right) "右侧" else "左侧"}边缘", style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted)
        SegmentedControl(
          options = listOf("左侧", "右侧"),
          selected = if (state.overlaySnapEdge == OverlaySnapEdge.Left) "左侧" else "右侧",
          onSelected = { label -> onOverlaySnapEdgeChange(if (label == "左侧") OverlaySnapEdge.Left else OverlaySnapEdge.Right) },
        )
      }
    }
    item {
      SliderSettingCard(
        title = "尺寸",
        subtitle = "${state.overlaySizeDp} dp · 兼顾可点按和遮挡范围",
        value = state.overlaySizeDp.toFloat(),
        onValueChange = { onOverlaySizeChange(it.toInt()) },
        valueRange = 52f..72f,
        steps = 19,
      )
    }
    item {
      SliderSettingCard(
        title = "闲置透明度",
        subtitle = "${state.overlayIdleOpacityPercent}% · 不完全隐藏，保持可发现",
        value = state.overlayIdleOpacityPercent.toFloat(),
        onValueChange = { onOverlayIdleOpacityChange(it.toInt()) },
        valueRange = 45f..100f,
        steps = 54,
      )
    }
    item {
      SliderSettingCard(
        title = "垂直位置",
        subtitle = "${(state.overlayVerticalFraction * 100).toInt()}% · 拖动后自动保存",
        value = state.overlayVerticalFraction,
        onValueChange = onOverlayVerticalFractionChange,
        valueRange = 0f..1f,
        steps = 19,
      )
    }
  }
}

@Composable
private fun FloatingPreview(state: ClipDockUiState) {
  val tokens = LocalClipDockTokens.current
  val latestItem = state.items.firstOrNull()
  Box(
    Modifier
      .fillMaxWidth()
      .height(112.dp)
      .clip(RoundedCornerShape(20.dp))
      .background(tokens.colors.surface2)
      .padding(16.dp),
  ) {
    ClipDockCard(modifier = Modifier.align(Alignment.CenterEnd).padding(end = 66.dp).width(190.dp)) {
      Text(if (latestItem == null) "暂无可复制内容" else "最近同步内容", style = MaterialTheme.typography.labelMedium)
      Text(
        latestItem?.let { it.displayTitle.ifBlank { it.displayBody } } ?: "同步后会显示真实最近记录",
        style = MaterialTheme.typography.labelSmall,
        color = tokens.colors.muted,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
      )
    }
    val right = state.overlaySnapEdge == OverlaySnapEdge.Right
    Box(
      Modifier
        .align(if (right) Alignment.CenterEnd else Alignment.CenterStart)
        .width(8.dp)
        .height(state.overlaySizeDp.dp)
        .clip(
          if (right) RoundedCornerShape(topStart = 6.dp, bottomStart = 6.dp) else RoundedCornerShape(topEnd = 6.dp, bottomEnd = 6.dp),
        )
        .background(tokens.colors.overlayDockHandle.copy(alpha = state.overlayIdleOpacityPercent / 100f)),
    )
  }
}

@Composable
private fun MetricCard(value: String, label: String, modifier: Modifier = Modifier) {
  ClipDockCard(modifier = modifier.height(58.dp), contentPadding = PaddingValues(horizontal = 10.dp, vertical = 9.dp)) {
    Text(value, style = MaterialTheme.typography.titleMedium, color = LocalClipDockTokens.current.colors.ink)
    Text(label, style = MaterialTheme.typography.labelSmall, color = LocalClipDockTokens.current.colors.muted)
  }
}

@Composable
private fun EmptyState(title: String, subtitle: String, actionLabel: String?, onAction: (() -> Unit)?) {
  ClipDockCard(modifier = Modifier.fillMaxWidth()) {
    Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Text(title, style = MaterialTheme.typography.titleMedium)
      Text(subtitle, style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted)
      if (actionLabel != null && onAction != null) {
        Button(onClick = onAction) { Text(actionLabel) }
      }
    }
  }
}

@Composable
private fun FeedbackBanner(message: String, isError: Boolean) {
  Surface(color = if (isError) LocalClipDockTokens.current.colors.dangerSoft else LocalClipDockTokens.current.colors.blueSoft, contentColor = if (isError) LocalClipDockTokens.current.colors.danger else LocalClipDockTokens.current.colors.accent2) {
    Text(message, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), style = MaterialTheme.typography.bodyMedium)
  }
}

@Composable
private fun rememberImageBitmap(uri: String?): androidx.compose.runtime.State<ImageBitmap?> {
  val context = LocalContext.current
  return produceState<ImageBitmap?>(initialValue = null, uri) {
    value =
      if (uri.isNullOrBlank()) {
        null
      } else {
        withContext(Dispatchers.IO) {
          runCatching {
              context.contentResolver.openInputStream(Uri.parse(uri))?.use { input ->
                BitmapFactory.decodeStream(input)?.asImageBitmap()
              }
            }
            .getOrNull()
        }
      }
  }
}

internal fun historyCardTestTag(stableId: String): String = "history-card-$stableId"

internal data class HistoryDetailDisplay(
  val previewIcon: ClipDockIconKind,
  val previewUri: String?,
  val title: String,
  val subtitle: String,
  val status: String,
  val source: String,
  val contentType: String,
  val timeLabel: String,
  val metaRows: List<HistoryDetailMetaRow>,
)

internal data class HistoryDetailMetaRow(
  val label: String,
  val value: String,
)

internal fun historyDetailDisplay(item: ClipHistoryItem): HistoryDetailDisplay {
  val source = item.sourceName?.takeIf { it.isNotBlank() } ?: "未知来源"
  val contentType = historyDetailContentType(item)
  val timeLabel = relativeTimeLabel(item.copiedAtMillis)
  val status = historyDetailStatus(item)
  val previewIcon =
    when (item.type) {
      ClipItemType.Image -> ClipDockIconKind.Image
      ClipItemType.File -> ClipDockIconKind.File
      ClipItemType.Link -> ClipDockIconKind.Link
      ClipItemType.Color -> ClipDockIconKind.Text
      ClipItemType.RichText,
      ClipItemType.Text -> ClipDockIconKind.Text
      ClipItemType.Unknown -> ClipDockIconKind.Alert
    }
  val previewUri =
    when (item.type) {
      ClipItemType.Link -> item.linkPreviewUri
      ClipItemType.Image -> item.thumbnailUri ?: item.localUri
      ClipItemType.File -> item.thumbnailUri
      else -> null
    }
  return HistoryDetailDisplay(
    previewIcon = previewIcon,
    previewUri = previewUri,
    title = item.displayTitle.ifBlank { item.type.label },
    subtitle = listOf(source, contentType, timeLabel).filter(String::isNotBlank).joinToString(" · "),
    status = status,
    source = source,
    contentType = contentType,
    timeLabel = timeLabel,
    metaRows =
      listOf(
        HistoryDetailMetaRow("状态", status),
        HistoryDetailMetaRow("来源设备", source),
        HistoryDetailMetaRow("内容类型", contentType),
        HistoryDetailMetaRow("时间", timeLabel),
      ),
  )
}

internal data class FileActionState(
  val primaryLabel: String,
  val message: String,
  val primaryEnabled: Boolean,
  val opensLocalUri: Boolean,
  val tone: ClipDockTone,
)

internal fun fileActionState(item: ClipHistoryItem, p2pEnabled: Boolean, wifiOnlyBlocked: Boolean): FileActionState =
  when {
    item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() ->
      FileActionState("打开", "已缓存 · ${item.body.ifBlank { item.detail.ifBlank { item.type.label } }}", primaryEnabled = true, opensLocalUri = true, tone = ClipDockTone.Green)
    item.assetId.isNullOrBlank() ->
      FileActionState("不可用", "缺少 assetId，无法取回", primaryEnabled = false, opensLocalUri = false, tone = ClipDockTone.Neutral)
    !p2pEnabled ->
      FileActionState("不可用", "P2P 未开启，无法取回远端内容", primaryEnabled = false, opensLocalUri = false, tone = ClipDockTone.Neutral)
    wifiOnlyBlocked ->
      FileActionState("等待 Wi-Fi", "仅 Wi-Fi 下载已开启，当前网络不可取回", primaryEnabled = false, opensLocalUri = false, tone = ClipDockTone.Amber)
    item.transferState == TransferState.DiscoveringPeer ->
      FileActionState("查找", "正在查找可用设备", primaryEnabled = false, opensLocalUri = false, tone = ClipDockTone.Blue)
    item.transferState == TransferState.Downloading ->
      FileActionState("下载中", "正在下载，进度由 P2P 传输完成后更新", primaryEnabled = false, opensLocalUri = false, tone = ClipDockTone.Blue)
    item.transferState == TransferState.Failed ->
      FileActionState("重试", "没有可用提供方或上次下载失败", primaryEnabled = true, opensLocalUri = false, tone = ClipDockTone.Amber)
    else ->
      FileActionState("取回", "远端内容尚未下载到本机", primaryEnabled = true, opensLocalUri = false, tone = ClipDockTone.Blue)
  }

private fun imageCacheSummary(item: ClipHistoryItem): String =
  when {
    item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() -> "原图已下载 · 自动使用清晰图片"
    item.transferState == TransferState.Downloading -> "正在下载原图 · 完成后自动切换清晰图"
    item.transferState == TransferState.DiscoveringPeer -> "正在查找来源设备 · 当前显示缩略图"
    item.thumbnailUri != null -> "原图保留在远端 · 当前显示模糊缩略图"
    else -> "远端原图未下载"
  }

private fun imageDrawerSubtitle(item: ClipHistoryItem): String {
  val source = item.sourceName?.takeIf(String::isNotBlank) ?: "未知来源"
  val time = relativeTimeLabel(item.copiedAtMillis)
  val sizeOrState =
    when {
      item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() -> item.localUri
      item.detail.isNotBlank() && !item.detail.startsWith("content://") -> imageDetailValueLabel(item.detail)
      item.thumbnailByteCount != null -> byteCountLabel(item.thumbnailByteCount).ifBlank { historyDetailStatus(item) }
      else -> historyDetailStatus(item)
    }
  return listOf(source, time, sizeOrState).filter(String::isNotBlank).joinToString(" · ")
}

private fun imageOriginalDimensionsLabel(item: ClipHistoryItem): String =
  if (item.thumbnailWidth != null && item.thumbnailHeight != null) {
    "${item.thumbnailWidth} x ${item.thumbnailHeight}"
  } else {
    "原图尺寸待取回"
  }

private fun imageOriginalSizeLabel(item: ClipHistoryItem): String =
  when {
    item.detail.isNotBlank() && !item.detail.startsWith("content://") -> imageDetailValueLabel(item.detail)
    item.thumbnailByteCount != null -> byteCountLabel(item.thumbnailByteCount).ifBlank { "原图大小待取回" }
    else -> "原图大小待取回"
  }

private fun imageDetailValueLabel(value: String): String {
  val trimmed = value.trim()
  val bytes = trimmed.toLongOrNull()
  return if (bytes != null) byteCountLabel(bytes).ifBlank { trimmed } else trimmed
}

private fun imageLocalCacheLabel(item: ClipHistoryItem): String =
  when {
    item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() -> "已下载到 app-owned cache"
    item.transferState == TransferState.Downloading -> "正在写入本机缓存"
    item.transferState == TransferState.DiscoveringPeer -> "等待来源设备"
    else -> "未下载"
  }

private fun imageOriginalStateLabel(item: ClipHistoryItem): String =
  when {
    item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() -> "本机可复制"
    item.transferState == TransferState.Downloading -> "下载中"
    item.transferState == TransferState.DiscoveringPeer -> "查找来源"
    item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed -> "取回失败"
    item.assetId.isNullOrBlank() -> "远端不可用"
    else -> "远端"
  }

private fun imageTransferTitle(item: ClipHistoryItem): String =
  when {
    item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() -> "清晰原图已就绪"
    item.transferState == TransferState.DiscoveringPeer -> "正在查找 P2P 来源"
    item.transferState == TransferState.Downloading -> "正在取回原图"
    item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed -> "取回失败"
    item.assetId.isNullOrBlank() -> "远端资产不可用"
    else -> "原图在远端设备"
  }

private fun imageTransferMessage(item: ClipHistoryItem, actions: MobileV4DetailActions): String =
  when {
    item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank() -> "复制时会直接使用本机原图，也可以只清理本机缓存保留同步记录。"
    item.transferState == TransferState.Downloading -> "P2P 下载完成后，本页会从模糊缩略图自动切换为本机清晰原图。"
    item.transferState == TransferState.DiscoveringPeer -> "正在根据 asset 查询可提供原图的设备。"
    item.thumbnailUri != null && actions.copyThumbnail.enabled -> "可先复制缩略图；选择取回或仅下载后会写入本机缓存。"
    else -> actions.primary.message
  }

private fun imageThumbnailDescription(item: ClipHistoryItem): String {
  val dimensions =
    if (item.thumbnailWidth != null && item.thumbnailHeight != null) {
      "${item.thumbnailWidth} x ${item.thumbnailHeight}"
    } else {
      "尺寸未知"
    }
  val bytes = byteCountLabel(item.thumbnailByteCount)
  val mime = item.thumbnailMimeType?.takeIf(String::isNotBlank) ?: "缩略图 MIME 未知"
  return listOf(dimensions, bytes, mime).filter(String::isNotBlank).joinToString(" · ")
}

private fun byteCountLabel(bytes: Long?): String =
  when {
    bytes == null || bytes <= 0L -> ""
    bytes < 1024L -> "$bytes B"
    bytes < 1024L * 1024L -> "${bytes / 1024L} KB"
    else -> String.format(java.util.Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
  }

private fun shortIdentifier(value: String): String =
  value
    .removePrefix("blake3:")
    .takeIf(String::isNotBlank)
    ?.let { if (it.length <= 16) it else "${it.take(10)}...${it.takeLast(6)}" }
    ?: "无"

private fun historyDetailStatus(item: ClipHistoryItem): String =
  when {
    item.transferState == TransferState.DiscoveringPeer -> "正在查找来源"
    item.transferState == TransferState.Downloading -> "正在下载"
    item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed -> "取回失败"
    mobileV4HasLocalCopySemantics(item) -> "已可复制"
    item.type == ClipItemType.Image || item.type == ClipItemType.File ->
      if (item.assetId.isNullOrBlank()) "远端不可用" else "远端可取回"
    item.type == ClipItemType.Unknown -> "暂不可用"
    else -> "暂不可用"
  }

private fun historyDetailContentType(item: ClipHistoryItem): String =
  when (item.type) {
    ClipItemType.Image -> historyMimeLabel(item.body, "图片")
    ClipItemType.File -> historyMimeLabel(item.body, "文件")
    ClipItemType.Link -> "链接"
    ClipItemType.Color -> "颜色"
    ClipItemType.RichText -> "富文本"
    ClipItemType.Text -> "文字"
    ClipItemType.Unknown -> "未知类型"
  }

private fun historyMimeLabel(value: String, fallback: String): String {
  val mime = value.trim().takeIf { it.isNotBlank() } ?: return fallback
  if (!mime.contains('/')) return mime
  val subtype = mime.substringAfter('/').substringBefore(';').substringAfterLast('.').uppercase()
  return subtype.takeIf { it.isNotBlank() }?.let { "$it $fallback" } ?: fallback
}

internal fun historyActionLabel(item: ClipHistoryItem): String =
  when (item.transferState) {
    TransferState.DiscoveringPeer -> "查找"
    TransferState.Downloading -> "下载中"
    TransferState.Failed -> "重试"
    TransferState.Ready -> "复制"
    TransferState.Idle ->
      when {
        item.needsRemotePayload && item.type == ClipItemType.Image -> "取回"
        item.needsRemotePayload -> "下载"
        else -> "复制"
      }
  }

private val ClipHistoryItem.displayTitle: String
  get() =
    when (type) {
      ClipItemType.Image -> title.takeUnless { it == "[图片]" } ?: body.takeIf { it.isNotBlank() && !it.startsWith("image/") } ?: "图片内容"
      else -> title.ifBlank { compactText }
    }

private val ClipHistoryItem.displayBody: String
  get() =
    when (type) {
      ClipItemType.Image -> body.takeIf { it.isNotBlank() } ?: detail
      else -> body
    }

private val ClipHistoryItem.metadataLabel: String
  get() =
    detail
      .takeUnless { it.isBlank() }
      ?.takeUnless { sourceName != null && it == sourceName }
      ?.let { if (it.length <= 8) it else it.substringAfterLast('.').takeIf { ext -> ext.length in 2..5 }?.uppercase() ?: it.take(7) + "..." }
      ?: ""

private fun relativeTimeLabel(timeMillis: Long): String {
  if (timeMillis <= 0L) return "未同步"
  val elapsed = System.currentTimeMillis() - timeMillis
  if (elapsed < 0) return "刚刚"
  val minutes = elapsed / 60_000
  return when {
    minutes < 1 -> "刚刚"
    minutes < 60 -> "${minutes} 分钟前"
    minutes < 24 * 60 -> "${minutes / 60} 小时前"
    else -> "${minutes / (24 * 60)} 天前"
  }
}

private fun pairingExpiryText(state: ClipDockUiState): String {
  val expiresAt = state.pairingExpiresAtMillis ?: return "未获取"
  val remainingSeconds = (expiresAt - System.currentTimeMillis()) / 1_000
  return if (remainingSeconds <= 0) "已过期" else "约 ${maxOf(1, (remainingSeconds + 59) / 60)} 分钟后过期"
}

private fun timeLabel(timeMillis: Long): String {
  if (timeMillis <= 0L) return "--:--"
  val elapsed = System.currentTimeMillis() - timeMillis
  val minutes = elapsed / 60_000
  return when {
    elapsed < 0 -> "刚刚"
    minutes < 1 -> "刚刚"
    minutes < 60 -> "${minutes} 分钟前"
    minutes < 24 * 60 -> "${minutes / 60} 小时前"
    else -> "${minutes / (24 * 60)} 天前"
  }
}

private fun typeTone(type: ClipItemType): ClipDockTone =
  when (type) {
    ClipItemType.Image -> ClipDockTone.Blue
    ClipItemType.File -> ClipDockTone.Amber
    ClipItemType.Link -> ClipDockTone.Blue
    ClipItemType.Color -> ClipDockTone.Amber
    ClipItemType.RichText -> ClipDockTone.Green
    ClipItemType.Text -> ClipDockTone.Neutral
    ClipItemType.Unknown -> ClipDockTone.Neutral
  }

private fun isWifiConnected(context: Context): Boolean {
  val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
  val network = manager.activeNetwork ?: return false
  val capabilities = manager.getNetworkCapabilities(network) ?: return false
  return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
}

private fun openLocalUri(context: Context, item: ClipHistoryItem) {
  val uri = item.localUri?.let(Uri::parse) ?: return
  val intent =
    Intent(Intent.ACTION_VIEW)
      .setDataAndType(uri, item.body.takeIf { it.contains("/") } ?: "*/*")
      .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
  runCatching { context.startActivity(intent) }.recoverCatching { openAppSettings(context) }
}

private fun openOverlayPermission(context: Context) {
  val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
  startActivityOrAppSettings(context, intent)
}

private fun openNotificationSettings(context: Context) {
  val intent =
    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
      .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
  startActivityOrAppSettings(context, intent)
}

private fun openBatteryOptimizationSettings(context: Context) {
  startActivityOrAppSettings(context, Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
}

private fun openVendorBackgroundSettings(context: Context) {
  val candidates =
    listOf(
      Intent().setClassName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
      Intent().setClassName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
      Intent().setClassName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
      Intent().setClassName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
    )
  val resolvable = candidates.firstOrNull { it.resolveActivity(context.packageManager) != null }
  startActivityOrAppSettings(context, resolvable ?: Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
}

private fun openAppSettings(context: Context) {
  startActivityOrAppSettings(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
}

private fun startActivityOrAppSettings(context: Context, intent: Intent) {
  try {
    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
  } catch (_: ActivityNotFoundException) {
    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
  }
}

private fun startFloatingOverlay(context: Context) {
  context.startService(Intent(context, FloatingOverlayService::class.java))
}

private fun stopFloatingOverlay(context: Context) {
  context.stopService(Intent(context, FloatingOverlayService::class.java))
}
