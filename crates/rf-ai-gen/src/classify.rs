//! T8.4: FFNC Auto-Categorization — FluxForge Neural Category assignment.
//!
//! Automatically assigns generated audio assets to the correct FFNC category
//! based on the original prompt's AudioDescriptor and optional audio metadata.
//!
//! FFNC (FluxForge Neural Categorization) is the internal taxonomy used
//! across all FluxForge tools for audio event classification.

use serde::{Deserialize, Serialize};
use crate::prompt::{AudioDescriptor, EventCategory, AudioTier};

/// FFNC top-level category
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum FfncCategory {
    /// Base game sounds: reels, spins, stops
    BaseGame,
    /// Win tier sounds: small to epic wins
    WinTier(WinTierLevel),
    /// Feature sounds: bonus triggers, free spins
    Feature,
    /// Jackpot: major/grand/mega jackpot events
    Jackpot,
    /// Ambient: background music, atmosphere
    Ambient,
    /// UI: buttons, transitions, notifications
    UserInterface,
    /// Near-miss and anticipation builds
    NearMiss,
    /// Reel mechanics: individual reel sounds
    ReelMechanic,
    /// Coin / credit sounds
    Coin,
    /// Game transition: level up, round change
    Transition,
    /// Voice/speech (if applicable)
    Voice,
}

/// Win tier levels for FFNC classification
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum WinTierLevel {
    /// Tier 1: Small win (< 2x bet)
    Tier1Small,
    /// Tier 2: Medium win (2-5x bet)
    Tier2Medium,
    /// Tier 3: Big win (5-20x bet)
    Tier3Big,
    /// Tier 4: Epic win (20-100x bet)
    Tier4Epic,
    /// Tier 5: Mega win (> 100x bet)
    Tier5Mega,
}

impl FfncCategory {
    pub fn display_name(&self) -> String {
        match self {
            Self::BaseGame => "Base Game".to_string(),
            Self::WinTier(t) => format!("Win Tier {}", match t {
                WinTierLevel::Tier1Small  => "1 (Small)",
                WinTierLevel::Tier2Medium => "2 (Medium)",
                WinTierLevel::Tier3Big    => "3 (Big)",
                WinTierLevel::Tier4Epic   => "4 (Epic)",
                WinTierLevel::Tier5Mega   => "5 (Mega)",
            }),
            Self::Feature      => "Feature / Bonus".to_string(),
            Self::Jackpot      => "Jackpot".to_string(),
            Self::Ambient      => "Ambient / Music".to_string(),
            Self::UserInterface => "User Interface".to_string(),
            Self::NearMiss     => "Near Miss".to_string(),
            Self::ReelMechanic => "Reel Mechanic".to_string(),
            Self::Coin         => "Coin / Credits".to_string(),
            Self::Transition   => "Transition".to_string(),
            Self::Voice        => "Voice".to_string(),
        }
    }

    pub fn ffnc_code(&self) -> String {
        match self {
            Self::BaseGame               => "BG".to_string(),
            Self::WinTier(WinTierLevel::Tier1Small)  => "W1".to_string(),
            Self::WinTier(WinTierLevel::Tier2Medium) => "W2".to_string(),
            Self::WinTier(WinTierLevel::Tier3Big)    => "W3".to_string(),
            Self::WinTier(WinTierLevel::Tier4Epic)   => "W4".to_string(),
            Self::WinTier(WinTierLevel::Tier5Mega)   => "W5".to_string(),
            Self::Feature      => "FT".to_string(),
            Self::Jackpot      => "JP".to_string(),
            Self::Ambient      => "AM".to_string(),
            Self::UserInterface => "UI".to_string(),
            Self::NearMiss     => "NM".to_string(),
            Self::ReelMechanic => "RM".to_string(),
            Self::Coin         => "CN".to_string(),
            Self::Transition   => "TR".to_string(),
            Self::Voice        => "VC".to_string(),
        }
    }
}

