use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::BTreeSet, net::SocketAddr, sync::Arc};

use crate::config::AccConfig;
use crate::diffpack::{write_diffpack, DiffpackPokeRequest, DiffpackPokeResponse};
use crate::gitops::{apply_patch_on_branch, PatchApplyRequest, PatchApplyResponse};
use crate::gpt_api::{gpt_router, GptState};
use crate::state::{read_json, write_json};

#[derive(Clone)]
struct AppState {
    cfg: Arc<AccConfig>,
}

pub async fn run_server(cfg: AccConfig) -> Result<(), String> {
    let listen_addr = cfg.listen_addr.clone();
    let addr: SocketAddr = listen_addr
        .parse()
        .map_err(|e| format!("Invalid listen_addr: {e}"))?;

    let cfg_arc = Arc::new(cfg);

    let state = AppState { cfg: cfg_arc.clone() };
    let gpt_state = GptState { cfg: cfg_arc };

    let app = Router::new()
        .route("/status", get(status))
        .route("/diffpack/poke", post(diffpack_poke))
        .route("/patch/apply", post(patch_apply))
        .route("/task/create", post(task_create))
        .route("/task/close", post(task_close))
        .route("/task/list", get(task_list))
        .with_state(state)
        .merge(gpt_router().with_state(gpt_state));

    tracing::info!(%addr, "ACC HTTP server listening");

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|e| e.to_string())?;

    axum::serve(listener, app).await.map_err(|e| e.to_string())
}

// ═══════════════════════════════════════════════════════════════
// GET /status
// ═══════════════════════════════════════════════════════════════

async fn status(State(st): State<AppState>) -> impl IntoResponse {
    let providers: Value = read_json(&st.cfg.state_dir().join("PROVIDERS.json")).unwrap_or_else(|e| json!({"error": e}));
    let milestones: Value = read_json(&st.cfg.state_dir().join("MILESTONES.json")).unwrap_or_else(|e| json!({"error": e}));
    let system_status: Value = read_json(&st.cfg.state_dir().join("SYSTEM_STATUS.json")).unwrap_or_else(|e| json!({"error": e}));
    let tasks: Value = read_json(&st.cfg.state_dir().join("TASKS_ACTIVE.json")).unwrap_or_else(|e| json!({"error": e}));

    let body = json!({
        "ok": true,
        "acc_version": "0.2.0",
        "listen_addr": st.cfg.listen_addr,
        "repo_root": st.cfg.repo_root,
        "gates_config": {
            "flutter_analyze": st.cfg.gates.run_typecheck,
            "tests": st.cfg.gates.run_tests,
            "git_clean": st.cfg.gates.run_git_status_clean_before_apply,
        },
        "providers": providers,
        "milestones": milestones,
        "system_status": system_status,
        "active_tasks": tasks,
    });

    (StatusCode::OK, Json(body))
}

// ═══════════════════════════════════════════════════════════════
// POST /diffpack/poke
// ═══════════════════════════════════════════════════════════════

