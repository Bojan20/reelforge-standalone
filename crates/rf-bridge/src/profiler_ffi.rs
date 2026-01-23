//! DSP Profiler FFI
//!
//! Real-time DSP performance profiling exposed to Flutter.
//! Tracks timing for each processing stage and provides statistics.

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

/// Maximum samples to keep in history
const MAX_HISTORY_SAMPLES: usize = 1000;

/// DSP processing stage
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DspStage {
    Input = 0,
    Mixing = 1,
    Effects = 2,
    Metering = 3,
    Output = 4,
    Total = 5,
}

/// Timing sample for a single audio block
#[derive(Debug, Clone, Copy, Default)]
pub struct DspTimingSample {
    pub input_us: u64,
    pub mixing_us: u64,
    pub effects_us: u64,
    pub metering_us: u64,
    pub output_us: u64,
    pub total_us: u64,
    pub block_size: u32,
    pub sample_rate: u32,
}

impl DspTimingSample {
    /// Calculate DSP load percentage based on available time
    pub fn load_percent(&self) -> f64 {
        if self.sample_rate == 0 || self.block_size == 0 {
            return 0.0;
        }
        let available_us = (self.block_size as f64 / self.sample_rate as f64) * 1_000_000.0;
        (self.total_us as f64 / available_us * 100.0).min(100.0)
    }
}

/// Profiler statistics
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct DspProfilerStats {
    pub avg_load_percent: f64,
    pub peak_load_percent: f64,
    pub min_load_percent: f64,
    pub avg_block_time_us: f64,
    pub overload_count: u32,
    pub total_samples: u32,
}

/// Global profiler state
struct ProfilerState {
    history: VecDeque<DspTimingSample>,
    current_sample: DspTimingSample,
    stage_start: Option<Instant>,
    enabled: bool,
    overload_count: AtomicUsize,
}

impl ProfilerState {
    fn new() -> Self {
        Self {
            history: VecDeque::with_capacity(MAX_HISTORY_SAMPLES),
            current_sample: DspTimingSample::default(),
            stage_start: None,
            enabled: true,
            overload_count: AtomicUsize::new(0),
        }
    }
}

