package expo.modules.opuslib

import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch

/**
 * A single encoded Opus frame with optional per-frame audio level.
 */
data class EncodedFrame(
  val data: ByteArray,
  val audioLevel: Float?  // null when enableAudioLevel is false
)

/**
 * AudioProcessor - Dedicated encoding thread for Opus 1.6.1 encoding and dispatch.
 *
 * The capture thread (AudioRecordManager) only reads PCM; this class owns the
 * encoder and runs all encoding work on a single dedicated thread:
 * - Owns a HandlerThread + Handler (a serial work queue)
 * - The capture thread calls pushSamples() which copies the data and posts it
 *   to this thread, so the capture loop never blocks on encoding
 * - All mutable state (pendingSamples, encoder, sequenceNumber, packet buffer)
 *   is only touched on the HandlerThread — no locks needed
 * - audioStarted/audioEnd events are emitted from this thread too, so preSkip
 *   and sequenceNumber are read without any cross-thread risk
 */
class AudioProcessor(private val config: AudioConfig) {
  companion object {
    private const val TAG = "AudioProcessor"
  }

  // Encoding thread + its serial work queue
  private var handlerThread: HandlerThread? = null
  private var handler: Handler? = null

  // All fields below are only accessed on handlerThread — no locks needed
  private var opusEncoder: OpusEncoder? = null
  private val pendingSamples = mutableListOf<Short>()
  private val samplesPerFrame: Int = (config.sampleRate * config.frameSize / 1000.0).toInt()
  private val framesPerPacket: Int = Math.max(1, config.framesPerCallback)
  private var packetFrames = mutableListOf<EncodedFrame>()  // independent Opus packets with per-frame level
  private var sequenceNumber: Int = 0
  private var startTime: Double = 0.0

  // Whether to compute per-frame audio level
  private val enableAudioLevel: Boolean = config.enableAudioLevel

  // Debug file output
  private var pcmFileOutputStream: FileOutputStream? = null

  // Event callbacks (all invoked on encoding thread)
  // onAudioChunk: (frames, timestamp, sequenceNumber, duration, frameCount)
  private var onAudioChunk: ((List<EncodedFrame>, Double, Int, Double, Int) -> Unit)? = null
  private var onStarted: ((timestamp: Double, sampleRate: Int, channels: Int, bitrate: Int, frameSize: Double, preSkip: Int) -> Unit)? = null
  private var onEnd: ((timestamp: Double, totalDuration: Double, totalPackets: Int) -> Unit)? = null

  /**
   * Start the encoding thread, create the Opus encoder, emit audioStarted.
   * Encoder init + preSkip read happen on the same thread — no cross-thread risk.
   */
  fun start(debugFile: File? = null) {
    val thread = HandlerThread("OpusEncodingThread").apply { start() }
    handlerThread = thread
    handler = Handler(thread.looper)

    val ready = CountDownLatch(1)
    handler!!.post {
      // Init encoder on encoding thread
      _initEncoder()

      // Debug file
      if (debugFile != null) {
        try {
          pcmFileOutputStream = FileOutputStream(debugFile)
          Log.d(TAG, "Debug PCM file: ${debugFile.absolutePath}")
        } catch (e: Exception) {
          Log.e(TAG, "Failed to create debug file: ${e.message}")
        }
      }

      // Emit audioStarted on encoding thread — preSkip read is safe here
      startTime = System.currentTimeMillis().toDouble()
      val preSkip = opusEncoder?.preSkip ?: 0
      onStarted?.invoke(
        startTime,
        config.sampleRate,
        config.channels,
        config.bitrate,
        config.frameSize,
        preSkip
      )

      ready.countDown()
    }
    ready.await()

    Log.d(TAG, "Started: ${config.sampleRate}Hz, ${config.channels}ch, frame=$samplesPerFrame samples")
  }

  /**
   * Push raw PCM samples from the capture thread (copy + post, no shared state).
   */
  fun pushSamples(samples: ShortArray, count: Int) {
    val buf = samples.copyOf(count)
    handler?.post {
      for (s in buf) {
        pendingSamples.add(s)
      }
      _processFrames()
    }
  }

  /**
   * Synchronously flush remaining audio, emit audioEnd, destroy encoder, stop thread.
   * All sequenceNumber/encoder access happens on the encoding thread — no cross-thread risk.
   */
  fun flushAndStop() {
    val h = handler ?: return
    val done = CountDownLatch(1)
    h.post {
      _flushRemainingFrames()

      // Emit audioEnd on encoding thread — sequenceNumber read is safe here
      val stopTime = System.currentTimeMillis().toDouble()
      val totalDuration = stopTime - startTime
      onEnd?.invoke(stopTime, totalDuration, sequenceNumber)

      // Destroy encoder on the same thread that used it
      opusEncoder?.destroy()
      opusEncoder = null
      pendingSamples.clear()
      pcmFileOutputStream?.close()
      pcmFileOutputStream = null
      done.countDown()
    }
    done.await()

    handlerThread?.quitSafely()
    handlerThread = null
    handler = null

    Log.d(TAG, "Flushed and stopped")
  }

