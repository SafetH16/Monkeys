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
        }
    }
}
