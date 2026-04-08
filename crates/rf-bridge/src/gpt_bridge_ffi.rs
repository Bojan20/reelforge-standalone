// GPT Browser Bridge FFI — C ABI Functions for Flutter
//
// Exposes the WebSocket-based GPT bridge to Flutter via dart:ffi:
// - Check browser connection status
// - Send queries (user-initiated)
// - Poll for responses (JSON)
// - Configure the bridge at runtime
// - Clear conversation / shutdown

#![allow(clippy::not_unsafe_ptr_arg_deref)]

use crate::GPT_BRIDGE;
use rf_gpt_bridge::protocol::GptIntent;
use std::ffi::{CStr, CString, c_char};

// ═══════════════════════════════════════════════════════════════════════════
// STATUS & STATS
// ═══════════════════════════════════════════════════════════════════════════

/// Check if GPT Browser Bridge is ready (WebSocket server running).
/// Returns: 1 = ready, 0 = not ready.
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_is_ready() -> i32 {
    GPT_BRIDGE.get().map(|b| b.is_ready()).unwrap_or(false) as i32
}

/// Check if browser is currently connected.
/// Returns: 1 = connected, 0 = not connected.
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_browser_connected() -> i32 {
    GPT_BRIDGE.get().map(|b| b.is_browser_connected()).unwrap_or(false) as i32
}

/// Get GPT Bridge statistics as JSON string.
/// Caller must free the returned pointer with gpt_bridge_free_string().
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_stats_json() -> *mut c_char {
    let Some(bridge) = GPT_BRIDGE.get() else {
        return to_c_string("{}");
    };

    let stats = bridge.stats();
    let json = serde_json::json!({
        "total_requests": stats.total_requests,
        "total_responses": stats.total_responses,
        "total_errors": stats.total_errors,
        "browser_connected": stats.browser_connected,
        "browser_model": stats.browser_model,
        "ping_latency_ms": stats.ping_latency_ms,
        "conversation_exchanges": stats.conversation_exchanges,
        "decision": {
            "autonomous_queries": stats.decision_stats.autonomous_queries_sent,
            "user_queries": stats.decision_stats.user_queries_sent,
            "unknown_pattern_streak": stats.decision_stats.unknown_pattern_streak,
        }
    });

    to_c_string(&json.to_string())
}

// ═══════════════════════════════════════════════════════════════════════════
// SEND QUERIES
// ═══════════════════════════════════════════════════════════════════════════

/// Send a user-initiated query to ChatGPT via the browser bridge.
/// query: UTF-8 string — the question to ask ChatGPT.
/// context: UTF-8 string — additional context (can be empty).
/// intent: UTF-8 string — "analysis", "architecture", "debugging",
///         "code_review", "insight", "creative", or "user_query".
/// Returns: 1 = sent, 0 = failed (bridge not ready or browser not connected).
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_send_query(
    query: *const c_char,
    context: *const c_char,
    intent: *const c_char,
) -> i32 {
    let Some(bridge) = GPT_BRIDGE.get() else {
        log::warn!("GPT Bridge: not initialized");
        return 0;
    };

    let query_str = read_c_str(query).unwrap_or_default();
    let context_str = read_c_str(context).unwrap_or_default();
    let intent_str = read_c_str(intent).unwrap_or_default();

    if query_str.is_empty() {
        return 0;
    }

    let gpt_intent = parse_intent(&intent_str);
    bridge.send_query(&query_str, &context_str, gpt_intent, 0.8);
    log::info!("GPT Bridge: user query sent — intent={:?}", gpt_intent);
    1
}

// ═══════════════════════════════════════════════════════════════════════════
// POLL RESPONSES
// ═══════════════════════════════════════════════════════════════════════════

