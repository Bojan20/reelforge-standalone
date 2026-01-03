//! Audio Engine - Central hub connecting audio I/O with processing
//!
//! Provides:
//! - Stream management with device selection
//! - Lock-free metering for UI
//! - Transport control (play/pause/stop)
//! - Integration with DualPathEngine

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use parking_lot::{Mutex, RwLock};
use rtrb::{Consumer, Producer, RingBuffer};

use rf_core::{BufferSize, Sample, SampleRate};

use crate::{
    AudioConfig, AudioError, AudioResult, AudioStream,
    get_default_output_device, get_output_device_by_name,
};

// ═══════════════════════════════════════════════════════════════════════════════
// METERING DATA (lock-free, for UI)
// ═══════════════════════════════════════════════════════════════════════════════

/// Peak meter values (atomic for lock-free access)
#[derive(Debug)]
pub struct MeterData {
    /// Left channel peak (0.0 - 1.0+)
    pub left_peak: AtomicU64,
    /// Right channel peak (0.0 - 1.0+)
    pub right_peak: AtomicU64,
    /// Left channel RMS
    pub left_rms: AtomicU64,
    /// Right channel RMS
    pub right_rms: AtomicU64,
    /// True peak (intersample)
    pub true_peak_l: AtomicU64,
    /// True peak (intersample)
    pub true_peak_r: AtomicU64,
    /// Clip indicator
    pub clipped: AtomicBool,
}

impl Default for MeterData {
    fn default() -> Self {
        Self {
            left_peak: AtomicU64::new(0),
            right_peak: AtomicU64::new(0),
            left_rms: AtomicU64::new(0),
            right_rms: AtomicU64::new(0),
            true_peak_l: AtomicU64::new(0),
            true_peak_r: AtomicU64::new(0),
            clipped: AtomicBool::new(false),
        }
    }
}

impl MeterData {
    pub fn get_left_peak(&self) -> f64 {
        f64::from_bits(self.left_peak.load(Ordering::Relaxed))
    }

    pub fn get_right_peak(&self) -> f64 {
        f64::from_bits(self.right_peak.load(Ordering::Relaxed))
    }

    pub fn get_left_rms(&self) -> f64 {
        f64::from_bits(self.left_rms.load(Ordering::Relaxed))
    }

    pub fn get_right_rms(&self) -> f64 {
        f64::from_bits(self.right_rms.load(Ordering::Relaxed))
    }

    pub fn set_left_peak(&self, value: f64) {
        self.left_peak.store(value.to_bits(), Ordering::Relaxed);
    }

    pub fn set_right_peak(&self, value: f64) {
        self.right_peak.store(value.to_bits(), Ordering::Relaxed);
    }

    pub fn set_left_rms(&self, value: f64) {
        self.left_rms.store(value.to_bits(), Ordering::Relaxed);
    }

    pub fn set_right_rms(&self, value: f64) {
        self.right_rms.store(value.to_bits(), Ordering::Relaxed);
    }

    pub fn is_clipped(&self) -> bool {
        self.clipped.load(Ordering::Relaxed)
    }

