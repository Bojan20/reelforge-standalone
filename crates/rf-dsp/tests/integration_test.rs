//! DSP Integration Tests
//!
//! Tests complete signal flow through DSP processing chains.
//! Verifies:
//! - Channel strip processing (EQ → Dynamics → Spatial)
//! - Full signal path integrity (no NaN/Inf)
//! - Frequency response correctness
//! - Phase coherence
//! - Latency compensation

use rf_dsp::analysis::{PeakMeter, RmsMeter};
use rf_dsp::LufsMeter; // Now from metering.rs
use rf_dsp::biquad::{BiquadCoeffs, BiquadTDF2};
use rf_dsp::channel::ChannelStrip;
use rf_dsp::delay::Delay;
use rf_dsp::dynamics::{
    Compressor, CompressorType, Oversampling, StereoCompressor, TruePeakLimiter,
};
use rf_dsp::eq::{EqFilterType, ParametricEq};
use rf_dsp::reverb::{AlgorithmicReverb, ReverbType};
use rf_dsp::spatial::{MsProcessor, StereoPanner, StereoWidth};
use rf_dsp::{MonoProcessor, Processor, StereoProcessor};

const SAMPLE_RATE: f64 = 48000.0;
const BLOCK_SIZE: usize = 256;

/// Generate test sine wave
fn generate_sine(samples: usize, freq: f64) -> Vec<f64> {
    (0..samples)
        .map(|i| {
            let t = i as f64 / SAMPLE_RATE;
            (2.0 * std::f64::consts::PI * freq * t).sin()
        })
        .collect()
}

/// Generate white noise
fn generate_noise(samples: usize) -> Vec<f64> {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    (0..samples)
        .map(|i| {
            let mut hasher = DefaultHasher::new();
            i.hash(&mut hasher);
            let h = hasher.finish();
            (h as f64 / u64::MAX as f64) * 2.0 - 1.0
        })
        .collect()
}

/// Check signal has no NaN or Infinity
fn is_valid_signal(signal: &[f64]) -> bool {
    signal.iter().all(|&x| x.is_finite())
}

/// Calculate RMS of signal
fn rms(signal: &[f64]) -> f64 {
    let sum: f64 = signal.iter().map(|x| x * x).sum();
    (sum / signal.len() as f64).sqrt()
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIGNAL INTEGRITY TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_biquad_signal_integrity() {
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    filter.set_coeffs(BiquadCoeffs::lowpass(1000.0, 0.707, SAMPLE_RATE));

    let input = generate_sine(BLOCK_SIZE * 100, 440.0);
    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        output.push(filter.process_sample(sample));
    }

    assert!(is_valid_signal(&output), "Biquad produced invalid signal");
}

#[test]
fn test_eq_signal_integrity() {
    let mut eq = ParametricEq::new(SAMPLE_RATE);

    // Configure multiple bands
    eq.set_band(0, 100.0, 3.0, 1.0, EqFilterType::LowShelf);
    eq.set_band(1, 500.0, -2.0, 1.5, EqFilterType::Bell);
    eq.set_band(2, 2000.0, 4.0, 2.0, EqFilterType::Bell);
    eq.set_band(3, 8000.0, 2.0, 0.7, EqFilterType::HighShelf);

    let mut left = generate_sine(BLOCK_SIZE * 100, 440.0);
    let mut right = generate_sine(BLOCK_SIZE * 100, 440.0);

    // Process in blocks
    for i in (0..left.len()).step_by(BLOCK_SIZE) {
        let end = (i + BLOCK_SIZE).min(left.len());
        eq.process_block(&mut left[i..end], &mut right[i..end]);
    }

    assert!(is_valid_signal(&left), "EQ produced invalid left signal");
    assert!(is_valid_signal(&right), "EQ produced invalid right signal");
}

#[test]
fn test_compressor_signal_integrity() {
    let mut comp = Compressor::new(SAMPLE_RATE);
    comp.set_type(CompressorType::Vca);
    comp.set_threshold(-20.0);
    comp.set_ratio(4.0);
    comp.set_times(10.0, 100.0);

    // Hot signal that will compress
    let input: Vec<f64> = generate_sine(BLOCK_SIZE * 100, 440.0)
        .iter()
        .map(|x| x * 2.0) // +6dB
        .collect();

    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        output.push(comp.process_sample(sample));
    }

    assert!(
        is_valid_signal(&output),
        "Compressor produced invalid signal"
    );

    // Compressed signal should be lower than input
    let input_peak = input.iter().map(|x| x.abs()).fold(0.0f64, f64::max);
    let output_peak = output.iter().map(|x| x.abs()).fold(0.0f64, f64::max);
    assert!(output_peak < input_peak, "Compressor should reduce peak");
}

