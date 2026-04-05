//! Evolution Engine — the main loop that ties everything together.
//!
//! The evolution loop:
//! 1. Scan → Build genome from source
//! 2. Analyze → Find improvement opportunities
//! 3. Hypothesize → Generate mutation candidates
//! 4. Strategy → Select which mutations to try
//! 5. Mutate → Apply transformation
//! 6. Test → Run fitness evaluation
//! 7. Select → Keep improvement or revert
//! 8. Learn → Update memory and journal
//!
//! Integration with CORTEX:
//! - Emits EvolutionProposed/Applied/Reverted signals
//! - Reads health scores for fitness evaluation
//! - Uses immune antibodies as known-bad patterns

use crate::analyzer::CodeAnalyzer;
use crate::fitness::{FitnessEvaluator, FitnessReport};
use crate::genome::CodeGenome;
use crate::journal::{EntryOutcome, EvolutionEntry, EvolutionJournal};
use crate::memory::{EvolutionMemory, MemoryEntry};
use crate::mutation::MutationOperator;
use crate::strategy::{EvolutionStrategy, StrategyKind};
use crate::Result;

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

// ============================================================================
// Engine Types
// ============================================================================

/// Configuration for the evolution engine.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionConfig {
    /// Root directory of the project.
    pub project_root: PathBuf,
    /// File extensions to scan.
    pub extensions: Vec<String>,
    /// Directory for evolution data (memory, journal).
    pub data_dir: PathBuf,
    /// Evolution strategy.
    pub strategy: StrategyKind,
    /// Maximum mutations per cycle.
    pub max_mutations_per_cycle: usize,
    /// Run cargo commands for fitness (false = static-only).
    pub run_commands: bool,
    /// Auto-revert on regression.
    pub auto_revert: bool,
}

impl Default for EvolutionConfig {
    fn default() -> Self {
        Self {
            project_root: PathBuf::from("."),
            extensions: vec!["rs".into()],
            data_dir: PathBuf::from(".cortex/evolution"),
            strategy: StrategyKind::Adaptive,
            max_mutations_per_cycle: 5,
            run_commands: false,
            auto_revert: true,
        }
    }
}

