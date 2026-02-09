//! Event detector — detects and classifies events from samples

use serde_json::Value;
use std::collections::HashMap;

use super::analyzer::AnalyzedStructure;
use super::DetectedEvent;

/// Common event name mappings to stages
const EVENT_STAGE_MAPPINGS: &[(&str, &str)] = &[
    // Spin lifecycle
    ("spin_start", "SpinStart"),
    ("spinstart", "SpinStart"),
    ("SPIN_START", "SpinStart"),
    ("startSpin", "SpinStart"),
    ("begin_spin", "SpinStart"),
    ("spin_end", "SpinEnd"),
    ("spinend", "SpinEnd"),
    ("SPIN_END", "SpinEnd"),
    ("endSpin", "SpinEnd"),
    ("spin_complete", "SpinEnd"),
    ("spinComplete", "SpinEnd"),
    ("SPIN_RESULT", "SpinEnd"),
    // Reels
    ("reel_stop", "ReelStop"),
    ("reelstop", "ReelStop"),
    ("REEL_STOP", "ReelStop"),
    ("reelStopped", "ReelStop"),
    ("reel_stopped", "ReelStop"),
    ("reel_spin", "ReelSpinning"),
    // Anticipation
    ("anticipation", "AnticipationOn"),
    ("anticipation_start", "AnticipationOn"),
    ("ANTICIPATION", "AnticipationOn"),
    ("anticipation_end", "AnticipationOff"),
    // Wins
    ("win", "WinPresent"),
    ("WIN", "WinPresent"),
    ("win_present", "WinPresent"),
    ("show_win", "WinPresent"),
    ("win_line", "WinLineShow"),
    ("winLine", "WinLineShow"),
    ("WIN_LINE", "WinLineShow"),
    // Big wins
    ("big_win", "BigWinTier"),
    ("bigwin", "BigWinTier"),
    ("BIG_WIN", "BigWinTier"),
    ("mega_win", "BigWinTier"),
    ("epic_win", "BigWinTier"),
    ("big_win_end", "BigWinEnd"),
    // Rollup
    ("rollup", "RollupStart"),
    ("rollup_start", "RollupStart"),
    ("ROLLUP", "RollupStart"),
    ("rollup_end", "RollupEnd"),
    ("count_up", "RollupStart"),
    // Features
    ("feature_enter", "FeatureEnter"),
    ("feature_start", "FeatureEnter"),
    ("FEATURE_START", "FeatureEnter"),
    ("bonus_start", "FeatureEnter"),
    ("free_spins_start", "FeatureEnter"),
    ("feature_exit", "FeatureExit"),
    ("feature_end", "FeatureExit"),
    ("FEATURE_END", "FeatureExit"),
    ("bonus_end", "FeatureExit"),
    // Free spins
    ("free_spin", "FreeSpinStart"),
    ("free_spin_start", "FreeSpinStart"),
    ("FREE_SPIN", "FreeSpinStart"),
    ("free_spin_end", "FreeSpinEnd"),
    ("freespin_awarded", "FreeSpinsAwarded"),
    // Cascade
    ("cascade", "CascadeStep"),
    ("tumble", "CascadeStep"),
    ("avalanche", "CascadeStep"),
    ("TUMBLE", "CascadeStep"),
    // Gamble
    ("gamble_start", "GambleStart"),
    ("gamble", "GambleStart"),
    ("GAMBLE", "GambleStart"),
    ("gamble_result", "GambleResult"),
    ("gamble_end", "GambleEnd"),
    // Jackpot
    ("jackpot", "JackpotWin"),
    ("JACKPOT", "JackpotWin"),
    ("jackpot_win", "JackpotWin"),
    // Idle
    ("idle", "IdleStart"),
    ("IDLE", "IdleStart"),
    // Symbols
    ("wild_expand", "SymbolTransform"),
    ("symbol_upgrade", "SymbolTransform"),
    ("scatter_collect", "ScatterCollect"),
    ("scatter", "ScatterCollect"),
    // Multiplier
    ("multiplier", "MultiplierChange"),
    ("mult_change", "MultiplierChange"),
    ("MULTIPLIER", "MultiplierChange"),
];

/// Detect events from samples
pub fn detect_events(samples: &[Value], structure: &AnalyzedStructure) -> Vec<DetectedEvent> {
    let mut event_counts: HashMap<String, (usize, Option<Value>)> = HashMap::new();

    // Find event type field
    let event_type_paths = find_event_type_paths(structure);

    for sample in samples {
        // Handle array of events
        let events: Vec<&Value> = if let Some(arr) = sample.as_array() {
            arr.iter().collect()
        } else {
            vec![sample]
        };

        for event in events {
            // Try each potential event type path
            for path in &event_type_paths {
                if let Some(event_name) = get_string_at_path(event, path) {
                    let entry = event_counts.entry(event_name.clone()).or_insert((0, None));
                    entry.0 += 1;
                    if entry.1.is_none() {
                        entry.1 = Some(event.clone());
                    }
                    break;
                }
            }
        }
    }

    // Convert to detected events
    let mut detected: Vec<DetectedEvent> = event_counts
        .into_iter()
        .map(|(event_name, (count, sample))| {
            let suggested_stage = find_stage_mapping(&event_name);
            DetectedEvent {
                event_name,
                suggested_stage,
                sample_count: count,
                sample_payload: sample,
            }
        })
        .collect();

    // Sort by count (most common first)
    detected.sort_by(|a, b| b.sample_count.cmp(&a.sample_count));

    detected
}

