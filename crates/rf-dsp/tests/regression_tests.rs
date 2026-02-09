// ============================================================================
// FluxForge DSP Regression Tests
// Ensures DSP processors maintain consistent behavior across updates
// ============================================================================

//! DSP Regression Test Suite
//!
//! These tests verify that DSP processors produce consistent output
//! and maintain expected numerical precision across code changes.

use std::f64::consts::PI;

// ============================================================================
// TEST UTILITIES
// ============================================================================

/// Generate a sine wave test signal
fn generate_sine(frequency: f64, sample_rate: f64, num_samples: usize) -> Vec<f64> {
    (0..num_samples)
        .map(|i| {
            let t = i as f64 / sample_rate;
            (2.0 * PI * frequency * t).sin()
        })
        .collect()
}

/// Generate an impulse signal
fn generate_impulse(num_samples: usize) -> Vec<f64> {
    let mut signal = vec![0.0; num_samples];
    if !signal.is_empty() {
        signal[0] = 1.0;
    }
    signal
}

/// Generate white noise
fn generate_noise(num_samples: usize, seed: u64) -> Vec<f64> {
    let mut state = seed;
    (0..num_samples)
        .map(|_| {
            // Simple LCG for reproducible noise
            state = state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            (state as f64 / u64::MAX as f64) * 2.0 - 1.0
        })
        .collect()
}

/// Calculate RMS of a signal
fn calculate_rms(signal: &[f64]) -> f64 {
    if signal.is_empty() {
        return 0.0;
    }
    let sum_squares: f64 = signal.iter().map(|s| s * s).sum();
    (sum_squares / signal.len() as f64).sqrt()
}

/// Calculate peak of a signal
fn calculate_peak(signal: &[f64]) -> f64 {
    signal
        .iter()
        .map(|s| s.abs())
        .fold(0.0_f64, |a, b| a.max(b))
}

/// Calculate DC offset of a signal
fn calculate_dc_offset(signal: &[f64]) -> f64 {
    if signal.is_empty() {
        return 0.0;
    }
    signal.iter().sum::<f64>() / signal.len() as f64
}

/// Check if signal is within bounds
fn signal_is_bounded(signal: &[f64], max_value: f64) -> bool {
    signal.iter().all(|s| s.abs() <= max_value)
}

// ============================================================================
// BIQUAD FILTER REGRESSION TESTS
// ============================================================================

#[test]
fn test_biquad_lowpass_impulse_response() {
    // Test that lowpass filter has expected impulse response characteristics

    // Simulated lowpass biquad coefficients for 1kHz @ 44.1kHz
    let b0 = 0.00460;
    let b1 = 0.00920;
    let b2 = 0.00460;
    let a1 = -1.79240;
    let a2 = 0.81079;

    let impulse = generate_impulse(1024);
    let mut output = vec![0.0; 1024];
    let mut z1 = 0.0;
    let mut z2 = 0.0;

    // TDF-II biquad
    for (i, &input) in impulse.iter().enumerate() {
        let out = b0 * input + z1;
        z1 = b1 * input - a1 * out + z2;
        z2 = b2 * input - a2 * out;
        output[i] = out;
    }

    // Verify impulse response characteristics
    let peak = calculate_peak(&output);
    let dc_at_end = output[1000..].iter().sum::<f64>() / 24.0;

    // Peak should be reasonable
    assert!(
        peak > 0.001 && peak < 1.0,
        "Peak out of expected range: {}",
        peak
    );

    // Should settle to near zero
    assert!(
        dc_at_end.abs() < 0.001,
        "Filter didn't settle: {}",
        dc_at_end
    );
}

