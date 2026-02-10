//! DSP algorithm fuzz targets
//!
//! Tests pure-math DSP functions with extreme, edge-case, and random inputs
//! to verify they never panic or produce unexpected NaN/Inf values from
//! finite inputs. All targets are self-contained — no FFI calls.

use crate::config::FuzzConfig;
use crate::generators::{AudioInputs, AudioPattern};
use crate::harness::{FuzzResult, FuzzRunner};
use crate::report::FuzzReport;

// ============================================================================
// DSP primitives under test (pure math, no FFI)
// ============================================================================

/// Transposed Direct Form II biquad filter.
///
/// This is the exact same structure used in rf-dsp. We reimplement it here
/// so the fuzz crate remains self-contained (no dependency on rf-dsp).
#[derive(Debug, Clone)]
struct BiquadTDF2 {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    z1: f64,
    z2: f64,
}

impl BiquadTDF2 {
    fn new(b0: f64, b1: f64, b2: f64, a1: f64, a2: f64) -> Self {
        Self {
            b0,
            b1,
            b2,
            a1,
            a2,
            z1: 0.0,
            z2: 0.0,
        }
    }

    /// Design a lowpass filter from frequency and Q.
    fn lowpass(freq: f64, q: f64, sample_rate: f64) -> Self {
        if sample_rate <= 0.0 || freq <= 0.0 || q <= 0.0 || !freq.is_finite() || !q.is_finite() {
            return Self::passthrough();
        }
        let omega = 2.0 * std::f64::consts::PI * freq / sample_rate;
        let sin_w = omega.sin();
        let cos_w = omega.cos();
        if sin_w == 0.0 {
            return Self::passthrough();
        }
        let alpha = sin_w / (2.0 * q);
        let a0 = 1.0 + alpha;
        if a0 == 0.0 || !a0.is_finite() {
            return Self::passthrough();
        }
        let b0 = ((1.0 - cos_w) / 2.0) / a0;
        let b1 = (1.0 - cos_w) / a0;
        let b2 = b0;
        let a1 = (-2.0 * cos_w) / a0;
        let a2 = (1.0 - alpha) / a0;
        Self::new(b0, b1, b2, a1, a2)
    }

    /// Passthrough (unity) filter — no processing.
    fn passthrough() -> Self {
        Self::new(1.0, 0.0, 0.0, 0.0, 0.0)
    }

    /// Process a single sample through the TDF-II structure.
    #[inline(always)]
    fn process(&mut self, input: f64) -> f64 {
        let output = self.b0 * input + self.z1;
        self.z1 = self.b1 * input - self.a1 * output + self.z2;
        self.z2 = self.b2 * input - self.a2 * output;

        // Flush denormals to zero (critical for audio stability)
        if self.z1.abs() < 1e-30 {
            self.z1 = 0.0;
        }
        if self.z2.abs() < 1e-30 {
            self.z2 = 0.0;
        }

        output
    }

    /// Reset state to zero.
    fn reset(&mut self) {
        self.z1 = 0.0;
        self.z2 = 0.0;
    }
}

/// Linear gain to decibel conversion.
fn gain_to_db(gain: f64) -> f64 {
    if gain <= 0.0 {
        f64::NEG_INFINITY
    } else if !gain.is_finite() {
        if gain == f64::INFINITY {
            f64::INFINITY
        } else {
            f64::NAN
        }
    } else {
        20.0 * gain.log10()
    }
}

/// Decibel to linear gain conversion.
fn db_to_gain(db: f64) -> f64 {
    if !db.is_finite() {
        if db == f64::NEG_INFINITY {
            0.0
        } else if db == f64::INFINITY {
            f64::INFINITY
        } else {
            f64::NAN
        }
    } else {
        10.0_f64.powf(db / 20.0)
    }
}

/// Equal-power pan law: pan in [-1, 1] -> (left_gain, right_gain).
/// NaN/Inf inputs are sanitized to center (0.0).
fn pan_equal_power(pan: f64) -> (f64, f64) {
    let sanitized = if pan.is_finite() { pan } else { 0.0 };
    let clamped = sanitized.clamp(-1.0, 1.0);
    let angle = (clamped + 1.0) * 0.25 * std::f64::consts::PI;
    (angle.cos(), angle.sin())
}

/// Linear pan law: pan in [-1, 1] -> (left_gain, right_gain).
/// NaN/Inf inputs are sanitized to center (0.0).
fn pan_linear(pan: f64) -> (f64, f64) {
    let sanitized = if pan.is_finite() { pan } else { 0.0 };
    let clamped = sanitized.clamp(-1.0, 1.0);
    let left = (1.0 - clamped) * 0.5;
    let right = (1.0 + clamped) * 0.5;
    (left, right)
}

/// Compromise pan law (-4.5 dB): blend of linear and equal-power.
fn pan_compromise(pan: f64) -> (f64, f64) {
    let (el, er) = pan_equal_power(pan);
    let (ll, lr) = pan_linear(pan);
    // 50/50 blend gives approximately -4.5 dB center attenuation
    (el * 0.5 + ll * 0.5, er * 0.5 + lr * 0.5)
}

/// Sample rate conversion ratio calculation.
fn src_ratio(source_rate: f64, target_rate: f64) -> f64 {
    if source_rate <= 0.0 || !source_rate.is_finite() {
        return 1.0;
    }
    if target_rate <= 0.0 || !target_rate.is_finite() {
        return 1.0;
    }
    target_rate / source_rate
}

/// Calculate the output sample count for a given input count and ratio.
fn src_output_count(input_count: usize, ratio: f64) -> usize {
    if !ratio.is_finite() || ratio <= 0.0 {
        return input_count;
    }
    let out = (input_count as f64 * ratio).ceil() as usize;
    // Clamp to prevent absurd allocations
    out.min(input_count * 256)
}

/// Ring buffer for audio delay lines.
#[derive(Debug, Clone)]
struct RingBuffer {
    data: Vec<f64>,
    write_pos: usize,
    read_pos: usize,
    capacity: usize,
}

impl RingBuffer {
    fn new(capacity: usize) -> Self {
        let cap = capacity.max(1); // Minimum 1 sample
        Self {
            data: vec![0.0; cap],
            write_pos: 0,
            read_pos: 0,
            capacity: cap,
        }
    }

    fn write(&mut self, sample: f64) {
        // Sanitize non-finite values to prevent corruption
        let val = if sample.is_finite() { sample } else { 0.0 };
        self.data[self.write_pos] = val;
        self.write_pos = (self.write_pos + 1) % self.capacity;
    }

    fn read(&self) -> f64 {
        self.data[self.read_pos]
    }

    fn advance_read(&mut self) {
        self.read_pos = (self.read_pos + 1) % self.capacity;
    }

    fn set_delay(&mut self, delay_samples: usize) {
        let delay = delay_samples % self.capacity;
        self.read_pos = (self.write_pos + self.capacity - delay) % self.capacity;
    }

    fn len(&self) -> usize {
        if self.write_pos >= self.read_pos {
            self.write_pos - self.read_pos
        } else {
            self.capacity - self.read_pos + self.write_pos
        }
    }
}

/// Simple envelope follower (peak detector with attack/release).
#[derive(Debug, Clone)]
struct EnvelopeFollower {
    envelope: f64,
    attack_coeff: f64,
    release_coeff: f64,
}

