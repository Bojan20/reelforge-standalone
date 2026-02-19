use axum::{
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    path::{Path, PathBuf},
    process::Command,
    sync::Arc,
};

use crate::config::AccConfig;
use crate::state::read_json;

// ═══════════════════════════════════════════════════════════════
// AUTH
// ═══════════════════════════════════════════════════════════════

const API_KEY_HEADER: &str = "x-acc-key";

fn check_auth(headers: &HeaderMap, cfg: &AccConfig) -> Result<(), (StatusCode, Json<Value>)> {
    let expected = match &cfg.api_key {
        Some(k) if !k.is_empty() => k,
        _ => return Ok(()), // no key configured = open (local dev)
    };

    let provided = headers
        .get(API_KEY_HEADER)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    if provided == expected {
        Ok(())
    } else {
        Err((
            StatusCode::UNAUTHORIZED,
            Json(json!({"ok": false, "error": "Invalid or missing API key. Set x-acc-key header."})),
        ))
    }
}

// ═══════════════════════════════════════════════════════════════
// ROUTER
// ═══════════════════════════════════════════════════════════════

#[derive(Clone)]
pub struct GptState {
    pub cfg: Arc<AccConfig>,
}

pub fn gpt_router() -> Router<GptState> {
    Router::new()
        .route("/gpt/files/read", get(files_read))
        .route("/gpt/files/tree", get(files_tree))
        .route("/gpt/files/search", get(files_search))
        .route("/gpt/context", get(context))
}

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════

const MAX_FILE_SIZE: u64 = 512_000; // 512 KB max per file read
const MAX_SEARCH_RESULTS: usize = 30;
const MAX_TREE_DEPTH: usize = 4;
const MAX_TREE_ENTRIES: usize = 500;

/// Resolve path relative to repo root, reject escapes
fn resolve_path(repo_root: &Path, requested: &str) -> Result<PathBuf, String> {
    // Reject absolute paths and obvious traversals
    if requested.starts_with('/') || requested.starts_with('\\') || requested.contains("..") {
        return Err("Path must be relative to repo root, no '..' allowed".into());
    }

    let full = repo_root.join(requested);
    let canonical = full
        .canonicalize()
        .map_err(|e| format!("Path not found: {requested} ({e})"))?;

    let repo_canonical = repo_root
        .canonicalize()
        .map_err(|e| format!("Repo root error: {e}"))?;

    if !canonical.starts_with(&repo_canonical) {
        return Err("Path escapes repo root".into());
    }

    Ok(canonical)
}

fn is_binary_file(path: &Path) -> bool {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    matches!(
        ext.as_str(),
        "png" | "jpg" | "jpeg" | "gif" | "bmp" | "ico" | "webp"
            | "mp3" | "wav" | "flac" | "ogg" | "aac" | "m4a"
            | "mp4" | "mov" | "avi" | "mkv"
            | "zip" | "tar" | "gz" | "bz2" | "xz" | "7z"
            | "exe" | "dll" | "so" | "dylib" | "a" | "o"
            | "pdf" | "woff" | "woff2" | "ttf" | "otf"
            | "sqlite" | "db"
    )
}

// ═══════════════════════════════════════════════════════════════
// GET /gpt/files/read?path=crates/rf-engine/src/ffi.rs
// ═══════════════════════════════════════════════════════════════

#[derive(Deserialize)]
struct FilesReadQuery {
    path: String,
    #[serde(default)]
    line_start: Option<usize>,
    #[serde(default)]
    line_end: Option<usize>,
}

