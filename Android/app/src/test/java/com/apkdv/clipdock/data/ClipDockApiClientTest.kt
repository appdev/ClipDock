package com.apkdv.clipdock.data

import java.util.concurrent.atomic.AtomicReference
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertNotNull
import junit.framework.TestCase.assertTrue
import junit.framework.TestCase.fail
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import okio.BufferedSource
import org.junit.Test

class ClipDockApiClientTest {
  @Test
  fun joinSync_usesOkHttpAndSerializesRequestBody() = runTest {
    val captured = AtomicReference<CapturedRequest>()
    val api =
      ClipDockApiClient(
        client =
          respondingClient(captured) {
            jsonResponse(
              code = 200,
              body = """{"protocol_version":2,"data":{"sync_id":"sync_test","device_id":"dev_test","token":"cds_test"}}""",
            )
          },
      )

    val data = api.joinSync("http://clipdock.test", "A1B2C", "Android Test")

    val request = captured.get()
    assertNotNull(request)
    assertEquals("POST", request.method)
    assertEquals("http://clipdock.test/v2/sync/join", request.url)
    assertEquals("""{"pairing_code":"A1B2C","device_name":"Android Test"}""", request.body)
    assertEquals("sync_test", data["sync_id"]?.jsonPrimitive?.content)
  }

  @Test
  fun createInvite_sendsBearerTokenWithEmptyPostBody() = runTest {
    val captured = AtomicReference<CapturedRequest>()
    val api =
      ClipDockApiClient(
        client =
          respondingClient(captured) {
            jsonResponse(
              code = 200,
              body = """{"protocol_version":2,"data":{"sync_id":"sync_test","pairing_code":"Z9Y8X","pairing_expires_at_ms":1}}""",
            )
          },
      )

    val data = api.createInvite("http://clipdock.test", "cds_secret")

    val request = captured.get()
    assertNotNull(request)
    assertEquals("POST", request.method)
    assertEquals("Bearer cds_secret", request.authorization)
    assertEquals("", request.body)
    assertEquals("Z9Y8X", data["pairing_code"]?.jsonPrimitive?.content)
  }

