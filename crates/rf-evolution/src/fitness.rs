//! Fitness Evaluation — multi-objective scoring of code quality.
//!
//! Evaluates code across multiple dimensions:
//! - Compilation: does it build without errors?
//! - Tests: do they pass? How many?
//! - Clippy: how many warnings?
//! - Complexity: average cyclomatic complexity
//! - Safety: unsafe blocks, unwrap usage
//! - Coverage: lines/functions covered by tests
//!
//! Each dimension produces a score 0.0-1.0, weighted and combined
//! into a single fitness value for comparison.

use crate::genome::{CodeGenome, GenomeStats};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::process::Command;

// ============================================================================
// Fitness Types
// ============================================================================

/// Complete fitness report for a codebase state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FitnessReport {
    /// Individual objective scores.
    pub objectives: HashMap<Objective, FitnessScore>,
    /// Weighted overall fitness (0.0-1.0).
    pub overall: f64,
    /// Genome fingerprint this report corresponds to.
    pub genome_fingerprint: String,
    /// Timestamp.
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

/// Individual fitness dimension score.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FitnessScore {
    /// Raw value (dimension-specific).
    pub raw: f64,
    /// Normalized score (0.0-1.0, higher = better).
    pub normalized: f64,
    /// Weight in overall calculation.
    pub weight: f64,
    /// Human-readable detail.
    pub detail: String,
}

/// Fitness objectives (dimensions to optimize).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Objective {
    /// Code compiles successfully.
    Compilation,
    /// Tests pass.
    TestSuccess,
    /// Number of clippy warnings.
    ClippyWarnings,
    /// Average cyclomatic complexity.
    Complexity,
    /// Safety score (unwrap, unsafe usage).
    Safety,
    /// Code conciseness (LOC efficiency).
    Conciseness,
    /// Function count and modularity.
    Modularity,
}

// ============================================================================
// Fitness Evaluator
// ============================================================================

/// Evaluates fitness of a codebase.
pub struct FitnessEvaluator {
    /// Working directory for running commands.
    pub project_root: std::path::PathBuf,
    /// Weights for each objective.
    pub weights: HashMap<Objective, f64>,
    /// Whether to actually run cargo commands (false for pure static analysis).
    pub run_commands: bool,
}

impl FitnessEvaluator {
    /// Create evaluator with default weights.
    pub fn new(project_root: &Path) -> Self {
        let mut weights = HashMap::new();
        weights.insert(Objective::Compilation, 0.30);
        weights.insert(Objective::TestSuccess, 0.25);
        weights.insert(Objective::ClippyWarnings, 0.10);
        weights.insert(Objective::Complexity, 0.15);
        weights.insert(Objective::Safety, 0.10);
        weights.insert(Objective::Conciseness, 0.05);
        weights.insert(Objective::Modularity, 0.05);

        Self {
            project_root: project_root.to_path_buf(),
            weights,
            run_commands: true,
        }
    }

    /// Create a static-only evaluator (no cargo commands).
    pub fn static_only(project_root: &Path) -> Self {
        let mut eval = Self::new(project_root);
        eval.run_commands = false;
        // Rebalance weights for static-only
        eval.weights.insert(Objective::Compilation, 0.0);
        eval.weights.insert(Objective::TestSuccess, 0.0);
        eval.weights.insert(Objective::ClippyWarnings, 0.0);
        eval.weights.insert(Objective::Complexity, 0.35);
        eval.weights.insert(Objective::Safety, 0.30);
        eval.weights.insert(Objective::Conciseness, 0.15);
        eval.weights.insert(Objective::Modularity, 0.20);
        eval
    }

    /// Evaluate fitness of a genome (static analysis only — fast).
    pub fn evaluate_static(&self, genome: &CodeGenome) -> FitnessReport {
        let mut objectives = HashMap::new();
        let stats = genome.stats();

        objectives.insert(Objective::Complexity, self.score_complexity(stats));
        objectives.insert(Objective::Safety, self.score_safety(stats));
        objectives.insert(Objective::Conciseness, self.score_conciseness(stats));
        objectives.insert(Objective::Modularity, self.score_modularity(stats));

        let overall = self.compute_overall(&objectives);

        FitnessReport {
            objectives,
            overall,
            genome_fingerprint: genome.fingerprint().to_string(),
            timestamp: chrono::Utc::now(),
        }
    }

