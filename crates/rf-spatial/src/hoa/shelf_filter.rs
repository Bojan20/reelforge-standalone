//! Per-order shelf / high-shelf filter for HOA
//!
//! Higher Ambisonic orders contain increasingly directional information that
//! is only audible above a frequency-dependent threshold.  Applying a gentle
//! high-shelf boost (or low-shelf cut) per order emulates the frequency-
//! dependent behaviour of the human head and improves perceived localisation.
//!
//! Implementation uses a cascade of 2nd-order Butterworth shelf filters,
//! one per spherical-harmonic degree `l`, in Transposed Direct-Form II
//! (TDF-II).  TDF-II is chosen because it has only two state variables per
//! biquad and favourable numerical properties for `f32` audio.
//!
//! The default cutoffs follow the "per-order shelf" rule of thumb:
//!   l=0 → bypass,  l=1 → 400 Hz,  l=2 → 800 Hz,  l=3 → 1.6 kHz,
//!   l=4 → 3.2 kHz, l=5 → 6.4 kHz, l=6 → 12.8 kHz, l=7 → 20 kHz
//!
//! Each shelf has +6 dB/octave rise above its cutoff, which approximately
//! compensates for the 6 dB/octave rolloff of directional cues at low
//! frequencies for that order.
//!
//! Reference:  Jérôme Daniel, "Spatial Sound Encoding Including Near Field
//!             Effect", AES 2001.

use super::AmbisonicOrder;

/// Coefficients for a single biquad section (TDF-II).
#[derive(Debug, Clone, Copy)]
struct BiquadCoefs {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
}

/// State for a single biquad section (TDF-II).
#[derive(Debug, Clone, Copy)]
struct BiquadState {
    z1: f32,
    z2: f32,
}

impl Default for BiquadState {
    fn default() -> Self {
        Self { z1: 0.0, z2: 0.0 }
    }
}

/// Per-degree high-shelf filter for Ambisonic signals.
///
/// One biquad is allocated for every SH degree `l` (not every channel).
/// All channels that share the same degree `l` are filtered identically.
pub struct HoaShelfFilter {
    /// Max SH degree (= order)
    max_l: usize,
    /// One biquad per degree `l`
    coefs: Vec<BiquadCoefs>,
    states: Vec<BiquadState>,
    /// Cutoff for each degree
    cutoffs: Vec<f32>,
    /// Sample rate
    sample_rate: u32,
    /// Global shelf gain in dB (applied to all l≥1)
    shelf_db: f32,
}

impl HoaShelfFilter {
    /// Create with default per-order cutoffs.
    pub fn new(order: AmbisonicOrder, sample_rate: u32) -> Self {
        let max_l = order.as_usize();
        let mut cutoffs = vec![0.0f32; max_l + 1];

        // Default cutoffs: 400·2^(l-1), clamped to Nyquist
        let nyquist = sample_rate as f32 / 2.0;
        for l in 1..=max_l {
            let fc = 400.0 * (2.0f32).powi((l - 1) as i32);
            cutoffs[l] = fc.min(nyquist * 0.99);
        }

        let mut filter = Self {
            max_l,
            coefs: vec![BiquadCoefs { b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0 }; max_l + 1],
            states: vec![BiquadState::default(); max_l + 1],
            cutoffs,
            sample_rate,
            shelf_db: 6.0,
        };

        filter.recompute_all_coefs();
        filter
    }

    /// Create with a uniform cutoff for all orders ≥ 1.
    pub fn with_cutoff(order: AmbisonicOrder, cutoff_hz: f32, sample_rate: u32) -> Self {
        let max_l = order.as_usize();
        let nyquist = sample_rate as f32 / 2.0;
        let fc = cutoff_hz.min(nyquist * 0.99).max(1.0);
        let cutoffs = vec![fc; max_l + 1];

        let mut filter = Self {
            max_l,
            coefs: vec![BiquadCoefs { b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0 }; max_l + 1],
            states: vec![BiquadState::default(); max_l + 1],
            cutoffs,
            sample_rate,
            shelf_db: 6.0,
        };

        filter.recompute_all_coefs();
        filter
    }

    /// Set shelf gain in dB (positive = boost highs).
    pub fn set_shelf_db(&mut self, db: f32) {
        self.shelf_db = db;
        self.recompute_all_coefs();
    }

    /// Set cutoff for a specific degree `l`.
    pub fn set_cutoff_for_degree(&mut self, l: usize, cutoff_hz: f32) {
        if l <= self.max_l {
            let nyquist = self.sample_rate as f32 / 2.0;
            self.cutoffs[l] = cutoff_hz.min(nyquist * 0.99).max(1.0);
            self.recompute_coef(l);
        }
    }

    /// Reset all filter states (e.g. after a seek or discontinuity).
    pub fn reset(&mut self) {
        for s in &mut self.states {
            s.z1 = 0.0;
            s.z2 = 0.0;
        }
    }

    /// Process a single sample frame.
    ///
    /// `input` and `output` must have the same length (number of Ambisonic
    /// channels).  Channel `c` is filtered by the biquad belonging to its
    /// SH degree `l`.
    pub fn process_frame(&mut self, input: &[f32], output: &mut [f32]) {
        assert_eq!(input.len(), output.len());
        for (ch, (&x, y)) in input.iter().zip(output.iter_mut()).enumerate() {
            let (l, _m) = super::acn_to_order_degree(ch);
            let l_usize = l as usize;
            if l_usize == 0 || l_usize > self.max_l {
                *y = x;
                continue;
            }
            *y = Self::process_biquad(x, &self.coefs[l_usize], &mut self.states[l_usize]);
        }
    }

