@preconcurrency import Cocoa
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let soundEngine = SoundEngine()
    private let keyboardMonitor = KeyboardMonitor()
    private let wpmTracker = WPMTracker()
    private let appProfileManager = AppProfileManager()
    private let typingStats = TypingStats()
    private var isEnabled = true
    private var permissionTimer: Timer?
    private var wpmTimer: Timer?
    private var gameWindow: GameWindow?
    private var speedTypeWindow: SpeedTypeWindow?

    // Menu item references for state updates
    private var toggleMenuItem: NSMenuItem!
    private var profileMenuItems: [NSMenuItem] = []
    private var volumeSlider: NSSlider!
    private var shortcutMenuItem: NSMenuItem!
    private var wpmMenuItem: NSMenuItem!
    private var statsMenuItem: NSMenuItem!
    private var autoMuteMenuItem: NSMenuItem!
    private var peakWpmMenuItem: NSMenuItem!

    private let allProfiles: [SoundProfile] = [
        .blue, .brown, .red, .black, .silentRed, .speedSilver,
        .gateronRed, .gateronYellow, .silentBlack,
        .typewriter, .bubbles, .retro8bit, .monkey,
    ]

    private let profileLocKeys: [String] = [
        "p_tactile_click", "p_soft_tactile", "p_light_linear", "p_heavy_linear",
        "p_quiet_light", "p_speed", "p_smooth", "p_medium", "p_quiet_heavy",
        "p_typewriter", "p_bubbles", "p_retro", "p_monkey",
    ]

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Check accessibility permission
        if !KeyboardMonitor.checkAccessibilityPermission() {
            let alert = NSAlert()
            alert.messageText = "Permesso di Accessibilità Richiesto"
            alert.informativeText = """
                Monkeys ha bisogno del permesso di Accessibilità per \
                rilevare la pressione dei tasti e riprodurre i suoni della \
                tastiera meccanica.

                Clicca OK per aprire le Impostazioni di Sistema, poi \
                abilita Monkeys nella sezione Accessibilità.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            KeyboardMonitor.requestAccessibilityPermission()
        }

        // 2. Set up keyboard monitor callbacks
        keyboardMonitor.onKeyDown = { [weak self] keyCode, isRepeat in
            guard let self else { return }
            self.soundEngine.playKeyDown(keyCode: keyCode, isRepeat: isRepeat)
            if !isRepeat {
                _ = self.wpmTracker.recordKeyPress()
                _ = self.typingStats.recordKeystroke()
            }
        }
        keyboardMonitor.onKeyUp = { [weak self] keyCode in
            guard let self else { return }
            self.soundEngine.playKeyUp(keyCode: keyCode)
        }
        keyboardMonitor.onShortcutTriggered = { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleEnabled()
            }
        }

        // 3. Start engines
        soundEngine.start()
        if !keyboardMonitor.start() {
            startPermissionCheckTimer()
        }

        // 4. Set up menu bar
        setupStatusItem()

        // 5. Start app profile manager (auto-mute in video calls)
        appProfileManager.onShouldMute = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.soundEngine.setEnabled(false)
                self.isEnabled = false
                self.toggleMenuItem.title = "🔇 Auto-Muto (videocall)"
            }
        }
        appProfileManager.onShouldUnmute = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.soundEngine.setEnabled(true)
                self.isEnabled = true
                self.toggleMenuItem.title = L.shared.s("enabled")
            }
        }
        appProfileManager.start()

        // 6. Start WPM timer
        wpmTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wpm = self.wpmTracker.currentWPM()
                let wpmEmoji: String
                if wpm >= 80 { wpmEmoji = "🚀" }
                else if wpm >= 50 { wpmEmoji = "⚡" }
                else if wpm >= 30 { wpmEmoji = "✍️" }
                else if wpm > 0 { wpmEmoji = "🐢" }
                else { wpmEmoji = "💤" }
                self.wpmMenuItem.title = "\(wpmEmoji) \(L.shared.sf("writing_wpm", wpm))"
                self.typingStats.updatePeakWPM(wpm)
                let tc = self.typingStats.getTodayCount()
                let tEmoji: String
                if tc >= 10000 { tEmoji = "🔥" }
                else if tc >= 5000 { tEmoji = "💪" }
                else if tc >= 1000 { tEmoji = "⌨️" }
                else { tEmoji = "🐵" }
                self.statsMenuItem.title = "\(tEmoji) \(L.shared.sf("today_keys", self.typingStats.formatNumber(tc)))"
                self.peakWpmMenuItem.title = L.shared.sf("record_wpm", self.typingStats.getPeakWPM())
            }
        }
        
        // 7. Silent update check at startup
        Updater.shared.checkForUpdates(silent: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        wpmTimer?.invalidate()
        keyboardMonitor.stop()
        appProfileManager.stop()
    }

    // MARK: - Menu Bar Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if #available(macOS 13.0, *),
               let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Monkeys") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⌨️"
            }
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 1. Title
        let titleItem = NSMenuItem(title: "🐒 Monkeys", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "🐒 Monkeys",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        // 2. Toggle + WPM (compact top section)
        toggleMenuItem = NSMenuItem(title: L.shared.s("enabled"), action: #selector(toggleEnabled), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        wpmMenuItem = NSMenuItem(title: L.shared.sf("writing_wpm", 0), action: nil, keyEquivalent: "")
        wpmMenuItem.isEnabled = false
        menu.addItem(wpmMenuItem)

        menu.addItem(.separator())

        // 3. Game + Shortcut
        let gameItem = NSMenuItem(title: L.shared.s("game_bananas"), action: #selector(startGame), keyEquivalent: "g")
        gameItem.target = self
        menu.addItem(gameItem)

        let speedItem = NSMenuItem(title: L.shared.s("game_speed"), action: #selector(startSpeedType), keyEquivalent: "t")
        speedItem.target = self
        menu.addItem(speedItem)

        shortcutMenuItem = NSMenuItem(title: "\(L.shared.s("shortcut_prefix")): \(getShortcutString())", action: #selector(changeShortcut), keyEquivalent: "")
        shortcutMenuItem.target = self
        menu.addItem(shortcutMenuItem)

        autoMuteMenuItem = NSMenuItem(
            title: appProfileManager.isEnabled ? L.shared.s("auto_mute_on") : L.shared.s("auto_mute_off"),
            action: #selector(toggleAutoMute), keyEquivalent: ""
        )
        autoMuteMenuItem.target = self
        menu.addItem(autoMuteMenuItem)

        menu.addItem(.separator())

        // 4. Volume (compact, no label)
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let volIcon = NSTextField(labelWithString: "🔊")
        volIcon.frame = NSRect(x: 4, y: 2, width: 20, height: 20)
        volIcon.font = NSFont.systemFont(ofSize: 12)
        sliderView.addSubview(volIcon)
        volumeSlider = NSSlider(frame: NSRect(x: 26, y: 2, width: 164, height: 20))
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 100
        volumeSlider.integerValue = 70
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        sliderView.addSubview(volumeSlider)
        let sliderMenuItem = NSMenuItem()
        sliderMenuItem.view = sliderView
        menu.addItem(sliderMenuItem)
        soundEngine.setVolume(Float(volumeSlider.integerValue) / 100.0)

        // 5. Profile submenu
        let profileItem = NSMenuItem(title: L.shared.s("sound_profile"), action: nil, keyEquivalent: "")
        let profileSubmenu = NSMenu()
        profileMenuItems = []

        for (i, key) in profileLocKeys.enumerated() {
            let item = NSMenuItem(title: L.shared.s(key), action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            profileMenuItems.append(item)
            profileSubmenu.addItem(item)
            if i == 8 { profileSubmenu.addItem(.separator()) }
        }

        profileMenuItems[0].state = .on
        soundEngine.setProfile(.blue)

        // Restore saved profile
        if let savedRaw = UserDefaults.standard.string(forKey: "MonkeysSoundProfile"),
           let savedProfile = SoundProfile(rawValue: savedRaw),
           let idx = allProfiles.firstIndex(of: savedProfile) {
            soundEngine.setProfile(savedProfile)
            for item in profileMenuItems { item.state = .off }
            profileMenuItems[idx].state = .on
        }

        menu.setSubmenu(profileSubmenu, for: profileItem)
        menu.addItem(profileItem)

        // 6. Stats submenu
        let statsItem = NSMenuItem(title: L.shared.s("statistics"), action: nil, keyEquivalent: "")
        let statsSubmenu = NSMenu()

        let todayCount = typingStats.getTodayCount()
        let emoji: String
        if todayCount >= 10000 { emoji = "🔥" }
        else if todayCount >= 5000 { emoji = "💪" }
        else if todayCount >= 1000 { emoji = "⌨️" }
        else { emoji = "🐵" }

        statsMenuItem = NSMenuItem(
            title: "\(emoji) \(L.shared.sf("today_keys", typingStats.formatNumber(todayCount)))",
            action: nil, keyEquivalent: ""
        )
        statsMenuItem.isEnabled = false
        statsSubmenu.addItem(statsMenuItem)

        peakWpmMenuItem = NSMenuItem(title: L.shared.sf("record_wpm", typingStats.getPeakWPM()), action: nil, keyEquivalent: "")
        peakWpmMenuItem.isEnabled = false
        statsSubmenu.addItem(peakWpmMenuItem)

        let totalItem = NSMenuItem(
            title: L.shared.sf("total_keys", typingStats.formatNumber(typingStats.getAllTimeCount())),
            action: nil, keyEquivalent: ""
        )
        totalItem.isEnabled = false
        statsSubmenu.addItem(totalItem)

        menu.setSubmenu(statsSubmenu, for: statsItem)
        menu.addItem(statsItem)

        // 7. Language submenu
        let langItem = NSMenuItem(title: L.shared.s("language"), action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu()
        for lang in L.Lang.allCases {
            let langMenuItem = NSMenuItem(title: L.shared.s("lang_\(lang.rawValue)"), action: #selector(changeLanguage(_:)), keyEquivalent: "")
            langMenuItem.target = self
            langMenuItem.tag = lang.hashValue
            langMenuItem.representedObject = lang.rawValue
            langMenuItem.state = (lang == L.shared.current) ? .on : .off
            langSubmenu.addItem(langMenuItem)
        }
        menu.setSubmenu(langSubmenu, for: langItem)
        menu.addItem(langItem)

        menu.addItem(.separator())

        // 8. Info + Quit
        let updateItem = NSMenuItem(title: L.shared.s("check_updates"), action: #selector(triggerCheckUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let infoItem = NSMenuItem(title: L.shared.s("info"), action: #selector(showInfo), keyEquivalent: "")
        infoItem.target = self
        menu.addItem(infoItem)

        let quitItem = NSMenuItem(title: L.shared.s("quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        toggleMenuItem.title = isEnabled ? L.shared.s("enabled") : L.shared.s("disabled")
        soundEngine.setEnabled(isEnabled)
    }

    @objc private func toggleAutoMute() {
        appProfileManager.isEnabled.toggle()
        autoMuteMenuItem.title = appProfileManager.isEnabled ? L.shared.s("auto_mute_on") : L.shared.s("auto_mute_off")
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        let volume = Float(sender.integerValue) / 100.0
        soundEngine.setVolume(volume)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        for item in profileMenuItems { item.state = .off }
        sender.state = .on
        let idx = sender.tag
        guard idx >= 0 && idx < allProfiles.count else { return }
        let profile = allProfiles[idx]
        soundEngine.setProfile(profile)
        UserDefaults.standard.set(profile.rawValue, forKey: "MonkeysSoundProfile")
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String,
              let lang = L.Lang(rawValue: code) else { return }
        L.shared.setLanguage(lang)
        statusItem.menu = buildMenu()
    }

    @objc private func triggerCheckUpdates() {
        Updater.shared.checkForUpdates(silent: false)
    }

    @objc private func showInfo() {
        let alert = NSAlert()
        alert.messageText = "🐒 Monkeys"
        alert.informativeText = """
            🐒 Monkeys v4.0

            \(L.shared.s("p_tactile_click")) · \(L.shared.s("p_soft_tactile"))
            \(L.shared.s("p_light_linear")) · \(L.shared.s("p_heavy_linear"))
            \(L.shared.s("p_quiet_light")) · \(L.shared.s("p_speed"))
            \(L.shared.s("p_smooth")) · \(L.shared.s("p_medium"))
            \(L.shared.s("p_quiet_heavy")) · \(L.shared.s("p_typewriter"))
            \(L.shared.s("p_bubbles")) · \(L.shared.s("p_retro"))
            \(L.shared.s("p_monkey"))
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func startPermissionCheckTimer() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if KeyboardMonitor.checkAccessibilityPermission() {
                    if self.keyboardMonitor.start() {
                        print("KeyboardMonitor: Started successfully after accessibility permission was granted.")
                        self.permissionTimer?.invalidate()
                        self.permissionTimer = nil
                    }
                }
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Game Launcher

    @objc private func startGame() {
        if gameWindow == nil {
            gameWindow = GameWindow()
            gameWindow?.gameView.onPlaySuccessSound = { [weak self] in
                self?.soundEngine.playSuccess()
            }
            gameWindow?.gameView.onPlayFailSound = { [weak self] in
                self?.soundEngine.playFail()
            }
            gameWindow?.gameView.onPlayComboSound = { [weak self] level in
                self?.soundEngine.playCombo(level: level)
            }
            gameWindow?.gameView.onPlayLevelUpSound = { [weak self] in
                self?.soundEngine.playLevelUp()
            }
            gameWindow?.gameView.onGameOver = { [weak self] in
                self?.soundEngine.stopMusic()
            }
            gameWindow?.gameView.onStartMusic = { [weak self] in
                self?.soundEngine.startMusic()
            }
            gameWindow?.gameView.onStopMusic = { [weak self] in
                self?.soundEngine.stopMusic()
            }
        }

        gameWindow?.gameView.resetGame()
        gameWindow?.center()
        gameWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func startSpeedType() {
        if speedTypeWindow == nil {
            speedTypeWindow = SpeedTypeWindow()
            speedTypeWindow?.speedTypeView.onPlaySuccessSound = { [weak self] in
                self?.soundEngine.playSuccess()
            }
            speedTypeWindow?.speedTypeView.onPlayFailSound = { [weak self] in
                self?.soundEngine.playFail()
            }
            speedTypeWindow?.speedTypeView.onPlayComboSound = { [weak self] level in
                self?.soundEngine.playCombo(level: level)
            }
            speedTypeWindow?.speedTypeView.onPlayLevelUpSound = { [weak self] in
                self?.soundEngine.playLevelUp()
            }
            speedTypeWindow?.speedTypeView.onStartMusic = { [weak self] in
                self?.soundEngine.startMusic()
            }
            speedTypeWindow?.speedTypeView.onStopMusic = { [weak self] in
                self?.soundEngine.stopMusic()
            }
        }

        speedTypeWindow?.speedTypeView.resetGame()
        speedTypeWindow?.center()
        speedTypeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Shortcut Helpers

    private func getShortcutString() -> String {
        let (keyCode, flags) = keyboardMonitor.currentShortcut
        return stringForShortcut(keyCode: keyCode, flags: flags)
    }

    @objc private func changeShortcut() {
        let recorder = ShortcutRecorderWindow()
        recorder.onShortcutRecorded = { [weak self] keyCode, flags in
            guard let self else { return }
            self.keyboardMonitor.setShortcut(keyCode: keyCode, flags: flags)
            self.shortcutMenuItem.title = "Scorciatoia: \(self.getShortcutString())"
            
            let alert = NSAlert()
            alert.messageText = "Scorciatoia Aggiornata"
            alert.informativeText = "Nuova scorciatoia globale impostata con successo: \(self.getShortcutString())"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        
        recorder.center()
        recorder.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Shortcut Keyboard Layout Mapping

func stringForShortcut(keyCode: Int64, flags: CGEventFlags) -> String {
    var result = ""
    if flags.contains(.maskControl) { result += "⌃" }
    if flags.contains(.maskAlternate) { result += "⌥" }
    if flags.contains(.maskShift) { result += "⇧" }
    if flags.contains(.maskCommand) { result += "⌘" }
    
    result += stringForKeyCode(keyCode)
    return result
}

func stringForKeyCode(_ keyCode: Int64) -> String {
    switch keyCode {
    case 36: return "↩︎" // Return
    case 48: return "⇥" // Tab
    case 49: return "⎵" // Space
    case 51: return "⌫" // Delete
    case 53: return "⎋" // Escape
    case 117: return "⌦" // Forward Delete
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    default:
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let dataRef = unsafeBitCast(layoutData, to: CFData.self)
            let keyLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)
            
            var deadKeys: UInt32 = 0
            var unicodeString = [UniChar](repeating: 0, count: 4)
            var actualLength = 0
            
            let status = UCKeyTranslate(
                keyLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys,
                4,
                &actualLength,
                &unicodeString
            )
            
            if status == noErr && actualLength > 0 {
                return String(utf16CodeUnits: unicodeString, count: actualLength).uppercased()
            }
        }
        return "Key \(keyCode)"
    }
}

// MARK: - ShortcutRecorderWindow

class ShortcutRecorderWindow: NSWindow {
    
    private let titleLabel = NSTextField(labelWithString: "Registrazione Scorciatoia")
    private let statusLabel = NSTextField(labelWithString: "Premi la combinazione di tasti desiderata...")
    private let escapeLabel = NSTextField(labelWithString: "Premi ⎋ per annullare")
    
    var onShortcutRecorded: ((Int64, CGEventFlags) -> Void)?
    
    init() {
        let styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        self.title = ""
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98)
        self.isReleasedWhenClosed = false
        
        setupViews()
    }
    
    private func setupViews() {
        guard let contentView = self.contentView else { return }
        
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 110, width: 300, height: 24)
        contentView.addSubview(titleLabel)
        
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 20, y: 50, width: 300, height: 48)
        statusLabel.cell?.wraps = true
        contentView.addSubview(statusLabel)
        
        escapeLabel.font = NSFont.systemFont(ofSize: 11)
        escapeLabel.alignment = .center
        escapeLabel.textColor = .tertiaryLabelColor
        escapeLabel.frame = NSRect(x: 20, y: 15, width: 300, height: 18)
        contentView.addSubview(escapeLabel)
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        
        // Escape cancels (when pressed without modifiers)
        if keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            self.close()
            return
        }
        
        // Determine modifier flags
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var cgFlags: CGEventFlags = []
        if modifiers.contains(.control) { cgFlags.insert(.maskControl) }
        if modifiers.contains(.shift) { cgFlags.insert(.maskShift) }
        if modifiers.contains(.option) { cgFlags.insert(.maskAlternate) }
        if modifiers.contains(.command) { cgFlags.insert(.maskCommand) }
        
        if cgFlags.isEmpty {
            // No modifiers held
            statusLabel.stringValue = "La scorciatoia deve contenere almeno un modificatore (⌃, ⌥, ⇧, ⌘)!"
            statusLabel.textColor = .systemRed
            return
        }
        
        // We have modifiers and a key! Save it.
        onShortcutRecorded?(keyCode, cgFlags)
        self.close()
    }
    
    override func flagsChanged(with event: NSEvent) {
        // Update display to show modifiers currently held down
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !modifiers.isEmpty {
            var tempStr = ""
            if modifiers.contains(.control) { tempStr += "⌃ " }
            if modifiers.contains(.option) { tempStr += "⌥ " }
            if modifiers.contains(.shift) { tempStr += "⇧ " }
            if modifiers.contains(.command) { tempStr += "⌘ " }
            statusLabel.stringValue = "Registrazione: \(tempStr)..."
            statusLabel.textColor = .labelColor
        } else {
            statusLabel.stringValue = "Premi la combinazione di tasti desiderata..."
            statusLabel.textColor = .secondaryLabelColor
        }
    }
}
