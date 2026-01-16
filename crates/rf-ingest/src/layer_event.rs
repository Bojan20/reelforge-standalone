//! Layer 1: Direct Event Ingest
//!
//! Parses engine event logs where events have explicit names.

use rf_stage::{Stage, StageEvent, StagePayload, StageTrace};
use serde_json::Value;

use crate::adapter::AdapterError;
use crate::config::AdapterConfig;

/// Parse a complete JSON document with events into a StageTrace
pub fn parse_with_config(json: &Value, config: &AdapterConfig) -> Result<StageTrace, AdapterError> {
    let game_id = extract_string(json, "game_id").unwrap_or_else(|| "unknown".to_string());
    let spin_id = extract_string(json, "spin_id");

    let mut trace = StageTrace::new(
        spin_id.clone().unwrap_or_else(uuid_simple),
        game_id,
    );

    if let Some(sid) = spin_id {
        trace = trace.with_spin(sid);
    }

    trace = trace.with_adapter(config.adapter_id.clone());

    // Find events array
    let events = find_events_array(json, config)?;

    for event_value in events {
        if let Some(stage_event) = parse_single_event(event_value, config)? {
            trace.push(stage_event);
        }
    }

    Ok(trace)
}

/// Parse a single event value into a StageEvent
pub fn parse_single_event(
    event: &Value,
    config: &AdapterConfig,
) -> Result<Option<StageEvent>, AdapterError> {
    // Get event name
    let event_name = extract_event_name(event, config)?;

    // Look up in mapping
    let stage_str = match config.get_stage(&event_name) {
        Some(s) => s,
        None => {
            // Unknown event - skip or log
            return Ok(None);
        }
    };

    // Parse stage from string
    let stage = parse_stage_string(stage_str, event)?;

    // Extract timestamp
    let timestamp = extract_timestamp(event, config);

    // Build payload
    let payload = extract_payload(event, config);

    let mut stage_event = StageEvent::with_payload(stage, timestamp, payload);
    stage_event.source_event = Some(event_name);

    Ok(Some(stage_event))
}

/// Find the events array in the JSON
fn find_events_array<'a>(
    json: &'a Value,
    config: &AdapterConfig,
) -> Result<Vec<&'a Value>, AdapterError> {
    // Try configured path first
    if let Some(path) = &config.payload_paths.events_path {
        if let Some(arr) = json_path(json, path) {
            if let Some(arr) = arr.as_array() {
                return Ok(arr.iter().collect());
            }
        }
    }

    // Try common paths
    for path in &["events", "event_log", "log", "data.events", "result.events"] {
        if let Some(arr) = json_path(json, path) {
            if let Some(arr) = arr.as_array() {
                return Ok(arr.iter().collect());
            }
        }
    }

    // If JSON is an array, use it directly
    if let Some(arr) = json.as_array() {
        return Ok(arr.iter().collect());
    }

    // Single event?
    if json.get("name").is_some() || json.get("event").is_some() || json.get("type").is_some() {
        return Ok(vec![json]);
    }

    Err(AdapterError::MissingField("events array".to_string()))
}

/// Extract event name from event object
fn extract_event_name(event: &Value, config: &AdapterConfig) -> Result<String, AdapterError> {
    // Try configured path
    if let Some(path) = &config.payload_paths.event_name_path {
        if let Some(name) = json_path(event, path).and_then(|v| v.as_str()) {
            return Ok(name.to_string());
        }
    }

    // Try common fields
    for field in &["name", "event", "type", "event_name", "eventName", "cmd"] {
        if let Some(name) = event.get(field).and_then(|v| v.as_str()) {
            return Ok(name.to_string());
        }
    }

    Err(AdapterError::MissingField("event name".to_string()))
}

