//! Code Genome — represents the DNA of the codebase.
//!
//! Scans source files, extracts function signatures, computes complexity
//! metrics, and generates stable fingerprints for change detection.
//!
//! Key principle: this is a READ-ONLY view of the code. It never modifies
//! anything — it only observes and measures.

use crate::{EvolutionError, Result};
use quote::ToTokens;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

// ============================================================================
// Core Types
// ============================================================================

/// The complete genome of a codebase — all source files, functions, metrics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeGenome {
    /// Root directory of the scanned codebase.
    root: PathBuf,
    /// Per-file genome data.
    files: Vec<FileGenome>,
    /// Aggregate fingerprint of the entire genome.
    fingerprint: String,
    /// Aggregate statistics.
    stats: GenomeStats,
}

/// Genome of a single source file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileGenome {
    /// Relative path from root.
    pub path: PathBuf,
    /// SHA-256 of file content.
    pub content_hash: String,
    /// Total lines of code (non-empty, non-comment).
    pub loc: usize,
    /// Total lines including comments and blanks.
    pub total_lines: usize,
    /// Extracted function signatures.
    pub functions: Vec<FunctionSignature>,
    /// Cyclomatic complexity estimate (sum of all functions).
    pub complexity: u32,
    /// Number of `unsafe` blocks.
    pub unsafe_blocks: usize,
    /// Number of `todo!()` / `unimplemented!()` / `TODO` comments.
    pub todo_count: usize,
    /// Number of `unwrap()` calls.
    pub unwrap_count: usize,
    /// Number of `clone()` calls.
    pub clone_count: usize,
    /// Detected language.
    pub language: Language,
}

/// A function/method signature extracted from source code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FunctionSignature {
    /// Function name.
    pub name: String,
    /// Line number where function starts.
    pub line: usize,
    /// Number of lines in function body.
    pub body_lines: usize,
    /// Number of parameters.
    pub param_count: usize,
    /// Is it public?
    pub is_public: bool,
    /// Is it async?
    pub is_async: bool,
    /// Is it unsafe?
    pub is_unsafe: bool,
    /// Estimated cyclomatic complexity.
    pub complexity: u32,
    /// Contains explicit `return` statement?
    pub has_explicit_return: bool,
    /// Return type (as string).
    pub return_type: Option<String>,
}

/// Aggregate genome statistics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GenomeStats {
    pub total_files: usize,
    pub total_lines: usize,
    pub total_loc: usize,
    pub total_functions: usize,
    pub total_public_functions: usize,
    pub total_unsafe_blocks: usize,
    pub total_unwrap_calls: usize,
    pub total_clone_calls: usize,
    pub total_todo_count: usize,
    pub avg_function_complexity: f64,
    pub max_function_complexity: u32,
    pub avg_function_lines: f64,
    pub max_function_lines: usize,
    pub languages: HashMap<Language, usize>,
}

/// Detected source language.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Language {
    Rust,
    Dart,
    TypeScript,
    JavaScript,
    Python,
    Unknown,
}

// ============================================================================
// Implementation
// ============================================================================

impl CodeGenome {
    /// Build a genome from a directory, scanning files with given extensions.
    pub fn from_directory(root: &Path, extensions: &[&str]) -> Result<Self> {
        let mut files = Vec::new();

        for entry in WalkDir::new(root)
            .follow_links(true)
            .into_iter()
            .filter_entry(|e| {
                // Don't filter the root directory itself
                if e.depth() == 0 {
                    return true;
                }
                !is_hidden(e) && !is_build_dir(e)
            })
        {
            let entry = entry.map_err(|e| EvolutionError::Io(e.into()))?;
            if !entry.file_type().is_file() {
                continue;
            }

            let path = entry.path();
            let ext = path
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("");

            if !extensions.contains(&ext) {
                continue;
            }

            match FileGenome::from_file(path, root) {
                Ok(fg) => files.push(fg),
                Err(e) => {
                    log::debug!("Skipping {}: {}", path.display(), e);
                }
            }
        }

        let stats = GenomeStats::compute(&files);
        let fingerprint = Self::compute_fingerprint(&files);

        Ok(Self {
            root: root.to_path_buf(),
            files,
            fingerprint,
            stats,
        })
    }

