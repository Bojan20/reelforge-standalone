//! Advanced Loudness Metering
//!
//! Beyond ITU-R BS.1770-4:
//! - Zwicker loudness model (ISO 532-1)
//! - Specific loudness (critical bands)
//! - Sharpness
//! - Roughness
//! - Fluctuation strength
//!
//! These psychoacoustic metrics provide deeper insight than LUFS alone.

use rf_core::Sample;
use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// CRITICAL BANDS (BARK SCALE)
// ═══════════════════════════════════════════════════════════════════════════════

/// Number of critical bands (0-24 Bark)
pub const NUM_BARK_BANDS: usize = 24;

/// Critical band center frequencies (Hz)
pub const BARK_CENTERS: [f64; NUM_BARK_BANDS] = [
    50.0, 150.0, 250.0, 350.0, 450.0, 570.0, 700.0, 840.0,
    1000.0, 1170.0, 1370.0, 1600.0, 1850.0, 2150.0, 2500.0, 2900.0,
    3400.0, 4000.0, 4800.0, 5800.0, 7000.0, 8500.0, 10500.0, 13500.0,
];

/// Critical band edges (Hz)
pub const BARK_EDGES: [f64; NUM_BARK_BANDS + 1] = [
    0.0, 100.0, 200.0, 300.0, 400.0, 510.0, 630.0, 770.0, 920.0,
    1080.0, 1270.0, 1480.0, 1720.0, 2000.0, 2320.0, 2700.0, 3150.0,
    3700.0, 4400.0, 5300.0, 6400.0, 7700.0, 9500.0, 12000.0, 15500.0,
];

/// Convert frequency to Bark scale
pub fn hz_to_bark(freq: f64) -> f64 {
    // Traunmüller formula
    let f = freq / 1000.0;
    26.81 * f / (1.0 + 1.96 * f) - 0.53
}

/// Convert Bark to frequency
pub fn bark_to_hz(bark: f64) -> f64 {
    // Inverse Traunmüller
    let z = bark + 0.53;
    1000.0 * z / (26.81 - z * 1.96)
}

// ═══════════════════════════════════════════════════════════════════════════════
// ZWICKER LOUDNESS MODEL (ISO 532-1)
// ═══════════════════════════════════════════════════════════════════════════════

/// Threshold in quiet (dB SPL) per critical band
const THRESHOLD_QUIET: [f64; NUM_BARK_BANDS] = [
    25.0, 15.0, 10.0, 7.0, 5.0, 4.0, 3.0, 3.0,
    3.0, 3.0, 3.0, 3.0, 3.0, 4.0, 5.0, 6.0,
    7.0, 9.0, 11.0, 14.0, 17.0, 21.0, 26.0, 32.0,
];

/// Zwicker loudness meter
///
/// Calculates psychoacoustic loudness in sones per ISO 532-1.
/// More accurate than LUFS for perceptual loudness.
#[derive(Debug, Clone)]
pub struct ZwickerLoudness {
    sample_rate: f64,
    /// Critical band energies
    band_energies: [f64; NUM_BARK_BANDS],
    /// Specific loudness (sones per Bark)
    specific_loudness: [f64; NUM_BARK_BANDS],
    /// Bandpass filter states
    bp_states: Vec<BandpassState>,
    /// Integration buffer
    integration_buffer: Vec<f64>,
    integration_pos: usize,
    integration_len: usize,
}

#[derive(Debug, Clone, Default)]
struct BandpassState {
    z1: f64,
    z2: f64,
    z3: f64,
    z4: f64,
}

impl ZwickerLoudness {
    pub fn new(sample_rate: f64) -> Self {
        // 200ms integration time per ISO 532-1
        let integration_len = (sample_rate * 0.2) as usize;

        Self {
            sample_rate,
            band_energies: [0.0; NUM_BARK_BANDS],
            specific_loudness: [0.0; NUM_BARK_BANDS],
            bp_states: vec![BandpassState::default(); NUM_BARK_BANDS],
            integration_buffer: vec![0.0; integration_len],
            integration_pos: 0,
            integration_len,
        }
    }

    /// Process mono sample
    pub fn process(&mut self, sample: Sample) {
        // Split into critical bands using bandpass filters
        for band in 0..NUM_BARK_BANDS {
            let f_low = BARK_EDGES[band];
            let f_high = BARK_EDGES[band + 1];
            let f_center = (f_low + f_high) / 2.0;
            let bw = f_high - f_low;

            // Butterworth bandpass
            let filtered = self.bandpass_filter(sample, band, f_center, bw);
            self.band_energies[band] += filtered * filtered;
        }

        // Integration
        self.integration_pos = (self.integration_pos + 1) % self.integration_len;

        if self.integration_pos == 0 {
            self.calculate_specific_loudness();
            // Reset band energies
            for e in &mut self.band_energies {
                *e = 0.0;
            }
        }
    }

