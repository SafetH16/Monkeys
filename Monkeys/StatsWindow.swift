// StatsWindow.swift
// MonKeys
//
// Statistics dashboard: stat cards, a keyboard heatmap of the most-pressed
// keys, and the top-keys ranking. Data comes from TypingStats.

import Cocoa

/// Window that hosts the statistics dashboard.
final class StatsWindow: NSWindow {

    let statsView: StatsView

    init() {
        let size = NSSize(width: 560, height: 440)
        self.statsView = StatsView(frame: NSRect(origin: .zero, size: size))

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "📊 MonKeys"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        self.isReleasedWhenClosed = false
        self.contentView = statsView
    }

    override var canBecomeKey: Bool { true }
}

/// Draws the dashboard: three stat cards, the keyboard heatmap and the
/// top-5 key ranking.
final class StatsView: NSView {

    // Injected data
    var todayCount: Int = 0
    var totalCount: Int = 0
    var peakWPM: Int = 0
    var keyCounts: [Int64: Int] = [:]

    // MARK: - Keyboard layout (ANSI-like, label + keyCode + relative width)

    private struct KeyDef {
        let label: String
        let code: Int64
        let width: CGFloat // in "key units", 1.0 = square key
    }

    private let layoutRows: [[KeyDef]] = [
        [
            KeyDef(label: "1", code: 18, width: 1), KeyDef(label: "2", code: 19, width: 1),
            KeyDef(label: "3", code: 20, width: 1), KeyDef(label: "4", code: 21, width: 1),
            KeyDef(label: "5", code: 23, width: 1), KeyDef(label: "6", code: 22, width: 1),
            KeyDef(label: "7", code: 26, width: 1), KeyDef(label: "8", code: 28, width: 1),
            KeyDef(label: "9", code: 25, width: 1), KeyDef(label: "0", code: 29, width: 1),
            KeyDef(label: "⌫", code: 51, width: 1.6),
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
            KeyDef(label: "↩", code: 36, width: 1.6),
        ],
        [
            KeyDef(label: "⇧", code: 56, width: 1.4),
            KeyDef(label: "Z", code: 6, width: 1), KeyDef(label: "X", code: 7, width: 1),
            KeyDef(label: "C", code: 8, width: 1), KeyDef(label: "V", code: 9, width: 1),
            KeyDef(label: "B", code: 11, width: 1), KeyDef(label: "N", code: 45, width: 1),
            KeyDef(label: "M", code: 46, width: 1),
        ],
        [
            KeyDef(label: "⎵", code: 49, width: 6.5),
        ],
    ]

    // MARK: - Data

    /// Reloads counters from the given stats store and repaints.
    func reload(from stats: TypingStats) {
        todayCount = stats.getTodayCount()
        totalCount = stats.getAllTimeCount()
        peakWPM = stats.getPeakWPM()
        keyCounts = stats.getKeyCounts()
        setNeedsDisplay(bounds)
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height

        // Background
        ctx.setFillColor(NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0).cgColor)
        ctx.fill(bounds)

        // ── Stat cards row ──
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.groupingSeparator = "."
        func fmtN(_ n: Int) -> String { fmt.string(from: NSNumber(value: n)) ?? "\(n)" }

        let cards: [(value: String, label: String, tint: NSColor)] = [
            (fmtN(todayCount), L.shared.s("stats_card_today"),
             NSColor(red: 0.45, green: 0.85, blue: 0.5, alpha: 1.0)),
            (fmtN(totalCount), L.shared.s("stats_card_total"),
             NSColor(red: 0.5, green: 0.75, blue: 1.0, alpha: 1.0)),
            ("\(peakWPM) WPM", L.shared.s("stats_card_peak"),
             NSColor(red: 1.0, green: 0.8, blue: 0.35, alpha: 1.0)),
        ]

