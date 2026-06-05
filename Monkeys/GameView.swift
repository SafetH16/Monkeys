// GameView.swift
// Monkeys
//
// Graphically renders the Banana Catch typing game with day/night cycle,
// palm trees, combos, levels, background music, and visual polish.

import Cocoa

/// A custom graphics canvas view that hosts the game loop.
final class GameView: NSView {

    // MARK: - Types

    struct GameBanana {
        let character: Character
        var position: CGPoint
        var speed: CGFloat
        let size: CGFloat = 40.0
    }

    struct Star {
        var position: CGPoint
        var size: CGFloat
        var brightness: CGFloat
        var twinkleSpeed: CGFloat
        var phase: CGFloat
        var isYellow: Bool
    }

    struct ScorePopup {
        var position: CGPoint
        var text: String
        var framesRemaining: Int
        let totalFrames: Int
    }

    struct PalmTree {
        var x: CGFloat
        var trunkHeight: CGFloat
        var leafSize: CGFloat
        var sway: CGFloat       // current sway angle
        var swaySpeed: CGFloat
    }

    struct Cloud {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var speed: CGFloat
        var opacity: CGFloat
    }

    enum TimeOfDay: Int {
        case morning = 0
        case afternoon = 1
        case evening = 2
        case night = 3
    }

    // MARK: - Callbacks

    var onPlaySuccessSound: (() -> Void)?
    var onPlayFailSound: (() -> Void)?
    var onPlayComboSound: ((Int) -> Void)?
    var onPlayLevelUpSound: (() -> Void)?
    var onGameOver: (() -> Void)?
    var onStartMusic: (() -> Void)?
    var onStopMusic: (() -> Void)?


    // MARK: - Game State

    private var bananas: [GameBanana] = []
    private var score = 0
    private var lives = 5
    private var level = 1
    private var comboCount = 0
    private var isGameOver = false
    private var isWaitingToStart = true

    // Monkey
    private var monkeyX: CGFloat = 210.0
    private var monkeyTargetX: CGFloat = 210.0
    private var monkeyBounceOffset: CGFloat = 0.0
    private var monkeyBounceFrames: Int = 0

    // Visual elements
    private var stars: [Star] = []
    private var scorePopups: [ScorePopup] = []
    private var palmTrees: [PalmTree] = []
    private var clouds: [Cloud] = []

    // Time cycle
    private var timeOfDay: TimeOfDay = .morning
    private var gameElapsedSeconds: CGFloat = 0.0
    private let timePhaseSeconds: CGFloat = 20.0 // 20s per phase

    // Spawning
    private var lastSpawnTime: Date = Date()
    private var spawnInterval: TimeInterval = 2.5

    // High score
    private var highScore: Int = UserDefaults.standard.integer(forKey: "MonkeysHighScore")

    // Animation
    private var gameTimer: Timer?
    private var frameCount: Int = 0

