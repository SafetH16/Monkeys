// VisualizerWindow.swift
// MonKeys
//
// Optional floating keyboard visualizer: a small always-on-top panel that
// briefly lights up keys as they are pressed. Purely visual and ephemeral —
// key highlights decay in ~300 ms and nothing is stored or logged.

import Cocoa

/// Non-activating floating panel hosting the visualizer. Draggable anywhere
/// by its background; its position is remembered between launches.
final class VisualizerPanel: NSPanel {

    let visualizerView: VisualizerView

    init() {
        let size = NSSize(width: 340, height: 132)
        self.visualizerView = VisualizerView(frame: NSRect(origin: .zero, size: size))

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.contentView = visualizerView
        self.setFrameAutosaveName("MonKeysVisualizer")
    }

    // A borderless panel must opt in to becoming key for dragging,
    // but it must never steal focus from the app being typed in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws a compact ANSI keyboard and fades out per-key highlights.
/// Unknown key codes simply don't light anything up (safe degradation).
final class VisualizerView: NSView {

    private struct KeyDef {
        let label: String
        let code: Int64
        let width: CGFloat
    }

    private let rows: [[KeyDef]] = [
        [
            KeyDef(label: "1", code: 18, width: 1), KeyDef(label: "2", code: 19, width: 1),
            KeyDef(label: "3", code: 20, width: 1), KeyDef(label: "4", code: 21, width: 1),
            KeyDef(label: "5", code: 23, width: 1), KeyDef(label: "6", code: 22, width: 1),
            KeyDef(label: "7", code: 26, width: 1), KeyDef(label: "8", code: 28, width: 1),
            KeyDef(label: "9", code: 25, width: 1), KeyDef(label: "0", code: 29, width: 1),
            KeyDef(label: "⌫", code: 51, width: 1.5),
        ],
        [
            KeyDef(label: "Q", code: 12, width: 1), KeyDef(label: "W", code: 13, width: 1),
            KeyDef(label: "E", code: 14, width: 1), KeyDef(label: "R", code: 15, width: 1),
            KeyDef(label: "T", code: 17, width: 1), KeyDef(label: "Y", code: 16, width: 1),
            KeyDef(label: "U", code: 32, width: 1), KeyDef(label: "I", code: 34, width: 1),
            KeyDef(label: "O", code: 31, width: 1), KeyDef(label: "P", code: 35, width: 1),
        ],
        [
            KeyDef(label: "A", code: 0, width: 1), KeyDef(label: "S", code: 1, width: 1),
            KeyDef(label: "D", code: 2, width: 1), KeyDef(label: "F", code: 3, width: 1),
            KeyDef(label: "G", code: 5, width: 1), KeyDef(label: "H", code: 4, width: 1),
            KeyDef(label: "J", code: 38, width: 1), KeyDef(label: "K", code: 40, width: 1),
            KeyDef(label: "L", code: 37, width: 1),
            KeyDef(label: "↩", code: 36, width: 1.5),
        ],
        [
            KeyDef(label: "⇧", code: 56, width: 1.3),
            KeyDef(label: "Z", code: 6, width: 1), KeyDef(label: "X", code: 7, width: 1),
            KeyDef(label: "C", code: 8, width: 1), KeyDef(label: "V", code: 9, width: 1),
            KeyDef(label: "B", code: 11, width: 1), KeyDef(label: "N", code: 45, width: 1),
            KeyDef(label: "M", code: 46, width: 1),
        ],
        [
            KeyDef(label: "", code: 49, width: 6.0),
        ],
    ]

    /// Highlight intensity per key code (1.0 → just pressed, decays to 0).
    private var intensities: [Int64: CGFloat] = [:]
    private var decayTimer: Timer?

    /// Lights a key up. Must be called on the main thread.
    func highlight(keyCode: Int64) {
        intensities[keyCode] = 1.0
        startDecayTimerIfNeeded()
        setNeedsDisplay(bounds)
    }

    private func startDecayTimerIfNeeded() {
        guard decayTimer == nil else { return }
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.decayTick()
            }
        }
    }

    private func decayTick() {
        var anyAlive = false
        for (key, value) in intensities {
            let next = value * 0.85
            if next < 0.03 {
                intensities.removeValue(forKey: key)
            } else {
                intensities[key] = next
                anyAlive = true
            }
        }
        // Stop the timer when idle: the visualizer costs nothing while not typing.
        if !anyAlive {
            decayTimer?.invalidate()
            decayTimer = nil
        }
        setNeedsDisplay(bounds)
    }

    func stopTimer() {
        decayTimer?.invalidate()
        decayTimer = nil
        intensities.removeAll()
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height

        // Panel background
        let bgPath = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                            cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.setFillColor(NSColor(white: 0.08, alpha: 0.82).cgColor)
        ctx.addPath(bgPath)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(bgPath)
        ctx.strokePath()

        let unit: CGFloat = 26
        let gap: CGFloat = 3
        let rowH: CGFloat = 20
        let topInset: CGFloat = 10

        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = row.reduce(CGFloat(0)) { $0 + $1.width * unit } + gap * CGFloat(row.count - 1)
            var x = w / 2 - rowWidth / 2
            let y = h - topInset - CGFloat(rowIndex + 1) * (rowH + gap)

            for key in row {
                let keyW = key.width * unit
                let keyRect = CGRect(x: x, y: y, width: keyW, height: rowH)
                let keyPath = CGPath(roundedRect: keyRect, cornerWidth: 4, cornerHeight: 4, transform: nil)

                let intensity = intensities[key.code] ?? 0
                if intensity > 0 {
                    ctx.setFillColor(NSColor(red: 1.0, green: 0.78, blue: 0.15,
                                             alpha: 0.25 + 0.7 * intensity).cgColor)
                } else {
                    ctx.setFillColor(NSColor(white: 1.0, alpha: 0.07).cgColor)
                }
                ctx.addPath(keyPath)
                ctx.fillPath()

                if !key.label.isEmpty {
                    let labelColor = intensity > 0.5 ?
                        NSColor(white: 0.1, alpha: 0.9) : NSColor(white: 0.75, alpha: 0.85)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                        .foregroundColor: labelColor,
                    ]
                    let str = key.label as NSString
                    let sz = str.size(withAttributes: attrs)
                    str.draw(at: NSPoint(x: keyRect.midX - sz.width / 2, y: keyRect.midY - sz.height / 2),
                             withAttributes: attrs)
                }

                x += keyW + gap
            }
        }
    }
}
