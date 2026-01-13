//! Cubase-Style Waveform Peak Generation
//!
//! Professional multi-resolution waveform cache with:
//! - min/max/rms per bucket for accurate display
//! - 8 LOD levels for smooth zoom
//! - Pixel-exact query (bucketFrames <= framesPerPixel)
//! - RMS body + peak stroke rendering data
//!
//! Levels:
//! - Level 0: 32 samples/bucket (finest - sample view transition)
//! - Level 1: 64 samples/bucket
//! - Level 2: 128 samples/bucket
//! - Level 3: 256 samples/bucket
//! - Level 4: 512 samples/bucket
//! - Level 5: 1024 samples/bucket
//! - Level 6: 2048 samples/bucket
//! - Level 7: 4096 samples/bucket (coarsest - full project overview)

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Number of LOD levels (11 for smooth zooming including ultra-fine for transient detail)
pub const NUM_LOD_LEVELS: usize = 11;

/// Samples per bucket at each LOD level
/// Levels 0-2: Ultra-fine for sample-level zoom (transient detail)
/// Levels 3-10: Standard zoom levels
pub const SAMPLES_PER_BUCKET: [usize; NUM_LOD_LEVELS] = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096];

// Keep old constants for backward compatibility
pub const SAMPLES_PER_PEAK: [usize; 5] = [64, 128, 256, 512, 1024];

// ═══════════════════════════════════════════════════════════════════════════
// BUCKET DATA - min/max/rms per bucket
// ═══════════════════════════════════════════════════════════════════════════

/// Single bucket with min, max, and RMS for accurate waveform display
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct WaveformBucket {
    /// Minimum sample value in bucket
    pub min: f32,
    /// Maximum sample value in bucket
    pub max: f32,
    /// RMS (root mean square) energy in bucket
    pub rms: f32,
}

impl WaveformBucket {
    #[inline]
    pub fn new(min: f32, max: f32, rms: f32) -> Self {
        Self { min, max, rms }
    }

    /// Create from samples
    pub fn from_samples(samples: &[f32]) -> Self {
        if samples.is_empty() {
            return Self::default();
        }

        let mut min = f32::MAX;
        let mut max = f32::MIN;
        let mut sum_sq = 0.0f64;

        for &s in samples {
            if s < min { min = s; }
            if s > max { max = s; }
            sum_sq += (s as f64) * (s as f64);
        }

        let rms = (sum_sq / samples.len() as f64).sqrt() as f32;

        Self { min, max, rms }
    }

    /// Merge multiple buckets (for aggregation)
    #[inline]
    pub fn merge(buckets: &[WaveformBucket]) -> Self {
        if buckets.is_empty() {
            return Self::default();
        }

        let mut min = f32::MAX;
        let mut max = f32::MIN;
        let mut rms_sq_sum = 0.0f64;

        for b in buckets {
            if b.min < min { min = b.min; }
            if b.max > max { max = b.max; }
            rms_sq_sum += (b.rms as f64) * (b.rms as f64);
        }

        // Combined RMS: sqrt(mean of squared RMS values)
        let rms = (rms_sq_sum / buckets.len() as f64).sqrt() as f32;

        Self { min, max, rms }
    }

    /// Get peak amplitude (for peak stroke)
    #[inline]
    pub fn peak_amplitude(&self) -> f32 {
        self.max.abs().max(self.min.abs())
    }
}

// Backward compatibility alias
pub type Peak = WaveformBucket;

impl Peak {
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
// WAVEFORM DATA - Single channel multi-resolution
// ═══════════════════════════════════════════════════════════════════════════

/// Multi-resolution waveform data for a single channel
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaveformData {
    /// Buckets at each LOD level
    levels: [Vec<WaveformBucket>; NUM_LOD_LEVELS],

    /// Sample rate of original audio
    pub sample_rate: u32,

    /// Total number of samples in original audio
    pub total_samples: usize,

    /// Total duration in seconds
    pub duration_secs: f64,
}

impl WaveformData {
    /// Create empty waveform data
    pub fn empty(sample_rate: u32) -> Self {
        Self {
            levels: std::array::from_fn(|_| Vec::new()),
            sample_rate,
            total_samples: 0,
            duration_secs: 0.0,
        }
    }

