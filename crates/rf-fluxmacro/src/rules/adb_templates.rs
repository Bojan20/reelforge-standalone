// ============================================================================
// rf-fluxmacro — ADB Templates
// ============================================================================
// FM-13: ADB section templates + emotional arc templates per mechanic.
// Used by the ADB auto-generator to produce Audio Design Brief documents.
// ============================================================================

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::context::VolatilityLevel;

/// Complete ADB template configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdbTemplates {
    /// Section templates for the ADB document.
    pub sections: Vec<AdbSection>,
    /// Volatility → audio profile mapping.
    pub volatility_profiles: HashMap<String, VolatilityAudioProfile>,
    /// Emotional arc templates per mechanic.
    pub emotional_arcs: HashMap<String, EmotionalArcTemplate>,
    /// Ducking priority rules.
    pub ducking_priorities: Vec<DuckingRule>,
}

/// A section template for the ADB document.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdbSection {
    /// Section number (1-10).
    pub number: u32,
    /// Section name.
    pub name: String,
    /// Description of what this section contains.
    pub description: String,
    /// Template content with placeholders (e.g., {{game_id}}).
    pub template: String,
}

/// Audio profile derived from volatility level.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolatilityAudioProfile {
    pub music_layers: u32,
    pub layer_names: Vec<String>,
    pub build_up_duration_range: (f32, f32),
    pub dynamic_range_db: f32,
    pub anticipation_boost_pct: f32,
}

/// Emotional arc template for ADB.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmotionalArcTemplate {
    pub mechanic_name: String,
    pub phases: Vec<ArcPhase>,
}

/// A phase within an emotional arc.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArcPhase {
    pub name: String,
    pub description: String,
    pub audio_cues: Vec<String>,
    pub duration_hint: String,
}

/// Ducking priority rule.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuckingRule {
    pub source: String,
    pub target: String,
    pub attenuation_db: f32,
    pub attack_ms: f32,
    pub release_ms: f32,
    pub priority: u32,
}

impl Default for AdbTemplates {
    fn default() -> Self {
        Self {
            sections: default_sections(),
            volatility_profiles: default_volatility_profiles(),
            emotional_arcs: default_emotional_arcs(),
            ducking_priorities: default_ducking_rules(),
        }
    }
}

fn default_sections() -> Vec<AdbSection> {
    vec![
        AdbSection {
            number: 1,
            name: "Game Info".to_string(),
            description: "ID, volatility, platforms, theme, mechanics".to_string(),
            template: "# 1. Game Info\n\n- **Game ID:** {{game_id}}\n- **Volatility:** {{volatility}}\n- **Theme:** {{theme}}\n- **Platforms:** {{platforms}}\n- **Mechanics:** {{mechanics}}\n".to_string(),
        },
        AdbSection {
            number: 2,
            name: "Music Plan".to_string(),
            description: "Layer count, contexts, transitions, tempo range".to_string(),
            template: "# 2. Music Plan\n\n- **Layer Count:** {{music_layers}}\n- **Layers:** {{layer_names}}\n- **Build-up Duration:** {{build_up_range}}\n- **Dynamic Range:** {{dynamic_range}} dB\n".to_string(),
        },
        AdbSection {
            number: 3,
            name: "SFX Plan".to_string(),
            description: "Event list, variant requirements, category breakdown".to_string(),
            template: "# 3. SFX Plan\n\n{{sfx_event_table}}\n".to_string(),
        },
        AdbSection {
            number: 4,
            name: "VO Plan".to_string(),
            description: "Voiceover triggers, language considerations".to_string(),
            template: "# 4. VO Plan\n\n{{vo_events}}\n".to_string(),
        },
        AdbSection {
            number: 5,
            name: "Ducking Rules".to_string(),
            description: "Feature vs UI, VO vs Music, BigWin override".to_string(),
            template: "# 5. Ducking Rules\n\n{{ducking_table}}\n".to_string(),
        },
        AdbSection {
            number: 6,
            name: "Loudness Targets".to_string(),
            description: "Per-category LUFS, True Peak ceiling".to_string(),
            template: "# 6. Loudness Targets\n\n{{loudness_table}}\n".to_string(),
        },
        AdbSection {
            number: 7,
            name: "Voice Budget".to_string(),
            description: "Max voices per platform, stealing priority".to_string(),
            template: "# 7. Voice Budget\n\n{{voice_budget_table}}\n".to_string(),
        },
        AdbSection {
            number: 8,
            name: "RTP Mapping".to_string(),
            description: "Psychoacoustic scaling per RTP band".to_string(),
            template: "# 8. RTP Mapping\n\n{{rtp_table}}\n".to_string(),
        },
        AdbSection {
            number: 9,
            name: "Win Tier System".to_string(),
            description: "Threshold multipliers, celebration scaling".to_string(),
            template: "# 9. Win Tier System\n\n{{win_tier_table}}\n".to_string(),
        },
        AdbSection {
            number: 10,
            name: "Fatigue Rules".to_string(),
            description: "Max repetition, cooldown timers, variation requirements".to_string(),
            template: "# 10. Fatigue Rules\n\n{{fatigue_rules}}\n".to_string(),
        },
    ]
}