    // Available letters
    private let availableLetters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        generateStars()
        generatePalmTrees()
        generateClouds()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        generateStars()
        generatePalmTrees()
        generateClouds()
    }

    // MARK: - Stars, Trees, Clouds Setup

    private func generateStars() {
        stars = (0..<100).map { _ in
            Star(
                position: CGPoint(x: CGFloat.random(in: 0...420), y: CGFloat.random(in: 80...580)),
                size: CGFloat.random(in: 1.0...3.0),
                brightness: CGFloat.random(in: 0.3...1.0),
                twinkleSpeed: CGFloat.random(in: 0.02...0.08),
                phase: CGFloat.random(in: 0...(.pi * 2)),
                isYellow: Bool.random()
            )
        }
    }

    private func generatePalmTrees() {
        palmTrees = [
            PalmTree(x: 30, trunkHeight: 120, leafSize: 50, sway: 0, swaySpeed: 0.015),
            PalmTree(x: 100, trunkHeight: 90, leafSize: 40, sway: 0.5, swaySpeed: 0.02),
            PalmTree(x: 320, trunkHeight: 110, leafSize: 45, sway: 1.0, swaySpeed: 0.018),
            PalmTree(x: 390, trunkHeight: 135, leafSize: 55, sway: 1.5, swaySpeed: 0.012),
        ]
    }

    private func generateClouds() {
        clouds = [
            Cloud(x: 50, y: 480, width: 80, speed: 0.3, opacity: 0.6),
            Cloud(x: 200, y: 520, width: 60, speed: 0.2, opacity: 0.4),
            Cloud(x: 350, y: 490, width: 70, speed: 0.35, opacity: 0.5),
        ]
    }

    // MARK: - Game Loop

    func resetGame() {
        bananas.removeAll()
        scorePopups.removeAll()
        score = 0
        lives = 5
        level = 1
        comboCount = 0
        isGameOver = false
        isWaitingToStart = true
        monkeyX = bounds.width / 2
        monkeyTargetX = monkeyX
        monkeyBounceOffset = 0
        monkeyBounceFrames = 0
        lastSpawnTime = Date()
        spawnInterval = 2.5
        frameCount = 0
        gameElapsedSeconds = 0
        timeOfDay = .morning
        highScore = UserDefaults.standard.integer(forKey: "MonkeysHighScore")

        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.gameTick()
            }
        }
    }

    private func gameTick() {
        guard !isWaitingToStart else {
            frameCount += 1
            setNeedsDisplay(bounds)
            return
        }
        guard !isGameOver else {
            setNeedsDisplay(bounds)
            return
        }

        frameCount += 1
        gameElapsedSeconds += 1.0 / 60.0

        // Update time of day
        let phase = Int(gameElapsedSeconds / timePhaseSeconds) % 4
        timeOfDay = TimeOfDay(rawValue: phase) ?? .morning

        // Update clouds
        for i in 0..<clouds.count {
            clouds[i].x += clouds[i].speed
            if clouds[i].x > bounds.width + clouds[i].width {
                clouds[i].x = -clouds[i].width
            }
        }

        // Update palm tree sway
        for i in 0..<palmTrees.count {
            palmTrees[i].sway += palmTrees[i].swaySpeed
        }

        // Spawn bananas
        let now = Date()
        let effectiveSpawnInterval = max(0.5, spawnInterval - Double(level - 1) * 0.15)
        let maxBananas = 4 + level
        if now.timeIntervalSince(lastSpawnTime) >= effectiveSpawnInterval && bananas.count < maxBananas {
            spawnBanana()
            lastSpawnTime = now
        }

        // Move bananas
        let effectiveSpeed: CGFloat = 1.2 + CGFloat(level - 1) * 0.15
        for i in 0..<bananas.count {
            bananas[i].position.y -= bananas[i].speed * effectiveSpeed / bananas[i].speed
        }

        // Remove fallen bananas
        let groundY: CGFloat = 70.0
        let fallen = bananas.filter { $0.position.y < groundY }
        bananas.removeAll { $0.position.y < groundY }
        for _ in fallen {
            lives -= 1
            comboCount = 0
            onPlayFailSound?()
            if lives <= 0 {
                endGame()
                return
            }
        }

        // Move monkey smoothly
        let dx = monkeyTargetX - monkeyX
        monkeyX += dx * 0.15

        // Monkey bounce animation
        if monkeyBounceFrames > 0 {
            monkeyBounceFrames -= 1
            if monkeyBounceFrames > 8 {
                monkeyBounceOffset += 3.0
            } else {
                monkeyBounceOffset = max(0, monkeyBounceOffset - 3.0)
            }
        } else {
            monkeyBounceOffset = 0
        }

        // Update score popups
        scorePopups = scorePopups.compactMap { popup in
            var p = popup
            p.position.y += 1.5
            p.framesRemaining -= 1
            return p.framesRemaining > 0 ? p : nil
        }

        setNeedsDisplay(bounds)
    }

    private func spawnBanana() {
        let char = availableLetters.randomElement()!
        let x = CGFloat.random(in: 30...(bounds.width - 30))
        let baseSpeed: CGFloat = 1.2 + CGFloat(level - 1) * 0.15
        let banana = GameBanana(
            character: char,
            position: CGPoint(x: x, y: bounds.height - 20),
            speed: baseSpeed
        )
        bananas.append(banana)
    }

    private func endGame() {
        isGameOver = true
        onStopMusic?()
        onGameOver?()
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "MonkeysHighScore")
        }
    }

    // MARK: - Key Input

    func handleKeyTyped(_ char: Character) {
        if isWaitingToStart {
            isWaitingToStart = false
            onStartMusic?()
            return
        }
        if isGameOver {
            resetGame()
            return
        }

        let upper = Character(String(char).uppercased())
        if let idx = bananas.firstIndex(where: { $0.character == upper }) {
            let pos = bananas[idx].position
            bananas.remove(at: idx)
            comboCount += 1

            let multiplier = min(comboCount >= 3 ? comboCount - 1 : 1, 5)
            let points = multiplier
            score += points

            // Score popup
            let popupText = multiplier > 1 ? "+\(points) 🔥" : "+1"
            scorePopups.append(ScorePopup(position: pos, text: popupText, framesRemaining: 40, totalFrames: 40))

            // Move monkey toward banana
            monkeyTargetX = pos.x
            monkeyBounceFrames = 15

            // Level up check
            let newLevel = (score / 10) + 1
            if newLevel > level {
                level = newLevel
                onPlayLevelUpSound?()
            }

            // Combo sound
            if comboCount >= 3 {
                onPlayComboSound?(comboCount)
            } else {
                onPlaySuccessSound?()
            }
        } else {
            comboCount = 0
            onPlayFailSound?()
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height

        // Draw sky gradient based on time of day
        drawSkyGradient(ctx: ctx, w: w, h: h)

        // Draw stars (visible in evening/night)
        if timeOfDay == .evening || timeOfDay == .night || isWaitingToStart {
            drawStars(ctx: ctx)
        }

        // Draw clouds
        drawClouds(ctx: ctx)

        // Draw sun/moon
        drawCelestialBody(ctx: ctx, w: w, h: h)

        // Draw palm trees (behind bananas)
        drawPalmTrees(ctx: ctx)

        // Draw ground
        drawGround(ctx: ctx, w: w)

        if isWaitingToStart {
            drawStartScreen(ctx: ctx, w: w, h: h)
            return
        }

        if isGameOver {
            drawGameOverScreen(ctx: ctx, w: w, h: h)
            return
        }

        // Draw bananas
        drawBananas(ctx: ctx)

        // Draw monkey
        drawMonkey(ctx: ctx, w: w)

        // Draw score popups
        drawScorePopups(ctx: ctx)

        // Draw HUD
        drawHUD(ctx: ctx, w: w, h: h)
    }

    // MARK: - Sky & Environment

    private func drawSkyGradient(ctx: CGContext, w: CGFloat, h: CGFloat) {
        let colors: (top: NSColor, bottom: NSColor)
        switch timeOfDay {
        case .morning:
            colors = (
                NSColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1.0),
                NSColor(red: 1.0, green: 0.85, blue: 0.60, alpha: 1.0)
            )
        case .afternoon:
            colors = (
                NSColor(red: 0.25, green: 0.61, blue: 0.95, alpha: 1.0),
                NSColor(red: 0.55, green: 0.80, blue: 0.95, alpha: 1.0)
            )
        case .evening:
            colors = (
                NSColor(red: 0.15, green: 0.10, blue: 0.35, alpha: 1.0),
                NSColor(red: 0.85, green: 0.40, blue: 0.20, alpha: 1.0)
            )
        case .night:
            colors = (
                NSColor(red: 0.03, green: 0.02, blue: 0.12, alpha: 1.0),
                NSColor(red: 0.08, green: 0.05, blue: 0.20, alpha: 1.0)
            )
        }

        // Override to night for start/gameover screens
        let topColor: NSColor
        let bottomColor: NSColor
        if isWaitingToStart || isGameOver {
            topColor = NSColor(red: 0.03, green: 0.02, blue: 0.12, alpha: 1.0)
            bottomColor = NSColor(red: 0.08, green: 0.05, blue: 0.20, alpha: 1.0)
        } else {
            topColor = colors.top
            bottomColor = colors.bottom
        }

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [bottomColor.cgColor, topColor.cgColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
    }

    private func drawStars(ctx: CGContext) {
        for star in stars {
            let twinkle = 0.5 + 0.5 * sin(CGFloat(frameCount) * star.twinkleSpeed + star.phase)
            let alpha = star.brightness * twinkle
            let color = star.isYellow ?
                NSColor(red: 1.0, green: 0.95, blue: 0.7, alpha: alpha) :
                NSColor(red: 0.95, green: 0.95, blue: 1.0, alpha: alpha)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(
                x: star.position.x - star.size / 2,
                y: star.position.y - star.size / 2,
                width: star.size,
                height: star.size
            ))
        }
    }

    private func drawClouds(ctx: CGContext) {
        guard !isWaitingToStart && !isGameOver else { return }
        let cloudColor: NSColor
        switch timeOfDay {
        case .morning: cloudColor = NSColor(white: 1.0, alpha: 0.7)
        case .afternoon: cloudColor = NSColor(white: 1.0, alpha: 0.8)
        case .evening: cloudColor = NSColor(red: 1.0, green: 0.7, blue: 0.5, alpha: 0.5)
        case .night: cloudColor = NSColor(white: 0.3, alpha: 0.3)
        }
        for cloud in clouds {
            ctx.setFillColor(cloudColor.cgColor)
            // Draw cloud as overlapping circles
            let cx = cloud.x
            let cy = cloud.y
            let cw = cloud.width
            ctx.fillEllipse(in: CGRect(x: cx, y: cy, width: cw * 0.6, height: cw * 0.3))
            ctx.fillEllipse(in: CGRect(x: cx + cw * 0.2, y: cy + cw * 0.1, width: cw * 0.5, height: cw * 0.35))
            ctx.fillEllipse(in: CGRect(x: cx + cw * 0.4, y: cy - cw * 0.05, width: cw * 0.5, height: cw * 0.3))
        }
    }

    private func drawCelestialBody(ctx: CGContext, w: CGFloat, h: CGFloat) {
        guard !isWaitingToStart && !isGameOver else { return }
        let bodyX = w * 0.75
        let bodyY = h * 0.82

        switch timeOfDay {
        case .morning:
            // Rising sun - warm yellow
            let sunGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.9).cgColor,
                         NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.0).cgColor] as CFArray,
                locations: [0.0, 1.0]
            )!
            ctx.drawRadialGradient(sunGradient, startCenter: CGPoint(x: bodyX, y: bodyY),
                                   startRadius: 0, endCenter: CGPoint(x: bodyX, y: bodyY),
                                   endRadius: 50, options: [])
            ctx.setFillColor(NSColor(red: 1.0, green: 0.95, blue: 0.4, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(x: bodyX - 18, y: bodyY - 18, width: 36, height: 36))

        case .afternoon:
            // Bright sun high
            ctx.setFillColor(NSColor(red: 1.0, green: 0.95, blue: 0.3, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(x: w * 0.5 - 20, y: h * 0.88, width: 40, height: 40))

        case .evening:
            // Setting sun - orange/red
            let sunGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [NSColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 0.8).cgColor,
                         NSColor(red: 1.0, green: 0.3, blue: 0.1, alpha: 0.0).cgColor] as CFArray,
                locations: [0.0, 1.0]
            )!
            ctx.drawRadialGradient(sunGradient, startCenter: CGPoint(x: w * 0.2, y: h * 0.55),
                                   startRadius: 0, endCenter: CGPoint(x: w * 0.2, y: h * 0.55),
                                   endRadius: 60, options: [])
            ctx.setFillColor(NSColor(red: 1.0, green: 0.5, blue: 0.15, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(x: w * 0.2 - 20, y: h * 0.55 - 20, width: 40, height: 40))

        case .night:
            // Moon - silver
            ctx.setFillColor(NSColor(red: 0.9, green: 0.92, blue: 0.95, alpha: 0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: w * 0.78 - 15, y: h * 0.85, width: 30, height: 30))
            // Dark crescent
            ctx.setFillColor(NSColor(red: 0.03, green: 0.02, blue: 0.12, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(x: w * 0.78 - 8, y: h * 0.85 + 3, width: 24, height: 24))
        }
    }

    // MARK: - Palm Trees

    private func drawPalmTrees(ctx: CGContext) {
        for tree in palmTrees {
            let groundY: CGFloat = 65.0
            let swayAngle = sin(tree.sway) * 0.08

            ctx.saveGState()
            ctx.translateBy(x: tree.x, y: groundY)
            ctx.rotate(by: swayAngle)

            // Trunk - brown gradient
            let trunkWidth: CGFloat = 10.0
            let trunkColor: NSColor
            switch timeOfDay {
            case .morning: trunkColor = NSColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1.0)
            case .afternoon: trunkColor = NSColor(red: 0.60, green: 0.40, blue: 0.18, alpha: 1.0)
            case .evening: trunkColor = NSColor(red: 0.40, green: 0.22, blue: 0.10, alpha: 1.0)
            case .night: trunkColor = NSColor(red: 0.18, green: 0.10, blue: 0.05, alpha: 1.0)
            }

            ctx.setFillColor(trunkColor.cgColor)
            let trunkPath = CGMutablePath()
            trunkPath.move(to: CGPoint(x: -trunkWidth / 2, y: 0))
            trunkPath.addLine(to: CGPoint(x: -trunkWidth / 3, y: tree.trunkHeight))
            trunkPath.addLine(to: CGPoint(x: trunkWidth / 3, y: tree.trunkHeight))
            trunkPath.addLine(to: CGPoint(x: trunkWidth / 2, y: 0))
            trunkPath.closeSubpath()
            ctx.addPath(trunkPath)
            ctx.fillPath()

            // Leaves - multiple fronds
            let leafColor: NSColor
            switch timeOfDay {
            case .morning: leafColor = NSColor(red: 0.20, green: 0.70, blue: 0.15, alpha: 0.9)
            case .afternoon: leafColor = NSColor(red: 0.15, green: 0.65, blue: 0.10, alpha: 0.9)
            case .evening: leafColor = NSColor(red: 0.15, green: 0.40, blue: 0.10, alpha: 0.8)
            case .night: leafColor = NSColor(red: 0.05, green: 0.20, blue: 0.05, alpha: 0.7)
            }
            ctx.setFillColor(leafColor.cgColor)

            let top = CGPoint(x: 0, y: tree.trunkHeight)
            let angles: [CGFloat] = [-0.9, -0.5, -0.15, 0.15, 0.5, 0.9]
            for angle in angles {
                let leafEndX = top.x + cos(CGFloat.pi / 2 + angle) * tree.leafSize
                let leafEndY = top.y + sin(CGFloat.pi / 2 + angle) * tree.leafSize * 0.7
                let cpX = top.x + cos(CGFloat.pi / 2 + angle * 0.5) * tree.leafSize * 0.6
                let cpY = top.y + sin(CGFloat.pi / 2 + angle * 0.5) * tree.leafSize * 0.9

                let leafPath = CGMutablePath()
                leafPath.move(to: top)
                leafPath.addQuadCurve(to: CGPoint(x: leafEndX, y: leafEndY), control: CGPoint(x: cpX, y: cpY))
                leafPath.addQuadCurve(to: top, control: CGPoint(x: cpX - 5, y: cpY - 10))
                leafPath.closeSubpath()
                ctx.addPath(leafPath)
                ctx.fillPath()
            }

            // Coconuts 🥥
            if tree.trunkHeight > 100 {
                ctx.setFillColor(NSColor(red: 0.45, green: 0.30, blue: 0.10, alpha: 1.0).cgColor)
                ctx.fillEllipse(in: CGRect(x: -5, y: tree.trunkHeight - 5, width: 8, height: 8))
                ctx.fillEllipse(in: CGRect(x: 4, y: tree.trunkHeight - 8, width: 8, height: 8))
            }

            ctx.restoreGState()
        }
    }

    // MARK: - Ground

    private func drawGround(ctx: CGContext, w: CGFloat) {
        let groundH: CGFloat = 70.0
        let grassTop: NSColor
        let grassBottom: NSColor

        switch timeOfDay {
        case .morning:
            grassTop = NSColor(red: 0.35, green: 0.75, blue: 0.20, alpha: 1.0)
            grassBottom = NSColor(red: 0.25, green: 0.55, blue: 0.12, alpha: 1.0)
        case .afternoon:
            grassTop = NSColor(red: 0.30, green: 0.70, blue: 0.15, alpha: 1.0)
            grassBottom = NSColor(red: 0.20, green: 0.50, blue: 0.10, alpha: 1.0)
        case .evening:
            grassTop = NSColor(red: 0.22, green: 0.45, blue: 0.12, alpha: 1.0)
            grassBottom = NSColor(red: 0.12, green: 0.30, blue: 0.08, alpha: 1.0)
        case .night:
            grassTop = NSColor(red: 0.08, green: 0.22, blue: 0.06, alpha: 1.0)
            grassBottom = NSColor(red: 0.04, green: 0.12, blue: 0.03, alpha: 1.0)
        }

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [grassBottom.cgColor, grassTop.cgColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: groundH), options: [])

        // Grass blades along the top
        let grassEmojis = ["🌿", "🌱", "🍀", "🌾"]
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
        for i in stride(from: 5, to: Int(w), by: 18) {
            let emoji = grassEmojis[i / 18 % grassEmojis.count]
            (emoji as NSString).draw(at: NSPoint(x: CGFloat(i), y: groundH - 14), withAttributes: attrs)
        }
    }

    // MARK: - Game Elements

    private func drawBananas(ctx: CGContext) {
        for banana in bananas {
            let x = banana.position.x
            let y = banana.position.y

            // Glow circle behind banana
            let glowColor: NSColor
            switch timeOfDay {
            case .morning, .afternoon:
                glowColor = NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.25)
            case .evening:
                glowColor = NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 0.3)
            case .night:
                glowColor = NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.4)
            }
            ctx.setFillColor(glowColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 18, y: y - 18, width: 36, height: 36))

            // Banana emoji
            let bananaStr = "🍌" as NSString
            let bananaAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26)]
            bananaStr.draw(at: NSPoint(x: x - 14, y: y - 14), withAttributes: bananaAttrs)

            // Letter badge
            let letterStr = String(banana.character) as NSString
            let letterAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: NSColor.white,
            ]
            let letterSize = letterStr.size(withAttributes: letterAttrs)
            ctx.setFillColor(NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.85).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: x - letterSize.width / 2 - 4,
                y: y - 28,
                width: letterSize.width + 8,
                height: letterSize.height + 4
            ))
            letterStr.draw(at: NSPoint(x: x - letterSize.width / 2, y: y - 26), withAttributes: letterAttrs)
        }
    }

    private func drawMonkey(ctx: CGContext, w: CGFloat) {
        let groundY: CGFloat = 70.0
        let monkeyY = groundY + monkeyBounceOffset

        // Combo flame aura
        if comboCount >= 3 {
            let flameColors = [
                NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.3),
                NSColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 0.0),
            ]
            let flameGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: flameColors.map { $0.cgColor } as CFArray,
                locations: [0.0, 1.0]
            )!
            let flameSize: CGFloat = 30 + CGFloat(comboCount) * 5
            ctx.drawRadialGradient(flameGradient,
                                   startCenter: CGPoint(x: monkeyX, y: monkeyY + 15),
                                   startRadius: 10,
                                   endCenter: CGPoint(x: monkeyX, y: monkeyY + 15),
                                   endRadius: flameSize, options: [])
        }

        // Monkey emoji
        let monkeyEmoji = monkeyBounceFrames > 0 ? "🙈" : "🐵"
        let monkeyStr = monkeyEmoji as NSString
        let monkeyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44)]
        let monkeySize = monkeyStr.size(withAttributes: monkeyAttrs)
        monkeyStr.draw(at: NSPoint(x: monkeyX - monkeySize.width / 2, y: monkeyY), withAttributes: monkeyAttrs)
    }

    private func drawScorePopups(ctx: CGContext) {
        for popup in scorePopups {
            let alpha = CGFloat(popup.framesRemaining) / CGFloat(popup.totalFrames)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: NSColor(red: 1.0, green: 1.0, blue: 0.3, alpha: alpha),
            ]
            (popup.text as NSString).draw(at: NSPoint(x: popup.position.x - 10, y: popup.position.y), withAttributes: attrs)
        }
    }

    // MARK: - HUD

    private func drawHUD(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Semi-transparent top bar
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.4).cgColor)
        ctx.fill(CGRect(x: 0, y: h - 45, width: w, height: 45))

        // Score
        let scoreStr = "⭐ \(score)" as NSString
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.white,
        ]
        scoreStr.draw(at: NSPoint(x: 12, y: h - 35), withAttributes: scoreAttrs)

        // Lives
        let heartsStr = String(repeating: "❤️", count: lives) + String(repeating: "🖤", count: max(0, 5 - lives))
        let heartsAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        (heartsStr as NSString).draw(at: NSPoint(x: w / 2 - 50, y: h - 32), withAttributes: heartsAttrs)

        // Level
        let levelStr = "LV.\(level)" as NSString
        let levelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor(red: 0.6, green: 1.0, blue: 0.6, alpha: 1.0),
        ]
        levelStr.draw(at: NSPoint(x: w - 60, y: h - 35), withAttributes: levelAttrs)

        // Combo indicator
        if comboCount >= 3 {
            let comboStr = "🔥 \(comboCount)x COMBO!" as NSString
            let comboAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 20),
                .foregroundColor: NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1.0),
            ]
            let comboSize = comboStr.size(withAttributes: comboAttrs)
            comboStr.draw(at: NSPoint(x: w / 2 - comboSize.width / 2, y: h - 70), withAttributes: comboAttrs)
        }

        // Time of day indicator
        let timeEmoji: String
        switch timeOfDay {
        case .morning: timeEmoji = "🌅"
        case .afternoon: timeEmoji = "☀️"
        case .evening: timeEmoji = "🌇"
        case .night: timeEmoji = "🌙"
        }
        let timeAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        (timeEmoji as NSString).draw(at: NSPoint(x: w - 28, y: h - 60), withAttributes: timeAttrs)
    }

    // MARK: - Start Screen

    private func drawStartScreen(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Big monkey
        let monkeyStr = "🐒" as NSString
        let monkeyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 80)]
        let monkeySize = monkeyStr.size(withAttributes: monkeyAttrs)
        monkeyStr.draw(at: NSPoint(x: w / 2 - monkeySize.width / 2, y: h / 2 + 60), withAttributes: monkeyAttrs)

        // Title
        let titleStr = L.shared.s("g_monkeys") as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 32),
            .foregroundColor: NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),
        ]
        let titleSize = titleStr.size(withAttributes: titleAttrs)
        titleStr.draw(at: NSPoint(x: w / 2 - titleSize.width / 2, y: h / 2 + 25), withAttributes: titleAttrs)

        // Subtitle
        let subStr = L.shared.s("g_save_bananas") as NSString
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
        ]
        let subSize = subStr.size(withAttributes: subAttrs)
        subStr.draw(at: NSPoint(x: w / 2 - subSize.width / 2, y: h / 2 - 5), withAttributes: subAttrs)

        // High score
        if highScore > 0 {
            let hsStr = L.shared.sf("g_best_score", highScore) as NSString
            let hsAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.9),
            ]
            let hsSize = hsStr.size(withAttributes: hsAttrs)
            hsStr.draw(at: NSPoint(x: w / 2 - hsSize.width / 2, y: h / 2 - 35), withAttributes: hsAttrs)
        }

        // Pulsing "Press any key" text
        let pulse = 0.5 + 0.5 * sin(CGFloat(frameCount) * 0.06)
        let startStr = L.shared.s("g_press_start") as NSString
        let startAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor(white: 1.0, alpha: pulse),
        ]
        let startSize = startStr.size(withAttributes: startAttrs)
        startStr.draw(at: NSPoint(x: w / 2 - startSize.width / 2, y: h / 2 - 80), withAttributes: startAttrs)

        // Decorative bananas
        let decoAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30)]
        ("🍌" as NSString).draw(at: NSPoint(x: 30, y: h / 2), withAttributes: decoAttrs)
        ("🍌" as NSString).draw(at: NSPoint(x: w - 60, y: h / 2 + 30), withAttributes: decoAttrs)
        ("🌴" as NSString).draw(at: NSPoint(x: 50, y: h / 2 + 90), withAttributes: decoAttrs)
        ("🌴" as NSString).draw(at: NSPoint(x: w - 80, y: h / 2 + 80), withAttributes: decoAttrs)
    }

    // MARK: - Game Over Screen

    private func drawGameOverScreen(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Dark overlay
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.6).cgColor)
        ctx.fill(bounds)

        // Game over title
        let isNewRecord = score >= highScore && score > 0
        let goTitle = isNewRecord ? L.shared.s("g_new_record") : L.shared.s("g_game_over")
        let goTitleStr = goTitle as NSString
        let goTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 28),
            .foregroundColor: isNewRecord ?
                NSColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1.0) :
                NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0),
        ]
        let goTitleSize = goTitleStr.size(withAttributes: goTitleAttrs)
        goTitleStr.draw(at: NSPoint(x: w / 2 - goTitleSize.width / 2, y: h / 2 + 80), withAttributes: goTitleAttrs)

        // Score
        let scoreStr = L.shared.sf("g_score", score) as NSString
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.white,
        ]
        let scoreSize = scoreStr.size(withAttributes: scoreAttrs)
        scoreStr.draw(at: NSPoint(x: w / 2 - scoreSize.width / 2, y: h / 2 + 40), withAttributes: scoreAttrs)

        // Level
        let lvlStr = L.shared.sf("g_level", level) as NSString
        let lvlAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
        ]
        let lvlSize = lvlStr.size(withAttributes: lvlAttrs)
        lvlStr.draw(at: NSPoint(x: w / 2 - lvlSize.width / 2, y: h / 2 + 10), withAttributes: lvlAttrs)

        // Best score
        let bestStr = L.shared.sf("g_best_score", highScore) as NSString
        let bestAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.9),
        ]
        let bestSize = bestStr.size(withAttributes: bestAttrs)
        bestStr.draw(at: NSPoint(x: w / 2 - bestSize.width / 2, y: h / 2 - 20), withAttributes: bestAttrs)

        // Performance message
        let perfMsg: String
        if score >= 50 { perfMsg = L.shared.s("g_genius") }
        else if score >= 30 { perfMsg = L.shared.s("g_fantastic") }
        else if score >= 15 { perfMsg = L.shared.s("g_well_done") }
        else if score >= 5 { perfMsg = L.shared.s("g_good_start") }
        else { perfMsg = L.shared.s("g_dont_give_up") }

        let perfStr = perfMsg as NSString
        let perfAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor(white: 0.9, alpha: 0.9),
        ]
        let perfSize = perfStr.size(withAttributes: perfAttrs)
        perfStr.draw(at: NSPoint(x: w / 2 - perfSize.width / 2, y: h / 2 - 55), withAttributes: perfAttrs)

        // Restart hint
        let pulse = 0.5 + 0.5 * sin(CGFloat(frameCount) * 0.06)
        let restartStr = L.shared.s("g_press_restart") as NSString
        let restartAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor(white: 1.0, alpha: pulse),
        ]
        let restartSize = restartStr.size(withAttributes: restartAttrs)
        restartStr.draw(at: NSPoint(x: w / 2 - restartSize.width / 2, y: h / 2 - 100), withAttributes: restartAttrs)
    }
}
