import Foundation

/**
 * AudioProcessor - Dedicated encoding thread for Opus encoding and dispatch.
 *
 * The real-time audio tap must never block, and the Opus encoder is not safe to
 * touch from multiple threads. This class isolates all encoder work onto a
 * single serial queue:
 * - The capture thread calls `pushSamples()`, which copies the PCM and posts it
 *   to the encoding queue.
 * - All mutable state (pendingSamples, encoder, sequenceNumber, level) is only
 *   accessed on the encoding queue, so no locks are needed.
 * - `audioStarted` / `audioEnd` events are emitted from the encoding queue, so
 *   `preSkip` / `sequenceNumber` are read without cross-thread risk.
 */

/// A single encoded Opus frame with optional per-frame audio level
struct EncodedFrame {
  let data: Data
  let audioLevel: Float?  // nil when enableAudioLevel is false
}

class AudioProcessor {
  // Dedicated serial queue — all encoder access happens here
  private let queue = DispatchQueue(label: "com.opuslib.encoding", qos: .userInitiated)

  // All fields below are only accessed on `queue` — no locks needed
  private var opusEncoder: OpusEncoder?
  private var pendingSamples: [Int16] = []
  private let samplesPerFrame: Int
  private let framesPerPacket: Int  // how many frames to batch before emitting
  private var packetFrames: [EncodedFrame] = []  // independent Opus packets with per-frame level
  private var sequenceNumber: Int = 0
  private var startTime: Double = 0

  // Whether to compute per-frame audio level
  private let enableAudioLevel: Bool

  // Debug file
  private var pcmFileHandle: FileHandle?

  // Event callbacks (all invoked on the encoding queue)
  // onAudioChunk: (frames, timestamp, sequenceNumber, duration, frameCount)
  private var onAudioChunk: (([EncodedFrame], Double, Int, Double, Int) -> Void)?
  private var onStarted: ((_ timestamp: Double, _ sampleRate: Int, _ channels: Int, _ bitrate: Int, _ frameSize: Double, _ preSkip: Int) -> Void)?
  private var onEnd: ((_ timestamp: Double, _ totalDuration: Double, _ totalPackets: Int) -> Void)?

  // Configuration (immutable)
  private let config: AudioConfig

  init(config: AudioConfig) {
    self.config = config
    self.samplesPerFrame = Int(Double(config.sampleRate) * config.frameSize / 1000.0)
    let framesPerCallback = config.framesPerCallback ?? 1
    self.framesPerPacket = max(1, framesPerCallback)
    self.enableAudioLevel = config.enableAudioLevel ?? false
  }

  // MARK: - Public API

  /**
   * Start: create the Opus encoder on the encoding queue and emit audioStarted.
   * All encoder init + preSkip read happen on the same thread — no cross-thread risk.
   */
  func start(debugFileURL: URL? = nil) throws {
    var initError: Error?
    queue.sync {
      do {
        self.opusEncoder = try OpusEncoder(
          sampleRate: self.config.sampleRate,
          channels: self.config.channels,
          bitrate: self.config.bitrate,
          frameSizeMs: self.config.frameSize,
          dredDurationMs: self.config.dredDuration ?? 100
        )
      } catch {
        initError = error
        return
      }

      // Debug file
      if let url = debugFileURL {
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        self.pcmFileHandle = try? FileHandle(forWritingTo: url)
      }

      // Emit audioStarted on the encoding queue — preSkip read is safe here
      self.startTime = Date().timeIntervalSince1970 * 1000
      let preSkip = self.opusEncoder?.preSkip ?? 0
      self.onStarted?(
        self.startTime,
        self.config.sampleRate,
        self.config.channels,
        self.config.bitrate,
        self.config.frameSize,
        preSkip
      )
    }

    if let error = initError { throw error }

    print("[AudioProcessor] Started: \(config.sampleRate)Hz, frame=\(samplesPerFrame) samples")
  }

  /**
   * Push raw PCM samples from the capture thread (copy + post, no shared state).
   */
  func pushSamples(_ samples: [Int16]) {
    queue.async { [weak self] in
      guard let self = self else { return }
      self.pendingSamples.append(contentsOf: samples)
      self._processFrames()
    }
  }

  /**
   * Synchronously flush remaining audio, emit audioEnd, and destroy the encoder.
   * All sequenceNumber/encoder access on the encoding queue — no cross-thread risk.
   */
  func flushAndStop() {
    queue.sync {
      self._flushRemainingFrames()

      // Emit audioEnd on the encoding queue — sequenceNumber read is safe here
      let stopTime = Date().timeIntervalSince1970 * 1000
      let totalDuration = stopTime - self.startTime
      self.onEnd?(stopTime, totalDuration, self.sequenceNumber)

      // Destroy the encoder on the same thread that used it
      self.opusEncoder = nil
      self.pendingSamples.removeAll()
      self.pcmFileHandle?.closeFile()
      self.pcmFileHandle = nil
    }

    print("[AudioProcessor] Flushed and stopped")
  }

