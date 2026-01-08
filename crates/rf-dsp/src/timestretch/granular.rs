//! # Granular Synthesis for Time Stretching
//!
//! Granular synthesis for extreme time stretch ratios and creative effects.
//!
//! ## Parameters
//!
//! - **Grain size**: Duration of each grain (typically 10-100ms)
//! - **Grain density**: Grains per second
//! - **Overlap**: How much grains overlap
//! - **Jitter**: Random variation in grain timing

use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// GRAIN
// ═══════════════════════════════════════════════════════════════════════════════

/// A single audio grain
#[derive(Debug, Clone)]
struct Grain {
    /// Source position (samples)
    source_pos: f64,
    /// Current playback position within grain
    playback_pos: f64,
    /// Grain length (samples)
    length: usize,
    /// Playback rate (for pitch shift)
    rate: f64,
    /// Amplitude envelope position
    envelope_pos: f64,
    /// Is grain active
    active: bool,
}

impl Grain {
    fn new(source_pos: f64, length: usize, rate: f64) -> Self {
        Self {
            source_pos,
            playback_pos: 0.0,
            length,
            rate,
            envelope_pos: 0.0,
            active: true,
        }
    }

    /// Get envelope value at current position (Hann window)
    fn envelope(&self) -> f64 {
        let phase = self.envelope_pos / self.length as f64;
        0.5 * (1.0 - (2.0 * PI * phase).cos())
    }

    /// Advance grain position
    fn advance(&mut self) -> bool {
        self.playback_pos += self.rate;
        self.envelope_pos += 1.0;

        if self.envelope_pos >= self.length as f64 {
            self.active = false;
        }

        self.active
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GRANULAR PROCESSOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Granular synthesis processor
pub struct GranularProcessor {
    /// Sample rate
    sample_rate: f64,
    /// Grain size (samples)
    grain_size: usize,
    /// Grain density (grains per second)
    density: f64,
    /// Random jitter amount (0.0 - 1.0)
    jitter: f64,
    /// Active grains
    grains: Vec<Grain>,
    /// Time since last grain spawn
    time_since_spawn: f64,
    /// Random seed state
    random_state: u64,
}

impl GranularProcessor {
    /// Create new granular processor
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            grain_size: (sample_rate * 0.05) as usize, // 50ms default
            density: 20.0, // 20 grains per second
            jitter: 0.1,
            grains: Vec::new(),
            time_since_spawn: 0.0,
            random_state: 12345,
        }
    }

    /// Create with custom parameters
    pub fn with_params(
        sample_rate: f64,
        grain_size_ms: f64,
        density: f64,
        jitter: f64,
    ) -> Self {
        Self {
            sample_rate,
            grain_size: (sample_rate * grain_size_ms / 1000.0) as usize,
            density,
            jitter: jitter.clamp(0.0, 1.0),
            grains: Vec::new(),
            time_since_spawn: 0.0,
            random_state: 12345,
        }
    }

    /// Process audio with time stretch and pitch shift
    pub fn process(
        &mut self,
        input: &[f64],
        time_ratio: f64,
        pitch_ratio: f64,
    ) -> Vec<f64> {
        if input.is_empty() || time_ratio <= 0.0 {
            return vec![];
        }

        let output_len = (input.len() as f64 * time_ratio) as usize;
        let mut output = vec![0.0; output_len];

        // Reset state
        self.grains.clear();
        self.time_since_spawn = 0.0;

        // Spawn interval (samples)
        let spawn_interval = self.sample_rate / self.density;

        // Read position increment per output sample
        let read_increment = 1.0 / time_ratio;
        let mut read_pos = 0.0;

        for (out_idx, out_sample) in output.iter_mut().enumerate() {
            // Check if we should spawn a new grain
            self.time_since_spawn += 1.0;

            let jittered_interval = spawn_interval * (1.0 + (self.random() - 0.5) * self.jitter);

            if self.time_since_spawn >= jittered_interval {
                self.time_since_spawn = 0.0;

                // Spawn grain at current read position
                let grain = Grain::new(read_pos, self.grain_size, pitch_ratio);
                self.grains.push(grain);
            }

            // Process all active grains
            let mut sample = 0.0;

            for grain in &mut self.grains {
                if !grain.active {
                    continue;
                }

                // Read from source with interpolation
                let src_pos = grain.source_pos + grain.playback_pos;
                let src_idx = src_pos.floor() as usize;
                let frac = src_pos - src_pos.floor();

                if src_idx < input.len() {
                    let s0 = input[src_idx];
                    let s1 = input.get(src_idx + 1).copied().unwrap_or(s0);

                    let interpolated = s0 * (1.0 - frac) + s1 * frac;
                    sample += interpolated * grain.envelope();
                }

                grain.advance();
            }

            *out_sample = sample;

            // Advance read position
            read_pos += read_increment;

            // Remove inactive grains periodically
            if out_idx % 1000 == 0 {
                self.grains.retain(|g| g.active);
            }
        }

        // Normalize output
        self.normalize(&mut output);

        output
    }

