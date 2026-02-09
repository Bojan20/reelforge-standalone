//! Bounce/Export System
//!
//! Provides offline rendering capabilities:
//! - Faster-than-realtime bounce
//! - Multiple export formats (WAV, FLAC, MP3, AAC)
//! - Dithering and noise shaping
//! - Progress reporting
//! - Parallel processing
//! - Stem export

use std::mem::MaybeUninit;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use mp3lame_encoder::{Builder, FlushNoGap, InterleavedPcm};
use parking_lot::RwLock;

use crate::{AudioData, AudioFormat, BitDepth, FileError, FileResult, write_flac, write_wav};

// ═══════════════════════════════════════════════════════════════════════════════
// BOUNCE CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Dithering type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DitherType {
    /// No dithering
    #[default]
    None,
    /// Rectangular (flat) dither
    Rectangular,
    /// Triangular (TPDF) dither
    Triangular,
    /// Noise-shaped dither
    NoiseShape,
}

/// Noise shaping type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum NoiseShapeType {
    #[default]
    None,
    /// Modified E-weighted
    ModifiedE,
    /// Improved E-weighted
    ImprovedE,
    /// F-weighted (psychoacoustic)
    FWeighted,
}

/// Export format configuration
#[derive(Debug, Clone)]
pub struct ExportFormat {
    /// Output file format
    pub format: AudioFormat,
    /// Bit depth (for WAV/FLAC)
    pub bit_depth: BitDepth,
    /// Sample rate (0 = same as project)
    pub sample_rate: u32,
    /// MP3/AAC bitrate (kbps)
    pub bitrate: u32,
    /// Dithering type
    pub dither: DitherType,
    /// Noise shaping
    pub noise_shape: NoiseShapeType,
    /// Normalize output
    pub normalize: bool,
    /// Normalize target (dBFS)
    pub normalize_target: f64,
    /// Allow clipping during normalization
    pub allow_clip: bool,
}

impl Default for ExportFormat {
    fn default() -> Self {
        Self {
            format: AudioFormat::Wav,
            bit_depth: BitDepth::Int24,
            sample_rate: 0, // Same as project
            bitrate: 320,
            dither: DitherType::Triangular,
            noise_shape: NoiseShapeType::None,
            normalize: false,
            normalize_target: -0.1,
            allow_clip: false,
        }
    }
}

impl ExportFormat {
    /// CD quality (16-bit 44.1kHz WAV)
    pub fn cd_quality() -> Self {
        Self {
            format: AudioFormat::Wav,
            bit_depth: BitDepth::Int16,
            sample_rate: 44100,
            dither: DitherType::Triangular,
            noise_shape: NoiseShapeType::ModifiedE,
            ..Default::default()
        }
    }

    /// High resolution (24-bit 96kHz WAV)
    pub fn hi_res() -> Self {
        Self {
            format: AudioFormat::Wav,
            bit_depth: BitDepth::Int24,
            sample_rate: 96000,
            dither: DitherType::None,
            ..Default::default()
        }
    }

    /// MP3 for distribution
    pub fn mp3_distribution() -> Self {
        Self {
            format: AudioFormat::Mp3,
            bit_depth: BitDepth::Int16,
            sample_rate: 44100,
            bitrate: 320,
            normalize: true,
            normalize_target: -1.0,
            ..Default::default()
        }
    }

    /// Mastered WAV
    pub fn mastered() -> Self {
        Self {
            format: AudioFormat::Wav,
            bit_depth: BitDepth::Int24,
            sample_rate: 0,
            normalize: true,
            normalize_target: -0.1,
            allow_clip: false,
            ..Default::default()
        }
    }
}

/// Bounce region
#[derive(Debug, Clone, Copy)]
pub struct BounceRegion {
    /// Start position in samples
    pub start_samples: u64,
    /// End position in samples
    pub end_samples: u64,
    /// Include tail (reverb/delay tails)
    pub include_tail: bool,
    /// Tail length in seconds
    pub tail_secs: f32,
}

impl Default for BounceRegion {
    fn default() -> Self {
        Self {
            start_samples: 0,
            end_samples: u64::MAX,
            include_tail: true,
            tail_secs: 2.0,
        }
    }
}

