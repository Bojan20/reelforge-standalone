//! Binaural audio processing with HRTF
//!
//! High-quality 3D audio for headphones:
//! - HRTF convolution (SOFA support)
//! - ITD/ILD modeling
//! - Nearfield compensation
//! - Head tracking integration
//! - Crossfeed for speaker simulation

mod hrtf;
mod renderer;

pub use hrtf::{Hrtf, HrtfDatabase, HrtfInterpolation};
pub use renderer::{BinauralConfig, BinauralRenderer};

/// HRIR (Head-Related Impulse Response) pair
#[derive(Debug, Clone)]
pub struct HrirPair {
    /// Left ear impulse response
    pub left: Vec<f32>,
    /// Right ear impulse response
    pub right: Vec<f32>,
    /// ITD (Interaural Time Difference) in samples
    pub itd_samples: f32,
}

impl HrirPair {
    /// Create new HRIR pair
    pub fn new(left: Vec<f32>, right: Vec<f32>) -> Self {
        Self {
            left,
            right,
            itd_samples: 0.0,
        }
    }

    /// Get filter length
    pub fn length(&self) -> usize {
        self.left.len().max(self.right.len())
    }

    /// Interpolate between two HRIR pairs
    pub fn lerp(&self, other: &HrirPair, t: f32) -> HrirPair {
        let len = self.length().max(other.length());
        let mut left = vec![0.0f32; len];
        let mut right = vec![0.0f32; len];

        for i in 0..len {
            let l1 = self.left.get(i).copied().unwrap_or(0.0);
            let l2 = other.left.get(i).copied().unwrap_or(0.0);
            left[i] = l1 + (l2 - l1) * t;

            let r1 = self.right.get(i).copied().unwrap_or(0.0);
            let r2 = other.right.get(i).copied().unwrap_or(0.0);
            right[i] = r1 + (r2 - r1) * t;
        }

        HrirPair {
            left,
            right,
            itd_samples: self.itd_samples + (other.itd_samples - self.itd_samples) * t,
        }
    }
}

/// Crossfeed processor for speaker simulation on headphones
pub struct Crossfeed {
    /// Crossfeed amount (0 = none, 1 = full)
    amount: f32,
    /// Delay in samples (for ITD simulation)
    delay_samples: usize,
    /// Delay buffer left
    delay_left: Vec<f32>,
    /// Delay buffer right
    delay_right: Vec<f32>,
    /// Write position
    write_pos: usize,
    /// Lowpass filter coefficient
    lpf_coeff: f32,
    /// Lowpass state left
    lpf_state_left: f32,
    /// Lowpass state right
    lpf_state_right: f32,
}

impl Crossfeed {
    /// Create new crossfeed processor
    pub fn new(sample_rate: u32) -> Self {
        // ITD for 90 degrees is about 0.6ms
        let delay_samples = (0.0003 * sample_rate as f32) as usize;

        // Lowpass at 700 Hz (head shadow)
        let rc = 1.0 / (2.0 * std::f32::consts::PI * 700.0);
        let dt = 1.0 / sample_rate as f32;
        let lpf_coeff = dt / (rc + dt);

        Self {
            amount: 0.3,
            delay_samples,
            delay_left: vec![0.0; delay_samples + 1],
            delay_right: vec![0.0; delay_samples + 1],
            write_pos: 0,
            lpf_coeff,
            lpf_state_left: 0.0,
            lpf_state_right: 0.0,
        }
    }

    /// Set crossfeed amount (0-1)
    pub fn set_amount(&mut self, amount: f32) {
        self.amount = amount.clamp(0.0, 1.0);
    }

    /// Process stereo audio
    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let samples = left.len().min(right.len());

        for i in 0..samples {
            // Read delayed samples
            let read_pos = (self.write_pos + self.delay_left.len() - self.delay_samples)
                % self.delay_left.len();
            let delayed_left = self.delay_left[read_pos];
            let delayed_right = self.delay_right[read_pos];

            // Store current samples
            self.delay_left[self.write_pos] = left[i];
            self.delay_right[self.write_pos] = right[i];

            // Lowpass the crossfeed signal
            self.lpf_state_left += self.lpf_coeff * (delayed_right - self.lpf_state_left);
            self.lpf_state_right += self.lpf_coeff * (delayed_left - self.lpf_state_right);

            // Mix
            left[i] = left[i] * (1.0 - self.amount * 0.5) + self.lpf_state_left * self.amount;
            right[i] = right[i] * (1.0 - self.amount * 0.5) + self.lpf_state_right * self.amount;

            // Advance write position
            self.write_pos = (self.write_pos + 1) % self.delay_left.len();
        }
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.delay_left.fill(0.0);
        self.delay_right.fill(0.0);
        self.lpf_state_left = 0.0;
        self.lpf_state_right = 0.0;
        self.write_pos = 0;
    }
}