    /// Generate waveform data from samples
    pub fn from_samples(samples: &[f32], sample_rate: u32) -> Self {
        if samples.is_empty() {
            return Self::empty(sample_rate);
        }

        let total_samples = samples.len();
        let duration_secs = total_samples as f64 / sample_rate as f64;

        // Build all LOD levels (11 levels: 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096)
        let levels = [
            Self::build_level(samples, SAMPLES_PER_BUCKET[0]),  // 4 samples - ultra fine
            Self::build_level(samples, SAMPLES_PER_BUCKET[1]),  // 8 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[2]),  // 16 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[3]),  // 32 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[4]),  // 64 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[5]),  // 128 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[6]),  // 256 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[7]),  // 512 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[8]),  // 1024 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[9]),  // 2048 samples
            Self::build_level(samples, SAMPLES_PER_BUCKET[10]), // 4096 samples - coarsest
        ];

        Self {
            levels,
            sample_rate,
            total_samples,
            duration_secs,
        }
    }

    /// Build one LOD level
    fn build_level(samples: &[f32], samples_per_bucket: usize) -> Vec<WaveformBucket> {
        if samples.is_empty() {
            return Vec::new();
        }

        let num_buckets = samples.len().div_ceil(samples_per_bucket);
        let mut buckets = Vec::with_capacity(num_buckets);

        for chunk in samples.chunks(samples_per_bucket) {
            buckets.push(WaveformBucket::from_samples(chunk));
        }

        buckets
    }

    /// Pixel-exact query: get aggregated data for each pixel column
    ///
    /// This is the key function for accurate waveform display.
    /// For each output pixel, we aggregate ALL buckets that fall within that pixel's time range.
    ///
    /// # Arguments
    /// * `start_frame` - Start frame in source audio
    /// * `end_frame` - End frame in source audio
    /// * `num_pixels` - Number of output pixels
    ///
    /// # Returns
    /// Vec of WaveformBucket, one per pixel, with correctly aggregated min/max/rms
    pub fn query_pixels(
        &self,
        start_frame: usize,
        end_frame: usize,
        num_pixels: usize,
    ) -> Vec<WaveformBucket> {
        if num_pixels == 0 || end_frame <= start_frame || self.total_samples == 0 {
            return Vec::new();
        }

        let frames_per_pixel = (end_frame - start_frame) as f64 / num_pixels as f64;

        // Select LOD level where bucket_frames <= frames_per_pixel
        // This ensures we never lose peaks (each pixel covers 1+ buckets)
        let level = self.select_level_for_query(frames_per_pixel);
        let bucket_samples = SAMPLES_PER_BUCKET[level];
        let buckets = &self.levels[level];

        let mut result = Vec::with_capacity(num_pixels);

        for px in 0..num_pixels {
            // Calculate exact frame range for this pixel
            let px_start_frame = start_frame + (px as f64 * frames_per_pixel) as usize;
            let px_end_frame = start_frame + ((px + 1) as f64 * frames_per_pixel) as usize;

            // Convert to bucket indices
            let bucket_start = px_start_frame / bucket_samples;
            let bucket_end = px_end_frame.div_ceil(bucket_samples); // Round up

            // Clamp to valid range
            let bucket_start = bucket_start.min(buckets.len());
            let bucket_end = bucket_end.min(buckets.len());

            if bucket_start >= bucket_end {
                result.push(WaveformBucket::default());
            } else {
                // Aggregate all buckets in range
                result.push(WaveformBucket::merge(&buckets[bucket_start..bucket_end]));
            }
        }

        result
    }

    /// Select appropriate LOD level for query
    ///
    /// Key rule from CUBASE_WAVEFORM_SPEC.md:
    /// bucket_samples <= frames_per_pixel (NEVER coarser!)
    ///
    /// We want the FINEST level that satisfies this constraint.
    /// Iterate from COARSEST to FINEST, return last valid level.
    fn select_level_for_query(&self, frames_per_pixel: f64) -> usize {
        // Find the finest (smallest bucket) level where bucket_samples <= frames_per_pixel
        // This preserves all transients - no peak is ever lost
        let mut best_level = 0; // Default to finest if nothing matches

        for (level, &bucket_samples) in SAMPLES_PER_BUCKET.iter().enumerate() {
            if (bucket_samples as f64) <= frames_per_pixel {
                // This level is valid (won't lose peaks)
                // Keep looking for finer levels that also satisfy constraint
                best_level = level;
            }
        }

        best_level
    }

