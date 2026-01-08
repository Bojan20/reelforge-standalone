//! Waveform Peak Generation
//!
//! Provides multi-resolution waveform peaks for efficient UI rendering:
//! - Level 0: 1 peak per 64 samples (finest, for maximum zoom)
//! - Level 1: 1 peak per 128 samples
//! - Level 2: 1 peak per 256 samples
//! - Level 3: 1 peak per 512 samples
//! - Level 4: 1 peak per 1024 samples (coarsest, for overview)
//!
//! Each peak stores (min, max) tuple for accurate waveform display.
//! SIMD optimized for fast peak calculation.

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Number of LOD levels
pub const NUM_LOD_LEVELS: usize = 5;

/// Samples per peak at each LOD level
pub const SAMPLES_PER_PEAK: [usize; NUM_LOD_LEVELS] = [64, 128, 256, 512, 1024];

// ═══════════════════════════════════════════════════════════════════════════
// PEAK DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Single peak value (min, max)
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct Peak {
    pub min: f32,
    pub max: f32,
}

impl Peak {
    pub fn new(min: f32, max: f32) -> Self {
        Self { min, max }
    }

    /// Get amplitude (max - min) / 2
    pub fn amplitude(&self) -> f32 {
        (self.max - self.min) / 2.0
    }

