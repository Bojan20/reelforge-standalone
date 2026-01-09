//! Multi-Output Audio Engine
//!
//! Provides support for multiple simultaneous audio outputs:
//! - Main output (stereo master)
//! - Monitor output (control room speakers - can be different device)
//! - 4 Cue/Headphone outputs (for performers)
//!
//! This enables professional studio workflows where:
//! - Engineer hears through monitor speakers
//! - Musicians hear independent headphone mixes
//! - Main output goes to recording/broadcast

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::{Mutex, RwLock};

use rf_core::{BufferSize, Sample, SampleRate};

use crate::{
    AudioConfig, AudioResult, AudioStream, get_default_output_device, get_output_device_by_name,
};
use crate::engine::MeterData;

// ═══════════════════════════════════════════════════════════════════════════════
// OUTPUT DESTINATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Identifies which output receives audio
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum OutputDestination {
    /// Main stereo output (master bus)
    Main,
    /// Monitor output (control room speakers)
    Monitor,
    /// Cue/Headphone output (0-3)
    Cue(u8),
}

impl OutputDestination {
    /// Get cue output index (0-3), returns None for non-cue outputs
    pub fn cue_index(&self) -> Option<u8> {
        match self {
            OutputDestination::Cue(idx) => Some(*idx),
            _ => None,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OUTPUT STREAM
// ═══════════════════════════════════════════════════════════════════════════════

/// Configuration for a single output
#[derive(Debug, Clone)]
pub struct OutputConfig {
    /// Device name (None = default device)
    pub device_name: Option<String>,
    /// Whether this output is enabled
    pub enabled: bool,
    /// Output level (0.0 - 1.0)
    pub level: f64,
}

impl Default for OutputConfig {
    fn default() -> Self {
        Self {
            device_name: None,
            enabled: true,
            level: 1.0,
        }
    }
}

/// Single output with its own stream
pub struct OutputChannel {
    /// Configuration
    config: OutputConfig,
    /// Active stream (if running)
    stream: Option<AudioStream>,
    /// Output buffer (stereo, interleaved)
    buffer: Vec<Sample>,
    /// Level (atomic for real-time access)
    level: AtomicU64,
    /// Enabled flag (atomic)
    enabled: AtomicBool,
    /// Metering
    meters: Arc<MeterData>,
}

impl OutputChannel {
    fn new(buffer_size: usize) -> Self {
        Self {
            config: OutputConfig::default(),
            stream: None,
            buffer: vec![0.0; buffer_size * 2], // Stereo interleaved
            level: AtomicU64::new(1.0_f64.to_bits()),
            enabled: AtomicBool::new(true),
            meters: Arc::new(MeterData::default()),
        }
    }

    /// Get output level (0.0 - 2.0)
    pub fn get_level(&self) -> f64 {
        f64::from_bits(self.level.load(Ordering::Relaxed))
    }

    /// Set output level (0.0 - 2.0)
    pub fn set_level(&self, level: f64) {
        self.level.store(level.clamp(0.0, 2.0).to_bits(), Ordering::Relaxed);
    }

    /// Check if output is enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Enable/disable output
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    /// Get mutable reference to output buffer (stereo interleaved)
    pub fn buffer_mut(&mut self) -> &mut [Sample] {
        &mut self.buffer
    }

    /// Get reference to output buffer
    pub fn buffer(&self) -> &[Sample] {
        &self.buffer
    }

    /// Get metering data
    pub fn meters(&self) -> &Arc<MeterData> {
        &self.meters
    }

    /// Fill buffer from separate L/R slices
    pub fn fill_from_lr(&mut self, left: &[Sample], right: &[Sample]) {
        let frames = left.len().min(right.len()).min(self.buffer.len() / 2);
        for i in 0..frames {
            self.buffer[i * 2] = left[i];
            self.buffer[i * 2 + 1] = right[i];
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MULTI-OUTPUT ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Number of cue outputs
pub const NUM_CUE_OUTPUTS: usize = 4;

/// Multi-output audio engine configuration
#[derive(Debug, Clone)]
pub struct MultiOutputSettings {
    /// Main output device
    pub main_output: OutputConfig,
    /// Monitor output device (separate speakers)
    pub monitor_output: OutputConfig,
    /// Cue outputs (headphones for performers)
    pub cue_outputs: [OutputConfig; NUM_CUE_OUTPUTS],
    /// Sample rate (shared across all outputs)
    pub sample_rate: SampleRate,
    /// Buffer size (shared across all outputs)
    pub buffer_size: BufferSize,
}

impl Default for MultiOutputSettings {
    fn default() -> Self {
        Self {
            main_output: OutputConfig::default(),
            monitor_output: OutputConfig {
                enabled: false, // Monitor output disabled by default
                ..Default::default()
            },
            cue_outputs: std::array::from_fn(|_| OutputConfig {
                enabled: false, // Cue outputs disabled by default
                ..Default::default()
            }),
            sample_rate: SampleRate::Hz48000,
            buffer_size: BufferSize::Samples256,
        }
    }
}

/// Callback type for filling output buffers
///
/// Arguments:
/// - `main_l`, `main_r`: Main output buffers
/// - `monitor_l`, `monitor_r`: Monitor output buffers
/// - `cue_outputs`: Array of (left, right) buffer pairs for each cue output
pub type MultiOutputCallback = Box<
    dyn FnMut(
        &mut [Sample], &mut [Sample],           // Main L/R
        &mut [Sample], &mut [Sample],           // Monitor L/R
        &mut [(&mut [Sample], &mut [Sample])]   // Cue outputs [(L, R); 4]
    ) + Send + 'static
>;

/// Multi-output audio engine
///
/// Supports:
/// - Main stereo output (master bus)
/// - Separate monitor output (control room)
/// - 4 independent cue/headphone outputs
pub struct MultiOutputEngine {
    /// Settings
    settings: RwLock<MultiOutputSettings>,
    /// Main output channel
    main: Mutex<OutputChannel>,
    /// Monitor output channel
    monitor: Mutex<OutputChannel>,
    /// Cue output channels
    cues: [Mutex<OutputChannel>; NUM_CUE_OUTPUTS],
    /// Running flag
    running: AtomicBool,
    /// Sample rate
    sample_rate: AtomicU64,
    /// Block size
    block_size: AtomicU64,
}

impl MultiOutputEngine {
    /// Create new multi-output engine with default settings
    pub fn new() -> Self {
        let buffer_size = BufferSize::Samples256.as_usize();
        Self {
            settings: RwLock::new(MultiOutputSettings::default()),
            main: Mutex::new(OutputChannel::new(buffer_size)),
            monitor: Mutex::new(OutputChannel::new(buffer_size)),
            cues: std::array::from_fn(|_| Mutex::new(OutputChannel::new(buffer_size))),
            running: AtomicBool::new(false),
            sample_rate: AtomicU64::new(48000),
            block_size: AtomicU64::new(buffer_size as u64),
        }
    }

    /// Create with custom settings
    pub fn with_settings(settings: MultiOutputSettings) -> Self {
        let buffer_size = settings.buffer_size.as_usize();
        let sample_rate = settings.sample_rate.as_u32() as u64;

        let engine = Self {
            settings: RwLock::new(settings),
            main: Mutex::new(OutputChannel::new(buffer_size)),
            monitor: Mutex::new(OutputChannel::new(buffer_size)),
            cues: std::array::from_fn(|_| Mutex::new(OutputChannel::new(buffer_size))),
            running: AtomicBool::new(false),
            sample_rate: AtomicU64::new(sample_rate),
            block_size: AtomicU64::new(buffer_size as u64),
        };
        engine
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate.load(Ordering::Relaxed) as u32
    }

    /// Get block size
    pub fn block_size(&self) -> usize {
        self.block_size.load(Ordering::Relaxed) as usize
    }

    /// Check if running
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OUTPUT CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    /// Set main output level (0.0 - 1.0)
    pub fn set_main_level(&self, level: f64) {
        self.main.lock().set_level(level);
    }

    /// Get main output level
    pub fn main_level(&self) -> f64 {
        self.main.lock().get_level()
    }

    /// Set monitor output level (0.0 - 1.0)
    pub fn set_monitor_level(&self, level: f64) {
        self.monitor.lock().set_level(level);
    }

    /// Get monitor output level
    pub fn monitor_level(&self) -> f64 {
        self.monitor.lock().get_level()
    }

    /// Enable/disable monitor output
    pub fn set_monitor_enabled(&self, enabled: bool) {
        self.monitor.lock().set_enabled(enabled);
    }

    /// Check if monitor output is enabled
    pub fn monitor_enabled(&self) -> bool {
        self.monitor.lock().is_enabled()
    }

    /// Set cue output level (0.0 - 1.0)
    pub fn set_cue_level(&self, index: usize, level: f64) {
        if index < NUM_CUE_OUTPUTS {
            self.cues[index].lock().set_level(level);
        }
    }

    /// Get cue output level
    pub fn cue_level(&self, index: usize) -> f64 {
        if index < NUM_CUE_OUTPUTS {
            self.cues[index].lock().get_level()
        } else {
            0.0
        }
    }

    /// Enable/disable cue output
    pub fn set_cue_enabled(&self, index: usize, enabled: bool) {
        if index < NUM_CUE_OUTPUTS {
            self.cues[index].lock().set_enabled(enabled);
        }
    }

    /// Check if cue output is enabled
    pub fn cue_enabled(&self, index: usize) -> bool {
        if index < NUM_CUE_OUTPUTS {
            self.cues[index].lock().is_enabled()
        } else {
            false
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // METERING
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get main output meters
    pub fn main_meters(&self) -> Arc<MeterData> {
        Arc::clone(&self.main.lock().meters)
    }

    /// Get monitor output meters
    pub fn monitor_meters(&self) -> Arc<MeterData> {
        Arc::clone(&self.monitor.lock().meters)
    }

    /// Get cue output meters
    pub fn cue_meters(&self, index: usize) -> Option<Arc<MeterData>> {
        if index < NUM_CUE_OUTPUTS {
            Some(Arc::clone(&self.cues[index].lock().meters))
        } else {
            None
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEVICE CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Set main output device
    pub fn set_main_device(&self, device_name: Option<String>) {
        self.main.lock().config.device_name = device_name;
    }

    /// Set monitor output device
    pub fn set_monitor_device(&self, device_name: Option<String>) {
        self.monitor.lock().config.device_name = device_name;
    }

    /// Set cue output device
    pub fn set_cue_device(&self, index: usize, device_name: Option<String>) {
        if index < NUM_CUE_OUTPUTS {
            self.cues[index].lock().config.device_name = device_name;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // START/STOP
    // ═══════════════════════════════════════════════════════════════════════════

    /// Start the multi-output engine
    ///
    /// Starts streams for all enabled outputs
    pub fn start(&self) -> AudioResult<()> {
        if self.running.load(Ordering::Acquire) {
            return Ok(());
        }

        let settings = self.settings.read().clone();
        let sample_rate = settings.sample_rate;
        let buffer_size = settings.buffer_size;

        self.sample_rate.store(sample_rate.as_u32() as u64, Ordering::Relaxed);
        self.block_size.store(buffer_size.as_usize() as u64, Ordering::Relaxed);

        // Start main output
        self.start_output_stream(
            &mut self.main.lock(),
            &settings.main_output,
            sample_rate,
            buffer_size,
        )?;

        // Start monitor output (if enabled and device specified)
        if settings.monitor_output.enabled {
            if let Err(e) = self.start_output_stream(
                &mut self.monitor.lock(),
                &settings.monitor_output,
                sample_rate,
                buffer_size,
            ) {
                log::warn!("Failed to start monitor output: {}", e);
            }
        }

        // Start cue outputs (if enabled)
        for (i, cue_config) in settings.cue_outputs.iter().enumerate() {
            if cue_config.enabled {
                if let Err(e) = self.start_output_stream(
                    &mut self.cues[i].lock(),
                    cue_config,
                    sample_rate,
                    buffer_size,
                ) {
                    log::warn!("Failed to start cue output {}: {}", i, e);
                }
            }
        }

        self.running.store(true, Ordering::Release);
        log::info!("Multi-output engine started");
        Ok(())
    }

    /// Start a single output stream
    fn start_output_stream(
        &self,
        channel: &mut OutputChannel,
        config: &OutputConfig,
        sample_rate: SampleRate,
        buffer_size: BufferSize,
    ) -> AudioResult<()> {
        // Get device
        let device = if let Some(ref name) = config.device_name {
            get_output_device_by_name(name)?
        } else {
            get_default_output_device()?
        };

        let audio_config = AudioConfig {
            sample_rate,
            buffer_size,
            input_channels: 0,
            output_channels: 2,
        };

        // Clone refs for callback
        let meters = Arc::clone(&channel.meters);
        let level = channel.level.load(Ordering::Relaxed);
        let level_atomic = AtomicU64::new(level);
        let enabled = channel.enabled.load(Ordering::Relaxed);
        let enabled_atomic = AtomicBool::new(enabled);

        // Pre-allocated buffer
        let buf_size = buffer_size.as_usize();
        let left_buf = vec![0.0_f64; buf_size];
        let right_buf = vec![0.0_f64; buf_size];
        let decay = 0.9995_f64.powf(buf_size as f64);

        // Create callback
        let callback = Box::new(move |_input: &[Sample], output: &mut [Sample]| {
            let frames = output.len() / 2;
            let level = f64::from_bits(level_atomic.load(Ordering::Relaxed));
            let enabled = enabled_atomic.load(Ordering::Relaxed);

            if !enabled {
                // Output silence if disabled
                output.fill(0.0);
                return;
            }

            // Apply level and calculate metering
            let mut peak_l = meters.get_left_peak() * decay;
            let mut peak_r = meters.get_right_peak() * decay;
            let mut sum_sq_l = 0.0;
            let mut sum_sq_r = 0.0;

            for i in 0..frames {
                let l = left_buf.get(i).copied().unwrap_or(0.0) * level;
                let r = right_buf.get(i).copied().unwrap_or(0.0) * level;

                output[i * 2] = l;
                output[i * 2 + 1] = r;

                let abs_l = l.abs();
                let abs_r = r.abs();
                peak_l = peak_l.max(abs_l);
                peak_r = peak_r.max(abs_r);
                sum_sq_l += l * l;
                sum_sq_r += r * r;

                if abs_l > 1.0 || abs_r > 1.0 {
                    meters.clipped.store(true, Ordering::Relaxed);
                }
            }

            meters.set_left_peak(peak_l);
            meters.set_right_peak(peak_r);
            meters.set_left_rms((sum_sq_l / frames as f64).sqrt());
            meters.set_right_rms((sum_sq_r / frames as f64).sqrt());
        });

        // Create and start stream
        let stream = AudioStream::new(&device, None, audio_config, callback)?;
        stream.start()?;

        channel.config = config.clone();
        channel.stream = Some(stream);
        channel.buffer.resize(buf_size * 2, 0.0);

        Ok(())
    }

    /// Stop the multi-output engine
    pub fn stop(&self) -> AudioResult<()> {
        if !self.running.load(Ordering::Acquire) {
            return Ok(());
        }

        // Stop main output
        if let Some(stream) = self.main.lock().stream.take() {
            stream.stop()?;
        }

        // Stop monitor output
        if let Some(stream) = self.monitor.lock().stream.take() {
            stream.stop()?;
        }

        // Stop cue outputs
        for cue in &self.cues {
            if let Some(stream) = cue.lock().stream.take() {
                let _ = stream.stop();
            }
        }

        self.running.store(false, Ordering::Release);
        log::info!("Multi-output engine stopped");
        Ok(())
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BUFFER ACCESS (for playback engine)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get mutable access to main output buffer
    ///
    /// Call this to fill the main output buffer before the next audio callback
    pub fn main_buffer(&self) -> parking_lot::MutexGuard<'_, OutputChannel> {
        self.main.lock()
    }

    /// Get mutable access to monitor output buffer
    pub fn monitor_buffer(&self) -> parking_lot::MutexGuard<'_, OutputChannel> {
        self.monitor.lock()
    }

    /// Get mutable access to cue output buffer
    pub fn cue_buffer(&self, index: usize) -> Option<parking_lot::MutexGuard<'_, OutputChannel>> {
        if index < NUM_CUE_OUTPUTS {
            Some(self.cues[index].lock())
        } else {
            None
        }
    }

    /// Fill all output buffers at once
    ///
    /// This is the preferred method for the playback engine to fill all outputs
    /// in a single call, ensuring synchronization.
    pub fn fill_outputs<F>(&self, mut fill_fn: F)
    where
        F: FnMut(
            &mut [Sample], &mut [Sample],  // main L/R
            &mut [Sample], &mut [Sample],  // monitor L/R
            [(&mut [Sample], &mut [Sample]); NUM_CUE_OUTPUTS],  // cues
        ),
    {
        let block_size = self.block_size() * 2; // Stereo interleaved

        // Lock all outputs
        let mut main = self.main.lock();
        let mut monitor = self.monitor.lock();
        let mut cues: [_; NUM_CUE_OUTPUTS] = std::array::from_fn(|i| self.cues[i].lock());

        // Ensure buffers are correct size
        if main.buffer.len() != block_size {
            main.buffer.resize(block_size, 0.0);
        }
        if monitor.buffer.len() != block_size {
            monitor.buffer.resize(block_size, 0.0);
        }
        for cue in &mut cues {
            if cue.buffer.len() != block_size {
                cue.buffer.resize(block_size, 0.0);
            }
        }

        // Split buffers into L/R
        let frames = block_size / 2;
        let (main_l, main_r) = main.buffer.split_at_mut(frames);
        let (monitor_l, monitor_r) = monitor.buffer.split_at_mut(frames);

        // Create cue buffer pairs
        let cue_pairs: [(&mut [Sample], &mut [Sample]); NUM_CUE_OUTPUTS] = unsafe {
            // Safe because we hold exclusive locks and buffers are correctly sized
            std::mem::transmute(std::array::from_fn::<_, NUM_CUE_OUTPUTS, _>(|i| {
                let (l, r) = cues[i].buffer.split_at_mut(frames);
                (l as *mut [Sample], r as *mut [Sample])
            }).map(|(l, r)| (&mut *l, &mut *r)))
        };

        // Call fill function
        fill_fn(main_l, main_r, monitor_l, monitor_r, cue_pairs);
    }
}

impl Default for MultiOutputEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for MultiOutputEngine {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_output_destination() {
        assert_eq!(OutputDestination::Main.cue_index(), None);
        assert_eq!(OutputDestination::Monitor.cue_index(), None);
        assert_eq!(OutputDestination::Cue(0).cue_index(), Some(0));
        assert_eq!(OutputDestination::Cue(3).cue_index(), Some(3));
    }

    #[test]
    fn test_multi_output_settings() {
        let settings = MultiOutputSettings::default();
        assert!(settings.main_output.enabled);
        assert!(!settings.monitor_output.enabled);
        assert!(!settings.cue_outputs[0].enabled);
    }

    #[test]
    fn test_engine_creation() {
        let engine = MultiOutputEngine::new();
        assert!(!engine.is_running());
        assert_eq!(engine.sample_rate(), 48000);
    }

    #[test]
    fn test_level_control() {
        let engine = MultiOutputEngine::new();

        engine.set_main_level(0.5);
        assert!((engine.main_level() - 0.5).abs() < 0.001);

        engine.set_monitor_level(0.8);
        assert!((engine.monitor_level() - 0.8).abs() < 0.001);

        engine.set_cue_level(0, 0.6);
        assert!((engine.cue_level(0) - 0.6).abs() < 0.001);
    }

    #[test]
    fn test_enable_control() {
        let engine = MultiOutputEngine::new();

        engine.set_monitor_enabled(true);
        assert!(engine.monitor_enabled());

        engine.set_cue_enabled(2, true);
        assert!(engine.cue_enabled(2));
    }
}
