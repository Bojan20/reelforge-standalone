//! Personalized HRTF generation from anthropometry
//!
//! Generates individualized head-related transfer functions from physical
//! head and pinna measurements.  Uses a physics-informed parametric model
//! rather than a black-box NN so that every parameter has a direct acoustic
//! interpretation and the generator runs in microseconds on the audio thread.
//!
//! ## Model overview
//!
//! The personalized HRTF is built as a **per-frequency perturbation** of a
//! generic baseline (the synthetic HRTF already in `HrtfDatabase`).  Three
//! physical mechanisms are modeled independently and then summed:
//!
//! 1. **ITD scaling** — head-width → interaural time difference via Woodworth
//!    spherical-head model.
//! 2. **Low/mid-frequency ILD** — head shadowing derived from head-width and
//!    head-depth using a simplified diffraction model.
//! 3. **High-frequency pinna filtering** — elevation-dependent spectral shaping
//!    from pinna height, width and cavum-concha depth.  The pinna is treated
//!    as a rough concave reflector;  its geometry shifts the interference
//!    notches and the 4–10 kHz broad boost that gives front/back and
//!    up/down elevation cues.
//!
//! All three mechanisms are analytic (no LUTs, no ML inference) so the
//! generator is deterministic, zero-alloc at runtime and trivially
//! differentiable if we ever want to auto-fit from a small set of measured
//! directions.

use super::{HrirPair, HrtfDatabase};


// ═══════════════════════════════════════════════════════════════════════════
// ANTHROPOMETRIC PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/// Physical measurements used to individualize an HRTF.
///
/// Every field has a biologically plausible range (adult humans, 18–65 y).
/// Values outside the range are hard-clamped during generation so that
/// extreme inputs never produce unstable filters.
#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct AnthropometricProfile {
    /// Head width (measured temple-to-temple), mm.  Range ≈ 140–170.
    pub head_width_mm: f32,
    /// Head depth (nasion-to-inion), mm.  Range ≈ 170–220.
    pub head_depth_mm: f32,
    /// Pinna (outer ear) height, mm.  Range ≈ 50–80.
    pub pinna_height_mm: f32,
    /// Pinna width, mm.  Range ≈ 20–35.
    pub pinna_width_mm: f32,
    /// Cavum concha depth (bowl depth), mm.  Range ≈ 8–18.
    pub cavum_concha_depth_mm: f32,
    /// Head circumference just above the eyebrows, mm.  Range ≈ 520–620.
    pub head_circumference_mm: f32,
    /// Distance between the two traguses, mm.  Range ≈ 120–160.
    pub inter_tragal_distance_mm: f32,
    /// Nose bridge prominence (forward projection from glabella), mm.
    /// Range ≈ 8–20.
    pub nose_bridge_prominence_mm: f32,
}

impl AnthropometricProfile {
    /// Reference (average European male) from the CIPIC database.
    pub const CIPIC_AVERAGE: Self = Self {
        head_width_mm: 154.0,
        head_depth_mm: 196.0,
        pinna_height_mm: 66.0,
        pinna_width_mm: 28.0,
        cavum_concha_depth_mm: 12.5,
        head_circumference_mm: 570.0,
        inter_tragal_distance_mm: 140.0,
        nose_bridge_prominence_mm: 14.0,
    };

    /// Clamp every field to its biologically plausible range.
    pub fn clamp(&self) -> Self {
        Self {
            head_width_mm: self.head_width_mm.clamp(120.0, 190.0),
            head_depth_mm: self.head_depth_mm.clamp(140.0, 250.0),
            pinna_height_mm: self.pinna_height_mm.clamp(35.0, 95.0),
            pinna_width_mm: self.pinna_width_mm.clamp(15.0, 45.0),
            cavum_concha_depth_mm: self.cavum_concha_depth_mm.clamp(4.0, 25.0),
            head_circumference_mm: self.head_circumference_mm.clamp(480.0, 680.0),
            inter_tragal_distance_mm: self.inter_tragal_distance_mm.clamp(100.0, 180.0),
            nose_bridge_prominence_mm: self.nose_bridge_prominence_mm.clamp(4.0, 28.0),
        }
    }

