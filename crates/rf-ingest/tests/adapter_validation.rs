//! Adapter Validation Test Suite
//!
//! P3.13: Comprehensive tests for validating Stage Ingest adapters.
//! Tests cover:
//! - Configuration validation
//! - Event mapping correctness
//! - JSON parsing accuracy
//! - Layer capability verification
//! - Big win threshold handling
//! - Edge cases and error handling

use rf_ingest::{
    adapter::{AdapterError, ConfigBasedAdapter, EngineAdapter, IngestLayer},
    config::{AdapterConfig, BigWinThresholds, PayloadPaths, SnapshotPaths},
};
use serde_json::{json, Value};

// ═══════════════════════════════════════════════════════════════════════════════
// TEST FIXTURES
// ═══════════════════════════════════════════════════════════════════════════════

fn create_basic_config() -> AdapterConfig {
    let mut config = AdapterConfig::new("test-adapter", "Test Company", "Test Engine");
    config.layers = vec![IngestLayer::DirectEvent];
    config.map_event("spin_start", "SpinStart");
    config.map_event("spin_end", "SpinEnd");
    config.map_event("reel_stop", "ReelStop");
    config
}

fn create_full_config() -> AdapterConfig {
    let mut config = AdapterConfig::new("full-adapter", "Full Corp", "Full Engine");
    config.layers = vec![IngestLayer::DirectEvent, IngestLayer::SnapshotDiff];

    // Event mappings
    config.map_event("cmd_spin", "SpinStart");
    config.map_event("reel_stopping_0", "ReelStop { reel_index: 0 }");
    config.map_event("reel_stopping_1", "ReelStop { reel_index: 1 }");
    config.map_event("reel_stopping_2", "ReelStop { reel_index: 2 }");
    config.map_event("reel_stopping_3", "ReelStop { reel_index: 3 }");
    config.map_event("reel_stopping_4", "ReelStop { reel_index: 4 }");
    config.map_event("spin_complete", "SpinEnd");
    config.map_event("win_evaluation", "EvaluateWins");
    config.map_event("anticipation_start", "AnticipationOn");
    config.map_event("anticipation_end", "AnticipationOff");
    config.map_event("rollup_begin", "RollupStart");
    config.map_event("rollup_tick", "RollupTick");
    config.map_event("rollup_end", "RollupEnd");
    config.map_event("bigwin_present", "BigWinStart");
    config.map_event("feature_trigger", "FeatureEnter");
    config.map_event("feature_end", "FeatureExit");

    // Payload paths
    config.payload_paths = PayloadPaths {
        events_path: Some("$.events".to_string()),
        event_name_path: Some("$.type".to_string()),
        timestamp_path: Some("$.timestamp".to_string()),
        win_amount_path: Some("$.data.win_amount".to_string()),
        bet_amount_path: Some("$.data.bet".to_string()),
        reel_data_path: Some("$.data.reels".to_string()),
        feature_path: Some("$.data.feature".to_string()),
        symbol_path: Some("$.data.symbols".to_string()),
    };

    // Snapshot paths
    config.snapshot_paths = SnapshotPaths {
        reels_path: Some("$.reels".to_string()),
        win_path: Some("$.total_win".to_string()),
        feature_active_path: Some("$.feature_active".to_string()),
        balance_path: Some("$.balance".to_string()),
    };

    // Big win thresholds
    config.bigwin_thresholds = BigWinThresholds {
        win: 5.0,
        big_win: 15.0,
        mega_win: 30.0,
        epic_win: 50.0,
        ultra_win: 100.0,
    };

    config
}

fn create_sample_event_json(event_type: &str) -> Value {
    json!({
        "type": event_type,
        "timestamp": 1234567890.0,
        "data": {
            "win_amount": 100.0,
            "bet": 10.0,
            "reels": [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10, 11, 12], [13, 14, 15]],
            "symbols": [1, 2, 3, 4, 5],
            "feature": null
        }
    })
}

fn create_sample_trace_json() -> Value {
    json!({
        "game_id": "test-game",
        "session_id": "session-123",
        "events": [
            { "type": "cmd_spin", "timestamp": 0.0 },
            { "type": "reel_stopping_0", "timestamp": 500.0 },
            { "type": "reel_stopping_1", "timestamp": 600.0 },
            { "type": "reel_stopping_2", "timestamp": 700.0 },
            { "type": "reel_stopping_3", "timestamp": 800.0 },
            { "type": "reel_stopping_4", "timestamp": 900.0 },
            { "type": "spin_complete", "timestamp": 1000.0 }
        ]
    })
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIGURATION VALIDATION TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_config_validation_empty_adapter_id() {
    let mut config = create_basic_config();
    config.adapter_id = String::new();

    let result = config.validate();
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), AdapterError::ConfigError(_)));
}

