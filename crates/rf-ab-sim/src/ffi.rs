//! FFI exports for batch simulation
//!
//! Provides async task API:
//! - `slot_lab_batch_sim_start(config_json)` → task_id (u64)
//! - `slot_lab_batch_sim_progress(task_id)` → f64 (0.0–1.0)
//! - `slot_lab_batch_sim_result(task_id)` → *mut c_char (JSON BatchSimResult)
//! - `slot_lab_batch_sim_cancel(task_id)` → void
//!
//! Task lifecycle:
//! 1. Dart calls `start` → gets task_id
//! 2. Background thread runs simulation, updates progress AtomicF64
//! 3. Dart polls `progress` until → 1.0
//! 4. Dart calls `result` → gets JSON result string (must free with slot_lab_free_string)
//! 5. Task automatically cleaned up after result is consumed

// NOTE: This module is included by rf-bridge/src/slot_lab_ffi.rs via include!()
// or as a separate FFI export. The actual #[no_mangle] functions are below.
// All types and dependencies come from the rf-ab-sim crate.

use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;

/// Task state
pub struct SimTask {
    pub progress: Arc<AtomicU64>, // Progress as f64 bits, use f64::from_bits()
    pub result: Arc<Mutex<Option<String>>>, // JSON result when done
    pub cancelled: Arc<std::sync::atomic::AtomicBool>,
}

/// Global task registry
static TASK_REGISTRY: LazyLock<Mutex<HashMap<u64, SimTask>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Task ID counter
static TASK_ID_COUNTER: AtomicU64 = AtomicU64::new(1);

/// Start a batch simulation.
/// Returns a task_id for polling.
pub fn batch_sim_start_impl(config_json: &str) -> u64 {
    use crate::config::BatchSimConfig;
    use crate::simulator::BatchSimulator;

    let config: BatchSimConfig = match serde_json::from_str(config_json) {
        Ok(c) => c,
        Err(e) => {
            log::warn!("batch_sim_start: invalid config JSON: {}", e);
            return 0; // 0 = error
        }
    };

    let task_id = TASK_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    let progress_atomic = Arc::new(AtomicU64::new(0f64.to_bits()));
    let result_mutex = Arc::new(Mutex::new(None::<String>));
    let cancelled = Arc::new(std::sync::atomic::AtomicBool::new(false));

    let task = SimTask {
        progress: Arc::clone(&progress_atomic),
        result: Arc::clone(&result_mutex),
        cancelled: Arc::clone(&cancelled),
    };

    {
        let mut registry = TASK_REGISTRY.lock().unwrap();
        registry.insert(task_id, task);
    }

    // Spawn background thread
    thread::spawn(move || {
        let progress_clone = Arc::clone(&progress_atomic);
        let cancelled_clone = Arc::clone(&cancelled);

        let result = BatchSimulator::run_with_progress(&config, move |frac| {
            if cancelled_clone.load(Ordering::Relaxed) {
                return;
            }
            progress_clone.store(frac.to_bits(), Ordering::Relaxed);
        });

        // Store result as JSON
        let json = match serde_json::to_string(&result) {
            Ok(j) => j,
            Err(e) => {
                log::warn!("batch_sim: failed to serialize result: {}", e);
                r#"{"error":"serialization_failed"}"#.to_string()
            }
        };

        if let Ok(mut guard) = result_mutex.lock() {
            *guard = Some(json);
        }
        // Mark as 100% done
        progress_atomic.store(1.0f64.to_bits(), Ordering::Relaxed);
    });

    task_id
}

/// Poll simulation progress (0.0–1.0)
pub fn batch_sim_progress_impl(task_id: u64) -> f64 {
    let registry = TASK_REGISTRY.lock().unwrap();
    if let Some(task) = registry.get(&task_id) {
        f64::from_bits(task.progress.load(Ordering::Relaxed))
    } else {
        -1.0 // Invalid task
    }
}

/// Get simulation result JSON string (returns None if not ready)
/// Task is removed from registry after result is consumed.
pub fn batch_sim_result_impl(task_id: u64) -> Option<String> {
    let mut registry = TASK_REGISTRY.lock().unwrap();
    if let Some(task) = registry.get(&task_id) {
        let guard = task.result.lock().unwrap();
        if guard.is_some() {
            drop(guard);
            // Remove task and return result
            if let Some(removed) = registry.remove(&task_id) {
                let guard = removed.result.lock().unwrap();
                return guard.clone();
            }
        }
    }
    None
}

/// Cancel a simulation task
pub fn batch_sim_cancel_impl(task_id: u64) {
    let registry = TASK_REGISTRY.lock().unwrap();
    if let Some(task) = registry.get(&task_id) {
        task.cancelled.store(true, Ordering::Relaxed);
    }
}