    /// Simple pseudo-random number generator (0.0 - 1.0)
    fn random(&mut self) -> f64 {
        // xorshift64
        self.random_state ^= self.random_state << 13;
        self.random_state ^= self.random_state >> 7;
        self.random_state ^= self.random_state << 17;

        (self.random_state as f64) / (u64::MAX as f64)
    }

    /// Normalize output to prevent clipping
    fn normalize(&self, output: &mut [f64]) {
        let max_abs = output.iter()
            .map(|&x| x.abs())
            .fold(0.0, f64::max);

        if max_abs > 1.0 {
            let scale = 0.95 / max_abs;
            for sample in output {
                *sample *= scale;
            }
        }
    }

    /// Reset processor state
    pub fn reset(&mut self) {
        self.grains.clear();
        self.time_since_spawn = 0.0;
    }

    /// Set grain size in milliseconds
    pub fn set_grain_size_ms(&mut self, ms: f64) {
        self.grain_size = (self.sample_rate * ms / 1000.0) as usize;
        self.grain_size = self.grain_size.max(64);
    }

    /// Set grain density (grains per second)
    pub fn set_density(&mut self, density: f64) {
        self.density = density.max(1.0);
    }

    /// Set jitter amount (0.0 - 1.0)
    pub fn set_jitter(&mut self, jitter: f64) {
        self.jitter = jitter.clamp(0.0, 1.0);
    }

    /// Get current number of active grains
    pub fn active_grain_count(&self) -> usize {
        self.grains.iter().filter(|g| g.active).count()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FREEZE MODE
// ═══════════════════════════════════════════════════════════════════════════════

/// Granular freeze effect (infinite stretch at a position)
pub struct GranularFreeze {
    /// Base granular processor
    processor: GranularProcessor,
    /// Freeze position (samples)
    freeze_pos: usize,
    /// Freeze window size (samples)
    window_size: usize,
    /// Is frozen
    frozen: bool,
}

impl GranularFreeze {
    /// Create new freeze effect
    pub fn new(sample_rate: f64) -> Self {
        Self {
            processor: GranularProcessor::new(sample_rate),
            freeze_pos: 0,
            window_size: (sample_rate * 0.1) as usize, // 100ms window
            frozen: false,
        }
    }

    /// Set freeze position
    pub fn set_freeze_position(&mut self, pos: usize) {
        self.freeze_pos = pos;
    }

    /// Enable/disable freeze
    pub fn set_frozen(&mut self, frozen: bool) {
        self.frozen = frozen;
        if !frozen {
            self.processor.reset();
        }
    }

    /// Process frozen output
    pub fn process(&mut self, input: &[f64], output_len: usize) -> Vec<f64> {
        if !self.frozen || input.is_empty() {
            return vec![0.0; output_len];
        }

        // Extract freeze window
        let start = self.freeze_pos.saturating_sub(self.window_size / 2);
        let end = (start + self.window_size).min(input.len());
        let window: Vec<f64> = input[start..end].to_vec();

        // Process with extreme stretch
        let stretch_ratio = output_len as f64 / window.len() as f64;
        self.processor.process(&window, stretch_ratio, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_granular_creation() {
        let processor = GranularProcessor::new(44100.0);
        assert!(processor.grain_size > 0);
        assert!(processor.density > 0.0);
    }

    #[test]
    fn test_granular_process() {
        let mut processor = GranularProcessor::new(44100.0);

        // Generate test signal
        let duration = 0.2; // 200ms
        let samples = (44100.0 * duration) as usize;
        let input: Vec<f64> = (0..samples)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        // Test stretch
        let output = processor.process(&input, 2.0, 1.0);

        // Output should be approximately 2x input length
        let ratio = output.len() as f64 / input.len() as f64;
        assert!(ratio > 1.5 && ratio < 2.5);
    }

    #[test]
    fn test_granular_extreme_stretch() {
        let mut processor = GranularProcessor::with_params(44100.0, 50.0, 30.0, 0.2);

        let duration = 0.1;
        let samples = (44100.0 * duration) as usize;
        let input: Vec<f64> = (0..samples)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        // Extreme stretch: 10x
        let output = processor.process(&input, 10.0, 1.0);

        assert!(output.len() > input.len() * 8);
    }

    #[test]
    fn test_grain_envelope() {
        let grain = Grain::new(0.0, 1000, 1.0);

        // Envelope should be 0 at start and 1 at center
        assert!(grain.envelope() < 0.01);
    }

    #[test]
    fn test_granular_freeze() {
        let mut freeze = GranularFreeze::new(44100.0);

        let duration = 0.5;
        let samples = (44100.0 * duration) as usize;
        let input: Vec<f64> = (0..samples)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        freeze.set_freeze_position(samples / 2);
        freeze.set_frozen(true);

        let output = freeze.process(&input, 44100); // 1 second output

        assert_eq!(output.len(), 44100);
    }
}
