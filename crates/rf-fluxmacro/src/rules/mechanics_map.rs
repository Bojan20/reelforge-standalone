// ============================================================================
// rf-fluxmacro — Mechanics Map
// ============================================================================
// FM-11: GameMechanic → AudioNeeds mapping table.
// Maps 14 game mechanics to their required audio events.
// ============================================================================

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

/// Complete mechanics → audio needs mapping.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MechanicsMap {
    pub mechanics: HashMap<String, MechanicAudioNeeds>,
}

/// Audio needs for a single game mechanic.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MechanicAudioNeeds {
    /// Human-readable mechanic name.
    pub name: String,
    /// Required audio events with descriptions.
    pub events: Vec<AudioEvent>,
    /// Emotional arc for this mechanic.
    pub emotional_arc: EmotionalArc,
    /// Suggested voice count for this mechanic.
    pub suggested_voices: u32,
    /// Whether this mechanic needs a dedicated music layer.
    pub needs_music_layer: bool,
}

/// A required audio event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEvent {
    /// Event identifier (e.g., "jackpot_tiers").
    pub id: String,
    /// Human-readable description.
    pub description: String,
    /// Suggested domain (sfx, mus, ui, vo, amb).
    pub domain: String,
    /// Minimum number of variants recommended.
    pub min_variants: u32,
}

/// Emotional arc template for a mechanic.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmotionalArc {
    /// Arc name.
    pub name: String,
    /// Phases in order.
    pub phases: Vec<String>,
    /// Description of the arc.
    pub description: String,
}

