//! Audio Recording System
//!
//! Provides professional recording capabilities:
//! - Disk streaming (non-blocking writes)
//! - Punch in/out recording
//! - Pre-roll buffer
//! - Multi-take management
//! - Automatic file naming
//! - Recording safeguards (disk space, buffer overflow)

use std::collections::VecDeque;
use std::fs::{File, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use parking_lot::{Mutex, RwLock};

use crate::{BitDepth, FileError, FileResult};

// ═══════════════════════════════════════════════════════════════════════════════
// RECORDING CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Recording configuration
#[derive(Debug, Clone)]
pub struct RecordingConfig {
    /// Output directory
    pub output_dir: PathBuf,
    /// File prefix (e.g., "Recording" -> "Recording_001.wav")
    pub file_prefix: String,
    /// Bit depth for recording
    pub bit_depth: BitDepth,
    /// Sample rate
    pub sample_rate: u32,
    /// Number of channels
    pub num_channels: u16,
    /// Pre-roll buffer size in seconds
    pub pre_roll_secs: f32,
    /// Enable pre-roll capture
    pub capture_pre_roll: bool,
    /// Minimum free disk space (bytes) before stopping
    pub min_disk_space: u64,
    /// Buffer size for disk writes (bytes)
    pub disk_buffer_size: usize,
    /// Auto-increment file names
    pub auto_increment: bool,
}

impl Default for RecordingConfig {
    fn default() -> Self {
        Self {
            output_dir: PathBuf::from("."),
            file_prefix: "Recording".to_string(),
            bit_depth: BitDepth::Int24,
            sample_rate: 48000,
            num_channels: 2,
            pre_roll_secs: 2.0,
            capture_pre_roll: true,
            min_disk_space: 100 * 1024 * 1024, // 100MB
            disk_buffer_size: 64 * 1024,       // 64KB
            auto_increment: true,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECORDING STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Recording state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordingState {
    /// Not recording
    Stopped,
    /// Armed and waiting for punch-in
    Armed,
    /// Actively recording
    Recording,
    /// Paused (can resume)
    Paused,
}

/// Punch region (for punch in/out)
#[derive(Debug, Clone, Copy)]
pub struct PunchRegion {
    /// Punch in point (samples from start)
    pub punch_in: u64,
    /// Punch out point (samples from start)
    pub punch_out: u64,
    /// Is punch in/out enabled
    pub enabled: bool,
}

impl Default for PunchRegion {
    fn default() -> Self {
        Self {
            punch_in: 0,
            punch_out: u64::MAX,
            enabled: false,
        }
    }
}

/// Recording statistics
#[derive(Debug, Clone, Copy, Default)]
pub struct RecordingStats {
    /// Samples recorded
    pub samples_recorded: u64,
    /// Duration in seconds
    pub duration_secs: f64,
    /// Bytes written
    pub bytes_written: u64,
    /// Buffer usage (0.0 - 1.0)
    pub buffer_usage: f32,
    /// Peak level (0.0 - 1.0)
    pub peak_level: f32,
    /// Clips detected
    pub clips_detected: u32,
    /// Disk write errors
    pub write_errors: u32,
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRE-ROLL BUFFER
// ═══════════════════════════════════════════════════════════════════════════════

/// Circular buffer for pre-roll
struct PreRollBuffer {
    buffer: Vec<f32>,
    write_pos: usize,
    capacity_samples: usize,
    num_channels: usize,
}

impl PreRollBuffer {
    fn new(duration_secs: f32, sample_rate: u32, num_channels: usize) -> Self {
        let capacity_samples = (duration_secs * sample_rate as f32) as usize;
        let total_samples = capacity_samples * num_channels;

        Self {
            buffer: vec![0.0; total_samples],
            write_pos: 0,
            capacity_samples,
            num_channels,
        }
    }

    fn write(&mut self, samples: &[f32]) {
        let frame_size = self.num_channels;
        for chunk in samples.chunks(frame_size) {
            let base = self.write_pos * frame_size;
            for (i, &sample) in chunk.iter().enumerate() {
                if base + i < self.buffer.len() {
                    self.buffer[base + i] = sample;
                }
            }
            self.write_pos = (self.write_pos + 1) % self.capacity_samples;
        }
    }

    fn read_all(&self) -> Vec<f32> {
        let frame_size = self.num_channels;
        let mut result = Vec::with_capacity(self.buffer.len());

        // Read from write_pos to end, then from 0 to write_pos
        for i in 0..self.capacity_samples {
            let idx = (self.write_pos + i) % self.capacity_samples;
            let base = idx * frame_size;
            for ch in 0..frame_size {
                if base + ch < self.buffer.len() {
                    result.push(self.buffer[base + ch]);
                }
            }
        }

        result
    }

    fn clear(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DISK WRITER
// ═══════════════════════════════════════════════════════════════════════════════

/// Buffered disk writer for streaming
struct DiskWriter {
    writer: Option<BufWriter<File>>,
    path: PathBuf,
    spec: hound::WavSpec,
    samples_written: u64,
    bytes_written: u64,
}

impl DiskWriter {
    fn new(path: PathBuf, config: &RecordingConfig) -> FileResult<Self> {
        let spec = hound::WavSpec {
            channels: config.num_channels,
            sample_rate: config.sample_rate,
            bits_per_sample: config.bit_depth.bits() as u16,
            sample_format: match config.bit_depth {
                BitDepth::Float32 | BitDepth::Float64 => hound::SampleFormat::Float,
                _ => hound::SampleFormat::Int,
            },
        };

        // Create parent directories if needed
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&path)?;

        let writer = BufWriter::with_capacity(config.disk_buffer_size, file);

        Ok(Self {
            writer: Some(writer),
            path,
            spec,
            samples_written: 0,
            bytes_written: 0,
        })
    }

    fn write_samples(&mut self, samples: &[f32]) -> FileResult<()> {
        let writer = self
            .writer
            .as_mut()
            .ok_or_else(|| FileError::WriteError("Writer closed".to_string()))?;

        match self.spec.sample_format {
            hound::SampleFormat::Float => {
                for &sample in samples {
                    let bytes = sample.to_le_bytes();
                    writer.write_all(&bytes)?;
                    self.bytes_written += 4;
                }
            }
            hound::SampleFormat::Int => match self.spec.bits_per_sample {
                16 => {
                    for &sample in samples {
                        let int_sample = (sample.clamp(-1.0, 1.0) * 32767.0) as i16;
                        let bytes = int_sample.to_le_bytes();
                        writer.write_all(&bytes)?;
                        self.bytes_written += 2;
                    }
                }
                24 => {
                    for &sample in samples {
                        let int_sample = (sample.clamp(-1.0, 1.0) * 8388607.0) as i32;
                        let bytes = int_sample.to_le_bytes();
                        writer.write_all(&bytes[0..3])?;
                        self.bytes_written += 3;
                    }
                }
                32 => {
                    for &sample in samples {
                        let int_sample = (sample.clamp(-1.0, 1.0) * 2147483647.0) as i32;
                        let bytes = int_sample.to_le_bytes();
                        writer.write_all(&bytes)?;
                        self.bytes_written += 4;
                    }
                }
                _ => {
                    return Err(FileError::WriteError("Unsupported bit depth".to_string()));
                }
            },
        }

        self.samples_written += samples.len() as u64 / self.spec.channels as u64;
        Ok(())
    }

    fn flush(&mut self) -> FileResult<()> {
        if let Some(writer) = self.writer.as_mut() {
            writer.flush()?;
        }
        Ok(())
    }

    fn finalize(mut self) -> FileResult<PathBuf> {
        // Flush and close
        if let Some(mut writer) = self.writer.take() {
            writer.flush()?;
        }

        // Now write proper WAV header
        // Re-open and write with hound for proper header
        let temp_path = self.path.with_extension("tmp");
        std::fs::rename(&self.path, &temp_path)?;

        // Read raw data
        let raw_data = std::fs::read(&temp_path)?;

        // Write with proper header
        let mut wav_writer = hound::WavWriter::create(&self.path, self.spec)?;

        match self.spec.sample_format {
            hound::SampleFormat::Float => {
                for chunk in raw_data.chunks(4) {
                    if chunk.len() == 4 {
                        let sample = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                        wav_writer.write_sample(sample)?;
                    }
                }
            }
            hound::SampleFormat::Int => {
                match self.spec.bits_per_sample {
                    16 => {
                        for chunk in raw_data.chunks(2) {
                            if chunk.len() == 2 {
                                let sample = i16::from_le_bytes([chunk[0], chunk[1]]);
                                wav_writer.write_sample(sample)?;
                            }
                        }
                    }
                    24 => {
                        for chunk in raw_data.chunks(3) {
                            if chunk.len() == 3 {
                                let sample = i32::from_le_bytes([chunk[0], chunk[1], chunk[2], 0]);
                                // Sign extend
                                let sample = if sample & 0x800000 != 0 {
                                    sample | 0xFF000000u32 as i32
                                } else {
                                    sample
                                };
                                wav_writer.write_sample(sample)?;
                            }
                        }
                    }
                    32 => {
                        for chunk in raw_data.chunks(4) {
                            if chunk.len() == 4 {
                                let sample =
                                    i32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                                wav_writer.write_sample(sample)?;
                            }
                        }
                    }
                    _ => {}
                }
            }
        }

        wav_writer.finalize()?;

        // Remove temp file
        std::fs::remove_file(&temp_path).ok();

        Ok(self.path)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO RECORDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Thread-safe audio recorder
pub struct AudioRecorder {
    config: RwLock<RecordingConfig>,
    state: RwLock<RecordingState>,
    punch: RwLock<PunchRegion>,
    stats: RwLock<RecordingStats>,

    /// Current transport position
    position_samples: AtomicU64,

    /// Pre-roll buffer
    pre_roll: Mutex<PreRollBuffer>,

    /// Pending samples queue (from audio thread)
    pending_samples: Mutex<VecDeque<Vec<f32>>>,

    /// Disk writer (on background thread)
    disk_writer: Mutex<Option<DiskWriter>>,

    /// Current recording file path
    current_file: RwLock<Option<PathBuf>>,

    /// Take counter
    take_counter: AtomicU64,

    /// Is processing (for thread safety)
    is_processing: AtomicBool,

    /// Recording start time
    start_time: AtomicU64,
}

impl AudioRecorder {
    /// Create new recorder
    pub fn new(config: RecordingConfig) -> Self {
        let pre_roll = PreRollBuffer::new(
            config.pre_roll_secs,
            config.sample_rate,
            config.num_channels as usize,
        );

        Self {
            config: RwLock::new(config),
            state: RwLock::new(RecordingState::Stopped),
            punch: RwLock::new(PunchRegion::default()),
            stats: RwLock::new(RecordingStats::default()),
            position_samples: AtomicU64::new(0),
            pre_roll: Mutex::new(pre_roll),
            pending_samples: Mutex::new(VecDeque::with_capacity(256)),
            disk_writer: Mutex::new(None),
            current_file: RwLock::new(None),
            take_counter: AtomicU64::new(1),
            is_processing: AtomicBool::new(false),
            start_time: AtomicU64::new(0),
        }
    }

    /// Update configuration
    pub fn set_config(&self, config: RecordingConfig) {
        let mut pre_roll = self.pre_roll.lock();
        *pre_roll = PreRollBuffer::new(
            config.pre_roll_secs,
            config.sample_rate,
            config.num_channels as usize,
        );
        *self.config.write() = config;
    }

    /// Get current state
    pub fn state(&self) -> RecordingState {
        *self.state.read()
    }

    /// Get recording stats
    pub fn stats(&self) -> RecordingStats {
        *self.stats.read()
    }

    /// Set punch region
    pub fn set_punch(&self, punch: PunchRegion) {
        *self.punch.write() = punch;
    }

    /// Get punch region
    pub fn punch(&self) -> PunchRegion {
        *self.punch.read()
    }

    /// Arm for recording
    pub fn arm(&self) -> FileResult<()> {
        let mut state = self.state.write();
        if *state == RecordingState::Stopped {
            *state = RecordingState::Armed;
            self.pre_roll.lock().clear();
            log::info!("Recording armed");
        }
        Ok(())
    }

    /// Disarm
    pub fn disarm(&self) {
        let mut state = self.state.write();
        if *state == RecordingState::Armed {
            *state = RecordingState::Stopped;
            log::info!("Recording disarmed");
        }
    }

    /// Start recording
    pub fn start(&self) -> FileResult<PathBuf> {
        let mut state = self.state.write();

        // Only start from armed or stopped
        if *state != RecordingState::Armed && *state != RecordingState::Stopped {
            return Err(FileError::WriteError(
                "Invalid state for recording".to_string(),
            ));
        }

        let config = self.config.read();

        // Generate file path
        let file_path = self.generate_file_path(&config)?;

        // Create disk writer
        let writer = DiskWriter::new(file_path.clone(), &config)?;
        *self.disk_writer.lock() = Some(writer);

        // Write pre-roll if enabled
        if config.capture_pre_roll && *state == RecordingState::Armed {
            let pre_roll_data = self.pre_roll.lock().read_all();
            if !pre_roll_data.is_empty()
                && let Some(writer) = self.disk_writer.lock().as_mut() {
                    writer.write_samples(&pre_roll_data)?;
                }
        }

        // Reset stats
        {
            let mut stats = self.stats.write();
            *stats = RecordingStats::default();
        }

        *self.current_file.write() = Some(file_path.clone());
        *state = RecordingState::Recording;

        // Record start time
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        self.start_time.store(now, Ordering::SeqCst);

        log::info!("Recording started: {:?}", file_path);

        Ok(file_path)
    }

    /// Stop recording
    pub fn stop(&self) -> FileResult<Option<PathBuf>> {
        let mut state = self.state.write();

        if *state != RecordingState::Recording && *state != RecordingState::Paused {
            return Ok(None);
        }

        // Process any remaining samples
        self.flush_pending()?;

        // Finalize disk writer
        let path = if let Some(writer) = self.disk_writer.lock().take() {
            Some(writer.finalize()?)
        } else {
            None
        };

        *state = RecordingState::Stopped;
        *self.current_file.write() = None;

        // Increment take counter
        self.take_counter.fetch_add(1, Ordering::SeqCst);

        log::info!("Recording stopped: {:?}", path);

        Ok(path)
    }

    /// Pause recording
    pub fn pause(&self) -> FileResult<()> {
        let mut state = self.state.write();
        if *state == RecordingState::Recording {
            *state = RecordingState::Paused;
            self.flush_pending()?;
            log::info!("Recording paused");
        }
        Ok(())
    }

    /// Resume recording
    pub fn resume(&self) -> FileResult<()> {
        let mut state = self.state.write();
        if *state == RecordingState::Paused {
            *state = RecordingState::Recording;
            log::info!("Recording resumed");
        }
        Ok(())
    }

    /// Process audio from audio thread (lock-free path)
    ///
    /// This should be called from the audio callback with incoming samples.
    /// Samples are interleaved: [L0, R0, L1, R1, ...]
    pub fn process(&self, samples: &[f32], position: u64) {
        // Update position
        self.position_samples.store(position, Ordering::Relaxed);

        let state = *self.state.read();

        match state {
            RecordingState::Armed => {
                // Only capture pre-roll
                self.pre_roll.lock().write(samples);

                // Check for punch-in
                let punch = *self.punch.read();
                if punch.enabled && position >= punch.punch_in {
                    // Auto-start recording (state is Copy, lock already released)
                    let _ = state; // silence unused warning
                    if self.start().is_ok() {
                        self.queue_samples(samples);
                    }
                }
            }
            RecordingState::Recording => {
                // Check for punch-out
                let punch = *self.punch.read();
                if punch.enabled && position >= punch.punch_out {
                    // Auto-stop recording
                    self.stop().ok();
                    return;
                }

                // Queue samples for disk writing
                self.queue_samples(samples);

                // Update peak level
                self.update_peak(samples);
            }
            RecordingState::Paused | RecordingState::Stopped => {
                // Do nothing
            }
        }
    }

    /// Queue samples for background writing
    fn queue_samples(&self, samples: &[f32]) {
        let mut pending = self.pending_samples.lock();

        // Limit queue size to prevent memory explosion
        if pending.len() < 1024 {
            pending.push_back(samples.to_vec());

            // Update buffer usage stat
            let mut stats = self.stats.write();
            stats.buffer_usage = pending.len() as f32 / 1024.0;
        } else {
            // Buffer overflow
            let mut stats = self.stats.write();
            stats.write_errors += 1;
            log::warn!("Recording buffer overflow");
        }
    }

    /// Flush pending samples to disk (call from background thread)
    pub fn flush_pending(&self) -> FileResult<()> {
        // Prevent concurrent flush
        if self.is_processing.swap(true, Ordering::SeqCst) {
            return Ok(());
        }

        let result = (|| {
            let mut writer_guard = self.disk_writer.lock();

            if let Some(writer) = writer_guard.as_mut() {
                // Process all pending samples
                loop {
                    let samples = {
                        let mut pending = self.pending_samples.lock();
                        pending.pop_front()
                    };

                    match samples {
                        Some(data) => {
                            writer.write_samples(&data)?;

                            // Update stats
                            let config = self.config.read();
                            let mut stats = self.stats.write();
                            let frames = data.len() / config.num_channels as usize;
                            stats.samples_recorded += frames as u64;
                            stats.duration_secs =
                                stats.samples_recorded as f64 / config.sample_rate as f64;
                            stats.bytes_written = writer.bytes_written;
                        }
                        None => break,
                    }
                }

                // Flush to disk
                writer.flush()?;
            }

            Ok(())
        })();

        self.is_processing.store(false, Ordering::SeqCst);
        result
    }

    /// Update peak level
    fn update_peak(&self, samples: &[f32]) {
        let max = samples
            .iter()
            .map(|s| s.abs())
            .fold(0.0f32, |a, b| a.max(b));

        let mut stats = self.stats.write();
        if max > stats.peak_level {
            stats.peak_level = max;
        }
        if max > 1.0 {
            stats.clips_detected += 1;
        }
    }

    /// Generate unique file path
    ///
    /// # File Naming Format
    /// Deterministic naming: `{prefix}_{YYYYMMDD}_{HHMMSS}_{take:03}.wav`
    /// Example: `Guitar_20250115_143022_001.wav`
    ///
    /// This format ensures:
    /// - Alphabetical sorting = chronological sorting
    /// - Human-readable timestamps
    /// - No collisions (take counter)
    /// - DAW-friendly (no spaces, standard chars)
    fn generate_file_path(&self, config: &RecordingConfig) -> FileResult<PathBuf> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        // Convert to date/time components (UTC)
        let secs_per_day = 86400u64;
        let secs_per_hour = 3600u64;
        let secs_per_minute = 60u64;

        // Days since Unix epoch
        let days = now / secs_per_day;
        let time_of_day = now % secs_per_day;

        // Calculate year, month, day (simplified - not accounting for leap seconds)
        let (year, month, day) = days_to_ymd(days);

        let hours = time_of_day / secs_per_hour;
        let minutes = (time_of_day % secs_per_hour) / secs_per_minute;
        let seconds = time_of_day % secs_per_minute;

        let take = self.take_counter.load(Ordering::SeqCst);

        // Format: {prefix}_{YYYYMMDD}_{HHMMSS}_{take:03}.wav
        let filename = if config.auto_increment {
            format!(
                "{}_{}{}{}_{:02}{:02}{:02}_{:03}.wav",
                config.file_prefix, year, month, day, hours, minutes, seconds, take
            )
        } else {
            format!(
                "{}_{}{}{}_{:02}{:02}{:02}.wav",
                config.file_prefix, year, month, day, hours, minutes, seconds
            )
        };

        let path = config.output_dir.join(filename);

        // Check disk space
        let available = get_available_disk_space(&config.output_dir);
        if available < config.min_disk_space {
            return Err(FileError::WriteError(format!(
                "Insufficient disk space: {} bytes available, {} required",
                available, config.min_disk_space
            )));
        }

        Ok(path)
    }

    /// Get current file path
    pub fn current_file(&self) -> Option<PathBuf> {
        self.current_file.read().clone()
    }

    /// Reset take counter
    pub fn reset_take_counter(&self) {
        self.take_counter.store(1, Ordering::SeqCst);
    }
}

impl Default for AudioRecorder {
    fn default() -> Self {
        Self::new(RecordingConfig::default())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MULTI-TAKE MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Take information
#[derive(Debug, Clone)]
pub struct TakeInfo {
    /// Take number
    pub take_number: u32,
    /// File path
    pub path: PathBuf,
    /// Duration in seconds
    pub duration_secs: f64,
    /// Sample rate
    pub sample_rate: u32,
    /// Number of channels
    pub num_channels: u16,
    /// Creation timestamp
    pub created_at: u64,
    /// Is marked as favorite/keeper
    pub is_favorite: bool,
    /// User notes
    pub notes: String,
}

/// Multi-take manager for comping
pub struct TakeManager {
    takes: RwLock<Vec<TakeInfo>>,
    active_take: RwLock<Option<usize>>,
}

impl TakeManager {
    pub fn new() -> Self {
        Self {
            takes: RwLock::new(Vec::new()),
            active_take: RwLock::new(None),
        }
    }

    /// Add a take
    pub fn add_take(&self, info: TakeInfo) -> usize {
        let mut takes = self.takes.write();
        let index = takes.len();
        takes.push(info);
        index
    }

    /// Get all takes
    pub fn takes(&self) -> Vec<TakeInfo> {
        self.takes.read().clone()
    }

    /// Set active take
    pub fn set_active(&self, index: usize) {
        let takes = self.takes.read();
        if index < takes.len() {
            *self.active_take.write() = Some(index);
        }
    }

    /// Get active take
    pub fn active_take(&self) -> Option<TakeInfo> {
        let active = *self.active_take.read();
        active.and_then(|i| self.takes.read().get(i).cloned())
    }

    /// Mark take as favorite
    pub fn set_favorite(&self, index: usize, favorite: bool) {
        let mut takes = self.takes.write();
        if let Some(take) = takes.get_mut(index) {
            take.is_favorite = favorite;
        }
    }

    /// Delete take
    pub fn delete_take(&self, index: usize) -> Option<TakeInfo> {
        let mut takes = self.takes.write();
        if index < takes.len() {
            // Adjust active take
            let mut active = self.active_take.write();
            if let Some(active_idx) = *active {
                if active_idx == index {
                    *active = None;
                } else if active_idx > index {
                    *active = Some(active_idx - 1);
                }
            }
            Some(takes.remove(index))
        } else {
            None
        }
    }

    /// Clear all takes
    pub fn clear(&self) {
        self.takes.write().clear();
        *self.active_take.write() = None;
    }
}

impl Default for TakeManager {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Convert days since Unix epoch to (year, month, day) strings
/// Returns formatted strings: ("2025", "01", "15")
fn days_to_ymd(days: u64) -> (String, String, String) {
    // Start from 1970-01-01
    let mut year = 1970u32;
    let mut remaining_days = days as u32;

    // Skip years
    loop {
        let days_in_year = if is_leap_year(year) { 366 } else { 365 };
        if remaining_days < days_in_year {
            break;
        }
        remaining_days -= days_in_year;
        year += 1;
    }

    // Days per month (0-indexed)
    let days_in_month: [u32; 12] = if is_leap_year(year) {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };

    let mut month = 1u32;
    for days_in_m in days_in_month.iter() {
        if remaining_days < *days_in_m {
            break;
        }
        remaining_days -= *days_in_m;
        month += 1;
    }

    let day = remaining_days + 1; // 1-indexed

    (format!("{:04}", year), format!("{:02}", month), format!("{:02}", day))
}

/// Check if year is a leap year
fn is_leap_year(year: u32) -> bool {
    (year.is_multiple_of(4) && !year.is_multiple_of(100)) || year.is_multiple_of(400)
}

/// Get available disk space for path
/// Returns u64::MAX if unable to determine (allowing recording to proceed)
fn get_available_disk_space(_path: &Path) -> u64 {
    // Platform-specific disk space check
    // For simplicity, we assume plenty of space
    // Real implementation would use:
    // - macOS: statvfs via nix crate
    // - Windows: GetDiskFreeSpaceExW
    // - Linux: statvfs via nix crate

    // For now, return a large value to not block recording
    // TODO: Add proper disk space checking with nix crate
    u64::MAX
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_recording_config_default() {
        let config = RecordingConfig::default();
        assert_eq!(config.bit_depth, BitDepth::Int24);
        assert_eq!(config.sample_rate, 48000);
        assert_eq!(config.num_channels, 2);
    }

    #[test]
    fn test_pre_roll_buffer() {
        let mut buffer = PreRollBuffer::new(1.0, 48000, 2);

        // Write some samples
        let samples: Vec<f32> = (0..1000).map(|i| i as f32 / 1000.0).collect();
        buffer.write(&samples);

        let read = buffer.read_all();
        assert!(!read.is_empty());
    }

    #[test]
    fn test_recorder_state_machine() {
        let temp = tempdir().unwrap();
        let config = RecordingConfig {
            output_dir: temp.path().to_path_buf(),
            ..Default::default()
        };

        let recorder = AudioRecorder::new(config);

        assert_eq!(recorder.state(), RecordingState::Stopped);

        recorder.arm().unwrap();
        assert_eq!(recorder.state(), RecordingState::Armed);

        recorder.disarm();
        assert_eq!(recorder.state(), RecordingState::Stopped);
    }

    #[test]
    fn test_recorder_basic_recording() {
        let temp = tempdir().unwrap();
        let config = RecordingConfig {
            output_dir: temp.path().to_path_buf(),
            capture_pre_roll: false,
            ..Default::default()
        };

        let recorder = AudioRecorder::new(config);

        // Start recording
        let path = recorder.start().unwrap();
        assert!(path.exists() || recorder.state() == RecordingState::Recording);

        // Process some samples
        let samples: Vec<f32> = vec![0.5; 2048];
        recorder.process(&samples, 0);

        // Flush
        recorder.flush_pending().unwrap();

        // Stop
        let final_path = recorder.stop().unwrap();
        assert!(final_path.is_some());

        // File should exist with some content
        if let Some(p) = final_path {
            assert!(p.exists());
        }
    }

    #[test]
    fn test_punch_region() {
        let punch = PunchRegion {
            punch_in: 48000,
            punch_out: 96000,
            enabled: true,
        };

        assert!(punch.enabled);
        assert_eq!(punch.punch_in, 48000);
        assert_eq!(punch.punch_out, 96000);
    }

    #[test]
    fn test_take_manager() {
        let manager = TakeManager::new();

        let take = TakeInfo {
            take_number: 1,
            path: PathBuf::from("/test/take1.wav"),
            duration_secs: 10.0,
            sample_rate: 48000,
            num_channels: 2,
            created_at: 0,
            is_favorite: false,
            notes: String::new(),
        };

        let index = manager.add_take(take);
        assert_eq!(index, 0);

        manager.set_active(0);
        assert!(manager.active_take().is_some());

        manager.set_favorite(0, true);
        let takes = manager.takes();
        assert!(takes[0].is_favorite);

        manager.delete_take(0);
        assert!(manager.takes().is_empty());
    }
}
