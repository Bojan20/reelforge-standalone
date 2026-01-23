//! DSP Processor Benchmarks
//!
//! Benchmarks for core DSP processors: filters, dynamics, gain.

use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use rf_bench::{generate_audio_buffer, generate_sine_buffer, BUFFER_SIZES};
use rf_dsp::biquad::{BiquadCoeffs, BiquadFilter, FilterType};
use rf_dsp::dynamics::{Compressor, CompressorParams, Limiter};
use rf_dsp::spatial::{StereoPanner, StereoWidth};

const SAMPLE_RATE: f64 = 48000.0;

fn bench_biquad_lowpass(c: &mut Criterion) {
    let mut group = c.benchmark_group("biquad_lowpass");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_sine_buffer(size, 1000.0, SAMPLE_RATE);
        let coeffs = BiquadCoeffs::lowpass(1000.0, 0.707, SAMPLE_RATE);
        let mut filter = BiquadFilter::new(coeffs);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                for sample in output.iter_mut() {
                    *sample = filter.process_sample(black_box(*sample));
                }
                filter.reset();
                black_box(output)
            })
        });
    }

    group.finish();
}

fn bench_biquad_peaking(c: &mut Criterion) {
    let mut group = c.benchmark_group("biquad_peaking");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);
        let coeffs = BiquadCoeffs::peaking(1000.0, 2.0, 6.0, SAMPLE_RATE);
        let mut filter = BiquadFilter::new(coeffs);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                for sample in output.iter_mut() {
                    *sample = filter.process_sample(black_box(*sample));
                }
                filter.reset();
                black_box(output)
            })
        });
    }

    group.finish();
}

fn bench_biquad_cascade(c: &mut Criterion) {
    let mut group = c.benchmark_group("biquad_cascade_4");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);

        // 4-band EQ (typical parametric EQ)
        let coeffs = [
            BiquadCoeffs::lowshelf(80.0, 0.707, 3.0, SAMPLE_RATE),
            BiquadCoeffs::peaking(250.0, 2.0, -2.0, SAMPLE_RATE),
            BiquadCoeffs::peaking(2500.0, 1.5, 4.0, SAMPLE_RATE),
            BiquadCoeffs::highshelf(8000.0, 0.707, 2.0, SAMPLE_RATE),
        ];
        let mut filters: Vec<BiquadFilter> = coeffs.iter().map(|&c| BiquadFilter::new(c)).collect();

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                for sample in output.iter_mut() {
                    let mut s = black_box(*sample);
                    for filter in filters.iter_mut() {
                        s = filter.process_sample(s);
                    }
                    *sample = s;
                }
                for filter in filters.iter_mut() {
                    filter.reset();
                }
                black_box(output)
            })
        });
    }

    group.finish();
}

fn bench_compressor(c: &mut Criterion) {
    let mut group = c.benchmark_group("compressor");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);
        let params = CompressorParams {
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            knee_db: 6.0,
            makeup_db: 0.0,
        };
        let mut comp = Compressor::new(SAMPLE_RATE, params);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                for sample in output.iter_mut() {
                    *sample = comp.process_sample(black_box(*sample));
                }
                comp.reset();
                black_box(output)
            })
        });
    }

    group.finish();
}

fn bench_limiter(c: &mut Criterion) {
    let mut group = c.benchmark_group("limiter");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);
        let mut limiter = Limiter::new(SAMPLE_RATE, -1.0, 5.0, 50.0);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                for sample in output.iter_mut() {
                    *sample = limiter.process_sample(black_box(*sample));
                }
                limiter.reset();
                black_box(output)
            })
        });
    }

    group.finish();
}

fn bench_stereo_panner(c: &mut Criterion) {
    let mut group = c.benchmark_group("stereo_panner");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);
        let panner = StereoPanner::new(0.3); // Pan slightly right

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut left = input.clone();
                let mut right = input.clone();
                panner.process_stereo(&mut left, &mut right);
                black_box((left, right))
            })
        });
    }

    group.finish();
}

fn bench_stereo_width(c: &mut Criterion) {
    let mut group = c.benchmark_group("stereo_width");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let left = generate_audio_buffer(size, 42);
        let right = generate_audio_buffer(size, 43);
        let width = StereoWidth::new(1.5); // Wider stereo

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut l = left.clone();
                let mut r = right.clone();
                width.process(&mut l, &mut r);
                black_box((l, r))
            })
        });
    }

    group.finish();
}

fn bench_gain_ramp(c: &mut Criterion) {
    let mut group = c.benchmark_group("gain_ramp");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                let start_gain = 0.5;
                let end_gain = 1.0;
                let step = (end_gain - start_gain) / size as f64;
                let mut gain = start_gain;

                for sample in output.iter_mut() {
                    *sample = black_box(*sample) * gain;
                    gain += step;
                }
                black_box(output)
            })
        });
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_biquad_lowpass,
    bench_biquad_peaking,
    bench_biquad_cascade,
    bench_compressor,
    bench_limiter,
    bench_stereo_panner,
    bench_stereo_width,
    bench_gain_ramp,
);

criterion_main!(benches);
