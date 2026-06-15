package expo.modules.opuslib

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.io.File
import kotlin.concurrent.thread

/**
 * AudioRecordManager - Manages AudioRecord for real-time audio capture.
 *
 * This class is responsible only for audio capture: it owns the AudioRecord
 * lifecycle and runs the PCM read loop. All Opus 1.6.1 encoding is delegated to
 * AudioProcessor, which runs on a separate dedicated encoding thread. The
 * capture thread calls processor.pushSamples(), which copies the PCM and posts
 * it to the encoding thread, so the read loop never blocks on encoding.
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

  // Encoding processor (owns the encoder, runs on a separate HandlerThread)
  private var processor: AudioProcessor? = null

  // State
  private var isRecording = false
  private var isPaused = false
  private var loggedFirstBuffer = false

  // Event callbacks
  private var onAudioChunk: ((List<EncodedFrame>, Double, Int, Double, Int) -> Unit)? = null
  private var onStarted: ((timestamp: Double, sampleRate: Int, channels: Int, bitrate: Int, frameSize: Double, preSkip: Int) -> Unit)? = null
  private var onEnd: ((timestamp: Double, totalDuration: Double, totalPackets: Int) -> Unit)? = null
  private var onAmplitude: ((Float, Float, Double) -> Unit)? = null
  private var onError: ((Exception) -> Unit)? = null

  // MARK: - Public Methods

  fun start() {
    if (isRecording) {
      throw AudioStreamException("ALREADY_STREAMING", "Already recording")
    }

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

    // Create and start AudioProcessor (encoding thread). It owns the encoder and
    // emits audioStarted (with preSkip) once the encoder is ready.
    val proc = AudioProcessor(config)
    proc.setOnAudioChunk { frames, timestamp, seq, duration, frameCount ->
      onAudioChunk?.invoke(frames, timestamp, seq, duration, frameCount)
    }
    proc.setOnStarted { timestamp, sampleRate, channels, bitrate, frameSize, preSkip ->
      onStarted?.invoke(timestamp, sampleRate, channels, bitrate, frameSize, preSkip)
    }
    proc.setOnEnd { timestamp, totalDuration, totalPackets ->
      onEnd?.invoke(timestamp, totalDuration, totalPackets)
    }

    // Debug PCM file (written on the encoding thread, per frame)
    val debugFile = if (config.saveDebugAudio) {
      val timestamp = System.currentTimeMillis()
      File(context.filesDir, "debug_pcm_$timestamp.raw").also {
        Log.d(TAG, "Debug PCM file: ${it.absolutePath}")
      }
    } else null

    proc.start(debugFile)
    processor = proc

    // Start recording
    try {
      record.startRecording()
    } catch (e: Exception) {
      // Tear down the encoding thread we just started before bailing out
      proc.flushAndStop()
      processor = null
      throw AudioStreamException("AUDIO_RECORD_ERROR", "Failed to start recording: ${e.message}")
    }

    isRecording = true

    // Start capture thread — only reads PCM and pushes to the processor
    recordingThread = thread(start = true, name = "AudioRecordThread") {
      captureLoop(record, samplesPerFrame)
    }

    Log.d(TAG, "Started recording: ${config.sampleRate}Hz, ${config.channels}ch, DRED: ${config.dredDuration}ms")
  }

  fun stop() {
    if (!isRecording) {
      return
    }

    isRecording = false

    // Stop AudioRecord
    audioRecord?.let { record ->
      try {
        if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
          record.stop()
        }
      } catch (e: Exception) {
        Log.e(TAG, "Error stopping AudioRecord: ${e.message}")
      }
    }

    // Wait for capture thread to finish
    recordingThread?.join(1000)
    recordingThread = null

    // Flush and stop the encoding thread (synchronous — drains remaining
    // samples, pads the final partial frame with silence, emits audioEnd).
    processor?.flushAndStop()
    processor = null

    // Release AudioRecord
    audioRecord?.release()
    audioRecord = null

    loggedFirstBuffer = false

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

  fun setOnAudioChunk(callback: (List<EncodedFrame>, Double, Int, Double, Int) -> Unit) {
    this.onAudioChunk = callback
  }

  fun setOnStarted(callback: (timestamp: Double, sampleRate: Int, channels: Int, bitrate: Int, frameSize: Double, preSkip: Int) -> Unit) {
    this.onStarted = callback
  }

  fun setOnEnd(callback: (timestamp: Double, totalDuration: Double, totalPackets: Int) -> Unit) {
    this.onEnd = callback
  }

  fun setOnAmplitude(callback: (Float, Float, Double) -> Unit) {
    this.onAmplitude = callback
  }

  fun setOnError(callback: (Exception) -> Unit) {
    this.onError = callback
  }

  // MARK: - Capture thread (only reads PCM, no encoding)

  private fun captureLoop(record: AudioRecord, samplesPerFrame: Int) {
    val buffer = ShortArray(samplesPerFrame)

    Log.d(TAG, "Capture thread started, frame size: $samplesPerFrame samples")

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
          // No data available, wait briefly and retry
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

        // Copy + post to the encoding thread (never blocks the capture loop)
        processor?.pushSamples(buffer, samplesRead)

      } catch (e: InterruptedException) {
        Log.d(TAG, "Capture thread interrupted")
        break
      } catch (e: Exception) {
        Log.e(TAG, "Error in capture loop: ${e.message}", e)
        onError?.invoke(e)
        break
      }
    }

    Log.d(TAG, "Capture thread stopped")
  }
}
