//! T6.1 + T6.4: Audio bundle fingerprinting and verification.

use sha2::{Digest, Sha256};
use serde::{Deserialize, Serialize};

/// Specification of one audio event for fingerprinting
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FingerprintSpec {
    pub name: String,
    pub category: String,
    pub tier: String,
    pub duration_ms: u32,
    pub voice_count: u8,
    pub is_required: bool,
    pub can_loop: bool,
}

impl FingerprintSpec {
    /// Canonical string representation (stable ordering for hashing)
    pub fn canonical(&self) -> String {
        format!(
            "{}|{}|{}|{}|{}|{}|{}",
            self.name,
            self.category,
            self.tier,
            self.duration_ms,
            self.voice_count,
            self.is_required as u8,
            self.can_loop as u8,
        )
    }
}

/// Computed fingerprint for a bundle of audio event specs
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BundleFingerprint {
    /// Hex-encoded SHA-256 digest of canonical event list
    pub digest: String,
    /// Game identifier
    pub game_id: String,
    /// Number of events fingerprinted
    pub event_count: usize,
    /// Short human-readable fingerprint (first 8 hex chars)
    pub short_id: String,
    /// Version string of the tool that generated this
    pub tool_version: String,
    /// ISO 8601 timestamp
    pub generated_at: String,
}

impl BundleFingerprint {
    /// Compute fingerprint from a list of event specs.
    pub fn compute(
        game_id: &str,
        events: &mut Vec<FingerprintSpec>,
        tool_version: &str,
        generated_at: &str,
    ) -> Self {
        // Sort events alphabetically for stable ordering
        events.sort_by(|a, b| a.name.cmp(&b.name));

        let mut hasher = Sha256::new();
        hasher.update(game_id.as_bytes());
        hasher.update(b"|");
        for ev in events.iter() {
            hasher.update(ev.canonical().as_bytes());
            hasher.update(b"\n");
        }

        let digest_bytes = hasher.finalize();
        let digest = hex::encode(digest_bytes);
        let short_id = digest[..8].to_string();
        let event_count = events.len();

        Self {
            digest,
            game_id: game_id.to_string(),
            event_count,
            short_id,
            tool_version: tool_version.to_string(),
            generated_at: generated_at.to_string(),
        }
    }
}

/// Result of a fingerprint verification check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationResult {
    pub matches: bool,
    pub expected_digest: String,
    pub actual_digest: String,
    pub expected_event_count: usize,
    pub actual_event_count: usize,
    /// Human-readable result message
    pub message: String,
}

impl VerificationResult {
    pub fn verify(stored: &BundleFingerprint, current: &BundleFingerprint) -> Self {
        let matches = stored.digest == current.digest;
        let message = if matches {
            format!("✓ Fingerprint verified [{}] — {} events match.", stored.short_id, stored.event_count)
        } else {
            format!(
                "✗ Fingerprint MISMATCH — expected [{}] got [{}]. \
                 Events: {} → {}. Bundle may have been modified.",
                stored.short_id, current.short_id,
                stored.event_count, current.event_count
            )
        };

        Self {
            matches,
            expected_digest: stored.digest.clone(),
            actual_digest: current.digest.clone(),
            expected_event_count: stored.event_count,
            actual_event_count: current.event_count,
            message,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_events() -> Vec<FingerprintSpec> {
        vec![
            FingerprintSpec {
                name: "SPIN_START".to_string(), category: "BaseGame".to_string(),
                tier: "subtle".to_string(), duration_ms: 150, voice_count: 1,
                is_required: true, can_loop: false,
            },
            FingerprintSpec {
                name: "WIN_5".to_string(), category: "Win".to_string(),
                tier: "flagship".to_string(), duration_ms: 8000, voice_count: 6,
                is_required: false, can_loop: false,
            },
            FingerprintSpec {
                name: "REEL_SPIN".to_string(), category: "BaseGame".to_string(),
                tier: "subtle".to_string(), duration_ms: 2000, voice_count: 2,
                is_required: true, can_loop: true,
            },
        ]
    }

    #[test]
    fn test_fingerprint_is_deterministic() {
        let mut events_a = sample_events();
        let mut events_b = sample_events();
        let fp_a = BundleFingerprint::compute("test_game", &mut events_a, "1.0", "2026-01-01");
        let fp_b = BundleFingerprint::compute("test_game", &mut events_b, "1.0", "2026-01-01");
        assert_eq!(fp_a.digest, fp_b.digest);
    }

    #[test]
    fn test_fingerprint_order_independent() {
        let mut events_normal = sample_events();
        let mut events_reversed = sample_events();
        events_reversed.reverse();

        let fp_a = BundleFingerprint::compute("game", &mut events_normal, "1.0", "t");
        let fp_b = BundleFingerprint::compute("game", &mut events_reversed, "1.0", "t");
        assert_eq!(fp_a.digest, fp_b.digest, "Fingerprint should be order-independent");
    }

    #[test]
    fn test_fingerprint_changes_when_event_modified() {
        let mut events_a = sample_events();
        let mut events_b = sample_events();
        events_b[0].duration_ms = 9999; // modify one event

        let fp_a = BundleFingerprint::compute("game", &mut events_a, "1.0", "t");
        let fp_b = BundleFingerprint::compute("game", &mut events_b, "1.0", "t");
        assert_ne!(fp_a.digest, fp_b.digest);
    }

    #[test]
    fn test_short_id_is_8_chars() {
        let mut events = sample_events();
        let fp = BundleFingerprint::compute("game", &mut events, "1.0", "t");
        assert_eq!(fp.short_id.len(), 8);
    }

    #[test]
    fn test_verification_matches() {
        let mut events = sample_events();
        let fp_a = BundleFingerprint::compute("game", &mut events, "1.0", "t");
        let fp_b = BundleFingerprint::compute("game", &mut events, "1.0", "t");
        let result = VerificationResult::verify(&fp_a, &fp_b);
        assert!(result.matches);
    }

    #[test]
    fn test_verification_fails_on_mismatch() {
        let mut events_a = sample_events();
        let mut events_b = sample_events();
        events_b.push(FingerprintSpec {
            name: "EXTRA_EVENT".to_string(), category: "BaseGame".to_string(),
            tier: "subtle".to_string(), duration_ms: 100, voice_count: 1,
            is_required: false, can_loop: false,
        });

        let fp_a = BundleFingerprint::compute("game", &mut events_a, "1.0", "t");
        let fp_b = BundleFingerprint::compute("game", &mut events_b, "1.0", "t");
        let result = VerificationResult::verify(&fp_a, &fp_b);
        assert!(!result.matches);
        assert!(result.message.contains("MISMATCH"));
    }
}