    /// Full fitness evaluation including cargo build/test/clippy.
    pub fn evaluate_full(&self, genome: &CodeGenome) -> FitnessReport {
        let mut objectives = HashMap::new();
        let stats = genome.stats();

        // Static scores
        objectives.insert(Objective::Complexity, self.score_complexity(stats));
        objectives.insert(Objective::Safety, self.score_safety(stats));
        objectives.insert(Objective::Conciseness, self.score_conciseness(stats));
        objectives.insert(Objective::Modularity, self.score_modularity(stats));

        // Dynamic scores (run cargo)
        if self.run_commands {
            objectives.insert(Objective::Compilation, self.score_compilation());
            objectives.insert(Objective::TestSuccess, self.score_tests());
            objectives.insert(Objective::ClippyWarnings, self.score_clippy());
        }

        let overall = self.compute_overall(&objectives);

        FitnessReport {
            objectives,
            overall,
            genome_fingerprint: genome.fingerprint().to_string(),
            timestamp: chrono::Utc::now(),
        }
    }

    /// Compare two fitness reports — returns delta (positive = improvement).
    pub fn compare(before: &FitnessReport, after: &FitnessReport) -> f64 {
        after.overall - before.overall
    }

    /// Is a fitness delta considered an improvement?
    pub fn is_improvement(delta: f64) -> bool {
        delta > 0.001 // Must improve by at least 0.1%
    }

    // ========================================================================
    // Individual scoring functions
    // ========================================================================

    fn score_complexity(&self, stats: &GenomeStats) -> FitnessScore {
        // Lower complexity is better. Score inversely proportional.
        let avg = stats.avg_function_complexity;
        let normalized = if avg <= 5.0 {
            1.0
        } else if avg >= 30.0 {
            0.0
        } else {
            1.0 - (avg - 5.0) / 25.0
        };

        FitnessScore {
            raw: avg,
            normalized,
            weight: *self.weights.get(&Objective::Complexity).unwrap_or(&0.15),
            detail: format!("Avg complexity: {:.1}", avg),
        }
    }

    fn score_safety(&self, stats: &GenomeStats) -> FitnessScore {
        // Fewer unwraps and unsafe blocks = safer
        let total_risk = stats.total_unwrap_calls + stats.total_unsafe_blocks * 3;
        let risk_per_kloc = if stats.total_loc > 0 {
            (total_risk as f64 / stats.total_loc as f64) * 1000.0
        } else {
            0.0
        };

        let normalized = if risk_per_kloc <= 1.0 {
            1.0
        } else if risk_per_kloc >= 20.0 {
            0.0
        } else {
            1.0 - (risk_per_kloc - 1.0) / 19.0
        };

        FitnessScore {
            raw: risk_per_kloc,
            normalized,
            weight: *self.weights.get(&Objective::Safety).unwrap_or(&0.10),
            detail: format!("{} risk items per KLOC", risk_per_kloc as u32),
        }
    }

    fn score_conciseness(&self, stats: &GenomeStats) -> FitnessScore {
        // Reasonable LOC per function (not too long, not too short)
        let avg_lines = stats.avg_function_lines;
        let normalized = if (5.0..=25.0).contains(&avg_lines) {
            1.0
        } else if avg_lines < 5.0 {
            avg_lines / 5.0
        } else if avg_lines <= 80.0 {
            1.0 - (avg_lines - 25.0) / 55.0
        } else {
            0.0
        };

        FitnessScore {
            raw: avg_lines,
            normalized,
            weight: *self.weights.get(&Objective::Conciseness).unwrap_or(&0.05),
            detail: format!("Avg {:.1} lines/function", avg_lines),
        }
    }

