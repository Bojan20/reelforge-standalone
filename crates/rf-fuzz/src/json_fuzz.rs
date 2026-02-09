//! JSON deserialization fuzz targets
//!
//! Generates malformed JSON data for GDD (Game Design Documents), templates,
//! and preset configurations to test deserialization robustness.
//! Tests deeply nested structures, type mismatches, overflow values,
//! and extremely large strings.

use crate::config::FuzzConfig;
use crate::generators::InputGenerator;
use crate::harness::{FuzzResult, FuzzRunner};
use crate::report::FuzzReport;
use serde_json::Value;

// ============================================================================
// GDD JSON generator
// ============================================================================

/// Generates malformed Game Design Document JSON structures.
///
/// A valid GDD has the following shape:
/// ```json
/// {
///   "name": "Game Name",
///   "version": "1.0",
///   "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
///   "symbols": [{ "id": "HP1", "name": "...", "tier": "high", "payouts": {...} }],
///   "features": [{ "id": "freespins", "type": "freespins", ... }],
///   "math": { "rtp": 96.5, "volatility": "high", "hit_frequency": 0.25 }
/// }
/// ```
pub struct GddJsonGenerator;

impl GddJsonGenerator {
    /// Generate a valid GDD JSON string.
    pub fn valid_gdd() -> String {
        serde_json::json!({
            "name": "Test Slot Game",
            "version": "1.0",
            "grid": {
                "rows": 3,
                "columns": 5,
                "mechanic": "ways",
                "paylines": null,
                "ways": 243
            },
            "symbols": [
                {
                    "id": "HP1",
                    "name": "Diamond",
                    "tier": "high",
                    "isWild": false,
                    "isScatter": false,
                    "isBonus": false,
                    "payouts": { "3": 20, "4": 50, "5": 100 }
                },
                {
                    "id": "WILD",
                    "name": "Wild Star",
                    "tier": "premium",
                    "isWild": true,
                    "isScatter": false,
                    "isBonus": false,
                    "payouts": { "3": 50, "4": 150, "5": 500 }
                }
            ],
            "features": [
                {
                    "id": "freespins",
                    "type": "freespins",
                    "trigger": "3+ scatters",
                    "spins": 10
                }
            ],
            "math": {
                "rtp": 96.5,
                "volatility": "high",
                "hit_frequency": 0.25
            }
        })
        .to_string()
    }

    /// Generate a fuzzed GDD JSON string.
    pub fn fuzzed_gdd(gen: &mut InputGenerator) -> String {
        let corruption = gen.u32() % 14;
        match corruption {
            0 => Self::missing_required_fields(gen),
            1 => Self::wrong_field_types(gen),
            2 => Self::extreme_grid_values(gen),
            3 => Self::empty_symbols_array(gen),
            4 => Self::huge_symbols_array(gen),
            5 => Self::invalid_symbol_tiers(gen),
            6 => Self::nan_inf_numeric_fields(gen),
            7 => Self::negative_payout_values(gen),
            8 => Self::deeply_nested_features(gen),
            9 => Self::extremely_long_strings(gen),
            10 => Self::unicode_stress_test(gen),
            11 => Self::null_everywhere(gen),
            12 => Self::extra_unexpected_fields(gen),
            13 => Self::duplicate_keys(gen),
            _ => Self::valid_gdd(),
        }
    }

    /// Omit one or more required top-level fields.
    fn missing_required_fields(gen: &mut InputGenerator) -> String {
        let mut obj = serde_json::json!({
            "name": "Test Game",
            "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
            "symbols": [],
            "features": [],
            "math": { "rtp": 96.5, "volatility": "high" }
        });

        let fields = ["name", "version", "grid", "symbols", "features", "math"];
        let remove_count = (gen.u32() % 4) as usize + 1;
        for i in 0..remove_count {
            let field_idx = (gen.u32() as usize + i) % fields.len();
            if let Value::Object(ref mut map) = obj {
                map.remove(fields[field_idx]);
            }
        }

        obj.to_string()
    }

    /// Replace fields with wrong types (string where number expected, etc.).
    fn wrong_field_types(gen: &mut InputGenerator) -> String {
        let wrong_type = gen.u32() % 6;
        match wrong_type {
            0 => {
                // grid.rows as string
                serde_json::json!({
                    "name": "Test", "version": "1.0",
                    "grid": { "rows": "three", "columns": "five", "mechanic": "ways" },
                    "symbols": [], "features": [],
                    "math": { "rtp": 96.5, "volatility": "high" }
                })
                .to_string()
            }
            1 => {
                // math.rtp as string
                serde_json::json!({
                    "name": "Test", "version": "1.0",
                    "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
                    "symbols": [], "features": [],
                    "math": { "rtp": "ninety-six", "volatility": 42 }
                })
                .to_string()
            }
            2 => {
                // symbols as object instead of array
                serde_json::json!({
                    "name": "Test", "version": "1.0",
                    "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
                    "symbols": { "HP1": { "name": "Diamond" } },
                    "features": [], "math": { "rtp": 96.5, "volatility": "high" }
                })
                .to_string()
            }
            3 => {
                // name as number
                serde_json::json!({
                    "name": 12345, "version": true,
                    "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
                    "symbols": [], "features": [],
                    "math": { "rtp": 96.5, "volatility": "high" }
                })
                .to_string()
            }
            4 => {
                // features as string
                serde_json::json!({
                    "name": "Test", "version": "1.0",
                    "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
                    "symbols": [], "features": "none",
                    "math": { "rtp": 96.5, "volatility": "high" }
                })
                .to_string()
            }
            _ => {
                // grid as array
                serde_json::json!({
                    "name": "Test", "version": "1.0",
                    "grid": [3, 5, "ways"],
                    "symbols": [], "features": [],
                    "math": { "rtp": 96.5, "volatility": "high" }
                })
                .to_string()
            }
        }
    }

    /// Grid with extreme row/column values (0, negative via overflow, huge).
    fn extreme_grid_values(gen: &mut InputGenerator) -> String {
        let rows = match gen.u32() % 5 {
            0 => Value::from(0),
            1 => Value::from(-1),
            2 => Value::from(i64::MAX),
            3 => Value::from(u64::MAX),
            _ => Value::from(1_000_000),
        };
        let columns = match gen.u32() % 5 {
            0 => Value::from(0),
            1 => Value::from(-1),
            2 => Value::from(i64::MAX),
            3 => Value::from(u64::MAX),
            _ => Value::from(999_999),
        };

        serde_json::json!({
            "name": "Extreme Grid", "version": "1.0",
            "grid": { "rows": rows, "columns": columns, "mechanic": "ways" },
            "symbols": [], "features": [],
            "math": { "rtp": 96.5, "volatility": "high" }
        })
        .to_string()
    }

