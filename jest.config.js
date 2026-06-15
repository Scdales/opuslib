// Unit tests cover the JavaScript/TypeScript wrapper only. The native Opus
// encoders (Swift / Kotlin / C) are exercised manually on-device — see
// docs/MAINTAINING.md. The iOS preset uses native platform resolution so
// `./OpuslibModule` resolves to the native-backed source rather than the
// `.web` stub (the web suite imports the `.web` file explicitly).
const nativePreset = require('jest-expo/ios/jest-preset')

module.exports = {
  ...nativePreset,
  rootDir: '.',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  clearMocks: true,
}
