# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/).

## [0.2.0]

This release is **fully backward compatible** — everything below is additive.
Existing code keeps working unchanged: `audioChunk` events still carry `data`,
and all the new config fields are optional.

### Fixed

- **Encoding no longer runs on the real-time audio thread.** Capture and Opus
  encoding now run on separate threads — the capture callback only converts and
  copies PCM, then hands it to a dedicated serial encoding thread that owns all
  encoder state. This removes the iOS crash that could occur when encoding on
  the audio render thread, and keeps the real-time audio path unblocked.
  (iOS: a serial `DispatchQueue`; Android: a `HandlerThread`.)
- **Flush on stop.** When you call `stopStreaming()`, any buffered tail of audio
  is padded with silence, encoded, and emitted before teardown — so the end of a
  session is no longer dropped.

### Added

- **`audioStarted` event** — fired once when streaming begins, from the encoding
  thread. Includes the active config and the Opus encoder `preSkip`
  (`OPUS_GET_LOOKAHEAD`) so a decoder knows how many samples to skip at the start
  of the stream.
- **`audioEnd` event** — fired once when streaming stops (after the flush above),
  with a session summary (`totalDuration`, `totalPackets`).
- **`framesPerCallback` config** — batch N independently-encoded Opus frames into
  a single `audioChunk` event to reduce bridge calls. Defaults to `1`.
- **`audioChunk.frames` / `duration` / `frameCount`** — `frames` is an array of
  independent, individually-decodable Opus packets (each with its own TOC byte;
  never concatenated). `audioChunk.data` is retained and equals `frames[0].data`.
- **`enableAudioLevel` config + `OpusFrame.audioLevel`** — opt-in per-frame audio
  level in `0.0–1.0` (RMS mapped through dBFS). Off by default.
- **`iosAudioSession` config (iOS only)** — customize the `AVAudioSession`
  category / mode / options (e.g. `playAndRecord`, `defaultToSpeaker`,
  `allowBluetooth`). Ignored on Android and web; omit to keep the default
  recording session.
- New helper methods `addAudioStartedListener()` and `addAudioEndListener()`,
  plus `audioStarted` / `audioEnd` overloads on `addListener()`.
- New exported types: `OpusFrame`, `AudioStartedEvent`, `AudioEndEvent`,
  `IOSAudioSessionConfig`.

### How to use the new features

```typescript
import Opuslib from 'opuslib'

// Lifecycle events
Opuslib.addAudioStartedListener((e) => {
  // e.preSkip — samples a decoder should skip at the start of the stream
  console.log(`started @ ${e.sampleRate}Hz, preSkip=${e.preSkip}`)
})
Opuslib.addAudioEndListener((e) => {
  console.log(`ended: ${e.totalPackets} packets over ${e.totalDuration}ms`)
})

// Per-frame audio level + frame batching
Opuslib.addListener('audioChunk', (e) => {
  // e.data still works (back-compat) === e.frames[0].data
  for (const frame of e.frames) {
    websocket.send(frame.data)        // each frame is an independent Opus packet
    meter(frame.audioLevel)           // present only when enableAudioLevel: true
  }
})

await Opuslib.startStreaming({
  sampleRate: 16000,
  channels: 1,
  bitrate: 24000,
  frameSize: 20,
  packetDuration: 100,
  framesPerCallback: 5,   // 5 independent frames per audioChunk (80% fewer bridge calls)
  enableAudioLevel: true, // populate frame.audioLevel
  // iOS-only: record + play, route to speaker
  iosAudioSession: {
    category: 'playAndRecord',
    mode: 'default',
    options: ['defaultToSpeaker', 'allowBluetooth'],
  },
})
```

### Migration notes

Nothing is required. To adopt the new behavior:

- Reading `event.data` keeps working. To consume batched frames, switch to
  iterating `event.frames` (with `framesPerCallback: 1`, the default, `frames`
  has exactly one entry equal to `data`).
- `framesPerCallback` supersedes `packetDuration` for deciding how many frames
  are grouped per event. `packetDuration` remains accepted for compatibility.

## [0.1.4]

### Changed

- Updated the vendored Opus codec from 1.6 to **1.6.1**.

## [0.1.2]

- Earlier published releases. See the Git history for details.
