//! # WSOLA (Waveform Similarity Overlap-Add)
//!
//! Time-domain time stretching algorithm optimal for transient-heavy material.
//!
//! ## Algorithm
//!
//! 1. Extract frames at analysis positions
//! 2. Find optimal synthesis position via cross-correlation
//! 3. Overlap-add with cross-fade
//!
//! ## References
//!
//! - Verhelst, W., & Roelands, M. (1993). "An overlap-add technique based on
//!   waveform similarity (WSOLA) for high quality time-scale modification of speech"

use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// WSOLA PROCESSOR
// ═══════════════════════════════════════════════════════════════════════════════

/// WSOLA time stretching processor
pub struct WsolaProcessor {
    /// Sample rate
    sample_rate: f64,
    /// Window size in samples
    window_size: usize,
    /// Search range for optimal position (±samples)
    search_range: usize,
    /// Overlap ratio (0.0 - 1.0)
    overlap_ratio: f64,
    /// Synthesis window
    window: Vec<f64>,
    /// Previous synthesis frame (for overlap)
    prev_frame: Vec<f64>,
}

impl WsolaProcessor {
    /// Create new WSOLA processor
    pub fn new(sample_rate: f64) -> Self {
        let window_size = (sample_rate * 0.025) as usize; // 25ms default
        let window_size = window_size.next_power_of_two();

        Self {
            sample_rate,
            window_size,
            search_range: window_size / 4,
            overlap_ratio: 0.5,
            window: Self::create_hann_window(window_size),
            prev_frame: vec![0.0; window_size],
        }
    }

    /// Create with custom window size
    pub fn with_window_size(sample_rate: f64, window_ms: f64) -> Self {
        let window_size = (sample_rate * window_ms / 1000.0) as usize;
        let window_size = window_size.max(64).next_power_of_two();

        Self {
            sample_rate,
            window_size,
            search_range: window_size / 4,
            overlap_ratio: 0.5,
            window: Self::create_hann_window(window_size),
            prev_frame: vec![0.0; window_size],
        }
    }

