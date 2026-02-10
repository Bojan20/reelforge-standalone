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
    (0..size * 2)
        .map(|_| rng.random::<f64>() * 2.0 - 1.0)
        .collect()
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

    #[test]
    fn test_audio_buffer_range() {
        let buf = generate_audio_buffer(1000, 99);
        for &sample in &buf {
            assert!(sample >= -1.0 && sample <= 1.0, "Sample {} out of range", sample);
        }
    }

    #[test]
    fn test_audio_buffer_different_seeds() {
        let buf1 = generate_audio_buffer(100, 1);
        let buf2 = generate_audio_buffer(100, 2);
        assert_ne!(buf1, buf2, "Different seeds should produce different buffers");
    }

    #[test]
    fn test_audio_buffer_empty() {
        let buf = generate_audio_buffer(0, 42);
        assert!(buf.is_empty());
    }

    #[test]
    fn test_sine_buffer_zero_crossing() {
        let buf = generate_sine_buffer(44100, 1.0, 44100.0);
        assert!(buf[0].abs() < 0.001, "Sine should start near 0");
    }

    #[test]
    fn test_sine_buffer_frequency() {
        let buf = generate_sine_buffer(44100, 440.0, 44100.0);
        let mut crossings = 0;
        for i in 1..buf.len() {
            if (buf[i - 1] >= 0.0 && buf[i] < 0.0) || (buf[i - 1] < 0.0 && buf[i] >= 0.0) {
                crossings += 1;
            }
        }
        assert!((crossings as i32 - 880).abs() < 5, "Expected ~880 crossings, got {}", crossings);
    }

    #[test]
    fn test_stereo_buffer_size() {
        let buf = generate_stereo_buffer(100, 42);
        assert_eq!(buf.len(), 200, "Stereo buffer should be 2x mono size");
    }

    #[test]
    fn test_stereo_buffer_range() {
        let buf = generate_stereo_buffer(500, 77);
        for &sample in &buf {
            assert!(sample >= -1.0 && sample <= 1.0);
        }
    }

    #[test]
    fn test_impulse_buffer_structure() {
        let buf = generate_impulse_buffer(100);
        assert_eq!(buf[0], 1.0);
        for &sample in &buf[1..] {
            assert_eq!(sample, 0.0);
        }
    }

    #[test]
    fn test_impulse_buffer_empty() {
        let buf = generate_impulse_buffer(0);
        assert!(buf.is_empty());
    }

    #[test]
    fn test_dc_buffer_value() {
        let buf = generate_dc_buffer(100, 0.5);
        for &sample in &buf {
            assert_eq!(sample, 0.5);
        }
    }

    #[test]
    fn test_dc_buffer_negative() {
        let buf = generate_dc_buffer(50, -0.75);
        for &sample in &buf {
            assert_eq!(sample, -0.75);
        }
    }

    #[test]
    fn test_buffer_sizes_sorted() {
        assert!(!BUFFER_SIZES.is_empty());
        for i in 1..BUFFER_SIZES.len() {
            assert!(BUFFER_SIZES[i] > BUFFER_SIZES[i - 1]);
        }
    }

    #[test]
    fn test_sample_rates_positive() {
        assert!(!SAMPLE_RATES.is_empty());
        for &rate in SAMPLE_RATES {
            assert!(rate > 0.0);
        }
    }

}
