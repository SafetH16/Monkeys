// AudioOutputMonitor.swift
// MonKeys
//
// Watches the system default audio output device via CoreAudio (no polling,
// no permissions, fully local) and classifies it into the three categories
// the per-device rules use. Also hosts the rules themselves.

import Foundation
import CoreAudio

/// Where the sound is coming out. Three buckets are enough for rules:
/// the embarrassing one (speakers), the private one (Bluetooth headphones)
/// and everything else (USB, HDMI, DisplayPort, AirPlay…).
enum AudioOutputCategory: String, Codable, CaseIterable {
    case builtIn
    case bluetooth
    case other

    /// English label for the Settings window (intentionally not localized).
    var settingsLabel: String {
        switch self {
        case .builtIn:   return "Built-in speakers"
        case .bluetooth: return "Bluetooth headphones"
        case .other:     return "USB & other outputs"
        }
    }
}

/// A per-output-category sound rule. `volume` nil keeps the global volume.
struct DeviceRule: Codable, Equatable {
    var muted: Bool = false
    var volume: Int?
}

/// Stores one optional rule per output category in UserDefaults.
final class DeviceRuleStore: @unchecked Sendable {

    private let lock = NSLock()
    private var rules: [String: DeviceRule]

    init() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.deviceRules),
           let decoded = try? JSONDecoder().decode([String: DeviceRule].self, from: data) {
            rules = decoded
        } else {
            rules = [:]
        }
    }

    func rule(for category: AudioOutputCategory) -> DeviceRule? {
        lock.lock()
        defer { lock.unlock() }
        return rules[category.rawValue]
    }

    /// Pass nil to remove the rule for the category.
    func set(_ rule: DeviceRule?, for category: AudioOutputCategory) {
        lock.lock()
        if let rule {
            rules[category.rawValue] = rule
        } else {
            rules.removeValue(forKey: category.rawValue)
        }
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: SettingsKey.deviceRules)
        }
        lock.unlock()
    }
}

/// Tracks the default output device (name + category) and notifies on change.
final class AudioOutputMonitor: @unchecked Sendable {

    private let lock = NSLock()
    private var storedName = ""
    private var storedCategory = AudioOutputCategory.other
    private var started = false

    /// Called on the main queue after the default output device changed
    /// (the new device is already readable via `current`).
    var onChange: (() -> Void)?

    var current: (name: String, category: AudioOutputCategory) {
        lock.lock()
        defer { lock.unlock() }
        return (storedName, storedCategory)
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self else { return }
            self.refresh()
            self.onChange?()
        }
    }

    // MARK: - CoreAudio plumbing

    private func refresh() {
        let deviceID = Self.defaultOutputDeviceID()
        let name = deviceID.flatMap { Self.deviceName($0) } ?? ""
        let category = deviceID.map { Self.category(forTransportOf: $0) } ?? .other

        lock.lock()
        storedName = name
        storedCategory = category
        lock.unlock()
    }

    private static func defaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return (status == noErr && deviceID != 0) ? deviceID : nil
    }

    private static func deviceName(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let name else { return nil }
        return name as String
    }

    private static func category(forTransportOf deviceID: AudioObjectID) -> AudioOutputCategory {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        guard status == noErr else { return .other }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        default:
            return .other
        }
    }
}