fn default_volatility_profiles() -> HashMap<String, VolatilityAudioProfile> {
    let mut profiles = HashMap::new();

    profiles.insert(
        "low".to_string(),
        VolatilityAudioProfile {
            music_layers: 2,
            layer_names: vec!["base".to_string(), "win".to_string()],
            build_up_duration_range: (0.5, 1.0),
            dynamic_range_db: 6.0,
            anticipation_boost_pct: 0.0,
        },
    );

    profiles.insert(
        "medium".to_string(),
        VolatilityAudioProfile {
            music_layers: 3,
            layer_names: vec!["base".to_string(), "mid".to_string(), "high".to_string()],
            build_up_duration_range: (1.0, 2.0),
            dynamic_range_db: 9.0,
            anticipation_boost_pct: 10.0,
        },
    );

    profiles.insert(
        "high".to_string(),
        VolatilityAudioProfile {
            music_layers: 4,
            layer_names: vec![
                "base".to_string(),
                "mid".to_string(),
                "high".to_string(),
                "peak".to_string(),
            ],
            build_up_duration_range: (2.0, 4.0),
            dynamic_range_db: 12.0,
            anticipation_boost_pct: 20.0,
        },
    );

    profiles.insert(
        "extreme".to_string(),
        VolatilityAudioProfile {
            music_layers: 5,
            layer_names: vec![
                "base".to_string(),
                "low".to_string(),
                "mid".to_string(),
                "high".to_string(),
                "peak".to_string(),
            ],
            build_up_duration_range: (3.0, 6.0),
            dynamic_range_db: 15.0,
            anticipation_boost_pct: 35.0,
        },
    );

    profiles
}

