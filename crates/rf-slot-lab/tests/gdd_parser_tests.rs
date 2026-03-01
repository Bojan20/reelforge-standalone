// ============================================================================
// GDD Parser Integration Tests — FM-50
// ============================================================================
// Tests the full GDD parsing pipeline: JSON, YAML, schema validation,
// constraint validation, and FluxMacro integration requirements.
// ============================================================================

use rf_slot_lab::parser::{
    GddDocument, GddFeature, GddGame, GddGrid, GddMath, GddParseError, GddParser, GddSchema,
    GddSymbol, GddWinTier, validate_constraints,
};

// ─── JSON Parsing ────────────────────────────────────────────────────────────

const MINIMAL_JSON: &str = r#"{
    "game": { "name": "Test Game", "id": "test_game" },
    "grid": { "reels": 5, "rows": 3 }
}"#;

const FULL_JSON: &str = r#"{
    "game": {
        "name": "Golden Pantheon",
        "id": "golden_pantheon",
        "provider": "FluxForge",
        "volatility": "high",
        "target_rtp": 0.965
    },
    "grid": {
        "reels": 5,
        "rows": 3,
        "paylines": 20
    },
    "win_mechanism": "paylines",
    "symbols": [
        { "id": 1, "name": "Zeus", "type": "regular", "pays": [0, 0, 5, 15, 50], "tier": 1 },
        { "id": 2, "name": "Athena", "type": "regular", "pays": [0, 0, 4, 12, 40], "tier": 1 },
        { "id": 10, "name": "Wild", "type": "wild", "pays": [], "tier": 0 },
        { "id": 11, "name": "Scatter", "type": "scatter", "pays": [], "tier": 0 }
    ],
    "features": [
        { "type": "free_spins", "trigger": "scatter_3" },
        { "type": "hold_and_win", "trigger": "coins_6" }
    ],
    "win_tiers": [
        { "name": "Small", "min_ratio": 1.0, "max_ratio": 5.0 },
        { "name": "Big", "min_ratio": 5.0, "max_ratio": 20.0 },
        { "name": "Mega", "min_ratio": 20.0, "max_ratio": 100.0 },
        { "name": "Epic", "min_ratio": 100.0, "max_ratio": 500.0 }
    ],
    "math": {
        "target_rtp": 0.965,
        "symbol_weights": {
            "Zeus": [3, 3, 3, 3, 3],
            "Athena": [4, 4, 4, 4, 4]
        }
    }
}"#;

#[test]
fn json_minimal_parse() {
    let parser = GddParser::new();
    let model = parser.parse_json(MINIMAL_JSON).unwrap();

    assert_eq!(model.info.name, "Test Game");
    assert_eq!(model.info.id, "test_game");
    assert_eq!(model.grid.reels, 5);
    assert_eq!(model.grid.rows, 3);
}

#[test]
fn json_full_parse() {
    let parser = GddParser::new();
    let model = parser.parse_json(FULL_JSON).unwrap();

    assert_eq!(model.info.name, "Golden Pantheon");
    assert_eq!(model.grid.paylines, 20);
    assert_eq!(model.features.len(), 2);
    assert_eq!(model.win_tiers.tiers.len(), 4);
    assert!(model.math.is_some());
}

#[test]
fn json_invalid_syntax() {
    let parser = GddParser::new();
    let result = parser.parse_json("not valid json {{{");
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), GddParseError::JsonError(_)));
}

#[test]
fn json_missing_game() {
    let json = r#"{ "grid": { "reels": 5, "rows": 3 } }"#;
    let parser = GddParser::new();
    let result = parser.parse_json(json);
    assert!(result.is_err());
}

// ─── YAML Parsing ────────────────────────────────────────────────────────────

const MINIMAL_YAML: &str = r#"
game:
  name: "Test YAML"
  id: "test_yaml"
grid:
  reels: 5
  rows: 3
"#;

const FULL_YAML: &str = r#"
game:
  name: "Golden Pantheon"
  id: "golden_pantheon"
  provider: "FluxForge"
  volatility: "high"
  target_rtp: 0.965
grid:
  reels: 5
  rows: 3
  paylines: 20
