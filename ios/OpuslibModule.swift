import ExpoModulesCore
import AVFoundation

/**
 * OpuslibModule - Expo module for Opus 1.6 audio encoding with DRED support
 *
 * This module provides native audio capture and Opus 1.6 encoding with Deep Redundancy (DRED)
 * for improved audio quality on lossy networks.
 */
public class OpuslibModule: Module {
  private var audioEngineManager: AudioEngineManager?
  private var isStreaming = false

  public func definition() -> ModuleDefinition {
    Name("Opuslib")

    // Events
    Events("audioChunk", "amplitude", "error")

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

    // Set up event callbacks
    print("[OpuslibModule] 🔗 Setting up event callbacks...")
    manager.setOnAudioChunk { [weak self] data, timestamp, sequenceNumber in
      self?.sendEvent("audioChunk", [
        "data": data,
        "timestamp": timestamp,
        "sequenceNumber": sequenceNumber
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

    // Start audio capture
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
  @Field var packetDuration: Double = 20.0
  @Field var dredDuration: Int? = 100  // NEW: DRED recovery duration in ms
  @Field var enableAmplitudeEvents: Bool? = false
  @Field var amplitudeEventInterval: Double? = 16.0
  @Field var saveDebugAudio: Bool? = false
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
