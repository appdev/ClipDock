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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.theme.LocalClipDockTokens
import com.apkdv.clipdock.ui.components.ClipDockIconKind
import com.apkdv.clipdock.ui.components.ClipDockSymbol

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
    if (state.edge == FloatingOverlayEdge.Left) {
      FloatingBall(state.loading, state.edge, state.sizeDp, state.idleOpacityPercent, onBallClick, onDrag, onDragEnd)
    }
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
    if (state.edge == FloatingOverlayEdge.Right) {
      FloatingBall(state.loading, state.edge, state.sizeDp, state.idleOpacityPercent, onBallClick, onDrag, onDragEnd)
    }
  }
}

@Composable
private fun FloatingBall(
  loading: Boolean,
  edge: FloatingOverlayEdge,
  sizeDp: Int,
  idleOpacityPercent: Int,
  onBallClick: () -> Unit,
  onDrag: (Float, Float) -> Unit,
  onDragEnd: () -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  val transition = rememberInfiniteTransition(label = "floating-loading")
  val progress by
    transition.animateFloat(
      initialValue = 0f,
      targetValue = 360f,
      animationSpec = infiniteRepeatable(animation = tween(900), repeatMode = RepeatMode.Restart),
      label = "loading-angle",
    )
  val shape =
    if (edge == FloatingOverlayEdge.Right) {
      RoundedCornerShape(topStart = 34.dp, bottomStart = 34.dp, topEnd = 0.dp, bottomEnd = 0.dp)
    } else {
      RoundedCornerShape(topStart = 0.dp, bottomStart = 0.dp, topEnd = 34.dp, bottomEnd = 34.dp)
    }

  Box(
    modifier =
      Modifier.width(sizeDp.dp)
        .height((sizeDp + 6).dp)
        .graphicsLayer(alpha = if (loading) 1f else idleOpacityPercent.coerceIn(45, 100) / 100f)
        .pointerInput(Unit) {
          detectDragGestures(
            onDragEnd = onDragEnd,
            onDragCancel = onDragEnd,
            onDrag = { change, dragAmount ->
              onDrag(dragAmount.x, dragAmount.y)
            },
          )
        }
        .clip(shape)
        .background(tokens.colors.overlayBall)
        .semantics { contentDescription = "同步并复制最新内容" }
        .clickable(enabled = !loading, onClick = onBallClick),
    contentAlignment = Alignment.Center,
  ) {
    if (loading) {
      Canvas(Modifier.size(58.dp)) {
        drawArc(
          color = tokens.colors.accent2,
          startAngle = progress,
          sweepAngle = 96f,
          useCenter = false,
          topLeft = Offset(4f, 4f),
          size = Size(size.width - 8f, size.height - 8f),
          style = Stroke(width = 6f, cap = StrokeCap.Round),
        )
      }
    }
    ClipboardGlyph(loading = loading)
    val dotAlignment = if (edge == FloatingOverlayEdge.Right) Alignment.BottomEnd else Alignment.BottomStart
    Box(
      Modifier.align(dotAlignment)
        .padding(horizontal = 9.dp, vertical = 12.dp)
        .size(12.dp)
        .clip(CircleShape)
        .background(tokens.colors.accent),
    )
  }
}

@Composable
private fun ClipboardGlyph(loading: Boolean) {
  val tokens = LocalClipDockTokens.current
  ClipDockSymbol(
    icon = ClipDockIconKind.Copy,
    modifier = Modifier.size(30.dp),
    color = if (loading) tokens.colors.accent2 else tokens.colors.overlayGlyph,
  )
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

@Composable
private fun panelColor(panel: FloatingPanelState): Color {
  val colors = LocalClipDockTokens.current.colors
  return when (panel) {
    is FloatingPanelState.Copied -> colors.overlayPanelSuccess
    is FloatingPanelState.Timeout -> colors.overlayPanelWarn
    is FloatingPanelState.Failed -> colors.overlayPanelDanger
    FloatingPanelState.Hidden -> Color.Unspecified
  }
}

@Composable
private fun typeColor(type: ClipItemType): Color {
  val colors = LocalClipDockTokens.current.colors
  return when (type) {
    ClipItemType.Link -> colors.typeLink
    ClipItemType.Image -> colors.typeImage
    ClipItemType.File -> colors.typeFile
    ClipItemType.Color -> colors.typeColor
    ClipItemType.RichText -> colors.typeRichText
    ClipItemType.Text -> colors.typeText
    ClipItemType.Unknown -> colors.typeUnknown
  }
}
