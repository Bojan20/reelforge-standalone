//! Stem types and output structures

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Available stem types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StemType {
    /// Drum kit (kick, snare, hats, toms, cymbals)
    Drums,
    /// Bass instruments (bass guitar, synth bass)
    Bass,
    /// Vocal content (lead, backing, harmonies)
    Vocals,
    /// Everything else (guitars, synths, strings, etc.)
    Other,
    /// Piano and keyboard instruments (htdemucs_6s only)
    Piano,
    /// Guitar (electric and acoustic) (htdemucs_6s only)
    Guitar,
    /// Full mix (original)
    Mix,
}

impl StemType {
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            StemType::Drums => "Drums",
            StemType::Bass => "Bass",
            StemType::Vocals => "Vocals",
            StemType::Other => "Other",
            StemType::Piano => "Piano",
            StemType::Guitar => "Guitar",
            StemType::Mix => "Mix",
        }
    }

    /// Get short name for file naming
    pub fn short_name(&self) -> &'static str {
        match self {
            StemType::Drums => "drums",
            StemType::Bass => "bass",
            StemType::Vocals => "vocals",
            StemType::Other => "other",
            StemType::Piano => "piano",
            StemType::Guitar => "guitar",
            StemType::Mix => "mix",
        }
    }

    /// Get icon emoji
    pub fn icon(&self) -> &'static str {
        match self {
            StemType::Drums => "🥁",
            StemType::Bass => "🎸",
            StemType::Vocals => "🎤",
            StemType::Other => "🎹",
            StemType::Piano => "🎹",
            StemType::Guitar => "🎸",
            StemType::Mix => "🎵",
        }
    }

    /// Get default color (RGB)
    pub fn color(&self) -> (u8, u8, u8) {
        match self {
            StemType::Drums => (255, 100, 100),  // Red
            StemType::Bass => (100, 100, 255),   // Blue
            StemType::Vocals => (100, 255, 100), // Green
            StemType::Other => (255, 200, 100),  // Orange
            StemType::Piano => (200, 100, 255),  // Purple
            StemType::Guitar => (255, 255, 100), // Yellow
            StemType::Mix => (200, 200, 200),    // Gray
        }
    }

    /// Standard 4-stem set
    pub fn standard_4() -> Vec<StemType> {
        vec![
            StemType::Drums,
            StemType::Bass,
            StemType::Vocals,
            StemType::Other,
        ]
    }

    /// Extended 6-stem set
    pub fn extended_6() -> Vec<StemType> {
        vec![
            StemType::Drums,
            StemType::Bass,
            StemType::Vocals,
            StemType::Other,
            StemType::Piano,
            StemType::Guitar,
        ]
    }
}

/// Single stem output
#[derive(Debug, Clone)]
pub struct StemOutput {
    /// Stem type
    pub stem_type: StemType,

    /// Audio data (interleaved stereo or mono)
    pub audio: Vec<f32>,

    /// Number of channels
    pub channels: usize,

    /// Sample rate
    pub sample_rate: u32,

    /// Quality metrics
    pub metrics: StemMetrics,
}

impl StemOutput {
    /// Create new stem output
    pub fn new(stem_type: StemType, audio: Vec<f32>, channels: usize, sample_rate: u32) -> Self {
        Self {
            stem_type,
            audio,
            channels,
            sample_rate,
            metrics: StemMetrics::default(),
        }
    }

    /// Duration in seconds
    pub fn duration(&self) -> f64 {
        self.audio.len() as f64 / (self.channels as f64 * self.sample_rate as f64)
    }

    /// Get left channel (deinterleaved)
    pub fn left(&self) -> Vec<f32> {
        if self.channels == 1 {
            return self.audio.clone();
        }
        self.audio.iter().step_by(2).copied().collect()
    }

    /// Get right channel (deinterleaved)
    pub fn right(&self) -> Vec<f32> {
        if self.channels == 1 {
            return self.audio.clone();
        }
        self.audio.iter().skip(1).step_by(2).copied().collect()
    }

    /// Convert to mono (average channels)
    pub fn to_mono(&self) -> Vec<f32> {
        if self.channels == 1 {
            return self.audio.clone();
        }

        let samples = self.audio.len() / self.channels;
        let mut mono = Vec::with_capacity(samples);

        for i in 0..samples {
            let mut sum = 0.0;
            for ch in 0..self.channels {
                sum += self.audio[i * self.channels + ch];
            }
            mono.push(sum / self.channels as f32);
        }

        mono
    }

    /// Compute RMS level
    pub fn rms(&self) -> f32 {
        if self.audio.is_empty() {
            return 0.0;
        }

        let sum_sq: f32 = self.audio.iter().map(|&s| s * s).sum();
        (sum_sq / self.audio.len() as f32).sqrt()
    }

    /// Compute peak level
    pub fn peak(&self) -> f32 {
        self.audio.iter().map(|&s| s.abs()).fold(0.0f32, f32::max)
    }

    /// Normalize to target peak
    pub fn normalize(&mut self, target_peak: f32) {
        let current_peak = self.peak();
        if current_peak > 1e-10 {
            let gain = target_peak / current_peak;
            for sample in &mut self.audio {
                *sample *= gain;
            }
        }
    }
}

