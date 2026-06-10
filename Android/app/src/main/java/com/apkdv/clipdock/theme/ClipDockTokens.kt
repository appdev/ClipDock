package com.apkdv.clipdock.theme

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Immutable
data class ClipDockColorTokens(
  val pageBg: Color,
  val surface: Color,
  val surface2: Color,
  val surface3: Color,
  val ink: Color,
  val muted: Color,
  val faint: Color,
  val line: Color,
  val softLine: Color,
  val accent: Color,
  val accent2: Color,
  val warn: Color,
  val danger: Color,
  val accentSoft: Color,
  val blueSoft: Color,
  val warnSoft: Color,
  val dangerSoft: Color,
  val heroBanner: Color,
  val heroBannerContent: Color,
  val heroBannerMuted: Color,
  val heroBannerIconContainer: Color,
  val historySyncBanner: Color,
  val overlayBall: Color,
  val overlayGlyph: Color,
  val overlayPanelSuccess: Color,
  val overlayPanelWarn: Color,
  val overlayPanelDanger: Color,
  val typeLink: Color,
  val typeImage: Color,
  val typeFile: Color,
  val typeColor: Color,
  val typeRichText: Color,
  val typeText: Color,
  val typeUnknown: Color,
  val success: Color = accent,
)

@Immutable
data class ClipDockSpacingTokens(
  val screen: Dp = 14.dp,
  val gapXs: Dp = 4.dp,
  val gapSm: Dp = 8.dp,
  val gapMd: Dp = 12.dp,
  val gapLg: Dp = 16.dp,
  val gapXl: Dp = 22.dp,
)

@Immutable
data class ClipDockShapeTokens(
  val card: Dp = 16.dp,
  val rowCard: Dp = 15.dp,
  val control: Dp = 999.dp,
  val iconTile: Dp = 12.dp,
  val bottomNav: Dp = 24.dp,
)

@Immutable
data class ClipDockTokens(
  val colors: ClipDockColorTokens,
  val spacing: ClipDockSpacingTokens = ClipDockSpacingTokens(),
  val shapes: ClipDockShapeTokens = ClipDockShapeTokens(),
)

val LightClipDockTokens =
  ClipDockTokens(
    colors =
      ClipDockColorTokens(
        pageBg = Color(0xFFF6F8F9),
        surface = Color(0xFFFFFFFF),
        surface2 = Color(0xFFF7FAFB),
        surface3 = Color(0xFFEEF4F2),
        ink = Color(0xFF172033),
        muted = Color(0xFF697586),
        faint = Color(0xFF94A3B8),
        line = Color(0xFFDBE3EA),
        softLine = Color(0x4794A3B8),
        accent = Color(0xFF18A67A),
        accent2 = Color(0xFF2563EB),
        warn = Color(0xFFC77916),
        danger = Color(0xFFD54B6A),
        accentSoft = Color(0xFFE8F6F1),
        blueSoft = Color(0xFFE9F0FF),
        warnSoft = Color(0xFFFFF4DF),
        dangerSoft = Color(0xFFFFF0F4),
        heroBanner = Color(0xFF10372E),
        heroBannerContent = Color(0xFFFFFFFF),
        heroBannerMuted = Color(0xFFCFE6DF),
        heroBannerIconContainer = Color(0x2EFFFFFF),
        historySyncBanner = Color(0xFF101820),
        overlayBall = Color(0xFF1C222D),
        overlayGlyph = Color(0xFFE5E7EB),
        overlayPanelSuccess = Color(0xFF15803D),
        overlayPanelWarn = Color(0xFFD97706),
        overlayPanelDanger = Color(0xFFDC2626),
        typeLink = Color(0xFF2563EB),
        typeImage = Color(0xFF0F766E),
        typeFile = Color(0xFFD97706),
        typeColor = Color(0xFFFFB300),
        typeRichText = Color(0xFF16A34A),
        typeText = Color(0xFF475569),
        typeUnknown = Color(0xFF64748B),
      ),
  )

val DarkClipDockTokens =
  ClipDockTokens(
    colors =
      ClipDockColorTokens(
        pageBg = Color(0xFF0D1416),
        surface = Color(0xFF141D20),
        surface2 = Color(0xFF101719),
        surface3 = Color(0xFF172422),
        ink = Color(0xFFEEF6F3),
        muted = Color(0xFF9AA9B5),
        faint = Color(0xFF778694),
        line = Color(0xFF26343A),
        softLine = Color(0x2E94A3B8),
        accent = Color(0xFF35D39F),
        accent2 = Color(0xFF73A5FF),
        warn = Color(0xFFF2B65E),
        danger = Color(0xFFFF7B99),
        accentSoft = Color(0x2635D39F),
        blueSoft = Color(0x2673A5FF),
        warnSoft = Color(0x24F2B65E),
        dangerSoft = Color(0x24FF7B99),
        heroBanner = Color(0xFF10372E),
        heroBannerContent = Color(0xFFFFFFFF),
        heroBannerMuted = Color(0xFFCFE6DF),
        heroBannerIconContainer = Color(0x2EFFFFFF),
        historySyncBanner = Color(0xFF101820),
        overlayBall = Color(0xFF1C222D),
        overlayGlyph = Color(0xFFE5E7EB),
        overlayPanelSuccess = Color(0xFF35D39F),
        overlayPanelWarn = Color(0xFFF2B65E),
        overlayPanelDanger = Color(0xFFFF7B99),
        typeLink = Color(0xFF73A5FF),
        typeImage = Color(0xFF35D39F),
        typeFile = Color(0xFFF2B65E),
        typeColor = Color(0xFFF2B65E),
        typeRichText = Color(0xFF35D39F),
        typeText = Color(0xFF9AA9B5),
        typeUnknown = Color(0xFF778694),
      ),
  )

val LocalClipDockTokens =
  staticCompositionLocalOf {
    LightClipDockTokens
  }
