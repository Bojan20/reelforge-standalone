//! Ingest FFI — C bindings for rf-ingest crate
//!
//! Exposes EngineAdapter, AdapterRegistry, ingest layers, and Wizard to Flutter/Dart.
//!
//! ## Architecture
//! - AdapterRegistry holds registered adapters (thread-safe)
//! - Config-based adapters can be created from TOML/JSON
//! - Three ingest layers: DirectEvent, SnapshotDiff, RuleBased
//! - Wizard for automatic config generation from samples

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char};
use std::ptr;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use rf_ingest::adapter::ConfigBasedAdapter;
use rf_ingest::config::AdapterConfig;
use rf_ingest::layer_rules::RuleEngine;
use rf_ingest::registry::AdapterRegistry;
use rf_ingest::wizard::AdapterWizard;
use rf_ingest::{layer_event, layer_snapshot};
use rf_stage::StageTrace;
use serde_json::Value;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STORAGE
// ═══════════════════════════════════════════════════════════════════════════════

/// Global adapter registry
static REGISTRY: Lazy<RwLock<AdapterRegistry>> = Lazy::new(|| RwLock::new(AdapterRegistry::new()));

/// Wizard instances (wizard_id → AdapterWizard)
static WIZARDS: Lazy<RwLock<HashMap<u64, AdapterWizard>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Config storage (config_id → AdapterConfig)
static CONFIGS: Lazy<RwLock<HashMap<u64, AdapterConfig>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Rule engine instances (engine_id → RuleEngine)
static RULE_ENGINES: Lazy<RwLock<HashMap<u64, RuleEngine>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Next wizard ID
static NEXT_WIZARD_ID: AtomicU64 = AtomicU64::new(1);

/// Next config ID
static NEXT_CONFIG_ID: AtomicU64 = AtomicU64::new(1);

/// Next rule engine ID
static NEXT_RULE_ENGINE_ID: AtomicU64 = AtomicU64::new(1);

// ═══════════════════════════════════════════════════════════════════════════════
// ADAPTER REGISTRY API
// ═══════════════════════════════════════════════════════════════════════════════

/// Register an adapter from TOML config
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn ingest_register_adapter_toml(toml_config: *const c_char) -> i32 {
    if toml_config.is_null() {
        return 0;
    }

    let toml_str = match unsafe { CStr::from_ptr(toml_config) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config: AdapterConfig = match toml::from_str(toml_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("ingest_register_adapter_toml: parse error: {}", e);
            return 0;
        }
    };

    let adapter = ConfigBasedAdapter::new(config);
    REGISTRY.write().register(Arc::new(adapter));
    1
}

/// Register an adapter from JSON config
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn ingest_register_adapter_json(json_config: *const c_char) -> i32 {
    if json_config.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(json_config) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config: AdapterConfig = match serde_json::from_str(json_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("ingest_register_adapter_json: parse error: {}", e);
            return 0;
        }
    };

    let adapter = ConfigBasedAdapter::new(config);
    REGISTRY.write().register(Arc::new(adapter));
    1
}