/// Extract timestamp from event
fn extract_timestamp(event: &Value, config: &AdapterConfig) -> f64 {
    // Try configured path
    if let Some(path) = &config.payload_paths.timestamp_path {
        if let Some(ts) = json_path(event, path).and_then(|v| v.as_f64()) {
            return ts;
        }
    }

    // Try common fields
    for field in &["time", "timestamp", "ts", "time_ms", "timeMs"] {
        if let Some(ts) = event.get(field).and_then(|v| v.as_f64()) {
            return ts;
        }
    }

    0.0
}

/// Extract payload data from event
fn extract_payload(event: &Value, config: &AdapterConfig) -> StagePayload {
    let mut payload = StagePayload::default();

    // Win amount
    if let Some(path) = &config.payload_paths.win_amount_path {
        payload.win_amount = json_path(event, path).and_then(|v| v.as_f64());
    } else {
        payload.win_amount = extract_number(event, &["win", "win_amount", "amount", "total_win"]);
    }

    // Bet amount
    if let Some(path) = &config.payload_paths.bet_amount_path {
        payload.bet_amount = json_path(event, path).and_then(|v| v.as_f64());
    } else {
        payload.bet_amount = extract_number(event, &["bet", "bet_amount", "total_bet", "stake"]);
    }

    // Symbol ID
    payload.symbol_id = extract_number(event, &["symbol", "symbol_id", "symbolId"])
        .map(|n| n as u32);

    // Symbol name
    payload.symbol_name = extract_string(event, "symbol_name")
        .or_else(|| extract_string(event, "symbolName"));

    // Multiplier
    payload.multiplier = extract_number(event, &["multiplier", "mult", "x"]);

    // Spins remaining
    payload.spins_remaining = extract_number(event, &["spins_remaining", "remaining", "spins_left"])
        .map(|n| n as u32);

    payload
}

/// Parse stage string to Stage enum
fn parse_stage_string(stage_str: &str, event: &Value) -> Result<Stage, AdapterError> {
    // Handle parameterized stages
    if stage_str.contains('{') {
        return parse_parameterized_stage(stage_str, event);
    }

    // Simple stages
    match stage_str {
        "SpinStart" => Ok(Stage::SpinStart),
        "SpinEnd" => Ok(Stage::SpinEnd),
        "EvaluateWins" => Ok(Stage::EvaluateWins),
        "WinPresent" => Ok(Stage::WinPresent {
            win_amount: extract_number(event, &["win", "amount"]).unwrap_or(0.0),
            line_count: extract_number(event, &["lines", "line_count"])
                .map(|n| n as u8)
                .unwrap_or(0),
        }),
        "RollupStart" => Ok(Stage::RollupStart {
            target_amount: extract_number(event, &["target", "amount"]).unwrap_or(0.0),
            start_amount: extract_number(event, &["start", "from"]).unwrap_or(0.0),
        }),
        "RollupEnd" => Ok(Stage::RollupEnd {
            final_amount: extract_number(event, &["final", "amount"]).unwrap_or(0.0),
        }),
        "FeatureExit" => Ok(Stage::FeatureExit {
            total_win: extract_number(event, &["total_win", "win"]).unwrap_or(0.0),
        }),
        "CascadeStart" => Ok(Stage::CascadeStart),
        "BonusEnter" => Ok(Stage::BonusEnter { bonus_name: None }),
        "BonusExit" => Ok(Stage::BonusExit { total_win: 0.0 }),
        "JackpotEnd" => Ok(Stage::JackpotEnd),
        "IdleStart" => Ok(Stage::IdleStart),
        "IdleLoop" => Ok(Stage::IdleLoop),
        "MenuClose" => Ok(Stage::MenuClose),
        _ => Err(AdapterError::UnknownEvent(format!(
            "Cannot parse stage: {}",
            stage_str
        ))),
    }
}

