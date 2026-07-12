// AppProfileManager.swift
// Monkeys
//
// Per-app sound rules + best-effort meeting mode, driven by the frontmost
// application (NSWorkspace notification — no polling, no private APIs, no
// microphone/screen access; detection is intentionally best effort).
//
// Mute priority, highest first:
//   1. Global manual mute (user turned sounds off) — always wins.
//   2. Manual unmute override — if the user re-enables sounds while
//      auto-muted, the override holds until the frontmost app changes.
//   3. Meeting mode (frontmost app is in the meeting whitelist).
//   4. Per-app rule (mute / profile / volume for a bundle identifier).
//   5. Global settings.

import Cocoa

/// A per-application sound rule keyed by bundle identifier.
struct PerAppRule: Codable, Equatable {
    var bundleID: String
    var appName: String
    var enabled: Bool = true
    var muted: Bool = false
    /// SoundProfile rawValue to switch to while the app is frontmost; nil keeps the global profile.
    var profileRaw: String?
    /// Volume 0–100 while the app is frontmost; nil keeps the global volume.
    var volume: Int?
}

/// The state the manager wants the app to be in for the current frontmost app.
struct AppSoundState {
    var autoMuted: Bool
    /// nil = keep the user's global profile
    var profileRaw: String?
    /// nil = keep the user's global volume
    var volume: Int?
    /// Why we auto-muted (for the menu indicator); nil when not auto-muted.
    var reason: AutoMuteReason?
}

enum AutoMuteReason {
    case meeting
    case appRule
}

final class AppProfileManager: @unchecked Sendable {

    // MARK: - Properties

    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var meetingModeEnabled: Bool
    private var storedRules: [PerAppRule]
    private var storedMeetingApps: [String]

    /// Bundle ID for which the user manually cancelled an auto-mute.
    /// Cleared on the next app switch.
    private var manualOverrideBundleID: String?

    private var currentBundleID: String?
    private var currentAppName: String?

    /// Called on app switches with the desired sound state (arrives on main queue).
    var onApplyState: ((AppSoundState) -> Void)?

    // MARK: - Defaults

    static let defaultMeetingApps: [String] = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.apple.FaceTime",
        "com.skype.skype",
        "com.tinyspeck.slackmacgap",
        "com.webex.meetingmanager",
        "com.cisco.webexmeetings",
        "com.hnc.Discord",
        "com.discord.Discord",
    ]

    // MARK: - Initialisation

    init() {
        meetingModeEnabled = UserDefaults.standard.object(forKey: SettingsKey.autoMute) as? Bool ?? true
        storedMeetingApps = UserDefaults.standard.stringArray(forKey: SettingsKey.meetingApps)
            ?? Self.defaultMeetingApps
        if let data = UserDefaults.standard.data(forKey: SettingsKey.perAppRules),
           let decoded = try? JSONDecoder().decode([PerAppRule].self, from: data) {
            storedRules = decoded
        } else {
            storedRules = []
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard observer == nil else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let bundleId = app.bundleIdentifier {
                self.handleAppActivated(bundleId: bundleId, appName: app.localizedName ?? bundleId)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    // MARK: - Meeting mode

    var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return meetingModeEnabled
        }
        set {
            lock.lock()
            meetingModeEnabled = newValue
            lock.unlock()
            UserDefaults.standard.set(newValue, forKey: SettingsKey.autoMute)
            reevaluate()
        }
    }

    var meetingApps: [String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedMeetingApps
        }
        set {
            lock.lock()
            storedMeetingApps = newValue
            lock.unlock()
            UserDefaults.standard.set(newValue, forKey: SettingsKey.meetingApps)
            reevaluate()
        }
    }

    // MARK: - Rules

    var rules: [PerAppRule] {
        lock.lock()
        defer { lock.unlock() }
        return storedRules
    }

    /// Inserts or replaces the rule for `rule.bundleID` (one rule per bundle).
    func upsertRule(_ rule: PerAppRule) {
        lock.lock()
        if let idx = storedRules.firstIndex(where: { $0.bundleID == rule.bundleID }) {
            storedRules[idx] = rule
        } else {
            storedRules.append(rule)
        }
        persistRulesLocked()
        lock.unlock()
        reevaluate()
    }

    func removeRule(bundleID: String) {
        lock.lock()
        storedRules.removeAll { $0.bundleID == bundleID }
        persistRulesLocked()
        lock.unlock()
        reevaluate()
    }

    /// - Precondition: `lock` must be held by the caller.
    private func persistRulesLocked() {
        if let data = try? JSONEncoder().encode(storedRules) {
            UserDefaults.standard.set(data, forKey: SettingsKey.perAppRules)
        }
    }

    // MARK: - Frontmost app info (for quick actions)

    var frontmostApp: (bundleID: String, name: String)? {
        if let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier {
            return (bundle, app.localizedName ?? bundle)
        }
        return nil
    }

    /// User re-enabled sounds while auto-muted: keep sounds on for the
    /// current app until the next app switch.
    func setManualOverrideForCurrentApp() {
        lock.lock()
        manualOverrideBundleID = currentBundleID
        lock.unlock()
    }

    /// True while the manual unmute override is holding for the frontmost app.
    var isOverrideActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return manualOverrideBundleID != nil && manualOverrideBundleID == currentBundleID
    }

    /// Re-applies the rules for the app that is frontmost right now
    /// (used after rules or the whitelist change from Settings).
    func reevaluate() {
        if let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier {
            handleAppActivated(bundleId: bundle, appName: app.localizedName ?? bundle)
        }
    }

    // MARK: - Core logic

    private func handleAppActivated(bundleId: String, appName: String) {
        lock.lock()

        // The manual unmute override only survives while the same app stays frontmost.
        if manualOverrideBundleID != nil && manualOverrideBundleID != bundleId {
            manualOverrideBundleID = nil
        }
        currentBundleID = bundleId
        currentAppName = appName

        var state = AppSoundState(autoMuted: false, profileRaw: nil, volume: nil, reason: nil)

        let overridden = (manualOverrideBundleID == bundleId)
        let isMeetingApp = meetingModeEnabled && storedMeetingApps.contains {
            bundleId == $0 || bundleId.hasPrefix($0)
        }
        let rule = storedRules.first { $0.enabled && ($0.bundleID == bundleId || bundleId.hasPrefix($0.bundleID)) }

        if !overridden && isMeetingApp {
            state.autoMuted = true
            state.reason = .meeting
        } else if let rule {
            if rule.muted && !overridden {
                state.autoMuted = true
                state.reason = .appRule
            }
            state.profileRaw = rule.profileRaw
            state.volume = rule.volume
        }

        lock.unlock()

        onApplyState?(state)
    }
}
