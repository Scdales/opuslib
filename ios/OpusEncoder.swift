import Foundation

/**
 * OpusEncoder - Swift wrapper for Opus 1.6 with DRED support
 *
 * This class provides a Swift interface to the Opus 1.6 C library for
 * encoding PCM audio to Opus format with Deep Redundancy (DRED) support.
 *
 * DRED (Deep Redundancy) embeds up to 1 second of recovery data in packet
 * padding for improved audio quality on lossy networks. This is particularly
 * valuable for real-time voice applications.
 *
 * Features:
 * - Low latency encoding (20ms frame sizes)
 * - Excellent compression (6-12x vs PCM)
 * - Optimized for speech (VOIP application mode)
 * - DRED packet loss concealment (Opus 1.6 feature)
 * - Configurable bitrate, VBR, complexity, FEC, DTX
 */
class OpusEncoder {
  // Opus encoder instance (opaque pointer from libopus)
  private var encoder: OpaquePointer?

  // Configuration
  private let sampleRate: Int
  private let channels: Int
  private let bitrate: Int
  private let frameSize: Int // samples per frame
  private let dredDuration: Int // DRED recovery duration in ms

  // Buffer for encoded output
  private let maxPacketSize = 4000 // bytes

  /**
   * Initialize Opus 1.6 encoder with DRED support
   *
   * @param sampleRate: Sample rate in Hz (8000, 12000, 16000, 24000, 48000)
   * @param channels: Number of channels (1 = mono, 2 = stereo)
   * @param bitrate: Target bitrate in bits/second (e.g., 24000 for 24kbps)
   * @param frameSizeMs: Frame duration in milliseconds (2.5, 5, 10, 20, 40, 60)
   * @param dredDurationMs: DRED recovery duration in ms (0-100, default 100)
   * @param vbr: Enable variable bitrate (default true)
   * @param complexity: Encoding complexity 0-10 (default 10)
   * @param inbandFec: Enable in-band forward error correction (default false)
   * @param dtx: Enable discontinuous transmission for silence (default false)
   */
  init(
    sampleRate: Int,
    channels: Int,
    bitrate: Int,
    frameSizeMs: Double,
    dredDurationMs: Int = 100,
    vbr: Bool = true,
    complexity: Int = 10,
    inbandFec: Bool = false,
    dtx: Bool = false
  ) throws {
    self.sampleRate = sampleRate
    self.channels = channels
    self.bitrate = bitrate
    self.dredDuration = dredDurationMs

    // Calculate frame size in samples
    // frameSize = (sampleRate * frameSizeMs) / 1000
    // Example: 16000Hz * 20ms / 1000 = 320 samples
    self.frameSize = Int(Double(sampleRate) * frameSizeMs / 1000.0)

    // Create Opus encoder
    var error: Int32 = 0
    guard let encoder = opus_encoder_create(
      Int32(sampleRate),
      Int32(channels),
      OPUS_APPLICATION_VOIP, // Optimized for speech
      &error
    ) else {
      throw NSError(
        domain: "OpusEncoder",
        code: Int(error),
        userInfo: [NSLocalizedDescriptionKey: "Failed to create Opus encoder (error \(error))"]
      )
    }

    if error != OPUS_OK {
      opus_encoder_destroy(encoder)
      throw NSError(
        domain: "OpusEncoder",
        code: Int(error),
        userInfo: [NSLocalizedDescriptionKey: "Opus encoder creation failed (error \(error))"]
      )
    }

    self.encoder = encoder

    // Configure encoder using Objective-C wrapper
    var result: Int32
    let encoderPtr = UnsafeMutableRawPointer(encoder)

    // Set bitrate
    result = Int32(OpusCtlHelpers.setBitrate(encoderPtr, bitrate: Int32(bitrate)))
    if result != OPUS_OK {
      print("[OpusEncoder] Warning: Failed to set bitrate (error \(result))")
    }

    // Set variable bitrate (VBR)
    result = Int32(OpusCtlHelpers.setVbr(encoderPtr, vbr: vbr ? 1 : 0))
    if result != OPUS_OK {
      print("[OpusEncoder] Warning: Failed to set VBR (error \(result))")
    }

    // Set complexity
    result = Int32(OpusCtlHelpers.setComplexity(encoderPtr, complexity: Int32(complexity)))
    if result != OPUS_OK {
      print("[OpusEncoder] Warning: Failed to set complexity (error \(result))")
    }

    // Set in-band FEC
    result = Int32(OpusCtlHelpers.setInbandFec(encoderPtr, fec: inbandFec ? 1 : 0))
    if result != OPUS_OK {
      print("[OpusEncoder] Warning: Failed to set FEC (error \(result))")
    }

    // Set DTX
    result = Int32(OpusCtlHelpers.setDtx(encoderPtr, dtx: dtx ? 1 : 0))
    if result != OPUS_OK {
      print("[OpusEncoder] Warning: Failed to set DTX (error \(result))")
    }

    // Enable DRED (Opus 1.6 feature)
    if dredDurationMs > 0 {
      result = Int32(OpusCtlHelpers.setDredDuration(encoderPtr, durationMs: Int32(dredDurationMs)))
      if result != OPUS_OK {
        print("[OpusEncoder] Warning: DRED not available or failed to configure (error \(result))")
        print("[OpusEncoder] This may indicate Opus was not compiled with DRED support")
      } else {
        print("[OpusEncoder] DRED enabled: \(dredDurationMs)ms recovery duration")
      }
    }

    print("""
    [OpusEncoder] Initialized:
      - Sample rate: \(sampleRate)Hz
      - Channels: \(channels)
      - Bitrate: \(bitrate/1000)kbps
      - Frame size: \(frameSize) samples (\(frameSizeMs)ms)
      - VBR: \(vbr)
      - Complexity: \(complexity)/10
      - In-band FEC: \(inbandFec)
      - DTX: \(dtx)
      - DRED: \(dredDurationMs)ms
    """)
  }

