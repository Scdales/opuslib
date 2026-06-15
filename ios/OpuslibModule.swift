import ExpoModulesCore
import AVFoundation

/**
 * OpuslibModule - Expo module for Opus 1.6.1 audio encoding with DRED support
 *
 * This module provides native audio capture and Opus 1.6.1 encoding with Deep Redundancy (DRED)
 * for improved audio quality on lossy networks.
 */
public class OpuslibModule: Module {
  private var audioEngineManager: AudioEngineManager?
  private var isStreaming = false

  public func definition() -> ModuleDefinition {
    Name("Opuslib")

    // Events
    Events("audioChunk", "amplitude", "audioStarted", "audioEnd", "error")

    // Start streaming method
    AsyncFunction("startStreaming") { (config: AudioConfig) in
      try self.startStreaming(config: config)
    }

    // Stop streaming method
    AsyncFunction("stopStreaming") {
      try await self.stopStreaming()
    }

    // Pause streaming method
    Function("pauseStreaming") {
      self.pauseStreaming()
    }

    // Resume streaming method
    Function("resumeStreaming") {
      self.resumeStreaming()
    }
  }

  // MARK: - Public Methods

  private func startStreaming(config: AudioConfig) throws {
    print("[OpuslibModule] 🎬 startStreaming() called with DRED: \(config.dredDuration ?? 100)ms")

    guard !isStreaming else {
      throw AudioStreamError.alreadyStreaming
    }

    // Request microphone permission
    print("[OpuslibModule] 🔐 Requesting microphone permission...")
    try requestMicrophonePermission()
    print("[OpuslibModule] ✅ Microphone permission granted")

    // Create audio engine manager
    print("[OpuslibModule] 🏗️ Creating AudioEngineManager...")
    let manager = AudioEngineManager(config: config)
    print("[OpuslibModule] ✅ AudioEngineManager created")

    // Set up event callbacks — audioStarted/audioEnd are emitted from the encoding thread
    print("[OpuslibModule] 🔗 Setting up event callbacks...")
    manager.setOnAudioChunk { [weak self] frames, timestamp, sequenceNumber, duration, frameCount in
      // Each frame is an independent Opus packet wrapped in { data, audioLevel? }
      let frameObjects: [[String: Any]] = frames.map { frame in
        var obj: [String: Any] = ["data": frame.data]
        if let level = frame.audioLevel {
          obj["audioLevel"] = level
        }
        return obj
      }
      // `data` is the first frame's packet, kept for backward compatibility with
      // consumers that read a single Opus packet per event.
      let firstData = frames.first?.data ?? Data()
      self?.sendEvent("audioChunk", [
        "data": firstData,
        "frames": frameObjects,
        "timestamp": timestamp,
        "sequenceNumber": sequenceNumber,
        "duration": duration,
        "frameCount": frameCount
      ])
    }

    manager.setOnStarted { [weak self] timestamp, sampleRate, channels, bitrate, frameSize, preSkip in
      self?.sendEvent("audioStarted", [
        "timestamp": timestamp,
        "sampleRate": sampleRate,
        "channels": channels,
        "bitrate": bitrate,
        "frameSize": frameSize,
        "preSkip": preSkip
      ])
    }

    manager.setOnEnd { [weak self] timestamp, totalDuration, totalPackets in
      self?.sendEvent("audioEnd", [
        "timestamp": timestamp,
        "totalDuration": totalDuration,
        "totalPackets": totalPackets
      ])
    }

    manager.setOnAmplitude { [weak self] rms, peak, timestamp in
      self?.sendEvent("amplitude", [
        "rms": rms,
        "peak": peak,
        "timestamp": timestamp
      ])
    }

    manager.setOnError { [weak self] error in
      print("[OpuslibModule] ❌ Error from manager: \(error.localizedDescription)")
      self?.sendEvent("error", [
        "code": "AUDIO_ENGINE_ERROR",
        "message": error.localizedDescription
      ])
    }

    // Start audio capture + encoding
    print("[OpuslibModule] 🚀 Calling manager.start()...")
    try manager.start()
    print("[OpuslibModule] ✅ manager.start() completed")

    audioEngineManager = manager
    isStreaming = true

    print("[OpuslibModule] ✅ Started streaming")
  }

  private func stopStreaming() async throws {
    guard isStreaming else {
      return
    }

    // stop() triggers flushAndStop(), which emits audioEnd from the encoding thread
    audioEngineManager?.stop()
    audioEngineManager = nil
    isStreaming = false

    print("[OpuslibModule] Stopped streaming")
  }

  private func pauseStreaming() {
    guard isStreaming else {
      return
    }

    audioEngineManager?.pause()
    print("[OpuslibModule] Paused streaming")
  }

  private func resumeStreaming() {
    guard isStreaming else {
      return
    }

    audioEngineManager?.resume()
    print("[OpuslibModule] Resumed streaming")
  }

  // MARK: - Private Methods

  private func requestMicrophonePermission() throws {
    let audioSession = AVAudioSession.sharedInstance()

    switch audioSession.recordPermission {
    case .granted:
      return

    case .denied:
      throw AudioStreamError.permissionDenied

    case .undetermined:
      var permissionGranted = false
      let semaphore = DispatchSemaphore(value: 0)

      audioSession.requestRecordPermission { granted in
        permissionGranted = granted
        semaphore.signal()
      }

      semaphore.wait()

      if !permissionGranted {
        throw AudioStreamError.permissionDenied
      }

    @unknown default:
      throw AudioStreamError.permissionDenied
    }
  }
}

// MARK: - Configuration

/**
 * Audio configuration for Opus encoding
 */
struct AudioConfig: Record {
  @Field var sampleRate: Int = 16000
  @Field var channels: Int = 1
  @Field var bitrate: Int = 24000
  @Field var frameSize: Double = 20.0
  // Retained for backward compatibility; framesPerCallback supersedes it for batching.
  @Field var packetDuration: Double = 20.0
  // Number of Opus frames to batch per audioChunk event (default 1 = one packet per event).
  @Field var framesPerCallback: Int? = 1
  @Field var dredDuration: Int? = 100  // NEW: DRED recovery duration in ms
  @Field var enableAmplitudeEvents: Bool? = false
  @Field var amplitudeEventInterval: Double? = 16.0
  @Field var enableAudioLevel: Bool? = false  // Enable per-frame audio level calculation
  @Field var saveDebugAudio: Bool? = false
  @Field var iosAudioSession: IOSAudioSessionConfig? = nil
}

/**
 * iOS AudioSession configuration (category, mode, options).
 * Maps JS string values to AVAudioSession enums.
 */
struct IOSAudioSessionConfig: Record {
  @Field var category: String = "record"
  @Field var mode: String = "measurement"
  @Field var options: [String]? = nil
}

// MARK: - Errors

/**
 * Custom errors for audio streaming
 */
enum AudioStreamError: Error {
  case alreadyStreaming
  case notStreaming
  case permissionDenied
  case audioEngineError(String)
  case opusEncodingError(String)
}
