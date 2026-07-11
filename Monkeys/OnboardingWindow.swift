// OnboardingWindow.swift
// MonKeys
//
// Friendly first-launch window that explains why the Accessibility
// permission is needed and takes the user straight to System Settings —
// replaces the bare NSAlert.

import Cocoa

final class OnboardingWindow: NSWindow {

    var onOpenSettings: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 330),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = ""
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.backgroundColor = NSColor.windowBackgroundColor

        setupViews()
    }

    override var canBecomeKey: Bool { true }

    private func setupViews() {
        guard let content = self.contentView else { return }

        // Big app glyph
        let iconLabel = NSTextField(labelWithString: "🐒⌨️")
        iconLabel.font = NSFont.systemFont(ofSize: 44)
        iconLabel.alignment = .center
        iconLabel.frame = NSRect(x: 20, y: 250, width: 400, height: 56)
        content.addSubview(iconLabel)

        // Title
        let titleLabel = NSTextField(labelWithString: L.shared.s("ob_title"))
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 214, width: 400, height: 28)
        content.addSubview(titleLabel)

        // Body: why the permission is needed + the steps
        let bodyLabel = NSTextField(wrappingLabelWithString: L.shared.s("ob_body"))
        bodyLabel.font = NSFont.systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.alignment = .center
        bodyLabel.frame = NSRect(x: 40, y: 96, width: 360, height: 110)
        content.addSubview(bodyLabel)

        // Primary action
        let button = NSButton(title: L.shared.s("ob_open_settings"), target: self,
                              action: #selector(openSettingsClicked))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r"
        button.frame = NSRect(x: 120, y: 44, width: 200, height: 36)
        content.addSubview(button)

        // Reassurance footnote
        let noteLabel = NSTextField(labelWithString: L.shared.s("ob_note"))
        noteLabel.font = NSFont.systemFont(ofSize: 11)
        noteLabel.textColor = .tertiaryLabelColor
        noteLabel.alignment = .center
        noteLabel.frame = NSRect(x: 20, y: 16, width: 400, height: 18)
        content.addSubview(noteLabel)
    }

    @objc private func openSettingsClicked() {
        onOpenSettings?()
    }
}
