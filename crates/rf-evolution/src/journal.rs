//! Evolution Journal — immutable audit trail of all evolution attempts.
//!
//! Unlike Memory (which learns and forgets), the Journal is a permanent
//! record of every mutation attempt: what was tried, what happened, and
//! whether it was kept or reverted.
//!
//! This is CORTEX's autobiography — the story of how it evolved.

use crate::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

// ============================================================================
// Journal Types
// ============================================================================

/// The evolution journal — append-only log of all evolution attempts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionJournal {
    /// All journal entries, ordered chronologically.
    entries: Vec<EvolutionEntry>,
    /// File path for persistence.
    #[serde(skip)]
    path: PathBuf,
}

/// A single evolution attempt record.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionEntry {
    /// Mutation that was attempted.
    pub mutation_name: String,
    /// Where in the code.
    pub target: String,
    /// What happened.
    pub outcome: EntryOutcome,
    /// When this happened.
    pub timestamp: chrono::DateTime<chrono::Utc>,
    /// Generation number (how many evolution cycles have occurred).
    pub generation: u64,
}

/// Outcome of an evolution attempt.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EntryOutcome {
    /// Mutation was applied and kept.
    Applied {
        /// How much fitness improved.
        fitness_delta: f64,
    },
    /// Mutation was applied but reverted.
    Reverted {
        /// Why it was reverted.
        reason: String,
    },
    /// Mutation was skipped (memory said don't bother).
    Skipped {
        /// Why it was skipped.
        reason: String,
    },
    /// Mutation failed to apply (syntax error, etc).
    Failed {
        /// Error message.
        error: String,
    },
}

// ============================================================================
// Implementation
// ============================================================================

impl EvolutionJournal {
    /// Create a new empty journal.
    pub fn new(path: &Path) -> Self {
        Self {
            entries: Vec::new(),
            path: path.to_path_buf(),
        }
    }

    /// Load journal from disk.
    pub fn load(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let mut journal: Self = serde_json::from_str(&content)?;
        journal.path = path.to_path_buf();
        Ok(journal)
    }

    /// Load or create.
    pub fn load_or_create(path: &Path) -> Self {
        Self::load(path).unwrap_or_else(|_| Self::new(path))
    }

    /// Save journal to disk.
    pub fn save(&self) -> Result<()> {
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(&self.path, content)?;
        Ok(())
    }

    /// Record a new entry.
    pub fn record(&mut self, entry: EvolutionEntry) {
        self.entries.push(entry);
    }

    /// Get all entries.
    pub fn entries(&self) -> &[EvolutionEntry] {
        &self.entries
    }

    /// Current generation (number of entries).
    pub fn generation(&self) -> u64 {
        self.entries.len() as u64
    }

    /// Success rate (applied / total).
    pub fn success_rate(&self) -> f64 {
        if self.entries.is_empty() {
            return 0.0;
        }

        let applied = self
            .entries
            .iter()
            .filter(|e| matches!(e.outcome, EntryOutcome::Applied { .. }))
            .count();

        applied as f64 / self.entries.len() as f64
    }

    /// Total fitness improvement across all applied mutations.
    pub fn total_improvement(&self) -> f64 {
        self.entries
            .iter()
            .filter_map(|e| match &e.outcome {
                EntryOutcome::Applied { fitness_delta } => Some(*fitness_delta),
                _ => None,
            })
            .sum()
    }

    /// Get the last N entries.
    pub fn recent(&self, n: usize) -> &[EvolutionEntry] {
        let start = self.entries.len().saturating_sub(n);
        &self.entries[start..]
    }

    /// Get entries by outcome type.
    pub fn applied_entries(&self) -> Vec<&EvolutionEntry> {
        self.entries
            .iter()
            .filter(|e| matches!(e.outcome, EntryOutcome::Applied { .. }))
            .collect()
    }

    pub fn reverted_entries(&self) -> Vec<&EvolutionEntry> {
        self.entries
            .iter()
            .filter(|e| matches!(e.outcome, EntryOutcome::Reverted { .. }))
            .collect()
    }