async fn files_read(
    State(st): State<GptState>,
    headers: HeaderMap,
    Query(q): Query<FilesReadQuery>,
) -> impl IntoResponse {
    if let Err(e) = check_auth(&headers, &st.cfg) {
        return e.into_response();
    }

    let full_path = match resolve_path(&st.cfg.repo_root, &q.path) {
        Ok(p) => p,
        Err(e) => return (StatusCode::BAD_REQUEST, Json(json!({"ok": false, "error": e}))).into_response(),
    };

    if !full_path.is_file() {
        return (StatusCode::NOT_FOUND, Json(json!({"ok": false, "error": "Not a file"}))).into_response();
    }

    if is_binary_file(&full_path) {
        return (StatusCode::BAD_REQUEST, Json(json!({"ok": false, "error": "Binary file — cannot read"}))).into_response();
    }

    // Check file size
    if let Ok(meta) = std::fs::metadata(&full_path) {
        if meta.len() > MAX_FILE_SIZE {
            return (StatusCode::BAD_REQUEST, Json(json!({
                "ok": false,
                "error": format!("File too large ({} bytes, max {}). Use line_start/line_end params.", meta.len(), MAX_FILE_SIZE),
                "size_bytes": meta.len(),
            }))).into_response();
        }
    }

    match std::fs::read_to_string(&full_path) {
        Ok(content) => {
            let lines: Vec<&str> = content.lines().collect();
            let total_lines = lines.len();

            let (start, end) = match (q.line_start, q.line_end) {
                (Some(s), Some(e)) => (s.saturating_sub(1), e.min(total_lines)),
                (Some(s), None) => (s.saturating_sub(1), total_lines),
                (None, Some(e)) => (0, e.min(total_lines)),
                (None, None) => (0, total_lines),
            };

            let sliced: String = lines[start..end.min(total_lines)]
                .iter()
                .enumerate()
                .map(|(i, line)| format!("{:>5}│{}", start + i + 1, line))
                .collect::<Vec<_>>()
                .join("\n");

            (StatusCode::OK, Json(json!({
                "ok": true,
                "path": q.path,
                "total_lines": total_lines,
                "showing_lines": [start + 1, end.min(total_lines)],
                "content": sliced,
            }))).into_response()
        }
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"ok": false, "error": e.to_string()}))).into_response(),
    }
}

// ═══════════════════════════════════════════════════════════════
// GET /gpt/files/tree?path=crates/rf-engine/src&depth=2
// ═══════════════════════════════════════════════════════════════

#[derive(Deserialize)]
struct FilesTreeQuery {
    #[serde(default = "default_tree_path")]
    path: String,
    #[serde(default = "default_depth")]
    depth: usize,
}

fn default_tree_path() -> String { ".".into() }
fn default_depth() -> usize { 2 }

#[derive(Serialize)]
struct TreeEntry {
    path: String,
    #[serde(rename = "type")]
    entry_type: String, // "file" | "dir"
    size: Option<u64>,
}

async fn files_tree(
    State(st): State<GptState>,
    headers: HeaderMap,
    Query(q): Query<FilesTreeQuery>,
) -> impl IntoResponse {
    if let Err(e) = check_auth(&headers, &st.cfg) {
        return e.into_response();
    }

    let full_path = match resolve_path(&st.cfg.repo_root, &q.path) {
        Ok(p) => p,
        Err(e) => return (StatusCode::BAD_REQUEST, Json(json!({"ok": false, "error": e}))).into_response(),
    };

    if !full_path.is_dir() {
        return (StatusCode::BAD_REQUEST, Json(json!({"ok": false, "error": "Not a directory"}))).into_response();
    }

    let depth = q.depth.min(MAX_TREE_DEPTH);
    let repo_canonical = st.cfg.repo_root.canonicalize().unwrap_or_default();
    let mut entries: Vec<TreeEntry> = Vec::new();

    fn walk(dir: &Path, repo_root: &Path, current_depth: usize, max_depth: usize, entries: &mut Vec<TreeEntry>, cfg: &AccConfig) {
        if current_depth > max_depth || entries.len() >= MAX_TREE_ENTRIES {
            return;
        }

        let mut items: Vec<_> = match std::fs::read_dir(dir) {
            Ok(rd) => rd.filter_map(|e| e.ok()).collect(),
            Err(_) => return,
        };

        items.sort_by_key(|e| e.file_name());

        for item in items {
            if entries.len() >= MAX_TREE_ENTRIES {
                break;
            }

            let path = item.path();
            let rel = path.strip_prefix(repo_root).unwrap_or(&path);
            let rel_str = rel.to_string_lossy().to_string();

            // Skip ignored paths
            if cfg.is_ignored(Path::new(&rel_str)) {
                continue;
            }

            // Skip hidden dirs
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with('.') && name != ".claude" {
                    continue;
                }
            }

            if path.is_dir() {
                entries.push(TreeEntry {
                    path: format!("{}/", rel_str),
                    entry_type: "dir".into(),
                    size: None,
                });
                walk(&path, repo_root, current_depth + 1, max_depth, entries, cfg);
            } else {
                let size = std::fs::metadata(&path).ok().map(|m| m.len());
                entries.push(TreeEntry {
                    path: rel_str,
                    entry_type: "file".into(),
                    size,
                });
            }
        }
    }

    walk(&full_path, &repo_canonical, 0, depth, &mut entries, &st.cfg);

    let truncated = entries.len() >= MAX_TREE_ENTRIES;

    (StatusCode::OK, Json(json!({
        "ok": true,
        "root": q.path,
        "depth": depth,
        "count": entries.len(),
        "truncated": truncated,
        "entries": entries,
    }))).into_response()
}

