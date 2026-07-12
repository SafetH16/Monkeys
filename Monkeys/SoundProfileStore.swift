// SoundProfileStore.swift
// MonKeys
//
// Persistence for user-created sound presets, plus validated JSON
// import/export. Storage lives in the sandbox container's Application
// Support directory; every write is atomic and every import is size-,
// schema- and range-checked so a malformed file can never crash the app
// or produce degenerate audio.

import Foundation

struct UserPreset: Codable, Equatable {
    var name: String
    var params: SoundParameters
}

/// On-disk / interchange format. `schemaVersion` lets future versions
/// migrate old files instead of rejecting them.
private struct PresetDocument: Codable {
    var schemaVersion: Int
    var presets: [UserPreset]
}

enum PresetImportError: LocalizedError {
    case fileTooLarge
    case unreadable
    case badSchema
    case empty
    case tooManyPresets

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:   return "The file is larger than 256 KB — not a valid MonKeys preset file."
        case .unreadable:     return "The file could not be parsed as MonKeys preset JSON."
        case .badSchema:      return "Unsupported preset schema version."
        case .empty:          return "The file contains no presets."
        case .tooManyPresets: return "Preset limit reached (max 50 user presets)."
        }
    }
}

final class SoundProfileStore: @unchecked Sendable {

    static let schemaVersion = 1
    static let maxPresets = 50
    static let maxImportBytes = 256 * 1024

    private let lock = NSLock()
    private var presets: [UserPreset] = []

    init() {
        presets = Self.loadFromDisk()
    }

    // MARK: - Storage location

    private static func storageURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("MonKeys", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir.appendingPathComponent("user_presets.json")
    }

    // MARK: - Load / save

    private static func loadFromDisk() -> [UserPreset] {
        guard let url = storageURL(),
              let data = try? Data(contentsOf: url),
              data.count <= maxImportBytes,
              let doc = try? JSONDecoder().decode(PresetDocument.self, from: data),
              doc.schemaVersion <= schemaVersion else {
            // Missing or corrupt store: start empty, never crash, and never
            // overwrite the broken file until the user actually saves.
            return []
        }
        return sanitize(doc.presets)
    }

    private func saveToDisk() {
        guard let url = Self.storageURL() else { return }
        let doc = PresetDocument(schemaVersion: Self.schemaVersion, presets: presets)
        guard let data = try? JSONEncoder().encode(doc) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Validation

    /// Trims, de-controls and length-limits a preset name. Returns nil for
    /// names that end up empty.
    static func sanitizeName(_ raw: String) -> String? {
        var cleaned = raw
            .components(separatedBy: .controlCharacters).joined()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 40 { cleaned = String(cleaned.prefix(40)) }
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func sanitize(_ raw: [UserPreset]) -> [UserPreset] {
        var seen = Set<String>()
        var result: [UserPreset] = []
        for preset in raw.prefix(maxPresets) {
            guard let name = sanitizeName(preset.name), !seen.contains(name) else { continue }
            var p = preset
            p.name = name
            p.params.clampToSafeRanges()
            seen.insert(name)
            result.append(p)
        }
        return result
    }

    /// Returns `base` or `base (2)`, `base (3)`… whichever is free.
    private func uniqueName(for base: String) -> String {
        let existing = Set(presets.map { $0.name })
        if !existing.contains(base) { return base }
        for i in 2...999 {
            let candidate = "\(base) (\(i))"
            if !existing.contains(candidate) { return candidate }
        }
        return "\(base) \(UUID().uuidString.prefix(4))"
    }

    // MARK: - Public API

    func all() -> [UserPreset] {
        lock.lock()
        defer { lock.unlock() }
        return presets
    }

    func preset(named name: String) -> UserPreset? {
        lock.lock()
        defer { lock.unlock() }
        return presets.first { $0.name == name }
    }

    /// Adds a preset (auto-renaming on collision). Returns the stored preset,
    /// or nil if the name is invalid or the store is full.
    @discardableResult
    func add(name rawName: String, params: SoundParameters) -> UserPreset? {
        lock.lock()
        defer { lock.unlock() }
        guard presets.count < Self.maxPresets,
              let base = Self.sanitizeName(rawName) else { return nil }
        var safe = params
        safe.clampToSafeRanges()
        let preset = UserPreset(name: uniqueName(for: base), params: safe)
        presets.append(preset)
        saveToDisk()
        return preset
    }

    /// Updates the parameters of an existing preset.
    func update(name: String, params: SoundParameters) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = presets.firstIndex(where: { $0.name == name }) else { return }
        var safe = params
        safe.clampToSafeRanges()
        presets[idx].params = safe
        saveToDisk()
    }

    @discardableResult
    func rename(from oldName: String, to rawNewName: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = presets.firstIndex(where: { $0.name == oldName }),
              let base = Self.sanitizeName(rawNewName) else { return nil }
        let newName = uniqueName(for: base)
        presets[idx].name = newName
        saveToDisk()
        return newName
    }

    func remove(name: String) {
        lock.lock()
        defer { lock.unlock() }
        presets.removeAll { $0.name == name }
        saveToDisk()
    }

    // MARK: - Export / Import

    /// Serializes the given presets as a standalone document.
    func exportData(_ toExport: [UserPreset]) -> Data? {
        let doc = PresetDocument(schemaVersion: Self.schemaVersion, presets: toExport)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(doc)
    }

    /// Validates and merges presets from `url`. Never overwrites an existing
    /// preset: collisions are auto-renamed. Returns the names actually added.
    func importPresets(from url: URL) throws -> [String] {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= Self.maxImportBytes else {
            throw PresetImportError.fileTooLarge
        }
        guard let data = try? Data(contentsOf: url) else {
            throw PresetImportError.unreadable
        }
        guard let doc = try? JSONDecoder().decode(PresetDocument.self, from: data) else {
            throw PresetImportError.unreadable
        }
        guard doc.schemaVersion >= 1 && doc.schemaVersion <= Self.schemaVersion else {
            throw PresetImportError.badSchema
        }
        let incoming = Self.sanitize(doc.presets)
        guard !incoming.isEmpty else { throw PresetImportError.empty }

        lock.lock()
        defer { lock.unlock() }
        guard presets.count < Self.maxPresets else { throw PresetImportError.tooManyPresets }

        var added: [String] = []
        for preset in incoming {
            guard presets.count < Self.maxPresets else { break }
            let name = uniqueName(for: preset.name)
            presets.append(UserPreset(name: name, params: preset.params))
            added.append(name)
        }
        saveToDisk()
        return added
    }
}
