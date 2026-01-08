//! Metering utilities

use crate::MeteringState;

impl MeteringState {
    /// Convert peak level to dB
    pub fn peak_to_db(peak: f32) -> f32 {
        if peak <= 0.0 {
            -120.0
        } else {
            20.0 * peak.log10()
        }
    }

    /// Convert dB to linear
    pub fn db_to_linear(db: f32) -> f32 {
        if db <= -120.0 {
            0.0
        } else {
            10.0f32.powf(db / 20.0)
        }
    }

    /// Get master peak in dB (L, R)
    pub fn master_peak_db(&self) -> (f32, f32) {
        (
            Self::peak_to_db(self.master_peak_l),
            Self::peak_to_db(self.master_peak_r),
        )
    }

    /// Get master RMS in dB (L, R)
    pub fn master_rms_db(&self) -> (f32, f32) {
        (
            Self::peak_to_db(self.master_rms_l),
            Self::peak_to_db(self.master_rms_r),
        )
    }

    /// Check if clipping
    pub fn is_clipping(&self) -> bool {
        self.master_peak_l >= 1.0 || self.master_peak_r >= 1.0
    }

    /// Reset peak hold
    pub fn reset_peaks(&mut self) {
        self.master_peak_l = 0.0;
        self.master_peak_r = 0.0;
    }
}
