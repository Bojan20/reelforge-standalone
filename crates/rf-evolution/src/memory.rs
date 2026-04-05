//! Evolution Memory — persistent learning from past mutations.
//!
//! Remembers:
//! - Successful mutations (what worked, where, how much it improved)
//! - Failed mutations (what didn't work, why)
//! - Patterns (recurring improvement opportunities)
//!
//! This is how CORTEX LEARNS across sessions. Without memory,
//! each evolution cycle starts from zero. With memory, the organism
//! accumulates wisdom — like antibodies in the immune system, but
//! for code quality.

use crate::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

// ============================================================================
// Memory Types
// ============================================================================

/// Persistent evolution memory.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionMemory {
    /// All recorded memories.
    entries: Vec<MemoryEntry>,
    /// Index by mutation kind for fast lookup.
    #[serde(skip)]
    kind_index: HashMap<String, Vec<usize>>,
    /// Index by file for fast lookup.
    #[serde(skip)]
    file_index: HashMap<String, Vec<usize>>,
    /// File path for persistence.
    #[serde(skip)]
    path: PathBuf,
}

/// A single memory entry — one mutation attempt remembered.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryEntry {
    /// What kind of mutation was attempted.
    pub mutation_kind: String,
    /// Which file was targeted.
    pub target_file: String,
    /// Whether it succeeded.
    pub succeeded: bool,
    /// Fitness delta (positive = improvement).
    pub fitness_delta: f64,
    /// Why it failed (if applicable).
    pub failure_reason: Option<String>,
    /// How many times this kind of mutation has been tried.
    pub attempt_count: u32,
    /// When this memory was created.
    pub created_at: chrono::DateTime<chrono::Utc>,
    /// When this memory was last updated.
    pub updated_at: chrono::DateTime<chrono::Utc>,
    /// Confidence in this memory (decays over time, reinforced by repetition).
    pub confidence: f64,
    /// Classification.
    pub kind: MemoryKind,
}

/// Kind of memory entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum MemoryKind {
    /// This mutation worked — do more of this.
    Success,
    /// This mutation failed — avoid repeating.
    Failure,
    /// Observation about code patterns.
    Pattern,
    /// Learned rule from multiple observations.
    Rule,
}

// ============================================================================
// Implementation
// ============================================================================

impl EvolutionMemory {
    /// Create a new empty memory.
    pub fn new(path: &Path) -> Self {
        Self {
            entries: Vec::new(),
            kind_index: HashMap::new(),
            file_index: HashMap::new(),
            path: path.to_path_buf(),
        }
    }

    /// Load memory from disk.
    pub fn load(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let mut memory: Self = serde_json::from_str(&content)?;
        memory.path = path.to_path_buf();
        memory.rebuild_indices();
        Ok(memory)
    }

    /// Load from disk or create new if file doesn't exist.
    pub fn load_or_create(path: &Path) -> Self {
        Self::load(path).unwrap_or_else(|_| Self::new(path))
    }

    /// Save memory to disk.
    pub fn save(&self) -> Result<()> {
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(&self.path, content)?;
        Ok(())
    }

    /// Record a new memory entry.
    pub fn record(&mut self, entry: MemoryEntry) {
        // Check if we already have a similar entry — update instead of duplicate
        if let Some(existing) = self.find_similar_mut(&entry.mutation_kind, &entry.target_file) {
            existing.attempt_count += 1;
            existing.updated_at = chrono::Utc::now();
            // Update confidence: reinforce on match, weaken on conflict
            if entry.succeeded == existing.succeeded {
                existing.confidence = (existing.confidence + 0.1).min(1.0);
            } else {
                existing.confidence = (existing.confidence - 0.2).max(0.0);
                // If the latest attempt disagrees, update the outcome
                existing.succeeded = entry.succeeded;
                existing.fitness_delta = entry.fitness_delta;
                existing.failure_reason = entry.failure_reason;
            }
            return;
        }

        let idx = self.entries.len();
        self.kind_index
            .entry(entry.mutation_kind.clone())
            .or_default()
            .push(idx);
        self.file_index
            .entry(entry.target_file.clone())
            .or_default()
            .push(idx);
        self.entries.push(entry);
    }

    /// Get all entries.
    pub fn entries(&self) -> &[MemoryEntry] {
        &self.entries
    }

    /// Get entries for a specific mutation kind.
    pub fn by_kind(&self, kind: &str) -> Vec<&MemoryEntry> {
        self.kind_index
            .get(kind)
            .map(|indices| indices.iter().filter_map(|&i| self.entries.get(i)).collect())
            .unwrap_or_default()
    }

