// KeySoundProfile.swift
// Monkeys
//
// Mechanical keyboard sound profiles for Cherry MX switch types
// plus fun/ASMR sound packs.

import Foundation

/// Defines the acoustic parameters for synthesizing mechanical keyboard sounds.
///
/// Each profile models a real Cherry MX switch type or a fun alternative:
/// - **Blue**: Loud, clicky switch with a prominent click mechanism and audible tactile bump.
/// - **Brown**: Moderate tactile switch with a softer click and lighter bottom-out.
/// - **Red**: Linear switch with no click mechanism — sound comes mainly from the bottom-out thud.
/// - **Typewriter**: Vintage metallic clack with bell on Enter.
/// - **Bubbles**: Soft, ASMR-style bubbly pop sounds.
/// - **Retro 8-Bit**: Bright chiptune arcade sounds.
enum SoundProfile: String, CaseIterable, Sendable {
    case blue        = "Cherry MX Blue"
    case brown       = "Cherry MX Brown"
    case red         = "Cherry MX Red"
    case black       = "Cherry MX Black"
    case silentRed   = "Cherry MX Silent Red"
    case speedSilver = "Cherry MX Speed Silver"
    case gateronRed  = "Gateron Red"
    case gateronYellow = "Gateron Yellow"
    case silentBlack = "Cherry MX Silent Black"
    case typewriter  = "Macchina da Scrivere"
    case bubbles     = "Bolle ASMR"
    case retro8bit   = "Retro 8-Bit"
    case monkey      = "Scimmia 🐒"
    case waxSlime    = "Wax Slime ASMR"
    case deepThock   = "Deep Thock"
    case silentOffice = "Silent Office"
    case terminal    = "Terminal"
    case softMac     = "Soft Mac-like"

    // MARK: - Click-down parameters

    /// Primary click tone frequency in Hz.
    var clickFrequency: Float {
        switch self {
        case .blue:        return 3500.0
        case .brown:       return 2500.0
        case .red:         return 1500.0
        case .black:       return 1200.0
        case .silentRed:   return 1000.0
        case .speedSilver: return 1600.0
        case .gateronRed:  return 1450.0
        case .gateronYellow: return 1300.0
        case .silentBlack: return 950.0
        case .typewriter:  return 800.0
        case .bubbles:     return 400.0
        case .retro8bit:   return 2000.0
        case .monkey:      return 1800.0  // chirpy primate screech
        case .waxSlime:    return 2000.0  // less high-pitched, more mid-range crunch
        case .deepThock:   return 900.0
        case .silentOffice: return 1050.0
        case .terminal:    return 2400.0
        case .softMac:     return 1500.0
        }
    }

    /// Proportion of broadband noise mixed into the click (0–1).
    var clickNoiseAmount: Float {
        switch self {
        case .blue:        return 0.55
        case .brown:       return 0.40
        case .red:         return 0.25
        case .black:       return 0.20
        case .silentRed:   return 0.08
        case .speedSilver: return 0.22
        case .gateronRed:  return 0.18
        case .gateronYellow: return 0.15
        case .silentBlack: return 0.07
        case .typewriter:  return 0.70
        case .bubbles:     return 0.05
        case .retro8bit:   return 0.10
        case .monkey:      return 0.60  // lots of breathy noise
        case .waxSlime:    return 0.45  // more noise for crunchiness
        case .deepThock:   return 0.30
        case .silentOffice: return 0.10
        case .terminal:    return 0.62
        case .softMac:     return 0.28
        }
    }

    /// Duration of the click transient in seconds.
    var clickDuration: Float {
        switch self {
        case .blue:        return 0.015
        case .brown:       return 0.010
        case .red:         return 0.007
        case .black:       return 0.008
        case .silentRed:   return 0.004
        case .speedSilver: return 0.006
        case .gateronRed:  return 0.007
        case .gateronYellow: return 0.009
        case .silentBlack: return 0.005
        case .typewriter:  return 0.020
        case .bubbles:     return 0.025
        case .retro8bit:   return 0.008
        case .monkey:      return 0.018  // longer chirp
        case .waxSlime:    return 0.015  // longer tap for crunchy texture
        case .deepThock:   return 0.012
        case .silentOffice: return 0.004
        case .terminal:    return 0.010
        case .softMac:     return 0.006
        }
    }

