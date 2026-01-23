//! Offline processing job definitions

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use super::{OutputFormat, NormalizationMode, OfflineResult, OfflineError};
use super::processors::ProcessorChain;
use super::config::SrcQuality;

/// Unique job identifier
pub type JobId = u64;

/// Offline processing job
#[derive(Debug, Serialize, Deserialize)]
pub struct OfflineJob {
    /// Unique job ID
    pub id: JobId,

    /// Input file path
    pub input_path: PathBuf,

    /// Output file path
    pub output_path: PathBuf,

    /// Output format
    pub format: OutputFormat,

    /// Sample rate (None = keep original)
    pub sample_rate: Option<u32>,

    /// Sample rate conversion quality
    pub src_quality: SrcQuality,

    /// Normalization mode
    pub normalization: Option<NormalizationMode>,

    /// Processing chain (effects)
    #[serde(skip)]
    pub processors: Option<ProcessorChain>,

    /// Time range (start, end) in samples (None = entire file)
    pub range: Option<(u64, u64)>,

    /// Fade in duration (samples)
    pub fade_in: Option<u64>,

    /// Fade out duration (samples)
    pub fade_out: Option<u64>,

    /// Tail handling (extra samples to capture reverb tails)
    pub tail_samples: u64,

    /// Priority (higher = process first)
    pub priority: u8,

    /// Job metadata (for UI)
    pub metadata: JobMetadata,
}

/// Job metadata for UI display
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct JobMetadata {
    /// Display name
    pub name: String,
    /// Source description
    pub source: String,
    /// Additional tags
    pub tags: Vec<String>,
}

impl OfflineJob {
    /// Create new job builder
    pub fn builder() -> JobBuilder {
        JobBuilder::new()
    }

    /// Validate job configuration
    pub fn validate(&self) -> OfflineResult<()> {
        if !self.input_path.exists() {
            return Err(OfflineError::InputNotFound(
                self.input_path.display().to_string(),
            ));
        }

        if let Some(parent) = self.output_path.parent() {
            if !parent.exists() {
                return Err(OfflineError::WriteError(format!(
                    "Output directory does not exist: {}",
                    parent.display()
                )));
            }
        }

        Ok(())
    }
}

/// Job builder for fluent API
#[derive(Debug, Default)]
pub struct JobBuilder {
    input_path: Option<PathBuf>,
    output_path: Option<PathBuf>,
    format: OutputFormat,
    sample_rate: Option<u32>,
    src_quality: SrcQuality,
    normalization: Option<NormalizationMode>,
    processors: Option<ProcessorChain>,
    range: Option<(u64, u64)>,
    fade_in: Option<u64>,
    fade_out: Option<u64>,
    tail_samples: u64,
    priority: u8,
    metadata: JobMetadata,
}

static JOB_ID_COUNTER: AtomicU64 = AtomicU64::new(1);

impl JobBuilder {
    pub fn new() -> Self {
        Self::default()
    }

    /// Set input file
    pub fn input<P: Into<PathBuf>>(mut self, path: P) -> Self {
        self.input_path = Some(path.into());
        self
    }

    /// Set output file
    pub fn output<P: Into<PathBuf>>(mut self, path: P) -> Self {
        self.output_path = Some(path.into());
        self
    }

    /// Set output format
    pub fn format(mut self, format: OutputFormat) -> Self {
        self.format = format;
        self
    }

    /// Set output sample rate
    pub fn sample_rate(mut self, rate: u32) -> Self {
        self.sample_rate = Some(rate);
        self
    }

    /// Set sample rate conversion quality
    pub fn src_quality(mut self, quality: SrcQuality) -> Self {
        self.src_quality = quality;
        self
    }

    /// Set normalization mode
    pub fn normalize(mut self, mode: NormalizationMode) -> Self {
        self.normalization = Some(mode);
        self
    }

    /// Set processing chain
    pub fn processors(mut self, chain: ProcessorChain) -> Self {
        self.processors = Some(chain);
        self
    }

    /// Set time range (start, end) in samples
    pub fn range(mut self, start: u64, end: u64) -> Self {
        self.range = Some((start, end));
        self
    }

    /// Set fade in duration in samples
    pub fn fade_in(mut self, samples: u64) -> Self {
        self.fade_in = Some(samples);
        self
    }

    /// Set fade out duration in samples
    pub fn fade_out(mut self, samples: u64) -> Self {
        self.fade_out = Some(samples);
        self
    }

    /// Set tail samples (for reverb/delay tails)
    pub fn tail(mut self, samples: u64) -> Self {
        self.tail_samples = samples;
        self
    }

    /// Set priority (0-255, higher = first)
    pub fn priority(mut self, priority: u8) -> Self {
        self.priority = priority;
        self
    }

    /// Set display name
    pub fn name<S: Into<String>>(mut self, name: S) -> Self {
        self.metadata.name = name.into();
        self
    }