    /// Symbols array is empty.
    fn empty_symbols_array(_gen: &mut InputGenerator) -> String {
        serde_json::json!({
            "name": "Empty Symbols", "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "lines" },
            "symbols": [],
            "features": [],
            "math": { "rtp": 96.5, "volatility": "medium" }
        })
        .to_string()
    }

    /// Very large symbols array to stress memory allocation.
    fn huge_symbols_array(gen: &mut InputGenerator) -> String {
        let count = match gen.u32() % 4 {
            0 => 100,
            1 => 500,
            2 => 1000,
            _ => 5000,
        };

        let symbols: Vec<Value> = (0..count)
            .map(|i| {
                serde_json::json!({
                    "id": format!("SYM_{}", i),
                    "name": format!("Symbol {}", i),
                    "tier": "low",
                    "isWild": false,
                    "isScatter": false,
                    "isBonus": false,
                    "payouts": { "3": i, "4": i * 2, "5": i * 5 }
                })
            })
            .collect();

        serde_json::json!({
            "name": "Huge Symbols", "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
            "symbols": symbols,
            "features": [],
            "math": { "rtp": 96.5, "volatility": "high" }
        })
        .to_string()
    }

    /// Symbols with invalid tier values.
    fn invalid_symbol_tiers(gen: &mut InputGenerator) -> String {
        let bad_tier = match gen.u32() % 5 {
            0 => Value::from(""),
            1 => Value::from("ultra_legendary"),
            2 => Value::from(42),
            3 => Value::Null,
            _ => Value::from(true),
        };

        serde_json::json!({
            "name": "Bad Tiers", "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
            "symbols": [{
                "id": "BAD1", "name": "Bad Tier Symbol",
                "tier": bad_tier, "isWild": false, "isScatter": false, "isBonus": false,
                "payouts": { "3": 10 }
            }],
            "features": [],
            "math": { "rtp": 96.5, "volatility": "high" }
        })
        .to_string()
    }

    /// Numeric fields set to NaN, Infinity, or near-overflow values.
    fn nan_inf_numeric_fields(gen: &mut InputGenerator) -> String {
        let bad_rtp = match gen.u32() % 5 {
            0 => "NaN".to_string(),
            1 => "Infinity".to_string(),
            2 => "-Infinity".to_string(),
            3 => format!("{}", f64::MAX),
            _ => format!("{}", f64::MIN),
        };
        // Use raw JSON to embed non-standard numeric literals
        format!(
            r#"{{"name":"NaN Test","version":"1.0","grid":{{"rows":3,"columns":5,"mechanic":"ways"}},"symbols":[],"features":[],"math":{{"rtp":{},"volatility":"high","hit_frequency":{}}}}}"#,
            bad_rtp,
            if gen.bool() { "NaN" } else { "-0.0" }
        )
    }

    /// Payouts with negative values or non-integer keys.
    fn negative_payout_values(gen: &mut InputGenerator) -> String {
        let bad_payout = match gen.u32() % 4 {
            0 => serde_json::json!({ "3": -100, "4": -200, "5": -500 }),
            1 => serde_json::json!({ "0": 10, "-1": 20, "100": 500 }),
            2 => serde_json::json!({ "abc": 10, "": 20 }),
            _ => serde_json::json!({ "3": 1e308, "4": -1e308 }),
        };

        serde_json::json!({
            "name": "Bad Payouts", "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "lines" },
            "symbols": [{
                "id": "HP1", "name": "Diamond", "tier": "high",
                "isWild": false, "isScatter": false, "isBonus": false,
                "payouts": bad_payout
            }],
            "features": [],
            "math": { "rtp": 96.5, "volatility": "high" }
        })
        .to_string()
    }

    /// Features array with deeply nested sub-objects.
    fn deeply_nested_features(gen: &mut InputGenerator) -> String {
        let depth = match gen.u32() % 4 {
            0 => 10,
            1 => 50,
            2 => 100,
            _ => 200,
        };

        // Build nested object: { "inner": { "inner": { ... } } }
        let mut nested = serde_json::json!({ "value": "leaf" });
        for _ in 0..depth {
            nested = serde_json::json!({ "inner": nested });
        }

        serde_json::json!({
            "name": "Deep Nesting", "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
            "symbols": [],
            "features": [{ "id": "deep", "type": "custom", "config": nested }],
            "math": { "rtp": 96.5, "volatility": "high" }
        })
        .to_string()
    }

    /// String fields with extremely long values.
    fn extremely_long_strings(gen: &mut InputGenerator) -> String {
        let len = match gen.u32() % 4 {
            0 => 1_000,
            1 => 10_000,
            2 => 100_000,
            _ => 500_000,
        };
        let long_string: String = (0..len).map(|i| (b'A' + (i % 26) as u8) as char).collect();

        serde_json::json!({
            "name": long_string,
            "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
            "symbols": [{
                "id": "HP1",
                "name": long_string[..long_string.len().min(1000)].to_string(),
                "tier": "high", "isWild": false, "isScatter": false, "isBonus": false,
                "payouts": { "3": 10 }
            }],
            "features": [],
            "math": { "rtp": 96.5, "volatility": "high" }
        })
        .to_string()
    }

    /// String fields with various Unicode edge cases.
    fn unicode_stress_test(gen: &mut InputGenerator) -> String {
        let name = match gen.u32() % 6 {
            0 => "\u{0000}\u{0001}\u{0002}".to_string(), // control chars
            1 => "\u{FEFF}\u{200B}\u{200C}".to_string(), // BOM + zero-width
            2 => "A\u{0300}\u{0301}\u{0302}\u{0303}".to_string(), // combining marks
            3 => "\u{FFFD}".to_string(),                 // replacement char (surrogate proxy)
            4 => "\u{1F600}\u{1F4A9}\u{1F525}".to_string(), // emoji
            _ => "\0\0\0\0".to_string(),                 // null bytes
        };

        serde_json::json!({
            "name": name,
            "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
            "symbols": [], "features": [],
            "math": { "rtp": 96.5, "volatility": "high" }
        })
        .to_string()
    }

    /// All optional fields set to null.
    fn null_everywhere(_gen: &mut InputGenerator) -> String {
        serde_json::json!({
            "name": null,
            "version": null,
            "grid": null,
            "symbols": null,
            "features": null,
            "math": null
        })
        .to_string()
    }

