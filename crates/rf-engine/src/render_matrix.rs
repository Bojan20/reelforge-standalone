//! Region Render Matrix — Batch Export Engine
//!
//! The killer feature for sound designers: define named regions on the timeline,
//! configure export formats in a matrix, and batch-render everything in one operation.
//!
//! ## Architecture
//!
//! ```text
//! RenderMatrix
//! ├── RenderPreset (format/quality combinations)
//! │   ├── "WAV 24-bit 48kHz"
//! │   ├── "MP3 320kbps"
//! │   └── "FLAC 24-bit 96kHz"
//! ├── RenderJob (region × preset)
//! │   ├── region: "footstep_wood_01" × preset: "WAV 24-bit"
//! │   ├── region: "footstep_wood_01" × preset: "MP3 320"
//! │   └── region: "explosion_large" × preset: "WAV 24-bit"
//! └── BatchProgress (overall + per-job tracking)
//! ```
//!
//! ## Naming Convention
//! Output filenames: `{prefix}{region_name}{suffix}.{ext}`
//! With subdirectories per format: `output_dir/{preset_name}/{filename}`
//!
//! ## Reaper Equivalent
//! Region Render Matrix + wildcard naming + multiple format presets

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use rayon::prelude::*;
use serde::{Deserialize, Serialize};

use crate::export::{ExportError, ExportFormat};
use crate::track_manager::{RenderRegion, TrackManager};
use crate::playback::PlaybackEngine;
use crate::freeze::OfflineRenderer;

use rf_file::{AudioData, BitDepth, write_flac, write_mp3};

// ═══════════════════════════════════════════════════════════════════════════
// RENDER PRESET — Format/quality combination
// ═══════════════════════════════════════════════════════════════════════════

/// A named export format preset for the render matrix.
/// Users create presets like "WAV Master", "MP3 Distribution", "FLAC Archive".
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderPreset {
    /// Unique preset ID
    pub id: u64,
    /// Display name (e.g. "WAV 24-bit 48kHz")
    pub name: String,
    /// Export format
    pub format: ExportFormat,
    /// Sample rate (0 = project rate)
    pub sample_rate: u32,
    /// Normalize audio
    pub normalize: bool,
    /// Normalize target in dBFS (e.g. -0.1)
    pub normalize_target: f64,
    /// Enabled in matrix
    pub enabled: bool,
    /// Subdirectory name for this preset's outputs (empty = flat)
    pub subdirectory: String,
}

impl RenderPreset {
    pub fn new(id: u64, name: &str, format: ExportFormat) -> Self {
        Self {
            id,
            name: name.to_string(),
            format,
            sample_rate: 0,
            normalize: false,
            normalize_target: -0.1,
            enabled: true,
            subdirectory: String::new(),
        }
    }

    /// WAV 24-bit 48kHz (sound design standard)
    pub fn wav_24_48() -> Self {
        Self::new(1, "WAV 24-bit 48kHz", ExportFormat::Wav24)
    }

    /// WAV 16-bit 44.1kHz (CD quality)
    pub fn wav_16_44() -> Self {
        let mut p = Self::new(2, "WAV 16-bit 44.1kHz", ExportFormat::Wav16);
        p.sample_rate = 44100;
        p
    }

    /// WAV 32-bit float (maximum quality)
    pub fn wav_32_float() -> Self {
        Self::new(3, "WAV 32-bit Float", ExportFormat::Wav32Float)
    }

    /// MP3 320kbps (distribution)
    pub fn mp3_320() -> Self {
        let mut p = Self::new(4, "MP3 320kbps", ExportFormat::Mp3_320);
        p.normalize = true;
        p.normalize_target = -1.0;
        p
    }

