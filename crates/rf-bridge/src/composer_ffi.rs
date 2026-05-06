//! AI Composer FFI — bridges `rf-composer` to Flutter.
//!
//! ## Functions
//!
//! Provider selection / settings:
//! - `composer_get_selection_json` → returns ProviderSelection JSON
//! - `composer_set_selection_json` → updates ProviderSelection from JSON
//! - `composer_describe_active_json` → returns AiProviderInfo (with health check)
//! - `composer_provider_options_json` → returns array of all 3 ProviderId labels
//!
//! Credentials (per-provider account names: "anthropic", "azure_openai"):
//! - `composer_credential_put` → store secret in OS keychain
//! - `composer_credential_delete` → remove secret
//! - `composer_credential_exists` → 1 if present, 0 otherwise
//!
//! Composer runs:
//! - `composer_run_json` → execute one ComposerJob, returns ComposerOutput JSON
//! - `composer_run_dry_json` → run a fast smoke test (just provider health check)
//!
//! Memory:
//! - `composer_free_string` → free any returned C string
//!
//! All blocking work runs on a private tokio runtime stored in OnceLock — safe
//! for repeat calls, no per-call runtime construction overhead.

use std::ffi::{c_char, c_int, CStr, CString};
use std::sync::{Arc, OnceLock};

use parking_lot::Mutex;
use rf_composer::{
    AiProviderId, ComposerJob, FluxComposer, KeychainStore, ProviderRegistry, ProviderSelection,
};
use rf_rgai::Jurisdiction;
use tokio::runtime::Runtime;

// ─── Singletons ───────────────────────────────────────────────────────────────

static COMPOSER_RUNTIME: OnceLock<Runtime> = OnceLock::new();
static COMPOSER_REGISTRY: OnceLock<Arc<ProviderRegistry>> = OnceLock::new();
/// Last error message (set by any FFI fn that fails). Caller can fetch with
/// `composer_last_error_json` for diagnostics.
static LAST_ERROR: OnceLock<Mutex<String>> = OnceLock::new();

fn runtime() -> &'static Runtime {
    COMPOSER_RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("rf-composer")
            .build()
            .expect("failed to start composer tokio runtime")
    })
}

fn registry() -> &'static Arc<ProviderRegistry> {
    COMPOSER_REGISTRY.get_or_init(|| {
        let store = Arc::new(KeychainStore::new());
        Arc::new(ProviderRegistry::new(ProviderSelection::default(), store))
    })
}

fn set_error(msg: impl Into<String>) {
    let cell = LAST_ERROR.get_or_init(|| Mutex::new(String::new()));
    *cell.lock() = msg.into();
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

// ─── Selection / Settings ────────────────────────────────────────────────────

/// Return current `ProviderSelection` as JSON. Caller MUST free with `composer_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn composer_get_selection_json() -> *mut c_char {
    let sel = registry().selection();
    let json = serde_json::to_string(&sel).unwrap_or_else(|_| "{}".to_string());
    json_to_c(json)
}

/// Replace the current selection from a JSON payload. Returns 0 on success, -1 on parse error.
#[unsafe(no_mangle)]
pub extern "C" fn composer_set_selection_json(payload: *const c_char) -> c_int {
    let s = match unsafe { cstr_to_str(payload) } {
        Some(s) => s,
        None => {
            set_error("composer_set_selection_json: null payload");
            return -1;
        }
    };
    match serde_json::from_str::<ProviderSelection>(s) {
        Ok(sel) => {
            registry().set_selection(sel);
            0
        }
        Err(e) => {
            set_error(format!("parse: {}", e));
            -1
        }
    }
}

/// Return `AiProviderInfo` JSON for the currently-selected provider, including
/// liveness check (this WILL hit the network on Anthropic/Azure).
#[unsafe(no_mangle)]
pub extern "C" fn composer_describe_active_json() -> *mut c_char {
    let info = runtime().block_on(async { registry().describe_active().await });
    json_to_c(serde_json::to_string(&info).unwrap_or_else(|_| "{}".to_string()))
}

/// Return JSON array of all selectable providers with their labels.
#[unsafe(no_mangle)]
pub extern "C" fn composer_provider_options_json() -> *mut c_char {
    let opts: Vec<serde_json::Value> = AiProviderId::all()
        .iter()
        .map(|id| {
            serde_json::json!({
                "id": id,
                "label": id.label(),
            })
        })
        .collect();
    json_to_c(serde_json::to_string(&opts).unwrap_or_else(|_| "[]".to_string()))
}

// ─── Credentials ──────────────────────────────────────────────────────────────

/// Store a secret. `account` is "anthropic" or "azure_openai". Returns 0 / -1.
#[unsafe(no_mangle)]
pub extern "C" fn composer_credential_put(
    account: *const c_char,
    secret: *const c_char,
) -> c_int {
    let account = match unsafe { cstr_to_str(account) } {
        Some(s) if !s.is_empty() => s,
        _ => {
            set_error("credential_put: invalid account");
            return -1;
        }
    };
    let secret = match unsafe { cstr_to_str(secret) } {
        Some(s) => s,
        None => {
            set_error("credential_put: null secret");
            return -1;
        }
    };
    match registry().credentials().put(account, secret) {
        Ok(()) => 0,
        Err(e) => {
            set_error(format!("credential_put: {}", e));
            -1
        }
    }
}

