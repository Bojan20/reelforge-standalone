//! Elastic Audio (Time Stretching & Warping)
//!
//! Non-destructive time-stretching with per-event control:
//! - Warp markers for precise control
//! - Multiple algorithms (Rhythmic, Monophonic, Polyphonic)
//! - Phase-coherent processing
//! - Real-time preview

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Warp marker defining a time stretch point
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WarpMarker {
    /// Position in source audio (samples)
    pub source_position: u64,
    /// Target position in output (samples)
    pub target_position: u64,
    /// Marker is locked (won't move with tempo changes)
    pub locked: bool,
    /// User-created vs auto-detected
    pub user_created: bool,
    /// Associated transient (if any)
    pub transient_strength: Option<f64>,
}

impl WarpMarker {
    /// Create a new warp marker
    pub fn new(source: u64, target: u64) -> Self {
        Self {
            source_position: source,
            target_position: target,
            locked: false,
            user_created: true,
            transient_strength: None,
        }
    }

    /// Calculate stretch ratio at this marker
    pub fn stretch_ratio(&self) -> f64 {
        if self.source_position == 0 {
            1.0
        } else {
            self.target_position as f64 / self.source_position as f64
        }
    }
}

/// Time stretching algorithm
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum StretchAlgorithm {
    /// Best for percussive/rhythmic content
    Rhythmic,
    /// Best for single-note instruments (vocals, bass, flute)
    Monophonic,
    /// Best for complex polyphonic material
    #[default]
    Polyphonic,
    /// Preserve formants (for voice)
    FormantPreserving,
    /// No time stretch, just reposition
    Slice,
}

impl StretchAlgorithm {
    /// Get description
    pub fn description(&self) -> &'static str {
        match self {
            Self::Rhythmic => "Drums, percussion, rhythmic material",
            Self::Monophonic => "Vocals, bass, single-note instruments",
            Self::Polyphonic => "Piano, guitar, mixed content",
            Self::FormantPreserving => "Voice with natural timbre",
            Self::Slice => "Slice and reposition without stretching",
        }
    }

    /// Get typical window size for this algorithm
    pub fn window_size(&self) -> usize {
        match self {
            Self::Rhythmic => 256,
            Self::Monophonic => 1024,
            Self::Polyphonic => 2048,
            Self::FormantPreserving => 2048,
            Self::Slice => 0,
        }
    }

    /// Get overlap factor
    pub fn overlap(&self) -> usize {
        match self {
            Self::Rhythmic => 2,
            Self::Monophonic => 4,
            Self::Polyphonic => 4,
            Self::FormantPreserving => 4,
            Self::Slice => 1,
        }
    }
}

/// Elastic audio configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ElasticConfig {
    /// Stretching algorithm
    pub algorithm: StretchAlgorithm,
    /// Preserve transients
    pub preserve_transients: bool,
    /// Pitch correction strength (0.0-1.0)
    pub pitch_correction: f64,
    /// Formant preservation amount (0.0-1.0)
    pub formant_preservation: f64,
    /// Anti-aliasing quality (1-4)
    pub quality: u8,
}

impl Default for ElasticConfig {
    fn default() -> Self {
        Self {
            algorithm: StretchAlgorithm::Polyphonic,
            preserve_transients: true,
            pitch_correction: 0.0,
            formant_preservation: 0.0,
            quality: 2,
        }
    }
}

/// Elastic audio processor
pub struct ElasticAudio {
    /// Configuration
    config: ElasticConfig,
    /// Warp markers (source position -> marker)
    markers: BTreeMap<u64, WarpMarker>,
    /// Sample rate
    sample_rate: f64,
    /// Original audio length
    source_length: u64,
    /// Target audio length
    target_length: u64,
    /// Analysis window
    window: Vec<f64>,
    /// Overlap-add buffer
    overlap_buffer: Vec<f64>,
    /// Phase accumulator for PSOLA
    phase_acc: Vec<f64>,
}

impl ElasticAudio {
    /// Create new elastic audio processor
    pub fn new(sample_rate: f64, source_length: u64) -> Self {
        let window_size = StretchAlgorithm::default().window_size();

        Self {
            config: ElasticConfig::default(),
            markers: BTreeMap::new(),
            sample_rate,
            source_length,
            target_length: source_length,
            window: Self::create_window(window_size),
            overlap_buffer: vec![0.0; window_size],
            phase_acc: vec![0.0; window_size / 2 + 1],
        }
    }

