//! AI Mastering Assistant
//!
//! Intelligent mastering recommendations and auto-processing:
//! - Reference track matching
//! - Loudness targeting (LUFS)
//! - Dynamic range optimization
//! - Frequency balance analysis
//! - Stereo width suggestions
//! - Genre-aware processing
//!
//! Uses ML to analyze reference tracks and suggest processing parameters.

use serde::{Deserialize, Serialize};

/// Target loudness standard
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[derive(Default)]
pub enum LoudnessTarget {
    /// Streaming platforms (-14 LUFS)
    #[default]
    Streaming,
    /// CD (-9 to -12 LUFS)
    CD,
    /// Vinyl (-12 to -18 LUFS)
    Vinyl,
    /// Broadcast (-23 to -24 LUFS)
    Broadcast,
    /// Club/DJ (-6 to -9 LUFS)
    Club,
    /// Podcast (-16 to -19 LUFS)
    Podcast,
    /// Custom target
    Custom(i8),
}

impl LoudnessTarget {
    /// Get target LUFS value
    pub fn lufs(&self) -> f64 {
        match self {
            Self::Streaming => -14.0,
            Self::CD => -10.0,
            Self::Vinyl => -14.0,
            Self::Broadcast => -23.0,
            Self::Club => -8.0,
            Self::Podcast => -16.0,
            Self::Custom(lufs) => *lufs as f64,
        }
    }

    /// Get acceptable tolerance (dB)
    pub fn tolerance(&self) -> f64 {
        match self {
            Self::Broadcast => 0.5, // Strict for broadcast
            _ => 1.0,
        }
    }
}


/// Genre classification for processing hints
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[derive(Default)]
pub enum MusicGenre {
    Pop,
    Rock,
    HipHop,
    Electronic,
    Classical,
    Jazz,
    Metal,
    RnB,
    Country,
    Acoustic,
    Ambient,
    Orchestral,
    #[default]
    Unknown,
}


impl MusicGenre {
    /// Typical dynamic range for genre
    pub fn typical_dynamic_range(&self) -> (f64, f64) {
        match self {
            Self::Classical | Self::Jazz | Self::Orchestral => (12.0, 20.0),
            Self::Acoustic | Self::Country => (10.0, 16.0),
            Self::Pop | Self::RnB => (6.0, 10.0),
            Self::Rock | Self::Metal => (4.0, 8.0),
            Self::Electronic | Self::HipHop => (4.0, 8.0),
            Self::Ambient => (10.0, 18.0),
            Self::Unknown => (6.0, 14.0),
        }
    }

    /// Typical frequency emphasis
    pub fn typical_eq_hints(&self) -> Vec<EqHint> {
        match self {
            Self::Pop => vec![
                EqHint::boost(100.0, 2.0),   // Low end warmth
                EqHint::boost(3000.0, 1.5),  // Presence
                EqHint::boost(10000.0, 1.0), // Air
            ],
            Self::HipHop => vec![
                EqHint::boost(60.0, 3.0),   // Sub bass
                EqHint::cut(300.0, 1.5),    // Mud cut
                EqHint::boost(8000.0, 2.0), // Crisp
            ],
            Self::Electronic => vec![
                EqHint::boost(50.0, 2.5),    // Sub
                EqHint::boost(5000.0, 1.5),  // Presence
                EqHint::boost(12000.0, 1.0), // Shimmer
            ],
            Self::Rock | Self::Metal => vec![
                EqHint::boost(80.0, 2.0),   // Punch
                EqHint::boost(2500.0, 1.5), // Aggression
                EqHint::cut(400.0, 1.0),    // Clean up
            ],
            Self::Classical | Self::Orchestral => vec![
                EqHint::cut(40.0, 1.5),      // Rumble cut
                EqHint::boost(2000.0, 0.5),  // Slight presence
                EqHint::boost(14000.0, 1.0), // Air
            ],
            Self::Jazz => vec![
                EqHint::boost(100.0, 1.5),  // Bass warmth
                EqHint::boost(5000.0, 1.0), // Clarity
            ],
            Self::Acoustic => vec![
                EqHint::boost(200.0, 1.0),   // Body
                EqHint::boost(3000.0, 1.5),  // Presence
                EqHint::boost(12000.0, 1.0), // Sparkle
            ],
            Self::Ambient => vec![
                EqHint::cut(60.0, 2.0),     // Clean low end
                EqHint::boost(8000.0, 1.0), // Atmosphere
            ],
            Self::RnB => vec![
                EqHint::boost(80.0, 2.0),    // Bass
                EqHint::boost(3500.0, 1.5),  // Vocals forward
                EqHint::boost(10000.0, 1.0), // Air
            ],
            Self::Country => vec![
                EqHint::boost(150.0, 1.0),  // Guitar body
                EqHint::boost(2000.0, 1.0), // Twang
                EqHint::boost(8000.0, 1.5), // Brightness
            ],
            Self::Unknown => vec![],
        }
    }
}

