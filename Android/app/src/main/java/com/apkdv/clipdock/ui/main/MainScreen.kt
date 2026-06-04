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
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
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
import com.apkdv.clipdock.theme.ClipDockTheme
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
  onDestinationSelected: (MainDestination) -> Unit = {},
  onOpenSettingsDetail: (SettingsDetailDestination) -> Unit = {},
  onBackFromDetail: () -> Unit = {},
  modifier: Modifier = Modifier,
  viewModel: MainScreenViewModel = viewModel(),
) {
  val state by viewModel.uiState.collectAsStateWithLifecycle()
  ClipDockApp(
    state = state,
    selectedDestination = if (settingsDetail != null) MainDestination.Settings else selectedDestination,
    settingsDetail = settingsDetail,
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
    modifier = modifier,
  )
}

@Composable
internal fun ClipDockApp(
  state: ClipDockUiState,
  selectedDestination: MainDestination,
  settingsDetail: SettingsDetailDestination?,
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
  modifier: Modifier = Modifier,
) {
  val tokens = LocalClipDockTokens.current
  val context = LocalContext.current
  val wifiOnlyBlocked = state.wifiOnly && !isWifiConnected(context)

  Scaffold(
    modifier = modifier.fillMaxSize(),
    containerColor = tokens.colors.pageBg,
    bottomBar = {
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
    },
  ) { innerPadding ->
    Column(
      Modifier
        .padding(innerPadding)
        .fillMaxSize()
        .background(tokens.colors.pageBg),
    ) {
      if (state.isSyncing || state.isSyncSetupInFlight) {
        LinearProgressIndicator(Modifier.fillMaxWidth(), color = tokens.colors.accent)
      }
      state.diagnostics.lastError?.let { FeedbackBanner(it, isError = true) }
      when {
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
        selectedDestination == MainDestination.History ->
          HistoryPage(
            state = state,
            onOpenSettings = { onDestinationSelected(MainDestination.Settings) },
            onSyncNow = onSyncNow,
            onUseItem = onUseItem,
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
          )
        selectedDestination == MainDestination.Settings ->
          SettingsOverviewPage(
            state = state,
            onServerUrlChange = onServerUrlChange,
            onDeviceNameChange = onDeviceNameChange,
            onCheckHealth = onCheckHealth,
            onCreateSyncSpace = onCreateSyncSpace,
            onJoinSyncSpace = onJoinSyncSpace,
            onCreateInvite = onCreateInvite,
            onRefreshInfo = onRefreshInfo,
            onSyncNow = onSyncNow,
            onP2pEnabledChange = onP2pEnabledChange,
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
internal fun HistoryPage(
  state: ClipDockUiState,
  onOpenSettings: () -> Unit,
  onSyncNow: () -> Unit,
  onUseItem: (ClipHistoryItem) -> Unit,
  modifier: Modifier = Modifier,
) {
  val context = LocalContext.current
  var selectedVisualFilter by remember { mutableStateOf(HistoryVisualFilter.All) }
  var selectedStableId by rememberSaveable { mutableStateOf<String?>(null) }
  val filtered = filteredHistoryItems(state.items, selectedVisualFilter)
  val selectedItem = selectedStableId?.let { id -> state.items.firstOrNull { it.stableId == id } }

  LaunchedEffect(selectedStableId, selectedItem) {
    if (selectedStableId != null && selectedItem == null) {
      selectedStableId = null
    }
  }

  Box(modifier = modifier.fillMaxSize()) {
    LazyVerticalGrid(
      columns = GridCells.Fixed(2),
      contentPadding = PaddingValues(start = 14.dp, top = 12.dp, end = 14.dp, bottom = 24.dp),
      horizontalArrangement = Arrangement.spacedBy(10.dp),
      verticalArrangement = Arrangement.spacedBy(10.dp),
      modifier = Modifier.fillMaxSize(),
    ) {
      item(span = { GridItemSpan(maxLineSpan) }) {
        HistoryStableTopBar(
          state = state,
          onOpenSettings = onOpenSettings,
          onSyncNow = onSyncNow,
        )
      }
      item(span = { GridItemSpan(maxLineSpan) }) {
        HistoryVisualFilterRow(
          selected = selectedVisualFilter,
          onSelected = { selectedVisualFilter = it },
        )
      }
      if (filtered.isEmpty()) {
        item(span = { GridItemSpan(maxLineSpan) }) {
          EmptyState(
            title = if (state.tokenPresent) "暂无同步记录" else "先连接服务端",
            subtitle = if (state.tokenPresent) "点击同步拉取最近剪贴板历史。" else "ClipDock Android 会从同步空间读取最近历史。",
            actionLabel = if (state.tokenPresent) "立即同步" else "打开设置",
            onAction = if (state.tokenPresent) onSyncNow else onOpenSettings,
          )
        }
      } else {
        items(filtered, key = { it.stableId }) { item ->
          HistoryStableCard(
            item = item,
            onOpenDetail = { selectedStableId = item.stableId },
            modifier = Modifier.height(168.dp),
          )
        }
      }
    }

    selectedItem?.let { item ->
      HistoryDetailBottomSheet(
        item = item,
        p2pEnabled = state.p2pEnabled,
        wifiOnlyBlocked = state.wifiOnly && !isWifiConnected(context),
        onUseItem = onUseItem,
        onDismiss = { selectedStableId = null },
      )
    }
  }
}

private enum class HistoryVisualFilter(val label: String) {
  All("全部"),
  Link("链接"),
  Important("重要"),
  Image("图片"),
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
    modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
    verticalAlignment = Alignment.Top,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
      Text(
        "ClipDock",
        color = HistoryDesignInk,
        fontSize = 31.sp,
        lineHeight = 31.sp,
        fontWeight = FontWeight.Black,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      HistorySyncLine(
        state = state,
        onClick = if (state.tokenPresent) onSyncNow else onOpenSettings,
      )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
      HistoryRoundIconButton(icon = ClipDockIconKind.Search, contentDescription = "搜索", onClick = {})
      HistoryRoundIconButton(icon = ClipDockIconKind.Settings, contentDescription = "设置", onClick = onOpenSettings)
    }
  }
}

@Composable
private fun HistorySyncLine(state: ClipDockUiState, onClick: () -> Unit) {
  val dotColor =
    when {
      state.tokenPresent -> Color(0xFF22C55E)
      else -> Color(0xFFF59E0B)
    }
  Row(
    modifier =
      Modifier
        .height(22.dp)
        .clip(CircleShape)
        .clickable(onClick = onClick)
        .padding(end = 8.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(7.dp),
  ) {
    Box(Modifier.size(14.dp), contentAlignment = Alignment.Center) {
      Box(Modifier.matchParentSize().clip(CircleShape).background(dotColor.copy(alpha = 0.14f)))
      Box(Modifier.size(8.dp).clip(CircleShape).background(dotColor))
    }
    Text(
      historyStableSyncText(state),
      color = Color(0xFF7B8796),
      fontSize = 15.sp,
      lineHeight = 17.sp,
      fontWeight = FontWeight.Bold,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
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
    color = Color.White,
    contentColor = HistoryDesignInk,
    border = BorderStroke(1.dp, Color(0xFFE4EBF1)),
    shadowElevation = 10.dp,
    modifier =
      Modifier
        .size(46.dp)
        .clip(CircleShape)
        .clickable(onClick = onClick)
        .semantics { this.contentDescription = contentDescription },
  ) {
    Box(contentAlignment = Alignment.Center) {
      ClipDockSymbol(icon, Modifier.size(20.dp), color = HistoryDesignInk)
    }
  }
}

@Composable
private fun HistoryVisualFilterRow(
  selected: HistoryVisualFilter,
  onSelected: (HistoryVisualFilter) -> Unit,
) {
  Row(
    modifier = Modifier.fillMaxWidth().height(38.dp).padding(horizontal = 1.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    HistoryVisualFilter.entries.forEach { filter ->
      HistoryVisualFilterChip(
        filter = filter,
        selected = filter == selected,
        onClick = { onSelected(filter) },
      )
    }
  }
}

@Composable
private fun HistoryVisualFilterChip(
  filter: HistoryVisualFilter,
  selected: Boolean,
  onClick: () -> Unit,
) {
  val contentColor =
    when {
      selected -> Color.White
      filter == HistoryVisualFilter.Link -> Color(0xFF0F766E)
      filter == HistoryVisualFilter.Important -> Color(0xFFB26A00)
      filter == HistoryVisualFilter.Image -> Color(0xFFD54B6A)
      else -> Color(0xFF697586)
    }
  val dotColor =
    when (filter) {
      HistoryVisualFilter.Image -> Color(0xFFFB7185)
      HistoryVisualFilter.Important -> Color(0xFFF59E0B)
      HistoryVisualFilter.Link -> Color(0xFF0F766E)
      HistoryVisualFilter.All -> contentColor
    }
  Surface(
    shape = CircleShape,
    color = if (selected) Color(0xFF101820) else Color.White.copy(alpha = 0.92f),
    contentColor = contentColor,
    border = BorderStroke(1.dp, if (selected) Color(0xFF101820) else Color(0xFFDFE6EE)),
    shadowElevation = if (selected) 9.dp else 4.dp,
    modifier =
      Modifier
        .height(34.dp)
        .clip(CircleShape)
        .clickable(onClick = onClick),
  ) {
    Row(
      modifier = Modifier.padding(horizontal = 14.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
      if (filter == HistoryVisualFilter.All) {
        ClipDockSymbol(ClipDockIconKind.History, Modifier.size(15.dp), color = contentColor)
      } else {
        Box(Modifier.size(8.dp).clip(CircleShape).background(dotColor))
      }
      Text(
        filter.label,
        color = contentColor,
        fontSize = 13.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.ExtraBold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun HistoryStableCard(
  item: ClipHistoryItem,
  onOpenDetail: () -> Unit,
  modifier: Modifier = Modifier,
) {
  when (historyCardVariant(item)) {
    HistoryCardVariant.Code -> HistoryCodeCard(item = item, onOpenDetail = onOpenDetail, modifier = modifier)
    HistoryCardVariant.Note -> HistoryNoteCard(item = item, onOpenDetail = onOpenDetail, modifier = modifier)
    HistoryCardVariant.Image -> HistoryImageCard(item = item, onOpenDetail = onOpenDetail, modifier = modifier)
    HistoryCardVariant.Link -> HistoryHeaderBodyCard(item = item, variant = HistoryCardVariant.Link, onOpenDetail = onOpenDetail, modifier = modifier)
    HistoryCardVariant.Text -> HistoryHeaderBodyCard(item = item, variant = HistoryCardVariant.Text, onOpenDetail = onOpenDetail, modifier = modifier)
    HistoryCardVariant.File -> HistoryHeaderBodyCard(item = item, variant = HistoryCardVariant.File, onOpenDetail = onOpenDetail, modifier = modifier)
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HistoryDetailBottomSheet(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
  onUseItem: (ClipHistoryItem) -> Unit,
  onDismiss: () -> Unit,
) {
  val display = historyDetailSheetDisplay(item)
  val actions = historyDetailSheetActions(item, p2pEnabled, wifiOnlyBlocked)
  val showActionRow = actions.visibleTiles.isNotEmpty()
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  val runPrimaryAction = {
    if (actions.primary.enabled && actions.primary.invokesUseItem) {
      onUseItem(item)
    }
  }

  ModalBottomSheet(
    onDismissRequest = onDismiss,
    sheetState = sheetState,
    shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp),
    containerColor = Color.White,
    tonalElevation = 0.dp,
    dragHandle = { HistoryDetailSheetHandle() },
    modifier = Modifier.testTag(HistoryDetailSheetTags.Sheet),
  ) {
    Column(
      modifier =
        Modifier
          .fillMaxWidth()
          .heightIn(min = if (showActionRow) 388.dp else 314.dp)
          .padding(start = 18.dp, end = 18.dp, bottom = 18.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        HistoryDetailPreview(display)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
          Text(
            display.title,
            color = HistoryDesignInk,
            fontSize = 16.sp,
            lineHeight = 20.sp,
            fontWeight = FontWeight.Black,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
          )
          Text(
            display.subtitle,
            color = Color(0xFF64748B),
            fontSize = 12.sp,
            lineHeight = 16.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
          )
        }
        HistoryDetailCloseButton(onDismiss)
      }

      if (showActionRow) {
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
          actions.visibleTiles.forEach { action ->
            HistoryDetailActionTile(
              action = action,
              onClick = if (action.invokesUseItem) runPrimaryAction else ({}),
              modifier = Modifier.weight(1f),
            )
          }
        }
      }

      HistoryDetailMetaBox(display)

      Button(
        onClick = runPrimaryAction,
        enabled = actions.primary.enabled,
        colors =
          ButtonDefaults.buttonColors(
            containerColor = HistoryDesignInk,
            contentColor = Color.White,
            disabledContainerColor = Color(0xFFE2E8F0),
            disabledContentColor = Color(0xFF94A3B8),
          ),
        shape = RoundedCornerShape(15.dp),
        modifier = Modifier.fillMaxWidth().height(48.dp).testTag(HistoryDetailSheetTags.PrimaryButton),
      ) {
        ClipDockSymbol(actions.primary.icon, Modifier.size(18.dp), color = if (actions.primary.enabled) Color.White else Color(0xFF94A3B8))
        Spacer(Modifier.width(8.dp))
        Text(actions.primary.label, fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
      }
    }
  }
}

@Composable
private fun HistoryDetailSheetHandle() {
  Box(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 2.dp), contentAlignment = Alignment.Center) {
    Box(Modifier.width(44.dp).height(5.dp).clip(CircleShape).background(Color(0xFFCBD5E1)))
  }
}

@Composable
private fun HistoryDetailPreview(display: HistoryDetailSheetDisplay) {
  val bitmap by rememberImageBitmap(display.previewUri)
  Box(
    modifier =
      Modifier
        .size(70.dp)
        .clip(RoundedCornerShape(18.dp))
        .background(Brush.linearGradient(listOf(Color(0x3D18A67A), Color(0x242563EB)))),
    contentAlignment = Alignment.Center,
  ) {
    if (bitmap != null) {
      Image(bitmap = bitmap!!, contentDescription = display.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    } else {
      ClipDockSymbol(display.previewIcon, Modifier.size(30.dp), color = Color(0xFF0F766E))
    }
  }
}

@Composable
private fun HistoryDetailCloseButton(onDismiss: () -> Unit) {
  Surface(
    shape = CircleShape,
    color = Color(0xFFF1F5F9),
    contentColor = Color(0xFF64748B),
    modifier =
      Modifier
        .size(34.dp)
        .clip(CircleShape)
        .clickable(onClick = onDismiss)
        .testTag(HistoryDetailSheetTags.Close),
  ) {
    Box(contentAlignment = Alignment.Center) {
      ClipDockSymbol(ClipDockIconKind.X, Modifier.size(18.dp), color = Color(0xFF64748B))
    }
  }
}

@Composable
private fun HistoryDetailActionTile(
  action: HistoryDetailSheetAction,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val toneColor = historyDetailToneColor(action.tone)
  val isPrimary = action.testTag == HistoryDetailSheetTags.PrimaryActionTile
  val container =
    when {
      action.enabled && isPrimary -> Color(0xFFE8F6F1)
      action.enabled -> Color(0xFFF7FAFB)
      else -> Color(0xFFF8FAFC)
    }
  val contentColor =
    when {
      action.enabled && isPrimary -> toneColor
      action.enabled -> Color(0xFF334155)
      else -> Color(0xFFB6C2D0)
    }
  Surface(
    shape = RoundedCornerShape(18.dp),
    color = container,
    contentColor = contentColor,
    border = BorderStroke(1.dp, if (action.enabled && isPrimary) Color(0xFFCAEADF) else Color(0xFFEDF2F6)),
    modifier =
      modifier
        .height(72.dp)
        .clip(RoundedCornerShape(18.dp))
        .clickable(enabled = action.enabled, onClick = onClick)
        .testTag(action.testTag),
  ) {
    Column(
      modifier = Modifier.fillMaxSize().padding(horizontal = 4.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterVertically),
    ) {
      ClipDockSymbol(action.icon, Modifier.size(23.dp), color = contentColor)
      Text(
        action.label,
        color = contentColor,
        fontSize = 11.sp,
        lineHeight = 13.sp,
        fontWeight = FontWeight.ExtraBold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
  }
}

@Composable
private fun HistoryDetailMetaBox(display: HistoryDetailSheetDisplay) {
  Surface(
    shape = RoundedCornerShape(18.dp),
    color = Color(0xFFF8FAFC),
    border = BorderStroke(1.dp, Color(0xFFEDF2F6)),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
      display.metaRows.forEach { row ->
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(16.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(row.label, color = Color(0xFF64748B), fontSize = 12.sp, lineHeight = 15.sp, fontWeight = FontWeight.Medium)
          Text(
            row.value,
            color = Color(0xFF334155),
            fontSize = 12.sp,
            lineHeight = 15.sp,
            fontWeight = FontWeight.ExtraBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
          )
        }
      }
    }
  }
}

@Composable
private fun historyDetailToneColor(tone: ClipDockTone): Color {
  val tokens = LocalClipDockTokens.current
  return when (tone) {
    ClipDockTone.Green -> tokens.colors.accent
    ClipDockTone.Blue -> tokens.colors.accent2
    ClipDockTone.Amber -> tokens.colors.warn
    ClipDockTone.Red -> tokens.colors.danger
    ClipDockTone.Neutral -> tokens.colors.muted
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
      HistoryVisualFilter.Link -> historyCardVariant(item) == HistoryCardVariant.Link
      HistoryVisualFilter.Important -> isImportantVisual(item)
      HistoryVisualFilter.Image -> historyCardVariant(item) == HistoryCardVariant.Image
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
    !state.tokenPresent -> "未加入 · 打开设置"
    state.isSyncing -> "正在同步 · ${relativeTimeLabel(state.diagnostics.lastSyncAtMillis)}"
    state.isSyncSetupInFlight -> "正在连接 · 请稍候"
    state.diagnostics.lastSyncAtMillis > 0 -> "已同步 · ${relativeTimeLabel(state.diagnostics.lastSyncAtMillis)}"
    else -> "已加入 · 未同步"
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
  LazyColumn(
    contentPadding = PaddingValues(14.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp),
    modifier = Modifier.fillMaxSize(),
  ) {
    item {
      ClipDockScreenHeader(
        title = "设备",
        subtitle = "${state.syncId ?: "未加入同步空间"} · ${onlineDevices.size + 1} 台可见",
        actions = {
          ClipDockIconButton(ClipDockIconKind.Plus, "生成配对码", onClick = onCreateInvite, enabled = state.tokenPresent && !state.isSyncSetupInFlight)
          ClipDockIconButton(ClipDockIconKind.More, "刷新设备", onClick = onRefresh, enabled = state.tokenPresent && !state.isSyncSetupInFlight)
        },
      )
    }
    item {
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        MetricCard((onlineDevices.size + 1).toString(), "可见设备", Modifier.weight(1f))
        MetricCard(state.diagnostics.nextCursor.toString(), "最新序号", Modifier.weight(1f))
        MetricCard(onlineDevices.size.toString(), "P2P 可用", Modifier.weight(1f))
      }
    }
    item {
      ClipDockHeroBanner(
        icon = ClipDockIconKind.Link,
        title = "邀请新设备",
        subtitle = state.pairingCode?.let { "$it · ${pairingExpiryText(state)}" } ?: "生成 5 位配对码给新设备加入",
        actionLabel = if (state.pairingCode == null) "生成" else "刷新",
        onClick = onCreateInvite,
      )
    }
    item {
      RowCard(
        icon = ClipDockIconKind.Devices,
        title = "${state.deviceName} · 本机",
        subtitle = "状态 ${state.connectionStatus} · cursor ${state.diagnostics.nextCursor}",
        tone = ClipDockTone.Green,
      ) {
        StatusPill(if (state.tokenPresent) "在线" else "未加入", if (state.tokenPresent) ClipDockTone.Green else ClipDockTone.Neutral)
      }
    }
    onlineDevices.forEach { device ->
      item(key = device.deviceId) {
        DeviceEndpointRow(device)
      }
    }
    item {
      RowCard(
        icon = ClipDockIconKind.Alert,
        title = "撤销丢失设备",
        subtitle = "当前服务端未提供 Android 端撤销接口",
        tone = ClipDockTone.Red,
      ) {
        StatusPill("说明", ClipDockTone.Neutral)
      }
    }
    item {
      ClipDockCard {
        Text("服务器能力", style = MaterialTheme.typography.titleSmall)
        Text("Protocol v${state.capabilities.protocolVersion}", color = LocalClipDockTokens.current.colors.muted, style = MaterialTheme.typography.bodySmall)
        Text("P2P ${state.capabilities.p2p}", color = LocalClipDockTokens.current.colors.muted, style = MaterialTheme.typography.bodySmall, maxLines = 3, overflow = TextOverflow.Ellipsis)
      }
    }
  }
}

@Composable
private fun DeviceEndpointRow(device: P2pDeviceInfo) {
  RowCard(
    icon = ClipDockIconKind.Devices,
    title = device.deviceName,
    subtitle = "P2P endpoint 在线 · ${timeLabel(device.endpoint.updatedAtMillis)}",
    tone = ClipDockTone.Blue,
  ) {
    StatusPill("可取回", ClipDockTone.Green)
  }
}

@Composable
private fun FilesPage(state: ClipDockUiState, wifiOnlyBlocked: Boolean, onUseItem: (ClipHistoryItem) -> Unit) {
  val context = LocalContext.current
  var selectedSegment by remember { mutableStateOf("全部") }
  val fileItems =
    state.items
      .filter { it.type == ClipItemType.Image || it.type == ClipItemType.File }
      .filter {
        when (selectedSegment) {
          "图片" -> it.type == ClipItemType.Image
          "文件" -> it.type == ClipItemType.File
          "已缓存" -> it.payloadState == PayloadState.Ready && !it.localUri.isNullOrBlank()
          else -> true
        }
      }
  LazyColumn(contentPadding = PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
    item {
      ClipDockScreenHeader(
        title = "文件",
        subtitle = "远端 ${state.items.count { it.needsRemotePayload }} 个 · 本机缓存 ${state.items.count { !it.localUri.isNullOrBlank() }} 个",
        actions = {
          ClipDockIconButton(ClipDockIconKind.Search, "搜索文件", onClick = {}, enabled = false)
          ClipDockIconButton(ClipDockIconKind.Trash, "清理缓存", onClick = {}, enabled = false)
        },
      )
    }
    item {
      SegmentedControl(listOf("全部", "图片", "文件", "已缓存"), selectedSegment, { selectedSegment = it })
    }
    item {
      ClipDockHeroBanner(
        icon = ClipDockIconKind.Folder,
        title = "按需下载",
        subtitle = if (wifiOnlyBlocked) "仅 Wi-Fi 下载已开启，当前网络不可取回" else "远端图片/文件不会在列表中自动下载",
        actionLabel = if (state.wifiOnly) "仅 Wi-Fi" else "允许下载",
        actionTone = if (wifiOnlyBlocked) ClipDockTone.Amber else ClipDockTone.Blue,
      )
    }
    if (fileItems.isEmpty()) {
      item {
        EmptyState("暂无文件", "图片和文件会从同步历史中自动聚合。", null, null)
      }
    } else {
      fileItems.forEach { item ->
        item(key = item.stableId) {
          FileRow(
            item = item,
            p2pEnabled = state.p2pEnabled,
            wifiOnlyBlocked = wifiOnlyBlocked,
            onUseItem = onUseItem,
            onOpenItem = { openLocalUri(context, item) },
          )
        }
      }
    }
    item {
      RowCard(
        icon = ClipDockIconKind.Folder,
        title = "缓存策略",
        subtitle = "默认保留 app-owned P2P payload；暂不自动清理",
        tone = ClipDockTone.Green,
      ) {
        ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(18.dp), color = LocalClipDockTokens.current.colors.muted)
      }
    }
  }
}

@Composable
private fun FileRow(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
  onUseItem: (ClipHistoryItem) -> Unit,
  onOpenItem: () -> Unit,
) {
  val state = fileActionState(item, p2pEnabled, wifiOnlyBlocked)
  ClipDockCard {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
      IconTile(if (item.type == ClipItemType.Image) ClipDockIconKind.Image else ClipDockIconKind.File, tone = typeTone(item.type))
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(item.displayTitle, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(state.message, style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
      }
      ActionChip(
        label = state.primaryLabel,
        enabled = state.primaryEnabled,
        tone = state.tone,
        onClick = { if (state.opensLocalUri) onOpenItem() else onUseItem(item) },
      )
    }
    if (item.transferState == TransferState.Downloading) {
      LinearProgressIndicator(Modifier.fillMaxWidth(), color = LocalClipDockTokens.current.colors.accent)
    }
    if (item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank()) {
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = onOpenItem, modifier = Modifier.weight(1f)) { Text("打开") }
        Button(onClick = { onUseItem(item) }, modifier = Modifier.weight(1f)) { Text("复制") }
      }
    }
  }
}

@Composable
private fun SettingsOverviewPage(
  state: ClipDockUiState,
  onServerUrlChange: (String) -> Unit,
  onDeviceNameChange: (String) -> Unit,
  onCheckHealth: () -> Unit,
  onCreateSyncSpace: () -> Unit,
  onJoinSyncSpace: (String) -> Unit,
  onCreateInvite: () -> Unit,
  onRefreshInfo: () -> Unit,
  onSyncNow: () -> Unit,
  onP2pEnabledChange: (Boolean) -> Unit,
  onWifiOnlyChange: (Boolean) -> Unit,
  onOverlayEnabledChange: (Boolean) -> Unit,
  onEncryptionEnabledChange: (Boolean) -> Unit,
  onOpenSettingsDetail: (SettingsDetailDestination) -> Unit,
) {
  val context = LocalContext.current
  LazyColumn(contentPadding = PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
    item {
      ClipDockScreenHeader(
        title = "设置",
        subtitle = "${state.connectionStatus} · ${state.syncId ?: "未加入"}",
        actions = { ClipDockIconButton(ClipDockIconKind.More, "更多设置", onClick = {}, enabled = false) },
      )
    }
    item {
      SettingGroup {
        SettingRow(ClipDockIconKind.Cloud, "同步服务运行中", "Server ${state.connectionStatus} · 本机令牌${if (state.tokenPresent) "已保存" else "未设置"}") {
          StatusPill(if (state.tokenPresent) "正常" else "未设置", if (state.tokenPresent) ClipDockTone.Green else ClipDockTone.Neutral)
        }
        SettingDivider()
        SwitchSettingRow(ClipDockIconKind.Cloud, "剪贴板同步", "文本、链接和缩略图自动同步", checked = state.tokenPresent, onCheckedChange = {}, tone = ClipDockTone.Green)
        SettingDivider()
        SwitchSettingRow(ClipDockIconKind.Wifi, "P2P 远端取回", "图片和文件按需下载", state.p2pEnabled, onP2pEnabledChange, ClipDockTone.Blue)
        SettingDivider()
        SettingRow(ClipDockIconKind.Devices, "已连接设备", state.p2pDevices.joinToString(limit = 3) { it.deviceName }.ifBlank { "暂无 fresh P2P endpoint" }) {
          StatusPill("${state.p2pDevices.size + 1} 台", ClipDockTone.Green)
        }
      }
    }
    item {
      SettingGroup {
        SettingRow(ClipDockIconKind.Battery, "保活权限", "通知、后台、电池优化和厂商设置", tone = ClipDockTone.Amber, onClick = { onOpenSettingsDetail(SettingsDetailDestination.KeepAlive) }) {
          StatusPill("检查", ClipDockTone.Amber)
        }
        SettingDivider()
        SettingRow(ClipDockIconKind.Window, "悬浮球", "同步并复制最新内容", onClick = { onOpenSettingsDetail(SettingsDetailDestination.FloatingBall) }) {
          StatusPill(if (state.overlayEnabled) "已启用" else "关闭", if (state.overlayEnabled) ClipDockTone.Green else ClipDockTone.Neutral)
        }
        SettingDivider()
        SwitchSettingRow(ClipDockIconKind.Folder, "文件与缓存", "${if (state.wifiOnly) "仅 Wi-Fi" else "任意网络"} 下载", state.wifiOnly, onWifiOnlyChange, ClipDockTone.Blue)
        SettingDivider()
        SettingRow(ClipDockIconKind.Server, "服务器地址", state.serverUrl, onClick = null) {
          ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(18.dp), color = LocalClipDockTokens.current.colors.muted)
        }
        SettingDivider()
        SettingRow(ClipDockIconKind.Trash, "清理本机缓存", "仅限 app-owned P2P/cache 文件；暂未启用自动清理", tone = ClipDockTone.Red) {
          ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(18.dp), color = LocalClipDockTokens.current.colors.muted)
        }
      }
    }
    item {
      SyncSetupCard(
        state = state,
        onServerUrlChange = onServerUrlChange,
        onDeviceNameChange = onDeviceNameChange,
        onCheckHealth = onCheckHealth,
        onCreateSyncSpace = onCreateSyncSpace,
        onJoinSyncSpace = onJoinSyncSpace,
        onCreateInvite = onCreateInvite,
        onRefreshInfo = onRefreshInfo,
        onSyncNow = onSyncNow,
      )
    }
    item {
      ClipDockCard {
        SwitchSettingRow(ClipDockIconKind.Shield, "加密密钥", "可选；启用后不在界面显示原始密钥", state.encryptionEnabled, onEncryptionEnabledChange)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          Button(onClick = { startFloatingOverlay(context) }, enabled = state.overlayEnabled && Settings.canDrawOverlays(context), modifier = Modifier.weight(1f)) { Text("启动悬浮球") }
          OutlinedButton(onClick = { stopFloatingOverlay(context) }, modifier = Modifier.weight(1f)) { Text("停止") }
        }
      }
    }
  }
}

@Composable
private fun SyncSetupCard(
  state: ClipDockUiState,
  onServerUrlChange: (String) -> Unit,
  onDeviceNameChange: (String) -> Unit,
  onCheckHealth: () -> Unit,
  onCreateSyncSpace: () -> Unit,
  onJoinSyncSpace: (String) -> Unit,
  onCreateInvite: () -> Unit,
  onRefreshInfo: () -> Unit,
  onSyncNow: () -> Unit,
) {
  var pairingCode by remember { mutableStateOf("") }
  val hasSyncRegistration = state.tokenPresent || !state.syncId.isNullOrBlank() || !state.deviceId.isNullOrBlank()
  val canRunSetup = !state.isSyncSetupInFlight
  ClipDockCard {
    Text("同步空间设置", style = MaterialTheme.typography.titleSmall)
    OutlinedTextField(value = state.serverUrl, onValueChange = onServerUrlChange, label = { Text("服务端地址") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(value = state.deviceName, onValueChange = onDeviceNameChange, label = { Text("设备名称") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      OutlinedButton(onClick = onCheckHealth, enabled = canRunSetup, modifier = Modifier.weight(1f)) { Text("检查连接") }
      Button(onClick = onCreateSyncSpace, enabled = !hasSyncRegistration && canRunSetup, modifier = Modifier.weight(1f)) { Text("创建") }
    }
    OutlinedTextField(value = pairingCode, onValueChange = { pairingCode = it.take(5).uppercase() }, label = { Text("5 位配对码") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      Button(onClick = { onJoinSyncSpace(pairingCode) }, enabled = pairingCode.length == 5 && canRunSetup, modifier = Modifier.weight(1f)) { Text("加入") }
      OutlinedButton(onClick = onCreateInvite, enabled = state.tokenPresent && canRunSetup, modifier = Modifier.weight(1f)) { Text(if (state.pairingCode == null) "生成配对码" else "刷新配对码") }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      OutlinedButton(onClick = onRefreshInfo, enabled = state.tokenPresent && canRunSetup, modifier = Modifier.weight(1f)) { Text("刷新能力") }
      Button(onClick = onSyncNow, enabled = state.tokenPresent && !state.isSyncing && canRunSetup, modifier = Modifier.weight(1f)) { Text("立即同步") }
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
        title = if (overlayGranted && notificationGranted && batteryIgnored) "关键权限已处理" else "还有建议权限",
        subtitle = "不影响基础使用，但会影响后台实时同步时间",
        actionLabel = if (overlayGranted && notificationGranted && batteryIgnored) "完成" else "检查",
        actionTone = if (overlayGranted && notificationGranted && batteryIgnored) ClipDockTone.Green else ClipDockTone.Amber,
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
        subtitle = "桌面快速同步并复制",
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
        SettingRow(ClipDockIconKind.Copy, "点击动作", "同步一次并复制最新可用内容") {
          StatusPill("默认", ClipDockTone.Green)
        }
        LaunchedEffect(Unit) {
          onOverlayClickActionChange(OverlayClickAction.QuickSyncCopy)
        }
        SettingDivider()
        SettingRow(ClipDockIconKind.Window, "停靠边缘", "拖动松手后自动吸附") {
          StatusPill(if (state.overlaySnapEdge == OverlaySnapEdge.Right) "右侧" else "左侧", ClipDockTone.Neutral)
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
      .height(122.dp)
      .clip(RoundedCornerShape(22.dp))
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
    Box(
      Modifier
        .align(if (state.overlaySnapEdge == OverlaySnapEdge.Right) Alignment.CenterEnd else Alignment.CenterStart)
        .width(state.overlaySizeDp.dp)
        .height((state.overlaySizeDp + 6).dp)
        .clip(
          if (state.overlaySnapEdge == OverlaySnapEdge.Right) {
            RoundedCornerShape(topStart = 34.dp, bottomStart = 34.dp)
          } else {
            RoundedCornerShape(topEnd = 34.dp, bottomEnd = 34.dp)
          },
        )
        .background(tokens.colors.overlayBall.copy(alpha = state.overlayIdleOpacityPercent / 100f)),
      contentAlignment = Alignment.Center,
    ) {
      ClipDockSymbol(ClipDockIconKind.Copy, Modifier.size(24.dp), color = tokens.colors.overlayGlyph)
      Box(Modifier.align(Alignment.BottomEnd).padding(10.dp).size(8.dp).clip(CircleShape).background(tokens.colors.accent))
    }
  }
}

@Composable
private fun MetricCard(value: String, label: String, modifier: Modifier = Modifier) {
  ClipDockCard(modifier = modifier, contentPadding = PaddingValues(10.dp)) {
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

internal object HistoryDetailSheetTags {
  const val Sheet = "history-detail-sheet"
  const val Close = "history-detail-close"
  const val PrimaryButton = "history-detail-primary-button"
  const val PrimaryActionTile = "history-detail-action-primary"
  const val SecondaryActionTile = "history-detail-action-secondary"
  const val ShareActionTile = "history-detail-action-share"
  const val PinActionTile = "history-detail-action-pin"
}

internal fun historyCardTestTag(stableId: String): String = "history-card-$stableId"

internal data class HistoryDetailSheetDisplay(
  val previewIcon: ClipDockIconKind,
  val previewUri: String?,
  val title: String,
  val subtitle: String,
  val status: String,
  val source: String,
  val contentType: String,
  val timeLabel: String,
  val metaRows: List<HistoryDetailSheetMetaRow>,
)

internal data class HistoryDetailSheetMetaRow(
  val label: String,
  val value: String,
)

internal data class HistoryDetailSheetActions(
  val primary: HistoryDetailSheetAction,
  val tiles: List<HistoryDetailSheetAction>,
  val visibleTiles: List<HistoryDetailSheetAction>,
)

internal data class HistoryDetailSheetAction(
  val kind: HistoryDetailSheetActionKind,
  val label: String,
  val icon: ClipDockIconKind,
  val enabled: Boolean,
  val tone: ClipDockTone,
  val message: String,
  val invokesUseItem: Boolean,
  val testTag: String,
)

internal enum class HistoryDetailSheetActionKind {
  Copy,
  Retrieve,
  Retry,
  Unavailable,
  Share,
  Pin,
}

internal fun historyDetailSheetDisplay(item: ClipHistoryItem): HistoryDetailSheetDisplay {
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
      ClipItemType.Image -> item.thumbnailUri ?: item.localUri
      ClipItemType.File -> item.thumbnailUri
      else -> null
    }
  return HistoryDetailSheetDisplay(
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
        HistoryDetailSheetMetaRow("状态", status),
        HistoryDetailSheetMetaRow("来源设备", source),
        HistoryDetailSheetMetaRow("内容类型", contentType),
        HistoryDetailSheetMetaRow("时间", timeLabel),
      ),
  )
}

internal fun historyDetailSheetActions(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
): HistoryDetailSheetActions {
  val primary = historyDetailPrimaryAction(item, p2pEnabled, wifiOnlyBlocked)
  val secondary =
    if (primary.kind == HistoryDetailSheetActionKind.Copy) {
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Retrieve,
        label = "取回",
        icon = ClipDockIconKind.Download,
        message = "当前内容不需要远端取回",
        testTag = HistoryDetailSheetTags.SecondaryActionTile,
      )
    } else {
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Copy,
        label = "复制",
        icon = ClipDockIconKind.Copy,
        message = "取回完成后可复制",
        testTag = HistoryDetailSheetTags.SecondaryActionTile,
      )
    }
  val share =
    historyDetailDisabledAction(
      kind = HistoryDetailSheetActionKind.Share,
      label = "分享",
      icon = ClipDockIconKind.Share,
      message = "分享暂未接入系统协议",
      testTag = HistoryDetailSheetTags.ShareActionTile,
    )
  val pin =
    historyDetailDisabledAction(
      kind = HistoryDetailSheetActionKind.Pin,
      label = "固定",
      icon = ClipDockIconKind.Pin,
      message = "固定暂未接入同步协议",
      testTag = HistoryDetailSheetTags.PinActionTile,
    )
  val tiles = listOf(primary, secondary, share, pin)
  return HistoryDetailSheetActions(
    primary = primary,
    tiles = tiles,
    visibleTiles = tiles.filter { action -> action != primary && action.enabled },
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

private fun historyDetailPrimaryAction(
  item: ClipHistoryItem,
  p2pEnabled: Boolean,
  wifiOnlyBlocked: Boolean,
): HistoryDetailSheetAction =
  when {
    historyHasLocalCopySemantics(item) ->
      HistoryDetailSheetAction(
        kind = HistoryDetailSheetActionKind.Copy,
        label = "复制",
        icon = ClipDockIconKind.Copy,
        enabled = true,
        tone = ClipDockTone.Green,
        message = "复制到剪贴板",
        invokesUseItem = true,
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    item.type == ClipItemType.Unknown ->
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Unavailable,
        label = "不可用",
        icon = ClipDockIconKind.Alert,
        message = "未知类型暂不支持复制",
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    item.type != ClipItemType.Image && item.type != ClipItemType.File ->
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Unavailable,
        label = "不可用",
        icon = ClipDockIconKind.Alert,
        message = "该内容暂不支持复制",
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    item.assetId.isNullOrBlank() ->
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Unavailable,
        label = "不可用",
        icon = ClipDockIconKind.Alert,
        message = "缺少 assetId，无法取回",
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    !p2pEnabled ->
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Unavailable,
        label = "不可用",
        icon = ClipDockIconKind.Alert,
        message = "P2P 未开启，无法取回",
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    wifiOnlyBlocked ->
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Unavailable,
        label = "等待 Wi-Fi",
        icon = ClipDockIconKind.Wifi,
        message = "仅 Wi-Fi 下载已开启，当前网络不可取回",
        tone = ClipDockTone.Amber,
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    item.transferState == TransferState.DiscoveringPeer ->
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Retrieve,
        label = "查找",
        icon = ClipDockIconKind.Search,
        message = "正在查找可用设备",
        tone = ClipDockTone.Blue,
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    item.transferState == TransferState.Downloading ->
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Retrieve,
        label = "下载中",
        icon = ClipDockIconKind.Download,
        message = "正在下载，完成后可复制",
        tone = ClipDockTone.Blue,
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed ->
      HistoryDetailSheetAction(
        kind = HistoryDetailSheetActionKind.Retry,
        label = "重试",
        icon = ClipDockIconKind.Download,
        enabled = true,
        tone = ClipDockTone.Amber,
        message = "重试取回并复制",
        invokesUseItem = true,
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    item.transferState == TransferState.Idle ->
      HistoryDetailSheetAction(
        kind = HistoryDetailSheetActionKind.Retrieve,
        label = "取回",
        icon = ClipDockIconKind.Download,
        enabled = true,
        tone = ClipDockTone.Blue,
        message = "取回并复制到剪贴板",
        invokesUseItem = true,
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
    else ->
      historyDetailDisabledAction(
        kind = HistoryDetailSheetActionKind.Unavailable,
        label = "不可用",
        icon = ClipDockIconKind.Alert,
        message = "当前状态暂不可用",
        testTag = HistoryDetailSheetTags.PrimaryActionTile,
      )
  }

private fun historyDetailDisabledAction(
  kind: HistoryDetailSheetActionKind,
  label: String,
  icon: ClipDockIconKind,
  message: String,
  tone: ClipDockTone = ClipDockTone.Neutral,
  testTag: String,
): HistoryDetailSheetAction =
  HistoryDetailSheetAction(
    kind = kind,
    label = label,
    icon = icon,
    enabled = false,
    tone = tone,
    message = message,
    invokesUseItem = false,
    testTag = testTag,
  )

private fun historyHasLocalCopySemantics(item: ClipHistoryItem): Boolean =
  when (item.type) {
    ClipItemType.Text,
    ClipItemType.Link,
    ClipItemType.RichText,
    ClipItemType.Color -> !item.needsRemotePayload
    ClipItemType.Image,
    ClipItemType.File -> item.payloadState == PayloadState.Ready && !item.localUri.isNullOrBlank()
    ClipItemType.Unknown -> false
  }

private fun historyDetailStatus(item: ClipHistoryItem): String =
  when {
    item.transferState == TransferState.DiscoveringPeer -> "正在查找来源"
    item.transferState == TransferState.Downloading -> "正在下载"
    item.transferState == TransferState.Failed || item.payloadState == PayloadState.Failed -> "取回失败"
    historyHasLocalCopySemantics(item) -> "已可复制"
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