fn default_emotional_arcs() -> HashMap<String, EmotionalArcTemplate> {
    let mut arcs = HashMap::new();

    arcs.insert(
        "progressive".to_string(),
        EmotionalArcTemplate {
            mechanic_name: "Progressive Jackpot".to_string(),
            phases: vec![
                ArcPhase {
                    name: "build".to_string(),
                    description: "Tension builds as jackpot approaches".to_string(),
                    audio_cues: vec!["ladder_tick".to_string(), "music_layer_up".to_string()],
                    duration_hint: "variable".to_string(),
                },
                ArcPhase {
                    name: "suspense".to_string(),
                    description: "Near-miss moments, heightened anticipation".to_string(),
                    audio_cues: vec![
                        "near_miss_stinger".to_string(),
                        "anticipation_riser".to_string(),
                    ],
                    duration_hint: "2-5s".to_string(),
                },
                ArcPhase {
                    name: "peak".to_string(),
                    description: "Jackpot hit — maximum energy".to_string(),
                    audio_cues: vec!["jackpot_tier_hit".to_string(), "explosion".to_string()],
                    duration_hint: "1-2s".to_string(),
                },
                ArcPhase {
                    name: "celebrate".to_string(),
                    description: "Victory celebration with layered music".to_string(),
                    audio_cues: vec!["celebration_layers".to_string(), "confetti".to_string()],
                    duration_hint: "5-15s".to_string(),
                },
                ArcPhase {
                    name: "resolve".to_string(),
                    description: "Gradual wind-down back to base state".to_string(),
                    audio_cues: vec!["music_layer_down".to_string(), "settle".to_string()],
                    duration_hint: "3-5s".to_string(),
                },
            ],
        },
    );

    arcs.insert(
        "hold_and_win".to_string(),
        EmotionalArcTemplate {
            mechanic_name: "Hold & Win".to_string(),
            phases: vec![
                ArcPhase {
                    name: "lock".to_string(),
                    description: "Symbols lock in place with impact".to_string(),
                    audio_cues: vec!["hold_lock_impact".to_string()],
                    duration_hint: "0.5-1s per lock".to_string(),
                },
                ArcPhase {
                    name: "tension".to_string(),
                    description: "Tension builds with each respin".to_string(),
                    audio_cues: vec!["respin_count_tick".to_string(), "coin_land".to_string()],
                    duration_hint: "variable".to_string(),
                },
                ArcPhase {
                    name: "collect".to_string(),
                    description: "Collection moment — catharsis".to_string(),
                    audio_cues: vec!["collect_celebration".to_string()],
                    duration_hint: "3-5s".to_string(),
                },
                ArcPhase {
                    name: "relief".to_string(),
                    description: "Return to base game".to_string(),
                    audio_cues: vec!["settle".to_string()],
                    duration_hint: "1-2s".to_string(),
                },
            ],
        },
    );

    arcs.insert(
        "cascades".to_string(),
        EmotionalArcTemplate {
            mechanic_name: "Cascades / Tumble".to_string(),
            phases: vec![
                ArcPhase {
                    name: "trigger".to_string(),
                    description: "Initial win triggers cascade".to_string(),
                    audio_cues: vec!["cascade_drop".to_string()],
                    duration_hint: "0.5s".to_string(),
                },
                ArcPhase {
                    name: "chain".to_string(),
                    description: "Chain reactions with escalating sounds".to_string(),
                    audio_cues: vec!["cascade_chain_n".to_string(), "cascade_clear".to_string()],
                    duration_hint: "variable".to_string(),
                },
                ArcPhase {
                    name: "accelerate".to_string(),
                    description: "Audio accelerates with deeper chains".to_string(),
                    audio_cues: vec!["cascade_multiplier_tick".to_string()],
                    duration_hint: "variable".to_string(),
                },
                ArcPhase {
                    name: "climax".to_string(),
                    description: "Peak on max chain depth".to_string(),
                    audio_cues: vec!["cascade_climax".to_string()],
                    duration_hint: "1-2s".to_string(),
                },
                ArcPhase {
                    name: "settle".to_string(),
                    description: "Cascade ends, symbols settle".to_string(),
                    audio_cues: vec!["settle".to_string()],
                    duration_hint: "1s".to_string(),
                },
            ],
        },
    );

    arcs.insert(
        "free_spins".to_string(),
        EmotionalArcTemplate {
            mechanic_name: "Free Spins".to_string(),
            phases: vec![
                ArcPhase {
                    name: "fanfare".to_string(),
                    description: "Entry fanfare announcing free spins".to_string(),
                    audio_cues: vec!["fs_trigger_fanfare".to_string()],
                    duration_hint: "2-4s".to_string(),
                },
                ArcPhase {
                    name: "loop".to_string(),
                    description: "Free spins music loop".to_string(),
                    audio_cues: vec!["fs_music_loop".to_string()],
                    duration_hint: "variable".to_string(),
                },
                ArcPhase {
                    name: "escalate".to_string(),
                    description: "Music escalates with wins".to_string(),
                    audio_cues: vec!["music_layer_up".to_string()],
                    duration_hint: "variable".to_string(),
                },
                ArcPhase {
                    name: "resolve".to_string(),
                    description: "Final spin resolution".to_string(),
                    audio_cues: vec!["fs_end_summary".to_string()],
                    duration_hint: "2-3s".to_string(),
                },
                ArcPhase {
                    name: "summary".to_string(),
                    description: "Summary screen with total win".to_string(),
                    audio_cues: vec!["summary_fanfare".to_string()],
                    duration_hint: "3-5s".to_string(),
                },
            ],
        },
    );

    arcs.insert(
        "pick_bonus".to_string(),
        EmotionalArcTemplate {
            mechanic_name: "Pick Bonus".to_string(),
            phases: vec![
                ArcPhase {
                    name: "anticipation".to_string(),
                    description: "Pre-pick tension".to_string(),
                    audio_cues: vec!["pick_ambient_loop".to_string()],
                    duration_hint: "continuous".to_string(),
                },
                ArcPhase {
                    name: "reveal".to_string(),
                    description: "Pick reveal moment".to_string(),
                    audio_cues: vec![
                        "pick_reveal_positive".to_string(),
                        "pick_reveal_negative".to_string(),
                    ],
                    duration_hint: "0.5-1s".to_string(),
                },
                ArcPhase {
                    name: "react".to_string(),
                    description: "Reaction to reveal result".to_string(),
                    audio_cues: vec!["pick_reveal_super".to_string()],
                    duration_hint: "1-2s".to_string(),
                },
                ArcPhase {
                    name: "collect".to_string(),
                    description: "Final collection".to_string(),
                    audio_cues: vec!["pick_collect".to_string()],
                    duration_hint: "2-3s".to_string(),
                },
            ],
        },
    );

    arcs.insert(
        "wheel_bonus".to_string(),
        EmotionalArcTemplate {
            mechanic_name: "Wheel Bonus".to_string(),
            phases: vec![
                ArcPhase {
                    name: "spin".to_string(),
                    description: "Wheel spinning at full speed".to_string(),
                    audio_cues: vec!["wheel_spin_loop".to_string()],
                    duration_hint: "2-4s".to_string(),
                },
                ArcPhase {
                    name: "decelerate".to_string(),
                    description: "Wheel slowing down".to_string(),
                    audio_cues: vec!["wheel_tick".to_string(), "wheel_decelerate".to_string()],
                    duration_hint: "3-6s".to_string(),
                },
                ArcPhase {
                    name: "stop".to_string(),
                    description: "Wheel stops on segment".to_string(),
                    audio_cues: vec!["wheel_stop".to_string()],
                    duration_hint: "0.5s".to_string(),
                },
                ArcPhase {
                    name: "prize".to_string(),
                    description: "Prize reveal".to_string(),
                    audio_cues: vec!["wheel_prize".to_string()],
                    duration_hint: "2-3s".to_string(),
                },
            ],
        },
    );

    arcs.insert(
        "megaways".to_string(),
        EmotionalArcTemplate {
            mechanic_name: "Megaways".to_string(),
            phases: vec![
                ArcPhase {
                    name: "expand".to_string(),
                    description: "Reels expanding to max symbols".to_string(),
                    audio_cues: vec!["reel_expand".to_string()],
                    duration_hint: "1-2s".to_string(),
                },
                ArcPhase {
                    name: "chaos".to_string(),
                    description: "Chaotic energy with many ways".to_string(),
                    audio_cues: vec![
                        "ways_counter_tick".to_string(),
                        "mystery_transform".to_string(),
                    ],
                    duration_hint: "variable".to_string(),
                },
                ArcPhase {
                    name: "resolve".to_string(),
                    description: "Reels stop, ways counted".to_string(),
                    audio_cues: vec!["big_reel_stop".to_string()],
                    duration_hint: "1-2s".to_string(),
                },
            ],
        },
    );

    arcs.insert(
        "gamble".to_string(),
        EmotionalArcTemplate {
            mechanic_name: "Gamble / Double Up".to_string(),
            phases: vec![
                ArcPhase {
                    name: "risk".to_string(),
                    description: "Decision moment — risk or collect".to_string(),
                    audio_cues: vec!["tension_loop".to_string()],
                    duration_hint: "variable".to_string(),
                },
                ArcPhase {
                    name: "flip".to_string(),
                    description: "Card flip / reveal".to_string(),
                    audio_cues: vec!["gamble_card_flip".to_string()],
                    duration_hint: "0.5-1s".to_string(),
                },
                ArcPhase {
                    name: "result".to_string(),
                    description: "Win or lose reveal".to_string(),
                    audio_cues: vec!["gamble_win".to_string(), "gamble_lose".to_string()],
                    duration_hint: "1-2s".to_string(),
                },
            ],
        },
    );

    arcs
}

