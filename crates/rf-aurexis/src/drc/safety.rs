//! DRC: Safety Envelope
//!
//! Non-negotiable limits enforced at every frame. Violation = bake rejection.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §10

use crate::core::parameter_map::DeterministicParameterMap;

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// Safety limits (hard caps).
#[derive(Debug, Clone)]
pub struct SafetyLimits {
    /// Maximum energy cap (≤ 1.0).
    pub max_energy: f64,
    /// Maximum consecutive frames at energy > 0.9 (~5s @ 48kHz).
    pub max_peak_duration_frames: u32,
    /// Maximum concurrent voices.
    pub max_voices: u32,
    /// Maximum harmonic layers per band.
    pub max_harmonic_density: u32,
    /// Maximum SCI (spectral complexity index).
    pub max_sci: f64,
    /// Maximum fraction of session at peak energy (> 0.8).
    pub max_peak_session_pct: f64,
}

impl Default for SafetyLimits {
    fn default() -> Self {
        Self {
            max_energy: 1.0,
            max_peak_duration_frames: 240,
            max_voices: 96,
            max_harmonic_density: 4,
            max_sci: 0.85,
            max_peak_session_pct: 0.40,
        }
    }
}

/// Violation type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnvelopeViolationType {
    Energy,
    PeakDuration,
    Voices,
    HarmonicDensity,
    Sci,
    SessionPeak,
}

impl EnvelopeViolationType {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Energy => "ENERGY",
            Self::PeakDuration => "PEAK_DURATION",
            Self::Voices => "VOICES",
            Self::HarmonicDensity => "HARMONIC_DENSITY",
            Self::Sci => "SCI",
            Self::SessionPeak => "SESSION_PEAK",
        }
    }
}

/// Single envelope violation.
#[derive(Debug, Clone)]
pub struct EnvelopeViolation {
    pub violation_type: EnvelopeViolationType,
    pub frame_index: u32,
    pub value: f64,
    pub limit: f64,
}

/// Envelope validation result.
#[derive(Debug, Clone)]
pub struct EnvelopeResult {
    pub passed: bool,
    pub violations: Vec<EnvelopeViolation>,
    pub peak_energy: f64,
    pub max_peak_duration: u32,
    pub peak_voices: u32,
    pub peak_harmonic_density: u32,
    pub peak_sci: f64,
    pub peak_session_pct: f64,
}

// ═════════════════════════════════════════════════════════════════════════════
// SAFETY ENVELOPE
// ═════════════════════════════════════════════════════════════════════════════

/// Safety Envelope validator.
///
/// Checks all 6 hard caps across every frame of a simulation output.
pub struct SafetyEnvelope {
    limits: SafetyLimits,
    last_result: Option<EnvelopeResult>,
}

impl SafetyEnvelope {
    pub fn new() -> Self {
        Self {
            limits: SafetyLimits::default(),
            last_result: None,
        }
    }

    pub fn with_limits(limits: SafetyLimits) -> Self {
        Self {
            limits,
            last_result: None,
        }
    }

    pub fn limits(&self) -> &SafetyLimits {
        &self.limits
    }

    pub fn set_limits(&mut self, limits: SafetyLimits) {
        self.limits = limits;
    }

    pub fn last_result(&self) -> Option<&EnvelopeResult> {
        self.last_result.as_ref()
    }

    pub fn passed(&self) -> bool {
        self.last_result.as_ref().map_or(false, |r| r.passed)
    }

    /// Validate a sequence of parameter map outputs against safety limits.
    pub fn validate(&mut self, outputs: &[DeterministicParameterMap]) -> &EnvelopeResult {
        let mut violations = Vec::new();
        let mut peak_energy = 0.0_f64;
        let mut peak_voices = 0u32;
        let mut peak_harmonic = 0u32;
        let mut peak_sci = 0.0_f64;
        let mut consecutive_peak_frames = 0u32;
        let mut max_peak_duration = 0u32;
        let mut peak_count = 0u32;

        for (i, output) in outputs.iter().enumerate() {
            let frame = i as u32;

            // 1. Energy check
            let energy = output.energy_density;
            peak_energy = peak_energy.max(energy);
            if energy > self.limits.max_energy {
                violations.push(EnvelopeViolation {
                    violation_type: EnvelopeViolationType::Energy,
                    frame_index: frame,
                    value: energy,
                    limit: self.limits.max_energy,
                });
            }

            // 2. Peak duration check (consecutive frames at energy > 0.9)
            if energy > 0.9 {
                consecutive_peak_frames += 1;
                max_peak_duration = max_peak_duration.max(consecutive_peak_frames);
                if consecutive_peak_frames > self.limits.max_peak_duration_frames {
                    violations.push(EnvelopeViolation {
                        violation_type: EnvelopeViolationType::PeakDuration,
                        frame_index: frame,
                        value: consecutive_peak_frames as f64,
                        limit: self.limits.max_peak_duration_frames as f64,
                    });
                }
            } else {
                consecutive_peak_frames = 0;
            }

            // 3. Voice check (estimate from center_occupancy + energy)
            let voice_count = output.center_occupancy + (energy * 8.0) as u32;
            peak_voices = peak_voices.max(voice_count);
            if voice_count > self.limits.max_voices {
                violations.push(EnvelopeViolation {
                    violation_type: EnvelopeViolationType::Voices,
                    frame_index: frame,
                    value: voice_count as f64,
                    limit: self.limits.max_voices as f64,
                });
            }

            // 4. Harmonic density check
            let harmonic = ((output.harmonic_excitation - 1.0).max(0.0) * 4.0).ceil() as u32;
            peak_harmonic = peak_harmonic.max(harmonic);
            if harmonic > self.limits.max_harmonic_density {
                violations.push(EnvelopeViolation {
                    violation_type: EnvelopeViolationType::HarmonicDensity,
                    frame_index: frame,
                    value: harmonic as f64,
                    limit: self.limits.max_harmonic_density as f64,
                });
            }

            // 5. SCI check (estimate)
            let sci = ((output.harmonic_excitation - 1.0).max(0.0)
                * energy
                * (output.center_occupancy as f64 / 10.0).min(1.0)
                * 2.0)
                .clamp(0.0, 1.0);
            peak_sci = peak_sci.max(sci);
            if sci > self.limits.max_sci {
                violations.push(EnvelopeViolation {
                    violation_type: EnvelopeViolationType::Sci,
                    frame_index: frame,
                    value: sci,
                    limit: self.limits.max_sci,
                });
            }

            // Count peak frames for session percentage
            if energy > 0.8 {
                peak_count += 1;
            }
        }

        // 6. Session peak percentage
        let total_frames = outputs.len().max(1) as f64;
        let peak_session_pct = peak_count as f64 / total_frames;
        if peak_session_pct > self.limits.max_peak_session_pct {
            violations.push(EnvelopeViolation {
                violation_type: EnvelopeViolationType::SessionPeak,
                frame_index: outputs.len() as u32,
                value: peak_session_pct,
                limit: self.limits.max_peak_session_pct,
            });
        }

        let passed = violations.is_empty();

        let result = EnvelopeResult {
            passed,
            violations,
            peak_energy,
            max_peak_duration,
            peak_voices,
            peak_harmonic_density: peak_harmonic,
            peak_sci,
            peak_session_pct,
        };

        self.last_result = Some(result);
        self.last_result.as_ref().unwrap()
    }

