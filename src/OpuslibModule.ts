import { NativeModule, requireNativeModule, EventEmitter } from 'expo'

import type {
  AudioConfig,
  AudioChunkEvent,
  AmplitudeEvent,
  AudioStartedEvent,
  AudioEndEvent,
  ErrorEvent,
  Subscription,
} from './Opuslib.types'

/**
 * Opuslib Native Module Interface
 *
 * Provides native audio capture and Opus 1.6.1 encoding with DRED support
 */
declare class OpuslibModuleType extends NativeModule {
  /**
   * Start audio streaming with Opus encoding
   * @param config Audio configuration
   */
  startStreaming(config: AudioConfig): Promise<void>

  /**
   * Stop audio streaming
   */
  stopStreaming(): Promise<void>

  /**
   * Pause audio streaming (keeps resources allocated)
   */
  pauseStreaming(): void

  /**
   * Resume audio streaming
   */
  resumeStreaming(): void
}

// Load the native module from JSI
const OpuslibModule = requireNativeModule<OpuslibModuleType>('Opuslib')

// Create event emitter for listening to events
const emitter = new EventEmitter(OpuslibModule as any)

/**
 * Opuslib - Opus 1.6.1 Audio Encoding with DRED Support
 *
 * This module provides real-time audio capture and Opus 1.6.1 encoding
 * with Deep Redundancy (DRED) for improved quality on lossy networks.
 */
export default {
  /**
   * Start audio streaming with Opus encoding
   *
   * @param config Audio configuration
   * @example
   * ```ts
   * await Opuslib.startStreaming({
   *   sampleRate: 16000,
   *   channels: 1,
   *   bitrate: 24000,
   *   frameSize: 20,
   *   packetDuration: 20,
   *   dredDuration: 100, // Enable 100ms DRED recovery
   * })
   * ```
   */
  startStreaming: (config: AudioConfig) => OpuslibModule.startStreaming(config),

  /**
   * Stop audio streaming and release resources
   */
  stopStreaming: () => OpuslibModule.stopStreaming(),

  /**
   * Pause audio streaming (keeps resources allocated)
   */
  pauseStreaming: () => OpuslibModule.pauseStreaming(),

  /**
   * Resume audio streaming
   */
  resumeStreaming: () => OpuslibModule.resumeStreaming(),

  /**
   * Listen for events (audioChunk, amplitude, or error)
   *
   * @param eventName Event type to listen for
   * @param listener Event listener callback
   * @returns Subscription object with remove() method
   * @example
   * ```ts
   * // Listen for audio chunks
   * const subscription = Opuslib.addListener('audioChunk', (event) => {
   *   console.log('Received Opus packet:', event.data.byteLength, 'bytes')
   *   websocket.send(event.data)
   * })
   *
   * // Listen for session lifecycle
   * Opuslib.addListener('audioStarted', (event) => {
   *   console.log('Started; decoder pre-skip:', event.preSkip)
   * })
   * Opuslib.addListener('audioEnd', (event) => {
   *   console.log(`Ended: ${event.totalPackets} packets in ${event.totalDuration}ms`)
   * })
   *
   * // Listen for errors
   * const errorSub = Opuslib.addListener('error', (event) => {
   *   console.error('Error:', event.message)
   * })
   *
   * // Later: unsubscribe
   * subscription.remove()
   * errorSub.remove()
   * ```
   */
  addListener: ((
    eventName:
      | 'audioChunk'
      | 'amplitude'
      | 'audioStarted'
      | 'audioEnd'
      | 'error',
    listener: (
      event:
        | AudioChunkEvent
        | AmplitudeEvent
        | AudioStartedEvent
        | AudioEndEvent
        | ErrorEvent,
    ) => void,
  ): Subscription => (emitter as any).addListener(eventName, listener)) as {
    (
      eventName: 'audioChunk',
      listener: (event: AudioChunkEvent) => void,
    ): Subscription
    (
      eventName: 'amplitude',
      listener: (event: AmplitudeEvent) => void,
    ): Subscription
    (
      eventName: 'audioStarted',
      listener: (event: AudioStartedEvent) => void,
    ): Subscription
    (
      eventName: 'audioEnd',
      listener: (event: AudioEndEvent) => void,
    ): Subscription
    (eventName: 'error', listener: (event: ErrorEvent) => void): Subscription
  },

  /**
   * Listen for amplitude events (for waveform visualization)
   *
   * @param listener Event listener callback
   * @returns Subscription object with remove() method
   */
  addAmplitudeListener: (
    listener: (event: AmplitudeEvent) => void,
  ): Subscription => (emitter as any).addListener('amplitude', listener),

  /**
   * Listen for the `audioStarted` event, emitted once when streaming begins.
   * Carries the active config and the Opus encoder `preSkip` (lookahead) so a
   * decoder knows how many samples to skip at the start of the stream.
   *
   * @param listener Event listener callback
   * @returns Subscription object with remove() method
   */
  addAudioStartedListener: (
    listener: (event: AudioStartedEvent) => void,
  ): Subscription => (emitter as any).addListener('audioStarted', listener),

  /**
   * Listen for the `audioEnd` event, emitted once when streaming stops (after
   * the final buffered audio has been flushed). Carries the session summary.
   *
   * @param listener Event listener callback
   * @returns Subscription object with remove() method
   */
  addAudioEndListener: (
    listener: (event: AudioEndEvent) => void,
  ): Subscription => (emitter as any).addListener('audioEnd', listener),

  /**
   * Listen for error events
   *
   * @param listener Event listener callback
   * @returns Subscription object with remove() method
   */
  addErrorListener: (listener: (event: ErrorEvent) => void): Subscription =>
    (emitter as any).addListener('error', listener),
}
