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
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::RwLock;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};

use crate::config::OfflineConfig;
use crate::decoder::AudioDecoder;
use crate::encoder::create_encoder;
use crate::error::OfflineResult;
use crate::formats::OutputFormat;
use crate::job::{JobResult, MonoDownmix, OfflineJob};
use crate::normalize::{LoudnessMeter, NormalizationMode};
use crate::processors::{OfflineProcessor, ProcessorChain, SoftClipProcessor};

use rf_dsp::dynamics::{TruePeakLimiter, LimiterStyle, LimiterLatencyProfile};
use rf_dsp::{Processor, StereoProcessor};

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Pipeline execution state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[derive(Default)]
pub enum PipelineState {
    #[default]
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


// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE PROGRESS
// ═══════════════════════════════════════════════════════════════════════════════

/// Detailed pipeline progress tracking
#[derive(Debug, Clone)]
pub struct PipelineProgress {
    pub state: PipelineState,
    pub current_stage: String,
    pub stage_progress: f64,   // 0.0 - 1.0 within current stage
    pub overall_progress: f64, // 0.0 - 1.0 total
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

    /// Convert to mono using left channel only
    pub fn to_mono_left(&self) -> AudioBuffer {
        if self.channels == 1 {
            return self.clone();
        }
        let frames = self.frames();
        let mut mono = Vec::with_capacity(frames);
        for frame in 0..frames {
            mono.push(self.samples[frame * self.channels]);
        }
        AudioBuffer { samples: mono, channels: 1, sample_rate: self.sample_rate }
    }

    /// Convert to mono using right channel only
    pub fn to_mono_right(&self) -> AudioBuffer {
        if self.channels == 1 {
            return self.clone();
        }
        let frames = self.frames();
        let mut mono = Vec::with_capacity(frames);
        for frame in 0..frames {
            mono.push(self.samples[frame * self.channels + 1]);
        }
        AudioBuffer { samples: mono, channels: 1, sample_rate: self.sample_rate }
    }

    /// Convert to mono using mid signal: (L+R) (no division, louder)
    pub fn to_mono_mid(&self) -> AudioBuffer {
        if self.channels == 1 {
            return self.clone();
        }
        let frames = self.frames();
        let mut mono = Vec::with_capacity(frames);
        for frame in 0..frames {
            let l = self.samples[frame * self.channels];
            let r = self.samples[frame * self.channels + 1];
            mono.push(l + r);
        }
        AudioBuffer { samples: mono, channels: 1, sample_rate: self.sample_rate }
    }

    /// Convert to mono using side signal: (L-R)
    pub fn to_mono_side(&self) -> AudioBuffer {
        if self.channels == 1 {
            return self.clone();
        }
        let frames = self.frames();
        let mut mono = Vec::with_capacity(frames);
        for frame in 0..frames {
            let l = self.samples[frame * self.channels];
            let r = self.samples[frame * self.channels + 1];
            mono.push(l - r);
        }
        AudioBuffer { samples: mono, channels: 1, sample_rate: self.sample_rate }
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
        self.samples.iter().map(|s| s.abs()).fold(0.0, f64::max)
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

    /// Post-normalization soft-clip ceiling in dB (e.g., -0.3).
    /// When set, applies polynomial soft-clipping after normalization
    /// to prevent hard clipping in encoders.
    soft_clip_ceiling_db: Option<f64>,

    /// Whether to use TruePeakLimiter from rf-dsp (professional limiter
    /// with lookahead, stereo linking, oversampling).
    /// Applied after normalization, before soft-clip.
    use_true_peak_limiter: bool,
    /// Ceiling for TruePeakLimiter in dB (default -0.3)
    limiter_ceiling_db: f64,

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
            soft_clip_ceiling_db: None,
            use_true_peak_limiter: false,
            limiter_ceiling_db: -0.3,
            state: Arc::new(RwLock::new(PipelineState::Idle)),
            samples_processed: Arc::new(AtomicU64::new(0)),
            total_samples: Arc::new(AtomicU64::new(0)),
            cancelled: Arc::new(AtomicBool::new(false)),
            start_time: None,
        }
    }

    /// Set processor chain (builder pattern)
    pub fn with_processors(mut self, processors: ProcessorChain) -> Self {
        self.processors = processors;
        self
    }

