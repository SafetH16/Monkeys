# Changelog

All notable changes to MonKeys are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.0] — 2026-07-13

### Added
- **Device awareness**: MonKeys now knows where its sound is going. The menu shows the current audio output under the volume slider, and the status header explains device-based decisions.
- **Rules by audio output** (Settings → Devices): mute or set a volume per output category — built-in speakers, Bluetooth headphones, USB & other. Priority: manual mute > unmute override > meeting > app rule > device rule > global.
- **Mascot glyph**: a line-art monkey holding a keyring of keycaps in the menu header and onboarding — drawn in code, template, adapts to light/dark.

### Fixed
- **Key sounds no longer die when the output device changes** (connecting AirPods, unplugging headphones…): the audio engine reconnects with the new hardware format and restarts automatically.
- **Auto-updater works with the private repository**: authenticated API checks, correct asset download (API asset URL with credential-stripping on the storage redirect), clear error reporting, and update dialogs localized in all 9 languages. The token is injected at build time from an untracked file and never enters the repository.

## [1.9.0] — 2026-07-12

### Added
- **Typing ranks**: an all-time keystroke rank from *Capuchin* to *Silverback*, shown in the statistics dashboard with progress toward the next rank.
- Muted state in the menu bar now uses a slashed monkey icon (native `speaker.slash` idiom) instead of a dimmed one.

### Changed
- Professional repository facelift: rewritten README, MIT license, this changelog.

## [1.8.0] — 2026-07-12

### Changed
- **Complete menu bar redesign** — from a 28-row control panel to an 11-row native menu: status header (state + live WPM/keys), quick controls with native checkmarks and SF Symbols, contextual submenu named after the frontmost app (with icon and one-click rule), Preset / Modes / Games submenus. The menu is rebuilt live on every open.
- Language, update check and version moved into Settings → General.

### Added
- User presets are now selectable directly from the menu.

## [1.7.0] — 2026-07-12

### Added
- *Save the Bananas*: 40-second **waves** with end-of-wave scorecards, **boss bananas**, a deterministic **weekly duel** with shareable score, four unlockable color palettes.

## [1.6.0] — 2026-07-12

### Added
- *Save the Bananas*: word bananas (type whole words).
- *Speed Challenge*: **weak-key drill** built from your own heatmap, ghost curve of your best run.
- Layered game music with intensity driven by flow tiers.

## [1.5.0] — 2026-07-12

### Added
- Game-feel pass on both games: hit-stop, spring screen shake, catch tweens, staggered result screens.
- Progression layer: per-mode medals, daily missions, play streak.

## [1.4.1] — 2026-07-12

### Fixed
- The onboarding button now reliably opens System Settings → Accessibility.
- CI moved to the `macos-15` runner (Swift 6 toolchain).

## [1.4.0] — 2026-07-12

### Added
- **Settings window** (General / Sound / App Profiles / Privacy) with a live preset editor and validated JSON import/export.
- **Per-app rules** and best-effort **meeting mode** with a configurable whitelist.
- Focus mode, Game mode, keyboard visualizer, opt-out aggregate statistics.
- Key-category acoustics (space, enter, modifiers…), per-key buffer cache, stereo panning.

### Security
- Hardened event-tap hot path; no keycode logging anywhere; batched persistence.

## [1.3.0] — 2026-07-11

### Added
- Launch at login, stereo audio, statistics heatmap, mouse level selection in games, zen mode.

### Security
- Updater hardening: verified archive swap with backup and rollback.

## [1.2.0] — 2026-07-11

### Changed
- More engaging games and refined visuals; fixed background timers and key auto-repeat.

## [1.1.0] — 2026-07-11

### Added
- Special bananas, particles, countdown, music with fade in the games; improved sounds.

## [1.0.x] — 2026-06-05 … 2026-06-07

- Initial releases: menu bar app with procedural key sounds, first presets, custom status bar icon, auto-updater based on GitHub Releases.