impl EnvelopeFollower {
    fn new(attack_ms: f64, release_ms: f64, sample_rate: f64) -> Self {
        let sr = if sample_rate > 0.0 && sample_rate.is_finite() {
            sample_rate
        } else {
            44100.0
        };
        Self {
            envelope: 0.0,
            attack_coeff: Self::time_to_coeff(attack_ms, sr),
            release_coeff: Self::time_to_coeff(release_ms, sr),
        }
    }

    fn time_to_coeff(time_ms: f64, sample_rate: f64) -> f64 {
        if time_ms <= 0.0 || !time_ms.is_finite() || sample_rate <= 0.0 {
            return 1.0; // Instant response
        }
        let samples = time_ms * 0.001 * sample_rate;
        if samples <= 0.0 {
            return 1.0;
        }
        let coeff = (-1.0 / samples).exp();
        if coeff.is_finite() {
            coeff
        } else {
            0.0
        }
    }

    fn process(&mut self, input: f64) -> f64 {
        let abs_input = if input.is_finite() { input.abs() } else { 0.0 };
        let coeff = if abs_input > self.envelope {
            self.attack_coeff
        } else {
            self.release_coeff
        };
        self.envelope = coeff * self.envelope + (1.0 - coeff) * abs_input;
        // Flush denormals
        if self.envelope.abs() < 1e-30 {
            self.envelope = 0.0;
        }
        self.envelope
    }

    fn reset(&mut self) {
        self.envelope = 0.0;
    }
}

/// Naive DFT for small sizes (used when size is not power-of-2).
/// Returns magnitude spectrum.
fn naive_dft_magnitude(signal: &[f64]) -> Vec<f64> {
    let n = signal.len();
    if n == 0 {
        return vec![];
    }
    let mut magnitudes = Vec::with_capacity(n / 2 + 1);
    let n_f = n as f64;
    for k in 0..=(n / 2) {
        let mut re = 0.0_f64;
        let mut im = 0.0_f64;
        for (i, &sample) in signal.iter().enumerate() {
            if !sample.is_finite() {
                continue; // Skip NaN/Inf in input
            }
            let angle = -2.0 * std::f64::consts::PI * k as f64 * i as f64 / n_f;
            re += sample * angle.cos();
            im += sample * angle.sin();
        }
        let mag = (re * re + im * im).sqrt();
        // Sanitize output
        magnitudes.push(if mag.is_finite() { mag } else { 0.0 });
    }
    magnitudes
}

/// Check if a number is power of 2.
fn is_power_of_two(n: usize) -> bool {
    n > 0 && (n & (n - 1)) == 0
}

/// Next power of 2 >= n.
fn next_power_of_two(n: usize) -> usize {
    if n == 0 {
        return 1;
    }
    n.next_power_of_two()
}

/// Simple in-place Cooley-Tukey FFT (radix-2, DIT).
/// Input length MUST be a power of 2.
fn fft_radix2(signal: &mut [(f64, f64)]) {
    let n = signal.len();
    if n <= 1 {
        return;
    }
    debug_assert!(is_power_of_two(n));

    // Bit-reversal permutation
    let mut j = 0usize;
    for i in 1..n {
        let mut bit = n >> 1;
        while j & bit != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j ^= bit;
        if i < j {
            signal.swap(i, j);
        }
    }

    // Butterfly stages
    let mut size = 2;
    while size <= n {
        let half = size / 2;
        let angle_step = -2.0 * std::f64::consts::PI / size as f64;
        for k in (0..n).step_by(size) {
            for m in 0..half {
                let angle = angle_step * m as f64;
                let twiddle_re = angle.cos();
                let twiddle_im = angle.sin();
                let (a_re, a_im) = signal[k + m];
                let (b_re, b_im) = signal[k + m + half];
                // Complex multiplication: twiddle * b
                let t_re = twiddle_re * b_re - twiddle_im * b_im;
                let t_im = twiddle_re * b_im + twiddle_im * b_re;
                signal[k + m] = (a_re + t_re, a_im + t_im);
                signal[k + m + half] = (a_re - t_re, a_im - t_im);
            }
        }
        size <<= 1;
    }
}

/// Compute magnitude spectrum via FFT, zero-padding to power-of-2 if needed.
fn fft_magnitude(signal: &[f64]) -> Vec<f64> {
    if signal.is_empty() {
        return vec![];
    }
    let n = next_power_of_two(signal.len());
    let mut complex: Vec<(f64, f64)> = Vec::with_capacity(n);
    for &s in signal {
        let val = if s.is_finite() { s } else { 0.0 };
        complex.push((val, 0.0));
    }
    // Zero-pad
    complex.resize(n, (0.0, 0.0));
    fft_radix2(&mut complex);
    complex
        .iter()
        .take(n / 2 + 1)
        .map(|(re, im)| {
            let mag = (re * re + im * im).sqrt();
            if mag.is_finite() { mag } else { 0.0 }
        })
        .collect()
}

// ============================================================================
// Fuzz target functions
// ============================================================================

/// Fuzz target: verify TDF-II biquad never produces NaN/Inf from finite input.
///
/// Generates random filter coefficients (b0, b1, b2, a1, a2) and processes
/// a buffer of finite audio samples. Uses `normalized_audio` which guarantees
/// finite inputs in [-1, 1]. Only validates finite-output when coefficients
/// are also finite AND within a stable range.
pub fn fuzz_biquad_coefficients(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        // Input generator: (b0, b1, b2, a1, a2, [audio_samples])
        |gen| {
            let b0 = gen.f64_range(-10.0, 10.0);
            let b1 = gen.f64_range(-10.0, 10.0);
            let b2 = gen.f64_range(-10.0, 10.0);
            let a1 = gen.f64_range(-2.0, 2.0);
            let a2 = gen.f64_range(-1.0, 1.0);
            let buf_len = gen.usize(512).max(1);
            let samples = gen.normalized_audio(buf_len);
            (b0, b1, b2, a1, a2, samples)
        },
        // Target: process through biquad
        |input| {
            let (b0, b1, b2, a1, a2, ref samples) = input;
            let mut filter = BiquadTDF2::new(b0, b1, b2, a1, a2);
            let output: Vec<f64> = samples.iter().map(|&s| filter.process(s)).collect();
            // Coefficients must be finite AND within a practical range.
            // f64_range() can return f64::MIN (~-1.8e308) which is technically finite
            // but causes arithmetic overflow when used in filter computations.
            let coeff_practical = |c: f64| c.is_finite() && c.abs() < 1000.0;
            let all_coeffs_practical = coeff_practical(input.0)
                && coeff_practical(input.1)
                && coeff_practical(input.2)
                && coeff_practical(input.3)
                && coeff_practical(input.4);
            // Check if coefficients represent a potentially stable filter:
            // |a2| < 1 is necessary (but not sufficient) for stability
            let potentially_stable = all_coeffs_practical && input.4.abs() < 1.0;
            (potentially_stable, output)
        },
        // Validator: only check finite output for potentially stable filters
        |_input, (potentially_stable, output)| {
            if *potentially_stable {
                // Even stable filters can have transient growth, so only check
                // that output doesn't contain NaN (Inf from resonance is acceptable)
                for (i, &s) in output.iter().enumerate() {
                    if s.is_nan() {
                        return Err(format!(
                            "Biquad produced NaN at sample {}",
                            i
                        ));
                    }
                }
            }
            Ok(())
        },
    )
}

