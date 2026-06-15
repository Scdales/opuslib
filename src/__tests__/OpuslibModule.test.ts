import type { AudioConfig } from '../Opuslib.types'
// Imported here, but `jest.mock` below is hoisted above this import by
// babel-jest, so the mock is registered before the module loads.
import Opuslib from '../OpuslibModule'

// Mock the `expo` runtime so the module loads without a real native binary.
// The factory exposes the underlying mocks via `__` handles for assertions.
jest.mock('expo', () => {
  const nativeModule = {
    startStreaming: jest.fn().mockResolvedValue(undefined),
    stopStreaming: jest.fn().mockResolvedValue(undefined),
    pauseStreaming: jest.fn(),
    resumeStreaming: jest.fn(),
  }
  const subscription = { remove: jest.fn() }
  const addListener = jest.fn(() => subscription)
  return {
    NativeModule: class NativeModule {},
    requireNativeModule: jest.fn(() => nativeModule),
    EventEmitter: jest.fn(() => ({ addListener })),
    __nativeModule: nativeModule,
    __addListener: addListener,
    __subscription: subscription,
  }
})

const expoMock = jest.requireMock('expo') as {
  requireNativeModule: jest.Mock
  EventEmitter: jest.Mock
  __nativeModule: {
    startStreaming: jest.Mock
    stopStreaming: jest.Mock
    pauseStreaming: jest.Mock
    resumeStreaming: jest.Mock
  }
  __addListener: jest.Mock
  __subscription: { remove: jest.Mock }
}

const config: AudioConfig = {
  sampleRate: 16000,
  channels: 1,
  bitrate: 24000,
  frameSize: 20,
  packetDuration: 100,
}

describe('OpuslibModule (native wrapper)', () => {
  // `clearMocks` resets call records before each test, so re-load the module in
  // isolation to capture the module-load-time wiring fresh.
  it('loads the native module registered as "Opuslib"', () => {
    jest.isolateModules(() => {
      require('../OpuslibModule')
    })
    expect(expoMock.requireNativeModule).toHaveBeenCalledWith('Opuslib')
  })

  it('constructs an EventEmitter bound to the native module', () => {
    jest.isolateModules(() => {
      require('../OpuslibModule')
    })
    expect(expoMock.EventEmitter).toHaveBeenCalledTimes(1)
    expect(expoMock.EventEmitter).toHaveBeenCalledWith(expoMock.__nativeModule)
  })

  describe('streaming controls', () => {
    it('delegates startStreaming with the provided config', async () => {
      await Opuslib.startStreaming(config)
      expect(expoMock.__nativeModule.startStreaming).toHaveBeenCalledWith(
        config,
      )
    })

    it('returns the native startStreaming promise', async () => {
      await expect(Opuslib.startStreaming(config)).resolves.toBeUndefined()
    })

    it('delegates stopStreaming', async () => {
      await Opuslib.stopStreaming()
      expect(expoMock.__nativeModule.stopStreaming).toHaveBeenCalledTimes(1)
    })

    it('delegates pauseStreaming', () => {
      Opuslib.pauseStreaming()
      expect(expoMock.__nativeModule.pauseStreaming).toHaveBeenCalledTimes(1)
    })

    it('delegates resumeStreaming', () => {
      Opuslib.resumeStreaming()
      expect(expoMock.__nativeModule.resumeStreaming).toHaveBeenCalledTimes(1)
    })

    it('propagates native rejections from startStreaming', async () => {
      const failure = new Error('mic permission denied')
      expoMock.__nativeModule.startStreaming.mockRejectedValueOnce(failure)
      await expect(Opuslib.startStreaming(config)).rejects.toThrow(
        'mic permission denied',
      )
    })
  })

  describe('event subscriptions', () => {
    it('routes addListener to the emitter with the event name and listener', () => {
      const listener = jest.fn()
      const sub = Opuslib.addListener('audioChunk', listener)
      expect(expoMock.__addListener).toHaveBeenCalledWith(
        'audioChunk',
        listener,
      )
      expect(sub).toBe(expoMock.__subscription)
    })

    it('supports the amplitude and error events through addListener', () => {
      const amplitude = jest.fn()
      const error = jest.fn()
      Opuslib.addListener('amplitude', amplitude)
      Opuslib.addListener('error', error)
      expect(expoMock.__addListener).toHaveBeenCalledWith(
        'amplitude',
        amplitude,
      )
      expect(expoMock.__addListener).toHaveBeenCalledWith('error', error)
    })

    it('maps addAmplitudeListener to the "amplitude" event', () => {
      const listener = jest.fn()
      Opuslib.addAmplitudeListener(listener)
      expect(expoMock.__addListener).toHaveBeenCalledWith('amplitude', listener)
    })

    it('maps addErrorListener to the "error" event', () => {
      const listener = jest.fn()
      Opuslib.addErrorListener(listener)
      expect(expoMock.__addListener).toHaveBeenCalledWith('error', listener)
    })

    it('returns a subscription whose remove() is callable', () => {
      const sub = Opuslib.addErrorListener(jest.fn())
      sub.remove()
      expect(expoMock.__subscription.remove).toHaveBeenCalledTimes(1)
    })
  })
})
