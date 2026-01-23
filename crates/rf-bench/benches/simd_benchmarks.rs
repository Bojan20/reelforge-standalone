//! SIMD vs Scalar Benchmarks
//!
//! Compares vectorized vs scalar implementations to measure SIMD speedup.

use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use rf_bench::{generate_audio_buffer, BUFFER_SIZES};

#[cfg(target_arch = "x86_64")]
use std::arch::x86_64::*;

const SAMPLE_RATE: f64 = 48000.0;

/// Scalar gain application
fn apply_gain_scalar(buffer: &mut [f64], gain: f64) {
    for sample in buffer.iter_mut() {
        *sample *= gain;
    }
}

/// SIMD gain application (AVX2 - 4 doubles at a time)
#[cfg(target_arch = "x86_64")]
fn apply_gain_simd_avx2(buffer: &mut [f64], gain: f64) {
    if !is_x86_feature_detected!("avx2") {
        apply_gain_scalar(buffer, gain);
        return;
    }

    unsafe {
        let gain_vec = _mm256_set1_pd(gain);
        let chunks = buffer.len() / 4;

        for i in 0..chunks {
            let ptr = buffer.as_mut_ptr().add(i * 4);
            let samples = _mm256_loadu_pd(ptr);
            let result = _mm256_mul_pd(samples, gain_vec);
            _mm256_storeu_pd(ptr, result);
        }

        // Handle remainder
        for i in (chunks * 4)..buffer.len() {
            buffer[i] *= gain;
        }
    }
}

/// Scalar stereo interleave
fn interleave_scalar(left: &[f64], right: &[f64], output: &mut [f64]) {
    for i in 0..left.len() {
        output[i * 2] = left[i];
        output[i * 2 + 1] = right[i];
    }
}

/// Scalar stereo deinterleave
fn deinterleave_scalar(input: &[f64], left: &mut [f64], right: &mut [f64]) {
    for i in 0..left.len() {
        left[i] = input[i * 2];
        right[i] = input[i * 2 + 1];
    }
}

/// Scalar sum
fn sum_scalar(buffer: &[f64]) -> f64 {
    buffer.iter().sum()
}

/// SIMD sum (AVX2)
#[cfg(target_arch = "x86_64")]
fn sum_simd_avx2(buffer: &[f64]) -> f64 {
    if !is_x86_feature_detected!("avx2") {
        return sum_scalar(buffer);
    }

    unsafe {
        let mut acc = _mm256_setzero_pd();
        let chunks = buffer.len() / 4;

        for i in 0..chunks {
            let ptr = buffer.as_ptr().add(i * 4);
            let samples = _mm256_loadu_pd(ptr);
            acc = _mm256_add_pd(acc, samples);
        }

        // Horizontal sum
        let mut result = [0.0f64; 4];
        _mm256_storeu_pd(result.as_mut_ptr(), acc);
        let mut sum = result[0] + result[1] + result[2] + result[3];

        // Handle remainder
        for i in (chunks * 4)..buffer.len() {
            sum += buffer[i];
        }

        sum
    }
}

/// Scalar peak detection
fn peak_scalar(buffer: &[f64]) -> f64 {
    buffer.iter().fold(0.0_f64, |acc, &x| acc.max(x.abs()))
}

/// SIMD peak detection (AVX2)
#[cfg(target_arch = "x86_64")]
fn peak_simd_avx2(buffer: &[f64]) -> f64 {
    if !is_x86_feature_detected!("avx2") {
        return peak_scalar(buffer);
    }

    unsafe {
        let sign_mask = _mm256_set1_pd(-0.0);
        let mut max_vec = _mm256_setzero_pd();
        let chunks = buffer.len() / 4;

        for i in 0..chunks {
            let ptr = buffer.as_ptr().add(i * 4);
            let samples = _mm256_loadu_pd(ptr);
            let abs_samples = _mm256_andnot_pd(sign_mask, samples);
            max_vec = _mm256_max_pd(max_vec, abs_samples);
        }

        // Horizontal max
        let mut result = [0.0f64; 4];
        _mm256_storeu_pd(result.as_mut_ptr(), max_vec);
        let mut peak = result[0].max(result[1]).max(result[2]).max(result[3]);

        // Handle remainder
        for i in (chunks * 4)..buffer.len() {
            peak = peak.max(buffer[i].abs());
        }

        peak
    }
}

/// Scalar mix (a * x + b * y)
fn mix_scalar(a: &[f64], b: &[f64], mix: f64, output: &mut [f64]) {
    let inv_mix = 1.0 - mix;
    for i in 0..a.len() {
        output[i] = a[i] * inv_mix + b[i] * mix;
    }
}