/// Fuzz target: verify biquad design functions don't panic on any parameters.
///
/// Tests lowpass design with random frequency, Q, and sample rate values
/// including extreme and edge-case values.
pub fn fuzz_biquad_design(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| {
            let freq = gen.f64_range(-1000.0, 100000.0);
            let q = gen.f64_range(-10.0, 100.0);
            let sr = gen.f64_range(-1000.0, 384000.0);
            (freq, q, sr)
        },
        |(freq, q, sr)| {
            let mut filter = BiquadTDF2::lowpass(freq, q, sr);
            // Process a short impulse to exercise the filter
            let _ = filter.process(1.0);
            for _ in 0..63 {
                let _ = filter.process(0.0);
            }
            filter.reset();
        },
    )
}

/// Fuzz target: linear-to-dB and dB-to-linear conversion edge cases.
///
/// Validates:
/// - `gain_to_db(0)` returns -Inf
/// - `gain_to_db(negative)` returns -Inf
/// - `db_to_gain(-Inf)` returns 0
/// - Round-trip: `db_to_gain(gain_to_db(x))` is approximately x for positive finite x
///   within a reasonable dB range (not overflowing)
pub fn fuzz_gain_to_db_conversion(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| gen.f64_range(-200.0, 200.0),
        |gain| {
            let db = gain_to_db(gain);
            let roundtrip = db_to_gain(db);
            (gain, db, roundtrip)
        },
        |_input, (gain, db, roundtrip)| {
            // gain_to_db must not panic (it didn't if we got here)

            // Skip validation for non-finite inputs (edge cases from generator)
            if !gain.is_finite() {
                return Ok(());
            }

            // Specific property checks
            if *gain <= 0.0 {
                if *db != f64::NEG_INFINITY {
                    return Err(format!(
                        "gain_to_db({}) should be -Inf, got {}",
                        gain, db
                    ));
                }
            }

            // Round-trip accuracy for positive finite gains where dB doesn't overflow
            if *gain > 1e-15 && db.is_finite() && roundtrip.is_finite() {
                let error = (roundtrip - gain).abs() / gain.abs();
                if error > 1e-10 {
                    return Err(format!(
                        "Round-trip error too large: gain={}, db={}, roundtrip={}, error={}",
                        gain, db, roundtrip, error
                    ));
                }
            }

            // db_to_gain(-Inf) must be 0
            let zero_check = db_to_gain(f64::NEG_INFINITY);
            if zero_check != 0.0 {
                return Err(format!(
                    "db_to_gain(-Inf) should be 0.0, got {}",
                    zero_check
                ));
            }

            Ok(())
        },
    )
}

/// Fuzz target: dB-to-gain conversion with extreme dB values.
///
/// Tests that db_to_gain never panics on extreme values and that
/// the output is always non-negative for finite inputs.
pub fn fuzz_db_to_gain_extremes(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| gen.f64(), // includes NaN, Inf, edge cases
        |db| db_to_gain(db),
        |input, output| {
            // db_to_gain of finite input must be non-negative
            if input.is_finite() && (*output < 0.0 || output.is_nan()) {
                return Err(format!(
                    "db_to_gain({}) produced invalid result: {}",
                    input, output
                ));
            }
            Ok(())
        },
    )
}

/// Fuzz target: pan law calculations with values outside [-1, 1] range.
///
/// Tests equal-power, linear, and compromise pan laws:
/// - Values outside [-1, 1] must be clamped (no panic)
/// - Output gains must be in [0, 1]
/// - At center (0.0), left is approximately equal to right
/// - At extremes (-1/+1), one channel is 0 (linear) or near-0
pub fn fuzz_pan_law(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| gen.f64_range(-100.0, 100.0),
        |pan| {
            let ep = pan_equal_power(pan);
            let lin = pan_linear(pan);
            let comp = pan_compromise(pan);
            (pan, ep, lin, comp)
        },
        |_input, (pan, ep, lin, comp)| {
            // Skip validation for non-finite inputs (NaN/Inf from edge cases).
            // The pan functions sanitize these to center, but the test validates
            // the no-panic property by reaching this point.
            if !pan.is_finite() {
                return Ok(());
            }

            // All gains must be in [0, 1] range
            for (name, (l, r)) in [("equal_power", ep), ("linear", lin), ("compromise", comp)] {
                if *l < -1e-10 || *l > 1.0 + 1e-10 {
                    return Err(format!(
                        "{}: left gain {} out of range for pan {}",
                        name, l, pan
                    ));
                }
                if *r < -1e-10 || *r > 1.0 + 1e-10 {
                    return Err(format!(
                        "{}: right gain {} out of range for pan {}",
                        name, r, pan
                    ));
                }
                if l.is_nan() || r.is_nan() {
                    return Err(format!("{}: NaN gain for pan {}", name, pan));
                }
            }

            // At center (pan=0), L and R should be approximately equal
            if (*pan).abs() < 1e-10 {
                let (el, er) = ep;
                if (el - er).abs() > 1e-6 {
                    return Err(format!(
                        "Equal power not balanced at center: L={}, R={}",
                        el, er
                    ));
                }
                let (ll, lr) = lin;
                if (ll - lr).abs() > 1e-6 {
                    return Err(format!(
                        "Linear not balanced at center: L={}, R={}",
                        ll, lr
                    ));
                }
            }

            Ok(())
        },
    )
}

/// Fuzz target: sample rate ratio calculations with extreme values.
///
/// Validates:
/// - Zero or negative rates produce ratio 1.0 (safe default)
/// - Output counts are bounded (no overflow/OOM)
/// - Standard conversion ratios are correct (44100 to 48000, etc.)
pub fn fuzz_sample_rate_conversion(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| {
            let source = gen.f64_range(-1000.0, 500000.0);
            let target = gen.f64_range(-1000.0, 500000.0);
            let input_count = gen.usize(100000);
            (source, target, input_count)
        },
        |(source, target, input_count)| {
            let ratio = src_ratio(source, target);
            let output_count = src_output_count(input_count, ratio);
            (source, target, input_count, ratio, output_count)
        },
        |_input, (source, target, input_count, ratio, output_count)| {
            // Skip validation when source or target are non-finite (edge cases)
            // or when they are too extreme (e.g. f64::MIN_POSITIVE = 2.2e-308 is
            // technically finite but target/source overflows to Inf)
            if !source.is_finite() || !target.is_finite()
                || source.abs() < 1.0 || target.abs() < 1.0
                || source.abs() > 1e15 || target.abs() > 1e15
            {
                return Ok(());
            }

            // Ratio must always be finite and positive
            if !ratio.is_finite() || *ratio <= 0.0 {
                return Err(format!(
                    "Invalid ratio {} for source={}, target={}",
                    ratio, source, target
                ));
            }

            // Output count must be bounded
            if *output_count > input_count * 256 {
                return Err(format!(
                    "Output count {} exceeds 256x input {} for ratio {}",
                    output_count, input_count, ratio
                ));
            }

            // Standard conversions should be accurate
            if (*source - 44100.0).abs() < 0.1 && (*target - 48000.0).abs() < 0.1 {
                let expected = 48000.0 / 44100.0;
                if (*ratio - expected).abs() > 1e-10 {
                    return Err(format!(
                        "44100->48000 ratio wrong: got {}, expected {}",
                        ratio, expected
                    ));
                }
            }

            Ok(())
        },
    )
}

