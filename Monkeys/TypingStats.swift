// TypingStats.swift
// Monkeys
//
// Tracks daily keystroke statistics and personal records.

import Foundation

/// Tracks and persists daily typing statistics.
final class TypingStats: @unchecked Sendable {

    // MARK: - Properties

    private let lock = NSLock()
    private var todayKeyCount: Int = 0
    private var todayDate: String = ""
    private var peakWPM: Int = 0
    private var allTimeKeyCount: Int = 0

    /// All-time per-key press counts, keyed by CGEvent key code (as String
    /// for UserDefaults compatibility). Persisted in batches to keep the
    /// hot path cheap.
    private var keyCounts: [String: Int] = [:]
    private var unsavedKeyCounts: Int = 0

    // MARK: - UserDefaults Keys

    private let kTodayKeyCount = "MonkeysTodayKeyCount"
    private let kTodayDate = "MonkeysTodayDate"
    private let kPeakWPM = "MonkeysPeakWPM"
    private let kAllTimeKeyCount = "MonkeysAllTimeKeyCount"
    private let kKeyCounts = "MonkeysKeyCounts"

    // MARK: - Initialisation

    init() {
        load()
    }

    // MARK: - Public API

    /// Records a keystroke. Returns the updated today count.
    /// Pass the key code to also feed the per-key heatmap counters.
    @discardableResult
    func recordKeystroke(keyCode: Int64? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }

        checkDateRollover()
        todayKeyCount += 1
        allTimeKeyCount += 1

        if let keyCode {
            keyCounts["\(keyCode)", default: 0] += 1
        }
        unsavedKeyCounts += 1
        // No UserDefaults write here: recordKeystroke runs on the event-tap
        // thread. Persistence happens via flushIfDirty() on a main-thread
        // timer and flush() at termination.
        return todayKeyCount
    }

    /// Persists pending counters if anything changed. Cheap no-op otherwise.
    /// Call from a timer on the main thread, never from the tap callback.
    func flushIfDirty() {
        lock.lock()
        defer { lock.unlock() }
        guard unsavedKeyCounts > 0 else { return }
        persistLocked()
    }

    /// Returns a snapshot of the all-time per-key press counts.
    func getKeyCounts() -> [Int64: Int] {
        lock.lock()
        defer { lock.unlock() }
        var result: [Int64: Int] = [:]
        for (key, count) in keyCounts {
            if let code = Int64(key) { result[code] = count }
        }
        return result
    }

    /// Flushes all batched counters to disk (call on app termination).
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        persistLocked()
    }

    /// Erases every stored statistic (today, all-time, peak WPM, per-key).
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        todayKeyCount = 0
        allTimeKeyCount = 0
        peakWPM = 0
        keyCounts.removeAll()
        unsavedKeyCounts = 0
        UserDefaults.standard.removeObject(forKey: kPeakWPM)
        persistLocked()
    }

    /// - Precondition: `lock` must be held by the caller.
    private func persistLocked() {
        UserDefaults.standard.set(keyCounts, forKey: kKeyCounts)
        UserDefaults.standard.set(todayKeyCount, forKey: kTodayKeyCount)
        UserDefaults.standard.set(todayDate, forKey: kTodayDate)
        UserDefaults.standard.set(allTimeKeyCount, forKey: kAllTimeKeyCount)
        unsavedKeyCounts = 0
    }

    /// Updates the peak WPM if the new value is higher.
    func updatePeakWPM(_ wpm: Int) {
        lock.lock()
        defer { lock.unlock() }

        if wpm > peakWPM {
            peakWPM = wpm
            UserDefaults.standard.set(peakWPM, forKey: kPeakWPM)
        }
    }

    /// Returns today's keystroke count.
    func getTodayCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        checkDateRollover()
        return todayKeyCount
    }

    /// Returns the all-time peak WPM.
    func getPeakWPM() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return peakWPM
    }

    /// Returns the all-time total keystrokes.
    func getAllTimeCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return allTimeKeyCount
    }

    /// Returns a fun description string for the menu.
    func menuDescription() -> String {
        lock.lock()
        defer { lock.unlock() }
        checkDateRollover()

        let emoji: String
        if todayKeyCount >= 10000 { emoji = "🔥" }
        else if todayKeyCount >= 5000 { emoji = "💪" }
        else if todayKeyCount >= 1000 { emoji = "⌨️" }
        else { emoji = "🐵" }

        return "\(emoji) Oggi: \(formatNumber(todayKeyCount)) tasti"
    }

    /// Returns stats summary for info dialog.
    func statsSummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        checkDateRollover()

        return """
            📊 Statistiche:
            • Tasti premuti oggi: \(formatNumber(todayKeyCount))
            • Tasti premuti in totale: \(formatNumber(allTimeKeyCount))
            • Record velocità: \(peakWPM) WPM
            """
    }

    // MARK: - Private

    private func currentDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func checkDateRollover() {
        let today = currentDateString()
        if todayDate != today {
            todayDate = today
            todayKeyCount = 0
            save()
        }
    }

    private func load() {
        todayKeyCount = UserDefaults.standard.integer(forKey: kTodayKeyCount)
        todayDate = UserDefaults.standard.string(forKey: kTodayDate) ?? currentDateString()
        peakWPM = UserDefaults.standard.integer(forKey: kPeakWPM)
        allTimeKeyCount = UserDefaults.standard.integer(forKey: kAllTimeKeyCount)
        keyCounts = UserDefaults.standard.dictionary(forKey: kKeyCounts) as? [String: Int] ?? [:]
        checkDateRollover()
    }

    private func save() {
        UserDefaults.standard.set(todayKeyCount, forKey: kTodayKeyCount)
        UserDefaults.standard.set(todayDate, forKey: kTodayDate)
        UserDefaults.standard.set(allTimeKeyCount, forKey: kAllTimeKeyCount)
    }

    func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