/// EQ processing hint
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EqHint {
    /// Center frequency (Hz)
    pub frequency: f64,
    /// Gain (dB) - positive for boost, negative for cut
    pub gain: f64,
    /// Q factor
    pub q: f64,
}

impl EqHint {
    /// Create boost hint
    pub fn boost(freq: f64, gain: f64) -> Self {
        Self {
            frequency: freq,
            gain,
            q: 1.5,
        }
    }

    /// Create cut hint
    pub fn cut(freq: f64, gain: f64) -> Self {
        Self {
            frequency: freq,
            gain: -gain,
            q: 2.0,
        }
    }
}

/// Audio analysis result
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AudioAnalysis {
    /// Detected genre
    pub genre: MusicGenre,
    /// Genre confidence (0-1)
    pub genre_confidence: f64,
    /// Integrated loudness (LUFS)
    pub integrated_lufs: f64,
    /// Short-term loudness range (LU)
    pub loudness_range: f64,
    /// True peak (dBTP)
    pub true_peak: f64,
    /// Dynamic range (dB)
    pub dynamic_range: f64,
    /// Crest factor (dB)
    pub crest_factor: f64,
    /// Stereo width (0-1)
    pub stereo_width: f64,
    /// Stereo correlation (-1 to 1)
    pub stereo_correlation: f64,
    /// Bass energy ratio (0-1)
    pub bass_ratio: f64,
    /// Mid energy ratio (0-1)
    pub mid_ratio: f64,
    /// High energy ratio (0-1)
    pub high_ratio: f64,
    /// Spectral centroid (Hz)
    pub spectral_centroid: f64,
    /// Spectral flatness (0-1)
    pub spectral_flatness: f64,
    /// Detected BPM
    pub bpm: Option<f64>,
    /// Key detection
    pub key: Option<String>,
}

impl AudioAnalysis {
    /// Create from audio samples
    pub fn analyze(_samples: &[f32], _sample_rate: u32) -> Self {
        // Placeholder - actual implementation would use ML models
        Self::default()
    }

    /// Is the track too quiet for target?
    pub fn is_too_quiet(&self, target: &LoudnessTarget) -> bool {
        self.integrated_lufs < target.lufs() - target.tolerance()
    }

    /// Is the track too loud for target?
    pub fn is_too_loud(&self, target: &LoudnessTarget) -> bool {
        self.integrated_lufs > target.lufs() + target.tolerance()
    }

    /// Is true peak clipping?
    pub fn is_clipping(&self) -> bool {
        self.true_peak > 0.0
    }

    /// Is dynamic range too low?
    pub fn is_over_compressed(&self) -> bool {
        let (min_dr, _) = self.genre.typical_dynamic_range();
        self.dynamic_range < min_dr
    }
}

/// Mastering recommendations
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MasteringRecommendations {
    /// Gain adjustment needed (dB)
    pub gain_adjustment: f64,
    /// Limiter ceiling recommendation (dBTP)
    pub limiter_ceiling: f64,
    /// Limiter threshold recommendation (dB)
    pub limiter_threshold: f64,
    /// EQ adjustments
    pub eq_adjustments: Vec<EqHint>,
    /// Stereo width adjustment (multiplier)
    pub stereo_width_mult: f64,
    /// Suggested compression ratio
    pub compression_ratio: Option<f64>,
    /// Suggested attack time (ms)
    pub attack_ms: Option<f64>,
    /// Suggested release time (ms)
    pub release_ms: Option<f64>,
    /// High pass filter frequency (Hz)
    pub highpass_freq: Option<f64>,
    /// Should add dither
    pub add_dither: bool,
    /// Warnings/issues
    pub warnings: Vec<String>,
    /// Overall confidence (0-1)
    pub confidence: f64,
}

