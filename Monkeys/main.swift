import Cocoa

// Disable output buffering so that logs appear immediately
setbuf(stdout, nil)

// One-time migration from the App Sandbox container.
//
// Up to v2.0.0 the app was sandboxed, so preferences and user presets lived
// in ~/Library/Containers/com.safethalipaj.MonkeysApp/. The sandbox was
// dropped in v2.1.0 (a self-replacing auto-updater cannot write into
// /Applications from inside a sandbox), which moves UserDefaults to the
// standard location — without this import, all statistics, medals, streaks
// and presets would silently reset. Must run before anything reads defaults.
func migrateFromSandboxContainerIfNeeded() {
    let defaults = UserDefaults.standard
    let markerKey = "MonkeysSandboxMigrated"
    guard !defaults.bool(forKey: markerKey) else { return }
    defaults.set(true, forKey: markerKey)

    let home = FileManager.default.homeDirectoryForCurrentUser
    let container = home.appendingPathComponent(
        "Library/Containers/com.safethalipaj.MonkeysApp/Data", isDirectory: true)

    // 1. Preferences: import every Monkeys* key that is not already set.
    let plist = container.appendingPathComponent(
        "Library/Preferences/com.safethalipaj.MonkeysApp.plist")
    if let dict = NSDictionary(contentsOf: plist) as? [String: Any] {
        for (key, value) in dict where key.hasPrefix("Monkeys") {
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }

    // 2. User presets (and future data files) in Application Support/MonKeys.
    let oldSupport = container.appendingPathComponent("Library/Application Support/MonKeys")
    if let realSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask).first {
        let newSupport = realSupport.appendingPathComponent("MonKeys", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldSupport.path),
           !FileManager.default.fileExists(atPath: newSupport.path) {
            try? FileManager.default.copyItem(at: oldSupport, to: newSupport)
        }
    }
}

migrateFromSandboxContainerIfNeeded()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
