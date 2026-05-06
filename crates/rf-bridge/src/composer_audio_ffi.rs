//! AI Composer — Audio production FFI bridge.
//!
//! ## Functions
//!
//! Routing settings:
//! - `composer_audio_routing_get_json` → returns AudioRoutingTable JSON
//! - `composer_audio_routing_set_json` → updates routing
//! - `composer_audio_air_gapped` → switch routing to all-Local
//!
//! Audio credentials (separate from LLM credentials):
//! - `composer_audio_credential_put` (account: "elevenlabs" | "suno")
//! - `composer_audio_credential_delete`
//! - `composer_audio_credential_exists`
//!
//! Batch generation:
//! - `composer_audio_generate_json` → start a batch (non-blocking; returns job_id)
//! - `composer_audio_progress_json` → poll progress (UI calls every 200ms)
//! - `composer_audio_cancel` → request cancellation
//! - `composer_audio_last_result_json` → fetch final BatchOutput once active=false
//!
//! Memory:
//! - `composer_audio_free_string`

use std::ffi::{c_char, c_int, CStr, CString};
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use parking_lot::{Mutex, RwLock};
use rf_composer::{
    run_batch, AudioBackendId, AudioGenerator, AudioRoutingTable, BackendMap, BatchJob,
    BatchOutput, BatchProgress, CredentialStore, ElevenLabsBackend, KeychainStore, LocalBackend,
    ProgressHandle, SunoBackend,
};
use serde::{Deserialize, Serialize};
use tokio::runtime::Runtime;

// ─── Singletons ───────────────────────────────────────────────────────────────

static AUDIO_RUNTIME: OnceLock<Runtime> = OnceLock::new();
static AUDIO_STATE: OnceLock<AudioState> = OnceLock::new();

struct AudioState {
    routing: RwLock<AudioRoutingTable>,
    credentials: Arc<KeychainStore>,
    progress: Arc<ProgressHandle>,
    last_result: Mutex<Option<BatchOutput>>,
    last_error: Mutex<String>,
}

fn runtime() -> &'static Runtime {
    AUDIO_RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("rf-composer-audio")
            .build()
            .expect("failed to start audio tokio runtime")
    })
}

fn state() -> &'static AudioState {
    AUDIO_STATE.get_or_init(|| AudioState {
        routing: RwLock::new(AudioRoutingTable::defaults()),
        credentials: Arc::new(KeychainStore::new()),
        progress: ProgressHandle::new(),
        last_result: Mutex::new(None),
        last_error: Mutex::new(String::new()),
    })
}

fn set_error(msg: impl Into<String>) {
    *state().last_error.lock() = msg.into();
}

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

unsafe fn cstr_to_str<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

// ─── Routing ─────────────────────────────────────────────────────────────────

/// Return current routing table as JSON.
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_routing_get_json() -> *mut c_char {
    let r = state().routing.read().clone();
    json_to_c(serde_json::to_string(&r).unwrap_or_else(|_| "{}".to_string()))
}

/// Replace the routing table from JSON.
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_routing_set_json(payload: *const c_char) -> c_int {
    let s = match unsafe { cstr_to_str(payload) } {
        Some(s) => s,
        None => {
            set_error("routing_set_json: null payload");
            return -1;
        }
    };
    match serde_json::from_str::<AudioRoutingTable>(s) {
        Ok(r) => {
            *state().routing.write() = r;
            0
        }
        Err(e) => {
            set_error(format!("parse: {}", e));
            -1
        }
    }
}

/// Switch routing to all-Local (offline / air-gapped mode).
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_air_gapped() -> c_int {
    *state().routing.write() = AudioRoutingTable::air_gapped();
    0
}

// ─── Credentials ─────────────────────────────────────────────────────────────

