//! Structure analyzer — analyzes JSON structure patterns

use serde_json::Value;
use std::collections::{HashMap, HashSet};

use super::{DetectedField, DetectedType, FieldPurpose};

/// Analyzed JSON structure
#[derive(Debug, Clone, Default)]
pub struct AnalyzedStructure {
    /// All discovered field paths
    pub field_paths: HashSet<String>,

    /// Field type frequencies
    pub field_types: HashMap<String, HashMap<DetectedType, usize>>,

    /// Field value samples
    pub field_samples: HashMap<String, Vec<Value>>,

    /// Is data an array of events or single objects
    pub is_event_array: bool,

    /// Common root keys
    pub root_keys: HashSet<String>,
}

/// Analyze structure of sample data
pub fn analyze_structure(samples: &[Value]) -> AnalyzedStructure {
    let mut structure = AnalyzedStructure::default();

    for sample in samples {
        // Check if sample is an array (batch of events)
        if let Some(arr) = sample.as_array() {
            structure.is_event_array = true;
            for item in arr {
                analyze_value(item, "", &mut structure);
            }
        } else {
            analyze_value(sample, "", &mut structure);
        }
    }

    structure
}

/// Recursively analyze a JSON value
fn analyze_value(value: &Value, path: &str, structure: &mut AnalyzedStructure) {
    let current_path = if path.is_empty() {
        String::new()
    } else {
        path.to_string()
    };

    match value {
        Value::Object(map) => {
            for (key, val) in map {
                let field_path = if current_path.is_empty() {
                    key.clone()
                } else {
                    format!("{}.{}", current_path, key)
                };

                // Track root keys
                if current_path.is_empty() {
                    structure.root_keys.insert(key.clone());
                }

                structure.field_paths.insert(field_path.clone());

                // Track type
                let detected_type = detect_type(val);
                structure
                    .field_types
                    .entry(field_path.clone())
                    .or_default()
                    .entry(detected_type)
                    .and_modify(|c| *c += 1)
                    .or_insert(1);

                // Track sample values (limit to 5)
                let samples = structure.field_samples.entry(field_path.clone()).or_default();
                if samples.len() < 5 && !samples.contains(val) {
                    samples.push(val.clone());
                }

                // Recurse for objects (but not too deep)
                if field_path.matches('.').count() < 4 {
                    analyze_value(val, &field_path, structure);
                }
            }
        }
        Value::Array(arr) => {
            // Analyze first few array items
            for (i, item) in arr.iter().take(3).enumerate() {
                let item_path = format!("{}[{}]", current_path, i);
                analyze_value(item, &item_path, structure);
            }
        }
        _ => {
            // Leaf value - already tracked in parent
        }
    }
}

/// Detect JSON value type
fn detect_type(value: &Value) -> DetectedType {
    match value {
        Value::Null => DetectedType::Null,
        Value::Bool(_) => DetectedType::Boolean,
        Value::Number(_) => DetectedType::Number,
        Value::String(_) => DetectedType::String,
        Value::Array(_) => DetectedType::Array,
        Value::Object(_) => DetectedType::Object,
    }
}

/// Detect fields with purposes
pub fn detect_fields(_samples: &[Value], structure: &AnalyzedStructure) -> Vec<DetectedField> {
    let mut fields = Vec::new();

    for path in &structure.field_paths {
        // Determine dominant type
        let types = structure.field_types.get(path);
        let value_type = types
            .and_then(|t| t.iter().max_by_key(|(_, count)| *count).map(|(ty, _)| *ty))
            .unwrap_or(DetectedType::Mixed);

        // Get sample values
        let sample_values = structure.field_samples.get(path).cloned().unwrap_or_default();

        // Guess purpose from field name and values
        let suggested_purpose = guess_field_purpose(path, value_type, &sample_values);

        fields.push(DetectedField {
            path: path.clone(),
            value_type,
            sample_values,
            suggested_purpose,
        });
    }

    // Sort by relevance (fields with known purpose first)
    fields.sort_by(|a, b| {
        let a_has_purpose = a.suggested_purpose.is_some() as u8;
        let b_has_purpose = b.suggested_purpose.is_some() as u8;
        b_has_purpose.cmp(&a_has_purpose)
    });

    fields
}