/// Find paths that likely contain event type
fn find_event_type_paths(structure: &AnalyzedStructure) -> Vec<String> {
    let mut paths = Vec::new();

    // Common event type field names
    let event_field_names = [
        "type",
        "event",
        "eventType",
        "event_type",
        "name",
        "action",
        "command",
        "msg_type",
        "message_type",
    ];

    for field_name in &event_field_names {
        // Check root level
        if structure.root_keys.contains(*field_name) {
            paths.push(field_name.to_string());
        }

        // Check nested (data.type, event.type, etc.)
        for path in &structure.field_paths {
            if path.ends_with(field_name) {
                paths.push(path.clone());
            }
        }
    }

    // Deduplicate
    paths.sort();
    paths.dedup();

    paths
}

/// Find stage mapping for event name
fn find_stage_mapping(event_name: &str) -> Option<String> {
    // Direct lookup
    for (event, stage) in EVENT_STAGE_MAPPINGS {
        if event_name.eq_ignore_ascii_case(event) {
            return Some(stage.to_string());
        }
    }

    // Fuzzy matching
    let lower = event_name.to_lowercase();

    // Spin detection
    if lower.contains("spin") && (lower.contains("start") || lower.contains("begin")) {
        return Some("SpinStart".to_string());
    }
    if lower.contains("spin")
        && (lower.contains("end") || lower.contains("complete") || lower.contains("result"))
    {
        return Some("SpinEnd".to_string());
    }

    // Reel detection
    if lower.contains("reel") && lower.contains("stop") {
        return Some("ReelStop".to_string());
    }

    // Win detection
    if lower.contains("win") && !lower.contains("big") && !lower.contains("mega") {
        return Some("WinPresent".to_string());
    }
    if lower.contains("big") && lower.contains("win") {
        return Some("BigWinTier".to_string());
    }

    // Feature detection
    if lower.contains("feature") || lower.contains("bonus") {
        if lower.contains("start") || lower.contains("enter") || lower.contains("trigger") {
            return Some("FeatureEnter".to_string());
        }
        if lower.contains("end") || lower.contains("exit") || lower.contains("complete") {
            return Some("FeatureExit".to_string());
        }
    }

    // Free spins
    if lower.contains("free") && lower.contains("spin") {
        return Some("FreeSpinStart".to_string());
    }

    // Cascade/tumble
    if lower.contains("cascade") || lower.contains("tumble") || lower.contains("avalanche") {
        return Some("CascadeStep".to_string());
    }

    // Gamble
    if lower.contains("gamble") || lower.contains("double") {
        return Some("GambleStart".to_string());
    }

    // Jackpot
    if lower.contains("jackpot") {
        return Some("JackpotWin".to_string());
    }

    None
}

/// Get string value at JSON path
fn get_string_at_path(json: &Value, path: &str) -> Option<String> {
    let parts: Vec<&str> = path.split('.').collect();
    let mut current = json;

    for part in parts {
        current = current.get(part)?;
    }

    current.as_str().map(|s| s.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_find_stage_mapping() {
        assert_eq!(
            find_stage_mapping("spin_start"),
            Some("SpinStart".to_string())
        );
        assert_eq!(
            find_stage_mapping("SPIN_RESULT"),
            Some("SpinEnd".to_string())
        );
        assert_eq!(
            find_stage_mapping("reel_stop"),
            Some("ReelStop".to_string())
        );
        assert_eq!(
            find_stage_mapping("big_win"),
            Some("BigWinTier".to_string())
        );
    }

    #[test]
    fn test_fuzzy_mapping() {
        assert_eq!(
            find_stage_mapping("begin_game_spin"),
            Some("SpinStart".to_string())
        );
        assert_eq!(
            find_stage_mapping("gameSpinComplete"),
            Some("SpinEnd".to_string())
        );
        assert_eq!(
            find_stage_mapping("bonusFeatureTrigger"),
            Some("FeatureEnter".to_string())
        );
    }

    #[test]
    fn test_detect_events() {
        let samples = vec![
            json!({ "type": "spin_start", "ts": 1000 }),
            json!({ "type": "spin_start", "ts": 2000 }),
            json!({ "type": "reel_stop", "reel": 0 }),
            json!({ "type": "win", "amount": 100 }),
        ];

        let structure = super::super::analyzer::analyze_structure(&samples);
        let events = detect_events(&samples, &structure);

        assert!(!events.is_empty());

        let spin_start = events.iter().find(|e| e.event_name == "spin_start");
        assert!(spin_start.is_some());
        assert_eq!(spin_start.unwrap().sample_count, 2);
        assert_eq!(
            spin_start.unwrap().suggested_stage,
            Some("SpinStart".to_string())
        );
    }
}