/// Unregister an adapter
/// Returns 1 on success, 0 if not found
#[unsafe(no_mangle)]
pub extern "C" fn ingest_unregister_adapter(adapter_id: *const c_char) -> i32 {
    if adapter_id.is_null() {
        return 0;
    }

    let adapter_id_str = match unsafe { CStr::from_ptr(adapter_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    // remove() returns Option<Arc<dyn EngineAdapter>>
    if REGISTRY.write().remove(adapter_id_str).is_some() {
        1
    } else {
        0
    }
}

/// Get list of registered adapter IDs
/// Returns JSON array, caller must free with ingest_free_string
#[unsafe(no_mangle)]
pub extern "C" fn ingest_list_adapters() -> *mut c_char {
    let registry = REGISTRY.read();
    let ids: Vec<String> = registry.adapter_ids();

    match serde_json::to_string(&ids) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get adapter info as JSON
/// Returns JSON object with adapter details, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn ingest_get_adapter_info(adapter_id: *const c_char) -> *mut c_char {
    if adapter_id.is_null() {
        return ptr::null_mut();
    }

    let adapter_id_str = match unsafe { CStr::from_ptr(adapter_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let registry = REGISTRY.read();
    if let Some(adapter) = registry.get(adapter_id_str) {
        let info = serde_json::json!({
            "adapter_id": adapter.adapter_id(),
            "company_name": adapter.company_name(),
            "engine_name": adapter.engine_name(),
            "supported_layers": adapter.supported_layers().iter()
                .map(|l| format!("{:?}", l))
                .collect::<Vec<_>>(),
        });

        match serde_json::to_string(&info) {
            Ok(json) => match CString::new(json) {
                Ok(cs) => cs.into_raw(),
                Err(_) => ptr::null_mut(),
            },
            Err(_) => ptr::null_mut(),
        }
    } else {
        ptr::null_mut()
    }
}

/// Auto-detect adapter for a JSON sample
/// Returns adapter_id string if detected, null if not, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn ingest_detect_adapter(sample_json: *const c_char) -> *mut c_char {
    if sample_json.is_null() {
        return ptr::null_mut();
    }

    let json_str = match unsafe { CStr::from_ptr(sample_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let sample: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(_) => return ptr::null_mut(),
    };

    let registry = REGISTRY.read();
    if let Some(adapter) = registry.detect_adapter(&sample) {
        match CString::new(adapter.adapter_id()) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        }
    } else {
        ptr::null_mut()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INGEST API (Parse JSON → StageTrace)
// ═══════════════════════════════════════════════════════════════════════════════

/// Ingest JSON using a specific adapter
/// Returns trace_id from stage_ffi (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_parse_json(adapter_id: *const c_char, json_data: *const c_char) -> u64 {
    if adapter_id.is_null() || json_data.is_null() {
        return 0;
    }

    let adapter_id_str = match unsafe { CStr::from_ptr(adapter_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let json_str = match unsafe { CStr::from_ptr(json_data) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let json: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            log::error!("ingest_parse_json: JSON parse error: {}", e);
            return 0;
        }
    };

    let registry = REGISTRY.read();
    let adapter = match registry.get(adapter_id_str) {
        Some(a) => a,
        None => {
            log::error!("ingest_parse_json: adapter '{}' not found", adapter_id_str);
            return 0;
        }
    };

    match adapter.parse_json(&json) {
        Ok(trace) => {
            // Store trace in stage_ffi storage and return ID
            store_trace(trace)
        }
        Err(e) => {
            log::error!("ingest_parse_json: adapter error: {}", e);
            0
        }
    }
}

/// Ingest JSON using auto-detected adapter
/// Returns trace_id from stage_ffi (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_parse_json_auto(json_data: *const c_char) -> u64 {
    if json_data.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(json_data) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let json: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            log::error!("ingest_parse_json_auto: JSON parse error: {}", e);
            return 0;
        }
    };

    let registry = REGISTRY.read();
    let adapter = match registry.detect_adapter(&json) {
        Some(a) => a,
        None => {
            log::error!("ingest_parse_json_auto: no adapter detected");
            return 0;
        }
    };

    match adapter.parse_json(&json) {
        Ok(trace) => store_trace(trace),
        Err(e) => {
            log::error!("ingest_parse_json_auto: adapter error: {}", e);
            0
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER-SPECIFIC INGEST
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse JSON using Layer 1 (Direct Event) with a config
/// Returns trace_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_layer1_parse(json_data: *const c_char, config_id: u64) -> u64 {
    if json_data.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(json_data) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let json: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            log::error!("ingest_layer1_parse: JSON parse error: {}", e);
            return 0;
        }
    };

    let configs = CONFIGS.read();
    let config = match configs.get(&config_id) {
        Some(c) => c,
        None => {
            log::error!("ingest_layer1_parse: config {} not found", config_id);
            return 0;
        }
    };

    // layer_event::parse_with_config takes &Value directly
    match layer_event::parse_with_config(&json, config) {
        Ok(trace) => store_trace(trace),
        Err(e) => {
            log::error!("ingest_layer1_parse: parse error: {}", e);
            0
        }
    }
}

/// Parse JSON using Layer 2 (Snapshot Diff) with a config
/// Returns trace_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_layer2_parse(snapshots_json: *const c_char, config_id: u64) -> u64 {
    if snapshots_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(snapshots_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let snapshots: Vec<Value> = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            log::error!("ingest_layer2_parse: JSON parse error: {}", e);
            return 0;
        }
    };

    let configs = CONFIGS.read();
    let config = match configs.get(&config_id) {
        Some(c) => c,
        None => {
            log::error!("ingest_layer2_parse: config {} not found", config_id);
            return 0;
        }
    };

    // layer_snapshot::parse_snapshots returns Vec<StageEvent>
    match layer_snapshot::parse_snapshots(&snapshots, config) {
        Ok(stage_events) => {
            // Create trace and add events
            let mut trace = StageTrace::new("snapshot-trace", "snapshot-game");
            for event in stage_events {
                trace.push(event);
            }
            store_trace(trace)
        }
        Err(e) => {
            log::error!("ingest_layer2_parse: parse error: {}", e);
            0
        }
    }
}

