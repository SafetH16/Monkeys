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

    // MARK: - Initialisation

    init() {
        guard let fmt = AVAudioFormat(
            standardFormatWithSampleRate: Self.sampleRate,
            channels: 1
        ) else {
            fatalError("SoundSynthesizer: unable to create mono Float32 format at \(Self.sampleRate) Hz")
        }
        self.format = fmt
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
        let sampleRate = Float(Self.sampleRate)
        // Use the longer of click / thud durations, plus a small tail.
        let totalDuration = max(profile.clickDuration, profile.thudDuration) + 0.010
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let samples = buffer.floatChannelData?[0] else { return nil }

        let pitchShift = 1.0 + (pitchVariation - 0.5) * 0.30 // ±15 %
        let largeKeyFactor: Float = isLargeKey ? 0.6 : 1.0  // Lower pitch for large keys
        let largeKeyResonance: Float = isLargeKey ? 1.4 : 1.0  // More resonance
        let clickFreq  = profile.clickFrequency * pitchShift * largeKeyFactor
        let thudFreq   = profile.thudFrequency * pitchShift * 0.5 * largeKeyFactor

        let clickDecay: Float = profile.clickDuration * 0.33
        let thudDecay:  Float = profile.thudDuration  * 0.50
        let attackEnd:  Float = 0.002 // 2 ms noise burst

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate

            // --- Layer 1: Initial noise burst (attack) ---
            var sample: Float = 0.0
            if t < attackEnd {
                let attackEnv = (1.0 - t / attackEnd) // linear fade
                let noise = Float.random(in: -1.0 ... 1.0)
                sample += noise * attackEnv * profile.clickAmplitude * profile.clickNoiseAmount
            }

            // --- Layer 2: Click sine with exponential decay ---
            let clickEnv = profile.clickAmplitude * expf(-t / clickDecay)
            let clickSine = sinf(Self.twoPi * clickFreq * t)
            let clickNoise = Float.random(in: -1.0 ... 1.0) * profile.clickNoiseAmount
            sample += clickEnv * (clickSine * (1.0 - profile.clickNoiseAmount) + clickNoise)

            // --- Layer 3: Low-frequency thud ---
            let thudEnv = profile.clickAmplitude * 0.6 * largeKeyResonance * expf(-t / thudDecay)
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
        let sampleRate = Float(Self.sampleRate)
        let totalDuration = profile.releaseDuration + 0.005
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let samples = buffer.floatChannelData?[0] else { return nil }

        let pitchShift  = 1.0 + (pitchVariation - 0.5) * 0.30
        let largeKeyFactor: Float = isLargeKey ? 0.65 : 1.0
        let releaseFreq = profile.releaseFrequency * pitchShift * largeKeyFactor
        let decayTime   = profile.releaseDuration * 0.33
        let attackEnd: Float = 0.001 // 1 ms noise burst

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate

            var sample: Float = 0.0

            // Brief noise burst
            if t < attackEnd {
                let attackEnv = 1.0 - t / attackEnd
                sample += Float.random(in: -1.0 ... 1.0) * attackEnv * profile.releaseAmplitude * 0.3
            }

            // Sine with exponential decay
            let env = profile.releaseAmplitude * expf(-t / decayTime)
            sample += env * sinf(Self.twoPi * releaseFreq * t)

            samples[i] = sample
        }

        return buffer
    }

    /// Synthesises a quick, happy two-note major-fifth chime for successful typing hits.
    func generateSuccessChime() -> AVAudioPCMBuffer? {
        let sampleRate = Float(Self.sampleRate)
        let duration: Float = 0.20
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        for i in 0 ..< Int(frameCount) {
            let t = Float(i) / sampleRate
            var freq: Float = 600.0
            var amp: Float = 0.25
            
            if t > 0.08 {
                freq = 900.0 // Perfect fifth jump
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
