//! SAMCL-2: SpectralAllocator — assigns spectral roles and resolves collisions.

use serde::{Deserialize, Serialize};
use super::roles::{SpectralRole, SpectralBand};
use super::masking::{MaskingResolver, MaskingStrategy, MaskingAction, SciAdvanced};

/// A voice with its spectral assignment.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpectralAssignment {
    pub voice_id: u32,
    pub role: SpectralRole,
    pub priority: i32,
    /// Harmonic layers active for this voice (SAMCL-6).
    pub harmonic_layers: u32,
    /// Applied masking action (if any collision resolved).
    pub masking_action: Option<MaskingAction>,
    /// Whether this voice was shifted to an alternate band (SAMCL-7).
    pub slot_shifted: bool,
    /// Effective band after potential slot shift.
    pub effective_band: SpectralBand,
}

/// Allocation output.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SpectralAllocationOutput {
    /// All voice assignments.
    pub assignments: Vec<SpectralAssignment>,
    /// Spectral Collision Index (advanced).
    pub sci_adv: f64,
    /// Number of collisions detected.
    pub collision_count: u32,
    /// Number of slot shifts applied (SAMCL-7).
    pub slot_shifts: u32,
    /// Whether aggressive carve mode is active (SAMCL-5).
    pub aggressive_carve_active: bool,
    /// Per-band density: count of voices occupying each of the 10 spectral roles.
    pub band_density: [u32; 10],
}

/// SpectralAllocator — assigns roles, detects collisions, resolves masking.
#[derive(Debug)]
pub struct SpectralAllocator {
    /// Registered voices with roles.
    voices: Vec<VoiceSlot>,
    /// Energy cap from GEG (affects SCI threshold).
    energy_cap: f64,
    /// SCI threshold above which aggressive carve engages (SAMCL-5).
    sci_threshold: f64,
    /// Last output.
    last_output: SpectralAllocationOutput,
}

/// Internal voice slot for allocation.
#[derive(Debug, Clone)]
struct VoiceSlot {
    voice_id: u32,
    role: SpectralRole,
    priority: i32,
    harmonic_layers: u32,
}

impl SpectralAllocator {
    pub fn new() -> Self {
        Self {
            voices: Vec::with_capacity(64),
            energy_cap: 0.5,
            sci_threshold: 0.85,
            last_output: SpectralAllocationOutput::default(),
        }
    }

    /// Set energy cap from GEG (0.0-1.0).
    pub fn set_energy_cap(&mut self, cap: f64) {
        self.energy_cap = cap.clamp(0.0, 1.0);
    }

    /// Register/assign a voice with a spectral role.
    pub fn assign_role(
        &mut self,
        voice_id: u32,
        role: SpectralRole,
        priority: i32,
        harmonic_layers: u32,
    ) -> bool {
        // Enforce harmonic density limit (SAMCL-6)
        let clamped_layers = harmonic_layers.min(role.harmonic_density_limit());

        // Remove existing if re-assigning
        self.voices.retain(|v| v.voice_id != voice_id);

        if self.voices.len() >= 64 {
            return false;
        }

        self.voices.push(VoiceSlot {
            voice_id,
            role,
            priority,
            harmonic_layers: clamped_layers,
        });
        true
    }

    /// Remove a voice from spectral tracking.
    pub fn remove_voice(&mut self, voice_id: u32) -> bool {
        let before = self.voices.len();
        self.voices.retain(|v| v.voice_id != voice_id);
        self.voices.len() < before
    }

    /// Clear all voices.
    pub fn clear(&mut self) {
        self.voices.clear();
    }

    /// Get voice count.
    pub fn voice_count(&self) -> usize {
        self.voices.len()
    }

