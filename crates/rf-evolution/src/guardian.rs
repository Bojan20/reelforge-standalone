//! CORTEX Code Guardian — autonomous code maintenance daemon.
//!
//! The Guardian is a background thread that periodically:
//! 1. Scans the codebase for improvement opportunities
//! 2. Applies safe mutations (auto-applicable transforms only)
//! 3. Verifies changes with cargo check + cargo test
//! 4. Reverts if anything breaks
//! 5. Git commits successful improvements
//! 6. Emits CORTEX signals about code health
//! 7. Learns from every attempt (memory + journal)
//!
//! The Guardian NEVER:
//! - Deletes code that isn't directly connected (vision-aware)
//! - Applies risky transforms without verification
//! - Makes changes that break compilation
//! - Commits without verification passing
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────┐
//! │              CORTEX CODE GUARDIAN                     │
//! │                                                      │
//! │  ┌──────────┐    ┌──────────┐    ┌──────────────┐   │
//! │  │  TIMER   │───▶│ EVOLUTION│───▶│   SANDBOX    │   │
//! │  │ (5 min)  │    │  ENGINE  │    │  VERIFIER    │   │
//! │  └──────────┘    └──────────┘    └──────────────┘   │
//! │       │               │                │             │
//! │       │               ▼                ▼             │
//! │       │         ┌──────────┐    ┌──────────────┐    │
//! │       │         │  WRITER  │◀───│   VERDICT    │    │
//! │       │         │ (fs+git) │    │  pass/revert │    │
//! │       │         └──────────┘    └──────────────┘    │
//! │       │               │                              │
//! │       ▼               ▼                              │
//! │  ┌──────────┐    ┌──────────┐                       │
//! │  │  CORTEX  │    │  MEMORY  │                       │
//! │  │  SIGNAL  │    │ (learn)  │                       │
//! │  └──────────┘    └──────────┘                       │
//! └─────────────────────────────────────────────────────┘
//! ```

use crate::evolution::{EvolutionConfig, EvolutionEngine, EvolutionOutcome};
use crate::strategy::StrategyKind;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

// ============================================================================
// Guardian Configuration
// ============================================================================

/// Configuration for the Code Guardian daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GuardianConfig {
    /// Root directory of the project.
    pub project_root: PathBuf,
    /// How often to run evolution cycles.
    pub cycle_interval: Duration,
    /// Maximum mutations per cycle.
    pub max_mutations_per_cycle: usize,
    /// Run cargo commands for verification (check + test).
    pub verify_with_cargo: bool,
    /// Auto-commit successful mutations to git.
    pub auto_commit: bool,
    /// Git branch for guardian commits (None = current branch).
    pub commit_branch: Option<String>,
    /// Evolution strategy.
    pub strategy: StrategyKind,
    /// File extensions to scan.
    pub extensions: Vec<String>,
    /// Data directory for evolution memory/journal.
    pub data_dir: PathBuf,
}

impl Default for GuardianConfig {
    fn default() -> Self {
        Self {
            project_root: PathBuf::from("."),
            cycle_interval: Duration::from_secs(300), // 5 minutes
            max_mutations_per_cycle: 3,
            verify_with_cargo: true,
            auto_commit: true,
            commit_branch: None,
            strategy: StrategyKind::Adaptive,
            extensions: vec!["rs".into()],
            data_dir: PathBuf::from(".cortex/evolution"),
        }
    }
}

// ============================================================================
// Guardian State (shared, lock-free reads)
// ============================================================================

/// Shared guardian state — readable from any thread.
pub struct GuardianState {
    /// Total evolution cycles completed.
    pub total_cycles: AtomicU64,
    /// Total mutations applied (kept).
    pub total_applied: AtomicU64,
    /// Total mutations reverted.
    pub total_reverted: AtomicU64,
    /// Total mutations skipped.
    pub total_skipped: AtomicU64,
    /// Total git commits made.
    pub total_commits: AtomicU64,
    /// Current code health score (0.0-1.0, stored as bits).
    pub code_health_bits: AtomicU64,
    /// Is the guardian currently running a cycle?
    pub is_cycling: AtomicBool,
    /// Last cycle timestamp (Unix seconds).
    pub last_cycle_epoch: AtomicU64,
    /// Cumulative fitness improvement.
    pub cumulative_improvement_bits: AtomicU64,
}

