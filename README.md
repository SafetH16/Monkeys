# MonKeys ⌨️🍌

![MonKeys Icon](cover.png)

**MonKeys** is a macOS menu bar app that turns your keyboard into a virtual mechanical keyboard. Every keypress produces a realistic, **procedurally synthesized** switch sound — with per-key stereo positioning, natural per-press variation, distinct acoustic character for space/enter/modifiers, and a fully custom preset editor. It also ships two typing mini-games, a local statistics dashboard with a keyboard heatmap, and an optional on-screen keyboard visualizer.

> 🔒 **Privacy first**: MonKeys never records, stores or transmits the text you type. Key events trigger local sounds and visuals, then they are discarded. All statistics are aggregate counters that never leave your Mac. The only network access is the update check against GitHub Releases — no analytics, no telemetry.

> 🎵 **All built-in sounds are procedurally synthesized.** No third-party audio recordings are distributed with this app.

---

## 🚀 Install

1. **[Download the latest MonKeys.zip](https://github.com/SafetH16/Monkeys/releases/latest/download/MonKeys.zip)**
2. Unzip and move **`MonKeys.app`** into your **Applications** folder.
3. MonKeys is currently **not code-signed or notarized** (no paid Apple Developer account yet), so Gatekeeper will warn you on first launch. To clear the quarantine flag, run in Terminal:
   ```bash
   xattr -cr /Applications/MonKeys.app
   ```
4. Launch the app and grant the **Accessibility** permission when prompted (see [Permissions](#-permissions)).

## 🔑 Permissions

MonKeys uses a global `CGEvent` tap to detect key presses system-wide, which on macOS requires the **Accessibility** permission (System Settings → Privacy & Security → Accessibility → enable MonKeys). A friendly onboarding window guides you through this on first launch and disappears automatically once the permission is granted.

That is the only permission MonKeys needs. It does not request microphone, screen recording, camera, or network permissions beyond the standard outgoing connection used by the updater.

If macOS temporarily disables the event tap (it can happen under heavy load), MonKeys re-enables it automatically.

## 🧭 Menu bar

| Item | What it does |
|---|---|
| ✅ Enabled / ❌ Disabled | Master toggle for all key sounds (same state as the shortcut) |
| ⌨️ Shortcut | Global mute shortcut, default **Control+Shift+K**, fully re-mappable |
| 🎧 Test Sound | Plays a click + release of the current voice without typing |
| 🔊 Volume | Master volume slider (persisted) |
| 🎵 Game Music | Toggles background music in the mini-games |
| 🍌 / ⌨️ Games | *Save the Bananas* and *Speed Challenge* |
| 🤫 Auto-Mute | Meeting Mode toggle (see below) |
| 🚀 Launch at Login | Starts MonKeys automatically (macOS 13+) |
| 🧘 Focus Mode | Instantly switches to a silent voice at 30% volume |
| 🎮 Game Mode | Boosts WASD/Space/Shift/digits, attenuates everything else |
| ⌨️ Keyboard Visualizer | Floating panel that lights up keys as you type |
| 🔇 Mute for Current App / ➕ Profile for Current App | One-click per-app rules |
| ⚙️ Settings… | Opens the full preferences window |
| 📊 Statistics | Live WPM, daily counters, heatmap dashboard |

The menu is localized in 9 languages (EN, IT, ES, FR, DE, PT, JA, ZH, KO).

## 🎛 Sound presets & custom editor

18 built-in procedural presets, including classic switch emulations (Clicky Blue-style, Tactile Brown-style, Linear Red-style…), **Deep Thock**, **Silent Office**, **Terminal**, **Soft Mac-like**, Retro Typewriter, ASMR bubbles and more.

In **Settings → Sound** you can:
- edit 8 synthesis parameters (loudness, pitch, click character, thock depth, resonance, hold, release, variation) with **live preview** while you type;
- save your edits as **user presets** (built-ins are never modified);
- **export / import** presets as JSON. Imports are strictly validated: 256 KB size limit, schema version check, numeric range clamping, and name collisions are auto-renamed — never silently overwritten. A malformed file can't crash the app.

Every key press gets subtle natural variation (~±2% pitch, ±5% gain) and per-key **stereo panning** matching the key's physical position. Space, Enter, Backspace, modifiers, navigation, function and numpad keys each have their own acoustic character. Sounds are cached per key after first synthesis, keeping the event-tap path allocation-free and low-latency, with full 16-voice polyphony.

## 🪟 App Profiles & Meeting Mode

**Settings → App Profiles** lets you define one rule per application (bundle identifier): enable/disable sounds, force a profile, set a custom volume, or mute entirely while that app is frontmost.

**Meeting Mode** (best effort): when the frontmost app is in the configurable meeting whitelist (Zoom, Teams, FaceTime, Skype, Slack, Webex, Discord by default), sounds auto-mute and the menu shows *Auto-muted (meeting)*. Detection is intentionally based only on the frontmost app — MonKeys does **not** access your microphone, screen, or other apps' content, so it cannot know with certainty that a call is active.

**Priority** (highest wins): your manual mute → manual unmute override (holds until you switch app) → Meeting Mode → app rule → global settings.

## 🎮 Mini-games

- **🍌 Save the Bananas** — catch falling letters before they hit the ground. Golden bananas 🌟 heal and multiply points, bombs 💣 must *not* be typed, ice ❄️ slows time, combos trigger Fever ×2. Zen mode (press **Z**) removes lives for younger players.
- **⌨️ Speed Challenge** — 4 difficulty levels selectable by mouse or keyboard, 3-2-1 countdown, live WPM, accuracy, combo tracking, WPM-over-time chart and confetti on new records. Word banks in 6 languages.

## 📊 Statistics & privacy

The dashboard (menu → Statistics) shows today's key count, all-time total, peak WPM, a **keyboard heatmap** of your most-pressed keys, and your top 5 keys.

- Counters are **aggregate only**: no text, no key sequences, no per-event timestamps, no app targets.
- Data is stored locally in the app sandbox and never transmitted.
- You can disable statistics or **Clear Local Statistics** anytime in Settings → Privacy.

## 🔨 Build from source

No Xcode project needed — the entire app compiles with `swiftc`:

```bash
./build.sh          # produces build/MonKeys.app (arm64, macOS 13+, Swift 6)
open build/MonKeys.app
```

CI: a GitHub Actions workflow compiles every push/PR on `macos-14` with read-only permissions and no secrets.

## 🛠 Troubleshooting

| Problem | Fix |
|---|---|
| No sounds at all | Check the Accessibility permission; check the master toggle and volume; check you're not in Focus/Meeting auto-mute (menu shows the reason) |
| "App is damaged / can't be opened" | Run `xattr -cr /Applications/MonKeys.app` (unsigned app, see above) |
| Sounds stopped after granting permission | Quit and relaunch MonKeys once |
| Auto-muted unexpectedly | An app rule or Meeting Mode matched the frontmost app — see Settings → App Profiles; a manual unmute overrides it until you switch app |
| Update failed | The updater never deletes the old app before verifying the new one; simply retry or download from Releases |

## 🔐 Security model

- No keylogging: key codes are used transiently for sound/visual dispatch and aggregate counters (opt-out), never stored as sequences or content.
- No third-party dependencies, no package managers, no external scripts at build time.
- Preset JSON import is size-limited, schema-checked and range-clamped; writes are atomic.
- The updater downloads exclusively from this repository's GitHub Releases over HTTPS and swaps the bundle only after verifying the archive.
- The repository and the shipped binary contain no credentials or secrets.

## 🔭 Future: code signing & notarization

MonKeys is not yet signed or notarized. When an Apple Developer membership is available, the plan is: Developer ID signing with hardened runtime, notarization in `build.sh`/CI, at which point the `xattr` step disappears. Nothing in the current design blocks this.

---

*MonKeys does not record, store, or transmit anything you type. All included sounds are procedurally synthesized; no third-party audio recordings are distributed.*