// ═══════════════════════════════════════════════════════════════
// GET /gpt/files/search?query=fn apply_patch&glob=*.rs
// ═══════════════════════════════════════════════════════════════

#[derive(Deserialize)]
struct FilesSearchQuery {
    query: String,
    #[serde(default)]
    glob: Option<String>,         // e.g. "*.rs", "*.dart"
    #[serde(default)]
    path: Option<String>,         // search within subdir
    #[serde(default = "default_context")]
    context: usize,               // lines of context around match
}

fn default_context() -> usize { 2 }

#[derive(Serialize)]
struct SearchMatch {
    file: String,
    line: usize,
    content: String, // matched line + context
}

async fn files_search(
    State(st): State<GptState>,
    headers: HeaderMap,
    Query(q): Query<FilesSearchQuery>,
) -> impl IntoResponse {
    if let Err(e) = check_auth(&headers, &st.cfg) {
        return e.into_response();
    }

    if q.query.len() < 2 {
        return (StatusCode::BAD_REQUEST, Json(json!({"ok": false, "error": "Query must be at least 2 characters"}))).into_response();
    }

    let search_dir = match &q.path {
        Some(p) => match resolve_path(&st.cfg.repo_root, p) {
            Ok(dir) => dir.to_string_lossy().to_string(),
            Err(e) => return (StatusCode::BAD_REQUEST, Json(json!({"ok": false, "error": e}))).into_response(),
        },
        None => st.cfg.repo_root.to_string_lossy().to_string(),
    };

    // Use grep (rg if available, otherwise grep -r)
    let mut cmd = Command::new("grep");
    let mut args: Vec<String> = vec![
        "-rn".into(),
        "--include".into(),
        q.glob.clone().unwrap_or_else(|| "*".into()),
        "-m".into(),
        MAX_SEARCH_RESULTS.to_string(),
    ];

    if q.context > 0 {
        args.push(format!("-C{}", q.context.min(5)));
    }

    args.push("--".into());
    args.push(q.query.clone());
    args.push(search_dir.clone());

    cmd.args(&args);

    let output = match cmd.output() {
        Ok(o) => o,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"ok": false, "error": format!("grep failed: {e}")}))).into_response(),
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    let repo_str = st.cfg.repo_root.canonicalize().unwrap_or_default();
    let repo_prefix = format!("{}/", repo_str.to_string_lossy());

    let mut matches: Vec<SearchMatch> = Vec::new();

    for line in stdout.lines().take(MAX_SEARCH_RESULTS * 3) {
        // grep output: file:line:content
        if let Some((file_line, content)) = line.split_once(':') {
            if let Some((file, line_num_str)) = file_line.split_once(':') {
                if let Ok(line_num) = line_num_str.parse::<usize>() {
                    let rel_file = file.strip_prefix(&repo_prefix).unwrap_or(file);
                    matches.push(SearchMatch {
                        file: rel_file.to_string(),
                        line: line_num,
                        content: content.to_string(),
                    });
                }
            }
        }
    }

    // Deduplicate to unique files
    let unique_files: Vec<String> = {
        let mut seen = std::collections::BTreeSet::new();
        for m in &matches {
            seen.insert(m.file.clone());
        }
        seen.into_iter().collect()
    };

    (StatusCode::OK, Json(json!({
        "ok": true,
        "query": q.query,
        "glob": q.glob,
        "match_count": matches.len(),
        "files_matched": unique_files.len(),
        "files": unique_files,
        "matches": matches,
    }))).into_response()
}

