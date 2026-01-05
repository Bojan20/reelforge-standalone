//! EQ Morphing - Preset Interpolation System
//!
//! Professional preset morphing:
//! - Smooth interpolation between EQ curves
//! - Band matching algorithms
//! - Animated transitions
//! - A/B comparison with crossfade
//! - Preset snapshots

use std::f64::consts::PI;
use rf_core::Sample;
use crate::{Processor, StereoProcessor, MonoProcessor};
use crate::biquad::{BiquadTDF2, BiquadCoeffs};

// ============================================================================
// EQ PRESET
// ============================================================================

/// Maximum bands in a preset
pub const PRESET_MAX_BANDS: usize = 32;

/// Single EQ band snapshot
#[derive(Debug, Clone, Copy)]
pub struct BandSnapshot {
    pub freq: f64,
    pub gain_db: f64,
    pub q: f64,
    pub filter_type: MorphFilterType,
    pub enabled: bool,
}

impl Default for BandSnapshot {
    fn default() -> Self {
        Self {
            freq: 1000.0,
            gain_db: 0.0,
            q: 1.0,
            filter_type: MorphFilterType::Bell,
            enabled: true,
        }
    }
}

/// Filter types for morphable EQ
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum MorphFilterType {
    #[default]
    Bell,
    LowShelf,
    HighShelf,
    LowCut,
    HighCut,
}

/// Complete EQ preset
#[derive(Debug, Clone)]
pub struct EqPreset {
    pub name: String,
    pub bands: Vec<BandSnapshot>,
}

impl Default for EqPreset {
    fn default() -> Self {
        Self {
            name: String::from("Default"),
            bands: Vec::new(),
        }
    }
}

impl EqPreset {
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            bands: Vec::new(),
        }
    }

    pub fn add_band(&mut self, freq: f64, gain_db: f64, q: f64, filter_type: MorphFilterType) {
        self.bands.push(BandSnapshot {
            freq,
            gain_db,
            q,
            filter_type,
            enabled: true,
        });
    }

    /// Get magnitude at frequency
    pub fn magnitude_at(&self, freq: f64, sample_rate: f64) -> f64 {
        let mut total = 1.0;

        for band in &self.bands {
            if !band.enabled {
                continue;
            }

            let omega = 2.0 * PI * freq / sample_rate;
            let band_omega = 2.0 * PI * band.freq / sample_rate;

            // Simplified magnitude calculation
            match band.filter_type {
                MorphFilterType::Bell => {
                    let a = 10.0_f64.powf(band.gain_db / 40.0);
                    let ratio = freq / band.freq;
                    let q_factor = band.q;

                    let denom = (1.0 - ratio * ratio).powi(2) + (ratio / q_factor).powi(2);
                    total *= (a * a / denom).sqrt();
                }
                MorphFilterType::LowShelf => {
                    if freq < band.freq {
                        let t = (freq / band.freq).log2() / 2.0;
                        total *= 10.0_f64.powf(band.gain_db * (1.0 + t.max(-1.0)) / 40.0);
                    }
                }
                MorphFilterType::HighShelf => {
                    if freq > band.freq {
                        let t = (band.freq / freq).log2() / 2.0;
                        total *= 10.0_f64.powf(band.gain_db * (1.0 + t.max(-1.0)) / 40.0);
                    }
                }
                _ => {}
            }
        }

        20.0 * total.log10()
    }

    /// Generate magnitude curve
    pub fn generate_curve(&self, num_points: usize, sample_rate: f64) -> Vec<f64> {
        (0..num_points).map(|i| {
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 20.0 * (1000.0_f64).powf(t);
            self.magnitude_at(freq, sample_rate)
        }).collect()
    }
}

// ============================================================================
// MORPHABLE BAND
// ============================================================================

/// Single morphable EQ band with interpolation
#[derive(Debug, Clone)]
struct MorphableBand {
    // Current (interpolated) values
    current_freq: f64,
    current_gain: f64,
    current_q: f64,
    current_type: MorphFilterType,

    // Target values
    target_freq: f64,
    target_gain: f64,
    target_q: f64,
    target_type: MorphFilterType,

