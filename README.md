# opuslib

**Opus 1.6.1 audio encoding for React Native and Expo**

Real-time audio capture and encoding using the latest Opus 1.6.1 codec, built from source with full native integration for iOS and Android.

[![npm version](https://img.shields.io/npm/v/opuslib.svg)](https://www.npmjs.com/package/opuslib)
[![npm downloads](https://img.shields.io/npm/dm/opuslib.svg)](https://www.npmjs.com/package/opuslib)
[![License: MIT](https://img.shields.io/npm/l/opuslib.svg)](https://opensource.org/licenses/MIT)

---
## Story

Created as I had a need for real-time voice communication in a React Native app. Figured it could be useful to share with the community as it's a popular format for moving realtime audio over the internet!

---

## Features

- **Opus 1.6.1** - Latest codec version compiled from the [official source](https://opus-codec.org/downloads/)
- **Low Latency** - Real-time encoding with minimal overhead
- **Native Performance** - Direct C/C++ integration, no JavaScript encoding
- **Thread-safe encoding** - Capture and Opus encoding run on separate threads, so the real-time audio thread is never blocked
- **Audio level metering** - Optional per-frame level (0.0–1.0) via `enableAudioLevel`
- **Lifecycle events** - `audioStarted` / `audioEnd` with session metadata, plus flush-on-stop so no trailing audio is lost
- **High Quality** - 24kbps achieves excellent speech quality
- **Cross-Platform** - iOS and Android with a consistent API
- **Zero Dependencies** - Self-contained with vendored Opus source
- **Configurable** - Bitrate, sample rate, frame size, frame batching
- **Event-Based** - Stream encoded audio chunks via events

### Why Opus 1.6.1?

Opus is the gold standard for real-time voice applications:
- **Better compression** than AAC, MP3, or Vorbis at low bitrates
- **Lower latency** than other codecs (as low as 5ms)
- **Royalty-free** and open source
- **Internet standard** (RFC 6716) used by Discord, WhatsApp, WebRTC

---

## Installation

```bash
# Using npm
npm install opuslib

# Using yarn
yarn add opuslib

# Using pnpm
pnpm add opuslib
```

### Additional Setup

#### For Expo Projects

```bash
npx expo install opuslib
npx expo prebuild
```

#### For React Native CLI

```bash
# iOS
cd ios && pod install && cd ..

# Android - no additional steps needed
```

---

## Quick Start

```typescript
import Opuslib from 'opuslib';
import { Platform, PermissionsAndroid } from 'react-native';

// Request microphone permission (Android)
async function requestPermission() {
  if (Platform.OS === 'android') {
    const granted = await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.RECORD_AUDIO
    );
    return granted === PermissionsAndroid.RESULTS.GRANTED;
  }
  return true; // iOS handles permissions automatically
}

// Start recording and encoding
async function startRecording() {
  // Request permission
  const hasPermission = await requestPermission();
  if (!hasPermission) {
    console.error('Microphone permission denied');
    return;
  }

  // Listen for encoded audio chunks
  const subscription = Opuslib.addListener('audioChunk', (event) => {
    const { data, timestamp, sequenceNumber } = event;
    console.log(`Received ${data.byteLength} bytes of Opus audio`);

    // Send to your backend, save to file, etc.
    // data is an ArrayBuffer containing raw Opus packets (not packets you can write to an ogg)
  });

  // Start streaming
  await Opuslib.startStreaming({
    sampleRate: 16000,      // 16 kHz
    channels: 1,            // Mono
    bitrate: 24000,         // 24 kbps
    frameSize: 20,          // 20ms frames
    packetDuration: 100,    // 100ms packets (5 frames)
  });

  console.log('Recording started!');
}

// Stop recording
async function stopRecording() {
  await Opuslib.stopStreaming();
  console.log('Recording stopped');
}
```

---

## API Reference

### Methods

#### `startStreaming(config: AudioConfig): Promise<void>`

Start audio capture and Opus encoding.

**Parameters:**
```typescript
interface AudioConfig {
  sampleRate: number;               // Sample rate in Hz (8000, 16000, 24000, 48000)
  channels: number;                 // Number of channels (1 = mono, 2 = stereo)
  bitrate: number;                  // Target bitrate in bits/second (e.g., 24000)
  frameSize: number;                // Frame duration in ms (2.5, 5, 10, 20, 40, 60)
  packetDuration: number;           // Packet duration in ms (multiple of frameSize)
  framesPerCallback?: number;       // Opus frames batched per audioChunk event (default: 1)
  dredDuration?: number;            // Reserved for future DRED support (default: 0)
  enableAmplitudeEvents?: boolean;  // Enable amplitude monitoring (default: false)
  amplitudeEventInterval?: number;  // Amplitude update interval in ms (default: 16)
  enableAudioLevel?: boolean;       // Per-frame audio level (0.0-1.0) on each OpusFrame (default: false)
  saveDebugAudio?: boolean;         // Save raw PCM to a file for debugging (development only)
  iosAudioSession?: {               // iOS AVAudioSession config (iOS only; ignored elsewhere)
    category: 'record' | 'playAndRecord' | 'playback' | 'ambient';
    mode: 'default' | 'voiceChat' | 'measurement' | 'spokenAudio';
    options?: Array<'mixWithOthers' | 'defaultToSpeaker' | 'allowBluetooth' | 'allowAirPlay' | 'allowBluetoothA2DP'>;
  };
}
```

> **Backward compatibility:** `framesPerCallback`, `enableAudioLevel`, and
> `iosAudioSession` are all optional. Omitting them preserves the previous
> behavior (one Opus packet per `audioChunk`, no level metering, default iOS
> recording session).

**Recommended Settings for Speech:**
```typescript
{
  sampleRate: 16000,     // 16 kHz - optimal for speech
  channels: 1,           // Mono - sufficient for voice
  bitrate: 24000,        // 24 kbps - excellent quality
  frameSize: 20,         // 20ms - standard for real-time
  packetDuration: 100,   // 100ms - good balance of latency/efficiency
}
```

**Throws:** Error if already streaming or if microphone permission denied

---

#### `stopStreaming(): Promise<void>`

Stop audio capture and encoding, release resources.

---

#### `pauseStreaming(): void`

Pause audio capture (keeps resources allocated). Call `resumeStreaming()` to continue.

---

#### `resumeStreaming(): void`

Resume audio capture after calling `pauseStreaming()`.

---

### Events

#### `audioChunk`

Emitted when an encoded Opus packet is ready.

```typescript
Opuslib.addListener('audioChunk', (event: AudioChunkEvent) => {
  // event.data: ArrayBuffer - First frame's Opus packet (back-compat; = frames[0].data)
  // event.frames: OpusFrame[] - Independent Opus packets (one per encoded frame)
  // event.timestamp: number - Capture timestamp in milliseconds
  // event.sequenceNumber: number - Event sequence number (starts at 0)
  // event.duration: number - Total duration in ms (frameSize * frameCount)
  // event.frameCount: number - Number of frames in this event

  // Each frame is an independent, decodable Opus packet:
  for (const frame of event.frames) {
    websocket.send(frame.data);
    // frame.audioLevel?: number - present only when enableAudioLevel is true
  }
});
```

**Event Data:**
```typescript
interface OpusFrame {
  data: ArrayBuffer;         // Independent Opus packet (one opus_encode() output, own TOC byte)
  audioLevel?: number;       // Per-frame level 0.0-1.0 (only when enableAudioLevel is true)
}

interface AudioChunkEvent {
  data: ArrayBuffer;         // First frame's packet — kept for backward compatibility (= frames[0].data)
  frames: OpusFrame[];       // Independent Opus packets (single entry unless framesPerCallback > 1)
  timestamp: number;         // Milliseconds since epoch
  sequenceNumber: number;    // Incrementing event counter
  duration: number;          // Total duration in ms (frameSize * frameCount)
  frameCount: number;        // Number of Opus frames (= frames.length)
}
```

> With the default `framesPerCallback` of 1, `frames` has a single entry and
> `data === frames[0].data`, so existing `event.data` consumers are unaffected.
> Frames are **never** concatenated — each is independently decodable.

---

#### `audioStarted`

Emitted once when streaming starts. Carries the active config and the Opus
encoder `preSkip` (lookahead) so a decoder knows how many samples to skip at the
beginning of the stream.

```typescript
Opuslib.addAudioStartedListener((event: AudioStartedEvent) => {
  console.log(`Started: ${event.sampleRate}Hz, preSkip=${event.preSkip}`);
});
// or: Opuslib.addListener('audioStarted', (event) => { ... })
```

**Event Data:**
```typescript
interface AudioStartedEvent {
  timestamp: number;   // Milliseconds since epoch
  sampleRate: number;  // Actual sample rate in Hz
  channels: number;    // Number of channels
  bitrate: number;     // Configured bitrate in bits/second
  frameSize: number;   // Frame duration in milliseconds
  preSkip: number;     // Encoder lookahead in samples (decoder should skip these)
}
```

---

#### `audioEnd`

Emitted once when streaming stops, after the final buffered audio has been
flushed (the trailing partial frame is padded with silence so no audio is lost).

```typescript
Opuslib.addAudioEndListener((event: AudioEndEvent) => {
  console.log(`Ended: ${event.totalDuration}ms, ${event.totalPackets} packets`);
});
// or: Opuslib.addListener('audioEnd', (event) => { ... })
```

**Event Data:**
```typescript
interface AudioEndEvent {
  timestamp: number;       // Milliseconds since epoch
  totalDuration: number;   // Total session duration in milliseconds
  totalPackets: number;    // Total audioChunk events emitted during the session
}
```

---

#### `amplitude`

Emitted periodically with audio amplitude data (requires `enableAmplitudeEvents: true`).

```typescript
Opuslib.addAmplitudeListener((event: AmplitudeEvent) => {
  // event.rms: number - Root mean square amplitude (0.0 - 1.0)
  // event.peak: number - Peak amplitude (0.0 - 1.0)
  // event.timestamp: number - Milliseconds since epoch
});
```

**Event Data:**
```typescript
interface AmplitudeEvent {
  rms: number;       // RMS amplitude (useful for average volume)
  peak: number;      // Peak amplitude (useful for clipping detection)
  timestamp: number; // Milliseconds since epoch
}
```

---

#### `error`

Emitted when an error occurs during recording.

```typescript
Opuslib.addErrorListener((event: ErrorEvent) => {
  console.error(`Error: ${event.message}`);
});
```

**Event Data:**
```typescript
interface ErrorEvent {
  code: string;      // Error code (e.g., "AUDIO_RECORD_ERROR")
  message: string;   // Human-readable error message
}
```

---

## Platform Notes

### iOS

- **Minimum iOS Version:** 15.1+
- **Audio Session:** Defaults to the `record` category with `measurement` mode (pure recording, system audio processing disabled). Override it per-session with the optional `iosAudioSession` config — e.g. for simultaneous playback or Bluetooth/speaker routing:
  ```typescript
  await Opuslib.startStreaming({
    sampleRate: 24000, channels: 1, bitrate: 24000, frameSize: 20, packetDuration: 100,
    iosAudioSession: {
      category: 'playAndRecord',           // record + play at the same time
      mode: 'default',                     // enable AGC / echo cancellation
      options: ['defaultToSpeaker', 'allowBluetooth'],
    },
  });
  ```

  | `category` | Behavior |
  |------------|----------|
  | `record` | Pure recording (default) |
  | `playAndRecord` | Record and play simultaneously |
  | `playback` | Playback only |
  | `ambient` | Mix with other audio without interrupting it |

  | `mode` | Behavior |
  |--------|----------|
  | `measurement` | Disable system audio processing (default) |
  | `default` | Enable AGC, echo cancellation, etc. |
  | `voiceChat` | Optimized for voice calls |
  | `spokenAudio` | Optimized for spoken content |

  | `options[]` | Behavior |
  |-------------|----------|
  | `mixWithOthers` | Allow mixing with other audio apps |
  | `defaultToSpeaker` | Route to speaker instead of earpiece |
  | `allowBluetooth` | Allow Bluetooth HFP devices |
  | `allowAirPlay` | Allow AirPlay output |
  | `allowBluetoothA2DP` | Allow Bluetooth A2DP (high-quality audio) |
- **Permissions:** Add to `app.json`:
  ```json
  {
    "expo": {
      "ios": {
        "infoPlist": {
          "NSMicrophoneUsageDescription": "This app needs microphone access to record audio."
        }
      }
    }
  }
  ```

### Android

- **Minimum SDK:** API 24 (Android 7.0)
- **Permissions:** Automatically added to manifest, request at runtime:
  ```typescript
  import { PermissionsAndroid } from 'react-native';

  const granted = await PermissionsAndroid.request(
    PermissionsAndroid.PERMISSIONS.RECORD_AUDIO
  );
  ```

---

## Performance

Benchmarks on iPhone 14 Pro and Pixel 7:

| Metric | iOS | Android |
|--------|-----|---------|
| Encoding Latency | <2ms per 20ms frame | <3ms per 20ms frame |
| CPU Usage | ~2% (single core) | ~3% (single core) |
| Memory Usage | ~5MB | ~8MB |
| Battery Impact | Minimal | Minimal |

*Note: Performance may vary based on device and configuration*

---

## Troubleshooting

### iOS: "Microphone permission not granted"

Add `NSMicrophoneUsageDescription` to your `Info.plist` or `app.json`:

```json
{
  "expo": {
    "ios": {
      "infoPlist": {
        "NSMicrophoneUsageDescription": "We need microphone access to record audio."
      }
    }
  }
}
```

### Android: "Microphone permission not granted"

Request permission at runtime:

```typescript
import { PermissionsAndroid, Platform } from 'react-native';

if (Platform.OS === 'android') {
  await PermissionsAndroid.request(
    PermissionsAndroid.PERMISSIONS.RECORD_AUDIO
  );
}
```

### Build Errors on iOS

Clean and reinstall pods:

```bash
cd ios
rm -rf Pods Podfile.lock opus-build
pod install
cd ..
```

### Build Errors on Android

Clean Gradle caches:

```bash
cd android
./gradlew clean
rm -rf .cxx build
cd ..
```

---

## Technical Details

Capture and encoding run on **separate threads**. The capture thread only reads
PCM, converts it, and copies the samples onto a dedicated serial encoding
thread; all Opus encoder state and `opus_encode()` calls happen there. This
keeps the real-time audio thread unblocked and avoids encoding on it.

```
Capture thread                      Encoding thread (serial)
  |  read PCM (AVAudioEngine / AudioRecord)
  |  convert + copy ----- post ----> append to pending buffer
  |                                  while (>= one frame) opus_encode() -> frame
  |                                  per-frame audioLevel (if enabled)
  |                                  batch framesPerCallback -> emit audioChunk
  |  (stop) ------------- flush ---> pad silence + encode tail -> emit audioEnd
```

**iOS:**
- AVAudioEngine for audio capture (48kHz PCM)
- Custom resampler (48kHz → 16kHz)
- Dedicated serial `DispatchQueue` for Opus encoding and event dispatch
- Opus 1.6.1 encoder (native C via Swift)
- Objective-C wrapper for CTL operations
- Event emission via Expo modules

**Android:**
- AudioRecord for audio capture (16kHz PCM)
- Dedicated `HandlerThread` for Opus encoding and event dispatch
- JNI wrapper for Opus 1.6.1 C library
- Event emission via Expo modules

### Opus Build Configuration

The module compiles Opus 1.6.1 from source with the following CMake flags:

```cmake
-DCMAKE_BUILD_TYPE=Release
-DOPUS_DRED=OFF                    # DRED disabled (future feature)
-DOPUS_BUILD_SHARED_LIBRARY=OFF    # Static linking
-DOPUS_BUILD_TESTING=OFF           # No tests
-DOPUS_BUILD_PROGRAMS=OFF          # No CLI tools
```

**iOS:** Built as universal binary (arm64 + x86_64) for device and simulator
**Android:** Built for arm64-v8a, armeabi-v7a, and x86_64

---

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting PRs.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/scdales/opuslib.git
cd opuslib

# Install dependencies
npm install

# Build TypeScript
npm run build

# Run example app
cd example
npm install
npx expo run:ios    # or run:android
```

### Running Tests

```bash
npm test
```

---

## License

MIT License - see [LICENSE](LICENSE) file for details

---

## Credits

- **Opus Codec** - [opus-codec.org](https://opus-codec.org/)
- **Expo Modules** - [docs.expo.dev](https://docs.expo.dev/modules/)

---

## Support

- 📧 **Email:** `opuslib@outlook.com`
- 🐛 **Issues:** [GitHub Issues](https://github.com/scdales/opuslib/issues)
- 💬 **Discussions:** [GitHub Discussions](https://github.com/scdales/opuslib/discussions)

---

## Acknowledgments

Special thanks to the Opus development team for creating an exceptional codec, and the Expo team for their awesome module framework.
