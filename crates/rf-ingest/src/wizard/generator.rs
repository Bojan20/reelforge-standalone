//! Config generator — generates adapter config from analysis

use std::collections::HashMap;

use crate::adapter::IngestLayer;
use crate::config::{AdapterConfig, BigWinThresholds, PayloadPaths, SnapshotPaths};

use super::{DetectedEvent, DetectedField, FieldPurpose};

/// Determine best ingest layer based on analysis
pub fn determine_layer(events: &[DetectedEvent], fields: &[DetectedField]) -> IngestLayer {
    // Count how many events have stage mappings
    let mapped_events = events
        .iter()
        .filter(|e| e.suggested_stage.is_some())
        .count();
    let total_events = events.len();

    // If we have good event mappings, use Layer 1
    if total_events > 0 && mapped_events as f64 / total_events as f64 > 0.7 {
        return IngestLayer::DirectEvent;
    }

    // Check if we have state fields that would work for snapshot diff
    let has_phase = fields
        .iter()
        .any(|f| f.suggested_purpose == Some(FieldPurpose::Phase));
    let has_balance = fields
        .iter()
        .any(|f| f.suggested_purpose == Some(FieldPurpose::Balance));
    let has_reels = fields
        .iter()
        .any(|f| f.suggested_purpose == Some(FieldPurpose::ReelSymbols));

    if has_phase && (has_balance || has_reels) {
        return IngestLayer::SnapshotDiff;
    }

    // Fall back to rule-based
    IngestLayer::RuleBased
}

/// Generate adapter config from detected events and fields
pub fn generate_config(
    events: &[DetectedEvent],
    fields: &[DetectedField],
    _layer: IngestLayer,
) -> AdapterConfig {
    AdapterConfig {
        event_mapping: generate_event_mapping(events),
        payload_paths: generate_payload_paths(fields),
        snapshot_paths: generate_snapshot_paths(fields),
        bigwin_thresholds: BigWinThresholds::default(),
        ..Default::default()
    }
}

/// Generate event name to stage mapping
fn generate_event_mapping(events: &[DetectedEvent]) -> HashMap<String, String> {
    events
        .iter()
        .filter_map(|e| {
            e.suggested_stage
                .as_ref()
                .map(|stage| (e.event_name.clone(), stage.clone()))
        })
        .collect()
}

/// Generate payload extraction paths
fn generate_payload_paths(fields: &[DetectedField]) -> PayloadPaths {
    let mut paths = PayloadPaths::default();

    for field in fields {
        match field.suggested_purpose {
            Some(FieldPurpose::Win) => {
                paths.win_amount_path = Some(field.path.clone());
            }
            Some(FieldPurpose::Bet) => {
                paths.bet_amount_path = Some(field.path.clone());
            }
            Some(FieldPurpose::ReelIndex) | Some(FieldPurpose::ReelSymbols) => {
                paths.reel_data_path = Some(field.path.clone());
            }
            Some(FieldPurpose::FeatureType) => {
                paths.feature_path = Some(field.path.clone());
            }
            Some(FieldPurpose::Timestamp) => {
                paths.timestamp_path = Some(field.path.clone());
            }
            Some(FieldPurpose::EventType) => {
                paths.event_name_path = Some(field.path.clone());
            }
            _ => {}
        }
    }

    paths
}

/// Generate snapshot extraction paths
fn generate_snapshot_paths(fields: &[DetectedField]) -> SnapshotPaths {
    let mut paths = SnapshotPaths::default();

    for field in fields {
        match field.suggested_purpose {
            Some(FieldPurpose::Balance) => {
                paths.balance_path = Some(field.path.clone());
            }
            Some(FieldPurpose::Win) => {
                paths.win_path = Some(field.path.clone());
            }
            Some(FieldPurpose::ReelSymbols) => {
                paths.reels_path = Some(field.path.clone());
            }
            Some(FieldPurpose::FeatureType) => {
                paths.feature_active_path = Some(field.path.clone());
            }
            _ => {}
        }
    }

    paths
}

