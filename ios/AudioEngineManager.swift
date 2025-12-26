import AVFoundation
import ExpoModulesCore

/**
 * AudioEngineManager - Manages AVAudioEngine for real-time audio capture with Opus 1.6 DRED
 *
 * This class handles:
 * - Audio session configuration
 * - AVAudioEngine setup and lifecycle
 * - Real-time PCM audio capture
 * - Opus 1.6 encoding with DRED support
 * - Audio interruption handling
 * - Microphone permission management
 */
class AudioEngineManager {
  // Audio engine and nodes
  private var audioEngine: AVAudioEngine?
  private var inputNode: AVAudioInputNode?

  // Opus encoder
  private var opusEncoder: OpusEncoder?

  // Audio format converter
  private var audioConverter: AVAudioConverter?

  // Configuration
  private var config: AudioConfig
  private var sequenceNumber: Int = 0

  // State
  private var isRecording = false
  private var isPaused = false
  private var loggedFirstBuffer = false

  // Frame accumulation for packet duration
  private var frameBuffer: [[Int16]] = []
  private let framesPerPacket: Int

  // Event callbacks
  private var onAudioChunk: ((Data, Double, Int) -> Void)?
  private var onAmplitude: ((Float, Float, Double) -> Void)?
  private var onError: ((Error) -> Void)?

  // Debug file handles
  private var pcmFileHandle: FileHandle?
  private var pcmFileURL: URL?

  init(config: AudioConfig) {
    self.config = config
    self.framesPerPacket = Int(config.packetDuration / config.frameSize)

    // Register for interruption notifications
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
  }

  // MARK: - Public Methods

  func start() throws {
    guard !isRecording else {
      throw AudioStreamError.alreadyStreaming
    }

    // Configure audio session
    try configureAudioSession()

    // Create Opus encoder with DRED support
    let dredDuration = config.dredDuration ?? 100
    opusEncoder = try OpusEncoder(
      sampleRate: config.sampleRate,
      channels: config.channels,
      bitrate: config.bitrate,
      frameSizeMs: config.frameSize,
      dredDurationMs: dredDuration
    )

    // Create and configure AVAudioEngine
    audioEngine = AVAudioEngine()
    guard let audioEngine = audioEngine else {
      throw AudioStreamError.audioEngineError("Failed to create AVAudioEngine")
    }

    inputNode = audioEngine.inputNode
    guard let inputNode = inputNode else {
      throw AudioStreamError.audioEngineError("Failed to get input node")
    }

    // Get hardware format from input node
    let hardwareFormat = inputNode.outputFormat(forBus: 0)
    print("[AudioEngineManager] Hardware format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount)ch")

    // Create desired output format (16kHz, mono, 16-bit PCM)
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(config.sampleRate),
      channels: AVAudioChannelCount(config.channels),
      interleaved: true
    ) else {
      throw AudioStreamError.audioEngineError("Failed to create output format")
    }
    print("[AudioEngineManager] Target output format: \(outputFormat.sampleRate)Hz, \(outputFormat.channelCount)ch")

    // Create converter from hardware format to desired format
    guard let converter = AVAudioConverter(from: hardwareFormat, to: outputFormat) else {
      throw AudioStreamError.audioEngineError("Failed to create audio converter")
    }
    audioConverter = converter
    print("[AudioEngineManager] Converter created: \(hardwareFormat.sampleRate)Hz → \(outputFormat.sampleRate)Hz")

    // Calculate buffer size for one frame
    let bufferSize: AVAudioFrameCount = 1024

    // Install tap on input node with hardware format
    inputNode.installTap(
      onBus: 0,
      bufferSize: bufferSize,
      format: hardwareFormat
    ) { [weak self] buffer, time in
      self?.processBuffer(buffer, time: time)
    }

    // Start audio engine
    try audioEngine.start()

    isRecording = true

    // Create debug output files if enabled
    if config.saveDebugAudio == true {
      do {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Date().timeIntervalSince1970

        pcmFileURL = documentsPath.appendingPathComponent("debug_pcm_\(timestamp).raw")

        // Create PCM file
        FileManager.default.createFile(atPath: pcmFileURL!.path, contents: nil, attributes: nil)

        // Open file handle for writing
        pcmFileHandle = try FileHandle(forWritingTo: pcmFileURL!)

        print("[AudioEngineManager] Debug audio file created:")
        print("  PCM: \(pcmFileURL!.path)")
      } catch {
        print("[AudioEngineManager] Failed to create debug files: \(error)")
      }
    }