  @Test
  fun pushEvents_postsV2EventsWithBearerTokenAndEnvelopeParsing() = runTest {
    val captured = AtomicReference<CapturedRequest>()
    val api =
      ClipDockApiClient(
        client =
          respondingClient(captured) {
            jsonResponse(
              code = 200,
              body = """{"protocol_version":2,"data":{"events":[{"client_event_id":"android-upsert-1","server_seq":9,"duplicate":false}],"next_cursor":9}}""",
            )
          },
      )

    val data =
      api.pushEvents(
        "http://clipdock.test",
        "cds_secret",
        listOf(
          SyncPushEventRequest(
            clientEventId = "android-upsert-1",
            type = "item_upsert",
            contentHash = "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            itemType = "text",
            payload =
              buildJsonObject {
                put("text", JsonPrimitive("hello"))
                put("source_platform", JsonPrimitive("android"))
              },
            copyCountDelta = 1,
          ),
        ),
      )

    val request = captured.get()
    assertNotNull(request)
    assertEquals("POST", request.method)
    assertEquals("http://clipdock.test/v2/events", request.url)
    assertEquals("Bearer cds_secret", request.authorization)
    assertTrue(request.body.contains(""""content_hash":"blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""""))
    assertTrue(request.body.contains(""""source_platform":"android""""))
    assertEquals("9", data["next_cursor"]?.jsonPrimitive?.content)
  }

  @Test
  fun p2pDevices_sendsBearerTokenToDevicesEndpoint() = runTest {
    val captured = AtomicReference<CapturedRequest>()
    val api =
      ClipDockApiClient(
        client =
          respondingClient(captured) {
            jsonResponse(
              code = 200,
              body = """{"protocol_version":2,"data":{"devices":[{"device_id":"dev_mac","device_name":"Mac","endpoint":{"endpoint_id":"iroh-node","direct_addresses":[],"capabilities":{"blob_transfer":true},"updated_at_ms":10,"expires_at_ms":20}}]}}""",
            )
          },
      )

    val data = api.p2pDevices("http://clipdock.test", "cds_secret")

    val request = captured.get()
    assertNotNull(request)
    assertEquals("GET", request.method)
    assertEquals("http://clipdock.test/v2/p2p/devices", request.url)
    assertEquals("Bearer cds_secret", request.authorization)
    assertEquals("dev_mac", data["devices"].toString().substringAfter("\"device_id\":\"").substringBefore("\""))
  }

  @Test
  fun uploadAsset_putsThumbnailBytesWithRequiredMetadataHeaders() = runTest {
    val captured = AtomicReference<CapturedRequest>()
    val api =
      ClipDockApiClient(
        client =
          respondingClient(captured) {
            jsonResponse(
              code = 200,
              body =
                """{"protocol_version":2,"data":{"digest":"blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","kind":"thumbnail","mime_type":"image/webp","size_bytes":4,"width_px":2,"height_px":2,"already_exists":false}}""",
            )
          },
      )

    val uploaded =
      api.uploadAsset(
        "http://clipdock.test",
        "cds_secret",
        "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        kind = "thumbnail",
        mimeType = "image/webp",
        width = 2,
        height = 2,
        bytes = "webp".toByteArray(),
      )

    val request = captured.get()
    assertNotNull(request)
    assertEquals("PUT", request.method)
    assertEquals(
      "http://clipdock.test/v2/assets/blake3%3Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request.url,
    )
    assertEquals("Bearer cds_secret", request.authorization)
    assertEquals("image/webp", request.contentType)
    assertEquals("thumbnail", request.assetKind)
    assertEquals("2", request.assetWidth)
    assertEquals("2", request.assetHeight)
    assertEquals("webp", request.body)
    assertEquals("thumbnail", uploaded.kind)
    assertEquals(4L, uploaded.byteCount)
    assertEquals(2, uploaded.width)
    assertEquals(2, uploaded.height)
  }

  @Test
  fun uploadAsset_usesRequestDimensionsWhenLegacyResponseOmitsDimensions() = runTest {
    val api =
      ClipDockApiClient(
        client =
          respondingClient {
            jsonResponse(
              code = 200,
              body =
                """{"protocol_version":2,"data":{"digest":"blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","kind":"thumbnail","mime_type":"image/webp","size_bytes":4,"already_exists":true}}""",
            )
          },
      )

    val uploaded =
      api.uploadAsset(
        "http://clipdock.test",
        "cds_secret",
        "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        kind = "thumbnail",
        mimeType = "image/webp",
        width = 420,
        height = 336,
        bytes = "webp".toByteArray(),
      )

    assertEquals("thumbnail", uploaded.kind)
    assertEquals(4L, uploaded.byteCount)
    assertEquals(420, uploaded.width)
    assertEquals(336, uploaded.height)
    assertTrue(uploaded.alreadyExists)
  }

  @Test
  fun uploadAsset_rejectsInvalidResponseDimensions() = runTest {
    val api =
      ClipDockApiClient(
        client =
          respondingClient {
            jsonResponse(
              code = 200,
              body =
                """{"protocol_version":2,"data":{"digest":"blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","kind":"thumbnail","mime_type":"image/webp","size_bytes":4,"width_px":0,"height_px":2,"already_exists":false}}""",
            )
          },
      )

    try {
      api.uploadAsset(
        "http://clipdock.test",
        "cds_secret",
        "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        kind = "thumbnail",
        mimeType = "image/webp",
        width = 2,
        height = 2,
        bytes = "webp".toByteArray(),
      )
      fail("Expected ClipDockApiException")
    } catch (exception: ClipDockApiException) {
      assertEquals("invalid_asset_metadata", exception.code)
    }
  }

  @Test
  fun errorEnvelopeThrowsClipDockApiException() = runTest {
    val api =
      ClipDockApiClient(
        client =
          respondingClient {
            jsonResponse(
              code = 403,
              body = """{"protocol_version":2,"error":{"code":"invalid_pairing_code","message":"invalid_pairing_code"}}""",
            )
          },
      )

    try {
      api.joinSync("http://clipdock.test", "A1B2C", "Android Test")
      fail("Expected ClipDockApiException")
    } catch (exception: ClipDockApiException) {
      assertEquals("invalid_pairing_code", exception.code)
      assertEquals("invalid_pairing_code", exception.message)
    }
  }

  @Test
  fun responseBodyIsReadOnOkHttpDispatcherThread() = runTest {
    val callerThread = Thread.currentThread().name
    val bodyReadThread = AtomicReference<String>()
    val api =
      ClipDockApiClient(
        client =
          respondingClient {
            jsonResponse(
              code = 200,
              body = """{"protocol_version":2,"data":{"status":"ok"}}""",
              bodyReadThread = bodyReadThread,
            )
          },
      )

    api.health("http://clipdock.test")

    assertNotNull(bodyReadThread.get())
    assertTrue(
      "Response body was read on caller thread $callerThread",
      bodyReadThread.get() != callerThread,
    )
  }

  private fun respondingClient(
    captured: AtomicReference<CapturedRequest>? = null,
    responseFactory: () -> Response,
  ): OkHttpClient =
    OkHttpClient.Builder()
      .addInterceptor { chain ->
        val request = chain.request()
        captured?.set(request.capture())
        responseFactory()
          .newBuilder()
          .request(request)
          .build()
      }
      .build()

  private fun Request.capture(): CapturedRequest {
    val buffer = Buffer()
    body?.writeTo(buffer)
    return CapturedRequest(
      method = method,
      url = url.toString(),
      authorization = header("Authorization"),
      contentType = header("Content-Type"),
      assetKind = header("X-ClipDock-Asset-Kind"),
      assetWidth = header("X-ClipDock-Asset-Width"),
      assetHeight = header("X-ClipDock-Asset-Height"),
      body = buffer.readUtf8(),
    )
  }

  private fun jsonResponse(
    code: Int,
    body: String,
    bodyReadThread: AtomicReference<String>? = null,
  ): Response {
    val mediaType = "application/json".toMediaType()
    val responseBody =
      if (bodyReadThread == null) {
        body.toResponseBody(mediaType)
      } else {
        CapturingResponseBody(mediaType, body, bodyReadThread)
      }
    return Response.Builder()
      .request(Request.Builder().url("http://clipdock.test").build())
      .protocol(Protocol.HTTP_1_1)
      .code(code)
      .message(if (code in 200..299) "OK" else "Error")
      .body(responseBody)
      .build()
  }

  private class CapturingResponseBody(
    private val mediaType: MediaType,
    private val body: String,
    private val bodyReadThread: AtomicReference<String>,
  ) : ResponseBody() {
    override fun contentLength(): Long = body.toByteArray(Charsets.UTF_8).size.toLong()

    override fun contentType(): MediaType = mediaType

    override fun source(): BufferedSource {
      bodyReadThread.set(Thread.currentThread().name)
      return Buffer().writeUtf8(body)
    }
  }

  private data class CapturedRequest(
    val method: String,
    val url: String,
    val authorization: String?,
    val contentType: String?,
    val assetKind: String?,
    val assetWidth: String?,
    val assetHeight: String?,
    val body: String,
  )
}
