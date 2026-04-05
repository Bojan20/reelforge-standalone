//! Mutation Operators — code transformation proposals.
//!
//! Takes analysis findings and generates concrete mutations:
//! - What to change (file, line, old code, new code)
//! - Why (which finding triggered it)
//! - Expected fitness improvement
//!
//! Mutations are PROPOSALS — they don't apply themselves. The evolution
//! engine decides whether to apply, test, and keep or revert.

use crate::analyzer::{AnalysisFinding, AnalysisKind};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

// ============================================================================
// Mutation Types
// ============================================================================

/// A proposed code mutation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mutation {
    /// Unique mutation ID.
    pub id: String,
    /// What kind of mutation.
    pub kind: MutationKind,
    /// Target file (relative path).
    pub file: PathBuf,
    /// Target line (0 if file-level).
    pub line: usize,
    /// Target function (if applicable).
    pub function: Option<String>,
    /// Description of what this mutation does.
    pub description: String,
    /// The finding that triggered this mutation.
    pub source_finding: AnalysisKind,
    /// Expected fitness improvement (0.0-1.0).
    pub expected_improvement: f64,
    /// Confidence that this mutation will succeed (0.0-1.0).
    pub confidence: f64,
    /// The actual transformation to apply.
    pub transform: Transform,
}

/// Categories of mutations.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum MutationKind {
    // Style / Idiom
    RemoveExplicitReturn,
    UseQuestionMark,
    UseIfLet,

    // Safety
    ReplaceUnwrapWithExpect,
    ReplaceUnwrapWithMatch,
    AddErrorContext,

    // Performance
    RemoveUnnecessaryClone,
    PreallocateBuffer,
    UseIteratorChain,

    // Architecture
    ExtractFunction,
    IntroduceConfigStruct,
    SimplifyCondition,

    // Quality
    AddDocComment,
    ResolveTodo,

    // Custom (for future extension)
    Custom,
}

/// The actual code transformation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Transform {
    /// Replace text at specific location.
    Replace {
        /// Old text to find.
        old: String,
        /// New text to replace with.
        new: String,
    },
    /// Insert text after a specific line.
    InsertAfter {
        after_line: usize,
        text: String,
    },
    /// Delete lines in range.
    DeleteRange {
        start_line: usize,
        end_line: usize,
    },
    /// Regex-based replacement.
    RegexReplace {
        pattern: String,
        replacement: String,
    },
    /// No-op — for findings that need human intervention.
    Manual {
        suggestion: String,
    },
}

/// Result of applying a mutation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MutationResult {
    /// The mutation that was applied.
    pub mutation_id: String,
    /// Whether the mutation was successfully applied.
    pub applied: bool,
    /// The actual diff (if applied).
    pub diff: Option<String>,
    /// The new file content after mutation (if applied).
    pub new_content: Option<String>,
    /// Error message (if failed).
    pub error: Option<String>,
    /// Lines changed.
    pub lines_changed: usize,
}

// ============================================================================
// Mutation Operator
// ============================================================================

/// Generates mutations from analysis findings.
pub struct MutationOperator {
    /// Counter for generating unique IDs.
    next_id: u64,
}

impl MutationOperator {
    pub fn new() -> Self {
        Self { next_id: 0 }
    }