/// Calculate confidence score
pub fn calculate_confidence(
    events: &[DetectedEvent],
    _fields: &[DetectedField],
    config: &AdapterConfig,
) -> f64 {
    let mut score = 0.0;
    let mut max_score = 0.0;

    // Event mapping quality (40% of score)
    max_score += 40.0;
    if !events.is_empty() {
        let mapped = events
            .iter()
            .filter(|e| e.suggested_stage.is_some())
            .count();
        score += 40.0 * (mapped as f64 / events.len() as f64);
    }

    // Core field detection (30% of score)
    max_score += 30.0;

    // Win amount (10%)
    if config.payload_paths.win_amount_path.is_some() {
        score += 10.0;
    }

    // Bet amount (5%)
    if config.payload_paths.bet_amount_path.is_some() {
        score += 5.0;
    }

    // Reel data (10%)
    if config.payload_paths.reel_data_path.is_some() || config.payload_paths.symbol_path.is_some() {
        score += 10.0;
    }

    // Timestamp (5%)
    if config.payload_paths.timestamp_path.is_some() {
        score += 5.0;
    }

    // Event type coverage (20% of score)
    max_score += 20.0;
    let critical_stages = ["SpinStart", "SpinEnd", "ReelStop", "WinPresent"];
    let found_critical = critical_stages
        .iter()
        .filter(|stage| config.event_mapping.values().any(|s| s == *stage))
        .count();
    score += 20.0 * (found_critical as f64 / critical_stages.len() as f64);

    // Bonus: feature detection (10%)
    max_score += 10.0;
    let has_feature_events = config
        .event_mapping
        .values()
        .any(|s| s.contains("Feature") || s.contains("FreeSpins"));
    if has_feature_events {
        score += 10.0;
    }

    score / max_score
}

#[cfg(test)]
mod tests {
    use super::super::DetectedType;
    use super::*;

    #[test]
    fn test_determine_layer_direct_event() {
        let events = vec![
            DetectedEvent {
                event_name: "spin_start".to_string(),
                suggested_stage: Some("SpinStart".to_string()),
                sample_count: 10,
                sample_payload: None,
            },
            DetectedEvent {
                event_name: "reel_stop".to_string(),
                suggested_stage: Some("ReelStop".to_string()),
                sample_count: 50,
                sample_payload: None,
            },
            DetectedEvent {
                event_name: "win".to_string(),
                suggested_stage: Some("WinPresent".to_string()),
                sample_count: 5,
                sample_payload: None,
            },
        ];

        let fields = vec![];

        let layer = determine_layer(&events, &fields);
        assert_eq!(layer, IngestLayer::DirectEvent);
    }

    #[test]
    fn test_determine_layer_snapshot() {
        let events = vec![DetectedEvent {
            event_name: "state_update".to_string(),
            suggested_stage: None,
            sample_count: 100,
            sample_payload: None,
        }];

        let fields = vec![
            DetectedField {
                path: "state".to_string(),
                value_type: DetectedType::String,
                sample_values: vec![],
                suggested_purpose: Some(FieldPurpose::Phase),
            },
            DetectedField {
                path: "balance".to_string(),
                value_type: DetectedType::Number,
                sample_values: vec![],
                suggested_purpose: Some(FieldPurpose::Balance),
            },
        ];

        let layer = determine_layer(&events, &fields);
        assert_eq!(layer, IngestLayer::SnapshotDiff);
    }

    #[test]
    fn test_generate_event_mapping() {
        let events = vec![
            DetectedEvent {
                event_name: "spin_start".to_string(),
                suggested_stage: Some("SpinStart".to_string()),
                sample_count: 10,
                sample_payload: None,
            },
            DetectedEvent {
                event_name: "unknown_event".to_string(),
                suggested_stage: None,
                sample_count: 5,
                sample_payload: None,
            },
        ];

        let mapping = generate_event_mapping(&events);

        assert_eq!(mapping.get("spin_start"), Some(&"SpinStart".to_string()));
        assert!(!mapping.contains_key("unknown_event"));
    }

    #[test]
    fn test_calculate_confidence() {
        let events = vec![
            DetectedEvent {
                event_name: "spin_start".to_string(),
                suggested_stage: Some("SpinStart".to_string()),
                sample_count: 10,
                sample_payload: None,
            },
            DetectedEvent {
                event_name: "spin_end".to_string(),
                suggested_stage: Some("SpinEnd".to_string()),
                sample_count: 10,
                sample_payload: None,
            },
            DetectedEvent {
                event_name: "reel_stop".to_string(),
                suggested_stage: Some("ReelStop".to_string()),
                sample_count: 50,
                sample_payload: None,
            },
            DetectedEvent {
                event_name: "win".to_string(),
                suggested_stage: Some("WinPresent".to_string()),
                sample_count: 5,
                sample_payload: None,
            },
        ];

        let fields = vec![DetectedField {
            path: "win_amount".to_string(),
            value_type: DetectedType::Number,
            sample_values: vec![],
            suggested_purpose: Some(FieldPurpose::Win),
        }];

        let config = generate_config(&events, &fields, IngestLayer::DirectEvent);
        let confidence = calculate_confidence(&events, &fields, &config);

        // Should have high confidence with all critical stages mapped
        // Expected: 40 (event mapping) + 10 (win path) + 20 (critical stages) = 70%
        assert!(confidence >= 0.7);
    }
}
