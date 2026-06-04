package com.apkdv.clipdock.data

import java.io.File
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.json.JSONObject
import org.junit.Test

class SyncContractFixtureTest {
  @Test
  fun kotlinSyncMirrorMatchesSharedFixture() {
    val fixture = sharedSyncContractFixture()
    val info = fixture["info"]!!.jsonObject

    assertEquals(262_144, info["thumbnail_normal_target_bytes"]!!.jsonPrimitive.content.toInt())
    assertEquals(SYNC_THUMBNAIL_NORMAL_TARGET_BYTES, info["thumbnail_normal_target_bytes"]!!.jsonPrimitive.content.toInt())
    assertEquals(SYNC_THUMBNAIL_DETAIL_TARGET_BYTES, info["thumbnail_detail_target_bytes"]!!.jsonPrimitive.content.toInt())
    assertEquals(SYNC_THUMBNAIL_MAX_BYTES, info["thumbnail_max_bytes"]!!.jsonPrimitive.content.toInt())

    val ids = fixture["ids"]!!.jsonObject
    for (value in ids["content_hash"]!!.jsonObject["valid_strict"]!!.jsonArray) {
      assertTrue(isCanonicalBlake3ContentHash(value.jsonPrimitive.content))
    }
    for (value in ids["content_hash"]!!.jsonObject["invalid_strict"]!!.jsonArray) {
      assertFalse(isCanonicalBlake3ContentHash(value.jsonPrimitive.content))
    }
    for (entry in ids["content_hash"]!!.jsonObject["client_normalize"]!!.jsonArray) {
      val input = entry.jsonObject["input"]!!.jsonPrimitive.content
      val expected = entry.jsonObject["expected"]!!.jsonPrimitive.content
      assertEquals(expected, normalizeClientContentHash(input))
    }

    for (value in fixture["ids"]!!.jsonObject["asset_digest"]!!.jsonObject["valid_strict"]!!.jsonArray) {
      assertTrue(isCanonicalBlake3Digest(value.jsonPrimitive.content))
    }
    for (value in fixture["ids"]!!.jsonObject["asset_digest"]!!.jsonObject["invalid_strict"]!!.jsonArray) {
      assertFalse(isCanonicalBlake3Digest(value.jsonPrimitive.content))
    }

    for (value in ids["p2p_asset_id"]!!.jsonObject["valid_strict"]!!.jsonArray) {
      assertTrue(isStrictP2pAssetId(value.jsonPrimitive.content))
    }
    for (value in ids["p2p_asset_id"]!!.jsonObject["invalid_strict"]!!.jsonArray) {
      assertFalse(isStrictP2pAssetId(value.jsonPrimitive.content))
    }
  }

