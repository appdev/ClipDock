package com.apkdv.clipdock.data

import junit.framework.TestCase.assertEquals
import org.junit.Test

class RealtimeReconnectBackoffTest {
  @Test
  fun growsExponentiallyAndCapsAtFiveMinutes() {
    val backoff = RealtimeReconnectBackoff()

    val delays = (0 until 10).map { backoff.nextDelayMillis() }

    assertEquals(
      listOf(
        5_000L,
        10_000L,
        20_000L,
        40_000L,
        80_000L,
        160_000L,
        300_000L,
        300_000L,
        300_000L,
        300_000L,
      ),
      delays,
    )
  }

  @Test
  fun resetStartsFromInitialDelayAgain() {
    val backoff = RealtimeReconnectBackoff()

    backoff.nextDelayMillis()
    backoff.nextDelayMillis()
    backoff.reset()

    assertEquals(5_000L, backoff.nextDelayMillis())
  }
}