    /// Set processor chain (mutable reference, for per-job use from FFI)
    pub fn set_processors(&mut self, processors: ProcessorChain) {
        self.processors = processors;
    }

    /// Set normalization mode (builder pattern)
    pub fn with_normalization(mut self, mode: NormalizationMode) -> Self {
        self.normalization = Some(mode);
        self
    }

    /// Set normalization mode (mutable reference, for FFI use)
    pub fn set_normalization(&mut self, mode: NormalizationMode) {
        self.normalization = Some(mode);
    }

    /// Clear normalization
    pub fn clear_normalization(&mut self) {
        self.normalization = None;
    }

    /// Enable soft-clipping with ceiling in dB (e.g., -0.3)
    pub fn set_soft_clip(&mut self, ceiling_db: f64) {
        self.soft_clip_ceiling_db = Some(ceiling_db);
    }

    /// Disable soft-clipping
    pub fn clear_soft_clip(&mut self) {
        self.soft_clip_ceiling_db = None;
    }

    /// Enable TruePeakLimiter with ceiling in dB
    pub fn set_true_peak_limiter(&mut self, enabled: bool, ceiling_db: f64) {
        self.use_true_peak_limiter = enabled;
        self.limiter_ceiling_db = ceiling_db;
    }

    /// Set output format (builder pattern)
    pub fn with_output_format(mut self, format: OutputFormat) -> Self {
        self.output_format = format;
        self
    }