    /// Valid structure but with many unexpected extra fields.
    fn extra_unexpected_fields(gen: &mut InputGenerator) -> String {
        let extra_count = (gen.u32() % 50) + 5;
        let mut obj = serde_json::json!({
            "name": "Extra Fields", "version": "1.0",
            "grid": { "rows": 3, "columns": 5, "mechanic": "ways" },
            "symbols": [], "features": [],
            "math": { "rtp": 96.5, "volatility": "high" }
        });

        if let Value::Object(ref mut map) = obj {
            for i in 0..extra_count {
                let key = format!("__extra_field_{}", i);
                let value = match gen.u32() % 4 {
                    0 => Value::from(gen.i32()),
                    1 => Value::from(format!("extra_{}", i)),
                    2 => Value::Bool(gen.bool()),
                    _ => Value::Null,
                };
                map.insert(key, value);
            }
        }

        obj.to_string()
    }

    /// JSON string with duplicate keys (behavior is implementation-defined).
    fn duplicate_keys(_gen: &mut InputGenerator) -> String {
        // Raw JSON with intentionally duplicated keys
        r#"{"name":"First","name":"Second","version":"1.0","version":"2.0","grid":{"rows":3,"columns":5,"rows":7,"mechanic":"ways"},"symbols":[],"features":[],"math":{"rtp":96.5,"rtp":50.0,"volatility":"high"}}"#.to_string()
    }
}

// ============================================================================
// Template JSON generator
// ============================================================================

/// Generates malformed template JSON structures.
///
/// Templates define starter configurations for SlotLab projects,
/// including grid settings, win tiers, bus config, and auto-wiring rules.
pub struct TemplateJsonGenerator;

impl TemplateJsonGenerator {
    /// Generate a valid template JSON string.
    pub fn valid_template() -> String {
        serde_json::json!({
            "id": "classic_5x3",
            "name": "Classic 5x3",
            "version": "1.0.0",
            "category": "classic",
            "grid": { "reels": 5, "rows": 3 },
            "symbols": [
                { "id": "HP1", "type": "highPay", "emoji": "\u{1F48E}" },
                { "id": "WILD", "type": "wild", "emoji": "\u{2B50}" },
                { "id": "SCATTER", "type": "scatter", "emoji": "\u{1F4A0}" }
            ],
            "winTiers": [
                { "tier": "tier1", "threshold": 1.0, "label": "WIN 1" },
                { "tier": "tier2", "threshold": 5.0, "label": "WIN 2" },
                { "tier": "tier3", "threshold": 15.0, "label": "WIN 3" }
            ],
            "buses": ["Master", "SFX", "Music", "Voice"],
            "stages": ["SPIN_START", "REEL_STOP", "WIN_PRESENT"]
        })
        .to_string()
    }

    /// Generate a fuzzed template JSON string.
    pub fn fuzzed_template(gen: &mut InputGenerator) -> String {
        let corruption = gen.u32() % 10;
        match corruption {
            0 => Self::missing_id_or_name(gen),
            1 => Self::invalid_category(gen),
            2 => Self::extreme_grid(gen),
            3 => Self::empty_collections(gen),
            4 => Self::invalid_win_tier_thresholds(gen),
            5 => Self::huge_stage_list(gen),
            6 => Self::nested_template_reference(gen),
            7 => Self::invalid_version_format(gen),
            8 => Self::symbol_type_mismatch(gen),
            9 => Self::completely_empty_object(gen),
            _ => Self::valid_template(),
        }
    }

    fn missing_id_or_name(gen: &mut InputGenerator) -> String {
        let mut obj = serde_json::from_str::<Value>(&Self::valid_template()).unwrap();
        if let Value::Object(ref mut map) = obj {
            if gen.bool() {
                map.remove("id");
            } else {
                map.remove("name");
            }
        }
        obj.to_string()
    }

    fn invalid_category(gen: &mut InputGenerator) -> String {
        let bad_cat = match gen.u32() % 4 {
            0 => Value::from(""),
            1 => Value::from("nonexistent_category_type"),
            2 => Value::from(42),
            _ => Value::Array(vec![Value::from("classic")]),
        };
        let mut obj = serde_json::from_str::<Value>(&Self::valid_template()).unwrap();
        if let Value::Object(ref mut map) = obj {
            map.insert("category".to_string(), bad_cat);
        }
        obj.to_string()
    }

    fn extreme_grid(gen: &mut InputGenerator) -> String {
        let reels = match gen.u32() % 4 {
            0 => Value::from(0),
            1 => Value::from(-5),
            2 => Value::from(1_000_000),
            _ => Value::from(i64::MAX),
        };
        let rows = match gen.u32() % 4 {
            0 => Value::from(0),
            1 => Value::from(-1),
            2 => Value::from(999_999),
            _ => Value::from(u64::MAX),
        };
        serde_json::json!({
            "id": "extreme", "name": "Extreme Grid", "version": "1.0.0",
            "category": "classic",
            "grid": { "reels": reels, "rows": rows },
            "symbols": [], "winTiers": [], "buses": [], "stages": []
        })
        .to_string()
    }

    fn empty_collections(_gen: &mut InputGenerator) -> String {
        serde_json::json!({
            "id": "empty", "name": "Empty Collections", "version": "1.0.0",
            "category": "classic",
            "grid": { "reels": 5, "rows": 3 },
            "symbols": [],
            "winTiers": [],
            "buses": [],
            "stages": []
        })
        .to_string()
    }

    fn invalid_win_tier_thresholds(gen: &mut InputGenerator) -> String {
        let bad_threshold = match gen.u32() % 5 {
            0 => Value::from(-1.0),
            1 => Value::from(0.0),
            2 => Value::from(f64::MAX),
            3 => Value::from("not_a_number"),
            _ => Value::Null,
        };
        serde_json::json!({
            "id": "bad_tiers", "name": "Bad Tiers", "version": "1.0.0",
            "category": "classic",
            "grid": { "reels": 5, "rows": 3 },
            "symbols": [],
            "winTiers": [
                { "tier": "tier1", "threshold": bad_threshold, "label": "WIN" }
            ],
            "buses": [], "stages": []
        })
        .to_string()
    }

    fn huge_stage_list(gen: &mut InputGenerator) -> String {
        let count = match gen.u32() % 3 {
            0 => 1000,
            1 => 5000,
            _ => 10000,
        };
        let stages: Vec<Value> = (0..count)
            .map(|i| Value::from(format!("CUSTOM_STAGE_{}", i)))
            .collect();

        serde_json::json!({
            "id": "huge", "name": "Huge Stages", "version": "1.0.0",
            "category": "classic",
            "grid": { "reels": 5, "rows": 3 },
            "symbols": [], "winTiers": [], "buses": [],
            "stages": stages
        })
        .to_string()
    }

