// SoundEngine.swift
// MonKeys
//
// Polyphonic audio engine for real-time mechanical keyboard sound playback.

import Foundation
@preconcurrency import AVFoundation

/// Manages an `AVAudioEngine` graph with a round-robin pool of player nodes
/// to deliver low-latency, polyphonic keyboard sounds.
///
/// Thread-safety is guaranteed by an `NSLock` — **do not** mark this class
/// `@MainActor`; CGEvent tap callbacks arrive on arbitrary system threads.
final class SoundEngine: @unchecked Sendable {

    // MARK: - Configuration

    /// Number of `AVAudioPlayerNode`s in the round-robin pool.
    private static let poolSize = 16

    // MARK: - Audio graph

    private let engine: AVAudioEngine
    private let mixer: AVAudioMixerNode
    private let synthesizer: SoundSynthesizer



    // MARK: - Player pool

    /// Fixed-size array of player nodes attached to the engine.
    private var playerNodes: [AVAudioPlayerNode]

    /// Round-robin index into `playerNodes`.
    private var playerIndex: Int = 0

    // MARK: - Active key tracking

    /// The set of keys currently pressed down.
    private var pressedKeys = Set<Int64>()

    /// The number of consecutive delete/backspace key presses.
    private var consecutiveDeletesCount: Int = 0

    /// Velocity-sensitive volume: tracks time between keypresses
    private var lastKeyPressTime: Date = Date()
    private var velocityMultiplier: Float = 1.0

    // MARK: - Adjustable state

    private var profile: SoundProfile
    private var volume: Float
    private var isEnabled: Bool

    // MARK: - Thread safety

    private let lock = NSLock()

    // MARK: - Initialisation

    init() {
        self.engine      = AVAudioEngine()
        self.mixer       = AVAudioMixerNode()
        self.synthesizer = SoundSynthesizer()
        self.profile     = .blue
        self.volume      = 1.0
        self.isEnabled   = true
        self.playerNodes = []

        // Build the audio graph.
        engine.attach(mixer)

        let format = synthesizer.format

        for _ in 0 ..< Self.poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            playerNodes.append(player)
        }