    /// Set output format (mutable reference, for FFI use)
    pub fn set_output_format(&mut self, format: OutputFormat) {
        self.output_format = format;
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

        let elapsed_ms = self
            .start_time
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

        // Step 1b: Trim to range (silence removal)
        if let Some((start_sample, end_sample)) = job.range {
            let start = (start_sample as usize).min(buffer.samples.len());
            let end = (end_sample as usize).min(buffer.samples.len());
            if start < end {
                buffer.samples = buffer.samples[start..end].to_vec();
            }
        }

        // Step 1c: Mono downmix (before any processing)
        if let Some(method) = &job.mono_downmix {
            if buffer.channels > 1 {
                buffer = match method {
                    MonoDownmix::SumHalf => buffer.to_mono(),
                    MonoDownmix::LeftOnly => buffer.to_mono_left(),
                    MonoDownmix::RightOnly => buffer.to_mono_right(),
                    MonoDownmix::Mid => buffer.to_mono_mid(),
                    MonoDownmix::Side => buffer.to_mono_side(),
                };
            }
        }

        self.total_samples
            .store(buffer.samples.len() as u64, Ordering::Relaxed);

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

        // Step 3b: Apply fades (frame-accurate, channel-aware)
        let frames = buffer.frames();
        let ch = buffer.channels;
        if let Some(fade_in_frames) = job.fade_in {
            let fade_in = fade_in_frames as usize;
            if fade_in > 0 && fade_in <= frames {
                for frame in 0..fade_in {
                    let gain = frame as f64 / fade_in as f64;
                    for c in 0..ch {
                        buffer.samples[frame * ch + c] *= gain;
                    }
                }
            }
        }
        if let Some(fade_out_frames) = job.fade_out {
            let fade_out = fade_out_frames as usize;
            if fade_out > 0 && fade_out <= frames {
                let fade_start = frames - fade_out;
                for frame in fade_start..frames {
                    let pos = (frame - fade_start) as f64 / fade_out as f64;
                    let gain = 1.0 - pos;
                    for c in 0..ch {
                        buffer.samples[frame * ch + c] *= gain;
                    }
                }
            }
        }

        // Step 4: Normalize
        if let Some(mode) = &self.normalization {
            self.set_state(PipelineState::Normalizing);
            self.normalize_buffer(&mut buffer, *mode)?;
        }

        // Step 4b: TruePeakLimiter (post-normalization, prevents peaks exceeding ceiling)
        if self.use_true_peak_limiter {
            self.apply_true_peak_limiter(&mut buffer);
        }

        // Step 4c: Soft-clip (post-normalization, prevents hard clipping in encoder)
        if let Some(ceiling_db) = self.soft_clip_ceiling_db {
            let mut clipper = SoftClipProcessor::new(ceiling_db);
            clipper.process(&mut buffer.samples, buffer.sample_rate);
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

        // Measure integrated LUFS on final buffer
        let mut meter = LoudnessMeter::new(buffer.sample_rate, buffer.channels);
        meter.process(&buffer.samples);
        let loudness = meter.get_info().integrated;

        Ok(JobResult::success(
            job.id,
            job.output_path.clone(),
            output_size,
            self.start_time.unwrap().elapsed(),
            peak_db,
            peak_db, // true_peak (same as peak for now)
            loudness,
        ))
    }

    /// Load audio from file (supports WAV, FLAC, MP3, OGG, AAC)
    fn load_audio(&self, path: &Path) -> OfflineResult<AudioBuffer> {
        AudioDecoder::decode(path)
    }

    /// Process buffer through DSP chain
    fn process_buffer(&mut self, buffer: &mut AudioBuffer) -> OfflineResult<()> {
        // Align block size to channel count to avoid splitting frames mid-channel
        let block_size = if buffer.channels > 1 {
            (self.config.buffer_size / buffer.channels) * buffer.channels
        } else {
            self.config.buffer_size
        };
        let block_size = block_size.max(buffer.channels); // at least one frame
        let mut processed = 0;

        // Process in blocks
        for chunk in buffer.samples.chunks_mut(block_size) {
            if self.is_cancelled() {
                return Ok(());
            }

            self.processors.process_interleaved(chunk, buffer.sample_rate, buffer.channels);

            processed += chunk.len();
            self.samples_processed
                .store(processed as u64, Ordering::Relaxed);
        }

        Ok(())
    }

    /// Normalize buffer
    fn normalize_buffer(
        &self,
        buffer: &mut AudioBuffer,
        mode: NormalizationMode,
    ) -> OfflineResult<()> {
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
                // True peak detection with 4x oversampling (ITU-R BS.1770-4)
                let mut meter = LoudnessMeter::new(buffer.sample_rate, buffer.channels);

                // Process in blocks for true peak measurement
                for chunk in buffer.samples.chunks(4096) {
                    meter.process(chunk);
                }

                let info = meter.get_info();
                // true_peak is linear, convert to dB
                let current_tp_db = if info.true_peak > 0.0 {
                    20.0 * info.true_peak.log10()
                } else {
                    -f64::INFINITY
                };

                if current_tp_db > -f64::INFINITY {
                    let gain_db = target_db - current_tp_db;
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

    /// Convert sample rate using high-quality sinc resampling (rubato).
    /// Uses SincFixedIn with 256-point Kaiser-windowed sinc interpolation.
    fn convert_sample_rate(
        &self,
        buffer: AudioBuffer,
        target_rate: u32,
    ) -> OfflineResult<AudioBuffer> {
        if buffer.sample_rate == target_rate {
            return Ok(buffer);
        }

        use rubato::{SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction, Resampler};

        let ratio = target_rate as f64 / buffer.sample_rate as f64;
        let channels = buffer.channels;
        let frames = buffer.frames();

        // High-quality sinc parameters for offline mastering
        let params = SincInterpolationParameters {
            sinc_len: 256,  // 256-point sinc (mastering quality)
            f_cutoff: 0.95, // Anti-alias cutoff (Nyquist fraction)
            interpolation: SincInterpolationType::Cubic,
            oversampling_factor: 256,
            window: WindowFunction::BlackmanHarris2,
        };

        // Chunk size for processing (large for efficiency)
        let chunk_size = 1024;

        let mut resampler = SincFixedIn::<f64>::new(
            ratio,
            2.0, // max relative ratio deviation
            params,
            chunk_size,
            channels,
        ).map_err(|e| crate::error::OfflineError::ProcessingFailed(format!("SRC init: {}", e)))?;

        // De-interleave input into per-channel vectors
        let input_channels: Vec<Vec<f64>> = (0..channels)
            .map(|ch| buffer.get_channel(ch))
            .collect();

        // Process through resampler in chunks
        let mut output_channels: Vec<Vec<f64>> = vec![Vec::new(); channels];
        let mut pos = 0;

        while pos < frames {
            let end = (pos + chunk_size).min(frames);
            let chunk_len = end - pos;
            let is_last = end >= frames;

            // Build chunk for each channel
            let chunk: Vec<Vec<f64>> = input_channels.iter()
                .map(|ch| ch[pos..end].to_vec())
                .collect();

            let result = if is_last && chunk_len < chunk_size {
                // Last partial chunk: use process_partial to avoid zero-padding artifacts
                let refs: Vec<&[f64]> = chunk.iter().map(|c| c.as_slice()).collect();
                resampler.process_partial(Some(&refs), None)
            } else {
                // Full chunk
                let refs: Vec<&[f64]> = chunk.iter().map(|c| c.as_slice()).collect();
                resampler.process(&refs, None)
            };

            match result {
                Ok(out) => {
                    for (ch_idx, ch_data) in out.iter().enumerate() {
                        output_channels[ch_idx].extend_from_slice(ch_data);
                    }
                }
                Err(e) => {
                    return Err(crate::error::OfflineError::ProcessingFailed(
                        format!("SRC process: {}", e),
                    ));
                }
            }

            pos += chunk_size;
        }

        // Calculate expected output length and trim excess (from zero-padding)
        let expected_frames = (frames as f64 * ratio).ceil() as usize;
        for ch in &mut output_channels {
            ch.truncate(expected_frames);
        }

        // Re-interleave
        let out_frames = output_channels[0].len();
        let mut interleaved = Vec::with_capacity(out_frames * channels);
        for frame in 0..out_frames {
            for ch in 0..channels {
                interleaved.push(output_channels[ch].get(frame).copied().unwrap_or(0.0));
            }
        }

        Ok(AudioBuffer {
            samples: interleaved,
            channels,
            sample_rate: target_rate,
        })
    }

    /// Encode buffer to output format (supports WAV, FLAC, MP3, OGG, Opus, AAC)
    fn encode_buffer(&self, buffer: &AudioBuffer) -> OfflineResult<Vec<u8>> {
        let encoder = create_encoder(&self.output_format);
        encoder.encode(buffer)
    }

    /// Apply TruePeakLimiter from rf-dsp (professional limiter with lookahead)
    /// Operates on interleaved f64 buffer, converting to stereo L/R for processing.
    fn apply_true_peak_limiter(&self, buffer: &mut AudioBuffer) {
        let sr = buffer.sample_rate as f64;
        let mut limiter = TruePeakLimiter::new(sr);

        // Configure for offline mastering: max quality, full lookahead
        limiter.set_ceiling(self.limiter_ceiling_db);
        limiter.set_latency_profile(LimiterLatencyProfile::OfflineMax);
        limiter.set_style(LimiterStyle::Allround);
        limiter.set_threshold(0.0); // Limit everything above ceiling

        let ch = buffer.channels;
        let frames = buffer.frames();

        if ch == 1 {
            // Mono: duplicate to stereo, process, take left
            let mut left = buffer.get_channel(0);
            let mut right = left.clone();
            limiter.process_block(&mut left, &mut right);
            buffer.set_channel(0, &left);
        } else if ch == 2 {
            // Stereo: direct processing
            let mut left = buffer.get_channel(0);
            let mut right = buffer.get_channel(1);
            limiter.process_block(&mut left, &mut right);
            buffer.set_channel(0, &left);
            buffer.set_channel(1, &right);
        } else {
            // Multi-channel: process pairs (ch0+ch1, ch2+ch3, ...)
            // with fallback for odd channel count
            let mut c = 0;
            while c < ch {
                let mut left = buffer.get_channel(c);
                let mut right = if c + 1 < ch {
                    buffer.get_channel(c + 1)
                } else {
                    left.clone()
                };
                limiter.reset();
                limiter.process_block(&mut left, &mut right);
                buffer.set_channel(c, &left);
                if c + 1 < ch {
                    buffer.set_channel(c + 1, &right);
                }
                c += 2;
            }
        }

        // Compensate limiter latency: lookahead introduces leading delay.
        // Remove leading latency samples and trim to original length.
        let latency = limiter.latency_samples();
        if latency > 0 && latency < frames {
            let remove_samples = latency * ch;
            buffer.samples.drain(..remove_samples);
            // Pad end to maintain original duration (limiter consumed those samples)
            buffer.samples.resize(frames * ch, 0.0);
        }
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
                        pipeline = pipeline.with_normalization(*mode);
                    }
                    pipeline = pipeline.with_output_format(self.output_format.clone());

                    match pipeline.process_job(job) {
                        Ok(result) => result,
                        Err(e) => {
                            JobResult::failure(job.id, e.to_string(), std::time::Duration::ZERO)
                        }
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