    fn nested_template_reference(gen: &mut InputGenerator) -> String {
        let depth = match gen.u32() % 3 {
            0 => 10,
            1 => 50,
            _ => 100,
        };
        let mut inner = serde_json::json!({ "ref": "leaf_template" });
        for _ in 0..depth {
            inner = serde_json::json!({ "extends": inner });
        }
        serde_json::json!({
            "id": "recursive", "name": "Recursive", "version": "1.0.0",
            "category": "custom",
            "grid": { "reels": 5, "rows": 3 },
            "symbols": [], "winTiers": [], "buses": [], "stages": [],
            "parent": inner
        })
        .to_string()
    }

    fn invalid_version_format(gen: &mut InputGenerator) -> String {
        let bad_version = match gen.u32() % 5 {
            0 => Value::from(""),
            1 => Value::from("not.semver"),
            2 => Value::from("999.999.999"),
            3 => Value::from(-1),
            _ => Value::Array(vec![Value::from(1), Value::from(0), Value::from(0)]),
        };
        let mut obj = serde_json::from_str::<Value>(&Self::valid_template()).unwrap();
        if let Value::Object(ref mut map) = obj {
            map.insert("version".to_string(), bad_version);
        }
        obj.to_string()
    }

    fn symbol_type_mismatch(gen: &mut InputGenerator) -> String {
        let bad_type = match gen.u32() % 4 {
            0 => Value::from(42),
            1 => Value::from(""),
            2 => Value::from(true),
            _ => Value::Array(vec![]),
        };
        serde_json::json!({
            "id": "bad_sym", "name": "Bad Symbols", "version": "1.0.0",
            "category": "classic",
            "grid": { "reels": 5, "rows": 3 },
            "symbols": [{ "id": "HP1", "type": bad_type, "emoji": "X" }],
            "winTiers": [], "buses": [], "stages": []
        })
        .to_string()
    }

    fn completely_empty_object(_gen: &mut InputGenerator) -> String {
        "{}".to_string()
    }
}

// ============================================================================
// Preset JSON generator
// ============================================================================

/// Generates malformed preset JSON for DSP/workspace/channel presets.
pub struct PresetJsonGenerator;

impl PresetJsonGenerator {
    /// Generate a valid preset JSON string.
    pub fn valid_preset() -> String {
        serde_json::json!({
            "name": "Default Preset",
            "version": 1,
            "category": "factory",
            "parameters": {
                "volume": 0.8,
                "pan": 0.0,
                "eq_low": 0.0,
                "eq_mid": 0.0,
                "eq_high": 0.0,
                "compressor_threshold": -12.0,
                "compressor_ratio": 4.0,
                "reverb_mix": 0.2
            },
            "metadata": {
                "author": "FluxForge",
                "description": "Default channel strip preset",
                "tags": ["default", "mixing"]
            }
        })
        .to_string()
    }

    /// Generate a fuzzed preset JSON string.
    pub fn fuzzed_preset(gen: &mut InputGenerator) -> String {
        let corruption = gen.u32() % 10;
        match corruption {
            0 => Self::invalid_parameter_types(gen),
            1 => Self::out_of_range_values(gen),
            2 => Self::missing_parameters(gen),
            3 => Self::extra_parameters(gen),
            4 => Self::deeply_nested_preset(gen),
            5 => Self::empty_preset(gen),
            6 => Self::huge_tag_list(gen),
            7 => Self::invalid_version(gen),
            8 => Self::binary_in_strings(gen),
            9 => Self::numeric_overflow(gen),
            _ => Self::valid_preset(),
        }
    }

    fn invalid_parameter_types(gen: &mut InputGenerator) -> String {
        let bad_val = match gen.u32() % 5 {
            0 => Value::from("not_a_number"),
            1 => Value::Bool(true),
            2 => Value::Array(vec![Value::from(1.0)]),
            3 => Value::Object(serde_json::Map::new()),
            _ => Value::Null,
        };
        serde_json::json!({
            "name": "Bad Types", "version": 1, "category": "factory",
            "parameters": {
                "volume": bad_val,
                "pan": "center",
                "eq_low": [1, 2, 3]
            },
            "metadata": { "author": "test", "description": "", "tags": [] }
        })
        .to_string()
    }

    fn out_of_range_values(_gen: &mut InputGenerator) -> String {
        serde_json::json!({
            "name": "Out of Range", "version": 1, "category": "factory",
            "parameters": {
                "volume": 999.99,
                "pan": -100.0,
                "eq_low": 1e308,
                "eq_mid": -1e308,
                "compressor_threshold": f64::MIN,
                "compressor_ratio": f64::MAX,
                "reverb_mix": -0.0
            },
            "metadata": { "author": "test", "description": "", "tags": [] }
        })
        .to_string()
    }

    fn missing_parameters(_gen: &mut InputGenerator) -> String {
        serde_json::json!({
            "name": "Missing Params", "version": 1, "category": "factory",
            "parameters": {},
            "metadata": { "author": "test", "description": "", "tags": [] }
        })
        .to_string()
    }

    fn extra_parameters(gen: &mut InputGenerator) -> String {
        let extra_count = (gen.u32() % 200) + 10;
        let mut params = serde_json::Map::new();
        params.insert("volume".to_string(), Value::from(0.8));
        for i in 0..extra_count {
            params.insert(
                format!("custom_param_{}", i),
                Value::from(gen.f64_range(0.0, 1.0)),
            );
        }
        serde_json::json!({
            "name": "Extra Params", "version": 1, "category": "factory",
            "parameters": params,
            "metadata": { "author": "test", "description": "", "tags": [] }
        })
        .to_string()
    }

    fn deeply_nested_preset(gen: &mut InputGenerator) -> String {
        let depth = match gen.u32() % 3 {
            0 => 50,
            1 => 200,
            _ => 500,
        };
        let mut nested = serde_json::json!({ "value": 0.5 });
        for _ in 0..depth {
            nested = serde_json::json!({ "layer": nested });
        }
        serde_json::json!({
            "name": "Deep Nested", "version": 1, "category": "factory",
            "parameters": { "complex": nested },
            "metadata": { "author": "test", "description": "", "tags": [] }
        })
        .to_string()
    }

    fn empty_preset(_gen: &mut InputGenerator) -> String {
        serde_json::json!({}).to_string()
    }

