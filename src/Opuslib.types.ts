/**
 * Audio configuration for Opus encoding
 */
export interface AudioConfig {
  /** Sample rate in Hz (8000, 12000, 16000, 24000, 48000) */
  sampleRate: number
  /** Number of channels (1 = mono, 2 = stereo) */
  channels: number
  /** Target bitrate in bits/second (e.g., 24000 for 24kbps) */
  bitrate: number
  /** Frame duration in milliseconds (2.5, 5, 10, 20, 40, 60) */
  frameSize: number
  /** Packet duration in milliseconds (typically 20-100ms) */
  packetDuration: number
  /**
   * Number of independently-encoded Opus frames to batch into a single
   * `audioChunk` event (default 1). Each entry in `AudioChunkEvent.frames` is a
   * complete, independently decodable Opus packet — frames are never
   * concatenated. Batching reduces the number of bridge calls.
   */
  framesPerCallback?: number
  /** DRED recovery duration in milliseconds (0-100, default 100) - NEW in Opus 1.6 */
  dredDuration?: number
  /** Enable amplitude events for waveform visualization */
  enableAmplitudeEvents?: boolean
  /** Amplitude event interval in milliseconds (default 16) */
  amplitudeEventInterval?: number
  /**
   * Enable per-frame audio level calculation (default false). When enabled,
   * each `OpusFrame` carries an `audioLevel` (0.0 - 1.0) derived from RMS.
   * Disabled by default to save computation.
   */
  enableAudioLevel?: boolean
  /** Save debug PCM audio to file (development only) */
  saveDebugAudio?: boolean
  /**
   * iOS AudioSession configuration (iOS only; ignored on Android and web).
   * Omit to keep the default recording session
   * (`record` category, `measurement` mode, no options).
   */
  iosAudioSession?: IOSAudioSessionConfig
}

/**
 * iOS `AVAudioSession` configuration. iOS only — ignored on Android and web.
 */
export interface IOSAudioSessionConfig {
  /**
   * `AVAudioSession.Category`
   * - `record`: pure recording (default)
   * - `playAndRecord`: record and play simultaneously
   * - `playback`: playback only
   * - `ambient`: mix with other audio without interrupting it
   */
  category: 'record' | 'playAndRecord' | 'playback' | 'ambient'
  /**
   * `AVAudioSession.Mode`
   * - `measurement`: disable system audio processing (default)
   * - `default`: enable system audio processing (AGC, echo cancellation)
   * - `voiceChat`: optimized for voice calls
   * - `spokenAudio`: optimized for spoken content
   */
  mode: 'default' | 'voiceChat' | 'measurement' | 'spokenAudio'
  /** `AVAudioSession.CategoryOptions` (combinable) */
  options?: (
    | 'mixWithOthers'
    | 'defaultToSpeaker'
    | 'allowBluetooth'
    | 'allowAirPlay'
    | 'allowBluetoothA2DP'
  )[]
}

/**
 * A single Opus frame — one complete `opus_encode()` output with its own TOC
 * byte, decodable on its own.
 */
export interface OpusFrame {
  /** Opus-encoded packet data (independent, decodable) */
  data: ArrayBuffer
  /** Per-frame audio level (0.0 - 1.0). Present only when `enableAudioLevel` is true. */
  audioLevel?: number
}

/**
 * Audio chunk event payload (Opus-encoded data)
 */
export interface AudioChunkEvent {
  /**
   * The first frame's Opus packet, kept for backward compatibility — equivalent
   * to `frames[0].data`. With the default `framesPerCallback` of 1 this is the
   * single packet for the event. Prefer `frames` for new code.
   */
  data: ArrayBuffer
  /**
   * Independently decodable Opus packets in this event (one per encoded frame).
   * Contains a single entry unless `framesPerCallback` > 1.
   */
  frames: OpusFrame[]
  /** Timestamp in milliseconds */
  timestamp: number
  /** Sequence number (increments with each event) */
  sequenceNumber: number
  /** Duration of all frames in milliseconds (`frameSize * frameCount`) */
  duration: number
  /** Number of Opus frames in this event (= `frames.length`) */
  frameCount: number
}

/**
 * Amplitude event payload (for waveform visualization)
 */
export interface AmplitudeEvent {
  /** Root mean square amplitude (0.0 - 1.0) */
  rms: number
  /** Peak amplitude (0.0 - 1.0) */
  peak: number
  /** Timestamp in milliseconds */
  timestamp: number
}

/**
 * Audio started event payload. Emitted once when streaming begins.
 */
export interface AudioStartedEvent {
  /** Timestamp in milliseconds when streaming started */
  timestamp: number
  /** Actual sample rate in Hz */
  sampleRate: number
  /** Number of channels */
  channels: number
  /** Configured bitrate in bits/second */
  bitrate: number
  /** Frame duration in milliseconds */
  frameSize: number
  /** Opus encoder lookahead in samples — decoders should skip this many samples at the start */
  preSkip: number
}

/**
 * Audio end event payload. Emitted once when streaming stops, after the final
 * buffered audio has been flushed.
 */
export interface AudioEndEvent {
  /** Timestamp in milliseconds when streaming stopped */
  timestamp: number
  /** Total session duration in milliseconds */
  totalDuration: number
  /** Total number of packets (audioChunk events) emitted during the session */
  totalPackets: number
}

/**
 * Error event payload
 */
export interface ErrorEvent {
  /** Error code */
  code: string
  /** Error message */
  message: string
}

/**
 * Event subscription
 */
export interface Subscription {
  remove: () => void
}
