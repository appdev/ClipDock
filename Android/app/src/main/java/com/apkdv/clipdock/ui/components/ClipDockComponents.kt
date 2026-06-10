package com.apkdv.clipdock.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DividerDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apkdv.clipdock.R
import com.apkdv.clipdock.theme.LocalClipDockTokens

enum class ClipDockIconKind {
  History,
  Devices,
  Folder,
  Settings,
  Search,
  Plus,
  More,
  Cloud,
  Server,
  Wifi,
  Battery,
  Bell,
  Window,
  Lock,
  Shield,
  Play,
  Copy,
  File,
  Image,
  Link,
  Text,
  Alert,
  Trash,
  Check,
  Download,
  Share,
  Chevron,
  X,
  Pin,
}

@Composable
fun ClipDockScreenHeader(
  title: String,
  subtitle: String,
  modifier: Modifier = Modifier,
  actions: @Composable RowScope.() -> Unit = {},
) {
  Row(
    modifier = modifier.fillMaxWidth(),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(LocalClipDockTokens.current.spacing.gapMd),
  ) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
      Text(title, color = LocalClipDockTokens.current.colors.ink, fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
      Text(subtitle, color = LocalClipDockTokens.current.colors.muted, fontSize = 13.sp, lineHeight = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically, content = actions)
  }
}

@Composable
fun ClipDockIconButton(
  icon: ClipDockIconKind,
  contentDescription: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = CircleShape,
    color = tokens.colors.surface,
    contentColor = if (enabled) tokens.colors.muted else tokens.colors.faint,
    border = BorderStroke(1.dp, tokens.colors.line),
    modifier =
      modifier
        .size(42.dp)
        .clip(CircleShape)
        .clickable(enabled = enabled, onClick = onClick)
        .semantics { this.contentDescription = contentDescription },
  ) {
    Box(contentAlignment = Alignment.Center) {
      ClipDockSymbol(icon, Modifier.size(22.dp))
    }
  }
}

@Composable
fun ClipDockCard(
  modifier: Modifier = Modifier,
  contentPadding: PaddingValues = PaddingValues(14.dp),
  content: @Composable ColumnScope.() -> Unit,
) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = RoundedCornerShape(tokens.shapes.card),
    color = tokens.colors.surface,
    border = BorderStroke(1.dp, tokens.colors.softLine),
    shadowElevation = 0.dp,
    modifier = modifier,
  ) {
    Column(Modifier.padding(contentPadding), verticalArrangement = Arrangement.spacedBy(9.dp), content = content)
  }
}

@Composable
fun ClipDockHeroBanner(
  icon: ClipDockIconKind,
  title: String,
  subtitle: String,
  actionLabel: String,
  modifier: Modifier = Modifier,
  actionTone: ClipDockTone = ClipDockTone.Green,
  onClick: (() -> Unit)? = null,
) {
  val tokens = LocalClipDockTokens.current
  Row(
    modifier =
      modifier
        .fillMaxWidth()
        .clip(RoundedCornerShape(18.dp))
        .background(tokens.colors.heroBanner)
        .clickable(enabled = onClick != null, onClick = { onClick?.invoke() })
        .padding(12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    IconTile(icon, tone = ClipDockTone.Neutral, dark = true)
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
      Text(title, style = MaterialTheme.typography.titleSmall, color = tokens.colors.heroBannerContent)
      Text(subtitle, style = MaterialTheme.typography.bodySmall, color = tokens.colors.heroBannerMuted, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
    StatusPill(actionLabel, actionTone)
  }
}

@Composable
fun RowCard(
  icon: ClipDockIconKind,
  title: String,
  subtitle: String,
  modifier: Modifier = Modifier,
  tone: ClipDockTone = ClipDockTone.Green,
  onClick: (() -> Unit)? = null,
  trailing: @Composable RowScope.() -> Unit = {},
) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = RoundedCornerShape(tokens.shapes.rowCard),
    color = tokens.colors.surface,
    border = BorderStroke(1.dp, tokens.colors.softLine),
    modifier =
      modifier
        .fillMaxWidth()
        .clip(RoundedCornerShape(tokens.shapes.rowCard))
        .clickable(enabled = onClick != null, onClick = { onClick?.invoke() }),
  ) {
    Row(
      modifier = Modifier.fillMaxWidth().padding(11.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
      IconTile(icon = icon, tone = tone)
      Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = tokens.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = tokens.colors.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
      }
      trailing()
    }
  }
}

@Composable
fun SettingGroup(content: @Composable ColumnScope.() -> Unit) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = RoundedCornerShape(tokens.shapes.card),
    color = tokens.colors.surface,
    border = BorderStroke(1.dp, tokens.colors.softLine),
    modifier = Modifier.fillMaxWidth(),
  ) {
    Column(content = content)
  }
}

