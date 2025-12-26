# Contributing to opuslib

First off, thank you for considering contributing to opuslib! It's people like you that make opuslib such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When you create a bug report, include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples** (code snippets, logs, etc.)
- **Describe the behavior you observed and what you expected**
- **Include details about your environment:**
  - opuslib version
  - React Native version
  - Expo SDK version (if applicable)
  - iOS/Android version
  - Device model

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion:

- **Use a clear and descriptive title**
- **Provide a detailed description of the proposed functionality**
- **Explain why this enhancement would be useful**
- **List any alternative solutions you've considered**

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Follow the development setup** instructions below
3. **Make your changes:**
   - Write clear, concise commit messages
   - Follow the existing code style
   - Add tests if applicable
   - Update documentation if needed
4. **Test your changes** on both iOS and Android
5. **Submit a pull request** with a clear description of your changes

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/opuslib.git
cd opuslib

# Install dependencies
npm install

# Build TypeScript
npm run build

# Run the example app
cd example
npm install
npx expo run:ios    # Test on iOS
npx expo run:android # Test on Android
```

## Development Workflow

### Building the Module

```bash
npm run build        # Build TypeScript
npm run clean        # Clean build artifacts
npm run lint         # Run ESLint
```

### Testing Changes

1. Make changes to the native code or TypeScript
2. Rebuild the module: `npm run build`
3. Test in the example app:
   ```bash
   cd example
   npx expo run:ios --no-build-cache
   ```

### Native Development

**iOS:**
```bash
# Open Xcode project
npm run open:ios

# Clean build
cd ios
rm -rf Pods Podfile.lock opus-build
pod install
```

**Android:**
```bash
# Open Android Studio
npm run open:android

# Clean build
cd android
./gradlew clean
rm -rf .cxx build
```

## Project Structure

```
opuslib/
├── src/               # TypeScript source
├── ios/               # iOS native module
│   ├── Opuslib.swift  # Main Swift implementation
│   └── OpusCWrapper.m # Objective-C wrapper for Opus CTL
├── android/           # Android native module
│   └── src/main/      # Kotlin/Java source
├── opus-1.6/          # Vendored Opus 1.6 source
└── example/           # Example React Native app
```

## Coding Standards

### TypeScript

- Use TypeScript for all new code
- Follow the existing code style
- Run `npm run lint` before committing
- Add JSDoc comments for public APIs

### Native Code

**iOS (Swift):**
- Follow Swift naming conventions
- Use Swift 5.9+ features where appropriate
- Add comments for complex logic
- Handle errors gracefully

**Android (Kotlin):**
- Follow Kotlin coding conventions
- Use coroutines for async operations
- Add KDoc comments for public APIs
- Handle exceptions appropriately

## Commit Messages

Write clear, concise commit messages:

```
Add support for DRED duration configuration

- Add dredDuration parameter to AudioConfig
- Update iOS encoder to pass DRED settings
- Add Android JNI wrapper for DRED CTL
- Update documentation
```

Format:
- First line: Short summary (50 chars or less)
- Blank line
- Detailed description (wrap at 72 chars)
- Reference issues: `Fixes #123` or `Closes #456`

## Testing

While we don't currently have automated tests, please manually test your changes:

- **Both platforms:** Test on iOS and Android
- **Multiple devices:** Test on different device models if possible
- **Edge cases:** Test error conditions, permission denials, etc.
- **Memory/Performance:** Check for leaks or performance issues

## Documentation

Update documentation when you make changes:

- **README.md:** Update API docs for new features
- **Code comments:** Add/update inline documentation
- **TypeScript types:** Keep type definitions accurate
- **Example app:** Update if you add new functionality

## Release Process

Maintainers handle releases:

1. Update version in `package.json`
2. Update CHANGELOG (if we add one)
3. Create git tag: `git tag v0.x.x`
4. Push tag: `git push --tags`
5. Publish to npm: `npm publish`

## Getting Help

- **Questions?** Open a [GitHub Discussion](https://github.com/scdales/opuslib/discussions)
- **Bug reports:** Create a [GitHub Issue](https://github.com/scdales/opuslib/issues)
- **Email:** Contact the maintainer at `opuslib@outlook.com`

## Recognition

Contributors will be recognized in:
- GitHub contributors list
- Future CHANGELOG entries
- Release notes

Thank you for contributing to opuslib!