/// Parse parameterized stage like "ReelStop { reel_index: 0 }"
fn parse_parameterized_stage(stage_str: &str, event: &Value) -> Result<Stage, AdapterError> {
    // Extract base name and params
    let parts: Vec<&str> = stage_str.splitn(2, '{').collect();
    let base_name = parts[0].trim();

    match base_name {
        "ReelStop" => {
            let reel_index = extract_param_or_event(stage_str, "reel_index", event)
                .map(|n| n as u8)
                .unwrap_or(0);
            Ok(Stage::ReelStop {
                reel_index,
                symbols: vec![],
            })
        }
        "ReelSpinning" => {
            let reel_index = extract_param_or_event(stage_str, "reel_index", event)
                .map(|n| n as u8)
                .unwrap_or(0);
            Ok(Stage::ReelSpinning { reel_index })
        }
        "AnticipationOn" => {
            let reel_index = extract_param_or_event(stage_str, "reel_index", event)
                .map(|n| n as u8)
                .unwrap_or(0);
            Ok(Stage::AnticipationOn {
                reel_index,
                reason: None,
            })
        }
        "AnticipationOff" => {
            let reel_index = extract_param_or_event(stage_str, "reel_index", event)
                .map(|n| n as u8)
                .unwrap_or(0);
            Ok(Stage::AnticipationOff { reel_index })
        }
        "BigWinTier" => {
            let tier_str = extract_param_string(stage_str, "tier").unwrap_or("win");
            let tier = match tier_str {
                "Win" | "win" => rf_stage::BigWinTier::Win,
                "BigWin" | "big_win" => rf_stage::BigWinTier::BigWin,
                "MegaWin" | "mega_win" => rf_stage::BigWinTier::MegaWin,
                "EpicWin" | "epic_win" => rf_stage::BigWinTier::EpicWin,
                "UltraWin" | "ultra_win" => rf_stage::BigWinTier::UltraWin,
                _ => rf_stage::BigWinTier::Win,
            };
            Ok(Stage::BigWinTier {
                tier,
                amount: extract_number(event, &["amount", "win"]).unwrap_or(0.0),
            })
        }
        "FeatureEnter" => {
            let feature_str = extract_param_string(stage_str, "feature_type").unwrap_or("Custom");
            let feature_type = match feature_str {
                "FreeSpins" => rf_stage::FeatureType::FreeSpins,
                "BonusGame" => rf_stage::FeatureType::BonusGame,
                "PickBonus" => rf_stage::FeatureType::PickBonus,
                "WheelBonus" => rf_stage::FeatureType::WheelBonus,
                "Respin" => rf_stage::FeatureType::Respin,
                "HoldAndSpin" => rf_stage::FeatureType::HoldAndSpin,
                _ => rf_stage::FeatureType::Custom(0),
            };
            Ok(Stage::FeatureEnter {
                feature_type,
                total_steps: None,
                multiplier: 1.0,
            })
        }
        "FeatureStep" => {
            let step_index = extract_param_or_event(stage_str, "step_index", event)
                .map(|n| n as u32)
                .unwrap_or(0);
            Ok(Stage::FeatureStep {
                step_index,
                steps_remaining: None,
                current_multiplier: 1.0,
            })
        }
        "CascadeStep" => {
            let step_index = extract_param_or_event(stage_str, "step_index", event)
                .map(|n| n as u32)
                .unwrap_or(0);
            Ok(Stage::CascadeStep {
                step_index,
                multiplier: 1.0,
            })
        }
        _ => Err(AdapterError::UnknownEvent(format!(
            "Unknown parameterized stage: {}",
            base_name
        ))),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Simple JSONPath-like extraction (supports dot notation)
fn json_path<'a>(json: &'a Value, path: &str) -> Option<&'a Value> {
    let parts: Vec<&str> = path.split('.').collect();
    let mut current = json;

    for part in parts {
        // Handle array index like "events[0]"
        if let Some(idx_start) = part.find('[') {
            let key = &part[..idx_start];
            let idx_str = &part[idx_start + 1..part.len() - 1];
            let idx: usize = idx_str.parse().ok()?;

            current = current.get(key)?.get(idx)?;
        } else {
            current = current.get(part)?;
        }
    }

    Some(current)
}

