//! SAMCL-3 to SAMCL-7: Masking resolution strategies.
//!
//! 5 strategies: notch attenuation, band EQ carve, harmonic attenuation,
//! spatial narrowing, deterministic slot shift.

use super::allocation::SpectralAssignment;
use super::roles::{SpectralBand, SpectralRole};
use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// MASKING STRATEGY (SAMCL-3)
// ═══════════════════════════════════════════════════════════════════════════════

/// 5 masking resolution strategies.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MaskingStrategy {
    /// Notch attenuation: narrow-band cut (-3 to -6 dB).
    NotchAttenuation,
    /// Band EQ carve: broader frequency cut.
    BandEqCarve,
    /// Harmonic attenuation: reduce harmonic content.
    HarmonicAttenuation,
    /// Spatial narrowing: reduce stereo width.
    SpatialNarrowing,
    /// Slot shift: move to alternate band (SAMCL-7).
    SlotShift,
}

/// Applied masking action.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MaskingAction {
    /// Notch cut applied.
    NotchCut { attenuation_db: f64 },
    /// Band EQ carve applied.
    BandCarve {
        attenuation_db: f64,
        bandwidth_hz: f64,
    },
    /// Harmonic layers reduced.
    HarmonicReduced { layers_removed: u32 },
    /// Stereo width narrowed.
    SpatialNarrowed { width_factor: f64 },
    /// Voice shifted to alternate band.
    SlotShifted { new_band: SpectralBand },
    /// Aggressive carve mode (SAMCL-5).
    AggressiveCarve { attenuation_db: f64 },
}

// ═══════════════════════════════════════════════════════════════════════════════
// MASKING RESOLVER (SAMCL-3)
// ═══════════════════════════════════════════════════════════════════════════════

/// Resolves masking conflicts between spectral voices.
pub struct MaskingResolver;

impl MaskingResolver {
    /// Select masking strategy based on priority difference and role (SAMCL-3).
    pub fn select_strategy(
        voice_priority: i32,
        existing_priority: i32,
        role: SpectralRole,
    ) -> MaskingStrategy {
        let diff = existing_priority - voice_priority;

        if diff <= 1 {
            // Very close priority — spatial narrowing (least destructive)
            MaskingStrategy::SpatialNarrowing
        } else if diff <= 3 {
            // Moderate difference — notch attenuation
            MaskingStrategy::NotchAttenuation
        } else if role.is_broadband() {
            // Broadband role with large priority diff — slot shift
            MaskingStrategy::SlotShift
        } else if diff <= 5 {
            // Significant difference — band EQ carve
            MaskingStrategy::BandEqCarve
        } else {
            // Large difference — harmonic attenuation
            MaskingStrategy::HarmonicAttenuation
        }
    }

    /// Resolve a masking conflict and return the action.
    pub fn resolve(strategy: MaskingStrategy, _voice_priority: i32) -> MaskingAction {
        match strategy {
            MaskingStrategy::NotchAttenuation => MaskingAction::NotchCut {
                attenuation_db: -3.0,
            },
            MaskingStrategy::BandEqCarve => MaskingAction::BandCarve {
                attenuation_db: -4.5,
                bandwidth_hz: 200.0,
            },
            MaskingStrategy::HarmonicAttenuation => {
                MaskingAction::HarmonicReduced { layers_removed: 1 }
            }
            MaskingStrategy::SpatialNarrowing => {
                MaskingAction::SpatialNarrowed { width_factor: 0.7 }
            }
            MaskingStrategy::SlotShift => {
                // This should be handled by SpectralAllocator directly
                MaskingAction::SlotShifted {
                    new_band: SpectralBand::new(0.0, 0.0),
                }
            }
        }
    }

    /// Compute deterministic slot shift (SAMCL-7).
    /// Shifts the band by alternating up/down based on shift_index.
    pub fn compute_slot_shift(original: SpectralBand, shift_index: u32) -> SpectralBand {
        let bw = original.bandwidth();
        // Alternate: even shifts go up, odd shifts go down
        let offset = if shift_index % 2 == 0 {
            bw * 0.3 * ((shift_index / 2 + 1) as f64)
        } else {
            -(bw * 0.3 * ((shift_index / 2 + 1) as f64))
        };

        let new_low = (original.low_hz + offset).max(20.0);
        let new_high = (original.high_hz + offset).max(new_low + 10.0);
        SpectralBand::new(new_low, new_high.min(20000.0))
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCI_ADV — Spectral Collision Index (SAMCL-4)
// ═══════════════════════════════════════════════════════════════════════════════

/// Advanced Spectral Collision Index result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SciAdvanced {
    /// SCI value (0.0-1.0+, above threshold triggers carve).
    pub value: f64,
    /// Number of overlapping band pairs.
    pub overlapping_pairs: u32,
    /// Average harmonic density across voices.
    pub avg_harmonic_density: f64,
}

impl SciAdvanced {
    /// Compute SCI_ADV = overlapping_bands × HarmonicDensity × EnergyCap
    pub fn compute(assignments: &[SpectralAssignment], energy_cap: f64) -> Self {
        let n = assignments.len();
        if n < 2 {
            return Self {
                value: 0.0,
                overlapping_pairs: 0,
                avg_harmonic_density: 0.0,
            };
        }

        // Count overlapping pairs
        let mut overlapping_pairs = 0u32;
        for i in 0..n {
            for j in (i + 1)..n {
                let band_a = assignments[i].effective_band;
                let band_b = assignments[j].effective_band;
                if band_a.overlaps(&band_b) {
                    overlapping_pairs += 1;
                }
            }
        }

        // Harmonic density: average layers across all voices
        let total_layers: u32 = assignments.iter().map(|a| a.harmonic_layers).sum();
        let avg_harmonic_density = total_layers as f64 / n as f64;

        // Normalize overlapping_pairs: max possible = n*(n-1)/2
        let max_pairs = (n * (n - 1) / 2) as f64;
        let overlap_ratio = if max_pairs > 0.0 {
            overlapping_pairs as f64 / max_pairs
        } else {
            0.0
        };

        // Normalize harmonic density (max density limit = 4)
        let norm_density = (avg_harmonic_density / 4.0).clamp(0.0, 1.0);

        // SCI_ADV = overlap_ratio × harmonic_density × energy_cap
        let value = overlap_ratio * norm_density * energy_cap;

        Self {
            value,
            overlapping_pairs,
            avg_harmonic_density,
        }
    }