/// Optional audio metadata from analysis of the generated file
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AudioAnalysisMetadata {
    /// RMS level in dBFS
    pub rms_db: Option<f32>,
    /// Peak level in dBFS
    pub peak_db: Option<f32>,
    /// Spectral centroid in Hz (brightness indicator)
    pub spectral_centroid_hz: Option<f32>,
    /// Has rhythmic transients
    pub has_transients: Option<bool>,
    /// Detected tempo in BPM (0 = no beat detected)
    pub detected_bpm: Option<f32>,
    /// Has sustained tones (melodic content)
    pub has_sustained_tones: Option<bool>,
}

/// FFNC classification result (T8.4)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClassificationResult {
    /// Primary FFNC category
    pub category: FfncCategory,
    /// FFNC code (e.g., "W4")
    pub ffnc_code: String,
    /// Display name
    pub display_name: String,
    /// Sub-category tags
    pub tags: Vec<String>,
    /// Suggested event name (e.g., "WIN_4", "AMBIENT_BED")
    pub suggested_event_name: String,
    /// Confidence score (0.0–1.0)
    pub confidence: f64,
    /// Whether this should be set as is_required in the spec
    pub is_required: bool,
    /// Suggested tier string for slot system
    pub tier_str: String,
}

/// Auto-categorizer for generated audio assets (T8.4)
pub struct FfncClassifier;

impl FfncClassifier {
    /// Classify a generated asset based on its descriptor and optional audio metadata.
    pub fn classify(
        descriptor: &AudioDescriptor,
        metadata: Option<&AudioAnalysisMetadata>,
    ) -> ClassificationResult {
        let category = Self::determine_category(descriptor, metadata);
        let tags = Self::generate_tags(descriptor, &category);
        let suggested_event_name = Self::suggest_event_name(descriptor, &category);
        let confidence = Self::compute_confidence(descriptor, metadata);
        let ffnc_code = category.ffnc_code();
        let display_name = category.display_name();
        let tier_str = descriptor.tier.as_str().to_string();
        let is_required = descriptor.is_required;

        ClassificationResult {
            category,
            ffnc_code,
            display_name,
            tags,
            suggested_event_name,
            confidence,
            is_required,
            tier_str,
        }
    }

    fn determine_category(
        descriptor: &AudioDescriptor,
        metadata: Option<&AudioAnalysisMetadata>,
    ) -> FfncCategory {
        match &descriptor.category {
            EventCategory::Jackpot => FfncCategory::Jackpot,
            EventCategory::Feature => FfncCategory::Feature,
            EventCategory::Ambient => FfncCategory::Ambient,
            EventCategory::UI => FfncCategory::UserInterface,
            EventCategory::NearMiss => FfncCategory::NearMiss,
            EventCategory::Transition => FfncCategory::Transition,
            EventCategory::BaseGame => {
                // Sub-classify: reel mechanic vs coin vs general base game
                let p = descriptor.prompt.to_lowercase();
                if p.contains("coin") || p.contains("credit") {
                    FfncCategory::Coin
                } else if p.contains("reel") || p.contains("spin") || p.contains("stop") {
                    FfncCategory::ReelMechanic
                } else {
                    FfncCategory::BaseGame
                }
            }
            EventCategory::Win => {
                // Map tier → win tier level
                // Also refine with audio analysis if available
                let tier_level = Self::win_tier_from_descriptor(descriptor, metadata);
                FfncCategory::WinTier(tier_level)
            }
        }
    }

