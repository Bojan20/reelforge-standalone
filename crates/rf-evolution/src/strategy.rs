//! Evolution Strategies — how to search the solution space.
//!
//! Different strategies for choosing which mutations to attempt:
//! - HillClimb: always pick the highest-expected-improvement mutation
//! - Exploration: try random mutations to discover new patterns
//! - Directed: use memory to focus on what worked before
//! - Adaptive: switch strategies based on recent success rate

use crate::memory::EvolutionMemory;
use crate::mutation::Mutation;
use rand::Rng;
use serde::{Deserialize, Serialize};

// ============================================================================
// Strategy Types
// ============================================================================

/// Evolution strategy — decides which mutations to attempt.
pub struct EvolutionStrategy {
    /// Current strategy kind.
    pub kind: StrategyKind,
    /// How many mutations to select per cycle.
    pub batch_size: usize,
    /// Exploration rate (0.0-1.0) — chance of random selection.
    pub exploration_rate: f64,
    /// Minimum confidence to attempt a mutation.
    pub min_confidence: f64,
}

/// Strategy variants.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StrategyKind {
    /// Always pick the best expected improvement. Fast convergence,
    /// but may miss novel improvements.
    HillClimb,

    /// Random selection with bias toward high-expected mutations.
    /// Discovers new patterns but slower convergence.
    Exploration,

    /// Use memory to focus on mutation kinds that worked before.
    /// Efficient but can get stuck in local optima.
    Directed,

    /// Automatically switch between strategies based on recent results.
    /// Best for long-running evolution — explores when stuck, exploits when improving.
    Adaptive,
}

// ============================================================================
// Implementation
// ============================================================================

impl EvolutionStrategy {
    /// Create a new strategy.
    pub fn new(kind: StrategyKind) -> Self {
        Self {
            kind,
            batch_size: 5,
            exploration_rate: 0.2,
            min_confidence: 0.3,
        }
    }

    /// Select which mutations to attempt from candidates.
    pub fn select(
        &self,
        candidates: &[Mutation],
        memory: &EvolutionMemory,
    ) -> Vec<Mutation> {
        if candidates.is_empty() {
            return Vec::new();
        }

        match self.kind {
            StrategyKind::HillClimb => self.hill_climb_select(candidates, memory),
            StrategyKind::Exploration => self.exploration_select(candidates, memory),
            StrategyKind::Directed => self.directed_select(candidates, memory),
            StrategyKind::Adaptive => self.adaptive_select(candidates, memory),
        }
    }