    pub fn reset_clip(&self) {
        self.clipped.store(false, Ordering::Relaxed);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSPORT STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Transport state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportState {
    Stopped,
    Playing,
    Paused,
    Recording,
}

impl Default for TransportState {
    fn default() -> Self {
        Self::Stopped
    }
}

/// Transport position (atomic for lock-free access)
#[derive(Debug)]
pub struct TransportPosition {
    /// Current sample position
    sample_position: AtomicU64,
    /// Sample rate for time conversion
    sample_rate: AtomicU64,
    /// Transport state
    state: RwLock<TransportState>,
}

impl Default for TransportPosition {
    fn default() -> Self {
        Self {
            sample_position: AtomicU64::new(0),
            sample_rate: AtomicU64::new(48000),
            state: RwLock::new(TransportState::Stopped),
        }
    }
}

impl TransportPosition {
    pub fn new(sample_rate: u64) -> Self {
        Self {
            sample_position: AtomicU64::new(0),
            sample_rate: AtomicU64::new(sample_rate),
            state: RwLock::new(TransportState::Stopped),
        }
    }

    pub fn samples(&self) -> u64 {
        self.sample_position.load(Ordering::Relaxed)
    }

    pub fn seconds(&self) -> f64 {
        let samples = self.samples();
        let rate = self.sample_rate.load(Ordering::Relaxed);
        samples as f64 / rate as f64
    }

    pub fn set_samples(&self, samples: u64) {
        self.sample_position.store(samples, Ordering::Relaxed);
    }

    pub fn advance(&self, samples: u64) {
        self.sample_position.fetch_add(samples, Ordering::Relaxed);
    }

    pub fn state(&self) -> TransportState {
        *self.state.read()
    }

    pub fn set_state(&self, state: TransportState) {
        *self.state.write() = state;
    }

    pub fn reset(&self) {
        self.sample_position.store(0, Ordering::Relaxed);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO PROCESSOR TRAIT
// ═══════════════════════════════════════════════════════════════════════════════

/// Trait for audio processors that can be used with the engine
pub trait AudioProcessor: Send + 'static {
    /// Process audio block
    ///
    /// # Arguments
    /// * `input_l` - Left input channel
    /// * `input_r` - Right input channel
    /// * `output_l` - Left output channel (pre-filled with zeros)
    /// * `output_r` - Right output channel (pre-filled with zeros)
    fn process(
        &mut self,
        input_l: &[Sample],
        input_r: &[Sample],
        output_l: &mut [Sample],
        output_r: &mut [Sample],
    );

    /// Reset processor state
    fn reset(&mut self);

    /// Set sample rate
    fn set_sample_rate(&mut self, sample_rate: f64);
}

/// Pass-through processor (default)
pub struct PassthroughProcessor;

impl AudioProcessor for PassthroughProcessor {
    fn process(
        &mut self,
        input_l: &[Sample],
        input_r: &[Sample],
        output_l: &mut [Sample],
        output_r: &mut [Sample],
    ) {
        output_l.copy_from_slice(input_l);
        output_r.copy_from_slice(input_r);
    }

    fn reset(&mut self) {}
    fn set_sample_rate(&mut self, _sample_rate: f64) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio engine configuration
#[derive(Debug, Clone)]
pub struct EngineSettings {
    pub output_device: Option<String>,
    pub input_device: Option<String>,
    pub sample_rate: SampleRate,
    pub buffer_size: BufferSize,
}

impl Default for EngineSettings {
    fn default() -> Self {
        Self {
            output_device: None, // Use default
            input_device: None,
            sample_rate: SampleRate::Hz48000,
            buffer_size: BufferSize::Samples256,
        }
    }
}

/// Central audio engine
pub struct AudioEngine {
    /// Current settings
    settings: RwLock<EngineSettings>,
    /// Active audio stream
    stream: Mutex<Option<AudioStream>>,
    /// Metering data (lock-free)
    pub meters: Arc<MeterData>,
    /// Transport position (lock-free)
    pub transport: Arc<TransportPosition>,
    /// Processor
    processor: Mutex<Box<dyn AudioProcessor>>,
    /// Engine running flag
    running: AtomicBool,
}

impl AudioEngine {
    /// Create new audio engine with default settings
    pub fn new() -> Self {
        Self {
            settings: RwLock::new(EngineSettings::default()),
            stream: Mutex::new(None),
            meters: Arc::new(MeterData::default()),
            transport: Arc::new(TransportPosition::default()),
            processor: Mutex::new(Box::new(PassthroughProcessor)),
            running: AtomicBool::new(false),
        }
    }

    /// Create audio engine with custom settings
    pub fn with_settings(settings: EngineSettings) -> Self {
        let engine = Self::new();
        *engine.settings.write() = settings;
        engine
    }

    /// Set the audio processor
    pub fn set_processor(&self, processor: Box<dyn AudioProcessor>) {
        *self.processor.lock() = processor;
    }

    /// Start the audio engine
    pub fn start(&self) -> AudioResult<()> {
        if self.running.load(Ordering::Acquire) {
            return Ok(());
        }

        let settings = self.settings.read().clone();

        // Get output device
        let output_device = if let Some(ref name) = settings.output_device {
            get_output_device_by_name(name)?
        } else {
            get_default_output_device()?
        };

        let config = AudioConfig {
            sample_rate: settings.sample_rate,
            buffer_size: settings.buffer_size,
            input_channels: 2,
            output_channels: 2,
        };

        // Clone Arcs for callback
        let meters = Arc::clone(&self.meters);
        let transport = Arc::clone(&self.transport);

        // Create pre-allocated buffers
        let buffer_size = settings.buffer_size.as_usize();
        let mut left_buf = vec![0.0f64; buffer_size];
        let mut right_buf = vec![0.0f64; buffer_size];

        // Peak decay coefficient (for smooth metering)
        let decay = 0.9995_f64.powf(buffer_size as f64);

        // Create callback
        let callback = Box::new(move |input: &[Sample], output: &mut [Sample]| {
            let frames = output.len() / 2;

            // Deinterleave input (if any)
            for i in 0..frames {
                if i * 2 + 1 < input.len() {
                    left_buf[i] = input[i * 2];
                    right_buf[i] = input[i * 2 + 1];
                } else {
                    left_buf[i] = 0.0;
                    right_buf[i] = 0.0;
                }
            }

            // Check if playing
            let state = transport.state();
            if state == TransportState::Playing {
                // Advance position
                transport.advance(frames as u64);
            }

            // For now, passthrough (processor will be called in future)
            // In production, we'd call processor.process() here
            // but we can't easily share the Mutex across callback boundary

            // Generate test tone when playing (440Hz sine)
            if state == TransportState::Playing {
                let sample_rate = 48000.0;
                let freq = 440.0;
                let pos = transport.samples();

                for i in 0..frames {
                    let t = (pos + i as u64) as f64 / sample_rate;
                    let sample = (2.0 * std::f64::consts::PI * freq * t).sin() * 0.3;
                    left_buf[i] = sample;
                    right_buf[i] = sample;
                }
            } else {
                // Output silence when stopped
                left_buf[..frames].fill(0.0);
                right_buf[..frames].fill(0.0);
            }

            // Calculate metering
            let mut peak_l = meters.get_left_peak() * decay;
            let mut peak_r = meters.get_right_peak() * decay;
            let mut sum_sq_l = 0.0;
            let mut sum_sq_r = 0.0;

            for i in 0..frames {
                let l = left_buf[i].abs();
                let r = right_buf[i].abs();

                peak_l = peak_l.max(l);
                peak_r = peak_r.max(r);

                sum_sq_l += left_buf[i] * left_buf[i];
                sum_sq_r += right_buf[i] * right_buf[i];

                // Check for clipping
                if l > 1.0 || r > 1.0 {
                    meters.clipped.store(true, Ordering::Relaxed);
                }
            }

            // Update meters
            meters.set_left_peak(peak_l);
            meters.set_right_peak(peak_r);
            meters.set_left_rms((sum_sq_l / frames as f64).sqrt());
            meters.set_right_rms((sum_sq_r / frames as f64).sqrt());

            // Interleave output
            for i in 0..frames {
                output[i * 2] = left_buf[i];
                output[i * 2 + 1] = right_buf[i];
            }
        });

        // Create and start stream
        let stream = AudioStream::new(&output_device, None, config, callback)?;
        stream.start()?;

        // Update transport sample rate
        self.transport.sample_rate.store(
            settings.sample_rate.as_u32() as u64,
            Ordering::Relaxed,
        );

        *self.stream.lock() = Some(stream);
        self.running.store(true, Ordering::Release);

        log::info!("Audio engine started");
        Ok(())
    }

    /// Stop the audio engine
    pub fn stop(&self) -> AudioResult<()> {
        if !self.running.load(Ordering::Acquire) {
            return Ok(());
        }

        if let Some(stream) = self.stream.lock().take() {
            stream.stop()?;
        }

        self.running.store(false, Ordering::Release);
        self.transport.set_state(TransportState::Stopped);

        log::info!("Audio engine stopped");
        Ok(())
    }

    /// Check if engine is running
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRANSPORT CONTROLS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Start playback
    pub fn play(&self) {
        self.transport.set_state(TransportState::Playing);
    }

    /// Pause playback
    pub fn pause(&self) {
        self.transport.set_state(TransportState::Paused);
    }

    /// Stop and reset position
    pub fn transport_stop(&self) {
        self.transport.set_state(TransportState::Stopped);
        self.transport.reset();
    }

    /// Seek to position (in samples)
    pub fn seek(&self, samples: u64) {
        self.transport.set_samples(samples);
    }

    /// Seek to position (in seconds)
    pub fn seek_seconds(&self, seconds: f64) {
        let rate = self.transport.sample_rate.load(Ordering::Relaxed);
        let samples = (seconds * rate as f64) as u64;
        self.transport.set_samples(samples);
    }

    /// Get current position in samples
    pub fn position_samples(&self) -> u64 {
        self.transport.samples()
    }

    /// Get current position in seconds
    pub fn position_seconds(&self) -> f64 {
        self.transport.seconds()
    }

    /// Get current transport state
    pub fn transport_state(&self) -> TransportState {
        self.transport.state()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SETTINGS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Update settings (requires restart)
    pub fn update_settings(&self, settings: EngineSettings) {
        *self.settings.write() = settings;
    }

    /// Get current settings
    pub fn settings(&self) -> EngineSettings {
        self.settings.read().clone()
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> SampleRate {
        self.settings.read().sample_rate
    }

    /// Get buffer size
    pub fn buffer_size(&self) -> BufferSize {
        self.settings.read().buffer_size
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // METERING
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get meter data reference (for UI)
    pub fn meter_data(&self) -> Arc<MeterData> {
        Arc::clone(&self.meters)
    }

    /// Reset clip indicator
    pub fn reset_clip(&self) {
        self.meters.reset_clip();
    }
}

impl Default for AudioEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for AudioEngine {
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
    fn test_meter_data() {
        let meters = MeterData::default();

        meters.set_left_peak(0.75);
        meters.set_right_peak(0.5);

        assert!((meters.get_left_peak() - 0.75).abs() < 0.001);
        assert!((meters.get_right_peak() - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_transport_position() {
        let transport = TransportPosition::new(48000);

        assert_eq!(transport.samples(), 0);
        assert_eq!(transport.state(), TransportState::Stopped);

        transport.set_state(TransportState::Playing);
        transport.advance(48000);

        assert_eq!(transport.samples(), 48000);
        assert!((transport.seconds() - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_engine_settings() {
        let settings = EngineSettings::default();

        assert!(settings.output_device.is_none());
        assert_eq!(settings.sample_rate, SampleRate::Hz48000);
        assert_eq!(settings.buffer_size, BufferSize::Samples256);
    }

    #[test]
    fn test_engine_creation() {
        let engine = AudioEngine::new();

        assert!(!engine.is_running());
        assert_eq!(engine.transport_state(), TransportState::Stopped);
        assert_eq!(engine.position_samples(), 0);
    }
}