  @Test
  fun kotlinPayloadShapeMirrorMatchesSharedFixture() {
    val events = sharedSyncContractFixture()["events"]!!.jsonObject

    val imagePayload = JSONObject(events["image_upsert_with_thumbnail"]!!.jsonObject["payload"].toString())
    assertTrue(imagePayload.hasValidThumbnailShapeForItemType("image"))

    val noThumbnailPayload = JSONObject(events["image_upsert_without_thumbnail"]!!.jsonObject["payload"].toString())
    assertTrue(noThumbnailPayload.hasValidThumbnailShapeForItemType("image"))

    val partialThumbnailPayload = JSONObject(events["invalid_partial_thumbnail"]!!.jsonObject["payload"].toString())
    assertFalse(partialThumbnailPayload.hasValidThumbnailShapeForItemType("image"))

    val nonImageThumbnailPayload = JSONObject(events["invalid_non_image_thumbnail"]!!.jsonObject["payload"].toString())
    assertFalse(nonImageThumbnailPayload.hasValidThumbnailShapeForItemType("text"))

    val nonWebpThumbnailPayload =
      JSONObject(imagePayload.toString()).put("thumbnail_mime_type", "image/png")
    assertTrue(nonWebpThumbnailPayload.hasValidThumbnailShapeForItemType("image"))

    val stringByteCountThumbnailPayload =
      JSONObject(imagePayload.toString()).put("thumbnail_byte_count", "24000")
    assertFalse(stringByteCountThumbnailPayload.hasValidThumbnailShapeForItemType("image"))

    val validPayloadUpdate = JSONObject(events["payload_asset_update"]!!.jsonObject["payload"].toString())
    assertTrue(validPayloadUpdate.payloadAssetUpdateAssetId().startsWith("blake3:"))

    val extraPayloadUpdate = JSONObject(events["invalid_payload_asset_update_extra"]!!.jsonObject["payload"].toString())
    assertPayloadAssetUpdateRejected("invalid_payload_asset_update_payload", extraPayloadUpdate)

    val mismatchPayloadUpdate = JSONObject(events["invalid_payload_asset_update_mismatch"]!!.jsonObject["payload"].toString())
    assertPayloadAssetUpdateRejected(
      events["invalid_payload_asset_update_mismatch"]!!.jsonObject["expected_error"]!!.jsonPrimitive.content,
      mismatchPayloadUpdate,
    )

    val invalidAssetIdPayload =
      JSONObject()
        .put("payload_asset_id", "blake3:abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopq0")
    assertPayloadAssetUpdateRejected("invalid_payload_asset_update_payload", invalidAssetIdPayload)

    assertPayloadAssetUpdateRejected("invalid_payload_asset_update_payload", JSONObject())
    assertPayloadAssetUpdateRejected(
      "invalid_payload_asset_update_payload",
      JSONObject().put("payload_asset_id", ""),
    )
    assertPayloadAssetUpdateRejected(
      "invalid_payload_asset_update_payload",
      JSONObject()
        .put("payload_asset_id", "blake3:${"a".repeat(64)}")
        .put("asset_id", JSONObject.NULL),
    )
    assertPayloadAssetUpdateRejected(
      "invalid_payload_asset_update_payload",
      JSONObject()
        .put("payload_asset_id", "blake3:${"a".repeat(64)}")
        .put("asset_id", " "),
    )
  }

  @Test
  fun basicSyncPushEventDoesNotRequireNativeP2pLoad() {
    val item =
      ClipHistoryItem(
        stableId = "local-text",
        contentHash = "",
        type = ClipItemType.Text,
        title = "hello",
        body = "hello",
        detail = "",
        sourceName = "Android",
        assetId = null,
        thumbnailUri = null,
        thumbnailDigest = null,
        thumbnailMimeType = null,
        thumbnailByteCount = null,
        thumbnailWidth = null,
        thumbnailHeight = null,
        localUri = null,
        payloadState = PayloadState.Ready,
        transferState = TransferState.Idle,
        copiedAtMillis = 1234,
        copyCount = 1,
      )

    val event = item.toSyncPushEventRequest("dev_android")

    assertEquals("item_upsert", event.type)
    assertEquals("text", event.itemType)
    assertTrue(event.contentHash.matches(Regex("^blake3:[0-9a-f]{64}$")))
    assertEquals("android", event.payload!!["source_platform"]!!.jsonPrimitive.content)
  }
}

private fun assertPayloadAssetUpdateRejected(expectedReason: String, payload: JSONObject) {
  try {
    payload.payloadAssetUpdateAssetId()
    error("Expected payload asset update rejection")
  } catch (recovery: SyncRecoveryRequired) {
    assertEquals(expectedReason, recovery.reason)
  }
}

private fun normalizeClientContentHash(value: String): String? {
  val trimmed = value.trim().lowercase()
  val rawHash = trimmed.removePrefix("blake3:")
  return if (isCanonicalBlake3ContentHash("blake3:$rawHash")) "blake3:$rawHash" else null
}

private fun sharedSyncContractFixture() =
  Json.parseToJsonElement(sharedSyncContractFixtureFile().readText()).jsonObject

private fun sharedSyncContractFixtureFile(): File {
  val userDir = System.getProperty("user.dir") ?: error("user.dir is not set")
  var directory: File? = File(userDir).absoluteFile
  while (directory != null) {
    val candidate = File(directory, "shared/fixtures/sync_contract/protocol_fixtures.json")
    if (candidate.isFile) return candidate
    directory = directory.parentFile
  }
  error("shared sync contract fixture not found")
}