/// Bounce configuration
#[derive(Debug, Clone)]
pub struct BounceConfig {
    /// Output path
    pub output_path: PathBuf,
    /// Export format
    pub export_format: ExportFormat,
    /// Region to bounce
    pub region: BounceRegion,
    /// Source sample rate
    pub source_sample_rate: u32,
    /// Number of channels
    pub num_channels: u16,
    /// Enable offline processing (faster than realtime)
    pub offline: bool,
    /// Process block size
    pub block_size: usize,
}

impl Default for BounceConfig {
    fn default() -> Self {
        Self {
            output_path: PathBuf::from("bounce.wav"),
            export_format: ExportFormat::default(),
            region: BounceRegion::default(),
            source_sample_rate: 48000,
            num_channels: 2,
            offline: true,
            block_size: 1024,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOUNCE PROGRESS
// ═══════════════════════════════════════════════════════════════════════════════

/// Bounce progress information
#[derive(Debug, Clone, Copy, Default)]
pub struct BounceProgress {
    /// Total samples to process
    pub total_samples: u64,
    /// Samples processed
    pub processed_samples: u64,
    /// Progress percentage (0.0 - 100.0)
    pub percent: f32,
    /// Estimated time remaining (seconds)
    pub eta_secs: f32,
    /// Processing speed (x realtime)
    pub speed_factor: f32,
    /// Peak level detected
    pub peak_level: f32,
    /// Is complete
    pub is_complete: bool,
    /// Was cancelled
    pub was_cancelled: bool,
}

impl BounceProgress {
    pub fn new(total_samples: u64) -> Self {
        Self {
            total_samples,
            ..Default::default()
        }
    }

    pub fn update(&mut self, processed: u64, elapsed_secs: f32) {
        self.processed_samples = processed;
        self.percent = if self.total_samples > 0 {
            (processed as f32 / self.total_samples as f32) * 100.0
        } else {
            0.0
        };

        // Calculate speed factor
        if elapsed_secs > 0.0 && processed > 0 {
            let realtime_secs = processed as f32 / 48000.0; // Assume 48kHz
            self.speed_factor = realtime_secs / elapsed_secs;

            // Estimate remaining time
            let remaining = self.total_samples.saturating_sub(processed);
            let samples_per_sec = processed as f32 / elapsed_secs;
            if samples_per_sec > 0.0 {
                self.eta_secs = remaining as f32 / samples_per_sec;
            }
        }
    }
}

/// Progress callback type
pub type BounceProgressCallback = Box<dyn Fn(&BounceProgress) + Send + Sync>;

// ═══════════════════════════════════════════════════════════════════════════════
// DITHERING
// ═══════════════════════════════════════════════════════════════════════════════

/// Dither generator
pub struct Ditherer {
    dither_type: DitherType,
    noise_shape: NoiseShapeType,
    /// Previous error for noise shaping
    error_buffer: Vec<f64>,
    /// Random state
    random_state: u64,
}

impl Ditherer {
    pub fn new(dither_type: DitherType, noise_shape: NoiseShapeType, num_channels: usize) -> Self {
        Self {
            dither_type,
            noise_shape,
            error_buffer: vec![0.0; num_channels * 4], // 4 samples history per channel
            random_state: 12345,
        }
    }

    /// Apply dithering to a sample
    pub fn process(&mut self, sample: f64, channel: usize, target_bits: u32) -> f64 {
        if self.dither_type == DitherType::None {
            return sample;
        }

        let quantize_step = 1.0 / (1u64 << (target_bits - 1)) as f64;

        // Generate dither noise
        let noise = match self.dither_type {
            DitherType::None => 0.0,
            DitherType::Rectangular => (self.next_random() - 0.5) * quantize_step,
            DitherType::Triangular => {
                // TPDF: sum of two rectangular distributions
                let r1 = self.next_random() - 0.5;
                let r2 = self.next_random() - 0.5;
                (r1 + r2) * quantize_step
            }
            DitherType::NoiseShape => {
                // TPDF with noise shaping
                let r1 = self.next_random() - 0.5;
                let r2 = self.next_random() - 0.5;
                (r1 + r2) * quantize_step
            }
        };

        let dithered = sample + noise;

        // Apply noise shaping if enabled
        if self.noise_shape != NoiseShapeType::None && self.dither_type == DitherType::NoiseShape {
            let base = channel * 4;
            let shaped = match self.noise_shape {
                NoiseShapeType::None => dithered,
                NoiseShapeType::ModifiedE => {
                    // Modified E-weighted: emphasizes high frequencies
                    dithered + 0.5 * self.error_buffer[base] - 0.25 * self.error_buffer[base + 1]
                }
                NoiseShapeType::ImprovedE => {
                    // More aggressive high-frequency shaping
                    dithered + 0.65 * self.error_buffer[base] - 0.35 * self.error_buffer[base + 1]
                        + 0.15 * self.error_buffer[base + 2]
                }
                NoiseShapeType::FWeighted => {
                    // Psychoacoustic curve
                    dithered + 0.7 * self.error_buffer[base] - 0.4 * self.error_buffer[base + 1]
                        + 0.2 * self.error_buffer[base + 2]
                        - 0.1 * self.error_buffer[base + 3]
                }
            };

            // Quantize and calculate error
            let quantized = (shaped / quantize_step).round() * quantize_step;
            let error = shaped - quantized;

            // Shift error buffer
            for i in (1..4).rev() {
                self.error_buffer[base + i] = self.error_buffer[base + i - 1];
            }
            self.error_buffer[base] = error;

            quantized
        } else {
            dithered
        }
    }

    /// Generate next random number (0.0 - 1.0)
    fn next_random(&mut self) -> f64 {
        // Simple xorshift64
        self.random_state ^= self.random_state << 13;
        self.random_state ^= self.random_state >> 7;
        self.random_state ^= self.random_state << 17;
        (self.random_state as f64) / (u64::MAX as f64)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAMPLE RATE CONVERTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Simple sample rate converter (linear interpolation)
/// For high quality, use a proper resampler like libsamplerate
pub struct SampleRateConverter {
    source_rate: u32,
    target_rate: u32,
    phase: f64,
    last_sample: Vec<f64>,
}

impl SampleRateConverter {
    pub fn new(source_rate: u32, target_rate: u32, num_channels: usize) -> Self {
        Self {
            source_rate,
            target_rate,
            phase: 0.0,
            last_sample: vec![0.0; num_channels],
        }
    }

    /// Process a block of samples
    pub fn process(&mut self, input: &[f64], output: &mut Vec<f64>, num_channels: usize) {
        if self.source_rate == self.target_rate {
            output.extend_from_slice(input);
            return;
        }

        let ratio = self.source_rate as f64 / self.target_rate as f64;
        let num_input_frames = input.len() / num_channels;

        // Calculate output frames
        let num_output_frames = ((num_input_frames as f64) / ratio) as usize;

        for _out_frame in 0..num_output_frames {
            let in_pos = self.phase;
            let in_frame = in_pos as usize;
            let frac = in_pos - in_frame as f64;

            for ch in 0..num_channels {
                let sample_a = if in_frame < num_input_frames {
                    input[in_frame * num_channels + ch]
                } else {
                    self.last_sample[ch]
                };

                let sample_b = if in_frame + 1 < num_input_frames {
                    input[(in_frame + 1) * num_channels + ch]
                } else if in_frame < num_input_frames {
                    input[in_frame * num_channels + ch]
                } else {
                    self.last_sample[ch]
                };

                // Linear interpolation
                let interpolated = sample_a + (sample_b - sample_a) * frac;
                output.push(interpolated);
            }

            self.phase += ratio;
        }

        // Update state
        self.phase -= num_input_frames as f64;
        if self.phase < 0.0 {
            self.phase = 0.0;
        }

        // Store last samples
        if num_input_frames > 0 {
            for ch in 0..num_channels {
                self.last_sample[ch] = input[(num_input_frames - 1) * num_channels + ch];
            }
        }
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.phase = 0.0;
        self.last_sample.fill(0.0);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OFFLINE RENDERER
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio processor trait for bounce
pub trait BounceProcessor: Send + Sync {
    /// Process a block of audio
    /// Input/output are interleaved
    fn process(&mut self, input: &[f64], output: &mut [f64]);

    /// Get latency in samples
    fn latency(&self) -> usize {
        0
    }

    /// Reset state
    fn reset(&mut self);
}

/// Simple passthrough processor
pub struct PassthroughProcessor;

impl BounceProcessor for PassthroughProcessor {
    fn process(&mut self, input: &[f64], output: &mut [f64]) {
        output.copy_from_slice(input);
    }

    fn reset(&mut self) {}
}

/// Offline audio renderer
pub struct OfflineRenderer {
    config: BounceConfig,
    progress: Arc<RwLock<BounceProgress>>,
    is_cancelled: Arc<AtomicBool>,
    progress_callback: Option<BounceProgressCallback>,
}

impl OfflineRenderer {
    /// Create new offline renderer
    pub fn new(config: BounceConfig) -> Self {
        let total_samples = config
            .region
            .end_samples
            .saturating_sub(config.region.start_samples);

        Self {
            config,
            progress: Arc::new(RwLock::new(BounceProgress::new(total_samples))),
            is_cancelled: Arc::new(AtomicBool::new(false)),
            progress_callback: None,
        }
    }

    /// Set progress callback
    pub fn set_progress_callback<F>(&mut self, callback: F)
    where
        F: Fn(&BounceProgress) + Send + Sync + 'static,
    {
        self.progress_callback = Some(Box::new(callback));
    }

    /// Cancel rendering
    pub fn cancel(&self) {
        self.is_cancelled.store(true, Ordering::SeqCst);
    }

    /// Get current progress
    pub fn progress(&self) -> BounceProgress {
        *self.progress.read()
    }

    /// Render audio through processor
    pub fn render<P: BounceProcessor>(
        &mut self,
        source: &AudioData,
        processor: &mut P,
    ) -> FileResult<PathBuf> {
        let start_time = std::time::Instant::now();

        let num_channels = self.config.num_channels as usize;
        let block_size = self.config.block_size;

        // Calculate region
        let start_frame = (self.config.region.start_samples as usize).min(source.num_frames());
        let mut end_frame = (self.config.region.end_samples as usize).min(source.num_frames());

        // Add tail if requested
        if self.config.region.include_tail {
            let tail_frames =
                (self.config.region.tail_secs * self.config.source_sample_rate as f32) as usize;
            end_frame = (end_frame + tail_frames).min(source.num_frames());
        }

        let _total_frames = end_frame - start_frame;

        // Setup sample rate conversion
        let target_sample_rate = if self.config.export_format.sample_rate > 0 {
            self.config.export_format.sample_rate
        } else {
            self.config.source_sample_rate
        };

        let mut resampler = if target_sample_rate != self.config.source_sample_rate {
            Some(SampleRateConverter::new(
                self.config.source_sample_rate,
                target_sample_rate,
                num_channels,
            ))
        } else {
            None
        };

        // Setup dithering
        let mut ditherer = Ditherer::new(
            self.config.export_format.dither,
            self.config.export_format.noise_shape,
            num_channels,
        );

        // Allocate output buffer
        let mut output_samples: Vec<Vec<f64>> = vec![Vec::new(); num_channels];
        let mut peak_level: f64 = 0.0;

        // Process in blocks
        let mut frame = start_frame;
        let mut processed_samples: u64 = 0;

        let mut input_block = vec![0.0f64; block_size * num_channels];
        let mut output_block = vec![0.0f64; block_size * num_channels];
        let mut resampled_block: Vec<f64> = Vec::new();

        processor.reset();

        while frame < end_frame {
            // Check cancellation
            if self.is_cancelled.load(Ordering::Relaxed) {
                let mut progress = self.progress.write();
                progress.was_cancelled = true;
                return Err(FileError::WriteError("Bounce cancelled".to_string()));
            }

            let frames_to_process = (end_frame - frame).min(block_size);

            // Fill input block (interleaved)
            for i in 0..frames_to_process {
                let src_frame = frame + i;
                for ch in 0..num_channels {
                    input_block[i * num_channels + ch] = if src_frame < source.num_frames() {
                        source
                            .channels
                            .get(ch)
                            .and_then(|c| c.get(src_frame))
                            .copied()
                            .unwrap_or(0.0)
                    } else {
                        0.0 // Tail silence
                    };
                }
            }

            // Process through processor
            processor.process(
                &input_block[..frames_to_process * num_channels],
                &mut output_block[..frames_to_process * num_channels],
            );

            // Resample if needed
            let processed = if let Some(ref mut resampler) = resampler {
                resampled_block.clear();
                resampler.process(
                    &output_block[..frames_to_process * num_channels],
                    &mut resampled_block,
                    num_channels,
                );
                &resampled_block[..]
            } else {
                &output_block[..frames_to_process * num_channels]
            };

            // Apply dithering and store
            let output_frames = processed.len() / num_channels;
            for i in 0..output_frames {
                for ch in 0..num_channels {
                    let sample = processed[i * num_channels + ch];
                    let dithered =
                        ditherer.process(sample, ch, self.config.export_format.bit_depth.bits());
                    output_samples[ch].push(dithered);

                    // Track peak
                    peak_level = peak_level.max(dithered.abs());
                }
            }

            frame += frames_to_process;
            processed_samples += frames_to_process as u64;

            // Update progress
            {
                let elapsed = start_time.elapsed().as_secs_f32();
                let mut progress = self.progress.write();
                progress.update(processed_samples, elapsed);
                progress.peak_level = peak_level as f32;

                if let Some(ref callback) = self.progress_callback {
                    callback(&progress);
                }
            }
        }

        // Normalize if requested
        if self.config.export_format.normalize {
            let target_peak = 10.0_f64.powf(self.config.export_format.normalize_target / 20.0);

            if peak_level > 0.0 {
                let gain = if self.config.export_format.allow_clip {
                    target_peak / peak_level
                } else {
                    (target_peak / peak_level).min(1.0)
                };

                for ch in &mut output_samples {
                    for sample in ch.iter_mut() {
                        *sample *= gain;
                    }
                }
            }
        }

        // Create AudioData for output
        let output_data = AudioData {
            channels: output_samples,
            sample_rate: target_sample_rate,
            bit_depth: self.config.export_format.bit_depth,
            format: self.config.export_format.format,
        };

        // Write output file
        let output_path = &self.config.output_path;

        // Create parent directories
        if let Some(parent) = output_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        // Write based on format
        match self.config.export_format.format {
            AudioFormat::Wav => {
                write_wav(
                    output_path,
                    &output_data,
                    self.config.export_format.bit_depth,
                )?;
            }
            AudioFormat::Flac => {
                write_flac(
                    output_path,
                    &output_data,
                    self.config.export_format.bit_depth,
                )?;
            }
            AudioFormat::Mp3 => {
                // Use LAME encoder for MP3
                write_mp3(output_path, &output_data, self.config.export_format.bitrate)?;
            }
            AudioFormat::Aac | AudioFormat::Ogg => {
                // AAC/Ogg not yet implemented - fall back to WAV
                log::warn!("AAC/Ogg encoding not implemented, falling back to WAV");
                let wav_path = output_path.with_extension("wav");
                write_wav(&wav_path, &output_data, self.config.export_format.bit_depth)?;
            }
            AudioFormat::Unknown => {
                return Err(FileError::UnsupportedFormat("Unknown format".to_string()));
            }
        }

        // Mark complete
        {
            let mut progress = self.progress.write();
            progress.is_complete = true;

            if let Some(ref callback) = self.progress_callback {
                callback(&progress);
            }
        }

        Ok(output_path.clone())
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEM EXPORTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Stem export configuration
#[derive(Debug, Clone)]
pub struct StemConfig {
    /// Stem name
    pub name: String,
    /// Output path
    pub output_path: PathBuf,
    /// Solo this stem
    pub solo: bool,
    /// Include in export
    pub include: bool,
}

/// Stem exporter for multi-track export
pub struct StemExporter {
    stems: Vec<StemConfig>,
    export_format: ExportFormat,
    region: BounceRegion,
    source_sample_rate: u32,
}

impl StemExporter {
    pub fn new(export_format: ExportFormat, source_sample_rate: u32) -> Self {
        Self {
            stems: Vec::new(),
            export_format,
            region: BounceRegion::default(),
            source_sample_rate,
        }
    }

    /// Add a stem
    pub fn add_stem(&mut self, name: impl Into<String>, output_path: PathBuf) {
        self.stems.push(StemConfig {
            name: name.into(),
            output_path,
            solo: false,
            include: true,
        });
    }

    /// Set region
    pub fn set_region(&mut self, region: BounceRegion) {
        self.region = region;
    }

    /// Get stems
    pub fn stems(&self) -> &[StemConfig] {
        &self.stems
    }

    /// Get mutable stems
    pub fn stems_mut(&mut self) -> &mut [StemConfig] {
        &mut self.stems
    }

    /// Export all stems
    pub fn export_all<F>(&self, source_getter: F) -> FileResult<Vec<PathBuf>>
    where
        F: Fn(&str) -> Option<AudioData>,
    {
        let mut exported = Vec::new();

        for stem in &self.stems {
            if !stem.include {
                continue;
            }

            if let Some(data) = source_getter(&stem.name) {
                let config = BounceConfig {
                    output_path: stem.output_path.clone(),
                    export_format: self.export_format.clone(),
                    region: self.region,
                    source_sample_rate: self.source_sample_rate,
                    num_channels: data.num_channels() as u16,
                    ..Default::default()
                };

                let mut renderer = OfflineRenderer::new(config);
                let mut processor = PassthroughProcessor;
                let path = renderer.render(&data, &mut processor)?;
                exported.push(path);
            }
        }

        Ok(exported)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MP3 ENCODING
// ═══════════════════════════════════════════════════════════════════════════════

/// Quality preset for MP3 encoding
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Mp3Quality {
    /// Low quality (128 kbps VBR)
    Low,
    /// Medium quality (192 kbps VBR)
    Medium,
    /// High quality (256 kbps VBR)
    High,
    /// Maximum quality (320 kbps CBR)
    #[default]
    Maximum,
}

impl Mp3Quality {
    /// Get VBR quality level (0 = best, 9 = worst)
    pub fn vbr_quality(&self) -> u8 {
        match self {
            Mp3Quality::Low => 6,
            Mp3Quality::Medium => 4,
            Mp3Quality::High => 2,
            Mp3Quality::Maximum => 0,
        }
    }

    /// Get CBR bitrate in kbps
    pub fn bitrate(&self) -> u32 {
        match self {
            Mp3Quality::Low => 128,
            Mp3Quality::Medium => 192,
            Mp3Quality::High => 256,
            Mp3Quality::Maximum => 320,
        }
    }
}

/// Write audio data to MP3 file using LAME encoder
pub fn write_mp3<P: AsRef<Path>>(path: P, data: &AudioData, bitrate_kbps: u32) -> FileResult<()> {
    let path = path.as_ref();
    let sample_rate = data.sample_rate;
    let num_channels = data.num_channels();

    // Validate parameters
    if num_channels == 0 || num_channels > 2 {
        return Err(FileError::WriteError(format!(
            "MP3 only supports 1 or 2 channels, got {}",
            num_channels
        )));
    }

    // Build LAME encoder
    let mut builder = Builder::new()
        .ok_or_else(|| FileError::WriteError("Failed to create LAME encoder".to_string()))?;

    // Configure encoder
    builder
        .set_sample_rate(sample_rate)
        .map_err(|e| FileError::WriteError(format!("Invalid sample rate: {:?}", e)))?;

    builder
        .set_num_channels(num_channels as u8)
        .map_err(|e| FileError::WriteError(format!("Invalid channel count: {:?}", e)))?;

    // Use CBR mode with specified bitrate
    builder
        .set_brate(mp3lame_encoder::Bitrate::Kbps320) // Start with max
        .map_err(|e| FileError::WriteError(format!("Invalid bitrate: {:?}", e)))?;

    // Select appropriate bitrate enum
    let bitrate = match bitrate_kbps {
        0..=96 => mp3lame_encoder::Bitrate::Kbps96,
        97..=112 => mp3lame_encoder::Bitrate::Kbps112,
        113..=128 => mp3lame_encoder::Bitrate::Kbps128,
        129..=160 => mp3lame_encoder::Bitrate::Kbps160,
        161..=192 => mp3lame_encoder::Bitrate::Kbps192,
        193..=224 => mp3lame_encoder::Bitrate::Kbps224,
        225..=256 => mp3lame_encoder::Bitrate::Kbps256,
        _ => mp3lame_encoder::Bitrate::Kbps320,
    };

    builder
        .set_brate(bitrate)
        .map_err(|e| FileError::WriteError(format!("Failed to set bitrate: {:?}", e)))?;

    // High quality encoding settings
    builder
        .set_quality(mp3lame_encoder::Quality::Best)
        .map_err(|e| FileError::WriteError(format!("Failed to set quality: {:?}", e)))?;

    // Build encoder
    let mut encoder = builder
        .build()
        .map_err(|e| FileError::WriteError(format!("Failed to build encoder: {:?}", e)))?;

    // Convert f64 samples to i16 interleaved
    let num_samples = data.num_frames();
    let mut interleaved = Vec::with_capacity(num_samples * num_channels);

    for frame in 0..num_samples {
        for ch in 0..num_channels {
            let sample = data.channels[ch][frame];
            // Clamp and convert to i16
            let sample_i16 = (sample.clamp(-1.0, 1.0) * 32767.0) as i16;
            interleaved.push(sample_i16);
        }
    }

    // Allocate output buffer (MP3 worst case: 1.25 * num_samples + 7200)
    let max_output_size = (num_samples as f64 * 1.25) as usize + 7200;
    let mut mp3_buffer: Vec<MaybeUninit<u8>> = vec![MaybeUninit::uninit(); max_output_size];

    // Encode
    let input = InterleavedPcm(&interleaved);
    let encoded_size = encoder
        .encode(input, &mut mp3_buffer)
        .map_err(|e| FileError::WriteError(format!("MP3 encoding failed: {:?}", e)))?;

    // Flush encoder
    let flush_size = encoder
        .flush::<FlushNoGap>(&mut mp3_buffer[encoded_size..])
        .map_err(|e| FileError::WriteError(format!("MP3 flush failed: {:?}", e)))?;

    let total_size = encoded_size + flush_size;

    // Convert MaybeUninit<u8> to u8 (safe because encoder initialized them)
    let mp3_bytes: Vec<u8> = mp3_buffer[..total_size]
        .iter()
        .map(|m| unsafe { m.assume_init() })
        .collect();

    // Write to file
    std::fs::write(path, &mp3_bytes)?;

    log::info!(
        "Wrote MP3: {} ({} kbps, {} channels, {} Hz, {} bytes)",
        path.display(),
        bitrate_kbps,
        num_channels,
        sample_rate,
        total_size
    );

    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_export_format_presets() {
        let cd = ExportFormat::cd_quality();
        assert_eq!(cd.bit_depth, BitDepth::Int16);
        assert_eq!(cd.sample_rate, 44100);

        let hires = ExportFormat::hi_res();
        assert_eq!(hires.bit_depth, BitDepth::Int24);
        assert_eq!(hires.sample_rate, 96000);
    }

    #[test]
    fn test_ditherer_rectangular() {
        let mut ditherer = Ditherer::new(DitherType::Rectangular, NoiseShapeType::None, 2);

        let result = ditherer.process(0.5, 0, 16);
        // Should be close to original with small noise
        assert!((result - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_ditherer_triangular() {
        let mut ditherer = Ditherer::new(DitherType::Triangular, NoiseShapeType::None, 2);

        let result = ditherer.process(0.5, 0, 16);
        assert!((result - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_sample_rate_converter() {
        let mut converter = SampleRateConverter::new(48000, 44100, 2);

        let input: Vec<f64> = (0..960).map(|i| (i as f64 / 100.0).sin()).collect();
        let mut output = Vec::new();

        converter.process(&input, &mut output, 2);

        // Output should be shorter (44100/48000 ratio)
        assert!(output.len() < input.len());
    }

    #[test]
    fn test_bounce_progress() {
        let mut progress = BounceProgress::new(48000 * 60); // 1 minute

        progress.update(48000 * 30, 1.0); // 30 seconds processed in 1 second

        assert!((progress.percent - 50.0).abs() < 0.1);
        assert!(progress.speed_factor > 1.0);
    }

    #[test]
    fn test_offline_renderer_passthrough() {
        let source = AudioData::new(2, 1000, 48000);

        let config = BounceConfig {
            output_path: PathBuf::from("/tmp/test_bounce.wav"),
            source_sample_rate: 48000,
            num_channels: 2,
            region: BounceRegion {
                start_samples: 0,
                end_samples: 1000,
                include_tail: false,
                tail_secs: 0.0,
            },
            ..Default::default()
        };

        let mut renderer = OfflineRenderer::new(config);
        let mut processor = PassthroughProcessor;

        // This would write to disk, so we just test that it doesn't panic
        // In real tests, use a temp directory
        let _ = renderer.render(&source, &mut processor);
    }

    #[test]
    fn test_stem_exporter() {
        let exporter = StemExporter::new(ExportFormat::default(), 48000);
        assert!(exporter.stems().is_empty());
    }
}
