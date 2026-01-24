//! Offline DSP Processing FFI Bridge
//!
//! Exposes rf-offline functionality to Dart for:
//! - Bounce/mixdown operations
//! - Batch processing
//! - Normalization
//! - Format conversion

use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use dashmap::DashMap;
use once_cell::sync::Lazy;
use parking_lot::RwLock;

use rf_offline::{
    BatchProcessor, JobBuilder, JobResult, NormalizationMode, OfflineConfig,
    OfflinePipeline, OutputFormat, PipelineState,
};

// ═══════════════════════════════════════════════════════════════════════════════
// STORAGE
// ═══════════════════════════════════════════════════════════════════════════════

/// Job ID counter
static JOB_ID: AtomicU64 = AtomicU64::new(1);

/// Active pipelines storage
static PIPELINES: Lazy<DashMap<u64, Arc<RwLock<OfflinePipeline>>>> = Lazy::new(DashMap::new);

/// Job results storage
static JOB_RESULTS: Lazy<DashMap<u64, JobResult>> = Lazy::new(DashMap::new);

/// Last error message
static LAST_ERROR: Lazy<RwLock<Option<String>>> = Lazy::new(|| RwLock::new(None));

fn set_error(msg: &str) {
    *LAST_ERROR.write() = Some(msg.to_string());
}

fn clear_error() {
    *LAST_ERROR.write() = None;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a new offline pipeline
/// Returns pipeline handle (>0) or 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_create() -> u64 {
    clear_error();

    let config = OfflineConfig::default();
    let pipeline = OfflinePipeline::new(config);
    let handle = JOB_ID.fetch_add(1, Ordering::Relaxed);

    PIPELINES.insert(handle, Arc::new(RwLock::new(pipeline)));
    handle
}

/// Create a pipeline with custom config
/// config_json: JSON string with OfflineConfig
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_create_with_config(config_json: *const c_char) -> u64 {
    clear_error();

    let config = if config_json.is_null() {
        OfflineConfig::default()
    } else {
        let c_str = unsafe { CStr::from_ptr(config_json) };
        match c_str.to_str() {
            Ok(s) => serde_json::from_str(s).unwrap_or_default(),
            Err(_) => OfflineConfig::default(),
        }
    };

    let pipeline = OfflinePipeline::new(config);
    let handle = JOB_ID.fetch_add(1, Ordering::Relaxed);

    PIPELINES.insert(handle, Arc::new(RwLock::new(pipeline)));
    handle
}

/// Destroy a pipeline
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_destroy(handle: u64) {
    PIPELINES.remove(&handle);
}

/// Set normalization mode for pipeline
/// mode: 0=None, 1=Peak, 2=LUFS, 3=TruePeak
/// target: target level in dB (for Peak/TruePeak) or LUFS
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_set_normalization(handle: u64, mode: i32, target: f64) {
    if let Some(pipeline) = PIPELINES.get(&handle) {
        let norm_mode = match mode {
            1 => Some(NormalizationMode::Peak { target_db: target }),
            2 => Some(NormalizationMode::Lufs { target_lufs: target }),
            3 => Some(NormalizationMode::TruePeak { target_db: target }),
            4 => Some(NormalizationMode::NoClip),
            _ => None,
        };

        if let Some(mode) = norm_mode {
            let mut p = pipeline.write();
            *p = OfflinePipeline::new(OfflineConfig::default()).with_normalization(mode);
        }
    }
}

/// Set output format for pipeline
/// format: 0=WAV16, 1=WAV24, 2=WAV32F, 3=FLAC, 4=MP3_320
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_set_format(handle: u64, format: i32) {
    if let Some(pipeline) = PIPELINES.get(&handle) {
        let output_format = match format {
            0 => OutputFormat::wav_16(),
            1 => OutputFormat::wav_24(),
            2 => OutputFormat::wav_32f(),
            3 => OutputFormat::flac(),
            4 => OutputFormat::mp3_320(),
            _ => OutputFormat::wav_24(),
        };

        let mut p = pipeline.write();
        *p = OfflinePipeline::new(OfflineConfig::default()).with_output_format(output_format);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// JOB PROCESSING
// ═══════════════════════════════════════════════════════════════════════════════

/// Process a single file
/// Returns job ID (>0) or 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn offline_process_file(
    handle: u64,
    input_path: *const c_char,
    output_path: *const c_char,
) -> u64 {
    clear_error();

    if input_path.is_null() || output_path.is_null() {
        set_error("Input or output path is null");
        return 0;
    }

    let input = unsafe { CStr::from_ptr(input_path) };
    let output = unsafe { CStr::from_ptr(output_path) };

    let input_str = match input.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid input path encoding");
            return 0;
        }
    };

    let output_str = match output.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid output path encoding");
            return 0;
        }
    };

    let job = match JobBuilder::new()
        .input(input_str)
        .output(output_str)
        .build()
    {
        Ok(j) => j,
        Err(e) => {
            set_error(&e.to_string());
            return 0;
        }
    };

    let job_id = job.id;

    if let Some(pipeline) = PIPELINES.get(&handle) {
        let mut p = pipeline.write();
        match p.process_job(&job) {
            Ok(result) => {
                JOB_RESULTS.insert(job_id, result);
                job_id
            }
            Err(e) => {
                set_error(&e.to_string());
                0
            }
        }
    } else {
        set_error("Pipeline not found");
        0
    }
}

