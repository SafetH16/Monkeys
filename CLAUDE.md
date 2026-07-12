# MonKeys - Project Instructions for Claude Code

## Overview
MonKeys is a macOS menu bar app that transforms your keyboard into a virtual mechanical keyboard. Each keypress produces a procedurally synthesized switch sound with stereo positioning and per-category character. The app lives in the status bar (no dock icon), ships two typing games, a settings window with a preset editor, per-app rules, a statistics dashboard and a keyboard visualizer.

## Tech Stack
- **Language:** Swift 6 (strict concurrency)
- **Frameworks:** Cocoa, AVFoundation, CoreGraphics, ApplicationServices, ServiceManagement, UniformTypeIdentifiers
- **Build System:** Custom `build.sh` (swiftc, no Xcode required)
- **Target:** macOS 13.0+ (arm64); universal builds target macOS 11.0+ (arm64 + x86_64)
- **Audio:** AVAudioEngine, 16-node round-robin pool, 44.1kHz mono PCM synthesis, per-key buffer cache

## Build & Deploy
```bash
./build.sh                          # → build/MonKeys.app
gdeploy -prod "msg" "v1.X.X"        # user's zsh fn: build+zip+commit+push+tag+release
```
Release asset must always be named `MonKeys.zip` (auto-updater contract).
CI: `.github/workflows/build.yml` compiles on macos-14 (read-only permissions, no secrets).

## Project Structure (Monkeys/ sources)
```
main.swift               Entry point (LSUIElement)
AppDelegate.swift        Menu bar, state composition (manual/auto mute, focus/game mode), windows
SettingsStore.swift      ALL UserDefaults keys (SettingsKey) + typed accessors (AppSettings)
KeyboardMonitor.swift    Global CGEvent tap; re-enables itself on timeout; Ctrl+Shift+K consumed
SoundEngine.swift        16-node pool, per-key buffer cache (3 pitch variants), stereo pan map,
                         gain jitter, game-mode gain shaping, music player w/ generation counter
SoundSynthesizer.swift   PCM synthesis (params-driven) + game chimes + synth music track
KeySoundProfile.swift    SoundProfile enum (18 built-ins) + SoundParameters + KeyCategory
SoundProfileStore.swift  User presets: Application Support JSON, atomic writes, validated import
SettingsWindow.swift     4-tab preferences (General/Sound/App Profiles/Privacy), English UI
AppProfileManager.swift  Per-app rules + meeting whitelist; priority: manual > override > meeting > rule
FrontmostAppMonitor:     (inside AppProfileManager) NSWorkspace notification, no polling
VisualizerWindow.swift   Floating key-highlight panel, decays via self-stopping 30fps timer
StatsWindow.swift        Dashboard: cards + keyboard heatmap + top keys
TypingStats.swift        Aggregate counters (today/all-time/peak/per-key); batched persistence
WPMTracker.swift         Sliding-window WPM (timestamps only)
GameView/GameWindow      Banana Catch game (zen mode, power-ups, particles)
SpeedTypeView/Window     Speed typing game (countdown, WPM chart, mouse selection)
OnboardingWindow.swift   First-launch Accessibility explainer (auto-closes when granted)
Updater.swift            Anonymous GitHub Releases updater; safe swap script w/ backup
Localization.swift       9 languages; every menu string must exist in all of them
```

## Critical Rules
1. **NEVER put credentials in the repo or binary.** The updater is anonymous by design; the repo must stay free of tokens (anything compiled in can be extracted with `strings`).
2. **Privacy:** never store/log/transmit typed text, key sequences or per-event timestamps. Statistics are aggregate counters only, clearable and toggleable in Settings → Privacy.
3. **Event tap hot path:** no I/O, UserDefaults writes, JSON, UI or heavy allocation in `KeyboardMonitor` callbacks / `SoundEngine.playKeyDown`. Persistence is batched (`TypingStats.flushIfDirty` on the 1s menu timer). Buffer synthesis happens once per key (cache) — keep it that way.
4. **Swift 6 strict concurrency:** AppDelegate/windows are `@MainActor`; engine/monitor/stores are `@unchecked Sendable` with `NSLock`. Background → UI via `Task { @MainActor [weak self] in }`. Zero-warning builds are the standard.
5. **Ctrl+Shift+K** (user-remappable) is the only consumed event.
6. **Sandbox:** App Sandbox + user-selected file read/write (needed for preset import/export panels). Do not add entitlements without need.
7. **Info.plist embedded** via `-sectcreate` AND copied into `Contents/` (build.sh does both).
8. **Menu strings** go through `L.shared` in all 9 languages; the Settings window is intentionally English-only.
9. **New Swift files must be added to build.sh** (and keep CI green).
10. No third-party dependencies of any kind. All built-in sounds are synthesized; `wax_slime.wav` is the user's own sample.
