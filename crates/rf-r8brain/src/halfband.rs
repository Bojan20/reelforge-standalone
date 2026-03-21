//! Half-Band Up/Downsampler — Efficient 2x sample rate change
//!
//! Half-band filters exploit the property that every other FIR coefficient
//! is exactly zero (except the center), reducing computation by ~4x vs
//! standard FIR. Combined with polyphase decomposition, this gives ~8x
//! efficiency for 2x rate change.
//!
//! Cascading multiple stages handles 4x, 8x, 16x... rate changes:
//! - 4x = 2x → 2x (each stage uses different filter steepness)
//! - 8x = 2x → 2x → 2x

/// Maximum half-band filter taps (from r8brain's steepest filter)
const MAX_HB_TAPS: usize = 14;

/// Ring buffer size for upsampler (must be power of 2, > 2 * MAX_HB_TAPS)
const UP_BUF_LEN: usize = 512;
const UP_BUF_MASK: usize = UP_BUF_LEN - 1;

/// Ring buffer size for downsampler (must be power of 2)
const DOWN_BUF_LEN: usize = 1024;
const DOWN_BUF_MASK: usize = DOWN_BUF_LEN - 1;

/// Half-band filter coefficient sets organized by steepness.
/// Steeper filters are used for first stages (closest to Nyquist),
/// gentler filters for later stages (more headroom).
///
/// Each set: (taps, coefficients[])
/// Coefficients are for the odd polyphase branch only.
/// Generated from r8brain's CDSPHBUpsampler.inc
pub const HB_FILTERS: &[HBFilterDef] = &[
    // Steepness 0 (steepest) — for 4x resampling first stage
    HBFilterDef { taps: 6, coeffs: [
        6.2187202340480707e-001, -1.7132842113816371e-001,
        6.9019169178765674e-002, -2.5799728312695277e-002,
        7.4880112525741666e-003, -1.2844465869952567e-003,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ]},
    // Steepness 1 — for 8x second stage
    HBFilterDef { taps: 4, coeffs: [
        5.8939775673538860e-001, -1.1537950318498112e-001,
        2.6561022092498659e-002, -3.5805507014023868e-003,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ]},
    // Steepness 2 — for 16x third stage
    HBFilterDef { taps: 3, coeffs: [
        5.6445693872997866e-001, -8.2858500244839564e-002,
        1.1593400520159030e-002, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ]},
    // Steepness 3 — for 32x fourth stage
    HBFilterDef { taps: 2, coeffs: [
        5.4031379609498065e-001, -5.3905001525498844e-002,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ]},
    // Steepness 4 — for 64x fifth stage
    HBFilterDef { taps: 2, coeffs: [
        5.2668548254498456e-001, -3.4227248541487383e-002,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ]},
    // Steepness 5 — for 128x sixth stage
    HBFilterDef { taps: 1, coeffs: [
        5.1388327466812880e-001, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ]},
];

/// Half-band filter definition
pub struct HBFilterDef {
    /// Number of taps (non-zero coefficients in odd branch)
    pub taps: usize,
    /// Coefficients for odd polyphase branch (padded to MAX_HB_TAPS)
    pub coeffs: [f64; MAX_HB_TAPS],
}

/// Half-band 2x upsampler.
///
/// For each input sample, produces 2 output samples:
/// - Even output: direct copy of input
/// - Odd output: convolution with half-band filter (symmetric taps)
///
/// Ring buffer + polyphase decomposition — zero allocation in audio path.
pub struct HBUpsampler {
    buf: [f64; UP_BUF_LEN + MAX_HB_TAPS * 2],
    flt: [f64; MAX_HB_TAPS],
    taps: usize,
    write_pos: usize,
}

impl HBUpsampler {
    /// Create new upsampler with given steepness index (0 = steepest)
    pub fn new(steepness: usize) -> Self {
        let def = &HB_FILTERS[steepness.min(HB_FILTERS.len() - 1)];
        let mut flt = [0.0f64; MAX_HB_TAPS];
        flt[..def.taps].copy_from_slice(&def.coeffs[..def.taps]);

        Self {
            buf: [0.0; UP_BUF_LEN + MAX_HB_TAPS * 2],
            flt,
            taps: def.taps,
            write_pos: MAX_HB_TAPS,
        }
    }

    /// Process a block of input samples, producing 2x output.
    ///
    /// `input`: input samples
    /// `output`: output buffer (must be 2× input length)
    ///
    /// Zero-allocation.
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        debug_assert!(output.len() >= input.len() * 2);

        for (i, &sample) in input.iter().enumerate() {
            // Write to ring buffer
            self.buf[self.write_pos] = sample;
            // Mirror for negative indexing
            if self.write_pos < MAX_HB_TAPS * 2 {
                self.buf[UP_BUF_LEN + self.write_pos] = sample;
            }

            let rp = self.write_pos;

            // Even output: direct copy
            output[i * 2] = self.buf[rp];

            // Odd output: symmetric half-band convolution
            let mut odd = 0.0;
            for k in 0..self.taps {
                let left_idx = rp.wrapping_sub(2 * k) & UP_BUF_MASK;
                let right_idx = (rp + 2 * k + 1) & UP_BUF_MASK;
                odd += self.flt[k] * (self.buf[right_idx] + self.buf[left_idx]);
            }
            output[i * 2 + 1] = odd;

            self.write_pos = (self.write_pos + 1) & UP_BUF_MASK;
        }
    }

    /// Reset internal state (silence the ring buffer)
    pub fn reset(&mut self) {
        self.buf = [0.0; UP_BUF_LEN + MAX_HB_TAPS * 2];
        self.write_pos = MAX_HB_TAPS;
    }

    /// Latency in output samples
    pub fn latency(&self) -> usize {
        self.taps
    }
}

