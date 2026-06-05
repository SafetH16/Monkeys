// GameWindow.swift
// Monkeys
//
// Dynamic window container for the Banana Catch typing game.

import Cocoa

/// A dedicated NSWindow that wraps the GameView, centers it, and routes keyboard input.
final class GameWindow: NSWindow, NSWindowDelegate {

    // MARK: - Properties

    let gameView: GameView

    // MARK: - Initialisation

    init() {
        let size = NSSize(width: 420, height: 580)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        
        self.gameView = GameView(frame: NSRect(origin: .zero, size: size))
        
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        self.title = "🐒 Monkeys — Salva le Banane! 🍌"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true

        // Window background color matches the game view
        self.backgroundColor = NSColor(red: 0.03, green: 0.02, blue: 0.12, alpha: 1.0)
        self.isReleasedWhenClosed = false
        self.delegate = self
        
        // Set content view
        self.contentView = gameView
    }

    // MARK: - NSWindow overrides

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        if let chars = event.characters, let firstChar = chars.first {
            gameView.handleKeyTyped(firstChar)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        gameView.onStopMusic?()
        gameView.resetGame()
    }
}
