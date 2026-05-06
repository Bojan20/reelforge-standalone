//! Stage→Asset map schema — the canonical structured output AI Composer produces.
//!
//! When a user types "Egyptian temple slot, 96% RTP, medium volatility" into the
//! AI Composer, the LLM must return a `StageAssetMap` that:
//! - covers every required Stage (REEL_SPIN_START, BIG_WIN, etc.)
//! - declares an asset intent per stage (file path, type, mood, dynamic level)
//! - includes compliance hints that RGAI can validate before commit

use serde::{Deserialize, Serialize};

/// Top-level structured output of an AI Composer job.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StageAssetMap {
    /// Theme tag (e.g. "egyptian_temple", "neon_cyber", "norse_mythology").
    pub theme: String,

    /// Free-form mood description ("mystical, anticipatory, brass-driven").
    pub mood: String,

    /// Approximate BPM target for music beds.
    pub target_bpm: u16,

    /// Per-stage asset intents.
    pub stages: Vec<StageIntent>,

    /// Compliance hints — what the AI thinks the regulators will check.
    /// Used by `FluxComposer` to seed RGAI before the final validation.
    pub compliance_hints: ComplianceHints,

    /// Self-reported quality score (0–100). Set by the grading pass.
    #[serde(default)]
    pub self_quality_score: u8,

    /// Self-critique (what the AI thinks could be improved).
    #[serde(default)]
    pub self_critique: String,
}

/// Audio intent for one stage in the slot lifecycle.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StageIntent {
    /// Stage identifier — must match a known `rf-stage::Stage` enum variant.
    /// E.g. `REEL_SPIN_START`, `REEL_STOP`, `BIG_WIN`, `BONUS_TRIGGER`.
    pub stage_id: String,

    /// One or more asset intents for this stage (some stages have multiple layers).
    pub assets: Vec<AssetIntent>,
}

/// Single asset description.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AssetIntent {
    /// Logical role: `loop`, `oneshot`, `transition`, `vo`, `ambient`, `sting`.
    pub kind: String,

    /// Suggested file name (no extension — engine resolves).
    pub suggested_name: String,

    /// Mood tag (e.g. "anticipation", "celebration", "tension").
    pub mood: String,

    /// Dynamic level 0–100 (0 = barely audible bed, 100 = peak hit).
    pub dynamic_level: u8,

    /// Suggested length in milliseconds (None = engine decides).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub length_ms: Option<u32>,

    /// Bus assignment hint (`music`, `sfx`, `voice`, `ambience`, `aux`).
    pub bus: String,

    /// Free-form prompt for downstream audio generation (Suno, Udio, ElevenLabs, etc.).
    pub generation_prompt: String,
}

/// Compliance hints declared by the AI alongside the asset map.
///
/// These are NOT authoritative — RGAI still runs full validation. They're used as
/// a "did you forget?" pre-check so the AI catches obvious LDW / near-miss issues
/// before they reach the validator.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct ComplianceHints {
    /// Jurisdictions the AI was told to satisfy (e.g. ["UKGC", "MGA"]).
    pub target_jurisdictions: Vec<String>,

    /// Whether the AI deliberately suppressed celebration audio for LDW spins.
    pub ldw_audio_suppressed: bool,

    /// Whether the AI generated proportional audio (small wins get small celebrations).
    pub proportional_celebrations: bool,

    /// Whether near-miss audio was deliberately neutralized.
    pub near_miss_neutralized: bool,

    /// Free-form notes the AI wants to flag for the human reviewer.
    pub reviewer_notes: String,
}

