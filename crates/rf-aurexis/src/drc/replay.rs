//! DRC: Deterministic Replay Core
//!
//! Records game hook sequence + engine state → replays in isolation →
//! compares per-frame hashes. Any mismatch = determinism failure.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §10

use crate::core::config::AurexisConfig;
use crate::core::engine::AurexisEngine;
use crate::core::parameter_map::DeterministicParameterMap;
use crate::qa::simulation::SimulationStep;
use serde::{Deserialize, Serialize};

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// Deterministic frame hash (FNV-1a 64-bit of serialized state).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct FrameHash(pub u64);

impl FrameHash {
    /// Compute hash from DeterministicParameterMap.
    pub fn from_map(map: &DeterministicParameterMap) -> Self {
        // FNV-1a hash of serialized JSON (deterministic)
        let json = serde_json::to_string(map).unwrap_or_default();
        let mut hash: u64 = 0xcbf29ce484222325;
        for byte in json.as_bytes() {
            hash ^= *byte as u64;
            hash = hash.wrapping_mul(0x100000001b3);
        }
        Self(hash)
    }

    pub fn as_hex(&self) -> String {
        format!("{:016x}", self.0)
    }
}

/// Single trace entry (one frame's recorded state).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceEntry {
    pub frame_index: u32,
    pub step: SimulationStepData,
    pub frame_hash: FrameHash,
}

/// Simplified step data for trace serialization.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationStepData {
    pub elapsed_ms: u64,
    pub volatility: f64,
    pub rtp: f64,
    pub win_multiplier: f64,
    pub jackpot_proximity: f64,
    pub rms_db: f64,
    pub hf_db: f64,
}

impl From<&SimulationStep> for SimulationStepData {
    fn from(s: &SimulationStep) -> Self {
        Self {
            elapsed_ms: s.elapsed_ms,
            volatility: s.volatility,
            rtp: s.rtp,
            win_multiplier: s.win_multiplier,
            jackpot_proximity: s.jackpot_proximity,
            rms_db: s.rms_db,
            hf_db: s.hf_db,
        }
    }
}

/// Trace metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceMetadata {
    pub fftrace_version: String,
    pub engine_version: String,
    pub total_frames: u32,
    pub total_events: u32,
    pub capture_mode: String,
}

/// Complete .fftrace format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceFormat {
    pub metadata: TraceMetadata,
    pub entries: Vec<TraceEntry>,
    pub final_state_hash: FrameHash,
}

/// Hash mismatch detail.
#[derive(Debug, Clone)]
pub struct HashMismatch {
    pub frame_index: u32,
    pub recorded_hash: FrameHash,
    pub replay_hash: FrameHash,
}

/// Replay verification result.
#[derive(Debug, Clone)]
pub struct ReplayResult {
    pub passed: bool,
    pub total_frames: u32,
    pub mismatches: Vec<HashMismatch>,
    pub recorded_final_hash: FrameHash,
    pub replay_final_hash: FrameHash,
}

// ═════════════════════════════════════════════════════════════════════════════
// DETERMINISTIC REPLAY CORE
// ═════════════════════════════════════════════════════════════════════════════

/// Deterministic Replay Core.
///
/// Records hook sequences and engine state, then replays to verify
/// deterministic output. Per-frame hashing ensures exact reproduction.
pub struct DeterministicReplayCore {
    config: AurexisConfig,
    last_trace: Option<TraceFormat>,
    last_result: Option<ReplayResult>,
}

impl DeterministicReplayCore {
    pub fn new() -> Self {
        Self {
            config: AurexisConfig::default(),
            last_trace: None,
            last_result: None,
        }
    }

    pub fn with_config(config: AurexisConfig) -> Self {
        Self {
            config,
            last_trace: None,
            last_result: None,
        }
    }

    pub fn last_trace(&self) -> Option<&TraceFormat> {
        self.last_trace.as_ref()
    }

    pub fn last_result(&self) -> Option<&ReplayResult> {
        self.last_result.as_ref()
    }

    pub fn passed(&self) -> bool {
        self.last_result.as_ref().is_some_and(|r| r.passed)
    }

    /// Record a session: execute steps and capture per-frame hashes.
    pub fn record(&mut self, steps: &[SimulationStep]) -> &TraceFormat {
        let (hashes, outputs) = self.execute_and_hash(steps);

        let entries: Vec<TraceEntry> = steps
            .iter()
            .zip(hashes.iter())
            .enumerate()
            .map(|(i, (step, hash))| TraceEntry {
                frame_index: i as u32,
                step: SimulationStepData::from(step),
                frame_hash: hash.clone(),
            })
            .collect();

        // Final hash = hash of all frame hashes concatenated
        let final_hash = Self::compute_final_hash(&hashes);

        let trace = TraceFormat {
            metadata: TraceMetadata {
                fftrace_version: "1.0".into(),
                engine_version: env!("CARGO_PKG_VERSION").into(),
                total_frames: entries.len() as u32,
                total_events: entries.len() as u32,
                capture_mode: "DETERMINISM_TEST".into(),
            },
            entries,
            final_state_hash: final_hash,
        };

        let _ = outputs; // consumed for hashing
        self.last_trace = Some(trace);
        self.last_trace.as_ref().unwrap()
    }