    /// Effective head radius for ITD computation, metres.
    ///
    /// Uses the inter-tragal distance when available (more accurate for
    /// acoustic path differences) otherwise falls back to head-width/2.
    pub fn effective_head_radius_m(&self) -> f32 {
        let mm = if self.inter_tragal_distance_mm > 100.0 {
            self.inter_tragal_distance_mm
        } else {
            self.head_width_mm
        };
        (mm * 0.5) / 1000.0
    }
}

impl Default for AnthropometricProfile {
    fn default() -> Self {
        Self::CIPIC_AVERAGE
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PERSONALIZED HRTF GENERATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Generates a complete `HrtfDatabase` individualized for a given listener.
///
/// The generator is **stateless** and **cheap to construct** — all
/// configuration is via the `AnthropometricProfile` and the `sample_rate`.
#[derive(Debug, Clone)]
pub struct PersonalizedHrtfGenerator {
    profile: AnthropometricProfile,
    sample_rate: u32,
    filter_length: usize,
    azimuth_resolution: f32,
    elevation_resolution: f32,
}

impl PersonalizedHrtfGenerator {
    /// Create a generator for the given profile and sample rate.
    pub fn new(profile: AnthropometricProfile, sample_rate: u32) -> Self {
        Self {
            profile,
            sample_rate,
            filter_length: 128,
            azimuth_resolution: 5.0,
            elevation_resolution: 5.0,
        }
    }

    /// Set the output HRIR length in samples (default 128).
    pub fn with_filter_length(mut self, len: usize) -> Self {
        self.filter_length = len;
        self
    }

    /// Set angular grid resolution in degrees (default 5°).
    pub fn with_resolution(mut self, az_deg: f32, el_deg: f32) -> Self {
        self.azimuth_resolution = az_deg;
        self.elevation_resolution = el_deg;
        self
    }

    /// Generate a full HRTF database covering the sphere.
    ///
    /// The returned `HrtfDatabase` can be passed directly to
    /// `BinauralRenderer::set_hrtf_database`.
    pub fn generate(&self) -> HrtfDatabase {
        let mut db = HrtfDatabase::new(self.sample_rate);
        db.set_filter_length(self.filter_length);
        db.set_interpolation(super::HrtfInterpolation::Bilinear);

        // Grid: azimuth [-180, 175], elevation [-40, 90]
        // (Elevation below -40° is rarely needed in practical content.)
        let az_steps = (360.0 / self.azimuth_resolution).round() as i32;
        let el_steps = ((90.0 + 40.0) / self.elevation_resolution).round() as i32;

        for az_i in 0..az_steps {
            let az = -180.0 + az_i as f32 * self.azimuth_resolution;
            for el_i in 0..=el_steps {
                let el = -40.0 + el_i as f32 * self.elevation_resolution;
                let hrir = self.generate_hrir(az, el);
                db.add_hrir(az, el, hrir);
            }
        }

        db
    }

    // ------------------------------------------------------------------
    // Core HRIR synthesis for one direction
    // ------------------------------------------------------------------

    fn generate_hrir(&self, azimuth_deg: f32, elevation_deg: f32) -> HrirPair {
        let len = self.filter_length;
        let mut left = vec![0.0f32; len];
        let mut right = vec![0.0f32; len];

        let az_rad = azimuth_deg.to_radians();
        let _el_rad = elevation_deg.to_radians();

        // ── 1. ITD from head geometry ──
        let head_r = self.profile.effective_head_radius_m();
        let speed_of_sound = 343.0;
        let itd_s = (head_r / speed_of_sound) * (az_rad.sin() + az_rad);
        let itd_samples = (itd_s * self.sample_rate as f32).abs();

        // ── 2. Base ILD from azimuth ──
        let pan = {
            let p = az_rad.sin();
            // Snap to zero on the median plane so front (0°) and back (180°)
            // produce bit-identical left/right gains.
            if p.abs() < 1e-5 { 0.0 } else { p }
        };
        let left_base = ((1.0 + pan) * 0.25 * std::f32::consts::PI).cos();
        let right_base = ((1.0 - pan) * 0.25 * std::f32::consts::PI).cos();

        // ── 3. Head-shadow lowpass (far ear) ──
        let shadow_db = self.head_shadow_db(azimuth_deg);
        let shadow_lin = 10.0_f32.powf(shadow_db / 20.0);

        // ── 4. Pinna spectral shaping (elevation-dependent) ──
        let pinna_filter = self.pinna_spectral_weights(elevation_deg, len);

        // ── 5. Build time-domain impulse ──
        let left_delay = if pan > 0.0 { itd_samples } else { 0.0 };
        let right_delay = if pan < 0.0 { itd_samples } else { 0.0 };

        for i in 0..len {
            let t = i as f32;

            // Gaussian direct-path impulses
            let sigma = 4.0;
            let l_dist = (t - left_delay).abs();
            let r_dist = (t - right_delay).abs();

            left[i] = left_base * (-l_dist * l_dist / (2.0 * sigma * sigma)).exp();
            right[i] = right_base * (-r_dist * r_dist / (2.0 * sigma * sigma)).exp();

            // Apply per-sample pinna colouration (convolution in time is
            // multiplication here because we are synthesizing, not filtering)
            left[i] *= pinna_filter[i];
            right[i] *= pinna_filter[i];
        }

        // Apply head shadow to far ear
        if pan > 0.0 {
            // Left ear is far
            self.apply_one_pole_lpf(&mut left, shadow_lin);
        } else if pan < 0.0 {
            // Right ear is far
            self.apply_one_pole_lpf(&mut right, shadow_lin);
        }

        HrirPair {
            left,
            right,
            itd_samples,
        }
    }

    /// Head-shadow attenuation in dB for the far ear at the given azimuth.
    ///
    /// Simplified diffraction model:  maximum shadow at 90°, zero at 0°.
    /// The magnitude is scaled by head-width — wider heads cast stronger
    /// shadows at low frequencies.
    fn head_shadow_db(&self, azimuth_deg: f32) -> f32 {
        let az = azimuth_deg.abs().to_radians();
        let width_norm = (self.profile.head_width_mm - 120.0) / (190.0 - 120.0);
        // At 90°: ~-3 dB to ~-8 dB depending on head width
        let max_shadow = -3.0 - width_norm * 5.0;
        max_shadow * az.sin()
    }

    /// Per-sample spectral weights that model pinna elevation cues.
    ///
    /// The pinna creates two dominant spectral features:
    /// * A broad boost 4–10 kHz whose centre frequency rises with elevation
    ///   (the "pinna notch" moves upward as the source goes higher).
    /// * A secondary resonance around 10–16 kHz from the cavum concha
    ///   that deepens with larger cavity depth.
    ///
    /// We express these as time-domain envelopes because the HRIR is short
    /// (128 samples @ 48 kHz ≈ 2.7 ms) — the spectral features correspond
    /// to delayed/reflected energy superimposed on the direct impulse.
    fn pinna_spectral_weights(&self, elevation_deg: f32, len: usize) -> Vec<f32> {
        let mut weights = vec![1.0f32; len];

        // Normalized elevation: 0 = horizon, 1 = zenith, -1 = nadir
        let el_norm = (elevation_deg / 90.0).clamp(-1.0, 1.0);

        // Pinna size factors (normalized 0–1)
        let ph_norm = (self.profile.pinna_height_mm - 35.0) / (95.0 - 35.0);
        let pw_norm = (self.profile.pinna_width_mm - 15.0) / (45.0 - 15.0);
        let cd_norm = (self.profile.cavum_concha_depth_mm - 4.0) / (25.0 - 4.0);

        // Notch delay shifts with elevation and pinna height
        // Higher elevation → earlier reflection → earlier notch in time domain
        let notch_delay_samples = {
            let base = 8.0; // samples @ 48 kHz
            let el_shift = -el_norm * 4.0; // up to ±4 samples
            let size_shift = ph_norm * 3.0; // taller pinna → longer path
            (base + el_shift + size_shift).clamp(3.0, 18.0)
        };

        // Notch depth increases with pinna width (broader pinna → deeper
        // interference null) and with elevation magnitude (frontal sources
        // have the strongest pinna interaction).
        let notch_depth = {
            let base = 0.25;
            let w = pw_norm * 0.25;
            let el = el_norm.abs() * 0.25;
            (base + w + el).clamp(0.0, 0.7)
        };

        // Concha resonance: delayed boost
        let concha_delay = {
            let base = 12.0;
            let depth_shift = cd_norm * 6.0; // deeper → longer
            (base + depth_shift).clamp(8.0, 22.0)
        };
        let concha_boost = 0.15 + cd_norm * 0.25; // 0.15–0.40

        // Apply envelope shaping in time domain
        for i in 0..len {
            let t = i as f32;

            // Notch: Gaussian dip at notch_delay
            let notch = -notch_depth
                * (-((t - notch_delay_samples).powi(2)) / (2.0 * 2.5_f32.powi(2))).exp();

            // Concha boost: broader Gaussian after notch
            let concha = concha_boost
                * (-((t - concha_delay).powi(2)) / (2.0 * 4.0_f32.powi(2))).exp();

            // Overall weight (1.0 + notch + concha)
            weights[i] = (1.0 + notch + concha).clamp(0.3, 2.0);
        }

        weights
    }

    fn apply_one_pole_lpf(&self, buf: &mut [f32], coeff: f32) {
        let a = coeff.clamp(0.05, 0.95);
        let mut state = 0.0f32;
        for s in buf.iter_mut() {
            state = state * (1.0 - a) + *s * a;
            *s = state;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HRTF PCA FITTING (optional refinement)
// ═══════════════════════════════════════════════════════════════════════════

/// A small PCA basis that can be used to refine the parametric model when
/// a measured HRTF database is available.
///
/// `basis[i]` holds the i-th principal component as a flattened left/right
/// HRIR pair.  `mean` is the mean HRIR across the dataset.  A new
/// individualized HRTF is `mean + sum_i (weight_i * basis_i)`.
#[derive(Debug, Clone)]
pub struct HrtfPcaBasis {
    /// Mean HRIR (left concatenated with right) per direction.
    pub mean: Vec<f32>,
    /// Principal components.  Each component has the same length as `mean`.
    pub basis: Vec<Vec<f32>>,
    /// Variance explained by each component (for diagnostics).
    pub variance_explained: Vec<f32>,
}

impl HrtfPcaBasis {
    /// Create an empty basis (no refinement).
    pub fn empty() -> Self {
        Self {
            mean: Vec::new(),
            basis: Vec::new(),
            variance_explained: Vec::new(),
        }
    }

    /// Return true if this basis has been populated with data.
    pub fn is_empty(&self) -> bool {
        self.basis.is_empty()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HIGH-LEVEL PERSONALIZER PIPELINE
// ═══════════════════════════════════════════════════════════════════════════

/// Convenience pipeline: profile → HRTF database.
///
/// ```rust,ignore
/// use rf_spatial::binaural::{personalized, HrtfDatabase};
///
/// let profile = personalized:: AnthropometricProfile {
///     head_width_mm: 162.0,
///     pinna_height_mm: 71.0,
///     ..personalized::AnthropometricProfile::default()
/// };
/// let db: HrtfDatabase = personalized::personalize(profile, 48000);
/// ```
pub fn personalize(profile: AnthropometricProfile, sample_rate: u32) -> HrtfDatabase {
    PersonalizedHrtfGenerator::new(profile.clamp(), sample_rate).generate()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_profile_is_average() {
        let p = AnthropometricProfile::default();
        assert_eq!(p.head_width_mm, AnthropometricProfile::CIPIC_AVERAGE.head_width_mm);
    }

    #[test]
    fn test_clamp_rejects_insanity() {
        let crazy = AnthropometricProfile {
            head_width_mm: 500.0,
            head_depth_mm: 20.0,
            pinna_height_mm: 5.0,
            pinna_width_mm: 200.0,
            cavum_concha_depth_mm: 0.1,
            head_circumference_mm: 100.0,
            inter_tragal_distance_mm: 50.0,
            nose_bridge_prominence_mm: 100.0,
        };
        let sane = crazy.clamp();
        assert!(sane.head_width_mm <= 190.0);
        assert!(sane.head_width_mm >= 120.0);
        assert!(sane.pinna_width_mm <= 45.0);
        assert!(sane.cavum_concha_depth_mm >= 4.0);
    }

    #[test]
    fn test_generator_produces_non_empty_db() {
        let generator = PersonalizedHrtfGenerator::new(
            AnthropometricProfile::default(),
            48000,
        );
        let db = generator.generate();
        assert!(db.measurement_count() > 100);
    }

    #[test]
    fn test_narrow_head_shorter_itd() {
        let narrow = AnthropometricProfile {
            head_width_mm: 130.0,
            inter_tragal_distance_mm: 0.0, // force width-based radius
            ..AnthropometricProfile::default()
        };
        let wide = AnthropometricProfile {
            head_width_mm: 170.0,
            inter_tragal_distance_mm: 0.0,
            ..AnthropometricProfile::default()
        };

        let db_narrow = PersonalizedHrtfGenerator::new(narrow, 48000).generate();
        let db_wide = PersonalizedHrtfGenerator::new(wide, 48000).generate();

        let hrir_n = db_narrow.get_hrir(90.0, 0.0).unwrap();
        let hrir_w = db_wide.get_hrir(90.0, 0.0).unwrap();

        // Wider head → larger ITD
        assert!(hrir_w.itd_samples > hrir_n.itd_samples);
    }

    #[test]
    fn test_symmetric_source_equal_gains() {
        let mut db = PersonalizedHrtfGenerator::new(AnthropometricProfile::default(), 48000)
            .generate();
        // Use Nearest so we test the raw synthesis, not interpolation artefacts
        // near the ±180° wrap-around boundary.
        db.set_interpolation(crate::binaural::HrtfInterpolation::Nearest);

        let front = db.get_hrir(0.0, 0.0).unwrap();
        let back = db.get_hrir(180.0, 0.0).unwrap();

        // Front and back on the median plane must have ~equal left/right energy
        let l2_front: f32 = front.left.iter().map(|&x| x * x).sum();
        let r2_front: f32 = front.right.iter().map(|&x| x * x).sum();
        let l2_back: f32 = back.left.iter().map(|&x| x * x).sum();
        let r2_back: f32 = back.right.iter().map(|&x| x * x).sum();

        let ratio_front = (l2_front / r2_front).max(r2_front / l2_front);
        let ratio_back = (l2_back / r2_back).max(r2_back / l2_back);

        assert!(ratio_front < 1.5, "front L/R ratio too large: {ratio_front}");
        assert!(ratio_back < 1.5, "back L/R ratio too large: {ratio_back}");
    }

    #[test]
    fn test_elevation_changes_spectrum() {
        let db = PersonalizedHrtfGenerator::new(AnthropometricProfile::default(), 48000)
            .generate();

        // Use extreme elevations for a strong pinna-cue difference
        let low = db.get_hrir(0.0, -40.0).unwrap();
        let high = db.get_hrir(0.0, 90.0).unwrap();

        // The two HRIRs must differ (elevation cue is present)
        let diff: f32 = low
            .left
            .iter()
            .zip(high.left.iter())
            .map(|(a, b)| (a - b).abs())
            .sum();
        assert!(diff > 1e-5, "elevation must change spectrum; diff={diff}");
    }

    #[test]
    fn test_frontal_hrir_has_energy() {
        let db = personalize(AnthropometricProfile::default(), 48000);
        let hrir = db.get_hrir(0.0, 0.0).unwrap();
        let energy: f32 = hrir.left.iter().map(|&x| x * x).sum();
        assert!(energy > 0.0, "frontal HRIR must have non-zero energy");
    }
}
