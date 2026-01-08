//! HRTF database and interpolation

use std::collections::HashMap;

use super::HrirPair;
use crate::position::{Position3D, SphericalCoord};

/// HRTF interpolation method
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HrtfInterpolation {
    /// Nearest neighbor (lowest quality, fastest)
    Nearest,
    /// Bilinear (good balance)
    Bilinear,
    /// Spherical (highest quality)
    Spherical,
    /// VBAP-style (vector base amplitude panning)
    Vbap,
}

/// HRTF database
pub struct HrtfDatabase {
    /// HRIR measurements indexed by (azimuth_idx, elevation_idx)
    hrirs: HashMap<(i32, i32), HrirPair>,
    /// Azimuth resolution in degrees
    azimuth_resolution: f32,
    /// Elevation resolution in degrees
    elevation_resolution: f32,
    /// Sample rate
    sample_rate: u32,
    /// Filter length
    filter_length: usize,
    /// Subject ID / name
    subject_id: String,
    /// Interpolation method
    interpolation: HrtfInterpolation,
}

impl HrtfDatabase {
    /// Create empty database
    pub fn new(sample_rate: u32) -> Self {
        Self {
            hrirs: HashMap::new(),
            azimuth_resolution: 5.0,
            elevation_resolution: 5.0,
            sample_rate,
            filter_length: 512,
            subject_id: "default".into(),
            interpolation: HrtfInterpolation::Bilinear,
        }
    }

    /// Create default synthetic HRTF
    pub fn default_synthetic(sample_rate: u32) -> Self {
        let mut db = Self::new(sample_rate);
        db.subject_id = "synthetic".into();
        db.generate_synthetic_hrirs();
        db
    }

    /// Set interpolation method
    pub fn set_interpolation(&mut self, method: HrtfInterpolation) {
        self.interpolation = method;
    }

    /// Add HRIR measurement
    pub fn add_hrir(&mut self, azimuth: f32, elevation: f32, hrir: HrirPair) {
        let az_idx = (azimuth / self.azimuth_resolution).round() as i32;
        let el_idx = (elevation / self.elevation_resolution).round() as i32;
        let length = hrir.length();
        self.hrirs.insert((az_idx, el_idx), hrir);
        self.filter_length = self.filter_length.max(length);
    }

    /// Get interpolated HRIR for direction
    pub fn get_hrir(&self, azimuth: f32, elevation: f32) -> Option<HrirPair> {
        match self.interpolation {
            HrtfInterpolation::Nearest => self.get_nearest(azimuth, elevation),
            HrtfInterpolation::Bilinear => self.get_bilinear(azimuth, elevation),
            HrtfInterpolation::Spherical => self.get_spherical(azimuth, elevation),
            HrtfInterpolation::Vbap => self.get_vbap(azimuth, elevation),
        }
    }

    /// Get nearest HRIR
    fn get_nearest(&self, azimuth: f32, elevation: f32) -> Option<HrirPair> {
        let az_idx = (azimuth / self.azimuth_resolution).round() as i32;
        let el_idx = (elevation / self.elevation_resolution).round() as i32;
        self.hrirs.get(&(az_idx, el_idx)).cloned()
    }

    /// Get bilinearly interpolated HRIR
    fn get_bilinear(&self, azimuth: f32, elevation: f32) -> Option<HrirPair> {
        let az_frac = azimuth / self.azimuth_resolution;
        let el_frac = elevation / self.elevation_resolution;

        let az_lo = az_frac.floor() as i32;
        let az_hi = az_frac.ceil() as i32;
        let el_lo = el_frac.floor() as i32;
        let el_hi = el_frac.ceil() as i32;

        let az_t = az_frac - az_frac.floor();
        let el_t = el_frac - el_frac.floor();

        // Get four corners
        let ll = self.hrirs.get(&(az_lo, el_lo))?;
        let lh = self.hrirs.get(&(az_lo, el_hi)).unwrap_or(ll);
        let hl = self.hrirs.get(&(az_hi, el_lo)).unwrap_or(ll);
        let hh = self.hrirs.get(&(az_hi, el_hi)).unwrap_or(ll);

        // Bilinear interpolation
        let low = ll.lerp(hl, az_t);
        let high = lh.lerp(hh, az_t);
        Some(low.lerp(&high, el_t))
    }