        engine.connect(mixer, to: engine.outputNode, format: engine.outputNode.inputFormat(forBus: 0))
        mixer.outputVolume = volume
    }

    // MARK: - Lifecycle

    /// Starts the audio engine and all player nodes.
    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !engine.isRunning else { return }

        do {
            try engine.start()
        } catch {
            print("SoundEngine: failed to start AVAudioEngine — \(error)")
            return
        }
    }

    /// Stops every player node and the engine itself.
    func stop() {
        lock.lock()
        defer { lock.unlock() }

        for player in playerNodes {
            player.stop()
        }
        pressedKeys.removeAll()
        engine.stop()
    }

    // MARK: - Key events

    /// Plays a click-down sound for `keyCode`, supporting repeat events for delete, enter, and space keys.
    func playKeyDown(keyCode: Int64, isRepeat: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        let variation = Float(keyCode % 50) / 50.0
        let isRepeatKey = (keyCode == 51 || keyCode == 117 || keyCode == 36 || keyCode == 76 || keyCode == 49)
        // Large keys: spacebar(49), return(36), numpad enter(76), left shift(56), right shift(60), tab(48), backspace(51), delete(117)
        let isLargeKey = [49, 36, 76, 56, 60, 48, 51, 117].contains(Int(keyCode))

        // Velocity-sensitive volume
        let now = Date()
        let timeSinceLast = Float(now.timeIntervalSince(lastKeyPressTime))
        lastKeyPressTime = now
        if timeSinceLast < 0.08 {
            velocityMultiplier = min(1.2, velocityMultiplier + 0.05)
        } else if timeSinceLast > 0.5 {
            velocityMultiplier = max(0.8, velocityMultiplier - 0.1)
        } else {
            velocityMultiplier += (1.0 - velocityMultiplier) * 0.3
        }

        if isRepeat {
            // Only process repeat events for Delete, Enter, and Space keys
            if isRepeatKey {
                consecutiveDeletesCount += 1
                if consecutiveDeletesCount >= 3 {
                    consecutiveDeletesCount = 0
                    // Play the normal click down
                    if let clickBuffer = synthesizer.generateClickDown(
                        profile: profile,
                        pitchVariation: variation,
                        isLargeKey: isLargeKey
                    ) {
                        let player = nextPlayer()
                        player.volume = velocityMultiplier
                        player.scheduleBuffer(clickBuffer, at: nil, options: [], completionHandler: nil)
                        player.play()
                    }
                }
            }
            return
        }

        // Ignore duplicate key-down while the key is already held (safety check for first presses)
        if pressedKeys.contains(keyCode) { return }
        pressedKeys.insert(keyCode)

        // Reset repeat counter on a new manual key press (either normal typing or first press)
        consecutiveDeletesCount = 0

        // --- Click-down ---
        if let clickBuffer = synthesizer.generateClickDown(
            profile: profile,
            pitchVariation: variation,
            isLargeKey: isLargeKey
        ) {
            let clickPlayer = nextPlayer()
            clickPlayer.volume = velocityMultiplier
            clickPlayer.scheduleBuffer(clickBuffer, at: nil, options: [], completionHandler: nil)
            clickPlayer.play()
        }
    }

    /// Plays a release click for `keyCode`.
    ///
    /// If `keyCode` is not currently tracked (e.g. the app started while a key
    /// was already pressed) the call is a harmless no-op.
    func playKeyUp(keyCode: Int64) {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        // Remove from pressed keys.
        guard pressedKeys.remove(keyCode) != nil else { return }

        // --- Release click ---
        let variation = Float(keyCode % 50) / 50.0
        let isLargeKey = [49, 36, 76, 56, 60, 48, 51, 117].contains(Int(keyCode))
        if let releaseBuffer = synthesizer.generateRelease(
            profile: profile,
            pitchVariation: variation,
            isLargeKey: isLargeKey
        ) {
            let releasePlayer = nextPlayer()
            releasePlayer.scheduleBuffer(releaseBuffer, at: nil, options: [], completionHandler: nil)
            releasePlayer.play()
        }
    }

    // MARK: - Settings

    /// Sets the master output volume (`0.0 ... 1.0`).
    func setVolume(_ newVolume: Float) {
        lock.lock()
        defer { lock.unlock() }
        volume = max(0.0, min(1.0, newVolume))
        mixer.outputVolume = volume
    }

    /// Switches the active sound profile.
    ///
    /// New sounds will use the updated profile; already-playing buffers
    /// are unaffected.
    func setProfile(_ newProfile: SoundProfile) {
        lock.lock()
        defer { lock.unlock() }
        profile = newProfile
    }

    /// Enables or disables all sound output.
    ///
    /// When disabled, key events are silently discarded.
    func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isEnabled = enabled

        if !enabled {
            pressedKeys.removeAll()
        }
    }

    // MARK: - Private helpers

    /// Returns the next player node from the round-robin pool.
    ///
    /// - Precondition: `lock` must be held by the caller.
    private func nextPlayer() -> AVAudioPlayerNode {
        let player = playerNodes[playerIndex]
        playerIndex = (playerIndex + 1) % Self.poolSize
        return player
    }

    /// Plays the game success chime.
    func playSuccess() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        if let buffer = synthesizer.generateSuccessChime() {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Plays the game fail chime.
    func playFail() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        if let buffer = synthesizer.generateFailChime() {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Plays the combo achievement chime.
    func playCombo(level: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        if let buffer = synthesizer.generateComboChime(comboLevel: level) {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Plays the level-up fanfare.
    func playLevelUp() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        if let buffer = synthesizer.generateLevelUpChime() {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Plays the sparkling golden-banana chime.
    func playGolden() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        if let buffer = synthesizer.generateGoldenChime() {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Plays the melancholic game-over jingle.
    func playGameOver() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        if let buffer = synthesizer.generateGameOverJingle() {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Plays one countdown tick (3… 2… 1…).
    func playCountdownTick() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        if let buffer = synthesizer.generateCountdownTick() {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Plays the bright "GO!" chime at the end of a countdown.
    func playCountdownGo() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, engine.isRunning else { return }

        if let buffer = synthesizer.generateCountdownGo() {
            let player = nextPlayer()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Plays a single sample click of `previewProfile` so the user can audition
    /// a sound profile from the menu without typing.
    func playPreviewClick(_ previewProfile: SoundProfile) {
        lock.lock()
        defer { lock.unlock() }

        guard engine.isRunning else { return }

        if let buffer = synthesizer.generateClickDown(
            profile: previewProfile,
            pitchVariation: 0.5,
            isLargeKey: false
        ) {
            let player = nextPlayer()
            player.volume = 1.0
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    // MARK: - Background Music

    private var backgroundMusicPlayer: AVAudioPlayer?
    private var isMusicEnabled: Bool = true
    private static let musicVolume: Float = 0.15

    /// Enables or disables game background music (independent of key sounds).
    func setMusicEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isMusicEnabled = enabled
        if !enabled {
            backgroundMusicPlayer?.setVolume(0.0, fadeDuration: 0.5)
            let player = backgroundMusicPlayer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                player?.stop()
            }
        }
    }

    /// Starts looping background music with a gentle fade-in.
    func startMusic() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, isMusicEnabled else { return }

        if let player = backgroundMusicPlayer, player.isPlaying {
            return
        }

        if backgroundMusicPlayer == nil {
            guard let url = Bundle.main.url(forResource: "bg_music", withExtension: "mp3") else {
                print("SoundEngine: bg_music.mp3 not found in bundle")
                return
            }
            do {
                backgroundMusicPlayer = try AVAudioPlayer(contentsOf: url)
                backgroundMusicPlayer?.numberOfLoops = -1
                backgroundMusicPlayer?.prepareToPlay()
            } catch {
                print("SoundEngine: failed to load background music - \(error)")
                return
            }
        }

        backgroundMusicPlayer?.volume = 0.0
        backgroundMusicPlayer?.play()
        backgroundMusicPlayer?.setVolume(Self.musicVolume, fadeDuration: 1.2)
    }

    /// Stops the background music with a short fade-out.
    func stopMusic() {
        lock.lock()
        defer { lock.unlock() }

        guard let player = backgroundMusicPlayer, player.isPlaying else { return }
        player.setVolume(0.0, fadeDuration: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak player] in
            player?.stop()
        }
    }

    /// Pauses the music (keeps position) with a quick fade — used for in-game pause.
    func pauseMusic() {
        lock.lock()
        defer { lock.unlock() }

        guard let player = backgroundMusicPlayer, player.isPlaying else { return }
        player.setVolume(0.0, fadeDuration: 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak player] in
            player?.pause()
        }
    }

    /// Resumes paused music with a fade-in.
    func resumeMusic() {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled, isMusicEnabled, let player = backgroundMusicPlayer, !player.isPlaying else { return }
        player.play()
        player.setVolume(Self.musicVolume, fadeDuration: 0.8)
    }
}
