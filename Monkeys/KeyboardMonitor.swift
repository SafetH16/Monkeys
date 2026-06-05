import Foundation
import CoreGraphics
import ApplicationServices

// MARK: - File-scope C callback for CGEvent tap

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // Re-enable the tap if it was disabled by the system
    if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        print("KeyboardMonitor Callback: Tap disabled by system (type: \(type.rawValue)), re-enabling...")
        if let tap = monitor.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    print("KeyboardMonitor Callback: received type=\(type.rawValue), keyCode=\(keyCode), isRepeat=\(isRepeat)")

    if type == .keyDown {
        let flags = event.flags
        let (monitorKeyCode, monitorFlags) = monitor.currentShortcut
        let cleanFlags = flags.intersection([.maskControl, .maskShift, .maskAlternate, .maskCommand])
        if cleanFlags == monitorFlags && keyCode == monitorKeyCode {
            print("KeyboardMonitor Callback: Shortcut triggered")
            monitor.onShortcutTriggered?()
            return nil // Consume event
        }
    }

    switch type {
    case .keyDown:
        monitor.handleKeyDown(keyCode: keyCode, isRepeat: isRepeat)

    case .keyUp:
        monitor.handleKeyUp(keyCode: keyCode)

    case .flagsChanged:
        let currentFlags = event.flags
        monitor.handleFlagsChanged(keyCode: keyCode, currentFlags: currentFlags)

    default:
        break
    }

    return Unmanaged.passRetained(event)
}

// MARK: - KeyboardMonitor

final class KeyboardMonitor: @unchecked Sendable {

    // MARK: Callbacks

    var onKeyDown: ((Int64, Bool) -> Void)?
    var onKeyUp: ((Int64) -> Void)?
    var onShortcutTriggered: (() -> Void)?

    // MARK: Internal state (accessed from callback)

    fileprivate var eventTap: CFMachPort?

    private var pressedKeys = Set<Int64>()
    private let lock = NSLock()
    private var previousModifierFlags: CGEventFlags = []
    private var runLoopSource: CFRunLoopSource?

    // Customizable shortcut settings
    private var shortcutKeyCode: Int64 = 40 // 'K'
    private var shortcutFlags: CGEventFlags = [.maskControl, .maskShift]

    init() {
        // Load custom shortcut if it exists
        if let storedKeyCode = UserDefaults.standard.object(forKey: "MonkeysShortcutKeyCode") as? Int64,
           let storedFlagsRaw = UserDefaults.standard.object(forKey: "MonkeysShortcutFlagsRaw") as? UInt64 {
            self.shortcutKeyCode = storedKeyCode
            self.shortcutFlags = CGEventFlags(rawValue: storedFlagsRaw)
        }
    }

    var currentShortcut: (keyCode: Int64, flags: CGEventFlags) {
        lock.lock()
        defer { lock.unlock() }
        return (shortcutKeyCode, shortcutFlags)
    }

    func setShortcut(keyCode: Int64, flags: CGEventFlags) {
        lock.lock()
        self.shortcutKeyCode = keyCode
        self.shortcutFlags = flags
        lock.unlock()

        // Save to UserDefaults
        UserDefaults.standard.set(keyCode, forKey: "MonkeysShortcutKeyCode")
        UserDefaults.standard.set(flags.rawValue, forKey: "MonkeysShortcutFlagsRaw")
    }

    // Modifier key codes mapped to their CGEventFlags bit
    private static let modifierKeyMap: [Int64: CGEventFlags] = [
        54: .maskCommand,       // Right Command
        55: .maskCommand,       // Left Command
        56: .maskShift,         // Left Shift
        60: .maskShift,         // Right Shift
        58: .maskAlternate,     // Left Option
        61: .maskAlternate,     // Right Option
        59: .maskControl,       // Left Control
        62: .maskControl,       // Right Control
        57: .maskAlphaShift,    // Caps Lock
        63: .maskSecondaryFn,   // Fn
    ]

    // MARK: - Public API

    var isStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventTap != nil
    }

    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if eventTap != nil {
            return true
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            print("KeyboardMonitor: CGEvent.tapCreate returned nil (Accessibility permission probably missing).")
            return false
        }

        print("KeyboardMonitor: CGEvent.tapCreate succeeded.")
        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        pressedKeys.removeAll()
    }

    // MARK: - Accessibility Permission

    static func checkAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Event handling (called from C callback)

    fileprivate func handleKeyDown(keyCode: Int64, isRepeat: Bool) {
        if isRepeat {
            // Propagate repeat events for Backspace (51), Delete (117), Return (36), Numpad Enter (76), and Spacebar (49)
            if keyCode == 51 || keyCode == 117 || keyCode == 36 || keyCode == 76 || keyCode == 49 {
                onKeyDown?(keyCode, true)
            }
        } else {
            lock.lock()
            let alreadyPressed = pressedKeys.contains(keyCode)
            if !alreadyPressed {
                pressedKeys.insert(keyCode)
            }
            lock.unlock()

            if !alreadyPressed {
                onKeyDown?(keyCode, false)
            }
        }
    }

    fileprivate func handleKeyUp(keyCode: Int64) {
        lock.lock()
        pressedKeys.remove(keyCode)
        lock.unlock()

        onKeyUp?(keyCode)
    }

    fileprivate func handleFlagsChanged(keyCode: Int64, currentFlags: CGEventFlags) {
        // Determine if this modifier key was pressed or released by checking
        // whether its corresponding flag bit is now set.
        if let flagBit = KeyboardMonitor.modifierKeyMap[keyCode] {
            let wasSet = previousModifierFlags.contains(flagBit)
            let isSet = currentFlags.contains(flagBit)

            if isSet && !wasSet {
                // Modifier key pressed
                lock.lock()
                pressedKeys.insert(keyCode)
                lock.unlock()
                onKeyDown?(keyCode, false)
            } else if !isSet && wasSet {
                // Modifier key released
                lock.lock()
                pressedKeys.remove(keyCode)
                lock.unlock()
                onKeyUp?(keyCode)
            }
        }

        previousModifierFlags = currentFlags
    }
}