    // Smoothing
    freq_smooth: f64,
    gain_smooth: f64,
    q_smooth: f64,

    // Filter
    filter_l: BiquadTDF2,
    filter_r: BiquadTDF2,

    sample_rate: f64,
    enabled: bool,
}

impl MorphableBand {
    fn new(sample_rate: f64) -> Self {
        Self {
            current_freq: 1000.0,
            current_gain: 0.0,
            current_q: 1.0,
            current_type: MorphFilterType::Bell,
            target_freq: 1000.0,
            target_gain: 0.0,
            target_q: 1.0,
            target_type: MorphFilterType::Bell,
            freq_smooth: 0.999,
            gain_smooth: 0.995,
            q_smooth: 0.998,
            filter_l: BiquadTDF2::new(sample_rate),
            filter_r: BiquadTDF2::new(sample_rate),
            sample_rate,
            enabled: true,
        }
    }

    fn set_target(&mut self, freq: f64, gain_db: f64, q: f64, filter_type: MorphFilterType) {
        self.target_freq = freq;
        self.target_gain = gain_db;
        self.target_q = q;
        self.target_type = filter_type;
    }

    fn set_immediate(&mut self, freq: f64, gain_db: f64, q: f64, filter_type: MorphFilterType) {
        self.current_freq = freq;
        self.current_gain = gain_db;
        self.current_q = q;
        self.current_type = filter_type;
        self.target_freq = freq;
        self.target_gain = gain_db;
        self.target_q = q;
        self.target_type = filter_type;
        self.update_coefficients();
    }

    fn update(&mut self) {
        // Smooth interpolation toward target
        self.current_freq = self.current_freq * self.freq_smooth
            + self.target_freq * (1.0 - self.freq_smooth);
        self.current_gain = self.current_gain * self.gain_smooth
            + self.target_gain * (1.0 - self.gain_smooth);
        self.current_q = self.current_q * self.q_smooth
            + self.target_q * (1.0 - self.q_smooth);

        // Update filter if parameters changed significantly
        let freq_diff = (self.current_freq - self.target_freq).abs() / self.target_freq;
        let gain_diff = (self.current_gain - self.target_gain).abs();
        let q_diff = (self.current_q - self.target_q).abs();

        if freq_diff > 0.001 || gain_diff > 0.01 || q_diff > 0.01 {
            self.update_coefficients();
        }
    }

    fn update_coefficients(&mut self) {
        let coeffs = match self.current_type {
            MorphFilterType::Bell => {
                BiquadCoeffs::peaking(self.current_freq, self.current_q, self.current_gain, self.sample_rate)
            }
            MorphFilterType::LowShelf => {
                BiquadCoeffs::low_shelf(self.current_freq, self.current_q, self.current_gain, self.sample_rate)
            }
            MorphFilterType::HighShelf => {
                BiquadCoeffs::high_shelf(self.current_freq, self.current_q, self.current_gain, self.sample_rate)
            }
            MorphFilterType::LowCut => {
                BiquadCoeffs::highpass(self.current_freq, self.current_q, self.sample_rate)
            }
            MorphFilterType::HighCut => {
                BiquadCoeffs::lowpass(self.current_freq, self.current_q, self.sample_rate)
            }
        };

        self.filter_l.set_coeffs(coeffs);
        self.filter_r.set_coeffs(coeffs);
    }

    #[inline(always)]
    fn process(&mut self, left: f64, right: f64) -> (f64, f64) {
        if !self.enabled || self.current_gain.abs() < 0.01 {
            return (left, right);
        }
        (self.filter_l.process_sample(left), self.filter_r.process_sample(right))
    }

    fn reset(&mut self) {
        self.filter_l.reset();
        self.filter_r.reset();
    }
}

// ============================================================================
// PRESET MATCHER
// ============================================================================

/// Matches bands between two presets for smooth morphing
struct PresetMatcher {
    /// Matched band pairs (source_idx, target_idx, weight)
    matches: Vec<(usize, usize, f64)>,
}

impl PresetMatcher {
    fn new() -> Self {
        Self {
            matches: Vec::new(),
        }
    }