@Composable
fun SettingRow(
  icon: ClipDockIconKind,
  title: String,
  subtitle: String,
  modifier: Modifier = Modifier,
  tone: ClipDockTone = ClipDockTone.Green,
  onClick: (() -> Unit)? = null,
  trailing: @Composable RowScope.() -> Unit = {},
) {
  Row(
    modifier =
      modifier
        .fillMaxWidth()
        .height(60.dp)
        .clickable(enabled = onClick != null, onClick = { onClick?.invoke() })
        .padding(horizontal = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(11.dp),
  ) {
    IconTile(icon, tone)
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
      Text(title, style = MaterialTheme.typography.titleSmall, color = LocalClipDockTokens.current.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
      Text(subtitle, style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    trailing()
  }
}

@Composable
fun SettingDivider() {
  HorizontalDivider(color = LocalClipDockTokens.current.colors.softLine, thickness = DividerDefaults.Thickness)
}

@Composable
fun SwitchSettingRow(
  icon: ClipDockIconKind,
  title: String,
  subtitle: String,
  checked: Boolean,
  onCheckedChange: (Boolean) -> Unit,
  tone: ClipDockTone = ClipDockTone.Green,
) {
  SettingRow(icon = icon, title = title, subtitle = subtitle, tone = tone) {
    Switch(checked = checked, onCheckedChange = onCheckedChange)
  }
}

@Composable
fun StatusPill(
  label: String,
  tone: ClipDockTone,
  modifier: Modifier = Modifier,
) {
  val colors = tone.colors()
  Surface(shape = CircleShape, color = colors.container, contentColor = colors.content, modifier = modifier) {
    Text(label, modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp), style = MaterialTheme.typography.labelSmall, maxLines = 1)
  }
}

@Composable
fun ActionChip(
  label: String,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
  enabled: Boolean = true,
  tone: ClipDockTone = ClipDockTone.Green,
) {
  val colors = tone.colors()
  Surface(
    shape = CircleShape,
    color = colors.container.copy(alpha = if (enabled) colors.container.alpha else 0.5f),
    contentColor = if (enabled) colors.content else LocalClipDockTokens.current.colors.faint,
    modifier =
      modifier
        .height(30.dp)
        .clip(CircleShape)
        .clickable(enabled = enabled, onClick = onClick),
  ) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.padding(horizontal = 10.dp)) {
      Text(label, style = MaterialTheme.typography.labelSmall, maxLines = 1)
    }
  }
}

@Composable
fun SegmentedControl(
  options: List<String>,
  selected: String,
  onSelected: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  val tokens = LocalClipDockTokens.current
  Row(
    modifier =
      modifier
        .fillMaxWidth()
        .height(34.dp)
        .clip(CircleShape)
        .background(tokens.colors.surface3)
        .padding(3.dp),
    horizontalArrangement = Arrangement.spacedBy(4.dp),
  ) {
    options.forEach { option ->
      val isSelected = option == selected
      Box(
        modifier =
          Modifier
            .weight(1f)
            .height(28.dp)
            .clip(CircleShape)
            .background(if (isSelected) tokens.colors.surface else Color.Transparent)
            .selectable(
              selected = isSelected,
              role = Role.Tab,
              onClick = { onSelected(option) },
              interactionSource = remember { MutableInteractionSource() },
              indication = null,
            )
            .semantics { this.selected = isSelected },
        contentAlignment = Alignment.Center,
      ) {
        Text(option, style = MaterialTheme.typography.labelSmall, color = if (isSelected) tokens.colors.ink else tokens.colors.muted)
      }
    }
  }
}

@Composable
fun SliderSettingCard(
  title: String,
  subtitle: String,
  value: Float,
  onValueChange: (Float) -> Unit,
  valueRange: ClosedFloatingPointRange<Float>,
  steps: Int,
  modifier: Modifier = Modifier,
) {
  ClipDockCard(modifier = modifier) {
    Text(title, style = MaterialTheme.typography.titleSmall, color = LocalClipDockTokens.current.colors.ink)
    Text(subtitle, style = MaterialTheme.typography.bodySmall, color = LocalClipDockTokens.current.colors.muted)
    Slider(value = value, onValueChange = onValueChange, valueRange = valueRange, steps = steps)
  }
}

@Composable
fun IconTile(
  icon: ClipDockIconKind,
  tone: ClipDockTone,
  modifier: Modifier = Modifier,
  dark: Boolean = false,
) {
  val colors = tone.colors()
  Box(
    modifier =
      modifier
        .size(40.dp)
        .clip(RoundedCornerShape(LocalClipDockTokens.current.shapes.iconTile))
        .background(if (dark) LocalClipDockTokens.current.colors.heroBannerIconContainer else colors.container),
    contentAlignment = Alignment.Center,
  ) {
    ClipDockSymbol(icon, Modifier.size(21.dp), color = if (dark) LocalClipDockTokens.current.colors.heroBannerContent else colors.content)
  }
}