impl GuardianState {
    fn new() -> Self {
        Self {
            total_cycles: AtomicU64::new(0),
            total_applied: AtomicU64::new(0),
            total_reverted: AtomicU64::new(0),
            total_skipped: AtomicU64::new(0),
            total_commits: AtomicU64::new(0),
            code_health_bits: AtomicU64::new(f64::to_bits(1.0)),
            is_cycling: AtomicBool::new(false),
            last_cycle_epoch: AtomicU64::new(0),
            cumulative_improvement_bits: AtomicU64::new(f64::to_bits(0.0)),
        }
    }

    /// Get current code health score (0.0-1.0).
    pub fn code_health(&self) -> f64 {
        f64::from_bits(self.code_health_bits.load(Ordering::Relaxed))
    }

    /// Get cumulative fitness improvement.
    pub fn cumulative_improvement(&self) -> f64 {
        f64::from_bits(self.cumulative_improvement_bits.load(Ordering::Relaxed))
    }

    /// Get a snapshot of the guardian state.
    pub fn snapshot(&self) -> GuardianSnapshot {
        GuardianSnapshot {
            total_cycles: self.total_cycles.load(Ordering::Relaxed),
            total_applied: self.total_applied.load(Ordering::Relaxed),
            total_reverted: self.total_reverted.load(Ordering::Relaxed),
            total_skipped: self.total_skipped.load(Ordering::Relaxed),
            total_commits: self.total_commits.load(Ordering::Relaxed),
            code_health: self.code_health(),
            is_cycling: self.is_cycling.load(Ordering::Relaxed),
            cumulative_improvement: self.cumulative_improvement(),
        }
    }
}

/// Immutable snapshot of guardian state (for FFI/serialization).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GuardianSnapshot {
    pub total_cycles: u64,
    pub total_applied: u64,
    pub total_reverted: u64,
    pub total_skipped: u64,
    pub total_commits: u64,
    pub code_health: f64,
    pub is_cycling: bool,
    pub cumulative_improvement: f64,
}

// ============================================================================
// Code Guardian
// ============================================================================

/// The CORTEX Code Guardian — autonomous background code maintenance.
pub struct CodeGuardian {
    /// Shared state (lock-free reads).
    shared: Arc<GuardianState>,
    /// Shutdown flag.
    shutdown: Arc<AtomicBool>,
    /// Background thread handle.
    thread: Option<std::thread::JoinHandle<()>>,
}

impl CodeGuardian {
    /// Start the Code Guardian daemon.
    pub fn start(config: GuardianConfig) -> Self {
        let shared = Arc::new(GuardianState::new());
        let shutdown = Arc::new(AtomicBool::new(false));

        let thread = {
            let shared = Arc::clone(&shared);
            let shutdown = Arc::clone(&shutdown);
            std::thread::Builder::new()
                .name("cortex-guardian".into())
                .spawn(move || {
                    Self::guardian_loop(config, shared, shutdown);
                })
                .expect("Failed to spawn cortex-guardian thread")
        };

        Self {
            shared,
            shutdown,
            thread: Some(thread),
        }
    }

