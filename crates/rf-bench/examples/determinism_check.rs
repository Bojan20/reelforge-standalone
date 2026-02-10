//! Determinism Checker — verifies DSP bit-exact reproducibility.
//!
//! Runs identical DSP operations multiple times with same input,
//! verifies output is bit-exact across all runs.
//!
//! Exit code 0 = deterministic, 1 = non-deterministic
//! Output: machine-parseable lines for qa.sh

use rf_dsp::biquad::BiquadTDF2;
use rf_dsp::dynamics::{Compressor, Limiter};
use rf_dsp::spatial::{StereoPanner, StereoWidth};
use rf_dsp::{MonoProcessor, StereoProcessor};
use std::hint::black_box;

const SAMPLE_RATE: f64 = 48000.0;
const BLOCK_SIZE: usize = 1024;
const NUM_RUNS: usize = 5;

/// Generate deterministic test signal (sine + harmonics)
fn generate_test_signal() -> Vec<f64> {
    (0..BLOCK_SIZE)
        .map(|i| {
            let t = i as f64 / SAMPLE_RATE;
            let fundamental = (t * 2.0 * std::f64::consts::PI * 440.0).sin();
            let harmonic2 = (t * 2.0 * std::f64::consts::PI * 880.0).sin() * 0.5;
            let harmonic3 = (t * 2.0 * std::f64::consts::PI * 1320.0).sin() * 0.25;
            (fundamental + harmonic2 + harmonic3) * 0.5
        })
        .collect()
}

/// Compare two buffers for bit-exact match
fn buffers_match(a: &[f64], b: &[f64]) -> (bool, f64, Option<usize>) {
    if a.len() != b.len() {
        return (false, f64::MAX, Some(0));
    }
    let mut max_diff: f64 = 0.0;
    let mut max_diff_idx: Option<usize> = None;
    for (i, (va, vb)) in a.iter().zip(b.iter()).enumerate() {
        let diff = (va - vb).abs();
        if diff > max_diff {
            max_diff = diff;
            max_diff_idx = Some(i);
        }
    }
    (max_diff == 0.0, max_diff, max_diff_idx)
}

fn check_biquad() -> bool {
    let input = generate_test_signal();
    let mut results: Vec<Vec<f64>> = Vec::new();

    for _ in 0..NUM_RUNS {
        let mut filter = BiquadTDF2::new(SAMPLE_RATE);
        filter.set_lowpass(1000.0, 0.707);
        let mut buf = input.clone();
        filter.process_block(&mut buf);
        results.push(buf);
    }

    let reference = &results[0];
    let mut all_match = true;
    for (run, result) in results.iter().enumerate().skip(1) {
        let (matched, max_diff, idx) = buffers_match(reference, result);
        if !matched {
            eprintln!(
                "DETERMINISM_FAIL: biquad run {} differs: max_diff={:.2e} at sample {}",
                run,
                max_diff,
                idx.unwrap_or(0)
            );
            all_match = false;
        }
    }
    all_match
}

fn check_compressor() -> bool {
    let input = generate_test_signal();
    let mut results: Vec<Vec<f64>> = Vec::new();

    for _ in 0..NUM_RUNS {
        let mut comp = Compressor::new(SAMPLE_RATE);
        comp.set_threshold(-20.0);
        comp.set_ratio(4.0);
        comp.set_times(10.0, 100.0);
        comp.set_knee(6.0);
        let mut buf = input.clone();
        comp.process_block(&mut buf);
        results.push(buf);
    }

    let reference = &results[0];
    let mut all_match = true;
    for (run, result) in results.iter().enumerate().skip(1) {
        let (matched, max_diff, idx) = buffers_match(reference, result);
        if !matched {
            eprintln!(
                "DETERMINISM_FAIL: compressor run {} differs: max_diff={:.2e} at sample {}",
                run,
                max_diff,
                idx.unwrap_or(0)
            );
            all_match = false;
        }
    }
    all_match
}