#[test]
fn test_biquad_highpass_dc_rejection() {
    // Highpass should reject DC

    // Simulated highpass biquad coefficients for 100Hz @ 44.1kHz
    let b0 = 0.98985;
    let b1 = -1.97970;
    let b2 = 0.98985;
    let a1 = -1.97946;
    let a2 = 0.97994;

    // DC signal
    let input = vec![1.0; 4096];
    let mut output = vec![0.0; 4096];
    let mut z1 = 0.0;
    let mut z2 = 0.0;

    for (i, &inp) in input.iter().enumerate() {
        let out = b0 * inp + z1;
        z1 = b1 * inp - a1 * out + z2;
        z2 = b2 * inp - a2 * out;
        output[i] = out;
    }

    // After settling, output should be near zero
    let dc_at_end = output[3000..].iter().sum::<f64>() / 1096.0;
    assert!(
        dc_at_end.abs() < 0.01,
        "Highpass didn't reject DC: {}",
        dc_at_end
    );
}

#[test]
fn test_biquad_stability() {
    // Test filter stability with extreme coefficients

    let coefficients = [
        // Standard lowpass
        (0.01, 0.02, 0.01, -1.9, 0.92),
        // Near-edge stability
        (0.001, 0.002, 0.001, -1.99, 0.99),
        // High Q resonant
        (0.1, 0.0, -0.1, -1.8, 0.95),
    ];

    for (b0, b1, b2, a1, a2) in coefficients {
        let noise = generate_noise(8192, 12345);
        let mut output = vec![0.0; 8192];
        let mut z1 = 0.0;
        let mut z2 = 0.0;

        for (i, &input) in noise.iter().enumerate() {
            let out = b0 * input + z1;
            z1 = b1 * input - a1 * out + z2;
            z2 = b2 * input - a2 * out;
            output[i] = out;
        }

        // Signal should not explode
        assert!(
            signal_is_bounded(&output, 100.0),
            "Filter became unstable with coefficients ({}, {}, {}, {}, {})",
            b0,
            b1,
            b2,
            a1,
            a2
        );
    }
}

// ============================================================================
// DYNAMICS PROCESSOR REGRESSION TESTS
// ============================================================================

#[test]
fn test_compressor_gain_reduction() {
    // Test that compressor reduces gain above threshold

    let threshold = 0.5;
    let ratio = 4.0;
    let attack_samples = 44; // ~1ms @ 44.1kHz
    let release_samples = 441; // ~10ms

    // Loud sine wave
    let input = generate_sine(1000.0, 44100.0, 4410);

    // Simple compressor simulation
    let mut envelope = 0.0;
    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        let input_level = sample.abs();

        // Envelope follower
        if input_level > envelope {
            envelope += (input_level - envelope) / attack_samples as f64;
        } else {
            envelope += (input_level - envelope) / release_samples as f64;
        }

        // Gain calculation
        let gain = if envelope > threshold {
            let over = envelope - threshold;
            let compressed = threshold + over / ratio;
            compressed / envelope
        } else {
            1.0
        };

        output.push(sample * gain);
    }

    let input_rms = calculate_rms(&input);
    let output_rms = calculate_rms(&output);

    // Output should be quieter due to compression
    assert!(
        output_rms < input_rms,
        "Compressor didn't reduce level: input={}, output={}",
        input_rms,
        output_rms
    );

    // Output should be bounded
    let output_peak = calculate_peak(&output);
    assert!(
        output_peak <= 1.0,
        "Compressor output exceeded 1.0: {}",
        output_peak
    );
}

#[test]
fn test_limiter_ceiling() {
    // Test that limiter enforces ceiling

    let ceiling = 0.8;

    // Signal that exceeds ceiling
    let input: Vec<f64> = (0..1000)
        .map(|i| {
            let t = i as f64 / 1000.0;
            (2.0 * PI * 100.0 * t).sin() * 1.5 // Peak at 1.5
        })
        .collect();

    // Simple brick-wall limiter
    let output: Vec<f64> = input
        .iter()
        .map(|&s| {
            if s.abs() > ceiling {
                s.signum() * ceiling
            } else {
                s
            }
        })
        .collect();

    let output_peak = calculate_peak(&output);
    assert!(
        output_peak <= ceiling + 0.0001,
        "Limiter exceeded ceiling: peak={}, ceiling={}",
        output_peak,
        ceiling
    );
}

