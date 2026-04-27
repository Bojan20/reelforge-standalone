//! FLUX_MASTER_TODO 1.1.5b/c — Unsafe-impl audit ratchet.
//!
//! `unsafe impl Send/Sync` is a manual override that tells the compiler
//! "trust me, this type is thread-safe." When that promise is wrong the
//! result is undefined behavior on a worker thread — silent until it
//! corrupts memory under load. Every such impl in this workspace MUST
//! have a `// SAFETY:` comment immediately above it explaining WHY it
//! holds.
//!
//! What this test does:
//!
//!   1. Walks every `.rs` file under `crates/`.
//!   2. Counts every `unsafe impl Send` / `unsafe impl Sync`.
//!   3. For each, looks at the immediately preceding lines (skipping
//!      blank lines + attribute macros) for a `// SAFETY:` comment.
//!   4. Fails the build if the count of UNDOCUMENTED impls exceeds the
//!      legacy baseline. The baseline is monotone-down: any commit
//!      that fixes one MUST also lower `LEGACY_UNDOCUMENTED_BASELINE`.
//!
//! Same shape as the gesture / dispose ratchets on the Flutter side —
//! turns a 38-file legacy debt into a tripwire that strictly disallows
//! growth.
//!
//! Captured 2026-04-28: 46 total `unsafe impl` lines, 8 with SAFETY
//! comments → 38 undocumented. Each fix reduces both numbers by 1.

use std::fs;
use std::path::{Path, PathBuf};

const LEGACY_UNDOCUMENTED_BASELINE: usize = 39;

#[test]
fn unsafe_impl_send_sync_count_must_not_exceed_baseline() {
    let root = workspace_root();
    let crates = root.join("crates");
    assert!(crates.is_dir(), "crates/ not found at {crates:?}");

    let mut findings: Vec<Finding> = Vec::new();
    walk(&crates, &mut findings);

    let undocumented: Vec<&Finding> = findings
        .iter()
        .filter(|f| !f.has_safety_comment)
        .collect();

    eprintln!(
        "[unsafe-safety-audit] total unsafe impl Send/Sync: {}, \
         documented: {}, undocumented: {}, baseline: {}",
        findings.len(),
        findings.len() - undocumented.len(),
        undocumented.len(),
        LEGACY_UNDOCUMENTED_BASELINE,
    );

    if undocumented.len() > LEGACY_UNDOCUMENTED_BASELINE {
        let mut msg = format!(
            "Undocumented `unsafe impl Send/Sync` count rose from baseline \
             {} → {}. Each unsafe impl MUST have an immediate `// SAFETY:` \
             comment justifying thread-safety.\n\nNew offenders (or \
             previously-documented impls that lost their SAFETY comment):\n",
            LEGACY_UNDOCUMENTED_BASELINE,
            undocumented.len()
        );
        for f in &undocumented {
            msg.push_str(&format!("  {}:{}  {}\n", f.file_rel, f.line, f.snippet.trim()));
        }
        panic!("{msg}");
    }

    // Reverse hint: if someone fixed N impls but forgot to lower the
    // baseline, surface it so the followup commit can claim the credit.
    if undocumented.len() < LEGACY_UNDOCUMENTED_BASELINE {
        eprintln!(
            "[unsafe-safety-audit] FYI: actual {} < baseline {}. Lower \
             LEGACY_UNDOCUMENTED_BASELINE in the same commit that fixed it.",
            undocumented.len(),
            LEGACY_UNDOCUMENTED_BASELINE,
        );
    }
}

#[derive(Debug)]
struct Finding {
    file_rel: String,
    line: usize,
    snippet: String,
    has_safety_comment: bool,
}

fn workspace_root() -> PathBuf {
    // CARGO_MANIFEST_DIR points at crates/rf-bridge; go up two levels.
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest.parent().unwrap().parent().unwrap().to_path_buf()
}

fn walk(dir: &Path, out: &mut Vec<Finding>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            // Skip target/ and external dependency snapshots.
            let name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if matches!(name, "target" | ".git" | "node_modules" | "tests") {
                // Skip tests/ too — we only audit production code.
                continue;
            }
            walk(&path, out);
        } else if path.extension().and_then(|s| s.to_str()) == Some("rs") {
            scan_file(&path, out);
        }
    }
}

fn scan_file(path: &Path, out: &mut Vec<Finding>) {
    let content = match fs::read_to_string(path) {
        Ok(s) => s,
        Err(_) => return,
    };
    let lines: Vec<&str> = content.lines().collect();
    let rel = strip_workspace_prefix(path);

    for (i, line) in lines.iter().enumerate() {
        let trimmed = line.trim_start();
        // Match "unsafe impl Send" / "unsafe impl Sync" — could be
        // "unsafe impl<T> Send for X {}" or just "unsafe impl Send for X {}".
        let is_send_or_sync = trimmed.starts_with("unsafe impl")
            && (line.contains(" Send ") || line.contains(" Sync ")
                || line.contains(" Send for") || line.contains(" Sync for"));
        if !is_send_or_sync {
            continue;
        }
        // Walk backwards skipping attribute macros (`#[...]`) and blank
        // lines. The first non-blank, non-attribute line MUST contain
        // "SAFETY:" for the impl to count as documented.
        let mut j = i;
        let mut has_safety = false;
        while j > 0 {
            j -= 1;
            let prev = lines[j].trim();
            if prev.is_empty() {
                continue;
            }
            if prev.starts_with("#[") {
                continue;
            }
            // The preceding line could be the SAFETY comment itself, or
            // another comment line in a multi-line // SAFETY: block.
            if prev.contains("SAFETY:") || prev.contains("Safety:") {
                has_safety = true;
            }
            break;
        }
        out.push(Finding {
            file_rel: rel.clone(),
            line: i + 1,
            snippet: line.to_string(),
            has_safety_comment: has_safety,
        });
    }
}

fn strip_workspace_prefix(path: &Path) -> String {
    let s = path.to_string_lossy().to_string();
    if let Some(idx) = s.find("/crates/") {
        s[idx + 1..].to_string()
    } else {
        s
    }
}