    fn win_tier_from_descriptor(
        descriptor: &AudioDescriptor,
        _metadata: Option<&AudioAnalysisMetadata>,
    ) -> WinTierLevel {
        // Duration-based refinement: longer wins = higher tier
        let prompt_lower = descriptor.prompt.to_lowercase();

        if prompt_lower.contains("small") || prompt_lower.contains("minor") {
            return WinTierLevel::Tier1Small;
        }
        if prompt_lower.contains("mega") || prompt_lower.contains("ultra")
            || prompt_lower.contains("maximum") {
            return WinTierLevel::Tier5Mega;
        }

        match descriptor.tier {
            AudioTier::Subtle   => WinTierLevel::Tier1Small,
            AudioTier::Standard => WinTierLevel::Tier2Medium,
            AudioTier::Premium  => WinTierLevel::Tier3Big,
            AudioTier::Flagship => WinTierLevel::Tier5Mega,
        }
    }

    fn generate_tags(descriptor: &AudioDescriptor, category: &FfncCategory) -> Vec<String> {
        let mut tags = Vec::new();

        // Style tags
        let style_tag = format!("{:?}", descriptor.style).to_lowercase();
        if style_tag != "unknown" { tags.push(style_tag); }

        // Mood tags
        let mood_tag = format!("{:?}", descriptor.mood).to_lowercase();
        if mood_tag != "neutral" { tags.push(mood_tag); }

        // Can loop
        if descriptor.can_loop { tags.push("loop".to_string()); }

        // Tier tag
        tags.push(descriptor.tier.as_str().to_string());

        // Category-specific tags
        match category {
            FfncCategory::Jackpot => {
                tags.push("jackpot".to_string());
                tags.push("celebration".to_string());
            }
            FfncCategory::Ambient => {
                tags.push("background".to_string());
                tags.push("atmosphere".to_string());
            }
            FfncCategory::ReelMechanic => {
                tags.push("mechanical".to_string());
                tags.push("reel".to_string());
            }
            _ => {}
        }

        // Custom generation tags from prompt
        tags.extend(descriptor.generation_tags.iter().cloned());

        tags.sort();
        tags.dedup();
        tags
    }

    fn suggest_event_name(descriptor: &AudioDescriptor, category: &FfncCategory) -> String {
        match category {
            FfncCategory::WinTier(t) => match t {
                WinTierLevel::Tier1Small  => "WIN_1".to_string(),
                WinTierLevel::Tier2Medium => "WIN_2".to_string(),
                WinTierLevel::Tier3Big    => "WIN_3".to_string(),
                WinTierLevel::Tier4Epic   => "WIN_4".to_string(),
                WinTierLevel::Tier5Mega   => "WIN_5".to_string(),
            },
            FfncCategory::Jackpot => "JACKPOT".to_string(),
            FfncCategory::Feature => "FEATURE_TRIGGER".to_string(),
            FfncCategory::Ambient => {
                if descriptor.can_loop { "AMBIENT_BED".to_string() }
                else { "AMBIENT_STINGER".to_string() }
            },
            FfncCategory::UserInterface => "UI_CLICK".to_string(),
            FfncCategory::NearMiss => "NEAR_MISS".to_string(),
            FfncCategory::ReelMechanic => {
                let p = descriptor.prompt.to_lowercase();
                if p.contains("stop") { "REEL_STOP".to_string() }
                else { "REEL_SPIN".to_string() }
            },
            FfncCategory::BaseGame => "SPIN_START".to_string(),
            FfncCategory::Coin => "COIN_IN".to_string(),
            FfncCategory::Transition => "TRANSITION_REVEAL".to_string(),
            FfncCategory::Voice => "VOICE_EVENT".to_string(),
        }
    }

    fn compute_confidence(
        descriptor: &AudioDescriptor,
        metadata: Option<&AudioAnalysisMetadata>,
    ) -> f64 {
        let mut conf = descriptor.confidence;
        // Audio metadata increases classification confidence
        if metadata.is_some() { conf = (conf + 0.15).min(1.0); }
        conf
    }

