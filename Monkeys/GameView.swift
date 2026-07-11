// GameView.swift
// Monkeys
//
// Graphically renders the Banana Catch typing game with day/night cycle,
// palm trees, combos, levels, background music, and visual polish.

import Cocoa

/// A custom graphics canvas view that hosts the game loop.
final class GameView: NSView {

    // MARK: - Types

    enum BananaKind {
        case normal   // 🍌 regular banana
        case golden   // ⭐ bonus: extra points + heals one life
        case bomb     // 💣 trap: typing it costs a life
        case ice      // ❄️ power-up: slows time for a few seconds
    }

    struct GameBanana {
        let character: Character
        var position: CGPoint
        var speed: CGFloat
        let kind: BananaKind
        var wobblePhase: CGFloat
        let size: CGFloat = 40.0
    }

    struct Particle {
        var position: CGPoint
        var velocity: CGVector
        var life: Int
        let totalLife: Int
        var size: CGFloat
        var color: NSColor
    }

    struct Bird {
        var x: CGFloat
        var y: CGFloat
        var speed: CGFloat
        var wingPhase: CGFloat
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
    var onPlayGoldenSound: (() -> Void)?
    var onPlayGameOverSound: (() -> Void)?
    var onGameOver: (() -> Void)?
    var onStartMusic: (() -> Void)?
    var onStopMusic: (() -> Void)?
    var onPauseMusic: (() -> Void)?
    var onResumeMusic: (() -> Void)?


    // MARK: - Game State

    private var bananas: [GameBanana] = []
    private var score = 0
    private var lives = 5
    private var level = 1
    private var comboCount = 0
    private var isGameOver = false
    private var isWaitingToStart = true
    private var isPaused = false

    // Visual feedback
    private var particles: [Particle] = []
    private var birds: [Bird] = []
    private var shakeFrames: Int = 0
    private var bannerText: String = ""
    private var bannerFrames: Int = 0
    private let bannerTotalFrames: Int = 90

    // Power-ups
    private var freezeFrames: Int = 0                  // > 0 while time is slowed
    private let freezeDuration: Int = 300              // 5 s at 60 fps
    private var isFever: Bool { comboCount >= 8 }      // double points while on a hot streak

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
    private var spawnInterval: TimeInterval = 2.0

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
        generateBirds()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        generateStars()
        generatePalmTrees()
        generateClouds()
        generateBirds()
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

    private func generateBirds() {
        birds = [
            Bird(x: -30, y: 460, speed: 0.8, wingPhase: 0),
            Bird(x: -120, y: 505, speed: 0.65, wingPhase: 1.7),
            Bird(x: -220, y: 435, speed: 0.95, wingPhase: 3.1),
        ]
    }

