//! Code Analyzer — the eyes of the evolution engine.
//!
//! Scans the genome and identifies improvement opportunities:
//! - Anti-patterns (explicit return, unnecessary clone, unwrap abuse)
//! - Complexity hotspots (functions too complex or too long)
//! - Safety concerns (unsafe blocks, missing error handling)
//! - Performance opportunities (allocation patterns, lock contention)
//!
//! KEY PRINCIPLE: Never flags "dead code" — unconnected code is FUTURE VISION.

use crate::genome::{CodeGenome, FileGenome, FunctionSignature, Language};
use serde::{Deserialize, Serialize};

// ============================================================================
// Finding Types
// ============================================================================

/// A finding from code analysis — something that could be improved.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisFinding {
    /// What kind of finding.
    pub kind: AnalysisKind,
    /// File where found.
    pub file: String,
    /// Line number (0 if file-level).
    pub line: usize,
    /// Function name (if applicable).
    pub function: Option<String>,
    /// Human-readable description.
    pub description: String,
    /// Severity (how much fitness improvement is expected).
    pub severity: FindingSeverity,
    /// Confidence that this is a real issue (0.0-1.0).
    pub confidence: f64,
}

/// Categories of analysis findings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AnalysisKind {
    // Anti-patterns
    ExplicitReturn,
    UnnecessaryClone,
    UnwrapAbuse,
    TodoLeftBehind,

    // Complexity
    HighComplexity,
    LongFunction,
    TooManyParameters,

    // Safety
    UnsafeBlock,
    MissingSafetyComment,

    // Performance
    PotentialAllocation,
    StringFormatInLoop,

    // Quality
    InconsistentNaming,
    MissingErrorContext,

    // Architecture
    GodFunction,
    DeepNesting,
}

/// How severe is a finding.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum FindingSeverity {
    /// Nice to have improvement.
    Hint,
    /// Should be improved when touching this code.
    Suggestion,
    /// Actively degrades quality.
    Warning,
    /// Potential bug or safety issue.
    Critical,
}

// ============================================================================
// Analyzer
// ============================================================================

/// The code analyzer — scans genome and produces findings.
pub struct CodeAnalyzer {
    /// Thresholds for complexity warnings.
    pub complexity_threshold: u32,
    /// Max function length before warning.
    pub max_function_lines: usize,
    /// Max parameters before warning.
    pub max_parameters: usize,
    /// Max unwrap() calls per file before warning.
    pub max_unwrap_per_file: usize,
    /// Max clone() calls per file before warning.
    pub max_clone_per_file: usize,
}

impl Default for CodeAnalyzer {
    fn default() -> Self {
        Self {
            complexity_threshold: 15,
            max_function_lines: 80,
            max_parameters: 6,
            max_unwrap_per_file: 5,
            max_clone_per_file: 10,
        }
    }
}

impl CodeAnalyzer {
    /// Create analyzer with default thresholds.
    pub fn new() -> Self {
        Self::default()
    }

    /// Analyze the entire genome and return all findings.
    pub fn analyze(&self, genome: &CodeGenome) -> Vec<AnalysisFinding> {
        let mut findings = Vec::new();

        for file in genome.files() {
            self.analyze_file(file, &mut findings);
        }

        // Sort by severity (critical first)
        findings.sort_by(|a, b| b.severity.cmp(&a.severity));
        findings
    }

    /// Analyze a single file.
    fn analyze_file(&self, file: &FileGenome, findings: &mut Vec<AnalysisFinding>) {
        let file_path = file.path.display().to_string();

        // File-level checks
        self.check_unwrap_abuse(file, &file_path, findings);
        self.check_clone_abuse(file, &file_path, findings);
        self.check_todo_markers(file, &file_path, findings);

        // Function-level checks
        for func in &file.functions {
            self.check_explicit_return(func, file, &file_path, findings);
            self.check_complexity(func, &file_path, findings);
            self.check_function_length(func, &file_path, findings);
            self.check_parameter_count(func, &file_path, findings);
            self.check_god_function(func, &file_path, findings);
        }

        // Unsafe checks (Rust only)
        if file.language == Language::Rust {
            self.check_unsafe_blocks(file, &file_path, findings);
        }
    }

    // ========================================================================
    // Individual checks
    // ========================================================================

    fn check_explicit_return(
        &self,
        func: &FunctionSignature,
        _file: &FileGenome,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        if func.has_explicit_return && func.return_type.is_some() {
            findings.push(AnalysisFinding {
                kind: AnalysisKind::ExplicitReturn,
                file: file_path.to_string(),
                line: func.line,
                function: Some(func.name.clone()),
                description: format!(
                    "Function '{}' uses explicit `return` — idiomatic Rust uses expression-based returns",
                    func.name
                ),
                severity: FindingSeverity::Hint,
                confidence: 0.9,
            });
        }
    }

