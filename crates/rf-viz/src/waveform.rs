//! Waveform display visualization

use rf_core::Sample;

/// Waveform display configuration
#[derive(Debug, Clone)]
pub struct WaveformConfig {
    pub width: u32,
    pub height: u32,
    pub samples_per_pixel: usize,
    pub color: [f32; 4],
    pub background_color: [f32; 4],
}

impl Default for WaveformConfig {
    fn default() -> Self {
        Self {
            width: 800,
            height: 100,
            samples_per_pixel: 256,
            color: [0.25, 0.78, 1.0, 1.0], // Cyan
            background_color: [0.05, 0.05, 0.06, 1.0],
        }
    }
}

/// Level-of-detail cache for waveform display
pub struct WaveformLod {
    /// Min/max pairs for each level of detail
    levels: Vec<Vec<(f32, f32)>>,
    sample_rate: f32,
    total_samples: usize,
}

impl WaveformLod {
    /// Create a new LOD cache from audio samples
    pub fn new(samples: &[Sample], sample_rate: f32) -> Self {
        let total_samples = samples.len();
        let mut levels = Vec::new();

        // Level 0: 1 sample per entry
        let level0: Vec<(f32, f32)> = samples
            .iter()
            .map(|&s| {
                let s = s as f32;
                (s, s)
            })
            .collect();
        levels.push(level0);

        // Generate higher LOD levels (each level is 2x reduction)
        let mut current_level = 0;
        while levels[current_level].len() > 1 {
            let prev = &levels[current_level];
            let next: Vec<(f32, f32)> = prev
                .chunks(2)
                .map(|chunk| {
                    let min = chunk.iter().map(|(min, _)| *min).fold(f32::INFINITY, f32::min);
                    let max = chunk.iter().map(|(_, max)| *max).fold(f32::NEG_INFINITY, f32::max);
                    (min, max)
                })
                .collect();
            levels.push(next);
            current_level += 1;

            // Stop at reasonable level
            if current_level > 16 {
                break;
            }
        }

        Self {
            levels,
            sample_rate,
            total_samples,
        }
    }

    /// Get min/max values for a range of samples at appropriate LOD
    pub fn get_range(&self, start_sample: usize, end_sample: usize, target_pixels: usize) -> Vec<(f32, f32)> {
        let sample_count = end_sample.saturating_sub(start_sample);
        if sample_count == 0 || target_pixels == 0 {
            return Vec::new();
        }

        // Choose appropriate LOD level
        let samples_per_pixel = sample_count / target_pixels;
        let lod_level = (samples_per_pixel as f32).log2().floor() as usize;
        let lod_level = lod_level.min(self.levels.len() - 1);

        let level = &self.levels[lod_level];
        let reduction = 1 << lod_level;

        let start_idx = start_sample / reduction;
        let end_idx = (end_sample / reduction).min(level.len());

        // Sample the LOD level for target pixels
        let indices_per_pixel = (end_idx - start_idx) / target_pixels.max(1);
        if indices_per_pixel == 0 {
            return level[start_idx..end_idx].to_vec();
        }

        (0..target_pixels)
            .map(|i| {
                let idx_start = start_idx + i * indices_per_pixel;
                let idx_end = (idx_start + indices_per_pixel).min(end_idx);

                let mut min = f32::INFINITY;
                let mut max = f32::NEG_INFINITY;

                for idx in idx_start..idx_end {
                    if idx < level.len() {
                        min = min.min(level[idx].0);
                        max = max.max(level[idx].1);
                    }
                }

                (min, max)
            })
            .collect()
    }

    /// Get duration in seconds
    pub fn duration(&self) -> f32 {
        self.total_samples as f32 / self.sample_rate
    }

    /// Get total sample count
    pub fn sample_count(&self) -> usize {
        self.total_samples
    }
}

/// Simple waveform renderer (CPU-based for now)
pub struct WaveformRenderer {
    config: WaveformConfig,
}

impl WaveformRenderer {
    pub fn new(config: WaveformConfig) -> Self {
        Self { config }
    }

    /// Render waveform to RGBA buffer
    pub fn render(&self, lod: &WaveformLod, start_sample: usize, end_sample: usize) -> Vec<u8> {
        let width = self.config.width as usize;
        let height = self.config.height as usize;
        let mut buffer = vec![0u8; width * height * 4];

        // Fill background
        for pixel in buffer.chunks_mut(4) {
            pixel[0] = (self.config.background_color[0] * 255.0) as u8;
            pixel[1] = (self.config.background_color[1] * 255.0) as u8;
            pixel[2] = (self.config.background_color[2] * 255.0) as u8;
            pixel[3] = (self.config.background_color[3] * 255.0) as u8;
        }

        // Get min/max values
        let min_max = lod.get_range(start_sample, end_sample, width);

        let center_y = height / 2;
        let amplitude = height as f32 / 2.0;

        for (x, (min, max)) in min_max.iter().enumerate() {
            // Convert to pixel coordinates
            let y_min = center_y - (max * amplitude) as usize;
            let y_max = center_y - (min * amplitude) as usize;

            let y_min = y_min.clamp(0, height - 1);
            let y_max = y_max.clamp(0, height - 1);

            // Draw vertical line
            for y in y_min..=y_max {
                let idx = (y * width + x) * 4;
                if idx + 3 < buffer.len() {
                    buffer[idx] = (self.config.color[0] * 255.0) as u8;
                    buffer[idx + 1] = (self.config.color[1] * 255.0) as u8;
                    buffer[idx + 2] = (self.config.color[2] * 255.0) as u8;
                    buffer[idx + 3] = (self.config.color[3] * 255.0) as u8;
                }
            }
        }

        buffer
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_waveform_lod() {
        // Create a simple sine wave
        let samples: Vec<Sample> = (0..48000)
            .map(|i| (i as f64 * 0.01).sin())
            .collect();

        let lod = WaveformLod::new(&samples, 48000.0);

        assert_eq!(lod.sample_count(), 48000);
        assert!((lod.duration() - 1.0).abs() < 0.001);

        // Get range at different zoom levels
        let range1 = lod.get_range(0, 48000, 100);
        assert_eq!(range1.len(), 100);

        let range2 = lod.get_range(0, 48000, 1000);
        assert_eq!(range2.len(), 1000);
    }
}
