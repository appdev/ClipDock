package com.apkdv.clipdock

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

@Serializable data object Main : NavKey

@Serializable
enum class MainDestination(val label: String) {
  History("历史"),
  Devices("设备"),
  Files("文件"),
  Settings("设置")
}

@Serializable
enum class SettingsDetailDestination {
  KeepAlive,
  FloatingBall,
  Pairing,
  ServerAdvanced,
}

@Serializable
data class SettingsDetail(val destination: SettingsDetailDestination) : NavKey

@Serializable
data class ItemDetail(
  val stableId: String,
  val origin: MainDestination = MainDestination.History,
) : NavKey
