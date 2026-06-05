// AppProfileManager.swift
// Monkeys
//
// Automatically adjusts sound profiles based on the active application.

import Cocoa

/// Monitors the frontmost application and applies per-app sound rules.
/// Automatically mutes or switches profile when video call apps are detected.
final class AppProfileManager: @unchecked Sendable {

    // MARK: - Types

    struct AppRule {
        let bundleIdentifier: String
        let action: Action

        enum Action {
            case mute
            case switchProfile(SoundProfile)
        }
    }

    // MARK: - Properties

    private let lock = NSLock()
    private var rules: [AppRule] = []
    private var observer: NSObjectProtocol?
    private var isAutoMuteEnabled = true

    var onShouldMute: (() -> Void)?
    var onShouldUnmute: (() -> Void)?
    var onShouldSwitchProfile: ((SoundProfile) -> Void)?

    private var wasMutedByApp = false

    // MARK: - Default Rules

    /// Built-in rules for common video call apps
    private static let defaultVideoCallBundles: [String] = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.apple.FaceTime",
        "com.skype.skype",
        "com.tinyspeck.slackmacgap",
        "com.webex.meetingmanager",
        "com.discord.Discord",
    ]

    // MARK: - Initialisation

    init() {
        isAutoMuteEnabled = UserDefaults.standard.object(forKey: "MonkeysAutoMute") as? Bool ?? true

        for bundle in Self.defaultVideoCallBundles {
            rules.append(AppRule(bundleIdentifier: bundle, action: .mute))
        }
    }

    // MARK: - Public API

    func start() {
        guard observer == nil else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard self.isAutoMuteEnabled else { return }

            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let bundleId = app.bundleIdentifier {
                self.handleAppActivated(bundleId: bundleId)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return isAutoMuteEnabled
        }
        set {
            lock.lock()
            isAutoMuteEnabled = newValue
            lock.unlock()
            UserDefaults.standard.set(newValue, forKey: "MonkeysAutoMute")

            if !newValue && wasMutedByApp {
                wasMutedByApp = false
                onShouldUnmute?()
            }
        }
    }

    // MARK: - Private

    private func handleAppActivated(bundleId: String) {
        lock.lock()
        defer { lock.unlock() }

        if let rule = rules.first(where: { bundleId.hasPrefix($0.bundleIdentifier) || $0.bundleIdentifier == bundleId }) {
            switch rule.action {
            case .mute:
                if !wasMutedByApp {
                    wasMutedByApp = true
                    onShouldMute?()
                }
            case .switchProfile(let profile):
                onShouldSwitchProfile?(profile)
            }
        } else {
            if wasMutedByApp {
                wasMutedByApp = false
                onShouldUnmute?()
            }
        }
    }
}