    /// Match bands between two presets
    fn match_presets(&mut self, source: &EqPreset, target: &EqPreset) {
        self.matches.clear();

        // Simple frequency-based matching
        for (si, sb) in source.bands.iter().enumerate() {
            let mut best_match: Option<(usize, f64)> = None;
            let mut best_distance = f64::MAX;

            for (ti, tb) in target.bands.iter().enumerate() {
                // Same filter type preferred
                let type_penalty = if sb.filter_type == tb.filter_type { 1.0 } else { 0.5 };

                // Frequency distance in octaves
                let freq_distance = (sb.freq / tb.freq).log2().abs();

                let distance = freq_distance / type_penalty;

                if distance < best_distance {
                    best_distance = distance;
                    best_match = Some((ti, type_penalty));
                }
            }

            if let Some((ti, weight)) = best_match {
                // Only match if reasonably close (< 2 octaves)
                if best_distance < 2.0 {
                    self.matches.push((si, ti, weight));
                }
            }
        }
    }

    /// Interpolate between presets
    fn interpolate(&self, source: &EqPreset, target: &EqPreset, t: f64) -> Vec<BandSnapshot> {
        let mut result = Vec::new();

        // Interpolate matched bands
        for &(si, ti, weight) in &self.matches {
            if si < source.bands.len() && ti < target.bands.len() {
                let sb = &source.bands[si];
                let tb = &target.bands[ti];

                // Logarithmic interpolation for frequency
                let freq = sb.freq * (tb.freq / sb.freq).powf(t);
                // Linear for gain
                let gain = sb.gain_db * (1.0 - t) + tb.gain_db * t;
                // Linear for Q
                let q = sb.q * (1.0 - t) + tb.q * t;

                result.push(BandSnapshot {
                    freq,
                    gain_db: gain,
                    q,
                    filter_type: if t < 0.5 { sb.filter_type } else { tb.filter_type },
                    enabled: sb.enabled || tb.enabled,
                });
            }
        }

        // Handle unmatched source bands (fade out)
        for (si, sb) in source.bands.iter().enumerate() {
            let is_matched = self.matches.iter().any(|&(s, _, _)| s == si);
            if !is_matched {
                result.push(BandSnapshot {
                    freq: sb.freq,
                    gain_db: sb.gain_db * (1.0 - t), // Fade out
                    q: sb.q,
                    filter_type: sb.filter_type,
                    enabled: sb.enabled,
                });
            }
        }

        // Handle unmatched target bands (fade in)
        for (ti, tb) in target.bands.iter().enumerate() {
            let is_matched = self.matches.iter().any(|&(_, t, _)| t == ti);
            if !is_matched {
                result.push(BandSnapshot {
                    freq: tb.freq,
                    gain_db: tb.gain_db * t, // Fade in
                    q: tb.q,
                    filter_type: tb.filter_type,
                    enabled: tb.enabled,
                });
            }
        }

        result
    }
}

// ============================================================================
// MORPHING EQ
// ============================================================================

/// EQ with preset morphing capabilities
pub struct MorphingEq {
    /// Current preset A
    preset_a: EqPreset,
    /// Current preset B
    preset_b: EqPreset,
    /// Morph position (0=A, 1=B)
    pub morph_position: f64,
    /// Target morph position
    target_morph: f64,
    /// Morph speed (samples to complete)
    pub morph_speed: f64,

    /// Morphable bands
    bands: Vec<MorphableBand>,
    /// Preset matcher
    matcher: PresetMatcher,

    /// A/B mode
    pub ab_mode: bool,
    /// Currently showing A (false=B)
    pub showing_a: bool,

    sample_rate: f64,
}

impl MorphingEq {
    pub fn new(sample_rate: f64) -> Self {
        let mut bands = Vec::with_capacity(PRESET_MAX_BANDS);
        for _ in 0..PRESET_MAX_BANDS {
            bands.push(MorphableBand::new(sample_rate));
        }

        Self {
            preset_a: EqPreset::default(),
            preset_b: EqPreset::default(),
            morph_position: 0.0,
            target_morph: 0.0,
            morph_speed: 0.001, // ~1 second at 48kHz
            bands,
            matcher: PresetMatcher::new(),
            ab_mode: false,
            showing_a: true,
            sample_rate,
        }
    }