    fn huge_tag_list(gen: &mut InputGenerator) -> String {
        let count = match gen.u32() % 3 {
            0 => 100,
            1 => 1000,
            _ => 5000,
        };
        let tags: Vec<Value> = (0..count)
            .map(|i| Value::from(format!("tag_{}", i)))
            .collect();
        serde_json::json!({
            "name": "Huge Tags", "version": 1, "category": "factory",
            "parameters": { "volume": 0.8 },
            "metadata": { "author": "test", "description": "", "tags": tags }
        })
        .to_string()
    }

    fn invalid_version(gen: &mut InputGenerator) -> String {
        let bad_version = match gen.u32() % 4 {
            0 => Value::from(-1),
            1 => Value::from(i64::MAX),
            2 => Value::from("v1.0"),
            _ => Value::Null,
        };
        let mut obj = serde_json::from_str::<Value>(&Self::valid_preset()).unwrap();
        if let Value::Object(ref mut map) = obj {
            map.insert("version".to_string(), bad_version);
        }
        obj.to_string()
    }

    fn binary_in_strings(_gen: &mut InputGenerator) -> String {
        // Build JSON with embedded control characters and unusual Unicode
        serde_json::json!({
            "name": "Binary\x00Test\x01\x02\x03",
            "version": 1,
            "category": "factory\x00injected",
            "parameters": { "volume": 0.8 },
            "metadata": {
                "author": "\x7F\u{0080}\u{0081}\u{0082}",
                "description": "Has \x00 nulls",
                "tags": ["\x00", "\u{00FF}"]
            }
        })
        .to_string()
    }

    fn numeric_overflow(_gen: &mut InputGenerator) -> String {
        // Raw JSON with numbers that exceed f64 precision
        r#"{"name":"Overflow","version":99999999999999999999999999999999,"category":"factory","parameters":{"volume":1.7976931348623157e+309,"pan":-1.7976931348623157e+309,"ratio":0.00000000000000000000000000000001},"metadata":{"author":"test","description":"","tags":[]}}"#.to_string()
    }
}

// ============================================================================
// Raw / malformed JSON generators
// ============================================================================

/// Generates syntactically malformed JSON strings.
pub struct MalformedJsonGenerator;

impl MalformedJsonGenerator {
    /// Generate syntactically broken JSON.
    pub fn broken_json(gen: &mut InputGenerator) -> String {
        let variant = gen.u32() % 12;
        match variant {
            0 => "".to_string(),                     // empty
            1 => "{".to_string(),                    // unclosed
            2 => "}".to_string(),                    // unexpected close
            3 => "{{}}".to_string(),                 // double braces
            4 => r#"{"key": }"#.to_string(),         // missing value
            5 => r#"{"key" "value"}"#.to_string(),   // missing colon
            6 => r#"{"key": "value",}"#.to_string(), // trailing comma
            7 => "null".to_string(),                 // bare null
            8 => "42".to_string(),                   // bare number
            9 => r#"["unclosed"#.to_string(),        // unclosed array
            10 => Self::deeply_nested_braces(gen),
            11 => Self::random_garbage(gen),
            _ => "{}".to_string(),
        }
    }

    /// Generate deeply nested braces for stack overflow testing.
    fn deeply_nested_braces(gen: &mut InputGenerator) -> String {
        let depth = match gen.u32() % 4 {
            0 => 100,
            1 => 500,
            2 => 1000,
            _ => 5000,
        };
        let open: String = (0..depth).map(|_| '{').collect();
        let close: String = (0..depth).map(|_| '}').collect();
        format!("{}\"key\":\"value\"{}", open, close)
    }

    /// Generate random bytes interpreted as a "JSON" string.
    fn random_garbage(gen: &mut InputGenerator) -> String {
        let len = gen.u32() as usize % 512;
        let bytes = gen.bytes(len);
        // Try to interpret as lossy UTF-8
        String::from_utf8_lossy(&bytes).to_string()
    }
}

// ============================================================================
// Fuzz target runners
// ============================================================================

/// Runs all JSON fuzz targets and collects results into a `FuzzReport`.
pub fn run_json_fuzz_suite(config: &FuzzConfig) -> FuzzReport {
    let mut report = FuzzReport::new("JSON Deserialization Fuzz Suite");

    // GDD targets
    report.add_result("gdd_parse_resilience", fuzz_gdd_parse(config));
    report.add_result("gdd_field_validation", fuzz_gdd_field_validation(config));

    // Template targets
    report.add_result("template_parse_resilience", fuzz_template_parse(config));
    report.add_result(
        "template_field_validation",
        fuzz_template_field_validation(config),
    );

    // Preset targets
    report.add_result("preset_parse_resilience", fuzz_preset_parse(config));
    report.add_result(
        "preset_parameter_validation",
        fuzz_preset_parameter_validation(config),
    );

    // Raw / malformed JSON targets
    report.add_result("malformed_json_resilience", fuzz_malformed_json(config));
    report.add_result("deeply_nested_json", fuzz_deeply_nested(config));

    report
}

/// Fuzz target: parse randomly corrupted GDD JSON.
pub fn fuzz_gdd_parse(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| GddJsonGenerator::fuzzed_gdd(gen),
        |json_str| parse_gdd_safe(&json_str),
    )
}

/// Fuzz target: validate GDD field values after parsing.
pub fn fuzz_gdd_field_validation(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| GddJsonGenerator::fuzzed_gdd(gen),
        |json_str| parse_gdd_safe(&json_str),
        |_input, result| match result {
            GddParseResult::Valid {
                grid_rows,
                grid_columns,
                symbol_count,
                ..
            } => {
                if *grid_rows == 0 {
                    return Err("Valid parse with zero rows".to_string());
                }
                if *grid_columns == 0 {
                    return Err("Valid parse with zero columns".to_string());
                }
                if *grid_rows > 100 {
                    return Err(format!("Rows too large: {}", grid_rows));
                }
                if *grid_columns > 100 {
                    return Err(format!("Columns too large: {}", grid_columns));
                }
                if *symbol_count > 10_000 {
                    return Err(format!("Too many symbols: {}", symbol_count));
                }
                Ok(())
            }
            GddParseResult::Invalid(_) => Ok(()),
        },
    )
}

/// Fuzz target: parse randomly corrupted template JSON.
pub fn fuzz_template_parse(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| TemplateJsonGenerator::fuzzed_template(gen),
        |json_str| parse_template_safe(&json_str),
    )
}

