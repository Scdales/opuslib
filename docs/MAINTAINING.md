# Maintaining opuslib

> Internal maintainer documentation. **Not published to npm** (excluded via `.npmignore`).
> User-facing docs live in `README.md`; contributor docs in `CONTRIBUTING.md`.

## What this project is

`opuslib` is an [Expo module](https://docs.expo.dev/modules/) that provides
real-time microphone capture and [Opus](https://opus-codec.org/) 1.6 audio
encoding for React Native and Expo apps on iOS and Android.

The defining characteristic of this package is that it **vendors the full Opus
1.6 C source tree** (`opus-1.6.1/`) and **compiles it from source at install /
build time** on each platform. There is no precompiled binary and no runtime
dependency on a system Opus library — the consuming app builds Opus as a static
library as part of its native build.

- **iOS:** the CocoaPods `prepare_command` in `ios/Opuslib.podspec` runs CMake
  against `opus-1.6.1/`, builds `libopus.a` into `ios/opus-build/`, and links it
  statically. Audio is captured with `AVAudioEngine` at 48 kHz and resampled.
- **Android:** `android/build.gradle` drives a CMake build
  (`android/src/main/cpp/CMakeLists.txt`) that compiles Opus via the NDK for
  `arm64-v8a`, `armeabi-v7a`, and `x86_64`, reached from Kotlin through a JNI
  wrapper (`opus_jni_wrapper.cpp`). Audio is captured with `AudioRecord`.
- **JS/TS:** the public API is a thin wrapper over the native module
  (`src/OpuslibModule.ts`) plus shared types (`src/Opuslib.types.ts`). The web
  target is a stub.

The API surface is intentionally small: `startStreaming(config)`,
`stopStreaming()`, `pauseStreaming()`, `resumeStreaming()`, and three event
streams — `audioChunk` (raw Opus packets), `amplitude` (RMS/peak for
visualization), and `error`.

> **DRED note:** the types and docs reference Deep Redundancy (DRED), but it is
> currently **disabled** in both native builds (`-DOPUS_DRED=OFF`). The
> `dredDuration` config field is reserved for future use. Keep marketing/docs
> honest about this until DRED is actually wired up.

## Repository layout

```
opuslib/
├── src/                  # TypeScript: public API + types (published as build/)
├── ios/                  # Swift module, Obj-C CTL helpers, podspec (source build)
├── android/              # Kotlin module + C++/JNI wrapper, CMake, gradle
├── opus-1.6.1/             # Vendored Opus 1.6 source — compiled per platform
├── example/              # Local Expo app for manual testing (NOT published)
├── build/                # Compiled TS output (generated; published, gitignored)
├── README.md             # User-facing documentation (published)
├── CONTRIBUTING.md       # Contributor guide (published)
├── CODE_OF_CONDUCT.md    # (published)
└── docs/                 # Internal maintainer docs (NOT published)
```

## Toolchain

- **Node:** pinned in `.nvmrc` (currently `v20.19.4`). Run `nvm use` first.
- **Build scripts:** all driven by `expo-module-scripts` via `package.json`:
  - `npm run build` — compile TypeScript to `build/`
  - `npm run clean` — remove build artifacts
  - `npm run lint` — ESLint (config in `.eslintrc.js`)
  - `npm test` — Jest via expo-module (no test suite exists yet)
  - `npm run prepare` / `prepublishOnly` — run automatically around publish
- **iOS native:** Xcode 15+, CMake (for the Opus source build), CocoaPods.
- **Android native:** Android Studio, NDK, CMake 3.22.1 (per `build.gradle`).

## Local development

```bash
nvm use
npm install
npm run build

cd example
npm install
npx expo run:ios       # or: npx expo run:android
```

Because the native side compiles Opus from source, native changes require a full
rebuild. After editing native code:

```bash
# iOS
npm run open:ios
cd ios && rm -rf Pods Podfile.lock opus-build && pod install

# Android
npm run open:android
cd android && ./gradlew clean && rm -rf .cxx build
```

`npm test` runs a Jest unit suite (`src/__tests__/`) over the JS/TS wrapper —
native-module delegation, event-subscription routing, and the web stub. It runs
under the `jest-expo/ios` preset (native platform resolution) with `expo`
mocked, so no native binary or device is required; config lives in
`jest.config.js` + `babel.config.js`.

The native encoders (Swift/Kotlin/C) cannot run under Jest, so **manual
verification on both physical iOS and Android devices remains the release gate
for native changes** — check capture starts, `audioChunk` packets arrive with
incrementing `sequenceNumber`, pause/resume work, and permission-denied paths
emit an `error` event rather than crashing.

## What gets published vs. what doesn't

`.npmignore` controls the npm tarball. The published package deliberately
**includes** the vendored `opus-1.6.1/` source (the build depends on it) along
with `src/`, `build/`, `ios/`, `android/`, the podspec, and user-facing docs.

It deliberately **excludes**:

- `example/` — the local test app
- `docs/` — internal/maintainer material
- all top-level hidden directories (`/.*/`), tarballs, test dirs, babel config

Always run `npm pack --dry-run` before publishing and read the file list. The
vendored Opus tree is large; confirm nothing unexpected (or anything from the
"excluded" list) leaked in.

## Versioning & release

Releases are maintainer-only and currently manual. The version lives in
`package.json` and is read by the iOS podspec; the Android `versionName` /
`versionCode` in `build.gradle` are tracked separately — keep them in sync when
cutting a release.

```bash
nvm use
npm run lint
npm run build
npm pack --dry-run          # audit the tarball contents

# bump version in package.json (and android/build.gradle if releasing native)
git tag v0.x.x
git push --tags
npm publish                 # prepare / prepublishOnly run automatically
```

Consider adding a `CHANGELOG.md` (referenced as a TODO in `CONTRIBUTING.md`) and
keeping `android/build.gradle` versions aligned with `package.json` as part of
this checklist.

## Upgrading Opus

To move to a newer Opus release:

1. Replace the `opus-1.6.1/` tree with the new official source (and rename the
   directory + every path that references it: podspec, `CMakeLists.txt`,
   gradle).
2. Re-verify the CMake flags (`OPUS_DRED`, `OPUS_BUILD_SHARED_LIBRARY`,
   `OPUS_BUILD_TESTING`, `OPUS_BUILD_PROGRAMS`) still exist and behave the same.
3. Rebuild and re-run the full manual device check on both platforms — the C ABI
   surface used by the JNI/Swift wrappers can shift between releases.
4. Update the version references in `README.md` and `src/index.ts` doc comments.

## Key files when debugging

- `ios/OpusEncoder.swift`, `ios/AudioEngineManager.swift` — capture + encode loop
- `ios/opus_ctl_helpers.c` / `.h`, `ios/OpusCtlHelpers.m` — Opus CTL bridging
- `android/.../OpusEncoder.kt`, `AudioRecordManager.kt` — capture + encode loop
- `android/src/main/cpp/opus_jni_wrapper.cpp` — JNI ↔ Opus C boundary
- `src/Opuslib.types.ts` — the contract shared across all platforms