// ═══════════════════════════════════════════════════════════════
// GET /gpt/context — Full project context for ChatGPT
// ═══════════════════════════════════════════════════════════════

async fn context(
    State(st): State<GptState>,
    headers: HeaderMap,
) -> impl IntoResponse {
    if let Err(e) = check_auth(&headers, &st.cfg) {
        return e.into_response();
    }

    // Read key AI_BRAIN docs
    let architecture = std::fs::read_to_string(
        st.cfg.repo_root.join("AI_BRAIN/memory/ARCHITECTURE.md")
    ).unwrap_or_else(|_| "Not found".into());

    let constraints = std::fs::read_to_string(
        st.cfg.repo_root.join("AI_BRAIN/memory/CONSTRAINTS.md")
    ).unwrap_or_else(|_| "Not found".into());

    let glossary = std::fs::read_to_string(
        st.cfg.repo_root.join("AI_BRAIN/memory/GLOSSARY.md")
    ).unwrap_or_else(|_| "Not found".into());

    let template = std::fs::read_to_string(
        st.cfg.repo_root.join("AI_BRAIN/docs/CHATGPT_TASK_TEMPLATE.md")
    ).unwrap_or_else(|_| "Not found".into());

    // Read active tasks
    let tasks: Value = read_json(&st.cfg.state_dir().join("TASKS_ACTIVE.json"))
        .unwrap_or_else(|_| json!({"active_tasks": []}));

    let milestones: Value = read_json(&st.cfg.state_dir().join("MILESTONES.json"))
        .unwrap_or_else(|_| json!({}));

    let system_status: Value = read_json(&st.cfg.state_dir().join("SYSTEM_STATUS.json"))
        .unwrap_or_else(|_| json!({}));

    // Top-level tree (depth 1)
    let repo_canonical = st.cfg.repo_root.canonicalize().unwrap_or_default();
    let mut top_dirs: Vec<String> = Vec::new();
    if let Ok(rd) = std::fs::read_dir(&repo_canonical) {
        let mut items: Vec<_> = rd.filter_map(|e| e.ok()).collect();
        items.sort_by_key(|e| e.file_name());
        for item in items {
            if let Some(name) = item.file_name().to_str() {
                if name.starts_with('.') { continue; }
                if name == "target" || name == "node_modules" || name == "build" { continue; }
                let suffix = if item.path().is_dir() { "/" } else { "" };
                top_dirs.push(format!("{name}{suffix}"));
            }
        }
    }

    (StatusCode::OK, Json(json!({
        "ok": true,
        "project": "FluxForge Studio",
        "description": "Professional DAW + Slot Audio Middleware — Flutter (Dart) + Rust (FFI bridge)",
        "top_level_structure": top_dirs,
        "architecture": architecture,
        "constraints": constraints,
        "glossary": glossary,
        "chatgpt_template": template,
        "active_tasks": tasks["active_tasks"],
        "milestones": milestones,
        "system_status": system_status,
        "available_endpoints": {
            "read_file": "GET /gpt/files/read?path=<relative_path>&line_start=N&line_end=N",
            "list_directory": "GET /gpt/files/tree?path=<relative_path>&depth=1-4",
            "search_code": "GET /gpt/files/search?query=<text>&glob=*.rs&path=crates/&context=2",
            "project_context": "GET /gpt/context",
            "apply_patch": "POST /patch/apply  {provider, task_id, reason, patch}",
            "create_task": "POST /task/create  {task_id, description, provider}",
            "close_task": "POST /task/close  {task_id, result, notes}",
            "list_tasks": "GET /task/list",
            "status": "GET /status",
        },
        "rules": [
            "Output ONLY unified diff patches when making code changes",
            "NEVER modify files in AI_BRAIN/memory/** — they are LOCKED",
            "Small, focused patches — one task = one patch",
            "Use POST /patch/apply to submit patches",
            "Always read relevant files BEFORE writing patches",
            "Dart: Provider pattern (ChangeNotifier + GetIt), import 'package:flutter_ui/...'",
            "Rust: ZERO allocations in audio thread, lock-free via rtrb ring buffer",
        ],
    }))).into_response()
}