    /// Process an entire block of interleaved or planar samples.
    ///
    /// `channels` is planar: `channels[ch][sample]`.
    pub fn process_block(&mut self, channels: &mut [Vec<f32>]) {
        for ch in 0..channels.len() {
            let (l, _m) = super::acn_to_order_degree(ch);
            let l_usize = l as usize;
            if l_usize == 0 || l_usize > self.max_l {
                continue;
            }
            let coef = self.coefs[l_usize];
            let state = &mut self.states[l_usize];
            for s in &mut channels[ch] {
                *s = Self::process_biquad(*s, &coef, state);
            }
        }
    }

    // ------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------

    fn recompute_all_coefs(&mut self) {
        for l in 0..=self.max_l {
            self.recompute_coef(l);
        }
    }

    fn recompute_coef(&mut self, l: usize) {
        if l == 0 {
            // Bypass for W
            self.coefs[l] = BiquadCoefs {
                b0: 1.0,
                b1: 0.0,
                b2: 0.0,
                a1: 0.0,
                a2: 0.0,
            };
            return;
        }

        let fc = self.cutoffs[l];
        let sr = self.sample_rate as f32;
        let gain = 10.0_f32.powf(self.shelf_db / 20.0);

        self.coefs[l] = Self::high_shelf_coefs(fc, sr, gain);
    }

    /// 2nd-order Butterworth-inspired high-shelf.
    ///
    /// Derived from the standard Audio EQ Cookbook (RBJ) shelf equations
    /// with Q = 1/√2 for maximally-flat pass-band.
    fn high_shelf_coefs(fc: f32, sr: f32, gain: f32) -> BiquadCoefs {
        let w0 = 2.0 * std::f32::consts::PI * fc / sr;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let q = std::f32::consts::FRAC_1_SQRT_2; // Q = 1/√2
        let alpha = sin_w0 / (2.0 * q);

        let sqrt_gain = gain.sqrt();
        let a = (gain + 1.0) + (gain - 1.0) * cos_w0 + 2.0 * sqrt_gain * alpha;

        let b0 = gain * ((gain + 1.0) - (gain - 1.0) * cos_w0 + 2.0 * sqrt_gain * alpha) / a;
        let b1 = 2.0 * gain * ((gain - 1.0) - (gain + 1.0) * cos_w0) / a;
        let b2 = gain * ((gain + 1.0) - (gain - 1.0) * cos_w0 - 2.0 * sqrt_gain * alpha) / a;
        let a1 = -2.0 * ((gain - 1.0) + (gain + 1.0) * cos_w0) / a;
        let a2 = ((gain + 1.0) + (gain - 1.0) * cos_w0 - 2.0 * sqrt_gain * alpha) / a;

        BiquadCoefs { b0, b1, b2, a1, a2 }
    }

    /// TDF-II biquad tick.
    #[inline]
    fn process_biquad(x: f32, c: &BiquadCoefs, s: &mut BiquadState) -> f32 {
        let y = c.b0 * x + s.z1;
        s.z1 = c.b1 * x - c.a1 * y + s.z2;
        s.z2 = c.b2 * x - c.a2 * y;
        y
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shelf_filter_creation() {
        let f = HoaShelfFilter::new(AmbisonicOrder::Third, 48000);
        assert_eq!(f.max_l, 3);
    }

    #[test]
    fn test_shelf_dc_response_l0_unchanged() {
        let mut f = HoaShelfFilter::new(AmbisonicOrder::Third, 48000);
        let mut out = [0.0f32; 4];
        // DC input on W (ch 0) should pass through unchanged
        f.process_frame(&[1.0, 0.0, 0.0, 0.0], &mut out);
        // Allow a few samples for any tiny numerical noise
        assert!((out[0] - 1.0).abs() < 1e-4, "W channel DC leaked: {}", out[0]);
    }

    #[test]
    fn test_shelf_energy_preserved_at_high_freq() {
        // At high frequencies the shelf should be near unity (bypass)
        // We simulate a high-freq sinusoid (10 kHz @ 48 kHz) on l=1
        let sr = 48000;
        let mut f = HoaShelfFilter::with_cutoff(AmbisonicOrder::First, 400.0, sr);
        f.set_shelf_db(0.0); // 0 dB = bypass

        let mut out = [0.0f32; 4];
        let mut max_out = 0.0f32;
        for i in 0..sr {
            let t = i as f32 / sr as f32;
            let sample = (2.0 * std::f32::consts::PI * 10000.0 * t).sin();
            f.process_frame(&[0.0, sample, 0.0, 0.0], &mut out);
            max_out = max_out.max(out[1].abs());
        }
        // With 0 dB shelf gain, output should be ≈ input (within a few %)
        assert!((max_out - 1.0).abs() < 0.05, "max_out = {}", max_out);
    }

    #[test]
    fn test_reset_clears_state() {
        let mut f = HoaShelfFilter::new(AmbisonicOrder::First, 48000);
        let mut out = [0.0f32; 4];
        f.process_frame(&[1.0, 1.0, 1.0, 1.0], &mut out);
        f.reset();
        for s in &f.states {
            assert_eq!(s.z1, 0.0);
            assert_eq!(s.z2, 0.0);
        }
    }
}