/// Create a Rule Engine for Layer 3 processing
/// Returns rule_engine_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_layer3_create_engine() -> u64 {
    let engine = RuleEngine::new();
    let id = NEXT_RULE_ENGINE_ID.fetch_add(1, Ordering::Relaxed);
    RULE_ENGINES.write().insert(id, engine);
    id
}

/// Destroy a Rule Engine
#[unsafe(no_mangle)]
pub extern "C" fn ingest_layer3_destroy_engine(engine_id: u64) {
    RULE_ENGINES.write().remove(&engine_id);
}

/// Process a single data point through Rule Engine
/// Returns JSON array of derived StageEvents, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn ingest_layer3_process(
    engine_id: u64,
    json_data: *const c_char,
    timestamp_ms: f64,
) -> *mut c_char {
    if json_data.is_null() {
        return ptr::null_mut();
    }

    let json_str = match unsafe { CStr::from_ptr(json_data) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let json: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            log::error!("ingest_layer3_process: JSON parse error: {}", e);
            return ptr::null_mut();
        }
    };

    let mut engines = RULE_ENGINES.write();
    let engine = match engines.get_mut(&engine_id) {
        Some(e) => e,
        None => {
            log::error!("ingest_layer3_process: engine {} not found", engine_id);
            return ptr::null_mut();
        }
    };

    match engine.process(&json, timestamp_ms) {
        Ok(events) => match serde_json::to_string(&events) {
            Ok(json) => match CString::new(json) {
                Ok(cs) => cs.into_raw(),
                Err(_) => ptr::null_mut(),
            },
            Err(_) => ptr::null_mut(),
        },
        Err(e) => {
            log::error!("ingest_layer3_process: process error: {}", e);
            ptr::null_mut()
        }
    }
}

/// Reset a Rule Engine state
#[unsafe(no_mangle)]
pub extern "C" fn ingest_layer3_reset(engine_id: u64) {
    let mut engines = RULE_ENGINES.write();
    if let Some(engine) = engines.get_mut(&engine_id) {
        engine.reset();
    }
}

/// Get all detected stages from Rule Engine as JSON
/// Returns JSON array, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn ingest_layer3_get_stages(engine_id: u64) -> *mut c_char {
    let engines = RULE_ENGINES.read();
    let engine = match engines.get(&engine_id) {
        Some(e) => e,
        None => return ptr::null_mut(),
    };

    let stages = engine.get_detected_stages();
    match serde_json::to_string(&stages) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Build a StageTrace from Rule Engine's detected stages
