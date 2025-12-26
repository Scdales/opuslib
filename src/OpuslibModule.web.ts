import type { AudioConfig } from './Opuslib.types'

/**
 * Web implementation of Opuslib (placeholder)
 *
 * Note: Web implementation requires WebRTC or WebAssembly Opus encoder
 * This is a stub for now - native platforms only
 */
export default {
  startStreaming: async (config: AudioConfig): Promise<void> => {
    throw new Error('Opuslib is not supported on web platform. Use iOS or Android.')
  },

  stopStreaming: async (): Promise<void> => {
    throw new Error('Opuslib is not supported on web platform. Use iOS or Android.')
  },

  pauseStreaming: (): void => {
    throw new Error('Opuslib is not supported on web platform. Use iOS or Android.')
  },

  resumeStreaming: (): void => {
    throw new Error('Opuslib is not supported on web platform. Use iOS or Android.')
  },

  addListener: () => ({
    remove: () => {}
  }),

  addAmplitudeListener: () => ({
    remove: () => {}
  }),

  addErrorListener: () => ({
    remove: () => {}
  }),
}
