//! Input generators for fuzzing

use rand::prelude::*;
use rand_chacha::ChaCha8Rng;

/// Input generator for fuzzing
pub struct InputGenerator {
    rng: ChaCha8Rng,
    include_edge_cases: bool,
    include_boundaries: bool,
    max_size: usize,
}

impl InputGenerator {
    /// Create a new generator with optional seed
    pub fn new(seed: Option<u64>, max_size: usize) -> Self {
        let rng = match seed {
            Some(s) => ChaCha8Rng::seed_from_u64(s),
            None => ChaCha8Rng::from_os_rng(),
        };

        Self {
            rng,
            include_edge_cases: true,
            include_boundaries: true,
            max_size,
        }
    }

    /// Set whether to include edge cases
    pub fn with_edge_cases(mut self, include: bool) -> Self {
        self.include_edge_cases = include;
        self
    }

    /// Set whether to include boundary values
    pub fn with_boundaries(mut self, include: bool) -> Self {
        self.include_boundaries = include;
        self
    }

    /// Generate random bytes
    pub fn bytes(&mut self, max_len: usize) -> Vec<u8> {
        let len = self.rng.random_range(0..=max_len.min(self.max_size));
        let mut buf = vec![0u8; len];
        self.rng.fill_bytes(&mut buf);
        buf
    }

    /// Generate f64 value with edge cases
    pub fn f64(&mut self) -> f64 {
        // 20% chance of edge case if enabled
        if self.include_edge_cases && self.rng.random_bool(0.2) {
            return self.f64_edge_case();
        }

        // 10% chance of boundary value if enabled
        if self.include_boundaries && self.rng.random_bool(0.1) {
            return self.f64_boundary();
        }

        // Normal random value
        self.rng.random::<f64>() * 2.0 - 1.0 // -1.0 to 1.0
    }

    /// Generate f64 in specific range
    pub fn f64_range(&mut self, min: f64, max: f64) -> f64 {
        if self.include_edge_cases && self.rng.random_bool(0.1) {
            return self.f64_edge_case();
        }

        min + self.rng.random::<f64>() * (max - min)
    }

    /// Generate f64 edge case
    fn f64_edge_case(&mut self) -> f64 {
        const EDGE_CASES: [f64; 10] = [
            0.0,
            -0.0,
            f64::NAN,
            f64::INFINITY,
            f64::NEG_INFINITY,
            f64::MIN,
            f64::MAX,
            f64::MIN_POSITIVE,
            f64::EPSILON,
            -f64::EPSILON,
        ];
        EDGE_CASES[self.rng.random_range(0..EDGE_CASES.len())]
    }

    /// Generate f64 boundary value
    fn f64_boundary(&mut self) -> f64 {
        const BOUNDARIES: [f64; 14] = [
            -1.0,
            1.0,
            0.5,
            -0.5,
            0.0,
            0.999999,
            -0.999999,
            1e-10,
            -1e-10,
            1e10,
            -1e10,
            std::f64::consts::PI,
            std::f64::consts::E,
            std::f64::consts::SQRT_2,
        ];
        BOUNDARIES[self.rng.random_range(0..BOUNDARIES.len())]
    }

    /// Generate i32 value with edge cases
    pub fn i32(&mut self) -> i32 {
        if self.include_edge_cases && self.rng.random_bool(0.2) {
            return self.i32_edge_case();
        }

        self.rng.random::<i32>()
    }

    /// Generate i32 in specific range
    pub fn i32_range(&mut self, min: i32, max: i32) -> i32 {
        if self.include_edge_cases && self.rng.random_bool(0.1) {
            let edge = self.i32_edge_case();
            if edge >= min && edge <= max {
                return edge;
            }
        }

        self.rng.random_range(min..=max)
    }

    /// Generate i32 edge case
    fn i32_edge_case(&mut self) -> i32 {
        const EDGE_CASES: [i32; 10] = [
            0,
            1,
            -1,
            i32::MIN,
            i32::MAX,
            i32::MIN + 1,
            i32::MAX - 1,
            127,
            -128,
            256,
        ];
        EDGE_CASES[self.rng.random_range(0..EDGE_CASES.len())]
    }

