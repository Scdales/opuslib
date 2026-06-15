import Opuslib from '../index'

// The public entry point re-exports the native-backed module, so `expo` must be
// mocked before it loads. `jest.mock` is hoisted above the import by babel-jest.
jest.mock('expo', () => ({
  NativeModule: class NativeModule {},
  requireNativeModule: jest.fn(() => ({
    startStreaming: jest.fn().mockResolvedValue(undefined),
    stopStreaming: jest.fn().mockResolvedValue(undefined),
    pauseStreaming: jest.fn(),
    resumeStreaming: jest.fn(),
  })),
  EventEmitter: jest.fn(() => ({
    addListener: jest.fn(() => ({ remove: jest.fn() })),
  })),
}))

describe('package entry point', () => {
  it('default-exports the full public API surface', () => {
    expect(typeof Opuslib.startStreaming).toBe('function')
    expect(typeof Opuslib.stopStreaming).toBe('function')
    expect(typeof Opuslib.pauseStreaming).toBe('function')
    expect(typeof Opuslib.resumeStreaming).toBe('function')
    expect(typeof Opuslib.addListener).toBe('function')
    expect(typeof Opuslib.addAmplitudeListener).toBe('function')
    expect(typeof Opuslib.addErrorListener).toBe('function')
  })
})
