//! DRC: Certification Gate
//!
//! Full certification pipeline: PBSE + DRC + Envelope + Manifest → BAKE.
//!
//! See: FLUXFORGE_MASTER_SPEC.md §10

use super::manifest::{CertificationStatus, FluxManifest};
use super::replay::DeterministicReplayCore;
use super::safety::SafetyEnvelope;
use crate::core::config::AurexisConfig;
use crate::core::parameter_map::DeterministicParameterMap;
use crate::qa::pbse::PbseResult;
use crate::qa::simulation::SimulationStep;

// ═════════════════════════════════════════════════════════════════════════════
// TYPES
// ═════════════════════════════════════════════════════════════════════════════

/// Certification result for a single stage.
#[derive(Debug, Clone)]
pub struct StageResult {
    pub name: &'static str,
    pub passed: bool,
    pub details: String,
}

/// Complete certification report.
#[derive(Debug, Clone)]
pub struct CertificationReport {
    pub overall_status: CertificationStatus,
    pub stages: Vec<StageResult>,
    pub blocking_failures: Vec<String>,
}

/// Certification result.
#[derive(Debug, Clone)]
pub struct CertificationResult {
    pub certified: bool,
    pub report: CertificationReport,
    pub manifest: FluxManifest,
}

// ═════════════════════════════════════════════════════════════════════════════
// CERTIFICATION GATE
// ═════════════════════════════════════════════════════════════════════════════

/// Certification Gate.
///
/// Orchestrates the full certification pipeline:
/// 1. PBSE PASS
/// 2. AIL Analysis (advisory, never blocks)
/// 3. DRC Run
/// 4. Safety Envelope
/// 5. Manifest Lock
/// 6. Final Hash Validation
/// 7. BAKE UNLOCKED
pub struct CertificationGate {
    _config: AurexisConfig,
    replay_core: DeterministicReplayCore,
    safety_envelope: SafetyEnvelope,
    manifest: FluxManifest,
    last_result: Option<CertificationResult>,
}

impl CertificationGate {
    pub fn new() -> Self {
        Self {
            _config: AurexisConfig::default(),
            replay_core: DeterministicReplayCore::new(),
            safety_envelope: SafetyEnvelope::new(),
            manifest: FluxManifest::new(),
            last_result: None,
        }
    }

    pub fn last_result(&self) -> Option<&CertificationResult> {
        self.last_result.as_ref()
    }

    pub fn is_certified(&self) -> bool {
        self.last_result.as_ref().map_or(false, |r| r.certified)
    }

    pub fn manifest(&self) -> &FluxManifest {
        &self.manifest
    }

    pub fn replay_core(&self) -> &DeterministicReplayCore {
        &self.replay_core
    }

    pub fn safety_envelope(&self) -> &SafetyEnvelope {
        &self.safety_envelope
    }

