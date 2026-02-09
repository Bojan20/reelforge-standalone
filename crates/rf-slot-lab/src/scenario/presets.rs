//! Built-in scenario presets for common demo sequences

use super::{DemoScenario, LoopMode, ScriptedOutcome, ScriptedSpin};

/// Get all built-in presets
pub fn all_presets() -> Vec<DemoScenario> {
    vec![
        win_showcase(),
        free_spins_demo(),
        cascade_demo(),
        jackpot_demo(),
        hold_and_win_demo(),
        stress_test(),
        audio_test(),
        near_miss_showcase(),
    ]
}

/// Win showcase — demonstrates all win tiers from lose to ultra
pub fn win_showcase() -> DemoScenario {
    DemoScenario {
        id: "win_showcase".to_string(),
        name: "Win Showcase".to_string(),
        description: "Demonstrates all win tiers from lose to ultra win".to_string(),
        loop_mode: LoopMode::Once,
        sequence: vec![
            spin(ScriptedOutcome::Lose, "No win - baseline"),
            spin(ScriptedOutcome::SmallWin { ratio: 2.0 }, "Small win 2x"),
            spin(ScriptedOutcome::SmallWin { ratio: 5.0 }, "Small win 5x"),
            spin(ScriptedOutcome::MediumWin { ratio: 10.0 }, "Medium win 10x"),
            spin(ScriptedOutcome::BigWin { ratio: 20.0 }, "Big win 20x"),
            spin(ScriptedOutcome::MegaWin { ratio: 40.0 }, "Mega win 40x"),
            spin(ScriptedOutcome::EpicWin { ratio: 75.0 }, "Epic win 75x"),
            spin(ScriptedOutcome::UltraWin { ratio: 150.0 }, "Ultra win 150x"),
        ],
    }
}

/// Free spins demo — trigger and play through free spins feature
pub fn free_spins_demo() -> DemoScenario {
    DemoScenario {
        id: "free_spins_demo".to_string(),
        name: "Free Spins Demo".to_string(),
        description: "Triggers free spins and plays through the feature".to_string(),
        loop_mode: LoopMode::Once,
        sequence: vec![
            spin(ScriptedOutcome::Lose, "Normal spin"),
            spin(ScriptedOutcome::SmallWin { ratio: 3.0 }, "Small win"),
            spin(
                ScriptedOutcome::TriggerFreeSpins {
                    count: 10,
                    multiplier: 2.0,
                },
                "Trigger 10 free spins with 2x multiplier",
            ),
            // Free spin sequence
            spin_delayed(
                ScriptedOutcome::SmallWin { ratio: 4.0 },
                500.0,
                "FS 1 - Small",
            ),
            spin_delayed(ScriptedOutcome::Lose, 500.0, "FS 2 - Lose"),
            spin_delayed(
                ScriptedOutcome::MediumWin { ratio: 12.0 },
                500.0,
                "FS 3 - Medium",
            ),
            spin_delayed(
                ScriptedOutcome::SmallWin { ratio: 6.0 },
                500.0,
                "FS 4 - Small",
            ),
            spin_delayed(ScriptedOutcome::Lose, 500.0, "FS 5 - Lose"),
            spin_delayed(
                ScriptedOutcome::BigWin { ratio: 25.0 },
                500.0,
                "FS 6 - Big win!",
            ),
            spin_delayed(
                ScriptedOutcome::SmallWin { ratio: 3.0 },
                500.0,
                "FS 7 - Small",
            ),
            spin_delayed(
                ScriptedOutcome::MediumWin { ratio: 15.0 },
                500.0,
                "FS 8 - Medium",
            ),
            spin_delayed(ScriptedOutcome::Lose, 500.0, "FS 9 - Lose"),
            spin_delayed(
                ScriptedOutcome::MegaWin { ratio: 50.0 },
                500.0,
                "FS 10 - Mega finish!",
            ),
        ],
    }
}

