#!/bin/bash
# Build script for MonKeys.app
# Creates a proper macOS .app bundle from the compiled Swift binary

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MonKeys"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "🔨 Building ${APP_NAME}..."

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Compile
swiftc -o "${BUILD_DIR}/${APP_NAME}" \
  "${SCRIPT_DIR}/Monkeys/main.swift" \
  "${SCRIPT_DIR}/Monkeys/AppDelegate.swift" \
  "${SCRIPT_DIR}/Monkeys/KeyboardMonitor.swift" \
  "${SCRIPT_DIR}/Monkeys/SoundEngine.swift" \
  "${SCRIPT_DIR}/Monkeys/SoundSynthesizer.swift" \
  "${SCRIPT_DIR}/Monkeys/KeySoundProfile.swift" \
  "${SCRIPT_DIR}/Monkeys/WPMTracker.swift" \
  "${SCRIPT_DIR}/Monkeys/GameView.swift" \
  "${SCRIPT_DIR}/Monkeys/GameWindow.swift" \
  "${SCRIPT_DIR}/Monkeys/AppProfileManager.swift" \
  "${SCRIPT_DIR}/Monkeys/TypingStats.swift" \
  "${SCRIPT_DIR}/Monkeys/SpeedTypeView.swift" \
  "${SCRIPT_DIR}/Monkeys/SpeedTypeWindow.swift" \
  "${SCRIPT_DIR}/Monkeys/Localization.swift" \
  "${SCRIPT_DIR}/Monkeys/Updater.swift" \
  -framework Cocoa \
  -framework AVFoundation \
  -framework CoreGraphics \
  -framework ApplicationServices \
  -target arm64-apple-macosx13.0 \
  -swift-version 6 \
  -O

echo "📦 Creating app bundle..."

# Create .app bundle structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp "${SCRIPT_DIR}/Monkeys/Info.plist" "${APP_BUNDLE}/Contents/"

# Copy Resources (AppIcon.icns, mp3, status bar icons)
cp "${SCRIPT_DIR}/Monkeys/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
cp "${SCRIPT_DIR}/Monkeys/bg_music.mp3" "${APP_BUNDLE}/Contents/Resources/"
cp "${SCRIPT_DIR}/Monkeys/statusBarIcon.png" "${APP_BUNDLE}/Contents/Resources/"
cp "${SCRIPT_DIR}/Monkeys/statusBarIcon@2x.png" "${APP_BUNDLE}/Contents/Resources/"

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Codesign the application bundle
echo "🔑 Codesigning application bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Build complete!"
echo "📍 App bundle: ${APP_BUNDLE}"
echo ""
echo "To run: open ${APP_BUNDLE}"
echo "To install: cp -R ${APP_BUNDLE} /Applications/"