impl MasteringRecommendations {
    /// Generate recommendations from analysis
    pub fn from_analysis(analysis: &AudioAnalysis, target: LoudnessTarget) -> Self {
        let mut rec = Self::default();
        let mut warnings = Vec::new();

        // Gain adjustment for loudness target
        rec.gain_adjustment = target.lufs() - analysis.integrated_lufs;

        // Limiter settings
        rec.limiter_ceiling = -1.0; // -1 dBTP is standard
        rec.limiter_threshold = rec.limiter_ceiling - rec.gain_adjustment.max(0.0);

        // Check for clipping
        if analysis.is_clipping() {
            warnings.push("Source audio has true peak clipping".to_string());
            rec.gain_adjustment = rec.gain_adjustment.min(-analysis.true_peak - 0.5);
        }

        // Over-compression warning
        if analysis.is_over_compressed() {
            warnings.push("Track appears over-compressed for genre".to_string());
        }

        // EQ recommendations based on genre
        rec.eq_adjustments = analysis.genre.typical_eq_hints();

        // Stereo width
        if analysis.stereo_width < 0.3 {
            rec.stereo_width_mult = 1.2; // Widen narrow mixes
        } else if analysis.stereo_width > 0.9 {
            rec.stereo_width_mult = 0.9; // Tighten very wide mixes
            warnings.push("Mix may have phase issues from excessive width".to_string());
        } else {
            rec.stereo_width_mult = 1.0;
        }

        // Correlation check
        if analysis.stereo_correlation < 0.0 {
            warnings.push("Potential mono compatibility issues".to_string());
        }

        // High pass for rumble
        if analysis.bass_ratio > 0.4 {
            rec.highpass_freq = Some(25.0);
        }

        // Compression suggestions for low DR
        let (min_dr, max_dr) = analysis.genre.typical_dynamic_range();
        if analysis.dynamic_range > max_dr {
            rec.compression_ratio = Some(2.0);
            rec.attack_ms = Some(30.0);
            rec.release_ms = Some(100.0);
        } else if analysis.dynamic_range < min_dr * 0.8 {
            warnings.push("Very limited dynamic range".to_string());
        }

        // Dither for bit depth reduction
        rec.add_dither = true;

        rec.warnings = warnings;
        rec.confidence = analysis.genre_confidence * 0.9; // Scale by genre certainty

        rec
    }

    /// Is this a "no processing needed" result?
    pub fn is_minimal(&self) -> bool {
        self.gain_adjustment.abs() < 0.5
            && self.eq_adjustments.is_empty()
            && self.compression_ratio.is_none()
            && (self.stereo_width_mult - 1.0).abs() < 0.05
    }
}

/// Reference track matching
#[derive(Debug, Clone, Default)]
pub struct ReferenceMatch {
    /// Reference track analysis
    pub reference: AudioAnalysis,
    /// Source track analysis
    pub source: AudioAnalysis,
    /// Match quality score (0-1)
    pub match_score: f64,
    /// EQ curve to match reference
    pub eq_curve: Vec<(f64, f64)>,
    /// Loudness difference (dB)
    pub loudness_diff: f64,
    /// Dynamic range difference (dB)
    pub dr_diff: f64,
    /// Width difference
    pub width_diff: f64,
}

impl ReferenceMatch {
    /// Create match from two analyses
    pub fn new(reference: AudioAnalysis, source: AudioAnalysis) -> Self {
        let loudness_diff = reference.integrated_lufs - source.integrated_lufs;
        let dr_diff = reference.dynamic_range - source.dynamic_range;
        let width_diff = reference.stereo_width - source.stereo_width;

        // Simple match score based on spectral similarity
        let spectral_match = 1.0
            - ((reference.bass_ratio - source.bass_ratio).abs()
                + (reference.mid_ratio - source.mid_ratio).abs()
                + (reference.high_ratio - source.high_ratio).abs())
                / 3.0;

        Self {
            reference,
            source,
            match_score: spectral_match.max(0.0),
            eq_curve: Vec::new(), // Would be computed by spectral matching
            loudness_diff,
            dr_diff,
            width_diff,
        }
    }

