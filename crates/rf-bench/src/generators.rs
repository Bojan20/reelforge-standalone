//! Test data generators for benchmarks

use rand::prelude::*;
use rand_chacha::ChaCha8Rng;

/// Generate reproducible audio buffer
pub fn generate_audio_buffer(size: usize, seed: u64) -> Vec<f64> {
    let mut rng = ChaCha8Rng::seed_from_u64(seed);
    (0..size).map(|_| rng.random::<f64>() * 2.0 - 1.0).collect()
}

/// Generate sine wave buffer
pub fn generate_sine_buffer(size: usize, freq: f64, sample_rate: f64) -> Vec<f64> {
    (0..size)
        .map(|i| (2.0 * std::f64::consts::PI * freq * i as f64 / sample_rate).sin())
        .collect()
}

/// Generate stereo buffer (interleaved)
pub fn generate_stereo_buffer(size: usize, seed: u64) -> Vec<f64> {
    let mut rng = ChaCha8Rng::seed_from_u64(seed);
    (0..size * 2).map(|_| rng.random::<f64>() * 2.0 - 1.0).collect()
}

/// Generate impulse buffer
pub fn generate_impulse_buffer(size: usize) -> Vec<f64> {
    let mut buf = vec![0.0; size];
    if !buf.is_empty() {
        buf[0] = 1.0;
    }
    buf
}

/// Generate DC offset buffer
pub fn generate_dc_buffer(size: usize, offset: f64) -> Vec<f64> {
    vec![offset; size]
}

/// Common buffer sizes for benchmarks
pub const BUFFER_SIZES: &[usize] = &[64, 128, 256, 512, 1024, 2048, 4096];

/// Common sample rates
pub const SAMPLE_RATES: &[f64] = &[44100.0, 48000.0, 96000.0];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reproducibility() {
        let buf1 = generate_audio_buffer(100, 42);
        let buf2 = generate_audio_buffer(100, 42);
        assert_eq!(buf1, buf2);
    }

    #[test]
    fn test_sine_amplitude() {
        let buf = generate_sine_buffer(44100, 440.0, 44100.0);
        let max = buf.iter().fold(0.0_f64, |a, &b| a.max(b.abs()));
        assert!((max - 1.0).abs() < 0.01);
    }
}
