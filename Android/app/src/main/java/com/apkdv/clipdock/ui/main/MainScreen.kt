package com.apkdv.clipdock.ui.main

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.apkdv.clipdock.data.ClipDockUiState
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.data.HistoryFilter
import com.apkdv.clipdock.data.PayloadState
import com.apkdv.clipdock.data.TransferState
import com.apkdv.clipdock.overlay.FloatingOverlayService
import com.apkdv.clipdock.theme.ClipDockTheme

private enum class MainTab(val label: String) {
  History("历史"),
  Settings("设置")
}

@Composable
fun MainScreen(modifier: Modifier = Modifier, viewModel: MainScreenViewModel = viewModel()) {
  val state by viewModel.uiState.collectAsStateWithLifecycle()
  ClipDockApp(
    state = state,
    onServerUrlChange = viewModel::setServerUrl,
    onDeviceNameChange = viewModel::setDeviceName,
    onFilterChange = viewModel::setFilter,
    onSyncNow = viewModel::syncNow,
    onCheckHealth = viewModel::checkHealth,
    onCreateSyncSpace = viewModel::createSyncSpace,
    onJoinSyncSpace = viewModel::joinSyncSpace,
    onCreateInvite = viewModel::createInvite,
    onRefreshInfo = viewModel::refreshInfo,
    onP2pEnabledChange = viewModel::setP2pEnabled,
    onWifiOnlyChange = viewModel::setWifiOnly,
    onOverlayEnabledChange = viewModel::setOverlayEnabled,
    onEncryptionEnabledChange = viewModel::setEncryptionEnabled,
    modifier = modifier,
  )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ClipDockApp(
  state: ClipDockUiState,
  onServerUrlChange: (String) -> Unit,
  onDeviceNameChange: (String) -> Unit,
  onFilterChange: (HistoryFilter) -> Unit,
  onSyncNow: () -> Unit,
  onCheckHealth: () -> Unit,
  onCreateSyncSpace: () -> Unit,
  onJoinSyncSpace: (String) -> Unit,
  onCreateInvite: () -> Unit,
  onRefreshInfo: () -> Unit,
  onP2pEnabledChange: (Boolean) -> Unit,
  onWifiOnlyChange: (Boolean) -> Unit,
  onOverlayEnabledChange: (Boolean) -> Unit,
  onEncryptionEnabledChange: (Boolean) -> Unit,
  modifier: Modifier = Modifier,
) {
  var selectedTab by remember { mutableStateOf(MainTab.History) }
  val context = LocalContext.current

  Scaffold(
    modifier = modifier.fillMaxSize(),
    topBar = {
      TopAppBar(
        title = {
          Column {
            Text("ClipDock", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text(state.connectionStatus, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
          }
        },
        actions = {
          TextButton(onClick = onSyncNow, enabled = state.tokenPresent && !state.isSyncing) { Text("同步") }
        },
      )
    },
    bottomBar = {
      NavigationBar {
        MainTab.entries.forEach { tab ->
          NavigationBarItem(selected = selectedTab == tab, onClick = { selectedTab = tab }, icon = { Text(if (tab == MainTab.History) "□" else "⚙") }, label = { Text(tab.label) })
        }
      }
    },
  ) { innerPadding ->
    Column(Modifier.padding(innerPadding).fillMaxSize()) {
      if (state.isSyncing) LinearProgressIndicator(Modifier.fillMaxWidth())
      when (selectedTab) {
        MainTab.History ->
          HistoryPage(
            state = state,
            onFilterChange = onFilterChange,
            onOpenSettings = { selectedTab = MainTab.Settings },
            onSyncNow = onSyncNow,
          )
        MainTab.Settings ->
          SettingsPage(
            state = state,
            context = context,
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
          )
      }
    }
  }
}

@Composable
private fun HistoryPage(
  state: ClipDockUiState,
  onFilterChange: (HistoryFilter) -> Unit,
  onOpenSettings: () -> Unit,
  onSyncNow: () -> Unit,
) {
  val filtered =
    state.items.filter { item ->
      when (state.selectedFilter) {
        HistoryFilter.All -> true
        HistoryFilter.Text -> item.type == ClipItemType.Text || item.type == ClipItemType.RichText
        HistoryFilter.Link -> item.type == ClipItemType.Link
        HistoryFilter.Image -> item.type == ClipItemType.Image
        HistoryFilter.File -> item.type == ClipItemType.File
        HistoryFilter.Color -> item.type == ClipItemType.Color
      }
    }

  LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
    if (!state.tokenPresent) {
      item {
        SetupBanner(onOpenSettings = onOpenSettings)
      }
    }
    item {
      FilterRow(selected = state.selectedFilter, onFilterChange = onFilterChange)
    }
    if (filtered.isEmpty()) {
      item {
        EmptyHistory(tokenPresent = state.tokenPresent, onSyncNow = onSyncNow, onOpenSettings = onOpenSettings)
      }
    } else {
      items(filtered, key = { it.stableId }) { item -> HistoryRow(item) }
    }
  }
}

@Composable
private fun FilterRow(selected: HistoryFilter, onFilterChange: (HistoryFilter) -> Unit) {
  Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
    HistoryFilter.entries.forEach { filter ->
      FilterChip(selected = selected == filter, onClick = { onFilterChange(filter) }, label = { Text(filter.label) })
    }
  }
}

@Composable
private fun SetupBanner(onOpenSettings: () -> Unit) {
  Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer), shape = RoundedCornerShape(8.dp)) {
    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
      Column(Modifier.weight(1f)) {
        Text("还未加入同步空间", fontWeight = FontWeight.SemiBold)
        Text("设置服务端地址后创建或输入配对码加入。", style = MaterialTheme.typography.bodySmall)
      }
      Button(onClick = onOpenSettings) { Text("设置") }
    }
  }
}

