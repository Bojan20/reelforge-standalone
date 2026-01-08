//! DSD Sample Rates
//!
//! All DSD rates from DSD64 to DSD512 (ULTIMATE - beyond Pyramix)

/// DSD sample rates
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DsdRate {
    /// DSD64: 2.8224 MHz (64 × 44.1kHz) - Standard SACD
    Dsd64,
    /// DSD128: 5.6448 MHz (128 × 44.1kHz) - Double-rate DSD
    Dsd128,
    /// DSD256: 11.2896 MHz (256 × 44.1kHz) - Quad-rate DSD
    Dsd256,
    /// DSD512: 22.5792 MHz (512 × 44.1kHz) - ULTIMATE (beyond Pyramix)
    Dsd512,
}

/// DSD rate constants
pub const DSD64_RATE: u32 = 2_822_400;    // 64 × 44100
pub const DSD128_RATE: u32 = 5_644_800;   // 128 × 44100
pub const DSD256_RATE: u32 = 11_289_600;  // 256 × 44100
pub const DSD512_RATE: u32 = 22_579_200;  // 512 × 44100

/// DXD (Digital eXtreme Definition) rate for intermediate editing
pub const DXD_RATE: u32 = 352_800;        // 8 × 44100

/// Common PCM rates for reference
pub const PCM_44100: u32 = 44_100;
pub const PCM_48000: u32 = 48_000;
pub const PCM_88200: u32 = 88_200;
pub const PCM_96000: u32 = 96_000;
pub const PCM_176400: u32 = 176_400;
pub const PCM_192000: u32 = 192_000;
pub const PCM_352800: u32 = 352_800;      // DXD
pub const PCM_384000: u32 = 384_000;

impl DsdRate {
    /// Get sample rate in Hz
    pub const fn sample_rate(self) -> u32 {
        match self {
            DsdRate::Dsd64 => DSD64_RATE,
            DsdRate::Dsd128 => DSD128_RATE,
            DsdRate::Dsd256 => DSD256_RATE,
            DsdRate::Dsd512 => DSD512_RATE,
        }
    }

    /// Get multiplier relative to 44.1kHz
    pub const fn multiplier(self) -> u32 {
        match self {
            DsdRate::Dsd64 => 64,
            DsdRate::Dsd128 => 128,
            DsdRate::Dsd256 => 256,
            DsdRate::Dsd512 => 512,
        }
    }

    /// Get decimation ratio to convert to DXD (352.8kHz)
    pub const fn decimation_to_dxd(self) -> u32 {
        match self {
            DsdRate::Dsd64 => 8,     // 2.8MHz → 352.8kHz
            DsdRate::Dsd128 => 16,   // 5.6MHz → 352.8kHz
            DsdRate::Dsd256 => 32,   // 11.2MHz → 352.8kHz
            DsdRate::Dsd512 => 64,   // 22.5MHz → 352.8kHz
        }
    }

    /// Get decimation ratio to convert to 44.1kHz
    pub const fn decimation_to_44100(self) -> u32 {
        match self {
            DsdRate::Dsd64 => 64,
            DsdRate::Dsd128 => 128,
            DsdRate::Dsd256 => 256,
            DsdRate::Dsd512 => 512,
        }
    }

    /// Get bits per second for single channel
    pub const fn bits_per_second(self) -> u64 {
        self.sample_rate() as u64
    }

    /// Get bytes per second for single channel (packed)
    pub const fn bytes_per_second(self) -> u64 {
        self.bits_per_second() / 8
    }

