//! Standalone DSP profiling binary for flamegraph generation.
//!
//! Usage: cargo flamegraph -p rf-bench --example dsp_profile

use rf_dsp::biquad::BiquadTDF2;
use rf_dsp::dynamics::{Compressor, Limiter};
use rf_dsp::spatial::{StereoPanner, StereoWidth};
use rf_dsp::{MonoProcessor, Processor, StereoProcessor};
use std::hint::black_box;
use std::time::Instant;

fn main() {
    let sample_rate = 48000.0;
    let iterations = 100_000;
    let block_size = 1024;
    let total_samples = iterations as f64 * block_size as f64;

    // Generate test buffer (1024-sample sine @ 1kHz)
    let input: Vec<f64> = (0..block_size)
        .map(|i| (i as f64 * 2.0 * std::f64::consts::PI * 1000.0 / sample_rate).sin())
        .collect();

    eprintln!("=== DSP Performance Profile ===");
    eprintln!("Iterations: {iterations}, Block: {block_size} samples");
    eprintln!("Total samples per phase: {:.0}M\n", total_samples / 1_000_000.0);

    // --- Phase 1: Biquad Lowpass (most common DSP op) ---
    let mut filter = BiquadTDF2::new(sample_rate);
    filter.set_lowpass(1000.0, 0.707);
    let t = Instant::now();
    for _ in 0..iterations {
        let mut buf = input.clone();
        filter.process_block(&mut buf);
        filter.reset();
        black_box(&buf);
    }
    let d1 = t.elapsed();
    eprintln!("[1/5] Biquad Lowpass:   {:>8.2}ms  ({:.1} ns/sample, {:.0} Msamples/s)",
        d1.as_secs_f64() * 1000.0,
        d1.as_nanos() as f64 / total_samples,
        total_samples / d1.as_secs_f64() / 1_000_000.0);

    // --- Phase 2: 4-Band EQ Cascade ---
    let mut filters: Vec<BiquadTDF2> = Vec::with_capacity(4);
    let mut f0 = BiquadTDF2::new(sample_rate);
    f0.set_low_shelf(80.0, 0.707, 3.0);
    filters.push(f0);
    let mut f1 = BiquadTDF2::new(sample_rate);
    f1.set_peaking(250.0, 2.0, -2.0);
    filters.push(f1);
    let mut f2 = BiquadTDF2::new(sample_rate);
    f2.set_peaking(2500.0, 1.5, 4.0);
    filters.push(f2);
    let mut f3 = BiquadTDF2::new(sample_rate);
    f3.set_high_shelf(8000.0, 0.707, 2.0);
    filters.push(f3);

    let t = Instant::now();
    for _ in 0..iterations {
        let mut buf = input.clone();
        for f in filters.iter_mut() {
            f.process_block(&mut buf);
        }
        for f in filters.iter_mut() {
            f.reset();
        }
        black_box(&buf);
    }
    let d2 = t.elapsed();
    eprintln!("[2/5] 4-Band EQ:        {:>8.2}ms  ({:.1} ns/sample, {:.0} Msamples/s)",
        d2.as_secs_f64() * 1000.0,
        d2.as_nanos() as f64 / total_samples,
        total_samples / d2.as_secs_f64() / 1_000_000.0);

    // --- Phase 3: Compressor ---
    let mut comp = Compressor::new(sample_rate);
    comp.set_threshold(-20.0);
    comp.set_ratio(4.0);
    comp.set_times(10.0, 100.0);
    comp.set_knee(6.0);

    let t = Instant::now();
    for _ in 0..iterations {
        let mut buf = input.clone();
        comp.process_block(&mut buf);
        comp.reset();
        black_box(&buf);
    }
    let d3 = t.elapsed();
    eprintln!("[3/5] Compressor:       {:>8.2}ms  ({:.1} ns/sample, {:.0} Msamples/s)",
        d3.as_secs_f64() * 1000.0,
        d3.as_nanos() as f64 / total_samples,
        total_samples / d3.as_secs_f64() / 1_000_000.0);

    // --- Phase 4: Limiter ---
    let mut limiter = Limiter::new(sample_rate);
    limiter.set_threshold(-1.0);
    limiter.set_release(50.0);

    let t = Instant::now();
    for _ in 0..iterations {
        let mut buf = input.clone();
        limiter.process_block(&mut buf);
        limiter.reset();
        black_box(&buf);
    }
    let d4 = t.elapsed();
    eprintln!("[4/5] Limiter:          {:>8.2}ms  ({:.1} ns/sample, {:.0} Msamples/s)",
        d4.as_secs_f64() * 1000.0,
        d4.as_nanos() as f64 / total_samples,
        total_samples / d4.as_secs_f64() / 1_000_000.0);

    // --- Phase 5: Stereo Processing (Pan + Width) ---
    let mut panner = StereoPanner::new();
    panner.set_pan(0.3);
    let mut width_proc = StereoWidth::new();
    width_proc.set_width(1.5);

    let input_r = input.clone();
    let t = Instant::now();
    for _ in 0..iterations {
        let mut left = input.clone();
        let mut right = input_r.clone();
        panner.process_block(&mut left, &mut right);
        width_proc.process_block(&mut left, &mut right);
        black_box((&left, &right));
    }
    let d5 = t.elapsed();
    eprintln!("[5/5] Stereo Pan+Width: {:>8.2}ms  ({:.1} ns/sample-pair, {:.0} Mpairs/s)",
        d5.as_secs_f64() * 1000.0,
        d5.as_nanos() as f64 / total_samples,
        total_samples / d5.as_secs_f64() / 1_000_000.0);

    let total = d1 + d2 + d3 + d4 + d5;
    eprintln!("\n=== Summary ===");
    eprintln!("Total:     {:.2}ms", total.as_secs_f64() * 1000.0);
    eprintln!("Breakdown:");
    eprintln!("  Biquad LP:   {:5.1}%", d1.as_secs_f64() / total.as_secs_f64() * 100.0);
    eprintln!("  4-Band EQ:   {:5.1}%", d2.as_secs_f64() / total.as_secs_f64() * 100.0);
    eprintln!("  Compressor:  {:5.1}%", d3.as_secs_f64() / total.as_secs_f64() * 100.0);
    eprintln!("  Limiter:     {:5.1}%", d4.as_secs_f64() / total.as_secs_f64() * 100.0);
    eprintln!("  Stereo:      {:5.1}%", d5.as_secs_f64() / total.as_secs_f64() * 100.0);

    // Real-time safety check
    let audio_budget_ms = block_size as f64 / sample_rate * 1000.0;
    eprintln!("\n=== Real-Time Safety ===");
    eprintln!("Audio budget @ 48kHz/1024: {:.2}ms", audio_budget_ms);
    eprintln!("Biquad LP per block:       {:.3}ms ({:.1}% budget)",
        d1.as_secs_f64() * 1000.0 / iterations as f64,
        d1.as_secs_f64() * 1000.0 / iterations as f64 / audio_budget_ms * 100.0);
    eprintln!("4-Band EQ per block:       {:.3}ms ({:.1}% budget)",
        d2.as_secs_f64() * 1000.0 / iterations as f64,
        d2.as_secs_f64() * 1000.0 / iterations as f64 / audio_budget_ms * 100.0);
    eprintln!("Full chain per block:      {:.3}ms ({:.1}% budget)",
        total.as_secs_f64() * 1000.0 / iterations as f64,
        total.as_secs_f64() * 1000.0 / iterations as f64 / audio_budget_ms * 100.0);
}