    /// Get all file genomes.
    pub fn files(&self) -> &[FileGenome] {
        &self.files
    }

    /// Get aggregate statistics.
    pub fn stats(&self) -> &GenomeStats {
        &self.stats
    }

    /// Get the genome fingerprint (changes when any source file changes).
    pub fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    /// Get the root directory.
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Find a file genome by relative path.
    pub fn find_file(&self, rel_path: &str) -> Option<&FileGenome> {
        self.files.iter().find(|f| {
            f.path.to_str().map_or(false, |p| p == rel_path)
        })
    }

    /// Get the N most complex functions across all files.
    pub fn most_complex_functions(&self, n: usize) -> Vec<(&FileGenome, &FunctionSignature)> {
        let mut all: Vec<_> = self
            .files
            .iter()
            .flat_map(|f| f.functions.iter().map(move |func| (f, func)))
            .collect();

        all.sort_by(|a, b| b.1.complexity.cmp(&a.1.complexity));
        all.truncate(n);
        all
    }

    /// Get the N longest functions across all files.
    pub fn longest_functions(&self, n: usize) -> Vec<(&FileGenome, &FunctionSignature)> {
        let mut all: Vec<_> = self
            .files
            .iter()
            .flat_map(|f| f.functions.iter().map(move |func| (f, func)))
            .collect();

        all.sort_by(|a, b| b.1.body_lines.cmp(&a.1.body_lines));
        all.truncate(n);
        all
    }

    /// Get files with the most unwrap() calls.
    pub fn unwrap_hotspots(&self, n: usize) -> Vec<&FileGenome> {
        let mut sorted: Vec<_> = self.files.iter().filter(|f| f.unwrap_count > 0).collect();
        sorted.sort_by(|a, b| b.unwrap_count.cmp(&a.unwrap_count));
        sorted.truncate(n);
        sorted
    }

    fn compute_fingerprint(files: &[FileGenome]) -> String {
        let mut hasher = Sha256::new();
        let mut sorted_hashes: Vec<_> = files
            .iter()
            .map(|f| format!("{}:{}", f.path.display(), f.content_hash))
            .collect();
        sorted_hashes.sort();
        for h in &sorted_hashes {
            hasher.update(h.as_bytes());
        }
        hex::encode(hasher.finalize())
    }
}

impl FileGenome {
    /// Parse a source file and extract its genome.
    pub fn from_file(path: &Path, root: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path).map_err(EvolutionError::Io)?;
        let rel_path = path.strip_prefix(root).unwrap_or(path).to_path_buf();
        let language = Language::from_extension(
            path.extension().and_then(|e| e.to_str()).unwrap_or(""),
        );

        let content_hash = {
            let mut hasher = Sha256::new();
            hasher.update(content.as_bytes());
            hex::encode(hasher.finalize())
        };

        let total_lines = content.lines().count();
        let loc = content
            .lines()
            .filter(|line| {
                let trimmed = line.trim();
                !trimmed.is_empty() && !trimmed.starts_with("//") && !trimmed.starts_with('#')
            })
            .count();

        let (functions, unsafe_blocks) = match language {
            Language::Rust => {
                // Try AST parsing first, fall back to text-based extraction
                extract_rust_functions(&content, path)
                    .unwrap_or_else(|_| extract_rust_text_based(&content))
            }
            _ => extract_generic_functions(&content, language),
        };

