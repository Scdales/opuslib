import AVFoundation
import ExpoModulesCore

/**
 * AudioEngineManager - Manages AVAudioEngine for real-time audio capture.
 *
 * This class handles ONLY audio capture (AVAudioEngine lifecycle, audio session
 * configuration, the real-time tap callback, and interruption handling). All
 * Opus 1.6.1 encoding is delegated to AudioProcessor, which runs on its own
 * serial queue. The tap callback only converts the PCM format and copies the
 * samples across to the encoding queue — it never blocks on the encoder.
 */
class AudioEngineManager {
  // Audio engine and nodes
  private var audioEngine: AVAudioEngine?
  private var inputNode: AVAudioInputNode?

  // Audio format converter
  private var audioConverter: AVAudioConverter?

  // Encoding processor (owns the encoder, runs on a separate serial queue)
  private var processor: AudioProcessor?

  // Configuration (immutable after init)
  private let config: AudioConfig

  // Recording state
  private var isRecording = false
  private var isPaused = false
  private var loggedFirstBuffer = false

  // Event callbacks
  private var onAudioChunk: (([EncodedFrame], Double, Int, Double, Int) -> Void)?
  private var onStarted: ((_ timestamp: Double, _ sampleRate: Int, _ channels: Int, _ bitrate: Int, _ frameSize: Double, _ preSkip: Int) -> Void)?
  private var onEnd: ((_ timestamp: Double, _ totalDuration: Double, _ totalPackets: Int) -> Void)?
  private var onAmplitude: ((Float, Float, Double) -> Void)?
  private var onError: ((Error) -> Void)?

  init(config: AudioConfig) {
    self.config = config

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

    // Create and start the AudioProcessor (encoding thread)
    let proc = AudioProcessor(config: config)
    proc.setOnAudioChunk { [weak self] frames, timestamp, seq, duration, frameCount in
      self?.onAudioChunk?(frames, timestamp, seq, duration, frameCount)
    }
    proc.setOnStarted { [weak self] timestamp, sampleRate, channels, bitrate, frameSize, preSkip in
      self?.onStarted?(timestamp, sampleRate, channels, bitrate, frameSize, preSkip)
    }
    proc.setOnEnd { [weak self] timestamp, totalDuration, totalPackets in
      self?.onEnd?(timestamp, totalDuration, totalPackets)
    }

    // Debug file
    var debugURL: URL? = nil
    if config.saveDebugAudio == true {
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      let timestamp = Date().timeIntervalSince1970
      debugURL = documentsPath.appendingPathComponent("debug_pcm_\(timestamp).raw")
    }

    try proc.start(debugFileURL: debugURL)
    processor = proc

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

    // Install tap — real-time thread callback, only does format convert + copy + post
    inputNode.installTap(
      onBus: 0,
      bufferSize: bufferSize,
      format: hardwareFormat
    ) { [weak self] buffer, _ in
      self?.onTapBuffer(buffer)
    }

    // Start audio engine
    try audioEngine.start()

    isRecording = true

    print("[AudioEngineManager] Started recording: \(hardwareFormat.sampleRate)Hz → \(config.sampleRate)Hz, \(config.channels) ch")
  }

  func stop() {
    guard isRecording else {
      return
    }

    isRecording = false

    // Stop audio capture
    inputNode?.removeTap(onBus: 0)
    audioEngine?.stop()

    // Flush and stop the encoding thread (synchronous — drains remaining samples,
    // pads the final partial frame with silence, and emits audioEnd)
    processor?.flushAndStop()
    processor = nil

    // Clean up
    audioEngine = nil
    inputNode = nil
    audioConverter = nil

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

  func setOnAudioChunk(_ callback: @escaping ([EncodedFrame], Double, Int, Double, Int) -> Void) {
    self.onAudioChunk = callback
  }

  func setOnStarted(_ callback: @escaping (_ timestamp: Double, _ sampleRate: Int, _ channels: Int, _ bitrate: Int, _ frameSize: Double, _ preSkip: Int) -> Void) {
    self.onStarted = callback
  }

  func setOnEnd(_ callback: @escaping (_ timestamp: Double, _ totalDuration: Double, _ totalPackets: Int) -> Void) {
    self.onEnd = callback
  }

  func setOnAmplitude(_ callback: @escaping (Float, Float, Double) -> Void) {
    self.onAmplitude = callback
  }

  func setOnError(_ callback: @escaping (Error) -> Void) {
    self.onError = callback
  }

  // MARK: - Real-time Audio Thread (tap callback)
  // Only does format conversion + copy + post. No encoding, no locks.

  private func onTapBuffer(_ buffer: AVAudioPCMBuffer) {
    guard !isPaused else { return }
    guard let audioConverter = audioConverter else { return }

    // Calculate output buffer size based on sample rate conversion
    let sampleRateRatio = Double(config.sampleRate) / buffer.format.sampleRate
    let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio)

    // Create output buffer in desired format (e.g. 16kHz, Int16)
    guard let outputFormat = audioConverter.outputFormat as? AVAudioFormat,
          let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
          ) else { return }