    /// Peak amplitude of the click (0–1).
    var clickAmplitude: Float {
        switch self {
        case .blue:        return 0.70
        case .brown:       return 0.40
        case .red:         return 0.15
        case .black:       return 0.22
        case .silentRed:   return 0.05
        case .speedSilver: return 0.16
        case .gateronRed:  return 0.14
        case .gateronYellow: return 0.18
        case .silentBlack: return 0.06
        case .typewriter:  return 0.60
        case .bubbles:     return 0.20
        case .retro8bit:   return 0.45
        case .monkey:      return 0.55  // loud chirp
        case .waxSlime:    return 0.25  // softer, more relaxing
        case .deepThock:   return 0.50
        case .silentOffice: return 0.055
        case .terminal:    return 0.48
        case .softMac:     return 0.20
        }
    }

    // MARK: - Bottom-out thud

    /// Low-frequency thud tone in Hz.
    var thudFrequency: Float {
        switch self {
        case .blue:        return 250.0
        case .brown:       return 200.0
        case .red:         return 180.0
        case .black:       return 140.0
        case .silentRed:   return 110.0
        case .speedSilver: return 190.0
        case .gateronRed:  return 170.0
        case .gateronYellow: return 150.0
        case .silentBlack: return 100.0
        case .typewriter:  return 120.0
        case .bubbles:     return 60.0
        case .retro8bit:   return 300.0
        case .monkey:      return 220.0  // chest thump
        case .waxSlime:    return 90.0  // deeper, softer thud
        case .deepThock:   return 85.0
        case .silentOffice: return 105.0
        case .terminal:    return 260.0
        case .softMac:     return 190.0
        }
    }

    /// Duration of the thud component in seconds.
    var thudDuration: Float {
        switch self {
        case .blue:        return 0.030
        case .brown:       return 0.025
        case .red:         return 0.035
        case .black:       return 0.040
        case .silentRed:   return 0.018
        case .speedSilver: return 0.030
        case .gateronRed:  return 0.038
        case .gateronYellow: return 0.045
        case .silentBlack: return 0.020
        case .typewriter:  return 0.050
        case .bubbles:     return 0.060
        case .retro8bit:   return 0.015
        case .monkey:      return 0.035  // resonant
        case .waxSlime:    return 0.070  // longer relaxing squish
        case .deepThock:   return 0.080
        case .silentOffice: return 0.016
        case .terminal:    return 0.020
        case .softMac:     return 0.028
        }
    }

    // MARK: - Hold / sustain resonance

    /// Amplitude of the low-level noise while a key is held (0.01–0.05).
    var holdNoiseAmplitude: Float {
        switch self {
        case .blue:        return 0.03
        case .brown:       return 0.02
        case .red:         return 0.01
        case .black:       return 0.01
        case .silentRed:   return 0.005
        case .speedSilver: return 0.01
        case .gateronRed:  return 0.01
        case .gateronYellow: return 0.01
        case .silentBlack: return 0.005
        case .typewriter:  return 0.04
        case .bubbles:     return 0.005
        case .retro8bit:   return 0.02
        case .monkey:      return 0.03
        case .waxSlime:    return 0.020
        case .deepThock:   return 0.020
        case .silentOffice: return 0.005
        case .terminal:    return 0.020
        case .softMac:     return 0.010
        }
    }

    /// Low-pass filter cutoff frequency for the hold noise in Hz.
    var holdFilterFrequency: Float {
        switch self {
        case .blue:        return 800.0
        case .brown:       return 600.0
        case .red:         return 400.0
        case .black:       return 300.0
        case .silentRed:   return 200.0
        case .speedSilver: return 450.0
        case .gateronRed:  return 380.0
        case .gateronYellow: return 320.0
        case .silentBlack: return 180.0
        case .typewriter:  return 1200.0
        case .bubbles:     return 150.0
        case .retro8bit:   return 900.0
        case .monkey:      return 700.0
        case .waxSlime:    return 300.0
        case .deepThock:   return 250.0
        case .silentOffice: return 180.0
        case .terminal:    return 900.0
        case .softMac:     return 400.0
        }
    }