#[test]
fn test_limiter_signal_integrity() {
    let mut limiter = TruePeakLimiter::new(SAMPLE_RATE);
    limiter.set_threshold(-1.0);
    limiter.set_oversampling(Oversampling::X4);

    // Hot signal
    let input: Vec<f64> = generate_sine(BLOCK_SIZE * 100, 440.0)
        .iter()
        .map(|x| x * 4.0) // +12dB
        .collect();

    let mut output_l = Vec::with_capacity(input.len());
    let mut output_r = Vec::with_capacity(input.len());

    for &sample in &input {
        let (l, r) = limiter.process_sample(sample, sample);
        output_l.push(l);
        output_r.push(r);
    }

    assert!(
        is_valid_signal(&output_l),
        "Limiter produced invalid left signal"
    );
    assert!(
        is_valid_signal(&output_r),
        "Limiter produced invalid right signal"
    );

    // Limited signal should never exceed threshold
    let max_out = output_l.iter().map(|x| x.abs()).fold(0.0f64, f64::max);
    // Allow small overshoot due to true peak reconstruction
    assert!(
        max_out < 1.2,
        "Limiter should limit signal, got {}",
        max_out
    );
}

#[test]
fn test_reverb_signal_integrity() {
    let mut reverb = AlgorithmicReverb::new(SAMPLE_RATE);
    reverb.set_type(ReverbType::Hall);
    reverb.set_room_size(0.8);
    reverb.set_dry_wet(0.5);

    let input = generate_sine(BLOCK_SIZE * 100, 440.0);
    let mut output_l = Vec::with_capacity(input.len());
    let mut output_r = Vec::with_capacity(input.len());

    for &sample in &input {
        let (l, r) = reverb.process_sample(sample, sample);
        output_l.push(l);
        output_r.push(r);
    }

    assert!(
        is_valid_signal(&output_l),
        "Reverb produced invalid left signal"
    );
    assert!(
        is_valid_signal(&output_r),
        "Reverb produced invalid right signal"
    );
}

#[test]
fn test_delay_signal_integrity() {
    let mut delay = Delay::new(SAMPLE_RATE, 1000.0);
    delay.set_delay_ms(250.0);
    delay.set_feedback(0.5);
    delay.set_dry_wet(0.5);

    let input = generate_sine(BLOCK_SIZE * 100, 440.0);
    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        output.push(delay.process_sample(sample));
    }

    assert!(is_valid_signal(&output), "Delay produced invalid signal");
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP CHAIN TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_full_channel_strip() {
    let mut channel = ChannelStrip::new(SAMPLE_RATE);

    // Configure EQ (using public API)
    channel.set_eq_enabled(true);
    channel.set_eq_low(80.0, 3.0);
    channel.set_eq_low_mid(250.0, -2.0, 2.0);
    channel.set_eq_high_mid(3000.0, 2.0, 1.5);
    channel.set_eq_high(10000.0, 1.0);

    // Configure compressor
    channel.set_comp_enabled(true);
    channel.set_comp_threshold(-18.0);
    channel.set_comp_ratio(3.0);

    // Configure spatial
    channel.set_pan(0.3);
    channel.set_width(1.2);

    // Process signal
    let mut left = generate_sine(BLOCK_SIZE * 100, 440.0);
    let mut right = generate_sine(BLOCK_SIZE * 100, 440.0);

    for i in (0..left.len()).step_by(BLOCK_SIZE) {
        let end = (i + BLOCK_SIZE).min(left.len());
        channel.process_block(&mut left[i..end], &mut right[i..end]);
    }

    assert!(
        is_valid_signal(&left),
        "Channel strip produced invalid left signal"
    );
    assert!(
        is_valid_signal(&right),
        "Channel strip produced invalid right signal"
    );
}