/// Cascade demo — demonstrates cascade/tumble mechanics
pub fn cascade_demo() -> DemoScenario {
    DemoScenario {
        id: "cascade_demo".to_string(),
        name: "Cascade Demo".to_string(),
        description: "Shows cascade chains with increasing multipliers".to_string(),
        loop_mode: LoopMode::Once,
        sequence: vec![
            spin(ScriptedOutcome::Lose, "No cascade"),
            spin(ScriptedOutcome::CascadeChain { wins: 2 }, "2-step cascade"),
            spin(ScriptedOutcome::Lose, "Break"),
            spin(ScriptedOutcome::CascadeChain { wins: 4 }, "4-step cascade"),
            spin(ScriptedOutcome::Lose, "Break"),
            spin(
                ScriptedOutcome::CascadeChain { wins: 6 },
                "6-step mega cascade!",
            ),
        ],
    }
}

/// Jackpot demo — shows jackpot triggers
pub fn jackpot_demo() -> DemoScenario {
    DemoScenario {
        id: "jackpot_demo".to_string(),
        name: "Jackpot Demo".to_string(),
        description: "Demonstrates jackpot triggers from mini to grand".to_string(),
        loop_mode: LoopMode::Once,
        sequence: vec![
            spin(ScriptedOutcome::SmallWin { ratio: 3.0 }, "Normal win"),
            spin(
                ScriptedOutcome::TriggerJackpot {
                    tier: "mini".to_string(),
                },
                "Mini jackpot",
            ),
            spin_delayed(ScriptedOutcome::Lose, 3000.0, "Cooldown"),
            spin(
                ScriptedOutcome::TriggerJackpot {
                    tier: "minor".to_string(),
                },
                "Minor jackpot",
            ),
            spin_delayed(ScriptedOutcome::Lose, 3000.0, "Cooldown"),
            spin(
                ScriptedOutcome::TriggerJackpot {
                    tier: "major".to_string(),
                },
                "Major jackpot",
            ),
            spin_delayed(ScriptedOutcome::Lose, 5000.0, "Build-up"),
            spin(
                ScriptedOutcome::TriggerJackpot {
                    tier: "grand".to_string(),
                },
                "GRAND JACKPOT!",
            ),
        ],
    }
}

/// Hold and Win demo
pub fn hold_and_win_demo() -> DemoScenario {
    DemoScenario {
        id: "hold_and_win_demo".to_string(),
        name: "Hold & Win Demo".to_string(),
        description: "Triggers and plays through Hold & Win feature".to_string(),
        loop_mode: LoopMode::Once,
        sequence: vec![
            spin(ScriptedOutcome::SmallWin { ratio: 2.0 }, "Normal win"),
            spin(ScriptedOutcome::TriggerHoldAndWin, "Trigger Hold & Win"),
            // Respin sequence
            spin_delayed(
                ScriptedOutcome::SmallWin { ratio: 5.0 },
                800.0,
                "Respin - 2 coins land",
            ),
            spin_delayed(ScriptedOutcome::Lose, 800.0, "Respin - nothing"),
            spin_delayed(
                ScriptedOutcome::SmallWin { ratio: 3.0 },
                800.0,
                "Respin - 1 coin",
            ),
            spin_delayed(ScriptedOutcome::Lose, 800.0, "Respin - nothing"),
            spin_delayed(
                ScriptedOutcome::Lose,
                800.0,
                "Respin - nothing (0 respins left)",
            ),
            spin_delayed(
                ScriptedOutcome::BigWin { ratio: 30.0 },
                1000.0,
                "Feature complete - total win",
            ),
        ],
    }
}

/// Stress test — rapid fire for performance testing
pub fn stress_test() -> DemoScenario {
    let mut sequence = Vec::new();

    // 100 rapid spins
    for i in 0..100 {
        let outcome = match i % 10 {
            0 => ScriptedOutcome::MediumWin { ratio: 15.0 },
            1..=3 => ScriptedOutcome::SmallWin {
                ratio: (i % 5 + 2) as f64,
            },
            _ => ScriptedOutcome::Lose,
        };
        sequence.push(ScriptedSpin {
            outcome,
            delay_before_ms: Some(100.0), // Fast!
            note: Some(format!("Stress #{}", i + 1)),
        });
    }

    DemoScenario {
        id: "stress_test".to_string(),
        name: "Stress Test".to_string(),
        description: "100 rapid spins for performance testing".to_string(),
        loop_mode: LoopMode::Once,
        sequence,
    }
}