/// Extract string from JSON
fn extract_string(json: &Value, field: &str) -> Option<String> {
    json.get(field).and_then(|v| v.as_str()).map(String::from)
}

/// Extract number from JSON, trying multiple field names
fn extract_number(json: &Value, fields: &[&str]) -> Option<f64> {
    for field in fields {
        if let Some(v) = json.get(*field) {
            if let Some(n) = v.as_f64() {
                return Some(n);
            }
            if let Some(n) = v.as_i64() {
                return Some(n as f64);
            }
        }
    }
    None
}

/// Extract parameter from stage string or fall back to event data
fn extract_param_or_event(stage_str: &str, param: &str, event: &Value) -> Option<f64> {
    // Try to find in stage string like "reel_index: 0"
    if let Some(param_value) = extract_param_number(stage_str, param) {
        return Some(param_value);
    }

    // Try to find $param placeholder
    if stage_str.contains(&format!("${}", param)) {
        return extract_number(event, &[param]);
    }

    // Fall back to event data
    extract_number(event, &[param])
}

/// Extract numeric parameter from stage string
fn extract_param_number(stage_str: &str, param: &str) -> Option<f64> {
    let pattern = format!("{}: ", param);
    if let Some(start) = stage_str.find(&pattern) {
        let value_start = start + pattern.len();
        let rest = &stage_str[value_start..];
        let end = rest
            .find(|c: char| !c.is_numeric() && c != '.' && c != '-')
            .unwrap_or(rest.len());
        rest[..end].parse().ok()
    } else {
        None
    }
}

/// Extract string parameter from stage string
fn extract_param_string<'a>(stage_str: &'a str, _param: &str) -> Option<&'a str> {
    let pattern = format!("{}: ", _param);
    if let Some(start) = stage_str.find(&pattern) {
        let value_start = start + pattern.len();
        let rest = &stage_str[value_start..];
        let end = rest
            .find([',', '}', ' '])
            .unwrap_or(rest.len());
        Some(&rest[..end])
    } else {
        None
    }
}

/// Generate simple UUID-like string
fn uuid_simple() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!("trace-{:x}", now)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_simple_events() {
        let mut config = AdapterConfig::new("test", "Test", "TestEngine");
        config.map_event("spin_start", "SpinStart");
        config.map_event("spin_end", "SpinEnd");

        let json = serde_json::json!({
            "game_id": "test_game",
            "events": [
                { "name": "spin_start", "time": 0 },
                { "name": "spin_end", "time": 1000 }
            ]
        });

        let trace = parse_with_config(&json, &config).unwrap();
        assert_eq!(trace.events.len(), 2);
        assert_eq!(trace.events[0].stage.type_name(), "spin_start");
        assert_eq!(trace.events[1].stage.type_name(), "spin_end");
    }

    #[test]
    fn test_parse_parameterized_stage() {
        let mut config = AdapterConfig::new("test", "Test", "TestEngine");
        config.map_event("reel_stop_0", "ReelStop { reel_index: 0 }");
        config.map_event("reel_stop_1", "ReelStop { reel_index: 1 }");

        let json = serde_json::json!({
            "events": [
                { "name": "reel_stop_0", "time": 500 },
                { "name": "reel_stop_1", "time": 650 }
            ]
        });

        let trace = parse_with_config(&json, &config).unwrap();
        assert_eq!(trace.events.len(), 2);

        if let Stage::ReelStop { reel_index, .. } = &trace.events[0].stage {
            assert_eq!(*reel_index, 0);
        } else {
            panic!("Expected ReelStop");
        }
    }

    #[test]
    fn test_json_path() {
        let json = serde_json::json!({
            "data": {
                "result": {
                    "win": 100
                }
            }
        });

        let value = json_path(&json, "data.result.win");
        assert_eq!(value.and_then(|v| v.as_f64()), Some(100.0));
    }
}