    pub fn failed_entries(&self) -> Vec<&EvolutionEntry> {
        self.entries
            .iter()
            .filter(|e| matches!(e.outcome, EntryOutcome::Failed { .. }))
            .collect()
    }

    /// Get a human-readable summary of the journal.
    pub fn summary(&self) -> JournalSummary {
        let total = self.entries.len();
        let applied = self.applied_entries().len();
        let reverted = self.reverted_entries().len();
        let failed = self.failed_entries().len();
        let skipped = total - applied - reverted - failed;

        JournalSummary {
            total_attempts: total,
            applied,
            reverted,
            failed,
            skipped,
            success_rate: self.success_rate(),
            total_improvement: self.total_improvement(),
            generation: self.generation(),
        }
    }
}

impl EvolutionEntry {
    /// Create a new entry (timestamp auto-set to now).
    pub fn new(mutation_name: &str, target: &str, outcome: EntryOutcome) -> Self {
        Self {
            mutation_name: mutation_name.to_string(),
            target: target.to_string(),
            outcome,
            timestamp: chrono::Utc::now(),
            generation: 0, // Set by journal
        }
    }
}

/// Summary of journal state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JournalSummary {
    pub total_attempts: usize,
    pub applied: usize,
    pub reverted: usize,
    pub failed: usize,
    pub skipped: usize,
    pub success_rate: f64,
    pub total_improvement: f64,
    pub generation: u64,
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn journal_persistence() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("journal.json");

        let mut journal = EvolutionJournal::new(&path);
        journal.record(EvolutionEntry::new(
            "remove_return",
            "src/a.rs:10",
            EntryOutcome::Applied { fitness_delta: 0.05 },
        ));
        journal.record(EvolutionEntry::new(
            "extract_fn",
            "src/b.rs:42",
            EntryOutcome::Reverted {
                reason: "test regression".into(),
            },
        ));
        journal.save().unwrap();

        let loaded = EvolutionJournal::load(&path).unwrap();
        assert_eq!(loaded.entries().len(), 2);
        assert_eq!(loaded.generation(), 2);
    }

    #[test]
    fn success_rate_calculation() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("journal.json");
        let mut journal = EvolutionJournal::new(&path);

        journal.record(EvolutionEntry::new("a", "x", EntryOutcome::Applied { fitness_delta: 0.1 }));
        journal.record(EvolutionEntry::new("b", "y", EntryOutcome::Applied { fitness_delta: 0.05 }));
        journal.record(EvolutionEntry::new("c", "z", EntryOutcome::Reverted { reason: "bad".into() }));
        journal.record(EvolutionEntry::new("d", "w", EntryOutcome::Failed { error: "oops".into() }));

        assert!((journal.success_rate() - 0.5).abs() < 0.001);
        assert!((journal.total_improvement() - 0.15).abs() < 0.001);
    }

    #[test]
    fn summary_counts() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("journal.json");
        let mut journal = EvolutionJournal::new(&path);

        journal.record(EvolutionEntry::new("a", "x", EntryOutcome::Applied { fitness_delta: 0.1 }));
        journal.record(EvolutionEntry::new("b", "y", EntryOutcome::Reverted { reason: "x".into() }));
        journal.record(EvolutionEntry::new("c", "z", EntryOutcome::Skipped { reason: "y".into() }));
        journal.record(EvolutionEntry::new("d", "w", EntryOutcome::Failed { error: "z".into() }));

        let summary = journal.summary();
        assert_eq!(summary.total_attempts, 4);
        assert_eq!(summary.applied, 1);
        assert_eq!(summary.reverted, 1);
        assert_eq!(summary.skipped, 1);
        assert_eq!(summary.failed, 1);
    }

    #[test]
    fn recent_entries() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("journal.json");
        let mut journal = EvolutionJournal::new(&path);

        for i in 0..10 {
            journal.record(EvolutionEntry::new(
                &format!("mut_{}", i),
                "x",
                EntryOutcome::Applied { fitness_delta: 0.01 },
            ));
        }

        let recent = journal.recent(3);
        assert_eq!(recent.len(), 3);
        assert_eq!(recent[0].mutation_name, "mut_7");
    }
}
