//! Audio Engine - Central hub connecting audio I/O with processing
//!
//! Provides:
//! - Stream management with device selection
//! - Lock-free metering for UI
//! - Transport control (play/pause/stop)
//! - Integration with DualPathEngine

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU32, AtomicU64, Ordering};
use std::thread;
use std::time::Duration;

use parking_lot::{Mutex, RwLock};

use rf_core::{BufferSize, Sample, SampleRate};
use rf_dsp::eq::{ParametricEq, EqFilterType}; // For EQ processing
use rf_dsp::StereoProcessor; // Trait for process_sample()
use rf_file::recording::{AudioRecorder, RecordingConfig, RecordingState};

use crate::{
    AudioConfig, AudioResult, AudioStream, get_default_input_device,
    get_default_output_device, get_input_device_by_name, get_output_device_by_name,
};

// ═══════════════════════════════════════════════════════════════════════════════
// METERING DATA (lock-free, for UI)
// ═══════════════════════════════════════════════════════════════════════════════

/// Peak meter values (atomic for lock-free access)
/// Cache-line aligned to prevent false sharing (each atomic on separate line)
#[derive(Debug)]
#[repr(align(64))]
pub struct MeterData {
    /// Left channel peak (0.0 - 1.0+)
    pub left_peak: AtomicU64,
    _pad1: [u8; 56],  // Cache-line padding (64 - 8 = 56)

    /// Right channel peak (0.0 - 1.0+)
    pub right_peak: AtomicU64,
    _pad2: [u8; 56],

    /// Left channel RMS
    pub left_rms: AtomicU64,
    _pad3: [u8; 56],

    /// Right channel RMS
    pub right_rms: AtomicU64,
    _pad4: [u8; 56],

    /// True peak (intersample)
    pub true_peak_l: AtomicU64,
    _pad5: [u8; 56],

    /// True peak (intersample)
    pub true_peak_r: AtomicU64,
    _pad6: [u8; 56],

    /// Clip indicator
    pub clipped: AtomicBool,
    _pad7: [u8; 63],  // Cache-line padding (64 - 1 = 63)
}

