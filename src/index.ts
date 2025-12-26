/**
 * Opuslib - Opus 1.6 Audio Encoding with DRED Support
 *
 * Native audio capture and Opus 1.6 encoding for React Native/Expo
 * with Deep Redundancy (DRED) for improved quality on lossy networks.
 *
 * @example
 * ```ts
 * import Opuslib from 'opuslib'
 *
 * // Start streaming with DRED enabled
 * await Opuslib.startStreaming({
 *   sampleRate: 16000,
 *   channels: 1,
 *   bitrate: 24000,
 *   frameSize: 20,
 *   packetDuration: 20,
 *   dredDuration: 100, // 100ms DRED recovery
 * })
 *
 * // Listen for Opus packets
 * Opuslib.addListener('audioChunk', (event) => {
 *   // Send to backend
 *   websocket.send(event.data)
 * })
 *
 * // Stop streaming
 * await Opuslib.stopStreaming()
 * ```
 */
export { default } from './OpuslibModule'
export * from './Opuslib.types'