    // MARK: - Release click

    /// Tone frequency of the upstroke click in Hz.
    var releaseFrequency: Float {
        switch self {
        case .blue:        return 4000.0
        case .brown:       return 3000.0
        case .red:         return 2000.0
        case .black:       return 1700.0
        case .silentRed:   return 1100.0
        case .speedSilver: return 2200.0
        case .gateronRed:  return 1900.0
        case .gateronYellow: return 1800.0
        case .silentBlack: return 1050.0
        case .typewriter:  return 1200.0
        case .bubbles:     return 500.0
        case .retro8bit:   return 2500.0
        case .monkey:      return 2200.0  // chirpy upstroke
        case .waxSlime:    return 800.0  // lower pitch release
        case .deepThock:   return 700.0
        case .silentOffice: return 1000.0
        case .terminal:    return 2600.0
        case .softMac:     return 1600.0
        }
    }

    /// Duration of the release click in seconds.
    var releaseDuration: Float {
        switch self {
        case .blue:        return 0.010
        case .brown:       return 0.008
        case .red:         return 0.005
        case .black:       return 0.006
        case .silentRed:   return 0.003
        case .speedSilver: return 0.004
        case .gateronRed:  return 0.005
        case .gateronYellow: return 0.006
        case .silentBlack: return 0.004
        case .typewriter:  return 0.015
        case .bubbles:     return 0.020
        case .retro8bit:   return 0.006
        case .monkey:      return 0.012
        case .waxSlime:    return 0.020  // longer, relaxing release
        case .deepThock:   return 0.008
        case .silentOffice: return 0.003
        case .terminal:    return 0.006
        case .softMac:     return 0.004
        }
    }

    /// Peak amplitude of the release click (0–1). Always softer than the down-click.
    var releaseAmplitude: Float {
        switch self {
        case .blue:        return 0.40
        case .brown:       return 0.25
        case .red:         return 0.10
        case .black:       return 0.14
        case .silentRed:   return 0.03
        case .speedSilver: return 0.11
        case .gateronRed:  return 0.09
        case .gateronYellow: return 0.12
        case .silentBlack: return 0.04
        case .typewriter:  return 0.35
        case .bubbles:     return 0.08
        case .retro8bit:   return 0.30
        case .monkey:      return 0.35
        case .waxSlime:    return 0.15  // softer release
        case .deepThock:   return 0.12
        case .silentOffice: return 0.03
        case .terminal:    return 0.22
        case .softMac:     return 0.09
        }
    }
}

// MARK: - SoundParameters

/// Plain value type holding every synthesis parameter. Built-in profiles are
/// bridged through `SoundProfile.parameters`; user presets are stored as JSON
/// of this struct. Keep it `Codable` and flat for safe import/export.
struct SoundParameters: Codable, Equatable, Sendable {
    var clickFrequency: Float
    var clickNoiseAmount: Float
    var clickDuration: Float
    var clickAmplitude: Float
    var thudFrequency: Float
    var thudDuration: Float
    var holdNoiseAmplitude: Float
    var releaseFrequency: Float
    var releaseDuration: Float
    var releaseAmplitude: Float
    /// Per-key pitch spread (0 = every key identical, 0.30 = ±15 %).
    var variation: Float

    /// Clamps every field to a safe, audible, non-degenerate range.
    /// Always applied to imported JSON so malformed values cannot produce
    /// silence, clipping or huge buffers.
    mutating func clampToSafeRanges() {
        clickFrequency    = min(max(clickFrequency, 100.0), 8000.0)
        clickNoiseAmount  = min(max(clickNoiseAmount, 0.0), 1.0)
        clickDuration     = min(max(clickDuration, 0.002), 0.20)
        clickAmplitude    = min(max(clickAmplitude, 0.0), 1.0)
        thudFrequency     = min(max(thudFrequency, 40.0), 2000.0)
        thudDuration      = min(max(thudDuration, 0.005), 0.30)
        holdNoiseAmplitude = min(max(holdNoiseAmplitude, 0.0), 0.10)
        releaseFrequency  = min(max(releaseFrequency, 100.0), 8000.0)
        releaseDuration   = min(max(releaseDuration, 0.002), 0.20)
        releaseAmplitude  = min(max(releaseAmplitude, 0.0), 1.0)
        variation         = min(max(variation, 0.0), 0.60)
    }
}