    /// Display name
    pub const fn name(self) -> &'static str {
        match self {
            DsdRate::Dsd64 => "DSD64",
            DsdRate::Dsd128 => "DSD128",
            DsdRate::Dsd256 => "DSD256",
            DsdRate::Dsd512 => "DSD512",
        }
    }

    /// Full description
    pub fn description(self) -> String {
        format!(
            "{} ({:.2} MHz, {}× base rate)",
            self.name(),
            self.sample_rate() as f64 / 1_000_000.0,
            self.multiplier()
        )
    }

    /// From sample rate (approximate match)
    pub fn from_sample_rate(rate: u32) -> Option<Self> {
        // Allow 1% tolerance
        let tolerance = |expected: u32| {
            let min = (expected as f64 * 0.99) as u32;
            let max = (expected as f64 * 1.01) as u32;
            rate >= min && rate <= max
        };

        if tolerance(DSD64_RATE) {
            Some(DsdRate::Dsd64)
        } else if tolerance(DSD128_RATE) {
            Some(DsdRate::Dsd128)
        } else if tolerance(DSD256_RATE) {
            Some(DsdRate::Dsd256)
        } else if tolerance(DSD512_RATE) {
            Some(DsdRate::Dsd512)
        } else {
            None
        }
    }

    /// Get optimal decimation stages for DSD→PCM conversion
    /// Returns (stage1_factor, stage2_factor, ...)
    pub fn decimation_stages(self, target_rate: u32) -> Vec<u32> {
        let total_factor = self.sample_rate() / target_rate;

        // Use multi-stage decimation for better quality
        // Prefer factors of 2, 4, 8
        match total_factor {
            64 => vec![8, 8],           // 64 = 8 × 8
            128 => vec![8, 8, 2],       // 128 = 8 × 8 × 2
            256 => vec![8, 8, 4],       // 256 = 8 × 8 × 4
            512 => vec![8, 8, 8],       // 512 = 8 × 8 × 8
            8 => vec![8],               // To DXD
            16 => vec![8, 2],           // DSD128 → DXD
            32 => vec![8, 4],           // DSD256 → DXD
            _ => {
                // Generic factorization
                let mut factors = Vec::new();
                let mut remaining = total_factor;

                while remaining > 1 {
                    if remaining % 8 == 0 {
                        factors.push(8);
                        remaining /= 8;
                    } else if remaining % 4 == 0 {
                        factors.push(4);
                        remaining /= 4;
                    } else if remaining % 2 == 0 {
                        factors.push(2);
                        remaining /= 2;
                    } else {
                        factors.push(remaining);
                        break;
                    }
                }

                factors
            }
        }
    }

    /// All DSD rates
    pub const fn all() -> [DsdRate; 4] {
        [DsdRate::Dsd64, DsdRate::Dsd128, DsdRate::Dsd256, DsdRate::Dsd512]
    }
}

impl std::fmt::Display for DsdRate {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rates() {
        assert_eq!(DsdRate::Dsd64.sample_rate(), 2_822_400);
        assert_eq!(DsdRate::Dsd128.sample_rate(), 5_644_800);
        assert_eq!(DsdRate::Dsd256.sample_rate(), 11_289_600);
        assert_eq!(DsdRate::Dsd512.sample_rate(), 22_579_200);
    }

    #[test]
    fn test_multipliers() {
        assert_eq!(DsdRate::Dsd64.multiplier(), 64);
        assert_eq!(DsdRate::Dsd128.multiplier(), 128);
        assert_eq!(DsdRate::Dsd256.multiplier(), 256);
        assert_eq!(DsdRate::Dsd512.multiplier(), 512);
    }

    #[test]
    fn test_decimation_stages() {
        assert_eq!(DsdRate::Dsd64.decimation_stages(44100), vec![8, 8]);
        assert_eq!(DsdRate::Dsd128.decimation_stages(44100), vec![8, 8, 2]);
        assert_eq!(DsdRate::Dsd256.decimation_stages(44100), vec![8, 8, 4]);
        assert_eq!(DsdRate::Dsd512.decimation_stages(44100), vec![8, 8, 8]);
    }

    #[test]
    fn test_from_sample_rate() {
        assert_eq!(DsdRate::from_sample_rate(2_822_400), Some(DsdRate::Dsd64));
        assert_eq!(DsdRate::from_sample_rate(5_644_800), Some(DsdRate::Dsd128));
        assert_eq!(DsdRate::from_sample_rate(11_289_600), Some(DsdRate::Dsd256));
        assert_eq!(DsdRate::from_sample_rate(22_579_200), Some(DsdRate::Dsd512));
        assert_eq!(DsdRate::from_sample_rate(44100), None);
    }

    #[test]
    fn test_bits_per_second() {
        // DSD64: 2.8224 Mbit/s per channel
        assert_eq!(DsdRate::Dsd64.bits_per_second(), 2_822_400);
        // DSD512: 22.5792 Mbit/s per channel
        assert_eq!(DsdRate::Dsd512.bits_per_second(), 22_579_200);
    }
}