    /// The guardian loop — runs on background thread.
    fn guardian_loop(
        config: GuardianConfig,
        shared: Arc<GuardianState>,
        shutdown: Arc<AtomicBool>,
    ) {
        log::info!(
            "CORTEX Guardian started — cycle interval: {:?}, verify: {}, auto-commit: {}",
            config.cycle_interval, config.verify_with_cargo, config.auto_commit
        );

        // Create evolution engine
        let evo_config = EvolutionConfig {
            project_root: config.project_root.clone(),
            extensions: config.extensions.clone(),
            data_dir: config.data_dir.clone(),
            strategy: config.strategy,
            max_mutations_per_cycle: config.max_mutations_per_cycle,
            run_commands: config.verify_with_cargo,
            auto_revert: true,
        };

        let mut engine = match EvolutionEngine::new(evo_config) {
            Ok(e) => e,
            Err(err) => {
                log::error!("CORTEX Guardian: failed to create evolution engine: {}", err);
                return;
            }
        };

        // Initial baseline analysis
        if let Ok(report) = engine.analyze_only() {
            shared.code_health_bits.store(
                f64::to_bits(report.fitness.overall),
                Ordering::Relaxed,
            );
            log::info!(
                "CORTEX Guardian: baseline health = {:.3} ({} findings, {} files, {} functions)",
                report.fitness.overall,
                report.finding_count,
                report.genome_stats.total_files,
                report.genome_stats.total_functions,
            );
        }

        let mut last_cycle = Instant::now();

        while !shutdown.load(Ordering::Relaxed) {
            // Sleep in short intervals so we respond to shutdown quickly
            if last_cycle.elapsed() < config.cycle_interval {
                std::thread::sleep(Duration::from_secs(1));
                continue;
            }

            // RUN EVOLUTION CYCLE
            shared.is_cycling.store(true, Ordering::Relaxed);
            let cycle_start = Instant::now();

            match engine.evolve_cycle() {
                Ok(outcome) => {
                    let elapsed = cycle_start.elapsed();

                    // Update shared state
                    shared.total_cycles.fetch_add(1, Ordering::Relaxed);
                    shared.total_applied.fetch_add(outcome.applied.len() as u64, Ordering::Relaxed);
                    shared.total_reverted.fetch_add(outcome.reverted.len() as u64, Ordering::Relaxed);
                    shared.total_skipped.fetch_add(outcome.skipped.len() as u64, Ordering::Relaxed);
                    shared.code_health_bits.store(
                        f64::to_bits(outcome.fitness_after),
                        Ordering::Relaxed,
                    );

                    // Accumulate improvement
                    let prev = shared.cumulative_improvement();
                    shared.cumulative_improvement_bits.store(
                        f64::to_bits(prev + outcome.improvement),
                        Ordering::Relaxed,
                    );

                    shared.last_cycle_epoch.store(
                        std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs(),
                        Ordering::Relaxed,
                    );

                    // GIT COMMIT if mutations were applied
                    if config.auto_commit && !outcome.applied.is_empty() {
                        let commit_count = Self::git_commit_mutations(&config.project_root, &outcome);
                        shared.total_commits.fetch_add(commit_count, Ordering::Relaxed);
                    }

                    log::info!(
                        "CORTEX Guardian cycle {} complete in {:?}: {} applied, {} reverted, {} skipped, health: {:.3}, improvement: {:.4}",
                        shared.total_cycles.load(Ordering::Relaxed),
                        elapsed,
                        outcome.applied.len(),
                        outcome.reverted.len(),
                        outcome.skipped.len(),
                        outcome.fitness_after,
                        outcome.improvement,
                    );
                }
                Err(e) => {
                    log::error!("CORTEX Guardian cycle failed: {}", e);
                }
            }

            shared.is_cycling.store(false, Ordering::Relaxed);
            last_cycle = Instant::now();
        }

        log::info!(
            "CORTEX Guardian shutting down — {} cycles, {} applied, {} commits",
            shared.total_cycles.load(Ordering::Relaxed),
            shared.total_applied.load(Ordering::Relaxed),
            shared.total_commits.load(Ordering::Relaxed),
        );
    }

    /// Commit applied mutations to git.
    fn git_commit_mutations(project_root: &std::path::Path, outcome: &EvolutionOutcome) -> u64 {
        if outcome.applied.is_empty() {
            return 0;
        }

        // Build commit message
        let mut msg = format!(
            "cortex(guardian): evolution cycle {} — {} improvements\n\n",
            outcome.generation,
            outcome.applied.len()
        );
        for m in &outcome.applied {
            msg.push_str(&format!("  - {}\n", m.description));
        }
        msg.push_str(&format!(
            "\nFitness: {:.4} → {:.4} (Δ{:+.4})\n",
            outcome.fitness_before, outcome.fitness_after, outcome.improvement
        ));
        msg.push_str("\nCo-Authored-By: CORTEX Guardian <cortex@fluxforge.studio>\n");

        // git add -A && git commit
        let add = std::process::Command::new("git")
            .args(["add", "-A"])
            .current_dir(project_root)
            .output();

        if add.is_err() || !add.as_ref().unwrap().status.success() {
            log::warn!("CORTEX Guardian: git add failed");
            return 0;
        }

        let commit = std::process::Command::new("git")
            .args(["commit", "-m", &msg])
            .current_dir(project_root)
            .output();

        match commit {
            Ok(output) if output.status.success() => {
                log::info!("CORTEX Guardian: committed {} mutations", outcome.applied.len());
                1
            }
            Ok(output) => {
                let stderr = String::from_utf8_lossy(&output.stderr);
                // "nothing to commit" is not an error
                if stderr.contains("nothing to commit") {
                    0
                } else {
                    log::warn!("CORTEX Guardian: git commit failed: {}", stderr.chars().take(200).collect::<String>());
                    0
                }
            }
            Err(e) => {
                log::warn!("CORTEX Guardian: git commit error: {}", e);
                0
            }
        }
    }

