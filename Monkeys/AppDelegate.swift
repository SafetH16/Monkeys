@preconcurrency import Cocoa
import Carbon
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

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
    private var statsWindow: StatsWindow?
    private var onboardingWindow: OnboardingWindow?
    private var settingsWindow: SettingsWindow?
    private var visualizerPanel: VisualizerPanel?
    private let presetStore = SoundProfileStore()

    /// True while sounds are muted by a meeting/app/device rule (not by the user).
    private var isAutoMuted = false
    private var isFocusMode = false
    private var isGameMode = false

    // Device awareness: where the audio is going right now, and the rules
    // that depend on it. `lastAppState` caches the app/meeting layer so the
    // final state can be recomposed when only the output device changes.
    private let audioMonitor = AudioOutputMonitor()
    private let deviceRuleStore = DeviceRuleStore()
    private var lastAppState = AppSoundState(autoMuted: false, profileRaw: nil, volume: nil, reason: nil)

    // The menu is rebuilt on every open (menuNeedsUpdate), so almost no
    // item references are needed. The slider label survives while dragging.
    private var volumeSliderLabel: NSTextField?
    private var lastAutoMuteReason: AutoMuteReason?

    private let allProfiles: [SoundProfile] = [
        .blue, .brown, .red, .black, .silentRed, .speedSilver,
        .gateronRed, .gateronYellow, .silentBlack,
        .deepThock, .silentOffice, .terminal, .softMac,
        .typewriter, .bubbles, .retro8bit, .monkey, .waxSlime,
    ]

    private let profileLocKeys: [String] = [
        "p_tactile_click", "p_soft_tactile", "p_light_linear", "p_heavy_linear",
        "p_quiet_light", "p_speed", "p_smooth", "p_medium", "p_quiet_heavy",
        "p_deep_thock", "p_silent_office", "p_terminal", "p_soft_mac",
        "p_typewriter", "p_bubbles", "p_retro", "p_monkey", "p_wax_slime",
    ]

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Check accessibility permission — friendly onboarding window
        if !KeyboardMonitor.checkAccessibilityPermission() {
            let onboarding = OnboardingWindow()
            onboarding.onOpenSettings = {
                KeyboardMonitor.requestAccessibilityPermission()
                // The AX prompt only appears the very first time an app asks.
                // Open the Accessibility pane directly so the button always
                // does something visible; the window closes by itself once
                // the permission is granted (see permission timer).
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            onboardingWindow = onboarding
            onboarding.center()
            onboarding.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        // 2. Set up keyboard monitor callbacks
        keyboardMonitor.onKeyDown = { [weak self] keyCode, isRepeat in
            guard let self else { return }
            self.soundEngine.playKeyDown(keyCode: keyCode, isRepeat: isRepeat)
            if !isRepeat {
                _ = self.wpmTracker.recordKeyPress()
                if AppSettings.statsEnabled {
                    self.typingStats.recordKeystroke(keyCode: keyCode)
                }
                Task { @MainActor [weak self] in
                    guard let self, let panel = self.visualizerPanel, panel.isVisible else { return }
                    panel.visualizerView.highlight(keyCode: keyCode)
                }
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

        // 5. Start app profile manager (per-app rules + meeting mode)
        appProfileManager.onApplyState = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.applyAppSoundState(state)
            }
        }
        appProfileManager.start()

        // 5b. Watch the default audio output device (AirPods vs speakers…):
        // recompose the sound state whenever it changes.
        audioMonitor.onChange = {
            Task { @MainActor [weak self] in
                self?.applyEffectiveState()
            }
        }
        audioMonitor.start()

        // 6. Housekeeping timer: peak-WPM tracking + batched stats flush.
        // (The menu needs no timer: it rebuilds itself on every open.)
        wpmTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.typingStats.updatePeakWPM(self.wpmTracker.currentWPM())
                self.typingStats.flushIfDirty()
            }
        }

        // 6b. Apply persisted audio settings (the menu no longer does this).
        // reevaluate() feeds the frontmost app through the full state
        // composition, so rules and device layers apply from the first key.
        soundEngine.setMusicEnabled(AppSettings.musicEnabled)
        appProfileManager.reevaluate()
        
        // 7. Restore the keyboard visualizer if it was visible last session
        if UserDefaults.standard.bool(forKey: SettingsKey.visualizerVisible) {
            showVisualizer()
        }

        // 8. Silent update check at startup
        Updater.shared.checkForUpdates(silent: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        wpmTimer?.invalidate()
        keyboardMonitor.stop()
        appProfileManager.stop()
        typingStats.flush()
    }

    // MARK: - Menu Bar Setup

    private func updateStatusItem() {
        if let button = statusItem.button {
            let imgName = NSImage.Name("statusBarIcon.png")
            let fallbackName = NSImage.Name("statusBarIcon")
            if let image = NSImage(named: imgName) ?? NSImage(named: fallbackName) {
                image.isTemplate = true
                let active = isEnabled && !isAutoMuted
                button.image = active ? image : Self.slashedIcon(from: image)
                button.title = ""
                button.contentTintColor = active ? nil : NSColor.labelColor.withAlphaComponent(0.45)
            } else {
                button.image = nil
                button.title = (isEnabled && !isAutoMuted) ? "🐵" : "🙉"
            }
        }
    }

    /// Monkey icon with a diagonal slash (native "speaker.slash" idiom) for
    /// the muted state. The knockout stroke keeps a gap around the slash so
    /// it stays readable over the silhouette.
    private static func slashedIcon(from base: NSImage) -> NSImage {
        let img = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let knockout = NSBezierPath()
            knockout.move(to: NSPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY - rect.height * 0.10))
            knockout.line(to: NSPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.10))
            knockout.lineWidth = rect.width * 0.24
            knockout.lineCapStyle = .round
            NSColor.black.setStroke()
            knockout.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + rect.width * 0.13, y: rect.maxY - rect.height * 0.13))
            slash.line(to: NSPoint(x: rect.maxX - rect.width * 0.13, y: rect.minY + rect.height * 0.13))
            slash.lineWidth = rect.width * 0.09
            slash.lineCapStyle = .round
            NSColor.black.setStroke()
            slash.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Menu (rebuilt on every open — always fresh, no timers)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        rebuildRootMenu(menu)
    }

    private func rebuildRootMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // ── Status block: state + typing at a glance ──
        let header = infoItem(statusLine(), size: 12, bold: true)
        header.image = MascotIcon.glyph(size: 18)
        menu.addItem(header)
        let wpm = wpmTracker.currentWPM()
        let today = typingStats.formatNumber(typingStats.getTodayCount())
        menu.addItem(infoItem(L.shared.sf("status_typing", wpm, today), size: 11, bold: false))
        menu.addItem(.separator())

        // ── Quick controls: the three everyday actions ──
        let soundsItem = NSMenuItem(title: L.shared.s("menu_sounds"), action: #selector(toggleEnabled), keyEquivalent: "")
        soundsItem.target = self
        soundsItem.state = (isEnabled && !isAutoMuted) ? .on : .off
        soundsItem.image = symbol("speaker.wave.2")
        applyShortcutEquivalent(to: soundsItem)
        menu.addItem(soundsItem)

        menu.addItem(volumeSliderItem())

        let presetItem = NSMenuItem(title: L.shared.s("menu_preset"), action: nil, keyEquivalent: "")
        presetItem.image = symbol("slider.horizontal.3")
        menu.setSubmenu(buildPresetSubmenu(), for: presetItem)
        menu.addItem(presetItem)
        menu.addItem(.separator())

        // ── Context & modes ──
        menu.addItem(currentAppItem())

        let modesItem = NSMenuItem(title: L.shared.s("menu_modes"), action: nil, keyEquivalent: "")
        modesItem.image = symbol("switch.2")
        menu.setSubmenu(buildModesSubmenu(), for: modesItem)
        menu.addItem(modesItem)

        let visualizerItem = NSMenuItem(title: "Visualizer", action: #selector(toggleVisualizer), keyEquivalent: "")
        visualizerItem.target = self
        visualizerItem.state = (visualizerPanel?.isVisible ?? false) ? .on : .off
        visualizerItem.image = symbol("keyboard")
        menu.addItem(visualizerItem)
        menu.addItem(.separator())

        // ── Extras & panels ──
        let gamesItem = NSMenuItem(title: L.shared.s("menu_games"), action: nil, keyEquivalent: "")
        gamesItem.image = symbol("gamecontroller")
        menu.setSubmenu(buildGamesSubmenu(), for: gamesItem)
        menu.addItem(gamesItem)

        let statsItem = NSMenuItem(title: L.shared.s("menu_stats_panel"), action: #selector(openStatsPanel), keyEquivalent: "")
        statsItem.target = self
        statsItem.image = symbol("chart.bar")
        menu.addItem(statsItem)

        let settingsItem = NSMenuItem(title: L.shared.s("menu_settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = symbol("gearshape")
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L.shared.s("menu_quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Menu builders

    /// First menu row: answers "is it playing, with which voice — and if
    /// not, exactly why?" without opening anything else.
    private func statusLine() -> String {
        let front = appProfileManager.frontmostApp?.name ?? "—"
        let prefix = "MonKeys — "
        if isAutoMuted {
            switch lastAutoMuteReason {
            case .deviceRule:
                return prefix + L.shared.sf("status_muted_device", audioMonitor.current.name)
            case .appRule:
                return prefix + L.shared.sf("status_muted_rule", front)
            default:
                return prefix + L.shared.sf("status_muted_meeting", front)
            }
        }
        if !isEnabled {
            return prefix + L.shared.s("status_paused")
        }
        if appProfileManager.isOverrideActive {
            return prefix + L.shared.sf("status_override", front)
        }
        if isFocusMode {
            return prefix + L.shared.s("status_focus")
        }
        return prefix + L.shared.sf("status_active", currentVoiceName())
    }

    private func currentVoiceName() -> String {
        if let custom = AppSettings.customPresetName {
            return custom
        }
        if let raw = AppSettings.savedProfileRaw,
           let profile = SoundProfile(rawValue: raw),
           let idx = allProfiles.firstIndex(of: profile) {
            return L.shared.s(profileLocKeys[idx])
        }
        return L.shared.s(profileLocKeys[0])
    }

    private func infoItem(_ text: String, size: CGFloat, bold: Bool) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: bold ? NSFont.systemFont(ofSize: size, weight: .semibold)
                        : NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    /// Shows the user's global shortcut as a native key equivalent on the
    /// sounds toggle (display only — the real hook is the CGEvent tap).
    private func applyShortcutEquivalent(to item: NSMenuItem) {
        let (code, flags) = keyboardMonitor.currentShortcut
        let keyString = stringForKeyCode(code)
        guard keyString.count == 1 else { return }
        item.keyEquivalent = keyString.lowercased()
        var mods: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { mods.insert(.control) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskCommand) { mods.insert(.command) }
        item.keyEquivalentModifierMask = mods
    }

    private func volumeSliderItem() -> NSMenuItem {
        // A second line under the slider names the current output device —
        // that volume is going somewhere, and the menu should say where.
        let deviceName = audioMonitor.current.name
        let hasDevice = !deviceName.isEmpty
        let height: CGFloat = hasDevice ? 40 : 26
        let rowY: CGFloat = hasDevice ? 17 : 3
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: height))

        let iconView = NSImageView(frame: NSRect(x: 14, y: rowY + 2, width: 16, height: 16))
        iconView.image = symbol("speaker.wave.2.fill")
        iconView.contentTintColor = .secondaryLabelColor
        container.addSubview(iconView)

        let slider = NSSlider(frame: NSRect(x: 36, y: rowY, width: 138, height: 20))
        slider.minValue = 0
        slider.maxValue = 100
        slider.integerValue = AppSettings.volume
        slider.target = self
        slider.action = #selector(volumeChanged(_:))
        container.addSubview(slider)

        let label = NSTextField(labelWithString: "\(AppSettings.volume)%")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.frame = NSRect(x: 178, y: rowY + 2, width: 40, height: 16)
        container.addSubview(label)
        volumeSliderLabel = label

        if hasDevice {
            let deviceLabel = NSTextField(labelWithString: L.shared.sf("menu_on_device", deviceName))
            deviceLabel.font = .systemFont(ofSize: 10)
            deviceLabel.textColor = .tertiaryLabelColor
            deviceLabel.lineBreakMode = .byTruncatingTail
            deviceLabel.frame = NSRect(x: 37, y: 3, width: 180, height: 13)
            container.addSubview(deviceLabel)
        }

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func buildPresetSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let activeRaw = AppSettings.customPresetName == nil ? AppSettings.savedProfileRaw : nil

        for (i, key) in profileLocKeys.enumerated() {
            let item = NSMenuItem(title: L.shared.s(key), action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (activeRaw == allProfiles[i].rawValue) ? .on : .off
            submenu.addItem(item)
            if i == 8 || i == 12 { submenu.addItem(.separator()) }
        }

        let userPresets = presetStore.all()
        if !userPresets.isEmpty {
            submenu.addItem(.separator())
            for preset in userPresets {
                let item = NSMenuItem(title: "👤 \(preset.name)", action: #selector(selectUserPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.name
                item.state = (AppSettings.customPresetName == preset.name) ? .on : .off
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())
        let previewItem = NSMenuItem(title: L.shared.s("menu_preview"), action: #selector(playTestSound), keyEquivalent: "")
        previewItem.target = self
        submenu.addItem(previewItem)
        return submenu
    }

    /// Contextual submenu named (and iconed) after the frontmost app.
    private func currentAppItem() -> NSMenuItem {
        let item = NSMenuItem()
        guard let front = appProfileManager.frontmostApp else {
            item.title = L.shared.s("menu_current_app")
            item.isEnabled = false
            return item
        }
        item.title = front.name
        if let icon = NSWorkspace.shared.frontmostApplication?.icon {
            let resized = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                icon.draw(in: rect)
                return true
            }
            item.image = resized
        }

        let submenu = NSMenu()
        let rule = appProfileManager.rules.first { $0.bundleID == front.bundleID }

        let muteItem = NSMenuItem(title: L.shared.sf("menu_mute_in", front.name),
                                  action: #selector(muteForCurrentApp), keyEquivalent: "")
        muteItem.target = self
        muteItem.state = (rule?.enabled == true && rule?.muted == true) ? .on : .off
        submenu.addItem(muteItem)

        let ruleKey = rule == nil ? "menu_rule_for" : "menu_rule_edit"
        let ruleAction = rule == nil ? #selector(createProfileForCurrentApp) : #selector(openSettings)
        let ruleItem = NSMenuItem(title: L.shared.sf(ruleKey, front.name), action: ruleAction, keyEquivalent: "")
        ruleItem.target = self
        submenu.addItem(ruleItem)

        submenu.addItem(.separator())
        let statusText: String
        if let rule {
            var parts: [String] = []
            if rule.muted { parts.append("🔇") }
            if let raw = rule.profileRaw { parts.append(raw) }
            if let volume = rule.volume { parts.append("\(volume)%") }
            statusText = L.shared.sf("menu_rule_active", parts.isEmpty ? "✓" : parts.joined(separator: " · "))
        } else {
            statusText = L.shared.s("menu_rule_none")
        }
        submenu.addItem(infoItem(statusText, size: 11, bold: false))

        item.submenu = submenu
        return item
    }

    private func buildModesSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let focusItem = NSMenuItem(title: "Focus", action: #selector(toggleFocusMode), keyEquivalent: "")
        focusItem.target = self
        focusItem.state = isFocusMode ? .on : .off
        if #available(macOS 14.4, *) { focusItem.subtitle = L.shared.s("sub_focus") }
        submenu.addItem(focusItem)

        let gameItem = NSMenuItem(title: L.shared.s("menu_mode_game"), action: #selector(toggleGameMode), keyEquivalent: "")
        gameItem.target = self
        gameItem.state = isGameMode ? .on : .off
        if #available(macOS 14.4, *) { gameItem.subtitle = L.shared.s("sub_game") }
        submenu.addItem(gameItem)

        submenu.addItem(.separator())

        let meetingsItem = NSMenuItem(title: L.shared.s("menu_mode_meetings"), action: #selector(toggleAutoMute), keyEquivalent: "")
        meetingsItem.target = self
        meetingsItem.state = appProfileManager.isEnabled ? .on : .off
        submenu.addItem(meetingsItem)

        return submenu
    }

    private func buildGamesSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let bananasItem = NSMenuItem(title: L.shared.s("game_bananas"), action: #selector(startGame), keyEquivalent: "g")
        bananasItem.target = self
        submenu.addItem(bananasItem)

        let speedItem = NSMenuItem(title: L.shared.s("game_speed"), action: #selector(startSpeedType), keyEquivalent: "t")
        speedItem.target = self
        submenu.addItem(speedItem)

        submenu.addItem(.separator())

        let musicItem = NSMenuItem(title: L.shared.s("menu_music"), action: #selector(toggleMusic), keyEquivalent: "")
        musicItem.target = self
        musicItem.state = AppSettings.musicEnabled ? .on : .off
        submenu.addItem(musicItem)

        submenu.addItem(.separator())
        submenu.addItem(infoItem(GameProgress.shared.missionMenuTitle, size: 11, bold: false))
        submenu.addItem(infoItem(L.shared.sf("streak_days", GameProgress.shared.currentStreak), size: 11, bold: false))

        return submenu
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        if isAutoMuted {
            // Manual unmute during an auto-mute: override for the current app.
            isAutoMuted = false
            isEnabled = true
            appProfileManager.setManualOverrideForCurrentApp()
        } else {
            isEnabled.toggle()
        }
        soundEngine.setEnabled(isEnabled)
        updateStatusItem()
    }

    /// Caches the app/meeting layer from AppProfileManager and recomposes.
    private func applyAppSoundState(_ state: AppSoundState) {
        lastAppState = state
        applyEffectiveState()
    }

    /// Composes the final sound state from every layer. Priority, highest
    /// first: global manual mute > manual unmute override > meeting >
    /// app rule > device rule > global settings. Auto-mute never flips
    /// `isEnabled`.
    private func applyEffectiveState() {
        let state = lastAppState
        let deviceRule = deviceRuleStore.rule(for: audioMonitor.current.category)

        var autoMuted = state.autoMuted
        var reason = state.reason
        if !autoMuted, let deviceRule, deviceRule.muted, !appProfileManager.isOverrideActive {
            autoMuted = true
            reason = .deviceRule
        }
        isAutoMuted = autoMuted
        lastAutoMuteReason = autoMuted ? reason : nil

        // Volume: app rule > device rule > global (focus scales the result).
        let baseVolume = state.volume ?? deviceRule?.volume ?? AppSettings.volume
        let scale: Float = isFocusMode ? 0.3 : 1.0
        soundEngine.setVolume(Float(baseVolume) / 100.0 * scale)

        // Voice: focus forces the quiet voice, then app rule, then the user's.
        if isFocusMode {
            soundEngine.setProfile(.silentOffice)
        } else if let raw = state.profileRaw, let ruleProfile = SoundProfile(rawValue: raw) {
            soundEngine.setProfile(ruleProfile)
        } else {
            restoreUserVoice()
        }

        soundEngine.setEnabled(isEnabled && !autoMuted)

        updateStatusItem()
    }

    /// Restores the user's chosen voice: custom preset if one is active,
    /// otherwise the saved built-in profile.
    private func restoreUserVoice() {
        if let customName = AppSettings.customPresetName,
           let preset = presetStore.preset(named: customName) {
            soundEngine.setCustomVoice(preset.params)
        } else if let raw = AppSettings.savedProfileRaw,
                  let saved = SoundProfile(rawValue: raw) {
            soundEngine.setProfile(saved)
        } else {
            soundEngine.setProfile(.blue)
        }
    }

    @objc private func toggleFocusMode() {
        isFocusMode.toggle()
        applyEffectiveState()
    }

    @objc private func toggleGameMode() {
        isGameMode.toggle()
        soundEngine.setGameMode(isGameMode)
    }

    @objc private func muteForCurrentApp() {
        guard let front = appProfileManager.frontmostApp else { return }
        if var rule = appProfileManager.rules.first(where: { $0.bundleID == front.bundleID }) {
            rule.muted.toggle()
            rule.enabled = true
            appProfileManager.upsertRule(rule)
        } else {
            var rule = PerAppRule(bundleID: front.bundleID, appName: front.name)
            rule.muted = true
            appProfileManager.upsertRule(rule)
        }
    }

    @objc private func createProfileForCurrentApp() {
        guard let front = appProfileManager.frontmostApp else { return }
        var rule = appProfileManager.rules.first { $0.bundleID == front.bundleID }
            ?? PerAppRule(bundleID: front.bundleID, appName: front.name)
        rule.profileRaw = AppSettings.savedProfileRaw
        rule.volume = AppSettings.volume
        rule.enabled = true
        appProfileManager.upsertRule(rule)
        openSettings()
    }

    @objc private func toggleVisualizer() {
        if let panel = visualizerPanel, panel.isVisible {
            panel.visualizerView.stopTimer()
            panel.orderOut(nil)
            UserDefaults.standard.set(false, forKey: SettingsKey.visualizerVisible)
        } else {
            showVisualizer()
        }
    }

    private func showVisualizer() {
        if visualizerPanel == nil {
            visualizerPanel = VisualizerPanel()
            // Default position: bottom center of the main screen
            if let screen = NSScreen.main, visualizerPanel?.frameAutosaveName.isEmpty == false {
                let frame = visualizerPanel?.frame ?? .zero
                if frame.origin == .zero {
                    let x = screen.visibleFrame.midX - 170
                    let y = screen.visibleFrame.minY + 60
                    visualizerPanel?.setFrameOrigin(NSPoint(x: x, y: y))
                }
            }
        }
        visualizerPanel?.orderFront(nil)
        UserDefaults.standard.set(true, forKey: SettingsKey.visualizerVisible)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = SettingsWindow(
                engine: soundEngine,
                presetStore: presetStore,
                profileManager: appProfileManager,
                typingStats: typingStats,
                keyboardMonitor: keyboardMonitor,
                deviceRuleStore: deviceRuleStore,
                audioMonitor: audioMonitor
            )
            window.onDeviceRulesChanged = { [weak self] in
                self?.applyEffectiveState()
            }
            window.isSoundsEnabled = { [weak self] in self?.isEnabled ?? true }
            window.onSetSoundsEnabled = { [weak self] enabled in
                guard let self else { return }
                self.isEnabled = enabled
                self.soundEngine.setEnabled(enabled && !self.isAutoMuted)
                self.updateStatusItem()
            }
            window.onGlobalChange = { [weak self] in
                self?.updateStatusItem()
            }
            settingsWindow = window
        }
        settingsWindow?.refreshGeneralTab()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAutoMute() {
        appProfileManager.isEnabled.toggle()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        let volume = Float(sender.integerValue) / 100.0
        soundEngine.setVolume(volume * (isFocusMode ? 0.3 : 1.0))
        UserDefaults.standard.set(sender.integerValue, forKey: "MonkeysVolume")
        volumeSliderLabel?.stringValue = "\(sender.integerValue)%"
    }

    @objc private func playTestSound() {
        soundEngine.playTestSound()
    }

    @objc private func selectUserPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let preset = presetStore.preset(named: name) else { return }
        soundEngine.setCustomVoice(preset.params)
        AppSettings.customPresetName = name
        soundEngine.playPreviewParams(preset.params)
    }

    @objc private func openStatsPanel() {
        if statsWindow == nil {
            statsWindow = StatsWindow()
        }
        statsWindow?.statsView.reload(from: typingStats)
        statsWindow?.center()
        statsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleMusic() {
        let enabled = !(UserDefaults.standard.object(forKey: "MonkeysMusicEnabled") as? Bool ?? true)
        UserDefaults.standard.set(enabled, forKey: "MonkeysMusicEnabled")
        soundEngine.setMusicEnabled(enabled)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0 && idx < allProfiles.count else { return }
        let profile = allProfiles[idx]
        soundEngine.setProfile(profile)
        UserDefaults.standard.set(profile.rawValue, forKey: SettingsKey.soundProfile)
        AppSettings.customPresetName = nil
        // Audition the new profile right away
        soundEngine.playPreviewClick(profile)
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
                        self.onboardingWindow?.close()
                        self.onboardingWindow = nil
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
            gameWindow?.gameView.onPlayGoldenSound = { [weak self] in
                self?.soundEngine.playGolden()
            }
            gameWindow?.gameView.onPlayGameOverSound = { [weak self] in
                self?.soundEngine.playGameOver()
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
            gameWindow?.gameView.onPauseMusic = { [weak self] in
                self?.soundEngine.pauseMusic()
            }
            gameWindow?.gameView.onResumeMusic = { [weak self] in
                self?.soundEngine.resumeMusic()
            }
            gameWindow?.gameView.onDuckMusic = { [weak self] in
                self?.soundEngine.duckMusic()
            }
            gameWindow?.gameView.onPlayTick = { [weak self] in
                self?.soundEngine.playCountdownTick()
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
            speedTypeWindow?.speedTypeView.onPlayCountdownTick = { [weak self] in
                self?.soundEngine.playCountdownTick()
            }
            speedTypeWindow?.speedTypeView.onPlayCountdownGo = { [weak self] in
                self?.soundEngine.playCountdownGo()
            }
            speedTypeWindow?.speedTypeView.onPlayRecordSound = { [weak self] in
                self?.soundEngine.playGolden()
            }
            speedTypeWindow?.speedTypeView.onPlaySuccessSemitone = { [weak self] semitone in
                self?.soundEngine.playSuccess(semitone: semitone)
            }
            speedTypeWindow?.speedTypeView.onStartMusic = { [weak self] in
                self?.soundEngine.startLayeredMusic()
            }
            speedTypeWindow?.speedTypeView.onStopMusic = { [weak self] in
                self?.soundEngine.stopLayeredMusic()
            }
            speedTypeWindow?.speedTypeView.onFlowTierChanged = { [weak self] tier in
                self?.soundEngine.setMusicIntensity(tier)
            }
            speedTypeWindow?.speedTypeView.weakKeyProvider = { [weak self] in
                self?.typingStats.getKeyCounts() ?? [:]
            }
        }

        speedTypeWindow?.speedTypeView.resetGame()
        speedTypeWindow?.center()
        speedTypeWindow?.makeKeyAndOrderFront(nil)
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