    // Convert audio from hardware format to desired format
    var error: NSError?
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }

    let status = audioConverter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
    if status == .error { return }

    guard let channelData = convertedBuffer.int16ChannelData else { return }

    let frameLength = Int(convertedBuffer.frameLength)
    let channelDataPointer = channelData[0]

    if !loggedFirstBuffer {
      print("[AudioEngineManager] First converted buffer: \(frameLength) samples at \(convertedBuffer.format.sampleRate)Hz")
      loggedFirstBuffer = true
    }

    // Copy the PCM and post it to the encoding queue (does not block the tap)
    let samples = Array(UnsafeBufferPointer(start: channelDataPointer, count: frameLength))
    processor?.pushSamples(samples)
  }

  // MARK: - Audio Session

  private func configureAudioSession() throws {
    let audioSession = AVAudioSession.sharedInstance()

    let sessionConfig = config.iosAudioSession
    let category = Self.mapCategory(sessionConfig?.category)
    let mode = Self.mapMode(sessionConfig?.mode)
    let options = Self.mapOptions(sessionConfig?.options)

    // Try the requested config first; if it is an invalid combination, fall back to safe defaults
    do {
      try audioSession.setCategory(category, mode: mode, options: options)
      print("[AudioEngineManager] Audio session configured: category=\(category.rawValue), mode=\(mode.rawValue), options=\(options.rawValue)")
    } catch {
      print("[AudioEngineManager] Custom audio session config failed (\(error.localizedDescription)), falling back to defaults")
      do {
        try audioSession.setCategory(.record, mode: .measurement, options: [])
        print("[AudioEngineManager] Audio session configured with defaults: category=record, mode=measurement, options=[]")
      } catch {
        print("[AudioEngineManager] Fallback audio session config also failed: \(error.localizedDescription), continuing with current session")
      }
    }

    // setPreferredSampleRate / setPreferredIOBufferDuration are hints, not hard requirements — don't let them crash
    do { try audioSession.setPreferredSampleRate(Double(config.sampleRate)) }
    catch { print("[AudioEngineManager] setPreferredSampleRate failed: \(error.localizedDescription)") }

    do { try audioSession.setPreferredIOBufferDuration(config.frameSize / 1000.0) }
    catch { print("[AudioEngineManager] setPreferredIOBufferDuration failed: \(error.localizedDescription)") }

    try audioSession.setActive(true)
  }

  // MARK: - String → AVAudioSession Mapping

  private static func mapCategory(_ value: String?) -> AVAudioSession.Category {
    guard let value = value else { return .record }
    switch value {
    case "record":          return .record
    case "playAndRecord":   return .playAndRecord
    case "playback":        return .playback
    case "ambient":         return .ambient
    default:
      print("[AudioEngineManager] Unknown category '\(value)', falling back to .record")
      return .record
    }
  }

  private static func mapMode(_ value: String?) -> AVAudioSession.Mode {
    guard let value = value else { return .measurement }
    switch value {
    case "default":         return .default
    case "voiceChat":       return .voiceChat
    case "measurement":     return .measurement
    case "spokenAudio":     return .spokenAudio
    default:
      print("[AudioEngineManager] Unknown mode '\(value)', falling back to .measurement")
      return .measurement
    }
  }

  private static func mapOptions(_ values: [String]?) -> AVAudioSession.CategoryOptions {
    guard let values = values else { return [] }
    var options: AVAudioSession.CategoryOptions = []
    for value in values {
      switch value {
      case "mixWithOthers":       options.insert(.mixWithOthers)
      case "defaultToSpeaker":    options.insert(.defaultToSpeaker)
      case "allowBluetooth":      options.insert(.allowBluetooth)
      case "allowAirPlay":        options.insert(.allowAirPlay)
      case "allowBluetoothA2DP":  options.insert(.allowBluetoothA2DP)
      default:
        print("[AudioEngineManager] Unknown option '\(value)', skipping")
      }
    }
    return options
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