    /// Create Hann window
    fn create_window(size: usize) -> Vec<f64> {
        (0..size)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f64::consts::PI * i as f64 / (size - 1) as f64).cos())
            })
            .collect()
    }

    /// Set algorithm
    pub fn set_algorithm(&mut self, algorithm: StretchAlgorithm) {
        self.config.algorithm = algorithm;
        let window_size = algorithm.window_size();
        self.window = Self::create_window(window_size);
        self.overlap_buffer.resize(window_size, 0.0);
        self.phase_acc.resize(window_size / 2 + 1, 0.0);
    }

    /// Add a warp marker
    pub fn add_marker(&mut self, source: u64, target: u64) {
        let marker = WarpMarker::new(source, target);
        self.markers.insert(source, marker);
        self.recalculate_target_length();
    }

    /// Remove a warp marker
    pub fn remove_marker(&mut self, source: u64) {
        self.markers.remove(&source);
        self.recalculate_target_length();
    }

    /// Move a marker's target position
    pub fn move_marker(&mut self, source: u64, new_target: u64) {
        if let Some(marker) = self.markers.get_mut(&source) {
            marker.target_position = new_target;
            self.recalculate_target_length();
        }
    }

    /// Add markers from transient detection
    pub fn add_markers_from_transients(&mut self, transients: &[(u64, f64)]) {
        for &(position, strength) in transients {
            let mut marker = WarpMarker::new(position, position); // Initially no stretch
            marker.user_created = false;
            marker.transient_strength = Some(strength);
            self.markers.insert(position, marker);
        }
    }

    /// Recalculate target length based on markers
    fn recalculate_target_length(&mut self) {
        if let Some((_, last_marker)) = self.markers.iter().last() {
            // Estimate based on last marker's stretch ratio
            let ratio = last_marker.stretch_ratio();
            self.target_length = (self.source_length as f64 * ratio) as u64;
        }
    }

    /// Set global stretch ratio
    pub fn set_stretch_ratio(&mut self, ratio: f64) {
        self.target_length = (self.source_length as f64 * ratio) as u64;

        // Adjust all markers proportionally
        for marker in self.markers.values_mut() {
            marker.target_position = (marker.source_position as f64 * ratio) as u64;
        }
    }

    /// Get stretch ratio at a given source position
    pub fn ratio_at(&self, source_position: u64) -> f64 {
        if self.markers.is_empty() {
            return self.target_length as f64 / self.source_length as f64;
        }

        // Find surrounding markers
        let before = self.markers.range(..=source_position).last();
        let after = self.markers.range(source_position..).next();

        match (before, after) {
            (Some((_, m1)), Some((_, m2))) => {
                // Interpolate between markers
                let source_span = m2.source_position - m1.source_position;
                let target_span = m2.target_position - m1.target_position;
                if source_span > 0 {
                    target_span as f64 / source_span as f64
                } else {
                    1.0
                }
            }
            (Some((_, m)), None) | (None, Some((_, m))) => m.stretch_ratio(),
            (None, None) => 1.0,
        }
    }

    /// Map source position to target position
    pub fn map_position(&self, source_position: u64) -> u64 {
        if self.markers.is_empty() {
            let ratio = self.target_length as f64 / self.source_length as f64;
            return (source_position as f64 * ratio) as u64;
        }

        // Find surrounding markers
        let before = self.markers.range(..=source_position).last();
        let after = self.markers.range((source_position + 1)..).next();

        match (before, after) {
            (Some((_, m1)), Some((_, m2))) => {
                // Linear interpolation between markers
                let source_span = m2.source_position - m1.source_position;
                if source_span == 0 {
                    return m1.target_position;
                }
                let t = (source_position - m1.source_position) as f64 / source_span as f64;
                let target_span = m2.target_position as f64 - m1.target_position as f64;
                (m1.target_position as f64 + t * target_span) as u64
            }
            (Some((_, m)), None) => {
                // Extrapolate from last marker
                let ratio = m.stretch_ratio();
                let offset = source_position - m.source_position;
                m.target_position + (offset as f64 * ratio) as u64
            }
            (None, Some((_, m))) => {
                // Extrapolate to first marker
                let ratio = m.stretch_ratio();
                (source_position as f64 * ratio) as u64
            }
            (None, None) => source_position,
        }
    }

    /// Process audio with time stretching (simplified OLA)
    /// Returns stretched audio buffer
    pub fn process(&self, source: &[f64]) -> Vec<f64> {
        let target_len = self.target_length as usize;
        let source_len = source.len();

        if source_len == 0 || target_len == 0 {
            return vec![0.0; target_len];
        }

        match self.config.algorithm {
            StretchAlgorithm::Slice => self.process_slice(source, target_len),
            _ => self.process_ola(source, target_len),
        }
    }

    /// Simple slice-based processing (no stretching, just repositioning)
    fn process_slice(&self, source: &[f64], target_len: usize) -> Vec<f64> {
        let mut output = vec![0.0; target_len];

        // Copy slices based on markers
        let mut prev_source = 0u64;
        let mut prev_target = 0u64;

        for marker in self.markers.values() {
            let source_start = prev_source as usize;
            let source_end = (marker.source_position as usize).min(source.len());
            let target_start = prev_target as usize;

            let len = source_end - source_start;
            let target_end = (target_start + len).min(target_len);

            if target_start < target_len && source_start < source.len() {
                let copy_len = (target_end - target_start).min(source_end - source_start);
                output[target_start..target_start + copy_len]
                    .copy_from_slice(&source[source_start..source_start + copy_len]);
            }

            prev_source = marker.source_position;
            prev_target = marker.target_position;
        }

        // Copy remaining
        if (prev_source as usize) < source.len() && (prev_target as usize) < target_len {
            let remaining = source.len() - prev_source as usize;
            let space = target_len - prev_target as usize;
            let copy_len = remaining.min(space);
            output[prev_target as usize..prev_target as usize + copy_len]
                .copy_from_slice(&source[prev_source as usize..prev_source as usize + copy_len]);
        }

        output
    }

    /// Overlap-add time stretching
    fn process_ola(&self, source: &[f64], target_len: usize) -> Vec<f64> {
        let mut output = vec![0.0; target_len];
        let window_size = self.window.len();
        let hop_out = window_size / self.config.algorithm.overlap();

        if window_size == 0 || hop_out == 0 {
            return output;
        }

        let mut target_pos = 0usize;

        while target_pos + window_size <= target_len {
            // Find corresponding source position
            let source_pos_f = self.reverse_map_position(target_pos as u64) as f64;
            let source_pos = source_pos_f as usize;

            // Extract windowed grain from source
            if source_pos + window_size <= source.len() {
                for i in 0..window_size {
                    let sample = source[source_pos + i] * self.window[i];
                    output[target_pos + i] += sample;
                }
            }

            target_pos += hop_out;
        }

        // Normalize by window overlap
        let overlap = self.config.algorithm.overlap() as f64;
        for sample in &mut output {
            *sample /= overlap * 0.5;
        }

        output
    }

    /// Reverse map: target position to source position
    fn reverse_map_position(&self, target_position: u64) -> u64 {
        if self.markers.is_empty() {
            let ratio = self.source_length as f64 / self.target_length as f64;
            return (target_position as f64 * ratio) as u64;
        }

        // Binary search through markers based on target position
        let markers: Vec<&WarpMarker> = self.markers.values().collect();

        // Find surrounding markers by target position
        let mut before_idx = None;
        let mut after_idx = None;

        for (i, m) in markers.iter().enumerate() {
            if m.target_position <= target_position {
                before_idx = Some(i);
            } else if after_idx.is_none() {
                after_idx = Some(i);
                break;
            }
        }

        match (before_idx, after_idx) {
            (Some(i), Some(j)) => {
                let m1 = markers[i];
                let m2 = markers[j];
                let target_span = m2.target_position - m1.target_position;
                if target_span == 0 {
                    return m1.source_position;
                }
                let t = (target_position - m1.target_position) as f64 / target_span as f64;
                let source_span = m2.source_position as f64 - m1.source_position as f64;
                (m1.source_position as f64 + t * source_span) as u64
            }
            (Some(i), None) => {
                let m = markers[i];
                let inv_ratio = 1.0 / m.stretch_ratio();
                let offset = target_position - m.target_position;
                m.source_position + (offset as f64 * inv_ratio) as u64
            }
            (None, Some(j)) => {
                let m = markers[j];
                let inv_ratio = 1.0 / m.stretch_ratio();
                (target_position as f64 * inv_ratio) as u64
            }
            (None, None) => target_position,
        }
    }

    /// Get all markers
    pub fn markers(&self) -> impl Iterator<Item = &WarpMarker> {
        self.markers.values()
    }

    /// Get target length
    pub fn target_length(&self) -> u64 {
        self.target_length
    }

    /// Get source length
    pub fn source_length(&self) -> u64 {
        self.source_length
    }

    /// Get current stretch ratio
    pub fn stretch_ratio(&self) -> f64 {
        self.target_length as f64 / self.source_length as f64
    }

    /// Reset to original timing
    pub fn reset(&mut self) {
        self.markers.clear();
        self.target_length = self.source_length;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stretch_ratio_calculation() {
        let marker = WarpMarker::new(1000, 2000);
        assert!((marker.stretch_ratio() - 2.0).abs() < 0.001);
    }

    #[test]
    fn test_position_mapping() {
        let mut elastic = ElasticAudio::new(48000.0, 10000);

        // Add marker: source 5000 -> target 10000 (2x stretch)
        elastic.add_marker(5000, 10000);

        // Position at 2500 should map to ~5000
        let mapped = elastic.map_position(2500);
        assert!((mapped as f64 - 5000.0).abs() < 100.0);
    }

    #[test]
    fn test_global_stretch() {
        let mut elastic = ElasticAudio::new(48000.0, 10000);
        elastic.set_stretch_ratio(2.0);

        assert_eq!(elastic.target_length(), 20000);
    }

    #[test]
    fn test_slice_processing() {
        let mut elastic = ElasticAudio::new(48000.0, 100);
        elastic.set_algorithm(StretchAlgorithm::Slice);
        elastic.target_length = 100; // No stretch

        let source: Vec<f64> = (0..100).map(|i| i as f64 / 100.0).collect();
        let output = elastic.process(&source);

        assert_eq!(output.len(), 100);
        // First sample should be preserved
        assert!((output[0] - source[0]).abs() < 0.001);
    }

    #[test]
    fn test_algorithm_settings() {
        assert_eq!(StretchAlgorithm::Rhythmic.window_size(), 256);
        assert_eq!(StretchAlgorithm::Polyphonic.window_size(), 2048);
        assert_eq!(StretchAlgorithm::Monophonic.overlap(), 4);
    }
}