fn check_limiter() -> bool {
    let input = generate_test_signal();
    let mut results: Vec<Vec<f64>> = Vec::new();

    for _ in 0..NUM_RUNS {
        let mut limiter = Limiter::new(SAMPLE_RATE);
        limiter.set_threshold(-1.0);
        limiter.set_release(50.0);
        let mut buf = input.clone();
        limiter.process_block(&mut buf);
        results.push(buf);
    }

    let reference = &results[0];
    let mut all_match = true;
    for (run, result) in results.iter().enumerate().skip(1) {
        let (matched, max_diff, idx) = buffers_match(reference, result);
        if !matched {
            eprintln!(
                "DETERMINISM_FAIL: limiter run {} differs: max_diff={:.2e} at sample {}",
                run,
                max_diff,
                idx.unwrap_or(0)
            );
            all_match = false;
        }
    }
    all_match
}

fn check_stereo() -> bool {
    let input = generate_test_signal();
    let mut results_l: Vec<Vec<f64>> = Vec::new();
    let mut results_r: Vec<Vec<f64>> = Vec::new();

    for _ in 0..NUM_RUNS {
        let mut panner = StereoPanner::new();
        panner.set_pan(0.3);
        let mut width = StereoWidth::new();
        width.set_width(1.5);

        let mut left = input.clone();
        let mut right = input.clone();
        panner.process_block(&mut left, &mut right);
        width.process_block(&mut left, &mut right);
        results_l.push(left);
        results_r.push(right);
    }

    let ref_l = &results_l[0];
    let ref_r = &results_r[0];
    let mut all_match = true;

    for run in 1..NUM_RUNS {
        let (ml, dl, il) = buffers_match(ref_l, &results_l[run]);
        let (mr, dr, ir) = buffers_match(ref_r, &results_r[run]);
        if !ml || !mr {
            eprintln!(
                "DETERMINISM_FAIL: stereo run {} L_diff={:.2e}@{} R_diff={:.2e}@{}",
                run,
                dl,
                il.unwrap_or(0),
                dr,
                ir.unwrap_or(0)
            );
            all_match = false;
        }
    }
    all_match
}

fn check_4band_eq_cascade() -> bool {
    let input = generate_test_signal();
    let mut results: Vec<Vec<f64>> = Vec::new();

    for _ in 0..NUM_RUNS {
        let mut filters: Vec<BiquadTDF2> = Vec::with_capacity(4);
        let mut f0 = BiquadTDF2::new(SAMPLE_RATE);
        f0.set_low_shelf(80.0, 0.707, 3.0);
        filters.push(f0);
        let mut f1 = BiquadTDF2::new(SAMPLE_RATE);
        f1.set_peaking(250.0, 2.0, -2.0);
        filters.push(f1);
        let mut f2 = BiquadTDF2::new(SAMPLE_RATE);
        f2.set_peaking(2500.0, 1.5, 4.0);
        filters.push(f2);
        let mut f3 = BiquadTDF2::new(SAMPLE_RATE);
        f3.set_high_shelf(8000.0, 0.707, 2.0);
        filters.push(f3);

        let mut buf = input.clone();
        for f in filters.iter_mut() {
            f.process_block(&mut buf);
        }
        results.push(buf);
    }

    let reference = &results[0];
    let mut all_match = true;
    for (run, result) in results.iter().enumerate().skip(1) {
        let (matched, max_diff, idx) = buffers_match(reference, result);
        if !matched {
            eprintln!(
                "DETERMINISM_FAIL: 4band_eq run {} differs: max_diff={:.2e} at sample {}",
                run,
                max_diff,
                idx.unwrap_or(0)
            );
            all_match = false;
        }
    }
    all_match
}

fn main() {
    eprintln!(
        "=== DSP Determinism Check ({} runs per processor) ===",
        NUM_RUNS
    );

    let checks: Vec<(&str, fn() -> bool)> = vec![
        ("biquad_lowpass", check_biquad),
        ("4band_eq_cascade", check_4band_eq_cascade),
        ("compressor", check_compressor),
        ("limiter", check_limiter),
        ("stereo_pan_width", check_stereo),
    ];

    let mut passed = 0;
    let mut failed = 0;

    for (name, check_fn) in &checks {
        let ok = black_box(check_fn());
        if ok {
            // Machine-parseable output for qa.sh
            println!("DETERMINISM_PASS: {}", name);
            passed += 1;
        } else {
            println!("DETERMINISM_FAIL: {}", name);
            failed += 1;
        }
    }

    eprintln!("\n=== Results: {}/{} passed ===", passed, passed + failed);
    println!("DETERMINISM_TOTAL: passed={} failed={}", passed, failed);

    if failed > 0 {
        std::process::exit(1);
    }
}
