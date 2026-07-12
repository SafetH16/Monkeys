// SoundSynthesizer.swift
// MonKeys
//
// Procedural audio synthesis for mechanical keyboard sounds.

import Foundation
@preconcurrency import AVFoundation

/// Generates PCM audio buffers that simulate mechanical keyboard switch sounds.
///
/// All buffers are mono Float32 at 44 100 Hz, suitable for scheduling on
/// `AVAudioPlayerNode` instances managed by ``SoundEngine``.
final class SoundSynthesizer: @unchecked Sendable {

    // MARK: - Constants

    private static let sampleRate: Double = 44100.0
    private static let twoPi: Float = 2.0 * .pi

    // MARK: - Properties

    /// The canonical audio format used by every buffer this synthesizer creates.
    let format: AVAudioFormat

    private var waxSlimeBuffer: AVAudioPCMBuffer?

    // MARK: - Initialisation

    init() {
        // Fail soft, never crash: 44.1kHz mono Float32 cannot realistically
        // fail, but if it ever does we fall back to 48kHz, then to a bare
        // format object (the app keeps running, just without synthesis).
        if let fmt = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) {
            self.format = fmt
        } else if let fallback = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 1) {
            self.format = fallback
        } else {
            self.format = AVAudioFormat()
        }
        let fmt = self.format

        // Preload wax_slime.wav
        if let url = Bundle.main.url(forResource: "wax_slime", withExtension: "wav") {
            do {
                let file = try AVAudioFile(forReading: url)
                if let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) {
                    try file.read(into: buffer)
                    if buffer.format == fmt {
                        self.waxSlimeBuffer = buffer
                    } else if let converter = AVAudioConverter(from: buffer.format, to: fmt),
                              let newBuffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * (fmt.sampleRate / buffer.format.sampleRate))) {
                        var error: NSError?
                        // Box the one-shot flag so the @Sendable input block can
                        // mutate it without a captured-var concurrency warning.
                        final class OneShotFlag: @unchecked Sendable { var hasData = true }
                        let flag = OneShotFlag()
                        converter.convert(to: newBuffer, error: &error, withInputFrom: { _, outStatus in
                            if flag.hasData {
                                outStatus.pointee = .haveData
                                flag.hasData = false
                                return buffer
                            } else {
                                outStatus.pointee = .endOfStream
                                return nil
                            }
                        })
                        self.waxSlimeBuffer = newBuffer
                    }
                }
            } catch {
                print("SoundSynthesizer: failed to load wax_slime.wav - \(error)")
            }
        }
    }

    // MARK: - Public API

    /// Synthesises a key-down *click* followed by a low-frequency *thud*.
    ///
    /// The sound is built from three layers:
    /// 1. A sharp noise burst in the first ~1–2 ms (attack).
    /// 2. A sine tone at `clickFrequency` with exponential decay.
    /// 3. A lower sine tone at `thudFrequency` with a slower decay.
    ///
    /// - Parameters:
    ///   - profile: The switch profile whose parameters drive the synthesis.
    ///   - pitchVariation: A value in `0.0 ... 1.0` that shifts the click
    ///     frequency by ±15 % so that different keys sound distinct.
    /// - Returns: A filled `AVAudioPCMBuffer`, or `nil` if allocation fails.
    func generateClickDown(profile: SoundProfile, pitchVariation: Float, isLargeKey: Bool = false) -> AVAudioPCMBuffer? {
        if profile == .waxSlime, let buffer = waxSlimeBuffer {
            return buffer
        }
        return generateClickDown(params: profile.parameters,
                                 pitchVariation: pitchVariation,
                                 category: isLargeKey ? .space : .normal)
    }

    /// Parameter-driven click synthesis: three layers (noise attack, click
    /// sine, low thud), with per-category pitch/gain/duration/resonance.
    func generateClickDown(params: SoundParameters, pitchVariation: Float, category: KeyCategory) -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let clickDuration = params.clickDuration * category.durationFactor
        let thudDuration = params.thudDuration * category.durationFactor
        let totalDuration = max(clickDuration, thudDuration) + 0.010
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let samples = buffer.floatChannelData?[0] else { return nil }

        let pitchShift = 1.0 + (pitchVariation - 0.5) * params.variation
        let clickFreq  = params.clickFrequency * pitchShift * category.pitchFactor
        let thudFreq   = params.thudFrequency * pitchShift * 0.5 * category.pitchFactor
        let amplitude  = params.clickAmplitude * category.gainFactor

        let clickDecay: Float = clickDuration * 0.33
        let thudDecay:  Float = thudDuration  * 0.50
        let attackEnd:  Float = 0.002 // 2 ms noise burst

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate

            // --- Layer 1: Initial noise burst (attack) ---
            var sample: Float = 0.0
            if t < attackEnd {
                let attackEnv = (1.0 - t / attackEnd) // linear fade
                let noise = Float.random(in: -1.0 ... 1.0)
                sample += noise * attackEnv * amplitude * params.clickNoiseAmount
            }

            // --- Layer 2: Click sine with exponential decay ---
            let clickEnv = amplitude * expf(-t / clickDecay)
            let clickSine = sinf(Self.twoPi * clickFreq * t)
            let clickNoise = Float.random(in: -1.0 ... 1.0) * params.clickNoiseAmount
            sample += clickEnv * (clickSine * (1.0 - params.clickNoiseAmount) + clickNoise)

            // --- Layer 3: Low-frequency thud ---
            let thudEnv = amplitude * 0.6 * category.resonanceFactor * expf(-t / thudDecay)
            let thudSine = sinf(Self.twoPi * thudFreq * t)
            sample += thudEnv * thudSine

            samples[i] = sample
        }

        return buffer
    }

    /// Synthesises a short, loopable hold/sustain buffer of low-pass filtered noise.
    ///
    /// The last 10 % of the buffer is crossfaded with the first 10 % so that
    /// the buffer can be scheduled with `.loops` without audible clicks.
    ///
    /// - Parameter profile: The switch profile.
    /// - Returns: A seamlessly-loopable `AVAudioPCMBuffer`, or `nil`.
    func generateHold(profile: SoundProfile) -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 0.10 // 100 ms loop
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let samples = buffer.floatChannelData?[0] else { return nil }

        let frequency = profile.thudFrequency
        let amplitude = profile.holdNoiseAmplitude * 0.35 // Clean, soft warm resonance

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            // Synthesize a clean sine wave resonance
            let sineValue = sinf(Self.twoPi * frequency * t)
            samples[i] = sineValue * amplitude
        }

        // Crossfade last 10% with first 10% for seamless looping
        let fadeLength = Int(Float(frameCount) * 0.10)
        if fadeLength > 0 {
            for i in 0 ..< fadeLength {
                let ratio = Float(i) / Float(fadeLength) // 0 → 1
                let tailIndex = Int(frameCount) - fadeLength + i
                let blended = samples[tailIndex] * (1.0 - ratio) + samples[i] * ratio
                samples[tailIndex] = blended
            }
        }

        return buffer
    }

    /// Synthesises a key-up *release* click — structurally similar to the
    /// down-click but shorter and quieter.
    ///
    /// - Parameters:
    ///   - profile: The switch profile.
    ///   - pitchVariation: Per-key pitch shift (`0.0 ... 1.0`).
    /// - Returns: A filled `AVAudioPCMBuffer`, or `nil`.
    func generateRelease(profile: SoundProfile, pitchVariation: Float, isLargeKey: Bool = false) -> AVAudioPCMBuffer? {
        if profile == .waxSlime {
            return nil
        }
        return generateRelease(params: profile.parameters,
                               pitchVariation: pitchVariation,
                               category: isLargeKey ? .space : .normal)
    }

    /// Parameter-driven upstroke click.
    func generateRelease(params: SoundParameters, pitchVariation: Float, category: KeyCategory) -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let releaseDuration = params.releaseDuration * category.durationFactor
        let totalDuration = releaseDuration + 0.005
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let samples = buffer.floatChannelData?[0] else { return nil }

        let pitchShift  = 1.0 + (pitchVariation - 0.5) * params.variation
        let releaseFreq = params.releaseFrequency * pitchShift * category.pitchFactor
        let amplitude   = params.releaseAmplitude * category.gainFactor
        let decayTime   = releaseDuration * 0.33
        let attackEnd: Float = 0.001 // 1 ms noise burst

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate

            var sample: Float = 0.0

            // Brief noise burst
            if t < attackEnd {
                let attackEnv = 1.0 - t / attackEnd
                sample += Float.random(in: -1.0 ... 1.0) * attackEnv * amplitude * 0.3
            }

            // Sine with exponential decay
            let env = amplitude * expf(-t / decayTime)
            sample += env * sinf(Self.twoPi * releaseFreq * t)

            samples[i] = sample
        }

        return buffer
    }

    /// Synthesises a quick, happy two-note major-fifth chime.
    /// `semitoneOffset` shifts the whole chime up: mapping it to the combo
    /// makes progress audible without looking at the HUD.
    func generateSuccessChime(semitoneOffset: Int = 0) -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 0.20
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        let clamped = min(max(semitoneOffset, 0), 14)
        let pitchFactor = powf(2.0, Float(clamped) / 12.0)

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            var freq: Float = 600.0 * pitchFactor
            var amp: Float = 0.25

            if t > 0.08 {
                freq = 900.0 * pitchFactor // Perfect fifth jump
                amp *= expf(-(t - 0.08) / 0.05)
            } else {
                amp *= expf(-t / 0.05)
            }

            samples[i] = sinf(Self.twoPi * freq * t) * amp
        }
        return buffer
    }

    /// Synthesises a celebratory ascending arpeggio for combo achievements.
    func generateComboChime(comboLevel: Int) -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let noteCount = min(comboLevel, 5)
        let noteDuration: Float = 0.06
        let totalDuration = noteDuration * Float(noteCount) + 0.10
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        // Major pentatonic ascending: C5, D5, E5, G5, A5
        let frequencies: [Float] = [523.25, 587.33, 659.25, 783.99, 880.0]

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            var sample: Float = 0.0

            for n in 0 ..< noteCount {
                let noteStart = Float(n) * noteDuration
                let noteT = t - noteStart
                if noteT >= 0 {
                    let env = 0.20 * expf(-noteT / 0.08)
                    sample += sinf(Self.twoPi * frequencies[n] * t) * env
                }
            }

            samples[i] = sample
        }
        return buffer
    }

    /// Synthesises a level-up fanfare — a bright major chord swell.
    func generateLevelUpChime() -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 0.40
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        // C major chord: C4, E4, G4, C5
        let freqs: [Float] = [261.63, 329.63, 392.0, 523.25]

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            // Swell envelope: quick attack, sustained, then decay
            let attack = min(t / 0.03, 1.0)
            let decay = expf(-max(0, t - 0.15) / 0.10)
            let env: Float = 0.15 * attack * decay

            var sample: Float = 0.0
            for freq in freqs {
                sample += sinf(Self.twoPi * freq * t) * env
            }
            samples[i] = sample
        }
        return buffer
    }

    /// Synthesises a sparkling ascending glissando for golden banana catches.
    func generateGoldenChime() -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 0.55
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        // Fast harp-like gliss: C6 E6 G6 C7 with shimmering overtones
        let notes: [Float] = [1046.50, 1318.51, 1567.98, 2093.00]
        let noteSpacing: Float = 0.07

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            var sample: Float = 0.0
            for (n, freq) in notes.enumerated() {
                let noteT = t - Float(n) * noteSpacing
                if noteT >= 0 {
                    let env = 0.16 * expf(-noteT / 0.12)
                    // Bell timbre: fundamental + soft 3rd harmonic with slow tremolo
                    let tremolo = 1.0 + 0.15 * sinf(Self.twoPi * 9.0 * noteT)
                    sample += (sinf(Self.twoPi * freq * noteT)
                               + 0.25 * sinf(Self.twoPi * freq * 3.0 * noteT)) * env * tremolo
                }
            }
            samples[i] = sample
        }
        return buffer
    }

    /// Synthesises a short melancholic descending jingle for game over.
    func generateGameOverJingle() -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 1.1
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        // Descending minor line: E5 → C5 → A4 → E4, last note held
        let melody: [(freq: Float, start: Float, dur: Float)] = [
            (659.25, 0.00, 0.18),
            (523.25, 0.20, 0.18),
            (440.00, 0.40, 0.18),
            (329.63, 0.60, 0.50),
        ]

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            var sample: Float = 0.0
            for note in melody {
                let noteT = t - note.start
                if noteT >= 0 && noteT < note.dur + 0.15 {
                    let attack = min(noteT / 0.015, 1.0)
                    let env = 0.20 * attack * expf(-noteT / (note.dur * 0.6))
                    // Warm timbre: fundamental + octave-down shadow
                    sample += (sinf(Self.twoPi * note.freq * noteT)
                               + 0.3 * sinf(Self.twoPi * note.freq * 0.5 * noteT)) * env
                }
            }
            samples[i] = sample
        }
        return buffer
    }

    /// Synthesises a short percussive tick for pre-game countdowns.
    func generateCountdownTick() -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 0.12
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            let env = 0.28 * expf(-t / 0.025)
            // Wood-block: mid sine + tight noise transient
            var sample = sinf(Self.twoPi * 880.0 * t) * env
            if t < 0.004 {
                sample += Float.random(in: -1.0 ... 1.0) * 0.15 * (1.0 - t / 0.004)
            }
            samples[i] = sample
        }
        return buffer
    }

    /// Synthesises a bright rising "GO!" chime that ends a countdown.
    func generateCountdownGo() -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 0.35
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            let attack = min(t / 0.01, 1.0)
            let env = 0.22 * attack * expf(-t / 0.15)
            // Octave power chord: A5 + A6 with a quick upward sweep
            let sweep = 1.0 + 0.06 * min(t / 0.05, 1.0)
            samples[i] = (sinf(Self.twoPi * 880.0 * sweep * t)
                          + 0.5 * sinf(Self.twoPi * 1760.0 * sweep * t)) * env
        }
        return buffer
    }

    /// Synthesises a quick, descending pitch slide for missed keystrokes or errors.
    func generateFailChime() -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 0.25
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            
            // Descending frequency sweep
            let freq = max(100.0, 300.0 - t * 800.0)
            let amp = 0.30 * expf(-t / 0.08)
            
            samples[i] = sinf(Self.twoPi * freq * t) * amp
        }
        return buffer
    }

    /// Generates a loopable upbeat background music buffer for the game.
    /// Bright synth-pop groove: warm pads + bouncy bass + crisp drums, ~14 seconds.
    func generateBackgroundMusic() -> AVAudioPCMBuffer? {
        let sr = Float(Self.sampleRate)
        let bpm: Float = 110.0  // Upbeat, energetic
        let beat = 60.0 / bpm
        let swing: Float = 0.10 // Light shuffle

        // ─── CHORDS: Bright synth pad (major voicings, high register) ───
        // Progression: C → F → Am → G (pop/bright, mostly major feel)
        // Repeated twice = 8 bars = 32 beats
        struct Chord {
            let freqs: [Float]
            let beats: Float
        }
        let chords: [Chord] = [
            // Section A
            Chord(freqs: [523.25, 659.25, 783.99], beats: 4),  // C5 E5 G5 (C major)
            Chord(freqs: [349.23, 523.25, 698.46], beats: 4),  // F4 C5 F5 (F major)
            Chord(freqs: [440.00, 523.25, 659.25], beats: 4),  // A4 C5 E5 (Am → but bright voicing)
            Chord(freqs: [392.00, 493.88, 587.33], beats: 4),  // G4 B4 D5 (G major)
            // Section B (variation)
            Chord(freqs: [523.25, 659.25, 783.99], beats: 4),  // C major
            Chord(freqs: [349.23, 440.00, 523.25], beats: 4),  // F major (diff voicing)
            Chord(freqs: [493.88, 587.33, 783.99], beats: 4),  // G/B (bright sus feel)
            Chord(freqs: [523.25, 659.25, 783.99], beats: 4),  // C major (resolve)
        ]

        // ─── BASS: Clean, bouncy mid-range ───
        let bassNotes: [(freq: Float, beats: Float)] = [
            // Section A
            (130.81, 1.5), (130.81, 0.5), (196.00, 1.0), (130.81, 1.0), // C
            (174.61, 1.5), (174.61, 0.5), (130.81, 1.0), (174.61, 1.0), // F
            (110.00, 1.5), (110.00, 0.5), (130.81, 1.0), (164.81, 1.0), // A
            (98.00,  1.5), (98.00,  0.5), (130.81, 1.0), (98.00,  1.0), // G
            // Section B
            (130.81, 1.5), (130.81, 0.5), (164.81, 1.0), (196.00, 1.0), // C
            (174.61, 1.5), (174.61, 0.5), (130.81, 1.0), (174.61, 1.0), // F
            (98.00,  1.5), (98.00,  0.5), (123.47, 1.0), (98.00,  1.0), // G
            (130.81, 2.0), (130.81, 1.0), (196.00, 1.0),                 // C (resolve)
        ]

        // ─── DRUMS: Clean, modern kit ───
        let drumBar: [(beat: Float, type: Int, vel: Float)] = [
            (0.00, 0, 0.9),                    // Kick on 1
            (0.50, 2, 0.5),                    // Hi-hat
            (1.00, 1, 0.8),                    // Clap on 2
            (1.00, 2, 0.4),                    // Hat
            (1.50, 2, 0.5),                    // Hat
            (2.00, 0, 0.7),                    // Kick on 3
            (2.50, 2, 0.5),                    // Hat
            (2.75, 0, 0.4),                    // Ghost kick
            (3.00, 1, 0.85),                   // Clap on 4
            (3.00, 2, 0.4),                    // Hat
            (3.50, 2, 0.45),                   // Hat
        ]

        var totalBeats: Float = 0
        for c in chords { totalBeats += c.beats }
        let totalDur = totalBeats * beat
        let frameCount = AVAudioFrameCount(totalDur * sr)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        for i in 0..<Int(frameCount) { samples[i] = 0 }

        // ════════════════════════════════════════════
        // RENDER CHORDS (bright, warm synth pad)
        // ════════════════════════════════════════════
        var chordTime: Float = 0
        for chord in chords {
            let chordDur = chord.beats * beat
            let startSmp = Int(chordTime * sr)
            let endSmp = min(Int((chordTime + chordDur) * sr), Int(frameCount))

            for i in startSmp..<endSmp {
                let t = Float(i - startSmp) / sr
                // Smooth envelope: soft attack, sustained, gentle release
                let attack = min(t / 0.08, 1.0)
                let release = t > (chordDur - 0.15) ? max(0, (chordDur - t) / 0.15) : 1.0
                let env: Float = 0.04 * attack * release

                var sample: Float = 0
                for (vi, freq) in chord.freqs.enumerated() {
                    // Slight detune for warmth (chorus effect)
                    let detune: Float = 1.0 + Float(vi) * 0.0012
                    let f = freq * detune
                    // Gentle vibrato
                    let vib = 1.0 + 0.0015 * sinf(Self.twoPi * 5.0 * t + Float(vi) * 1.5)
                    let fv = f * vib

                    // Bright pad: sine + soft square-ish harmonic
                    let sine = sinf(Self.twoPi * fv * t)
                    let h2 = sinf(Self.twoPi * fv * 2.0 * t) * 0.15
                    let h3 = sinf(Self.twoPi * fv * 3.0 * t) * 0.05
                    sample += (sine + h2 + h3)
                }
                samples[i] += sample * env
            }
            chordTime += chordDur
        }

        // ════════════════════════════════════════════
        // RENDER BASS (clean, bouncy)
        // ════════════════════════════════════════════
        var bassTime: Float = 0
        var prevBassFreq: Float = 130.81
        for bassNote in bassNotes {
            let noteDur = bassNote.beats * beat
            let humanize = Float.random(in: -0.006...0.006)
            let noteStart = max(0, bassTime + humanize)
            let startSmp = Int(noteStart * sr)
            let endSmp = min(Int((noteStart + noteDur) * sr), Int(frameCount))

            for i in startSmp..<endSmp {
                let t = Float(i - startSmp) / sr
                // Quick portamento glide (30ms)
                let glide = min(t / 0.03, 1.0)
                let smooth = glide * glide * (3.0 - 2.0 * glide)
                let freq = prevBassFreq + (bassNote.freq - prevBassFreq) * smooth

                // Punchy envelope: fast attack, sustained
                let attack = min(t / 0.008, 1.0)
                let sustain = 0.7 + 0.3 * expf(-t / (noteDur * 0.5))
                let release = t > (noteDur - 0.02) ? max(0, (noteDur - t) / 0.02) : 1.0
                let env: Float = 0.08 * attack * sustain * release

                // Clean bass: fundamental + subtle octave
                let sine = sinf(Self.twoPi * freq * t)
                let octave = sinf(Self.twoPi * freq * 2.0 * t) * 0.12
                samples[i] += (sine + octave) * env
            }
            prevBassFreq = bassNote.freq
            bassTime += noteDur
        }

        // ════════════════════════════════════════════
        // RENDER DRUMS (crisp, modern)
        // ════════════════════════════════════════════
        for bar in 0..<8 {
            let barOffset = Float(bar) * 4.0 * beat
            for hit in drumBar {
                let isOffBeat = hit.beat.truncatingRemainder(dividingBy: 1.0) > 0.4
                let swingDelay = isOffBeat ? beat * swing : 0.0
                let humanize = Float.random(in: -0.004...0.004)
                let hitTime = barOffset + hit.beat * beat + swingDelay + humanize
                let startSmp = Int(max(0, hitTime) * sr)
                let vel = hit.vel * Float.random(in: 0.85...1.0)

                switch hit.type {
                case 0: // Kick: punchy, clean
                    let dur: Float = 0.10
                    let endSmp = min(startSmp + Int(dur * sr), Int(frameCount))
                    for i in startSmp..<endSmp {
                        let t = Float(i - startSmp) / sr
                        let env = vel * 0.14 * expf(-t / 0.035)
                        // Clean pitch drop: 160Hz → 55Hz
                        let freq = 55.0 + 105.0 * expf(-t / 0.015)
                        samples[i] += sinf(Self.twoPi * freq * t) * env
                    }

                case 1: // Clap: bright, snappy
                    let dur: Float = 0.08
                    let endSmp = min(startSmp + Int(dur * sr), Int(frameCount))
                    for i in startSmp..<endSmp {
                        let t = Float(i - startSmp) / sr
                        let env = vel * 0.06 * expf(-t / 0.025)
                        // Noise burst (bright)
                        let noise = Float.random(in: -1.0...1.0)
                        // Body tone
                        let body = sinf(Self.twoPi * 220.0 * t) * 0.3
                        samples[i] += (noise * 0.7 + body) * env
                    }

                default: // Hi-hat: crisp, bright
                    let dur: Float = 0.035
                    let endSmp = min(startSmp + Int(dur * sr), Int(frameCount))
                    for i in startSmp..<endSmp {
                        let t = Float(i - startSmp) / sr
                        let env = vel * 0.035 * expf(-t / 0.010)
                        let noise = Float.random(in: -1.0...1.0)
                        // Bright metallic shimmer
                        let metal = sinf(Self.twoPi * 8400.0 * t) * 0.2 +
                                    sinf(Self.twoPi * 12000.0 * t) * 0.1
                        samples[i] += (noise * 0.6 + metal) * env
                    }
                }
            }
        }

        // ════════════════════════════════════════════
        // MASTER: Gentle soft-clip (no dark low-pass!)
        // ════════════════════════════════════════════
        for i in 0..<Int(frameCount) {
            samples[i] = tanh(samples[i] * 2.0) * 0.5
        }

        // ─── Crossfade for seamless looping ───
        let fadeLen = Int(Float(frameCount) * 0.05)
        if fadeLen > 0 {
            for i in 0..<fadeLen {
                let ratio = Float(i) / Float(fadeLen)
                let tail = Int(frameCount) - fadeLen + i
                if tail < Int(frameCount) {
                    samples[tail] = samples[tail] * (1.0 - ratio) + samples[i] * ratio
                }
            }
        }

        return buffer
    }
}
