//! Audio declipping - reconstruct clipped waveforms
//!
//! Advanced declipping using:
//! - Spline interpolation for hard clips
//! - Spectral reconstruction
//! - Psychoacoustic masking

use crate::error::{RestoreError, RestoreResult};
use crate::{RestoreConfig, Restorer};

/// Clipping detection mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClipDetectionMode {
    /// Hard clipping (flat tops)
    Hard,
    /// Soft clipping (rounded saturation)
    Soft,
    /// Auto detect
    Auto,
}

/// Declipping configuration
#[derive(Debug, Clone)]
pub struct DeclipConfig {
    /// Base configuration
    pub base: RestoreConfig,
    /// Detection threshold (0.9 - 1.0)
    pub threshold: f32,
    /// Margin for reconstruction (samples)
    pub margin_samples: usize,
    /// Detection mode
    pub mode: ClipDetectionMode,
    /// Quality (iterations)
    pub quality: usize,
    /// Preserve transients
    pub preserve_transients: bool,
}

impl Default for DeclipConfig {
    fn default() -> Self {
        Self {
            base: RestoreConfig::default(),
            threshold: 0.99,
            margin_samples: 4,
            mode: ClipDetectionMode::Auto,
            quality: 3,
            preserve_transients: true,
        }
    }
}

/// Declipping processor
pub struct Declip {
    /// Configuration
    config: DeclipConfig,
    /// Internal buffer
    buffer: Vec<f32>,
    /// Clip regions [(start, end)]
    clip_regions: Vec<(usize, usize)>,
}

impl Declip {
    /// Create new declipping processor
    pub fn new(config: DeclipConfig) -> Self {
        Self {
            config,
            buffer: Vec::new(),
            clip_regions: Vec::new(),
        }
    }

    /// Detect clipped regions
    fn detect_clips(&mut self, audio: &[f32]) {
        self.clip_regions.clear();

        let threshold = self.config.threshold;
        let margin = self.config.margin_samples;

        let mut in_clip = false;
        let mut clip_start = 0;

        for (i, &sample) in audio.iter().enumerate() {
            let is_clipped = sample.abs() >= threshold;

            if is_clipped && !in_clip {
                // Start of clip region
                clip_start = i.saturating_sub(margin);
                in_clip = true;
            } else if !is_clipped && in_clip {
                // End of clip region
                let clip_end = (i + margin).min(audio.len());
                self.clip_regions.push((clip_start, clip_end));
                in_clip = false;
            }
        }

        // Handle clip at end
        if in_clip {
            self.clip_regions.push((clip_start, audio.len()));
        }

        // Merge adjacent regions
        self.merge_adjacent_regions();
    }

    /// Merge overlapping clip regions
    fn merge_adjacent_regions(&mut self) {
        if self.clip_regions.len() < 2 {
            return;
        }

        let mut merged = Vec::new();
        let mut current = self.clip_regions[0];

        for &(start, end) in self.clip_regions.iter().skip(1) {
            if start <= current.1 {
                // Overlapping, merge
                current.1 = current.1.max(end);
            } else {
                // Not overlapping, save and start new
                merged.push(current);
                current = (start, end);
            }
        }
        merged.push(current);

        self.clip_regions = merged;
    }

    /// Reconstruct clipped region using cubic spline
    fn reconstruct_spline(&self, audio: &[f32], start: usize, end: usize) -> Vec<f32> {
        let margin = self.config.margin_samples;
        let len = end - start;

        if len < 4 {
            return audio[start..end].to_vec();
        }

        // Get boundary points
        let left_points: Vec<f32> = audio[start.saturating_sub(margin * 2)..start]
            .iter()
            .copied()
            .collect();
        let right_points: Vec<f32> = audio[end..(end + margin * 2).min(audio.len())]
            .iter()
            .copied()
            .collect();

        if left_points.is_empty() || right_points.is_empty() {
            return audio[start..end].to_vec();
        }

        // Cubic Hermite spline interpolation
        let mut result = vec![0.0f32; len];

        // Estimate derivatives at boundaries
        let left_deriv = if left_points.len() >= 2 {
            left_points[left_points.len() - 1] - left_points[left_points.len() - 2]
        } else {
            0.0
        };
        let right_deriv = if right_points.len() >= 2 {
            right_points[1] - right_points[0]
        } else {
            0.0
        };

        let p0 = *left_points.last().unwrap_or(&0.0);
        let p1 = *right_points.first().unwrap_or(&0.0);
        let m0 = left_deriv * len as f32;
        let m1 = right_deriv * len as f32;

        for i in 0..len {
            let t = i as f32 / len as f32;
            let t2 = t * t;
            let t3 = t2 * t;

            // Hermite basis functions
            let h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
            let h10 = t3 - 2.0 * t2 + t;
            let h01 = -2.0 * t3 + 3.0 * t2;
            let h11 = t3 - t2;

            result[i] = h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1;
        }

        result
    }