/// SIMD mix (AVX2)
#[cfg(target_arch = "x86_64")]
fn mix_simd_avx2(a: &[f64], b: &[f64], mix: f64, output: &mut [f64]) {
    if !is_x86_feature_detected!("avx2") {
        mix_scalar(a, b, mix, output);
        return;
    }

    unsafe {
        let mix_vec = _mm256_set1_pd(mix);
        let inv_mix_vec = _mm256_set1_pd(1.0 - mix);
        let chunks = a.len() / 4;

        for i in 0..chunks {
            let ptr_a = a.as_ptr().add(i * 4);
            let ptr_b = b.as_ptr().add(i * 4);
            let ptr_out = output.as_mut_ptr().add(i * 4);

            let samples_a = _mm256_loadu_pd(ptr_a);
            let samples_b = _mm256_loadu_pd(ptr_b);

            let scaled_a = _mm256_mul_pd(samples_a, inv_mix_vec);
            let scaled_b = _mm256_mul_pd(samples_b, mix_vec);
            let result = _mm256_add_pd(scaled_a, scaled_b);

            _mm256_storeu_pd(ptr_out, result);
        }

        // Handle remainder
        let inv_mix = 1.0 - mix;
        for i in (chunks * 4)..a.len() {
            output[i] = a[i] * inv_mix + b[i] * mix;
        }
    }
}

fn bench_gain_scalar_vs_simd(c: &mut Criterion) {
    let mut group = c.benchmark_group("gain_scalar_vs_simd");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);

        group.bench_with_input(BenchmarkId::new("scalar", size), &size, |b, _| {
            b.iter(|| {
                let mut buffer = input.clone();
                apply_gain_scalar(&mut buffer, black_box(0.8));
                black_box(buffer)
            })
        });

        #[cfg(target_arch = "x86_64")]
        group.bench_with_input(BenchmarkId::new("avx2", size), &size, |b, _| {
            b.iter(|| {
                let mut buffer = input.clone();
                apply_gain_simd_avx2(&mut buffer, black_box(0.8));
                black_box(buffer)
            })
        });
    }

    group.finish();
}

fn bench_sum_scalar_vs_simd(c: &mut Criterion) {
    let mut group = c.benchmark_group("sum_scalar_vs_simd");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);

        group.bench_with_input(BenchmarkId::new("scalar", size), &size, |b, _| {
            b.iter(|| black_box(sum_scalar(black_box(&input))))
        });

        #[cfg(target_arch = "x86_64")]
        group.bench_with_input(BenchmarkId::new("avx2", size), &size, |b, _| {
            b.iter(|| black_box(sum_simd_avx2(black_box(&input))))
        });
    }

    group.finish();
}

fn bench_peak_scalar_vs_simd(c: &mut Criterion) {
    let mut group = c.benchmark_group("peak_scalar_vs_simd");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let input = generate_audio_buffer(size, 42);

        group.bench_with_input(BenchmarkId::new("scalar", size), &size, |b, _| {
            b.iter(|| black_box(peak_scalar(black_box(&input))))
        });

        #[cfg(target_arch = "x86_64")]
        group.bench_with_input(BenchmarkId::new("avx2", size), &size, |b, _| {
            b.iter(|| black_box(peak_simd_avx2(black_box(&input))))
        });
    }

    group.finish();
}

fn bench_mix_scalar_vs_simd(c: &mut Criterion) {
    let mut group = c.benchmark_group("mix_scalar_vs_simd");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64));

        let a = generate_audio_buffer(size, 42);
        let b = generate_audio_buffer(size, 43);
        let mut output = vec![0.0; size];

        group.bench_with_input(BenchmarkId::new("scalar", size), &size, |b_iter, _| {
            b_iter.iter(|| {
                mix_scalar(&a, &b, black_box(0.5), &mut output);
                black_box(&output)
            })
        });

        #[cfg(target_arch = "x86_64")]
        group.bench_with_input(BenchmarkId::new("avx2", size), &size, |b_iter, _| {
            b_iter.iter(|| {
                mix_simd_avx2(&a, &b, black_box(0.5), &mut output);
                black_box(&output)
            })
        });
    }

    group.finish();
}

fn bench_interleave(c: &mut Criterion) {
    let mut group = c.benchmark_group("interleave_deinterleave");

    for &size in BUFFER_SIZES {
        group.throughput(Throughput::Elements(size as u64 * 2));

        let left = generate_audio_buffer(size, 42);
        let right = generate_audio_buffer(size, 43);
        let mut interleaved = vec![0.0; size * 2];
        let mut out_left = vec![0.0; size];
        let mut out_right = vec![0.0; size];

        group.bench_with_input(BenchmarkId::new("interleave", size), &size, |b, _| {
            b.iter(|| {
                interleave_scalar(&left, &right, &mut interleaved);
                black_box(&interleaved)
            })
        });

        interleave_scalar(&left, &right, &mut interleaved);

        group.bench_with_input(BenchmarkId::new("deinterleave", size), &size, |b, _| {
            b.iter(|| {
                deinterleave_scalar(&interleaved, &mut out_left, &mut out_right);
                black_box((&out_left, &out_right))
            })
        });
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_gain_scalar_vs_simd,
    bench_sum_scalar_vs_simd,
    bench_peak_scalar_vs_simd,
    bench_mix_scalar_vs_simd,
    bench_interleave,
);

criterion_main!(benches);