    /// Bandpass filter for critical band
    fn bandpass_filter(&mut self, input: f64, band: usize, fc: f64, bw: f64) -> f64 {
        let state = &mut self.bp_states[band];
        let q = fc / bw;
        let w0 = 2.0 * PI * fc / self.sample_rate;
        let alpha = w0.sin() / (2.0 * q);

        // Coefficients for 2nd order bandpass
        let a0 = 1.0 + alpha;
        let b0 = alpha / a0;
        let b1 = 0.0;
        let b2 = -alpha / a0;
        let a1 = -2.0 * w0.cos() / a0;
        let a2 = (1.0 - alpha) / a0;

        // TDF-II
        let output = b0 * input + state.z1;
        state.z1 = b1 * input - a1 * output + state.z2;
        state.z2 = b2 * input - a2 * output;

        output
    }

    /// Calculate specific loudness from band energies
    fn calculate_specific_loudness(&mut self) {
        for band in 0..NUM_BARK_BANDS {
            // Convert energy to dB SPL (assuming calibrated input)
            let energy = self.band_energies[band] / self.integration_len as f64;
            let level_db = 10.0 * energy.max(1e-20).log10() + 94.0; // Reference: 94 dB SPL at full scale

            // Excitation level above threshold
            let excitation = (level_db - THRESHOLD_QUIET[band]).max(0.0);

            // Specific loudness calculation (simplified Zwicker model)
            // N' = 0.08 * (E_TQ / s) * [(0.5 + 0.5 * E / E_TQ)^0.23 - 1]
            // Simplified: N' ≈ (excitation / 40)^0.35 for typical levels
            self.specific_loudness[band] = if excitation > 0.0 {
                (excitation / 40.0).powf(0.35)
            } else {
                0.0
            };
        }
    }

    /// Get total loudness in sones
    pub fn loudness_sones(&self) -> f64 {
        // Sum specific loudness (integrate over Bark scale)
        // Each critical band is approximately 1 Bark wide
        self.specific_loudness.iter().sum::<f64>()
    }

    /// Get loudness in phons (equal loudness contour reference)
    pub fn loudness_phons(&self) -> f64 {
        let sones = self.loudness_sones();
        if sones <= 1.0 {
            40.0 * sones.powf(0.35)
        } else {
            40.0 + 10.0 * sones.log2()
        }
    }

    /// Get specific loudness per critical band
    pub fn specific_loudness(&self) -> &[f64; NUM_BARK_BANDS] {
        &self.specific_loudness
    }

    pub fn reset(&mut self) {
        self.band_energies = [0.0; NUM_BARK_BANDS];
        self.specific_loudness = [0.0; NUM_BARK_BANDS];
        for state in &mut self.bp_states {
            *state = BandpassState::default();
        }
        self.integration_buffer.fill(0.0);
        self.integration_pos = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARPNESS (Aures / Zwicker)
// ═══════════════════════════════════════════════════════════════════════════════

/// Sharpness meter (sensory pleasantness measure)
///
/// High sharpness = bright, piercing sound
/// Low sharpness = dull, warm sound
/// Unit: acum
pub struct SharpnessMeter {
    zwicker: ZwickerLoudness,
}

impl SharpnessMeter {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            zwicker: ZwickerLoudness::new(sample_rate),
        }
    }

    pub fn process(&mut self, sample: Sample) {
        self.zwicker.process(sample);
    }

    /// Calculate sharpness in acum
    pub fn sharpness(&self) -> f64 {
        let specific = self.zwicker.specific_loudness();
        let total_loudness = self.zwicker.loudness_sones();

        if total_loudness < 0.001 {
            return 0.0;
        }

        // Zwicker sharpness formula
        // S = 0.11 * ∫ N'(z) * g(z) * z dz / N
        // where g(z) is a weighting function that increases for high Bark numbers

        let mut numerator = 0.0;
        for band in 0..NUM_BARK_BANDS {
            let z = band as f64 + 0.5; // Bark position

            // Weighting function g(z)
            let g = if z < 15.8 {
                1.0
            } else {
                0.066 * (0.171 * z).exp()
            };

            numerator += specific[band] * g * z;
        }

        0.11 * numerator / total_loudness
    }