    /// Generate processing to match reference
    pub fn generate_processing(&self) -> MasteringRecommendations {
        let mut rec = MasteringRecommendations::default();

        rec.gain_adjustment = self.loudness_diff;
        rec.limiter_ceiling = -1.0;
        rec.limiter_threshold = -1.0 - self.loudness_diff.max(0.0);

        // Width adjustment
        if self.width_diff.abs() > 0.1 {
            rec.stereo_width_mult = 1.0 + (self.width_diff * 0.5);
        }

        rec.confidence = self.match_score;
        rec
    }
}

/// AI Mastering Session
#[derive(Debug, Clone)]
pub struct MasteringSession {
    /// Source audio analysis
    pub source_analysis: Option<AudioAnalysis>,
    /// Reference track analyses
    pub references: Vec<AudioAnalysis>,
    /// Target loudness
    pub target: LoudnessTarget,
    /// Current recommendations
    pub recommendations: Option<MasteringRecommendations>,
    /// Processing history for A/B
    pub history: Vec<MasteringRecommendations>,
}

impl Default for MasteringSession {
    fn default() -> Self {
        Self::new()
    }
}

impl MasteringSession {
    /// Create new session
    pub fn new() -> Self {
        Self {
            source_analysis: None,
            references: Vec::new(),
            target: LoudnessTarget::default(),
            recommendations: None,
            history: Vec::new(),
        }
    }

    /// Set source audio
    pub fn set_source(&mut self, samples: &[f32], sample_rate: u32) {
        self.source_analysis = Some(AudioAnalysis::analyze(samples, sample_rate));
        self.update_recommendations();
    }

    /// Add reference track
    pub fn add_reference(&mut self, samples: &[f32], sample_rate: u32) {
        self.references
            .push(AudioAnalysis::analyze(samples, sample_rate));
        self.update_recommendations();
    }

    /// Set loudness target
    pub fn set_target(&mut self, target: LoudnessTarget) {
        self.target = target;
        self.update_recommendations();
    }

    /// Update recommendations based on current state
    fn update_recommendations(&mut self) {
        if let Some(ref source) = self.source_analysis {
            // If we have references, match to them
            if !self.references.is_empty() {
                // Average the reference characteristics
                // For now, just use first reference
                let reference = &self.references[0];
                let match_result = ReferenceMatch::new(reference.clone(), source.clone());
                self.recommendations = Some(match_result.generate_processing());
            } else {
                // Generate recommendations based on target only
                self.recommendations =
                    Some(MasteringRecommendations::from_analysis(source, self.target));
            }
        }
    }

    /// Store current recommendations in history
    pub fn checkpoint(&mut self) {
        if let Some(ref rec) = self.recommendations {
            self.history.push(rec.clone());
        }
    }

    /// Revert to previous recommendations
    pub fn revert(&mut self) -> Option<MasteringRecommendations> {
        self.history.pop()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_loudness_target() {
        assert_eq!(LoudnessTarget::Streaming.lufs(), -14.0);
        assert_eq!(LoudnessTarget::Broadcast.lufs(), -23.0);
        assert_eq!(LoudnessTarget::Custom(-12).lufs(), -12.0);
    }

    #[test]
    fn test_genre_hints() {
        let hints = MusicGenre::Pop.typical_eq_hints();
        assert!(!hints.is_empty());
    }

    #[test]
    fn test_audio_analysis() {
        let analysis = AudioAnalysis {
            integrated_lufs: -18.0,
            true_peak: -0.5,
            ..Default::default()
        };

        assert!(analysis.is_too_quiet(&LoudnessTarget::Streaming));
        assert!(!analysis.is_clipping());
    }

    #[test]
    fn test_recommendations() {
        let analysis = AudioAnalysis {
            genre: MusicGenre::Pop,
            genre_confidence: 0.9,
            integrated_lufs: -18.0,
            dynamic_range: 8.0,
            stereo_width: 0.5,
            stereo_correlation: 0.8,
            ..Default::default()
        };

        let rec = MasteringRecommendations::from_analysis(&analysis, LoudnessTarget::Streaming);
        assert!((rec.gain_adjustment - 4.0).abs() < 0.1); // Need +4dB to reach -14 LUFS
        assert!(!rec.eq_adjustments.is_empty());
    }

    #[test]
    fn test_mastering_session() {
        let mut session = MasteringSession::new();
        session.set_target(LoudnessTarget::Streaming);
        assert!(session.recommendations.is_none()); // No source yet
    }
}
