//! Layer 2: Snapshot Diff Ingest
//!
//! Derives STAGES by comparing consecutive game state snapshots.
//! Used when engine doesn't emit discrete events but does provide state dumps.

use serde_json::Value;

use crate::adapter::AdapterError;
use crate::config::AdapterConfig;
use rf_stage::event::StageEvent;
use rf_stage::stage::Stage;
use rf_stage::taxonomy::{BigWinTier, FeatureType};

/// State snapshot representing a point-in-time game state
#[derive(Debug, Clone, Default)]
pub struct GameSnapshot {
    /// Raw JSON state
    pub raw: Value,

    /// Extracted state fields
    pub state: ExtractedState,

    /// Timestamp when snapshot was taken
    pub timestamp_ms: f64,
}

/// Extracted state from snapshot for comparison
#[derive(Debug, Clone, Default)]
pub struct ExtractedState {
    /// Current balance
    pub balance: Option<f64>,

    /// Last win amount
    pub win_amount: Option<f64>,

    /// Reel positions (per reel)
    pub reel_positions: Vec<Vec<u32>>,

    /// Is spinning
    pub is_spinning: bool,

    /// Reels that have stopped (indices)
    pub stopped_reels: Vec<u8>,

    /// Active feature (if any)
    pub active_feature: Option<String>,

    /// Feature step (if in feature)
    pub feature_step: Option<u32>,

    /// Total feature steps
    pub feature_total_steps: Option<u32>,

    /// Is in big win celebration
    pub big_win_active: bool,

    /// Big win tier
    pub big_win_tier: Option<String>,

    /// Multiplier
    pub multiplier: Option<f64>,

    /// Win lines count
    pub win_lines: Option<u8>,
}

/// Snapshot diff result
#[derive(Debug, Clone)]
pub struct SnapshotDiff {
    /// Derived stages from the diff
    pub stages: Vec<StageEvent>,

    /// Previous state
    pub from: ExtractedState,

    /// Current state
    pub to: ExtractedState,
}

/// Parse snapshots using config
pub fn parse_snapshots(
    snapshots: &[Value],
    config: &AdapterConfig,
) -> Result<Vec<StageEvent>, AdapterError> {
    if snapshots.is_empty() {
        return Ok(vec![]);
    }

    let mut events = Vec::new();
    let mut previous: Option<GameSnapshot> = None;

    for (i, snapshot_json) in snapshots.iter().enumerate() {
        let snapshot = extract_snapshot(snapshot_json, config, i as f64 * 100.0)?;

        if let Some(prev) = previous {
            let diff = compute_diff(&prev, &snapshot)?;
            events.extend(diff.stages);
        } else {
            // First snapshot - check if we're already in a state
            if snapshot.state.is_spinning {
                events.push(StageEvent::new(Stage::SpinStart, snapshot.timestamp_ms));
            }
        }

        previous = Some(snapshot);
    }

    Ok(events)
}

/// Extract snapshot from JSON using config paths
fn extract_snapshot(
    json: &Value,
    config: &AdapterConfig,
    default_timestamp: f64,
) -> Result<GameSnapshot, AdapterError> {
    let paths = &config.snapshot_paths;
    let mut state = ExtractedState::default();

    // Extract balance
    if let Some(path) = &paths.balance_path {
        state.balance = get_json_number(json, path);
    }

    // Extract win amount
    if let Some(path) = &paths.win_path {
        state.win_amount = get_json_number(json, path);
    }

    // Extract reel positions
    if let Some(path) = &paths.reels_path {
        if let Some(reels) = get_json_value(json, path) {
            if let Some(arr) = reels.as_array() {
                state.reel_positions = arr
                    .iter()
                    .filter_map(|r| {
                        r.as_array().map(|symbols| {
                            symbols
                                .iter()
                                .filter_map(|s| s.as_u64().map(|v| v as u32))
                                .collect()
                        })
                    })
                    .collect();
            }
        }
    }

    // Extract feature info
    if let Some(path) = &paths.feature_active_path {
        state.active_feature = get_json_string(json, path);
    }

    // Infer spinning state from reels data
    // If we have reels data but not all reels have stopped, we're spinning
    if !state.reel_positions.is_empty() {
        // Assume spinning if balance decreased from previous (heuristic)
        state.is_spinning = false; // Will be set by diff logic
    }

    Ok(GameSnapshot {
        raw: json.clone(),
        state,
        timestamp_ms: default_timestamp,
    })
}

