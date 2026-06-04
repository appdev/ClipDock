package com.apkdv.clipdock.data

import java.util.Locale
import org.apache.commons.codec.digest.Blake3

internal fun canonicalBlake3Digest(bytes: ByteArray): String = "blake3:${blake3Hex(bytes)}"

internal fun blake3Hex(bytes: ByteArray): String =
  Blake3
    .hash(bytes)
    .joinToString("") { byte -> "%02x".format(Locale.US, byte.toInt() and 0xff) }

internal fun isCanonicalBlake3Digest(value: String): Boolean {
  val hex = value.removePrefix("blake3:")
  return value.startsWith("blake3:") &&
    hex.length == 64 &&
    hex.all { character -> character in '0'..'9' || character in 'a'..'f' }
}