    /// Hill climbing: pick top N by expected improvement, filtered by memory.
    fn hill_climb_select(
        &self,
        candidates: &[Mutation],
        memory: &EvolutionMemory,
    ) -> Vec<Mutation> {
        let mut filtered: Vec<_> = candidates
            .iter()
            .filter(|m| {
                let (should, _) = memory.should_attempt(
                    &format!("{:?}", m.kind),
                    &m.file.display().to_string(),
                );
                should && m.confidence >= self.min_confidence
            })
            .cloned()
            .collect();

        // Sort by expected improvement (descending)
        filtered.sort_by(|a, b| {
            b.expected_improvement
                .partial_cmp(&a.expected_improvement)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        filtered.truncate(self.batch_size);
        filtered
    }

    /// Exploration: weighted random selection.
    fn exploration_select(
        &self,
        candidates: &[Mutation],
        memory: &EvolutionMemory,
    ) -> Vec<Mutation> {
        let mut rng = rand::rng();
        let mut filtered: Vec<_> = candidates
            .iter()
            .filter(|m| {
                let (should, _) = memory.should_attempt(
                    &format!("{:?}", m.kind),
                    &m.file.display().to_string(),
                );
                should
            })
            .cloned()
            .collect();

        if filtered.is_empty() {
            return Vec::new();
        }

        let mut selected = Vec::new();
        for _ in 0..self.batch_size.min(filtered.len()) {
            if rng.random::<f64>() < self.exploration_rate {
                // Random pick
                let idx = rng.random_range(0..filtered.len());
                selected.push(filtered.remove(idx));
            } else {
                // Best pick
                filtered.sort_by(|a, b| {
                    b.expected_improvement
                        .partial_cmp(&a.expected_improvement)
                        .unwrap_or(std::cmp::Ordering::Equal)
                });
                selected.push(filtered.remove(0));
            }

            if filtered.is_empty() {
                break;
            }
        }

        selected
    }

    /// Directed: use memory success rates to boost selection.
    fn directed_select(
        &self,
        candidates: &[Mutation],
        memory: &EvolutionMemory,
    ) -> Vec<Mutation> {
        let mut scored: Vec<_> = candidates
            .iter()
            .filter_map(|m| {
                let kind_str = format!("{:?}", m.kind);
                let (should, _) = memory.should_attempt(&kind_str, &m.file.display().to_string());
                if !should {
                    return None;
                }

                let memory_boost = memory.success_rate(&kind_str);
                let combined_score = m.expected_improvement * (0.5 + memory_boost * 0.5);
                Some((m.clone(), combined_score))
            })
            .collect();

        scored.sort_by(|a, b| {
            b.1.partial_cmp(&a.1)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        scored
            .into_iter()
            .take(self.batch_size)
            .map(|(m, _)| m)
            .collect()
    }

    /// Adaptive: switch between strategies based on recent performance.
    fn adaptive_select(
        &self,
        candidates: &[Mutation],
        memory: &EvolutionMemory,
    ) -> Vec<Mutation> {
        let summary = memory.summary();

        if summary.total_entries < 10 {
            // Not enough data — explore
            self.exploration_select(candidates, memory)
        } else if summary.successes as f64 / summary.total_entries as f64 > 0.5 {
            // Good success rate — exploit with directed
            self.directed_select(candidates, memory)
        } else {
            // Low success rate — explore more
            let mut strategy = self.exploration_select(candidates, memory);
            // But also keep the best hill-climb option
            let hill = self.hill_climb_select(candidates, memory);
            if let Some(best) = hill.first() {
                if !strategy.iter().any(|m| m.id == best.id) {
                    strategy.push(best.clone());
                }
            }
            strategy
        }
    }
}

impl Default for EvolutionStrategy {
    fn default() -> Self {
        Self::new(StrategyKind::Adaptive)
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analyzer::AnalysisKind;
    use crate::mutation::{MutationKind, Transform};
    use std::path::PathBuf;
    use tempfile::TempDir;

    fn make_mutations(n: usize) -> Vec<Mutation> {
        (0..n)
            .map(|i| Mutation {
                id: format!("mut_{}", i),
                kind: MutationKind::RemoveExplicitReturn,
                file: PathBuf::from(format!("src/file_{}.rs", i)),
                line: i * 10,
                function: Some(format!("fn_{}", i)),
                description: format!("Mutation {}", i),
                source_finding: AnalysisKind::ExplicitReturn,
                expected_improvement: (i as f64 + 1.0) * 0.01,
                confidence: 0.8,
                transform: Transform::Manual {
                    suggestion: String::new(),
                },
            })
            .collect()
    }

    #[test]
    fn hill_climb_selects_best() {
        let dir = TempDir::new().unwrap();
        let memory = EvolutionMemory::new(&dir.path().join("m.json"));
        let mutations = make_mutations(10);

        let strategy = EvolutionStrategy {
            kind: StrategyKind::HillClimb,
            batch_size: 3,
            exploration_rate: 0.0,
            min_confidence: 0.0,
        };

        let selected = strategy.select(&mutations, &memory);
        assert_eq!(selected.len(), 3);
        // Should be top 3 by expected improvement (highest first)
        assert!(selected[0].expected_improvement >= selected[1].expected_improvement);
        assert!(selected[1].expected_improvement >= selected[2].expected_improvement);
    }

    #[test]
    fn exploration_selects_varied() {
        let dir = TempDir::new().unwrap();
        let memory = EvolutionMemory::new(&dir.path().join("m.json"));
        let mutations = make_mutations(20);

        let strategy = EvolutionStrategy {
            kind: StrategyKind::Exploration,
            batch_size: 5,
            exploration_rate: 1.0, // Always random
            min_confidence: 0.0,
        };

        let selected = strategy.select(&mutations, &memory);
        assert!(!selected.is_empty());
        assert!(selected.len() <= 5);
    }

    #[test]
    fn directed_uses_memory() {
        let dir = TempDir::new().unwrap();
        let mut memory = EvolutionMemory::new(&dir.path().join("m.json"));

        // Record success for RemoveExplicitReturn
        memory.record(crate::memory::MemoryEntry::success(
            "RemoveExplicitReturn",
            "src/file_0.rs",
            0.1,
        ));

        let mutations = make_mutations(5);
        let strategy = EvolutionStrategy::new(StrategyKind::Directed);
        let selected = strategy.select(&mutations, &memory);
        assert!(!selected.is_empty());
    }

    #[test]
    fn memory_blocks_known_failures() {
        let dir = TempDir::new().unwrap();
        let mut memory = EvolutionMemory::new(&dir.path().join("m.json"));

        // Record repeated failure for file_0
        memory.record(crate::memory::MemoryEntry::failure(
            "RemoveExplicitReturn",
            "src/file_0.rs",
            "broke",
        ));
        memory.record(crate::memory::MemoryEntry::failure(
            "RemoveExplicitReturn",
            "src/file_0.rs",
            "still broke",
        ));

        let mutations = make_mutations(3);
        let strategy = EvolutionStrategy::new(StrategyKind::HillClimb);
        let selected = strategy.select(&mutations, &memory);

        // file_0 should be skipped (index 0 in make_mutations)
        assert!(!selected.iter().any(|m| m.file.display().to_string().contains("file_0")));
    }

    #[test]
    fn empty_candidates_returns_empty() {
        let dir = TempDir::new().unwrap();
        let memory = EvolutionMemory::new(&dir.path().join("m.json"));

        let strategy = EvolutionStrategy::default();
        let selected = strategy.select(&[], &memory);
        assert!(selected.is_empty());
    }

    #[test]
    fn adaptive_explores_with_few_memories() {
        let dir = TempDir::new().unwrap();
        let memory = EvolutionMemory::new(&dir.path().join("m.json"));
        let mutations = make_mutations(10);

        let strategy = EvolutionStrategy::new(StrategyKind::Adaptive);
        let selected = strategy.select(&mutations, &memory);
        // With empty memory, adaptive should explore
        assert!(!selected.is_empty());
    }
}
