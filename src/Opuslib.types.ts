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
  /** DRED recovery duration in milliseconds (0-100, default 100) - NEW in Opus 1.6 */
  dredDuration?: number
  /** Enable amplitude events for waveform visualization */
  enableAmplitudeEvents?: boolean
  /** Amplitude event interval in milliseconds (default 16) */
  amplitudeEventInterval?: number
  /** Save debug PCM audio to file (development only) */
  saveDebugAudio?: boolean
}

/**
 * Audio chunk event payload (Opus-encoded data)
 */
export interface AudioChunkEvent {
  /** Opus-encoded audio data as ArrayBuffer */
  data: ArrayBuffer
  /** Timestamp in milliseconds */
  timestamp: number
  /** Sequence number (increments with each packet) */
  sequenceNumber: number
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