/// Fuzz target: validate template field values after parsing.
pub fn fuzz_template_field_validation(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| TemplateJsonGenerator::fuzzed_template(gen),
        |json_str| parse_template_safe(&json_str),
        |_input, result| match result {
            TemplateParseResult::Valid { reels, rows, .. } => {
                if *reels == 0 {
                    return Err("Valid parse with zero reels".to_string());
                }
                if *rows == 0 {
                    return Err("Valid parse with zero rows".to_string());
                }
                if *reels > 100 {
                    return Err(format!("Reels too large: {}", reels));
                }
                if *rows > 100 {
                    return Err(format!("Rows too large: {}", rows));
                }
                Ok(())
            }
            TemplateParseResult::Invalid(_) => Ok(()),
        },
    )
}

/// Fuzz target: parse randomly corrupted preset JSON.
pub fn fuzz_preset_parse(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| PresetJsonGenerator::fuzzed_preset(gen),
        |json_str| parse_preset_safe(&json_str),
    )
}

/// Fuzz target: validate preset parameter values after parsing.
pub fn fuzz_preset_parameter_validation(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_with_validation(
        |gen| PresetJsonGenerator::fuzzed_preset(gen),
        |json_str| parse_preset_safe(&json_str),
        |_input, result| match result {
            PresetParseResult::Valid { parameters, .. } => {
                for (key, value) in parameters {
                    if value.is_nan() {
                        return Err(format!("NaN value for parameter: {}", key));
                    }
                    if value.is_infinite() {
                        return Err(format!("Infinite value for parameter: {}", key));
                    }
                }
                Ok(())
            }
            PresetParseResult::Invalid(_) => Ok(()),
        },
    )
}

/// Fuzz target: feed syntactically broken JSON to parsers.
pub fn fuzz_malformed_json(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| MalformedJsonGenerator::broken_json(gen),
        |json_str| {
            // Try all parsers — none should panic
            let _ = parse_gdd_safe(&json_str);
            let _ = parse_template_safe(&json_str);
            let _ = parse_preset_safe(&json_str);
        },
    )
}

/// Fuzz target: exercise deeply nested JSON for stack overflow prevention.
pub fn fuzz_deeply_nested(config: &FuzzConfig) -> FuzzResult {
    let runner = FuzzRunner::new(config.clone());
    runner.fuzz_custom(
        |gen| {
            let depth = match gen.u32() % 5 {
                0 => 10,
                1 => 100,
                2 => 500,
                3 => 1000,
                _ => 2000,
            };
            let open: String = (0..depth).map(|_| "[").collect::<Vec<_>>().join("");
            let close: String = (0..depth).map(|_| "]").collect::<Vec<_>>().join("");
            format!("{}{}", open, close)
        },
        |json_str| {
            // serde_json has a default recursion limit; this tests it
            let _ = serde_json::from_str::<Value>(&json_str);
        },
    )
}

// ============================================================================
// Safe parsing functions (the targets under test)
// ============================================================================

/// Result of attempting to parse a GDD JSON.
#[derive(Debug, Clone)]
pub enum GddParseResult {
    Valid {
        name: String,
        grid_rows: u32,
        grid_columns: u32,
        symbol_count: usize,
        feature_count: usize,
        rtp: f64,
    },
    Invalid(String),
}

/// Result of attempting to parse a template JSON.
#[derive(Debug, Clone)]
pub enum TemplateParseResult {
    Valid {
        id: String,
        name: String,
        reels: u32,
        rows: u32,
        symbol_count: usize,
        stage_count: usize,
    },
    Invalid(String),
}

/// Result of attempting to parse a preset JSON.
#[derive(Debug, Clone)]
pub enum PresetParseResult {
    Valid {
        name: String,
        version: i64,
        parameters: Vec<(String, f64)>,
    },
    Invalid(String),
}

/// Safely parse GDD JSON from an arbitrary string.
///
/// Must never panic regardless of input.
pub fn parse_gdd_safe(json_str: &str) -> GddParseResult {
    let value: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => return GddParseResult::Invalid(format!("JSON parse error: {}", e)),
    };

    let obj = match value.as_object() {
        Some(o) => o,
        None => return GddParseResult::Invalid("Root is not an object".to_string()),
    };

    // Extract name
    let name = match obj.get("name").and_then(|v| v.as_str()) {
        Some(n) => n.to_string(),
        None => return GddParseResult::Invalid("Missing or invalid 'name'".to_string()),
    };

    // Extract grid
    let grid = match obj.get("grid").and_then(|v| v.as_object()) {
        Some(g) => g,
        None => return GddParseResult::Invalid("Missing or invalid 'grid'".to_string()),
    };

    let grid_rows = match grid.get("rows").and_then(|v| v.as_u64()) {
        Some(r) if r > 0 && r <= 100 => r as u32,
        Some(r) => return GddParseResult::Invalid(format!("Invalid rows: {}", r)),
        None => return GddParseResult::Invalid("Missing or invalid 'grid.rows'".to_string()),
    };

    let grid_columns = match grid.get("columns").and_then(|v| v.as_u64()) {
        Some(c) if c > 0 && c <= 100 => c as u32,
        Some(c) => return GddParseResult::Invalid(format!("Invalid columns: {}", c)),
        None => return GddParseResult::Invalid("Missing or invalid 'grid.columns'".to_string()),
    };

    // Extract symbols
    let symbol_count = match obj.get("symbols").and_then(|v| v.as_array()) {
        Some(arr) => arr.len(),
        None => return GddParseResult::Invalid("Missing or invalid 'symbols'".to_string()),
    };

    // Extract features
    let feature_count = match obj.get("features").and_then(|v| v.as_array()) {
        Some(arr) => arr.len(),
        None => return GddParseResult::Invalid("Missing or invalid 'features'".to_string()),
    };

    // Extract math.rtp
    let rtp = match obj
        .get("math")
        .and_then(|v| v.as_object())
        .and_then(|m| m.get("rtp"))
        .and_then(|v| v.as_f64())
    {
        Some(r) if r.is_finite() => r,
        Some(_) => return GddParseResult::Invalid("RTP is not finite".to_string()),
        None => return GddParseResult::Invalid("Missing or invalid 'math.rtp'".to_string()),
    };

    GddParseResult::Valid {
        name,
        grid_rows,
        grid_columns,
        symbol_count,
        feature_count,
        rtp,
    }
}