  // MARK: - Event callback setters

  fun setOnAudioChunk(callback: (List<EncodedFrame>, Double, Int, Double, Int) -> Unit) {
    this.onAudioChunk = callback
  }

  fun setOnStarted(callback: (timestamp: Double, sampleRate: Int, channels: Int, bitrate: Int, frameSize: Double, preSkip: Int) -> Unit) {
    this.onStarted = callback
  }

  fun setOnEnd(callback: (timestamp: Double, totalDuration: Double, totalPackets: Int) -> Unit) {
    this.onEnd = callback
  }

  // MARK: - Encoding thread internals (all below only called on HandlerThread)

  private fun _initEncoder() {
    opusEncoder = OpusEncoder(
      sampleRate = config.sampleRate,
      channels = config.channels,
      bitrate = config.bitrate,
      frameSizeMs = config.frameSize,
      dredDurationMs = config.dredDuration
    )
    Log.d(TAG, "Opus encoder created, preSkip=${opusEncoder?.preSkip}")
  }

  private fun _processFrames() {
    val encoder = opusEncoder ?: return

    while (pendingSamples.size >= samplesPerFrame) {
      val frameData = ShortArray(samplesPerFrame)
      for (i in 0 until samplesPerFrame) {
        frameData[i] = pendingSamples.removeAt(0)
      }

      // Debug PCM file
      pcmFileOutputStream?.let { fos ->
        val bytes = ByteArray(frameData.size * 2)
        java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(frameData)
        fos.write(bytes)
      }

      // Encode single frame to Opus
      val opusData = try {
        encoder.encode(frameData, samplesPerFrame)
      } catch (e: Exception) {
        Log.e(TAG, "Opus encode error: ${e.message}")
        continue
      }

      if (opusData == null || opusData.isEmpty()) {
        Log.w(TAG, "Opus encode returned null/empty")
        continue
      }

      // Per-frame audio level (RMS → dBFS → 0~1)
      var frameLevel: Float? = null
      if (enableAudioLevel) {
        var sumSquares = 0.0
        for (sample in frameData) {
          val s = sample.toDouble() / 32768.0
          sumSquares += s * s
        }
        val rms = Math.sqrt(sumSquares / frameData.size)
        val dB = 20.0 * Math.log10(Math.max(rms, 1e-10))
        val dbFloor = -35.0
        val dbCeiling = -6.0
        frameLevel = Math.max(0.0, Math.min(1.0, (dB - dbFloor) / (dbCeiling - dbFloor))).toFloat()
      }

      // Accumulate encoded frame as an independent packet (no byte concatenation)
      packetFrames.add(EncodedFrame(data = opusData, audioLevel = frameLevel))

      // Emit when we have enough frames (framesPerCallback)
      if (packetFrames.size >= framesPerPacket) {
        val timestampMs = System.currentTimeMillis().toDouble()
        val frameCount = packetFrames.size
        val duration = frameCount * config.frameSize
        onAudioChunk?.invoke(packetFrames.toList(), timestampMs, sequenceNumber, duration, frameCount)
        sequenceNumber++
        packetFrames.clear()
      }
    }
  }

  private fun _flushRemainingFrames() {
    val encoder = opusEncoder ?: return

    // Pad remaining PCM with silence to fill the last frame
    if (pendingSamples.isNotEmpty() && pendingSamples.size < samplesPerFrame) {
      while (pendingSamples.size < samplesPerFrame) {
        pendingSamples.add(0)
      }
    }

    // Encode remaining frames
    while (pendingSamples.size >= samplesPerFrame) {
      val frameData = ShortArray(samplesPerFrame)
      for (i in 0 until samplesPerFrame) {
        frameData[i] = pendingSamples.removeAt(0)
      }

      val opusData = try {
        encoder.encode(frameData, samplesPerFrame)
      } catch (e: Exception) {
        continue
      }

      if (opusData == null || opusData.isEmpty()) continue
      // Flush frames get level 0 (silence-padded)
      packetFrames.add(EncodedFrame(data = opusData, audioLevel = if (enableAudioLevel) 0.0f else null))
    }

    // Flush any remaining frames (even if fewer than framesPerPacket)
    if (packetFrames.isNotEmpty()) {
      val timestampMs = System.currentTimeMillis().toDouble()
      val frameCount = packetFrames.size
      val duration = frameCount * config.frameSize
      onAudioChunk?.invoke(packetFrames.toList(), timestampMs, sequenceNumber, duration, frameCount)
      sequenceNumber++
      packetFrames.clear()
    }
  }
}