        let complexity: u32 = functions.iter().map(|f| f.complexity).sum();
        let todo_count = count_pattern(&content, &["todo!()", "unimplemented!()", "TODO", "FIXME", "HACK"]);
        let unwrap_count = count_pattern(&content, &[".unwrap()"]);
        let clone_count = count_pattern(&content, &[".clone()"]);

        Ok(Self {
            path: rel_path,
            content_hash,
            loc,
            total_lines,
            functions,
            complexity,
            unsafe_blocks,
            todo_count,
            unwrap_count,
            clone_count,
            language,
        })
    }
}

impl GenomeStats {
    fn compute(files: &[FileGenome]) -> Self {
        let total_files = files.len();
        let total_lines: usize = files.iter().map(|f| f.total_lines).sum();
        let total_loc: usize = files.iter().map(|f| f.loc).sum();
        let total_functions: usize = files.iter().map(|f| f.functions.len()).sum();
        let total_public_functions: usize = files
            .iter()
            .flat_map(|f| &f.functions)
            .filter(|func| func.is_public)
            .count();
        let total_unsafe_blocks: usize = files.iter().map(|f| f.unsafe_blocks).sum();
        let total_unwrap_calls: usize = files.iter().map(|f| f.unwrap_count).sum();
        let total_clone_calls: usize = files.iter().map(|f| f.clone_count).sum();
        let total_todo_count: usize = files.iter().map(|f| f.todo_count).sum();

        let all_functions: Vec<_> = files.iter().flat_map(|f| &f.functions).collect();
        let avg_function_complexity = if all_functions.is_empty() {
            0.0
        } else {
            all_functions.iter().map(|f| f.complexity as f64).sum::<f64>() / all_functions.len() as f64
        };
        let max_function_complexity = all_functions.iter().map(|f| f.complexity).max().unwrap_or(0);
        let avg_function_lines = if all_functions.is_empty() {
            0.0
        } else {
            all_functions.iter().map(|f| f.body_lines as f64).sum::<f64>() / all_functions.len() as f64
        };
        let max_function_lines = all_functions.iter().map(|f| f.body_lines).max().unwrap_or(0);

        let mut languages: HashMap<Language, usize> = HashMap::new();
        for f in files {
            *languages.entry(f.language).or_default() += 1;
        }

        Self {
            total_files,
            total_lines,
            total_loc,
            total_functions,
            total_public_functions,
            total_unsafe_blocks,
            total_unwrap_calls,
            total_clone_calls,
            total_todo_count,
            avg_function_complexity,
            max_function_complexity,
            avg_function_lines,
            max_function_lines,
            languages,
        }
    }
}

impl Language {
    pub fn from_extension(ext: &str) -> Self {
        match ext {
            "rs" => Language::Rust,
            "dart" => Language::Dart,
            "ts" | "tsx" => Language::TypeScript,
            "js" | "jsx" => Language::JavaScript,
            "py" => Language::Python,
            _ => Language::Unknown,
        }
    }
}

// ============================================================================
// Rust-specific extraction using syn
// ============================================================================

fn extract_rust_functions(content: &str, path: &Path) -> Result<(Vec<FunctionSignature>, usize)> {
    let syntax = syn::parse_file(content).map_err(|e| EvolutionError::Parse {
        file: path.display().to_string(),
        message: e.to_string(),
    })?;

    let mut functions = Vec::new();
    let mut unsafe_blocks = 0usize;

    for item in &syntax.items {
        match item {
            syn::Item::Fn(func) => {
                functions.push(extract_fn_sig(func, content));
                unsafe_blocks += count_unsafe_in_block(&func.block);
            }
            syn::Item::Impl(imp) => {
                for impl_item in &imp.items {
                    if let syn::ImplItem::Fn(method) = impl_item {
                        functions.push(extract_method_sig(method, content));
                        unsafe_blocks += count_unsafe_in_block(&method.block);
                    }
                }
            }
            syn::Item::Mod(module) => {
                if let Some((_, items)) = &module.content {
                    for sub_item in items {
                        if let syn::Item::Fn(func) = sub_item {
                            functions.push(extract_fn_sig(func, content));
                            unsafe_blocks += count_unsafe_in_block(&func.block);
                        }
                    }
                }
            }
            _ => {}
        }
    }

    Ok((functions, unsafe_blocks))
}