    /// Generate u32 value
    pub fn u32(&mut self) -> u32 {
        if self.include_edge_cases && self.rng.random_bool(0.2) {
            return self.u32_edge_case();
        }

        self.rng.random::<u32>()
    }

    /// Generate u32 edge case
    fn u32_edge_case(&mut self) -> u32 {
        const EDGE_CASES: [u32; 8] = [0, 1, u32::MAX, u32::MAX - 1, u32::MAX / 2, 255, 256, 65535];
        EDGE_CASES[self.rng.random_range(0..EDGE_CASES.len())]
    }

    /// Generate usize value
    pub fn usize(&mut self, max: usize) -> usize {
        if self.include_edge_cases && self.rng.random_bool(0.2) {
            let edge = self.usize_edge_case();
            if edge <= max {
                return edge;
            }
        }

        self.rng.random_range(0..=max)
    }

    /// Generate usize edge case
    fn usize_edge_case(&mut self) -> usize {
        const EDGE_CASES: [usize; 8] = [0, 1, 2, 255, 256, 1023, 1024, 4096];
        EDGE_CASES[self.rng.random_range(0..EDGE_CASES.len())]
    }

    /// Generate bool
    pub fn bool(&mut self) -> bool {
        self.rng.random::<bool>()
    }

    /// Generate audio samples (f64 array)
    pub fn audio_samples(&mut self, len: usize) -> Vec<f64> {
        (0..len).map(|_| self.f64()).collect()
    }

    /// Generate normalized audio samples (-1.0 to 1.0)
    pub fn normalized_audio(&mut self, len: usize) -> Vec<f64> {
        (0..len)
            .map(|_| self.rng.random::<f64>() * 2.0 - 1.0)
            .collect()
    }

    /// Generate frequency value (Hz)
    pub fn frequency(&mut self) -> f64 {
        if self.include_edge_cases && self.rng.random_bool(0.1) {
            const EDGE_FREQS: [f64; 8] = [0.0, 1.0, 20.0, 440.0, 1000.0, 20000.0, 22050.0, 44100.0];
            return EDGE_FREQS[self.rng.random_range(0..EDGE_FREQS.len())];
        }

        // Log-distributed frequency from 1 Hz to 22050 Hz
        let log_min = 0.0_f64; // log(1)
        let log_max = (22050.0_f64).ln();
        let log_freq = log_min + self.rng.random::<f64>() * (log_max - log_min);
        log_freq.exp()
    }

    /// Generate gain value (dB)
    pub fn gain_db(&mut self) -> f64 {
        if self.include_edge_cases && self.rng.random_bool(0.1) {
            const EDGE_GAINS: [f64; 8] =
                [f64::NEG_INFINITY, -96.0, -60.0, -12.0, 0.0, 6.0, 12.0, 24.0];
            return EDGE_GAINS[self.rng.random_range(0..EDGE_GAINS.len())];
        }

        self.rng.random::<f64>() * 96.0 - 72.0 // -72 dB to +24 dB
    }

    /// Generate pan value (-1.0 to 1.0)
    pub fn pan(&mut self) -> f64 {
        if self.include_boundaries && self.rng.random_bool(0.2) {
            const BOUNDARIES: [f64; 5] = [-1.0, -0.5, 0.0, 0.5, 1.0];
            return BOUNDARIES[self.rng.random_range(0..BOUNDARIES.len())];
        }

        self.rng.random::<f64>() * 2.0 - 1.0
    }

    /// Generate sample rate
    pub fn sample_rate(&mut self) -> u32 {
        const RATES: [u32; 8] = [8000, 11025, 22050, 44100, 48000, 88200, 96000, 192000];
        RATES[self.rng.random_range(0..RATES.len())]
    }