impl StageAssetMap {
    /// JSON schema describing this structure — sent to providers that support
    /// structured output (Anthropic JSON mode, Azure function calling).
    pub fn json_schema() -> serde_json::Value {
        serde_json::json!({
            "type": "object",
            "required": ["theme", "mood", "target_bpm", "stages", "compliance_hints"],
            "properties": {
                "theme": { "type": "string" },
                "mood": { "type": "string" },
                "target_bpm": { "type": "integer", "minimum": 40, "maximum": 220 },
                "stages": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["stage_id", "assets"],
                        "properties": {
                            "stage_id": { "type": "string" },
                            "assets": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "required": ["kind", "suggested_name", "mood", "dynamic_level", "bus", "generation_prompt"],
                                    "properties": {
                                        "kind": { "type": "string" },
                                        "suggested_name": { "type": "string" },
                                        "mood": { "type": "string" },
                                        "dynamic_level": { "type": "integer", "minimum": 0, "maximum": 100 },
                                        "length_ms": { "type": "integer", "minimum": 50 },
                                        "bus": { "type": "string", "enum": ["music", "sfx", "voice", "ambience", "aux"] },
                                        "generation_prompt": { "type": "string" }
                                    }
                                }
                            }
                        }
                    }
                },
                "compliance_hints": {
                    "type": "object",
                    "required": ["target_jurisdictions", "ldw_audio_suppressed", "proportional_celebrations", "near_miss_neutralized", "reviewer_notes"],
                    "properties": {
                        "target_jurisdictions": { "type": "array", "items": { "type": "string" } },
                        "ldw_audio_suppressed": { "type": "boolean" },
                        "proportional_celebrations": { "type": "boolean" },
                        "near_miss_neutralized": { "type": "boolean" },
                        "reviewer_notes": { "type": "string" }
                    }
                },
                "self_quality_score": { "type": "integer", "minimum": 0, "maximum": 100 },
                "self_critique": { "type": "string" }
            }
        })
    }

    /// List of stage identifiers that any production-ready map MUST cover.
    ///
    /// This is the contract `FluxComposer` enforces — if the LLM omits any of
    /// these, the composer either re-prompts with the missing list or fails the job.
    pub fn required_stage_ids() -> &'static [&'static str] {
        &[
            "REEL_SPIN_START",
            "REEL_SPIN_LOOP",
            "REEL_STOP",
            "WIN_SMALL",
            "WIN_MEDIUM",
            "BIG_WIN",
            "NEAR_MISS",
            "LOSS",
            "BONUS_TRIGGER",
            "AMBIENT_BED",
        ]
    }

    /// Find missing required stages.
    pub fn missing_required_stages(&self) -> Vec<&'static str> {
        Self::required_stage_ids()
            .iter()
            .filter(|req| !self.stages.iter().any(|s| s.stage_id == **req))
            .copied()
            .collect()
    }

    /// Validate basic structural sanity (does NOT replace RGAI compliance).
    pub fn validate(&self) -> Result<(), Vec<String>> {
        let mut errors = Vec::new();

        if self.theme.trim().is_empty() {
            errors.push("theme is empty".to_string());
        }
        if !(40..=220).contains(&self.target_bpm) {
            errors.push(format!(
                "target_bpm {} out of range [40, 220]",
                self.target_bpm
            ));
        }
        let missing = self.missing_required_stages();
        if !missing.is_empty() {
            errors.push(format!("missing required stages: {:?}", missing));
        }
        for stage in &self.stages {
            if stage.assets.is_empty() {
                errors.push(format!("stage {} has no assets", stage.stage_id));
            }
            for asset in &stage.assets {
                if asset.dynamic_level > 100 {
                    errors.push(format!(
                        "stage {}: dynamic_level {} > 100",
                        stage.stage_id, asset.dynamic_level
                    ));
                }
                if !["music", "sfx", "voice", "ambience", "aux"].contains(&asset.bus.as_str()) {
                    errors.push(format!(
                        "stage {}: invalid bus '{}'",
                        stage.stage_id, asset.bus
                    ));
                }
            }
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_minimal_map() -> StageAssetMap {
        let stages = StageAssetMap::required_stage_ids()
            .iter()
            .map(|id| StageIntent {
                stage_id: id.to_string(),
                assets: vec![AssetIntent {
                    kind: "oneshot".to_string(),
                    suggested_name: format!("{}_default", id.to_lowercase()),
                    mood: "neutral".to_string(),
                    dynamic_level: 50,
                    length_ms: Some(1000),
                    bus: "sfx".to_string(),
                    generation_prompt: "neutral oneshot".to_string(),
                }],
            })
            .collect();

        StageAssetMap {
            theme: "test_theme".to_string(),
            mood: "test mood".to_string(),
            target_bpm: 120,
            stages,
            compliance_hints: ComplianceHints {
                target_jurisdictions: vec!["UKGC".to_string()],
                ldw_audio_suppressed: true,
                proportional_celebrations: true,
                near_miss_neutralized: true,
                reviewer_notes: "test".to_string(),
            },
            self_quality_score: 80,
            self_critique: String::new(),
        }
    }

    #[test]
    fn required_stages_are_unique() {
        let ids = StageAssetMap::required_stage_ids();
        let mut sorted: Vec<_> = ids.to_vec();
        sorted.sort();
        sorted.dedup();
        assert_eq!(ids.len(), sorted.len());
    }

    #[test]
    fn minimal_map_validates() {
        let m = make_minimal_map();
        assert!(m.validate().is_ok());
    }

    #[test]
    fn missing_required_stage_detected() {
        let mut m = make_minimal_map();
        m.stages.retain(|s| s.stage_id != "BIG_WIN");
        let errs = m.validate().unwrap_err();
        assert!(errs.iter().any(|e| e.contains("BIG_WIN")));
    }

    #[test]
    fn empty_theme_rejected() {
        let mut m = make_minimal_map();
        m.theme = String::new();
        assert!(m.validate().is_err());
    }

    #[test]
    fn out_of_range_bpm_rejected() {
        let mut m = make_minimal_map();
        m.target_bpm = 300;
        let errs = m.validate().unwrap_err();
        assert!(errs.iter().any(|e| e.contains("target_bpm")));
    }

    #[test]
    fn invalid_bus_rejected() {
        let mut m = make_minimal_map();
        m.stages[0].assets[0].bus = "main".to_string();
        let errs = m.validate().unwrap_err();
        assert!(errs.iter().any(|e| e.contains("invalid bus")));
    }

    #[test]
    fn json_schema_is_valid_json() {
        let schema = StageAssetMap::json_schema();
        assert!(schema.is_object());
        assert_eq!(schema["type"], "object");
    }

    #[test]
    fn round_trip_serde_json() {
        let m = make_minimal_map();
        let s = serde_json::to_string(&m).unwrap();
        let back: StageAssetMap = serde_json::from_str(&s).unwrap();
        assert_eq!(m, back);
    }
}
