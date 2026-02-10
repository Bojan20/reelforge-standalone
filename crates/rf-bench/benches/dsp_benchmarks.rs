//! DSP Processor Benchmarks
//!
//! Benchmarks for core DSP processors: filters, dynamics, spatial, gain.

use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use rf_bench::{generate_audio_buffer, generate_sine_buffer, BUFFER_SIZES};
use rf_dsp::biquad::BiquadTDF2;
use rf_dsp::dynamics::{Compressor, Limiter};
use rf_dsp::spatial::{StereoPanner, StereoWidth};
use rf_dsp::{MonoProcessor, Processor, StereoProcessor};

const SAMPLE_RATE: f64 = 48000.0;

fn bench_biquad_lowpass(c: &mut Criterion) {
    let mut group = c.benchmark_group("biquad_lowpass");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_sine_buffer(size, 1000.0, SAMPLE_RATE);
        let mut filter = BiquadTDF2::new(SAMPLE_RATE);
        filter.set_lowpass(1000.0, 0.707);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                filter.process_block(&mut output);
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
        let mut filter = BiquadTDF2::new(SAMPLE_RATE);
        filter.set_peaking(1000.0, 2.0, 6.0);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                filter.process_block(&mut output);
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

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut output = input.clone();
                for filter in filters.iter_mut() {
                    filter.process_block(&mut output);
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
        let mut comp = Compressor::new(SAMPLE_RATE);
        comp.set_threshold(-20.0);
        comp.set_ratio(4.0);
        comp.set_times(10.0, 100.0);
        comp.set_knee(6.0);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut buffer = input.clone();
                comp.process_block(&mut buffer);
                comp.reset();
                black_box(buffer)
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
        let mut limiter = Limiter::new(SAMPLE_RATE);
        limiter.set_threshold(-1.0);
        limiter.set_release(50.0);

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut buffer = input.clone();
                limiter.process_block(&mut buffer);
                limiter.reset();
                black_box(buffer)
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
        let mut panner = StereoPanner::new();
        panner.set_pan(0.3); // Pan slightly right

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut left = input.clone();
                let mut right = input.clone();
                panner.process_block(&mut left, &mut right);
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
        let mut width = StereoWidth::new();
        width.set_width(1.5); // Wider stereo

        group.bench_with_input(BenchmarkId::from_parameter(size), &size, |b, _| {
            b.iter(|| {
                let mut l = left.clone();
                let mut r = right.clone();
                width.process_block(&mut l, &mut r);
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
