// SettingsWindow.swift
// MonKeys
//
// Lightweight AppKit preferences window: General, Sound (user preset editor
// with live preview and validated JSON import/export), App Profiles and
// Privacy. English UI, light/dark aware (system controls + semantic colors).

import Cocoa
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class SettingsWindow: NSWindow {

    // MARK: - Dependencies

    private let engine: SoundEngine
    private let presetStore: SoundProfileStore
    private let profileManager: AppProfileManager
    private let typingStats: TypingStats
    private let keyboardMonitor: KeyboardMonitor

    /// Called after any change that the menu bar must reflect
    /// (enabled state, volume, profile, music…).
    var onGlobalChange: (() -> Void)?
    /// Asks AppDelegate to flip the global sounds-enabled state.
    var onSetSoundsEnabled: ((Bool) -> Void)?
    /// Current global enabled state provider.
    var isSoundsEnabled: (() -> Bool)?

    // MARK: - Sound tab state

    /// Parameters currently shown by the sliders.
    private var currentParams: SoundParameters = SoundProfile.brown.parameters
    /// Name of the selected user preset, nil when a built-in is selected.
    private var selectedUserPresetName: String?
    private var selectedBuiltin: SoundProfile = .brown

    // MARK: - Controls

    private var enabledCheck: NSButton!
    private var musicCheck: NSButton!
    private var loginCheck: NSButton!
    private var volumeSlider: NSSlider!
    private var volumeLabel: NSTextField!
    private var shortcutLabel: NSTextField!

    private var presetPopup: NSPopUpButton!
    private var paramSliders: [String: NSSlider] = [:]
    private var deleteButton: NSButton!
    private var saveButton: NSButton!

    private var rulesTable: NSTableView!
    private var ruleEnabledCheck: NSButton!
    private var ruleMutedCheck: NSButton!
    private var ruleProfilePopup: NSPopUpButton!
    private var ruleVolumeSlider: NSSlider!
    private var ruleVolumeCheck: NSButton!

    private var statsCheck: NSButton!
    private var languagePopup: NSPopUpButton!

    private let builtinProfiles: [SoundProfile] = [
        .blue, .brown, .red, .black, .silentRed, .speedSilver,
        .gateronRed, .gateronYellow, .silentBlack,
        .deepThock, .silentOffice, .terminal, .softMac,
        .typewriter, .bubbles, .retro8bit, .monkey, .waxSlime,
    ]

    // MARK: - Init

    init(engine: SoundEngine,
         presetStore: SoundProfileStore,
         profileManager: AppProfileManager,
         typingStats: TypingStats,
         keyboardMonitor: KeyboardMonitor) {
        self.engine = engine
        self.presetStore = presetStore
        self.profileManager = profileManager
        self.typingStats = typingStats
        self.keyboardMonitor = keyboardMonitor

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.title = "MonKeys Settings"
        self.isReleasedWhenClosed = false

        let tabView = NSTabView(frame: NSRect(x: 12, y: 12, width: 536, height: 476))
        tabView.addTabViewItem(makeTab("General", view: buildGeneralTab()))
        tabView.addTabViewItem(makeTab("Sound", view: buildSoundTab()))
        tabView.addTabViewItem(makeTab("App Profiles", view: buildRulesTab()))
        tabView.addTabViewItem(makeTab("Privacy", view: buildPrivacyTab()))

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 500))
        content.addSubview(tabView)
        self.contentView = content

        refreshGeneralTab()
        reloadPresetPopup()
        loadSelectedVoiceIntoSliders()
        reloadRulesTable()
    }

    override var canBecomeKey: Bool { true }

    private func makeTab(_ label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = view
        return item
    }

    /// Refreshes controls that mirror global state (call when reopening).
    func refreshGeneralTab() {
        enabledCheck.state = (isSoundsEnabled?() ?? true) ? .on : .off
        musicCheck.state = AppSettings.musicEnabled ? .on : .off
        if #available(macOS 13.0, *) {
            loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
            loginCheck.isEnabled = true
        } else {
            loginCheck.isEnabled = false
        }
        volumeSlider.integerValue = AppSettings.volume
        volumeLabel.stringValue = "\(AppSettings.volume)%"
        let (code, flags) = keyboardMonitor.currentShortcut
        shortcutLabel.stringValue = stringForShortcut(keyCode: code, flags: flags)
        statsCheck.state = AppSettings.statsEnabled ? .on : .off
    }

    // MARK: - General tab

    private func buildGeneralTab() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))

        enabledCheck = NSButton(checkboxWithTitle: "Sounds enabled", target: self, action: #selector(enabledChanged))
        enabledCheck.frame = NSRect(x: 30, y: 380, width: 250, height: 22)
        v.addSubview(enabledCheck)

        musicCheck = NSButton(checkboxWithTitle: "Game background music", target: self, action: #selector(musicChanged))
        musicCheck.frame = NSRect(x: 30, y: 350, width: 250, height: 22)
        v.addSubview(musicCheck)

        loginCheck = NSButton(checkboxWithTitle: "Launch at login (macOS 13+)", target: self, action: #selector(loginChanged))
        loginCheck.frame = NSRect(x: 30, y: 320, width: 280, height: 22)
        v.addSubview(loginCheck)

        let volTitle = NSTextField(labelWithString: "Volume")
        volTitle.frame = NSRect(x: 30, y: 280, width: 80, height: 20)
        v.addSubview(volTitle)

        volumeSlider = NSSlider(value: 70, minValue: 0, maxValue: 100, target: self, action: #selector(volumeChanged))
        volumeSlider.frame = NSRect(x: 110, y: 278, width: 300, height: 24)
        v.addSubview(volumeSlider)

        volumeLabel = NSTextField(labelWithString: "70%")
        volumeLabel.frame = NSRect(x: 420, y: 280, width: 60, height: 20)
        v.addSubview(volumeLabel)

        let scTitle = NSTextField(labelWithString: "Global mute shortcut")
        scTitle.frame = NSRect(x: 30, y: 238, width: 160, height: 20)
        v.addSubview(scTitle)

        shortcutLabel = NSTextField(labelWithString: "⌃⇧K")
        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        shortcutLabel.frame = NSRect(x: 195, y: 238, width: 120, height: 20)
        v.addSubview(shortcutLabel)

        let scButton = NSButton(title: "Change…", target: self, action: #selector(changeShortcutClicked))
        scButton.frame = NSRect(x: 320, y: 232, width: 100, height: 30)
        v.addSubview(scButton)

        // Language (moved out of the menu bar: set-once preference)
        let langTitle = NSTextField(labelWithString: "Menu language")
        langTitle.frame = NSRect(x: 30, y: 198, width: 130, height: 20)
        v.addSubview(langTitle)

        languagePopup = NSPopUpButton(frame: NSRect(x: 165, y: 192, width: 200, height: 28))
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        for lang in L.Lang.allCases {
            languagePopup.addItem(withTitle: L.shared.s("lang_\(lang.rawValue)"))
        }
        if let idx = L.Lang.allCases.firstIndex(of: L.shared.current) {
            languagePopup.selectItem(at: idx)
        }
        v.addSubview(languagePopup)

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaultsClicked))
        resetButton.frame = NSRect(x: 30, y: 30, width: 160, height: 30)
        v.addSubview(resetButton)

        let updatesButton = NSButton(title: "Check for Updates…", target: self, action: #selector(checkUpdatesClicked))
        updatesButton.frame = NSRect(x: 200, y: 30, width: 180, height: 30)
        v.addSubview(updatesButton)

        let note = NSTextField(wrappingLabelWithString:
            "The menu bar and the shortcut always control the same state. Defaults: volume 70%, Tactile Brown-style profile, sounds on.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 30, y: 128, width: 460, height: 56)
        v.addSubview(note)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let versionLabel = NSTextField(labelWithString: "MonKeys v\(version)")
        versionLabel.font = NSFont.systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.frame = NSRect(x: 30, y: 6, width: 300, height: 16)
        v.addSubview(versionLabel)

        return v
    }

    @objc private func languageChanged() {
        let idx = languagePopup.indexOfSelectedItem
        guard idx >= 0 && idx < L.Lang.allCases.count else { return }
        L.shared.setLanguage(L.Lang.allCases[idx])
        onGlobalChange?()
    }

    @objc private func checkUpdatesClicked() {
        Updater.shared.checkForUpdates(silent: false)
    }

    @objc private func enabledChanged() {
        onSetSoundsEnabled?(enabledCheck.state == .on)
        onGlobalChange?()
    }

    @objc private func musicChanged() {
        AppSettings.musicEnabled = musicCheck.state == .on
        engine.setMusicEnabled(musicCheck.state == .on)
        onGlobalChange?()
    }

    @objc private func loginChanged() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if loginCheck.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the checkbox so the UI never lies about the real state.
            loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        onGlobalChange?()
    }

    @objc private func volumeChanged() {
        let value = volumeSlider.integerValue
        AppSettings.volume = value
        engine.setVolume(Float(value) / 100.0)
        volumeLabel.stringValue = "\(value)%"
        onGlobalChange?()
    }

    @objc private func changeShortcutClicked() {
        let recorder = ShortcutRecorderWindow()
        recorder.onShortcutRecorded = { [weak self] keyCode, flags in
            guard let self else { return }
            self.keyboardMonitor.setShortcut(keyCode: keyCode, flags: flags)
            self.shortcutLabel.stringValue = stringForShortcut(keyCode: keyCode, flags: flags)
            self.onGlobalChange?()
        }
        recorder.center()
        recorder.makeKeyAndOrderFront(nil)
    }

    @objc private func resetDefaultsClicked() {
        AppSettings.volume = 70
        AppSettings.musicEnabled = true
        AppSettings.savedProfileRaw = SoundProfile.brown.rawValue
        AppSettings.customPresetName = nil
        engine.setVolume(0.7)
        engine.setMusicEnabled(true)
        engine.setProfile(.brown)
        onSetSoundsEnabled?(true)
        refreshGeneralTab()
        reloadPresetPopup()
        loadSelectedVoiceIntoSliders()
        onGlobalChange?()
    }

    // MARK: - Sound tab

    private struct SliderSpec {
        let key: String
        let label: String
        let min: Double
        let max: Double
    }

    private let sliderSpecs: [SliderSpec] = [
        SliderSpec(key: "clickAmplitude", label: "Loudness", min: 0.0, max: 1.0),
        SliderSpec(key: "clickFrequency", label: "Pitch", min: 100, max: 8000),
        SliderSpec(key: "clickNoiseAmount", label: "Click character", min: 0.0, max: 1.0),
        SliderSpec(key: "thudFrequency", label: "Thock depth", min: 40, max: 2000),
        SliderSpec(key: "thudDuration", label: "Resonance", min: 0.005, max: 0.3),
        SliderSpec(key: "holdNoiseAmplitude", label: "Hold intensity", min: 0.0, max: 0.1),
        SliderSpec(key: "releaseAmplitude", label: "Release intensity", min: 0.0, max: 1.0),
        SliderSpec(key: "variation", label: "Variation", min: 0.0, max: 0.6),
    ]

    private func buildSoundTab() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))

        let presetTitle = NSTextField(labelWithString: "Preset")
        presetTitle.frame = NSRect(x: 30, y: 392, width: 60, height: 20)
        v.addSubview(presetTitle)

        presetPopup = NSPopUpButton(frame: NSRect(x: 95, y: 386, width: 250, height: 28))
        presetPopup.target = self
        presetPopup.action = #selector(presetSelected)
        v.addSubview(presetPopup)

        let previewButton = NSButton(title: "▶ Preview", target: self, action: #selector(previewClicked))
        previewButton.frame = NSRect(x: 355, y: 384, width: 110, height: 30)
        v.addSubview(previewButton)

        var y: CGFloat = 344
        for spec in sliderSpecs {
            let label = NSTextField(labelWithString: spec.label)
            label.font = NSFont.systemFont(ofSize: 12)
            label.frame = NSRect(x: 30, y: y, width: 130, height: 18)
            v.addSubview(label)

            let slider = NSSlider(value: spec.min, minValue: spec.min, maxValue: spec.max,
                                  target: self, action: #selector(paramSliderChanged))
            slider.frame = NSRect(x: 165, y: y - 2, width: 320, height: 22)
            slider.identifier = NSUserInterfaceItemIdentifier(spec.key)
            paramSliders[spec.key] = slider
            v.addSubview(slider)

            y -= 32
        }

        saveButton = NSButton(title: "Save as User Preset…", target: self, action: #selector(savePresetClicked))
        saveButton.frame = NSRect(x: 30, y: 52, width: 180, height: 30)
        v.addSubview(saveButton)

        deleteButton = NSButton(title: "Delete", target: self, action: #selector(deletePresetClicked))
        deleteButton.frame = NSRect(x: 215, y: 52, width: 80, height: 30)
        v.addSubview(deleteButton)

        let exportButton = NSButton(title: "Export…", target: self, action: #selector(exportClicked))
        exportButton.frame = NSRect(x: 300, y: 52, width: 90, height: 30)
        v.addSubview(exportButton)

        let importButton = NSButton(title: "Import…", target: self, action: #selector(importClicked))
        importButton.frame = NSRect(x: 395, y: 52, width: 90, height: 30)
        v.addSubview(importButton)

        let note = NSTextField(wrappingLabelWithString:
            "All sounds are procedurally synthesized. Moving a slider applies the voice immediately; save it as a user preset to keep it. Built-in presets cannot be modified or deleted.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 30, y: 6, width: 460, height: 42)
        v.addSubview(note)

        return v
    }

    private func reloadPresetPopup() {
        presetPopup.removeAllItems()
        for profile in builtinProfiles {
            presetPopup.addItem(withTitle: profile.rawValue)
        }
        let userPresets = presetStore.all()
        if !userPresets.isEmpty {
            presetPopup.menu?.addItem(.separator())
            for preset in userPresets {
                presetPopup.addItem(withTitle: "👤 \(preset.name)")
            }
        }
        // Reflect the currently active voice
        if let customName = AppSettings.customPresetName,
           userPresets.contains(where: { $0.name == customName }) {
            selectedUserPresetName = customName
            presetPopup.selectItem(withTitle: "👤 \(customName)")
        } else {
            selectedUserPresetName = nil
            let raw = AppSettings.savedProfileRaw ?? SoundProfile.blue.rawValue
            selectedBuiltin = SoundProfile(rawValue: raw) ?? .blue
            presetPopup.selectItem(withTitle: selectedBuiltin.rawValue)
        }
        updateSoundButtons()
    }

    private func loadSelectedVoiceIntoSliders() {
        if let name = selectedUserPresetName, let preset = presetStore.preset(named: name) {
            currentParams = preset.params
        } else {
            currentParams = selectedBuiltin.parameters
        }
        syncSliders()
    }

    private func syncSliders() {
        paramSliders["clickAmplitude"]?.doubleValue = Double(currentParams.clickAmplitude)
        paramSliders["clickFrequency"]?.doubleValue = Double(currentParams.clickFrequency)
        paramSliders["clickNoiseAmount"]?.doubleValue = Double(currentParams.clickNoiseAmount)
        paramSliders["thudFrequency"]?.doubleValue = Double(currentParams.thudFrequency)
        paramSliders["thudDuration"]?.doubleValue = Double(currentParams.thudDuration)
        paramSliders["holdNoiseAmplitude"]?.doubleValue = Double(currentParams.holdNoiseAmplitude)
        paramSliders["releaseAmplitude"]?.doubleValue = Double(currentParams.releaseAmplitude)
        paramSliders["variation"]?.doubleValue = Double(currentParams.variation)
    }

    private func updateSoundButtons() {
        let isUser = selectedUserPresetName != nil
        deleteButton.isEnabled = isUser
        saveButton.title = isUser ? "Save Changes" : "Save as User Preset…"
    }

    @objc private func presetSelected() {
        let title = presetPopup.titleOfSelectedItem ?? ""
        if title.hasPrefix("👤 ") {
            let name = String(title.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            selectedUserPresetName = name
            if let preset = presetStore.preset(named: name) {
                engine.setCustomVoice(preset.params)
                AppSettings.customPresetName = name
            }
        } else if let profile = builtinProfiles.first(where: { $0.rawValue == title }) {
            selectedUserPresetName = nil
            selectedBuiltin = profile
            engine.setProfile(profile)
            AppSettings.savedProfileRaw = profile.rawValue
            AppSettings.customPresetName = nil
        }
        loadSelectedVoiceIntoSliders()
        updateSoundButtons()
        engine.playPreviewParams(currentParams)
        onGlobalChange?()
    }

    @objc private func paramSliderChanged(_ sender: NSSlider) {
        guard let key = sender.identifier?.rawValue else { return }
        let value = Float(sender.doubleValue)
        switch key {
        case "clickAmplitude":     currentParams.clickAmplitude = value
        case "clickFrequency":     currentParams.clickFrequency = value
        case "clickNoiseAmount":   currentParams.clickNoiseAmount = value
        case "thudFrequency":      currentParams.thudFrequency = value
        case "thudDuration":       currentParams.thudDuration = value
        case "holdNoiseAmplitude": currentParams.holdNoiseAmplitude = value
        case "releaseAmplitude":   currentParams.releaseAmplitude = value
        case "variation":          currentParams.variation = value
        default: break
        }
        // Live-apply the edited voice so typing reflects the sliders instantly.
        engine.setCustomVoice(currentParams)
    }

    @objc private func previewClicked() {
        engine.playPreviewParams(currentParams)
    }

    @objc private func savePresetClicked() {
        if let name = selectedUserPresetName {
            presetStore.update(name: name, params: currentParams)
            engine.setCustomVoice(currentParams)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Save User Preset"
        alert.informativeText = "Choose a name for your preset."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = "\(selectedBuiltin.rawValue) (custom)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let saved = presetStore.add(name: field.stringValue, params: currentParams) else {
            showError("The preset could not be saved (invalid name or preset limit reached).")
            return
        }
        selectedUserPresetName = saved.name
        AppSettings.customPresetName = saved.name
        engine.setCustomVoice(saved.params)
        reloadPresetPopup()
        presetPopup.selectItem(withTitle: "👤 \(saved.name)")
        updateSoundButtons()
    }

    @objc private func deletePresetClicked() {
        guard let name = selectedUserPresetName else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "This user preset will be removed. Built-in presets are never affected."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        presetStore.remove(name: name)
        selectedUserPresetName = nil
        AppSettings.customPresetName = nil
        engine.setProfile(selectedBuiltin)
        reloadPresetPopup()
        loadSelectedVoiceIntoSliders()
    }

    @objc private func exportClicked() {
        let userPresets = presetStore.all()
        guard !userPresets.isEmpty else {
            showError("There are no user presets to export yet. Save one first.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MonKeys Presets.json"
        panel.beginSheetModal(for: self) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let data = self.presetStore.exportData(userPresets) else {
                self.showError("Export failed.")
                return
            }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self.showError("Could not write the file: \(error.localizedDescription)")
            }
        }
    }

    @objc private func importClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: self) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let added = try self.presetStore.importPresets(from: url)
                self.reloadPresetPopup()
                let alert = NSAlert()
                alert.messageText = "Import complete"
                alert.informativeText = "Imported: \(added.joined(separator: ", "))"
                alert.runModal()
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    // MARK: - App Profiles tab

    private func buildRulesTab() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))

        let scroll = NSScrollView(frame: NSRect(x: 30, y: 210, width: 460, height: 195))
        rulesTable = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rule"))
        col.title = "Application rules (one per bundle identifier)"
        col.width = 430
        rulesTable.addTableColumn(col)
        rulesTable.dataSource = self
        rulesTable.delegate = self
        rulesTable.rowHeight = 22
        scroll.documentView = rulesTable
        scroll.hasVerticalScroller = true
        v.addSubview(scroll)

        let addAppButton = NSButton(title: "＋ App…", target: self, action: #selector(addAppClicked))
        addAppButton.frame = NSRect(x: 30, y: 172, width: 90, height: 30)
        v.addSubview(addAppButton)

        let addFrontButton = NSButton(title: "＋ Frontmost App", target: self, action: #selector(addFrontmostClicked))
        addFrontButton.frame = NSRect(x: 125, y: 172, width: 150, height: 30)
        v.addSubview(addFrontButton)

        let removeButton = NSButton(title: "－ Remove", target: self, action: #selector(removeRuleClicked))
        removeButton.frame = NSRect(x: 280, y: 172, width: 100, height: 30)
        v.addSubview(removeButton)

        ruleEnabledCheck = NSButton(checkboxWithTitle: "Rule enabled", target: self, action: #selector(ruleControlChanged))
        ruleEnabledCheck.frame = NSRect(x: 30, y: 136, width: 130, height: 22)
        v.addSubview(ruleEnabledCheck)

        ruleMutedCheck = NSButton(checkboxWithTitle: "Mute in this app", target: self, action: #selector(ruleControlChanged))
        ruleMutedCheck.frame = NSRect(x: 170, y: 136, width: 160, height: 22)
        v.addSubview(ruleMutedCheck)

        let profTitle = NSTextField(labelWithString: "Profile")
        profTitle.frame = NSRect(x: 30, y: 102, width: 60, height: 20)
        v.addSubview(profTitle)

        ruleProfilePopup = NSPopUpButton(frame: NSRect(x: 95, y: 96, width: 240, height: 28))
        ruleProfilePopup.target = self
        ruleProfilePopup.action = #selector(ruleControlChanged)
        ruleProfilePopup.addItem(withTitle: "Keep global profile")
        for profile in builtinProfiles { ruleProfilePopup.addItem(withTitle: profile.rawValue) }
        v.addSubview(ruleProfilePopup)

        ruleVolumeCheck = NSButton(checkboxWithTitle: "Custom volume", target: self, action: #selector(ruleControlChanged))
        ruleVolumeCheck.frame = NSRect(x: 30, y: 64, width: 140, height: 22)
        v.addSubview(ruleVolumeCheck)

        ruleVolumeSlider = NSSlider(value: 70, minValue: 0, maxValue: 100, target: self, action: #selector(ruleControlChanged))
        ruleVolumeSlider.frame = NSRect(x: 175, y: 62, width: 250, height: 24)
        v.addSubview(ruleVolumeSlider)

        let note = NSTextField(wrappingLabelWithString:
            "Priority: your manual mute always wins, then Meeting Mode, then app rules, then global settings. Manually unmuting during an auto-mute keeps sounds on until you switch app.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 30, y: 6, width: 460, height: 48)
        v.addSubview(note)

        return v
    }

    private func reloadRulesTable() {
        rulesTable.reloadData()
        syncRuleDetailControls()
    }

    private var selectedRule: PerAppRule? {
        let row = rulesTable.selectedRow
        let rules = profileManager.rules
        guard row >= 0 && row < rules.count else { return nil }
        return rules[row]
    }

    private func syncRuleDetailControls() {
        let rule = selectedRule
        let hasSelection = rule != nil
        ruleEnabledCheck.isEnabled = hasSelection
        ruleMutedCheck.isEnabled = hasSelection
        ruleProfilePopup.isEnabled = hasSelection
        ruleVolumeCheck.isEnabled = hasSelection
        ruleVolumeSlider.isEnabled = hasSelection && (rule?.volume != nil)
        guard let rule else { return }
        ruleEnabledCheck.state = rule.enabled ? .on : .off
        ruleMutedCheck.state = rule.muted ? .on : .off
        if let raw = rule.profileRaw {
            ruleProfilePopup.selectItem(withTitle: raw)
        } else {
            ruleProfilePopup.selectItem(at: 0)
        }
        ruleVolumeCheck.state = rule.volume != nil ? .on : .off
        ruleVolumeSlider.integerValue = rule.volume ?? AppSettings.volume
    }

    @objc private func ruleControlChanged() {
        guard var rule = selectedRule else { return }
        rule.enabled = ruleEnabledCheck.state == .on
        rule.muted = ruleMutedCheck.state == .on
        let profileTitle = ruleProfilePopup.titleOfSelectedItem ?? ""
        rule.profileRaw = builtinProfiles.first { $0.rawValue == profileTitle }?.rawValue
        rule.volume = ruleVolumeCheck.state == .on ? ruleVolumeSlider.integerValue : nil
        ruleVolumeSlider.isEnabled = ruleVolumeCheck.state == .on
        profileManager.upsertRule(rule)
        rulesTable.reloadData()
    }

    @objc private func addAppClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: self) { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { return }
            let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            self.profileManager.upsertRule(PerAppRule(bundleID: bundleID, appName: name))
            self.reloadRulesTable()
        }
    }

    @objc private func addFrontmostClicked() {
        guard let front = profileManager.frontmostApp else { return }
        profileManager.upsertRule(PerAppRule(bundleID: front.bundleID, appName: front.name))
        reloadRulesTable()
    }

    @objc private func removeRuleClicked() {
        guard let rule = selectedRule else { return }
        profileManager.removeRule(bundleID: rule.bundleID)
        reloadRulesTable()
    }

    // MARK: - Privacy tab

    private func buildPrivacyTab() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))

        let statement = NSTextField(wrappingLabelWithString: """
        MonKeys never records, stores, or transmits the text you type. \
        Key events are used exclusively to trigger local sounds and visuals, then discarded.

        Local statistics (daily key counts, all-time totals, peak WPM and the \
        per-key heatmap) are aggregate counters stored only on this Mac, never \
        associated with any text, sequence or timestamp, and never sent anywhere. \
        You can disable them or erase them at any time.
        """)
        statement.font = NSFont.systemFont(ofSize: 12)
        statement.frame = NSRect(x: 30, y: 250, width: 460, height: 150)
        v.addSubview(statement)

        statsCheck = NSButton(checkboxWithTitle: "Local statistics enabled", target: self, action: #selector(statsToggled))
        statsCheck.frame = NSRect(x: 30, y: 200, width: 250, height: 22)
        v.addSubview(statsCheck)

        let clearButton = NSButton(title: "Clear Local Statistics", target: self, action: #selector(clearStatsClicked))
        clearButton.frame = NSRect(x: 30, y: 156, width: 190, height: 30)
        v.addSubview(clearButton)

        let netNote = NSTextField(wrappingLabelWithString:
            "Network access is used for one purpose only: checking GitHub Releases for app updates. No analytics, no telemetry.")
        netNote.font = NSFont.systemFont(ofSize: 11)
        netNote.textColor = .secondaryLabelColor
        netNote.frame = NSRect(x: 30, y: 90, width: 460, height: 40)
        v.addSubview(netNote)

        return v
    }

    @objc private func statsToggled() {
        AppSettings.statsEnabled = statsCheck.state == .on
    }

    @objc private func clearStatsClicked() {
        let alert = NSAlert()
        alert.messageText = "Clear all local statistics?"
        alert.informativeText = "Today's count, all-time totals, peak WPM and the keyboard heatmap will be reset to zero."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        typingStats.clearAll()
    }

    // MARK: - Helpers

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MonKeys"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - Rules table data source

extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        profileManager.rules.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rules = profileManager.rules
        guard row < rules.count else { return nil }
        let rule = rules[row]

        var summary: [String] = []
        if !rule.enabled { summary.append("disabled") }
        if rule.muted { summary.append("muted") }
        if let raw = rule.profileRaw { summary.append(raw) }
        if let vol = rule.volume { summary.append("\(vol)%") }
        let detail = summary.isEmpty ? "no overrides" : summary.joined(separator: " · ")

        let text = NSTextField(labelWithString: "\(rule.appName)  —  \(rule.bundleID)  (\(detail))")
        text.font = NSFont.systemFont(ofSize: 11)
        text.lineBreakMode = .byTruncatingMiddle
        return text
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        syncRuleDetailControls()
    }
}
