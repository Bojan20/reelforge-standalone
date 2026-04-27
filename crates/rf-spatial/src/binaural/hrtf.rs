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

    /// Add HRIR measurement.
    ///
    /// Azimuth is wrapped into the canonical [0, az_steps) bucket so that
    /// callers passing -90° and +270° land in the same slot — the lookup
    /// helpers all wrap, and inserts that don't would create dead keys
    /// the lookups can't find. (FLUX_MASTER_TODO 1.5.1.)
    pub fn add_hrir(&mut self, azimuth: f32, elevation: f32, hrir: HrirPair) {
        let az_idx_raw = (azimuth / self.azimuth_resolution).round() as i32;
        let az_idx = self.wrap_az_idx(az_idx_raw);
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

    /// Wrap an azimuth bin index into the periodic [0, az_steps) range so
    /// that azimuth = 179° and azimuth = -181° resolve to the same grid
    /// point (they're physically the same direction). Pre-2026-04-27 the
    /// bilinear path indexed `(azimuth / resolution).floor() as i32` directly
    /// — `179.5° / 5° = 35.9 → floor=35, ceil=36`, but on a 5° grid index 36
    /// (= 180°) is the same as index −36 (= -180°). Without the wrap, the
    /// `ceil` corner missed half the time and the `unwrap_or(ll)` fallback
    /// silently degraded the bilinear to a 1-D (azimuth-only) lerp,
    /// introducing ITD discontinuities every time a moving source crossed
    /// ±180° (FLUX_MASTER_TODO 1.5.1 / BUG #35).
    #[inline]
    fn wrap_az_idx(&self, idx: i32) -> i32 {
        let steps = (360.0 / self.azimuth_resolution).round() as i32;
        if steps <= 0 {
            return idx;
        }
        ((idx % steps) + steps) % steps
    }

    /// Get nearest HRIR
    fn get_nearest(&self, azimuth: f32, elevation: f32) -> Option<HrirPair> {
        let az_idx = self.wrap_az_idx((azimuth / self.azimuth_resolution).round() as i32);
        let el_idx = (elevation / self.elevation_resolution).round() as i32;
        self.hrirs.get(&(az_idx, el_idx)).cloned()
    }

    /// Get bilinearly interpolated HRIR.
    ///
    /// Performs proper bilinear interpolation in (azimuth, elevation)
    /// parameter space, with azimuth wrapped modulo 360° so that azimuth
    /// values near ±180° still find both bracketing corners.
    fn get_bilinear(&self, azimuth: f32, elevation: f32) -> Option<HrirPair> {
        let az_frac = azimuth / self.azimuth_resolution;
        let el_frac = elevation / self.elevation_resolution;

        let az_lo_raw = az_frac.floor() as i32;
        let az_hi_raw = az_lo_raw + 1; // always lo+1 — ceil() is wrong on integer-aligned values
        let el_lo = el_frac.floor() as i32;
        let el_hi = el_lo + 1;

        let az_lo = self.wrap_az_idx(az_lo_raw);
        let az_hi = self.wrap_az_idx(az_hi_raw);

        let az_t = az_frac - az_frac.floor();
        let el_t = el_frac - el_frac.floor();

        // Get four corners. We require ll (the principal anchor); if any of
        // the other three are missing the database is sparse near the poles
        // — falling back to ll preserves the previous "graceful degradation"
        // behavior rather than dropping the whole sample.
        let ll = self.hrirs.get(&(az_lo, el_lo))?;
        let lh = self.hrirs.get(&(az_lo, el_hi)).unwrap_or(ll);
        let hl = self.hrirs.get(&(az_hi, el_lo)).unwrap_or(ll);
        let hh = self.hrirs.get(&(az_hi, el_hi)).unwrap_or(ll);

        // Bilinear: lerp along azimuth at both elevations, then along elevation.
        let low = ll.lerp(hl, az_t);
        let high = lh.lerp(hh, az_t);
        Some(low.lerp(&high, el_t))
    }

    /// Get spherically interpolated HRIR (highest quality on a regular
    /// azimuth/elevation grid).
    ///
    /// Uses the same 4 bracketing corners as bilinear but weights them by
    /// **angular** (great-circle) distance from the target direction
    /// rather than by parameter-space distance. Near the poles, where the
    /// equi-angular grid bunches up, two grid points that are 5° apart in
    /// azimuth might be only fractions of a degree apart on the sphere —
    /// bilinear over-counts that bunching, spherical does not.
    ///
    /// Pre-fix this method delegated to `get_vbap` (inverse-distance-weighted
    /// blend of the 3 nearest grid points across the whole HRTF database),
    /// which produced visible ITD/ILD smearing for off-grid directions
    /// because the 3 nearest points often weren't on the same local "patch"
    /// (FLUX_MASTER_TODO 1.5.1 / BUG #35).
    fn get_spherical(&self, azimuth: f32, elevation: f32) -> Option<HrirPair> {
        let az_frac = azimuth / self.azimuth_resolution;
        let el_frac = elevation / self.elevation_resolution;

        let az_lo_raw = az_frac.floor() as i32;
        let az_hi_raw = az_lo_raw + 1;
        let el_lo = el_frac.floor() as i32;
        let el_hi = el_lo + 1;

        let az_lo_w = self.wrap_az_idx(az_lo_raw);
        let az_hi_w = self.wrap_az_idx(az_hi_raw);

        let target = Position3D::from_spherical(azimuth, elevation, 1.0);

        // Compute great-circle (arc) distance from target to each corner.
        // Two grid points that bracket the target in parameter space might
        // be the same physical point on the sphere (poles); this naturally
        // collapses one of the weights to zero distance ⇒ huge weight ⇒
        // that corner dominates, which is what we want.
        let mut weighted: Vec<(HrirPair, f32)> = Vec::with_capacity(4);
        let corners = [
            (az_lo_w, el_lo, az_lo_raw),
            (az_hi_w, el_lo, az_hi_raw),
            (az_lo_w, el_hi, az_lo_raw),
            (az_hi_w, el_hi, az_hi_raw),
        ];
        for &(az_idx, el_idx, az_for_pos) in &corners {
            if let Some(hrir) = self.hrirs.get(&(az_idx, el_idx)) {
                let pos = Position3D::from_spherical(
                    az_for_pos as f32 * self.azimuth_resolution,
                    el_idx as f32 * self.elevation_resolution,
                    1.0,
                );
                let arc = target.distance_to(&pos);
                weighted.push((hrir.clone(), arc));
            }
        }
        if weighted.is_empty() {
            return None;
        }

        // Spherical inverse-arc-distance weighting on the 4-point patch.
        // Epsilon avoids div-by-zero when target lands exactly on a corner.
        let mut total_w = 0.0f32;
        let mut weights: Vec<f32> = Vec::with_capacity(weighted.len());
        for (_, arc) in &weighted {
            let w = if *arc < 1e-6 { 1.0e6 } else { 1.0 / *arc };
            total_w += w;
            weights.push(w);
        }

        let len = self.filter_length;
        let mut left = vec![0.0f32; len];
        let mut right = vec![0.0f32; len];
        let mut itd_acc = 0.0f32;
        for ((hrir, _), w) in weighted.iter().zip(weights.iter()) {
            let scale = *w / total_w;
            for (i, &s) in hrir.left.iter().enumerate().take(len) {
                left[i] += s * scale;
            }
            for (i, &s) in hrir.right.iter().enumerate().take(len) {
                right[i] += s * scale;
            }
            itd_acc += hrir.itd_samples * scale;
        }
        Some(HrirPair { left, right, itd_samples: itd_acc })
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

        nearest.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));

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

    // ── BUG #35 / FLUX_MASTER_TODO 1.5.1 — interpolation regression tests ──

    /// `wrap_az_idx` must map negative or over-range indices into the
    /// canonical [0, az_steps) range. With the default 5° resolution the
    /// step count is 72; index 72 must collapse to 0, and -1 to 71.
    #[test]
    fn test_wrap_az_idx_modular() {
        let db = HrtfDatabase::default_synthetic(48000);
        // 5° resolution ⇒ 72 azimuth bins.
        assert_eq!(db.wrap_az_idx(0), 0);
        assert_eq!(db.wrap_az_idx(72), 0);
        assert_eq!(db.wrap_az_idx(73), 1);
        assert_eq!(db.wrap_az_idx(-1), 71);
        assert_eq!(db.wrap_az_idx(-73), 71);
    }

    /// Pre-fix, querying just below ±180° (179.5° here) had `az_lo` = 35
    /// but `az_hi` = 36 (a non-existent bin) ⇒ the high-az corner was
    /// silently replaced by the low-az corner, degrading bilinear to a
    /// 1-D azimuth-only blend. Post-fix, az_hi wraps to 0 and proper
    /// 4-corner bilinear runs.
    #[test]
    fn test_bilinear_wraps_around_180() {
        let mut db = HrtfDatabase::default_synthetic(48000);
        db.set_interpolation(HrtfInterpolation::Bilinear);

        // 179° is between bin 35 (175°) and bin 36 ≡ bin 0 (180°/-180°).
        let near_180 = db.get_hrir(179.0, 0.0);
        assert!(near_180.is_some(),
            "bilinear must succeed near ±180° once azimuth wraps");

        // -179° is the same physical direction; HRIR must be very close
        // to +179°. Pre-fix the two values produced different bilinear
        // outputs because the `unwrap_or(ll)` fallback at 179° mirrored
        // the wrong corner.
        let pos = db.get_hrir(179.0, 0.0).unwrap();
        let neg = db.get_hrir(-181.0, 0.0).unwrap();
        let max_diff = pos.left.iter().zip(neg.left.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0_f32, f32::max);
        // Synthetic HRTF doesn't have measurement noise, so the two should
        // be exactly equal once the wrap is correct.
        assert!(max_diff < 1e-3,
            "+179° and -181° must produce ~identical HRIR after azimuth wrap; max_diff={max_diff}");
    }

    /// Spherical interpolation must NOT delegate to global IDW any more.
    /// At an off-grid direction, spherical and bilinear should agree to
    /// within a small tolerance (both are smooth blends of the same 4
    /// corners) — pre-fix spherical was IDW over 3 GLOBAL nearest points
    /// and could disagree wildly because it pulled weight from across
    /// the head.
    #[test]
    fn test_spherical_uses_local_patch_not_global_idw() {
        let mut db = HrtfDatabase::default_synthetic(48000);
        db.set_interpolation(HrtfInterpolation::Bilinear);
        let bilinear = db.get_hrir(2.5, 2.5).unwrap();

        db.set_interpolation(HrtfInterpolation::Spherical);
        let spherical = db.get_hrir(2.5, 2.5).unwrap();

        let max_diff = bilinear.left.iter().zip(spherical.left.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0_f32, f32::max);
        // Pre-fix: spherical called get_vbap which blended global 3 nearest
        // and could differ from bilinear by 0.1+ on a normalized impulse.
        // Post-fix: same 4 corners, just slightly different weights ⇒
        // small bounded difference.
        assert!(max_diff < 0.1,
            "spherical must operate on the local 4-corner patch; max_diff vs bilinear={max_diff}");
    }

    /// Spherical must reproduce a corner exactly when the query lands on
    /// it (the 1/arc weight goes to its safety-net 1e6 and dominates).
    #[test]
    fn test_spherical_lands_on_grid_point() {
        let mut db = HrtfDatabase::default_synthetic(48000);
        db.set_interpolation(HrtfInterpolation::Spherical);

        let exact = db.get_hrir(0.0, 0.0).unwrap();
        // Anchor: same angle via Nearest must give a similar (synthetic)
        // result; spherical at the exact grid point must collapse to it.
        db.set_interpolation(HrtfInterpolation::Nearest);
        let nearest = db.get_hrir(0.0, 0.0).unwrap();

        let max_diff = exact.left.iter().zip(nearest.left.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0_f32, f32::max);
        assert!(max_diff < 1e-4,
            "spherical at grid point must equal nearest; max_diff={max_diff}");
    }
}