    /// Get entries for a specific file.
    pub fn by_file(&self, file: &str) -> Vec<&MemoryEntry> {
        self.file_index
            .get(file)
            .map(|indices| indices.iter().filter_map(|&i| self.entries.get(i)).collect())
            .unwrap_or_default()
    }

    /// Should we attempt this mutation? Check memory for past failures.
    pub fn should_attempt(&self, mutation_kind: &str, target_file: &str) -> (bool, f64) {
        // Check for past failures on same file with same mutation
        if let Some(entry) = self.find_similar(mutation_kind, target_file) {
            if !entry.succeeded && entry.confidence > 0.5 && entry.attempt_count >= 2 {
                return (false, entry.confidence);
            }
            if entry.succeeded {
                return (true, entry.confidence);
            }
        }

        // No memory → go ahead
        (true, 0.0)
    }

    /// Get the success rate for a mutation kind across all files.
    pub fn success_rate(&self, mutation_kind: &str) -> f64 {
        let entries = self.by_kind(mutation_kind);
        if entries.is_empty() {
            return 0.5; // Unknown — neutral
        }

        let successes = entries.iter().filter(|e| e.succeeded).count();
        successes as f64 / entries.len() as f64
    }

    /// Get the top N most impactful successful mutations.
    pub fn top_improvements(&self, n: usize) -> Vec<&MemoryEntry> {
        let mut successes: Vec<_> = self
            .entries
            .iter()
            .filter(|e| e.succeeded && e.fitness_delta > 0.0)
            .collect();
        successes.sort_by(|a, b| {
            b.fitness_delta
                .partial_cmp(&a.fitness_delta)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        successes.truncate(n);
        successes
    }

    /// Decay old memories — reduce confidence of old, unreinforced entries.
    pub fn decay(&mut self, decay_rate: f64) {
        let now = chrono::Utc::now();
        for entry in &mut self.entries {
            let age_days = (now - entry.updated_at).num_days() as f64;
            if age_days > 7.0 {
                entry.confidence *= 1.0 - (decay_rate * (age_days / 30.0).min(1.0));
                entry.confidence = entry.confidence.max(0.0);
            }
        }

        // Prune entries with near-zero confidence
        self.entries.retain(|e| e.confidence > 0.01);
        self.rebuild_indices();
    }

    /// Get total number of entries.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Is memory empty?
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Summary statistics.
    pub fn summary(&self) -> MemorySummary {
        let total = self.entries.len();
        let successes = self.entries.iter().filter(|e| e.succeeded).count();
        let failures = total - successes;
        let avg_improvement = if successes > 0 {
            self.entries
                .iter()
                .filter(|e| e.succeeded)
                .map(|e| e.fitness_delta)
                .sum::<f64>()
                / successes as f64
        } else {
            0.0
        };

        let mut kind_counts: HashMap<String, usize> = HashMap::new();
        for entry in &self.entries {
            *kind_counts.entry(entry.mutation_kind.clone()).or_default() += 1;
        }

        MemorySummary {
            total_entries: total,
            successes,
            failures,
            avg_improvement,
            mutation_kinds: kind_counts,
        }
    }

    // ========================================================================
    // Internal helpers
    // ========================================================================

    fn find_similar(&self, mutation_kind: &str, target_file: &str) -> Option<&MemoryEntry> {
        self.entries
            .iter()
            .find(|e| e.mutation_kind == mutation_kind && e.target_file == target_file)
    }

    fn find_similar_mut(&mut self, mutation_kind: &str, target_file: &str) -> Option<&mut MemoryEntry> {
        self.entries
            .iter_mut()
            .find(|e| e.mutation_kind == mutation_kind && e.target_file == target_file)
    }

    fn rebuild_indices(&mut self) {
        self.kind_index.clear();
        self.file_index.clear();
        for (idx, entry) in self.entries.iter().enumerate() {
            self.kind_index
                .entry(entry.mutation_kind.clone())
                .or_default()
                .push(idx);
            self.file_index
                .entry(entry.target_file.clone())
                .or_default()
                .push(idx);
        }
    }
}

/// Helper constructors for MemoryEntry.
impl MemoryEntry {
    pub fn success(mutation_kind: &str, target_file: &str, fitness_delta: f64) -> Self {
        let now = chrono::Utc::now();
        Self {
            mutation_kind: mutation_kind.to_string(),
            target_file: target_file.to_string(),
            succeeded: true,
            fitness_delta,
            failure_reason: None,
            attempt_count: 1,
            created_at: now,
            updated_at: now,
            confidence: 0.8,
            kind: MemoryKind::Success,
        }
    }

    pub fn failure(mutation_kind: &str, target_file: &str, reason: &str) -> Self {
        let now = chrono::Utc::now();
        Self {
            mutation_kind: mutation_kind.to_string(),
            target_file: target_file.to_string(),
            succeeded: false,
            fitness_delta: 0.0,
            failure_reason: Some(reason.to_string()),
            attempt_count: 1,
            created_at: now,
            updated_at: now,
            confidence: 0.7,
            kind: MemoryKind::Failure,
        }
    }

    pub fn pattern(mutation_kind: &str, _description: &str) -> Self {
        let now = chrono::Utc::now();
        Self {
            mutation_kind: mutation_kind.to_string(),
            target_file: String::new(),
            succeeded: true,
            fitness_delta: 0.0,
            failure_reason: None,
            attempt_count: 0,
            created_at: now,
            updated_at: now,
            confidence: 0.5,
            kind: MemoryKind::Pattern,
        }
    }
}

/// Summary of evolution memory state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySummary {
    pub total_entries: usize,
    pub successes: usize,
    pub failures: usize,
    pub avg_improvement: f64,
    pub mutation_kinds: HashMap<String, usize>,
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn create_and_save_memory() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("memory.json");

        let mut memory = EvolutionMemory::new(&path);
        memory.record(MemoryEntry::success("explicit_return", "src/a.rs", 0.05));
        memory.record(MemoryEntry::failure("clone_removal", "src/b.rs", "broke API"));
        memory.save().unwrap();

        let loaded = EvolutionMemory::load(&path).unwrap();
        assert_eq!(loaded.entries().len(), 2);
    }