win_mechanism: "paylines"
symbols:
  - id: 1
    name: "Zeus"
    type: "regular"
    pays: [0, 0, 5.0, 15.0, 50.0]
    tier: 1
  - id: 10
    name: "Wild"
    type: "wild"
    pays: []
features:
  - type: "free_spins"
    trigger: "scatter_3"
  - type: "hold_and_win"
    trigger: "coins_6"
win_tiers:
  - name: "Small"
    min_ratio: 1.0
    max_ratio: 5.0
  - name: "Big"
    min_ratio: 5.0
    max_ratio: 20.0
"#;

#[test]
fn yaml_minimal_parse() {
    let parser = GddParser::new();
    let model = parser.parse_yaml(MINIMAL_YAML).unwrap();

    assert_eq!(model.info.name, "Test YAML");
    assert_eq!(model.info.id, "test_yaml");
    assert_eq!(model.grid.reels, 5);
}

#[test]
fn yaml_full_parse() {
    let parser = GddParser::new();
    let model = parser.parse_yaml(FULL_YAML).unwrap();

    assert_eq!(model.info.name, "Golden Pantheon");
    assert_eq!(model.features.len(), 2);
    assert_eq!(model.win_tiers.tiers.len(), 2);
}

#[test]
fn yaml_invalid_syntax() {
    let parser = GddParser::new();
    let result = parser.parse_yaml("not: [valid {{yaml");
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), GddParseError::YamlError(_)));
}

#[test]
fn yaml_json_equivalent() {
    let parser = GddParser::new();

    let json_model = parser.parse_json(FULL_JSON).unwrap();
    let yaml_model = parser.parse_yaml(FULL_YAML).unwrap();

    // Same game info
    assert_eq!(json_model.info.name, yaml_model.info.name);
    assert_eq!(json_model.info.id, yaml_model.info.id);
    assert_eq!(json_model.grid.reels, yaml_model.grid.reels);
    assert_eq!(json_model.grid.rows, yaml_model.grid.rows);
}

// ─── Schema Validation ──────────────────────────────────────────────────────

#[test]
fn schema_valid_document() {
    let schema = GddSchema::default();
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test_game".into(),
            provider: None,
            volatility: Some("high".into()),
            target_rtp: Some(0.965),
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: Some(20),
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![],
        math: None,
    };

    let warnings = schema.validate(&doc).unwrap();
    assert!(warnings.is_empty());
}

#[test]
fn schema_empty_name_fails() {
    let schema = GddSchema::default();
    let doc = GddDocument {
        game: GddGame {
            name: "".into(),
            id: "test".into(),
            provider: None,
            volatility: None,
            target_rtp: None,
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![],
        math: None,
    };

    assert!(schema.validate(&doc).is_err());
}

#[test]
fn schema_invalid_game_id() {
    let schema = GddSchema::default();
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "invalid id!@#".into(),
            provider: None,
            volatility: None,
            target_rtp: None,
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![],
        math: None,
    };

    assert!(schema.validate(&doc).is_err());
}

#[test]
fn schema_rtp_out_of_range() {
    let schema = GddSchema::default();
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test".into(),
            provider: None,
            volatility: None,
            target_rtp: Some(1.5),
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![],
        math: None,
    };

    assert!(schema.validate(&doc).is_err());
}

#[test]
fn schema_duplicate_symbol_ids() {
    let schema = GddSchema::default();
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test".into(),
            provider: None,
            volatility: None,
            target_rtp: None,
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![
            GddSymbol {
                id: 1,
                name: "A".into(),
                symbol_type: "regular".into(),
                pays: vec![],
                tier: 0,
            },
            GddSymbol {
                id: 1,
                name: "B".into(),
                symbol_type: "regular".into(),
                pays: vec![],
                tier: 0,
            },
        ],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![],
        math: None,
    };

    assert!(schema.validate(&doc).is_err());
}

#[test]
fn schema_unknown_volatility_warns() {
    let schema = GddSchema::default();
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test".into(),
            provider: None,
            volatility: Some("super_extreme".into()),
            target_rtp: None,
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![],
        math: None,
    };

    let warnings = schema.validate(&doc).unwrap();
    assert!(!warnings.is_empty());
}

