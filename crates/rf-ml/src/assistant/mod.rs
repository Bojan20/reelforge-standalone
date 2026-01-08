//! Intelligent Audio Assistant
//!
//! AI-powered audio analysis and suggestions:
//! - Genre/mood classification
//! - Mix analysis (balance, dynamics, frequency)
//! - Intelligent suggestions for processing
//! - Reference track comparison
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_ml::assistant::{AudioAssistant, AnalysisResult};
//!
//! let mut assistant = AudioAssistant::new("models/audio_assistant.onnx")?;
//!
//! let analysis = assistant.analyze(&audio, channels, sample_rate)?;
//!
//! println!("Genre: {:?}", analysis.genre);
//! for suggestion in &analysis.suggestions {
//!     println!("Suggestion: {}", suggestion.description);
//! }
//! ```

mod analyzer;
mod classifier;
mod config;
mod suggestions;

pub use analyzer::AudioAnalyzer;
pub use classifier::{Genre, GenreClassifier, Mood};
pub use config::AssistantConfig;
pub use suggestions::{Suggestion, SuggestionPriority, SuggestionType};

use crate::error::MlResult;

/// Complete audio analysis result
#[derive(Debug, Clone)]
pub struct AnalysisResult {
    /// Detected genre(s) with confidence
    pub genres: Vec<(Genre, f32)>,

    /// Detected mood(s) with confidence
    pub moods: Vec<(Mood, f32)>,

    /// Tempo estimate (BPM)
    pub tempo_bpm: Option<f32>,

    /// Key detection
    pub key: Option<MusicKey>,

    /// Loudness analysis
    pub loudness: LoudnessAnalysis,

    /// Spectral analysis
    pub spectral: SpectralAnalysis,

    /// Dynamic range analysis
    pub dynamics: DynamicsAnalysis,

    /// Stereo image analysis
    pub stereo: StereoAnalysis,

    /// AI-generated suggestions
    pub suggestions: Vec<Suggestion>,

    /// Overall quality score (0.0 - 1.0)
    pub quality_score: f32,
}

/// Musical key
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MusicKey {
    /// Root note (0-11, C=0)
    pub root: u8,
    /// Major or minor
    pub is_minor: bool,
    /// Confidence (0.0 - 1.0)
    pub confidence: f32,
}

impl MusicKey {
    /// Get key name (e.g., "C major", "A minor")
    pub fn name(&self) -> String {
        let note_names = [
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
        ];
        let mode = if self.is_minor { "minor" } else { "major" };
        format!("{} {}", note_names[self.root as usize % 12], mode)
    }

    /// Get Camelot notation
    pub fn camelot(&self) -> String {
        let camelot_major = [
            "8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "4B", "11B", "6B", "1B",
        ];
        let camelot_minor = [
            "5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A",
        ];

        let table = if self.is_minor {
            &camelot_minor
        } else {
            &camelot_major
        };
        table[self.root as usize % 12].to_string()
    }
}

/// Loudness analysis
#[derive(Debug, Clone, Default)]
pub struct LoudnessAnalysis {
    /// Integrated loudness (LUFS)
    pub integrated_lufs: f32,
    /// Short-term loudness (LUFS)
    pub short_term_lufs: f32,
    /// Momentary loudness (LUFS)
    pub momentary_lufs: f32,
    /// Loudness range (LU)
    pub loudness_range: f32,
    /// True peak (dBTP)
    pub true_peak_db: f32,
    /// Target deviation (how far from target)
    pub target_deviation: f32,
}

/// Spectral analysis
#[derive(Debug, Clone, Default)]
pub struct SpectralAnalysis {
    /// Spectral centroid (brightness indicator)
    pub centroid_hz: f32,
    /// Spectral spread
    pub spread_hz: f32,
    /// Spectral flatness (0 = tonal, 1 = noise)
    pub flatness: f32,
    /// Spectral rolloff (95% energy point)
    pub rolloff_hz: f32,
    /// Low frequency energy ratio (< 250Hz)
    pub low_ratio: f32,
    /// Mid frequency energy ratio (250Hz - 4kHz)
    pub mid_ratio: f32,
    /// High frequency energy ratio (> 4kHz)
    pub high_ratio: f32,
    /// Perceived brightness (-1 = dark, 0 = neutral, 1 = bright)
    pub brightness: f32,
}

/// Dynamics analysis
#[derive(Debug, Clone, Default)]
pub struct DynamicsAnalysis {
    /// Crest factor (peak/RMS ratio in dB)
    pub crest_factor_db: f32,
    /// Dynamic range (difference between loud and quiet)
    pub dynamic_range_db: f32,
    /// RMS level
    pub rms_db: f32,
    /// Peak level
    pub peak_db: f32,
    /// Compression estimate (how compressed)
    pub compression_estimate: f32,
    /// Transient sharpness (0 = soft, 1 = sharp)
    pub transient_sharpness: f32,
}

/// Stereo analysis
#[derive(Debug, Clone, Default)]
pub struct StereoAnalysis {
    /// Stereo width (0 = mono, 1 = wide)
    pub width: f32,
    /// Balance (-1 = left, 0 = center, 1 = right)
    pub balance: f32,
    /// Correlation (-1 = out of phase, 1 = mono)
    pub correlation: f32,
    /// Mid/Side ratio (0 = all mid, 1 = all side)
    pub mid_side_ratio: f32,
    /// Phase issues detected
    pub phase_issues: bool,
}

/// Common trait for audio assistants
pub trait AudioAssistantTrait: Send + Sync {
    /// Analyze audio and get suggestions
    fn analyze(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<AnalysisResult>;

    /// Classify genre only
    fn classify_genre(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<Vec<(Genre, f32)>>;

    /// Get processing suggestions
    fn suggest(
        &mut self,
        audio: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<Vec<Suggestion>>;

    /// Compare with reference track
    fn compare_with_reference(
        &mut self,
        audio: &[f32],
        reference: &[f32],
        channels: usize,
        sample_rate: u32,
    ) -> MlResult<ComparisonResult>;

    /// Reset state
    fn reset(&mut self);
}

/// Reference comparison result
#[derive(Debug, Clone)]
pub struct ComparisonResult {
    /// Overall similarity (0.0 - 1.0)
    pub similarity: f32,

    /// Loudness difference (dB)
    pub loudness_diff_db: f32,

    /// Spectral similarity (0.0 - 1.0)
    pub spectral_similarity: f32,

    /// Dynamic similarity (0.0 - 1.0)
    pub dynamic_similarity: f32,

    /// Stereo similarity (0.0 - 1.0)
    pub stereo_similarity: f32,

    /// Suggestions to match reference
    pub suggestions: Vec<Suggestion>,
}
