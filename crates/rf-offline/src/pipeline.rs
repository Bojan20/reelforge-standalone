//! Main offline processing pipeline
//!
//! Orchestrates the complete offline rendering workflow:
//! 1. Load source audio
//! 2. Apply DSP chain
//! 3. Normalize (optional)
//! 4. Convert sample rate (optional)
//! 5. Encode to output format
//! 6. Write to disk

use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use parking_lot::RwLock;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};

use crate::config::OfflineConfig;
use crate::error::{OfflineError, OfflineResult};
use crate::formats::OutputFormat;
use crate::job::{JobResult, OfflineJob};
use crate::normalize::{LoudnessMeter, NormalizationMode};
use crate::processors::ProcessorChain;

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Pipeline execution state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PipelineState {
    Idle,
    Loading,
    Analyzing,
    Processing,
    Normalizing,
    Converting,
    Encoding,
    Writing,
    Complete,
    Failed,
    Cancelled,
}

impl Default for PipelineState {
    fn default() -> Self {
        Self::Idle
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE PROGRESS
// ═══════════════════════════════════════════════════════════════════════════════

/// Detailed pipeline progress tracking
#[derive(Debug, Clone)]
pub struct PipelineProgress {
    pub state: PipelineState,
    pub current_stage: String,
    pub stage_progress: f64,    // 0.0 - 1.0 within current stage
    pub overall_progress: f64,  // 0.0 - 1.0 total
    pub samples_processed: u64,
    pub total_samples: u64,
    pub elapsed_ms: u64,
    pub estimated_remaining_ms: Option<u64>,
}

impl Default for PipelineProgress {
    fn default() -> Self {
        Self {
            state: PipelineState::Idle,
            current_stage: String::new(),
            stage_progress: 0.0,
            overall_progress: 0.0,
            samples_processed: 0,
            total_samples: 0,
            elapsed_ms: 0,
            estimated_remaining_ms: None,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO BUFFER
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio buffer for offline processing (f64 for maximum precision)
#[derive(Debug, Clone)]
pub struct AudioBuffer {
    /// Interleaved samples
    pub samples: Vec<f64>,
    /// Number of channels
    pub channels: usize,
    /// Sample rate
    pub sample_rate: u32,
}

impl AudioBuffer {
    /// Create new buffer
    pub fn new(channels: usize, sample_rate: u32) -> Self {
        Self {
            samples: Vec::new(),
            channels,
            sample_rate,
        }
    }

    /// Create buffer with capacity
    pub fn with_capacity(channels: usize, sample_rate: u32, frames: usize) -> Self {
        Self {
            samples: Vec::with_capacity(frames * channels),
            channels,
            sample_rate,
        }
    }

    /// Number of frames
    pub fn frames(&self) -> usize {
        if self.channels == 0 {
            0
        } else {
            self.samples.len() / self.channels
        }
    }

    /// Duration in seconds
    pub fn duration(&self) -> f64 {
        if self.sample_rate == 0 {
            0.0
        } else {
            self.frames() as f64 / self.sample_rate as f64
        }
    }

    /// Get channel slice (non-interleaved view)
    pub fn get_channel(&self, channel: usize) -> Vec<f64> {
        if channel >= self.channels {
            return Vec::new();
        }
        self.samples
            .iter()
            .skip(channel)
            .step_by(self.channels)
            .copied()
            .collect()
    }

    /// Set channel data
    pub fn set_channel(&mut self, channel: usize, data: &[f64]) {
        if channel >= self.channels {
            return;
        }
        for (i, &sample) in data.iter().enumerate() {
            let idx = i * self.channels + channel;
            if idx < self.samples.len() {
                self.samples[idx] = sample;
            }
        }
    }

    /// Convert to mono (mixdown)
    pub fn to_mono(&self) -> AudioBuffer {
        if self.channels == 1 {
            return self.clone();
        }

        let frames = self.frames();
        let mut mono = Vec::with_capacity(frames);

        for frame in 0..frames {
            let mut sum = 0.0;
            for ch in 0..self.channels {
                sum += self.samples[frame * self.channels + ch];
            }
            mono.push(sum / self.channels as f64);
        }

        AudioBuffer {
            samples: mono,
            channels: 1,
            sample_rate: self.sample_rate,
        }
    }

    /// Convert mono to stereo
    pub fn to_stereo(&self) -> AudioBuffer {
        if self.channels == 2 {
            return self.clone();
        }
        if self.channels != 1 {
            // For multi-channel, just take first two
            let frames = self.frames();
            let mut stereo = Vec::with_capacity(frames * 2);
            for frame in 0..frames {
                stereo.push(self.samples[frame * self.channels]);
                stereo.push(self.samples[frame * self.channels + 1.min(self.channels - 1)]);
            }
            return AudioBuffer {
                samples: stereo,
                channels: 2,
                sample_rate: self.sample_rate,
            };
        }

        // Mono to stereo
        let mut stereo = Vec::with_capacity(self.samples.len() * 2);
        for &sample in &self.samples {
            stereo.push(sample);
            stereo.push(sample);
        }

        AudioBuffer {
            samples: stereo,
            channels: 2,
            sample_rate: self.sample_rate,
        }
    }

    /// Apply gain
    pub fn apply_gain(&mut self, gain: f64) {
        for sample in &mut self.samples {
            *sample *= gain;
        }
    }

    /// Get peak level (linear)
    pub fn peak(&self) -> f64 {
        self.samples
            .iter()
            .map(|s| s.abs())
            .fold(0.0, f64::max)
    }

    /// Get peak level (dB)
    pub fn peak_db(&self) -> f64 {
        let peak = self.peak();
        if peak <= 0.0 {
            -f64::INFINITY
        } else {
            20.0 * peak.log10()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OFFLINE PIPELINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Main offline processing pipeline
pub struct OfflinePipeline {
    config: OfflineConfig,
    processors: ProcessorChain,
    normalization: Option<NormalizationMode>,
    output_format: OutputFormat,

    // Progress tracking
    state: Arc<RwLock<PipelineState>>,
    samples_processed: Arc<AtomicU64>,
    total_samples: Arc<AtomicU64>,
    cancelled: Arc<AtomicBool>,
    start_time: Option<std::time::Instant>,
}

impl OfflinePipeline {
    /// Create new pipeline with config
    pub fn new(config: OfflineConfig) -> Self {
        Self {
            config,
            processors: ProcessorChain::new(),
            normalization: None,
            output_format: OutputFormat::wav_16(),
            state: Arc::new(RwLock::new(PipelineState::Idle)),
            samples_processed: Arc::new(AtomicU64::new(0)),
            total_samples: Arc::new(AtomicU64::new(0)),
            cancelled: Arc::new(AtomicBool::new(false)),
            start_time: None,
        }
    }

    /// Set processor chain
    pub fn with_processors(mut self, processors: ProcessorChain) -> Self {
        self.processors = processors;
        self
    }

    /// Set normalization mode
    pub fn with_normalization(mut self, mode: NormalizationMode) -> Self {
        self.normalization = Some(mode);
        self
    }

    /// Set output format
    pub fn with_output_format(mut self, format: OutputFormat) -> Self {
        self.output_format = format;
        self
    }

    /// Cancel processing
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    /// Check if cancelled
    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }

    /// Get current state
    pub fn state(&self) -> PipelineState {
        *self.state.read()
    }

    /// Get progress
    pub fn progress(&self) -> PipelineProgress {
        let state = *self.state.read();
        let samples_processed = self.samples_processed.load(Ordering::Relaxed);
        let total_samples = self.total_samples.load(Ordering::Relaxed);

        let stage_progress = if total_samples > 0 {
            samples_processed as f64 / total_samples as f64
        } else {
            0.0
        };

        // Calculate overall progress based on state
        let stage_weight = match state {
            PipelineState::Idle => 0.0,
            PipelineState::Loading => 0.05,
            PipelineState::Analyzing => 0.15,
            PipelineState::Processing => 0.50,
            PipelineState::Normalizing => 0.70,
            PipelineState::Converting => 0.80,
            PipelineState::Encoding => 0.90,
            PipelineState::Writing => 0.95,
            PipelineState::Complete => 1.0,
            PipelineState::Failed | PipelineState::Cancelled => 0.0,
        };

        let elapsed_ms = self.start_time
            .map(|t| t.elapsed().as_millis() as u64)
            .unwrap_or(0);

        let estimated_remaining_ms = if stage_progress > 0.0 && elapsed_ms > 0 {
            let total_estimated = (elapsed_ms as f64 / stage_progress) as u64;
            Some(total_estimated.saturating_sub(elapsed_ms))
        } else {
            None
        };

        PipelineProgress {
            state,
            current_stage: format!("{:?}", state),
            stage_progress,
            overall_progress: stage_weight,
            samples_processed,
            total_samples,
            elapsed_ms,
            estimated_remaining_ms,
        }
    }

    /// Set state
    fn set_state(&self, state: PipelineState) {
        *self.state.write() = state;
    }

    /// Process a single job
    pub fn process_job(&mut self, job: &OfflineJob) -> OfflineResult<JobResult> {
        self.cancelled.store(false, Ordering::SeqCst);
        self.samples_processed.store(0, Ordering::Relaxed);
        self.start_time = Some(std::time::Instant::now());

        // Step 1: Load audio
        self.set_state(PipelineState::Loading);
        let mut buffer = self.load_audio(&job.input_path)?;

        if self.is_cancelled() {
            self.set_state(PipelineState::Cancelled);
            return Ok(JobResult::cancelled(
                job.id,
                self.start_time.unwrap().elapsed(),
            ));
        }

        self.total_samples.store(buffer.samples.len() as u64, Ordering::Relaxed);

        // Step 2: Analyze if normalizing
        if self.normalization.is_some() {
            self.set_state(PipelineState::Analyzing);
            // Analysis happens during normalization
        }

        // Step 3: Process through DSP chain
        self.set_state(PipelineState::Processing);
        self.process_buffer(&mut buffer)?;

        if self.is_cancelled() {
            self.set_state(PipelineState::Cancelled);
            return Ok(JobResult::cancelled(
                job.id,
                self.start_time.unwrap().elapsed(),
            ));
        }

        // Step 4: Normalize
        if let Some(mode) = &self.normalization {
            self.set_state(PipelineState::Normalizing);
            self.normalize_buffer(&mut buffer, mode.clone())?;
        }

        // Step 5: Sample rate conversion (if needed)
        if let Some(target_rate) = job.sample_rate {
            if target_rate != buffer.sample_rate {
                self.set_state(PipelineState::Converting);
                buffer = self.convert_sample_rate(buffer, target_rate)?;
            }
        }

        // Step 6: Encode
        self.set_state(PipelineState::Encoding);
        let encoded = self.encode_buffer(&buffer)?;

        // Step 7: Write
        self.set_state(PipelineState::Writing);
        self.write_output(&job.output_path, &encoded)?;

        self.set_state(PipelineState::Complete);

        // Measure final audio statistics
        let peak_db = buffer.peak_db();
        let output_size = encoded.len() as u64;

        Ok(JobResult::success(
            job.id,
            job.output_path.clone(),
            output_size,
            self.start_time.unwrap().elapsed(),
            peak_db,
            peak_db, // true_peak (same as peak for now)
            -23.0,   // loudness placeholder (needs proper LUFS metering)
        ))
    }

    /// Load audio from file
    fn load_audio(&self, path: &Path) -> OfflineResult<AudioBuffer> {
        // For now, use hound for WAV files
        // TODO: Use symphonia for other formats

        let extension = path.extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase())
            .unwrap_or_default();

        match extension.as_str() {
            "wav" => self.load_wav(path),
            "flac" => self.load_flac(path),
            _ => Err(OfflineError::UnsupportedFormat(extension)),
        }
    }

    /// Load WAV file
    fn load_wav(&self, path: &Path) -> OfflineResult<AudioBuffer> {
        let reader = hound::WavReader::open(path)
            .map_err(|e| OfflineError::ReadError(e.to_string()))?;

        let spec = reader.spec();
        let channels = spec.channels as usize;
        let sample_rate = spec.sample_rate;

        let samples: Vec<f64> = match spec.sample_format {
            hound::SampleFormat::Int => {
                let max_val = (1i64 << (spec.bits_per_sample - 1)) as f64;
                reader
                    .into_samples::<i32>()
                    .filter_map(|s: Result<i32, _>| s.ok())
                    .map(|s| s as f64 / max_val)
                    .collect()
            }
            hound::SampleFormat::Float => {
                reader
                    .into_samples::<f32>()
                    .filter_map(|s: Result<f32, _>| s.ok())
                    .map(|s| s as f64)
                    .collect()
            }
        };

        Ok(AudioBuffer {
            samples,
            channels,
            sample_rate,
        })
    }

    /// Load FLAC file (stub - needs symphonia)
    fn load_flac(&self, _path: &Path) -> OfflineResult<AudioBuffer> {
        // TODO: Implement with symphonia
        Err(OfflineError::UnsupportedFormat("flac".to_string()))
    }

    /// Process buffer through DSP chain
    fn process_buffer(&mut self, buffer: &mut AudioBuffer) -> OfflineResult<()> {
        let block_size = self.config.buffer_size;
        let total_samples = buffer.samples.len();
        let mut processed = 0;

        // Process in blocks
        for chunk in buffer.samples.chunks_mut(block_size) {
            if self.is_cancelled() {
                return Ok(());
            }

            self.processors.process(chunk, buffer.sample_rate);

            processed += chunk.len();
            self.samples_processed.store(processed as u64, Ordering::Relaxed);
        }

        Ok(())
    }

    /// Normalize buffer
    fn normalize_buffer(&self, buffer: &mut AudioBuffer, mode: NormalizationMode) -> OfflineResult<()> {
        match mode {
            NormalizationMode::Peak { target_db } => {
                let current_peak = buffer.peak_db();
                if current_peak > -f64::INFINITY {
                    let gain_db = target_db - current_peak;
                    let gain_linear = 10.0_f64.powf(gain_db / 20.0);
                    buffer.apply_gain(gain_linear);
                }
            }
            NormalizationMode::Lufs { target_lufs } => {
                // Measure current loudness
                let mut meter = LoudnessMeter::new(buffer.sample_rate, buffer.channels);

                // Process in blocks
                for chunk in buffer.samples.chunks(4096) {
                    meter.process(chunk);
                }

                let info = meter.get_info();
                if info.integrated > -f64::INFINITY {
                    let gain_db = target_lufs - info.integrated;
                    let gain_linear = 10.0_f64.powf(gain_db / 20.0);
                    buffer.apply_gain(gain_linear);
                }
            }
            NormalizationMode::TruePeak { target_db } => {
                // Simple peak normalization for now
                // TODO: Implement true peak detection with oversampling
                let current_peak = buffer.peak_db();
                if current_peak > -f64::INFINITY {
                    let gain_db = target_db - current_peak;
                    let gain_linear = 10.0_f64.powf(gain_db / 20.0);
                    buffer.apply_gain(gain_linear);
                }
            }
            NormalizationMode::NoClip => {
                // Just ensure no clipping
                let peak = buffer.peak();
                if peak > 1.0 {
                    buffer.apply_gain(1.0 / peak);
                }
            }
        }
        Ok(())
    }

    /// Convert sample rate
    fn convert_sample_rate(&self, buffer: AudioBuffer, target_rate: u32) -> OfflineResult<AudioBuffer> {
        if buffer.sample_rate == target_rate {
            return Ok(buffer);
        }

        // Simple linear interpolation SRC
        // TODO: Use higher quality resampling (sinc, polyphase)
        let ratio = target_rate as f64 / buffer.sample_rate as f64;
        let new_frames = (buffer.frames() as f64 * ratio).ceil() as usize;
        let mut new_samples = Vec::with_capacity(new_frames * buffer.channels);

        for frame in 0..new_frames {
            let src_pos = frame as f64 / ratio;
            let src_frame = src_pos.floor() as usize;
            let frac = src_pos - src_frame as f64;

            for ch in 0..buffer.channels {
                let idx0 = src_frame * buffer.channels + ch;
                let idx1 = ((src_frame + 1).min(buffer.frames() - 1)) * buffer.channels + ch;

                let s0 = buffer.samples.get(idx0).copied().unwrap_or(0.0);
                let s1 = buffer.samples.get(idx1).copied().unwrap_or(0.0);

                // Linear interpolation
                let sample = s0 + (s1 - s0) * frac;
                new_samples.push(sample);
            }
        }

        Ok(AudioBuffer {
            samples: new_samples,
            channels: buffer.channels,
            sample_rate: target_rate,
        })
    }

    /// Encode buffer to output format
    fn encode_buffer(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        match &self.output_format {
            OutputFormat::Wav(config) => {
                self.encode_wav(buffer, config.bit_depth as u16)
            }
            OutputFormat::Flac(config) => {
                self.encode_flac(buffer, config.bit_depth as u16)
            }
            _ => {
                // TODO: Implement other encoders
                Err(OfflineError::UnsupportedFormat(format!("{:?}", self.output_format)))
            }
        }
    }

    /// Encode to WAV
    fn encode_wav(&self, buffer: &AudioBuffer, bit_depth: u16) -> OfflineResult<Vec<u8>> {
        let mut output = Vec::new();
        let cursor = std::io::Cursor::new(&mut output);

        let spec = hound::WavSpec {
            channels: buffer.channels as u16,
            sample_rate: buffer.sample_rate,
            bits_per_sample: bit_depth,
            sample_format: if bit_depth == 32 {
                hound::SampleFormat::Float
            } else {
                hound::SampleFormat::Int
            },
        };

        let mut writer = hound::WavWriter::new(cursor, spec)
            .map_err(|e| OfflineError::EncodingError(e.to_string()))?;

        match bit_depth {
            16 => {
                for &sample in &buffer.samples {
                    let s = (sample.clamp(-1.0, 1.0) * 32767.0) as i16;
                    writer.write_sample(s)
                        .map_err(|e| OfflineError::EncodingError(e.to_string()))?;
                }
            }
            24 => {
                for &sample in &buffer.samples {
                    let s = (sample.clamp(-1.0, 1.0) * 8388607.0) as i32;
                    writer.write_sample(s)
                        .map_err(|e| OfflineError::EncodingError(e.to_string()))?;
                }
            }
            32 => {
                for &sample in &buffer.samples {
                    writer.write_sample(sample as f32)
                        .map_err(|e| OfflineError::EncodingError(e.to_string()))?;
                }
            }
            _ => {
                return Err(OfflineError::ConfigError(format!(
                    "Unsupported bit depth: {}",
                    bit_depth
                )));
            }
        }

        writer.finalize()
            .map_err(|e| OfflineError::EncodingError(e.to_string()))?;

        Ok(output)
    }

    /// Encode to FLAC (stub)
    fn encode_flac(&self, _buffer: &AudioBuffer, _bit_depth: u16) -> OfflineResult<Vec<u8>> {
        // TODO: Implement FLAC encoding
        Err(OfflineError::UnsupportedFormat("flac encoding".to_string()))
    }

    /// Write output to file
    fn write_output(&self, path: &Path, data: &[u8]) -> OfflineResult<()> {
        // Create parent directories if needed
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        std::fs::write(path, data)?;
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BATCH PROCESSOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Batch processor for multiple jobs
pub struct BatchProcessor {
    config: OfflineConfig,
    processors: ProcessorChain,
    normalization: Option<NormalizationMode>,
    output_format: OutputFormat,
    max_parallel: usize,
}

impl BatchProcessor {
    /// Create new batch processor
    pub fn new(config: OfflineConfig) -> Self {
        Self {
            config,
            processors: ProcessorChain::new(),
            normalization: None,
            output_format: OutputFormat::wav_16(),
            max_parallel: rayon::current_num_threads(),
        }
    }

    /// Set processor chain
    pub fn with_processors(mut self, processors: ProcessorChain) -> Self {
        self.processors = processors;
        self
    }

    /// Set normalization
    pub fn with_normalization(mut self, mode: NormalizationMode) -> Self {
        self.normalization = Some(mode);
        self
    }

    /// Set output format
    pub fn with_output_format(mut self, format: OutputFormat) -> Self {
        self.output_format = format;
        self
    }

    /// Set max parallel jobs
    pub fn with_max_parallel(mut self, max: usize) -> Self {
        self.max_parallel = max.max(1);
        self
    }

    /// Process all jobs in parallel
    pub fn process_all(&self, jobs: &[OfflineJob]) -> Vec<JobResult> {
        // Use rayon for parallel processing
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(self.max_parallel)
            .build()
            .unwrap_or_else(|_| rayon::ThreadPoolBuilder::new().build().unwrap());

        pool.install(|| {
            jobs.par_iter()
                .map(|job| {
                    let mut pipeline = OfflinePipeline::new(self.config.clone());

                    // Note: ProcessorChain is not Clone, so we'd need to recreate it
                    // For now, use default chain
                    if let Some(ref mode) = self.normalization {
                        pipeline = pipeline.with_normalization(mode.clone());
                    }
                    pipeline = pipeline.with_output_format(self.output_format.clone());

                    match pipeline.process_job(job) {
                        Ok(result) => result,
                        Err(e) => JobResult::failure(
                            job.id,
                            e.to_string(),
                            std::time::Duration::ZERO,
                        ),
                    }
                })
                .collect()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audio_buffer_mono_to_stereo() {
        let mono = AudioBuffer {
            samples: vec![0.5, -0.5, 0.25],
            channels: 1,
            sample_rate: 44100,
        };

        let stereo = mono.to_stereo();
        assert_eq!(stereo.channels, 2);
        assert_eq!(stereo.samples.len(), 6);
        assert_eq!(stereo.samples, vec![0.5, 0.5, -0.5, -0.5, 0.25, 0.25]);
    }

    #[test]
    fn test_audio_buffer_stereo_to_mono() {
        let stereo = AudioBuffer {
            samples: vec![0.5, 0.3, -0.5, -0.3, 0.25, 0.15],
            channels: 2,
            sample_rate: 44100,
        };

        let mono = stereo.to_mono();
        assert_eq!(mono.channels, 1);
        assert_eq!(mono.samples.len(), 3);
        assert!((mono.samples[0] - 0.4).abs() < 0.001);
        assert!((mono.samples[1] - (-0.4)).abs() < 0.001);
        assert!((mono.samples[2] - 0.2).abs() < 0.001);
    }

    #[test]
    fn test_audio_buffer_peak() {
        let buffer = AudioBuffer {
            samples: vec![0.5, -0.8, 0.3, -0.2],
            channels: 1,
            sample_rate: 44100,
        };

        assert!((buffer.peak() - 0.8).abs() < 0.001);
    }

    #[test]
    fn test_audio_buffer_gain() {
        let mut buffer = AudioBuffer {
            samples: vec![0.5, -0.5],
            channels: 1,
            sample_rate: 44100,
        };

        buffer.apply_gain(2.0);
        assert!((buffer.samples[0] - 1.0).abs() < 0.001);
        assert!((buffer.samples[1] - (-1.0)).abs() < 0.001);
    }
}
