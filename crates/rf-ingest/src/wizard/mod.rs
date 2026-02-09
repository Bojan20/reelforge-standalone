//! Adapter Wizard — Auto-detection and configuration generation
//!
//! Analyzes sample JSON files to automatically detect event patterns
//! and generate adapter configurations.

mod analyzer;
mod detector;
mod generator;

pub use analyzer::*;
pub use detector::*;
pub use generator::*;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::adapter::{AdapterError, IngestLayer};
use crate::config::AdapterConfig;

/// Wizard analysis result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WizardResult {
    /// Detected company (if recognized)
    pub detected_company: Option<String>,

    /// Detected engine (if recognized)
    pub detected_engine: Option<String>,

    /// Recommended ingest layer
    pub recommended_layer: IngestLayer,

    /// Generated adapter config
    pub config: AdapterConfig,

    /// Confidence score (0.0 - 1.0)
    pub confidence: f64,

    /// Detection notes
    pub notes: Vec<String>,

    /// Detected event types
    pub detected_events: Vec<DetectedEvent>,

    /// Detected state fields
    pub detected_fields: Vec<DetectedField>,

    /// Warnings
    pub warnings: Vec<String>,
}

/// Detected event from sample data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectedEvent {
    /// Event name/type
    pub event_name: String,

    /// Suggested stage mapping
    pub suggested_stage: Option<String>,

    /// Sample count
    pub sample_count: usize,

    /// Sample payload
    pub sample_payload: Option<Value>,
}

/// Detected field from sample data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectedField {
    /// Field path (dot notation)
    pub path: String,

    /// Detected type
    pub value_type: DetectedType,

    /// Sample values
    pub sample_values: Vec<Value>,

    /// Suggested purpose
    pub suggested_purpose: Option<FieldPurpose>,
}

/// Detected value type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum DetectedType {
    String,
    Number,
    Boolean,
    Array,
    Object,
    Null,
    Mixed,
}

/// Suggested field purpose
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FieldPurpose {
    EventType,
    Timestamp,
    Balance,
    Bet,
    Win,
    Multiplier,
    ReelIndex,
    ReelSymbols,
    FeatureType,
    SpinNumber,
    Phase,
    Unknown,
}

/// Adapter Wizard
#[derive(Debug, Default)]
pub struct AdapterWizard {
    /// Sample data for analysis
    samples: Vec<Value>,

    /// Known engine signatures
    signatures: Vec<EngineSignature>,
}

/// Engine signature for recognition
#[derive(Debug, Clone)]
pub struct EngineSignature {
    pub company: String,
    pub engine: String,
    pub markers: Vec<SignatureMarker>,
}

/// Signature marker
#[derive(Debug, Clone)]
pub enum SignatureMarker {
    /// Field exists at path
    FieldExists(String),
    /// Field has specific value
    FieldValue(String, Value),
    /// Field matches pattern
    FieldPattern(String, String),
    /// Event type exists
    EventType(String),
}

impl AdapterWizard {
    /// Create new wizard
    pub fn new() -> Self {
        Self {
            samples: Vec::new(),
            signatures: default_signatures(),
        }
    }

    /// Add sample data
    pub fn add_sample(&mut self, sample: Value) {
        self.samples.push(sample);
    }

    /// Add multiple samples
    pub fn add_samples(&mut self, samples: impl IntoIterator<Item = Value>) {
        self.samples.extend(samples);
    }

    /// Clear samples
    pub fn clear_samples(&mut self) {
        self.samples.clear();
    }

    /// Analyze samples and generate config
    pub fn analyze(&self) -> Result<WizardResult, AdapterError> {
        if self.samples.is_empty() {
            return Err(AdapterError::ConfigError("No samples provided".to_string()));
        }

        let mut notes = Vec::new();
        let mut warnings = Vec::new();

        // Step 1: Detect engine
        let (detected_company, detected_engine) = self.detect_engine();
        if detected_company.is_some() {
            notes.push(format!(
                "Detected engine: {} / {}",
                detected_company.as_deref().unwrap_or("unknown"),
                detected_engine.as_deref().unwrap_or("unknown")
            ));
        }

        // Step 2: Analyze structure
        let structure = analyze_structure(&self.samples);

        // Step 3: Detect events
        let detected_events = detect_events(&self.samples, &structure);
        notes.push(format!(
            "Found {} unique event types",
            detected_events.len()
        ));

        // Step 4: Detect fields
        let detected_fields = detect_fields(&self.samples, &structure);
        notes.push(format!("Found {} relevant fields", detected_fields.len()));

        // Step 5: Determine best layer
        let recommended_layer = determine_layer(&detected_events, &detected_fields);
        notes.push(format!("Recommended layer: {:?}", recommended_layer));

        // Step 6: Generate config
        let config = generate_config(&detected_events, &detected_fields, recommended_layer);

        // Step 7: Calculate confidence
        let confidence = calculate_confidence(&detected_events, &detected_fields, &config);

        if confidence < 0.5 {
            warnings.push("Low confidence - manual review recommended".to_string());
        }

        if detected_events.iter().any(|e| e.suggested_stage.is_none()) {
            warnings.push("Some events could not be mapped to stages".to_string());
        }

        Ok(WizardResult {
            detected_company,
            detected_engine,
            recommended_layer,
            config,
            confidence,
            notes,
            detected_events,
            detected_fields,
            warnings,
        })
    }

