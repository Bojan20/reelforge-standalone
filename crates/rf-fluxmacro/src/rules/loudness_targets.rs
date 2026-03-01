// ============================================================================
// rf-fluxmacro — Loudness Targets
// ============================================================================
// FM-12: Per-domain LUFS/True Peak targets for 5 audio domains.
// ============================================================================

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

/// Complete loudness target configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoudnessTargets {
    pub domains: HashMap<String, DomainLoudnessTarget>,
}

/// Loudness target for a single audio domain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainLoudnessTarget {
    /// Target integrated LUFS.
    pub lufs_target: f32,
    /// Allowed tolerance (±).
    pub lufs_tolerance: f32,
    /// Maximum true peak in dBTP.
    pub true_peak_max: f32,
    /// Headroom for layering in dB.
    pub layering_headroom: f32,
}

impl DomainLoudnessTarget {
    /// Check if a measured LUFS value is within tolerance.
    pub fn is_lufs_compliant(&self, measured: f32) -> bool {
        (measured - self.lufs_target).abs() <= self.lufs_tolerance
    }

    /// Check if a measured true peak is compliant.
    pub fn is_tp_compliant(&self, measured: f32) -> bool {
        measured <= self.true_peak_max
    }

    /// Suggested gain correction to reach target.
    pub fn suggested_gain_correction(&self, measured_lufs: f32) -> f32 {
        self.lufs_target - measured_lufs
    }
}

impl Default for LoudnessTargets {
    fn default() -> Self {
        let mut domains = HashMap::new();

        domains.insert(
            "ui".to_string(),
            DomainLoudnessTarget {
                lufs_target: -20.0,
                lufs_tolerance: 1.5,
                true_peak_max: -1.0,
                layering_headroom: 6.0,
            },
        );

        domains.insert(
            "sfx".to_string(),
            DomainLoudnessTarget {
                lufs_target: -18.0,
                lufs_tolerance: 2.0,
                true_peak_max: -1.0,
                layering_headroom: 6.0,
            },
        );

        domains.insert(
            "mus".to_string(),
            DomainLoudnessTarget {
                lufs_target: -16.0,
                lufs_tolerance: 1.5,
                true_peak_max: -1.0,
                layering_headroom: 3.0,
            },
        );

        domains.insert(
            "vo".to_string(),
            DomainLoudnessTarget {
                lufs_target: -18.0,
                lufs_tolerance: 1.0,
                true_peak_max: -1.0,
                layering_headroom: 6.0,
            },
        );

        domains.insert(
            "amb".to_string(),
            DomainLoudnessTarget {
                lufs_target: -24.0,
                lufs_tolerance: 2.0,
                true_peak_max: -2.0,
                layering_headroom: 9.0,
            },
        );

        Self { domains }
    }
}

impl LoudnessTargets {
    /// Get target for a domain.
    pub fn get(&self, domain: &str) -> Option<&DomainLoudnessTarget> {
        self.domains.get(domain)
    }

    /// All domain IDs.
    pub fn domain_ids(&self) -> Vec<&str> {
        self.domains.keys().map(|k| k.as_str()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_has_5_domains() {
        let targets = LoudnessTargets::default();
        assert_eq!(targets.domains.len(), 5);
    }

    #[test]
    fn lufs_compliance() {
        let targets = LoudnessTargets::default();
        let sfx = targets.get("sfx").unwrap();

        assert!(sfx.is_lufs_compliant(-18.0)); // exact
        assert!(sfx.is_lufs_compliant(-16.5)); // within +1.5
        assert!(sfx.is_lufs_compliant(-19.5)); // within -1.5
        assert!(!sfx.is_lufs_compliant(-12.0)); // too loud
        assert!(!sfx.is_lufs_compliant(-25.0)); // too quiet
    }

    #[test]
    fn true_peak_compliance() {
        let targets = LoudnessTargets::default();
        let sfx = targets.get("sfx").unwrap();

        assert!(sfx.is_tp_compliant(-3.0)); // well under
        assert!(sfx.is_tp_compliant(-1.0)); // exact
        assert!(!sfx.is_tp_compliant(-0.5)); // over
        assert!(!sfx.is_tp_compliant(0.0)); // over
    }

    #[test]
    fn gain_correction() {
        let targets = LoudnessTargets::default();
        let mus = targets.get("mus").unwrap();

        let correction = mus.suggested_gain_correction(-12.0);
        assert!((correction - -4.0).abs() < 0.01); // need -4 dB
    }
}