    print("[AudioEngineManager] Started recording: \(hardwareFormat.sampleRate)Hz → \(config.sampleRate)Hz, \(config.channels) ch, DRED: \(dredDuration)ms")
  }

  func stop() {
    guard isRecording else {
      return
    }

    // Remove tap and stop engine
    inputNode?.removeTap(onBus: 0)
    audioEngine?.stop()

    // Clean up
    audioEngine = nil
    inputNode = nil
    opusEncoder = nil
    audioConverter = nil
    frameBuffer.removeAll()

    isRecording = false
    sequenceNumber = 0

    // Close debug file handle
    if let fileHandle = pcmFileHandle {
      fileHandle.closeFile()
      pcmFileHandle = nil
      print("[AudioEngineManager] Closed PCM debug file: \(pcmFileURL?.path ?? "")")
    }

    print("[AudioEngineManager] Stopped recording")
  }

  func pause() {
    isPaused = true
    print("[AudioEngineManager] Paused")
  }

  func resume() {
    isPaused = false
    print("[AudioEngineManager] Resumed")
  }

  // MARK: - Event Handlers

  func setOnAudioChunk(_ callback: @escaping (Data, Double, Int) -> Void) {
    self.onAudioChunk = callback
  }

  func setOnAmplitude(_ callback: @escaping (Float, Float, Double) -> Void) {
    self.onAmplitude = callback
  }

  func setOnError(_ callback: @escaping (Error) -> Void) {
    self.onError = callback
  }

  // MARK: - Private Methods

  private func processBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
    guard !isPaused else {
      return
    }

    guard let audioConverter = audioConverter else {
      return
    }

    // Calculate output buffer size based on sample rate conversion
    let outputSampleRate = Double(config.sampleRate)
    let inputSampleRate = buffer.format.sampleRate
    let sampleRateRatio = outputSampleRate / inputSampleRate
    let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio)

    // Create output buffer in desired format (16kHz, Int16)
    guard let outputFormat = audioConverter.outputFormat as? AVAudioFormat,
          let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
          ) else {
      return
    }

    // Convert audio from hardware format to desired format
    var error: NSError?
    let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }

    let status = audioConverter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

    if status == .error {
      return
    }

    // Process the converted Int16 data
    guard let channelData = convertedBuffer.int16ChannelData else {
      return
    }

    let frameLength = Int(convertedBuffer.frameLength)
    let channelDataPointer = channelData[0]

    // DEBUG: Log first buffer to verify conversion
    if !loggedFirstBuffer {
      print("[AudioEngineManager] First converted buffer: \(frameLength) samples at \(convertedBuffer.format.sampleRate)Hz")
      loggedFirstBuffer = true
    }

    // Copy PCM data to frame buffer
    let frame = Array(UnsafeBufferPointer(start: channelDataPointer, count: frameLength))

    // Save PCM to debug file if enabled
    if let fileHandle = pcmFileHandle {
      let data = Data(bytes: channelDataPointer, count: frameLength * MemoryLayout<Int16>.size)
      fileHandle.write(data)
    }

    frameBuffer.append(frame)

    // Calculate how many samples we need for one packet
    let samplesPerPacket = Int(Double(config.sampleRate) * config.packetDuration / 1000.0)
    let currentSampleCount = frameBuffer.reduce(0) { $0 + $1.count }

    // When we have enough samples for a packet, encode and send
    if currentSampleCount >= samplesPerPacket {
      encodeAndSendPacket(timestamp: time.sampleTime)
    }
  }

  private func encodeAndSendPacket(timestamp: AVAudioFramePosition) {
    guard let opusEncoder = opusEncoder else {
      return
    }

    // Flatten frame buffer into continuous PCM data
    let pcmData = frameBuffer.flatMap { $0 }

    // Calculate samples per frame
    let samplesPerFrame = Int(Double(config.sampleRate) * config.frameSize / 1000.0)

    // We should only encode when we have at least one frame
    guard pcmData.count >= samplesPerFrame else {
      return
    }

    // Take only ONE frame worth of samples
    let frameData = Array(pcmData.prefix(samplesPerFrame))

    // Encode this single frame to Opus (with DRED padding if enabled)
    var encodedPacket: Data?
    frameData.withUnsafeBufferPointer { bufferPointer in
      guard let baseAddress = bufferPointer.baseAddress else {
        return
      }

      encodedPacket = opusEncoder.encode(pcm: baseAddress, frameSize: samplesPerFrame)
    }

    guard let opusData = encodedPacket, !opusData.isEmpty else {
      print("[AudioEngineManager] Failed to encode Opus packet")
      frameBuffer.removeAll()
      return
    }

    // Calculate timestamp in milliseconds
    let timestampMs = Date().timeIntervalSince1970 * 1000

    // Emit audioChunk event with Opus packet (may be larger due to DRED)
    onAudioChunk?(opusData, timestampMs, sequenceNumber)

    sequenceNumber += 1

    // Keep any remaining samples for next packet
    let remainingSamples = pcmData.count - samplesPerFrame
    if remainingSamples > 0 {
      frameBuffer = [Array(pcmData[samplesPerFrame...])]
    } else {
      frameBuffer.removeAll()
    }
  }

  private func configureAudioSession() throws {
    let audioSession = AVAudioSession.sharedInstance()

    try audioSession.setCategory(.record, mode: .measurement, options: [])
    try audioSession.setPreferredSampleRate(Double(config.sampleRate))
    try audioSession.setPreferredIOBufferDuration(config.frameSize / 1000.0)

    try audioSession.setActive(true)

    print("[AudioEngineManager] Audio session configured")
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    switch type {
    case .began:
      print("[AudioEngineManager] Audio interruption began")
      pause()

    case .ended:
      print("[AudioEngineManager] Audio interruption ended")
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
          resume()
        }
      }

    @unknown default:
      break
    }
  }

  deinit {
    stop()
    NotificationCenter.default.removeObserver(self)
  }
}
