//! Golden Reference Checker — verifies DSP output against known-good values.
//!
//! Generates DSP output from deterministic inputs and compares against
//! saved golden reference values. If no goldens exist, generates them.
//!
//! Exit code 0 = all match, 1 = mismatch or generation failure
//! Output: machine-parseable lines for qa.sh
//!
//! Usage:
//!   cargo run -p rf-bench --release --example golden_check
//!   cargo run -p rf-bench --release --example golden_check -- --regenerate

use rf_dsp::biquad::BiquadTDF2;
use rf_dsp::dynamics::{Compressor, Limiter};
use rf_dsp::spatial::{StereoPanner, StereoWidth};
use rf_dsp::{MonoProcessor, StereoProcessor};
use std::fs;
use std::path::{Path, PathBuf};

const SAMPLE_RATE: f64 = 48000.0;
const BLOCK_SIZE: usize = 512;

/// Tolerance for floating-point comparison (accounts for platform differences)
const TOLERANCE: f64 = 1e-10;

struct GoldenTest {
    name: &'static str,
    /// Returns (output_samples, checksum)
    generate: fn() -> Vec<f64>,
}

/// Generate deterministic sine input
fn test_input() -> Vec<f64> {
    (0..BLOCK_SIZE)
        .map(|i| {
            let t = i as f64 / SAMPLE_RATE;
            (t * 2.0 * std::f64::consts::PI * 1000.0).sin() * 0.8
        })
        .collect()
}

/// Compute a stable fingerprint of audio data
fn fingerprint(data: &[f64]) -> String {
    // Use first 8 stats as fingerprint (portable across platforms)
    let sum: f64 = data.iter().sum();
    let abs_sum: f64 = data.iter().map(|x| x.abs()).sum();
    let max = data.iter().fold(f64::NEG_INFINITY, |a, &b| a.max(b));
    let min = data.iter().fold(f64::INFINITY, |a, &b| a.min(b));
    let rms = (data.iter().map(|x| x * x).sum::<f64>() / data.len() as f64).sqrt();
    let first = data.first().copied().unwrap_or(0.0);
    let last = data.last().copied().unwrap_or(0.0);
    let mid = data.get(data.len() / 2).copied().unwrap_or(0.0);

    format!(
        "{:.15},{:.15},{:.15},{:.15},{:.15},{:.15},{:.15},{:.15}",
        sum, abs_sum, max, min, rms, first, last, mid
    )
}

/// Compare fingerprint values with tolerance
fn fingerprints_match(a: &str, b: &str) -> (bool, f64) {
    let vals_a: Vec<f64> = a.split(',').filter_map(|s| s.trim().parse().ok()).collect();
    let vals_b: Vec<f64> = b.split(',').filter_map(|s| s.trim().parse().ok()).collect();

    if vals_a.len() != vals_b.len() || vals_a.is_empty() {
        return (false, f64::MAX);
    }

    let mut max_rel_diff: f64 = 0.0;
    for (va, vb) in vals_a.iter().zip(vals_b.iter()) {
        let diff = (va - vb).abs();
        let rel = if va.abs() > 1e-20 {
            diff / va.abs()
        } else {
            diff
        };
        max_rel_diff = max_rel_diff.max(rel);
    }

    (max_rel_diff < TOLERANCE, max_rel_diff)
}

fn gen_biquad_lowpass() -> Vec<f64> {
    let input = test_input();
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    filter.set_lowpass(1000.0, 0.707);
    let mut buf = input;
    filter.process_block(&mut buf);
    buf
}

fn gen_biquad_highpass() -> Vec<f64> {
    let input = test_input();
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    filter.set_highpass(500.0, 0.707);
    let mut buf = input;
    filter.process_block(&mut buf);
    buf
}

fn gen_biquad_peaking() -> Vec<f64> {
    let input = test_input();
    let mut filter = BiquadTDF2::new(SAMPLE_RATE);
    filter.set_peaking(2000.0, 1.5, 6.0);
    let mut buf = input;
    filter.process_block(&mut buf);
    buf
}

fn gen_4band_eq() -> Vec<f64> {
    let input = test_input();
    let mut buf = input;
    let mut f0 = BiquadTDF2::new(SAMPLE_RATE);
    f0.set_low_shelf(80.0, 0.707, 3.0);
    f0.process_block(&mut buf);
    let mut f1 = BiquadTDF2::new(SAMPLE_RATE);
    f1.set_peaking(250.0, 2.0, -2.0);
    f1.process_block(&mut buf);
    let mut f2 = BiquadTDF2::new(SAMPLE_RATE);
    f2.set_peaking(2500.0, 1.5, 4.0);
    f2.process_block(&mut buf);
    let mut f3 = BiquadTDF2::new(SAMPLE_RATE);
    f3.set_high_shelf(8000.0, 0.707, 2.0);
    f3.process_block(&mut buf);
    buf
}