extension SoundProfile {
    /// Snapshot of this built-in profile as a mutable parameter set.
    var parameters: SoundParameters {
        SoundParameters(
            clickFrequency: clickFrequency,
            clickNoiseAmount: clickNoiseAmount,
            clickDuration: clickDuration,
            clickAmplitude: clickAmplitude,
            thudFrequency: thudFrequency,
            thudDuration: thudDuration,
            holdNoiseAmplitude: holdNoiseAmplitude,
            releaseFrequency: releaseFrequency,
            releaseDuration: releaseDuration,
            releaseAmplitude: releaseAmplitude,
            variation: 0.30
        )
    }
}

// MARK: - KeyCategory

/// Classifies physical keys so each family gets a subtly different acoustic
/// character (a spacebar thocks deeper than an arrow key). Kept as static
/// data — categorization must stay allocation-free for the event-tap path.
enum KeyCategory: Sendable {
    case normal, space, returnEnter, deleteKey, modifier, navigation, function, numpad

    private static let spaceCodes: Set<Int64> = [49]
    private static let returnCodes: Set<Int64> = [36, 76]
    private static let deleteCodes: Set<Int64> = [51, 117]
    private static let modifierCodes: Set<Int64> = [48, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    private static let navigationCodes: Set<Int64> = [115, 116, 119, 121, 123, 124, 125, 126]
    private static let functionCodes: Set<Int64> = [53, 96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113, 118, 120, 122]
    private static let numpadCodes: Set<Int64> = [65, 67, 69, 71, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    static func of(_ keyCode: Int64) -> KeyCategory {
        if spaceCodes.contains(keyCode) { return .space }
        if returnCodes.contains(keyCode) { return .returnEnter }
        if deleteCodes.contains(keyCode) { return .deleteKey }
        if modifierCodes.contains(keyCode) { return .modifier }
        if navigationCodes.contains(keyCode) { return .navigation }
        if functionCodes.contains(keyCode) { return .function }
        if numpadCodes.contains(keyCode) { return .numpad }
        return .normal
    }

    /// Multiplier on click/thud pitch (large keys ring lower).
    var pitchFactor: Float {
        switch self {
        case .normal:      return 1.0
        case .space:       return 0.58
        case .returnEnter: return 0.62
        case .deleteKey:   return 0.66
        case .modifier:    return 0.72
        case .navigation:  return 0.88
        case .function:    return 0.85
        case .numpad:      return 1.04
        }
    }

    /// Multiplier on click amplitude.
    var gainFactor: Float {
        switch self {
        case .normal:      return 1.0
        case .space:       return 1.10
        case .returnEnter: return 1.10
        case .deleteKey:   return 1.0
        case .modifier:    return 0.92
        case .navigation:  return 0.88
        case .function:    return 0.85
        case .numpad:      return 0.95
        }
    }

    /// Multiplier on click/thud durations.
    var durationFactor: Float {
        switch self {
        case .normal:      return 1.0
        case .space:       return 1.20
        case .returnEnter: return 1.10
        case .deleteKey:   return 1.0
        case .modifier:    return 1.0
        case .navigation:  return 0.90
        case .function:    return 0.85
        case .numpad:      return 0.95
        }
    }

    /// Multiplier on the low-frequency thud envelope (body resonance).
    var resonanceFactor: Float {
        switch self {
        case .normal:      return 1.0
        case .space:       return 1.50
        case .returnEnter: return 1.45
        case .deleteKey:   return 1.30
        case .modifier:    return 1.20
        case .navigation:  return 1.0
        case .function:    return 1.0
        case .numpad:      return 1.0
        }
    }
}