/// Delete a stored secret (idempotent — returns 0 even if absent).
#[unsafe(no_mangle)]
pub extern "C" fn composer_credential_delete(account: *const c_char) -> c_int {
    let account = match unsafe { cstr_to_str(account) } {
        Some(s) if !s.is_empty() => s,
        _ => return -1,
    };
    match registry().credentials().delete(account) {
        Ok(()) => 0,
        Err(e) => {
            set_error(format!("credential_delete: {}", e));
            -1
        }
    }
}

/// Returns 1 if a secret exists for the account, 0 otherwise.
#[unsafe(no_mangle)]
pub extern "C" fn composer_credential_exists(account: *const c_char) -> c_int {
    let account = match unsafe { cstr_to_str(account) } {
        Some(s) if !s.is_empty() => s,
        _ => return 0,
    };
    if registry().credentials().exists(account) {
        1
    } else {
        0
    }
}

// ─── Composer runs ────────────────────────────────────────────────────────────

/// Execute one ComposerJob. Payload is a JSON object:
/// ```json
/// {
///   "description": "Egyptian temple slot, 96% RTP",
///   "jurisdictions": ["UKGC", "MGA"],
///   "include_brief": true,
///   "include_voice_direction": true,
///   "include_quality_grade": true
/// }
/// ```
/// Returns ComposerOutput JSON or null on failure (use composer_last_error_json).
#[unsafe(no_mangle)]
pub extern "C" fn composer_run_json(payload: *const c_char) -> *mut c_char {
    let s = match unsafe { cstr_to_str(payload) } {
        Some(s) => s,
        None => {
            set_error("composer_run_json: null payload");
            return std::ptr::null_mut();
        }
    };

    // The Dart side sends jurisdictions as an array of codes ("UKGC"), not enum names.
    // Parse the loose shape, then map codes → Jurisdiction.
    #[derive(serde::Deserialize)]
    struct LoosePayload {
        description: String,
        jurisdictions: Vec<String>,
        #[serde(default = "yes")]
        include_brief: bool,
        #[serde(default = "yes")]
        include_voice_direction: bool,
        #[serde(default = "yes")]
        include_quality_grade: bool,
    }
    fn yes() -> bool {
        true
    }

    let loose: LoosePayload = match serde_json::from_str(s) {
        Ok(p) => p,
        Err(e) => {
            set_error(format!("composer_run_json parse: {}", e));
            return std::ptr::null_mut();
        }
    };

    let jurisdictions: Vec<Jurisdiction> = loose
        .jurisdictions
        .iter()
        .filter_map(|c| Jurisdiction::from_code(c))
        .collect();

    let job = ComposerJob {
        description: loose.description,
        jurisdictions,
        include_brief: loose.include_brief,
        include_voice_direction: loose.include_voice_direction,
        include_quality_grade: loose.include_quality_grade,
    };

    let provider = match registry().build() {
        Ok(p) => p,
        Err(e) => {
            set_error(format!("provider build: {}", e));
            return std::ptr::null_mut();
        }
    };
    let composer = FluxComposer::new(Arc::from(provider));

    match runtime().block_on(composer.run(job)) {
        Ok(out) => json_to_c(serde_json::to_string(&out).unwrap_or_else(|_| "{}".to_string())),
        Err(e) => {
            set_error(format!("composer.run: {}", e));
            std::ptr::null_mut()
        }
    }
}

/// Quick smoke test — just runs the active provider's health check.
/// Returns JSON `{ "healthy": true|false, "error": "...", "info": {...} }`.
#[unsafe(no_mangle)]
pub extern "C" fn composer_run_dry_json() -> *mut c_char {
    let info = runtime().block_on(async { registry().describe_active().await });
    let json = serde_json::json!({
        "healthy": info.healthy,
        "info": info,
    });
    json_to_c(json.to_string())
}

// ─── Diagnostics ──────────────────────────────────────────────────────────────

/// Return the last error message (string, may be empty). Always callable.
#[unsafe(no_mangle)]
pub extern "C" fn composer_last_error_json() -> *mut c_char {
    let cell = LAST_ERROR.get_or_init(|| Mutex::new(String::new()));
    let msg = cell.lock().clone();
    json_to_c(msg)
}

// ─── Memory management ───────────────────────────────────────────────────────

/// Free a string previously returned by any composer_* function.
#[unsafe(no_mangle)]
pub extern "C" fn composer_free_string(ptr: *mut c_char) {
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
    fn provider_options_returns_three() {
        let raw = composer_provider_options_json();
        assert!(!raw.is_null());
        let s = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
        composer_free_string(raw);
        let v: Vec<serde_json::Value> = serde_json::from_str(&s).unwrap();
        assert_eq!(v.len(), 3);
    }

    #[test]
    fn get_selection_returns_default_ollama() {
        let raw = composer_get_selection_json();
        assert!(!raw.is_null());
        let s = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
        composer_free_string(raw);
        let v: serde_json::Value = serde_json::from_str(&s).unwrap();
        assert_eq!(v["provider"], "ollama");
    }

    #[test]
    fn set_selection_with_invalid_json_returns_minus_one() {
        let bad = CString::new("{ not json").unwrap();
        let rc = composer_set_selection_json(bad.as_ptr());
        assert_eq!(rc, -1);
    }

    #[test]
    fn last_error_callable_when_empty() {
        let raw = composer_last_error_json();
        assert!(!raw.is_null());
        composer_free_string(raw);
    }

    #[test]
    fn credential_exists_with_null_returns_zero() {
        assert_eq!(composer_credential_exists(std::ptr::null()), 0);
    }
}