        let cardW = (w - 60) / 3
        let cardH: CGFloat = 64
        let cardY = h - 60 - cardH
        for (i, card) in cards.enumerated() {
            let cardX = 20 + CGFloat(i) * (cardW + 10)
            let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
            let path = CGPath(roundedRect: cardRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.06).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(path)
            ctx.strokePath()

            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold),
                .foregroundColor: card.tint,
            ]
            let valueStr = card.value as NSString
            let vs = valueStr.size(withAttributes: valueAttrs)
            valueStr.draw(at: NSPoint(x: cardRect.midX - vs.width / 2, y: cardRect.midY - 2),
                          withAttributes: valueAttrs)

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor(white: 0.65, alpha: 1.0),
            ]
            let labelStr = card.label as NSString
            let ls = labelStr.size(withAttributes: labelAttrs)
            labelStr.draw(at: NSPoint(x: cardRect.midX - ls.width / 2, y: cardRect.minY + 9),
                          withAttributes: labelAttrs)
        }

        // ── Heatmap title ──
        let heatTitle = L.shared.s("stats_heatmap") as NSString
        let heatTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
        ]
        heatTitle.draw(at: NSPoint(x: 24, y: cardY - 34), withAttributes: heatTitleAttrs)

        // ── Keyboard heatmap ──
        let maxCount = max(keyCounts.values.max() ?? 1, 1)
        let unit: CGFloat = 40
        let gap: CGFloat = 5
        let keyboardTop = cardY - 48
        let rowH = unit * 0.82

        for (rowIndex, row) in layoutRows.enumerated() {
            // Center each row horizontally
            let rowUnits = row.reduce(CGFloat(0)) { $0 + $1.width } + gap / unit * CGFloat(row.count - 1)
            var x = w / 2 - (rowUnits * unit) / 2
            let y = keyboardTop - CGFloat(rowIndex + 1) * (rowH + gap)

            for key in row {
                let keyW = key.width * unit
                let keyRect = CGRect(x: x, y: y, width: keyW, height: rowH)
                let keyPath = CGPath(roundedRect: keyRect, cornerWidth: 6, cornerHeight: 6, transform: nil)

                // Heat: log-scaled intensity from dark slate to warm banana-yellow
                let count = keyCounts[key.code] ?? 0
                let intensity = count > 0 ? CGFloat(log(1.0 + Double(count)) / log(1.0 + Double(maxCount))) : 0
                let baseColor = NSColor(white: 1.0, alpha: 0.06)
                let hotColor = NSColor(red: 1.0, green: 0.72, blue: 0.1, alpha: 0.92)
                let fill = intensity > 0 ?
                    (baseColor.blended(withFraction: intensity, of: hotColor) ?? baseColor) : baseColor

                ctx.setFillColor(fill.cgColor)
                ctx.addPath(keyPath)
                ctx.fillPath()
                ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.09).cgColor)
                ctx.setLineWidth(1)
                ctx.addPath(keyPath)
                ctx.strokePath()

                // Label — dark on hot keys, light on cold ones
                let labelColor = intensity > 0.55 ?
                    NSColor(white: 0.1, alpha: 0.9) : NSColor(white: 0.8, alpha: 0.9)
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: labelColor,
                ]
                let labelStr = key.label as NSString
                let ls = labelStr.size(withAttributes: labelAttrs)
                labelStr.draw(at: NSPoint(x: keyRect.midX - ls.width / 2, y: keyRect.midY - ls.height / 2),
                              withAttributes: labelAttrs)

                x += keyW + gap
            }
        }

        // ── Top keys ranking ──
        let rankingY = keyboardTop - CGFloat(layoutRows.count) * (rowH + gap) - 36
        let topTitle = L.shared.s("stats_top_keys") as NSString
        topTitle.draw(at: NSPoint(x: 24, y: rankingY + 8), withAttributes: heatTitleAttrs)

        let allKeys = layoutRows.flatMap { $0 }
        let labelByCode = Dictionary(uniqueKeysWithValues: allKeys.map { ($0.code, $0.label) })
        let top = keyCounts
            .filter { labelByCode[$0.key] != nil }
            .sorted { $0.value > $1.value }
            .prefix(5)

        var topX: CGFloat = 24
        for (code, count) in top {
            let chip = "\(labelByCode[code] ?? "?")  \(fmtN(count))" as NSString
            let chipAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1.0),
            ]
            let cs = chip.size(withAttributes: chipAttrs)
            let chipRect = CGRect(x: topX, y: rankingY - 18, width: cs.width + 20, height: 24)
            let chipPath = CGPath(roundedRect: chipRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.07).cgColor)
            ctx.addPath(chipPath)
            ctx.fillPath()
            chip.draw(at: NSPoint(x: chipRect.minX + 10, y: chipRect.midY - cs.height / 2),
                      withAttributes: chipAttrs)
            topX += chipRect.width + 8
        }
    }
}
