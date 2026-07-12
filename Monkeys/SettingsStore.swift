// SettingsStore.swift
// MonKeys
//
// Single source of truth for every UserDefaults key used by the app,
// plus typed accessors for the main preferences. Centralizing the keys
// prevents typo-drift and makes the persistence surface auditable.

import Foundation

enum SettingsKey {
    // Core sound state
    static let soundProfile        = "MonkeysSoundProfile"
    static let customPresetName    = "MonkeysCustomPresetName"
    static let volume              = "MonkeysVolume"
    static let musicEnabled        = "MonkeysMusicEnabled"

    // Shortcut
    static let shortcutKeyCode     = "MonkeysShortcutKeyCode"
    static let shortcutFlagsRaw    = "MonkeysShortcutFlagsRaw"

    // Behaviour toggles
    static let autoMute            = "MonkeysAutoMute"
    static let statsEnabled        = "MonkeysStatsEnabled"
    static let zenMode             = "MonkeysZenMode"
    static let language            = "MonkeysLanguage"

    // Daily typing goal (0 = off) + the day it was last celebrated
    static let dailyGoal           = "MonkeysDailyGoal"
    static let goalCelebratedDay   = "MonkeysGoalCelebrated"

    // Per-app rules & meeting whitelist (JSON-encoded)
    static let perAppRules         = "MonkeysPerAppRules"
    static let meetingApps         = "MonkeysMeetingApps"

    // Per-output-device rules (JSON-encoded, keyed by AudioOutputCategory)
    static let deviceRules         = "MonkeysDeviceRules"

    // Statistics
    static let todayKeyCount       = "MonkeysTodayKeyCount"
    static let todayDate           = "MonkeysTodayDate"
    static let peakWPM             = "MonkeysPeakWPM"
    static let allTimeKeyCount     = "MonkeysAllTimeKeyCount"
    static let keyCounts           = "MonkeysKeyCounts"

    // Game records (written by the game views)
    static let gameHighScore       = "MonkeysHighScore"
    static let speedTypeWPMPrefix  = "MonkeysSpeedTypeWPM_"     // + difficulty raw value
    static let speedHistoryPrefix  = "MonkeysSpeedHistory_"     // + difficulty raw value

    // Visualizer
    static let visualizerVisible   = "MonkeysVisualizerVisible"
}

/// Typed convenience accessors for the most-used settings.
/// Reads are cheap; writes must never happen on the event-tap thread —
/// call them from the main thread or a timer.
enum AppSettings {
    static var volume: Int {
        get { UserDefaults.standard.object(forKey: SettingsKey.volume) as? Int ?? 70 }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.volume) }
    }

    static var musicEnabled: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.musicEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.musicEnabled) }
    }

    static var statsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.statsEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.statsEnabled) }
    }

    /// Daily typing goal in keystrokes; 0 = disabled.
    static var dailyGoal: Int {
        get { UserDefaults.standard.object(forKey: SettingsKey.dailyGoal) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.dailyGoal) }
    }

    static var savedProfileRaw: String? {
        get { UserDefaults.standard.string(forKey: SettingsKey.soundProfile) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.soundProfile) }
    }

    static var customPresetName: String? {
        get { UserDefaults.standard.string(forKey: SettingsKey.customPresetName) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.customPresetName)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.customPresetName)
            }
        }
    }
}