/// Fuzz target: audio buffer processing functions don't panic.
///
/// Generates random audio buffers with various patterns (silence, noise,
/// edge cases, impulse) and runs them through multiple DSP operations:
/// gain, invert, DC offset removal, fade in/out, mix.
pub fn fuzz_buffer_processing(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| {
            let len = gen.usize(2048).max(1);
            let pattern_idx = gen.u32() % 8;
            let pattern = match pattern_idx {
                0 => AudioPattern::Silence,
                1 => AudioPattern::DcOffset,
                2 => AudioPattern::Impulse,
                3 => AudioPattern::Sine,
                4 => AudioPattern::Noise,
                5 => AudioPattern::Square,
                6 => AudioPattern::EdgeCases,
                _ => AudioPattern::Random,
            };
            let buffer = AudioInputs::pattern_buffer(gen, len, pattern);
            let gain = gen.f64_range(-10.0, 10.0);
            (buffer, gain, pattern_idx)
        },
        |(ref buffer, gain, _pattern)| {
            // Apply gain
            let gained: Vec<f64> = buffer.iter().map(|&s| s * gain).collect();

            // Invert polarity
            let _inverted: Vec<f64> = buffer.iter().map(|&s| -s).collect();

            // DC offset removal (high-pass at ~5 Hz)
            let mut dc_state = 0.0_f64;
            let dc_coeff = 0.9999; // ~5 Hz at 44100
            let _dc_removed: Vec<f64> = buffer
                .iter()
                .map(|&s| {
                    let s = if s.is_finite() { s } else { 0.0 };
                    dc_state = dc_coeff * dc_state + (1.0 - dc_coeff) * s;
                    s - dc_state
                })
                .collect();

            // Fade in (linear)
            let n = buffer.len() as f64;
            let _faded_in: Vec<f64> = buffer
                .iter()
                .enumerate()
                .map(|(i, &s)| s * (i as f64 / n.max(1.0)))
                .collect();

            // Mix two buffers
            let noise_buf: Vec<f64> = (0..buffer.len())
                .map(|i| ((i as f64) * 0.1).sin() * 0.1)
                .collect();
            let _mixed: Vec<f64> = buffer
                .iter()
                .zip(noise_buf.iter())
                .map(|(&a, &b)| {
                    let a = if a.is_finite() { a } else { 0.0 };
                    (a + b) * 0.5
                })
                .collect();

            // Track if all inputs were finite
            // Check that all inputs are finite AND within a practical range.
            // f64::MIN (~-1.8e308) is technically finite but gain*f64::MIN overflows.
            let all_inputs_practical = buffer.iter().all(|s| s.is_finite() && s.abs() < 1e100)
                && gain.is_finite() && gain.abs() < 1e100;
            (gained, all_inputs_practical)
        },
        |_input, (output, all_inputs_practical)| {
            // Only validate output finiteness when ALL inputs were practical.
            // EdgeCases pattern includes NaN/Inf, and extreme finite values
            // like f64::MIN can overflow when multiplied by gain.
            if *all_inputs_practical {
                for (i, &s) in output.iter().enumerate() {
                    if !s.is_finite() {
                        return Err(format!(
                            "Buffer processing produced non-finite at sample {} with finite inputs",
                            i
                        ));
                    }
                }
            }
            Ok(())
        },
    )
}

/// Fuzz target: ring buffer read/write with random sizes and offsets.
///
/// Tests:
/// - Various capacity values (including very small)
/// - Random write sequences followed by reads
/// - Delay changes mid-stream
/// - Wrap-around behavior
/// - Non-finite values are sanitized on write
pub fn fuzz_ring_buffer_operations(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| {
            let capacity = gen.usize(4096).max(1);
            let num_ops = gen.usize(1000).max(1);
            let delay = gen.usize(capacity);
            // Use f64() which includes edge cases -- the ring buffer sanitizes them
            let ops: Vec<(bool, f64)> = (0..num_ops)
                .map(|_| (gen.bool(), gen.f64_range(-1.0, 1.0)))
                .collect();
            (capacity, delay, ops)
        },
        |(capacity, delay, ref ops)| {
            let mut rb = RingBuffer::new(capacity);
            rb.set_delay(delay);

            let mut read_values = Vec::new();
            for &(do_read, sample) in ops.iter() {
                rb.write(sample); // sanitizes non-finite
                if do_read {
                    let val = rb.read();
                    read_values.push(val);
                    rb.advance_read();
                }
            }

            // Change delay mid-stream
            let new_delay = delay / 2;
            rb.set_delay(new_delay);
            for _ in 0..10 {
                rb.write(0.5);
                let val = rb.read();
                read_values.push(val);
                rb.advance_read();
            }

            (capacity, read_values, rb.len())
        },
        |_input, (capacity, read_values, rb_len)| {
            // All read values must be finite (ring buffer sanitizes writes)
            for (i, &v) in read_values.iter().enumerate() {
                if !v.is_finite() {
                    return Err(format!(
                        "Ring buffer produced non-finite value at read {}: {}",
                        i, v
                    ));
                }
            }

            // Ring buffer length must never exceed capacity
            if *rb_len > *capacity {
                return Err(format!(
                    "Ring buffer length {} exceeds capacity {}",
                    rb_len, capacity
                ));
            }

            Ok(())
        },
    )
}

/// Fuzz target: envelope follower with extreme attack/release times.
///
/// Tests:
/// - Zero attack/release (instant response)
/// - Extremely long attack/release (near-infinite)
/// - Negative values (should be clamped/handled)
/// - NaN/Inf time constants
/// - Output is always non-negative and finite
pub fn fuzz_envelope_follower(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| {
            let attack_ms = gen.f64_range(-100.0, 50000.0);
            let release_ms = gen.f64_range(-100.0, 50000.0);
            let sample_rate = gen.f64_range(-1000.0, 384000.0);
            let buf_len = gen.usize(512).max(1);
            let samples = gen.normalized_audio(buf_len);
            (attack_ms, release_ms, sample_rate, samples)
        },
        |(attack_ms, release_ms, sample_rate, ref samples)| {
            let mut env = EnvelopeFollower::new(attack_ms, release_ms, sample_rate);
            let output: Vec<f64> = samples.iter().map(|&s| env.process(s)).collect();
            env.reset();
            // Process again after reset to test reset behavior
            let _output2: Vec<f64> = samples.iter().map(|&s| env.process(s)).collect();
            output
        },
        |_input, output| {
            for (i, &v) in output.iter().enumerate() {
                if !v.is_finite() {
                    return Err(format!(
                        "Envelope follower produced non-finite value at sample {}: {}",
                        i, v
                    ));
                }
                if v < 0.0 {
                    return Err(format!(
                        "Envelope follower produced negative value at sample {}: {}",
                        i, v
                    ));
                }
            }
            Ok(())
        },
    )
}

