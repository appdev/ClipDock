package com.apkdv.clipdock.p2p

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class P2pNativeBridgeInstrumentedTest {
  @Test
  fun startsNativeNodeAndReturnsEndpointId() {
    runBlocking {
      val context = ApplicationProvider.getApplicationContext<Context>()
      val transport = NativeP2pTransport(context)

      assertTrue(transport.isAvailable())
      val endpoint = transport.startNode()

      assertTrue(endpoint.endpointId.isNotBlank())
      transport.shutdown()
    }
  }
}