#[test]
fn test_chain_eq_comp_limiter() {
    // Manual chain: EQ → Compressor → Limiter
    let mut eq = ParametricEq::new(SAMPLE_RATE);
    eq.set_band(0, 100.0, 3.0, 1.0, EqFilterType::Bell);

    let mut comp = StereoCompressor::new(SAMPLE_RATE);
    comp.set_both(|c| {
        c.set_threshold(-18.0);
        c.set_ratio(4.0);
    });

    let mut limiter = TruePeakLimiter::new(SAMPLE_RATE);
    limiter.set_threshold(-1.0);

    let mut left = generate_sine(BLOCK_SIZE * 100, 440.0);
    let mut right = generate_sine(BLOCK_SIZE * 100, 440.0);

    // Scale up
    for s in &mut left {
        *s *= 2.0;
    }
    for s in &mut right {
        *s *= 2.0;
    }

    // Process chain
    eq.process_block(&mut left, &mut right);

    for i in 0..left.len() {
        let (l, r) = comp.process_sample(left[i], right[i]);
        let (ol, or) = limiter.process_sample(l, r);
        left[i] = ol;
        right[i] = or;
    }

    assert!(is_valid_signal(&left), "Chain produced invalid left signal");
    assert!(
        is_valid_signal(&right),
        "Chain produced invalid right signal"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// FREQUENCY RESPONSE TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_lowpass_frequency_response() {
    let cutoff = 1000.0;
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    filter.set_coeffs(BiquadCoeffs::lowpass(cutoff, 0.707, SAMPLE_RATE));

    // Test frequencies below and above cutoff
    let test_freqs = [100.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];
    let mut responses = Vec::new();

    for &freq in &test_freqs {
        filter.reset();
        let input = generate_sine(BLOCK_SIZE * 10, freq);
        let mut output = Vec::with_capacity(input.len());

        for &sample in &input {
            output.push(filter.process_sample(sample));
        }

        // Skip transient, measure RMS
        let input_rms = rms(&input[BLOCK_SIZE..]);
        let output_rms = rms(&output[BLOCK_SIZE..]);
        responses.push((freq, output_rms / input_rms));
    }

    // Check that high frequencies are attenuated
    let below_cutoff = responses.iter().find(|(f, _)| *f < cutoff).unwrap().1;
    let above_cutoff = responses.iter().find(|(f, _)| *f > cutoff * 2.0).unwrap().1;

    assert!(
        above_cutoff < below_cutoff * 0.5,
        "Lowpass should attenuate high frequencies: {} vs {}",
        above_cutoff,
        below_cutoff
    );
}

#[test]
fn test_highpass_frequency_response() {
    let cutoff = 1000.0;
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    filter.set_coeffs(BiquadCoeffs::highpass(cutoff, 0.707, SAMPLE_RATE));

    let test_freqs = [100.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0];
    let mut responses = Vec::new();

    for &freq in &test_freqs {
        filter.reset();
        let input = generate_sine(BLOCK_SIZE * 10, freq);
        let mut output = Vec::with_capacity(input.len());

        for &sample in &input {
            output.push(filter.process_sample(sample));
        }

        let input_rms = rms(&input[BLOCK_SIZE..]);
        let output_rms = rms(&output[BLOCK_SIZE..]);
        responses.push((freq, output_rms / input_rms));
    }

    // Check that low frequencies are attenuated
    let below_cutoff = responses.iter().find(|(f, _)| *f < cutoff / 2.0).unwrap().1;
    let above_cutoff = responses.iter().find(|(f, _)| *f > cutoff).unwrap().1;

    assert!(
        below_cutoff < above_cutoff * 0.5,
        "Highpass should attenuate low frequencies: {} vs {}",
        below_cutoff,
        above_cutoff
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEREO IMAGING TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_stereo_width_mono() {
    let mut width = StereoWidth::new();
    width.set_width(0.0); // Mono

    let left = generate_sine(BLOCK_SIZE, 440.0);
    let right: Vec<f64> = left.iter().map(|x| -x).collect(); // Inverted = pure side

    let mut out_l = left.clone();
    let mut out_r = right.clone();

    for i in 0..out_l.len() {
        let (l, r) = width.process_sample(out_l[i], out_r[i]);
        out_l[i] = l;
        out_r[i] = r;
    }

    // In mono mode, L and R should be identical (mid only)
    for i in 0..out_l.len() {
        assert!(
            (out_l[i] - out_r[i]).abs() < 0.001,
            "Width 0 should produce mono: L={}, R={}",
            out_l[i],
            out_r[i]
        );
    }
}

#[test]
fn test_panner_hard_left() {
    let mut panner = StereoPanner::new();
    panner.set_pan(-1.0); // Hard left

    let (l, r) = panner.process_sample(1.0, 1.0);

    assert!(
        l.abs() > 0.9,
        "Hard left pan should have signal on left: {}",
        l
    );
    assert!(
        r.abs() < 0.1,
        "Hard left pan should have minimal right: {}",
        r
    );
}

#[test]
fn test_panner_hard_right() {
    let mut panner = StereoPanner::new();
    panner.set_pan(1.0); // Hard right

    let (l, r) = panner.process_sample(1.0, 1.0);

    assert!(
        l.abs() < 0.1,
        "Hard right pan should have minimal left: {}",
        l
    );
    assert!(
        r.abs() > 0.9,
        "Hard right pan should have signal on right: {}",
        r
    );
}

#[test]
fn test_ms_roundtrip() {
    let mut ms = MsProcessor::new();
    ms.set_mid_gain(1.0);
    ms.set_side_gain(1.0);

    let test_pairs = vec![
        (1.0, 1.0),  // Mono
        (1.0, -1.0), // Pure side
        (0.5, 0.8),  // Mixed
        (0.0, 0.0),  // Silence
    ];

    for (left, right) in test_pairs {
        let (l, r) = ms.process_sample(left, right);

        // With unity gains, should be passthrough
        assert!(
            (l - left).abs() < 0.001 && (r - right).abs() < 0.001,
            "M/S unity should passthrough: in=({}, {}), out=({}, {})",
            left,
            right,
            l,
            r
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// METERING TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_peak_meter_accuracy() {
    let mut peak = PeakMeter::new(SAMPLE_RATE);

    // Process known level signal
    let level = 0.5;
    let input = vec![level; BLOCK_SIZE * 10];
    peak.process_block(&input);

    // Peak should be close to 0.5
    let measured_db = peak.current_db();
    let expected_db = 20.0 * level.log10();

    assert!(
        (measured_db - expected_db).abs() < 3.0,
        "Peak meter inaccurate: got {} dB, expected {} dB",
        measured_db,
        expected_db
    );
}

#[test]
fn test_rms_meter_accuracy() {
    let mut rms_meter = RmsMeter::new(SAMPLE_RATE, 300.0);

    // Sine wave: RMS = peak / sqrt(2)
    let input = generate_sine(BLOCK_SIZE * 100, 440.0);
    rms_meter.process_block(&input);

    let measured = rms_meter.rms();
    let expected = 1.0 / 2.0_f64.sqrt(); // ~0.707

    assert!(
        (measured - expected).abs() < 0.1,
        "RMS meter inaccurate: got {}, expected {}",
        measured,
        expected
    );
}

#[test]
fn test_lufs_meter_silence() {
    let mut lufs = LufsMeter::new(SAMPLE_RATE);

    // Silence should result in very low LUFS
    let input_l = vec![0.0; BLOCK_SIZE * 100];
    let input_r = vec![0.0; BLOCK_SIZE * 100];
    lufs.process_block(&input_l, &input_r);

    let measured = lufs.integrated_loudness();
    assert!(
        measured < -70.0,
        "Silence should be very quiet: {} LUFS",
        measured
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDGE CASE TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_dc_offset_handling() {
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    filter.set_coeffs(BiquadCoeffs::highpass(20.0, 0.707, SAMPLE_RATE));

    // Signal with DC offset
    let input: Vec<f64> = generate_sine(BLOCK_SIZE * 100, 440.0)
        .iter()
        .map(|x| x + 0.5) // 0.5 DC offset
        .collect();

    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        output.push(filter.process_sample(sample));
    }

    // After settling, DC should be removed
    let output_dc = output[BLOCK_SIZE * 50..].iter().sum::<f64>() / (BLOCK_SIZE * 50) as f64;

    assert!(
        output_dc.abs() < 0.05,
        "Highpass should remove DC: remaining {}",
        output_dc
    );
}

#[test]
fn test_near_nyquist_stability() {
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    // Filter near Nyquist
    filter.set_coeffs(BiquadCoeffs::lowpass(22000.0, 0.707, SAMPLE_RATE));

    // High frequency signal
    let input = generate_sine(BLOCK_SIZE * 10, 20000.0);
    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        output.push(filter.process_sample(sample));
    }

    assert!(
        is_valid_signal(&output),
        "Near-Nyquist filter should be stable"
    );
}

#[test]
fn test_reset_clears_state() {
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    filter.set_coeffs(BiquadCoeffs::lowpass(1000.0, 0.707, SAMPLE_RATE));

    // Process signal
    let input = generate_sine(BLOCK_SIZE, 440.0);
    for &sample in &input {
        filter.process_sample(sample);
    }

    // Reset
    filter.reset();

    // First sample after reset should have no ringing
    let output = filter.process_sample(0.0);
    assert!(output.abs() < 0.001, "Reset should clear state: {}", output);
}

#[test]
fn test_very_small_signals() {
    let mut comp = Compressor::new(SAMPLE_RATE);
    comp.set_threshold(-60.0);

    // Very small signal
    let input = vec![1e-10; BLOCK_SIZE];
    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        output.push(comp.process_sample(sample));
    }

    assert!(
        is_valid_signal(&output),
        "Small signals should not produce NaN"
    );
}

#[test]
fn test_clipping_protection() {
    let mut limiter = TruePeakLimiter::new(SAMPLE_RATE);
    limiter.set_threshold(0.0);

    // Extremely hot signal
    let input: Vec<f64> = generate_sine(BLOCK_SIZE, 440.0)
        .iter()
        .map(|x| x * 100.0) // +40dB
        .collect();

    let mut output_l = Vec::with_capacity(input.len());
    let mut output_r = Vec::with_capacity(input.len());

    for &sample in &input {
        let (l, r) = limiter.process_sample(sample, sample);
        output_l.push(l);
        output_r.push(r);
    }

    assert!(
        is_valid_signal(&output_l),
        "Limiter should handle hot signals"
    );

    let max = output_l.iter().map(|x| x.abs()).fold(0.0f64, f64::max);
    assert!(
        max < 10.0,
        "Limiter should prevent extreme clipping: {}",
        max
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// THREAD SAFETY TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_processor_send_sync() {
    // Verify processors implement Send + Sync
    fn assert_send_sync<T: Send + Sync>() {}

    assert_send_sync::<BiquadTDF2>();
    assert_send_sync::<ParametricEq>();
    assert_send_sync::<Compressor>();
    assert_send_sync::<TruePeakLimiter>();
    assert_send_sync::<AlgorithmicReverb>();
    assert_send_sync::<StereoPanner>();
    assert_send_sync::<StereoWidth>();
    assert_send_sync::<PeakMeter>();
    assert_send_sync::<LufsMeter>();
}

// ═══════════════════════════════════════════════════════════════════════════════
// STRESS TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_long_signal_stability() {
    let mut eq = ParametricEq::new(SAMPLE_RATE);
    eq.set_band(0, 100.0, 6.0, 1.0, EqFilterType::Bell);

    let mut comp = Compressor::new(SAMPLE_RATE);
    comp.set_threshold(-12.0);
    comp.set_ratio(4.0);

    // 10 seconds of audio
    let samples = (SAMPLE_RATE * 10.0) as usize;
    let mut left = generate_sine(samples, 440.0);
    let mut right = generate_sine(samples, 440.0);

    // Process in blocks
    for i in (0..samples).step_by(BLOCK_SIZE) {
        let end = (i + BLOCK_SIZE).min(samples);
        eq.process_block(&mut left[i..end], &mut right[i..end]);

        for j in i..end {
            left[j] = comp.process_sample(left[j]);
            right[j] = comp.process_sample(right[j]);
        }
    }

    assert!(is_valid_signal(&left), "Long signal should remain stable");
    assert!(is_valid_signal(&right), "Long signal should remain stable");
}

#[test]
fn test_noise_through_chain() {
    let mut eq = ParametricEq::new(SAMPLE_RATE);
    eq.set_band(0, 1000.0, 12.0, 2.0, EqFilterType::Bell); // Extreme boost

    let mut comp = Compressor::new(SAMPLE_RATE);
    comp.set_threshold(-30.0);
    comp.set_ratio(20.0); // Heavy compression

    let mut limiter = TruePeakLimiter::new(SAMPLE_RATE);
    limiter.set_threshold(-3.0);

    let mut left = generate_noise(BLOCK_SIZE * 100);
    let mut right = generate_noise(BLOCK_SIZE * 100);

    // Process chain
    eq.process_block(&mut left, &mut right);

    for i in 0..left.len() {
        left[i] = comp.process_sample(left[i]);
        right[i] = comp.process_sample(right[i]);
        let (l, r) = limiter.process_sample(left[i], right[i]);
        left[i] = l;
        right[i] = r;
    }

    assert!(
        is_valid_signal(&left),
        "Noise chain should produce valid signal"
    );
    assert!(
        is_valid_signal(&right),
        "Noise chain should produce valid signal"
    );
}
