package com.apkdv.clipdock.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

private val DarkColorScheme =
  darkColorScheme(
    primary = DarkClipDockTokens.colors.accent,
    onPrimary = DarkClipDockTokens.colors.pageBg,
    primaryContainer = DarkClipDockTokens.colors.accentSoft,
    onPrimaryContainer = DarkClipDockTokens.colors.ink,
    secondary = DarkClipDockTokens.colors.accent2,
    onSecondary = DarkClipDockTokens.colors.pageBg,
    secondaryContainer = DarkClipDockTokens.colors.blueSoft,
    onSecondaryContainer = DarkClipDockTokens.colors.ink,
    tertiary = DarkClipDockTokens.colors.warn,
    onTertiary = DarkClipDockTokens.colors.pageBg,
    tertiaryContainer = DarkClipDockTokens.colors.warnSoft,
    onTertiaryContainer = DarkClipDockTokens.colors.ink,
    error = DarkClipDockTokens.colors.danger,
    errorContainer = DarkClipDockTokens.colors.dangerSoft,
    onErrorContainer = DarkClipDockTokens.colors.ink,
    background = DarkClipDockTokens.colors.pageBg,
    onBackground = DarkClipDockTokens.colors.ink,
    surface = DarkClipDockTokens.colors.surface,
    onSurface = DarkClipDockTokens.colors.ink,
    surfaceVariant = DarkClipDockTokens.colors.surface3,
    onSurfaceVariant = DarkClipDockTokens.colors.muted,
    outline = DarkClipDockTokens.colors.line,
    outlineVariant = DarkClipDockTokens.colors.softLine,
  )

private val LightColorScheme =
  lightColorScheme(
    primary = LightClipDockTokens.colors.accent,
    onPrimary = LightClipDockTokens.colors.surface,
    primaryContainer = LightClipDockTokens.colors.accentSoft,
    onPrimaryContainer = LightClipDockTokens.colors.ink,
    secondary = LightClipDockTokens.colors.accent2,
    onSecondary = LightClipDockTokens.colors.surface,
    secondaryContainer = LightClipDockTokens.colors.blueSoft,
    onSecondaryContainer = LightClipDockTokens.colors.ink,
    tertiary = LightClipDockTokens.colors.warn,
    onTertiary = LightClipDockTokens.colors.surface,
    tertiaryContainer = LightClipDockTokens.colors.warnSoft,
    onTertiaryContainer = LightClipDockTokens.colors.ink,
    error = LightClipDockTokens.colors.danger,
    errorContainer = LightClipDockTokens.colors.dangerSoft,
    onErrorContainer = LightClipDockTokens.colors.ink,
    background = LightClipDockTokens.colors.pageBg,
    onBackground = LightClipDockTokens.colors.ink,
    surface = LightClipDockTokens.colors.surface,
    onSurface = LightClipDockTokens.colors.ink,
    surfaceVariant = LightClipDockTokens.colors.surface3,
    onSurfaceVariant = LightClipDockTokens.colors.muted,
    outline = LightClipDockTokens.colors.line,
    outlineVariant = LightClipDockTokens.colors.softLine,
  )

@Composable
fun ClipDockTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  dynamicColor: Boolean = false,
  content: @Composable () -> Unit,
) {
  val tokens = if (darkTheme) DarkClipDockTokens else LightClipDockTokens
  val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

  CompositionLocalProvider(LocalClipDockTokens provides tokens) {
    MaterialTheme(colorScheme = colorScheme, typography = Typography, content = content)
  }
}