    /// Run full certification pipeline.
    ///
    /// Steps:
    /// 1. Check PBSE results
    /// 2. Run DRC (record + replay + verify)
    /// 3. Run Safety Envelope validation
    /// 4. Update manifest
    /// 5. Final hash validation
    pub fn certify(
        &mut self,
        pbse_result: Option<&PbseResult>,
        steps: &[SimulationStep],
        outputs: &[DeterministicParameterMap],
        config_data: &str,
    ) -> &CertificationResult {
        let mut stages = Vec::new();
        let mut blocking_failures = Vec::new();

        // Stage 1: PBSE
        let pbse_pass = pbse_result.map_or(false, |r| r.all_passed);
        stages.push(StageResult {
            name: "PBSE",
            passed: pbse_pass,
            details: if pbse_pass {
                "All 10 domains passed".into()
            } else {
                "PBSE validation failed or not run".into()
            },
        });
        if !pbse_pass {
            blocking_failures.push("PBSE validation failed".into());
        }

        // Stage 2: DRC (record + replay)
        self.replay_core.record(steps);
        let drc_result = self.replay_core.replay_and_verify(steps);
        let drc_pass = drc_result.passed;
        stages.push(StageResult {
            name: "DRC",
            passed: drc_pass,
            details: if drc_pass {
                format!("{} frames verified deterministic", drc_result.total_frames)
            } else {
                format!(
                    "{} hash mismatches in {} frames",
                    drc_result.mismatches.len(),
                    drc_result.total_frames
                )
            },
        });
        if !drc_pass {
            blocking_failures.push(format!(
                "DRC: {} hash mismatches",
                drc_result.mismatches.len()
            ));
        }

        // Stage 3: Safety Envelope
        let envelope_result = self.safety_envelope.validate(outputs);
        let envelope_pass = envelope_result.passed;
        stages.push(StageResult {
            name: "Safety Envelope",
            passed: envelope_pass,
            details: if envelope_pass {
                "All 6 safety limits within bounds".into()
            } else {
                format!("{} envelope violations", envelope_result.violations.len())
            },
        });
        if !envelope_pass {
            for v in &envelope_result.violations {
                blocking_failures.push(format!(
                    "{}: {:.4} > {:.4} at frame {}",
                    v.violation_type.name(),
                    v.value,
                    v.limit,
                    v.frame_index
                ));
            }
        }

        // Stage 4: Manifest Lock
        self.manifest.set_config_hash(config_data);
        let manifest_check = self.manifest.validate_config_hash(config_data);
        stages.push(StageResult {
            name: "Manifest Lock",
            passed: manifest_check,
            details: format!(
                "Config bundle hash: {:016x}",
                self.manifest.config_bundle.config_bundle_hash
            ),
        });
        if !manifest_check {
            blocking_failures.push("Manifest config hash mismatch".into());
        }

        // Stage 5: Final Hash Validation
        self.manifest
            .update_certification(drc_pass, pbse_pass, envelope_pass);
        let hash_pass = self.manifest.manifest_hash != 0;
        stages.push(StageResult {
            name: "Hash Validation",
            passed: hash_pass,
            details: format!("Manifest hash: {:016x}", self.manifest.manifest_hash),
        });

        // Overall
        let certified = pbse_pass && drc_pass && envelope_pass && manifest_check && hash_pass;
        let overall_status = if certified {
            CertificationStatus::Certified
        } else {
            CertificationStatus::Failed
        };

        let report = CertificationReport {
            overall_status,
            stages,
            blocking_failures,
        };

        let result = CertificationResult {
            certified,
            report,
            manifest: self.manifest.clone(),
        };

        self.last_result = Some(result);
        self.last_result.as_ref().unwrap()
    }

    /// Reset all state.
    pub fn reset(&mut self) {
        self.replay_core.reset();
        self.safety_envelope.reset();
        self.manifest = FluxManifest::new();
        self.last_result = None;
    }

    /// Get certification report as JSON.
    pub fn report_json(&self) -> Result<String, String> {
        let result = self.last_result.as_ref().ok_or("No certification result")?;

        use std::fmt::Write;
        let mut json = String::with_capacity(2048);
        write!(json, "{{").map_err(|e| e.to_string())?;

        write!(
            json,
            "\"overall_status\":\"{}\",",
            result.report.overall_status.name()
        )
        .map_err(|e| e.to_string())?;
        write!(json, "\"certified\":{},", result.certified).map_err(|e| e.to_string())?;

        write!(json, "\"stages\":[").map_err(|e| e.to_string())?;
        for (i, stage) in result.report.stages.iter().enumerate() {
            if i > 0 {
                write!(json, ",").map_err(|e| e.to_string())?;
            }
            write!(
                json,
                "{{\"name\":\"{}\",\"passed\":{},\"details\":\"{}\"}}",
                stage.name,
                stage.passed,
                stage.details.replace('\"', "\\\"")
            )
            .map_err(|e| e.to_string())?;
        }
        write!(json, "],").map_err(|e| e.to_string())?;

        write!(json, "\"blocking_failures\":[").map_err(|e| e.to_string())?;
        for (i, failure) in result.report.blocking_failures.iter().enumerate() {
            if i > 0 {
                write!(json, ",").map_err(|e| e.to_string())?;
            }
            write!(json, "\"{}\"", failure.replace('\"', "\\\"")).map_err(|e| e.to_string())?;
        }
        write!(json, "]").map_err(|e| e.to_string())?;

        write!(json, "}}").map_err(|e| e.to_string())?;
        Ok(json)
    }
}