    /// Get center value
    pub fn center(&self) -> f32 {
        (self.max + self.min) / 2.0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVEFORM PEAKS
// ═══════════════════════════════════════════════════════════════════════════

/// Multi-resolution waveform peaks for a single channel
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaveformPeaks {
    /// Peaks at each LOD level
    levels: [Vec<Peak>; NUM_LOD_LEVELS],

    /// Sample rate of original audio
    pub sample_rate: u32,

    /// Total duration in seconds
    pub duration_secs: f64,
}

impl WaveformPeaks {
    /// Create empty waveform peaks
    pub fn empty(sample_rate: u32) -> Self {
        Self {
            levels: Default::default(),
            sample_rate,
            duration_secs: 0.0,
        }
    }

    /// Generate peaks from audio samples
    pub fn from_samples(samples: &[f32], sample_rate: u32) -> Self {
        let duration_secs = samples.len() as f64 / sample_rate as f64;

        let levels = [
            Self::generate_peaks_at_level(samples, SAMPLES_PER_PEAK[0]),
            Self::generate_peaks_at_level(samples, SAMPLES_PER_PEAK[1]),
            Self::generate_peaks_at_level(samples, SAMPLES_PER_PEAK[2]),
            Self::generate_peaks_at_level(samples, SAMPLES_PER_PEAK[3]),
            Self::generate_peaks_at_level(samples, SAMPLES_PER_PEAK[4]),
        ];

        Self {
            levels,
            sample_rate,
            duration_secs,
        }
    }

    /// Generate peaks at a specific samples-per-peak resolution
    fn generate_peaks_at_level(samples: &[f32], samples_per_peak: usize) -> Vec<Peak> {
        if samples.is_empty() {
            return Vec::new();
        }

        let num_peaks = (samples.len() + samples_per_peak - 1) / samples_per_peak;
        let mut peaks = Vec::with_capacity(num_peaks);

        for chunk in samples.chunks(samples_per_peak) {
            let (min, max) = Self::find_min_max(chunk);
            peaks.push(Peak::new(min, max));
        }

        peaks
    }

    /// Find min/max in a chunk of samples
    #[inline]
    fn find_min_max(samples: &[f32]) -> (f32, f32) {
        // SIMD-friendly reduction
        let mut min = f32::MAX;
        let mut max = f32::MIN;

        for &sample in samples {
            if sample < min {
                min = sample;
            }
            if sample > max {
                max = sample;
            }
        }

        (min, max)
    }

    /// Get peaks for a given zoom level (pixels per second)
    ///
    /// Returns the appropriate LOD level based on zoom
    pub fn get_peaks_for_zoom(&self, pixels_per_second: f64) -> &[Peak] {
        let lod = self.select_lod_level(pixels_per_second);
        &self.levels[lod]
    }

    /// Get peaks at a specific LOD level (0 = finest, 4 = coarsest)
    pub fn get_level(&self, level: usize) -> &[Peak] {
        &self.levels[level.min(NUM_LOD_LEVELS - 1)]
    }

    /// Select appropriate LOD level based on zoom
    ///
    /// Higher zoom = finer detail (lower level)
    /// Lower zoom = coarser detail (higher level)
    fn select_lod_level(&self, pixels_per_second: f64) -> usize {
        // Calculate pixels per sample at current zoom
        let pixels_per_sample = pixels_per_second / self.sample_rate as f64;

        // We want roughly 1 peak per 2-4 pixels for good visual density
        let target_samples_per_pixel = 2.0 / pixels_per_sample;

        // Find the LOD level that gives us closest to target
        for (level, &samples_per_peak) in SAMPLES_PER_PEAK.iter().enumerate() {
            if samples_per_peak as f64 >= target_samples_per_pixel {
                return level;
            }
        }

        NUM_LOD_LEVELS - 1
    }

    /// Get peaks for a time range at appropriate LOD
    pub fn get_peaks_in_range(
        &self,
        start_time: f64,
        end_time: f64,
        pixels_per_second: f64,
    ) -> Vec<Peak> {
        let lod = self.select_lod_level(pixels_per_second);
        let samples_per_peak = SAMPLES_PER_PEAK[lod];
        let seconds_per_peak = samples_per_peak as f64 / self.sample_rate as f64;

        let start_idx = (start_time / seconds_per_peak).floor() as usize;
        let end_idx = ((end_time / seconds_per_peak).ceil() as usize).min(self.levels[lod].len());

        if start_idx >= end_idx || start_idx >= self.levels[lod].len() {
            return Vec::new();
        }

        self.levels[lod][start_idx..end_idx].to_vec()
    }

    /// Total number of peaks at finest level
    pub fn len(&self) -> usize {
        self.levels[0].len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.levels[0].is_empty()
    }

    /// Get flat array of peak values for FFI (min0, max0, min1, max1, ...)
    pub fn to_flat_array(&self, level: usize) -> Vec<f32> {
        let level = level.min(NUM_LOD_LEVELS - 1);
        let mut result = Vec::with_capacity(self.levels[level].len() * 2);

        for peak in &self.levels[level] {
            result.push(peak.min);
            result.push(peak.max);
        }

        result
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO WAVEFORM
// ═══════════════════════════════════════════════════════════════════════════

/// Stereo waveform with separate L/R peaks
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StereoWaveformPeaks {
    pub left: WaveformPeaks,
    pub right: WaveformPeaks,
}

impl StereoWaveformPeaks {
    /// Create from interleaved stereo samples
    pub fn from_interleaved(samples: &[f32], sample_rate: u32) -> Self {
        let (left, right): (Vec<f32>, Vec<f32>) = samples
            .chunks(2)
            .map(|chunk| (chunk[0], chunk.get(1).copied().unwrap_or(chunk[0])))
            .unzip();

        Self {
            left: WaveformPeaks::from_samples(&left, sample_rate),
            right: WaveformPeaks::from_samples(&right, sample_rate),
        }
    }

    /// Create mono waveform (same peaks for both channels)
    pub fn from_mono(samples: &[f32], sample_rate: u32) -> Self {
        let peaks = WaveformPeaks::from_samples(samples, sample_rate);
        Self {
            left: peaks.clone(),
            right: peaks,
        }
    }

    /// Get combined (mixed) peaks for display
    pub fn get_combined_peaks_for_zoom(&self, pixels_per_second: f64) -> Vec<Peak> {
        let left = self.left.get_peaks_for_zoom(pixels_per_second);
        let right = self.right.get_peaks_for_zoom(pixels_per_second);

        left.iter()
            .zip(right.iter())
            .map(|(l, r)| Peak::new(l.min.min(r.min), l.max.max(r.max)))
            .collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVEFORM CACHE
// ═══════════════════════════════════════════════════════════════════════════

use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;

/// Cache for computed waveform peaks
pub struct WaveformCache {
    /// Internal cache storage
    pub cache: RwLock<HashMap<String, Arc<StereoWaveformPeaks>>>,
}

impl WaveformCache {
    pub fn new() -> Self {
        Self {
            cache: RwLock::new(HashMap::new()),
        }
    }

    /// Get or compute waveform peaks for a file
    pub fn get_or_compute<F>(&self, key: &str, compute: F) -> Arc<StereoWaveformPeaks>
    where
        F: FnOnce() -> StereoWaveformPeaks,
    {
        // Check cache first
        if let Some(peaks) = self.cache.read().get(key) {
            return Arc::clone(peaks);
        }

        // Compute and cache
        let peaks = Arc::new(compute());
        self.cache
            .write()
            .insert(key.to_string(), Arc::clone(&peaks));
        peaks
    }

    /// Remove from cache
    pub fn invalidate(&self, key: &str) {
        self.cache.write().remove(key);
    }

    /// Clear entire cache
    pub fn clear(&self) {
        self.cache.write().clear();
    }

    /// Get cache size
    pub fn len(&self) -> usize {
        self.cache.read().len()
    }

    pub fn is_empty(&self) -> bool {
        self.cache.read().is_empty()
    }

    /// Get memory usage in bytes (approximate)
    pub fn memory_usage(&self) -> usize {
        self.cache
            .read()
            .values()
            .map(|peaks| {
                // Each level has Vec<Peak> where Peak is 8 bytes (2 x f32)
                let left_size: usize = peaks
                    .left
                    .levels
                    .iter()
                    .map(|v| v.len() * std::mem::size_of::<Peak>())
                    .sum();
                let right_size: usize = peaks
                    .right
                    .levels
                    .iter()
                    .map(|v| v.len() * std::mem::size_of::<Peak>())
                    .sum();
                left_size + right_size
            })
            .sum()
    }
}

impl Default for WaveformCache {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::f32::consts::PI;

    fn generate_sine_wave(freq: f32, sample_rate: u32, duration_secs: f32) -> Vec<f32> {
        let num_samples = (sample_rate as f32 * duration_secs) as usize;
        (0..num_samples)
            .map(|i| (2.0 * PI * freq * i as f32 / sample_rate as f32).sin())
            .collect()
    }

    #[test]
    fn test_peak_generation() {
        let samples = generate_sine_wave(440.0, 48000, 1.0);
        let peaks = WaveformPeaks::from_samples(&samples, 48000);

        // Should have peaks at all levels
        assert!(!peaks.is_empty());
        assert_eq!(peaks.sample_rate, 48000);
        assert!((peaks.duration_secs - 1.0).abs() < 0.001);

        // Finest level should have most peaks
        assert!(peaks.levels[0].len() > peaks.levels[4].len());
    }

    #[test]
    fn test_peak_values() {
        // Sine wave should have peaks near -1 and +1
        let samples = generate_sine_wave(10.0, 48000, 1.0); // Low freq for clear peaks
        let peaks = WaveformPeaks::from_samples(&samples, 48000);

        let finest = &peaks.levels[0];
        assert!(!finest.is_empty());

        // Check that we found the sine wave extremes
        let max_peak = finest.iter().map(|p| p.max).fold(f32::MIN, f32::max);
        let min_peak = finest.iter().map(|p| p.min).fold(f32::MAX, f32::min);

        assert!(max_peak > 0.9);
        assert!(min_peak < -0.9);
    }

    #[test]
    fn test_lod_selection() {
        let samples = generate_sine_wave(440.0, 48000, 1.0);
        let peaks = WaveformPeaks::from_samples(&samples, 48000);

        // Very high zoom (many pixels per second) should select fine level
        let lod_high_zoom = peaks.select_lod_level(10000.0);
        assert!(
            lod_high_zoom <= 2,
            "High zoom should select fine LOD, got {}",
            lod_high_zoom
        );

        // Low zoom (few pixels per second) should select coarser level
        let lod_low_zoom = peaks.select_lod_level(10.0);
        assert!(
            lod_low_zoom >= 2,
            "Low zoom should select coarse LOD, got {}",
            lod_low_zoom
        );

        // Verify ordering: higher zoom = finer LOD (lower level)
        assert!(lod_high_zoom <= lod_low_zoom);
    }

    #[test]
    fn test_stereo_waveform() {
        let left: Vec<f32> = (0..1000).map(|i| (i as f32 / 1000.0).sin()).collect();
        let right: Vec<f32> = (0..1000).map(|i| (i as f32 / 1000.0).cos()).collect();

        // Interleave
        let stereo: Vec<f32> = left
            .iter()
            .zip(right.iter())
            .flat_map(|(&l, &r)| [l, r])
            .collect();

        let peaks = StereoWaveformPeaks::from_interleaved(&stereo, 48000);

        assert!(!peaks.left.is_empty());
        assert!(!peaks.right.is_empty());
    }

    #[test]
    fn test_flat_array_output() {
        let samples = vec![0.0, 0.5, 1.0, 0.5, 0.0, -0.5, -1.0, -0.5];
        let peaks = WaveformPeaks::from_samples(&samples, 48000);

        // At finest level with small sample count
        let flat = peaks.to_flat_array(0);

        // Should be pairs of (min, max)
        assert_eq!(flat.len() % 2, 0);
    }

    #[test]
    fn test_waveform_cache() {
        let cache = WaveformCache::new();

        let peaks1 = cache.get_or_compute("test.wav", || {
            StereoWaveformPeaks::from_mono(&[0.0, 0.5, 1.0], 48000)
        });

        let peaks2 = cache.get_or_compute("test.wav", || {
            panic!("Should not recompute!");
        });

        // Should be same Arc
        assert!(Arc::ptr_eq(&peaks1, &peaks2));
        assert_eq!(cache.len(), 1);
    }
}