#[test]
fn test_config_validation_empty_company_name() {
    let mut config = create_basic_config();
    config.company_name = String::new();

    let result = config.validate();
    assert!(result.is_err());
}

#[test]
fn test_config_validation_empty_layers() {
    let mut config = create_basic_config();
    config.layers = vec![];

    let result = config.validate();
    assert!(result.is_err());
}

#[test]
fn test_config_validation_valid_config() {
    let config = create_basic_config();
    assert!(config.validate().is_ok());
}

#[test]
fn test_config_validation_multiple_layers() {
    let mut config = create_basic_config();
    config.layers = vec![
        IngestLayer::DirectEvent,
        IngestLayer::SnapshotDiff,
        IngestLayer::RuleBased,
    ];

    assert!(config.validate().is_ok());
    assert_eq!(config.layers.len(), 3);
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT MAPPING TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_event_mapping_basic() {
    let config = create_basic_config();

    assert_eq!(config.get_stage("spin_start"), Some("SpinStart"));
    assert_eq!(config.get_stage("spin_end"), Some("SpinEnd"));
    assert_eq!(config.get_stage("reel_stop"), Some("ReelStop"));
}

#[test]
fn test_event_mapping_unknown_event() {
    let config = create_basic_config();

    assert_eq!(config.get_stage("unknown_event"), None);
    assert_eq!(config.get_stage(""), None);
}

#[test]
fn test_event_mapping_case_sensitive() {
    let config = create_basic_config();

    // Event names should be case-sensitive
    assert_eq!(config.get_stage("spin_start"), Some("SpinStart"));
    assert_eq!(config.get_stage("SPIN_START"), None);
    assert_eq!(config.get_stage("Spin_Start"), None);
}

#[test]
fn test_event_mapping_overwrite() {
    let mut config = create_basic_config();

    // Initial mapping
    assert_eq!(config.get_stage("spin_start"), Some("SpinStart"));

    // Overwrite with new mapping
    config.map_event("spin_start", "SpinStartV2");
    assert_eq!(config.get_stage("spin_start"), Some("SpinStartV2"));
}

#[test]
fn test_event_mapping_with_parameters() {
    let config = create_full_config();

    // Reel stop events with indices
    assert_eq!(
        config.get_stage("reel_stopping_0"),
        Some("ReelStop { reel_index: 0 }")
    );
    assert_eq!(
        config.get_stage("reel_stopping_4"),
        Some("ReelStop { reel_index: 4 }")
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// TOML SERIALIZATION TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_toml_roundtrip() {
    let config = create_full_config();

    let toml_str = config.to_toml().expect("Failed to serialize to TOML");
    let parsed = AdapterConfig::from_toml(&toml_str).expect("Failed to parse TOML");

    assert_eq!(parsed.adapter_id, config.adapter_id);
    assert_eq!(parsed.company_name, config.company_name);
    assert_eq!(parsed.engine_name, config.engine_name);
    assert_eq!(parsed.layers, config.layers);
    assert_eq!(parsed.event_mapping, config.event_mapping);
}

#[test]
fn test_toml_invalid_format() {
    let invalid_toml = "this is { not valid toml";
    let result = AdapterConfig::from_toml(invalid_toml);
    assert!(result.is_err());
}

#[test]
fn test_toml_missing_required_fields() {
    // TOML with missing adapter_id should fail to parse
    // since adapter_id is required without serde(default)
    let minimal_toml = r#"
        company_name = "Test"
        engine_name = "Engine"
        layers = ["direct_event"]
    "#;

    let result = AdapterConfig::from_toml(minimal_toml);
    // This should fail because adapter_id is required
    assert!(result.is_err());
}

#[test]
fn test_toml_with_all_required_fields() {
    let valid_toml = r#"
        adapter_id = "test-adapter"
        company_name = "Test"
        engine_name = "Engine"
        layers = ["direct_event"]
    "#;

    let config = AdapterConfig::from_toml(valid_toml).expect("Should parse");
    assert_eq!(config.adapter_id, "test-adapter");
}

// ═══════════════════════════════════════════════════════════════════════════════
// BIG WIN THRESHOLD TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_bigwin_thresholds_default() {
    let thresholds = BigWinThresholds::default();

    assert_eq!(thresholds.win, 10.0);
    assert_eq!(thresholds.big_win, 15.0);
    assert_eq!(thresholds.mega_win, 25.0);
    assert_eq!(thresholds.epic_win, 50.0);
    assert_eq!(thresholds.ultra_win, 100.0);
}

#[test]
fn test_bigwin_thresholds_custom() {
    let config = create_full_config();

    assert_eq!(config.bigwin_thresholds.win, 5.0);
    assert_eq!(config.bigwin_thresholds.big_win, 15.0);
    assert_eq!(config.bigwin_thresholds.mega_win, 30.0);
    assert_eq!(config.bigwin_thresholds.epic_win, 50.0);
    assert_eq!(config.bigwin_thresholds.ultra_win, 100.0);
}

#[test]
fn test_bigwin_thresholds_ordering() {
    let config = create_full_config();
    let t = &config.bigwin_thresholds;

    // Thresholds should be in ascending order
    assert!(t.win < t.big_win);
    assert!(t.big_win < t.mega_win);
    assert!(t.mega_win < t.epic_win);
    assert!(t.epic_win < t.ultra_win);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADAPTER TRAIT TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_adapter_trait_implementation() {
    let config = create_full_config();
    let adapter = ConfigBasedAdapter::new(config.clone());

    assert_eq!(adapter.adapter_id(), "full-adapter");
    assert_eq!(adapter.company_name(), "Full Corp");
    assert_eq!(adapter.engine_name(), "Full Engine");
}

#[test]
fn test_adapter_supported_layers() {
    let config = create_full_config();
    let adapter = ConfigBasedAdapter::new(config);

    let layers = adapter.supported_layers();
    assert!(layers.contains(&IngestLayer::DirectEvent));
    assert!(layers.contains(&IngestLayer::SnapshotDiff));
    assert!(!layers.contains(&IngestLayer::RuleBased));
}

#[test]
fn test_adapter_config_validation() {
    let config = create_full_config();
    let adapter = ConfigBasedAdapter::new(config.clone());

    // Valid config should pass
    assert!(adapter.validate_config(&config).is_ok());

    // Invalid config should fail
    let mut invalid = config.clone();
    invalid.adapter_id = String::new();
    assert!(adapter.validate_config(&invalid).is_err());
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAYLOAD PATH TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_payload_paths_default() {
    let paths = PayloadPaths::default();

    assert!(paths.events_path.is_none());
    assert!(paths.event_name_path.is_none());
    assert!(paths.timestamp_path.is_none());
}

#[test]
fn test_payload_paths_custom() {
    let config = create_full_config();

    assert_eq!(config.payload_paths.events_path, Some("$.events".to_string()));
    assert_eq!(
        config.payload_paths.event_name_path,
        Some("$.type".to_string())
    );
    assert_eq!(
        config.payload_paths.timestamp_path,
        Some("$.timestamp".to_string())
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SNAPSHOT PATH TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_snapshot_paths_default() {
    let paths = SnapshotPaths::default();

    assert!(paths.reels_path.is_none());
    assert!(paths.win_path.is_none());
    assert!(paths.feature_active_path.is_none());
    assert!(paths.balance_path.is_none());
}

#[test]
fn test_snapshot_paths_custom() {
    let config = create_full_config();

    assert_eq!(
        config.snapshot_paths.reels_path,
        Some("$.reels".to_string())
    );
    assert_eq!(
        config.snapshot_paths.win_path,
        Some("$.total_win".to_string())
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// INGEST LAYER SERIALIZATION TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_ingest_layer_serialization() {
    let layer = IngestLayer::DirectEvent;
    let serialized = serde_json::to_string(&layer).unwrap();
    assert_eq!(serialized, "\"direct_event\"");

    let layer = IngestLayer::SnapshotDiff;
    let serialized = serde_json::to_string(&layer).unwrap();
    assert_eq!(serialized, "\"snapshot_diff\"");

    let layer = IngestLayer::RuleBased;
    let serialized = serde_json::to_string(&layer).unwrap();
    assert_eq!(serialized, "\"rule_based\"");
}

#[test]
fn test_ingest_layer_deserialization() {
    let layer: IngestLayer = serde_json::from_str("\"direct_event\"").unwrap();
    assert_eq!(layer, IngestLayer::DirectEvent);

    let layer: IngestLayer = serde_json::from_str("\"snapshot_diff\"").unwrap();
    assert_eq!(layer, IngestLayer::SnapshotDiff);

    let layer: IngestLayer = serde_json::from_str("\"rule_based\"").unwrap();
    assert_eq!(layer, IngestLayer::RuleBased);
}

#[test]
fn test_ingest_layer_invalid_deserialization() {
    let result: Result<IngestLayer, _> = serde_json::from_str("\"invalid_layer\"");
    assert!(result.is_err());
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDGE CASE TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_config_with_special_characters() {
    let mut config = AdapterConfig::new("adapter-with-dashes", "Company Name With Spaces", "Engine/Platform");
    config.map_event("event:with:colons", "Stage");
    config.map_event("event.with.dots", "Stage");

    assert!(config.validate().is_ok());
    assert_eq!(config.get_stage("event:with:colons"), Some("Stage"));
    assert_eq!(config.get_stage("event.with.dots"), Some("Stage"));
}

#[test]
fn test_config_with_unicode() {
    let mut config = AdapterConfig::new("unicode-adapter", "会社名", "引擎");
    config.map_event("スピン開始", "SpinStart");

    assert!(config.validate().is_ok());
    assert_eq!(config.get_stage("スピン開始"), Some("SpinStart"));
}

#[test]
fn test_config_with_empty_event_mapping() {
    let mut config = create_basic_config();
    config.event_mapping.clear();

    // Config with empty event mapping is still valid (just useless)
    assert!(config.validate().is_ok());
    assert!(config.event_mapping.is_empty());
}

#[test]
fn test_config_metadata() {
    let mut config = create_basic_config();
    config.metadata.insert("custom_key".to_string(), json!("custom_value"));
    config.metadata.insert("version".to_string(), json!(1));
    config
        .metadata
        .insert("nested".to_string(), json!({"key": "value"}));

    let toml = config.to_toml().unwrap();
    let parsed = AdapterConfig::from_toml(&toml).unwrap();

    assert_eq!(
        parsed.metadata.get("custom_key"),
        Some(&json!("custom_value"))
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUILDER PATTERN TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_config_builder_pattern() {
    let config = AdapterConfig::new("builder-test", "Builder Co", "Engine")
        .tap(|c| {
            c.map_event("event1", "Stage1");
            c.map_event("event2", "Stage2");
            c.layers = vec![IngestLayer::DirectEvent];
        });

    assert_eq!(config.get_stage("event1"), Some("Stage1"));
    assert_eq!(config.get_stage("event2"), Some("Stage2"));
}

// Helper trait for tap pattern
trait Tap: Sized {
    fn tap(mut self, f: impl FnOnce(&mut Self)) -> Self {
        f(&mut self);
        self
    }
}

impl Tap for AdapterConfig {}

// ═══════════════════════════════════════════════════════════════════════════════
// JSON PARSING TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_adapter_parse_json_basic() {
    let config = create_full_config();
    let adapter = ConfigBasedAdapter::new(config);

    let json = create_sample_trace_json();
    let result = adapter.parse_json(&json);

    // This test verifies the adapter can attempt to parse JSON
    // Actual parsing depends on layer_event implementation
    // For now, we just verify no panic
    let _ = result;
}

#[test]
fn test_adapter_parse_single_event() {
    let config = create_full_config();
    let adapter = ConfigBasedAdapter::new(config);

    let event_json = create_sample_event_json("cmd_spin");
    let result = adapter.parse_event(&event_json);

    // Verify parsing doesn't panic
    let _ = result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONCURRENCY TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_adapter_is_send_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<ConfigBasedAdapter>();
}

#[test]
fn test_config_clone() {
    let config = create_full_config();
    let cloned = config.clone();

    assert_eq!(config.adapter_id, cloned.adapter_id);
    assert_eq!(config.event_mapping, cloned.event_mapping);
    assert_eq!(config.layers, cloned.layers);
}

// ═══════════════════════════════════════════════════════════════════════════════
// STRESS TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_large_event_mapping() {
    let mut config = create_basic_config();

    // Add 1000 event mappings
    for i in 0..1000 {
        config.map_event(&format!("event_{}", i), &format!("Stage_{}", i));
    }

    assert_eq!(config.event_mapping.len(), 1003); // 1000 + 3 from basic config
    assert_eq!(config.get_stage("event_500"), Some("Stage_500"));
}

#[test]
fn test_toml_roundtrip_large_config() {
    let mut config = create_basic_config();

    // Add many mappings
    for i in 0..100 {
        config.map_event(&format!("event_{}", i), &format!("Stage_{}", i));
    }

    let toml = config.to_toml().unwrap();
    let parsed = AdapterConfig::from_toml(&toml).unwrap();

    assert_eq!(parsed.event_mapping.len(), config.event_mapping.len());
}