    /// Load preset into slot A
    pub fn load_preset_a(&mut self, preset: EqPreset) {
        self.preset_a = preset;
        self.matcher.match_presets(&self.preset_a, &self.preset_b);

        if self.morph_position < 0.5 {
            self.apply_preset(&self.preset_a.clone());
        }
    }

    /// Load preset into slot B
    pub fn load_preset_b(&mut self, preset: EqPreset) {
        self.preset_b = preset;
        self.matcher.match_presets(&self.preset_a, &self.preset_b);

        if self.morph_position >= 0.5 {
            self.apply_preset(&self.preset_b.clone());
        }
    }

    /// Set morph position (0=A, 1=B)
    pub fn set_morph(&mut self, position: f64) {
        self.target_morph = position.clamp(0.0, 1.0);
    }

    /// Morph to A
    pub fn morph_to_a(&mut self) {
        self.target_morph = 0.0;
    }

    /// Morph to B
    pub fn morph_to_b(&mut self) {
        self.target_morph = 1.0;
    }

    /// Toggle A/B instantly
    pub fn toggle_ab(&mut self) {
        self.showing_a = !self.showing_a;
        let preset = if self.showing_a {
            self.preset_a.clone()
        } else {
            self.preset_b.clone()
        };
        self.apply_preset(&preset);
    }

    /// Capture current state as preset
    pub fn capture_preset(&self, name: &str) -> EqPreset {
        let mut preset = EqPreset::new(name);

        for band in &self.bands {
            if band.enabled && band.current_gain.abs() > 0.1 {
                preset.bands.push(BandSnapshot {
                    freq: band.current_freq,
                    gain_db: band.current_gain,
                    q: band.current_q,
                    filter_type: band.current_type,
                    enabled: true,
                });
            }
        }

        preset
    }

    fn apply_preset(&mut self, preset: &EqPreset) {
        // Disable all bands first
        for band in &mut self.bands {
            band.enabled = false;
        }

        // Apply preset bands
        for (i, snapshot) in preset.bands.iter().enumerate() {
            if i < self.bands.len() {
                self.bands[i].set_immediate(
                    snapshot.freq,
                    snapshot.gain_db,
                    snapshot.q,
                    snapshot.filter_type,
                );
                self.bands[i].enabled = snapshot.enabled;
            }
        }
    }

    fn update_morph(&mut self) {
        // Smooth morph toward target
        let diff = self.target_morph - self.morph_position;
        if diff.abs() > 0.0001 {
            self.morph_position += diff * self.morph_speed;

            // Get interpolated state
            let interpolated = self.matcher.interpolate(
                &self.preset_a,
                &self.preset_b,
                self.morph_position
            );

            // Apply to bands
            for (i, snapshot) in interpolated.iter().enumerate() {
                if i < self.bands.len() {
                    self.bands[i].set_target(
                        snapshot.freq,
                        snapshot.gain_db,
                        snapshot.q,
                        snapshot.filter_type,
                    );
                    self.bands[i].enabled = snapshot.enabled;
                }
            }

            // Disable unused bands
            for i in interpolated.len()..self.bands.len() {
                self.bands[i].enabled = false;
            }
        }

        // Update all band smoothing
        for band in &mut self.bands {
            band.update();
        }
    }

    /// Get current morph position
    pub fn get_morph_position(&self) -> f64 {
        self.morph_position
    }

