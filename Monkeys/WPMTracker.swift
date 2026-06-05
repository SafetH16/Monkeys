// WPMTracker.swift
// Monkeys
//
// Calculates real-time words-per-minute typing speed using a sliding window.

import Foundation

/// Monitors keystroke speed and translates it into a Words Per Minute (WPM) value.
///
/// Thread-safety is guaranteed by an internal lock, as callbacks can trigger
/// from arbitrary system event tap threads.
final class WPMTracker: @unchecked Sendable {

    // MARK: - Properties

    private var keyPressTimestamps: [Date] = []
    private let windowDuration: TimeInterval = 5.0
    private let lock = NSLock()

    // MARK: - Public API

    /// Appends a new keystroke timestamp and returns the updated WPM.
    func recordKeyPress() -> Int {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        keyPressTimestamps.append(now)
        cleanOldTimestamps(now: now)

        return calculateWPM()
    }

    /// Evaluates the current WPM without registering a new keystroke.
    /// Useful for timer-based UI updates to let WPM fade to 0 when typing stops.
    func currentWPM() -> Int {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        cleanOldTimestamps(now: now)

        return calculateWPM()
    }

    // MARK: - Private Helpers

    /// Discards timestamps that have fallen out of the sliding time window.
    ///
    /// - Precondition: `lock` must be held by the caller.
    private func cleanOldTimestamps(now: Date) {
        keyPressTimestamps = keyPressTimestamps.filter { now.timeIntervalSince($0) <= windowDuration }
    }

    /// Translates raw keystrokes in the time window to WPM.
    ///
    /// - Precondition: `lock` must be held by the caller.
    private func calculateWPM() -> Int {
        // Standard definition: 1 word = 5 keystrokes.
        // WPM = (keystrokes / 5) * (60 / windowDuration)
        let keystrokesCount = Double(keyPressTimestamps.count)
        let wpm = (keystrokesCount / 5.0) * (60.0 / windowDuration)
        return Int(round(wpm))
    }
}