fn extract_fn_sig(func: &syn::ItemFn, source: &str) -> FunctionSignature {
    let name = func.sig.ident.to_string();
    let span = func.sig.ident.span();
    let line = span.start().line;
    let body_text = func.block.to_token_stream().to_string();
    let body_lines = body_text.lines().count();
    let param_count = func.sig.inputs.len();
    let is_public = matches!(func.vis, syn::Visibility::Public(_));
    let is_async = func.sig.asyncness.is_some();
    let is_unsafe = func.sig.unsafety.is_some();
    let complexity = estimate_complexity(&body_text);
    let has_explicit_return = has_explicit_return_stmt(source, &func.block);
    let return_type = extract_return_type(&func.sig.output);

    FunctionSignature {
        name,
        line,
        body_lines,
        param_count,
        is_public,
        is_async,
        is_unsafe,
        complexity,
        has_explicit_return,
        return_type,
    }
}

fn extract_method_sig(method: &syn::ImplItemFn, source: &str) -> FunctionSignature {
    let name = method.sig.ident.to_string();
    let span = method.sig.ident.span();
    let line = span.start().line;
    let body_text = method.block.to_token_stream().to_string();
    let body_lines = body_text.lines().count();
    let param_count = method.sig.inputs.len();
    let is_public = matches!(method.vis, syn::Visibility::Public(_));
    let is_async = method.sig.asyncness.is_some();
    let is_unsafe = method.sig.unsafety.is_some();
    let complexity = estimate_complexity(&body_text);
    let has_explicit_return = has_explicit_return_stmt(source, &method.block);
    let return_type = extract_return_type(&method.sig.output);

    FunctionSignature {
        name,
        line,
        body_lines,
        param_count,
        is_public,
        is_async,
        is_unsafe,
        complexity,
        has_explicit_return,
        return_type,
    }
}

fn extract_return_type(output: &syn::ReturnType) -> Option<String> {
    match output {
        syn::ReturnType::Default => None,
        syn::ReturnType::Type(_, ty) => Some(ty.to_token_stream().to_string()),
    }
}

fn has_explicit_return_stmt(_source: &str, block: &syn::Block) -> bool {
    let block_str = block.to_token_stream().to_string();
    // Look for `return` keyword that isn't inside a closure or nested fn
    // Simple heuristic: if the source contains "return " outside string literals
    block_str.contains("return ")
}

fn count_unsafe_in_block(block: &syn::Block) -> usize {
    let text = block.to_token_stream().to_string();
    text.matches("unsafe").count()
}