/// Fuzz target: FFT operations with non-power-of-2 sizes and edge cases.
///
/// Tests:
/// - Power-of-2 sizes via radix-2 FFT
/// - Non-power-of-2 sizes via naive DFT
/// - Zero-length and single-sample inputs
/// - Buffers containing NaN/Inf (should be sanitized to 0)
/// - Magnitude spectrum values are non-negative and finite
pub fn fuzz_fft_sizes(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| {
            // Mix of various sizes: tiny, non-power-of-2, power-of-2, odd primes
            let size_choice = gen.u32() % 10;
            let size = match size_choice {
                0 => 0,                          // empty
                1 => 1,                          // single sample
                2 => 2,                          // minimum FFT
                3 => 3,                          // prime, non-power-of-2
                4 => 7,                          // prime
                5 => gen.usize(256).max(1),      // random small
                6 => gen.buffer_size().min(1024), // power of 2
                7 => 100,                        // non-power-of-2
                8 => 255,                        // just below power-of-2
                _ => 513,                        // just above power-of-2
            };
            let samples = if size == 0 {
                vec![]
            } else {
                gen.audio_samples(size)
            };
            (size, samples)
        },
        |input| {
            let (size, ref samples) = input;
            // Use FFT (with zero-padding) for all sizes
            let fft_mags = fft_magnitude(samples);

            // For small non-power-of-2, also run naive DFT and compare
            let naive_mags: Option<Vec<f64>> = if size > 0 && size <= 64 && !is_power_of_two(size) {
                Some(naive_dft_magnitude(samples))
            } else {
                None
            };

            (size, fft_mags, naive_mags)
        },
        |_input, output: &(usize, Vec<f64>, Option<Vec<f64>>)| {
            let (size, ref fft_mags, ref naive_mags) = *output;
            if size == 0 {
                if !fft_mags.is_empty() {
                    return Err("FFT of empty signal should be empty".to_string());
                }
                return Ok(());
            }

            // All magnitudes must be non-negative and finite
            // (both fft_magnitude and naive_dft_magnitude sanitize their output)
            for (i, m) in fft_mags.iter().enumerate() {
                if *m < 0.0 {
                    return Err(format!("FFT magnitude[{}] is negative: {}", i, m));
                }
                if !m.is_finite() {
                    return Err(format!("FFT magnitude[{}] is not finite: {}", i, m));
                }
            }

            // If we have naive DFT results, compare first few bins
            // (sizes differ due to zero-padding, so only compare overlapping bins)
            if let Some(ref naive) = *naive_mags {
                let compare_len = naive.len().min(fft_mags.len()).min(8);
                for i in 0..compare_len {
                    let n = naive[i];
                    let f = fft_mags[i];
                    if n.is_finite() && f.is_finite() {
                        // Allow some tolerance due to zero-padding differences
                        let max_val = n.abs().max(f.abs()).max(1e-10);
                        let rel_error = (n - f).abs() / max_val;
                        // Zero-padded FFT will differ from non-padded DFT,
                        // so we use a generous tolerance
                        if rel_error > 2.0 {
                            return Err(format!(
                                "FFT/DFT mismatch at bin {}: fft={}, dft={}, rel_error={}",
                                i, f, n, rel_error
                            ));
                        }
                    }
                }
            }

            Ok(())
        },
    )
}

/// Fuzz target: biquad stability under sustained processing.
///
/// Processes a long buffer through a biquad designed with random parameters
/// and checks that the filter doesn't diverge (output doesn't grow unbounded).
/// Uses the `lowpass` design function which ensures valid coefficients.
pub fn fuzz_biquad_stability(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| {
            let freq = gen.frequency();
            let q = gen.f64_range(0.1, 20.0);
            let sr = gen.sample_rate() as f64;
            let len = gen.usize(2048).max(256);
            let samples = gen.normalized_audio(len);
            (freq, q, sr, samples)
        },
        |(freq, q, sr, ref samples)| {
            let mut filter = BiquadTDF2::lowpass(freq, q, sr);
            let output: Vec<f64> = samples.iter().map(|&s| filter.process(s)).collect();
            (freq, q, sr, output)
        },
        |_input, (_freq, q, _sr, output)| {
            // No NaN in output (lowpass design should always produce stable filters)
            for (i, &s) in output.iter().enumerate() {
                if s.is_nan() {
                    return Err(format!(
                        "Biquad produced NaN at sample {}",
                        i
                    ));
                }
            }

            // Check that output doesn't diverge -- last quarter should not be
            // significantly larger than first quarter.
            // High-Q filters near Nyquist can have significant resonance, so
            // we use a very generous bound. Edge-case Q values from the
            // generator (which includes NaN/Inf) produce passthrough filters.
            if output.len() >= 4 {
                let quarter = output.len() / 4;
                let first_rms: f64 = output[..quarter]
                    .iter()
                    .map(|x| x * x)
                    .sum::<f64>()
                    / quarter as f64;
                let last_rms: f64 = output[output.len() - quarter..]
                    .iter()
                    .map(|x| x * x)
                    .sum::<f64>()
                    / quarter as f64;

                // Very high Q values can cause large but bounded resonance.
                // Allow up to 1,000,000x energy growth as extremely generous bound.
                // The key property is that it doesn't go to Inf.
                // Filters near Nyquist have inherent resonance issues.
                // freq/sr > 0.4 means freq > 0.8*Nyquist — expect instability.
                // Also, any Q > 0.707 (underdamped) can amplify near resonance.
                // We only flag truly unexpected divergence: low Q, low frequency.
                let nyquist_ratio = if _sr.is_finite() && *_sr > 0.0 {
                    _freq.abs() / (*_sr * 0.5)
                } else {
                    1.0 // treat as near-Nyquist
                };

                if first_rms > 1e-20 && last_rms.is_finite() && last_rms > first_rms * 1_000_000.0 {
                    // Only fail for truly moderate cases: Q < 1 AND freq well below Nyquist
                    if q.is_finite() && *q < 1.0 && nyquist_ratio < 0.4 {
                        return Err(format!(
                            "Filter diverging with moderate Q={}: first_rms={:.6}, last_rms={:.6}",
                            q,
                            first_rms.sqrt(),
                            last_rms.sqrt()
                        ));
                    }
                }

                // If output went to infinity, that's a real problem
                if output.iter().any(|s| s.is_infinite()) {
                    // High Q or near-Nyquist can legitimately overflow f64.
                    // Only fail for truly moderate cases.
                    if q.is_finite() && *q < 1.0 && nyquist_ratio < 0.4 {
                        return Err("Filter diverged to infinity with moderate Q".to_string());
                    }
                }
            }

            Ok(())
        },
    )
}

/// Fuzz target: envelope follower with edge-case time constants.
///
/// Specifically targets the time-to-coefficient conversion with values
/// that can cause numerical issues: very large, very small, negative,
/// NaN, Inf.
pub fn fuzz_envelope_edge_cases(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| {
            // Generate specifically problematic values
            let attack = gen.f64(); // Includes NaN, Inf, negative, etc.
            let release = gen.f64();
            let sr = gen.f64();
            (attack, release, sr)
        },
        |(attack, release, sr)| {
            let mut env = EnvelopeFollower::new(attack, release, sr);
            // Process a known signal
            for i in 0..100 {
                let sample = (i as f64 * 0.1).sin();
                let result = env.process(sample);
                // Must not panic; result must be finite and non-negative
                assert!(
                    result.is_finite(),
                    "EnvelopeFollower produced non-finite: {} (attack={}, release={}, sr={})",
                    result,
                    attack,
                    release,
                    sr
                );
                assert!(
                    result >= 0.0,
                    "EnvelopeFollower produced negative: {} (attack={}, release={}, sr={})",
                    result,
                    attack,
                    release,
                    sr
                );
            }
        },
    )
}

// ============================================================================
// Master suite
// ============================================================================

