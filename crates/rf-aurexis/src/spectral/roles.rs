//! SAMCL-1: 10 SpectralRole enums with frequency bands.

use serde::{Deserialize, Serialize};

/// Frequency band definition (Hz).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct SpectralBand {
    pub low_hz: f64,
    pub high_hz: f64,
}

impl SpectralBand {
    pub const fn new(low_hz: f64, high_hz: f64) -> Self {
        Self { low_hz, high_hz }
    }

    /// Check if two bands overlap.
    pub fn overlaps(&self, other: &SpectralBand) -> bool {
        self.low_hz < other.high_hz && other.low_hz < self.high_hz
    }

    /// Bandwidth in Hz.
    pub fn bandwidth(&self) -> f64 {
        self.high_hz - self.low_hz
    }

    /// Overlap amount in Hz (0 if no overlap).
    pub fn overlap_hz(&self, other: &SpectralBand) -> f64 {
        let start = self.low_hz.max(other.low_hz);
        let end = self.high_hz.min(other.high_hz);
        (end - start).max(0.0)
    }

    /// Overlap ratio (0.0-1.0, relative to the smaller band).
    pub fn overlap_ratio(&self, other: &SpectralBand) -> f64 {
        let overlap = self.overlap_hz(other);
        let min_bw = self.bandwidth().min(other.bandwidth());
        if min_bw <= 0.0 { 0.0 } else { overlap / min_bw }
    }
}

/// 10 spectral roles for slot audio voices.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum SpectralRole {
    /// Sub bass energy (20-90 Hz).
    SubEnergy = 0,
    /// Low body, warmth (80-250 Hz).
    LowBody = 1,
    /// Low-mid body, fullness (200-600 Hz).
    LowMidBody = 2,
    /// Mid core, presence (500-2000 Hz).
    MidCore = 3,
    /// High transient, click/attack (2000-6000 Hz).
    HighTransient = 4,
    /// Air layer, sparkle (6000-14000 Hz).
    AirLayer = 5,
    /// Full spectrum (80-10000 Hz).
    FullSpectrum = 6,
    /// Noise/impact (broadband).
    NoiseImpact = 7,
    /// Melodic topline (200-4000 Hz).
    MelodicTopline = 8,
    /// Background pad (100-8000 Hz).
    BackgroundPad = 9,
}

impl SpectralRole {
    /// Primary frequency band for this role.
    pub fn band(self) -> SpectralBand {
        match self {
            SpectralRole::SubEnergy => SpectralBand::new(20.0, 90.0),
            SpectralRole::LowBody => SpectralBand::new(80.0, 250.0),
            SpectralRole::LowMidBody => SpectralBand::new(200.0, 600.0),
            SpectralRole::MidCore => SpectralBand::new(500.0, 2000.0),
            SpectralRole::HighTransient => SpectralBand::new(2000.0, 6000.0),
            SpectralRole::AirLayer => SpectralBand::new(6000.0, 14000.0),
            SpectralRole::FullSpectrum => SpectralBand::new(80.0, 10000.0),
            SpectralRole::NoiseImpact => SpectralBand::new(20.0, 16000.0),
            SpectralRole::MelodicTopline => SpectralBand::new(200.0, 4000.0),
            SpectralRole::BackgroundPad => SpectralBand::new(100.0, 8000.0),
        }
    }

    /// Display name.
    pub fn name(self) -> &'static str {
        match self {
            SpectralRole::SubEnergy => "Sub Energy",
            SpectralRole::LowBody => "Low Body",
            SpectralRole::LowMidBody => "Low-Mid Body",
            SpectralRole::MidCore => "Mid Core",
            SpectralRole::HighTransient => "High Transient",
            SpectralRole::AirLayer => "Air Layer",
            SpectralRole::FullSpectrum => "Full Spectrum",
            SpectralRole::NoiseImpact => "Noise/Impact",
            SpectralRole::MelodicTopline => "Melodic Topline",
            SpectralRole::BackgroundPad => "Background Pad",
        }
    }

    /// Get from index (0-9).
    pub fn from_index(i: u8) -> Option<Self> {
        match i {
            0 => Some(SpectralRole::SubEnergy),
            1 => Some(SpectralRole::LowBody),
            2 => Some(SpectralRole::LowMidBody),
            3 => Some(SpectralRole::MidCore),
            4 => Some(SpectralRole::HighTransient),
            5 => Some(SpectralRole::AirLayer),
            6 => Some(SpectralRole::FullSpectrum),
            7 => Some(SpectralRole::NoiseImpact),
            8 => Some(SpectralRole::MelodicTopline),
            9 => Some(SpectralRole::BackgroundPad),
            _ => None,
        }
    }

    /// Number of spectral roles.
    pub const COUNT: usize = 10;

    /// Whether this role has broad spectral coverage (overlaps many bands).
    pub fn is_broadband(self) -> bool {
        matches!(
            self,
            SpectralRole::FullSpectrum | SpectralRole::NoiseImpact | SpectralRole::BackgroundPad
        )
    }

    /// Default harmonic density limit for this role (SAMCL-6).
    pub fn harmonic_density_limit(self) -> u32 {
        match self {
            // LOW density zones
            SpectralRole::SubEnergy | SpectralRole::AirLayer => 2,
            // MID density zones
            SpectralRole::LowBody | SpectralRole::LowMidBody | SpectralRole::HighTransient => 3,
            // PEAK density zones
            SpectralRole::MidCore | SpectralRole::FullSpectrum |
            SpectralRole::NoiseImpact | SpectralRole::MelodicTopline |
            SpectralRole::BackgroundPad => 4,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_band_overlap() {
        let sub = SpectralRole::SubEnergy.band();
        let low = SpectralRole::LowBody.band();
        assert!(sub.overlaps(&low), "Sub and LowBody should overlap (80-90 Hz)");

        let air = SpectralRole::AirLayer.band();
        assert!(!sub.overlaps(&air), "Sub and Air should not overlap");
    }

    #[test]
    fn test_overlap_ratio() {
        let a = SpectralBand::new(0.0, 100.0);
        let b = SpectralBand::new(50.0, 150.0);
        let ratio = a.overlap_ratio(&b);
        assert!((ratio - 0.5).abs() < 0.01, "50% overlap expected, got {ratio}");
    }

    #[test]
    fn test_all_roles_valid() {
        for i in 0..SpectralRole::COUNT {
            let role = SpectralRole::from_index(i as u8).unwrap();
            assert!(role.band().bandwidth() > 0.0, "Band {} should have positive bandwidth", role.name());
        }
    }

    #[test]
    fn test_harmonic_density_limits() {
        assert_eq!(SpectralRole::SubEnergy.harmonic_density_limit(), 2);
        assert_eq!(SpectralRole::LowBody.harmonic_density_limit(), 3);
        assert_eq!(SpectralRole::MidCore.harmonic_density_limit(), 4);
    }

    #[test]
    fn test_broadband_roles() {
        assert!(SpectralRole::FullSpectrum.is_broadband());
        assert!(SpectralRole::NoiseImpact.is_broadband());
        assert!(!SpectralRole::SubEnergy.is_broadband());
    }
}