/// Quality metrics for a stem
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StemMetrics {
    /// Signal-to-Distortion Ratio (dB)
    pub sdr: Option<f32>,

    /// Signal-to-Interference Ratio (dB)
    pub sir: Option<f32>,

    /// Signal-to-Artifacts Ratio (dB)
    pub sar: Option<f32>,

    /// Confidence score (0.0 - 1.0)
    pub confidence: f32,

    /// Processing time (ms)
    pub processing_time_ms: u64,
}

/// Collection of separated stems
#[derive(Debug, Clone)]
pub struct StemCollection {
    /// All stems
    stems: HashMap<StemType, StemOutput>,

    /// Original sample rate
    pub sample_rate: u32,

    /// Total duration
    pub duration: f64,

    /// Model used
    pub model_name: String,

    /// Processing stats
    pub stats: SeparationStats,
}

impl StemCollection {
    /// Create new stem collection
    pub fn new(sample_rate: u32, model_name: String) -> Self {
        Self {
            stems: HashMap::new(),
            sample_rate,
            duration: 0.0,
            model_name,
            stats: SeparationStats::default(),
        }
    }

    /// Add a stem
    pub fn add(&mut self, stem: StemOutput) {
        if self.duration == 0.0 {
            self.duration = stem.duration();
        }
        self.stems.insert(stem.stem_type, stem);
    }

    /// Get a stem by type
    pub fn get(&self, stem_type: &StemType) -> Option<&StemOutput> {
        self.stems.get(stem_type)
    }

    /// Get mutable stem
    pub fn get_mut(&mut self, stem_type: &StemType) -> Option<&mut StemOutput> {
        self.stems.get_mut(stem_type)
    }

    /// Get all stems
    pub fn all(&self) -> &HashMap<StemType, StemOutput> {
        &self.stems
    }

    /// Get stem types present
    pub fn stem_types(&self) -> Vec<StemType> {
        self.stems.keys().copied().collect()
    }

    /// Number of stems
    pub fn len(&self) -> usize {
        self.stems.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.stems.is_empty()
    }

    /// Remix stems with custom gains
    pub fn remix(&self, gains: &HashMap<StemType, f32>) -> Vec<f32> {
        // Find a reference stem for size
        let reference = match self.stems.values().next() {
            Some(stem) => stem,
            None => return Vec::new(),
        };

        let len = reference.audio.len();
        let mut output = vec![0.0f32; len];

        for (stem_type, stem) in &self.stems {
            let gain = gains.get(stem_type).copied().unwrap_or(1.0);

            for (i, &sample) in stem.audio.iter().enumerate() {
                if i < output.len() {
                    output[i] += sample * gain;
                }
            }
        }

        output
    }

    /// Get karaoke mix (everything except vocals)
    pub fn karaoke(&self) -> Vec<f32> {
        let mut gains = HashMap::new();
        for stem_type in self.stems.keys() {
            let gain = if *stem_type == StemType::Vocals {
                0.0
            } else {
                1.0
            };
            gains.insert(*stem_type, gain);
        }
        self.remix(&gains)
    }

    /// Get instrumental mix (everything except vocals)
    pub fn instrumental(&self) -> Vec<f32> {
        self.karaoke()
    }

    /// Get acapella (vocals only)
    pub fn acapella(&self) -> Vec<f32> {
        let mut gains = HashMap::new();
        for stem_type in self.stems.keys() {
            let gain = if *stem_type == StemType::Vocals {
                1.0
            } else {
                0.0
            };
            gains.insert(*stem_type, gain);
        }
        self.remix(&gains)
    }
}

/// Separation statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SeparationStats {
    /// Total processing time (ms)
    pub total_time_ms: u64,

    /// GPU time (ms), if used
    pub gpu_time_ms: Option<u64>,

    /// Number of segments processed
    pub segments_processed: usize,

    /// Peak memory usage (bytes)
    pub peak_memory: Option<usize>,

    /// Real-time factor (1.0 = real-time, 10.0 = 10x faster)
    pub rtf: f32,

    /// GPU utilized
    pub gpu_utilized: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stem_type() {
        let stems = StemType::standard_4();
        assert_eq!(stems.len(), 4);

        let stems = StemType::extended_6();
        assert_eq!(stems.len(), 6);
    }

    #[test]
    fn test_stem_output() {
        let audio = vec![0.5f32; 1000];
        let stem = StemOutput::new(StemType::Vocals, audio, 1, 44100);

        assert_eq!(stem.stem_type, StemType::Vocals);
        assert!(stem.peak() <= 0.5);
        assert!(stem.rms() > 0.0);
    }

    #[test]
    fn test_stem_collection_remix() {
        let mut collection = StemCollection::new(44100, "test".into());

        collection.add(StemOutput::new(StemType::Vocals, vec![1.0; 100], 1, 44100));
        collection.add(StemOutput::new(StemType::Drums, vec![0.5; 100], 1, 44100));

        let mut gains = HashMap::new();
        gains.insert(StemType::Vocals, 0.5);
        gains.insert(StemType::Drums, 1.0);

        let remixed = collection.remix(&gains);
        assert_eq!(remixed.len(), 100);

        // First sample should be 1.0*0.5 + 0.5*1.0 = 1.0
        assert!((remixed[0] - 1.0).abs() < 0.001);
    }
}