    /// Get sharpness assessment
    pub fn assessment(&self) -> &'static str {
        let s = self.sharpness();
        if s < 1.0 {
            "Dull/Warm"
        } else if s < 1.5 {
            "Neutral"
        } else if s < 2.0 {
            "Bright"
        } else if s < 2.5 {
            "Sharp"
        } else {
            "Very Sharp/Piercing"
        }
    }

    pub fn reset(&mut self) {
        self.zwicker.reset();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLUCTUATION STRENGTH
// ═══════════════════════════════════════════════════════════════════════════════

/// Fluctuation strength meter
///
/// Measures slow amplitude modulations (0.5 - 20 Hz).
/// Maximum at 4 Hz (syllabic rate of speech).
/// Unit: vacil
pub struct FluctuationMeter {
    sample_rate: f64,
    /// Envelope detector
    envelope: f64,
    envelope_attack: f64,
    envelope_release: f64,
    /// Modulation detector
    mod_buffer: Vec<f64>,
    mod_pos: usize,
    /// Previous envelope for modulation detection
    prev_envelope: f64,
}

impl FluctuationMeter {
    pub fn new(sample_rate: f64) -> Self {
        // Buffer for ~1 second to detect low-frequency modulation
        let mod_buffer_len = (sample_rate) as usize;

        Self {
            sample_rate,
            envelope: 0.0,
            envelope_attack: (-1.0 / (0.002 * sample_rate)).exp(),
            envelope_release: (-1.0 / (0.050 * sample_rate)).exp(),
            mod_buffer: vec![0.0; mod_buffer_len],
            mod_pos: 0,
            prev_envelope: 0.0,
        }
    }

    pub fn process(&mut self, sample: Sample) {
        let abs = sample.abs();

        // Envelope follower
        if abs > self.envelope {
            self.envelope = self.envelope_attack * (self.envelope - abs) + abs;
        } else {
            self.envelope = self.envelope_release * (self.envelope - abs) + abs;
        }

        // Store envelope rate of change
        let mod_signal = (self.envelope - self.prev_envelope).abs();
        self.mod_buffer[self.mod_pos] = mod_signal;
        self.mod_pos = (self.mod_pos + 1) % self.mod_buffer.len();
        self.prev_envelope = self.envelope;
    }

    /// Get fluctuation strength in vacil
    pub fn fluctuation_strength(&self) -> f64 {
        // Simple estimate based on modulation depth
        let mod_sum: f64 = self.mod_buffer.iter().sum();
        let mod_avg = mod_sum / self.mod_buffer.len() as f64;

        // Scale to vacil range (0-1 typically)
        // 1 vacil = fluctuation of 60 dB 1 kHz tone at 4 Hz modulation rate
        (mod_avg * 1000.0).min(2.0)
    }

    pub fn reset(&mut self) {
        self.envelope = 0.0;
        self.mod_buffer.fill(0.0);
        self.mod_pos = 0;
        self.prev_envelope = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ROUGHNESS
// ═══════════════════════════════════════════════════════════════════════════════

/// Roughness meter
///
/// Measures fast amplitude modulations (20 - 300 Hz).
/// Maximum around 70 Hz.
/// Unit: asper
pub struct RoughnessMeter {
    sample_rate: f64,
    /// Modulation detection per critical band
    band_mod: [f64; NUM_BARK_BANDS],
    /// Highpass state for modulation detection
    hp_z1: f64,
    hp_z2: f64,
    /// Lowpass for envelope
    lp_z: f64,
}

impl RoughnessMeter {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            band_mod: [0.0; NUM_BARK_BANDS],
            hp_z1: 0.0,
            hp_z2: 0.0,
            lp_z: 0.0,
        }
    }

    pub fn process(&mut self, sample: Sample) {
        // Simplified roughness detection using envelope modulation
        let abs = sample.abs();

        // Lowpass for envelope (10ms time constant)
        let lp_coeff = (-1.0 / (0.01 * self.sample_rate)).exp();
        self.lp_z = lp_coeff * self.lp_z + (1.0 - lp_coeff) * abs;

        // Highpass to extract modulation (20 Hz cutoff)
        let hp_fc = 20.0;
        let hp_w0 = 2.0 * PI * hp_fc / self.sample_rate;
        let hp_alpha = (1.0 - hp_w0.sin()) / hp_w0.cos();

        let hp_input = self.lp_z;
        let hp_output = hp_alpha * (self.hp_z1 + hp_input - self.hp_z2);
        self.hp_z2 = self.hp_z1;
        self.hp_z1 = hp_output;

        // Accumulate roughness (smoothed modulation energy)
        let mod_energy = hp_output.abs();
        for band in &mut self.band_mod {
            *band = 0.99 * *band + 0.01 * mod_energy;
        }
    }

    /// Get roughness in asper
    pub fn roughness(&self) -> f64 {
        let total: f64 = self.band_mod.iter().sum();
        // Scale to asper range (0-2 typical for complex signals)
        (total * 10.0).min(3.0)
    }

    /// Get roughness assessment
    pub fn assessment(&self) -> &'static str {
        let r = self.roughness();
        if r < 0.3 {
            "Smooth"
        } else if r < 0.7 {
            "Slightly Rough"
        } else if r < 1.2 {
            "Moderate Roughness"
        } else if r < 2.0 {
            "Rough"
        } else {
            "Very Rough/Harsh"
        }
    }

    pub fn reset(&mut self) {
        self.band_mod = [0.0; NUM_BARK_BANDS];
        self.hp_z1 = 0.0;
        self.hp_z2 = 0.0;
        self.lp_z = 0.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMBINED PSYCHOACOUSTIC METER
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete psychoacoustic analysis
///
/// Combines all metrics for full perceptual analysis:
/// - Loudness (sones/phons)
/// - Sharpness (acum)
/// - Fluctuation (vacil)
/// - Roughness (asper)
/// - Specific loudness pattern
pub struct PsychoacousticMeter {
    pub loudness: ZwickerLoudness,
    pub sharpness: SharpnessMeter,
    pub fluctuation: FluctuationMeter,
    pub roughness: RoughnessMeter,
}

impl PsychoacousticMeter {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            loudness: ZwickerLoudness::new(sample_rate),
            sharpness: SharpnessMeter::new(sample_rate),
            fluctuation: FluctuationMeter::new(sample_rate),
            roughness: RoughnessMeter::new(sample_rate),
        }
    }

    pub fn process(&mut self, sample: Sample) {
        self.loudness.process(sample);
        self.sharpness.process(sample);
        self.fluctuation.process(sample);
        self.roughness.process(sample);
    }

    pub fn process_block(&mut self, samples: &[Sample]) {
        for &s in samples {
            self.process(s);
        }
    }

    /// Get all metrics as a report
    pub fn report(&self) -> PsychoacousticReport {
        PsychoacousticReport {
            loudness_sones: self.loudness.loudness_sones(),
            loudness_phons: self.loudness.loudness_phons(),
            sharpness_acum: self.sharpness.sharpness(),
            fluctuation_vacil: self.fluctuation.fluctuation_strength(),
            roughness_asper: self.roughness.roughness(),
            sharpness_assessment: self.sharpness.assessment(),
            roughness_assessment: self.roughness.assessment(),
        }
    }

    pub fn reset(&mut self) {
        self.loudness.reset();
        self.sharpness.reset();
        self.fluctuation.reset();
        self.roughness.reset();
    }
}

