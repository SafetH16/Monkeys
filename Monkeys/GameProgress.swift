// GameProgress.swift
// MonKeys
//
// Local, lightweight retention systems for the mini-games: per-mode medals,
// one deterministic daily mission, and a play streak. Everything lives in
// UserDefaults, nothing ever leaves the Mac, no timers, no notifications.

import Foundation

enum Medal: Int, Comparable {
    case none = 0, bronze = 1, silver = 2, gold = 3

    static func < (lhs: Medal, rhs: Medal) -> Bool { lhs.rawValue < rhs.rawValue }

    var emoji: String {
        switch self {
        case .none: return ""
        case .bronze: return "🥉"
        case .silver: return "🥈"
        case .gold: return "🥇"
        }
    }
}

/// One mission per day, derived deterministically from the date so it needs
/// no scheduling and is identical across launches.
struct DailyMission {
    enum Kind {
        case catchGolden(Int)   // catch N golden bananas (Banana game)
        case scoreRun(Int)      // reach a score in a single Banana run
        case reachWPM(Int)      // reach N WPM in a Speed run
    }
    let kind: Kind

    /// Localized human description.
    var text: String {
        switch kind {
        case .catchGolden(let n): return L.shared.sf("mi_golden", n)
        case .scoreRun(let n):    return L.shared.sf("mi_score", n)
        case .reachWPM(let n):    return L.shared.sf("mi_wpm", n)
        }
    }
}

@MainActor
final class GameProgress {

    static let shared = GameProgress()
    private init() {}

    private let defaults = UserDefaults.standard

    // MARK: - Medals

    /// Medal thresholds per mode key.
    private func thresholds(for mode: String) -> (bronze: Int, silver: Int, gold: Int) {
        switch mode {
        case "bananas":      return (40, 80, 140)
        case "speed_sprint": return (25, 40, 55)
        default:             return (30, 45, 60)   // classic speed modes (WPM)
        }
    }

    func medal(forScore score: Int, mode: String) -> Medal {
        let t = thresholds(for: mode)
        if score >= t.gold { return .gold }
        if score >= t.silver { return .silver }
        if score >= t.bronze { return .bronze }
        return .none
    }

    /// Records a finished run: returns the medal earned by this run and
    /// whether it improves the best medal stored for the mode.
    @discardableResult
    func recordRun(mode: String, score: Int) -> (medal: Medal, isNewBest: Bool) {
        let earned = medal(forScore: score, mode: mode)
        let key = "MonkeysMedal_\(mode)"
        let best = Medal(rawValue: defaults.integer(forKey: key)) ?? .none
        let isNewBest = earned > best
        if isNewBest {
            defaults.set(earned.rawValue, forKey: key)
        }
        touchStreak()
        return (earned, isNewBest)
    }

    func bestMedal(mode: String) -> Medal {
        Medal(rawValue: defaults.integer(forKey: "MonkeysMedal_\(mode)")) ?? .none
    }

    /// Sum of best-medal values across all modes (gold=3): currency for
    /// the cosmetic palette unlocks. Max 9 with the current three modes.
    var medalScore: Int {
        ["bananas", "speed", "speed_sprint"].reduce(0) { $0 + bestMedal(mode: $1).rawValue }
    }

    // MARK: - Play streak

    private(set) var currentStreak: Int {
        get { defaults.integer(forKey: "MonkeysPlayStreak") }
        set { defaults.set(newValue, forKey: "MonkeysPlayStreak") }
    }

    /// Call whenever a run ends: extends or resets the daily play streak.
    private func touchStreak() {
        let today = Self.dayString(Date())
        let last = defaults.string(forKey: "MonkeysPlayStreakDate")
        if last == today { return }
        let yesterday = Self.dayString(Date(timeIntervalSinceNow: -86_400))
        currentStreak = (last == yesterday) ? currentStreak + 1 : 1
        defaults.set(today, forKey: "MonkeysPlayStreakDate")
    }

    // MARK: - Daily mission

    /// Deterministic mission of the day (same across launches, no scheduling).
    var todayMission: DailyMission {
        let seed = Self.daySeed()
        switch seed % 3 {
        case 0:  return DailyMission(kind: .catchGolden(3 + Int(seed / 3 % 3)))          // 3–5
        case 1:  return DailyMission(kind: .scoreRun(40 + Int(seed / 3 % 5) * 10))       // 40–80
        default: return DailyMission(kind: .reachWPM(30 + Int(seed / 3 % 4) * 10))       // 30–60
        }
    }

    private var missionProgressKey: String { "MonkeysMission_\(Self.dayString(Date()))" }

    var isMissionCompleted: Bool {
        defaults.bool(forKey: missionProgressKey + "_done")
    }

    private var missionCounter: Int {
        get { defaults.integer(forKey: missionProgressKey) }
        set { defaults.set(newValue, forKey: missionProgressKey) }
    }

    /// Golden banana caught (Banana game).
    func registerGolden() {
        guard case .catchGolden(let target) = todayMission.kind, !isMissionCompleted else { return }
        missionCounter += 1
        if missionCounter >= target { completeMission() }
    }

    /// Banana run finished with `score`.
    func registerScore(_ score: Int) {
        guard case .scoreRun(let target) = todayMission.kind, !isMissionCompleted else { return }
        if score >= target { completeMission() }
    }

    /// Speed run finished with `wpm`.
    func registerWPM(_ wpm: Int) {
        guard case .reachWPM(let target) = todayMission.kind, !isMissionCompleted else { return }
        if wpm >= target { completeMission() }
    }

    private func completeMission() {
        defaults.set(true, forKey: missionProgressKey + "_done")
    }

    /// Menu line for the mission (with progress where meaningful).
    var missionMenuTitle: String {
        if isMissionCompleted { return L.shared.s("mission_done") }
        var title = "🎯 " + todayMission.text
        if case .catchGolden(let target) = todayMission.kind, missionCounter > 0 {
            title += "  (\(missionCounter)/\(target))"
        }
        return title
    }

    // MARK: - Helpers

    private static func dayString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    /// Stable per-day seed.
    private static func daySeed() -> UInt64 {
        var hash: UInt64 = 5381
        for byte in dayString(Date()).utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }
}