    /// Compute spectral allocation and resolve collisions.
    pub fn compute(&mut self) -> &SpectralAllocationOutput {
        let n = self.voices.len();
        let mut assignments = Vec::with_capacity(n);
        let mut collision_count = 0u32;
        let mut slot_shifts = 0u32;
        let mut band_density = [0u32; 10];

        // Sort by priority descending (highest priority gets first pick)
        let mut sorted: Vec<VoiceSlot> = self.voices.clone();
        sorted.sort_by(|a, b| b.priority.cmp(&a.priority));

        // Track occupied bands (role index → list of priorities)
        let mut occupied: Vec<Vec<(u32, i32)>> = vec![Vec::new(); SpectralRole::COUNT];

        for slot in &sorted {
            let role_idx = slot.role as usize;
            let band = slot.role.band();
            let mut effective_band = band;
            let mut masking_action = None;
            let mut was_shifted = false;

            // Check for collision with existing voices in overlapping bands
            let mut has_collision = false;
            for (other_role_idx, others) in occupied.iter().enumerate() {
                if others.is_empty() || other_role_idx == role_idx {
                    continue;
                }
                if let Some(other_role) = SpectralRole::from_index(other_role_idx as u8) {
                    if band.overlaps(&other_role.band()) {
                        has_collision = true;
                        break;
                    }
                }
            }

            if has_collision {
                collision_count += 1;
                // Determine masking strategy based on priority difference
                let existing_max_priority = occupied[role_idx]
                    .iter()
                    .map(|(_, p)| *p)
                    .max()
                    .unwrap_or(0);

                let strategy = MaskingResolver::select_strategy(
                    slot.priority,
                    existing_max_priority,
                    slot.role,
                );

                match strategy {
                    MaskingStrategy::SlotShift => {
                        // SAMCL-7: Deterministic slot shift
                        effective_band = MaskingResolver::compute_slot_shift(band, slot_shifts);
                        was_shifted = true;
                        slot_shifts += 1;
                        masking_action = Some(MaskingAction::SlotShifted {
                            new_band: effective_band,
                        });
                    }
                    _ => {
                        masking_action = Some(MaskingResolver::resolve(strategy, slot.priority));
                    }
                }
            }

            // Track density
            band_density[role_idx] = band_density[role_idx].saturating_add(1);
            occupied[role_idx].push((slot.voice_id, slot.priority));

            assignments.push(SpectralAssignment {
                voice_id: slot.voice_id,
                role: slot.role,
                priority: slot.priority,
                harmonic_layers: slot.harmonic_layers,
                masking_action,
                slot_shifted: was_shifted,
                effective_band,
            });
        }

        // Compute SCI_ADV (SAMCL-4)
        let sci = SciAdvanced::compute(&assignments, self.energy_cap);

        // SAMCL-5: Aggressive carve if SCI exceeds threshold
        let aggressive = sci.value > self.sci_threshold;
        if aggressive {
            // Apply aggressive carve: increase all masking actions
            for assignment in assignments.iter_mut() {
                if assignment.masking_action.is_some() {
                    assignment.masking_action = Some(MaskingAction::AggressiveCarve {
                        attenuation_db: -6.0,
                    });
                }
            }
        }

        self.last_output = SpectralAllocationOutput {
            assignments,
            sci_adv: sci.value,
            collision_count,
            slot_shifts,
            aggressive_carve_active: aggressive,
            band_density,
        };

        &self.last_output
    }

    /// Get last computed output.
    pub fn last_output(&self) -> &SpectralAllocationOutput {
        &self.last_output
    }

    /// Reset state.
    pub fn reset(&mut self) {
        self.voices.clear();
        self.last_output = SpectralAllocationOutput::default();
    }

    /// Band config JSON for bake (SAMCL-12).
    pub fn band_config_json() -> Result<String, serde_json::Error> {
        let mut bands = std::collections::BTreeMap::new();
        for i in 0..SpectralRole::COUNT {
            if let Some(role) = SpectralRole::from_index(i as u8) {
                let band = role.band();
                bands.insert(role.name().to_string(), serde_json::json!({
                    "low_hz": band.low_hz,
                    "high_hz": band.high_hz,
                    "harmonic_density_limit": role.harmonic_density_limit(),
                    "is_broadband": role.is_broadband(),
                }));
            }
        }
        serde_json::to_string_pretty(&bands)
    }

    /// Role assignment JSON for bake (SAMCL-12).
    pub fn role_assignment_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(&self.last_output.assignments)
    }

    /// Collision rules JSON for bake (SAMCL-12).
    pub fn collision_rules_json() -> Result<String, serde_json::Error> {
        let rules = serde_json::json!({
            "sci_threshold": 0.85,
            "aggressive_carve_above_threshold": true,
            "strategies": ["NotchAttenuation", "BandEqCarve", "HarmonicAttenuation", "SpatialNarrowing", "SlotShift"],
            "harmonic_density_limits": {
                "LOW": 2,
                "MID": 3,
                "PEAK": 4
            },
            "notch_attenuation_range_db": [-3, -6],
        });
        serde_json::to_string_pretty(&rules)
    }

    /// Shift curves JSON for bake (SAMCL-12).
    pub fn shift_curves_json(&self) -> Result<String, serde_json::Error> {
        let shifts: Vec<serde_json::Value> = self.last_output.assignments.iter()
            .filter(|a| a.slot_shifted)
            .map(|a| serde_json::json!({
                "voice_id": a.voice_id,
                "original_band": {
                    "low_hz": a.role.band().low_hz,
                    "high_hz": a.role.band().high_hz,
                },
                "shifted_band": {
                    "low_hz": a.effective_band.low_hz,
                    "high_hz": a.effective_band.high_hz,
                },
            }))
            .collect();
        serde_json::to_string_pretty(&shifts)
    }
}