#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_credential_put(
    account: *const c_char,
    secret: *const c_char,
) -> c_int {
    let a = match unsafe { cstr_to_str(account) } {
        Some(s) if !s.is_empty() => s,
        _ => {
            set_error("credential_put: invalid account");
            return -1;
        }
    };
    let v = match unsafe { cstr_to_str(secret) } {
        Some(s) => s,
        None => {
            set_error("credential_put: null secret");
            return -1;
        }
    };
    match state().credentials.put(a, v) {
        Ok(()) => 0,
        Err(e) => {
            set_error(format!("credential_put: {}", e));
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_credential_delete(account: *const c_char) -> c_int {
    let a = match unsafe { cstr_to_str(account) } {
        Some(s) if !s.is_empty() => s,
        _ => return -1,
    };
    match state().credentials.delete(a) {
        Ok(()) => 0,
        Err(e) => {
            set_error(format!("credential_delete: {}", e));
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_credential_exists(account: *const c_char) -> c_int {
    let a = match unsafe { cstr_to_str(account) } {
        Some(s) if !s.is_empty() => s,
        _ => return 0,
    };
    if state().credentials.exists(a) {
        1
    } else {
        0
    }
}

// ─── Batch generation ────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct BatchRequest {
    /// Output directory (project assets folder).
    out_dir: String,
    /// Pre-built ComposerOutput JSON containing the asset_map.
    #[serde(default)]
    composer_output: Option<serde_json::Value>,
    /// Or directly an asset map (alternative to composer_output).
    #[serde(default)]
    asset_map: Option<serde_json::Value>,
    /// Default voice ID for TTS.
    #[serde(default)]
    default_voice_id: Option<String>,
    /// Concurrency (defaults to 4).
    #[serde(default)]
    concurrency: Option<usize>,
}

#[derive(Serialize)]
struct StartResponse {
    accepted: bool,
    total: u32,
}

/// Start a batch generation. Returns immediately with `{accepted, total}` —
/// the actual work runs on the audio runtime. Caller polls
/// `composer_audio_progress_json` for updates.
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_generate_json(payload: *const c_char) -> *mut c_char {
    let s = match unsafe { cstr_to_str(payload) } {
        Some(s) => s,
        None => {
            set_error("generate_json: null payload");
            return std::ptr::null_mut();
        }
    };
    let req: BatchRequest = match serde_json::from_str(s) {
        Ok(r) => r,
        Err(e) => {
            set_error(format!("parse: {}", e));
            return std::ptr::null_mut();
        }
    };

    // Pull the StageAssetMap from either composer_output.asset_map or asset_map directly.
    let asset_map_value = req
        .composer_output
        .as_ref()
        .and_then(|v| v.get("asset_map").cloned())
        .or(req.asset_map.clone());

    let asset_map = match asset_map_value {
        Some(v) => match serde_json::from_value::<rf_composer::schema::StageAssetMap>(v) {
            Ok(m) => m,
            Err(e) => {
                set_error(format!("asset_map parse: {}", e));
                return std::ptr::null_mut();
            }
        },
        None => {
            set_error("missing asset_map / composer_output.asset_map");
            return std::ptr::null_mut();
        }
    };

    let total = asset_map.stages.iter().map(|s| s.assets.len()).sum::<usize>() as u32;

    let routing = state().routing.read().clone();
    let job = BatchJob {
        out_dir: PathBuf::from(req.out_dir),
        map: asset_map,
        routing: routing.clone(),
        default_voice_id: req.default_voice_id,
        concurrency: req
            .concurrency
            .unwrap_or(rf_composer::audio::DEFAULT_CONCURRENCY),
    };

    // Build only the backends actually referenced by the routing table.
    let mut backends = BackendMap::new();
    let needed: std::collections::HashSet<AudioBackendId> =
        routing.map.values().copied().collect();
    let creds = Arc::clone(&state().credentials);
    for id in needed {
        let r: Result<Arc<dyn AudioGenerator>, String> = match id {
            AudioBackendId::Elevenlabs => {
                let store: Arc<dyn rf_composer::CredentialStore> = creds.clone();
                ElevenLabsBackend::new(store)
                    .map(|b| Arc::new(b) as Arc<dyn AudioGenerator>)
                    .map_err(|e| e.to_string())
            }
            AudioBackendId::Suno => {
                let store: Arc<dyn rf_composer::CredentialStore> = creds.clone();
                SunoBackend::new(store)
                    .map(|b| Arc::new(b) as Arc<dyn AudioGenerator>)
                    .map_err(|e| e.to_string())
            }
            AudioBackendId::Local => Ok(Arc::new(LocalBackend::new()) as Arc<dyn AudioGenerator>),
        };
        match r {
            Ok(g) => {
                backends.insert(id, g);
            }
            Err(e) => {
                set_error(format!("backend {:?}: {}", id, e));
                return std::ptr::null_mut();
            }
        }
    }

    // Reset the shared progress handle and store None for last_result.
    state().progress.reset(total);
    *state().last_result.lock() = None;

    let progress = Arc::clone(&state().progress);
    runtime().spawn(async move {
        let res = run_batch(job, backends, Arc::clone(&progress)).await;
        match res {
            Ok(out) => {
                *state().last_result.lock() = Some(out);
            }
            Err(e) => {
                *state().last_error.lock() = format!("batch: {}", e);
            }
        }
    });

    let resp = StartResponse {
        accepted: true,
        total,
    };
    json_to_c(serde_json::to_string(&resp).unwrap_or_else(|_| "{}".to_string()))
}

/// Poll the progress handle. Returns BatchProgress JSON.
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_progress_json() -> *mut c_char {
    let snap: BatchProgress = state().progress.snapshot();
    json_to_c(serde_json::to_string(&snap).unwrap_or_else(|_| "{}".to_string()))
}

/// Request cancellation. In-flight HTTP requests may still finish.
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_cancel() -> c_int {
    state().progress.cancel();
    0
}

/// Fetch the last completed BatchOutput (or `{}` if none ready). Caller checks
/// `progress.active == false` first.
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_last_result_json() -> *mut c_char {
    let r = state().last_result.lock().clone();
    match r {
        Some(out) => json_to_c(serde_json::to_string(&out).unwrap_or_else(|_| "{}".to_string())),
        None => json_to_c("{}".to_string()),
    }
}

/// Last error message (empty string if none).
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_last_error_json() -> *mut c_char {
    let msg = state().last_error.lock().clone();
    json_to_c(msg)
}

/// Free a string returned by any composer_audio_* function.
#[unsafe(no_mangle)]
pub extern "C" fn composer_audio_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn routing_get_returns_default_json() {
        let raw = composer_audio_routing_get_json();
        assert!(!raw.is_null());
        let s = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
        composer_audio_free_string(raw);
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        assert!(v.is_object());
    }

    #[test]
    fn air_gapped_switches_routing() {
        // Save current routing.
        composer_audio_air_gapped();
        let raw = composer_audio_routing_get_json();
        let s = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
        composer_audio_free_string(raw);
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        let map = v.get("map").and_then(|m| m.as_object()).unwrap();
        for val in map.values() {
            assert_eq!(val.as_str().unwrap(), "local");
        }
    }

    #[test]
    fn progress_callable_when_idle() {
        let raw = composer_audio_progress_json();
        assert!(!raw.is_null());
        composer_audio_free_string(raw);
    }

    #[test]
    fn cancel_idempotent() {
        assert_eq!(composer_audio_cancel(), 0);
        assert_eq!(composer_audio_cancel(), 0);
    }
}