    /// Maximum SCI threshold before aggressive carve.
    pub const MAX_SCI: f64 = 0.85;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_strategy_selection_close_priority() {
        let strategy = MaskingResolver::select_strategy(9, 10, SpectralRole::MidCore);
        assert_eq!(strategy, MaskingStrategy::SpatialNarrowing);
    }

    #[test]
    fn test_strategy_selection_moderate_diff() {
        let strategy = MaskingResolver::select_strategy(7, 10, SpectralRole::MidCore);
        assert_eq!(strategy, MaskingStrategy::NotchAttenuation);
    }

    #[test]
    fn test_strategy_selection_broadband_large_diff() {
        let strategy = MaskingResolver::select_strategy(2, 10, SpectralRole::FullSpectrum);
        assert_eq!(strategy, MaskingStrategy::SlotShift);
    }

    #[test]
    fn test_strategy_selection_large_diff() {
        let strategy = MaskingResolver::select_strategy(1, 10, SpectralRole::MidCore);
        assert_eq!(strategy, MaskingStrategy::HarmonicAttenuation);
    }

    #[test]
    fn test_resolve_notch() {
        let action = MaskingResolver::resolve(MaskingStrategy::NotchAttenuation, 5);
        match action {
            MaskingAction::NotchCut { attenuation_db } => {
                assert!(attenuation_db <= -3.0);
            }
            _ => panic!("Expected NotchCut"),
        }
    }

    #[test]
    fn test_slot_shift_alternates() {
        let band = SpectralBand::new(500.0, 2000.0);
        let shift_0 = MaskingResolver::compute_slot_shift(band, 0);
        let shift_1 = MaskingResolver::compute_slot_shift(band, 1);
        // Even index shifts up, odd shifts down
        assert!(shift_0.low_hz > band.low_hz, "Even shift should go up");
        assert!(shift_1.low_hz < band.low_hz, "Odd shift should go down");
    }

    #[test]
    fn test_sci_adv_no_voices() {
        let sci = SciAdvanced::compute(&[], 0.5);
        assert_eq!(sci.value, 0.0);
    }

    #[test]
    fn test_sci_adv_no_overlap() {
        let assignments = vec![
            SpectralAssignment {
                voice_id: 1,
                role: SpectralRole::SubEnergy,
                priority: 10,
                harmonic_layers: 2,
                masking_action: None,
                slot_shifted: false,
                effective_band: SpectralRole::SubEnergy.band(),
            },
            SpectralAssignment {
                voice_id: 2,
                role: SpectralRole::AirLayer,
                priority: 8,
                harmonic_layers: 2,
                masking_action: None,
                slot_shifted: false,
                effective_band: SpectralRole::AirLayer.band(),
            },
        ];
        let sci = SciAdvanced::compute(&assignments, 0.5);
        assert_eq!(sci.overlapping_pairs, 0);
        assert_eq!(sci.value, 0.0);
    }

    #[test]
    fn test_sci_adv_with_overlap() {
        let assignments = vec![
            SpectralAssignment {
                voice_id: 1,
                role: SpectralRole::MidCore,
                priority: 10,
                harmonic_layers: 3,
                masking_action: None,
                slot_shifted: false,
                effective_band: SpectralRole::MidCore.band(),
            },
            SpectralAssignment {
                voice_id: 2,
                role: SpectralRole::MelodicTopline,
                priority: 8,
                harmonic_layers: 3,
                masking_action: None,
                slot_shifted: false,
                effective_band: SpectralRole::MelodicTopline.band(),
            },
        ];
        let sci = SciAdvanced::compute(&assignments, 0.8);
        assert!(
            sci.overlapping_pairs > 0,
            "MidCore and MelodicTopline overlap"
        );
        assert!(sci.value > 0.0, "SCI should be > 0 with overlap");
    }

    #[test]
    fn test_sci_increases_with_energy_cap() {
        let assignments = vec![
            SpectralAssignment {
                voice_id: 1,
                role: SpectralRole::FullSpectrum,
                priority: 10,
                harmonic_layers: 4,
                masking_action: None,
                slot_shifted: false,
                effective_band: SpectralRole::FullSpectrum.band(),
            },
            SpectralAssignment {
                voice_id: 2,
                role: SpectralRole::BackgroundPad,
                priority: 5,
                harmonic_layers: 4,
                masking_action: None,
                slot_shifted: false,
                effective_band: SpectralRole::BackgroundPad.band(),
            },
        ];
        let sci_low = SciAdvanced::compute(&assignments, 0.3);
        let sci_high = SciAdvanced::compute(&assignments, 0.9);
        assert!(
            sci_high.value > sci_low.value,
            "Higher energy cap should increase SCI: low={}, high={}",
            sci_low.value,
            sci_high.value
        );
    }
}