    /// FLAC 24-bit (lossless archive)
    pub fn flac_24() -> Self {
        Self::new(5, "FLAC 24-bit", ExportFormat::Flac24)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// RENDER JOB — Single region × preset combination
// ═══════════════════════════════════════════════════════════════════════════

/// Status of a single render job
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RenderJobStatus {
    /// Waiting to be rendered
    Pending,
    /// Currently rendering
    Rendering,
    /// Successfully completed
    Complete,
    /// Skipped (disabled region or preset)
    Skipped,
    /// Failed with error
    Failed,
}

/// A single render job: one region rendered with one preset
#[derive(Debug, Clone)]
pub struct RenderJob {
    /// Region being rendered
    pub region: RenderRegion,
    /// Preset being used
    pub preset: RenderPreset,
    /// Output file path
    pub output_path: PathBuf,
    /// Current status
    pub status: RenderJobStatus,
    /// Error message (if Failed)
    pub error: Option<String>,
    /// Render progress (0.0 - 1.0)
    pub progress: f32,
}

// ═══════════════════════════════════════════════════════════════════════════
// RENDER MATRIX CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Filename wildcard tokens for output naming
/// Supports: $region, $preset, $date, $time, $index, $tag
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamingConfig {
    /// Filename template (e.g. "$region" or "$tag/$region_$preset")
    pub template: String,
    /// Whether to create subdirectories per preset
    pub subdirs_per_preset: bool,
    /// Whether to create subdirectories per tag
    pub subdirs_per_tag: bool,
    /// File prefix (prepended before template)
    pub prefix: String,
    /// File suffix (appended after template, before extension)
    pub suffix: String,
}

impl Default for NamingConfig {
    fn default() -> Self {
        Self {
            template: "$region".to_string(),
            subdirs_per_preset: true,
            subdirs_per_tag: false,
            prefix: String::new(),
            suffix: String::new(),
        }
    }
}

/// Full render matrix configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderMatrixConfig {
    /// Output root directory
    pub output_dir: PathBuf,
    /// Format presets to render
    pub presets: Vec<RenderPreset>,
    /// Naming configuration
    pub naming: NamingConfig,
    /// Render block size
    pub block_size: usize,
    /// Enable parallel rendering of regions (uses rayon)
    pub parallel: bool,
    /// Maximum parallel render threads (0 = auto / rayon default)
    pub max_threads: usize,
}

impl Default for RenderMatrixConfig {
    fn default() -> Self {
        Self {
            output_dir: PathBuf::from("render_output"),
            presets: vec![RenderPreset::wav_24_48()],
            naming: NamingConfig::default(),
            block_size: 1024,
            parallel: true,
            max_threads: 0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// BATCH PROGRESS
// ═══════════════════════════════════════════════════════════════════════════

/// Overall batch render progress
#[derive(Debug, Clone)]
pub struct BatchProgress {
    /// Total number of jobs
    pub total_jobs: usize,
    /// Completed jobs
    pub completed_jobs: usize,
    /// Failed jobs
    pub failed_jobs: usize,
    /// Skipped jobs
    pub skipped_jobs: usize,
    /// Currently rendering job index
    pub current_job: usize,
    /// Current job's region name
    pub current_region: String,
    /// Current job's preset name
    pub current_preset: String,
    /// Overall progress (0.0 - 100.0)
    pub percent: f32,
    /// Is the batch complete
    pub is_complete: bool,
    /// Was cancelled
    pub was_cancelled: bool,
}

impl BatchProgress {
    fn new(total: usize) -> Self {
        Self {
            total_jobs: total,
            completed_jobs: 0,
            failed_jobs: 0,
            skipped_jobs: 0,
            current_job: 0,
            current_region: String::new(),
            current_preset: String::new(),
            percent: 0.0,
            is_complete: false,
            was_cancelled: false,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// RENDER MATRIX ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// Region Render Matrix — batch renders multiple regions × multiple formats.
///
/// # Thread Safety
/// - `render_batch()` blocks the calling thread (FFI thread, not audio thread)
/// - Progress is tracked atomically for polling from UI
/// - Parallel rendering uses rayon thread pool (regions in parallel, presets sequential)
/// - Cancellation is cooperative via AtomicBool
pub struct RenderMatrix {
    playback_engine: Arc<PlaybackEngine>,
    track_manager: Arc<TrackManager>,
    /// Atomic progress (0-10000 = 0.00% - 100.00%)
    progress: AtomicU64,
    /// Is currently rendering
    is_rendering: AtomicBool,
    /// Cancel flag
    is_cancelled: AtomicBool,
    /// Current batch progress (detailed)
    batch_progress: parking_lot::RwLock<BatchProgress>,
    /// Last batch results (jobs with final status)
    last_results: parking_lot::RwLock<Vec<RenderJob>>,
}

impl RenderMatrix {
    pub fn new(
        playback_engine: Arc<PlaybackEngine>,
        track_manager: Arc<TrackManager>,
    ) -> Self {
        Self {
            playback_engine,
            track_manager,
            progress: AtomicU64::new(0),
            is_rendering: AtomicBool::new(false),
            is_cancelled: AtomicBool::new(false),
            batch_progress: parking_lot::RwLock::new(BatchProgress::new(0)),
            last_results: parking_lot::RwLock::new(Vec::new()),
        }
    }

    /// Get current progress (0.0 - 100.0)
    pub fn progress(&self) -> f32 {
        self.progress.load(Ordering::Relaxed) as f32 / 100.0
    }

    /// Is currently rendering
    pub fn is_rendering(&self) -> bool {
        self.is_rendering.load(Ordering::Relaxed)
    }

    /// Cancel the current batch render
    pub fn cancel(&self) {
        self.is_cancelled.store(true, Ordering::Relaxed);
    }

    /// Get detailed batch progress
    pub fn batch_progress(&self) -> BatchProgress {
        self.batch_progress.read().clone()
    }

    /// Get last batch results
    pub fn last_results(&self) -> Vec<RenderJob> {
        self.last_results.read().clone()
    }

    /// Build the list of render jobs from regions × presets
    pub fn build_jobs(
        &self,
        regions: &[RenderRegion],
        config: &RenderMatrixConfig,
    ) -> Vec<RenderJob> {
        let mut jobs = Vec::with_capacity(regions.len() * config.presets.len());

        for region in regions {
            if !region.enabled {
                continue;
            }

            for preset in &config.presets {
                if !preset.enabled {
                    continue;
                }

                let output_path =
                    self.build_output_path(region, preset, config);

                jobs.push(RenderJob {
                    region: region.clone(),
                    preset: preset.clone(),
                    output_path,
                    status: RenderJobStatus::Pending,
                    error: None,
                    progress: 0.0,
                });
            }
        }

        jobs
    }

    /// Build output file path for a region × preset combination
    fn build_output_path(
        &self,
        region: &RenderRegion,
        preset: &RenderPreset,
        config: &RenderMatrixConfig,
    ) -> PathBuf {
        let mut path = config.output_dir.clone();

        // Subdirectory per preset
        if config.naming.subdirs_per_preset && !preset.subdirectory.is_empty() {
            path.push(&preset.subdirectory);
        } else if config.naming.subdirs_per_preset {
            path.push(sanitize_filename(&preset.name));
        }

        // Subdirectory per tag (first tag)
        if config.naming.subdirs_per_tag {
            if let Some(tag) = region.tags.first() {
                path.push(sanitize_filename(tag));
            }
        }

        // Build filename from template
        let filename = self.expand_template(
            &config.naming.template,
            region,
            preset,
            &config.naming.prefix,
            &config.naming.suffix,
        );

        let ext = preset.format.file_extension();
        path.push(format!("{}.{}", filename, ext));

        path
    }

    /// Expand naming template with wildcard tokens
    fn expand_template(
        &self,
        template: &str,
        region: &RenderRegion,
        preset: &RenderPreset,
        prefix: &str,
        suffix: &str,
    ) -> String {
        let now = chrono_compat_date();
        let expanded = template
            .replace("$region", &sanitize_filename(&region.name))
            .replace("$preset", &sanitize_filename(&preset.name))
            .replace("$date", &now)
            .replace("$index", &region.order.to_string());

        // Replace $tag with first tag or "untagged"
        let expanded = if let Some(tag) = region.tags.first() {
            expanded.replace("$tag", &sanitize_filename(tag))
        } else {
            expanded.replace("$tag", "untagged")
        };

        format!("{}{}{}", prefix, expanded, suffix)
    }

    /// Execute batch render. Blocks until complete or cancelled.
    ///
    /// Returns Vec of completed RenderJobs with final status.
    pub fn render_batch(
        &self,
        config: RenderMatrixConfig,
    ) -> Result<Vec<RenderJob>, ExportError> {
        // Prevent concurrent batch renders
        if self.is_rendering.swap(true, Ordering::Relaxed) {
            return Err(ExportError::AlreadyExporting);
        }

        self.is_cancelled.store(false, Ordering::Relaxed);
        self.progress.store(0, Ordering::Relaxed);

        // Get enabled regions
        let regions = self.track_manager.get_enabled_render_regions();
        if regions.is_empty() {
            self.is_rendering.store(false, Ordering::Relaxed);
            return Err(ExportError::RenderError(
                "No enabled render regions".to_string(),
            ));
        }

        // Build job list
        let mut jobs = self.build_jobs(&regions, &config);
        let total_jobs = jobs.len();

        if total_jobs == 0 {
            self.is_rendering.store(false, Ordering::Relaxed);
            return Err(ExportError::RenderError(
                "No enabled presets".to_string(),
            ));
        }

        // Initialize progress
        *self.batch_progress.write() = BatchProgress::new(total_jobs);

        // Create output directories
        for job in &jobs {
            if let Some(parent) = job.output_path.parent() {
                std::fs::create_dir_all(parent)
                    .map_err(|e| ExportError::IoError(e.to_string()))?;
            }
        }

        // Get project sample rate
        let project_sr = self.playback_engine.position.sample_rate() as u32;

        if config.parallel && total_jobs > 1 {
            // Parallel render: each job gets its own buffers
            // Jobs are independent (different regions/presets)
            let results: Vec<RenderJob> = jobs
                .into_par_iter()
                .enumerate()
                .map(|(idx, mut job)| {
                    if self.is_cancelled.load(Ordering::Relaxed) {
                        job.status = RenderJobStatus::Skipped;
                        return job;
                    }

                    // Update progress
                    {
                        let mut bp = self.batch_progress.write();
                        bp.current_job = idx;
                        bp.current_region = job.region.name.clone();
                        bp.current_preset = job.preset.name.clone();
                    }

                    job.status = RenderJobStatus::Rendering;

                    match self.render_single_job(&job, project_sr, config.block_size) {
                        Ok(()) => {
                            job.status = RenderJobStatus::Complete;
                            job.progress = 1.0;
                        }
                        Err(e) => {
                            job.status = RenderJobStatus::Failed;
                            job.error = Some(e.to_string());
                            log::error!(
                                "Render failed: {} × {}: {}",
                                job.region.name,
                                job.preset.name,
                                e
                            );
                        }
                    }

                    // Update overall progress
                    // Each job adds (10000 / total) so progress() = load / 100.0 gives 0-100%
                    let increment = 10000u64 / total_jobs as u64;
                    let new_val = self.progress.fetch_add(increment, Ordering::Relaxed) + increment;
                    let percent = (new_val as f32 / 100.0).min(100.0);
                    {
                        let mut bp = self.batch_progress.write();
                        bp.percent = percent;
                        if job.status == RenderJobStatus::Complete {
                            bp.completed_jobs += 1;
                        } else if job.status == RenderJobStatus::Failed {
                            bp.failed_jobs += 1;
                        }
                    }

                    job
                })
                .collect();

            // Finalize
            {
                let mut bp = self.batch_progress.write();
                bp.is_complete = true;
                bp.percent = 100.0;
            }

            *self.last_results.write() = results.clone();
            self.is_rendering.store(false, Ordering::Relaxed);
            Ok(results)
        } else {
            // Sequential render
            for (idx, job) in jobs.iter_mut().enumerate() {
                if self.is_cancelled.load(Ordering::Relaxed) {
                    job.status = RenderJobStatus::Skipped;
                    {
                        let mut bp = self.batch_progress.write();
                        bp.was_cancelled = true;
                        bp.skipped_jobs += 1;
                    }
                    continue;
                }

                // Update progress
                {
                    let mut bp = self.batch_progress.write();
                    bp.current_job = idx;
                    bp.current_region = job.region.name.clone();
                    bp.current_preset = job.preset.name.clone();
                }

                job.status = RenderJobStatus::Rendering;

                match self.render_single_job(job, project_sr, config.block_size) {
                    Ok(()) => {
                        job.status = RenderJobStatus::Complete;
                        job.progress = 1.0;
                        self.batch_progress.write().completed_jobs += 1;
                    }
                    Err(e) => {
                        job.status = RenderJobStatus::Failed;
                        job.error = Some(e.to_string());
                        self.batch_progress.write().failed_jobs += 1;
                        log::error!(
                            "Render failed: {} × {}: {}",
                            job.region.name,
                            job.preset.name,
                            e
                        );
                    }
                }

                // Update overall progress
                let percent = ((idx + 1) as f32 / total_jobs as f32) * 100.0;
                self.progress
                    .store((percent * 100.0) as u64, Ordering::Relaxed);
                self.batch_progress.write().percent = percent;
            }

            // Finalize
            {
                let mut bp = self.batch_progress.write();
                bp.is_complete = true;
                bp.percent = 100.0;
            }

            let results = jobs.clone();
            *self.last_results.write() = results.clone();
            self.is_rendering.store(false, Ordering::Relaxed);
            Ok(results)
        }
    }

    /// Render a single job (one region × one preset)
    fn render_single_job(
        &self,
        job: &RenderJob,
        project_sr: u32,
        block_size: usize,
    ) -> Result<(), ExportError> {
        let region = &job.region;
        let preset = &job.preset;

        // Determine sample rate
        let sample_rate = if preset.sample_rate == 0 {
            project_sr
        } else {
            preset.sample_rate
        };

        // Calculate total render samples
        let render_duration = region.render_duration();
        let total_samples = (render_duration * sample_rate as f64) as usize;

        if total_samples == 0 {
            return Err(ExportError::InvalidTimeRange);
        }

        // Allocate output buffers
        let mut output_l = vec![0.0f64; total_samples];
        let mut output_r = vec![0.0f64; total_samples];

        // Render in blocks through playback engine
        let num_blocks = total_samples.div_ceil(block_size);
        for block_idx in 0..num_blocks {
            if self.is_cancelled.load(Ordering::Relaxed) {
                return Err(ExportError::RenderError("Cancelled".to_string()));
            }

            let block_start = block_idx * block_size;
            let block_end = (block_start + block_size).min(total_samples);

            let block_start_sample =
                (region.start * sample_rate as f64) as usize + block_start;

            let block_l = &mut output_l[block_start..block_end];
            let block_r = &mut output_r[block_start..block_end];

            self.playback_engine
                .process_offline(block_start_sample, block_l, block_r);
        }

        // Normalize
        let should_normalize = region.normalize.unwrap_or(preset.normalize);
        if should_normalize {
            let target = region.normalize_target.unwrap_or(preset.normalize_target);
            normalize_audio(&mut output_l, &mut output_r, target);
        }

        // Write output file
        write_output(
            &job.output_path,
            &output_l,
            &output_r,
            sample_rate,
            preset.format,
        )
    }

    /// Quick-render a single region with a single preset (for preview/test)
    pub fn render_single_region(
        &self,
        region: &RenderRegion,
        preset: &RenderPreset,
        output_path: &Path,
    ) -> Result<(), ExportError> {
        let project_sr = self.playback_engine.position.sample_rate() as u32;
        let job = RenderJob {
            region: region.clone(),
            preset: preset.clone(),
            output_path: output_path.to_path_buf(),
            status: RenderJobStatus::Pending,
            error: None,
            progress: 0.0,
        };
        self.render_single_job(&job, project_sr, 1024)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Normalize audio to target dBFS
fn normalize_audio(left: &mut [f64], right: &mut [f64], target_dbfs: f64) {
    // Find peak
    let mut peak = 0.0f64;
    for &sample in left.iter().chain(right.iter()) {
        peak = peak.max(sample.abs());
    }

    if peak > 0.0 {
        // Convert target dBFS to linear
        let target_linear = 10.0_f64.powf(target_dbfs / 20.0);
        let gain = target_linear / peak;

        for sample in left.iter_mut().chain(right.iter_mut()) {
            *sample *= gain;
        }
    }
}

/// Write output in specified format (same as ExportEngine but standalone)
fn write_output(
    path: &Path,
    left: &[f64],
    right: &[f64],
    sample_rate: u32,
    format: ExportFormat,
) -> Result<(), ExportError> {
    let path_buf = path.to_path_buf();
    match format {
        ExportFormat::Wav16 => {
            OfflineRenderer::write_wav_16bit(&path_buf, left, right, sample_rate)
                .map_err(|e| ExportError::IoError(e.to_string()))?;
        }
        ExportFormat::Wav24 => {
            OfflineRenderer::write_wav_24bit(&path_buf, left, right, sample_rate)
                .map_err(|e| ExportError::IoError(e.to_string()))?;
        }
        ExportFormat::Wav32Float => {
            OfflineRenderer::write_wav_f32(&path_buf, left, right, sample_rate)
                .map_err(|e| ExportError::IoError(e.to_string()))?;
        }
        ExportFormat::Flac16 | ExportFormat::Flac24 => {
            let bit_depth = if format == ExportFormat::Flac16 {
                BitDepth::Int16
            } else {
                BitDepth::Int24
            };
            let mut audio_data = AudioData::new(2, left.len(), sample_rate);
            audio_data.channels[0].copy_from_slice(left);
            audio_data.channels[1].copy_from_slice(right);
            write_flac(path, &audio_data, bit_depth)
                .map_err(|e: rf_file::FileError| ExportError::IoError(e.to_string()))?;
        }
        ExportFormat::Mp3_320
        | ExportFormat::Mp3_256
        | ExportFormat::Mp3_192
        | ExportFormat::Mp3_128 => {
            let bitrate = match format {
                ExportFormat::Mp3_320 => 320,
                ExportFormat::Mp3_256 => 256,
                ExportFormat::Mp3_192 => 192,
                ExportFormat::Mp3_128 => 128,
                _ => 320,
            };
            let mut audio_data = AudioData::new(2, left.len(), sample_rate);
            audio_data.channels[0].copy_from_slice(left);
            audio_data.channels[1].copy_from_slice(right);
            write_mp3(path, &audio_data, bitrate)
                .map_err(|e: rf_file::FileError| ExportError::IoError(e.to_string()))?;
        }
    }
    Ok(())
}

/// Sanitize filename by replacing invalid characters and spaces
fn sanitize_filename(name: &str) -> String {
    name.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | ' ' => '_',
            _ => c,
        })
        .collect()
}

/// Get current date string for filename templates (YYYY-MM-DD)
fn chrono_compat_date() -> String {
    // Use std::time to avoid chrono dependency
    let now = std::time::SystemTime::now();
    let since_epoch = now
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let secs = since_epoch.as_secs();
    // Approximate date calculation (good enough for filenames)
    let days = secs / 86400;
    let mut y = 1970;
    let mut remaining_days = days;
    loop {
        let days_in_year = if is_leap_year(y) { 366 } else { 365 };
        if remaining_days < days_in_year {
            break;
        }
        remaining_days -= days_in_year;
        y += 1;
    }
    let months = [31, if is_leap_year(y) { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    let mut m = 1u64;
    for &dim in &months {
        if remaining_days < dim {
            break;
        }
        remaining_days -= dim;
        m += 1;
    }
    let d = remaining_days + 1;
    format!("{:04}-{:02}-{:02}", y, m, d)
}

fn is_leap_year(y: u64) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::track_manager::RenderRegion;

    #[test]
    fn test_render_preset_defaults() {
        let p = RenderPreset::wav_24_48();
        assert_eq!(p.format, ExportFormat::Wav24);
        assert_eq!(p.sample_rate, 0);
        assert!(!p.normalize);
        assert!(p.enabled);
    }

    #[test]
    fn test_naming_template_expansion() {
        let tm = Arc::new(TrackManager::new());
        let pe = Arc::new(PlaybackEngine::new(tm.clone(), 48000));
        let matrix = RenderMatrix::new(pe, tm);

        let region = RenderRegion::new("footstep_wood_01", 1.0, 2.0);
        let preset = RenderPreset::wav_24_48();

        let name = matrix.expand_template(
            "$region_$preset",
            &region,
            &preset,
            "SFX_",
            "_final",
        );

        assert_eq!(name, "SFX_footstep_wood_01_WAV_24-bit_48kHz_final");
    }

    #[test]
    fn test_build_jobs() {
        let tm = Arc::new(TrackManager::new());
        let pe = Arc::new(PlaybackEngine::new(tm.clone(), 48000));
        let matrix = RenderMatrix::new(pe, tm.clone());

        // Add regions
        tm.add_render_region("explosion", 0.0, 3.0);
        tm.add_render_region("footstep", 5.0, 5.5);

        let regions = tm.get_enabled_render_regions();
        let config = RenderMatrixConfig {
            presets: vec![
                RenderPreset::wav_24_48(),
                RenderPreset::mp3_320(),
            ],
            ..Default::default()
        };

        let jobs = matrix.build_jobs(&regions, &config);
        // 2 regions × 2 presets = 4 jobs
        assert_eq!(jobs.len(), 4);

        // All should be Pending
        for job in &jobs {
            assert_eq!(job.status, RenderJobStatus::Pending);
        }
    }

    #[test]
    fn test_normalize_audio() {
        let mut left = vec![0.5, -0.8, 0.3];
        let mut right = vec![0.6, -0.7, 0.4];

        normalize_audio(&mut left, &mut right, -0.1);

        let peak = left
            .iter()
            .chain(right.iter())
            .map(|s| s.abs())
            .fold(0.0f64, f64::max);
        // -0.1 dBFS = 0.9885...
        assert!((peak - 0.9885).abs() < 0.01, "Peak should be ~0.989, got {}", peak);
    }

    #[test]
    fn test_render_region_model() {
        let r = RenderRegion::new("test_sfx", 1.0, 3.5);
        assert_eq!(r.duration(), 2.5);
        assert!(r.include_tail);
        assert_eq!(r.render_duration(), 3.0); // 2.5 + 0.5 tail
        assert!(r.contains_time(2.0));
        assert!(!r.contains_time(0.5));
        assert!(r.overlaps(2.0, 4.0));
        assert!(!r.overlaps(4.0, 5.0));
    }

    #[test]
    fn test_disabled_region_skipped() {
        let tm = Arc::new(TrackManager::new());
        let pe = Arc::new(PlaybackEngine::new(tm.clone(), 48000));
        let matrix = RenderMatrix::new(pe, tm.clone());

        let id = tm.add_render_region("disabled_one", 0.0, 1.0);
        tm.update_render_region(id, |r| r.enabled = false);
        tm.add_render_region("enabled_one", 2.0, 3.0);

        let regions = tm.get_enabled_render_regions();
        assert_eq!(regions.len(), 1);
        assert_eq!(regions[0].name, "enabled_one");

        let config = RenderMatrixConfig {
            presets: vec![RenderPreset::wav_24_48()],
            ..Default::default()
        };
        let jobs = matrix.build_jobs(&regions, &config);
        assert_eq!(jobs.len(), 1);
    }

    #[test]
    fn test_sanitize_filename() {
        assert_eq!(sanitize_filename("foo/bar:baz"), "foo_bar_baz");
        assert_eq!(sanitize_filename("normal_name"), "normal_name");
        assert_eq!(sanitize_filename("with spaces"), "with_spaces");
        assert_eq!(sanitize_filename("a*b?c"), "a_b_c");
    }

    #[test]
    fn test_chrono_compat_date() {
        let date = chrono_compat_date();
        // Should be YYYY-MM-DD format
        assert_eq!(date.len(), 10);
        assert_eq!(&date[4..5], "-");
        assert_eq!(&date[7..8], "-");
    }
}