    /// Get magnitude curve for current state
    pub fn get_magnitude_curve(&self, num_points: usize) -> Vec<f64> {
        (0..num_points).map(|i| {
            let t = i as f64 / (num_points - 1) as f64;
            let freq = 20.0 * (1000.0_f64).powf(t);

            let mut total_db = 0.0;

            for band in &self.bands {
                if !band.enabled || band.current_gain.abs() < 0.01 {
                    continue;
                }

                // Approximate band contribution
                let ratio = freq / band.current_freq;
                let q = band.current_q;

                match band.current_type {
                    MorphFilterType::Bell => {
                        let denom = (1.0 - ratio * ratio).powi(2) + (ratio / q).powi(2);
                        total_db += band.current_gain / denom.sqrt();
                    }
                    MorphFilterType::LowShelf => {
                        if freq < band.current_freq {
                            let t = (freq / band.current_freq).log2() / 2.0;
                            total_db += band.current_gain * (1.0 + t.max(-1.0));
                        }
                    }
                    MorphFilterType::HighShelf => {
                        if freq > band.current_freq {
                            let t = (band.current_freq / freq).log2() / 2.0;
                            total_db += band.current_gain * (1.0 + t.max(-1.0));
                        }
                    }
                    _ => {}
                }
            }

            total_db
        }).collect()
    }

    /// Number of active bands
    pub fn num_active_bands(&self) -> usize {
        self.bands.iter().filter(|b| b.enabled).count()
    }
}

impl Processor for MorphingEq {
    fn reset(&mut self) {
        for band in &mut self.bands {
            band.reset();
        }
    }

    fn latency(&self) -> usize {
        0
    }
}

impl StereoProcessor for MorphingEq {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Update morphing state
        self.update_morph();

        // Process through all active bands
        let (mut l, mut r) = (left, right);

        for band in &mut self.bands {
            (l, r) = band.process(l, r);
        }

        (l, r)
    }
}

// ============================================================================
// PRESET LIBRARY
// ============================================================================

/// Common EQ presets
pub mod presets {
    use super::*;

    /// Vocal presence boost
    pub fn vocal_presence() -> EqPreset {
        let mut p = EqPreset::new("Vocal Presence");
        p.add_band(80.0, -3.0, 0.7, MorphFilterType::LowShelf);
        p.add_band(200.0, -2.0, 2.0, MorphFilterType::Bell);
        p.add_band(3000.0, 3.0, 1.5, MorphFilterType::Bell);
        p.add_band(10000.0, 2.0, 0.7, MorphFilterType::HighShelf);
        p
    }

    /// Bass enhancement
    pub fn bass_boost() -> EqPreset {
        let mut p = EqPreset::new("Bass Boost");
        p.add_band(60.0, 4.0, 0.8, MorphFilterType::LowShelf);
        p.add_band(120.0, 2.0, 1.5, MorphFilterType::Bell);
        p.add_band(250.0, -2.0, 2.0, MorphFilterType::Bell);
        p
    }

    /// Bright and airy
    pub fn bright_air() -> EqPreset {
        let mut p = EqPreset::new("Bright Air");
        p.add_band(8000.0, 3.0, 0.7, MorphFilterType::HighShelf);
        p.add_band(12000.0, 2.0, 1.0, MorphFilterType::Bell);
        p.add_band(250.0, -1.5, 1.0, MorphFilterType::Bell);
        p
    }

    /// Telephone effect
    pub fn telephone() -> EqPreset {
        let mut p = EqPreset::new("Telephone");
        p.add_band(300.0, 0.0, 0.7, MorphFilterType::LowCut);
        p.add_band(3000.0, 0.0, 0.7, MorphFilterType::HighCut);
        p.add_band(1000.0, 3.0, 1.0, MorphFilterType::Bell);
        p
    }

    /// Flat/bypass
    pub fn flat() -> EqPreset {
        EqPreset::new("Flat")
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preset_creation() {
        let preset = presets::vocal_presence();
        assert_eq!(preset.bands.len(), 4);
    }

    #[test]
    fn test_morphing() {
        let mut eq = MorphingEq::new(48000.0);

        eq.load_preset_a(presets::flat());
        eq.load_preset_b(presets::bass_boost());

        eq.set_morph(0.5);

        // Process some samples
        for _ in 0..1000 {
            eq.process_sample(1.0, 1.0);
        }

        assert!(eq.morph_position > 0.0);
    }

    #[test]
    fn test_ab_toggle() {
        let mut eq = MorphingEq::new(48000.0);

        eq.load_preset_a(presets::flat());
        eq.load_preset_b(presets::bass_boost());

        assert!(eq.showing_a);
        eq.toggle_ab();
        assert!(!eq.showing_a);
    }
}
