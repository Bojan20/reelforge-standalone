//! # rf-evolution — CORTEX Evolution Engine
//!
//! Self-learning, self-evolving code organism. Transforms CORTEX from a
//! reactive nervous system into a proactive, self-improving intelligence.
//!
//! ## Architecture
//!
//! ```text
//!    ┌──────────────────────────────────────────────────────────┐
//!    │                   EVOLUTION ENGINE                        │
//!    │                                                          │
//!    │  ┌──────────┐   ┌──────────┐   ┌──────────┐            │
//!    │  │  Genome   │──▶│ Analyzer │──▶│ Mutation │            │
//!    │  │ (Code DNA)│   │ (Eyes)   │   │(Operator)│            │
//!    │  └──────────┘   └──────────┘   └────┬─────┘            │
//!    │                                      │                   │
//!    │  ┌──────────┐   ┌──────────┐   ┌────▼─────┐            │
//!    │  │  Memory   │◀──│ Strategy │◀──│ Fitness  │            │
//!    │  │ (Learn)   │   │ (Search) │   │ (Verify) │            │
//!    │  └──────────┘   └──────────┘   └──────────┘            │
//!    │        │                                                 │
//!    │  ┌─────▼────┐                                           │
//!    │  │ Journal   │  ← every attempt recorded                │
//!    │  └──────────┘                                           │
//!    └──────────────────────────────────────────────────────────┘
//!              ▲                              │
//!              │     NeuralBus signals        │
//!              └──────────────────────────────┘
//!                    (CORTEX integration)
//! ```
//!
//! ## The Evolution Loop
//!
//! 1. **Scan** — Build genome from source files
//! 2. **Analyze** — Find improvement opportunities
//! 3. **Hypothesize** — Generate mutation candidates
//! 4. **Mutate** — Apply transformation to code
//! 5. **Test** — Run fitness evaluation (build, test, bench)
//! 6. **Evaluate** — Score the result (multi-objective)
//! 7. **Select** — Keep improvement or revert
//! 8. **Learn** — Update memory with outcome
//!
//! ## Key Principle: Vision-Aware
//!
//! Code that appears "dead" may be FUTURE VISION. The evolution engine
//! NEVER deletes unconnected code — it only improves what exists.

pub mod analyzer;
pub mod evolution;
pub mod fitness;
pub mod genome;
pub mod journal;
pub mod memory;
pub mod mutation;
pub mod strategy;

/// Prelude — import everything you need
pub mod prelude {
    pub use crate::analyzer::{
        AnalysisFinding, AnalysisKind, CodeAnalyzer, FindingSeverity,
    };
    pub use crate::evolution::{EvolutionConfig, EvolutionEngine, EvolutionOutcome};
    pub use crate::fitness::{FitnessEvaluator, FitnessReport, FitnessScore, Objective};
    pub use crate::genome::{CodeGenome, FileGenome, FunctionSignature, GenomeStats};
    pub use crate::journal::{EvolutionEntry, EvolutionJournal, EntryOutcome};
    pub use crate::memory::{EvolutionMemory, MemoryEntry, MemoryKind};
    pub use crate::mutation::{Mutation, MutationKind, MutationOperator, MutationResult};
    pub use crate::strategy::{EvolutionStrategy, StrategyKind};
}

/// Errors for the evolution engine.
#[derive(Debug, thiserror::Error)]
pub enum EvolutionError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Parse error in {file}: {message}")]
    Parse { file: String, message: String },

    #[error("Fitness evaluation failed: {0}")]
    FitnessFailure(String),

    #[error("Mutation failed: {0}")]
    MutationFailure(String),

    #[error("Memory error: {0}")]
    Memory(String),

    #[error("Strategy error: {0}")]
    Strategy(String),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, EvolutionError>;

#[cfg(test)]
mod integration_tests {
    use crate::prelude::*;
    use tempfile::TempDir;

    #[test]
    fn full_evolution_pipeline() {
        // Create a temp project with a simple Rust file
        let dir = TempDir::new().unwrap();
        let src_dir = dir.path().join("src");
        std::fs::create_dir_all(&src_dir).unwrap();

        // Write a file with known improvement opportunities
        std::fs::write(
            src_dir.join("example.rs"),
            r#"
pub fn add(a: i32, b: i32) -> i32 {
    let result = a + b;
    return result;
}

pub fn multiply(x: f64, y: f64) -> f64 {
    let product = x * y;
    return product;
}

#[allow(dead_code)]
fn unused_helper() -> String {
    let s = String::new();
    return s;
}
"#,
        )
        .unwrap();

        // 1. Build genome
        let genome = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();
        assert!(genome.files().len() >= 1);
        assert!(genome.stats().total_functions >= 3);

        // 2. Analyze
        let analyzer = CodeAnalyzer::new();
        let findings = analyzer.analyze(&genome);
        // Should find "explicit return" anti-pattern
        assert!(!findings.is_empty(), "Expected findings, got none");
        let has_return_finding = findings.iter().any(|f| {
            matches!(f.kind, AnalysisKind::ExplicitReturn)
        });
        assert!(has_return_finding, "Expected explicit return finding");

        // 3. Generate mutations
        let mut operator = MutationOperator::new();
        let mutations = operator.from_findings(&findings);
        assert!(!mutations.is_empty());

        // 4. Memory persists
        let memory_path = dir.path().join("evolution_memory.json");
        let mut memory = EvolutionMemory::new(&memory_path);
        memory.record(MemoryEntry::success(
            "explicit_return_removal",
            "example.rs",
            0.15,
        ));
        memory.save().unwrap();

        let loaded = EvolutionMemory::load(&memory_path).unwrap();
        assert_eq!(loaded.entries().len(), 1);
        assert!(loaded.entries()[0].fitness_delta > 0.0);
    }

    #[test]
    fn genome_fingerprinting_stability() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("lib.rs"), "pub fn hello() -> &'static str { \"world\" }").unwrap();

        let g1 = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();
        let g2 = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();

        // Same source → same fingerprint
        assert_eq!(g1.fingerprint(), g2.fingerprint());

        // Mutate the file
        std::fs::write(src.join("lib.rs"), "pub fn hello() -> &'static str { \"changed\" }").unwrap();
        let g3 = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();

        // Different source → different fingerprint
        assert_ne!(g1.fingerprint(), g3.fingerprint());
    }

    #[test]
    fn journal_records_evolution_history() {
        let dir = TempDir::new().unwrap();
        let journal_path = dir.path().join("evolution_journal.json");
        let mut journal = EvolutionJournal::new(&journal_path);

        journal.record(EvolutionEntry::new(
            "remove_explicit_return",
            "src/example.rs:3",
            EntryOutcome::Applied { fitness_delta: 0.05 },
        ));
        journal.record(EvolutionEntry::new(
            "optimize_loop",
            "src/engine.rs:42",
            EntryOutcome::Reverted { reason: "test failure".into() },
        ));

        journal.save().unwrap();
        let loaded = EvolutionJournal::load(&journal_path).unwrap();
        assert_eq!(loaded.entries().len(), 2);
        assert!(loaded.success_rate() > 0.0);
    }
}