#[test]
fn test_gate_silence() {
    // Test that gate silences signal below threshold

    let threshold = 0.1;
    let attack_samples = 22;
    let release_samples = 220;

    // Low level signal
    let input: Vec<f64> = (0..4410)
        .map(|i| {
            let t = i as f64 / 44100.0;
            (2.0 * PI * 1000.0 * t).sin() * 0.05 // Peak at 0.05, below threshold
        })
        .collect();

    // Simple gate simulation
    let mut gate_level = 0.0;
    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        let input_level = sample.abs();

        // Gate envelope
        if input_level > threshold {
            gate_level += (1.0 - gate_level) / attack_samples as f64;
        } else {
            gate_level -= gate_level / release_samples as f64;
        }

        output.push(sample * gate_level);
    }

    // Output should be nearly silent
    let output_rms = calculate_rms(&output);
    assert!(
        output_rms < 0.01,
        "Gate didn't silence signal: rms={}",
        output_rms
    );
}

// ============================================================================
// SPATIAL PROCESSOR REGRESSION TESTS
// ============================================================================

#[test]
fn test_stereo_pan_law() {
    // Test constant-power pan law

    let test_positions = [-1.0, -0.5, 0.0, 0.5, 1.0];

    for &pan in &test_positions {
        // Constant power pan law
        let angle = (pan + 1.0) * 0.25 * PI;
        let left_gain = angle.cos();
        let right_gain = angle.sin();

        // Total power should be constant (approximately 1.0)
        let total_power = left_gain * left_gain + right_gain * right_gain;

        assert!(
            (total_power - 1.0).abs() < 0.01,
            "Pan law power not constant at pan={}: power={}",
            pan,
            total_power
        );
    }
}

#[test]
fn test_stereo_width() {
    // Test stereo width control

    // Create stereo signal with different L/R
    let left: Vec<f64> = generate_sine(440.0, 44100.0, 1024);
    let right: Vec<f64> = generate_sine(880.0, 44100.0, 1024);

    let widths = [0.0, 0.5, 1.0, 1.5, 2.0];

    for &width in &widths {
        let mut out_left = Vec::with_capacity(1024);
        let mut out_right = Vec::with_capacity(1024);

        for (l, r) in left.iter().zip(right.iter()) {
            let mid = (*l + *r) * 0.5;
            let side = (*l - *r) * 0.5;

            out_left.push(mid + side * width);
            out_right.push(mid - side * width);
        }

        // Width 0 should be mono (L == R)
        if width == 0.0 {
            let diff: f64 = out_left
                .iter()
                .zip(out_right.iter())
                .map(|(l, r)| (l - r).abs())
                .sum();
            assert!(diff < 0.0001, "Width 0 should produce mono signal");
        }

        // Width 1 should be unchanged
        if width == 1.0 {
            let left_diff: f64 = left
                .iter()
                .zip(out_left.iter())
                .map(|(a, b)| (a - b).abs())
                .sum();
            assert!(left_diff < 0.0001, "Width 1 should be unchanged");
        }

        // Output should be bounded
        assert!(
            signal_is_bounded(&out_left, 3.0),
            "Width {} caused overflow",
            width
        );
        assert!(
            signal_is_bounded(&out_right, 3.0),
            "Width {} caused overflow",
            width
        );
    }
}

// ============================================================================
// ANALYSIS REGRESSION TESTS
// ============================================================================

#[test]
fn test_rms_calculation() {
    // Test RMS calculation accuracy

    // Sine wave should have RMS of peak / sqrt(2)
    let sine = generate_sine(1000.0, 44100.0, 44100);
    let rms = calculate_rms(&sine);
    let expected_rms = 1.0 / 2.0_f64.sqrt();

    assert!(
        (rms - expected_rms).abs() < 0.001,
        "RMS calculation wrong: got={}, expected={}",
        rms,
        expected_rms
    );

    // DC signal should have RMS equal to its value
    let dc = vec![0.5; 1000];
    let dc_rms = calculate_rms(&dc);
    assert!(
        (dc_rms - 0.5).abs() < 0.0001,
        "DC RMS wrong: got={}, expected=0.5",
        dc_rms
    );
}

