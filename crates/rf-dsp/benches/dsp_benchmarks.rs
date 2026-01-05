//! DSP Performance Benchmarks
//!
//! Measures processing performance for all DSP components.
//! Target: < 20% CPU @ 48kHz stereo on modern hardware

use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId};
use rf_dsp::biquad::{BiquadTDF2, BiquadCoeffs};
use rf_dsp::eq::{ParametricEq, EqFilterType};
use rf_dsp::dynamics::{Compressor, CompressorType, TruePeakLimiter, Gate, StereoCompressor, Oversampling};
use rf_dsp::analysis::{PeakMeter, RmsMeter, TruePeakMeter, LufsMeter, FftAnalyzer};
use rf_dsp::spatial::{StereoPanner, StereoWidth, CorrelationMeter};
use rf_dsp::delay::{Delay, PingPongDelay, ModulatedDelay};
use rf_dsp::reverb::{AlgorithmicReverb, ReverbType};
use rf_dsp::{MonoProcessor, StereoProcessor};

const SAMPLE_RATE: f64 = 48000.0;
const BLOCK_SIZES: &[usize] = &[64, 128, 256, 512, 1024];

/// Generate test audio (440Hz sine wave)
fn generate_test_audio(samples: usize) -> Vec<f64> {
    (0..samples)
        .map(|i| {
            let t = i as f64 / SAMPLE_RATE;
            (2.0 * std::f64::consts::PI * 440.0 * t).sin() * 0.5
        })
        .collect()
}