/// Compute diff between two snapshots and derive stages
fn compute_diff(prev: &GameSnapshot, curr: &GameSnapshot) -> Result<SnapshotDiff, AdapterError> {
    let mut stages = Vec::new();
    let timestamp = curr.timestamp_ms;

    // Check for spin start (balance decreased)
    if let (Some(prev_bal), Some(curr_bal)) = (prev.state.balance, curr.state.balance) {
        if curr_bal < prev_bal && prev.state.win_amount.is_none() {
            stages.push(StageEvent::new(Stage::SpinStart, timestamp));
        }
    }

    // Check for reel stops
    let prev_stopped: std::collections::HashSet<_> = prev.state.stopped_reels.iter().collect();
    for &reel_idx in &curr.state.stopped_reels {
        if !prev_stopped.contains(&reel_idx) {
            let symbols = curr
                .state
                .reel_positions
                .get(reel_idx as usize)
                .cloned()
                .unwrap_or_default();

            stages.push(StageEvent::new(
                Stage::ReelStop {
                    reel_index: reel_idx,
                    symbols,
                },
                timestamp,
            ));
        }
    }

    // Check for feature enter
    if prev.state.active_feature.is_none() && curr.state.active_feature.is_some() {
        let feature_type = match curr.state.active_feature.as_deref() {
            Some("free_spins") => FeatureType::FreeSpins,
            Some("bonus") => FeatureType::PickBonus,
            Some("respin") => FeatureType::Respin,
            Some("cascade") => FeatureType::Cascade,
            _ => FeatureType::Custom(0),
        };

        stages.push(StageEvent::new(
            Stage::FeatureEnter {
                feature_type,
                total_steps: curr.state.feature_total_steps,
                multiplier: curr.state.multiplier.unwrap_or(1.0),
            },
            timestamp,
        ));
    }

    // Check for feature exit
    if prev.state.active_feature.is_some() && curr.state.active_feature.is_none() {
        stages.push(StageEvent::new(
            Stage::FeatureExit { total_win: 0.0 },
            timestamp,
        ));
    }

    // Check for feature step
    if let (Some(prev_step), Some(curr_step)) = (prev.state.feature_step, curr.state.feature_step) {
        if curr_step > prev_step {
            stages.push(StageEvent::new(
                Stage::FeatureStep {
                    step_index: curr_step,
                    steps_remaining: curr.state.feature_total_steps.map(|t| t - curr_step),
                    current_multiplier: curr.state.multiplier.unwrap_or(1.0),
                },
                timestamp,
            ));
        }
    }

    // Check for big win start
    if !prev.state.big_win_active && curr.state.big_win_active {
        let tier = match curr.state.big_win_tier.as_deref() {
            Some("big") => BigWinTier::BigWin,
            Some("mega") => BigWinTier::MegaWin,
            Some("epic") => BigWinTier::EpicWin,
            Some("ultra") => BigWinTier::UltraWin,
            _ => BigWinTier::Win,
        };

        stages.push(StageEvent::new(
            Stage::BigWinTier {
                tier,
                amount: curr.state.win_amount.unwrap_or(0.0),
            },
            timestamp,
        ));
    }

    // Check for win present
    if let (Some(prev_win), Some(curr_win)) = (prev.state.win_amount, curr.state.win_amount) {
        if curr_win > 0.0 && prev_win == 0.0 {
            stages.push(StageEvent::new(
                Stage::WinPresent {
                    win_amount: curr_win,
                    line_count: curr.state.win_lines.unwrap_or(0),
                },
                timestamp,
            ));
        }
    }

    // Check for spin end (win amount appeared or returned to idle)
    if prev.state.win_amount.is_none() && curr.state.win_amount.is_some() {
        stages.push(StageEvent::new(Stage::SpinEnd, timestamp));
    }

    Ok(SnapshotDiff {
        stages,
        from: prev.state.clone(),
        to: curr.state.clone(),
    })
}

// JSON path helpers

fn get_json_value<'a>(json: &'a Value, path: &str) -> Option<&'a Value> {
    let parts: Vec<&str> = path.split('.').collect();
    let mut current = json;

    for part in parts {
        if let Some(idx) = part.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            // Array index
            if let Ok(i) = idx.parse::<usize>() {
                current = current.get(i)?;
            } else {
                return None;
            }
        } else {
            current = current.get(part)?;
        }
    }

    Some(current)
}

fn get_json_string(json: &Value, path: &str) -> Option<String> {
    get_json_value(json, path).and_then(|v| v.as_str().map(|s| s.to_string()))
}

fn get_json_number(json: &Value, path: &str) -> Option<f64> {
    get_json_value(json, path).and_then(|v| v.as_f64())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_snapshot_diff_spin_start() {
        let prev = GameSnapshot {
            raw: json!({}),
            state: ExtractedState {
                balance: Some(100.0),
                win_amount: None,
                ..Default::default()
            },
            timestamp_ms: 0.0,
        };

        let curr = GameSnapshot {
            raw: json!({}),
            state: ExtractedState {
                balance: Some(90.0),
                win_amount: None,
                ..Default::default()
            },
            timestamp_ms: 100.0,
        };

        let diff = compute_diff(&prev, &curr).unwrap();
        assert_eq!(diff.stages.len(), 1);
        assert!(matches!(diff.stages[0].stage, Stage::SpinStart));
    }

    #[test]
    fn test_snapshot_diff_reel_stop() {
        let prev = GameSnapshot {
            raw: json!({}),
            state: ExtractedState {
                stopped_reels: vec![],
                reel_positions: vec![vec![1, 2, 3], vec![4, 5, 6]],
                ..Default::default()
            },
            timestamp_ms: 0.0,
        };

        let curr = GameSnapshot {
            raw: json!({}),
            state: ExtractedState {
                stopped_reels: vec![0],
                reel_positions: vec![vec![1, 2, 3], vec![4, 5, 6]],
                ..Default::default()
            },
            timestamp_ms: 100.0,
        };

        let diff = compute_diff(&prev, &curr).unwrap();
        assert_eq!(diff.stages.len(), 1);
        assert!(matches!(
            diff.stages[0].stage,
            Stage::ReelStop {
                reel_index: 0,
                ..
            }
        ));
    }
}
