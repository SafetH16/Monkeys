// SpeedTypeWindow.swift
// Monkeys
//
// Window container for the Speed Typing challenge game.

import Cocoa

final class SpeedTypeWindow: NSWindow, NSWindowDelegate {

    let speedTypeView: SpeedTypeView

    init() {
        let size = NSSize(width: 520, height: 560)
        self.speedTypeView = SpeedTypeView(frame: NSRect(origin: .zero, size: size))

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = L.shared.s("game_speed")
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = NSColor(red: 0.02, green: 0.08, blue: 0.03, alpha: 1.0)
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.contentView = speedTypeView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Handle backspace (auto-repeat allowed: holding it keeps deleting)
        if event.keyCode == 51 {
            speedTypeView.handleKeyTyped("\u{7F}")
            return
        }
        // For every other key, ignore auto-repeat to avoid input spam
        guard !event.isARepeat else { return }
        // Handle arrow keys by keyCode (macOS doesn't reliably pass arrows as characters)
        // 126 = Up, 125 = Down, 124 = Right, 123 = Left
        if event.keyCode == 126 || event.keyCode == 123 {
            speedTypeView.navigateLevel(direction: -1)
            return
        }
        if event.keyCode == 125 || event.keyCode == 124 {
            speedTypeView.navigateLevel(direction: 1)
            return
        }
        if let chars = event.characters, let firstChar = chars.first {
            speedTypeView.handleKeyTyped(firstChar)
        }
    }

    func windowWillClose(_ notification: Notification) {
        speedTypeView.onStopMusic?()
        speedTypeView.stopGame()
    }
}