// ═══════════════════════════════════════════════════════════════════════════════
// BIQUAD FILTER BENCHMARKS
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_biquad(c: &mut Criterion) {
    let mut group = c.benchmark_group("Biquad Filter");

    for &block_size in BLOCK_SIZES {
        group.bench_with_input(
            BenchmarkId::new("TDF2", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut filter = BiquadTDF2::new(SAMPLE_RATE);
                filter.set_coeffs(BiquadCoeffs::lowpass(1000.0, 0.707, SAMPLE_RATE));

                b.iter(|| {
                    let mut sum = 0.0;
                    for &sample in &input {
                        sum += filter.process_sample(black_box(sample));
                    }
                    black_box(sum)
                });
            },
        );
    }

    group.finish();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EQ BENCHMARKS
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_eq(c: &mut Criterion) {
    let mut group = c.benchmark_group("Parametric EQ");

    for &block_size in BLOCK_SIZES {
        // 8-band EQ
        group.bench_with_input(
            BenchmarkId::new("8-band", block_size),
            &block_size,
            |b, &size| {
                let mut left = generate_test_audio(size);
                let mut right = generate_test_audio(size);
                let mut eq8 = ParametricEq::new(SAMPLE_RATE);
                for i in 0..8 {
                    let freq = 100.0 * 2.0_f64.powf(i as f64);
                    eq8.set_band(i, freq, 3.0, 1.0, EqFilterType::Bell);
                }

                b.iter(|| {
                    eq8.process_block(black_box(&mut left), black_box(&mut right));
                });
            },
        );

        // 24-band EQ (Pro-Q style)
        group.bench_with_input(
            BenchmarkId::new("24-band", block_size),
            &block_size,
            |b, &size| {
                let mut left = generate_test_audio(size);
                let mut right = generate_test_audio(size);
                let mut eq24 = ParametricEq::new(SAMPLE_RATE);
                for i in 0..24 {
                    let freq = 50.0 * 2.0_f64.powf(i as f64 * 0.4);
                    eq24.set_band(i, freq.min(20000.0), 2.0, 1.5, EqFilterType::Bell);
                }

                b.iter(|| {
                    eq24.process_block(black_box(&mut left), black_box(&mut right));
                });
            },
        );
    }

    group.finish();
}

// ═══════════════════════════════════════════════════════════════════════════════
// DYNAMICS BENCHMARKS
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_dynamics(c: &mut Criterion) {
    let mut group = c.benchmark_group("Dynamics");

    for &block_size in BLOCK_SIZES {
        // VCA Compressor
        group.bench_with_input(
            BenchmarkId::new("Compressor VCA", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut comp_vca = Compressor::new(SAMPLE_RATE);
                comp_vca.set_type(CompressorType::Vca);
                comp_vca.set_threshold(-20.0);
                comp_vca.set_ratio(4.0);

                b.iter(|| {
                    let mut sum = 0.0;
                    for &sample in &input {
                        sum += comp_vca.process_sample(black_box(sample));
                    }
                    black_box(sum)
                });
            },
        );

        // Opto Compressor
        group.bench_with_input(
            BenchmarkId::new("Compressor Opto", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut comp_opto = Compressor::new(SAMPLE_RATE);
                comp_opto.set_type(CompressorType::Opto);

                b.iter(|| {
                    let mut sum = 0.0;
                    for &sample in &input {
                        sum += comp_opto.process_sample(black_box(sample));
                    }
                    black_box(sum)
                });
            },
        );

        // True Peak Limiter
        group.bench_with_input(
            BenchmarkId::new("True Peak Limiter 4x", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut limiter = TruePeakLimiter::new(SAMPLE_RATE);
                limiter.set_oversampling(Oversampling::X4);

                b.iter(|| {
                    let mut sum = 0.0;
                    for &sample in &input {
                        let (l, r) = limiter.process_sample(black_box(sample), black_box(sample));
                        sum += l + r;
                    }
                    black_box(sum)
                });
            },
        );

        // Gate
        group.bench_with_input(
            BenchmarkId::new("Gate", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut gate = Gate::new(SAMPLE_RATE);
                gate.set_threshold(-40.0);

                b.iter(|| {
                    let mut sum = 0.0;
                    for &sample in &input {
                        sum += gate.process_sample(black_box(sample));
                    }
                    black_box(sum)
                });
            },
        );
    }

    group.finish();
}

// ═══════════════════════════════════════════════════════════════════════════════
// METERING BENCHMARKS
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_metering(c: &mut Criterion) {
    let mut group = c.benchmark_group("Metering");

    for &block_size in BLOCK_SIZES {
        // Peak meter
        group.bench_with_input(
            BenchmarkId::new("Peak", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut peak = PeakMeter::new(SAMPLE_RATE);

                b.iter(|| {
                    peak.process_block(black_box(&input));
                    black_box(peak.current_db())
                });
            },
        );

        // RMS meter
        group.bench_with_input(
            BenchmarkId::new("RMS", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut rms = RmsMeter::new(SAMPLE_RATE, 300.0);

                b.iter(|| {
                    rms.process_block(black_box(&input));
                    black_box(rms.rms())
                });
            },
        );

        // True Peak meter
        group.bench_with_input(
            BenchmarkId::new("True Peak", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut true_peak = TruePeakMeter::new(SAMPLE_RATE);

                b.iter(|| {
                    for &s in &input {
                        true_peak.process(black_box(s));
                    }
                    black_box(true_peak.current_dbtp())
                });
            },
        );

        // LUFS meter
        group.bench_with_input(
            BenchmarkId::new("LUFS", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut lufs = LufsMeter::new(SAMPLE_RATE);

                b.iter(|| {
                    lufs.process_block(black_box(&input));
                    black_box(lufs.integrated())
                });
            },
        );
    }

    group.finish();
}

// ═══════════════════════════════════════════════════════════════════════════════
// FFT BENCHMARKS
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_fft(c: &mut Criterion) {
    let mut group = c.benchmark_group("FFT Analysis");

    for fft_size in [256, 512, 1024, 2048, 4096, 8192] {
        group.bench_with_input(
            BenchmarkId::new("FFT", fft_size),
            &fft_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut analyzer = FftAnalyzer::new(size);

                b.iter(|| {
                    analyzer.push_samples(black_box(&input));
                    analyzer.analyze();
                    black_box(analyzer.magnitudes().len())
                });
            },
        );
    }

    group.finish();
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPATIAL BENCHMARKS
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_spatial(c: &mut Criterion) {
    let mut group = c.benchmark_group("Spatial");

    for &block_size in BLOCK_SIZES {
        // Stereo panner
        group.bench_with_input(
            BenchmarkId::new("Panner", block_size),
            &block_size,
            |b, &size| {
                let left = generate_test_audio(size);
                let right = generate_test_audio(size);
                let mut panner = StereoPanner::new();
                panner.set_pan(0.3);

                b.iter(|| {
                    let mut sum = 0.0;
                    for i in 0..left.len() {
                        let (l, r) = panner.process_sample(black_box(left[i]), black_box(right[i]));
                        sum += l + r;
                    }
                    black_box(sum)
                });
            },
        );

        // Stereo width
        group.bench_with_input(
            BenchmarkId::new("Width", block_size),
            &block_size,
            |b, &size| {
                let left = generate_test_audio(size);
                let right = generate_test_audio(size);
                let mut width = StereoWidth::new();
                width.set_width(1.5);

                b.iter(|| {
                    let mut sum = 0.0;
                    for i in 0..left.len() {
                        let (l, r) = width.process_sample(black_box(left[i]), black_box(right[i]));
                        sum += l + r;
                    }
                    black_box(sum)
                });
            },
        );

        // Correlation meter
        group.bench_with_input(
            BenchmarkId::new("Correlation", block_size),
            &block_size,
            |b, &size| {
                let left = generate_test_audio(size);
                let right = generate_test_audio(size);
                let mut corr = CorrelationMeter::new(SAMPLE_RATE);

                b.iter(|| {
                    for i in 0..left.len() {
                        corr.process(black_box(left[i]), black_box(right[i]));
                    }
                    black_box(corr.correlation())
                });
            },
        );
    }

    group.finish();
}

// ═══════════════════════════════════════════════════════════════════════════════
// DELAY BENCHMARKS
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_delay(c: &mut Criterion) {
    let mut group = c.benchmark_group("Delay");

    for &block_size in BLOCK_SIZES {
        // Simple delay (mono)
        group.bench_with_input(
            BenchmarkId::new("Mono Delay", block_size),
            &block_size,
            |b, &size| {
                let input = generate_test_audio(size);
                let mut delay_line = Delay::new(SAMPLE_RATE, 1000.0);
                delay_line.set_delay_ms(250.0);
                delay_line.set_feedback(0.3);

                b.iter(|| {
                    let mut sum = 0.0;
                    for &sample in &input {
                        sum += delay_line.process_sample(black_box(sample));
                    }
                    black_box(sum)
                });
            },
        );

        // Ping-pong delay
        group.bench_with_input(
            BenchmarkId::new("Ping-Pong", block_size),
            &block_size,
            |b, &size| {
                let left = generate_test_audio(size);
                let right = generate_test_audio(size);
                let mut pingpong = PingPongDelay::new(SAMPLE_RATE, 1000.0);
                pingpong.set_delay_ms(300.0);

                b.iter(|| {
                    let mut sum = 0.0;
                    for i in 0..left.len() {
                        let (l, r) = pingpong.process_sample(black_box(left[i]), black_box(right[i]));
                        sum += l + r;
                    }
                    black_box(sum)
                });
            },
        );

        // Modulated delay (chorus)
        group.bench_with_input(
            BenchmarkId::new("Chorus", block_size),
            &block_size,
            |b, &size| {
                let left = generate_test_audio(size);
                let right = generate_test_audio(size);
                let mut chorus = ModulatedDelay::chorus(SAMPLE_RATE);

                b.iter(|| {
                    let mut sum = 0.0;
                    for i in 0..left.len() {
                        let (l, r) = chorus.process_sample(black_box(left[i]), black_box(right[i]));
                        sum += l + r;
                    }
                    black_box(sum)
                });
            },
        );
    }

    group.finish();
}

// ═══════════════════════════════════════════════════════════════════════════════
// REVERB BENCHMARKS
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_reverb(c: &mut Criterion) {
    let mut group = c.benchmark_group("Reverb");
    group.sample_size(50); // Reverb is heavier

    for &block_size in &[256, 512, 1024] {
        // Algorithmic reverb - Hall
        group.bench_with_input(
            BenchmarkId::new("Algorithmic Hall", block_size),
            &block_size,
            |b, &size| {
                let left = generate_test_audio(size);
                let right = generate_test_audio(size);
                let mut reverb_hall = AlgorithmicReverb::new(SAMPLE_RATE);
                reverb_hall.set_type(ReverbType::Hall);

                b.iter(|| {
                    let mut sum = 0.0;
                    for i in 0..left.len() {
                        let (l, r) = reverb_hall.process_sample(black_box(left[i]), black_box(right[i]));
                        sum += l + r;
                    }
                    black_box(sum)
                });
            },
        );

        // Algorithmic reverb - Plate
        group.bench_with_input(
            BenchmarkId::new("Algorithmic Plate", block_size),
            &block_size,
            |b, &size| {
                let left = generate_test_audio(size);
                let right = generate_test_audio(size);
                let mut reverb_plate = AlgorithmicReverb::new(SAMPLE_RATE);
                reverb_plate.set_type(ReverbType::Plate);

                b.iter(|| {
                    let mut sum = 0.0;
                    for i in 0..left.len() {
                        let (l, r) = reverb_plate.process_sample(black_box(left[i]), black_box(right[i]));
                        sum += l + r;
                    }
                    black_box(sum)
                });
            },
        );
    }

    group.finish();
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMBINED CHANNEL STRIP BENCHMARK
// ═══════════════════════════════════════════════════════════════════════════════

fn bench_channel_strip(c: &mut Criterion) {
    let mut group = c.benchmark_group("Channel Strip");
    group.sample_size(50);

    for &block_size in BLOCK_SIZES {
        // Full channel strip: EQ + Compressor + Limiter
        group.bench_with_input(
            BenchmarkId::new("EQ+Comp+Limiter", block_size),
            &block_size,
            |b, &size| {
                let mut eq = ParametricEq::new(SAMPLE_RATE);
                eq.set_band(0, 80.0, 3.0, 0.7, EqFilterType::LowShelf);
                eq.set_band(1, 250.0, -2.0, 2.0, EqFilterType::Bell);
                eq.set_band(2, 3000.0, 2.0, 1.5, EqFilterType::Bell);
                eq.set_band(3, 10000.0, 3.0, 0.7, EqFilterType::HighShelf);

                let mut comp = StereoCompressor::new(SAMPLE_RATE);
                comp.set_both(|c| {
                    c.set_threshold(-18.0);
                    c.set_ratio(3.0);
                    c.set_times(10.0, 100.0);
                });

                let mut limiter = TruePeakLimiter::new(SAMPLE_RATE);
                limiter.set_threshold(-1.0);

                b.iter(|| {
                    let mut left = generate_test_audio(size);
                    let mut right = generate_test_audio(size);

                    eq.process_block(&mut left, &mut right);

                    for i in 0..left.len() {
                        let (l, r) = comp.process_sample(left[i], right[i]);
                        let (ol, or) = limiter.process_sample(l, r);
                        left[i] = ol;
                        right[i] = or;
                    }

                    black_box(left.iter().sum::<f64>() + right.iter().sum::<f64>())
                });
            },
        );
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_biquad,
    bench_eq,
    bench_dynamics,
    bench_metering,
    bench_fft,
    bench_spatial,
    bench_delay,
    bench_reverb,
    bench_channel_strip,
);

criterion_main!(benches);