/// Safely parse template JSON from an arbitrary string.
///
/// Must never panic regardless of input.
pub fn parse_template_safe(json_str: &str) -> TemplateParseResult {
    let value: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => return TemplateParseResult::Invalid(format!("JSON parse error: {}", e)),
    };

    let obj = match value.as_object() {
        Some(o) => o,
        None => return TemplateParseResult::Invalid("Root is not an object".to_string()),
    };

    let id = match obj.get("id").and_then(|v| v.as_str()) {
        Some(i) if !i.is_empty() => i.to_string(),
        _ => return TemplateParseResult::Invalid("Missing or empty 'id'".to_string()),
    };

    let name = match obj.get("name").and_then(|v| v.as_str()) {
        Some(n) if !n.is_empty() => n.to_string(),
        _ => return TemplateParseResult::Invalid("Missing or empty 'name'".to_string()),
    };

    let grid = match obj.get("grid").and_then(|v| v.as_object()) {
        Some(g) => g,
        None => return TemplateParseResult::Invalid("Missing or invalid 'grid'".to_string()),
    };

    let reels = match grid.get("reels").and_then(|v| v.as_u64()) {
        Some(r) if r > 0 && r <= 100 => r as u32,
        _ => return TemplateParseResult::Invalid("Missing or invalid 'grid.reels'".to_string()),
    };

    let rows = match grid.get("rows").and_then(|v| v.as_u64()) {
        Some(r) if r > 0 && r <= 100 => r as u32,
        _ => return TemplateParseResult::Invalid("Missing or invalid 'grid.rows'".to_string()),
    };

    let symbol_count = obj
        .get("symbols")
        .and_then(|v| v.as_array())
        .map(|a| a.len())
        .unwrap_or(0);

    let stage_count = obj
        .get("stages")
        .and_then(|v| v.as_array())
        .map(|a| a.len())
        .unwrap_or(0);

    TemplateParseResult::Valid {
        id,
        name,
        reels,
        rows,
        symbol_count,
        stage_count,
    }
}

