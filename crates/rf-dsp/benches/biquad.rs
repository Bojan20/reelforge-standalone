//! Biquad filter benchmarks

use criterion::{Criterion, black_box, criterion_group, criterion_main};
use rf_dsp::biquad::{BiquadCoeffs, BiquadSimd4, BiquadTDF2};

fn bench_biquad_scalar(c: &mut Criterion) {
    let mut filter = BiquadTDF2::new(48000.0);
    filter.set_lowpass(1000.0, 0.707);

    let mut buffer: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).sin()).collect();

    c.bench_function("biquad_scalar_1024", |b| {
        b.iter(|| {
            filter.process_block(black_box(&mut buffer));
        })
    });
}

fn bench_biquad_simd4(c: &mut Criterion) {
    let mut filter = BiquadSimd4::new(48000.0);
    filter.set_coeffs(BiquadCoeffs::lowpass(1000.0, 0.707, 48000.0));

    let mut buffer: Vec<f64> = (0..1024).map(|i| (i as f64 * 0.01).sin()).collect();

    c.bench_function("biquad_simd4_1024", |b| {
        b.iter(|| {
            filter.process_block(black_box(&mut buffer));
        })
    });
}

criterion_group!(benches, bench_biquad_scalar, bench_biquad_simd4);
criterion_main!(benches);
