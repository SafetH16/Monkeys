# MonKeys - Project Instructions for Claude Code

## Overview
MonKeys is a macOS menu bar app that transforms your keyboard into a virtual mechanical keyboard. Each keypress produces a realistic mechanical switch sound. The app lives in the system tray (status bar) and has no dock icon.

## Tech Stack
- **Language:** Swift 6 (strict concurrency)
- **Frameworks:** Cocoa, AVFoundation, CoreGraphics, ApplicationServices
- **Build System:** Custom `build.sh` script (no Xcode build required)
- **Target:** macOS 13.0+ (arm64) for main build; universal builds target macOS 11.0+ (arm64 + x86_64)
- **Audio:** AVAudioEngine with 16-node round-robin pool, 44.1kHz mono PCM synthesis

## Build & Run

### Compile the app
```bash
./build.sh
```
This produces `build/MonKeys.app`.

### Install and run
```bash
cp -R build/MonKeys.app /Applications/
open /Applications/MonKeys.app
```

### Deploy to GitHub (commit + tag + release)
Use the custom zsh function `gdeploy`:
```bash
gdeploy -prod "Commit message" "v1.X.X"
```
This compiles, zips, commits, pushes, tags, and uploads the release asset to GitHub (`SafetH16/Monkeys`).

### Universal Build (Intel + Apple Silicon, macOS 11.0+)
Compile separately for arm64 and x86_64 with `-target <arch>-apple-macosx11.0`, then combine with `lipo`. Update `Info.plist` `LSMinimumSystemVersion` to `11.0` before building universal.

## Project Structure

```
Monkeys/                      ← Source code directory
├── main.swift                ← Entry point
├── AppDelegate.swift         ← Menu bar UI, profile switching, game launching (@MainActor)
├── KeyboardMonitor.swift     ← Global CGEvent tap for keyDown/keyUp events
├── SoundEngine.swift         ← Polyphonic audio engine (AVAudioEngine, 16 player nodes, NSLock)
├── SoundSynthesizer.swift    ← Procedural audio synthesis + wax_slime.wav sample loading
├── KeySoundProfile.swift     ← Sound profile parameters (Blue, Brown, Red, Typewriter, Bubble, WaxSlime)
├── WPMTracker.swift          ← Words-per-minute tracking
├── GameView.swift            ← Monkey typing game UI
├── GameWindow.swift          ← Game window controller
├── SpeedTypeView.swift       ← Speed typing challenge UI
├── SpeedTypeWindow.swift     ← Speed typing window controller
├── AppProfileManager.swift   ← Per-app sound profile association
├── TypingStats.swift         ← Typing statistics persistence
├── Localization.swift        ← Multi-language strings (IT, EN, FR, DE, ES, PT, JA, KO, ZH, AR, RU)
├── Updater.swift             ← Auto-updater from GitHub Releases (contains PAT - DO NOT EXPOSE)
├── Info.plist                ← App metadata (LSUIElement=true, bundle ID, version)
├── Monkeys.entitlements      ← App Sandbox entitlements
├── AppIcon.icns              ← App icon
├── statusBarIcon.png         ← Menu bar icon (1x)
├── statusBarIcon@2x.png      ← Menu bar icon (2x Retina)
├── bg_music.mp3              ← Background lo-fi music
└── wax_slime.wav             ← User-provided wax slime ASMR sound sample
build.sh                      ← Build script (swiftc + codesign)
```

## Architecture

| Component | Responsibility |
|---|---|
| **AppDelegate** | `@MainActor` isolated. Manages NSStatusBar menu, profile switching, volume slider, game windows, localization. |
| **KeyboardMonitor** | Uses `CGEvent.tapCreate` for global key interception. Thread-safe via `NSLock`. Handles key repeat for delete/enter/space (plays sound every 3rd repeat). |
| **SoundEngine** | `@unchecked Sendable`. Pool of 16 `AVAudioPlayerNode` in round-robin. Thread-safe via `NSLock`. Manages key-down clicks, key-up release sounds, velocity-sensitive volume. Also handles background music via `AVAudioPlayer`. |
| **SoundSynthesizer** | Generates PCM buffers procedurally (sine waves + filtered noise + envelopes). For the `waxSlime` profile, loads `wax_slime.wav` from bundle instead. Release sound is muted for waxSlime. |
| **KeySoundProfile** | Enum with associated parameters: click frequency/duration, thud frequency, release characteristics, noise amplitudes. Profiles: `.blue`, `.brown`, `.red`, `.typewriter`, `.bubble`, `.waxSlime`. |
| **Updater** | Checks GitHub Releases API for new versions, downloads and replaces the app bundle. Contains a GitHub PAT for private repo access. |

## Critical Rules

1. **DO NOT leak credentials:** `Updater.swift` contains a GitHub Personal Access Token for private repo access. Never expose it in logs, URLs, or commits.
2. **Swift 6 Strict Concurrency:** All code must be concurrency-safe. `AppDelegate` is `@MainActor`. `SoundEngine` is `@unchecked Sendable` with `NSLock`. Background work must use `Task { @MainActor [weak self] in ... }` for UI updates.
3. **Release Asset Naming:** The GitHub release asset must always be named `MonKeys.zip` for the auto-updater to work.
4. **Sandbox:** The app uses App Sandbox (`Monkeys.entitlements`). The sandbox is required for publishing.
5. **No Xcode required:** The project compiles entirely via `swiftc` in `build.sh`. The `.xcodeproj` exists but is not the primary build method.
6. **Audio format:** The `wax_slime.wav` file is a user-provided audio sample. If replacing it, use WAV format, mono or stereo, any sample rate (the synthesizer handles conversion to 44.1kHz).
7. **Info.plist is embedded:** The build script embeds `Info.plist` into the binary via `-Xlinker -sectcreate` AND copies it into the app bundle's `Contents/` directory.