/// Guess field purpose from name and values
fn guess_field_purpose(
    path: &str,
    value_type: DetectedType,
    _samples: &[Value],
) -> Option<FieldPurpose> {
    let last_part = path.split('.').next_back().unwrap_or(path).to_lowercase();

    // Event type fields
    if matches!(last_part.as_str(), "type" | "event" | "eventtype" | "event_type" | "name" | "action")
        && value_type == DetectedType::String
    {
        return Some(FieldPurpose::EventType);
    }

    // Timestamp fields
    if matches!(
        last_part.as_str(),
        "timestamp" | "time" | "ts" | "created_at" | "created" | "datetime"
    ) && value_type == DetectedType::Number
    {
        return Some(FieldPurpose::Timestamp);
    }

    // Balance fields
    if matches!(last_part.as_str(), "balance" | "credits" | "coins" | "money")
        && value_type == DetectedType::Number
    {
        return Some(FieldPurpose::Balance);
    }

    // Bet fields
    if matches!(
        last_part.as_str(),
        "bet" | "stake" | "wager" | "bet_amount" | "betamount" | "totalbet"
    ) && value_type == DetectedType::Number
    {
        return Some(FieldPurpose::Bet);
    }

    // Win fields
    if matches!(
        last_part.as_str(),
        "win" | "payout" | "win_amount" | "winamount" | "totalwin" | "total_win"
    ) && value_type == DetectedType::Number
    {
        return Some(FieldPurpose::Win);
    }

    // Multiplier fields
    if matches!(last_part.as_str(), "multiplier" | "multi" | "mult" | "x")
        && value_type == DetectedType::Number
    {
        return Some(FieldPurpose::Multiplier);
    }

    // Reel index
    if matches!(
        last_part.as_str(),
        "reel" | "reel_index" | "reelindex" | "reel_id" | "column"
    ) && value_type == DetectedType::Number
    {
        return Some(FieldPurpose::ReelIndex);
    }

    // Reel symbols
    if matches!(
        last_part.as_str(),
        "symbols" | "reels" | "reel_symbols" | "grid" | "matrix"
    ) && value_type == DetectedType::Array
    {
        return Some(FieldPurpose::ReelSymbols);
    }

    // Feature type
    if matches!(
        last_part.as_str(),
        "feature" | "feature_type" | "featuretype" | "bonus" | "bonus_type"
    ) {
        return Some(FieldPurpose::FeatureType);
    }

    // Spin number
    if matches!(
        last_part.as_str(),
        "spin" | "spin_number" | "spinnumber" | "spin_count" | "round"
    ) && value_type == DetectedType::Number
    {
        return Some(FieldPurpose::SpinNumber);
    }

    // Phase/state
    if matches!(last_part.as_str(), "phase" | "state" | "status" | "mode") {
        return Some(FieldPurpose::Phase);
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_analyze_structure() {
        let samples = vec![
            json!({
                "type": "spin",
                "balance": 100.0,
                "data": {
                    "reels": [[1, 2, 3], [4, 5, 6]]
                }
            }),
            json!({
                "type": "win",
                "balance": 150.0,
                "win_amount": 50.0
            }),
        ];

        let structure = analyze_structure(&samples);

        assert!(structure.root_keys.contains("type"));
        assert!(structure.root_keys.contains("balance"));
        assert!(structure.field_paths.contains("type"));
        assert!(structure.field_paths.contains("data.reels"));
    }

    #[test]
    fn test_guess_field_purpose() {
        assert_eq!(
            guess_field_purpose("event_type", DetectedType::String, &[]),
            Some(FieldPurpose::EventType)
        );

        assert_eq!(
            guess_field_purpose("data.win_amount", DetectedType::Number, &[]),
            Some(FieldPurpose::Win)
        );

        assert_eq!(
            guess_field_purpose("timestamp", DetectedType::Number, &[]),
            Some(FieldPurpose::Timestamp)
        );
    }
}