/// Safely parse preset JSON from an arbitrary string.
///
/// Must never panic regardless of input.
pub fn parse_preset_safe(json_str: &str) -> PresetParseResult {
    let value: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => return PresetParseResult::Invalid(format!("JSON parse error: {}", e)),
    };

    let obj = match value.as_object() {
        Some(o) => o,
        None => return PresetParseResult::Invalid("Root is not an object".to_string()),
    };

    let name = match obj.get("name").and_then(|v| v.as_str()) {
        Some(n) => n.to_string(),
        None => return PresetParseResult::Invalid("Missing or invalid 'name'".to_string()),
    };

    let version = match obj.get("version").and_then(|v| v.as_i64()) {
        Some(v) if v >= 0 => v,
        _ => return PresetParseResult::Invalid("Missing or invalid 'version'".to_string()),
    };

    // Extract parameters — all must be finite f64
    let parameters = match obj.get("parameters").and_then(|v| v.as_object()) {
        Some(params) => {
            let mut result = Vec::new();
            for (key, val) in params {
                match val.as_f64() {
                    Some(f) if f.is_finite() => {
                        result.push((key.clone(), f));
                    }
                    Some(f) => {
                        return PresetParseResult::Invalid(format!(
                            "Non-finite value for '{}': {}",
                            key, f
                        ));
                    }
                    None => {
                        return PresetParseResult::Invalid(format!(
                            "Non-numeric value for '{}'",
                            key
                        ));
                    }
                }
            }
            result
        }
        None => {
            return PresetParseResult::Invalid("Missing or invalid 'parameters'".to_string());
        }
    };

    PresetParseResult::Valid {
        name,
        version,
        parameters,
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // ---- Valid roundtrip tests ----

    #[test]
    fn test_valid_gdd_roundtrip() {
        let json = GddJsonGenerator::valid_gdd();
        match parse_gdd_safe(&json) {
            GddParseResult::Valid {
                name,
                grid_rows,
                grid_columns,
                symbol_count,
                rtp,
                ..
            } => {
                assert_eq!(name, "Test Slot Game");
                assert_eq!(grid_rows, 3);
                assert_eq!(grid_columns, 5);
                assert_eq!(symbol_count, 2);
                assert!((rtp - 96.5).abs() < 0.01);
            }
            GddParseResult::Invalid(e) => panic!("Valid GDD rejected: {}", e),
        }
    }

    #[test]
    fn test_valid_template_roundtrip() {
        let json = TemplateJsonGenerator::valid_template();
        match parse_template_safe(&json) {
            TemplateParseResult::Valid {
                id,
                name,
                reels,
                rows,
                symbol_count,
                stage_count,
            } => {
                assert_eq!(id, "classic_5x3");
                assert_eq!(name, "Classic 5x3");
                assert_eq!(reels, 5);
                assert_eq!(rows, 3);
                assert_eq!(symbol_count, 3);
                assert_eq!(stage_count, 3);
            }
            TemplateParseResult::Invalid(e) => panic!("Valid template rejected: {}", e),
        }
    }

    #[test]
    fn test_valid_preset_roundtrip() {
        let json = PresetJsonGenerator::valid_preset();
        match parse_preset_safe(&json) {
            PresetParseResult::Valid {
                name,
                version,
                parameters,
            } => {
                assert_eq!(name, "Default Preset");
                assert_eq!(version, 1);
                assert!(!parameters.is_empty());
                // Check volume parameter
                let vol = parameters.iter().find(|(k, _)| k == "volume");
                assert!(vol.is_some());
                assert!((vol.unwrap().1 - 0.8).abs() < 0.001);
            }
            PresetParseResult::Invalid(e) => panic!("Valid preset rejected: {}", e),
        }
    }

    // ---- Rejection tests ----

    #[test]
    fn test_empty_string_rejected() {
        assert!(matches!(parse_gdd_safe(""), GddParseResult::Invalid(_)));
        assert!(matches!(
            parse_template_safe(""),
            TemplateParseResult::Invalid(_)
        ));
        assert!(matches!(
            parse_preset_safe(""),
            PresetParseResult::Invalid(_)
        ));
    }

    #[test]
    fn test_null_json_rejected() {
        assert!(matches!(parse_gdd_safe("null"), GddParseResult::Invalid(_)));
        assert!(matches!(
            parse_template_safe("null"),
            TemplateParseResult::Invalid(_)
        ));
        assert!(matches!(
            parse_preset_safe("null"),
            PresetParseResult::Invalid(_)
        ));
    }

    #[test]
    fn test_array_json_rejected() {
        assert!(matches!(parse_gdd_safe("[]"), GddParseResult::Invalid(_)));
        assert!(matches!(
            parse_template_safe("[1,2,3]"),
            TemplateParseResult::Invalid(_)
        ));
        assert!(matches!(
            parse_preset_safe("[{}]"),
            PresetParseResult::Invalid(_)
        ));
    }

    #[test]
    fn test_empty_object_rejected() {
        assert!(matches!(parse_gdd_safe("{}"), GddParseResult::Invalid(_)));
        assert!(matches!(
            parse_template_safe("{}"),
            TemplateParseResult::Invalid(_)
        ));
        assert!(matches!(
            parse_preset_safe("{}"),
            PresetParseResult::Invalid(_)
        ));
    }

    #[test]
    fn test_gdd_missing_grid_rejected() {
        let json = r#"{"name":"Test","version":"1.0","symbols":[],"features":[],"math":{"rtp":96.5,"volatility":"high"}}"#;
        assert!(matches!(parse_gdd_safe(json), GddParseResult::Invalid(_)));
    }

    #[test]
    fn test_gdd_zero_rows_rejected() {
        let json = r#"{"name":"Test","version":"1.0","grid":{"rows":0,"columns":5,"mechanic":"ways"},"symbols":[],"features":[],"math":{"rtp":96.5,"volatility":"high"}}"#;
        assert!(matches!(parse_gdd_safe(json), GddParseResult::Invalid(_)));
    }

    #[test]
    fn test_template_missing_id_rejected() {
        let json = r#"{"name":"Test","version":"1.0.0","category":"classic","grid":{"reels":5,"rows":3},"symbols":[],"winTiers":[],"buses":[],"stages":[]}"#;
        assert!(matches!(
            parse_template_safe(json),
            TemplateParseResult::Invalid(_)
        ));
    }

    #[test]
    fn test_preset_negative_version_rejected() {
        let json = r#"{"name":"Test","version":-1,"category":"factory","parameters":{"volume":0.8},"metadata":{"author":"test","description":"","tags":[]}}"#;
        assert!(matches!(
            parse_preset_safe(json),
            PresetParseResult::Invalid(_)
        ));
    }

    #[test]
    fn test_preset_non_numeric_param_rejected() {
        let json = r#"{"name":"Test","version":1,"category":"factory","parameters":{"volume":"loud"},"metadata":{"author":"test","description":"","tags":[]}}"#;
        assert!(matches!(
            parse_preset_safe(json),
            PresetParseResult::Invalid(_)
        ));
    }

    // ---- Fuzz suite tests ----

    #[test]
    fn test_fuzz_gdd_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_gdd_parse(&config);
        assert!(
            result.passed,
            "GDD fuzz panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_gdd_field_validation() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_gdd_field_validation(&config);
        assert!(
            result.passed,
            "GDD field validation failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_template_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_template_parse(&config);
        assert!(
            result.passed,
            "Template fuzz panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_template_field_validation() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_template_field_validation(&config);
        assert!(
            result.passed,
            "Template validation failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_preset_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_preset_parse(&config);
        assert!(
            result.passed,
            "Preset fuzz panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_preset_parameter_validation() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_preset_parameter_validation(&config);
        assert!(
            result.passed,
            "Preset param validation failed: {:?}",
            result.failure_details
        );
    }

    #[test]
    fn test_fuzz_malformed_json_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(500);
        let result = fuzz_malformed_json(&config);
        assert!(
            result.passed,
            "Malformed JSON panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_fuzz_deeply_nested_no_panics() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(200);
        let result = fuzz_deeply_nested(&config);
        assert!(
            result.passed,
            "Deeply nested JSON panicked: {:?}",
            result.failure_details
        );
        assert_eq!(result.panics, 0);
    }

    #[test]
    fn test_full_json_fuzz_suite() {
        let config = FuzzConfig::minimal().with_seed(42).with_iterations(100);
        let report = run_json_fuzz_suite(&config);
        assert!(
            report.all_passed(),
            "JSON fuzz suite failed:\n{}",
            report.to_text()
        );
    }

    // ---- Generator determinism ----

    #[test]
    fn test_gdd_generator_determinism() {
        let mut gen1 = InputGenerator::new(Some(777), 4096);
        let mut gen2 = InputGenerator::new(Some(777), 4096);

        for _ in 0..20 {
            let gdd1 = GddJsonGenerator::fuzzed_gdd(&mut gen1);
            let gdd2 = GddJsonGenerator::fuzzed_gdd(&mut gen2);
            assert_eq!(gdd1, gdd2, "GDD generators diverged with same seed");
        }
    }

    #[test]
    fn test_template_generator_determinism() {
        let mut gen1 = InputGenerator::new(Some(888), 4096);
        let mut gen2 = InputGenerator::new(Some(888), 4096);

        for _ in 0..20 {
            let t1 = TemplateJsonGenerator::fuzzed_template(&mut gen1);
            let t2 = TemplateJsonGenerator::fuzzed_template(&mut gen2);
            assert_eq!(t1, t2, "Template generators diverged with same seed");
        }
    }

    #[test]
    fn test_preset_generator_determinism() {
        let mut gen1 = InputGenerator::new(Some(555), 4096);
        let mut gen2 = InputGenerator::new(Some(555), 4096);

        for _ in 0..20 {
            let p1 = PresetJsonGenerator::fuzzed_preset(&mut gen1);
            let p2 = PresetJsonGenerator::fuzzed_preset(&mut gen2);
            assert_eq!(p1, p2, "Preset generators diverged with same seed");
        }
    }

    // ---- Specific malformation tests ----

    #[test]
    fn test_deeply_nested_braces_no_crash() {
        let mut gen = InputGenerator::new(Some(42), 4096);
        let deep = MalformedJsonGenerator::deeply_nested_braces(&mut gen);
        // Should not panic, just fail to parse or parse partially
        let _ = serde_json::from_str::<Value>(&deep);
        let _ = parse_gdd_safe(&deep);
        let _ = parse_template_safe(&deep);
        let _ = parse_preset_safe(&deep);
    }

    #[test]
    fn test_duplicate_keys_handled() {
        let json = GddJsonGenerator::duplicate_keys(&mut InputGenerator::new(Some(1), 4096));
        // serde_json keeps the last value for duplicate keys — should not panic
        let result = serde_json::from_str::<Value>(&json);
        assert!(result.is_ok());
    }

    #[test]
    fn test_unicode_stress_no_crash() {
        let mut gen = InputGenerator::new(Some(42), 4096);
        for _ in 0..10 {
            let json = GddJsonGenerator::unicode_stress_test(&mut gen);
            let _ = parse_gdd_safe(&json);
        }
    }

    #[test]
    fn test_extremely_long_strings_no_crash() {
        let mut gen = InputGenerator::new(Some(42), 4096);
        let json = GddJsonGenerator::extremely_long_strings(&mut gen);
        // Should parse without panicking (might reject due to missing fields)
        let _ = parse_gdd_safe(&json);
    }
}