fn default_ducking_rules() -> Vec<DuckingRule> {
    vec![
        DuckingRule {
            source: "vo".to_string(),
            target: "mus".to_string(),
            attenuation_db: -6.0,
            attack_ms: 50.0,
            release_ms: 300.0,
            priority: 1,
        },
        DuckingRule {
            source: "vo".to_string(),
            target: "sfx".to_string(),
            attenuation_db: -3.0,
            attack_ms: 50.0,
            release_ms: 200.0,
            priority: 2,
        },
        DuckingRule {
            source: "sfx".to_string(),
            target: "mus".to_string(),
            attenuation_db: -3.0,
            attack_ms: 30.0,
            release_ms: 200.0,
            priority: 3,
        },
        DuckingRule {
            source: "sfx".to_string(),
            target: "amb".to_string(),
            attenuation_db: -6.0,
            attack_ms: 30.0,
            release_ms: 500.0,
            priority: 4,
        },
        DuckingRule {
            source: "mus".to_string(),
            target: "amb".to_string(),
            attenuation_db: -9.0,
            attack_ms: 100.0,
            release_ms: 500.0,
            priority: 5,
        },
        DuckingRule {
            source: "sfx".to_string(),
            target: "ui".to_string(),
            attenuation_db: -3.0,
            attack_ms: 20.0,
            release_ms: 150.0,
            priority: 6,
        },
    ]
}