async fn diffpack_poke(State(st): State<AppState>, Json(req): Json<DiffpackPokeRequest>) -> impl IntoResponse {
    let mut set = BTreeSet::new();
    for f in req.changed_files {
        set.insert(f);
    }
    let reason = req.reason.unwrap_or_else(|| "manual".to_string());

    match write_diffpack(&st.cfg, &set, &reason) {
        Ok((_ts, archived)) => {
            let body = DiffpackPokeResponse {
                ok: true,
                written_to: st.cfg.diffpack_path.to_string_lossy().to_string(),
                archived,
                count: set.len(),
            };
            (StatusCode::OK, Json(body)).into_response()
        }
        Err(e) => {
            let body = json!({"ok": false, "error": e});
            (StatusCode::INTERNAL_SERVER_ERROR, Json(body)).into_response()
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// POST /patch/apply
// ═══════════════════════════════════════════════════════════════

async fn patch_apply(State(st): State<AppState>, Json(req): Json<PatchApplyRequest>) -> impl IntoResponse {
    let res: Result<PatchApplyResponse, String> = apply_patch_on_branch(&st.cfg, req);

    match res {
        Ok(body) => (StatusCode::OK, Json(body)).into_response(),
        Err(e) => {
            let body = json!({"ok": false, "error": e});
            (StatusCode::INTERNAL_SERVER_ERROR, Json(body)).into_response()
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// POST /task/create
// ═══════════════════════════════════════════════════════════════

#[derive(Debug, Deserialize)]
struct TaskCreateRequest {
    task_id: String,
    description: String,
    provider: Option<String>,       // "claude" | "openai", default "claude"
    acceptance_criteria: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
struct TaskCreateResponse {
    ok: bool,
    task_id: String,
    error: Option<String>,
}

async fn task_create(State(st): State<AppState>, Json(req): Json<TaskCreateRequest>) -> impl IntoResponse {
    let tasks_path = st.cfg.state_dir().join("TASKS_ACTIVE.json");

    let mut tasks: Value = read_json(&tasks_path).unwrap_or_else(|_| json!({
        "active_tasks": [],
        "task_history": [],
        "schema_version": "1.0",
    }));

    let ts = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_else(|_| "unknown".to_string());

    // Check for duplicate task_id
    if let Some(active) = tasks["active_tasks"].as_array() {
        for t in active {
            if t["task_id"].as_str() == Some(&req.task_id) {
                return (StatusCode::CONFLICT, Json(TaskCreateResponse {
                    ok: false,
                    task_id: req.task_id,
                    error: Some("Task ID already exists".into()),
                })).into_response();
            }
        }
    }

    let new_task = json!({
        "task_id": req.task_id,
        "description": req.description,
        "provider": req.provider.unwrap_or_else(|| "claude".into()),
        "status": "READY",
        "created_at": ts,
        "closed_at": null,
        "acceptance_criteria": req.acceptance_criteria.unwrap_or_default(),
        "result": null,
    });

    if let Some(active) = tasks["active_tasks"].as_array_mut() {
        active.push(new_task);
    }

    match write_json(&tasks_path, &tasks) {
        Ok(_) => {
            tracing::info!(task_id=%req.task_id, "Task created");
            (StatusCode::OK, Json(TaskCreateResponse {
                ok: true,
                task_id: req.task_id,
                error: None,
            })).into_response()
        }
        Err(e) => {
            (StatusCode::INTERNAL_SERVER_ERROR, Json(TaskCreateResponse {
                ok: false,
                task_id: req.task_id,
                error: Some(e),
            })).into_response()
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// POST /task/close
// ═══════════════════════════════════════════════════════════════

#[derive(Debug, Deserialize)]
struct TaskCloseRequest {
    task_id: String,
    result: String,  // "PASS" | "FAIL" | "SKIPPED"
    notes: Option<String>,
}

#[derive(Debug, Serialize)]
struct TaskCloseResponse {
    ok: bool,
    task_id: String,
    error: Option<String>,
}

async fn task_close(State(st): State<AppState>, Json(req): Json<TaskCloseRequest>) -> impl IntoResponse {
    let tasks_path = st.cfg.state_dir().join("TASKS_ACTIVE.json");

    let mut tasks: Value = read_json(&tasks_path).unwrap_or_else(|_| json!({
        "active_tasks": [],
        "task_history": [],
        "schema_version": "1.0",
    }));

    let ts = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_else(|_| "unknown".to_string());

    // Find and remove from active_tasks
    let mut found = None;
    if let Some(active) = tasks["active_tasks"].as_array_mut() {
        if let Some(idx) = active.iter().position(|t| t["task_id"].as_str() == Some(&req.task_id)) {
            let mut task = active.remove(idx);
            task["status"] = json!(req.result);
            task["closed_at"] = json!(ts);
            task["result"] = json!(req.result);
            if let Some(notes) = &req.notes {
                task["notes"] = json!(notes);
            }
            found = Some(task);
        }
    }

    match found {
        Some(closed_task) => {
            // Move to history
            if let Some(history) = tasks["task_history"].as_array_mut() {
                history.push(closed_task);
                // Keep last 100
                if history.len() > 100 {
                    let drain = history.len() - 100;
                    history.drain(0..drain);
                }
            }

            match write_json(&tasks_path, &tasks) {
                Ok(_) => {
                    tracing::info!(task_id=%req.task_id, result=%req.result, "Task closed");
                    (StatusCode::OK, Json(TaskCloseResponse {
                        ok: true,
                        task_id: req.task_id,
                        error: None,
                    })).into_response()
                }
                Err(e) => {
                    (StatusCode::INTERNAL_SERVER_ERROR, Json(TaskCloseResponse {
                        ok: false,
                        task_id: req.task_id,
                        error: Some(e),
                    })).into_response()
                }
            }
        }
        None => {
            (StatusCode::NOT_FOUND, Json(TaskCloseResponse {
                ok: false,
                task_id: req.task_id,
                error: Some("Task not found in active_tasks".into()),
            })).into_response()
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// GET /task/list
// ═══════════════════════════════════════════════════════════════

async fn task_list(State(st): State<AppState>) -> impl IntoResponse {
    let tasks_path = st.cfg.state_dir().join("TASKS_ACTIVE.json");
    let tasks: Value = read_json(&tasks_path).unwrap_or_else(|_| json!({
        "active_tasks": [],
        "task_history": [],
    }));

    (StatusCode::OK, Json(json!({
        "ok": true,
        "active_tasks": tasks["active_tasks"],
        "history_count": tasks["task_history"].as_array().map(|a| a.len()).unwrap_or(0),
        "recent_history": tasks["task_history"].as_array()
            .map(|a| a.iter().rev().take(10).cloned().collect::<Vec<_>>())
            .unwrap_or_default(),
    })))
}
