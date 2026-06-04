package com.apkdv.clipdock.data

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters

object ClipDockSyncScheduler {
  private const val UNIQUE_RECOVERY_WORK = "clipdock-sync-recovery"

  fun enqueueRecovery(context: Context) {
    val request =
      OneTimeWorkRequestBuilder<SyncRecoveryWorker>()
        .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
        .build()
    WorkManager.getInstance(context.applicationContext)
      .enqueueUniqueWork(UNIQUE_RECOVERY_WORK, ExistingWorkPolicy.REPLACE, request)
  }
}

class SyncRecoveryWorker(
  appContext: Context,
  workerParameters: WorkerParameters,
) : CoroutineWorker(appContext, workerParameters) {
  override suspend fun doWork(): Result {
    return try {
      ClipDockRepository(applicationContext).syncNow()
      Result.success()
    } catch (exception: ClipDockApiException) {
      if (exception.code == "unauthorized") Result.success() else Result.retry()
    } catch (_: Throwable) {
      Result.retry()
    }
  }
}
