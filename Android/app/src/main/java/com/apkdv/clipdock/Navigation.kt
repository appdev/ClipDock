package com.apkdv.clipdock

import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.apkdv.clipdock.ui.main.MainScreen

@Composable
fun MainNavigation() {
  val backStack = rememberNavBackStack(Main)
  var selectedDestinationName by rememberSaveable { mutableStateOf(MainDestination.History.name) }
  val selectedDestination =
    MainDestination.entries.firstOrNull { it.name == selectedDestinationName } ?: MainDestination.History

  fun selectRoot(destination: MainDestination) {
    selectedDestinationName = destination.name
    if (backStack.lastOrNull() is SettingsDetail) {
      backStack.removeLastOrNull()
    }
  }

  NavDisplay(
    backStack = backStack,
    onBack = { backStack.removeLastOrNull() },
    entryProvider =
      entryProvider {
        entry<Main> {
          MainScreen(
            selectedDestination = selectedDestination,
            settingsDetail = null,
            onDestinationSelected = ::selectRoot,
            onOpenSettingsDetail = { detail ->
              selectedDestinationName = MainDestination.Settings.name
              if (backStack.lastOrNull() != SettingsDetail(detail)) {
                backStack.add(SettingsDetail(detail))
              }
            },
            onBackFromDetail = { backStack.removeLastOrNull() },
            modifier = Modifier.safeDrawingPadding(),
          )
        }
        entry<SettingsDetail> { key ->
          MainScreen(
            selectedDestination = MainDestination.Settings,
            settingsDetail = key.destination,
            onDestinationSelected = ::selectRoot,
            onOpenSettingsDetail = { detail ->
              if (key.destination != detail) {
                backStack.removeLastOrNull()
                backStack.add(SettingsDetail(detail))
              }
            },
            onBackFromDetail = { backStack.removeLastOrNull() },
            modifier = Modifier.safeDrawingPadding(),
          )
        }
      },
  )
}