    /// Detect engine from signatures
    fn detect_engine(&self) -> (Option<String>, Option<String>) {
        for signature in &self.signatures {
            if self.matches_signature(signature) {
                return (
                    Some(signature.company.clone()),
                    Some(signature.engine.clone()),
                );
            }
        }
        (None, None)
    }

    /// Check if samples match a signature
    fn matches_signature(&self, signature: &EngineSignature) -> bool {
        let mut matches = 0;
        let required = signature.markers.len();

        for sample in &self.samples {
            for marker in &signature.markers {
                if match_marker(sample, marker) {
                    matches += 1;
                    break;
                }
            }
        }

        // Require at least 50% match
        matches * 2 >= required
    }
}

/// Check if sample matches a marker
fn match_marker(sample: &Value, marker: &SignatureMarker) -> bool {
    match marker {
        SignatureMarker::FieldExists(path) => get_value_at_path(sample, path).is_some(),

        SignatureMarker::FieldValue(path, expected) => get_value_at_path(sample, path)
            .map(|v| v == expected)
            .unwrap_or(false),

        SignatureMarker::FieldPattern(path, pattern) => {
            if let Some(Value::String(s)) = get_value_at_path(sample, path) {
                regex::Regex::new(pattern)
                    .map(|re| re.is_match(s))
                    .unwrap_or(false)
            } else {
                false
            }
        }

        SignatureMarker::EventType(event) => {
            // Check common event type paths
            let paths = ["type", "event", "eventType", "event_type", "name"];
            paths.iter().any(|path| {
                get_value_at_path(sample, path)
                    .and_then(|v| v.as_str())
                    .map(|s| s.eq_ignore_ascii_case(event))
                    .unwrap_or(false)
            })
        }
    }
}

/// Get value at JSON path
fn get_value_at_path<'a>(json: &'a Value, path: &str) -> Option<&'a Value> {
    let parts: Vec<&str> = path.split('.').collect();
    let mut current = json;

    for part in parts {
        current = current.get(part)?;
    }

    Some(current)
}

/// Default engine signatures
fn default_signatures() -> Vec<EngineSignature> {
    vec![
        // Pragmatic Play
        EngineSignature {
            company: "Pragmatic Play".to_string(),
            engine: "Slot Engine v2".to_string(),
            markers: vec![
                SignatureMarker::FieldExists("pragmatic".to_string()),
                SignatureMarker::EventType("SPIN_RESULT".to_string()),
            ],
        },
        // NetEnt
        EngineSignature {
            company: "NetEnt".to_string(),
            engine: "NetEnt Core".to_string(),
            markers: vec![
                SignatureMarker::FieldExists("netent".to_string()),
                SignatureMarker::EventType("spinComplete".to_string()),
            ],
        },
        // Play'n GO
        EngineSignature {
            company: "Play'n GO".to_string(),
            engine: "PNG Framework".to_string(),
            markers: vec![SignatureMarker::FieldPattern(
                "version".to_string(),
                r"PNG.*".to_string(),
            )],
        },
        // Big Time Gaming
        EngineSignature {
            company: "Big Time Gaming".to_string(),
            engine: "Megaways".to_string(),
            markers: vec![
                SignatureMarker::FieldExists("megaways".to_string()),
                SignatureMarker::EventType("MEGAWAYS_RESULT".to_string()),
            ],
        },
        // Generic slot
        EngineSignature {
            company: "Generic".to_string(),
            engine: "Standard Slot".to_string(),
            markers: vec![
                SignatureMarker::EventType("spin".to_string()),
                SignatureMarker::EventType("win".to_string()),
            ],
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_wizard_basic_analysis() {
        let mut wizard = AdapterWizard::new();

        wizard.add_sample(json!({
            "type": "spin_start",
            "timestamp": 1000,
            "balance": 100.0
        }));

        wizard.add_sample(json!({
            "type": "reel_stop",
            "timestamp": 1500,
            "reel_index": 0,
            "symbols": [1, 2, 3]
        }));

        wizard.add_sample(json!({
            "type": "win",
            "timestamp": 2000,
            "win_amount": 50.0
        }));

        let result = wizard.analyze().unwrap();

        assert!(!result.detected_events.is_empty());
        assert!(result.confidence > 0.0);
    }

    #[test]
    fn test_signature_detection() {
        let mut wizard = AdapterWizard::new();

        wizard.add_sample(json!({
            "pragmatic": true,
            "type": "SPIN_RESULT",
            "data": {}
        }));

        let result = wizard.analyze().unwrap();

        assert_eq!(result.detected_company, Some("Pragmatic Play".to_string()));
    }
}
