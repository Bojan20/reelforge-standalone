//! T6.5: Honeypot Export Mode — unique watermark injection for leak tracing.
//!
//! Each export recipient receives a uniquely-marked bundle. If a package appears
//! in the wild (pirated / leaked), the embedded honeypot marker identifies the
//! original recipient. Watermark is injected into export metadata JSON only —
//! the actual audio files are NOT modified.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// A unique watermark to be injected into export metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HoneypotMarker {
    /// Unique token derived from game_id + recipient + secret seed
    pub token: String,
    /// Short display label (first 12 hex chars)
    pub short_token: String,
    /// Recipient identifier (masked for storage — only hash stored)
    pub recipient_hash: String,
    /// Game identifier
    pub game_id: String,
    /// ISO 8601 generation timestamp
    pub issued_at: String,
    /// Version of honeypot scheme
    pub scheme_version: u8,
    /// Whether this marker has been triggered (found in the wild)
    pub triggered: bool,
}

impl HoneypotMarker {
    /// Generate a honeypot marker for a specific recipient.
    ///
    /// `secret_seed` should be a server-side secret (never sent to recipient).
    /// The token is: SHA-256(game_id || recipient_id || secret_seed || issued_at)
    pub fn generate(
        game_id: &str,
        recipient_id: &str,
        secret_seed: &str,
        issued_at: &str,
    ) -> Self {
        // Main token: binds all four inputs together
        let mut hasher = Sha256::new();
        hasher.update(game_id.as_bytes());
        hasher.update(b"|");
        hasher.update(recipient_id.as_bytes());
        hasher.update(b"|");
        hasher.update(secret_seed.as_bytes());
        hasher.update(b"|");
        hasher.update(issued_at.as_bytes());
        let token_bytes = hasher.finalize();
        let token = hex::encode(token_bytes);
        let short_token = token[..12].to_string();

        // Recipient hash: one-way, for lookup without exposing PII in export
        let mut rh = Sha256::new();
        rh.update(recipient_id.as_bytes());
        rh.update(b"|");
        rh.update(secret_seed.as_bytes());
        let rh_bytes = rh.finalize();
        let recipient_hash = hex::encode(&rh_bytes[..16]); // 32-char hex

        Self {
            token,
            short_token,
            recipient_hash,
            game_id: game_id.to_string(),
            issued_at: issued_at.to_string(),
            scheme_version: 1,
            triggered: false,
        }
    }

    /// Verify that a token found in the wild was issued for a specific recipient.
    ///
    /// Re-derives the token from the same inputs and checks equality.
    pub fn verify(
        token: &str,
        game_id: &str,
        recipient_id: &str,
        secret_seed: &str,
        issued_at: &str,
    ) -> bool {
        let marker = Self::generate(game_id, recipient_id, secret_seed, issued_at);
        marker.token == token
    }

    /// Inject honeypot metadata into an existing JSON export payload.
    ///
    /// Adds a `_honeypot` key to the root object. Returns modified JSON string.
    /// If the input is not a valid JSON object, returns Err.
    pub fn inject_into_json(&self, export_json: &str) -> Result<String, String> {
        let mut value: serde_json::Value = serde_json::from_str(export_json)
            .map_err(|e| format!("Invalid JSON: {e}"))?;

        let obj = value.as_object_mut()
            .ok_or_else(|| "JSON root must be an object".to_string())?;

        let hp_payload = serde_json::json!({
            "token": self.short_token,
            "issued": self.issued_at,
            "v": self.scheme_version,
        });

        obj.insert("_honeypot".to_string(), hp_payload);

        serde_json::to_string_pretty(&value)
            .map_err(|e| format!("Serialization error: {e}"))
    }

    /// Extract honeypot token from export JSON (if present).
    ///
    /// Returns `Some(short_token)` if `_honeypot.token` key exists, else `None`.
    pub fn extract_from_json(export_json: &str) -> Option<String> {
        let value: serde_json::Value = serde_json::from_str(export_json).ok()?;
        value.get("_honeypot")?.get("token")?.as_str().map(|s| s.to_string())
    }
}

/// Result of a honeypot detection / attribution attempt
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HoneypotResult {
    /// Short token found in the export (or None if no honeypot found)
    pub found_token: Option<String>,
    /// Whether attribution was successful
    pub attributed: bool,
    /// Recipient hash (if attributed)
    pub recipient_hash: Option<String>,
    /// Human-readable attribution message
    pub message: String,
}