    /// Build the job
    pub fn build(self) -> OfflineResult<OfflineJob> {
        let input_path = self.input_path.ok_or_else(|| {
            OfflineError::InvalidConfig("Input path is required".to_string())
        })?;

        let output_path = self.output_path.ok_or_else(|| {
            OfflineError::InvalidConfig("Output path is required".to_string())
        })?;

        let id = JOB_ID_COUNTER.fetch_add(1, Ordering::Relaxed);

        let mut metadata = self.metadata;
        if metadata.name.is_empty() {
            metadata.name = input_path
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| format!("Job {}", id));
        }

        Ok(OfflineJob {
            id,
            input_path,
            output_path,
            format: self.format,
            sample_rate: self.sample_rate,
            src_quality: self.src_quality,
            normalization: self.normalization,
            processors: self.processors,
            range: self.range,
            fade_in: self.fade_in,
            fade_out: self.fade_out,
            tail_samples: self.tail_samples,
            priority: self.priority,
            metadata,
        })
    }
}

/// Job execution status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum JobStatus {
    /// Waiting in queue
    Pending,
    /// Currently processing
    Processing,
    /// Completed successfully
    Completed,
    /// Failed with error
    Failed,
    /// Cancelled by user
    Cancelled,
}

/// Job progress tracking
#[derive(Debug)]
pub struct JobProgress {
    /// Job ID
    pub job_id: JobId,
    /// Current status
    pub status: JobStatus,
    /// Progress (0.0 - 1.0)
    pub progress: f64,
    /// Current stage description
    pub stage: String,
    /// Elapsed time
    pub elapsed: Duration,
    /// Estimated time remaining
    pub remaining: Option<Duration>,
    /// Samples processed
    pub samples_processed: u64,
    /// Total samples
    pub total_samples: u64,
    /// Cancel flag
    cancelled: Arc<AtomicBool>,
}

impl JobProgress {
    /// Create new progress tracker
    pub fn new(job_id: JobId, total_samples: u64) -> Self {
        Self {
            job_id,
            status: JobStatus::Pending,
            progress: 0.0,
            stage: "Initializing".to_string(),
            elapsed: Duration::ZERO,
            remaining: None,
            samples_processed: 0,
            total_samples,
            cancelled: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Update progress
    pub fn update(&mut self, samples: u64, stage: &str, start: Instant) {
        self.samples_processed = samples;
        self.stage = stage.to_string();
        self.elapsed = start.elapsed();

        if self.total_samples > 0 {
            self.progress = samples as f64 / self.total_samples as f64;

            // Estimate remaining time
            if samples > 0 && self.progress > 0.01 {
                let rate = samples as f64 / self.elapsed.as_secs_f64();
                let remaining_samples = self.total_samples - samples;
                let remaining_secs = remaining_samples as f64 / rate;
                self.remaining = Some(Duration::from_secs_f64(remaining_secs));
            }
        }
    }

    /// Check if cancelled
    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }

    /// Get cancel flag for sharing
    pub fn cancel_flag(&self) -> Arc<AtomicBool> {
        self.cancelled.clone()
    }

    /// Cancel the job
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }
}

/// Job completion result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JobResult {
    /// Job ID
    pub job_id: JobId,
    /// Final status
    pub status: JobStatus,
    /// Output file path (if successful)
    pub output_path: Option<PathBuf>,
    /// Output file size in bytes
    pub output_size: u64,
    /// Processing duration
    pub duration: Duration,
    /// Peak level (dBFS)
    pub peak_level: f64,
    /// True peak level (dBFS)
    pub true_peak: f64,
    /// Integrated loudness (LUFS)
    pub loudness: f64,
    /// Error message (if failed)
    pub error: Option<String>,
}

impl JobResult {
    /// Create successful result
    pub fn success(
        job_id: JobId,
        output_path: PathBuf,
        output_size: u64,
        duration: Duration,
        peak_level: f64,
        true_peak: f64,
        loudness: f64,
    ) -> Self {
        Self {
            job_id,
            status: JobStatus::Completed,
            output_path: Some(output_path),
            output_size,
            duration,
            peak_level,
            true_peak,
            loudness,
            error: None,
        }
    }

    /// Create failed result
    pub fn failure(job_id: JobId, error: String, duration: Duration) -> Self {
        Self {
            job_id,
            status: JobStatus::Failed,
            output_path: None,
            output_size: 0,
            duration,
            peak_level: 0.0,
            true_peak: 0.0,
            loudness: 0.0,
            error: Some(error),
        }
    }

    /// Create cancelled result
    pub fn cancelled(job_id: JobId, duration: Duration) -> Self {
        Self {
            job_id,
            status: JobStatus::Cancelled,
            output_path: None,
            output_size: 0,
            duration,
            peak_level: 0.0,
            true_peak: 0.0,
            loudness: 0.0,
            error: None,
        }
    }
}