/// Text-based Rust function extraction (fallback when syn can't parse).
fn extract_rust_text_based(content: &str) -> (Vec<FunctionSignature>, usize) {
    let fn_re = regex::Regex::new(
        r"(?m)^\s*(pub\s+)?(async\s+)?(unsafe\s+)?fn\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)"
    ).unwrap();

    let mut functions = Vec::new();

    for cap in fn_re.captures_iter(content) {
        let is_public = cap.get(1).is_some();
        let is_async = cap.get(2).is_some();
        let is_unsafe = cap.get(3).is_some();
        let name = cap[4].to_string();
        let params_str = &cap[5];
        let param_count = if params_str.trim().is_empty() {
            0
        } else {
            params_str.split(',').count()
        };

        // Find line number
        let match_start = cap.get(0).unwrap().start();
        let line = content[..match_start].lines().count() + 1;

        // Estimate body by counting lines until matching brace
        let after_match = &content[cap.get(0).unwrap().end()..];
        let body_lines = estimate_body_lines(after_match);

        // Check for explicit return
        let body_text = if body_lines > 0 {
            let body_start = cap.get(0).unwrap().end();
            let body_end = (body_start + body_lines * 80).min(content.len());
            &content[body_start..body_end]
        } else {
            ""
        };
        let has_explicit_return = body_text.contains("return ");

        // Get return type
        let return_type = {
            let after_params = &content[cap.get(0).unwrap().end()..];
            if let Some(arrow_pos) = after_params.find("->") {
                let type_start = arrow_pos + 2;
                let type_end = after_params[type_start..].find('{')
                    .map(|p| type_start + p)
                    .unwrap_or(type_start + 20.min(after_params.len() - type_start));
                Some(after_params[type_start..type_end].trim().to_string())
            } else {
                None
            }
        };

        let complexity = estimate_complexity(body_text);

        functions.push(FunctionSignature {
            name,
            line,
            body_lines,
            param_count,
            is_public,
            is_async,
            is_unsafe,
            complexity,
            has_explicit_return,
            return_type,
        });
    }

    // Count unsafe blocks
    let unsafe_blocks = content.matches("unsafe {").count() + content.matches("unsafe{").count();

    (functions, unsafe_blocks)
}

/// Estimate function body lines by counting brace depth.
fn estimate_body_lines(text: &str) -> usize {
    let mut depth = 0i32;
    let mut started = false;
    let mut lines = 0usize;

    for ch in text.chars() {
        if ch == '{' {
            depth += 1;
            started = true;
        } else if ch == '}' {
            depth -= 1;
            if started && depth == 0 {
                return lines;
            }
        } else if ch == '\n' && started {
            lines += 1;
        }
    }
    lines
}

/// Estimate cyclomatic complexity from token stream text.
/// Counts branching keywords as a rough proxy.
fn estimate_complexity(body: &str) -> u32 {
    let mut complexity = 1u32; // base path

    let keywords = [
        " if ", " else ", " match ", " for ", " while ", " loop ",
        " && ", " || ", "? ", " => ",
    ];

    for kw in &keywords {
        complexity += body.matches(kw).count() as u32;
    }

    complexity
}

// ============================================================================
// Generic (non-Rust) extraction
// ============================================================================

fn extract_generic_functions(content: &str, language: Language) -> (Vec<FunctionSignature>, usize) {
    let mut functions = Vec::new();
    let fn_pattern = match language {
        Language::Dart => regex::Regex::new(r"(?m)^\s*([\w<>\?]+\s+)?(\w+)\s*\([^)]*\)\s*(async\s*)?\{").ok(),
        Language::TypeScript | Language::JavaScript => {
            regex::Regex::new(r"(?m)(?:export\s+)?(?:async\s+)?(?:function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>)").ok()
        }
        Language::Python => regex::Regex::new(r"(?m)^(?:async\s+)?def\s+(\w+)\s*\(").ok(),
        _ => None,
    };

    if let Some(re) = fn_pattern {
        for (i, line) in content.lines().enumerate() {
            if re.is_match(line) {
                let name = re
                    .captures(line)
                    .and_then(|c| {
                        c.get(1)
                            .or_else(|| c.get(2))
                            .map(|m| m.as_str().to_string())
                    })
                    .unwrap_or_else(|| format!("anonymous_{}", i));

                functions.push(FunctionSignature {
                    name,
                    line: i + 1,
                    body_lines: 0, // Can't determine without full parsing
                    param_count: 0,
                    is_public: line.contains("pub ") || line.contains("export "),
                    is_async: line.contains("async"),
                    is_unsafe: false,
                    complexity: 1,
                    has_explicit_return: false,
                    return_type: None,
                });
            }
        }
    }

    (functions, 0)
}

// ============================================================================
// Helpers
// ============================================================================

fn is_hidden(entry: &walkdir::DirEntry) -> bool {
    entry
        .file_name()
        .to_str()
        .map_or(false, |s| s.starts_with('.') && s != ".")
}