/// Half-band 2x downsampler.
///
/// For every 2 input samples, produces 1 output sample.
/// Uses two ring buffers (even/odd decomposition).
///
/// Output has 2.0 gain — caller must scale by 0.5 if needed.
pub struct HBDownsampler {
    buf_even: [f64; DOWN_BUF_LEN + MAX_HB_TAPS * 2],
    buf_odd: [f64; DOWN_BUF_LEN + MAX_HB_TAPS * 2],
    flt: [f64; MAX_HB_TAPS],
    taps: usize,
    write_pos: usize,
    input_phase: bool, // false = expecting even sample, true = expecting odd
}

impl HBDownsampler {
    /// Create new downsampler with given steepness index
    pub fn new(steepness: usize) -> Self {
        let def = &HB_FILTERS[steepness.min(HB_FILTERS.len() - 1)];
        let mut flt = [0.0f64; MAX_HB_TAPS];
        flt[..def.taps].copy_from_slice(&def.coeffs[..def.taps]);

        Self {
            buf_even: [0.0; DOWN_BUF_LEN + MAX_HB_TAPS * 2],
            buf_odd: [0.0; DOWN_BUF_LEN + MAX_HB_TAPS * 2],
            flt,
            taps: def.taps,
            write_pos: MAX_HB_TAPS,
            input_phase: false,
        }
    }

    /// Process a block of input samples (2x oversampled), producing 1x output.
    ///
    /// `input`: input samples (length must be even)
    /// `output`: output buffer (must be input.len() / 2)
    ///
    /// Output has 2.0 gain (matches r8brain convention).
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        debug_assert!(input.len() % 2 == 0);
        debug_assert!(output.len() >= input.len() / 2);

        let pairs = input.len() / 2;
        for i in 0..pairs {
            let even = input[i * 2];
            let odd = input[i * 2 + 1];

            // Write even sample to even buffer
            self.buf_even[self.write_pos] = even;
            if self.write_pos < MAX_HB_TAPS * 2 {
                self.buf_even[DOWN_BUF_LEN + self.write_pos] = even;
            }

            // Write odd sample to odd buffer
            self.buf_odd[self.write_pos] = odd;
            if self.write_pos < MAX_HB_TAPS * 2 {
                self.buf_odd[DOWN_BUF_LEN + self.write_pos] = odd;
            }

            let rp = self.write_pos;

            // Output: center (even) + filtered (odd)
            let mut out = self.buf_even[rp];
            for k in 0..self.taps {
                let left_idx = rp.wrapping_sub(2 * k) & DOWN_BUF_MASK;
                let right_idx = (rp + 2 * k + 1) & DOWN_BUF_MASK;
                out += self.flt[k] * (self.buf_odd[right_idx] + self.buf_odd[left_idx]);
            }
            output[i] = out; // 2.0 gain (r8brain convention)

            self.write_pos = (self.write_pos + 1) & DOWN_BUF_MASK;
        }
    }

    /// Reset internal state
    pub fn reset(&mut self) {
        self.buf_even = [0.0; DOWN_BUF_LEN + MAX_HB_TAPS * 2];
        self.buf_odd = [0.0; DOWN_BUF_LEN + MAX_HB_TAPS * 2];
        self.write_pos = MAX_HB_TAPS;
        self.input_phase = false;
    }

    /// Latency in input samples
    pub fn latency(&self) -> usize {
        self.taps * 2
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_upsampler_creates() {
        let up = HBUpsampler::new(0);
        assert_eq!(up.taps, 6);
    }

    #[test]
    fn test_upsampler_dc() {
        // DC input (all 1.0) should produce all ~1.0 output
        let mut up = HBUpsampler::new(0);
        let input = [1.0f64; 256];
        let mut output = [0.0f64; 512];
        up.process(&input, &mut output);

        // Skip first few samples (filter settling)
        for &s in &output[20..] {
            assert!((s - 1.0).abs() < 0.05, "DC preservation failed: {s}");
        }
    }

    #[test]
    fn test_downsampler_creates() {
        let down = HBDownsampler::new(0);
        assert_eq!(down.taps, 6);
    }

    #[test]
    fn test_updown_roundtrip() {
        // Upsample then downsample should approximate identity
        let mut up = HBUpsampler::new(0);
        let mut down = HBDownsampler::new(0);

        let input = [1.0f64; 256];
        let mut mid = [0.0f64; 512];
        let mut output = [0.0f64; 256];

        up.process(&input, &mut mid);
        down.process(&mid, &mut output);

        // Scale by 0.5 (downsampler has 2.0 gain)
        for s in &mut output {
            *s *= 0.5;
        }

        // After settling, should be close to input
        for &s in &output[30..] {
            assert!((s - 1.0).abs() < 0.1, "Roundtrip DC failed: {s}");
        }
    }

    #[test]
    fn test_all_steepness_levels() {
        for i in 0..HB_FILTERS.len() {
            let up = HBUpsampler::new(i);
            assert!(up.taps > 0 && up.taps <= MAX_HB_TAPS);
        }
    }
}
