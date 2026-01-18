//! Dynamics processor benchmarks

use criterion::{BenchmarkId, Criterion, black_box, criterion_group, criterion_main};
use rf_dsp::dynamics::{Compressor, CompressorType, StereoCompressor};
use rf_dsp::{MonoProcessor, StereoProcessor};

fn bench_compressor_mono(c: &mut Criterion) {
    let mut group = c.benchmark_group("compressor_mono");

    for comp_type in [
        CompressorType::Vca,
        CompressorType::Opto,
        CompressorType::Fet,
    ] {
        let mut comp = Compressor::new(48000.0);
        comp.set_type(comp_type);
        comp.set_threshold(-18.0);
        comp.set_ratio(4.0);
        comp.set_attack(10.0);
        comp.set_release(100.0);

        let mut buffer: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).sin() * 0.5).collect();

        group.bench_with_input(
            BenchmarkId::from_parameter(format!("{:?}", comp_type)),
            &comp_type,
            |b, _| {
                b.iter(|| {
                    comp.process_block(black_box(&mut buffer));
                })
            },
        );
    }

    group.finish();
}

fn bench_compressor_stereo(c: &mut Criterion) {
    let mut comp = StereoCompressor::new(48000.0);
    comp.set_both(|c| {
        c.set_threshold(-18.0);
        c.set_ratio(4.0);
        c.set_attack(10.0);
        c.set_release(100.0);
    });

    let mut left: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).sin() * 0.5).collect();
    let mut right: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).cos() * 0.5).collect();

    c.bench_function("compressor_stereo_1024", |b| {
        b.iter(|| {
            comp.process_block(black_box(&mut left), black_box(&mut right));
        })
    });
}

fn bench_compressor_lookahead(c: &mut Criterion) {
    let mut comp = Compressor::new(48000.0);
    comp.set_threshold(-18.0);
    comp.set_ratio(4.0);
    comp.set_attack(0.0); // Instant attack for lookahead test
    comp.set_release(100.0);

    let mut buffer: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).sin() * 0.5).collect();

    c.bench_function("compressor_lookahead_1024", |b| {
        b.iter(|| {
            comp.process_block(black_box(&mut buffer));
        })
    });
}

criterion_group!(
    benches,
    bench_compressor_mono,
    bench_compressor_stereo,
    bench_compressor_lookahead
);
criterion_main!(benches);
