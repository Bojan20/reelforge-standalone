//! SIMD dispatch benchmarks

use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId, Throughput};
use rf_dsp::simd::{apply_gain, mix_add, apply_stereo_gain, simd_level};

fn bench_apply_gain(c: &mut Criterion) {
    let mut group = c.benchmark_group("apply_gain");

    for size in [256, 512, 1024, 2048, 4096] {
        let mut buffer: Vec<f64> = (0..size).map(|i| (i as f64 * 0.001).sin()).collect();

        group.throughput(Throughput::Elements(size as u64));
        group.bench_with_input(
            BenchmarkId::from_parameter(size),
            &size,
            |b, _| {
                b.iter(|| {
                    apply_gain(black_box(&mut buffer), black_box(0.5));
                })
            },
        );
    }

    group.finish();
}

fn bench_mix_add(c: &mut Criterion) {
    let mut group = c.benchmark_group("mix_add");

    for size in [256, 512, 1024, 2048] {
        let source: Vec<f64> = (0..size).map(|i| (i as f64 * 0.001).sin()).collect();
        let mut dest: Vec<f64> = (0..size).map(|i| (i as f64 * 0.002).cos()).collect();

        group.throughput(Throughput::Elements(size as u64));
        group.bench_with_input(
            BenchmarkId::from_parameter(size),
            &size,
            |b, _| {
                b.iter(|| {
                    mix_add(black_box(&mut dest), black_box(&source), black_box(0.5));
                })
            },
        );
    }

    group.finish();
}

fn bench_stereo_gain(c: &mut Criterion) {
    let mut group = c.benchmark_group("stereo_gain");

    for size in [256, 512, 1024, 2048] {
        let mut left: Vec<f64> = (0..size).map(|i| (i as f64 * 0.001).sin()).collect();
        let mut right: Vec<f64> = (0..size).map(|i| (i as f64 * 0.001).cos()).collect();

        group.throughput(Throughput::Elements((size * 2) as u64));
        group.bench_with_input(
            BenchmarkId::from_parameter(size),
            &size,
            |b, _| {
                b.iter(|| {
                    apply_stereo_gain(
                        black_box(&mut left),
                        black_box(&mut right),
                        black_box(0.8),
                        black_box(0.6),
                    );
                })
            },
        );
    }

    group.finish();
}

fn bench_simd_report(c: &mut Criterion) {
    // Just report the detected SIMD level
    let level = simd_level();
    println!("\n=== SIMD Level: {} (width: {}) ===\n", level.name(), level.width());

    c.bench_function("simd_level_check", |b| {
        b.iter(|| {
            black_box(simd_level())
        })
    });
}

criterion_group!(
    benches,
    bench_simd_report,
    bench_apply_gain,
    bench_mix_add,
    bench_stereo_gain
);
criterion_main!(benches);
