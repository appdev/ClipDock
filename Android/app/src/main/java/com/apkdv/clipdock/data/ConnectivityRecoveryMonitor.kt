package com.apkdv.clipdock.data

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest

class ConnectivityRecoveryMonitor(private val context: Context) {
  private val appContext = context.applicationContext
  private val connectivityManager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
  private var registered = false

  fun start() {
    if (registered) return
    registered = true
    val request =
      NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .build()
    connectivityManager.registerNetworkCallback(
      request,
      object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
          ClipDockSyncScheduler.enqueueRecovery(appContext)
        }
      },
    )
  }
}