  // MARK: - Event callbacks

  func setOnAudioChunk(_ callback: @escaping ([EncodedFrame], Double, Int, Double, Int) -> Void) {
    self.onAudioChunk = callback
  }

  func setOnStarted(_ callback: @escaping (_ timestamp: Double, _ sampleRate: Int, _ channels: Int, _ bitrate: Int, _ frameSize: Double, _ preSkip: Int) -> Void) {
    self.onStarted = callback
  }

  func setOnEnd(_ callback: @escaping (_ timestamp: Double, _ totalDuration: Double, _ totalPackets: Int) -> Void) {
    self.onEnd = callback
  }

  // MARK: - Encoding queue internals (all below only called on `queue`)

  private func _processFrames() {
    guard let opusEncoder = opusEncoder else { return }

    while pendingSamples.count >= samplesPerFrame {
      let frameData = Array(pendingSamples.prefix(samplesPerFrame))
      pendingSamples.removeFirst(samplesPerFrame)

      // Debug PCM file
      if let fileHandle = pcmFileHandle {
        frameData.withUnsafeBufferPointer { ptr in
          let data = Data(bytes: ptr.baseAddress!, count: frameData.count * MemoryLayout<Int16>.size)
          fileHandle.write(data)
        }
      }

      // Encode single frame to Opus
      var encodedPacket: Data?
      frameData.withUnsafeBufferPointer { bufferPointer in
        guard let baseAddress = bufferPointer.baseAddress else { return }
        encodedPacket = opusEncoder.encode(pcm: baseAddress, frameSize: samplesPerFrame)
      }

      guard let opusData = encodedPacket, !opusData.isEmpty else {
        print("[AudioProcessor] Failed to encode Opus packet")
        continue
      }

      // Per-frame audio level (RMS → dBFS → 0~1)
      var frameLevel: Float? = nil
      if enableAudioLevel {
        var sumSquares: Double = 0.0
        for sample in frameData {
          let s = Double(sample) / 32768.0
          sumSquares += s * s
        }
        let rms = sqrt(sumSquares / Double(frameData.count))
        let dB = 20.0 * log10(max(rms, 1e-10))
        let dbFloor = -35.0
        let dbCeiling = -6.0
        frameLevel = Float(max(0.0, min(1.0, (dB - dbFloor) / (dbCeiling - dbFloor))))
      }

      // Accumulate the encoded frame as an independent packet (no byte concatenation)
      packetFrames.append(EncodedFrame(data: opusData, audioLevel: frameLevel))

      // Emit once we have enough frames (framesPerCallback)
      if packetFrames.count >= framesPerPacket {
        let timestampMs = Date().timeIntervalSince1970 * 1000
        let frameCount = packetFrames.count
        let duration = Double(frameCount) * config.frameSize
        onAudioChunk?(packetFrames, timestampMs, sequenceNumber, duration, frameCount)
        sequenceNumber += 1
        packetFrames.removeAll()
      }
    }
  }

  private func _flushRemainingFrames() {
    guard let opusEncoder = opusEncoder else { return }

    // Pad remaining PCM with silence to fill the last frame
    if !pendingSamples.isEmpty && pendingSamples.count < samplesPerFrame {
      pendingSamples.append(contentsOf: [Int16](repeating: 0, count: samplesPerFrame - pendingSamples.count))
    }

    // Encode remaining frames
    while pendingSamples.count >= samplesPerFrame {
      let frameData = Array(pendingSamples.prefix(samplesPerFrame))
      pendingSamples.removeFirst(samplesPerFrame)

      var encodedPacket: Data?
      frameData.withUnsafeBufferPointer { bufferPointer in
        guard let baseAddress = bufferPointer.baseAddress else { return }
        encodedPacket = opusEncoder.encode(pcm: baseAddress, frameSize: samplesPerFrame)
      }

      guard let opusData = encodedPacket, !opusData.isEmpty else { continue }
      // Flush frames get level 0 (silence-padded)
      packetFrames.append(EncodedFrame(data: opusData, audioLevel: enableAudioLevel ? 0.0 : nil))
    }

    // Flush any remaining frames (even if fewer than framesPerPacket)
    if !packetFrames.isEmpty {
      let timestampMs = Date().timeIntervalSince1970 * 1000
      let frameCount = packetFrames.count
      let duration = Double(frameCount) * config.frameSize
      onAudioChunk?(packetFrames, timestampMs, sequenceNumber, duration, frameCount)
      sequenceNumber += 1
      packetFrames.removeAll()
    }
  }
}