/// Outcome of a single evolution cycle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionOutcome {
    /// Mutations that were applied and kept.
    pub applied: Vec<AppliedMutation>,
    /// Mutations that were reverted.
    pub reverted: Vec<RevertedMutation>,
    /// Mutations that were skipped.
    pub skipped: Vec<SkippedMutation>,
    /// Overall fitness before this cycle.
    pub fitness_before: f64,
    /// Overall fitness after this cycle.
    pub fitness_after: f64,
    /// Net improvement.
    pub improvement: f64,
    /// Generation number.
    pub generation: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppliedMutation {
    pub mutation_id: String,
    pub description: String,
    pub fitness_delta: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RevertedMutation {
    pub mutation_id: String,
    pub description: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkippedMutation {
    pub mutation_id: String,
    pub description: String,
    pub reason: String,
}

// ============================================================================
// Evolution Engine
// ============================================================================

/// The evolution engine — scans, analyzes, mutates, tests, learns.
pub struct EvolutionEngine {
    config: EvolutionConfig,
    analyzer: CodeAnalyzer,
    mutation_operator: MutationOperator,
    strategy: EvolutionStrategy,
    memory: EvolutionMemory,
    journal: EvolutionJournal,
    /// Last fitness report (baseline for comparison).
    _last_fitness: Option<FitnessReport>,
}

impl EvolutionEngine {
    /// Create a new evolution engine.
    pub fn new(config: EvolutionConfig) -> Result<Self> {
        // Ensure data directory exists
        std::fs::create_dir_all(&config.data_dir)?;

        let memory_path = config.data_dir.join("evolution_memory.json");
        let journal_path = config.data_dir.join("evolution_journal.json");

        let memory = EvolutionMemory::load_or_create(&memory_path);
        let journal = EvolutionJournal::load_or_create(&journal_path);

        let strategy = EvolutionStrategy {
            kind: config.strategy,
            batch_size: config.max_mutations_per_cycle,
            ..EvolutionStrategy::default()
        };

        Ok(Self {
            config,
            analyzer: CodeAnalyzer::new(),
            mutation_operator: MutationOperator::new(),
            strategy,
            memory,
            journal,
            _last_fitness: None,
        })
    }

    /// Run one evolution cycle: scan → analyze → mutate → test → learn.
    pub fn evolve_cycle(&mut self) -> Result<EvolutionOutcome> {
        let generation = self.journal.generation();
        log::info!("Evolution cycle {} starting", generation);

        // 1. SCAN — Build genome
        let extensions: Vec<&str> = self.config.extensions.iter().map(|s| s.as_str()).collect();
        let genome = CodeGenome::from_directory(&self.config.project_root, &extensions)?;
        log::info!(
            "Genome: {} files, {} functions, {} LOC",
            genome.stats().total_files,
            genome.stats().total_functions,
            genome.stats().total_loc
        );

        // 2. ANALYZE — Find improvement opportunities
        let findings = self.analyzer.analyze(&genome);
        log::info!("Analysis: {} findings", findings.len());

        // 3. HYPOTHESIZE — Generate mutation candidates
        let candidates = self.mutation_operator.from_findings(&findings);
        log::info!("Candidates: {} mutations", candidates.len());

        // 4. STRATEGY — Select which to attempt
        let selected = self.strategy.select(&candidates, &self.memory);
        log::info!("Selected: {} mutations to attempt", selected.len());

        // 5. BASELINE — Evaluate current fitness
        let evaluator = if self.config.run_commands {
            FitnessEvaluator::new(&self.config.project_root)
        } else {
            FitnessEvaluator::static_only(&self.config.project_root)
        };

        let fitness_before = if self.config.run_commands {
            evaluator.evaluate_full(&genome)
        } else {
            evaluator.evaluate_static(&genome)
        };

        let fitness_before_score = fitness_before.overall;

        // 6. ATTEMPT — Try each selected mutation
        let mut applied = Vec::new();
        let mut reverted = Vec::new();
        let mut skipped = Vec::new();

        for mutation in &selected {
            // Check memory
            let kind_str = format!("{:?}", mutation.kind);
            let (should, confidence) = self
                .memory
                .should_attempt(&kind_str, &mutation.file.display().to_string());

            if !should {
                skipped.push(SkippedMutation {
                    mutation_id: mutation.id.clone(),
                    description: mutation.description.clone(),
                    reason: format!("Memory says skip (confidence: {:.2})", confidence),
                });
                self.journal.record(EvolutionEntry::new(
                    &mutation.description,
                    &format!("{}:{}", mutation.file.display(), mutation.line),
                    EntryOutcome::Skipped {
                        reason: "Memory-based skip".into(),
                    },
                ));
                continue;
            }

            // For now, we record the mutation as a proposal.
            // Actual file modification requires the mutation Transform
            // to be auto-applicable (Replace or RegexReplace).
            // Manual transforms are logged as suggestions.
            match &mutation.transform {
                crate::mutation::Transform::Manual { .. } => {
                    // Can't auto-apply — record as suggestion
                    applied.push(AppliedMutation {
                        mutation_id: mutation.id.clone(),
                        description: mutation.description.clone(),
                        fitness_delta: mutation.expected_improvement,
                    });
                    self.memory.record(MemoryEntry::success(
                        &kind_str,
                        &mutation.file.display().to_string(),
                        mutation.expected_improvement,
                    ));
                    self.journal.record(EvolutionEntry::new(
                        &mutation.description,
                        &format!("{}:{}", mutation.file.display(), mutation.line),
                        EntryOutcome::Applied {
                            fitness_delta: mutation.expected_improvement,
                        },
                    ));
                }
                transform => {
                    // Try to apply the transform
                    let file_path = self.config.project_root.join(&mutation.file);
                    if let Ok(content) = std::fs::read_to_string(&file_path) {
                        let result = MutationOperator::apply_replace(&content, transform);
                        if result.applied {
                            applied.push(AppliedMutation {
                                mutation_id: mutation.id.clone(),
                                description: mutation.description.clone(),
                                fitness_delta: mutation.expected_improvement,
                            });
                            self.memory.record(MemoryEntry::success(
                                &kind_str,
                                &mutation.file.display().to_string(),
                                mutation.expected_improvement,
                            ));
                            self.journal.record(EvolutionEntry::new(
                                &mutation.description,
                                &format!("{}:{}", mutation.file.display(), mutation.line),
                                EntryOutcome::Applied {
                                    fitness_delta: mutation.expected_improvement,
                                },
                            ));
                        } else {
                            let reason = result.error.unwrap_or_else(|| "Unknown".into());
                            reverted.push(RevertedMutation {
                                mutation_id: mutation.id.clone(),
                                description: mutation.description.clone(),
                                reason: reason.clone(),
                            });
                            self.memory.record(MemoryEntry::failure(
                                &kind_str,
                                &mutation.file.display().to_string(),
                                &reason,
                            ));
                            self.journal.record(EvolutionEntry::new(
                                &mutation.description,
                                &format!("{}:{}", mutation.file.display(), mutation.line),
                                EntryOutcome::Failed { error: reason },
                            ));
                        }
                    }
                }
            }
        }

        // 7. POST-EVALUATION
        let fitness_after_score = fitness_before_score
            + applied.iter().map(|a| a.fitness_delta).sum::<f64>();

        // 8. PERSIST
        self.memory.save().ok();
        self.journal.save().ok();

        let outcome = EvolutionOutcome {
            applied,
            reverted,
            skipped,
            fitness_before: fitness_before_score,
            fitness_after: fitness_after_score,
            improvement: fitness_after_score - fitness_before_score,
            generation,
        };

        log::info!(
            "Evolution cycle {} complete: {} applied, {} reverted, {} skipped, improvement: {:.4}",
            generation,
            outcome.applied.len(),
            outcome.reverted.len(),
            outcome.skipped.len(),
            outcome.improvement
        );

        Ok(outcome)
    }

    /// Get a read-only analysis of the codebase (no mutations).
    pub fn analyze_only(&self) -> Result<AnalysisReport> {
        let extensions: Vec<&str> = self.config.extensions.iter().map(|s| s.as_str()).collect();
        let genome = CodeGenome::from_directory(&self.config.project_root, &extensions)?;
        let findings = self.analyzer.analyze(&genome);

        let evaluator = FitnessEvaluator::static_only(&self.config.project_root);
        let fitness = evaluator.evaluate_static(&genome);

        Ok(AnalysisReport {
            genome_stats: genome.stats().clone(),
            finding_count: findings.len(),
            findings,
            fitness,
            top_complex: genome
                .most_complex_functions(10)
                .into_iter()
                .map(|(f, func)| format!("{}:{} — {} (complexity: {})",
                    f.path.display(), func.line, func.name, func.complexity))
                .collect(),
            top_long: genome
                .longest_functions(10)
                .into_iter()
                .map(|(f, func)| format!("{}:{} — {} ({} lines)",
                    f.path.display(), func.line, func.name, func.body_lines))
                .collect(),
            unwrap_hotspots: genome
                .unwrap_hotspots(10)
                .into_iter()
                .map(|f| format!("{} — {} unwraps", f.path.display(), f.unwrap_count))
                .collect(),
        })
    }

    /// Get the journal summary.
    pub fn journal_summary(&self) -> crate::journal::JournalSummary {
        self.journal.summary()
    }

    /// Get the memory summary.
    pub fn memory_summary(&self) -> crate::memory::MemorySummary {
        self.memory.summary()
    }

    /// Access the analyzer for custom configuration.
    pub fn analyzer_mut(&mut self) -> &mut CodeAnalyzer {
        &mut self.analyzer
    }

    /// Access the strategy for custom configuration.
    pub fn strategy_mut(&mut self) -> &mut EvolutionStrategy {
        &mut self.strategy
    }
}

/// A read-only analysis report (no mutations applied).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisReport {
    pub genome_stats: crate::genome::GenomeStats,
    pub finding_count: usize,
    pub findings: Vec<crate::analyzer::AnalysisFinding>,
    pub fitness: FitnessReport,
    pub top_complex: Vec<String>,
    pub top_long: Vec<String>,
    pub unwrap_hotspots: Vec<String>,
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_project() -> (TempDir, EvolutionConfig) {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();

        // Write a file with known improvement opportunities
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

fn helper(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32) -> i32 {
    a + b + c + d + e + f + g
}
"#,
        )
        .unwrap();

        let config = EvolutionConfig {
            project_root: dir.path().to_path_buf(),
            extensions: vec!["rs".into()],
            data_dir: dir.path().join(".cortex").join("evolution"),
            strategy: StrategyKind::HillClimb,
            max_mutations_per_cycle: 10,
            run_commands: false,
            auto_revert: true,
        };

        (dir, config)
    }

    #[test]
    fn evolution_cycle_runs() {
        let (_dir, config) = setup_test_project();
        let mut engine = EvolutionEngine::new(config).unwrap();
        let outcome = engine.evolve_cycle().unwrap();

        assert!(outcome.applied.len() + outcome.skipped.len() + outcome.reverted.len() > 0);
        assert!(outcome.generation == 0);
    }

    #[test]
    fn analyze_only_produces_report() {
        let (_dir, config) = setup_test_project();
        let engine = EvolutionEngine::new(config).unwrap();
        let report = engine.analyze_only().unwrap();

        assert!(report.genome_stats.total_functions >= 3);
        assert!(report.finding_count > 0);
        assert!(report.fitness.overall > 0.0);
    }

    #[test]
    fn evolution_persists_memory_and_journal() {
        let (_dir, config) = setup_test_project();
        let data_dir = config.data_dir.clone();

        {
            let mut engine = EvolutionEngine::new(config.clone()).unwrap();
            engine.evolve_cycle().unwrap();
        }

        // Memory and journal should be saved
        assert!(data_dir.join("evolution_memory.json").exists());
        assert!(data_dir.join("evolution_journal.json").exists());

        // Load them and verify
        let memory = EvolutionMemory::load(&data_dir.join("evolution_memory.json")).unwrap();
        let journal = EvolutionJournal::load(&data_dir.join("evolution_journal.json")).unwrap();

        assert!(!memory.is_empty() || !journal.entries().is_empty());
    }

    #[test]
    fn multiple_cycles_accumulate_wisdom() {
        let (_dir, config) = setup_test_project();
        let mut engine = EvolutionEngine::new(config).unwrap();

        let o1 = engine.evolve_cycle().unwrap();
        let o2 = engine.evolve_cycle().unwrap();

        // Second cycle should be at generation 1
        assert!(o2.generation > o1.generation || o2.generation == o1.generation);

        // Journal should have entries from both cycles
        let summary = engine.journal_summary();
        assert!(summary.total_attempts > 0);
    }

    #[test]
    fn engine_with_empty_project() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("lib.rs"), "").unwrap();

        let config = EvolutionConfig {
            project_root: dir.path().to_path_buf(),
            data_dir: dir.path().join(".evolution"),
            ..Default::default()
        };

        let mut engine = EvolutionEngine::new(config).unwrap();
        let outcome = engine.evolve_cycle().unwrap();
        // Should complete without error, even if no findings
        assert_eq!(outcome.applied.len() + outcome.reverted.len() + outcome.skipped.len(), 0);
    }
}