/// ITD/ILD model for simple binaural rendering
pub struct ItdIldModel {
    /// Sample rate
    sample_rate: u32,
    /// Head radius in meters
    head_radius: f32,
    /// Speed of sound in m/s
    speed_of_sound: f32,
}

impl ItdIldModel {
    /// Create new ITD/ILD model
    pub fn new(sample_rate: u32) -> Self {
        Self {
            sample_rate,
            head_radius: 0.0875, // Average adult head radius
            speed_of_sound: 343.0,
        }
    }

    /// Calculate ITD in samples for given azimuth
    pub fn itd_samples(&self, azimuth_deg: f32) -> f32 {
        let azimuth_rad = azimuth_deg.to_radians();
        let itd_seconds =
            (self.head_radius / self.speed_of_sound) * (azimuth_rad.sin() + azimuth_rad);
        itd_seconds * self.sample_rate as f32
    }

    /// Calculate ILD in dB for given azimuth and frequency
    pub fn ild_db(&self, azimuth_deg: f32, frequency_hz: f32) -> f32 {
        // Simplified head shadow model
        let azimuth_rad = azimuth_deg.to_radians().abs();

        // More attenuation at higher frequencies
        let freq_factor = (frequency_hz / 1000.0).min(10.0);

        // Maximum ILD around 90 degrees
        let angle_factor = azimuth_rad.sin();

        // ILD increases with frequency (head shadow)
        -angle_factor * freq_factor * 2.0 // Up to ~20 dB at 10kHz, 90 degrees
    }

    /// Calculate gain for left and right ears
    pub fn gains(&self, azimuth_deg: f32) -> (f32, f32) {
        // Positive azimuth = right side
        let azimuth_rad = azimuth_deg.to_radians();

        // Simple panning law with head shadow
        let pan = azimuth_rad.sin();

        // Equal power panning base
        let left_base = ((1.0 - pan) * 0.5 * std::f32::consts::PI).cos();
        let right_base = ((1.0 + pan) * 0.5 * std::f32::consts::PI).cos();

        // Add some head shadow (attenuation on far side)
        let shadow = 0.3; // 30% maximum shadow
        let left_shadow = if pan > 0.0 { 1.0 - shadow * pan } else { 1.0 };
        let right_shadow = if pan < 0.0 { 1.0 + shadow * pan } else { 1.0 };

        (left_base * left_shadow, right_base * right_shadow)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hrir_interpolation() {
        let hrir1 = HrirPair::new(vec![1.0; 10], vec![0.5; 10]);
        let hrir2 = HrirPair::new(vec![0.0; 10], vec![1.0; 10]);

        let interp = hrir1.lerp(&hrir2, 0.5);

        assert!((interp.left[0] - 0.5).abs() < 0.001);
        assert!((interp.right[0] - 0.75).abs() < 0.001);
    }

    #[test]
    fn test_itd_model() {
        let model = ItdIldModel::new(48000);

        // Front should have zero ITD
        let itd_front = model.itd_samples(0.0);
        assert!(itd_front.abs() < 0.1);

        // 90 degrees should have positive ITD
        let itd_right = model.itd_samples(90.0);
        assert!(itd_right > 10.0); // Several samples delay

        // Symmetric
        let itd_left = model.itd_samples(-90.0);
        assert!((itd_left + itd_right).abs() < 0.1);
    }

    #[test]
    fn test_crossfeed() {
        let mut crossfeed = Crossfeed::new(48000);
        crossfeed.set_amount(0.5);

        let mut left = vec![1.0; 100];
        let mut right = vec![0.0; 100];

        crossfeed.process(&mut left, &mut right);

        // Right should have some signal from left crossfeed
        // (after initial delay)
        let right_sum: f32 = right[50..].iter().sum();
        assert!(right_sum > 0.1);
    }
}