/// Psychoacoustic analysis report
#[derive(Debug, Clone)]
pub struct PsychoacousticReport {
    pub loudness_sones: f64,
    pub loudness_phons: f64,
    pub sharpness_acum: f64,
    pub fluctuation_vacil: f64,
    pub roughness_asper: f64,
    pub sharpness_assessment: &'static str,
    pub roughness_assessment: &'static str,
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bark_conversion() {
        // 1000 Hz should be approximately 8.5 Bark
        let bark = hz_to_bark(1000.0);
        assert!(bark > 8.0 && bark < 9.0, "Bark at 1kHz: {}", bark);

        // Round-trip
        let hz = bark_to_hz(bark);
        assert!((hz - 1000.0).abs() < 10.0);
    }

    #[test]
    fn test_zwicker_loudness() {
        let mut meter = ZwickerLoudness::new(48000.0);

        // Process 1 second of 1kHz sine at -20 dBFS
        let amplitude = 10.0_f64.powf(-20.0 / 20.0);
        for i in 0..48000 {
            let sample = amplitude * (2.0 * PI * 1000.0 * i as f64 / 48000.0).sin();
            meter.process(sample);
        }

        // Should have measurable loudness
        let sones = meter.loudness_sones();
        assert!(sones > 0.0, "Loudness: {} sones", sones);
    }

    #[test]
    fn test_sharpness() {
        let mut meter = SharpnessMeter::new(48000.0);

        // High frequency tone should have higher sharpness
        for i in 0..48000 {
            let sample = 0.5 * (2.0 * PI * 8000.0 * i as f64 / 48000.0).sin();
            meter.process(sample);
        }

        let sharp = meter.sharpness();
        assert!(sharp > 1.5, "Sharpness: {} acum", sharp);
    }
}
