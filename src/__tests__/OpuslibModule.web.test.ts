import type { AudioConfig } from '../Opuslib.types'
import OpuslibWeb from '../OpuslibModule.web'

const UNSUPPORTED =
  'Opuslib is not supported on web platform. Use iOS or Android.'

const config: AudioConfig = {
  sampleRate: 16000,
  channels: 1,
  bitrate: 24000,
  frameSize: 20,
  packetDuration: 100,
}

describe('OpuslibModule (web stub)', () => {
  it('rejects startStreaming with the unsupported-platform error', async () => {
    await expect(OpuslibWeb.startStreaming(config)).rejects.toThrow(UNSUPPORTED)
  })

  it('rejects stopStreaming with the unsupported-platform error', async () => {
    await expect(OpuslibWeb.stopStreaming()).rejects.toThrow(UNSUPPORTED)
  })

  it('throws synchronously from pauseStreaming', () => {
    expect(() => OpuslibWeb.pauseStreaming()).toThrow(UNSUPPORTED)
  })

  it('throws synchronously from resumeStreaming', () => {
    expect(() => OpuslibWeb.resumeStreaming()).toThrow(UNSUPPORTED)
  })

  it('returns removable no-op subscriptions from every listener', () => {
    const subscriptions = [
      OpuslibWeb.addListener(),
      OpuslibWeb.addAmplitudeListener(),
      OpuslibWeb.addAudioStartedListener(),
      OpuslibWeb.addAudioEndListener(),
      OpuslibWeb.addErrorListener(),
    ]
    for (const sub of subscriptions) {
      expect(typeof sub.remove).toBe('function')
      expect(() => sub.remove()).not.toThrow()
    }
  })
})