    /// Get spherically interpolated HRIR (higher quality)
    fn get_spherical(&self, azimuth: f32, elevation: f32) -> Option<HrirPair> {
        // For simplicity, fall back to bilinear
        // Full implementation would use spherical barycentric coordinates
        self.get_bilinear(azimuth, elevation)
    }

    /// Get VBAP-style interpolated HRIR
    fn get_vbap(&self, azimuth: f32, elevation: f32) -> Option<HrirPair> {
        // Find three nearest HRIRs and blend
        let target = Position3D::from_spherical(azimuth, elevation, 1.0);

        let mut nearest: Vec<((i32, i32), f32)> = self
            .hrirs
            .keys()
            .map(|&(az_idx, el_idx)| {
                let pos = Position3D::from_spherical(
                    az_idx as f32 * self.azimuth_resolution,
                    el_idx as f32 * self.elevation_resolution,
                    1.0,
                );
                let dist = target.distance_to(&pos);
                ((az_idx, el_idx), dist)
            })
            .collect();

        nearest.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());

        if nearest.is_empty() {
            return None;
        }

        // Use inverse distance weighting for top 3
        let count = nearest.len().min(3);
        let mut total_weight = 0.0f32;
        let mut result_left = vec![0.0f32; self.filter_length];
        let mut result_right = vec![0.0f32; self.filter_length];

        for &(key, dist) in nearest.iter().take(count) {
            let weight = if dist > 0.0 {
                1.0 / (dist + 0.001)
            } else {
                1000.0
            };
            total_weight += weight;

            if let Some(hrir) = self.hrirs.get(&key) {
                for (i, &s) in hrir.left.iter().enumerate() {
                    if i < result_left.len() {
                        result_left[i] += s * weight;
                    }
                }
                for (i, &s) in hrir.right.iter().enumerate() {
                    if i < result_right.len() {
                        result_right[i] += s * weight;
                    }
                }
            }
        }

        // Normalize
        if total_weight > 0.0 {
            for s in &mut result_left {
                *s /= total_weight;
            }
            for s in &mut result_right {
                *s /= total_weight;
            }
        }

        Some(HrirPair::new(result_left, result_right))
    }

    /// Generate synthetic HRIRs (simple model)
    fn generate_synthetic_hrirs(&mut self) {
        let filter_len = 128;
        self.filter_length = filter_len;

        // Generate HRIRs for common positions
        for az in (-180..180).step_by(self.azimuth_resolution as usize) {
            for el in (-40..=90).step_by(self.elevation_resolution as usize) {
                let az_f = az as f32;
                let el_f = el as f32;

                let hrir = self.generate_synthetic_hrir(az_f, el_f, filter_len);
                self.add_hrir(az_f, el_f, hrir);
            }
        }
    }

    /// Generate single synthetic HRIR
    fn generate_synthetic_hrir(&self, azimuth: f32, elevation: f32, length: usize) -> HrirPair {
        let mut left = vec![0.0f32; length];
        let mut right = vec![0.0f32; length];

        let az_rad = azimuth.to_radians();
        let el_rad = elevation.to_radians();

        // ITD model
        let head_radius = 0.0875; // meters
        let speed_of_sound = 343.0; // m/s
        let itd_seconds = (head_radius / speed_of_sound) * (az_rad.sin() + az_rad);
        let itd_samples = (itd_seconds * self.sample_rate as f32).abs();

        // ILD model (frequency dependent, simplified here)
        let pan = az_rad.sin();
        let left_gain = ((1.0 - pan) * 0.5 * std::f32::consts::PI).cos();
        let right_gain = ((1.0 + pan) * 0.5 * std::f32::consts::PI).cos();

        // Head shadow (simple lowpass for far ear)
        let shadow_amount = pan.abs() * 0.5;

        // Generate impulse response
        // Simple model: direct path + early reflections from pinna
        for i in 0..length {
            let t = i as f32;

            // Direct sound (delayed for far ear)
            let left_delay = if pan > 0.0 { itd_samples } else { 0.0 };
            let right_delay = if pan < 0.0 { itd_samples } else { 0.0 };

            // Gaussian-windowed impulse
            let left_dist = (t - left_delay).abs();
            let right_dist = (t - right_delay).abs();

            let sigma = 5.0; // Impulse width
            left[i] = left_gain * (-left_dist * left_dist / (2.0 * sigma * sigma)).exp();
            right[i] = right_gain * (-right_dist * right_dist / (2.0 * sigma * sigma)).exp();

            // Pinna reflection (simplified)
            if i > 10 && i < 30 {
                let pinna_gain = 0.2 * (1.0 - el_rad.abs() / (std::f32::consts::PI / 2.0));
                left[i] += pinna_gain * left_gain * 0.1;
                right[i] += pinna_gain * right_gain * 0.1;
            }
        }

        // Apply head shadow (lowpass on far ear)
        let lpf_coeff = 0.3 * (1.0 - shadow_amount);
        if pan > 0.0 {
            // Right ear is near, left is far - lowpass left
            let mut state = 0.0f32;
            for s in &mut left {
                state = state * (1.0 - lpf_coeff) + *s * lpf_coeff;
                *s = state;
            }
        } else if pan < 0.0 {
            // Left ear is near, right is far - lowpass right
            let mut state = 0.0f32;
            for s in &mut right {
                state = state * (1.0 - lpf_coeff) + *s * lpf_coeff;
                *s = state;
            }
        }

        HrirPair {
            left,
            right,
            itd_samples,
        }
    }

    /// Get filter length
    pub fn filter_length(&self) -> usize {
        self.filter_length
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    /// Get number of measurements
    pub fn measurement_count(&self) -> usize {
        self.hrirs.len()
    }
}