    /// Generate mutations from a set of findings.
    pub fn from_findings(&mut self, findings: &[AnalysisFinding]) -> Vec<Mutation> {
        let mut mutations = Vec::new();

        for finding in findings {
            if let Some(mutation) = self.finding_to_mutation(finding) {
                mutations.push(mutation);
            }
        }

        // Sort by expected improvement (best first)
        mutations.sort_by(|a, b| {
            b.expected_improvement
                .partial_cmp(&a.expected_improvement)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        mutations
    }

    /// Generate a mutation proposal from a single finding.
    fn finding_to_mutation(&mut self, finding: &AnalysisFinding) -> Option<Mutation> {
        let id = self.next_id();

        match finding.kind {
            AnalysisKind::ExplicitReturn => Some(Mutation {
                id,
                kind: MutationKind::RemoveExplicitReturn,
                file: PathBuf::from(&finding.file),
                line: finding.line,
                function: finding.function.clone(),
                description: format!(
                    "Remove explicit `return` from '{}' — use expression-based return",
                    finding.function.as_deref().unwrap_or("?")
                ),
                source_finding: finding.kind,
                expected_improvement: 0.02,
                confidence: 0.95,
                transform: Transform::RegexReplace {
                    pattern: r"return\s+(.+);(\s*\})".to_string(),
                    replacement: "$1$2".to_string(),
                },
            }),

            AnalysisKind::UnwrapAbuse => Some(Mutation {
                id,
                kind: MutationKind::ReplaceUnwrapWithExpect,
                file: PathBuf::from(&finding.file),
                line: finding.line,
                function: finding.function.clone(),
                description: "Replace .unwrap() with .expect(\"context\") for better panic messages".to_string(),
                source_finding: finding.kind,
                expected_improvement: 0.05,
                confidence: 0.8,
                transform: Transform::Manual {
                    suggestion: "Replace each .unwrap() with .expect(\"descriptive message\") or proper error handling with ?".to_string(),
                },
            }),

            AnalysisKind::HighComplexity => Some(Mutation {
                id,
                kind: MutationKind::ExtractFunction,
                file: PathBuf::from(&finding.file),
                line: finding.line,
                function: finding.function.clone(),
                description: format!(
                    "Decompose '{}' — extract inner logic into smaller functions",
                    finding.function.as_deref().unwrap_or("?")
                ),
                source_finding: finding.kind,
                expected_improvement: 0.1,
                confidence: 0.6,
                transform: Transform::Manual {
                    suggestion: "Identify logical blocks within the function and extract them as separate helper functions".to_string(),
                },
            }),

            AnalysisKind::LongFunction => Some(Mutation {
                id,
                kind: MutationKind::ExtractFunction,
                file: PathBuf::from(&finding.file),
                line: finding.line,
                function: finding.function.clone(),
                description: format!(
                    "Split '{}' into smaller functions",
                    finding.function.as_deref().unwrap_or("?")
                ),
                source_finding: finding.kind,
                expected_improvement: 0.08,
                confidence: 0.65,
                transform: Transform::Manual {
                    suggestion: "Break the function at natural boundary points (e.g., setup/process/cleanup phases)".to_string(),
                },
            }),

            AnalysisKind::TooManyParameters => Some(Mutation {
                id,
                kind: MutationKind::IntroduceConfigStruct,
                file: PathBuf::from(&finding.file),
                line: finding.line,
                function: finding.function.clone(),
                description: format!(
                    "Introduce a config struct for '{}' parameters",
                    finding.function.as_deref().unwrap_or("?")
                ),
                source_finding: finding.kind,
                expected_improvement: 0.06,
                confidence: 0.7,
                transform: Transform::Manual {
                    suggestion: "Create a FunctionNameConfig struct grouping related parameters, pass it instead of individual args".to_string(),
                },
            }),

            AnalysisKind::GodFunction => Some(Mutation {
                id,
                kind: MutationKind::ExtractFunction,
                file: PathBuf::from(&finding.file),
                line: finding.line,
                function: finding.function.clone(),
                description: format!(
                    "God function '{}' needs major decomposition",
                    finding.function.as_deref().unwrap_or("?")
                ),
                source_finding: finding.kind,
                expected_improvement: 0.15,
                confidence: 0.5,
                transform: Transform::Manual {
                    suggestion: "Apply Single Responsibility Principle: identify distinct responsibilities and create a function for each".to_string(),
                },
            }),

            AnalysisKind::TodoLeftBehind => Some(Mutation {
                id,
                kind: MutationKind::ResolveTodo,
                file: PathBuf::from(&finding.file),
                line: 0,
                function: None,
                description: format!("Resolve TODO/FIXME markers in {}", finding.file),
                source_finding: finding.kind,
                expected_improvement: 0.03,
                confidence: 0.3, // Low — TODOs often need context
                transform: Transform::Manual {
                    suggestion: "Review each TODO marker and either implement the feature or remove the marker with a tracking issue".to_string(),
                },
            }),

            AnalysisKind::UnnecessaryClone => Some(Mutation {
                id,
                kind: MutationKind::RemoveUnnecessaryClone,
                file: PathBuf::from(&finding.file),
                line: 0,
                function: None,
                description: format!("Reduce clone() usage in {}", finding.file),
                source_finding: finding.kind,
                expected_improvement: 0.04,
                confidence: 0.4, // Many clones are actually needed
                transform: Transform::Manual {
                    suggestion: "Audit each clone() — replace with borrows where possible, Rc/Arc for shared ownership".to_string(),
                },
            }),

            _ => None,
        }
    }

    /// Apply a Transform to file content. Returns the new content if successful.
    pub fn apply_replace(content: &str, transform: &Transform) -> MutationResult {
        match transform {
            Transform::Replace { old, new } => {
                if content.contains(old.as_str()) {
                    let new_content = content.replacen(old.as_str(), new.as_str(), 1);
                    let lines_changed = old.lines().count().max(new.lines().count());
                    MutationResult {
                        mutation_id: String::new(),
                        applied: true,
                        diff: Some(format!("-{}\n+{}", old, new)),
                        new_content: Some(new_content),
                        error: None,
                        lines_changed,
                    }
                } else {
                    MutationResult {
                        mutation_id: String::new(),
                        applied: false,
                        diff: None,
                        new_content: None,
                        error: Some("Old text not found in file".to_string()),
                        lines_changed: 0,
                    }
                }
            }
            Transform::RegexReplace { pattern, replacement } => {
                match regex::Regex::new(pattern) {
                    Ok(re) => {
                        let new_content = re.replace_all(content, replacement.as_str()).into_owned();
                        if new_content != content {
                            MutationResult {
                                mutation_id: String::new(),
                                applied: true,
                                diff: Some(format!("Regex: s/{}/{}/", pattern, replacement)),
                                new_content: Some(new_content),
                                error: None,
                                lines_changed: 1,
                            }
                        } else {
                            MutationResult {
                                mutation_id: String::new(),
                                applied: false,
                                diff: None,
                                new_content: None,
                                error: Some("Regex pattern did not match".to_string()),
                                lines_changed: 0,
                            }
                        }
                    }
                    Err(e) => MutationResult {
                        mutation_id: String::new(),
                        applied: false,
                        diff: None,
                        new_content: None,
                        error: Some(format!("Invalid regex: {}", e)),
                        lines_changed: 0,
                    },
                }
            }
            _ => MutationResult {
                mutation_id: String::new(),
                applied: false,
                diff: None,
                new_content: None,
                error: Some("Transform type not auto-applicable".to_string()),
                lines_changed: 0,
            },
        }
    }

    fn next_id(&mut self) -> String {
        self.next_id += 1;
        format!("mut_{:06}", self.next_id)
    }
}

impl Default for MutationOperator {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analyzer::{CodeAnalyzer, AnalysisKind, FindingSeverity};
    use crate::genome::CodeGenome;
    use tempfile::TempDir;

    #[test]
    fn generates_mutations_from_findings() {
        let finding = AnalysisFinding {
            kind: AnalysisKind::ExplicitReturn,
            file: "src/test.rs".to_string(),
            line: 3,
            function: Some("bad_fn".to_string()),
            description: "Uses explicit return".to_string(),
            severity: FindingSeverity::Hint,
            confidence: 0.9,
        };

        let mut operator = MutationOperator::new();
        let mutations = operator.from_findings(&[finding]);
        assert_eq!(mutations.len(), 1);
        assert_eq!(mutations[0].kind, MutationKind::RemoveExplicitReturn);
    }

    #[test]
    fn apply_replace_transform() {
        let content = "fn foo() -> i32 {\n    return 42;\n}";
        let transform = Transform::Replace {
            old: "return 42;".to_string(),
            new: "42".to_string(),
        };

        let result = MutationOperator::apply_replace(content, &transform);
        assert!(result.applied);
        assert!(result.diff.is_some());
    }

    #[test]
    fn apply_regex_transform() {
        let content = "fn foo() -> i32 {\n    return 42;\n}";
        let transform = Transform::RegexReplace {
            pattern: r"return\s+(\d+);".to_string(),
            replacement: "$1".to_string(),
        };

        let result = MutationOperator::apply_replace(content, &transform);
        assert!(result.applied);
    }

    #[test]
    fn mutations_sorted_by_improvement() {
        let findings = vec![
            AnalysisFinding {
                kind: AnalysisKind::ExplicitReturn,
                file: "a.rs".into(),
                line: 1,
                function: Some("f".into()),
                description: String::new(),
                severity: FindingSeverity::Hint,
                confidence: 0.9,
            },
            AnalysisFinding {
                kind: AnalysisKind::GodFunction,
                file: "b.rs".into(),
                line: 1,
                function: Some("g".into()),
                description: String::new(),
                severity: FindingSeverity::Warning,
                confidence: 0.5,
            },
        ];

        let mut operator = MutationOperator::new();
        let mutations = operator.from_findings(&findings);
        assert!(mutations.len() >= 2);
        // God function should have higher expected improvement
        assert!(mutations[0].expected_improvement >= mutations[1].expected_improvement);
    }

    #[test]
    fn full_pipeline_findings_to_mutations() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(
            src.join("test.rs"),
            r#"
pub fn messy(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32) -> i32 {
    return a + b + c + d + e + f + g;
}
"#,
        )
        .unwrap();

        let genome = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();
        let findings = CodeAnalyzer::new().analyze(&genome);
        let mut operator = MutationOperator::new();
        let mutations = operator.from_findings(&findings);

        // Should have at least: explicit return + too many params
        assert!(mutations.len() >= 2);
    }

    #[test]
    fn unique_mutation_ids() {
        let mut operator = MutationOperator::new();
        let finding = AnalysisFinding {
            kind: AnalysisKind::ExplicitReturn,
            file: "a.rs".into(),
            line: 1,
            function: Some("f".into()),
            description: String::new(),
            severity: FindingSeverity::Hint,
            confidence: 0.9,
        };

        let m1 = operator.from_findings(&[finding.clone()]);
        let m2 = operator.from_findings(&[finding]);
        assert_ne!(m1[0].id, m2[0].id);
    }
}
