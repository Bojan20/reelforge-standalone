//! Audio assistant configuration

use serde::{Deserialize, Serialize};

/// Assistant configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssistantConfig {
    /// Target loudness (LUFS) for suggestions
    pub target_loudness_lufs: f32,

    /// Target true peak (dBTP)
    pub target_true_peak_db: f32,

    /// Use GPU for classification
    pub use_gpu: bool,

    /// Enable genre classification
    pub classify_genre: bool,

    /// Enable mood classification
    pub classify_mood: bool,

    /// Enable tempo detection
    pub detect_tempo: bool,

    /// Enable key detection
    pub detect_key: bool,

    /// Minimum confidence for suggestions
    pub min_suggestion_confidence: f32,

    /// Analysis segment length (seconds)
    pub segment_length_secs: f32,
}

impl Default for AssistantConfig {
    fn default() -> Self {
        Self {
            target_loudness_lufs: -14.0,
            target_true_peak_db: -1.0,
            use_gpu: true,
            classify_genre: true,
            classify_mood: true,
            detect_tempo: true,
            detect_key: true,
            min_suggestion_confidence: 0.5,
            segment_length_secs: 10.0,
        }
    }
}

impl AssistantConfig {
    /// Create config for streaming target
    pub fn streaming() -> Self {
        Self {
            target_loudness_lufs: -14.0,
            target_true_peak_db: -1.0,
            ..Default::default()
        }
    }

    /// Create config for CD/Mastering target
    pub fn mastering() -> Self {
        Self {
            target_loudness_lufs: -9.0,
            target_true_peak_db: -0.3,
            ..Default::default()
        }
    }

    /// Create config for broadcast
    pub fn broadcast() -> Self {
        Self {
            target_loudness_lufs: -24.0,
            target_true_peak_db: -2.0,
            ..Default::default()
        }
    }

    /// Create config for podcast
    pub fn podcast() -> Self {
        Self {
            target_loudness_lufs: -16.0,
            target_true_peak_db: -1.5,
            classify_genre: false,
            detect_key: false,
            ..Default::default()
        }
    }

    /// Create minimal config (fast)
    pub fn minimal() -> Self {
        Self {
            classify_genre: false,
            classify_mood: false,
            detect_tempo: false,
            detect_key: false,
            ..Default::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_presets() {
        let streaming = AssistantConfig::streaming();
        let mastering = AssistantConfig::mastering();
        let broadcast = AssistantConfig::broadcast();

        // Streaming is louder than broadcast
        assert!(streaming.target_loudness_lufs > broadcast.target_loudness_lufs);

        // Mastering is loudest
        assert!(mastering.target_loudness_lufs > streaming.target_loudness_lufs);
    }
}
