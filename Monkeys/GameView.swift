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
        case word     // 🍌🍌 bunch: type the whole word to catch it
    }

    struct GameBanana {
        let character: Character
        var position: CGPoint
        var speed: CGFloat
        let kind: BananaKind
        var wobblePhase: CGFloat
        var warned: Bool = false
        /// Word-bunch payload: full word and letters already typed.
        var word: String?
        var typedCount: Int = 0
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
    var onDuckMusic: (() -> Void)?
    var onPlayTick: (() -> Void)?


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
    private var bannerText: String = ""
    private var bannerFrames: Int = 0
    private let bannerTotalFrames: Int = 90

    // Game feel
    /// Caught banana flying to the monkey (80 ms tween closes the
    /// cause→effect loop: "I typed → she caught it").
    struct FlyingCatch {
        var from: CGPoint
        let kind: BananaKind
        var t: CGFloat
        let popupText: String
    }
    private var flyingCatches: [FlyingCatch] = []
    /// Freeze-frame counter: 2-3 skipped update frames on important events.
    private var hitStopFrames: Int = 0
    /// Damped-spring screen shake (reads as impact, not glitch).
    private var shakeOffset: CGFloat = 0
    private var shakeVelocity: CGFloat = 0
    /// Score shown in the HUD eases toward the real score (count-up ticker).
    private var displayedScore: CGFloat = 0
    /// Red vignette pulse after losing a life.
    private var missFlashFrames: Int = 0
    /// Brief slow-motion when Fever triggers, so the state change lands.
    private var feverSlowmoFrames: Int = 0
    private var wasFever = false
    /// First-30-seconds ramp bookkeeping.
    private var spawnCount = 0
    private var scriptedGoldenDone = false
    /// Staggered game-over reveal.
    private var gameOverFrame = 0
    private var lastRunDelta: Int?
    private var earnedMedal: Medal = .none
    private var earnedMedalIsNew = false
    /// Monkey pose animation.
    private enum MonkeyPose { case idle, reach, celebrate }
    private var monkeyPose: MonkeyPose = .idle
    private var poseFrames = 0
    private var reachTarget: CGPoint = .zero
    /// Y below which a banana is "in danger" (line + pulse + warning tick).
    private let dangerY: CGFloat = 165

    // Power-ups
    private var freezeFrames: Int = 0                  // > 0 while time is slowed
    private let freezeDuration: Int = 300              // 5 s at 60 fps
    private var isFever: Bool { comboCount >= 8 }      // double points while on a hot streak

    // Zen mode: no lives lost — relaxed play for younger players (persisted)
    private var isZenMode: Bool = UserDefaults.standard.bool(forKey: "MonkeysZenMode")

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
    private var spawnInterval: TimeInterval = 1.6

    // High score
    private var highScore: Int = UserDefaults.standard.integer(forKey: "MonkeysHighScore")

    // Animation
    private var gameTimer: Timer?
    private var frameCount: Int = 0

    // Available letters
    private let availableLetters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Short jungle words for word-bunches (accent-free by design).
    /// Non-latin locales fall back to English.
    private static let wordBunchBank: [L.Lang: [String]] = [
        .it: ["SOLE", "LUNA", "MARE", "RAMO", "NIDO", "VENTO", "CIELO", "SALTO", "PALMA", "MANGO", "LIANA", "COCCO"],
        .en: ["SUN", "MOON", "TREE", "VINE", "LEAF", "PALM", "NEST", "WIND", "RAIN", "MANGO", "JUMP", "STAR"],
        .es: ["SOL", "LUNA", "MAR", "RAMA", "NIDO", "PALMA", "MANGO", "CIELO", "SALTO", "COCO"],
        .fr: ["LUNE", "MER", "NID", "VENT", "CIEL", "SAUT", "PALME", "COCO", "LIANE"],
        .de: ["SONNE", "MOND", "BAUM", "NEST", "WIND", "PALME", "MANGO", "AST", "MEER"],
        .pt: ["SOL", "LUA", "MAR", "NINHO", "PALMA", "MANGA", "VENTO", "SALTO", "COCO"],
    ]

    private func randomBunchWord() -> String {
        let bank = Self.wordBunchBank[L.shared.current] ?? Self.wordBunchBank[.en] ?? ["MANGO"]
        return bank.randomElement() ?? "MANGO"
    }

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

    /// Downward impulse; the spring brings it back with damped oscillation.
    private func shakeImpulse(_ strength: CGFloat) {
        shakeVelocity -= strength
    }

    func resetGame() {
        bananas.removeAll()
        scorePopups.removeAll()
        particles.removeAll()
        flyingCatches.removeAll()
        hitStopFrames = 0
        shakeOffset = 0
        shakeVelocity = 0
        displayedScore = 0
        missFlashFrames = 0
        feverSlowmoFrames = 0
        wasFever = false
        spawnCount = 0
        scriptedGoldenDone = false
        gameOverFrame = 0
        lastRunDelta = nil
        earnedMedal = .none
        earnedMedalIsNew = false
        monkeyPose = .idle
        poseFrames = 0
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
        spawnInterval = 1.6
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
            // Staggered end-screen reveal, with a tick on each step
            gameOverFrame += 1
            if [1, 15, 45, 60, 78].contains(gameOverFrame) {
                onPlayTick?()
            }
            setNeedsDisplay(bounds)
            return
        }
        if isPaused {
            frameCount += 1
            setNeedsDisplay(bounds)
            return
        }
        // Hit-stop: freeze the world for 2-3 frames on heavy events
        if hitStopFrames > 0 {
            hitStopFrames -= 1
            setNeedsDisplay(bounds)
            return
        }

        frameCount += 1
        gameElapsedSeconds += 1.0 / 60.0

        // Damped-spring shake (k=0.28, damping=0.72)
        if abs(shakeOffset) > 0.05 || abs(shakeVelocity) > 0.05 {
            shakeVelocity += -0.28 * shakeOffset
            shakeVelocity *= 0.72
            shakeOffset += shakeVelocity
        } else {
            shakeOffset = 0
            shakeVelocity = 0
        }

        // Score count-up ticker
        displayedScore += (CGFloat(score) - displayedScore) * 0.22
        if abs(displayedScore - CGFloat(score)) < 0.05 { displayedScore = CGFloat(score) }

        if missFlashFrames > 0 { missFlashFrames -= 1 }

        // Fever slow-mo on the frame it triggers
        if isFever && !wasFever {
            feverSlowmoFrames = 15
        }
        wasFever = isFever
        if feverSlowmoFrames > 0 { feverSlowmoFrames -= 1 }

        // Flying catches: 80 ms ease-in flight toward the monkey
        let monkeyPoint = CGPoint(x: monkeyX, y: 70 + monkeyBounceOffset + 30)
        flyingCatches = flyingCatches.compactMap { fc in
            var catchItem = fc
            catchItem.t += 0.2
            if catchItem.t >= 1.0 {
                // Arrival: burst + popup at the monkey — the catch is visible
                let colors: [NSColor]
                switch catchItem.kind {
                case .golden: colors = [NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),
                                        NSColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1.0), .white]
                case .ice:    colors = [NSColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0),
                                        NSColor(red: 0.8, green: 0.95, blue: 1.0, alpha: 1.0), .white]
                default:      colors = [NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),
                                        NSColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1.0)]
                }
                spawnParticles(at: monkeyPoint, count: catchItem.kind == .golden ? 22 : 12, colors: colors)
                scorePopups.append(ScorePopup(position: CGPoint(x: monkeyPoint.x, y: monkeyPoint.y + 14),
                                              text: catchItem.popupText, framesRemaining: 40, totalFrames: 40))
                return nil
            }
            return catchItem
        }

        // Monkey pose timers
        if poseFrames > 0 {
            poseFrames -= 1
            if poseFrames == 0 { monkeyPose = isFever ? .celebrate : .idle }
        } else {
            monkeyPose = isFever ? .celebrate : .idle
        }

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
        // While frozen: 45% speed. Fever onset: brief 35% slow-mo so the
        // state change registers.
        var timeScale: CGFloat = freezeFrames > 0 ? 0.45 : 1.0
        if feverSlowmoFrames > 0 { timeScale *= 0.35 }
        if freezeFrames > 0 { freezeFrames -= 1 }
        // Evening wind: lateral drift, telegraphed by the swaying palms
        let wind: CGFloat = timeOfDay == .evening ?
            sin(CGFloat(frameCount) * 0.008) * 0.45 : 0
        for i in 0..<bananas.count {
            bananas[i].position.y -= bananas[i].speed * timeScale
            bananas[i].wobblePhase += 0.05 * timeScale
            bananas[i].position.x += (sin(bananas[i].wobblePhase) * 0.4 + wind) * timeScale
            bananas[i].position.x = min(max(bananas[i].position.x, 16), bounds.width - 16)
            // Danger warning: one tick as each banana crosses the line
            if !bananas[i].warned && bananas[i].position.y < dangerY && bananas[i].kind != .bomb && bananas[i].kind != .ice {
                bananas[i].warned = true
                onPlayTick?()
            }
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
            if !isZenMode { lives -= 1 }
            comboCount = 0
            shakeImpulse(7)
            missFlashFrames = 12
            spawnParticles(at: CGPoint(x: banana.position.x, y: groundY),
                           count: 10,
                           colors: [NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0),
                                    NSColor(red: 0.85, green: 0.65, blue: 0.1, alpha: 1.0)])
            // Heart-shatter shards near the HUD lives
            spawnParticles(at: CGPoint(x: bounds.width / 2, y: bounds.height - 27),
                           count: 6,
                           colors: [NSColor(red: 1.0, green: 0.33, blue: 0.38, alpha: 1.0)])
            onPlayFailSound?()
            onDuckMusic?()
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

        // Decay level banner (shake is spring-driven above)
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

        spawnCount += 1

        var kind: BananaKind
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
        // Word bunch: from level 4, ~14% of spawns, never more than one
        // falling at a time (keeps the matching unambiguous).
        let hasWordBunch = bananas.contains { $0.kind == .word }
        if level >= 4 && !hasWordBunch && kind == .normal && roll >= 0.16 && roll < 0.30 {
            kind = .word
        }

        // First-30s ramp: the first 3 bananas are always plain and gentle
        // (implicit tutorial), and one golden is guaranteed around second 13
        // so the player tastes the reward early and starts chasing it.
        if spawnCount <= 3 {
            kind = .normal
        } else if !scriptedGoldenDone && gameElapsedSeconds > 12 {
            kind = .golden
            scriptedGoldenDone = true
        }
        if kind == .golden { scriptedGoldenDone = true }

        let x = CGFloat.random(in: 30...(bounds.width - 30))
        var speed = (1.5 + CGFloat(level - 1) * 0.18) * CGFloat.random(in: 0.85...1.15)
        if spawnCount <= 3 { speed *= 0.8 }
        if kind == .golden { speed *= 1.35 } // golden bananas are faster — worth the chase
        if kind == .word { speed *= 0.62 }   // whole word to type: falls slower

        var bunchWord: String?
        var bunchChar = char
        if kind == .word {
            // Prefer a word whose first letter isn't already falling
            var candidate = randomBunchWord()
            for _ in 0..<4 where usedLetters.contains(candidate.first ?? " ") {
                candidate = randomBunchWord()
            }
            bunchWord = candidate
            bunchChar = candidate.first ?? "M"
        }

        let banana = GameBanana(
            character: bunchChar,
            position: CGPoint(x: x, y: bounds.height - 20),
            speed: speed,
            kind: kind,
            wobblePhase: CGFloat.random(in: 0...(.pi * 2)),
            word: bunchWord
        )
        bananas.append(banana)
    }

    private func endGame() {
        isGameOver = true
        gameOverFrame = 0
        flyingCatches.removeAll()
        onStopMusic?()
        onPlayGameOverSound?()
        onGameOver?()

        if !isZenMode {
            // Delta vs previous run — the "one more try" hook
            let previous = UserDefaults.standard.integer(forKey: "MonkeysLastGameScore")
            lastRunDelta = previous > 0 ? score - previous : nil
            UserDefaults.standard.set(score, forKey: "MonkeysLastGameScore")

            let result = GameProgress.shared.recordRun(mode: "bananas", score: score)
            earnedMedal = result.medal
            earnedMedalIsNew = result.isNewBest
            GameProgress.shared.registerScore(score)
        }

        if score > highScore && !isZenMode {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "MonkeysHighScore")
        }
    }

    // MARK: - Key Input

    func handleKeyTyped(_ char: Character) {
        if isWaitingToStart {
            // ESC on the start screen should not launch a game
            if char == "\u{1B}" { return }
            // Z toggles Zen mode on the start screen; any other key starts
            if char == "z" || char == "Z" {
                isZenMode.toggle()
                UserDefaults.standard.set(isZenMode, forKey: "MonkeysZenMode")
                return
            }
            isWaitingToStart = false
            onStartMusic?()
            return
        }
        if isGameOver {
            if gameOverFrame >= 45 { resetGame() }
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

        // 1) A word bunch already in progress captures the input first
        if let wIdx = bananas.firstIndex(where: { $0.kind == .word && $0.typedCount > 0 }) {
            if let word = bananas[wIdx].word {
                let letters = Array(word)
                if bananas[wIdx].typedCount < letters.count && letters[bananas[wIdx].typedCount] == upper {
                    advanceWordBunch(at: wIdx)
                } else {
                    // Wrong letter: the word resets, combo breaks
                    bananas[wIdx].typedCount = 0
                    comboCount = 0
                    onPlayFailSound?()
                }
                return
            }
        }

        if let idx = bananas.firstIndex(where: { $0.kind != .word && $0.character == upper }) {
            let banana = bananas[idx]
            let pos = banana.position
            bananas.remove(at: idx)

            // Typing a bomb's letter detonates it!
            if banana.kind == .bomb {
                if !isZenMode { lives -= 1 }
                comboCount = 0
                shakeImpulse(11)
                hitStopFrames = 3
                missFlashFrames = 12
                onDuckMusic?()
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
                hitStopFrames = 3 // freeze-frame: this event matters
                GameProgress.shared.registerGolden()
                onPlayGoldenSound?()
            case .ice:
                points = multiplier * feverBonus
                popupText = "❄️"
                freezeFrames = freezeDuration
                onPlayGoldenSound?()
            case .normal, .bomb, .word:
                points = multiplier * feverBonus
                popupText = feverBonus > 1 ? "+\(points) ⚡" : (multiplier > 1 ? "+\(points) 🔥" : "+1")
            }
            score += points

            // The banana flies to the monkey (particles + popup on arrival)
            flyingCatches.append(FlyingCatch(from: pos, kind: banana.kind, t: 0, popupText: popupText))

            // Monkey reaches toward the catch point
            monkeyTargetX = pos.x
            monkeyBounceFrames = 15
            monkeyPose = .reach
            poseFrames = 12
            reachTarget = pos

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
        } else if let wIdx = bananas.firstIndex(where: { $0.kind == .word && $0.word?.first == upper }) {
            // 3) Start typing a word bunch
            advanceWordBunch(at: wIdx)
        } else {
            comboCount = 0
            onPlayFailSound?()
        }
    }

    /// Advances a word bunch by one letter; completes the catch when the
    /// whole word has been typed.
    private func advanceWordBunch(at index: Int) {
        guard index < bananas.count, let word = bananas[index].word else { return }
        bananas[index].typedCount += 1
        comboCount += 1
        onPlayTick?() // soft per-letter feedback

        guard bananas[index].typedCount >= word.count else { return }

        // Word complete: worth its length, with combo and fever multipliers
        let banana = bananas[index]
        let pos = banana.position
        bananas.remove(at: index)

        let multiplier = min(comboCount >= 3 ? comboCount - 1 : 1, 5)
        let feverBonus = isFever ? 2 : 1
        let points = word.count * max(1, multiplier) * feverBonus
        score += points
        hitStopFrames = 2

        flyingCatches.append(FlyingCatch(from: pos, kind: .word, t: 0, popupText: "+\(points) 🍌"))
        monkeyTargetX = pos.x
        monkeyBounceFrames = 15
        monkeyPose = .reach
        poseFrames = 12
        reachTarget = pos

        let newLevel = (score / 10) + 1
        if newLevel > level {
            level = newLevel
            bannerText = L.shared.sf("g_level_up", level)
            bannerFrames = bannerTotalFrames
            onPlayLevelUpSound?()
        }

        if comboCount >= 3 {
            onPlayComboSound?(comboCount)
        } else {
            onPlaySuccessSound?()
        }
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        if isWaitingToStart {
            isWaitingToStart = false
            onStartMusic?()
            return
        }
        if isGameOver {
            if gameOverFrame >= 45 { resetGame() }
            return
        }
        if isPaused {
            isPaused = false
            onResumeMusic?()
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height

        // Damped-spring shake: a downward impact that springs back
        let isShaking = abs(shakeOffset) > 0.1 && !isGameOver && !isWaitingToStart && !isPaused
        if isShaking {
            ctx.saveGState()
            ctx.translateBy(x: shakeOffset * 0.25, y: shakeOffset)
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

        // Danger line: subtle when clear, red when a banana has crossed it
        let anyDanger = bananas.contains { $0.position.y < dangerY && $0.kind != .bomb && $0.kind != .ice }
        let lineAlpha: CGFloat = anyDanger ? 0.30 : 0.10
        let lineColor = anyDanger ?
            NSColor(red: 1.0, green: 0.35, blue: 0.3, alpha: lineAlpha) :
            NSColor(white: 1.0, alpha: lineAlpha)
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: CGFloat(frameCount) * 0.5, lengths: [6, 6])
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 12, y: dangerY))
        ctx.addLine(to: CGPoint(x: w - 12, y: dangerY))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        // Draw bananas
        drawBananas(ctx: ctx)

        // Flying catches (banana zipping to the monkey, ease-in, shrinking)
        let monkeyPoint = CGPoint(x: monkeyX, y: 70 + monkeyBounceOffset + 30)
        for fc in flyingCatches {
            let e = fc.t * fc.t // ease-in
            let x = fc.from.x + (monkeyPoint.x - fc.from.x) * e
            let y = fc.from.y + (monkeyPoint.y - fc.from.y) * e
            let emoji: String
            switch fc.kind {
            case .golden: emoji = "🌟"
            case .ice:    emoji = "❄️"
            default:      emoji = "🍌"
            }
            let scale = 1.0 - 0.5 * e
            (emoji as NSString).draw(at: NSPoint(x: x - 13 * scale, y: y - 13 * scale),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 26 * scale)])
        }

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

        // Red vignette pulse after losing a life (the loss must *cost*)
        if missFlashFrames > 0 {
            let intensity = CGFloat(missFlashFrames) / 12.0
            for (inset, alpha) in [(CGFloat(3), 0.35), (10, 0.18), (20, 0.08)] {
                ctx.setStrokeColor(NSColor(red: 1.0, green: 0.2, blue: 0.15,
                                           alpha: alpha * intensity).cgColor)
                ctx.setLineWidth(inset == 3 ? 4 : 10)
                ctx.stroke(bounds.insetBy(dx: inset, dy: inset))
            }
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
            let swayAngle = sin(tree.sway) * (timeOfDay == .evening ? 0.16 : 0.08)

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

            // Urgency ring: pulsing red outline once past the danger line —
            // the eye always knows which banana to save first
            if y < dangerY && banana.kind != .bomb && banana.kind != .ice {
                let pulse = 0.45 + 0.35 * sin(CGFloat(frameCount) * 0.35)
                ctx.setStrokeColor(NSColor(red: 1.0, green: 0.3, blue: 0.25, alpha: pulse).cgColor)
                ctx.setLineWidth(2.5)
                ctx.strokeEllipse(in: CGRect(x: x - 21, y: y - 21, width: 42, height: 42))
            }

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
            case .word:
                // Leafy green halo, pulsing faster as letters land
                let pulse = 0.28 + 0.14 * sin(CGFloat(frameCount) * (0.1 + CGFloat(banana.typedCount) * 0.05))
                glowColor = NSColor(red: 0.4, green: 0.95, blue: 0.45, alpha: pulse)
                ctx.setFillColor(glowColor.cgColor)
                ctx.fillEllipse(in: CGRect(x: x - 24, y: y - 24, width: 48, height: 48))
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
            var emojiSize: CGFloat = 26
            switch banana.kind {
            case .normal: emoji = "🍌"
            case .golden: emoji = "🌟"
            case .bomb:   emoji = "💣"
            case .ice:    emoji = "❄️"
            case .word:   emoji = "🍌"; emojiSize = 32
            }
            let bananaStr = emoji as NSString
            let bananaAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: emojiSize)]
            bananaStr.draw(at: NSPoint(x: x - emojiSize / 2 + 2, y: y - emojiSize / 2 + 2), withAttributes: bananaAttrs)

            // Word bunch: progress badge (typed part green, rest white)
            if banana.kind == .word, let word = banana.word {
                let typed = String(word.prefix(banana.typedCount)) as NSString
                let rest = String(word.dropFirst(banana.typedCount)) as NSString
                let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
                let typedAttrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: NSColor(red: 0.35, green: 1.0, blue: 0.45, alpha: 1.0)]
                let restAttrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: NSColor.white]
                let typedW = typed.size(withAttributes: typedAttrs).width
                let restW = rest.size(withAttributes: restAttrs).width
                let totalW = typedW + restW
                let badgeRect = CGRect(x: x - totalW / 2 - 6, y: y - 36, width: totalW + 12, height: 19)
                let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                ctx.setFillColor(NSColor(red: 0.05, green: 0.25, blue: 0.08, alpha: 0.9).cgColor)
                ctx.addPath(badgePath)
                ctx.fillPath()
                typed.draw(at: NSPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 2), withAttributes: typedAttrs)
                rest.draw(at: NSPoint(x: badgeRect.minX + 6 + typedW, y: badgeRect.minY + 2), withAttributes: restAttrs)
                continue
            }

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
            case .normal, .word:
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
            if let flameGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: flameColors.map { $0.cgColor } as CFArray,
                locations: [0.0, 1.0]
            ) {
                let flameSize: CGFloat = 30 + CGFloat(comboCount) * 5
                ctx.drawRadialGradient(flameGradient,
                                       startCenter: CGPoint(x: monkeyX, y: monkeyY + 15),
                                       startRadius: 10,
                                       endCenter: CGPoint(x: monkeyX, y: monkeyY + 15),
                                       endRadius: flameSize, options: [])
            }
        }

        drawVectorMonkey(ctx: ctx, baseX: monkeyX, baseY: monkeyY, scale: 1.0)
    }

    // MARK: - Vector Monkey

    /// Hand-drawn flat monkey with three poses (idle / reach / celebrate),
    /// breathing animation, blinking, and pupils that track the most
    /// dangerous banana. Replaces the system emoji — the single biggest
    /// jump from "toy" to "drawn game".
    private func drawVectorMonkey(ctx: CGContext, baseX cx: CGFloat, baseY base: CGFloat, scale: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: cx, y: base)
        ctx.scaleBy(x: scale, y: scale)

        let fur = NSColor(red: 0.52, green: 0.34, blue: 0.18, alpha: 1.0)
        let furDark = NSColor(red: 0.38, green: 0.24, blue: 0.12, alpha: 1.0)
        let skin = NSColor(red: 0.93, green: 0.78, blue: 0.62, alpha: 1.0)

        // Breathing: subtle vertical squash on idle
        let breath = monkeyPose == .idle ? 1.0 + 0.02 * sin(CGFloat(frameCount) * 0.06) : 1.0

        // Tail: curled quad curve behind the body
        ctx.setStrokeColor(fur.cgColor)
        ctx.setLineWidth(3.5)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 8, y: 6))
        ctx.addQuadCurve(to: CGPoint(x: 22, y: 18 + 2 * sin(CGFloat(frameCount) * 0.08)),
                         control: CGPoint(x: 22, y: 2))
        ctx.strokePath()

        // Legs
        ctx.setFillColor(furDark.cgColor)
        ctx.fillEllipse(in: CGRect(x: -10, y: -1, width: 9, height: 6))
        ctx.fillEllipse(in: CGRect(x: 1, y: -1, width: 9, height: 6))

        // Body
        ctx.setFillColor(fur.cgColor)
        ctx.fillEllipse(in: CGRect(x: -11, y: 2, width: 22, height: 24 * breath))
        // Belly
        ctx.setFillColor(skin.withAlphaComponent(0.85).cgColor)
        ctx.fillEllipse(in: CGRect(x: -6.5, y: 5, width: 13, height: 14 * breath))

        // Arms: pose-dependent
        ctx.setStrokeColor(fur.cgColor)
        ctx.setLineWidth(4.5)
        let shoulderL = CGPoint(x: -8, y: 18)
        let shoulderR = CGPoint(x: 8, y: 18)
        var handL: CGPoint
        var handR: CGPoint
        switch monkeyPose {
        case .idle:
            let sway = 1.5 * sin(CGFloat(frameCount) * 0.05)
            handL = CGPoint(x: -13 + sway, y: 6)
            handR = CGPoint(x: 13 + sway, y: 6)
        case .reach:
            // One arm stretched toward the catch point
            let dx = reachTarget.x - cx
            let reachRight = dx >= 0
            let angle = atan2(max(reachTarget.y - base - 18, 8), dx)
            let stretch: CGFloat = 19
            let reachHand = CGPoint(x: (reachRight ? shoulderR.x : shoulderL.x) + cos(angle) * stretch,
                                    y: (reachRight ? shoulderR.y : shoulderL.y) + sin(angle) * stretch)
            if reachRight {
                handR = reachHand
                handL = CGPoint(x: -13, y: 6)
            } else {
                handL = reachHand
                handR = CGPoint(x: 13, y: 6)
            }
        case .celebrate:
            let wave = 2.0 * sin(CGFloat(frameCount) * 0.25)
            handL = CGPoint(x: -14, y: 32 + wave)
            handR = CGPoint(x: 14, y: 32 - wave)
        }
        for (shoulder, hand) in [(shoulderL, handL), (shoulderR, handR)] {
            ctx.beginPath()
            ctx.move(to: shoulder)
            ctx.addLine(to: hand)
            ctx.strokePath()
        }
        // Paws
        ctx.setFillColor(skin.cgColor)
        ctx.fillEllipse(in: CGRect(x: handL.x - 3, y: handL.y - 3, width: 6, height: 6))
        ctx.fillEllipse(in: CGRect(x: handR.x - 3, y: handR.y - 3, width: 6, height: 6))

        // Head
        let headCenter = CGPoint(x: 0, y: 34)
        // Ears with inner skin
        ctx.setFillColor(fur.cgColor)
        ctx.fillEllipse(in: CGRect(x: -15.5, y: 30, width: 9, height: 9))
        ctx.fillEllipse(in: CGRect(x: 6.5, y: 30, width: 9, height: 9))
        ctx.setFillColor(skin.cgColor)
        ctx.fillEllipse(in: CGRect(x: -13.5, y: 32, width: 5, height: 5))
        ctx.fillEllipse(in: CGRect(x: 8.5, y: 32, width: 5, height: 5))
        // Skull
        ctx.setFillColor(fur.cgColor)
        ctx.fillEllipse(in: CGRect(x: -11, y: headCenter.y - 11, width: 22, height: 22))
        // Face plate
        ctx.setFillColor(skin.cgColor)
        ctx.fillEllipse(in: CGRect(x: -8, y: headCenter.y - 9, width: 16, height: 15))

        // Eyes: pupils track the most urgent banana; periodic blink
        let isBlinking = (frameCount % 190) < 5
        let lowestBanana = bananas.min { $0.position.y < $1.position.y }
        var pupilOffset = CGPoint.zero
        if let target = lowestBanana {
            let dx = target.position.x - cx
            let dy = target.position.y - (base + 34)
            let len = max(sqrt(dx * dx + dy * dy), 1)
            pupilOffset = CGPoint(x: dx / len * 1.3, y: dy / len * 1.0)
        }
        for eyeX in [CGFloat(-4), 4] {
            if isBlinking {
                ctx.setStrokeColor(furDark.cgColor)
                ctx.setLineWidth(1.4)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: eyeX - 2.2, y: headCenter.y + 3))
                ctx.addLine(to: CGPoint(x: eyeX + 2.2, y: headCenter.y + 3))
                ctx.strokePath()
            } else {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: eyeX - 2.6, y: headCenter.y + 0.5, width: 5.2, height: 5.6))
                ctx.setFillColor(NSColor(white: 0.08, alpha: 1.0).cgColor)
                ctx.fillEllipse(in: CGRect(x: eyeX - 1.2 + pupilOffset.x,
                                           y: headCenter.y + 1.8 + pupilOffset.y,
                                           width: 2.6, height: 2.8))
            }
        }

        // Muzzle: nostrils + mouth (smile widens on celebrate)
        ctx.setFillColor(furDark.cgColor)
        ctx.fillEllipse(in: CGRect(x: -2.4, y: headCenter.y - 3.4, width: 1.6, height: 1.8))
        ctx.fillEllipse(in: CGRect(x: 0.8, y: headCenter.y - 3.4, width: 1.6, height: 1.8))
        ctx.setStrokeColor(furDark.cgColor)
        ctx.setLineWidth(1.4)
        ctx.beginPath()
        let smile: CGFloat = monkeyPose == .celebrate ? 4.5 : 2.5
        ctx.move(to: CGPoint(x: -3.5, y: headCenter.y - 5.5))
        ctx.addQuadCurve(to: CGPoint(x: 3.5, y: headCenter.y - 5.5),
                         control: CGPoint(x: 0, y: headCenter.y - 5.5 - smile))
        ctx.strokePath()

        // Hair tuft
        ctx.setStrokeColor(fur.cgColor)
        ctx.setLineWidth(2)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: headCenter.y + 10))
        ctx.addQuadCurve(to: CGPoint(x: 2.5, y: headCenter.y + 14), control: CGPoint(x: -1, y: headCenter.y + 13))
        ctx.strokePath()

        ctx.restoreGState()
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
        let scoreStr = "\(Int(displayedScore.rounded()))" as NSString
        scoreStr.draw(at: NSPoint(x: panelRect.minX + 30, y: panelRect.midY - 10), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .bold),
            .foregroundColor: NSColor.white,
        ])

        // Lives — five vector hearts, centered (or ∞ in Zen mode)
        if isZenMode {
            let zenStr = "∞" as NSString
            let zenAttrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont(size: 18, weight: .bold),
                .foregroundColor: NSColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 0.95),
            ]
            let zs = zenStr.size(withAttributes: zenAttrs)
            zenStr.draw(at: NSPoint(x: w / 2 - zs.width / 2, y: panelRect.midY - zs.height / 2 + 1),
                        withAttributes: zenAttrs)
        } else {
            let heartSpacing: CGFloat = 17
            let firstHeartX = w / 2 - heartSpacing * 2
            for i in 0..<5 {
                drawHeart(ctx: ctx,
                          at: CGPoint(x: firstHeartX + CGFloat(i) * heartSpacing, y: panelRect.midY),
                          size: 11,
                          filled: i < lives)
            }
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

        // Fever build-up pips: 8 segments filling with the combo, so Fever
        // is visibly *earned*, not a random event
        if !isFever {
            let pipW: CGFloat = 9, pipH: CGFloat = 4, pipGap: CGFloat = 3
            let totalW = 8 * pipW + 7 * pipGap
            let startX = w / 2 - totalW / 2
            let pipY = h - 82
            let filled = min(comboCount, 8)
            for i in 0..<8 {
                let rect = CGRect(x: startX + CGFloat(i) * (pipW + pipGap), y: pipY, width: pipW, height: pipH)
                let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
                if i < filled {
                    ctx.setFillColor(NSColor(red: 1.0, green: 0.65, blue: 0.1, alpha: 0.95).cgColor)
                } else {
                    ctx.setFillColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
                }
                ctx.addPath(path)
                ctx.fillPath()
            }
        }

        // Freeze countdown (left, under the panel)
        if freezeFrames > 0 {
            let secs = (freezeFrames + 59) / 60
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
        // Big vector monkey (celebrating)
        let savedPose = monkeyPose
        monkeyPose = .celebrate
        drawVectorMonkey(ctx: ctx, baseX: w / 2, baseY: h / 2 + 68, scale: 1.7)
        monkeyPose = savedPose

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

        // Zen mode hint + current state
        let zenText = isZenMode ? "🧘 \(L.shared.s("g_zen_hint"))  ✓" : "🧘 \(L.shared.s("g_zen_hint"))"
        let zenStr = zenText as NSString
        let zenAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: isZenMode ?
                NSColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 0.95) :
                NSColor(white: 0.55, alpha: 0.8),
        ]
        let zenSize = zenStr.size(withAttributes: zenAttrs)
        zenStr.draw(at: NSPoint(x: w / 2 - zenSize.width / 2, y: h / 2 - 108), withAttributes: zenAttrs)

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
        let cardRect = CGRect(x: w / 2 - 155, y: h / 2 - 148, width: 310, height: 272)
        let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.setFillColor(NSColor(white: 0.07, alpha: 0.72).cgColor)
        ctx.addPath(cardPath)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(cardPath)
        ctx.strokePath()

        // ── Staggered reveal: each element lands 15-20 frames after the
        // previous one, with a tick (fired from gameTick). The end-of-run
        // ritual is where "one more try" is born.
        let gof = gameOverFrame

        // Title (frame 0+)
        let isNewRecord = score >= highScore && score > 0 && !isZenMode
        let goTitle = isNewRecord ? L.shared.s("g_new_record") : L.shared.s("g_game_over")
        let goTitleStr = goTitle as NSString
        let goTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: roundedFont(size: 28, weight: .heavy),
            .foregroundColor: isNewRecord ?
                NSColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1.0) :
                NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0),
        ]
        let goTitleSize = goTitleStr.size(withAttributes: goTitleAttrs)
        goTitleStr.draw(at: NSPoint(x: w / 2 - goTitleSize.width / 2, y: h / 2 + 78), withAttributes: goTitleAttrs)

        // Score counts up from 0 (frame 15+)
        if gof >= 15 {
            let progress = min(1.0, CGFloat(gof - 15) / 30.0)
            let eased = 1.0 - (1.0 - progress) * (1.0 - progress)
            let shownScore = Int((CGFloat(score) * eased).rounded())
            let scoreStr = L.shared.sf("g_score", shownScore) as NSString
            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let scoreSize = scoreStr.size(withAttributes: scoreAttrs)
            scoreStr.draw(at: NSPoint(x: w / 2 - scoreSize.width / 2, y: h / 2 + 42), withAttributes: scoreAttrs)
        }

        // Delta vs previous run (frame 45+) — language-neutral arrows
        if gof >= 45, let delta = lastRunDelta {
            let deltaText: String
            let deltaColor: NSColor
            if delta > 0 {
                deltaText = "▲ +\(delta)"
                deltaColor = NSColor(red: 0.45, green: 0.95, blue: 0.5, alpha: 1.0)
            } else if delta < 0 {
                deltaText = "▼ \(delta)"
                deltaColor = NSColor(red: 1.0, green: 0.5, blue: 0.45, alpha: 1.0)
            } else {
                deltaText = "＝"
                deltaColor = NSColor(white: 0.7, alpha: 1.0)
            }
            let deltaStr = deltaText as NSString
            let deltaAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: deltaColor,
            ]
            let ds = deltaStr.size(withAttributes: deltaAttrs)
            deltaStr.draw(at: NSPoint(x: w / 2 - ds.width / 2, y: h / 2 + 16), withAttributes: deltaAttrs)
        }

        // Level + best (frame 60+)
        if gof >= 60 {
            let lvlStr = L.shared.sf("g_level", level) as NSString
            let lvlAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
            ]
            let lvlSize = lvlStr.size(withAttributes: lvlAttrs)
            lvlStr.draw(at: NSPoint(x: w / 2 - lvlSize.width / 2, y: h / 2 - 10), withAttributes: lvlAttrs)

            let bestStr = L.shared.sf("g_best_score", highScore) as NSString
            let bestAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.9),
            ]
            let bestSize = bestStr.size(withAttributes: bestAttrs)
            bestStr.draw(at: NSPoint(x: w / 2 - bestSize.width / 2, y: h / 2 - 32), withAttributes: bestAttrs)
        }

        // Medal stamp with scale-in (frame 78+)
        if gof >= 78 && earnedMedal != .none {
            let stampProgress = min(1.0, CGFloat(gof - 78) / 6.0)
            let stampScale = 1.7 - 0.7 * stampProgress
            let medalText = earnedMedalIsNew ? "\(earnedMedal.emoji)✨" : earnedMedal.emoji
            let medalStr = medalText as NSString
            let medalAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34 * stampScale)]
            let ms = medalStr.size(withAttributes: medalAttrs)
            medalStr.draw(at: NSPoint(x: w / 2 - ms.width / 2, y: h / 2 - 76 - ms.height / 2 + 17),
                          withAttributes: medalAttrs)
        }

        // Performance message (frame 78+)
        if gof >= 78 {
            let perfMsg: String
            if score >= 50 { perfMsg = L.shared.s("g_genius") }
            else if score >= 30 { perfMsg = L.shared.s("g_fantastic") }
            else if score >= 15 { perfMsg = L.shared.s("g_well_done") }
            else if score >= 5 { perfMsg = L.shared.s("g_good_start") }
            else { perfMsg = L.shared.s("g_dont_give_up") }

            let perfStr = perfMsg as NSString
            let perfAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(white: 0.9, alpha: 0.9),
            ]
            let perfSize = perfStr.size(withAttributes: perfAttrs)
            perfStr.draw(at: NSPoint(x: w / 2 - perfSize.width / 2, y: h / 2 - 104), withAttributes: perfAttrs)
        }

        // Restart hint (frame 95+)
        if gof >= 95 {
            let pulse = 0.5 + 0.5 * sin(CGFloat(gameOverFrame) * 0.06)
            let restartStr = L.shared.s("g_press_restart") as NSString
            let restartAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(white: 1.0, alpha: pulse),
            ]
            let restartSize = restartStr.size(withAttributes: restartAttrs)
            restartStr.draw(at: NSPoint(x: w / 2 - restartSize.width / 2, y: h / 2 - 132), withAttributes: restartAttrs)
        }
    }
}