    /// Reset state.
    pub fn reset(&mut self) {
        self.last_result = None;
    }
}

impl Default for SafetyEnvelope {
    fn default() -> Self {
        Self::new()
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn safe_outputs(count: usize) -> Vec<DeterministicParameterMap> {
        (0..count)
            .map(|_| {
                let mut m = DeterministicParameterMap::default();
                m.energy_density = 0.3;
                m.harmonic_excitation = 1.2;
                m.center_occupancy = 5;
                m
            })
            .collect()
    }

    #[test]
    fn test_safe_outputs_pass() {
        let mut envelope = SafetyEnvelope::new();
        let outputs = safe_outputs(100);
        let result = envelope.validate(&outputs);

        assert!(result.passed);
        assert!(result.violations.is_empty());
    }

    #[test]
    fn test_energy_violation() {
        let mut envelope = SafetyEnvelope::new();
        let mut outputs = safe_outputs(10);
        outputs[5].energy_density = 1.5; // Exceeds MAX_ENERGY=1.0

        let result = envelope.validate(&outputs);
        assert!(!result.passed);
        assert!(
            result
                .violations
                .iter()
                .any(|v| v.violation_type == EnvelopeViolationType::Energy)
        );
    }

    #[test]
    fn test_peak_duration_violation() {
        let mut envelope = SafetyEnvelope::with_limits(SafetyLimits {
            max_peak_duration_frames: 5,
            ..Default::default()
        });

        let outputs: Vec<DeterministicParameterMap> = (0..20)
            .map(|_| {
                let mut m = DeterministicParameterMap::default();
                m.energy_density = 0.95; // Above 0.9 threshold
                m
            })
            .collect();

        let result = envelope.validate(&outputs);
        assert!(!result.passed);
        assert!(
            result
                .violations
                .iter()
                .any(|v| v.violation_type == EnvelopeViolationType::PeakDuration)
        );
    }

    #[test]
    fn test_session_peak_violation() {
        let mut envelope = SafetyEnvelope::new();
        // All frames at high energy > 0.8 → session peak > 40%
        let outputs: Vec<DeterministicParameterMap> = (0..100)
            .map(|_| {
                let mut m = DeterministicParameterMap::default();
                m.energy_density = 0.85;
                m
            })
            .collect();

        let result = envelope.validate(&outputs);
        assert!(!result.passed);
        assert!(
            result
                .violations
                .iter()
                .any(|v| v.violation_type == EnvelopeViolationType::SessionPeak)
        );
    }

    #[test]
    fn test_default_limits() {
        let limits = SafetyLimits::default();
        assert_eq!(limits.max_energy, 1.0);
        assert_eq!(limits.max_peak_duration_frames, 240);
        assert_eq!(limits.max_voices, 96);
        assert_eq!(limits.max_harmonic_density, 4);
        assert_eq!(limits.max_sci, 0.85);
        assert_eq!(limits.max_peak_session_pct, 0.40);
    }

    #[test]
    fn test_violation_type_names() {
        assert_eq!(EnvelopeViolationType::Energy.name(), "ENERGY");
        assert_eq!(EnvelopeViolationType::PeakDuration.name(), "PEAK_DURATION");
        assert_eq!(EnvelopeViolationType::SessionPeak.name(), "SESSION_PEAK");
    }

    #[test]
    fn test_reset() {
        let mut envelope = SafetyEnvelope::new();
        envelope.validate(&safe_outputs(10));
        assert!(envelope.last_result().is_some());

        envelope.reset();
        assert!(envelope.last_result().is_none());
    }

    #[test]
    fn test_peak_metrics_tracked() {
        let mut envelope = SafetyEnvelope::new();
        let mut outputs = safe_outputs(50);
        outputs[25].energy_density = 0.95;
        outputs[25].center_occupancy = 10;

        let result = envelope.validate(&outputs);
        assert!(result.peak_energy >= 0.95);
        assert!(result.peak_voices >= 10);
    }
}