  /**
   * Encode PCM samples to Opus
   *
   * @param pcm: Pointer to Int16 PCM samples
   * @param frameSize: Number of samples to encode (must match configured frameSize)
   * @returns: Opus-encoded data, or nil if encoding fails
   */
  func encode(pcm: UnsafePointer<Int16>, frameSize: Int) -> Data? {
    guard let encoder = encoder else {
      print("[OpusEncoder] Encoder not initialized")
      return nil
    }

    guard frameSize == self.frameSize else {
      print("[OpusEncoder] Frame size mismatch: expected \(self.frameSize), got \(frameSize)")
      return nil
    }

    // Allocate output buffer
    var outputBuffer = [UInt8](repeating: 0, count: maxPacketSize)

    // Encode PCM to Opus
    let encodedBytes = opus_encode(
      encoder,
      pcm,
      Int32(frameSize),
      &outputBuffer,
      Int32(maxPacketSize)
    )

    if encodedBytes < 0 {
      print("[OpusEncoder] Encoding failed (error \(encodedBytes))")
      return nil
    }

    if encodedBytes == 0 {
      print("[OpusEncoder] Warning: Encoded 0 bytes")
      return nil
    }

    // Return encoded data (may include DRED padding if enabled)
    return Data(outputBuffer.prefix(Int(encodedBytes)))
  }

  /**
   * Encode multiple frames into a single packet
   *
   * This method accumulates multiple small frames (e.g., 5x 20ms frames)
   * into a single packet (e.g., 100ms) for more efficient transmission.
   *
   * @param pcmFrames: Array of PCM frame buffers
   * @returns: Opus-encoded data containing all frames, or nil if encoding fails
   */
  func encodePacket(pcmFrames: [UnsafePointer<Int16>]) -> Data? {
    guard !pcmFrames.isEmpty else {
      return nil
    }

    var encodedPacket = Data()

    // Encode each frame and concatenate
    for pcm in pcmFrames {
      guard let encodedFrame = encode(pcm: pcm, frameSize: frameSize) else {
        print("[OpusEncoder] Failed to encode frame in packet")
        return nil
      }
      encodedPacket.append(encodedFrame)
    }

    return encodedPacket
  }

  deinit {
    if let encoder = encoder {
      opus_encoder_destroy(encoder)
      self.encoder = nil
      print("[OpusEncoder] Encoder destroyed")
    }
  }
}