    /// Generate buffer size (power of 2)
    pub fn buffer_size(&mut self) -> usize {
        const SIZES: [usize; 8] = [32, 64, 128, 256, 512, 1024, 2048, 4096];
        SIZES[self.rng.random_range(0..SIZES.len())]
    }

    /// Generate channel count
    pub fn channels(&mut self) -> usize {
        if self.include_edge_cases && self.rng.random_bool(0.1) {
            const EDGE: [usize; 4] = [0, 1, 2, 128];
            return EDGE[self.rng.random_range(0..EDGE.len())];
        }

        self.rng.random_range(1..=8)
    }
}

/// Audio-specific input generators
pub struct AudioInputs;

impl AudioInputs {
    /// Generate a test buffer with various patterns
    pub fn pattern_buffer(gen: &mut InputGenerator, len: usize, pattern: AudioPattern) -> Vec<f64> {
        match pattern {
            AudioPattern::Silence => vec![0.0; len],
            AudioPattern::DcOffset => {
                let offset = gen.f64_range(-1.0, 1.0);
                vec![offset; len]
            }
            AudioPattern::Impulse => {
                let mut buf = vec![0.0; len];
                if !buf.is_empty() {
                    buf[0] = 1.0;
                }
                buf
            }
            AudioPattern::Sine => {
                let freq = gen.frequency();
                let sr = 44100.0;
                (0..len)
                    .map(|i| (2.0 * std::f64::consts::PI * freq * i as f64 / sr).sin())
                    .collect()
            }
            AudioPattern::Noise => gen.normalized_audio(len),
            AudioPattern::Square => {
                let freq = gen.frequency();
                let sr = 44100.0;
                (0..len)
                    .map(|i| {
                        let phase = (freq * i as f64 / sr).fract();
                        if phase < 0.5 {
                            1.0
                        } else {
                            -1.0
                        }
                    })
                    .collect()
            }
            AudioPattern::EdgeCases => {
                let mut buf = Vec::with_capacity(len);
                for _ in 0..len {
                    buf.push(gen.f64());
                }
                buf
            }
            AudioPattern::Random => gen.audio_samples(len),
        }
    }
}

/// Audio test patterns
#[derive(Debug, Clone, Copy)]
pub enum AudioPattern {
    /// All zeros
    Silence,
    /// Constant DC offset
    DcOffset,
    /// Single impulse at start
    Impulse,
    /// Sine wave
    Sine,
    /// White noise
    Noise,
    /// Square wave
    Square,
    /// Mix of edge case values
    EdgeCases,
    /// Random samples including edge cases
    Random,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generator_reproducibility() {
        let mut gen1 = InputGenerator::new(Some(42), 1024);
        let mut gen2 = InputGenerator::new(Some(42), 1024);

        for _ in 0..100 {
            let v1 = gen1.f64();
            let v2 = gen2.f64();
            // Handle NaN comparison (NaN != NaN but should match for reproducibility)
            if v1.is_nan() {
                assert!(v2.is_nan(), "Expected NaN, got {}", v2);
            } else {
                assert_eq!(v1, v2);
            }
            assert_eq!(gen1.i32(), gen2.i32());
        }
    }

    #[test]
    fn test_f64_range() {
        let mut gen = InputGenerator::new(Some(123), 1024).with_edge_cases(false);

        for _ in 0..1000 {
            let val = gen.f64_range(0.0, 1.0);
            assert!(val >= 0.0 && val <= 1.0, "Value {} out of range", val);
        }
    }

    #[test]
    fn test_audio_patterns() {
        let mut gen = InputGenerator::new(Some(456), 1024);

        let silence = AudioInputs::pattern_buffer(&mut gen, 100, AudioPattern::Silence);
        assert!(silence.iter().all(|&s| s == 0.0));

        let impulse = AudioInputs::pattern_buffer(&mut gen, 100, AudioPattern::Impulse);
        assert_eq!(impulse[0], 1.0);
        assert!(impulse[1..].iter().all(|&s| s == 0.0));
    }
}
