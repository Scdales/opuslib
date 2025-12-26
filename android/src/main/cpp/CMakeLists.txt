cmake_minimum_required(VERSION 3.18.1)

project(opuslib)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add Opus 1.6 library
# Note: The path is relative to this CMakeLists.txt file
# From: android/src/main/cpp/CMakeLists.txt
# To:   opus-1.6/
# Path: ../../../../opus-1.6
add_subdirectory(
  ${CMAKE_CURRENT_SOURCE_DIR}/../../../../opus-1.6
  ${CMAKE_CURRENT_BINARY_DIR}/opus-build
)

# Create JNI wrapper library
add_library(
  opuslib-jni
  SHARED
  opus_jni_wrapper.cpp
)

# Link libraries
target_link_libraries(
  opuslib-jni
  opus          # The Opus 1.6 library we just built
  android       # Android system library
  log           # Android logging
)

# Include Opus headers
target_include_directories(
  opuslib-jni
  PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../../../opus-1.6/include
)