    fn check_complexity(
        &self,
        func: &FunctionSignature,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        if func.complexity > self.complexity_threshold {
            let severity = if func.complexity > self.complexity_threshold * 2 {
                FindingSeverity::Warning
            } else {
                FindingSeverity::Suggestion
            };

            findings.push(AnalysisFinding {
                kind: AnalysisKind::HighComplexity,
                file: file_path.to_string(),
                line: func.line,
                function: Some(func.name.clone()),
                description: format!(
                    "Function '{}' has cyclomatic complexity {} (threshold: {})",
                    func.name, func.complexity, self.complexity_threshold
                ),
                severity,
                confidence: 0.85,
            });
        }
    }

    fn check_function_length(
        &self,
        func: &FunctionSignature,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        if func.body_lines > self.max_function_lines {
            let severity = if func.body_lines > self.max_function_lines * 3 {
                FindingSeverity::Warning
            } else {
                FindingSeverity::Suggestion
            };

            findings.push(AnalysisFinding {
                kind: AnalysisKind::LongFunction,
                file: file_path.to_string(),
                line: func.line,
                function: Some(func.name.clone()),
                description: format!(
                    "Function '{}' is {} lines (max: {})",
                    func.name, func.body_lines, self.max_function_lines
                ),
                severity,
                confidence: 0.8,
            });
        }

        // God function: both complex AND long
        if func.body_lines > self.max_function_lines * 2 && func.complexity > self.complexity_threshold {
            findings.push(AnalysisFinding {
                kind: AnalysisKind::GodFunction,
                file: file_path.to_string(),
                line: func.line,
                function: Some(func.name.clone()),
                description: format!(
                    "Function '{}' is a God Function: {} lines, complexity {} — consider splitting",
                    func.name, func.body_lines, func.complexity
                ),
                severity: FindingSeverity::Warning,
                confidence: 0.9,
            });
        }
    }

    fn check_parameter_count(
        &self,
        func: &FunctionSignature,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        if func.param_count > self.max_parameters {
            findings.push(AnalysisFinding {
                kind: AnalysisKind::TooManyParameters,
                file: file_path.to_string(),
                line: func.line,
                function: Some(func.name.clone()),
                description: format!(
                    "Function '{}' has {} parameters (max: {}) — consider a config struct",
                    func.name, func.param_count, self.max_parameters
                ),
                severity: FindingSeverity::Suggestion,
                confidence: 0.75,
            });
        }
    }

    fn check_god_function(
        &self,
        func: &FunctionSignature,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        // Already checked in check_function_length — this catches the
        // "many params + complex" variant
        if func.param_count > self.max_parameters && func.complexity > self.complexity_threshold {
            findings.push(AnalysisFinding {
                kind: AnalysisKind::GodFunction,
                file: file_path.to_string(),
                line: func.line,
                function: Some(func.name.clone()),
                description: format!(
                    "Function '{}' does too much: {} params + complexity {} — needs decomposition",
                    func.name, func.param_count, func.complexity
                ),
                severity: FindingSeverity::Warning,
                confidence: 0.85,
            });
        }
    }

    fn check_unwrap_abuse(
        &self,
        file: &FileGenome,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        if file.unwrap_count > self.max_unwrap_per_file {
            findings.push(AnalysisFinding {
                kind: AnalysisKind::UnwrapAbuse,
                file: file_path.to_string(),
                line: 0,
                function: None,
                description: format!(
                    "File has {} unwrap() calls (max: {}) — use proper error handling",
                    file.unwrap_count, self.max_unwrap_per_file
                ),
                severity: FindingSeverity::Warning,
                confidence: 0.7,
            });
        }
    }

    fn check_clone_abuse(
        &self,
        file: &FileGenome,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        if file.clone_count > self.max_clone_per_file {
            findings.push(AnalysisFinding {
                kind: AnalysisKind::UnnecessaryClone,
                file: file_path.to_string(),
                line: 0,
                function: None,
                description: format!(
                    "File has {} clone() calls (max: {}) — consider borrowing or Rc/Arc",
                    file.clone_count, self.max_clone_per_file
                ),
                severity: FindingSeverity::Hint,
                confidence: 0.5, // Many clones are necessary
            });
        }
    }

    fn check_todo_markers(
        &self,
        file: &FileGenome,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        if file.todo_count > 0 {
            findings.push(AnalysisFinding {
                kind: AnalysisKind::TodoLeftBehind,
                file: file_path.to_string(),
                line: 0,
                function: None,
                description: format!(
                    "File has {} TODO/FIXME/HACK markers — unfinished work",
                    file.todo_count
                ),
                severity: FindingSeverity::Hint,
                confidence: 1.0,
            });
        }
    }