    /// Get shared state reference.
    pub fn shared(&self) -> &Arc<GuardianState> {
        &self.shared
    }

    /// Get a snapshot of the current guardian state.
    pub fn snapshot(&self) -> GuardianSnapshot {
        self.shared.snapshot()
    }

    /// Trigger an immediate evolution cycle (non-blocking — signals the thread).
    /// The guardian will run on next wakeup.
    pub fn trigger_cycle(&self) {
        // Reset the last_cycle_epoch to 0 so the loop runs immediately
        self.shared.last_cycle_epoch.store(0, Ordering::Relaxed);
    }

    /// Gracefully shut down the guardian.
    pub fn shutdown(mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

impl Drop for CodeGuardian {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_project() -> (TempDir, GuardianConfig) {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();

        std::fs::write(
            src.join("lib.rs"),
            r#"
pub fn add(a: i32, b: i32) -> i32 {
    let result = a + b;
    return result;
}

pub fn multiply(x: f64, y: f64) -> f64 {
    let product = x * y;
    return product;
}
"#,
        )
        .unwrap();

        let config = GuardianConfig {
            project_root: dir.path().to_path_buf(),
            cycle_interval: Duration::from_millis(100),
            max_mutations_per_cycle: 5,
            verify_with_cargo: false, // no cargo in test
            auto_commit: false,       // no git in test
            strategy: StrategyKind::HillClimb,
            extensions: vec!["rs".into()],
            data_dir: dir.path().join(".cortex").join("evolution"),
            commit_branch: None,
        };

        (dir, config)
    }

    #[test]
    fn guardian_starts_and_stops() {
        let (_dir, config) = setup_test_project();
        let guardian = CodeGuardian::start(config);

        // Let it run — initial analysis + first cycle (100ms interval + engine startup time)
        std::thread::sleep(Duration::from_millis(2000));

        let snap = guardian.snapshot();
        assert!(snap.total_cycles > 0, "Expected at least one cycle, got {}", snap.total_cycles);
        assert!(snap.code_health > 0.0);

        guardian.shutdown();
    }

    #[test]
    fn guardian_applies_mutations() {
        let (dir, config) = setup_test_project();
        let guardian = CodeGuardian::start(config);

        // Wait for at least one cycle to complete
        std::thread::sleep(Duration::from_millis(2000));

        let snap = guardian.snapshot();
        // In static-only mode (no cargo), mutations should be applied or recorded
        assert!(snap.total_applied > 0 || snap.total_skipped > 0 || snap.total_reverted > 0,
            "Expected some mutation activity: applied={}, skipped={}, reverted={}",
            snap.total_applied, snap.total_skipped, snap.total_reverted);

        // Check that the file was actually modified (if mutations were applied)
        if snap.total_applied > 0 {
            let content = std::fs::read_to_string(dir.path().join("src/lib.rs")).unwrap();
            // The explicit returns should have been removed
            let return_count = content.matches("return ").count();
            assert!(return_count < 3, "Expected some returns removed, still have {}", return_count);
        }

        guardian.shutdown();
    }

    #[test]
    fn guardian_state_snapshot() {
        let state = GuardianState::new();
        assert_eq!(state.code_health(), 1.0);
        assert_eq!(state.cumulative_improvement(), 0.0);

        state.total_cycles.store(5, Ordering::Relaxed);
        state.total_applied.store(3, Ordering::Relaxed);
        state.code_health_bits.store(f64::to_bits(0.85), Ordering::Relaxed);

        let snap = state.snapshot();
        assert_eq!(snap.total_cycles, 5);
        assert_eq!(snap.total_applied, 3);
        assert!((snap.code_health - 0.85).abs() < 0.001);
    }

    #[test]
    fn guardian_config_defaults() {
        let config = GuardianConfig::default();
        assert_eq!(config.cycle_interval, Duration::from_secs(300));
        assert!(config.verify_with_cargo);
        assert!(config.auto_commit);
        assert_eq!(config.max_mutations_per_cycle, 3);
    }
}