/// Audio test — specifically for audio sync testing
pub fn audio_test() -> DemoScenario {
    DemoScenario {
        id: "audio_test".to_string(),
        name: "Audio Test".to_string(),
        description: "Designed for testing audio sync and timing".to_string(),
        loop_mode: LoopMode::Forever, // Loop for extended testing
        sequence: vec![
            spin_delayed(ScriptedOutcome::Lose, 2000.0, "Silence baseline"),
            spin_delayed(
                ScriptedOutcome::SmallWin { ratio: 3.0 },
                1500.0,
                "Small win audio",
            ),
            spin_delayed(ScriptedOutcome::Lose, 1500.0, "Return to silence"),
            spin_delayed(
                ScriptedOutcome::BigWin { ratio: 25.0 },
                1500.0,
                "Big win fanfare",
            ),
            spin_delayed(ScriptedOutcome::Lose, 3000.0, "Let celebration finish"),
            spin_delayed(
                ScriptedOutcome::CascadeChain { wins: 3 },
                1500.0,
                "Cascade sounds",
            ),
            spin_delayed(ScriptedOutcome::Lose, 2000.0, "Reset"),
        ],
    }
}

/// Near miss showcase
pub fn near_miss_showcase() -> DemoScenario {
    DemoScenario {
        id: "near_miss_showcase".to_string(),
        name: "Near Miss Showcase".to_string(),
        description: "Shows near-miss anticipation scenarios".to_string(),
        loop_mode: LoopMode::Once,
        sequence: vec![
            spin(ScriptedOutcome::Lose, "Normal lose"),
            spin(
                ScriptedOutcome::NearMiss {
                    feature: "free_spins".to_string(),
                },
                "Almost free spins (2 scatters)",
            ),
            spin(ScriptedOutcome::Lose, "Break"),
            spin(
                ScriptedOutcome::NearMiss {
                    feature: "jackpot".to_string(),
                },
                "Almost jackpot (4 coins)",
            ),
            spin(ScriptedOutcome::SmallWin { ratio: 5.0 }, "Consolation win"),
            spin(
                ScriptedOutcome::NearMiss {
                    feature: "free_spins".to_string(),
                },
                "SO close to free spins!",
            ),
            spin(
                ScriptedOutcome::TriggerFreeSpins {
                    count: 8,
                    multiplier: 1.0,
                },
                "Finally triggers!",
            ),
        ],
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

fn spin(outcome: ScriptedOutcome, note: &str) -> ScriptedSpin {
    ScriptedSpin {
        outcome,
        delay_before_ms: None,
        note: Some(note.to_string()),
    }
}

fn spin_delayed(outcome: ScriptedOutcome, delay_ms: f64, note: &str) -> ScriptedSpin {
    ScriptedSpin {
        outcome,
        delay_before_ms: Some(delay_ms),
        note: Some(note.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_all_presets_valid() {
        let presets = all_presets();
        assert!(!presets.is_empty());

        for preset in presets {
            assert!(!preset.id.is_empty());
            assert!(!preset.name.is_empty());
            assert!(!preset.sequence.is_empty());
        }
    }

    #[test]
    fn test_win_showcase_tiers() {
        let showcase = win_showcase();
        assert_eq!(showcase.sequence.len(), 8); // lose + 7 win tiers
    }

    #[test]
    fn test_stress_test_count() {
        let stress = stress_test();
        assert_eq!(stress.sequence.len(), 100);
    }

    #[test]
    fn test_audio_test_loops() {
        let audio = audio_test();
        assert_eq!(audio.loop_mode, LoopMode::Forever);
    }
}