impl HoneypotResult {
    /// Attempt to attribute a leaked export JSON to a recipient.
    ///
    /// Checks if honeypot is present; if so, verifies against the provided marker.
    pub fn detect(export_json: &str, marker: Option<&HoneypotMarker>) -> Self {
        let found_token = HoneypotMarker::extract_from_json(export_json);

        match (&found_token, marker) {
            (None, _) => Self {
                found_token: None,
                attributed: false,
                recipient_hash: None,
                message: "No honeypot marker found in export.".to_string(),
            },
            (Some(token), None) => Self {
                found_token: Some(token.clone()),
                attributed: false,
                recipient_hash: None,
                message: format!(
                    "Honeypot token [{}] detected but no marker provided for attribution.",
                    token
                ),
            },
            (Some(token), Some(m)) => {
                let matches = m.short_token == *token;
                if matches {
                    Self {
                        found_token: Some(token.clone()),
                        attributed: true,
                        recipient_hash: Some(m.recipient_hash.clone()),
                        message: format!(
                            "✓ Attribution success: token [{}] matches recipient hash [{}]. \
                             Game: {}. Issued: {}.",
                            token, m.recipient_hash, m.game_id, m.issued_at
                        ),
                    }
                } else {
                    Self {
                        found_token: Some(token.clone()),
                        attributed: false,
                        recipient_hash: None,
                        message: format!(
                            "✗ Token [{}] found but does not match provided marker [{}].",
                            token, m.short_token
                        ),
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    const GAME: &str = "golden_phoenix";
    const SEED: &str = "super_secret_seed_2026";
    const DATE: &str = "2026-04-16T12:00:00Z";

    #[test]
    fn test_marker_generation_is_deterministic() {
        let m1 = HoneypotMarker::generate(GAME, "casino_a", SEED, DATE);
        let m2 = HoneypotMarker::generate(GAME, "casino_a", SEED, DATE);
        assert_eq!(m1.token, m2.token);
        assert_eq!(m1.short_token, m2.short_token);
        assert_eq!(m1.recipient_hash, m2.recipient_hash);
    }

    #[test]
    fn test_different_recipients_produce_different_tokens() {
        let m_a = HoneypotMarker::generate(GAME, "casino_a", SEED, DATE);
        let m_b = HoneypotMarker::generate(GAME, "casino_b", SEED, DATE);
        assert_ne!(m_a.token, m_b.token);
        assert_ne!(m_a.recipient_hash, m_b.recipient_hash);
    }

    #[test]
    fn test_short_token_is_12_chars() {
        let m = HoneypotMarker::generate(GAME, "casino_x", SEED, DATE);
        assert_eq!(m.short_token.len(), 12);
    }

    #[test]
    fn test_verify_correct_recipient() {
        let m = HoneypotMarker::generate(GAME, "casino_a", SEED, DATE);
        assert!(HoneypotMarker::verify(&m.token, GAME, "casino_a", SEED, DATE));
    }

    #[test]
    fn test_verify_wrong_recipient_fails() {
        let m = HoneypotMarker::generate(GAME, "casino_a", SEED, DATE);
        assert!(!HoneypotMarker::verify(&m.token, GAME, "casino_b", SEED, DATE));
    }

    #[test]
    fn test_inject_and_extract_roundtrip() {
        let m = HoneypotMarker::generate(GAME, "casino_a", SEED, DATE);
        let base_json = r#"{"game":"golden_phoenix","format":"howler"}"#;
        let injected = m.inject_into_json(base_json).unwrap();
        let extracted = HoneypotMarker::extract_from_json(&injected);
        assert_eq!(extracted, Some(m.short_token.clone()));
    }

    #[test]
    fn test_inject_into_non_object_fails() {
        let m = HoneypotMarker::generate(GAME, "casino_a", SEED, DATE);
        let result = m.inject_into_json(r#"["not","an","object"]"#);
        assert!(result.is_err());
    }

    #[test]
    fn test_extract_from_json_without_honeypot_returns_none() {
        let result = HoneypotMarker::extract_from_json(r#"{"game":"x"}"#);
        assert!(result.is_none());
    }

    #[test]
    fn test_detection_attributes_correctly() {
        let marker = HoneypotMarker::generate(GAME, "casino_leak", SEED, DATE);
        let base_json = r#"{"game":"golden_phoenix"}"#;
        let injected = marker.inject_into_json(base_json).unwrap();

        let result = HoneypotResult::detect(&injected, Some(&marker));
        assert!(result.attributed);
        assert_eq!(result.found_token.as_deref(), Some(marker.short_token.as_str()));
    }

    #[test]
    fn test_detection_fails_with_wrong_marker() {
        let real_marker = HoneypotMarker::generate(GAME, "casino_leak", SEED, DATE);
        let wrong_marker = HoneypotMarker::generate(GAME, "casino_other", SEED, DATE);

        let base_json = r#"{"game":"golden_phoenix"}"#;
        let injected = real_marker.inject_into_json(base_json).unwrap();

        let result = HoneypotResult::detect(&injected, Some(&wrong_marker));
        assert!(!result.attributed);
    }

    #[test]
    fn test_detection_with_no_honeypot() {
        let marker = HoneypotMarker::generate(GAME, "casino_a", SEED, DATE);
        let result = HoneypotResult::detect(r#"{"game":"x"}"#, Some(&marker));
        assert!(!result.attributed);
        assert!(result.found_token.is_none());
    }
}