impl AdbTemplates {
    /// Get the volatility audio profile for a level.
    pub fn get_volatility_profile(
        &self,
        level: VolatilityLevel,
    ) -> Option<&VolatilityAudioProfile> {
        let key = match level {
            VolatilityLevel::Low => "low",
            VolatilityLevel::Medium => "medium",
            VolatilityLevel::High => "high",
            VolatilityLevel::Extreme => "extreme",
        };
        self.volatility_profiles.get(key)
    }

    /// Get emotional arc template for a mechanic.
    pub fn get_emotional_arc(&self, mechanic_id: &str) -> Option<&EmotionalArcTemplate> {
        self.emotional_arcs.get(mechanic_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_has_10_sections() {
        let templates = AdbTemplates::default();
        assert_eq!(templates.sections.len(), 10);
    }

    #[test]
    fn default_has_4_volatility_profiles() {
        let templates = AdbTemplates::default();
        assert_eq!(templates.volatility_profiles.len(), 4);
    }

    #[test]
    fn default_has_emotional_arcs() {
        let templates = AdbTemplates::default();
        assert!(templates.emotional_arcs.len() >= 8);
    }

    #[test]
    fn volatility_profile_lookup() {
        let templates = AdbTemplates::default();
        let high = templates
            .get_volatility_profile(VolatilityLevel::High)
            .unwrap();
        assert_eq!(high.music_layers, 4);
        assert_eq!(high.dynamic_range_db, 12.0);
    }

    #[test]
    fn ducking_rules_priority_order() {
        let templates = AdbTemplates::default();
        for (i, rule) in templates.ducking_priorities.iter().enumerate() {
            assert_eq!(rule.priority, (i + 1) as u32);
        }
    }
}