impl Default for CertificationGate {
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
    use crate::core::engine::AurexisEngine;
    use crate::qa::pbse::{PbseResult, PreBakeSimulator};

    fn test_steps() -> Vec<SimulationStep> {
        (0..50)
            .map(|i| SimulationStep {
                elapsed_ms: 50,
                volatility: 0.5,
                rtp: 96.0,
                win_multiplier: if i % 10 == 0 { 5.0 } else { 0.0 },
                jackpot_proximity: 0.0,
                rms_db: -20.0,
                hf_db: -26.0,
            })
            .collect()
    }

    fn run_engine(steps: &[SimulationStep]) -> Vec<DeterministicParameterMap> {
        let mut engine = AurexisEngine::new();
        engine.initialize();
        engine.set_seed(0, 0, 0, 0);

        steps
            .iter()
            .map(|step| {
                engine.set_volatility(step.volatility);
                engine.set_rtp(step.rtp);
                engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
                engine.set_metering(step.rms_db, step.hf_db);
                engine.record_spin(step.win_multiplier, false, false);
                engine.compute_cloned(step.elapsed_ms)
            })
            .collect()
    }

    #[test]
    fn test_certification_without_pbse() {
        let mut gate = CertificationGate::new();
        let steps = test_steps();
        let outputs = run_engine(&steps);

        let result = gate.certify(None, &steps, &outputs, "test config");
        assert!(!result.certified, "Should fail without PBSE");
        assert!(!result.report.blocking_failures.is_empty());
    }

    #[test]
    fn test_certification_with_passing_pbse() {
        let mut simulator = PreBakeSimulator::new();
        let pbse_result = simulator.run_full_simulation().clone();

        let mut gate = CertificationGate::new();
        let steps = test_steps();
        let outputs = run_engine(&steps);

        let result = gate.certify(Some(&pbse_result), &steps, &outputs, "test config");
        // DRC should pass (deterministic replay)
        let drc_stage = result
            .report
            .stages
            .iter()
            .find(|s| s.name == "DRC")
            .unwrap();
        assert!(drc_stage.passed, "DRC should pass for deterministic engine");
    }

    #[test]
    fn test_certification_report_json() {
        let mut gate = CertificationGate::new();
        let steps = test_steps();
        let outputs = run_engine(&steps);

        gate.certify(None, &steps, &outputs, "config");
        let json = gate.report_json().expect("JSON should work");
        assert!(json.contains("\"overall_status\":"));
        assert!(json.contains("\"stages\":"));
        assert!(json.contains("\"blocking_failures\":"));
    }

    #[test]
    fn test_certification_reset() {
        let mut gate = CertificationGate::new();
        let steps = test_steps();
        let outputs = run_engine(&steps);

        gate.certify(None, &steps, &outputs, "config");
        assert!(gate.last_result().is_some());

        gate.reset();
        assert!(gate.last_result().is_none());
    }

    #[test]
    fn test_manifest_after_certification() {
        let mut gate = CertificationGate::new();
        let steps = test_steps();
        let outputs = run_engine(&steps);

        gate.certify(None, &steps, &outputs, "config");
        let manifest = gate.manifest();
        assert_ne!(manifest.manifest_hash, 0);
        assert_ne!(manifest.config_bundle.config_bundle_hash, 0);
    }
}
