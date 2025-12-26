package expo.modules.opuslib

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

/**
 * AudioRecordManager - Manages AudioRecord for real-time audio capture with Opus 1.6 DRED
 *
 * This class handles:
 * - AudioRecord setup and lifecycle
 * - Real-time PCM audio capture
 * - Opus 1.6 encoding with DRED support
 * - Background recording thread management
 */
class AudioRecordManager(
  private val context: Context,
  private val config: AudioConfig
) {
  companion object {
    private const val TAG = "AudioRecordManager"
  }

  // Audio recording
  private var audioRecord: AudioRecord? = null
  private var recordingThread: Thread? = null

  // Opus encoder
  private var opusEncoder: OpusEncoder? = null

  // State
  private var isRecording = false
  private var isPaused = false
  private var sequenceNumber = 0
  private var loggedFirstBuffer = false

  // Frame accumulation for packet duration
  private val frameBuffer = mutableListOf<ShortArray>()
  private val framesPerPacket: Int = (config.packetDuration / config.frameSize).toInt()

  // Event callbacks
  private var onAudioChunk: ((ByteArray, Double, Int) -> Unit)? = null
  private var onAmplitude: ((Float, Float, Double) -> Unit)? = null
  private var onError: ((Exception) -> Unit)? = null

  // Debug file output
  private var pcmFileOutputStream: FileOutputStream? = null
  private var pcmFile: File? = null

  // MARK: - Public Methods

  fun start() {
    if (isRecording) {
      throw AudioStreamException("ALREADY_STREAMING", "Already recording")
    }

    // Create Opus encoder with DRED support
    val dredDuration = config.dredDuration
    opusEncoder = OpusEncoder(
      sampleRate = config.sampleRate,
      channels = config.channels,
      bitrate = config.bitrate,
      frameSizeMs = config.frameSize,
      dredDurationMs = dredDuration
    )

    // Calculate buffer size
    val samplesPerFrame = (config.sampleRate * config.frameSize / 1000.0).toInt()
    val bufferSize = samplesPerFrame * 2 // 2 bytes per sample (Int16)

    // Ensure buffer size meets minimum requirements
    val minBufferSize = AudioRecord.getMinBufferSize(
      config.sampleRate,
      AudioFormat.CHANNEL_IN_MONO,
      AudioFormat.ENCODING_PCM_16BIT
    )

    if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
      throw AudioStreamException(
        "INVALID_AUDIO_CONFIG",
        "Invalid audio configuration: sample rate ${config.sampleRate}Hz"
      )
    }

    val actualBufferSize = maxOf(bufferSize, minBufferSize)

    Log.d(TAG, "Buffer size: requested=$bufferSize, min=$minBufferSize, actual=$actualBufferSize")

    // Create AudioRecord
    try {
      audioRecord = AudioRecord(
        MediaRecorder.AudioSource.MIC,
        config.sampleRate,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT,
        actualBufferSize
      )
    } catch (e: Exception) {
      throw AudioStreamException("AUDIO_RECORD_ERROR", "Failed to create AudioRecord: ${e.message}")
    }

    val record = audioRecord ?: throw AudioStreamException(
      "AUDIO_RECORD_ERROR",
      "AudioRecord is null after creation"
    )

    if (record.state != AudioRecord.STATE_INITIALIZED) {
      throw AudioStreamException(
        "AUDIO_RECORD_ERROR",
        "AudioRecord not initialized properly"
      )
    }

    // Create debug output file if enabled
    if (config.saveDebugAudio) {
      try {
        val timestamp = System.currentTimeMillis()
        pcmFile = File(context.filesDir, "debug_pcm_$timestamp.raw")
        pcmFileOutputStream = FileOutputStream(pcmFile)
        Log.d(TAG, "Debug PCM file created: ${pcmFile?.absolutePath}")
      } catch (e: Exception) {
        Log.e(TAG, "Failed to create debug file: ${e.message}")
      }
    }

    // Start recording
    try {
      record.startRecording()
    } catch (e: Exception) {
      throw AudioStreamException("AUDIO_RECORD_ERROR", "Failed to start recording: ${e.message}")
    }

    isRecording = true

    // Start recording thread
    recordingThread = thread(start = true, name = "AudioRecordThread") {
      recordAudioLoop(record, samplesPerFrame)
    }

    Log.d(TAG, "Started recording: ${config.sampleRate}Hz, ${config.channels}ch, DRED: ${dredDuration}ms")
  }

  fun stop() {
    if (!isRecording) {
      return
    }

    isRecording = false

    // Stop recording
    audioRecord?.let { record ->
      try {
        if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
          record.stop()
        }
      } catch (e: Exception) {
        Log.e(TAG, "Error stopping AudioRecord: ${e.message}")
      }
    }

    // Wait for recording thread to finish
    recordingThread?.join(1000)
    recordingThread = null

    // Release resources
    audioRecord?.release()
    audioRecord = null

    opusEncoder?.destroy()
    opusEncoder = null

    frameBuffer.clear()
    sequenceNumber = 0

    // Close debug file
    pcmFileOutputStream?.close()
    pcmFileOutputStream = null
    if (pcmFile != null) {
      Log.d(TAG, "Closed PCM debug file: ${pcmFile?.absolutePath}")
    }

    Log.d(TAG, "Stopped recording")
  }

  fun pause() {
    isPaused = true
    Log.d(TAG, "Paused")
  }

  fun resume() {
    isPaused = false
    Log.d(TAG, "Resumed")
  }

  // MARK: - Event Handlers

  fun setOnAudioChunk(callback: (ByteArray, Double, Int) -> Unit) {
    this.onAudioChunk = callback
  }

  fun setOnAmplitude(callback: (Float, Float, Double) -> Unit) {
    this.onAmplitude = callback
  }

  fun setOnError(callback: (Exception) -> Unit) {
    this.onError = callback
  }

  // MARK: - Private Methods

  private fun recordAudioLoop(record: AudioRecord, samplesPerFrame: Int) {
    val buffer = ShortArray(samplesPerFrame)

    Log.d(TAG, "Recording thread started, frame size: $samplesPerFrame samples")

    while (isRecording) {
      try {
        // Read audio data
        val samplesRead = record.read(buffer, 0, buffer.size)

        if (samplesRead < 0) {
          Log.e(TAG, "AudioRecord read error: $samplesRead")
          onError?.invoke(Exception("AudioRecord read error: $samplesRead"))
          break
        }

        if (samplesRead == 0) {
          // No data available, continue
          Thread.sleep(10)
          continue
        }

        // DEBUG: Log first buffer
        if (!loggedFirstBuffer) {
          Log.d(TAG, "First buffer: $samplesRead samples")
          loggedFirstBuffer = true
        }

        // Skip if paused
        if (isPaused) {
          continue
        }

        // Write to debug file if enabled
        pcmFileOutputStream?.let { fos ->
          val byteBuffer = ByteBuffer.allocate(samplesRead * 2)
          byteBuffer.order(ByteOrder.LITTLE_ENDIAN)
          for (i in 0 until samplesRead) {
            byteBuffer.putShort(buffer[i])
          }
          fos.write(byteBuffer.array())
        }

        // Process the buffer
        processBuffer(buffer.copyOf(samplesRead))

      } catch (e: InterruptedException) {
        Log.d(TAG, "Recording thread interrupted")
        break
      } catch (e: Exception) {
        Log.e(TAG, "Error in recording loop: ${e.message}", e)
        onError?.invoke(e)
        break
      }
    }

    Log.d(TAG, "Recording thread stopped")
  }

  private fun processBuffer(pcmData: ShortArray) {
    // Add to frame buffer
    frameBuffer.add(pcmData)

    // Calculate how many samples we need for one packet
    val samplesPerPacket = (config.sampleRate * config.packetDuration / 1000.0).toInt()
    val currentSampleCount = frameBuffer.sumOf { it.size }

    // When we have enough samples for a packet, encode and send
    if (currentSampleCount >= samplesPerPacket) {
      encodeAndSendPacket()
    }
  }

  private fun encodeAndSendPacket() {
    val encoder = opusEncoder ?: return

    // Flatten frame buffer into continuous PCM data
    val pcmData = ShortArray(frameBuffer.sumOf { it.size })
    var offset = 0
    for (frame in frameBuffer) {
      frame.copyInto(pcmData, offset)
      offset += frame.size
    }

    // Calculate samples per frame
    val samplesPerFrame = (config.sampleRate * config.frameSize / 1000.0).toInt()

    // We should only encode when we have at least one frame
    if (pcmData.size < samplesPerFrame) {
      return
    }

    // Take only ONE frame worth of samples
    val frameData = pcmData.copyOfRange(0, samplesPerFrame)

    // Encode this single frame to Opus (with DRED padding if enabled)
    val opusData = try {
      encoder.encode(frameData, samplesPerFrame)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to encode Opus packet: ${e.message}")
      frameBuffer.clear()
      return
    }

    if (opusData == null || opusData.isEmpty()) {
      Log.w(TAG, "Failed to encode Opus packet (null or empty)")
      frameBuffer.clear()
      return
    }

    // Calculate timestamp in milliseconds
    val timestampMs = System.currentTimeMillis().toDouble()

    // Emit audioChunk event with Opus packet (may be larger due to DRED)
    onAudioChunk?.invoke(opusData, timestampMs, sequenceNumber)

    sequenceNumber++

    // Keep any remaining samples for next packet
    val remainingSamples = pcmData.size - samplesPerFrame
    if (remainingSamples > 0) {
      val remaining = pcmData.copyOfRange(samplesPerFrame, pcmData.size)
      frameBuffer.clear()
      frameBuffer.add(remaining)
    } else {
      frameBuffer.clear()
    }
  }
}