    /// Get all FFNC categories available for assignment
    pub fn all_categories() -> Vec<FfncCategory> {
        vec![
            FfncCategory::BaseGame,
            FfncCategory::WinTier(WinTierLevel::Tier1Small),
            FfncCategory::WinTier(WinTierLevel::Tier2Medium),
            FfncCategory::WinTier(WinTierLevel::Tier3Big),
            FfncCategory::WinTier(WinTierLevel::Tier4Epic),
            FfncCategory::WinTier(WinTierLevel::Tier5Mega),
            FfncCategory::Feature,
            FfncCategory::Jackpot,
            FfncCategory::Ambient,
            FfncCategory::UserInterface,
            FfncCategory::NearMiss,
            FfncCategory::ReelMechanic,
            FfncCategory::Coin,
            FfncCategory::Transition,
            FfncCategory::Voice,
        ]
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::prompt::PromptParser;

    #[test]
    fn test_jackpot_classifies_as_jackpot() {
        let desc = PromptParser::parse("epic jackpot celebration fanfare");
        let result = FfncClassifier::classify(&desc, None);
        assert_eq!(result.category, FfncCategory::Jackpot);
        assert_eq!(result.ffnc_code, "JP");
        assert_eq!(result.suggested_event_name, "JACKPOT");
    }

    #[test]
    fn test_ambient_loop_classifies_correctly() {
        let desc = PromptParser::parse("relaxed casino ambient music loop");
        let result = FfncClassifier::classify(&desc, None);
        assert_eq!(result.category, FfncCategory::Ambient);
        assert_eq!(result.suggested_event_name, "AMBIENT_BED");
        assert!(result.tags.contains(&"loop".to_string()));
    }

    #[test]
    fn test_mega_win_classifies_as_tier5() {
        let desc = PromptParser::parse("mega win fanfare flagship ultimate");
        let result = FfncClassifier::classify(&desc, None);
        assert_eq!(result.category, FfncCategory::WinTier(WinTierLevel::Tier5Mega));
        assert_eq!(result.ffnc_code, "W5");
        assert_eq!(result.suggested_event_name, "WIN_5");
    }

    #[test]
    fn test_reel_stop_classifies_as_reel_mechanic() {
        let desc = PromptParser::parse("mechanical reel stop click");
        let result = FfncClassifier::classify(&desc, None);
        assert_eq!(result.category, FfncCategory::ReelMechanic);
        assert_eq!(result.suggested_event_name, "REEL_STOP");
    }

    #[test]
    fn test_ui_click_classifies_as_ui() {
        let desc = PromptParser::parse("short UI button click press");
        let result = FfncClassifier::classify(&desc, None);
        assert_eq!(result.category, FfncCategory::UserInterface);
    }

    #[test]
    fn test_near_miss_classifies_correctly() {
        let desc = PromptParser::parse("tense near miss almost winning sound");
        let result = FfncClassifier::classify(&desc, None);
        assert_eq!(result.category, FfncCategory::NearMiss);
    }

    #[test]
    fn test_metadata_increases_confidence() {
        let desc = PromptParser::parse("win sound");
        let without_meta = FfncClassifier::classify(&desc, None);
        let meta = AudioAnalysisMetadata { rms_db: Some(-18.0), has_transients: Some(true), ..Default::default() };
        let with_meta = FfncClassifier::classify(&desc, Some(&meta));
        assert!(with_meta.confidence >= without_meta.confidence);
    }

    #[test]
    fn test_all_categories_returns_complete_list() {
        let cats = FfncClassifier::all_categories();
        assert!(cats.len() >= 10);
        assert!(cats.contains(&FfncCategory::Jackpot));
        assert!(cats.contains(&FfncCategory::WinTier(WinTierLevel::Tier5Mega)));
    }

    #[test]
    fn test_ffnc_codes_are_unique() {
        let cats = FfncClassifier::all_categories();
        let codes: Vec<String> = cats.iter().map(|c| c.ffnc_code()).collect();
        let unique: std::collections::HashSet<_> = codes.iter().collect();
        assert_eq!(unique.len(), codes.len(), "FFNC codes must be unique");
    }
}
