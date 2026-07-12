// StudyList.swift
// MonKeys
//
// The user's custom typing list for the Speed Challenge: vocabulary words,
// definitions, formulas — one entry per line, imported from a plain-text
// file. Stored in Application Support/MonKeys, fully local, loaded once and
// cached (the game reads it inside its render loop).

import Foundation

enum StudyList {

    private static let lock = NSLock()
    /// Guarded by `lock` — safe despite the annotation.
    nonisolated(unsafe) private static var cache: [String]?

    static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MonKeys/study_list.txt")
    }

    static var isAvailable: Bool { !words().isEmpty }

    static func words() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let loaded: [String]
        if let url = fileURL, let raw = try? String(contentsOf: url, encoding: .utf8) {
            loaded = sanitize(raw)
        } else {
            loaded = []
        }
        cache = loaded
        return loaded
    }

    /// Parses raw text into clean entries: one per line, first column of
    /// CSV-ish lines (tab / semicolon / comma), trimmed, deduplicated,
    /// length-capped. Keeps at most 500 entries.
    static func sanitize(_ raw: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            var entry = String(line)
            if let cut = entry.firstIndex(where: { $0 == "\t" || $0 == ";" || $0 == "," }) {
                entry = String(entry[..<cut])
            }
            entry = entry.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty, entry.count <= 40 else { continue }
            guard seen.insert(entry.lowercased()).inserted else { continue }
            out.append(entry)
            if out.count >= 500 { break }
        }
        return out
    }

    /// Saves sanitized entries and refreshes the cache; returns how many
    /// entries were kept (0 = nothing usable, nothing written).
    @discardableResult
    static func importText(_ raw: String) -> Int {
        let entries = sanitize(raw)
        guard !entries.isEmpty, let url = fileURL else { return 0 }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try entries.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return 0
        }
        lock.lock()
        cache = entries
        lock.unlock()
        return entries.count
    }
}
