package com.apkdv.clipdock.overlay

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apkdv.clipdock.data.ClipHistoryItem
import com.apkdv.clipdock.data.ClipItemType
import com.apkdv.clipdock.theme.LocalClipDockTokens
import com.apkdv.clipdock.ui.components.ClipDockIconKind
import com.apkdv.clipdock.ui.components.ClipDockSymbol
import kotlin.math.abs

@Composable
fun FloatingOverlayContent(
  state: FloatingOverlayUiState,
  onHandleTap: () -> Unit,
  onHandleExpand: () -> Unit,
  onHandleMove: (Float, Float) -> Unit,
  onHandleMoveEnd: () -> Unit,
  onCollapse: () -> Unit,
  onSync: () -> Unit,
  onCopyItem: (ClipHistoryItem) -> Unit,
  onSelectItem: (ClipHistoryItem) -> Unit,
  onOpenApp: () -> Unit,
) {
  if (state.expanded) {
    SideDock(state, onCollapse, onSync, onCopyItem, onSelectItem, onOpenApp)
  } else {
    CollapsedHandle(state, onHandleTap, onHandleExpand, onHandleMove, onHandleMoveEnd)
  }
}

@Composable
private fun CollapsedHandle(
  state: FloatingOverlayUiState,
  onTap: () -> Unit,
  onExpand: () -> Unit,
  onMove: (Float, Float) -> Unit,
  onMoveEnd: () -> Unit,
) {
  val right = state.edge == FloatingOverlayEdge.Right
  val alpha = if (state.loading) 1f else state.idleOpacityPercent.coerceIn(45, 100) / 100f
  Row(
    modifier = Modifier.padding(4.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(6.dp),
  ) {
    if (right && state.panel != FloatingPanelState.Hidden) FlashBubble(state.panel)
    HandleBar(state, right, alpha, onTap, onExpand, onMove, onMoveEnd)
    if (!right && state.panel != FloatingPanelState.Hidden) FlashBubble(state.panel)
  }
}

@Composable
private fun HandleBar(
  state: FloatingOverlayUiState,
  right: Boolean,
  alpha: Float,
  onTap: () -> Unit,
  onExpand: () -> Unit,
  onMove: (Float, Float) -> Unit,
  onMoveEnd: () -> Unit,
) {
  val tokens = LocalClipDockTokens.current.colors
  val barColor = if (state.loading) tokens.accent2 else tokens.overlayDockHandle
  val barShape =
    if (right) RoundedCornerShape(topStart = 6.dp, bottomStart = 6.dp) else RoundedCornerShape(topEnd = 6.dp, bottomEnd = 6.dp)
  Box(
    modifier =
      Modifier
        .graphicsLayer(alpha = alpha)
        .width(22.dp)
        .height(state.sizeDp.dp)
        .semantics { contentDescription = "点击复制最新内容，内滑展开剪贴板" }
        .pointerInput(right) { detectTapGestures(onTap = { onTap() }) }
        .pointerInput(right) {
          var ax = 0f
          var ay = 0f
          var mode = 0
          val expandPx = 22.dp.toPx()
          val movePx = 14.dp.toPx()
          detectDragGestures(
            onDragStart = {
              ax = 0f
              ay = 0f
              mode = 0
            },
            onDragEnd = { if (mode == 1) onMoveEnd() },
            onDragCancel = { if (mode == 1) onMoveEnd() },
          ) { _, drag ->
            ax += drag.x
            ay += drag.y
            if (mode == 0) {
              val inward = if (right) -ax else ax
              if (inward > expandPx && abs(ax) > abs(ay)) {
                mode = 2
                onExpand()
              } else if (abs(ay) > movePx && abs(ay) >= abs(ax)) {
                mode = 1
              }
            }
            if (mode == 1) onMove(drag.x, drag.y)
          }
        },
    contentAlignment = if (right) Alignment.CenterEnd else Alignment.CenterStart,
  ) {
    Box(Modifier.width(6.dp).height(46.dp).clip(barShape).background(barColor))
  }
}

@Composable
private fun FlashBubble(panel: FloatingPanelState) {
  val tokens = LocalClipDockTokens.current.colors
  val icon: ClipDockIconKind
  val label: String
  val color: Color
  when (panel) {
    is FloatingPanelState.Copied -> {
      icon = ClipDockIconKind.Check
      label = "已复制"
      color = tokens.overlayPanelSuccess
    }
    is FloatingPanelState.Timeout -> {
      icon = ClipDockIconKind.Download
      label = "需同步"
      color = tokens.overlayPanelWarn
    }
    is FloatingPanelState.Failed -> {
      icon = ClipDockIconKind.Alert
      label = "未就绪"
      color = tokens.overlayPanelDanger
    }
    FloatingPanelState.Hidden -> return
  }
  Row(
    modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(tokens.overlayDock).padding(horizontal = 10.dp, vertical = 7.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(5.dp),
  ) {
    ClipDockSymbol(icon, Modifier.size(14.dp), color = color)
    Text(label, color = tokens.overlayGlyph, fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
  }
}

@Composable
private fun SideDock(
  state: FloatingOverlayUiState,
  onCollapse: () -> Unit,
  onSync: () -> Unit,
  onCopyItem: (ClipHistoryItem) -> Unit,
  onSelectItem: (ClipHistoryItem) -> Unit,
  onOpenApp: () -> Unit,
) {
  val right = state.edge == FloatingOverlayEdge.Right
  val selected = state.recentItems.find { it.stableId == state.selectedItemId }
  Row(
    modifier = Modifier.padding(6.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    if (right && selected != null) PreviewFlyout(selected, onCopyItem)
    DockColumn(state, onCollapse, onSync, onCopyItem, onSelectItem, onOpenApp)
    if (!right && selected != null) PreviewFlyout(selected, onCopyItem)
  }
}

@Composable
private fun DockColumn(
  state: FloatingOverlayUiState,
  onCollapse: () -> Unit,
  onSync: () -> Unit,
  onCopyItem: (ClipHistoryItem) -> Unit,
  onSelectItem: (ClipHistoryItem) -> Unit,
  onOpenApp: () -> Unit,
) {
  val tokens = LocalClipDockTokens.current.colors
  Column(
    modifier = Modifier.width(72.dp).clip(RoundedCornerShape(20.dp)).background(tokens.overlayDock).padding(vertical = 9.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Box(
      modifier = Modifier.size(26.dp).clip(CircleShape).clickable(onClick = onCollapse),
      contentAlignment = Alignment.Center,
    ) {
      ClipDockSymbol(ClipDockIconKind.Chevron, Modifier.size(16.dp), color = Color(0xFF9AA9B5))
    }
    if (state.panel != FloatingPanelState.Hidden) StatusChip(state.panel)
    DockSyncTile(state.loading, onSync)
    DockDivider()
    state.recentItems.take(5).forEach { item ->
      DockItemTile(item, item.stableId == state.selectedItemId, onCopyItem, onSelectItem)
    }
    DockDivider()
    DockActionTile(ClipDockIconKind.Window, onOpenApp)
    DockActionTile(ClipDockIconKind.History, onOpenApp)
  }
}

@Composable
private fun DockDivider() {
  Box(Modifier.width(44.dp).height(1.dp).background(Color.White.copy(alpha = 0.10f)))
}

@Composable
private fun StatusChip(panel: FloatingPanelState) {
  val tokens = LocalClipDockTokens.current.colors
  val icon: ClipDockIconKind
  val label: String
  val color: Color
  when (panel) {
    is FloatingPanelState.Copied -> {
      icon = ClipDockIconKind.Check
      label = "已复制"
      color = tokens.overlayPanelSuccess
    }
    is FloatingPanelState.Timeout -> {
      icon = ClipDockIconKind.Download
      label = "需同步"
      color = tokens.overlayPanelWarn
    }
    is FloatingPanelState.Failed -> {
      icon = ClipDockIconKind.Alert
      label = "未就绪"
      color = tokens.overlayPanelDanger
    }
    FloatingPanelState.Hidden -> return
  }
  Row(
    modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(color.copy(alpha = 0.18f)).padding(horizontal = 7.dp, vertical = 4.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(3.dp),
  ) {
    ClipDockSymbol(icon, Modifier.size(11.dp), color = color)
    Text(label, color = color, fontSize = 9.sp, lineHeight = 11.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
  }
}

@Composable
private fun DockSyncTile(loading: Boolean, onSync: () -> Unit) {
  val tokens = LocalClipDockTokens.current.colors
  Box(
    modifier = Modifier.size(48.dp).clip(RoundedCornerShape(15.dp)).background(tokens.accent).clickable(enabled = !loading, onClick = onSync),
    contentAlignment = Alignment.Center,
  ) {
    if (loading) {
      val transition = rememberInfiniteTransition(label = "dock-sync")
      val angle by
        transition.animateFloat(
          initialValue = 0f,
          targetValue = 360f,
          animationSpec = infiniteRepeatable(animation = tween(900), repeatMode = RepeatMode.Restart),
          label = "dock-sync-angle",
        )
      Canvas(Modifier.size(34.dp)) {
        drawArc(
          color = Color.White,
          startAngle = angle,
          sweepAngle = 90f,
          useCenter = false,
          topLeft = Offset(3f, 3f),
          size = Size(size.width - 6f, size.height - 6f),
          style = Stroke(width = 5f, cap = StrokeCap.Round),
        )
      }
    } else {
      ClipDockSymbol(ClipDockIconKind.Cloud, Modifier.size(22.dp), color = Color.White)
    }
  }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DockItemTile(
  item: ClipHistoryItem,
  selected: Boolean,
  onCopyItem: (ClipHistoryItem) -> Unit,
  onSelectItem: (ClipHistoryItem) -> Unit,
) {
  val tone = typeColor(item.type)
  Box(
    modifier =
      Modifier
        .size(46.dp)
        .clip(RoundedCornerShape(14.dp))
        .background(tone.copy(alpha = 0.16f))
        .then(if (selected) Modifier.border(1.5.dp, tone, RoundedCornerShape(14.dp)) else Modifier)
        .combinedClickable(onClick = { onCopyItem(item) }, onLongClick = { onSelectItem(item) }),
    contentAlignment = Alignment.Center,
  ) {
    ClipDockSymbol(typeIcon(item.type), Modifier.size(19.dp), color = tone)
  }
}

@Composable
private fun DockActionTile(icon: ClipDockIconKind, onClick: () -> Unit) {
  Box(
    modifier = Modifier.size(46.dp).clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = 0.06f)).clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    ClipDockSymbol(icon, Modifier.size(18.dp), color = Color(0xFF9AA9B5))
  }
}

@Composable
private fun PreviewFlyout(item: ClipHistoryItem, onCopyItem: (ClipHistoryItem) -> Unit) {
  val tokens = LocalClipDockTokens.current.colors
  val tone = typeColor(item.type)
  Column(
    modifier = Modifier.width(168.dp).clip(RoundedCornerShape(16.dp)).background(tokens.overlayDock).padding(12.dp),
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
      Box(Modifier.clip(RoundedCornerShape(6.dp)).background(tone.copy(alpha = 0.20f)).padding(horizontal = 6.dp, vertical = 2.dp)) {
        Text(item.type.label, color = tone, fontSize = 10.sp, lineHeight = 13.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
      }
      item.sourceName?.takeIf { it.isNotBlank() }?.let {
        Text(it, color = Color(0xFF9AA9B5), fontSize = 10.sp, lineHeight = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
      }
    }
    Text(
      item.compactText,
      color = tokens.overlayGlyph,
      fontSize = 12.sp,
      lineHeight = 17.sp,
      maxLines = 3,
      overflow = TextOverflow.Ellipsis,
    )
    Box(
      modifier = Modifier.fillMaxWidth().height(32.dp).clip(RoundedCornerShape(9.dp)).background(tokens.accent).clickable(onClick = { onCopyItem(item) }),
      contentAlignment = Alignment.Center,
    ) {
      Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        ClipDockSymbol(ClipDockIconKind.Copy, Modifier.size(14.dp), color = Color.White)
        Text("复制", color = Color.White, fontSize = 12.sp, lineHeight = 15.sp, fontWeight = FontWeight.ExtraBold)
      }
    }
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

private fun typeIcon(type: ClipItemType): ClipDockIconKind =
  when (type) {
    ClipItemType.Link -> ClipDockIconKind.Link
    ClipItemType.Image -> ClipDockIconKind.Image
    ClipItemType.File -> ClipDockIconKind.File
    ClipItemType.Color -> ClipDockIconKind.Pin
    ClipItemType.RichText -> ClipDockIconKind.Text
    ClipItemType.Text -> ClipDockIconKind.Text
    ClipItemType.Unknown -> ClipDockIconKind.Copy
  }