fn gen_compressor() -> Vec<f64> {
    let input = test_input();
    let mut comp = Compressor::new(SAMPLE_RATE);
    comp.set_threshold(-20.0);
    comp.set_ratio(4.0);
    comp.set_times(10.0, 100.0);
    comp.set_knee(6.0);
    let mut buf = input;
    comp.process_block(&mut buf);
    buf
}

fn gen_limiter() -> Vec<f64> {
    let input = test_input();
    let mut limiter = Limiter::new(SAMPLE_RATE);
    limiter.set_threshold(-1.0);
    limiter.set_release(50.0);
    let mut buf = input;
    limiter.process_block(&mut buf);
    buf
}

fn gen_stereo_pan() -> Vec<f64> {
    let input = test_input();
    let mut panner = StereoPanner::new();
    panner.set_pan(0.3);
    let mut left = input.clone();
    let mut right = input;
    panner.process_block(&mut left, &mut right);
    // Interleave L/R for fingerprinting
    let mut out = Vec::with_capacity(left.len() * 2);
    for (l, r) in left.iter().zip(right.iter()) {
        out.push(*l);
        out.push(*r);
    }
    out
}

fn gen_stereo_width() -> Vec<f64> {
    let input = test_input();
    let mut width = StereoWidth::new();
    width.set_width(1.5);
    let mut left = input.clone();
    let mut right = input;
    width.process_block(&mut left, &mut right);
    let mut out = Vec::with_capacity(left.len() * 2);
    for (l, r) in left.iter().zip(right.iter()) {
        out.push(*l);
        out.push(*r);
    }
    out
}

fn golden_dir() -> PathBuf {
    // Store goldens in artifacts/qa/goldens/
    let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".to_string());
    Path::new(&manifest)
        .parent()
        .unwrap_or(Path::new("."))
        .parent()
        .unwrap_or(Path::new("."))
        .join("artifacts")
        .join("qa")
        .join("goldens")
}

fn main() {
    let regenerate = std::env::args().any(|a| a == "--regenerate");
    let dir = golden_dir();

    eprintln!("=== DSP Golden Reference Check ===");
    eprintln!("Golden dir: {}", dir.display());

    let tests: Vec<GoldenTest> = vec![
        GoldenTest {
            name: "biquad_lowpass",
            generate: gen_biquad_lowpass,
        },
        GoldenTest {
            name: "biquad_highpass",
            generate: gen_biquad_highpass,
        },
        GoldenTest {
            name: "biquad_peaking",
            generate: gen_biquad_peaking,
        },
        GoldenTest {
            name: "4band_eq",
            generate: gen_4band_eq,
        },
        GoldenTest {
            name: "compressor",
            generate: gen_compressor,
        },
        GoldenTest {
            name: "limiter",
            generate: gen_limiter,
        },
        GoldenTest {
            name: "stereo_pan",
            generate: gen_stereo_pan,
        },
        GoldenTest {
            name: "stereo_width",
            generate: gen_stereo_width,
        },
    ];

    fs::create_dir_all(&dir).expect("Failed to create goldens directory");

    let mut passed = 0;
    let mut failed = 0;
    let mut generated = 0;

    for test in &tests {
        let golden_path = dir.join(format!("{}.golden", test.name));
        let output = (test.generate)();
        let fp = fingerprint(&output);

        if regenerate || !golden_path.exists() {
            // Save golden reference
            fs::write(&golden_path, &fp).expect("Failed to write golden file");
            println!("GOLDEN_GENERATED: {}", test.name);
            generated += 1;
            passed += 1;
        } else {
            // Compare against saved golden
            let saved = fs::read_to_string(&golden_path).expect("Failed to read golden file");
            let (matched, max_diff) = fingerprints_match(saved.trim(), &fp);

            if matched {
                println!("GOLDEN_PASS: {}", test.name);
                passed += 1;
            } else {
                println!("GOLDEN_FAIL: {} max_rel_diff={:.2e}", test.name, max_diff);
                eprintln!("  Expected: {}", saved.trim());
                eprintln!("  Got:      {}", fp);
                failed += 1;
            }
        }
    }

    eprintln!(
        "\n=== Results: {}/{} passed, {} generated ===",
        passed,
        passed + failed,
        generated
    );
    println!(
        "GOLDEN_TOTAL: passed={} failed={} generated={}",
        passed, failed, generated
    );

    if failed > 0 {
        std::process::exit(1);
    }
}