impl Default for MechanicsMap {
    fn default() -> Self {
        let mut mechanics = HashMap::new();

        mechanics.insert(
            "progressive".to_string(),
            MechanicAudioNeeds {
                name: "Progressive Jackpot".to_string(),
                events: vec![
                    AudioEvent { id: "jackpot_tier_1".to_string(), description: "Minor jackpot win".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "jackpot_tier_2".to_string(), description: "Major jackpot win".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "jackpot_tier_3".to_string(), description: "Grand jackpot win".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "jackpot_tier_4".to_string(), description: "Ultimate jackpot win".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "ladder_tick".to_string(), description: "Jackpot ladder increment".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "near_miss_stinger".to_string(), description: "Near miss on jackpot".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "celebration_layer_1".to_string(), description: "Base celebration layer".to_string(), domain: "mus".to_string(), min_variants: 1 },
                    AudioEvent { id: "celebration_layer_2".to_string(), description: "Mid celebration layer".to_string(), domain: "mus".to_string(), min_variants: 1 },
                    AudioEvent { id: "celebration_layer_3".to_string(), description: "Peak celebration layer".to_string(), domain: "mus".to_string(), min_variants: 1 },
                    AudioEvent { id: "jackpot_music_loop".to_string(), description: "Jackpot feature music".to_string(), domain: "mus".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "build_to_climax".to_string(),
                    phases: vec!["build".to_string(), "suspense".to_string(), "peak".to_string(), "celebrate".to_string(), "resolve".to_string()],
                    description: "Long build-up, crescendo before jackpot, explosion, gradual wind-down".to_string(),
                },
                suggested_voices: 6,
                needs_music_layer: true,
            },
        );

        mechanics.insert(
            "mystery_scatter".to_string(),
            MechanicAudioNeeds {
                name: "Mystery Scatter".to_string(),
                events: vec![
                    AudioEvent { id: "mystery_reveal".to_string(), description: "Mystery symbol reveal".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "collection_tick".to_string(), description: "Collection meter increment".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "instant_trigger".to_string(), description: "Instant feature trigger".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "scatter_land".to_string(), description: "Scatter symbol landing".to_string(), domain: "sfx".to_string(), min_variants: 3 },
                    AudioEvent { id: "scatter_anticipation".to_string(), description: "Scatter anticipation build".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "mystery_reveal".to_string(),
                    phases: vec!["anticipation".to_string(), "reveal".to_string(), "react".to_string()],
                    description: "Mystery builds anticipation, reveal creates surprise".to_string(),
                },
                suggested_voices: 4,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "pick_bonus".to_string(),
            MechanicAudioNeeds {
                name: "Pick Bonus".to_string(),
                events: vec![
                    AudioEvent { id: "pick_reveal_positive".to_string(), description: "Positive pick reveal".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "pick_reveal_negative".to_string(), description: "Negative pick reveal (end)".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "pick_reveal_super".to_string(), description: "Super prize pick reveal".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "pick_collect".to_string(), description: "Collect prize fanfare".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "pick_ambient_loop".to_string(), description: "Pick bonus ambient".to_string(), domain: "mus".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "pick_drama".to_string(),
                    phases: vec!["anticipation".to_string(), "reveal".to_string(), "react".to_string(), "collect".to_string()],
                    description: "Each pick has micro-drama: reveal + reaction".to_string(),
                },
                suggested_voices: 3,
                needs_music_layer: true,
            },
        );

        mechanics.insert(
            "hold_and_win".to_string(),
            MechanicAudioNeeds {
                name: "Hold & Win".to_string(),
                events: vec![
                    AudioEvent { id: "hold_lock_impact".to_string(), description: "Symbol lock impact".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "respin_count_tick".to_string(), description: "Respin counter tick".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "coin_land".to_string(), description: "Coin/value landing".to_string(), domain: "sfx".to_string(), min_variants: 3 },
                    AudioEvent { id: "coin_upgrade".to_string(), description: "Coin value upgrade".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "collect_celebration".to_string(), description: "Collection celebration".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "grand_trigger".to_string(), description: "Grand prize trigger".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "lock_tension".to_string(),
                    phases: vec!["lock".to_string(), "tension".to_string(), "collect".to_string(), "relief".to_string()],
                    description: "Each lock increases tension, collect is catharsis".to_string(),
                },
                suggested_voices: 4,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "cascades".to_string(),
            MechanicAudioNeeds {
                name: "Cascades / Tumble".to_string(),
                events: vec![
                    AudioEvent { id: "cascade_drop".to_string(), description: "Symbols dropping/tumbling".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "cascade_clear".to_string(), description: "Winning symbols clearing".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "cascade_chain_1".to_string(), description: "First cascade chain".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "cascade_chain_2".to_string(), description: "Second cascade chain".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "cascade_chain_3_plus".to_string(), description: "Third+ cascade chain".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "cascade_multiplier_tick".to_string(), description: "Multiplier increment".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "chain_escalation".to_string(),
                    phases: vec!["trigger".to_string(), "chain".to_string(), "accelerate".to_string(), "climax".to_string(), "settle".to_string()],
                    description: "Each cascade step accelerates, peak on max chain".to_string(),
                },
                suggested_voices: 4,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "free_spins".to_string(),
            MechanicAudioNeeds {
                name: "Free Spins".to_string(),
                events: vec![
                    AudioEvent { id: "fs_trigger_fanfare".to_string(), description: "Free spins trigger".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "fs_music_loop".to_string(), description: "Free spins music".to_string(), domain: "mus".to_string(), min_variants: 1 },
                    AudioEvent { id: "fs_retrigger".to_string(), description: "Free spins retrigger".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "fs_spin_whoosh".to_string(), description: "Free spin reel whoosh".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "fs_end_summary".to_string(), description: "Free spins end summary".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "feature_journey".to_string(),
                    phases: vec!["fanfare".to_string(), "loop".to_string(), "escalate".to_string(), "resolve".to_string(), "summary".to_string()],
                    description: "Entry fanfare, loop with escalation, summary recap".to_string(),
                },
                suggested_voices: 4,
                needs_music_layer: true,
            },
        );

        mechanics.insert(
            "megaways".to_string(),
            MechanicAudioNeeds {
                name: "Megaways".to_string(),
                events: vec![
                    AudioEvent { id: "reel_expand".to_string(), description: "Reel expansion".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "ways_counter_tick".to_string(), description: "Ways counter increment".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "big_reel_stop".to_string(), description: "Big reel stop impact".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "mystery_transform".to_string(), description: "Mystery symbol transform".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "expand_chaos".to_string(),
                    phases: vec!["expand".to_string(), "chaos".to_string(), "resolve".to_string()],
                    description: "Reel expansion = chaos, resolution on stop".to_string(),
                },
                suggested_voices: 5,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "cluster_pay".to_string(),
            MechanicAudioNeeds {
                name: "Cluster Pay".to_string(),
                events: vec![
                    AudioEvent { id: "cluster_form".to_string(), description: "Cluster forming".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "cluster_grow".to_string(), description: "Cluster growing".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "cluster_clear".to_string(), description: "Cluster clearing".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "cluster_chain".to_string(), description: "Cluster chain reaction".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "grow_burst".to_string(),
                    phases: vec!["form".to_string(), "grow".to_string(), "burst".to_string()],
                    description: "Clusters form, grow, then burst with clearing".to_string(),
                },
                suggested_voices: 3,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "gamble".to_string(),
            MechanicAudioNeeds {
                name: "Gamble / Double Up".to_string(),
                events: vec![
                    AudioEvent { id: "gamble_card_flip".to_string(), description: "Card flip reveal".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "gamble_win".to_string(), description: "Gamble win".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "gamble_lose".to_string(), description: "Gamble lose".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "gamble_collect".to_string(), description: "Collect winnings".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "risk_reward".to_string(),
                    phases: vec!["risk".to_string(), "flip".to_string(), "result".to_string()],
                    description: "Short risk/reward cycles".to_string(),
                },
                suggested_voices: 2,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "wheel_bonus".to_string(),
            MechanicAudioNeeds {
                name: "Wheel Bonus".to_string(),
                events: vec![
                    AudioEvent { id: "wheel_spin_loop".to_string(), description: "Wheel spinning loop".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "wheel_tick".to_string(), description: "Wheel tick per segment".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "wheel_decelerate".to_string(), description: "Wheel decelerating".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "wheel_stop".to_string(), description: "Wheel stop impact".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "wheel_prize".to_string(), description: "Prize reveal fanfare".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "circular_tension".to_string(),
                    phases: vec!["spin".to_string(), "decelerate".to_string(), "stop".to_string(), "prize".to_string()],
                    description: "Circular tension, deceleration, impact on stop".to_string(),
                },
                suggested_voices: 3,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "multiplier".to_string(),
            MechanicAudioNeeds {
                name: "Multiplier".to_string(),
                events: vec![
                    AudioEvent { id: "mult_increment".to_string(), description: "Multiplier increment".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "mult_apply".to_string(), description: "Multiplier applied to win".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "mult_display".to_string(), description: "Multiplier display effect".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "amplify".to_string(),
                    phases: vec!["increment".to_string(), "apply".to_string()],
                    description: "Each increment amplifies excitement".to_string(),
                },
                suggested_voices: 2,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "expanding_wilds".to_string(),
            MechanicAudioNeeds {
                name: "Expanding Wilds".to_string(),
                events: vec![
                    AudioEvent { id: "wild_land".to_string(), description: "Wild symbol landing".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "wild_expand".to_string(), description: "Wild expanding".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "wild_complete".to_string(), description: "Wild expansion complete".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "expand_glow".to_string(),
                    phases: vec!["land".to_string(), "expand".to_string(), "complete".to_string()],
                    description: "Impact, visual expansion, completion glow".to_string(),
                },
                suggested_voices: 2,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "sticky_wilds".to_string(),
            MechanicAudioNeeds {
                name: "Sticky Wilds".to_string(),
                events: vec![
                    AudioEvent { id: "wild_stick".to_string(), description: "Wild sticking/locking".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "wild_persist".to_string(), description: "Wild persisting shimmer".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "wild_clear".to_string(), description: "Wild clearing/releasing".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "lock_release".to_string(),
                    phases: vec!["lock".to_string(), "persist".to_string(), "release".to_string()],
                    description: "Lock with impact, ambient persist, release".to_string(),
                },
                suggested_voices: 2,
                needs_music_layer: false,
            },
        );

        mechanics.insert(
            "trail_bonus".to_string(),
            MechanicAudioNeeds {
                name: "Trail Bonus".to_string(),
                events: vec![
                    AudioEvent { id: "trail_step".to_string(), description: "Trail step movement".to_string(), domain: "sfx".to_string(), min_variants: 2 },
                    AudioEvent { id: "trail_prize".to_string(), description: "Trail prize collection".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "trail_boss".to_string(), description: "Trail boss encounter".to_string(), domain: "sfx".to_string(), min_variants: 1 },
                    AudioEvent { id: "trail_ambient".to_string(), description: "Trail ambient loop".to_string(), domain: "amb".to_string(), min_variants: 1 },
                ],
                emotional_arc: EmotionalArc {
                    name: "journey".to_string(),
                    phases: vec!["step".to_string(), "discover".to_string(), "encounter".to_string()],
                    description: "Step-by-step journey with discoveries and encounters".to_string(),
                },
                suggested_voices: 3,
                needs_music_layer: true,
            },
        );

        Self { mechanics }
    }
}

impl MechanicsMap {
    /// Get audio needs for a mechanic by its ID.
    pub fn get(&self, mechanic_id: &str) -> Option<&MechanicAudioNeeds> {
        self.mechanics.get(mechanic_id)
    }

    /// Total number of unique audio events across all specified mechanics.
    pub fn total_events(&self, mechanic_ids: &[&str]) -> usize {
        mechanic_ids
            .iter()
            .filter_map(|id| self.mechanics.get(*id))
            .map(|m| m.events.len())
            .sum()
    }

    /// Total suggested voices across all specified mechanics.
    pub fn total_suggested_voices(&self, mechanic_ids: &[&str]) -> u32 {
        mechanic_ids
            .iter()
            .filter_map(|id| self.mechanics.get(*id))
            .map(|m| m.suggested_voices)
            .sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_has_14_mechanics() {
        let map = MechanicsMap::default();
        assert_eq!(map.mechanics.len(), 14);
    }

    #[test]
    fn all_mechanics_have_events() {
        let map = MechanicsMap::default();
        for (id, needs) in &map.mechanics {
            assert!(
                !needs.events.is_empty(),
                "Mechanic '{id}' has no events"
            );
        }
    }

    #[test]
    fn all_mechanics_have_arcs() {
        let map = MechanicsMap::default();
        for (id, needs) in &map.mechanics {
            assert!(
                !needs.emotional_arc.phases.is_empty(),
                "Mechanic '{id}' has empty emotional arc"
            );
        }
    }

    #[test]
    fn total_events_calculation() {
        let map = MechanicsMap::default();
        let total = map.total_events(&["progressive", "free_spins"]);
        assert!(total > 10, "Should have many events, got {total}");
    }
}