@Composable
fun ClipDockBottomNav(
  destinations: List<BottomNavItem>,
  selected: String,
  onSelected: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  val tokens = LocalClipDockTokens.current
  Surface(
    shape = RoundedCornerShape(tokens.shapes.bottomNav),
    color = tokens.colors.surface.copy(alpha = 0.94f),
    border = BorderStroke(1.dp, tokens.colors.softLine),
    shadowElevation = 4.dp,
    modifier =
      modifier
        .fillMaxWidth()
        .height(76.dp),
  ) {
    Row(
      modifier = Modifier.fillMaxSize().padding(7.dp),
      horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
      destinations.forEach { destination ->
        val isSelected = destination.key == selected
        val contentColor = if (isSelected) tokens.colors.accent else tokens.colors.muted
        Column(
          modifier =
            Modifier
              .weight(1f)
              .fillMaxHeight()
              .clip(RoundedCornerShape(17.dp))
              .background(if (isSelected) tokens.colors.accentSoft else Color.Transparent)
              .clickable { onSelected(destination.key) }
              .semantics {
                this.contentDescription = destination.label
                this.selected = isSelected
              },
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
        ) {
          ClipDockSymbol(destination.icon, Modifier.size(22.dp), color = contentColor)
          Text(
            destination.label,
            color = contentColor,
            fontSize = 12.sp,
            lineHeight = 16.sp,
            fontWeight = FontWeight.ExtraBold,
            maxLines = 1,
          )
        }
      }
    }
  }
}

data class BottomNavItem(val key: String, val label: String, val icon: ClipDockIconKind)

enum class ClipDockTone {
  Green,
  Blue,
  Amber,
  Red,
  Neutral,
}

private data class ToneColors(val content: Color, val container: Color)

@Composable
private fun ClipDockTone.colors(): ToneColors {
  val colors = LocalClipDockTokens.current.colors
  return when (this) {
    ClipDockTone.Green -> ToneColors(colors.accent, colors.accentSoft)
    ClipDockTone.Blue -> ToneColors(colors.accent2, colors.blueSoft)
    ClipDockTone.Amber -> ToneColors(colors.warn, colors.warnSoft)
    ClipDockTone.Red -> ToneColors(colors.danger, colors.dangerSoft)
    ClipDockTone.Neutral -> ToneColors(colors.muted, colors.surface3)
  }
}

@Composable
@Suppress("UNUSED_PARAMETER")
fun ClipDockSymbol(
  icon: ClipDockIconKind,
  modifier: Modifier = Modifier,
  color: Color = LocalClipDockTokens.current.colors.muted,
  strokeWidth: Float = 2.4f,
) {
  Icon(
    painter = painterResource(icon.drawableRes),
    contentDescription = null,
    modifier = modifier,
    tint = color,
  )
}

@get:DrawableRes
private val ClipDockIconKind.drawableRes: Int
  get() =
    when (this) {
      ClipDockIconKind.History -> R.drawable.ic_clipdock_history
      ClipDockIconKind.Devices -> R.drawable.ic_clipdock_devices
      ClipDockIconKind.Folder -> R.drawable.ic_clipdock_folder
      ClipDockIconKind.Settings -> R.drawable.ic_clipdock_settings
      ClipDockIconKind.Search -> R.drawable.ic_clipdock_search
      ClipDockIconKind.Plus -> R.drawable.ic_clipdock_plus
      ClipDockIconKind.More -> R.drawable.ic_clipdock_more
      ClipDockIconKind.Cloud -> R.drawable.ic_clipdock_cloud
      ClipDockIconKind.Server -> R.drawable.ic_clipdock_server
      ClipDockIconKind.Wifi -> R.drawable.ic_clipdock_wifi
      ClipDockIconKind.Battery -> R.drawable.ic_clipdock_battery
      ClipDockIconKind.Bell -> R.drawable.ic_clipdock_bell
      ClipDockIconKind.Window -> R.drawable.ic_clipdock_window
      ClipDockIconKind.Lock -> R.drawable.ic_clipdock_lock
      ClipDockIconKind.Shield -> R.drawable.ic_clipdock_shield
      ClipDockIconKind.Play -> R.drawable.ic_clipdock_play
      ClipDockIconKind.Copy -> R.drawable.ic_clipdock_copy
      ClipDockIconKind.File -> R.drawable.ic_clipdock_file
      ClipDockIconKind.Image -> R.drawable.ic_clipdock_image
      ClipDockIconKind.Link -> R.drawable.ic_clipdock_link
      ClipDockIconKind.Text -> R.drawable.ic_clipdock_text
      ClipDockIconKind.Alert -> R.drawable.ic_clipdock_alert
      ClipDockIconKind.Trash -> R.drawable.ic_clipdock_trash
      ClipDockIconKind.Check -> R.drawable.ic_clipdock_check
      ClipDockIconKind.Download -> R.drawable.ic_clipdock_download
      ClipDockIconKind.Share -> R.drawable.ic_clipdock_share
      ClipDockIconKind.Chevron -> R.drawable.ic_clipdock_chevron
      ClipDockIconKind.X -> R.drawable.ic_clipdock_x
      ClipDockIconKind.Pin -> R.drawable.ic_clipdock_pin
    }