    /// Get raw buckets at a specific level (for advanced use)
    pub fn get_level(&self, level: usize) -> &[WaveformBucket] {
        &self.levels[level.min(NUM_LOD_LEVELS - 1)]
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.total_samples == 0
    }

    /// Get bucket count at finest level
    pub fn len(&self) -> usize {
        self.levels[0].len()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO WAVEFORM DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Stereo waveform with separate L/R data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StereoWaveformData {
    pub left: WaveformData,
    pub right: WaveformData,
}

impl StereoWaveformData {
    /// Create empty stereo waveform
    pub fn empty(sample_rate: u32) -> Self {
        Self {
            left: WaveformData::empty(sample_rate),
            right: WaveformData::empty(sample_rate),
        }
    }

    /// Create from interleaved stereo samples [L0, R0, L1, R1, ...]
    pub fn from_interleaved(samples: &[f32], sample_rate: u32) -> Self {
        if samples.is_empty() {
            return Self::empty(sample_rate);
        }

        let frame_count = samples.len() / 2;
        let mut left = Vec::with_capacity(frame_count);
        let mut right = Vec::with_capacity(frame_count);

        for chunk in samples.chunks(2) {
            left.push(chunk[0]);
            right.push(chunk.get(1).copied().unwrap_or(chunk[0]));
        }

        Self {
            left: WaveformData::from_samples(&left, sample_rate),
            right: WaveformData::from_samples(&right, sample_rate),
        }
    }

    /// Create mono waveform (same data for both channels)
    pub fn from_mono(samples: &[f32], sample_rate: u32) -> Self {
        if samples.is_empty() {
            return Self::empty(sample_rate);
        }

        let data = WaveformData::from_samples(samples, sample_rate);
        Self {
            left: data.clone(),
            right: data,
        }
    }

    /// Pixel-exact query for both channels
    pub fn query_pixels(
        &self,
        start_frame: usize,
        end_frame: usize,
        num_pixels: usize,
    ) -> (Vec<WaveformBucket>, Vec<WaveformBucket>) {
        (
            self.left.query_pixels(start_frame, end_frame, num_pixels),
            self.right.query_pixels(start_frame, end_frame, num_pixels),
        )
    }

    /// Query combined (mono mix) for simple display
    pub fn query_pixels_combined(
        &self,
        start_frame: usize,
        end_frame: usize,
        num_pixels: usize,
    ) -> Vec<WaveformBucket> {
        let left = self.left.query_pixels(start_frame, end_frame, num_pixels);
        let right = self.right.query_pixels(start_frame, end_frame, num_pixels);

        left.iter()
            .zip(right.iter())
            .map(|(l, r)| WaveformBucket::new(
                l.min.min(r.min),
                l.max.max(r.max),
                (l.rms + r.rms) / 2.0, // Average RMS for combined
            ))
            .collect()
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> u32 {
        self.left.sample_rate
    }

    /// Get total samples
    pub fn total_samples(&self) -> usize {
        self.left.total_samples
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.left.is_empty()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// BACKWARD COMPATIBILITY - Old API wrappers
// ═══════════════════════════════════════════════════════════════════════════

/// Old WaveformPeaks type (backward compatibility)
pub type WaveformPeaks = WaveformData;

/// Old StereoWaveformPeaks type (backward compatibility)
pub type StereoWaveformPeaks = StereoWaveformData;

impl WaveformPeaks {
    /// Old API: get peaks for zoom level
    pub fn get_peaks_for_zoom(&self, pixels_per_second: f64) -> &[WaveformBucket] {
        let frames_per_pixel = self.sample_rate as f64 / pixels_per_second;
        let level = self.select_level_for_query(frames_per_pixel);
        &self.levels[level]
    }

    /// Old API: get peaks in time range
    pub fn get_peaks_in_range(
        &self,
        start_time: f64,
        end_time: f64,
        pixels_per_second: f64,
    ) -> Vec<WaveformBucket> {
        let start_frame = (start_time * self.sample_rate as f64) as usize;
        let end_frame = (end_time * self.sample_rate as f64) as usize;
        let duration = end_time - start_time;
        let num_pixels = (duration * pixels_per_second) as usize;

        self.query_pixels(start_frame, end_frame, num_pixels.max(1))
    }

    /// Old API: flat array output
    pub fn to_flat_array(&self, level: usize) -> Vec<f32> {
        let level = level.min(NUM_LOD_LEVELS - 1);
        let mut result = Vec::with_capacity(self.levels[level].len() * 2);

        for bucket in &self.levels[level] {
            result.push(bucket.min);
            result.push(bucket.max);
        }

        result
    }
}

impl StereoWaveformPeaks {
    /// Old API: get combined peaks for zoom
    pub fn get_combined_peaks_for_zoom(&self, pixels_per_second: f64) -> Vec<WaveformBucket> {
        let left = self.left.get_peaks_for_zoom(pixels_per_second);
        let right = self.right.get_peaks_for_zoom(pixels_per_second);

        left.iter()
            .zip(right.iter())
            .map(|(l, r)| WaveformBucket::new(
                l.min.min(r.min),
                l.max.max(r.max),
                (l.rms + r.rms) / 2.0,
            ))
            .collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVEFORM CACHE
// ═══════════════════════════════════════════════════════════════════════════

/// Cache for computed waveform data
pub struct WaveformCache {
    /// Internal cache storage
    pub cache: RwLock<HashMap<String, Arc<StereoWaveformData>>>,
}

impl WaveformCache {
    pub fn new() -> Self {
        Self {
            cache: RwLock::new(HashMap::new()),
        }
    }

    /// Get or compute waveform data for a file
    pub fn get_or_compute<F>(&self, key: &str, compute: F) -> Arc<StereoWaveformData>
    where
        F: FnOnce() -> StereoWaveformData,
    {
        // Check cache first
        if let Some(data) = self.cache.read().get(key) {
            return Arc::clone(data);
        }

        // Compute and cache
        let data = Arc::new(compute());
        self.cache.write().insert(key.to_string(), Arc::clone(&data));
        data
    }

    /// Get cached data without computing
    pub fn get(&self, key: &str) -> Option<Arc<StereoWaveformData>> {
        self.cache.read().get(key).cloned()
    }

    /// Insert pre-computed data
    pub fn insert(&self, key: &str, data: StereoWaveformData) {
        self.cache.write().insert(key.to_string(), Arc::new(data));
    }

    /// Remove from cache
    pub fn invalidate(&self, key: &str) {
        self.cache.write().remove(key);
    }

    /// Remove by ClipId
    pub fn remove(&self, clip_id: crate::track_manager::ClipId) {
        let key = format!("clip_{}", clip_id.0);
        self.cache.write().remove(&key);
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
            .map(|data| {
                // WaveformBucket is 12 bytes (3 x f32)
                let bucket_size = std::mem::size_of::<WaveformBucket>();
                let left_size: usize = data.left.levels.iter().map(|v| v.len() * bucket_size).sum();
                let right_size: usize = data.right.levels.iter().map(|v| v.len() * bucket_size).sum();
                left_size + right_size
            })
            .sum()
    }

    /// Get source path for clip (backward compat)
    pub fn get_source_path(&self, clip_id: crate::track_manager::ClipId) -> Option<String> {
        let cache = self.cache.read();
        for key in cache.keys() {
            if key.contains(&clip_id.0.to_string()) {
                return Some(key.clone());
            }
        }
        None
    }
}

impl Default for WaveformCache {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FFI QUERY RESULT - For sending to Flutter
// ═══════════════════════════════════════════════════════════════════════════

/// Waveform query result for FFI
/// Flat array format: [min0, max0, rms0, min1, max1, rms1, ...]
#[derive(Debug, Clone)]
pub struct WaveformQueryResult {
    /// Combined L+R data as flat array (min, max, rms per pixel)
    pub data: Vec<f32>,
    /// Number of pixels
    pub num_pixels: usize,
    /// Sample rate of source
    pub sample_rate: u32,
}

impl WaveformQueryResult {
    /// Create from stereo waveform query
    pub fn from_query(
        waveform: &StereoWaveformData,
        start_frame: usize,
        end_frame: usize,
        num_pixels: usize,
    ) -> Self {
        let buckets = waveform.query_pixels_combined(start_frame, end_frame, num_pixels);

        let mut data = Vec::with_capacity(buckets.len() * 3);
        for b in &buckets {
            data.push(b.min);
            data.push(b.max);
            data.push(b.rms);
        }

        Self {
            data,
            num_pixels: buckets.len(),
            sample_rate: waveform.sample_rate(),
        }
    }

    /// Get bucket at pixel index
    pub fn get_bucket(&self, pixel: usize) -> Option<WaveformBucket> {
        if pixel >= self.num_pixels {
            return None;
        }
        let i = pixel * 3;
        Some(WaveformBucket::new(
            self.data[i],
            self.data[i + 1],
            self.data[i + 2],
        ))
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
    fn test_bucket_from_samples() {
        let samples = vec![0.0, 0.5, 1.0, -0.5, -1.0, 0.3];
        let bucket = WaveformBucket::from_samples(&samples);

        assert_eq!(bucket.min, -1.0);
        assert_eq!(bucket.max, 1.0);
        assert!(bucket.rms > 0.0 && bucket.rms < 1.0);
    }

    #[test]
    fn test_bucket_merge() {
        let b1 = WaveformBucket::new(-0.5, 0.8, 0.3);
        let b2 = WaveformBucket::new(-0.9, 0.6, 0.4);
        let merged = WaveformBucket::merge(&[b1, b2]);

        assert_eq!(merged.min, -0.9);
        assert_eq!(merged.max, 0.8);
        // RMS should be combined
        assert!(merged.rms > 0.3 && merged.rms < 0.5);
    }

    #[test]
    fn test_waveform_data_generation() {
        let samples = generate_sine_wave(440.0, 48000, 1.0);
        let data = WaveformData::from_samples(&samples, 48000);

        assert!(!data.is_empty());
        assert_eq!(data.sample_rate, 48000);
        assert!((data.duration_secs - 1.0).abs() < 0.001);

        // Finest level should have most buckets
        assert!(data.levels[0].len() > data.levels[7].len());
    }

    #[test]
    fn test_pixel_exact_query() {
        let samples = generate_sine_wave(10.0, 48000, 1.0);
        let data = WaveformData::from_samples(&samples, 48000);

        // Query 100 pixels for entire waveform
        let result = data.query_pixels(0, 48000, 100);

        assert_eq!(result.len(), 100);

        // Should capture peaks of sine wave
        let max_peak = result.iter().map(|b| b.max).fold(f32::MIN, f32::max);
        let min_peak = result.iter().map(|b| b.min).fold(f32::MAX, f32::min);

        assert!(max_peak > 0.9, "Should capture positive peak");
        assert!(min_peak < -0.9, "Should capture negative peak");
    }

    #[test]
    fn test_stereo_waveform() {
        let left: Vec<f32> = (0..1000).map(|i| (i as f32 / 100.0).sin()).collect();
        let right: Vec<f32> = (0..1000).map(|i| (i as f32 / 100.0).cos()).collect();

        let stereo: Vec<f32> = left.iter().zip(right.iter())
            .flat_map(|(&l, &r)| [l, r])
            .collect();

        let data = StereoWaveformData::from_interleaved(&stereo, 48000);

        assert!(!data.is_empty());
        assert_eq!(data.total_samples(), 1000);
    }

    #[test]
    fn test_rms_body_visible() {
        // Generate audio with quiet section and loud section
        let mut samples = Vec::with_capacity(10000);

        // Quiet section (low RMS)
        for i in 0..5000 {
            samples.push((i as f32 / 500.0).sin() * 0.1);
        }
        // Loud section (high RMS)
        for i in 0..5000 {
            samples.push((i as f32 / 500.0).sin() * 0.9);
        }

        let data = WaveformData::from_samples(&samples, 48000);
        let result = data.query_pixels(0, 10000, 10);

        // First half should have lower RMS than second half
        let avg_rms_first = result[0..5].iter().map(|b| b.rms).sum::<f32>() / 5.0;
        let avg_rms_second = result[5..10].iter().map(|b| b.rms).sum::<f32>() / 5.0;

        assert!(avg_rms_second > avg_rms_first * 3.0,
            "Loud section should have much higher RMS");
    }

    #[test]
    fn test_backward_compat() {
        let samples = generate_sine_wave(440.0, 48000, 0.1);
        let peaks = WaveformPeaks::from_samples(&samples, 48000);

        // Old API should still work
        let _ = peaks.get_peaks_for_zoom(1000.0);
        let _ = peaks.get_peaks_in_range(0.0, 0.05, 1000.0);
        let flat = peaks.to_flat_array(0);
        assert!(!flat.is_empty());
    }
}