static PROFILER: Lazy<RwLock<ProfilerState>> = Lazy::new(|| RwLock::new(ProfilerState::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// C FFI FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the profiler
#[unsafe(no_mangle)]
pub extern "C" fn profiler_init() {
    let mut state = PROFILER.write();
    state.history.clear();
    state.current_sample = DspTimingSample::default();
    state.enabled = true;
    state.overload_count = AtomicUsize::new(0);
}

/// Enable/disable profiling
#[unsafe(no_mangle)]
pub extern "C" fn profiler_set_enabled(enabled: bool) {
    PROFILER.write().enabled = enabled;
}

/// Check if profiling is enabled
#[unsafe(no_mangle)]
pub extern "C" fn profiler_is_enabled() -> bool {
    PROFILER.read().enabled
}

/// Start timing a stage (call from audio thread)
#[unsafe(no_mangle)]
pub extern "C" fn profiler_stage_begin(_stage: DspStage) {
    let mut state = PROFILER.write();
    if !state.enabled {
        return;
    }
    state.stage_start = Some(Instant::now());
}

/// End timing a stage (call from audio thread)
#[unsafe(no_mangle)]
pub extern "C" fn profiler_stage_end(stage: DspStage) {
    let mut state = PROFILER.write();
    if !state.enabled {
        return;
    }

    let elapsed_us = state.stage_start
        .map(|start| start.elapsed().as_micros() as u64)
        .unwrap_or(0);

    match stage {
        DspStage::Input => state.current_sample.input_us = elapsed_us,
        DspStage::Mixing => state.current_sample.mixing_us = elapsed_us,
        DspStage::Effects => state.current_sample.effects_us = elapsed_us,
        DspStage::Metering => state.current_sample.metering_us = elapsed_us,
        DspStage::Output => state.current_sample.output_us = elapsed_us,
        DspStage::Total => {
            state.current_sample.total_us = elapsed_us;
            // Check for overload (> 90% of available time)
            if state.current_sample.load_percent() > 90.0 {
                state.overload_count.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    state.stage_start = None;
}

/// Record a complete sample (call at end of each audio block)
#[unsafe(no_mangle)]
pub extern "C" fn profiler_record_sample(block_size: u32, sample_rate: u32) {
    let mut state = PROFILER.write();
    if !state.enabled {
        return;
    }

    state.current_sample.block_size = block_size;
    state.current_sample.sample_rate = sample_rate;

    // Calculate total if not set
    if state.current_sample.total_us == 0 {
        state.current_sample.total_us = state.current_sample.input_us
            + state.current_sample.mixing_us
            + state.current_sample.effects_us
            + state.current_sample.metering_us
            + state.current_sample.output_us;
    }

    // Add to history (clone sample before pushing to avoid borrow conflict)
    let sample = state.current_sample;
    if state.history.len() >= MAX_HISTORY_SAMPLES {
        state.history.pop_front();
    }
    state.history.push_back(sample);

    // Reset current sample
    state.current_sample = DspTimingSample::default();
}

/// Record a complete sample with all timings at once
#[unsafe(no_mangle)]
pub extern "C" fn profiler_record_full_sample(
    input_us: u64,
    mixing_us: u64,
    effects_us: u64,
    metering_us: u64,
    output_us: u64,
    block_size: u32,
    sample_rate: u32,
) {
    let mut state = PROFILER.write();
    if !state.enabled {
        return;
    }

    let total_us = input_us + mixing_us + effects_us + metering_us + output_us;
    let sample = DspTimingSample {
        input_us,
        mixing_us,
        effects_us,
        metering_us,
        output_us,
        total_us,
        block_size,
        sample_rate,
    };

    // Check for overload
    if sample.load_percent() > 90.0 {
        state.overload_count.fetch_add(1, Ordering::Relaxed);
    }

    // Add to history
    if state.history.len() >= MAX_HISTORY_SAMPLES {
        state.history.pop_front();
    }
    state.history.push_back(sample);
}

/// Get profiler statistics
#[unsafe(no_mangle)]
pub extern "C" fn profiler_get_stats(stats_out: *mut DspProfilerStats) {
    if stats_out.is_null() {
        return;
    }

    let state = PROFILER.read();

    if state.history.is_empty() {
        unsafe {
            *stats_out = DspProfilerStats::default();
        }
        return;
    }

    let mut sum_load = 0.0;
    let mut sum_time = 0.0;
    let mut peak_load = 0.0f64;
    let mut min_load = 100.0f64;

    for sample in state.history.iter() {
        let load = sample.load_percent();
        sum_load += load;
        sum_time += sample.total_us as f64;
        peak_load = peak_load.max(load);
        min_load = min_load.min(load);
    }

    let count = state.history.len() as f64;

    unsafe {
        *stats_out = DspProfilerStats {
            avg_load_percent: sum_load / count,
            peak_load_percent: peak_load,
            min_load_percent: min_load,
            avg_block_time_us: sum_time / count,
            overload_count: state.overload_count.load(Ordering::Relaxed) as u32,
            total_samples: state.history.len() as u32,
        };
    }
}

/// Get current DSP load percentage (0-100)
#[unsafe(no_mangle)]
pub extern "C" fn profiler_get_current_load() -> f64 {
    let state = PROFILER.read();
    state.history.back().map(|s| s.load_percent()).unwrap_or(0.0)
}

/// Get load history as JSON array
#[unsafe(no_mangle)]
pub extern "C" fn profiler_get_load_history_json(count: u32) -> *mut std::ffi::c_char {
    let state = PROFILER.read();

    let history: Vec<f64> = state.history
        .iter()
        .rev()
        .take(count as usize)
        .map(|s| s.load_percent())
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();

    let json = serde_json::to_string(&history).unwrap_or_else(|_| "[]".to_string());

    let c_str = std::ffi::CString::new(json).unwrap();
    c_str.into_raw()
}

/// Get current stage breakdown as JSON
#[unsafe(no_mangle)]
pub extern "C" fn profiler_get_stage_breakdown_json() -> *mut std::ffi::c_char {
    let state = PROFILER.read();

    let sample = state.history.back().cloned().unwrap_or_default();
    let total = sample.total_us.max(1) as f64;

    let breakdown = serde_json::json!({
        "input": sample.input_us as f64 / total * 100.0,
        "mixing": sample.mixing_us as f64 / total * 100.0,
        "effects": sample.effects_us as f64 / total * 100.0,
        "metering": sample.metering_us as f64 / total * 100.0,
        "output": sample.output_us as f64 / total * 100.0,
        "total_us": sample.total_us,
    });

    let json = serde_json::to_string(&breakdown).unwrap_or_else(|_| "{}".to_string());

    let c_str = std::ffi::CString::new(json).unwrap();
    c_str.into_raw()
}

/// Clear profiler history
#[unsafe(no_mangle)]
pub extern "C" fn profiler_clear() {
    let mut state = PROFILER.write();
    state.history.clear();
    state.overload_count = AtomicUsize::new(0);
}

/// Free a string allocated by profiler
#[unsafe(no_mangle)]
pub extern "C" fn profiler_free_string(ptr: *mut std::ffi::c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(std::ffi::CString::from_raw(ptr));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_profiler_basic() {
        profiler_init();

        // Record some samples
        for i in 0..10 {
            profiler_record_full_sample(
                100 + i * 10,  // input
                200 + i * 10,  // mixing
                300 + i * 10,  // effects
                50,            // metering
                100,           // output
                512,           // block_size
                48000,         // sample_rate
            );
        }

        let mut stats = DspProfilerStats::default();
        profiler_get_stats(&mut stats);

        assert_eq!(stats.total_samples, 10);
        assert!(stats.avg_load_percent > 0.0);
    }

    #[test]
    fn test_load_calculation() {
        let sample = DspTimingSample {
            total_us: 5333, // ~50% of 10.67ms (512 samples @ 48kHz)
            block_size: 512,
            sample_rate: 48000,
            ..Default::default()
        };

        let load = sample.load_percent();
        assert!(load > 45.0 && load < 55.0, "Load should be ~50%, got {}", load);
    }
}