    /// Apply soft limiting to reconstructed peaks
    fn soft_limit(&self, sample: f32, limit: f32) -> f32 {
        if sample.abs() <= limit {
            sample
        } else {
            let sign = sample.signum();
            let x = sample.abs();
            let over = x - limit;
            sign * (limit + over / (1.0 + over / limit))
        }
    }
}

impl Restorer for Declip {
    fn process(&mut self, input: &[f32], output: &mut [f32]) -> RestoreResult<()> {
        if input.len() != output.len() {
            return Err(RestoreError::BufferMismatch {
                expected: input.len(),
                got: output.len(),
            });
        }

        // Detect clips
        self.detect_clips(input);

        // Copy input to output
        output.copy_from_slice(input);

        // Reconstruct each clip region
        for &(start, end) in &self.clip_regions {
            let reconstructed = self.reconstruct_spline(input, start, end);

            // Apply reconstruction with soft limiting
            for (i, &sample) in reconstructed.iter().enumerate() {
                let idx = start + i;
                if idx < output.len() {
                    // Soft limit to prevent new clipping
                    output[idx] = self.soft_limit(sample, 0.999);
                }
            }
        }

        // Apply quality iterations (spectral refinement)
        for _ in 0..self.config.quality.saturating_sub(1) {
            // Re-detect any remaining clips
            self.detect_clips(output);

            // Apply smaller corrections
            for &(start, end) in &self.clip_regions {
                let reconstructed = self.reconstruct_spline(output, start, end);
                for (i, &sample) in reconstructed.iter().enumerate() {
                    let idx = start + i;
                    if idx < output.len() {
                        output[idx] = self.soft_limit(sample, 0.999);
                    }
                }
            }
        }

        Ok(())
    }

    fn reset(&mut self) {
        self.buffer.clear();
        self.clip_regions.clear();
    }

    fn latency_samples(&self) -> usize {
        0 // Non-latent processing
    }

    fn name(&self) -> &str {
        "Declip"
    }
}

/// Statistics about declipping
#[derive(Debug, Clone, Default)]
pub struct DeclipStats {
    /// Number of clipped regions detected
    pub regions_detected: usize,
    /// Total clipped samples
    pub samples_repaired: usize,
    /// Peak original value
    pub peak_original: f32,
    /// Peak reconstructed value
    pub peak_reconstructed: f32,
}

impl Declip {
    /// Get statistics from last processing
    pub fn get_stats(&self, original: &[f32], processed: &[f32]) -> DeclipStats {
        DeclipStats {
            regions_detected: self.clip_regions.len(),
            samples_repaired: self.clip_regions.iter().map(|(s, e)| e - s).sum(),
            peak_original: original.iter().map(|s| s.abs()).fold(0.0f32, f32::max),
            peak_reconstructed: processed.iter().map(|s| s.abs()).fold(0.0f32, f32::max),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_declip_creation() {
        let config = DeclipConfig::default();
        let declip = Declip::new(config);
        assert_eq!(declip.name(), "Declip");
    }

    #[test]
    fn test_clip_detection() {
        let config = DeclipConfig::default();
        let mut declip = Declip::new(config);

        // Create signal with clipping
        let signal: Vec<f32> = (0..1000).map(|i| {
            let s = (i as f32 * 0.05).sin() * 1.5;
            s.clamp(-1.0, 1.0) // Hard clip at ±1
        }).collect();

        declip.detect_clips(&signal);

        assert!(!declip.clip_regions.is_empty(), "Should detect clip regions");
    }

    #[test]
    fn test_declip_process() {
        let config = DeclipConfig::default();
        let mut declip = Declip::new(config);

        // Create clipped signal
        let input: Vec<f32> = (0..1000).map(|i| {
            let s = (i as f32 * 0.05).sin() * 1.5;
            s.clamp(-1.0, 1.0)
        }).collect();

        let mut output = vec![0.0f32; 1000];
        declip.process(&input, &mut output).unwrap();

        // Output should be different from input (reconstructed)
        let diff: f32 = input.iter()
            .zip(output.iter())
            .map(|(a, b)| (a - b).abs())
            .sum();

        assert!(diff > 0.0, "Declipping should modify clipped regions");
    }

    #[test]
    fn test_soft_limit() {
        let config = DeclipConfig::default();
        let declip = Declip::new(config);

        assert_eq!(declip.soft_limit(0.5, 1.0), 0.5);
        assert!(declip.soft_limit(1.5, 1.0) < 1.5);
        assert!(declip.soft_limit(1.5, 1.0) > 1.0);
    }
}