impl Default for MeterData {
    fn default() -> Self {
        Self {
            left_peak: AtomicU64::new(0),
            _pad1: [0; 56],
            right_peak: AtomicU64::new(0),
            _pad2: [0; 56],
            left_rms: AtomicU64::new(0),
            _pad3: [0; 56],
            right_rms: AtomicU64::new(0),
            _pad4: [0; 56],
            true_peak_l: AtomicU64::new(0),
            _pad5: [0; 56],
            true_peak_r: AtomicU64::new(0),
            _pad6: [0; 56],
            clipped: AtomicBool::new(false),
            _pad7: [0; 63],
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
#[derive(Default)]
pub enum TransportState {
    #[default]
    Stopped,
    Playing,
    Paused,
    Recording,
}

impl TransportState {
    #[inline]
    fn to_u8(self) -> u8 {
        match self {
            Self::Stopped => 0,
            Self::Playing => 1,
            Self::Paused => 2,
            Self::Recording => 3,
        }
    }

    #[inline]
    fn from_u8(value: u8) -> Self {
        match value {
            1 => Self::Playing,
            2 => Self::Paused,
            3 => Self::Recording,
            _ => Self::Stopped,
        }
    }
}


/// Transport position (atomic for lock-free access)
#[derive(Debug)]
pub struct TransportPosition {
    /// Current sample position
    sample_position: AtomicU64,
    /// Sample rate for time conversion
    sample_rate: AtomicU64,
    /// Transport state (lock-free atomic)
    state: AtomicU8,
}

impl Default for TransportPosition {
    fn default() -> Self {
        Self {
            sample_position: AtomicU64::new(0),
            sample_rate: AtomicU64::new(48000),
            state: AtomicU8::new(TransportState::Stopped.to_u8()),
        }
    }
}

impl TransportPosition {
    pub fn new(sample_rate: u64) -> Self {
        Self {
            sample_position: AtomicU64::new(0),
            sample_rate: AtomicU64::new(sample_rate),
            state: AtomicU8::new(TransportState::Stopped.to_u8()),
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

    #[inline]
    pub fn state(&self) -> TransportState {
        TransportState::from_u8(self.state.load(Ordering::Relaxed))
    }

    #[inline]
    pub fn set_state(&self, state: TransportState) {
        self.state.store(state.to_u8(), Ordering::Release);
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
    /// Device configuration (UI thread only - not accessed in audio callback)
    device_config: RwLock<DeviceConfig>,
    /// Lock-free sample rate (accessed in audio thread)
    sample_rate: AtomicU32,
    /// Lock-free buffer size (accessed in audio thread)
    buffer_size: AtomicU32,
    /// Active audio stream
    stream: Mutex<Option<AudioStream>>,
    /// Metering data (lock-free)
    pub meters: Arc<MeterData>,
    /// Transport position (lock-free)
    pub transport: Arc<TransportPosition>,
    /// Audio recorder (shared with audio callback)
    pub recorder: Arc<AudioRecorder>,
    /// Processor
    processor: Mutex<Box<dyn AudioProcessor>>,
    /// Engine running flag
    running: AtomicBool,
    /// Recording flush thread handle
    recorder_thread: Mutex<Option<thread::JoinHandle<()>>>,
}

/// Device configuration (UI thread only)
#[derive(Debug, Clone)]
struct DeviceConfig {
    pub output_device: Option<String>,
    pub input_device: Option<String>,
}

impl AudioEngine {
    /// Create new audio engine with default settings
    pub fn new() -> Self {
        let default = EngineSettings::default();
        let recorder_config = RecordingConfig {
            sample_rate: default.sample_rate.as_u32(),
            ..Default::default()
        };
        Self {
            device_config: RwLock::new(DeviceConfig {
                output_device: default.output_device,
                input_device: default.input_device,
            }),
            sample_rate: AtomicU32::new(default.sample_rate.as_u32()),
            buffer_size: AtomicU32::new(default.buffer_size.as_u32()),
            stream: Mutex::new(None),
            meters: Arc::new(MeterData::default()),
            transport: Arc::new(TransportPosition::default()),
            recorder: Arc::new(AudioRecorder::new(recorder_config)),
            processor: Mutex::new(Box::new(PassthroughProcessor)),
            running: AtomicBool::new(false),
            recorder_thread: Mutex::new(None),
        }
    }

    /// Create audio engine with custom settings
    pub fn with_settings(settings: EngineSettings) -> Self {
        let recorder_config = RecordingConfig {
            sample_rate: settings.sample_rate.as_u32(),
            ..Default::default()
        };
        Self {
            device_config: RwLock::new(DeviceConfig {
                output_device: settings.output_device.clone(),
                input_device: settings.input_device.clone(),
            }),
            sample_rate: AtomicU32::new(settings.sample_rate.as_u32()),
            buffer_size: AtomicU32::new(settings.buffer_size.as_u32()),
            stream: Mutex::new(None),
            meters: Arc::new(MeterData::default()),
            transport: Arc::new(TransportPosition::default()),
            recorder: Arc::new(AudioRecorder::new(recorder_config)),
            processor: Mutex::new(Box::new(PassthroughProcessor)),
            running: AtomicBool::new(false),
            recorder_thread: Mutex::new(None),
        }
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

        // Read device config (UI thread only - not accessed in callback)
        let device_cfg = self.device_config.read().clone();

        // Load audio settings (lock-free atomic reads)
        let sample_rate_u32 = self.sample_rate.load(Ordering::Relaxed);
        let buffer_size_u32 = self.buffer_size.load(Ordering::Relaxed);
        let sample_rate = SampleRate::from_u32(sample_rate_u32).unwrap_or(SampleRate::Hz48000);
        let buffer_size = BufferSize::from_u32(buffer_size_u32).unwrap_or(BufferSize::Samples256);

        // Get output device
        let output_device = if let Some(ref name) = device_cfg.output_device {
            get_output_device_by_name(name)?
        } else {
            get_default_output_device()?
        };

        // Get input device (if specified)
        let input_device = if let Some(ref name) = device_cfg.input_device {
            Some(get_input_device_by_name(name)?)
        } else {
            // Try to get default input device
            get_default_input_device().ok()
        };

        let config = AudioConfig {
            sample_rate,
            buffer_size,
            input_channels: 2,
            output_channels: 2,
        };

        // Clone Arcs for callback
        let meters = Arc::clone(&self.meters);
        let transport = Arc::clone(&self.transport);
        let recorder = Arc::clone(&self.recorder);

        // Create pre-allocated buffers
        let buffer_size_usize = buffer_size.as_usize();
        let mut left_buf = vec![0.0f64; buffer_size_usize];
        let mut right_buf = vec![0.0f64; buffer_size_usize];
        // Pre-allocated interleaved f32 buffer for recording
        let mut record_buf = vec![0.0f32; buffer_size_usize * 2];

        // Peak decay coefficient (for smooth metering)
        let decay = 0.9995_f64.powf(buffer_size_usize as f64);

        // Create EQ instance (moved into callback for lock-free access)
        let mut eq = ParametricEq::new(sample_rate.as_f64());

        // Enable test band: 1kHz +6dB Bell filter
        eq.set_band(0, 1000.0, 6.0, 1.0, EqFilterType::Bell);

        // Create callback
        let callback = Box::new(move |input: &[Sample], output: &mut [Sample]| {
            let frames = output.len() / 2;

            // Deinterleave input audio
            let has_input = !input.is_empty() && input.len() >= frames * 2;
            for i in 0..frames {
                if has_input && i * 2 + 1 < input.len() {
                    left_buf[i] = input[i * 2];
                    right_buf[i] = input[i * 2 + 1];
                } else {
                    left_buf[i] = 0.0;
                    right_buf[i] = 0.0;
                }
            }

            // Send input audio to recording system
            // Recorder expects interleaved f32 samples: [L0, R0, L1, R1, ...]
            if has_input {
                let rec_state = recorder.state();
                if rec_state == RecordingState::Armed || rec_state == RecordingState::Recording {
                    // Convert to interleaved f32
                    for i in 0..frames {
                        record_buf[i * 2] = left_buf[i] as f32;
                        record_buf[i * 2 + 1] = right_buf[i] as f32;
                    }
                    let position = transport.samples();
                    recorder.process(&record_buf[..frames * 2], position);
                }
            }

            // Check if playing
            let state = transport.state();
            if state == TransportState::Playing {
                // Advance position
                transport.advance(frames as u64);
            }

            // Process audio based on state
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

                // Process through EQ (sample-by-sample)
                for i in 0..frames {
                    let (out_l, out_r) = eq.process_sample(left_buf[i], right_buf[i]);
                    left_buf[i] = out_l;
                    right_buf[i] = out_r;
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

        // Create and start stream (with input device if available)
        let stream = AudioStream::new(
            &output_device,
            input_device.as_ref(),
            config,
            callback,
        )?;
        stream.start()?;

        if input_device.is_some() {
            log::info!("Audio engine started with input device");
        } else {
            log::info!("Audio engine started (no input device)");
        }

        // Update transport sample rate
        self.transport
            .sample_rate
            .store(sample_rate_u32 as u64, Ordering::Relaxed);

        *self.stream.lock() = Some(stream);
        self.running.store(true, Ordering::Release);

        // Start recording flush thread
        let recorder_clone = Arc::clone(&self.recorder);
        let running_flag = self.running.load(Ordering::Acquire);
        let recorder_handle = thread::Builder::new()
            .name("audio-recorder-flush".into())
            .spawn(move || {
                log::debug!("Recording flush thread started");
                while running_flag {
                    // Flush pending samples to disk
                    if let Err(e) = recorder_clone.flush_pending() {
                        log::error!("Recording flush error: {}", e);
                    }
                    // Sleep briefly to avoid busy-waiting
                    thread::sleep(Duration::from_millis(10));
                }
                log::debug!("Recording flush thread stopped");
            })
            .ok();
        *self.recorder_thread.lock() = recorder_handle;

        log::info!("Audio engine started");
        Ok(())
    }

    /// Stop the audio engine
    pub fn stop(&self) -> AudioResult<()> {
        if !self.running.load(Ordering::Acquire) {
            return Ok(());
        }

        // Stop recording if active
        if self.recorder.state() == RecordingState::Recording {
            let _ = self.recorder.stop();
        }

        if let Some(stream) = self.stream.lock().take() {
            stream.stop()?;
        }

        self.running.store(false, Ordering::Release);
        self.transport.set_state(TransportState::Stopped);

        // Wait for recorder thread to finish
        if let Some(handle) = self.recorder_thread.lock().take() {
            let _ = handle.join();
        }

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
    // RECORDING CONTROLS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Arm recording
    pub fn record_arm(&self) -> Result<(), rf_file::FileError> {
        self.recorder.arm()
    }

    /// Disarm recording
    pub fn record_disarm(&self) {
        self.recorder.disarm();
    }

    /// Start recording (arms first if not armed)
    pub fn record_start(&self) -> Result<std::path::PathBuf, rf_file::FileError> {
        if self.recorder.state() == RecordingState::Stopped {
            self.recorder.arm()?;
        }
        self.transport.set_state(TransportState::Recording);
        self.recorder.start()
    }

    /// Stop recording
    pub fn record_stop(&self) -> Result<Option<std::path::PathBuf>, rf_file::FileError> {
        let result = self.recorder.stop();
        if self.transport.state() == TransportState::Recording {
            self.transport.set_state(TransportState::Playing);
        }
        result
    }

    /// Pause recording
    pub fn record_pause(&self) -> Result<(), rf_file::FileError> {
        self.recorder.pause()
    }

    /// Resume recording
    pub fn record_resume(&self) -> Result<(), rf_file::FileError> {
        self.recorder.resume()
    }

    /// Get recording state
    pub fn recording_state(&self) -> RecordingState {
        self.recorder.state()
    }

    /// Get recording stats
    pub fn recording_stats(&self) -> rf_file::recording::RecordingStats {
        self.recorder.stats()
    }

    /// Set recording output directory
    pub fn set_recording_output_dir(&self, path: std::path::PathBuf) {
        let mut config = rf_file::recording::RecordingConfig::default();
        config.output_dir = path;
        config.sample_rate = self.sample_rate.load(Ordering::Relaxed);
        self.recorder.set_config(config);
    }

    /// Get recorder reference (for advanced configuration)
    pub fn recorder(&self) -> &Arc<AudioRecorder> {
        &self.recorder
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SETTINGS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Update settings (requires restart)
    pub fn update_settings(&self, settings: EngineSettings) {
        // Update device config (UI thread only)
        *self.device_config.write() = DeviceConfig {
            output_device: settings.output_device,
            input_device: settings.input_device,
        };

        // Update audio settings atomically (lock-free)
        self.sample_rate.store(settings.sample_rate.as_u32(), Ordering::Release);
        self.buffer_size.store(settings.buffer_size.as_u32(), Ordering::Release);
    }

    /// Get current settings
    pub fn settings(&self) -> EngineSettings {
        let device_cfg = self.device_config.read().clone();
        let sample_rate_u32 = self.sample_rate.load(Ordering::Relaxed);
        let buffer_size_u32 = self.buffer_size.load(Ordering::Relaxed);

        EngineSettings {
            output_device: device_cfg.output_device,
            input_device: device_cfg.input_device,
            sample_rate: SampleRate::from_u32(sample_rate_u32).unwrap_or(SampleRate::Hz48000),
            buffer_size: BufferSize::from_u32(buffer_size_u32).unwrap_or(BufferSize::Samples256),
        }
    }

    /// Get sample rate (lock-free)
    pub fn sample_rate(&self) -> SampleRate {
        let rate = self.sample_rate.load(Ordering::Relaxed);
        SampleRate::from_u32(rate).unwrap_or(SampleRate::Hz48000)
    }

    /// Get buffer size (lock-free)
    pub fn buffer_size(&self) -> BufferSize {
        let size = self.buffer_size.load(Ordering::Relaxed);
        BufferSize::from_u32(size).unwrap_or(BufferSize::Samples256)
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