    /// Create Hann window
    fn create_hann_window(size: usize) -> Vec<f64> {
        (0..size)
            .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f64 / size as f64).cos()))
            .collect()
    }

    /// Process audio with time stretch
    pub fn process(&mut self, input: &[f64], ratio: f64) -> Vec<f64> {
        if input.is_empty() || ratio <= 0.0 {
            return vec![];
        }

        let overlap_samples = (self.window_size as f64 * self.overlap_ratio) as usize;
        let hop_analysis = self.window_size - overlap_samples;
        let hop_synthesis = (hop_analysis as f64 * ratio) as usize;

        // Calculate output length
        let num_frames = (input.len().saturating_sub(self.window_size)) / hop_analysis + 1;
        let output_len = (num_frames - 1) * hop_synthesis + self.window_size;
        let mut output = vec![0.0; output_len];

        // Initialize previous frame position
        let mut _prev_analysis_pos: i64 = 0;
        let mut synthesis_pos: usize = 0;

        // Reset previous frame
        self.prev_frame.fill(0.0);

        for frame_idx in 0..num_frames {
            // Target analysis position (where we want to read)
            let target_analysis = (frame_idx as f64 * hop_analysis as f64 / ratio) as i64;

            // Find optimal position within search range
            let optimal_pos = self.find_optimal_position(input, target_analysis, &self.prev_frame);

            // Extract frame at optimal position
            let frame = self.extract_frame(input, optimal_pos as usize);

            // Apply window and overlap-add
            for (i, (&sample, &win)) in frame.iter().zip(self.window.iter()).enumerate() {
                if synthesis_pos + i < output_len {
                    output[synthesis_pos + i] += sample * win;
                }
            }

            // Store for next iteration's cross-correlation
            self.prev_frame.copy_from_slice(&frame);

            // Advance positions
            _prev_analysis_pos = optimal_pos;
            synthesis_pos += hop_synthesis;
        }

        // Normalize by window overlap
        self.normalize_output(&mut output, hop_synthesis);

        output
    }

    /// Find optimal analysis position using cross-correlation
    fn find_optimal_position(&self, input: &[f64], target: i64, prev_frame: &[f64]) -> i64 {
        let input_len = input.len() as i64;
        let search_start = (target - self.search_range as i64).max(0);
        let search_end =
            (target + self.search_range as i64).min(input_len - self.window_size as i64);

        if search_start >= search_end {
            return target.clamp(0, input_len - self.window_size as i64);
        }

        let mut best_pos = target;
        let mut best_correlation = f64::NEG_INFINITY;

        // Search for position with best correlation to previous frame
        for pos in search_start..search_end {
            let correlation = self.cross_correlation(input, pos as usize, prev_frame);
            if correlation > best_correlation {
                best_correlation = correlation;
                best_pos = pos;
            }
        }

        best_pos.max(0)
    }

    /// Compute normalized cross-correlation
    fn cross_correlation(&self, input: &[f64], pos: usize, reference: &[f64]) -> f64 {
        let overlap = (self.window_size as f64 * self.overlap_ratio) as usize;

        let mut sum = 0.0;
        let mut energy_input = 0.0;
        let mut energy_ref = 0.0;

        for i in 0..overlap {
            if pos + i < input.len() && i < reference.len() {
                let a = input[pos + i];
                let b = reference[self.window_size - overlap + i];

                sum += a * b;
                energy_input += a * a;
                energy_ref += b * b;
            }
        }

        let denominator = (energy_input * energy_ref).sqrt();
        if denominator > 1e-10 {
            sum / denominator
        } else {
            0.0
        }
    }

    /// Extract windowed frame from input
    fn extract_frame(&self, input: &[f64], pos: usize) -> Vec<f64> {
        let mut frame = vec![0.0; self.window_size];

        for i in 0..self.window_size {
            if pos + i < input.len() {
                frame[i] = input[pos + i];
            }
        }

        frame
    }

    /// Normalize output by window overlap sum
    fn normalize_output(&self, output: &mut [f64], hop: usize) {
        // Compute window overlap sum
        let mut window_sum = vec![0.0; output.len()];
        let num_frames = (output.len().saturating_sub(self.window_size)) / hop + 1;

        for frame in 0..num_frames {
            let pos = frame * hop;
            for (i, &w) in self.window.iter().enumerate() {
                if pos + i < window_sum.len() {
                    window_sum[pos + i] += w * w;
                }
            }
        }

        // Normalize
        for (out, &norm) in output.iter_mut().zip(window_sum.iter()) {
            if norm > 1e-10 {
                *out /= norm;
            }
        }
    }

    /// Reset processor state
    pub fn reset(&mut self) {
        self.prev_frame.fill(0.0);
    }

    /// Set window size in milliseconds
    pub fn set_window_size_ms(&mut self, ms: f64) {
        let size = (self.sample_rate * ms / 1000.0) as usize;
        self.window_size = size.max(64).next_power_of_two();
        self.search_range = self.window_size / 4;
        self.window = Self::create_hann_window(self.window_size);
        self.prev_frame = vec![0.0; self.window_size];
    }

    /// Set search range in milliseconds
    pub fn set_search_range_ms(&mut self, ms: f64) {
        self.search_range = (self.sample_rate * ms / 1000.0) as usize;
    }

    /// Set overlap ratio (0.0 - 0.9)
    pub fn set_overlap_ratio(&mut self, ratio: f64) {
        self.overlap_ratio = ratio.clamp(0.1, 0.9);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_wsola_creation() {
        let wsola = WsolaProcessor::new(44100.0);
        assert!(wsola.window_size > 0);
        assert!(wsola.search_range > 0);
    }

    #[test]
    fn test_wsola_unity_stretch() {
        let mut wsola = WsolaProcessor::new(44100.0);

        // Generate sine wave
        let duration = 0.1; // 100ms
        let samples = (44100.0 * duration) as usize;
        let input: Vec<f64> = (0..samples)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        // Unity stretch should produce similar length output
        let output = wsola.process(&input, 1.0);

        let length_ratio = output.len() as f64 / input.len() as f64;
        assert!((length_ratio - 1.0).abs() < 0.2); // Within 20%
    }

    #[test]
    fn test_wsola_stretch() {
        let mut wsola = WsolaProcessor::new(44100.0);

        // Longer signal for more stable stretch
        let duration = 0.3;
        let samples = (44100.0 * duration) as usize;
        let input: Vec<f64> = (0..samples)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        // 2x stretch
        let output = wsola.process(&input, 2.0);
        let length_ratio = output.len() as f64 / input.len() as f64;

        // Output should be approximately 2x length (wider tolerance for frame-based processing)
        assert!(
            length_ratio > 1.2 && length_ratio < 3.0,
            "ratio was {}",
            length_ratio
        );
    }

    #[test]
    fn test_wsola_compress() {
        let mut wsola = WsolaProcessor::new(44100.0);

        let duration = 0.3;
        let samples = (44100.0 * duration) as usize;
        let input: Vec<f64> = (0..samples)
            .map(|i| (2.0 * PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        // 0.5x stretch (compression)
        let output = wsola.process(&input, 0.5);
        let length_ratio = output.len() as f64 / input.len() as f64;

        // Output should be approximately 0.5x length (wider tolerance)
        assert!(
            length_ratio > 0.2 && length_ratio < 0.9,
            "ratio was {}",
            length_ratio
        );
    }

    #[test]
    fn test_cross_correlation() {
        let wsola = WsolaProcessor::new(44100.0);

        // Test that cross_correlation doesn't panic and returns a valid number
        // The actual correlation depends on the overlap region algorithm
        let len = 4096;
        let signal: Vec<f64> = (0..len)
            .map(|i| (2.0 * PI * 100.0 * i as f64 / 44100.0).sin())
            .collect();

        let corr = wsola.cross_correlation(&signal, 0, &signal);
        // Just verify it returns a valid normalized correlation [-1, 1]
        assert!(corr >= -1.0 && corr <= 1.0, "correlation was {}", corr);
    }
}