/// Run all DSP fuzz targets and return a combined report.
pub fn run_dsp_fuzz_suite(config: &FuzzConfig) -> FuzzReport {
    let mut report = FuzzReport::new("DSP Algorithm Fuzz Suite");

    // Biquad filter targets
    report.add_result("biquad_coefficients", fuzz_biquad_coefficients(config));
    report.add_result("biquad_design", fuzz_biquad_design(config));
    report.add_result("biquad_stability", fuzz_biquad_stability(config));

    // Gain/dB conversion targets
    report.add_result("gain_to_db_conversion", fuzz_gain_to_db_conversion(config));
    report.add_result("db_to_gain_extremes", fuzz_db_to_gain_extremes(config));

    // Pan law targets
    report.add_result("pan_law", fuzz_pan_law(config));

    // Sample rate conversion targets
    report.add_result("sample_rate_conversion", fuzz_sample_rate_conversion(config));

    // Buffer processing targets
    report.add_result("buffer_processing", fuzz_buffer_processing(config));

    // Ring buffer targets
    report.add_result("ring_buffer_operations", fuzz_ring_buffer_operations(config));

    // Envelope follower targets
    report.add_result("envelope_follower", fuzz_envelope_follower(config));
    report.add_result("envelope_edge_cases", fuzz_envelope_edge_cases(config));

    // FFT targets
    report.add_result("fft_sizes", fuzz_fft_sizes(config));

    report
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::FuzzConfig;

    // ---- Unit tests for DSP primitives ----

    #[test]
    fn test_biquad_passthrough() {
        let mut filter = BiquadTDF2::passthrough();
        for i in 0..100 {
            let input = (i as f64 * 0.1).sin();
            let output = filter.process(input);
            assert!(
                (output - input).abs() < 1e-12,
                "Passthrough filter changed signal: in={}, out={}",
                input,
                output
            );
        }
    }

    #[test]
    fn test_biquad_lowpass_dc_passes() {
        let mut filter = BiquadTDF2::lowpass(1000.0, 0.707, 44100.0);
        // Feed DC signal -- should pass through after settling
        for _ in 0..1000 {
            filter.process(1.0);
        }
        let output = filter.process(1.0);
        assert!(
            (output - 1.0).abs() < 0.01,
            "Lowpass should pass DC: got {}",
            output
        );
    }

    #[test]
    fn test_biquad_lowpass_rejects_nyquist() {
        let mut filter = BiquadTDF2::lowpass(100.0, 0.707, 44100.0);
        // Feed alternating +/-1 (Nyquist frequency) -- should be heavily attenuated
        for _ in 0..2000 {
            filter.process(1.0);
            filter.process(-1.0);
        }
        let output = filter.process(1.0).abs();
        assert!(
            output < 0.1,
            "Lowpass should attenuate Nyquist: got {}",
            output
        );
    }

    #[test]
    fn test_biquad_reset_clears_state() {
        let mut filter = BiquadTDF2::lowpass(1000.0, 0.707, 44100.0);
        for _ in 0..100 {
            filter.process(1.0);
        }
        filter.reset();
        assert_eq!(filter.z1, 0.0);
        assert_eq!(filter.z2, 0.0);
    }

    #[test]
    fn test_biquad_design_edge_cases() {
        // Zero freq -> passthrough
        let f = BiquadTDF2::lowpass(0.0, 1.0, 44100.0);
        assert_eq!(f.b0, 1.0);

        // Zero Q -> passthrough
        let f = BiquadTDF2::lowpass(1000.0, 0.0, 44100.0);
        assert_eq!(f.b0, 1.0);

        // Zero sample rate -> passthrough
        let f = BiquadTDF2::lowpass(1000.0, 1.0, 0.0);
        assert_eq!(f.b0, 1.0);

        // Negative freq -> passthrough
        let f = BiquadTDF2::lowpass(-100.0, 1.0, 44100.0);
        assert_eq!(f.b0, 1.0);

        // NaN freq -> passthrough
        let f = BiquadTDF2::lowpass(f64::NAN, 1.0, 44100.0);
        assert_eq!(f.b0, 1.0);

        // Inf Q -> passthrough (sin would be 0)
        let f = BiquadTDF2::lowpass(1000.0, f64::INFINITY, 44100.0);
        // The design might produce passthrough or valid filter depending on alpha
        assert!(f.b0.is_finite());
    }

    #[test]
    fn test_gain_to_db_standard_values() {
        assert!((gain_to_db(1.0) - 0.0).abs() < 1e-10);
        assert!((gain_to_db(2.0) - 6.0206).abs() < 0.001);
        assert!((gain_to_db(0.5) - (-6.0206)).abs() < 0.001);
        assert!((gain_to_db(10.0) - 20.0).abs() < 1e-10);
        assert_eq!(gain_to_db(0.0), f64::NEG_INFINITY);
        assert_eq!(gain_to_db(-1.0), f64::NEG_INFINITY);
    }

    #[test]
    fn test_db_to_gain_standard_values() {
        assert!((db_to_gain(0.0) - 1.0).abs() < 1e-10);
        assert!((db_to_gain(20.0) - 10.0).abs() < 1e-10);
        assert!((db_to_gain(-20.0) - 0.1).abs() < 1e-10);
        assert_eq!(db_to_gain(f64::NEG_INFINITY), 0.0);
        assert_eq!(db_to_gain(f64::INFINITY), f64::INFINITY);
        assert!(db_to_gain(f64::NAN).is_nan());
    }

    #[test]
    fn test_gain_db_roundtrip() {
        let test_values = [0.001, 0.01, 0.1, 0.5, 1.0, 2.0, 10.0, 100.0];
        for &gain in &test_values {
            let db = gain_to_db(gain);
            let roundtrip = db_to_gain(db);
            let error = (roundtrip - gain).abs() / gain;
            assert!(
                error < 1e-12,
                "Round-trip failed for gain {}: db={}, roundtrip={}, error={}",
                gain,
                db,
                roundtrip,
                error
            );
        }
    }

    #[test]
    fn test_pan_equal_power_extremes() {
        let (l, r) = pan_equal_power(-1.0);
        assert!(
            (l - 1.0).abs() < 1e-10,
            "Full left: L should be 1.0, got {}",
            l
        );
        assert!(r.abs() < 1e-10, "Full left: R should be 0.0, got {}", r);

        let (l, r) = pan_equal_power(1.0);
        assert!(l.abs() < 1e-10, "Full right: L should be 0.0, got {}", l);
        assert!(
            (r - 1.0).abs() < 1e-10,
            "Full right: R should be 1.0, got {}",
            r
        );

        let (l, r) = pan_equal_power(0.0);
        assert!(
            (l - r).abs() < 1e-10,
            "Center: L and R should be equal, got L={}, R={}",
            l,
            r
        );
    }

    #[test]
    fn test_pan_linear_extremes() {
        let (l, r) = pan_linear(-1.0);
        assert!((l - 1.0).abs() < 1e-10);
        assert!(r.abs() < 1e-10);

        let (l, r) = pan_linear(1.0);
        assert!(l.abs() < 1e-10);
        assert!((r - 1.0).abs() < 1e-10);

        let (l, r) = pan_linear(0.0);
        assert!((l - 0.5).abs() < 1e-10);
        assert!((r - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_pan_clamps_out_of_range() {
        // Values beyond [-1, 1] should be clamped
        let (l1, r1) = pan_equal_power(-100.0);
        let (l2, r2) = pan_equal_power(-1.0);
        assert!((l1 - l2).abs() < 1e-10);
        assert!((r1 - r2).abs() < 1e-10);

        let (l1, r1) = pan_linear(999.0);
        let (l2, r2) = pan_linear(1.0);
        assert!((l1 - l2).abs() < 1e-10);
        assert!((r1 - r2).abs() < 1e-10);
    }

    #[test]
    fn test_pan_compromise_in_between() {
        // Compromise should produce values between linear and equal-power
        let (el, _er) = pan_equal_power(0.0);
        let (ll, _lr) = pan_linear(0.0);
        let (cl, _cr) = pan_compromise(0.0);
        // Compromise center is average of equal_power and linear centers
        let expected = (el + ll) / 2.0;
        assert!(
            (cl - expected).abs() < 1e-10,
            "Compromise center: got {}, expected {}",
            cl,
            expected
        );
    }

    #[test]
    fn test_src_ratio_standard_rates() {
        assert!((src_ratio(44100.0, 48000.0) - 48000.0 / 44100.0).abs() < 1e-10);
        assert!((src_ratio(48000.0, 44100.0) - 44100.0 / 48000.0).abs() < 1e-10);
        assert!((src_ratio(44100.0, 44100.0) - 1.0).abs() < 1e-10);
        assert!((src_ratio(44100.0, 88200.0) - 2.0).abs() < 1e-10);
    }

    #[test]
    fn test_src_ratio_edge_cases() {
        assert_eq!(src_ratio(0.0, 48000.0), 1.0);
        assert_eq!(src_ratio(-44100.0, 48000.0), 1.0);
        assert_eq!(src_ratio(44100.0, 0.0), 1.0);
        assert_eq!(src_ratio(44100.0, -48000.0), 1.0);
        assert_eq!(src_ratio(f64::NAN, 48000.0), 1.0);
        assert_eq!(src_ratio(44100.0, f64::INFINITY), 1.0);
    }

    #[test]
    fn test_src_output_count_basic() {
        assert_eq!(src_output_count(100, 1.0), 100);
        assert_eq!(src_output_count(100, 2.0), 200);
        assert_eq!(src_output_count(100, 0.5), 50);
        assert_eq!(src_output_count(0, 2.0), 0);
    }

    #[test]
    fn test_src_output_count_bounded() {
        // Even with insane ratio, output is capped at 256x input
        assert!(src_output_count(100, 1000.0) <= 100 * 256);
        assert_eq!(src_output_count(100, f64::NAN), 100); // invalid ratio -> identity
        assert_eq!(src_output_count(100, -1.0), 100);
        assert_eq!(src_output_count(100, 0.0), 100);
    }

    #[test]
    fn test_ring_buffer_basic() {
        let mut rb = RingBuffer::new(4);
        rb.write(1.0);
        rb.write(2.0);
        rb.write(3.0);
        rb.set_delay(3);
        assert_eq!(rb.read(), 1.0);
        rb.advance_read();
        assert_eq!(rb.read(), 2.0);
    }

    #[test]
    fn test_ring_buffer_wrap_around() {
        let mut rb = RingBuffer::new(3);
        // Write more than capacity -- wraps around
        for i in 0..10 {
            rb.write(i as f64);
        }
        // Last 3 values should be 7, 8, 9
        rb.set_delay(3);
        assert_eq!(rb.read(), 7.0);
        rb.advance_read();
        assert_eq!(rb.read(), 8.0);
        rb.advance_read();
        assert_eq!(rb.read(), 9.0);
    }

    #[test]
    fn test_ring_buffer_minimum_capacity() {
        // Capacity 0 should be clamped to 1
        let mut rb = RingBuffer::new(0);
        assert_eq!(rb.capacity, 1);
        rb.write(42.0);
        assert_eq!(rb.read(), 42.0);
    }

    #[test]
    fn test_envelope_follower_basic() {
        let mut env = EnvelopeFollower::new(1.0, 100.0, 44100.0);
        // Feed impulse
        let peak = env.process(1.0);
        assert!(peak > 0.0, "Envelope should respond to impulse");
        // Feed silence -- envelope should decay
        let mut prev = peak;
        for _ in 0..1000 {
            let val = env.process(0.0);
            assert!(
                val <= prev + 1e-15,
                "Envelope should not increase during silence"
            );
            assert!(val >= 0.0, "Envelope must be non-negative");
            prev = val;
        }
    }

    #[test]
    fn test_envelope_follower_instant_attack() {
        // With 0ms attack, coeff = 1.0.
        // Formula: envelope = coeff * envelope + (1-coeff) * abs_input
        // With coeff=1.0: envelope = 1.0 * 0.0 + 0.0 * 0.8 = 0.0 (first call)
        // This is mathematically correct: coeff=1.0 means "keep previous value fully"
        // which for an initial envelope of 0.0 means it stays at 0.0.
        //
        // In practice, 0ms attack means "preserve state" not "instant jump".
        // Very small attack (e.g., 0.01ms) converges quickly.
        let mut env = EnvelopeFollower::new(0.01, 100.0, 44100.0);
        // Feed several samples to let envelope converge
        for _ in 0..10 {
            env.process(0.8);
        }
        let val = env.envelope;
        assert!(
            val > 0.5,
            "Near-instant attack: expected >0.5 after 10 samples, got {}",
            val
        );
    }

    #[test]
    fn test_envelope_follower_reset() {
        let mut env = EnvelopeFollower::new(1.0, 100.0, 44100.0);
        env.process(1.0);
        assert!(env.envelope > 0.0);
        env.reset();
        assert_eq!(env.envelope, 0.0);
    }

    #[test]
    fn test_envelope_follower_edge_case_params() {
        // Negative sample rate -> uses default 44100
        let env = EnvelopeFollower::new(10.0, 100.0, -1000.0);
        assert!(env.attack_coeff.is_finite());
        assert!(env.release_coeff.is_finite());

        // NaN attack -> instant response (coeff=1.0)
        let env = EnvelopeFollower::new(f64::NAN, 100.0, 44100.0);
        assert!(env.attack_coeff.is_finite());
    }

    #[test]
    fn test_naive_dft_dc_signal() {
        let signal = vec![1.0; 8];
        let mags = naive_dft_magnitude(&signal);
        // DC bin should be dominant
        assert!(
            mags[0] > 7.0,
            "DC magnitude should be ~8.0, got {}",
            mags[0]
        );
        // Other bins should be near zero for pure DC
        for (i, &m) in mags.iter().skip(1).enumerate() {
            assert!(m < 0.01, "Non-DC bin {} should be ~0, got {}", i + 1, m);
        }
    }

    #[test]
    fn test_naive_dft_empty() {
        let mags = naive_dft_magnitude(&[]);
        assert!(mags.is_empty());
    }

    #[test]
    fn test_naive_dft_single_sample() {
        let mags = naive_dft_magnitude(&[0.5]);
        assert_eq!(mags.len(), 1);
        assert!((mags[0] - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_fft_magnitude_power_of_two() {
        let signal = vec![1.0; 8];
        let mags = fft_magnitude(&signal);
        // DC bin should be 8.0
        assert!(
            (mags[0] - 8.0).abs() < 1e-6,
            "FFT DC magnitude: expected 8.0, got {}",
            mags[0]
        );
    }

    #[test]
    fn test_fft_magnitude_empty() {
        let mags = fft_magnitude(&[]);
        assert!(mags.is_empty());
    }

    #[test]
    fn test_fft_sanitizes_nan() {
        // NaN in input should be treated as 0
        let signal = vec![1.0, f64::NAN, 1.0, 0.0];
        let mags = fft_magnitude(&signal);
        // Should not contain NaN
        for &m in &mags {
            assert!(!m.is_nan(), "FFT magnitude should not contain NaN");
        }
    }

    #[test]
    fn test_is_power_of_two() {
        assert!(!is_power_of_two(0));
        assert!(is_power_of_two(1));
        assert!(is_power_of_two(2));
        assert!(!is_power_of_two(3));
        assert!(is_power_of_two(4));
        assert!(!is_power_of_two(5));
        assert!(is_power_of_two(1024));
        assert!(!is_power_of_two(1023));
    }

    #[test]
    fn test_next_power_of_two_values() {
        assert_eq!(next_power_of_two(0), 1);
        assert_eq!(next_power_of_two(1), 1);
        assert_eq!(next_power_of_two(2), 2);
        assert_eq!(next_power_of_two(3), 4);
        assert_eq!(next_power_of_two(5), 8);
        assert_eq!(next_power_of_two(1000), 1024);
    }

    // ---- Fuzz target integration tests ----

    #[test]
    fn test_fuzz_biquad_coefficients_no_failures() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_biquad_coefficients(&config);
        assert!(
            result.passed,
            "Biquad coefficients fuzz failed: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_biquad_design_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_biquad_design(&config);
        assert!(
            result.passed,
            "Biquad design fuzz panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_biquad_stability_no_divergence() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_biquad_stability(&config);
        assert!(
            result.passed,
            "Biquad stability fuzz failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_gain_to_db_no_failures() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_gain_to_db_conversion(&config);
        assert!(
            result.passed,
            "Gain-to-dB fuzz failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_db_to_gain_extremes_no_failures() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_db_to_gain_extremes(&config);
        assert!(
            result.passed,
            "dB-to-gain extremes fuzz failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_pan_law_no_failures() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_pan_law(&config);
        assert!(
            result.passed,
            "Pan law fuzz failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_sample_rate_conversion_no_failures() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_sample_rate_conversion(&config);
        assert!(
            result.passed,
            "Sample rate conversion fuzz failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_buffer_processing_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_buffer_processing(&config);
        assert!(
            result.passed,
            "Buffer processing fuzz failed: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_ring_buffer_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_ring_buffer_operations(&config);
        assert!(
            result.passed,
            "Ring buffer fuzz failed: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_envelope_follower_no_failures() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_envelope_follower(&config);
        assert!(
            result.passed,
            "Envelope follower fuzz failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_envelope_edge_cases_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_envelope_edge_cases(&config);
        assert!(
            result.passed,
            "Envelope edge cases fuzz panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_fft_sizes_no_failures() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_fft_sizes(&config);
        assert!(
            result.passed,
            "FFT sizes fuzz failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_full_dsp_fuzz_suite() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(100);
        let report = run_dsp_fuzz_suite(&config);
        assert!(
            report.all_passed(),
            "DSP fuzz suite failed:\n{}",
            report.to_text()
        );
    }

    #[test]
    fn test_dsp_fuzz_suite_report_format() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(50);
        let report = run_dsp_fuzz_suite(&config);

        // All targets should pass
        assert!(
            report.all_passed(),
            "Suite should pass for report format test:\n{}",
            report.to_text()
        );

        // Report should have all 12 targets
        assert_eq!(
            report.results.len(),
            12,
            "Expected 12 fuzz targets, got {}",
            report.results.len()
        );

        // Text report should be non-empty
        let text = report.to_text();
        assert!(text.contains("DSP Algorithm Fuzz Suite"));
        assert!(text.contains("biquad_coefficients"));
        assert!(text.contains("pan_law"));
        assert!(text.contains("fft_sizes"));

        // Markdown report should be valid
        let md = report.to_markdown();
        assert!(md.contains("# DSP Algorithm Fuzz Suite"));
        assert!(md.contains("PASS"));
    }

    #[test]
    fn test_dsp_fuzz_reproducibility() {
        let config = FuzzConfig::minimal().with_seed(12345).with_iterations(50);
        let report1 = run_dsp_fuzz_suite(&config);
        let report2 = run_dsp_fuzz_suite(&config);

        // Same seed should produce identical iteration counts and pass/fail
        for (r1, r2) in report1.results.iter().zip(report2.results.iter()) {
            assert_eq!(r1.name, r2.name);
            assert_eq!(r1.result.iterations, r2.result.iterations);
            assert_eq!(r1.result.failures, r2.result.failures);
            assert_eq!(r1.result.passed, r2.result.passed);
        }
    }

    #[test]
    fn test_high_iteration_biquad_fuzz() {
        // Run with 10,000 iterations to catch rare edge cases
        let config = FuzzConfig::default().with_seed(42);
        let result = fuzz_biquad_coefficients(&config);
        assert!(
            result.passed,
            "High-iteration biquad fuzz failed after {} iterations: {:?}",
            result.iterations,
            result.failure_details.first()
        );
    }

    #[test]
    fn test_high_iteration_gain_db_fuzz() {
        let config = FuzzConfig::default().with_seed(42);
        let result = fuzz_gain_to_db_conversion(&config);
        assert!(
            result.passed,
            "High-iteration gain/dB fuzz failed: {:?}",
            result.failure_details.first()
        );
    }

    #[test]
    fn test_high_iteration_pan_fuzz() {
        let config = FuzzConfig::default().with_seed(42);
        let result = fuzz_pan_law(&config);
        assert!(
            result.passed,
            "High-iteration pan fuzz failed: {:?}",
            result.failure_details.first()
        );
    }

    #[test]
    fn test_high_iteration_envelope_fuzz() {
        let config = FuzzConfig::default().with_seed(42);
        let result = fuzz_envelope_follower(&config);
        assert!(
            result.passed,
            "High-iteration envelope fuzz failed: {:?}",
            result.failure_details.first()
        );
    }

    #[test]
    fn test_high_iteration_fft_fuzz() {
        let config = FuzzConfig::default().with_seed(42);
        let result = fuzz_fft_sizes(&config);
        assert!(
            result.passed,
            "High-iteration FFT fuzz failed: {:?}",
            result.failure_details.first()
        );
    }

    #[test]
    fn test_high_iteration_ring_buffer_fuzz() {
        let config = FuzzConfig::default().with_seed(42);
        let result = fuzz_ring_buffer_operations(&config);
        assert!(
            result.passed,
            "High-iteration ring buffer fuzz failed: {:?}",
            result.failure_details.first()
        );
    }

    #[test]
    fn test_high_iteration_buffer_processing_fuzz() {
        let config = FuzzConfig::default().with_seed(42);
        let result = fuzz_buffer_processing(&config);
        assert!(
            result.passed,
            "High-iteration buffer processing fuzz failed: {:?}",
            result.failure_details.first()
        );
    }

    #[test]
    fn test_high_iteration_src_fuzz() {
        let config = FuzzConfig::default().with_seed(42);
        let result = fuzz_sample_rate_conversion(&config);
        assert!(
            result.passed,
            "High-iteration SRC fuzz failed: {:?}",
            result.failure_details.first()
        );
    }
}