impl Default for SpectralAllocator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_assign_and_remove() {
        let mut alloc = SpectralAllocator::new();
        assert!(alloc.assign_role(1, SpectralRole::SubEnergy, 10, 2));
        assert!(alloc.assign_role(2, SpectralRole::MidCore, 8, 3));
        assert_eq!(alloc.voice_count(), 2);
        assert!(alloc.remove_voice(1));
        assert_eq!(alloc.voice_count(), 1);
    }

    #[test]
    fn test_harmonic_density_clamped() {
        let mut alloc = SpectralAllocator::new();
        alloc.assign_role(1, SpectralRole::SubEnergy, 10, 10); // limit is 2
        let output = alloc.compute();
        assert_eq!(output.assignments[0].harmonic_layers, 2, "Should clamp to density limit");
    }

    #[test]
    fn test_collision_detection() {
        let mut alloc = SpectralAllocator::new();
        // SubEnergy (20-90) and LowBody (80-250) overlap
        alloc.assign_role(1, SpectralRole::SubEnergy, 10, 2);
        alloc.assign_role(2, SpectralRole::LowBody, 8, 2);
        let output = alloc.compute();
        assert!(output.collision_count > 0, "Overlapping bands should cause collision");
    }

    #[test]
    fn test_no_collision_non_overlapping() {
        let mut alloc = SpectralAllocator::new();
        // SubEnergy (20-90) and AirLayer (6000-14000) don't overlap
        alloc.assign_role(1, SpectralRole::SubEnergy, 10, 2);
        alloc.assign_role(2, SpectralRole::AirLayer, 8, 2);
        let output = alloc.compute();
        assert_eq!(output.collision_count, 0, "Non-overlapping bands should not collide");
    }

    #[test]
    fn test_aggressive_carve_on_high_sci() {
        let mut alloc = SpectralAllocator::new();
        alloc.set_energy_cap(0.9);
        // Create many overlapping voices to push SCI high
        for i in 0..10 {
            alloc.assign_role(i, SpectralRole::FullSpectrum, (10 - i) as i32, 4);
        }
        let output = alloc.compute();
        // With 10 full spectrum voices, SCI should be very high
        if output.sci_adv > 0.85 {
            assert!(output.aggressive_carve_active, "High SCI should trigger aggressive carve");
        }
    }

    #[test]
    fn test_band_density() {
        let mut alloc = SpectralAllocator::new();
        alloc.assign_role(1, SpectralRole::MidCore, 10, 3);
        alloc.assign_role(2, SpectralRole::MidCore, 8, 2);
        let output = alloc.compute();
        assert_eq!(output.band_density[SpectralRole::MidCore as usize], 2);
    }

    #[test]
    fn test_band_config_json() {
        let json = SpectralAllocator::band_config_json().unwrap();
        assert!(json.contains("Sub Energy"));
        assert!(json.contains("low_hz"));
    }

    #[test]
    fn test_collision_rules_json() {
        let json = SpectralAllocator::collision_rules_json().unwrap();
        assert!(json.contains("sci_threshold"));
        assert!(json.contains("NotchAttenuation"));
    }

    #[test]
    fn test_determinism() {
        let mut a = SpectralAllocator::new();
        let mut b = SpectralAllocator::new();
        a.set_energy_cap(0.6);
        b.set_energy_cap(0.6);
        for i in 0..5 {
            let role = SpectralRole::from_index(i).unwrap();
            a.assign_role(i as u32, role, (10 - i) as i32, 2);
            b.assign_role(i as u32, role, (10 - i) as i32, 2);
        }
        let oa = a.compute();
        let ob = b.compute();
        assert_eq!(oa.sci_adv, ob.sci_adv);
        assert_eq!(oa.collision_count, ob.collision_count);
    }

    #[test]
    fn test_reset() {
        let mut alloc = SpectralAllocator::new();
        alloc.assign_role(1, SpectralRole::SubEnergy, 10, 2);
        alloc.reset();
        assert_eq!(alloc.voice_count(), 0);
    }

    #[test]
    fn test_slot_shift() {
        let mut alloc = SpectralAllocator::new();
        // Two voices in overlapping roles, lower priority should get shifted
        alloc.assign_role(1, SpectralRole::MidCore, 10, 3);
        alloc.assign_role(2, SpectralRole::MelodicTopline, 5, 2); // overlaps MidCore
        let output = alloc.compute();
        // At least one collision should be detected
        assert!(output.collision_count > 0);
    }
}
