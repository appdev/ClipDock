package com.apkdv.clipdock.ui.main

import com.apkdv.clipdock.data.ClipDockUiState
import com.apkdv.clipdock.data.ClipHistoryItem

internal fun resolveMobileV4Item(
  state: ClipDockUiState,
  stableId: String,
): ClipHistoryItem? =
  state.items.firstOrNull { it.stableId == stableId }