    /// Replay a recorded trace and verify determinism.
    pub fn replay_and_verify(&mut self, steps: &[SimulationStep]) -> &ReplayResult {
        // Record if no trace exists
        if self.last_trace.is_none() {
            self.record(steps);
        }

        let trace = self.last_trace.as_ref().unwrap();

        // Replay
        let (replay_hashes, _outputs) = self.execute_and_hash(steps);
        let replay_final_hash = Self::compute_final_hash(&replay_hashes);

        // Compare
        let mut mismatches = Vec::new();
        for (i, (recorded, replayed)) in trace.entries.iter().zip(replay_hashes.iter()).enumerate()
        {
            if recorded.frame_hash != *replayed {
                mismatches.push(HashMismatch {
                    frame_index: i as u32,
                    recorded_hash: recorded.frame_hash.clone(),
                    replay_hash: replayed.clone(),
                });
            }
        }

        let passed = mismatches.is_empty() && replay_final_hash == trace.final_state_hash;

        let result = ReplayResult {
            passed,
            total_frames: trace.entries.len() as u32,
            mismatches,
            recorded_final_hash: trace.final_state_hash.clone(),
            replay_final_hash,
        };

        self.last_result = Some(result);
        self.last_result.as_ref().unwrap()
    }

    /// Reset state.
    pub fn reset(&mut self) {
        self.last_trace = None;
        self.last_result = None;
    }

    /// Get trace as JSON string.
    pub fn trace_json(&self) -> Result<String, String> {
        let trace = self.last_trace.as_ref().ok_or("No trace recorded")?;
        serde_json::to_string(trace).map_err(|e| e.to_string())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    fn execute_and_hash(
        &self,
        steps: &[SimulationStep],
    ) -> (Vec<FrameHash>, Vec<DeterministicParameterMap>) {
        let mut engine = AurexisEngine::with_config(self.config.clone());
        engine.initialize();
        engine.set_seed(0, 0, 0, 0);

        let mut hashes = Vec::with_capacity(steps.len());
        let mut outputs = Vec::with_capacity(steps.len());

        for step in steps {
            engine.set_volatility(step.volatility);
            engine.set_rtp(step.rtp);
            engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
            engine.set_metering(step.rms_db, step.hf_db);

            let is_jackpot = step.jackpot_proximity > 0.9 && step.win_multiplier > 100.0;
            let is_feature = step.win_multiplier > 10.0;
            engine.record_spin(step.win_multiplier, is_feature, is_jackpot);

            let map = engine.compute_cloned(step.elapsed_ms);
            hashes.push(FrameHash::from_map(&map));
            outputs.push(map);
        }

        (hashes, outputs)
    }

    fn compute_final_hash(hashes: &[FrameHash]) -> FrameHash {
        let mut hash: u64 = 0xcbf29ce484222325;
        for h in hashes {
            // Mix each frame hash into final
            hash ^= h.0;
            hash = hash.wrapping_mul(0x100000001b3);
        }
        FrameHash(hash)
    }
}

impl Default for DeterministicReplayCore {
    fn default() -> Self {
        Self::new()
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn test_steps(count: usize) -> Vec<SimulationStep> {
        (0..count)
            .map(|i| SimulationStep {
                elapsed_ms: 50,
                volatility: 0.5 + (i as f64 * 0.01),
                rtp: 96.0,
                win_multiplier: if i % 5 == 0 { 10.0 } else { 0.0 },
                jackpot_proximity: 0.0,
                rms_db: -20.0,
                hf_db: -26.0,
            })
            .collect()
    }

    #[test]
    fn test_frame_hash_deterministic() {
        let map = DeterministicParameterMap::default();
        let h1 = FrameHash::from_map(&map);
        let h2 = FrameHash::from_map(&map);
        assert_eq!(h1, h2);
    }

    #[test]
    fn test_frame_hash_different_maps() {
        let m1 = DeterministicParameterMap::default();
        let mut m2 = DeterministicParameterMap::default();
        m2.stereo_width = 1.5;
        assert_ne!(FrameHash::from_map(&m1), FrameHash::from_map(&m2));
    }

    #[test]
    fn test_record_creates_trace() {
        let mut drc = DeterministicReplayCore::new();
        let steps = test_steps(50);
        let trace = drc.record(&steps);

        assert_eq!(trace.metadata.fftrace_version, "1.0");
        assert_eq!(trace.metadata.total_frames, 50);
        assert_eq!(trace.entries.len(), 50);
    }

    #[test]
    fn test_replay_deterministic() {
        let mut drc = DeterministicReplayCore::new();
        let steps = test_steps(50);
        drc.record(&steps);
        let result = drc.replay_and_verify(&steps);

        assert!(result.passed, "Identical replay should pass");
        assert_eq!(result.mismatches.len(), 0);
        assert_eq!(result.recorded_final_hash, result.replay_final_hash);
    }

    #[test]
    fn test_replay_detects_mismatch() {
        let mut drc = DeterministicReplayCore::new();
        let steps = test_steps(50);
        drc.record(&steps);

        // Modify one step
        let mut modified = steps.clone();
        modified[25].win_multiplier = 999.0;
        let result = drc.replay_and_verify(&modified);

        assert!(!result.passed, "Modified replay should fail");
        assert!(!result.mismatches.is_empty());
    }

    #[test]
    fn test_trace_json() {
        let mut drc = DeterministicReplayCore::new();
        let steps = test_steps(10);
        drc.record(&steps);

        let json = drc.trace_json().expect("JSON should work");
        assert!(json.contains("fftrace_version"));
        assert!(json.contains("frame_hash"));
        assert!(json.contains("final_state_hash"));
    }

    #[test]
    fn test_frame_hash_hex() {
        let h = FrameHash(0xdeadbeef12345678);
        assert_eq!(h.as_hex(), "deadbeef12345678");
    }

    #[test]
    fn test_reset() {
        let mut drc = DeterministicReplayCore::new();
        let steps = test_steps(10);
        drc.record(&steps);
        assert!(drc.last_trace().is_some());

        drc.reset();
        assert!(drc.last_trace().is_none());
        assert!(drc.last_result().is_none());
    }
}
