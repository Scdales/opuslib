package expo.modules.opuslib

import android.util.Log

/**
 * OpusEncoder - Kotlin wrapper for Opus 1.6 with DRED support
 *
 * This class provides a Kotlin interface to the Opus 1.6 C library via JNI
 * for encoding PCM audio to Opus format with Deep Redundancy (DRED) support.
 *
 * DRED embeds up to 1 second of recovery data in packet padding for improved
 * audio quality on lossy networks.
 */
class OpusEncoder(
  private val sampleRate: Int,
  private val channels: Int,
  private val bitrate: Int,
  frameSizeMs: Double,
  dredDurationMs: Int = 100
) {
  companion object {
    private const val TAG = "OpusEncoder"

    init {
      try {
        System.loadLibrary("opuslib-jni")
        Log.i(TAG, "Loaded opuslib-jni native library")
      } catch (e: UnsatisfiedLinkError) {
        Log.e(TAG, "Failed to load opuslib-jni native library", e)
        throw e
      }
    }
  }

  val frameSize: Int = (sampleRate * frameSizeMs / 1000.0).toInt()
  private var encoderPtr: Long = 0

  init {
    // Create native encoder
    encoderPtr = nativeCreate(sampleRate, channels, bitrate, dredDurationMs)
    if (encoderPtr == 0L) {
      throw RuntimeException("Failed to create Opus encoder")
    }

    Log.i(TAG, """
      Opus encoder initialized:
        - Sample rate: ${sampleRate}Hz
        - Channels: $channels
        - Bitrate: ${bitrate / 1000}kbps
        - Frame size: $frameSize samples (${frameSizeMs}ms)
        - DRED: ${dredDurationMs}ms
    """.trimIndent())
  }

  /**
   * Encode PCM samples to Opus
   *
   * @param pcm PCM samples as ShortArray (Int16)
   * @param frameSize Number of samples per channel (must match configured frameSize)
   * @return Opus-encoded bytes, or null on failure
   */
  fun encode(pcm: ShortArray, frameSize: Int): ByteArray? {
    if (encoderPtr == 0L) {
      throw RuntimeException("Encoder not initialized")
    }

    if (frameSize != this.frameSize) {
      throw IllegalArgumentException(
        "Frame size mismatch: expected ${this.frameSize}, got $frameSize"
      )
    }

    return nativeEncode(encoderPtr, pcm, frameSize)
  }

  /**
   * Destroy encoder and free native resources
   */
  fun destroy() {
    if (encoderPtr != 0L) {
      nativeDestroy(encoderPtr)
      encoderPtr = 0
      Log.i(TAG, "Opus encoder destroyed")
    }
  }

  // Native methods (implemented in opus_jni_wrapper.cpp)

  private external fun nativeCreate(
    sampleRate: Int,
    channels: Int,
    bitrate: Int,
    dredDurationMs: Int
  ): Long

  private external fun nativeEncode(
    encoderPtr: Long,
    pcm: ShortArray,
    frameSize: Int
  ): ByteArray?

  private external fun nativeDestroy(encoderPtr: Long)
}