/// Returns trace_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_layer3_build_trace(
    engine_id: u64,
    trace_id: *const c_char,
    game_id: *const c_char,
) -> u64 {
    if trace_id.is_null() || game_id.is_null() {
        return 0;
    }

    let trace_id_str = match unsafe { CStr::from_ptr(trace_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let game_id_str = match unsafe { CStr::from_ptr(game_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let engines = RULE_ENGINES.read();
    let engine = match engines.get(&engine_id) {
        Some(e) => e,
        None => return 0,
    };

    let mut trace = StageTrace::new(trace_id_str, game_id_str);
    for event in engine.get_detected_stages() {
        trace.push(event.clone());
    }

    store_trace(trace)
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Create an AdapterConfig from JSON
/// Returns config_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_create_json(json_config: *const c_char) -> u64 {
    if json_config.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(json_config) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config: AdapterConfig = match serde_json::from_str(json_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("ingest_config_create_json: parse error: {}", e);
            return 0;
        }
    };

    let id = NEXT_CONFIG_ID.fetch_add(1, Ordering::Relaxed);
    CONFIGS.write().insert(id, config);
    id
}

/// Create an AdapterConfig from TOML
/// Returns config_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_create_toml(toml_config: *const c_char) -> u64 {
    if toml_config.is_null() {
        return 0;
    }

    let toml_str = match unsafe { CStr::from_ptr(toml_config) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config: AdapterConfig = match toml::from_str(toml_str) {
        Ok(c) => c,
        Err(e) => {
            log::error!("ingest_config_create_toml: parse error: {}", e);
            return 0;
        }
    };

    let id = NEXT_CONFIG_ID.fetch_add(1, Ordering::Relaxed);
    CONFIGS.write().insert(id, config);
    id
}

/// Create a default AdapterConfig
/// Returns config_id
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_create_default() -> u64 {
    let config = AdapterConfig::default();
    let id = NEXT_CONFIG_ID.fetch_add(1, Ordering::Relaxed);
    CONFIGS.write().insert(id, config);
    id
}

/// Create an AdapterConfig with basic info
/// Returns config_id
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_create(
    adapter_id: *const c_char,
    company_name: *const c_char,
    engine_name: *const c_char,
) -> u64 {
    if adapter_id.is_null() || company_name.is_null() || engine_name.is_null() {
        return 0;
    }

    let adapter_id_str = match unsafe { CStr::from_ptr(adapter_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let company_str = match unsafe { CStr::from_ptr(company_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let engine_str = match unsafe { CStr::from_ptr(engine_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let config = AdapterConfig::new(adapter_id_str, company_str, engine_str);
    let id = NEXT_CONFIG_ID.fetch_add(1, Ordering::Relaxed);
    CONFIGS.write().insert(id, config);
    id
}

/// Destroy an AdapterConfig
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_destroy(config_id: u64) {
    CONFIGS.write().remove(&config_id);
}

/// Get config as JSON
/// Caller must free with ingest_free_string
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_to_json(config_id: u64) -> *mut c_char {
    let configs = CONFIGS.read();
    if let Some(config) = configs.get(&config_id) {
        match serde_json::to_string_pretty(config) {
            Ok(json) => match CString::new(json) {
                Ok(cs) => cs.into_raw(),
                Err(_) => ptr::null_mut(),
            },
            Err(_) => ptr::null_mut(),
        }
    } else {
        ptr::null_mut()
    }
}

/// Get config as TOML
/// Caller must free with ingest_free_string
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_to_toml(config_id: u64) -> *mut c_char {
    let configs = CONFIGS.read();
    if let Some(config) = configs.get(&config_id) {
        match toml::to_string_pretty(config) {
            Ok(toml_str) => match CString::new(toml_str) {
                Ok(cs) => cs.into_raw(),
                Err(_) => ptr::null_mut(),
            },
            Err(_) => ptr::null_mut(),
        }
    } else {
        ptr::null_mut()
    }
}

/// Add event mapping to config
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_add_event_mapping(
    config_id: u64,
    event_name: *const c_char,
    stage_name: *const c_char,
) -> i32 {
    if event_name.is_null() || stage_name.is_null() {
        return 0;
    }

    let event_str = match unsafe { CStr::from_ptr(event_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let stage_str = match unsafe { CStr::from_ptr(stage_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let mut configs = CONFIGS.write();
    if let Some(config) = configs.get_mut(&config_id) {
        config.map_event(event_str, stage_str);
        1
    } else {
        0
    }
}

/// Set payload path in config
/// path_type: "events", "event_name", "timestamp", "win_amount", "bet_amount", "reel_data", "feature", "symbol"
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_set_payload_path(
    config_id: u64,
    path_type: *const c_char,
    json_path: *const c_char,
) -> i32 {
    if path_type.is_null() || json_path.is_null() {
        return 0;
    }

    let path_type_str = match unsafe { CStr::from_ptr(path_type) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let path_str = match unsafe { CStr::from_ptr(json_path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let mut configs = CONFIGS.write();
    if let Some(config) = configs.get_mut(&config_id) {
        match path_type_str {
            "events" => config.payload_paths.events_path = Some(path_str),
            "event_name" => config.payload_paths.event_name_path = Some(path_str),
            "timestamp" => config.payload_paths.timestamp_path = Some(path_str),
            "win_amount" => config.payload_paths.win_amount_path = Some(path_str),
            "bet_amount" => config.payload_paths.bet_amount_path = Some(path_str),
            "reel_data" => config.payload_paths.reel_data_path = Some(path_str),
            "feature" => config.payload_paths.feature_path = Some(path_str),
            "symbol" => config.payload_paths.symbol_path = Some(path_str),
            _ => return 0,
        }
        1
    } else {
        0
    }
}

/// Set snapshot path in config (for Layer 2)
/// path_type: "reels", "win", "feature_active", "balance"
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_set_snapshot_path(
    config_id: u64,
    path_type: *const c_char,
    json_path: *const c_char,
) -> i32 {
    if path_type.is_null() || json_path.is_null() {
        return 0;
    }

    let path_type_str = match unsafe { CStr::from_ptr(path_type) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let path_str = match unsafe { CStr::from_ptr(json_path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let mut configs = CONFIGS.write();
    if let Some(config) = configs.get_mut(&config_id) {
        match path_type_str {
            "reels" => config.snapshot_paths.reels_path = Some(path_str),
            "win" => config.snapshot_paths.win_path = Some(path_str),
            "feature_active" => config.snapshot_paths.feature_active_path = Some(path_str),
            "balance" => config.snapshot_paths.balance_path = Some(path_str),
            _ => return 0,
        }
        1
    } else {
        0
    }
}

/// Set big win thresholds in config
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_set_bigwin_thresholds(
    config_id: u64,
    win: f64,
    big_win: f64,
    mega_win: f64,
    epic_win: f64,
    ultra_win: f64,
) -> i32 {
    let mut configs = CONFIGS.write();
    if let Some(config) = configs.get_mut(&config_id) {
        config.bigwin_thresholds.win = win;
        config.bigwin_thresholds.big_win = big_win;
        config.bigwin_thresholds.mega_win = mega_win;
        config.bigwin_thresholds.epic_win = epic_win;
        config.bigwin_thresholds.ultra_win = ultra_win;
        1
    } else {
        0
    }
}

/// Validate a config
/// Returns 1 if valid, 0 if invalid
#[unsafe(no_mangle)]
pub extern "C" fn ingest_config_validate(config_id: u64) -> i32 {
    let configs = CONFIGS.read();
    if let Some(config) = configs.get(&config_id) {
        if config.validate().is_ok() { 1 } else { 0 }
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIZARD API
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a new wizard instance
/// Returns wizard_id
#[unsafe(no_mangle)]
pub extern "C" fn ingest_wizard_create() -> u64 {
    let wizard = AdapterWizard::new();
    let id = NEXT_WIZARD_ID.fetch_add(1, Ordering::Relaxed);
    WIZARDS.write().insert(id, wizard);
    id
}

/// Destroy a wizard instance
#[unsafe(no_mangle)]
pub extern "C" fn ingest_wizard_destroy(wizard_id: u64) {
    WIZARDS.write().remove(&wizard_id);
}

/// Add a sample to the wizard
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn ingest_wizard_add_sample(wizard_id: u64, sample_json: *const c_char) -> i32 {
    if sample_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(sample_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let sample: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            log::error!("ingest_wizard_add_sample: parse error: {}", e);
            return 0;
        }
    };

    let mut wizards = WIZARDS.write();
    if let Some(wizard) = wizards.get_mut(&wizard_id) {
        wizard.add_sample(sample);
        1
    } else {
        0
    }
}

/// Add multiple samples to the wizard
/// samples_json should be a JSON array
/// Returns number of samples added (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_wizard_add_samples(wizard_id: u64, samples_json: *const c_char) -> i32 {
    if samples_json.is_null() {
        return 0;
    }

    let json_str = match unsafe { CStr::from_ptr(samples_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let samples: Vec<Value> = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            log::error!("ingest_wizard_add_samples: parse error: {}", e);
            return 0;
        }
    };

    let count = samples.len() as i32;

    let mut wizards = WIZARDS.write();
    if let Some(wizard) = wizards.get_mut(&wizard_id) {
        wizard.add_samples(samples);
        count
    } else {
        0
    }
}

/// Clear all samples from the wizard
#[unsafe(no_mangle)]
pub extern "C" fn ingest_wizard_clear_samples(wizard_id: u64) {
    let mut wizards = WIZARDS.write();
    if let Some(wizard) = wizards.get_mut(&wizard_id) {
        wizard.clear_samples();
    }
}

/// Run wizard analysis
/// Returns JSON WizardResult, caller must free with ingest_free_string
#[unsafe(no_mangle)]
pub extern "C" fn ingest_wizard_analyze(wizard_id: u64) -> *mut c_char {
    let wizards = WIZARDS.read();
    let wizard = match wizards.get(&wizard_id) {
        Some(w) => w,
        None => return ptr::null_mut(),
    };

    match wizard.analyze() {
        Ok(result) => match serde_json::to_string(&result) {
            Ok(json) => match CString::new(json) {
                Ok(cs) => cs.into_raw(),
                Err(_) => ptr::null_mut(),
            },
            Err(_) => ptr::null_mut(),
        },
        Err(e) => {
            log::error!("ingest_wizard_analyze: error: {}", e);
            ptr::null_mut()
        }
    }
}

/// Run wizard analysis and get generated config
/// Returns config_id (0 on error)
#[unsafe(no_mangle)]
pub extern "C" fn ingest_wizard_generate_config(wizard_id: u64) -> u64 {
    let wizards = WIZARDS.read();
    let wizard = match wizards.get(&wizard_id) {
        Some(w) => w,
        None => return 0,
    };

    match wizard.analyze() {
        Ok(result) => {
            let id = NEXT_CONFIG_ID.fetch_add(1, Ordering::Relaxed);
            CONFIGS.write().insert(id, result.config);
            id
        }
        Err(e) => {
            log::error!("ingest_wizard_generate_config: error: {}", e);
            0
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string allocated by this module
#[unsafe(no_mangle)]
pub extern "C" fn ingest_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Get supported ingest layers as JSON array
/// Caller must free
#[unsafe(no_mangle)]
pub extern "C" fn ingest_get_layers() -> *mut c_char {
    let layers = vec!["DirectEvent", "SnapshotDiff", "RuleBased"];
    match serde_json::to_string(&layers) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Validate a JSON event structure
/// Returns JSON validation result, caller must free
#[unsafe(no_mangle)]
pub extern "C" fn ingest_validate_json(json_data: *const c_char) -> *mut c_char {
    if json_data.is_null() {
        return ptr::null_mut();
    }

    let json_str = match unsafe { CStr::from_ptr(json_data) }.to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let json: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(e) => {
            let result = serde_json::json!({
                "valid": false,
                "error": format!("JSON parse error: {}", e),
                "has_type_field": false,
                "is_array": false,
            });
            match serde_json::to_string(&result) {
                Ok(json) => match CString::new(json) {
                    Ok(cs) => return cs.into_raw(),
                    Err(_) => return ptr::null_mut(),
                },
                Err(_) => return ptr::null_mut(),
            }
        }
    };

    let is_array = json.is_array();
    let sample = if is_array {
        json.as_array().and_then(|a| a.first()).cloned()
    } else {
        Some(json.clone())
    };

    let has_type_field = sample
        .as_ref()
        .and_then(|v| v.as_object())
        .map(|obj| {
            obj.contains_key("type")
                || obj.contains_key("event")
                || obj.contains_key("eventType")
                || obj.contains_key("event_type")
                || obj.contains_key("name")
        })
        .unwrap_or(false);

    let result = serde_json::json!({
        "valid": true,
        "is_array": is_array,
        "has_type_field": has_type_field,
        "item_count": if is_array { json.as_array().map(|a| a.len()).unwrap_or(0) } else { 1 },
    });

    match serde_json::to_string(&result) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(_) => ptr::null_mut(),
    }
}

/// Get adapter count
#[unsafe(no_mangle)]
pub extern "C" fn ingest_adapter_count() -> u64 {
    REGISTRY.read().len() as u64
}

/// Check if an adapter exists
/// Returns 1 if exists, 0 otherwise
#[unsafe(no_mangle)]
pub extern "C" fn ingest_adapter_exists(adapter_id: *const c_char) -> i32 {
    if adapter_id.is_null() {
        return 0;
    }

    let adapter_id_str = match unsafe { CStr::from_ptr(adapter_id) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    if REGISTRY.read().contains(adapter_id_str) {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Store a trace in the global stage_ffi storage
/// This connects ingest_ffi to stage_ffi
fn store_trace(trace: StageTrace) -> u64 {
    // Use the stage_ffi's storage via its public API
    let json = match serde_json::to_string(&trace) {
        Ok(j) => j,
        Err(_) => return 0,
    };

    let cstr = match CString::new(json) {
        Ok(c) => c,
        Err(_) => return 0,
    };

    // Call stage_trace_from_json to store in stage_ffi
    crate::stage_ffi::stage_trace_from_json(cstr.as_ptr())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_lifecycle() {
        let config_id = ingest_config_create_default();
        assert!(config_id > 0);

        ingest_config_destroy(config_id);
    }

    #[test]
    fn test_wizard_lifecycle() {
        let wizard_id = ingest_wizard_create();
        assert!(wizard_id > 0);

        let sample = r#"{"type": "spin_start", "balance": 100}"#;
        let cstr = CString::new(sample).unwrap();
        let result = ingest_wizard_add_sample(wizard_id, cstr.as_ptr());
        assert_eq!(result, 1);

        ingest_wizard_destroy(wizard_id);
    }

    #[test]
    fn test_validate_json() {
        let valid_json = r#"{"type": "spin_start"}"#;
        let cstr = CString::new(valid_json).unwrap();
        let result = ingest_validate_json(cstr.as_ptr());
        assert!(!result.is_null());

        unsafe {
            let result_str = CStr::from_ptr(result).to_str().unwrap();
            let parsed: Value = serde_json::from_str(result_str).unwrap();
            assert_eq!(parsed["valid"], true);
            assert_eq!(parsed["has_type_field"], true);
            ingest_free_string(result);
        }
    }

    #[test]
    fn test_rule_engine_lifecycle() {
        let engine_id = ingest_layer3_create_engine();
        assert!(engine_id > 0);

        ingest_layer3_destroy_engine(engine_id);
    }
}