    fn score_modularity(&self, stats: &GenomeStats) -> FitnessScore {
        // Good ratio of public to total functions
        let pub_ratio = if stats.total_functions > 0 {
            stats.total_public_functions as f64 / stats.total_functions as f64
        } else {
            0.5
        };

        // Ideal: 30-60% public (good encapsulation)
        let normalized = if (0.3..=0.6).contains(&pub_ratio) {
            1.0
        } else if pub_ratio < 0.3 {
            pub_ratio / 0.3
        } else {
            1.0 - (pub_ratio - 0.6) / 0.4
        };

        FitnessScore {
            raw: pub_ratio,
            normalized,
            weight: *self.weights.get(&Objective::Modularity).unwrap_or(&0.05),
            detail: format!("{:.0}% public functions", pub_ratio * 100.0),
        }
    }

    fn score_compilation(&self) -> FitnessScore {
        let output = Command::new("cargo")
            .arg("check")
            .arg("--quiet")
            .current_dir(&self.project_root)
            .output();

        let (success, detail) = match output {
            Ok(out) => {
                if out.status.success() {
                    (true, "Compilation successful".to_string())
                } else {
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    let error_count = stderr.matches("error[E").count();
                    (false, format!("{} compilation errors", error_count))
                }
            }
            Err(e) => (false, format!("Failed to run cargo: {}", e)),
        };

        FitnessScore {
            raw: if success { 1.0 } else { 0.0 },
            normalized: if success { 1.0 } else { 0.0 },
            weight: *self.weights.get(&Objective::Compilation).unwrap_or(&0.30),
            detail,
        }
    }

    fn score_tests(&self) -> FitnessScore {
        let output = Command::new("cargo")
            .arg("test")
            .arg("--quiet")
            .current_dir(&self.project_root)
            .output();

        let (passed, total, detail) = match output {
            Ok(out) => {
                let stdout = String::from_utf8_lossy(&out.stdout);
                let stderr = String::from_utf8_lossy(&out.stderr);
                let combined = format!("{}{}", stdout, stderr);

                // Parse "test result: ok. X passed; Y failed; Z ignored"
                let passed = parse_test_count(&combined, "passed");
                let failed = parse_test_count(&combined, "failed");
                let total = passed + failed;

                if out.status.success() {
                    (passed, total, format!("{}/{} tests passed", passed, total))
                } else {
                    (passed, total, format!("{}/{} tests failed", failed, total))
                }
            }
            Err(e) => (0, 0, format!("Failed to run tests: {}", e)),
        };

        let normalized = if total > 0 {
            passed as f64 / total as f64
        } else {
            0.5 // No tests = neutral
        };

        FitnessScore {
            raw: passed as f64,
            normalized,
            weight: *self.weights.get(&Objective::TestSuccess).unwrap_or(&0.25),
            detail,
        }
    }

    fn score_clippy(&self) -> FitnessScore {
        let output = Command::new("cargo")
            .arg("clippy")
            .arg("--quiet")
            .arg("--message-format=short")
            .current_dir(&self.project_root)
            .output();

        let (warnings, detail) = match output {
            Ok(out) => {
                let stderr = String::from_utf8_lossy(&out.stderr);
                let warning_count = stderr.matches("warning:").count();
                (warning_count, format!("{} clippy warnings", warning_count))
            }
            Err(e) => (999, format!("Failed to run clippy: {}", e)),
        };

        let normalized = if warnings == 0 {
            1.0
        } else if warnings >= 50 {
            0.0
        } else {
            1.0 - (warnings as f64 / 50.0)
        };

        FitnessScore {
            raw: warnings as f64,
            normalized,
            weight: *self.weights.get(&Objective::ClippyWarnings).unwrap_or(&0.10),
            detail,
        }
    }

    fn compute_overall(&self, objectives: &HashMap<Objective, FitnessScore>) -> f64 {
        let mut total_weight = 0.0;
        let mut weighted_sum = 0.0;

        for score in objectives.values() {
            weighted_sum += score.normalized * score.weight;
            total_weight += score.weight;
        }

        if total_weight > 0.0 {
            weighted_sum / total_weight
        } else {
            0.0
        }
    }
}