// ─── Constraint Validation ───────────────────────────────────────────────────

#[test]
fn constraint_megaways_grid_warning() {
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test".into(),
            provider: None,
            volatility: Some("high".into()),
            target_rtp: Some(0.965),
        },
        grid: GddGrid {
            reels: 3,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "megaways".into(),
        features: vec![],
        win_tiers: vec![],
        math: None,
    };

    let report = validate_constraints(&doc).unwrap();
    assert!(report.warnings.iter().any(|w| w.contains("Megaways")));
}

#[test]
fn constraint_rtp_mismatch() {
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test".into(),
            provider: None,
            volatility: None,
            target_rtp: Some(0.96),
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![],
        math: Some(GddMath {
            target_rtp: 0.94,
            volatility: None,
            symbol_weights: Default::default(),
        }),
    };

    let report = validate_constraints(&doc).unwrap();
    assert!(!report.valid);
    assert!(report.errors.iter().any(|e| e.contains("RTP mismatch")));
}

#[test]
fn constraint_win_tier_gap() {
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test".into(),
            provider: None,
            volatility: Some("high".into()),
            target_rtp: Some(0.965),
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![
            GddWinTier {
                name: "Small".into(),
                min_ratio: Some(1.0),
                max_ratio: Some(5.0),
            },
            GddWinTier {
                name: "Mega".into(),
                min_ratio: Some(50.0),
                max_ratio: Some(200.0),
            },
        ],
        math: None,
    };

    let report = validate_constraints(&doc).unwrap();
    assert!(report.warnings.iter().any(|w| w.contains("Gap")));
}

#[test]
fn constraint_fluxmacro_no_features() {
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test".into(),
            provider: None,
            volatility: None,
            target_rtp: None,
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![],
        win_tiers: vec![],
        math: None,
    };

    let report = validate_constraints(&doc).unwrap();
    // Should have FluxMacro-related warnings
    assert!(
        report.warnings.iter().any(|w| w.contains("FluxMacro"))
            || report.suggestions.iter().any(|s| s.contains("FluxMacro"))
    );
}

#[test]
fn constraint_many_bonus_features() {
    let doc = GddDocument {
        game: GddGame {
            name: "Test".into(),
            id: "test".into(),
            provider: None,
            volatility: Some("high".into()),
            target_rtp: Some(0.965),
        },
        grid: GddGrid {
            reels: 5,
            rows: 3,
            paylines: None,
        },
        symbols: vec![],
        win_mechanism: "paylines".into(),
        features: vec![
            GddFeature {
                feature_type: "free_spins".into(),
                trigger: "scatter".into(),
                params: Default::default(),
            },
            GddFeature {
                feature_type: "pick_bonus".into(),
                trigger: "bonus".into(),
                params: Default::default(),
            },
            GddFeature {
                feature_type: "wheel_bonus".into(),
                trigger: "wheel".into(),
                params: Default::default(),
            },
            GddFeature {
                feature_type: "hold_and_win".into(),
                trigger: "coins".into(),
                params: Default::default(),
            },
        ],
        win_tiers: vec![],
        math: None,
    };

    let report = validate_constraints(&doc).unwrap();
    assert!(report.warnings.iter().any(|w| w.contains("bonus features")));
}

// ─── Full Validation Pipeline ────────────────────────────────────────────────

#[test]
fn full_validate_json_pass() {
    let parser = GddParser::new();
    let report = parser.full_validate(FULL_JSON, false).unwrap();
    assert!(report.valid);
}

#[test]
fn full_validate_yaml_pass() {
    let parser = GddParser::new();
    let report = parser.full_validate(FULL_YAML, true).unwrap();
    assert!(report.valid);
}

#[test]
fn full_validate_invalid_json() {
    let parser = GddParser::new();
    let result = parser.full_validate("not json", false);
    assert!(result.is_err());
}

#[test]
fn full_validate_invalid_yaml() {
    let parser = GddParser::new();
    let result = parser.full_validate("not: [valid {{yaml", true);
    assert!(result.is_err());
}
