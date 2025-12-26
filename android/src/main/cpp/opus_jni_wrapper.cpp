#include <jni.h>
#include <android/log.h>
#include <opus.h>
#include <cstring>

#define LOG_TAG "OpusJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

/**
 * Create Opus encoder with DRED support
 *
 * @param env JNI environment
 * @param thiz Java object instance
 * @param sample_rate Sample rate in Hz (8000, 12000, 16000, 24000, 48000)
 * @param channels Number of channels (1=mono, 2=stereo)
 * @param bitrate Target bitrate in bits/second
 * @param dred_duration_ms DRED recovery duration in milliseconds (0-100)
 * @return Encoder pointer as jlong, or 0 on failure
 */
JNIEXPORT jlong JNICALL
Java_expo_modules_opuslib_OpusEncoder_nativeCreate(
    JNIEnv *env,
    jobject thiz,
    jint sample_rate,
    jint channels,
    jint bitrate,
    jint dred_duration_ms
) {
  int error = 0;

  // Create Opus encoder
  OpusEncoder *encoder = opus_encoder_create(
    sample_rate,
    channels,
    OPUS_APPLICATION_VOIP,
    &error
  );

  if (error != OPUS_OK || !encoder) {
    LOGE("Failed to create Opus encoder: error %d", error);
    return 0;
  }

  LOGI("Opus encoder created: %dHz, %dch, %dkbps", sample_rate, channels, bitrate / 1000);

  // Set bitrate
  int result = opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
  if (result != OPUS_OK) {
    LOGE("Failed to set bitrate: error %d", result);
  } else {
    LOGI("Bitrate set to %d bps", bitrate);
  }

  // Enable DRED if duration > 0
  if (dred_duration_ms > 0) {
    result = opus_encoder_ctl(encoder, OPUS_SET_DRED_DURATION(dred_duration_ms));
    if (result != OPUS_OK) {
      LOGE("DRED not available or failed to configure: error %d", result);
      LOGE("This may indicate Opus was not compiled with DRED support");
    } else {
      LOGI("DRED enabled: %dms recovery duration", dred_duration_ms);
    }
  }

  // Return encoder pointer as long
  return reinterpret_cast<jlong>(encoder);
}

/**
 * Encode PCM data to Opus
 *
 * @param env JNI environment
 * @param thiz Java object instance
 * @param encoder_ptr Encoder pointer from nativeCreate
 * @param pcm_data PCM samples as short array (Int16)
 * @param frame_size Number of samples per channel
 * @return Opus-encoded bytes, or null on failure
 */
JNIEXPORT jbyteArray JNICALL
Java_expo_modules_opuslib_OpusEncoder_nativeEncode(
    JNIEnv *env,
    jobject thiz,
    jlong encoder_ptr,
    jshortArray pcm_data,
    jint frame_size
) {
  OpusEncoder *encoder = reinterpret_cast<OpusEncoder*>(encoder_ptr);
  if (!encoder) {
    LOGE("Encoder pointer is null");
    return nullptr;
  }

  // Get PCM data from Java short array
  jshort *pcm = env->GetShortArrayElements(pcm_data, nullptr);
  if (!pcm) {
    LOGE("Failed to get PCM data");
    return nullptr;
  }

  // Allocate output buffer (4000 bytes max for Opus packets)
  unsigned char output[4000];

  // Encode PCM to Opus
  int encoded_bytes = opus_encode(
    encoder,
    pcm,
    frame_size,
    output,
    sizeof(output)
  );

  // Release PCM data (JNI_ABORT means don't copy back changes)
  env->ReleaseShortArrayElements(pcm_data, pcm, JNI_ABORT);

  // Check encoding result
  if (encoded_bytes < 0) {
    LOGE("Encoding failed: error %d", encoded_bytes);
    return nullptr;
  }

  if (encoded_bytes == 0) {
    LOGE("Encoded 0 bytes (DTX or silence)");
    return nullptr;
  }

  // Create Java byte array with encoded data
  jbyteArray result = env->NewByteArray(encoded_bytes);
  if (!result) {
    LOGE("Failed to allocate byte array");
    return nullptr;
  }

  // Copy encoded data to Java byte array
  env->SetByteArrayRegion(
    result,
    0,
    encoded_bytes,
    reinterpret_cast<jbyte*>(output)
  );

  return result;
}

/**
 * Destroy Opus encoder and free resources
 *
 * @param env JNI environment
 * @param thiz Java object instance
 * @param encoder_ptr Encoder pointer from nativeCreate
 */
JNIEXPORT void JNICALL
Java_expo_modules_opuslib_OpusEncoder_nativeDestroy(
    JNIEnv *env,
    jobject thiz,
    jlong encoder_ptr
) {
  OpusEncoder *encoder = reinterpret_cast<OpusEncoder*>(encoder_ptr);
  if (encoder) {
    opus_encoder_destroy(encoder);
    LOGI("Opus encoder destroyed");
  }
}

} // extern "C"
