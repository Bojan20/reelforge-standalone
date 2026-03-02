// ============================================================================
// rf-fluxmacro — Hashing
// ============================================================================
// FM-6: SHA-256 streaming run hash + FNV-1a config hash.
// ============================================================================

use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::Path;

use crate::context::MacroContext;
use crate::error::FluxMacroError;

// ─── SHA-256 ─────────────────────────────────────────────────────────────────

/// Compute SHA-256 hash of a byte slice, returns hex string.
pub fn sha256_bytes(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    format!("{:x}", hasher.finalize())
}

/// Compute SHA-256 hash of a string, returns hex string.
pub fn sha256_str(s: &str) -> String {
    sha256_bytes(s.as_bytes())
}

/// Compute SHA-256 hash of a file using streaming (constant memory).
/// Reads in 8KB chunks to avoid loading entire file into memory.
pub fn sha256_file(path: &Path) -> Result<String, FluxMacroError> {
    let mut file =
        std::fs::File::open(path).map_err(|e| FluxMacroError::FileRead(path.to_path_buf(), e))?;

    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 8192];

    loop {
        let bytes_read = file
            .read(&mut buffer)
            .map_err(|e| FluxMacroError::FileRead(path.to_path_buf(), e))?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

/// Incrementally build a SHA-256 hash from multiple inputs.
pub struct StreamingHash {
    hasher: Sha256,
}

impl StreamingHash {
    pub fn new() -> Self {
        Self {
            hasher: Sha256::new(),
        }
    }

    /// Feed data into the hash.
    pub fn update(&mut self, data: &[u8]) {
        self.hasher.update(data);
    }

    /// Feed a string into the hash.
    pub fn update_str(&mut self, s: &str) {
        self.hasher.update(s.as_bytes());
    }

    /// Finalize and return hex hash string.
    pub fn finalize(self) -> String {
        format!("{:x}", self.hasher.finalize())
    }
}

impl Default for StreamingHash {
    fn default() -> Self {
        Self::new()
    }
}

// ─── FNV-1a ──────────────────────────────────────────────────────────────────

const FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;

/// FNV-1a 64-bit hash of a byte slice.
/// Fast, non-cryptographic hash suitable for config fingerprinting.
pub fn fnv1a_bytes(data: &[u8]) -> u64 {
    let mut hash = FNV_OFFSET_BASIS;
    for &byte in data {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

/// FNV-1a hash of a string.
pub fn fnv1a_str(s: &str) -> u64 {
    fnv1a_bytes(s.as_bytes())
}

/// FNV-1a hash formatted as hex string.
pub fn fnv1a_hex(data: &[u8]) -> String {
    format!("{:016x}", fnv1a_bytes(data))
}

// ─── Run Hash ────────────────────────────────────────────────────────────────

/// Compute the run hash for a completed macro execution.
/// Hash = SHA-256(macro_name + inputs + step_results + artifact_hashes + seed).
pub fn compute_run_hash(ctx: &MacroContext, macro_name: &str, steps: &[String]) -> String {
    let mut hasher = StreamingHash::new();

    // Macro identity
    hasher.update_str(macro_name);
    hasher.update_str(&format!("{}", ctx.seed));

    // Input parameters
    hasher.update_str(&ctx.game_id);
    hasher.update_str(&format!("{:?}", ctx.volatility));
    for platform in &ctx.platforms {
        hasher.update_str(&format!("{platform:?}"));
    }
    for mechanic in &ctx.mechanics {
        hasher.update_str(mechanic.id());
    }

    // Step names
    for step_name in steps {
        hasher.update_str(step_name);
    }

    // QA results
    for qa in &ctx.qa_results {
        hasher.update_str(&qa.test_name);
        hasher.update_str(if qa.passed { "PASS" } else { "FAIL" });
    }

    // Artifact hashes (sorted by name for determinism)
    let mut artifact_names: Vec<&String> = ctx.artifacts.keys().collect();
    artifact_names.sort();
    for name in artifact_names {
        hasher.update_str(name);
        if let Some(path) = ctx.artifacts.get(name) {
            if path.exists() {
                if let Ok(hash) = sha256_file(path) {
                    hasher.update_str(&hash);
                }
            }
        }
    }

    hasher.finalize()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_deterministic() {
        let a = sha256_str("hello world");
        let b = sha256_str("hello world");
        assert_eq!(a, b);
        assert_eq!(a.len(), 64); // SHA-256 hex = 64 chars
    }

    #[test]
    fn sha256_different_inputs() {
        let a = sha256_str("hello");
        let b = sha256_str("world");
        assert_ne!(a, b);
    }

    #[test]
    fn fnv1a_deterministic() {
        let a = fnv1a_str("test config");
        let b = fnv1a_str("test config");
        assert_eq!(a, b);
    }

    #[test]
    fn fnv1a_different_inputs() {
        let a = fnv1a_str("config_a");
        let b = fnv1a_str("config_b");
        assert_ne!(a, b);
    }

    #[test]
    fn streaming_hash_matches_oneshot() {
        let oneshot = sha256_str("abcdef");

        let mut streaming = StreamingHash::new();
        streaming.update_str("abc");
        streaming.update_str("def");
        let streamed = streaming.finalize();

        assert_eq!(oneshot, streamed);
    }

    #[test]
    fn fnv1a_hex_format() {
        let hex = fnv1a_hex(b"test");
        assert_eq!(hex.len(), 16); // 64-bit = 16 hex chars
    }
}