    private func spawnParticles(at point: CGPoint, count: Int, colors: [NSColor]) {
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 1.0...4.0)
            particles.append(Particle(
                position: point,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed + 1.5),
                life: Int.random(in: 25...45),
                totalLife: 45,
                size: CGFloat.random(in: 2.5...5.5),
                color: colors.randomElement()!
            ))
        }
    }

    // MARK: - Game Loop

    func resetGame() {
        bananas.removeAll()
        scorePopups.removeAll()
        particles.removeAll()
        shakeFrames = 0
        bannerFrames = 0
        freezeFrames = 0
        isPaused = false
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
        spawnInterval = 2.0
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

    /// Stops the game loop entirely — call when the window closes so the
    /// 60 fps timer doesn't keep burning CPU in the background.
    func stopGame() {
        gameTimer?.invalidate()
        gameTimer = nil
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
        if isPaused {
            frameCount += 1
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

        // Spawn bananas (freeze slows the spawn cadence too)
        let now = Date()
        var effectiveSpawnInterval = max(0.45, spawnInterval - Double(level - 1) * 0.15)
        if freezeFrames > 0 { effectiveSpawnInterval *= 1.6 }
        let maxBananas = 4 + level
        if now.timeIntervalSince(lastSpawnTime) >= effectiveSpawnInterval && bananas.count < maxBananas {
            spawnBanana()
            lastSpawnTime = now
        }

        // Move bananas (each carries its own speed, with gentle horizontal wobble).
        // While frozen, everything falls at 45% speed.
        let timeScale: CGFloat = freezeFrames > 0 ? 0.45 : 1.0
        if freezeFrames > 0 { freezeFrames -= 1 }
        for i in 0..<bananas.count {
            bananas[i].position.y -= bananas[i].speed * timeScale
            bananas[i].wobblePhase += 0.05 * timeScale
            bananas[i].position.x += sin(bananas[i].wobblePhase) * 0.4 * timeScale
        }

        // Remove fallen bananas — a missed bomb is harmless, a missed banana costs a life
        let groundY: CGFloat = 70.0
        let fallen = bananas.filter { $0.position.y < groundY }
        bananas.removeAll { $0.position.y < groundY }
        for banana in fallen {
            if banana.kind == .bomb {
                // Bomb hits the ground and fizzles out — dust puff, no damage
                spawnParticles(at: CGPoint(x: banana.position.x, y: groundY),
                               count: 8,
                               colors: [NSColor(white: 0.5, alpha: 0.8), NSColor(white: 0.35, alpha: 0.8)])
                continue
            }
            if banana.kind == .ice {
                // A missed power-up just melts away — no penalty
                spawnParticles(at: CGPoint(x: banana.position.x, y: groundY),
                               count: 8,
                               colors: [NSColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 0.8),
                                        NSColor(red: 0.8, green: 0.95, blue: 1.0, alpha: 0.8)])
                continue
            }
            lives -= 1
            comboCount = 0
            shakeFrames = 12
            spawnParticles(at: CGPoint(x: banana.position.x, y: groundY),
                           count: 10,
                           colors: [NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0),
                                    NSColor(red: 0.85, green: 0.65, blue: 0.1, alpha: 1.0)])
            onPlayFailSound?()
            if lives <= 0 {
                endGame()
                return
            }
        }

        // Update particles (simple gravity)
        particles = particles.compactMap { p in
            var particle = p
            particle.position.x += particle.velocity.dx
            particle.position.y += particle.velocity.dy
            particle.velocity.dy -= 0.15
            particle.life -= 1
            return particle.life > 0 ? particle : nil
        }

        // Update birds (fly across during the day)
        for i in 0..<birds.count {
            birds[i].x += birds[i].speed
            birds[i].wingPhase += 0.15
            if birds[i].x > bounds.width + 40 {
                birds[i].x = -CGFloat.random(in: 40...200)
                birds[i].y = CGFloat.random(in: 420...530)
            }
        }

        // Decay screen shake and level banner
        if shakeFrames > 0 { shakeFrames -= 1 }
        if bannerFrames > 0 { bannerFrames -= 1 }

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
        // Never spawn a letter that is already falling: with bombs in play,
        // duplicated letters would make hits ambiguous.
        let usedLetters = Set(bananas.map { $0.character })
        let freeLetters = availableLetters.filter { !usedLetters.contains($0) }
        guard let char = freeLetters.randomElement() else { return }

        let kind: BananaKind
        let roll = Double.random(in: 0...1)
        if level >= 2 && roll < 0.08 {
            kind = .golden
        } else if level >= 4 && roll >= 0.08 && roll < 0.15 && freezeFrames == 0 {
            kind = .ice
        } else if level >= 3 && roll > 0.88 {
            kind = .bomb
        } else {
            kind = .normal
        }

        let x = CGFloat.random(in: 30...(bounds.width - 30))
        var speed = (1.5 + CGFloat(level - 1) * 0.18) * CGFloat.random(in: 0.85...1.15)
        if kind == .golden { speed *= 1.35 } // golden bananas are faster — worth the chase

        let banana = GameBanana(
            character: char,
            position: CGPoint(x: x, y: bounds.height - 20),
            speed: speed,
            kind: kind,
            wobblePhase: CGFloat.random(in: 0...(.pi * 2))
        )
        bananas.append(banana)
    }

    private func endGame() {
        isGameOver = true
        onStopMusic?()
        onPlayGameOverSound?()
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

        // ESC toggles pause during play
        if char == "\u{1B}" {
            isPaused.toggle()
            if isPaused {
                onPauseMusic?()
            } else {
                onResumeMusic?()
            }
            return
        }
        guard !isPaused else { return }

        let upper = Character(String(char).uppercased())
        if let idx = bananas.firstIndex(where: { $0.character == upper }) {
            let banana = bananas[idx]
            let pos = banana.position
            bananas.remove(at: idx)

            // Typing a bomb's letter detonates it!
            if banana.kind == .bomb {
                lives -= 1
                comboCount = 0
                shakeFrames = 18
                spawnParticles(at: pos, count: 22,
                               colors: [NSColor(red: 1.0, green: 0.45, blue: 0.1, alpha: 1.0),
                                        NSColor(red: 1.0, green: 0.2, blue: 0.1, alpha: 1.0),
                                        NSColor(white: 0.4, alpha: 0.9)])
                scorePopups.append(ScorePopup(position: pos, text: "💥", framesRemaining: 40, totalFrames: 40))
                onPlayFailSound?()
                if lives <= 0 {
                    endGame()
                }
                return
            }

            comboCount += 1
            let multiplier = min(comboCount >= 3 ? comboCount - 1 : 1, 5)
            let feverBonus = isFever ? 2 : 1

            var points: Int
            let popupText: String
            switch banana.kind {
            case .golden:
                points = 5 * max(1, multiplier) * feverBonus
                popupText = "+\(points) ⭐"
                if lives < 5 { lives += 1 } // golden banana heals one life
                spawnParticles(at: pos, count: 24,
                               colors: [NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),
                                        NSColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1.0),
                                        NSColor.white])
                onPlayGoldenSound?()
            case .ice:
                points = multiplier * feverBonus
                popupText = "❄️"
                freezeFrames = freezeDuration
                spawnParticles(at: pos, count: 18,
                               colors: [NSColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0),
                                        NSColor(red: 0.8, green: 0.95, blue: 1.0, alpha: 1.0),
                                        NSColor.white])
                onPlayGoldenSound?()
            case .normal, .bomb:
                points = multiplier * feverBonus
                popupText = feverBonus > 1 ? "+\(points) ⚡" : (multiplier > 1 ? "+\(points) 🔥" : "+1")
                spawnParticles(at: pos, count: 12,
                               colors: [NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),
                                        NSColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1.0)])
            }
            score += points

            // Score popup
            scorePopups.append(ScorePopup(position: pos, text: popupText, framesRemaining: 40, totalFrames: 40))

            // Move monkey toward banana
            monkeyTargetX = pos.x
            monkeyBounceFrames = 15

            // Level up check
            let newLevel = (score / 10) + 1
            if newLevel > level {
                level = newLevel
                bannerText = L.shared.sf("g_level_up", level)
                bannerFrames = bannerTotalFrames
                onPlayLevelUpSound?()
            }

            // Combo sound (golden/ice already played their own chime)
            if banana.kind != .golden && banana.kind != .ice {
                if comboCount >= 3 {
                    onPlayComboSound?(comboCount)
                } else {
                    onPlaySuccessSound?()
                }
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

        // Screen shake: jitter the whole scene while shakeFrames > 0
        let isShaking = shakeFrames > 0 && !isGameOver && !isWaitingToStart && !isPaused
        if isShaking {
            let mag = CGFloat(shakeFrames) * 0.5
            ctx.saveGState()
            ctx.translateBy(x: CGFloat.random(in: -mag...mag), y: CGFloat.random(in: -mag...mag))
        }

        // Draw sky gradient based on time of day
        drawSkyGradient(ctx: ctx, w: w, h: h)

        // Draw stars (visible in evening/night)
        if timeOfDay == .evening || timeOfDay == .night || isWaitingToStart {
            drawStars(ctx: ctx)
        }

        // Draw clouds
        drawClouds(ctx: ctx)

        // Draw birds (daytime ambience)
        drawBirds(ctx: ctx)

        // Draw sun/moon
        drawCelestialBody(ctx: ctx, w: w, h: h)

        // Draw palm trees (behind bananas)
        drawPalmTrees(ctx: ctx)

        // Draw ground
        drawGround(ctx: ctx, w: w)

        if isWaitingToStart {
            if isShaking { ctx.restoreGState() }
            drawStartScreen(ctx: ctx, w: w, h: h)
            return
        }

        if isGameOver {
            if isShaking { ctx.restoreGState() }
            drawGameOverScreen(ctx: ctx, w: w, h: h)
            return
        }

        // Draw bananas
        drawBananas(ctx: ctx)

        // Draw monkey
        drawMonkey(ctx: ctx, w: w)

        // Draw particles
        drawParticles(ctx: ctx)

        // Draw score popups
        drawScorePopups(ctx: ctx)

        // Icy tint while time is slowed
        if freezeFrames > 0 {
            let fade = min(1.0, CGFloat(freezeFrames) / 40.0)
            ctx.setFillColor(NSColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.10 * fade).cgColor)
            ctx.fill(bounds)
        }

        if isShaking { ctx.restoreGState() }

        // Draw HUD
        drawHUD(ctx: ctx, w: w, h: h)

        // Level-up banner
        if bannerFrames > 0 {
            drawLevelBanner(ctx: ctx, w: w, h: h)
        }

        // Pause overlay
        if isPaused {
            drawPauseOverlay(ctx: ctx, w: w, h: h)
        }
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

        // Vector grass blades along the top edge, gently swaying.
        // Heights come from a position-based hash so they don't flicker per frame.
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        for i in stride(from: 0, to: Int(w), by: 7) {
            let x = CGFloat(i)
            let hash = sin(x * 12.9898) * 43758.5453
            let frac = hash - floor(hash) // 0..1, stable per blade
            let height = 5.0 + frac * 9.0
            let sway = sin(CGFloat(frameCount) * 0.03 + x * 0.15) * 2.0
            let shade = 0.75 + frac * 0.5
            ctx.setStrokeColor(grassTop.withAlphaComponent(0.9)
                .blended(withFraction: 1.0 - min(shade, 1.0), of: .black)?.cgColor ?? grassTop.cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: groundH - 2))
            ctx.addQuadCurve(to: CGPoint(x: x + sway, y: groundH + height),
                             control: CGPoint(x: x + sway * 0.3, y: groundH + height * 0.5))
            ctx.strokePath()
        }
    }

    // MARK: - Game Elements

    private func drawBananas(ctx: CGContext) {
        for banana in bananas {
            let x = banana.position.x
            let y = banana.position.y

            // Glow circle behind banana (kind-specific)
            let glowColor: NSColor
            switch banana.kind {
            case .golden:
                // Pulsing golden halo
                let pulse = 0.35 + 0.2 * sin(CGFloat(frameCount) * 0.15 + banana.wobblePhase)
                glowColor = NSColor(red: 1.0, green: 0.85, blue: 0.1, alpha: pulse)
                ctx.setFillColor(glowColor.cgColor)
                ctx.fillEllipse(in: CGRect(x: x - 24, y: y - 24, width: 48, height: 48))
            case .bomb:
                // Menacing red halo
                let pulse = 0.25 + 0.15 * sin(CGFloat(frameCount) * 0.2)
                glowColor = NSColor(red: 1.0, green: 0.2, blue: 0.1, alpha: pulse)
                ctx.setFillColor(glowColor.cgColor)
                ctx.fillEllipse(in: CGRect(x: x - 20, y: y - 20, width: 40, height: 40))
            case .ice:
                // Cool cyan halo
                let pulse = 0.3 + 0.15 * sin(CGFloat(frameCount) * 0.12)
                glowColor = NSColor(red: 0.5, green: 0.85, blue: 1.0, alpha: pulse)
                ctx.setFillColor(glowColor.cgColor)
                ctx.fillEllipse(in: CGRect(x: x - 22, y: y - 22, width: 44, height: 44))
            case .normal:
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
            }

            // Falling item emoji
            let emoji: String
            switch banana.kind {
            case .normal: emoji = "🍌"
            case .golden: emoji = "🌟"
            case .bomb:   emoji = "💣"
            case .ice:    emoji = "❄️"
            }
            let bananaStr = emoji as NSString
            let bananaAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26)]
            bananaStr.draw(at: NSPoint(x: x - 14, y: y - 14), withAttributes: bananaAttrs)

            // Letter badge
            let letterStr = String(banana.character) as NSString
            let badgeColor: NSColor
            let letterColor: NSColor
            switch banana.kind {
            case .golden:
                badgeColor = NSColor(red: 0.55, green: 0.42, blue: 0.05, alpha: 0.9)
                letterColor = NSColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1.0)
            case .bomb:
                badgeColor = NSColor(red: 0.45, green: 0.08, blue: 0.05, alpha: 0.9)
                letterColor = NSColor(red: 1.0, green: 0.75, blue: 0.7, alpha: 1.0)
            case .ice:
                badgeColor = NSColor(red: 0.1, green: 0.3, blue: 0.5, alpha: 0.9)
                letterColor = NSColor(red: 0.8, green: 0.95, blue: 1.0, alpha: 1.0)
            case .normal:
                badgeColor = NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.85)
                letterColor = .white
            }
            let letterAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: letterColor,
            ]
            let letterSize = letterStr.size(withAttributes: letterAttrs)
            ctx.setFillColor(badgeColor.cgColor)
            ctx.fillEllipse(in: CGRect(
                x: x - letterSize.width / 2 - 4,
                y: y - 28,
                width: letterSize.width + 8,
                height: letterSize.height + 4
            ))
            letterStr.draw(at: NSPoint(x: x - letterSize.width / 2, y: y - 26), withAttributes: letterAttrs)
        }
    }

    private func drawParticles(ctx: CGContext) {
        for particle in particles {
            let alpha = CGFloat(particle.life) / CGFloat(particle.totalLife)
            ctx.setFillColor(particle.color.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: particle.position.x - particle.size / 2,
                y: particle.position.y - particle.size / 2,
                width: particle.size,
                height: particle.size
            ))
        }
    }

    private func drawBirds(ctx: CGContext) {
        // Birds only fly during daylight, and not on menu screens
        guard !isWaitingToStart && !isGameOver else { return }
        guard timeOfDay == .morning || timeOfDay == .afternoon else { return }

        let birdColor: NSColor = timeOfDay == .morning ?
            NSColor(white: 0.25, alpha: 0.7) : NSColor(white: 0.2, alpha: 0.8)
        ctx.setStrokeColor(birdColor.cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineCap(.round)

        for bird in birds {
            let flap = sin(bird.wingPhase) * 4.0
            // Two arcs forming a "V" seagull silhouette with flapping wings
            ctx.beginPath()
            ctx.move(to: CGPoint(x: bird.x - 7, y: bird.y + flap))
            ctx.addQuadCurve(to: CGPoint(x: bird.x, y: bird.y),
                             control: CGPoint(x: bird.x - 3.5, y: bird.y + 3 + flap))
            ctx.addQuadCurve(to: CGPoint(x: bird.x + 7, y: bird.y + flap),
                             control: CGPoint(x: bird.x + 3.5, y: bird.y + 3 + flap))
            ctx.strokePath()
        }
    }

    private func drawLevelBanner(ctx: CGContext, w: CGFloat, h: CGFloat) {
        let progress = CGFloat(bannerFrames) / CGFloat(bannerTotalFrames)
        // Fade in fast at the start, fade out toward the end
        let alpha: CGFloat = progress > 0.85 ? (1.0 - progress) / 0.15 : min(1.0, progress / 0.3)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: roundedFont(size: 30, weight: .heavy),
            .foregroundColor: NSColor(red: 0.5, green: 1.0, blue: 0.5, alpha: alpha),
            .strokeColor: NSColor(red: 0.0, green: 0.3, blue: 0.0, alpha: alpha),
            .strokeWidth: -3.0,
        ]
        let str = bannerText as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: w / 2 - size.width / 2, y: h / 2 + 100), withAttributes: attrs)
    }

    private func drawPauseOverlay(ctx: CGContext, w: CGFloat, h: CGFloat) {
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.55).cgColor)
        ctx.fill(bounds)

        let pauseStr = "⏸" as NSString
        let pauseAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 60)]
        let ps = pauseStr.size(withAttributes: pauseAttrs)
        pauseStr.draw(at: NSPoint(x: w / 2 - ps.width / 2, y: h / 2 + 30), withAttributes: pauseAttrs)

        let titleStr = L.shared.s("g_paused") as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 26),
            .foregroundColor: NSColor.white,
        ]
        let ts = titleStr.size(withAttributes: titleAttrs)
        titleStr.draw(at: NSPoint(x: w / 2 - ts.width / 2, y: h / 2 - 10), withAttributes: titleAttrs)

        let pulse = 0.5 + 0.5 * sin(CGFloat(frameCount) * 0.06)
        let hintStr = L.shared.s("g_resume_hint") as NSString
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor(white: 1.0, alpha: pulse),
        ]
        let hs = hintStr.size(withAttributes: hintAttrs)
        hintStr.draw(at: NSPoint(x: w / 2 - hs.width / 2, y: h / 2 - 45), withAttributes: hintAttrs)
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

    /// System font with the rounded design — friendlier than the default
    /// without looking childish.
    private func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: desc, size: size) {
            return rounded
        }
        return base
    }

    /// Draws a small vector heart (two lobes + triangle) — crisper than emoji
    /// hearts at small sizes and adapts to filled/empty states.
    private func drawHeart(ctx: CGContext, at c: CGPoint, size s: CGFloat, filled: Bool) {
        let color = filled ?
            NSColor(red: 1.0, green: 0.33, blue: 0.38, alpha: 0.95) :
            NSColor(white: 1.0, alpha: 0.22)
        ctx.setFillColor(color.cgColor)

        let r = s * 0.28
        // Two top lobes
        ctx.fillEllipse(in: CGRect(x: c.x - 2 * r, y: c.y - r + s * 0.1, width: 2 * r, height: 2 * r))
        ctx.fillEllipse(in: CGRect(x: c.x, y: c.y - r + s * 0.1, width: 2 * r, height: 2 * r))
        // Bottom wedge down to the tip
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: c.x - 1.9 * r, y: c.y + s * 0.08))
        tri.addLine(to: CGPoint(x: c.x + 1.9 * r, y: c.y + s * 0.08))
        tri.addLine(to: CGPoint(x: c.x, y: c.y - s * 0.5))
        tri.closeSubpath()
        ctx.addPath(tri)
        ctx.fillPath()
    }

    private func drawHUD(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Translucent rounded panel with a hairline border
        let panelRect = CGRect(x: 8, y: h - 46, width: w - 16, height: 38)
        let panelPath = CGPath(roundedRect: panelRect, cornerWidth: 11, cornerHeight: 11, transform: nil)
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.38).cgColor)
        ctx.addPath(panelPath)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(panelPath)
        ctx.strokePath()

        // Score — banana glyph + monospaced digits
        ("🍌" as NSString).draw(at: NSPoint(x: panelRect.minX + 10, y: panelRect.midY - 8),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
        let scoreStr = "\(score)" as NSString
        scoreStr.draw(at: NSPoint(x: panelRect.minX + 30, y: panelRect.midY - 10), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .bold),
            .foregroundColor: NSColor.white,
        ])

        // Lives — five vector hearts, centered
        let heartSpacing: CGFloat = 17
        let firstHeartX = w / 2 - heartSpacing * 2
        for i in 0..<5 {
            drawHeart(ctx: ctx,
                      at: CGPoint(x: firstHeartX + CGFloat(i) * heartSpacing, y: panelRect.midY),
                      size: 11,
                      filled: i < lives)
        }

        // Level label (right) with a thin progress bar to the next level
        let lvlStr = "LV \(level)" as NSString
        let lvlAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(red: 0.65, green: 1.0, blue: 0.65, alpha: 1.0),
        ]
        let lvlSize = lvlStr.size(withAttributes: lvlAttrs)
        lvlStr.draw(at: NSPoint(x: panelRect.maxX - lvlSize.width - 12, y: panelRect.midY + 1),
                    withAttributes: lvlAttrs)

        let barW: CGFloat = 44
        let barX = panelRect.maxX - barW - 12
        let barY = panelRect.midY - 9
        let progress = CGFloat(score % 10) / 10.0
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: barX, y: barY, width: barW, height: 4),
                           cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.fillPath()
        if progress > 0 {
            ctx.setFillColor(NSColor(red: 0.65, green: 1.0, blue: 0.65, alpha: 0.9).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: barX, y: barY, width: max(4, barW * progress), height: 4),
                               cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.fillPath()
        }

        // Fever / combo indicator below the panel
        if isFever {
            let pulse = 0.75 + 0.25 * sin(CGFloat(frameCount) * 0.25)
            let feverStr = "⚡ FEVER ×2" as NSString
            let feverAttrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont(size: 18, weight: .heavy),
                .foregroundColor: NSColor(red: 1.0, green: 0.8, blue: 0.1, alpha: pulse),
            ]
            let fs = feverStr.size(withAttributes: feverAttrs)
            feverStr.draw(at: NSPoint(x: w / 2 - fs.width / 2, y: h - 72), withAttributes: feverAttrs)
        } else if comboCount >= 3 {
            let comboStr = "🔥 \(comboCount)×" as NSString
            let comboAttrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont(size: 16, weight: .bold),
                .foregroundColor: NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1.0),
            ]
            let cs = comboStr.size(withAttributes: comboAttrs)
            comboStr.draw(at: NSPoint(x: w / 2 - cs.width / 2, y: h - 70), withAttributes: comboAttrs)
        }

        // Freeze countdown (left, under the panel)
        if freezeFrames > 0 {
            let secs = freezeFrames / 60 + 1
            let frzStr = "❄️ \(secs)s" as NSString
            frzStr.draw(at: NSPoint(x: 14, y: h - 70), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 0.95),
            ])
        }

        // Time of day indicator (right, under the panel)
        let timeEmoji: String
        switch timeOfDay {
        case .morning: timeEmoji = "🌅"
        case .afternoon: timeEmoji = "☀️"
        case .evening: timeEmoji = "🌇"
        case .night: timeEmoji = "🌙"
        }
        (timeEmoji as NSString).draw(at: NSPoint(x: w - 30, y: h - 70),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
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
            .font: roundedFont(size: 32, weight: .heavy),
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

        // Legend for special bananas
        let legendStr = L.shared.s("g_legend") as NSString
        let legendAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(white: 0.75, alpha: 0.9),
        ]
        let legendSize = legendStr.size(withAttributes: legendAttrs)
        legendStr.draw(at: NSPoint(x: w / 2 - legendSize.width / 2, y: h / 2 - 28), withAttributes: legendAttrs)

        // High score
        if highScore > 0 {
            let hsStr = L.shared.sf("g_best_score", highScore) as NSString
            let hsAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.9),
            ]
            let hsSize = hsStr.size(withAttributes: hsAttrs)
            hsStr.draw(at: NSPoint(x: w / 2 - hsSize.width / 2, y: h / 2 - 52), withAttributes: hsAttrs)
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

    }

    // MARK: - Game Over Screen

    private func drawGameOverScreen(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Dark overlay
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.6).cgColor)
        ctx.fill(bounds)

        // Rounded card behind the stats
        let cardRect = CGRect(x: w / 2 - 155, y: h / 2 - 118, width: 310, height: 240)
        let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.setFillColor(NSColor(white: 0.07, alpha: 0.72).cgColor)
        ctx.addPath(cardPath)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(cardPath)
        ctx.strokePath()

        // Game over title
        let isNewRecord = score >= highScore && score > 0
        let goTitle = isNewRecord ? L.shared.s("g_new_record") : L.shared.s("g_game_over")
        let goTitleStr = goTitle as NSString
        let goTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: roundedFont(size: 28, weight: .heavy),
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