    fn check_unsafe_blocks(
        &self,
        file: &FileGenome,
        file_path: &str,
        findings: &mut Vec<AnalysisFinding>,
    ) {
        if file.unsafe_blocks > 3 {
            findings.push(AnalysisFinding {
                kind: AnalysisKind::UnsafeBlock,
                file: file_path.to_string(),
                line: 0,
                function: None,
                description: format!(
                    "File has {} unsafe blocks — consider safe abstractions",
                    file.unsafe_blocks
                ),
                severity: FindingSeverity::Warning,
                confidence: 0.6,
            });
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use crate::genome::CodeGenome;
    use tempfile::TempDir;

    fn make_genome(code: &str) -> CodeGenome {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("test.rs"), code).unwrap();
        CodeGenome::from_directory(dir.path(), &["rs"]).unwrap()
    }

    #[test]
    fn detects_explicit_return() {
        let genome = make_genome(
            r#"
pub fn bad() -> i32 {
    return 42;
}

pub fn good() -> i32 {
    42
}
"#,
        );

        let findings = CodeAnalyzer::new().analyze(&genome);
        let return_findings: Vec<_> = findings
            .iter()
            .filter(|f| f.kind == AnalysisKind::ExplicitReturn)
            .collect();
        assert_eq!(return_findings.len(), 1);
        assert_eq!(return_findings[0].function.as_deref(), Some("bad"));
    }

    #[test]
    fn detects_high_complexity() {
        let genome = make_genome(
            r#"
pub fn messy(x: i32, y: i32, z: i32) -> i32 {
    if x > 0 {
        if y > 0 {
            if z > 0 {
                match x {
                    1 => {
                        if y > 10 {
                            for i in 0..z {
                                if i > 5 {
                                    while x > 0 {
                                        if y > 0 && z > 0 {
                                            return 1;
                                        } else {
                                            return 2;
                                        }
                                    }
                                }
                            }
                        }
                        3
                    }
                    _ => 0,
                }
            } else { 0 }
        } else { 0 }
    } else { 0 }
}
"#,
        );

        let analyzer = CodeAnalyzer {
            complexity_threshold: 5,
            ..Default::default()
        };
        let findings = analyzer.analyze(&genome);
        let complexity_findings: Vec<_> = findings
            .iter()
            .filter(|f| f.kind == AnalysisKind::HighComplexity)
            .collect();
        assert!(!complexity_findings.is_empty());
    }

    #[test]
    fn detects_unwrap_abuse() {
        let genome = make_genome(
            r#"
fn risky() {
    let a = x.unwrap();
    let b = y.unwrap();
    let c = z.unwrap();
    let d = w.unwrap();
    let e = v.unwrap();
    let f = u.unwrap();
}
"#,
        );

        let findings = CodeAnalyzer::new().analyze(&genome);
        let unwrap_findings: Vec<_> = findings
            .iter()
            .filter(|f| f.kind == AnalysisKind::UnwrapAbuse)
            .collect();
        assert!(!unwrap_findings.is_empty());
    }

    #[test]
    fn detects_too_many_params() {
        let genome = make_genome(
            r#"
pub fn overloaded(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32) -> i32 {
    a + b + c + d + e + f + g + h
}
"#,
        );

        let analyzer = CodeAnalyzer {
            max_parameters: 6,
            ..Default::default()
        };
        let findings = analyzer.analyze(&genome);
        let param_findings: Vec<_> = findings
            .iter()
            .filter(|f| f.kind == AnalysisKind::TooManyParameters)
            .collect();
        assert!(!param_findings.is_empty());
    }

    #[test]
    fn no_findings_for_clean_code() {
        let genome = make_genome(
            r#"
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

pub fn multiply(x: f64, y: f64) -> f64 {
    x * y
}
"#,
        );

        let findings = CodeAnalyzer::new().analyze(&genome);
        // Clean code should have zero or near-zero findings
        let significant: Vec<_> = findings
            .iter()
            .filter(|f| f.severity >= FindingSeverity::Warning)
            .collect();
        assert!(significant.is_empty());
    }

    #[test]
    fn findings_sorted_by_severity() {
        let genome = make_genome(
            r#"
pub fn bad() -> i32 {
    return 42;
}
fn risky() {
    let a = x.unwrap();
    let b = y.unwrap();
    let c = z.unwrap();
    let d = w.unwrap();
    let e = v.unwrap();
    let f = u.unwrap();
}
"#,
        );

        let findings = CodeAnalyzer::new().analyze(&genome);
        for w in findings.windows(2) {
            assert!(w[0].severity >= w[1].severity);
        }
    }
}