fn is_build_dir(entry: &walkdir::DirEntry) -> bool {
    let name = entry.file_name().to_str().unwrap_or("");
    matches!(
        name,
        "target" | "node_modules" | "build" | ".dart_tool" | "__pycache__"
            | "Pods" | ".build" | "DerivedData"
    )
}

fn count_pattern(content: &str, patterns: &[&str]) -> usize {
    patterns.iter().map(|p| content.matches(p).count()).sum()
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn parse_simple_rust_file() {
        let dir = TempDir::new().unwrap();
        let file = dir.path().join("test.rs");
        std::fs::write(
            &file,
            r#"
pub fn greet(name: &str) -> String {
    format!("Hello, {}!", name)
}

fn helper() -> i32 {
    if true {
        42
    } else {
        0
    }
}

pub async fn fetch_data() -> Result<String, Error> {
    let response = client.get(url).await?;
    Ok(response.text().await?)
}
"#,
        )
        .unwrap();

        let genome = FileGenome::from_file(&file, dir.path()).unwrap();
        assert_eq!(genome.functions.len(), 3);
        assert!(genome.functions[0].is_public);
        assert_eq!(genome.functions[0].name, "greet");
        assert_eq!(genome.functions[0].param_count, 1);
        assert!(!genome.functions[1].is_public);
        assert!(genome.functions[1].complexity > 1); // has if/else
        assert!(genome.functions[2].is_async);
    }

    #[test]
    fn genome_from_directory() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("a.rs"), "pub fn a() {}").unwrap();
        std::fs::write(src.join("b.rs"), "pub fn b() {} fn c() {}").unwrap();

        let genome = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();
        assert_eq!(genome.files().len(), 2);
        assert_eq!(genome.stats().total_functions, 3);
        assert_eq!(genome.stats().total_public_functions, 2);
    }

    #[test]
    fn complexity_estimation() {
        assert_eq!(estimate_complexity("{ x + y }"), 1);
        assert_eq!(
            estimate_complexity("{ if a { b } else { c } }"),
            3 // 1 base + if + else
        );
        assert!(estimate_complexity("{ match x { A => 1, B => 2, C => 3 } }") > 1);
    }

    #[test]
    fn language_detection() {
        assert_eq!(Language::from_extension("rs"), Language::Rust);
        assert_eq!(Language::from_extension("dart"), Language::Dart);
        assert_eq!(Language::from_extension("ts"), Language::TypeScript);
        assert_eq!(Language::from_extension("py"), Language::Python);
        assert_eq!(Language::from_extension("xyz"), Language::Unknown);
    }

    #[test]
    fn most_complex_functions_ranking() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(
            src.join("test.rs"),
            r#"
fn simple() -> i32 { 42 }
fn complex(x: i32) -> i32 {
    if x > 0 {
        if x > 10 {
            match x {
                11 => 1,
                12 => 2,
                _ => 3,
            }
        } else {
            x
        }
    } else {
        0
    }
}
"#,
        )
        .unwrap();

        let genome = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();
        let top = genome.most_complex_functions(1);
        assert_eq!(top.len(), 1);
        assert_eq!(top[0].1.name, "complex");
    }

    #[test]
    fn unwrap_hotspots() {
        let dir = TempDir::new().unwrap();
        let src = dir.path().join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("safe.rs"), "fn safe() -> i32 { 42 }").unwrap();
        std::fs::write(
            src.join("risky.rs"),
            "fn risky() { x.unwrap(); y.unwrap(); z.unwrap(); }",
        )
        .unwrap();

        let genome = CodeGenome::from_directory(dir.path(), &["rs"]).unwrap();
        let hotspots = genome.unwrap_hotspots(10);
        assert_eq!(hotspots.len(), 1);
        assert_eq!(hotspots[0].unwrap_count, 3);
    }
}