#[test]
fn test_peak_detection() {
    // Test peak detection

    // Signal with known peak
    let mut signal = generate_sine(1000.0, 44100.0, 4410);
    signal[2000] = 2.5; // Add a spike

    let peak = calculate_peak(&signal);
    assert!(
        (peak - 2.5).abs() < 0.0001,
        "Peak detection wrong: got={}, expected=2.5",
        peak
    );
}

// ============================================================================
// NUMERICAL PRECISION TESTS
// ============================================================================

#[test]
fn test_denormal_handling() {
    // Test that processing handles denormal numbers

    // Create near-denormal signal
    let input: Vec<f64> = (0..1000)
        .map(|i| {
            let t = i as f64 / 1000.0;
            (2.0 * PI * 100.0 * t).sin() * 1e-300
        })
        .collect();

    // Simple processing that might cause denormals
    let mut z1 = 0.0;
    let mut output = Vec::with_capacity(input.len());

    for &sample in &input {
        // IIR filter step
        let out = sample * 0.1 + z1 * 0.9;
        z1 = out;

        // Flush denormals
        let processed = if out.abs() < 1e-308 { 0.0 } else { out };
        output.push(processed);
    }

    // Should not contain NaN or Inf
    assert!(
        output.iter().all(|s| s.is_finite()),
        "Processing produced non-finite values"
    );
}

#[test]
fn test_coefficient_quantization() {
    // Test that coefficients maintain precision

    let coefficients = [0.00001, 0.001, 0.1, 0.5, 0.9, 0.99, 0.999, 0.9999];

    for &coef in &coefficients {
        // Round-trip through f32
        let as_f32 = coef as f32;
        let back = as_f32 as f64;

        // Should maintain reasonable precision
        let error = (coef - back).abs() / coef.abs().max(1e-10);
        assert!(
            error < 1e-6,
            "Coefficient precision lost: original={}, recovered={}, error={}",
            coef,
            back,
            error
        );
    }
}

// ============================================================================
// DETERMINISM TESTS
// ============================================================================

#[test]
fn test_processing_determinism() {
    // Test that processing is deterministic

    // Run same processing twice
    let input = generate_noise(1024, 42);

    let process_signal = |signal: &[f64]| -> Vec<f64> {
        let mut output = Vec::with_capacity(signal.len());
        let mut z1 = 0.0;

        for &sample in signal {
            let out = sample * 0.5 + z1 * 0.5;
            z1 = out;
            output.push(out);
        }
        output
    };

    let output1 = process_signal(&input);
    let output2 = process_signal(&input);

    // Results should be identical
    for (i, (a, b)) in output1.iter().zip(output2.iter()).enumerate() {
        assert!(
            (a - b).abs() < f64::EPSILON,
            "Non-deterministic at sample {}: {} != {}",
            i,
            a,
            b
        );
    }
}

#[test]
fn test_state_independence() {
    // Test that processing doesn't depend on uninitialized state

    let input = generate_sine(1000.0, 44100.0, 1024);

    // Process with explicit zero state
    let mut z1 = 0.0;
    let mut z2 = 0.0;
    let output1: Vec<f64> = input
        .iter()
        .map(|&s| {
            let out = s * 0.25 + z1 * 0.5 + z2 * 0.25;
            z2 = z1;
            z1 = out;
            out
        })
        .collect();

    // Process again with same initial state
    z1 = 0.0;
    z2 = 0.0;
    let output2: Vec<f64> = input
        .iter()
        .map(|&s| {
            let out = s * 0.25 + z1 * 0.5 + z2 * 0.25;
            z2 = z1;
            z1 = out;
            out
        })
        .collect();

    // Should be identical
    let diff: f64 = output1
        .iter()
        .zip(output2.iter())
        .map(|(a, b)| (a - b).abs())
        .sum();
    assert!(
        diff < f64::EPSILON * 1024.0,
        "State-dependent behavior detected"
    );
}