    #[test]
    fn should_attempt_avoids_known_failures() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("memory.json");
        let mut memory = EvolutionMemory::new(&path);

        // Record two failures → should learn to avoid
        memory.record(MemoryEntry::failure("clone_removal", "src/b.rs", "broke API"));
        memory.record(MemoryEntry::failure("clone_removal", "src/b.rs", "still broken"));

        let (should, confidence) = memory.should_attempt("clone_removal", "src/b.rs");
        assert!(!should);
        assert!(confidence > 0.5);

        // Unknown mutation → should try
        let (should, _) = memory.should_attempt("new_thing", "src/c.rs");
        assert!(should);
    }

    #[test]
    fn success_rate_tracking() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("memory.json");
        let mut memory = EvolutionMemory::new(&path);

        memory.record(MemoryEntry::success("explicit_return", "a.rs", 0.05));
        memory.record(MemoryEntry::success("explicit_return", "b.rs", 0.03));
        memory.record(MemoryEntry::failure("explicit_return", "c.rs", "syntax error"));

        let rate = memory.success_rate("explicit_return");
        assert!((rate - 0.666).abs() < 0.01);
    }

    #[test]
    fn top_improvements_ranked() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("memory.json");
        let mut memory = EvolutionMemory::new(&path);

        memory.record(MemoryEntry::success("a", "f1.rs", 0.05));
        memory.record(MemoryEntry::success("b", "f2.rs", 0.20));
        memory.record(MemoryEntry::success("c", "f3.rs", 0.10));

        let top = memory.top_improvements(2);
        assert_eq!(top.len(), 2);
        assert!(top[0].fitness_delta >= top[1].fitness_delta);
    }

    #[test]
    fn deduplication_on_record() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("memory.json");
        let mut memory = EvolutionMemory::new(&path);

        memory.record(MemoryEntry::success("explicit_return", "a.rs", 0.05));
        memory.record(MemoryEntry::success("explicit_return", "a.rs", 0.06));

        // Should have merged into one entry with attempt_count=2
        assert_eq!(memory.entries().len(), 1);
        assert_eq!(memory.entries()[0].attempt_count, 2);
    }

    #[test]
    fn summary_statistics() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("memory.json");
        let mut memory = EvolutionMemory::new(&path);

        memory.record(MemoryEntry::success("a", "f1.rs", 0.10));
        memory.record(MemoryEntry::failure("b", "f2.rs", "oops"));

        let summary = memory.summary();
        assert_eq!(summary.total_entries, 2);
        assert_eq!(summary.successes, 1);
        assert_eq!(summary.failures, 1);
        assert!((summary.avg_improvement - 0.10).abs() < 0.001);
    }

    #[test]
    fn load_or_create_handles_missing_file() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("nonexistent.json");
        let memory = EvolutionMemory::load_or_create(&path);
        assert!(memory.is_empty());
    }
}