fn parse_test_count(output: &str, kind: &str) -> usize {
    // Matches patterns like "42 passed" or "3 failed"
    let re = regex::Regex::new(&format!(r"(\d+)\s+{}", kind)).ok();
    re.and_then(|r| {
        r.captures(output)
            .and_then(|c| c.get(1))
            .and_then(|m| m.as_str().parse().ok())
    })
    .unwrap_or(0)
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::genome::CodeGenome;
    use tempfile::TempDir;

    fn make_genome(code: &str) -> (TempDir, CodeGenome) {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("lib.rs"), code).unwrap();
        let genome = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();
        (dir, genome)
    }

    #[test]
    fn static_evaluation_produces_scores() {
        let (_dir, genome) = make_genome(
            r#"
pub fn clean(a: i32, b: i32) -> i32 {
    a + b
}
fn helper() -> bool {
    true
}
"#,
        );

        let evaluator = FitnessEvaluator::static_only(_dir.path());
        let report = evaluator.evaluate_static(&genome);

        assert!(report.overall > 0.0);
        assert!(report.overall <= 1.0);
        assert!(report.objectives.contains_key(&Objective::Complexity));
        assert!(report.objectives.contains_key(&Objective::Safety));
    }

    #[test]
    fn clean_code_scores_higher() {
        let (_dir1, genome1) = make_genome(
            r#"
pub fn clean(a: i32, b: i32) -> i32 {
    a + b
}
"#,
        );

        let (_dir2, genome2) = make_genome(
            r#"
pub fn messy(a: i32, b: i32) -> i32 {
    let x = a.to_string().parse::<i32>().unwrap();
    let y = b.to_string().parse::<i32>().unwrap();
    if x > 0 {
        if y > 0 {
            if x > y {
                return x.clone();
            } else {
                return y.clone();
            }
        } else {
            return x.clone();
        }
    } else {
        return y.clone();
    }
}
"#,
        );

        let eval1 = FitnessEvaluator::static_only(_dir1.path());
        let eval2 = FitnessEvaluator::static_only(_dir2.path());
        let report1 = eval1.evaluate_static(&genome1);
        let report2 = eval2.evaluate_static(&genome2);

        // Clean code should score better on complexity
        let c1 = report1.objectives.get(&Objective::Complexity).unwrap().normalized;
        let c2 = report2.objectives.get(&Objective::Complexity).unwrap().normalized;
        assert!(c1 >= c2, "Clean code complexity: {} vs messy: {}", c1, c2);
    }

    #[test]
    fn fitness_comparison() {
        let report1 = FitnessReport {
            objectives: HashMap::new(),
            overall: 0.7,
            genome_fingerprint: "abc".into(),
            timestamp: chrono::Utc::now(),
        };
        let report2 = FitnessReport {
            objectives: HashMap::new(),
            overall: 0.75,
            genome_fingerprint: "def".into(),
            timestamp: chrono::Utc::now(),
        };

        let delta = FitnessEvaluator::compare(&report1, &report2);
        assert!(FitnessEvaluator::is_improvement(delta));
        assert!(!FitnessEvaluator::is_improvement(-delta));
    }

    #[test]
    fn weight_normalization() {
        let mut weights = HashMap::new();
        weights.insert(Objective::Complexity, 0.5);
        weights.insert(Objective::Safety, 0.5);

        let eval = FitnessEvaluator {
            project_root: std::path::PathBuf::from("/tmp"),
            weights,
            run_commands: false,
        };

        let mut objectives = HashMap::new();
        objectives.insert(
            Objective::Complexity,
            FitnessScore { raw: 5.0, normalized: 1.0, weight: 0.5, detail: String::new() },
        );
        objectives.insert(
            Objective::Safety,
            FitnessScore { raw: 0.0, normalized: 0.5, weight: 0.5, detail: String::new() },
        );

        let overall = eval.compute_overall(&objectives);
        assert!((overall - 0.75).abs() < 0.001);
    }
}