/// Single HRTF for specific position (optimized for real-time)
#[derive(Clone)]
pub struct Hrtf {
    /// Left ear filter coefficients (frequency domain)
    pub left_freq: Vec<num_complex::Complex32>,
    /// Right ear filter coefficients (frequency domain)
    pub right_freq: Vec<num_complex::Complex32>,
    /// Position
    pub position: SphericalCoord,
}

impl Hrtf {
    /// Create from HRIR pair
    pub fn from_hrir(hrir: &HrirPair, position: SphericalCoord, fft_size: usize) -> Self {
        use rustfft::{num_complex::Complex32, FftPlanner};

        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);

        // Prepare left channel
        let mut left_time: Vec<Complex32> = hrir
            .left
            .iter()
            .map(|&x| Complex32::new(x, 0.0))
            .chain(std::iter::repeat(Complex32::new(0.0, 0.0)))
            .take(fft_size)
            .collect();

        // Prepare right channel
        let mut right_time: Vec<Complex32> = hrir
            .right
            .iter()
            .map(|&x| Complex32::new(x, 0.0))
            .chain(std::iter::repeat(Complex32::new(0.0, 0.0)))
            .take(fft_size)
            .collect();

        // FFT
        fft.process(&mut left_time);
        fft.process(&mut right_time);

        Self {
            left_freq: left_time,
            right_freq: right_time,
            position,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_synthetic_hrtf() {
        let db = HrtfDatabase::default_synthetic(48000);
        assert!(db.measurement_count() > 0);

        // Get front HRIR
        let front = db.get_hrir(0.0, 0.0);
        assert!(front.is_some());

        let hrir = front.unwrap();
        assert!(!hrir.left.is_empty());
        assert!(!hrir.right.is_empty());
    }

    #[test]
    fn test_interpolation() {
        let db = HrtfDatabase::default_synthetic(48000);

        // Get interpolated position
        let hrir = db.get_hrir(2.5, 2.5); // Between grid points
        assert!(hrir.is_some());
    }

    #[test]
    fn test_hrtf_symmetry() {
        let db = HrtfDatabase::default_synthetic(48000);

        let left_90 = db.get_hrir(-90.0, 0.0).unwrap();
        let right_90 = db.get_hrir(90.0, 0.0).unwrap();

        // Left ear for left source should be similar to right ear for right source
        let diff: f32 = left_90
            .left
            .iter()
            .zip(right_90.right.iter())
            .map(|(a, b)| (a - b).abs())
            .sum();

        // Should be similar (not exact due to numeric precision)
        assert!(diff < 1.0);
    }
}