@Composable
private fun EmptyHistory(tokenPresent: Boolean, onSyncNow: () -> Unit, onOpenSettings: () -> Unit) {
  Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
    Text(if (tokenPresent) "暂无同步记录" else "先连接服务端", style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(8.dp))
    Text(if (tokenPresent) "点击同步拉取最近剪贴板历史。" else "ClipDock Android 会从同步空间读取最近历史。", color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(16.dp))
    Button(onClick = if (tokenPresent) onSyncNow else onOpenSettings) { Text(if (tokenPresent) "立即同步" else "打开设置") }
  }
}

@Composable
private fun HistoryRow(item: ClipHistoryItem) {
  Surface(shape = RoundedCornerShape(8.dp), tonalElevation = 1.dp, modifier = Modifier.fillMaxWidth()) {
    Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
      TypeBadge(item.type)
      Spacer(Modifier.width(12.dp))
      Column(Modifier.weight(1f)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Text(item.type.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
          item.sourceName?.let {
            Text(" · $it", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
          }
        }
        Text(item.title.ifBlank { item.compactText }, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
        if (item.body.isNotBlank()) Text(item.body, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          Text(item.detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
          if (item.payloadState == PayloadState.RemoteOnly) {
            Text("远程", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.tertiary)
          }
        }
      }
    }
  }
}

@Composable
private fun TypeBadge(type: ClipItemType) {
  val color =
    when (type) {
      ClipItemType.Link -> Color(0xFF2563EB)
      ClipItemType.Image -> Color(0xFF0F766E)
      ClipItemType.File -> Color(0xFFD97706)
      ClipItemType.Color -> Color(0xFFFFB300)
      ClipItemType.RichText -> Color(0xFF16A34A)
      ClipItemType.Text -> Color(0xFF475569)
      ClipItemType.Unknown -> Color(0xFF64748B)
    }
  Box(Modifier.size(42.dp).clip(RoundedCornerShape(8.dp)).background(color.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
    Text(
      when (type) {
        ClipItemType.Link -> "L"
        ClipItemType.Image -> "I"
        ClipItemType.File -> "F"
        ClipItemType.Color -> "C"
        ClipItemType.RichText -> "R"
        ClipItemType.Text -> "T"
        ClipItemType.Unknown -> "?"
      },
      color = color,
      fontWeight = FontWeight.Bold,
    )
  }
}

@Composable
private fun SettingsPage(
  state: ClipDockUiState,
  context: Context,
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
) {
  var pairingCode by remember { mutableStateOf("") }
  LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
    item {
      SettingsSection("服务端与同步空间") {
        OutlinedTextField(value = state.serverUrl, onValueChange = onServerUrlChange, label = { Text("服务端地址") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = state.deviceName, onValueChange = onDeviceNameChange, label = { Text("设备名称") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          OutlinedButton(onClick = onCheckHealth) { Text("检查连接") }
          Button(onClick = onCreateSyncSpace) { Text("创建同步空间") }
        }
        OutlinedTextField(value = pairingCode, onValueChange = { pairingCode = it.take(5).uppercase() }, label = { Text("5 位配对码") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Button(onClick = { onJoinSyncSpace(pairingCode) }, enabled = pairingCode.length == 5) { Text("加入同步空间") }
        InfoRow("同步空间", state.syncId ?: "未加入")
        InfoRow("本机设备", state.deviceId ?: "未注册")
        InfoRow("令牌状态", if (state.tokenPresent) "有效" else "未设置")
        state.pairingCode?.let { code ->
          InfoRow("当前配对码", "$code · ${state.pairingExpiresAtMillis ?: 0}")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          OutlinedButton(onClick = onCreateInvite, enabled = state.tokenPresent) { Text("生成配对码") }
          OutlinedButton(onClick = onRefreshInfo, enabled = state.tokenPresent) { Text("刷新能力") }
          Button(onClick = onSyncNow, enabled = state.tokenPresent && !state.isSyncing) { Text("立即同步") }
        }
      }
    }
    item {
      SettingsSection("同步诊断") {
        InfoRow("快照序号", state.diagnostics.snapshotSeq.toString())
        InfoRow("下一游标", state.diagnostics.nextCursor.toString())
        InfoRow("最后同步", state.diagnostics.lastSyncAtMillis.takeIf { it > 0 }?.toString() ?: "未同步")
        InfoRow("最后错误", state.diagnostics.lastError ?: "无")
      }
    }
    item {
      SettingsSection("下载与 P2P") {
        SwitchRow("P2P 下载", "完整图片/文件按需下载", state.p2pEnabled, onP2pEnabledChange)
        SwitchRow("仅 Wi-Fi 下载", "避免移动网络下载大文件", state.wifiOnly, onWifiOnlyChange)
        InfoRow("预览资产", state.capabilities.assetKinds.ifEmpty { listOf("未获取") }.joinToString())
        InfoRow("支持 MIME", state.capabilities.assetMimeTypes.ifEmpty { listOf("未获取") }.joinToString())
        InfoRow("最大资产大小", if (state.capabilities.maxAssetBytes > 0) "${state.capabilities.maxAssetBytes / 1024} KiB" else "未获取")
      }
    }
    item {
      SettingsSection("权限") {
        SwitchRow("启用悬浮球", "桌面点击后同步并复制最新内容", state.overlayEnabled, onOverlayEnabledChange)
        PermissionRow("全局悬浮窗", if (Settings.canDrawOverlays(context)) "已授权" else "未授权") { openOverlayPermission(context) }
        PermissionRow("后台运行", "按系统策略运行") { openAppSettings(context) }
        PermissionRow("电池优化", "按需加入白名单") { openAppSettings(context) }
        PermissionRow("通知权限", "用于前台同步状态") { openAppSettings(context) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          Button(onClick = { startFloatingOverlay(context) }, enabled = state.overlayEnabled && Settings.canDrawOverlays(context)) { Text("启动悬浮球") }
          OutlinedButton(onClick = { stopFloatingOverlay(context) }) { Text("停止") }
        }
      }
    }
    item {
      SettingsSection("加密") {
        SwitchRow("加密密钥", "可选；启用后不在界面显示原始密钥", state.encryptionEnabled, onEncryptionEnabledChange)
      }
    }
  }
}

@Composable
private fun SettingsSection(title: String, content: @Composable ColumnScope.() -> Unit) {
  Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
    Surface(shape = RoundedCornerShape(8.dp), tonalElevation = 1.dp, modifier = Modifier.fillMaxWidth()) {
      Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
  }
}

@Composable
private fun InfoRow(title: String, value: String) {
  Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    Text(title, modifier = Modifier.weight(1f), fontWeight = FontWeight.Medium)
    Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
  }
}

@Composable
private fun SwitchRow(title: String, detail: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
  Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    Column(Modifier.weight(1f)) {
      Text(title, fontWeight = FontWeight.Medium)
      Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Switch(checked = checked, onCheckedChange = onCheckedChange)
  }
}

@Composable
private fun PermissionRow(title: String, status: String, onClick: () -> Unit) {
  Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).clickable(onClick = onClick).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
    Column(Modifier.weight(1f)) {
      Text(title, fontWeight = FontWeight.Medium)
      Text(status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Text("›", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
  }
}

private fun openOverlayPermission(context: Context) {
  val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
  context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

private fun openAppSettings(context: Context) {
  val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
  context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

private fun startFloatingOverlay(context: Context) {
  context.startService(Intent(context, FloatingOverlayService::class.java))
}

private fun stopFloatingOverlay(context: Context) {
  context.stopService(Intent(context, FloatingOverlayService::class.java))
}

@Preview(showBackground = true, widthDp = 390)
@Composable
private fun ClipDockAppPreview() {
  ClipDockTheme {
    ClipDockApp(
      state =
        ClipDockUiState(
          tokenPresent = true,
          syncId = "sync_8K7Qh2L9",
          deviceId = "dev_3f81a7d2",
          connectionStatus = "已加入",
          items =
            listOf(
              ClipHistoryItem(
                stableId = "1",
                contentHash = "sha256:1",
                type = ClipItemType.Text,
                title = "会议记录",
                body = "项目进度同步：接口联调完成，UI 评审通过。",
                detail = "09:28",
                sourceName = "ClipDock",
                assetId = null,
                localUri = null,
                payloadState = PayloadState.Ready,
                transferState = TransferState.Idle,
                copiedAtMillis = 1,
                copyCount = 1,
              )
            ),
        ),
      onServerUrlChange = {},
      onDeviceNameChange = {},
      onFilterChange = {},
      onSyncNow = {},
      onCheckHealth = {},
      onCreateSyncSpace = {},
      onJoinSyncSpace = {},
      onCreateInvite = {},
      onRefreshInfo = {},
      onP2pEnabledChange = {},
      onWifiOnlyChange = {},
      onOverlayEnabledChange = {},
      onEncryptionEnabledChange = {},
    )
  }
}
