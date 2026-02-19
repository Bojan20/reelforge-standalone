use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};
use std::{collections::BTreeSet, net::SocketAddr, sync::Arc};

use crate::config::AccConfig;
use crate::diffpack::{write_diffpack, DiffpackPokeRequest, DiffpackPokeResponse};
use crate::gitops::{apply_patch_on_branch, PatchApplyRequest, PatchApplyResponse};
use crate::state::read_json;

#[derive(Clone)]
struct AppState {
    cfg: Arc<AccConfig>,
}

pub async fn run_server(cfg: AccConfig) -> Result<(), String> {
    let listen_addr = cfg.listen_addr.clone();
    let addr: SocketAddr = listen_addr
        .parse()
        .map_err(|e| format!("Invalid listen_addr: {e}"))?;

    let state = AppState { cfg: Arc::new(cfg) };

    let app = Router::new()
        .route("/status", get(status))
        .route("/diffpack/poke", post(diffpack_poke))
        .route("/patch/apply", post(patch_apply))
        .with_state(state);

    tracing::info!(%addr, "ACC HTTP server listening");

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|e| e.to_string())?;

    axum::serve(listener, app).await.map_err(|e| e.to_string())
}

async fn status(State(st): State<AppState>) -> impl IntoResponse {
    let providers_path = st.cfg.state_dir().join("PROVIDERS.json");
    let milestones_path = st.cfg.state_dir().join("MILESTONES.json");
    let system_status_path = st.cfg.state_dir().join("SYSTEM_STATUS.json");

    let providers: Value = read_json(&providers_path).unwrap_or_else(|e| json!({"error": e}));
    let milestones: Value = read_json(&milestones_path).unwrap_or_else(|e| json!({"error": e}));
    let system_status: Value = read_json(&system_status_path).unwrap_or_else(|e| json!({"error": e}));

    let body = json!({
        "ok": true,
        "listen_addr": st.cfg.listen_addr,
        "repo_root": st.cfg.repo_root,
        "providers": providers,
        "milestones": milestones,
        "system_status": system_status
    });

    (StatusCode::OK, Json(body))
}

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