/// Drain all pending GPT responses as JSON array string.
/// Flutter should poll this periodically (e.g., every 500ms).
/// Returns JSON string: "[]" if no responses, or array of response objects.
/// Caller must free the returned pointer with gpt_bridge_free_string().
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_drain_responses_json() -> *mut c_char {
    let Some(bridge) = GPT_BRIDGE.get() else {
        return to_c_string("[]");
    };

    let payloads = bridge.drain_responses();
    if payloads.is_empty() {
        return to_c_string("[]");
    }

    let responses: Vec<serde_json::Value> = payloads
        .into_iter()
        .map(|p| {
            serde_json::json!({
                "request_id": p.response.request_id,
                "content": p.response.content,
                "model": p.response.model,
                "latency_ms": p.response.latency_ms,
                "from_browser": p.response.from_browser,
            })
        })
        .collect();

    let json = serde_json::to_string(&responses).unwrap_or_else(|_| "[]".into());
    to_c_string(&json)
}

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Update GPT Bridge configuration at runtime.
/// config_json: JSON string with fields to update (autonomous_enabled, etc.).
/// Returns: 1 = updated, 0 = failed.
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_update_config(config_json: *const c_char) -> i32 {
    let Some(bridge) = GPT_BRIDGE.get() else {
        return 0;
    };

    let json_str = match read_c_str(config_json) {
        Some(s) => s,
        None => return 0,
    };

    #[derive(serde::Deserialize)]
    struct ConfigPatch {
        autonomous_enabled: Option<bool>,
        min_query_interval_secs: Option<u64>,
        response_timeout_secs: Option<u64>,
        confidence_threshold: Option<f32>,
        quality_threshold: Option<f64>,
        max_pending_queries: Option<usize>,
        pipeline_enabled: Option<bool>,
        max_conversation_history: Option<usize>,
    }

    let Ok(patch) = serde_json::from_str::<ConfigPatch>(&json_str) else {
        log::warn!("GPT Bridge: invalid config JSON");
        return 0;
    };

    // Start from current config, not default — prevents data loss
    let mut config = bridge.current_config();

    if let Some(auto) = patch.autonomous_enabled {
        config.autonomous_enabled = auto;
    }
    if let Some(interval) = patch.min_query_interval_secs {
        config.min_query_interval_secs = interval;
    }
    if let Some(timeout) = patch.response_timeout_secs {
        config.response_timeout_secs = timeout;
    }
    if let Some(threshold) = patch.confidence_threshold {
        config.confidence_threshold = threshold;
    }
    if let Some(quality) = patch.quality_threshold {
        config.quality_threshold = quality;
    }
    if let Some(max) = patch.max_pending_queries {
        config.max_pending_queries = max;
    }
    if let Some(pipeline) = patch.pipeline_enabled {
        config.pipeline_enabled = pipeline;
    }
    if let Some(history) = patch.max_conversation_history {
        config.max_conversation_history = history;
    }

    bridge.update_config(config);
    log::info!("GPT Bridge: configuration updated");
    1
}

/// Clear GPT conversation memory and start new chat in browser.
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_clear_conversation() {
    if let Some(bridge) = GPT_BRIDGE.get() {
        bridge.clear_conversation();
        log::info!("GPT Bridge: conversation cleared + new chat requested");
    }
}

/// Shutdown GPT Bridge gracefully.
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_shutdown() {
    if let Some(bridge) = GPT_BRIDGE.get() {
        bridge.shutdown();
        log::info!("GPT Bridge: shut down");
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

/// Free a string returned by any gpt_bridge_* function.
/// Must be called for every *mut c_char returned by this module.
#[unsafe(no_mangle)]
pub extern "C" fn gpt_bridge_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)); }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS (internal)
// ═══════════════════════════════════════════════════════════════════════════

fn parse_intent(intent: &str) -> GptIntent {
    match intent {
        "analysis" => GptIntent::Analysis,
        "architecture" => GptIntent::Architecture,
        "debugging" => GptIntent::Debugging,
        "code_review" => GptIntent::CodeReview,
        "creative" => GptIntent::Creative,
        "insight" => GptIntent::Insight,
        _ => GptIntent::UserQuery,
    }
}

fn read_c_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string()) }
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}