/// Process a file with full options (JSON config)
#[unsafe(no_mangle)]
pub extern "C" fn offline_process_file_with_options(
    handle: u64,
    options_json: *const c_char,
) -> u64 {
    clear_error();

    if options_json.is_null() {
        set_error("Options JSON is null");
        return 0;
    }

    let c_str = unsafe { CStr::from_ptr(options_json) };
    let options_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid options encoding");
            return 0;
        }
    };

    // Parse options
    #[derive(serde::Deserialize)]
    struct ProcessOptions {
        input_path: String,
        output_path: String,
        sample_rate: Option<u32>,
        normalize_mode: Option<i32>,
        normalize_target: Option<f64>,
        fade_in_samples: Option<u64>,
        fade_out_samples: Option<u64>,
        format: Option<i32>,
    }

    let opts: ProcessOptions = match serde_json::from_str(options_str) {
        Ok(o) => o,
        Err(e) => {
            set_error(&format!("Failed to parse options: {}", e));
            return 0;
        }
    };

    let mut builder = JobBuilder::new()
        .input(&opts.input_path)
        .output(&opts.output_path);

    if let Some(rate) = opts.sample_rate {
        builder = builder.sample_rate(rate);
    }

    if let Some(fade_in) = opts.fade_in_samples {
        builder = builder.fade_in(fade_in);
    }

    if let Some(fade_out) = opts.fade_out_samples {
        builder = builder.fade_out(fade_out);
    }

    if let (Some(mode), Some(target)) = (opts.normalize_mode, opts.normalize_target) {
        let norm = match mode {
            1 => NormalizationMode::Peak { target_db: target },
            2 => NormalizationMode::Lufs { target_lufs: target },
            3 => NormalizationMode::TruePeak { target_db: target },
            _ => NormalizationMode::NoClip,
        };
        builder = builder.normalize(norm);
    }

    let job = match builder.build() {
        Ok(j) => j,
        Err(e) => {
            set_error(&e.to_string());
            return 0;
        }
    };

    let job_id = job.id;

    if let Some(pipeline) = PIPELINES.get(&handle) {
        let mut p = pipeline.write();
        match p.process_job(&job) {
            Ok(result) => {
                JOB_RESULTS.insert(job_id, result);
                job_id
            }
            Err(e) => {
                set_error(&e.to_string());
                0
            }
        }
    } else {
        set_error("Pipeline not found");
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROGRESS & STATUS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get pipeline progress (0.0 - 1.0)
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_get_progress(handle: u64) -> f64 {
    if let Some(pipeline) = PIPELINES.get(&handle) {
        let p = pipeline.read();
        p.progress().overall_progress
    } else {
        0.0
    }
}

/// Get pipeline state
/// Returns: 0=Idle, 1=Loading, 2=Analyzing, 3=Processing, 4=Normalizing,
///          5=Converting, 6=Encoding, 7=Writing, 8=Complete, 9=Failed, 10=Cancelled
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_get_state(handle: u64) -> i32 {
    if let Some(pipeline) = PIPELINES.get(&handle) {
        let p = pipeline.read();
        match p.state() {
            PipelineState::Idle => 0,
            PipelineState::Loading => 1,
            PipelineState::Analyzing => 2,
            PipelineState::Processing => 3,
            PipelineState::Normalizing => 4,
            PipelineState::Converting => 5,
            PipelineState::Encoding => 6,
            PipelineState::Writing => 7,
            PipelineState::Complete => 8,
            PipelineState::Failed => 9,
            PipelineState::Cancelled => 10,
        }
    } else {
        -1
    }
}

/// Get progress as JSON
/// Returns allocated string (caller must free with offline_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_get_progress_json(handle: u64) -> *mut c_char {
    if let Some(pipeline) = PIPELINES.get(&handle) {
        let p = pipeline.read();
        let progress = p.progress();

        #[derive(serde::Serialize)]
        struct ProgressJson {
            state: String,
            stage: String,
            stage_progress: f64,
            overall_progress: f64,
            samples_processed: u64,
            total_samples: u64,
            elapsed_ms: u64,
            estimated_remaining_ms: Option<u64>,
        }

        let json = ProgressJson {
            state: format!("{:?}", progress.state),
            stage: progress.current_stage.clone(),
            stage_progress: progress.stage_progress,
            overall_progress: progress.overall_progress,
            samples_processed: progress.samples_processed,
            total_samples: progress.total_samples,
            elapsed_ms: progress.elapsed_ms,
            estimated_remaining_ms: progress.estimated_remaining_ms,
        };

        match serde_json::to_string(&json) {
            Ok(s) => {
                match CString::new(s) {
                    Ok(c) => c.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            }
            Err(_) => ptr::null_mut(),
        }
    } else {
        ptr::null_mut()
    }
}

/// Cancel pipeline processing
#[unsafe(no_mangle)]
pub extern "C" fn offline_pipeline_cancel(handle: u64) {
    if let Some(pipeline) = PIPELINES.get(&handle) {
        let p = pipeline.read();
        p.cancel();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// JOB RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get job result as JSON
/// Returns allocated string (caller must free with offline_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_job_result(job_id: u64) -> *mut c_char {
    if let Some(result) = JOB_RESULTS.get(&job_id) {
        match serde_json::to_string(result.value()) {
            Ok(s) => {
                match CString::new(s) {
                    Ok(c) => c.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            }
            Err(_) => ptr::null_mut(),
        }
    } else {
        ptr::null_mut()
    }
}

/// Check if job completed successfully
#[unsafe(no_mangle)]
pub extern "C" fn offline_job_succeeded(job_id: u64) -> bool {
    if let Some(result) = JOB_RESULTS.get(&job_id) {
        matches!(result.status, rf_offline::JobStatus::Completed)
    } else {
        false
    }
}

/// Get job error message
/// Returns allocated string (caller must free with offline_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_job_error(job_id: u64) -> *mut c_char {
    if let Some(result) = JOB_RESULTS.get(&job_id) {
        if let Some(ref error) = result.error {
            match CString::new(error.clone()) {
                Ok(c) => return c.into_raw(),
                Err(_) => return ptr::null_mut(),
            }
        }
    }
    ptr::null_mut()
}

/// Clear job result from storage
#[unsafe(no_mangle)]
pub extern "C" fn offline_clear_job_result(job_id: u64) {
    JOB_RESULTS.remove(&job_id);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BATCH PROCESSING
// ═══════════════════════════════════════════════════════════════════════════════

/// Process multiple files in batch
/// jobs_json: JSON array of job configs
/// Returns: JSON string with results array (caller must free with offline_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn offline_batch_process(jobs_json: *const c_char) -> *mut c_char {
    clear_error();

    if jobs_json.is_null() {
        set_error("Jobs JSON is null");
        return ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(jobs_json) };
    let jobs_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid jobs encoding");
            return ptr::null_mut();
        }
    };

    #[derive(serde::Deserialize)]
    struct BatchJobConfig {
        input_path: String,
        output_path: String,
        sample_rate: Option<u32>,
    }

    let configs: Vec<BatchJobConfig> = match serde_json::from_str(jobs_str) {
        Ok(c) => c,
        Err(e) => {
            set_error(&format!("Failed to parse jobs: {}", e));
            return ptr::null_mut();
        }
    };

    let mut jobs = Vec::new();
    for config in configs {
        let mut builder = JobBuilder::new()
            .input(&config.input_path)
            .output(&config.output_path);

        if let Some(rate) = config.sample_rate {
            builder = builder.sample_rate(rate);
        }

        match builder.build() {
            Ok(job) => jobs.push(job),
            Err(e) => {
                set_error(&format!("Failed to create job: {}", e));
                return ptr::null_mut();
            }
        }
    }

    let processor = BatchProcessor::new(OfflineConfig::default());
    let results = processor.process_all(&jobs);

    // Store results
    for result in &results {
        JOB_RESULTS.insert(result.job_id, result.clone());
    }

    // Return JSON
    match serde_json::to_string(&results) {
        Ok(s) => {
            match CString::new(s) {
                Ok(c) => c.into_raw(),
                Err(_) => ptr::null_mut(),
            }
        }
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ERROR HANDLING
// ═══════════════════════════════════════════════════════════════════════════════

/// Get last error message
/// Returns allocated string (caller must free with offline_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_last_error() -> *mut c_char {
    if let Some(ref error) = *LAST_ERROR.read() {
        match CString::new(error.clone()) {
            Ok(c) => c.into_raw(),
            Err(_) => ptr::null_mut(),
        }
    } else {
        ptr::null_mut()
    }
}

/// Free a string allocated by this module
#[unsafe(no_mangle)]
pub extern "C" fn offline_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get supported output formats as JSON
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_supported_formats() -> *mut c_char {
    let formats = r#"[
        {"id": 0, "name": "WAV 16-bit", "extension": "wav", "lossless": true},
        {"id": 1, "name": "WAV 24-bit", "extension": "wav", "lossless": true},
        {"id": 2, "name": "WAV 32-bit float", "extension": "wav", "lossless": true},
        {"id": 3, "name": "FLAC", "extension": "flac", "lossless": true},
        {"id": 4, "name": "MP3 320kbps", "extension": "mp3", "lossless": false}
    ]"#;

    match CString::new(formats) {
        Ok(c) => c.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Get supported normalization modes as JSON
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_normalization_modes() -> *mut c_char {
    let modes = r#"[
        {"id": 0, "name": "None", "unit": ""},
        {"id": 1, "name": "Peak", "unit": "dBFS"},
        {"id": 2, "name": "Loudness (LUFS)", "unit": "LUFS"},
        {"id": 3, "name": "True Peak", "unit": "dBTP"},
        {"id": 4, "name": "No Clip", "unit": ""}
    ]"#;

    match CString::new(modes) {
        Ok(c) => c.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO FILE INFO (METADATA)
// ═══════════════════════════════════════════════════════════════════════════════

/// Get audio file metadata without decoding
/// Returns JSON with: sample_rate, channels, bit_depth, duration_seconds, samples
/// Caller must free with offline_free_string
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_audio_info(path: *const c_char) -> *mut c_char {
    clear_error();

    if path.is_null() {
        set_error("Path is null");
        return ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => {
            set_error("Invalid path encoding");
            return ptr::null_mut();
        }
    };

    let path = std::path::Path::new(path_str);

    match rf_offline::AudioDecoder::probe(path) {
        Ok(info) => {
            #[derive(serde::Serialize)]
            struct AudioInfoJson {
                path: String,
                format: String,
                sample_rate: u32,
                channels: usize,
                bit_depth: u8,
                duration_seconds: f64,
                samples: usize,
                duration_str: String,
            }

            // Call duration_str() before moving fields
            let duration_str = info.duration_str();

            let json = AudioInfoJson {
                path: info.path.to_string_lossy().to_string(),
                format: info.format,
                sample_rate: info.sample_rate,
                channels: info.channels,
                bit_depth: info.bit_depth,
                duration_seconds: info.duration,
                samples: info.samples,
                duration_str,
            };

            match serde_json::to_string(&json) {
                Ok(s) => match CString::new(s) {
                    Ok(c) => c.into_raw(),
                    Err(_) => ptr::null_mut(),
                },
                Err(_) => ptr::null_mut(),
            }
        }
        Err(e) => {
            set_error(&e.to_string());
            ptr::null_mut()
        }
    }
}

/// Get audio file duration in seconds
/// Returns -1.0 on error
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_audio_duration(path: *const c_char) -> f64 {
    if path.is_null() {
        return -1.0;
    }

    let c_str = unsafe { CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return -1.0,
    };

    let path = std::path::Path::new(path_str);

    match rf_offline::AudioDecoder::probe(path) {
        Ok(info) => info.duration,
        Err(_) => -1.0,
    }
}

/// Get audio file sample rate
/// Returns 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_audio_sample_rate(path: *const c_char) -> u32 {
    if path.is_null() {
        return 0;
    }

    let c_str = unsafe { CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let path = std::path::Path::new(path_str);

    match rf_offline::AudioDecoder::probe(path) {
        Ok(info) => info.sample_rate,
        Err(_) => 0,
    }
}

/// Get audio file channel count
/// Returns 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn offline_get_audio_channels(path: *const c_char) -> u32 {
    if path.is_null() {
        return 0;
    }

    let c_str = unsafe { CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let path = std::path::Path::new(path_str);

    match rf_offline::AudioDecoder::probe(path) {
        Ok(info) => info.channels as u32,
        Err(_) => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pipeline_lifecycle() {
        let handle = offline_pipeline_create();
        assert!(handle > 0);

        let state = offline_pipeline_get_state(handle);
        assert_eq!(state, 0); // Idle

        offline_pipeline_destroy(handle);

        let state_after = offline_pipeline_get_state(handle);
        assert_eq!(state_after, -1); // Not found
    }

    #[test]
    fn test_get_formats() {
        let formats = offline_get_supported_formats();
        assert!(!formats.is_null());
        offline_free_string(formats);
    }
}
