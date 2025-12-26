require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'Opuslib'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platforms      = {
    :ios => '15.1',
    :tvos => '15.1'
  }
  s.swift_version  = '5.9'
  s.source         = { git: 'https://github.com/Scdales/opuslib' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # Compile Opus 1.6 with DRED enabled using CMake
  s.prepare_command = <<-CMD
    set -e
    echo "Building Opus 1.6 with DRED support for iOS..."
    echo "Working directory: $(pwd)"

    # Create build directory (we're already in ios/)
    mkdir -p opus-build
    cd opus-build

    # Configure with CMake targeting iOS (disable DRED, disable shared library and tests)
    # opus-1.6 is one directory up and then one more up from ios/opus-build/
    # Note: DRED disabled - can be enabled later if needed
    cmake ../../opus-1.6 \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=15.1 \
      -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
      -DCMAKE_OSX_SYSROOT=iphonesimulator \
      -DCMAKE_IOS_INSTALL_COMBINED=YES \
      -DOPUS_DRED=OFF \
      -DOPUS_BUILD_SHARED_LIBRARY=OFF \
      -DOPUS_BUILD_TESTING=OFF \
      -DOPUS_BUILD_PROGRAMS=OFF \
      -DCMAKE_INSTALL_PREFIX=.

    # Build using all available CPU cores
    make -j$(sysctl -n hw.ncpu)

    # Install to local directory
    make install

    echo "Opus 1.6 built successfully with DRED support for iOS"
  CMD

  # Link the compiled Opus library (path relative to podspec location)
  s.vendored_libraries = 'opus-build/lib/libopus.a'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../opus-1.6/include"'
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
