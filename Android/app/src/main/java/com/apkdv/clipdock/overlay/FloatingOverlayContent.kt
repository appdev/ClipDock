package com.apkdv.clipdock.overlay

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType

@Composable
fun FloatingOverlayContent(
  state: FloatingOverlayUiState,
  onBallClick: () -> Unit,
  onDrag: (Float, Float) -> Unit,
  onDragEnd: () -> Unit,
  onClosePanel: () -> Unit,
  onRetry: () -> Unit,
  onOpenApp: () -> Unit,
  onCopyItem: (ClipHistoryItem) -> Unit,
) {
  Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(4.dp)) {
    if (state.panel !is FloatingPanelState.Hidden) {
      FloatingResultPanel(
        panel = state.panel,
        recentItems = state.recentItems,
        onClosePanel = onClosePanel,
        onRetry = onRetry,
        onOpenApp = onOpenApp,
        onCopyItem = onCopyItem,
      )
    }
    FloatingBall(state.loading, onBallClick, onDrag, onDragEnd)
  }
}

@Composable
private fun FloatingBall(
  loading: Boolean,
  onBallClick: () -> Unit,
  onDrag: (Float, Float) -> Unit,
  onDragEnd: () -> Unit,
) {
  val transition = rememberInfiniteTransition(label = "floating-loading")
  val progress by
    transition.animateFloat(
      initialValue = 0f,
      targetValue = 360f,
      animationSpec = infiniteRepeatable(animation = tween(900), repeatMode = RepeatMode.Restart),
      label = "loading-angle",
    )

  Box(
    modifier =
      Modifier.size(64.dp)
        .pointerInput(Unit) {
          detectDragGestures(
            onDragEnd = onDragEnd,
            onDragCancel = onDragEnd,
            onDrag = { change, dragAmount ->
              onDrag(dragAmount.x, dragAmount.y)
            },
          )
        }
        .clip(CircleShape)
        .background(MaterialTheme.colorScheme.surface)
        .clickable(enabled = !loading, onClick = onBallClick),
    contentAlignment = Alignment.Center,
  ) {
    if (loading) {
      Canvas(Modifier.size(60.dp)) {
        drawArc(
          color = Color(0xFF0B63CE),
          startAngle = progress,
          sweepAngle = 96f,
          useCenter = false,
          topLeft = Offset(4f, 4f),
          size = Size(size.width - 8f, size.height - 8f),
          style = Stroke(width = 6f, cap = StrokeCap.Round),
        )
      }
    }
    Text("C", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleLarge)
    Box(Modifier.align(Alignment.BottomEnd).padding(8.dp).size(10.dp).clip(CircleShape).background(Color(0xFF16A34A)))
  }
}

@Composable
private fun FloatingResultPanel(
  panel: FloatingPanelState,
  recentItems: List<ClipHistoryItem>,
  onClosePanel: () -> Unit,
  onRetry: () -> Unit,
  onOpenApp: () -> Unit,
  onCopyItem: (ClipHistoryItem) -> Unit,
) {
  Card(
    shape = RoundedCornerShape(8.dp),
    elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    modifier = Modifier.width(306.dp),
  ) {
    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Row(verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
          Text(panelTitle(panel), fontWeight = FontWeight.SemiBold, color = panelColor(panel))
          Text(panelSubtitle(panel), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text("×", modifier = Modifier.clip(CircleShape).clickable(onClick = onClosePanel).padding(horizontal = 8.dp), style = MaterialTheme.typography.titleMedium)
      }
      when (panel) {
        is FloatingPanelState.Copied -> CopiedPreview(panel.item)
        is FloatingPanelState.Timeout -> TimeoutActions(panel.latest, panel.message, onRetry, onOpenApp)
        is FloatingPanelState.Failed -> TimeoutActions(panel.latest, panel.message, onRetry, onOpenApp)
        FloatingPanelState.Hidden -> Unit
      }
      if (recentItems.isNotEmpty()) {
        Text("最近记录", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        recentItems.take(5).forEach { item -> CompactItemRow(item, onCopyItem) }
      }
    }
  }
}

@Composable
private fun CopiedPreview(item: ClipHistoryItem) {
  SurfaceBlock {
    Text(item.compactText, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Medium)
    if (item.body.isNotBlank()) Text(item.body, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
  }
}

@Composable
private fun TimeoutActions(latest: ClipHistoryItem?, message: String, onRetry: () -> Unit, onOpenApp: () -> Unit) {
  SurfaceBlock {
    Text(message, style = MaterialTheme.typography.bodySmall)
    latest?.let { Text("最新内容：${it.compactText}", maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall) }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
      OutlinedButton(onClick = onRetry, modifier = Modifier.weight(1f)) { Text("重试") }
      Button(onClick = onOpenApp, modifier = Modifier.weight(1f)) { Text("打开") }
    }
  }
}

@Composable
private fun CompactItemRow(item: ClipHistoryItem, onCopyItem: (ClipHistoryItem) -> Unit) {
  Row(
    Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).clickable { onCopyItem(item) }.padding(vertical = 6.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Box(Modifier.size(28.dp).clip(RoundedCornerShape(6.dp)).background(typeColor(item.type).copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
      Text(item.type.label.take(1), color = typeColor(item.type), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
    }
    Spacer(Modifier.width(8.dp))
    Column(Modifier.weight(1f)) {
      Text(item.compactText, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
      if (item.body.isNotBlank()) Text(item.body, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Text("复制", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
  }
}

@Composable
private fun SurfaceBlock(content: @Composable ColumnScope.() -> Unit) {
  Column(
    Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)).padding(10.dp),
    verticalArrangement = Arrangement.spacedBy(6.dp),
    content = content,
  )
}

private fun panelTitle(panel: FloatingPanelState): String =
  when (panel) {
    is FloatingPanelState.Copied -> "已复制最新内容"
    is FloatingPanelState.Timeout -> "同步超时"
    is FloatingPanelState.Failed -> "复制失败"
    FloatingPanelState.Hidden -> ""
  }

private fun panelSubtitle(panel: FloatingPanelState): String =
  when (panel) {
    is FloatingPanelState.Copied -> "已写入系统剪贴板"
    is FloatingPanelState.Timeout -> "剪贴板未更改"
    is FloatingPanelState.Failed -> "剪贴板未更改"
    FloatingPanelState.Hidden -> ""
  }

private fun panelColor(panel: FloatingPanelState): Color =
  when (panel) {
    is FloatingPanelState.Copied -> Color(0xFF15803D)
    is FloatingPanelState.Timeout -> Color(0xFFD97706)
    is FloatingPanelState.Failed -> Color(0xFFDC2626)
    FloatingPanelState.Hidden -> Color.Unspecified
  }

private fun typeColor(type: ClipItemType): Color =
  when (type) {
    ClipItemType.Link -> Color(0xFF2563EB)
    ClipItemType.Image -> Color(0xFF0F766E)
    ClipItemType.File -> Color(0xFFD97706)
    ClipItemType.Color -> Color(0xFFFFB300)
    ClipItemType.RichText -> Color(0xFF16A34A)
    ClipItemType.Text -> Color(0xFF475569)
    ClipItemType.Unknown -> Color(0xFF64748B)
  }
