//! Unified Playback System
//!
//! Connects rf-audio (cpal I/O) with rf-engine (PlaybackEngine)
//! Full audio flow: Clips → Tracks → Buses → Master → Audio Output
//!
//! Architecture:
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │ rf-engine::PlaybackEngine                                       │
//! │ ├── TrackManager (clips, tracks)                                │
//! │ ├── AudioCache (loaded audio files)                             │
//! │ ├── BusBuffers (6 buses + master)                               │
//! │ └── process() → outputs stereo f64                              │
//! └────────────────────┬────────────────────────────────────────────┘
//!                      │ AudioProcessor trait
//!                      ▼
//! ┌─────────────────────────────────────────────────────────────────┐
//! │ rf-audio::AudioEngine                                           │
//! │ ├── cpal output stream                                          │
//! │ ├── MeterData (atomic lock-free)                                │
//! │ ├── DSP Command Queue (lock-free)                               │
//! │ └── callback → f64 to f32 conversion                            │
//! └─────────────────────────────────────────────────────────────────┘
//! ```

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use parking_lot::{Mutex, RwLock};
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::thread;
use std::time::Duration;

use crate::command_queue::audio_command_handle;
use crate::dsp_commands::DspCommand;

use rf_engine::playback::{BusState, PlaybackEngine as EnginePlayback};
// Re-export BusState for external use

use rf_file::{AudioRecorder, RecordingConfig, RecordingState};

// ═══════════════════════════════════════════════════════════════════════════════
// BRIDGE PLAYBACK STATE (atomic for Flutter access)
// ═══════════════════════════════════════════════════════════════════════════════

/// Playback state (atomic for lock-free access)
#[derive(Debug, Default)]
pub struct PlaybackState {
    /// Is playing
    pub playing: AtomicBool,
    /// Is recording
    pub recording: AtomicBool,
    /// Current position in samples
    pub position_samples: AtomicU64,
    /// Sample rate as u64 bits
    sample_rate_bits: AtomicU64,
    /// Loop enabled
    pub loop_enabled: AtomicBool,
    /// Loop start in samples
    pub loop_start_samples: AtomicU64,
    /// Loop end in samples
    pub loop_end_samples: AtomicU64,
}

impl PlaybackState {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            playing: AtomicBool::new(false),
            recording: AtomicBool::new(false),
            position_samples: AtomicU64::new(0),
            sample_rate_bits: AtomicU64::new(sample_rate.to_bits()),
            loop_enabled: AtomicBool::new(false),
            loop_start_samples: AtomicU64::new(0),
            loop_end_samples: AtomicU64::new(0),
        }
    }

    pub fn sample_rate(&self) -> f64 {
        f64::from_bits(self.sample_rate_bits.load(Ordering::Relaxed))
    }

    pub fn set_sample_rate(&self, sr: f64) {
        self.sample_rate_bits.store(sr.to_bits(), Ordering::Relaxed);
    }

    pub fn position_seconds(&self) -> f64 {
        let samples = self.position_samples.load(Ordering::Relaxed);
        let sr = self.sample_rate();
        if sr > 0.0 { samples as f64 / sr } else { 0.0 }
    }

    pub fn set_position_seconds(&self, seconds: f64) {
        let sr = self.sample_rate();
        let samples = (seconds * sr) as u64;
        self.position_samples.store(samples, Ordering::Relaxed);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// METERS (atomic for lock-free Flutter access)
// ═══════════════════════════════════════════════════════════════════════════════

/// Real-time metering data (atomic for lock-free UI access)
#[derive(Debug, Default)]
pub struct PlaybackMeters {
    pub peak_l: AtomicU64,
    pub peak_r: AtomicU64,
    pub rms_l: AtomicU64,
    pub rms_r: AtomicU64,
    pub clipped: AtomicBool,
    /// Bus peaks (6 buses)
    pub bus_peaks: [AtomicU64; 12], // L/R for each bus
}

impl PlaybackMeters {
    pub fn new() -> Self {
        Self {
            peak_l: AtomicU64::new(0),
            peak_r: AtomicU64::new(0),
            rms_l: AtomicU64::new(0),
            rms_r: AtomicU64::new(0),
            clipped: AtomicBool::new(false),
            bus_peaks: std::array::from_fn(|_| AtomicU64::new(0)),
        }
    }

    pub fn get_peak_l(&self) -> f32 {
        f32::from_bits(self.peak_l.load(Ordering::Relaxed) as u32)
    }

    pub fn get_peak_r(&self) -> f32 {
        f32::from_bits(self.peak_r.load(Ordering::Relaxed) as u32)
    }

    pub fn set_peak(&self, l: f32, r: f32) {
        self.peak_l.store(l.to_bits() as u64, Ordering::Relaxed);
        self.peak_r.store(r.to_bits() as u64, Ordering::Relaxed);
    }

    pub fn get_rms_l(&self) -> f32 {
        f32::from_bits(self.rms_l.load(Ordering::Relaxed) as u32)
    }

    pub fn get_rms_r(&self) -> f32 {
        f32::from_bits(self.rms_r.load(Ordering::Relaxed) as u32)
    }

    pub fn set_rms(&self, l: f32, r: f32) {
        self.rms_l.store(l.to_bits() as u64, Ordering::Relaxed);
        self.rms_r.store(r.to_bits() as u64, Ordering::Relaxed);
    }

    pub fn get_bus_peak(&self, bus_idx: usize) -> (f32, f32) {
        let l_idx = bus_idx * 2;
        let r_idx = l_idx + 1;
        if r_idx < self.bus_peaks.len() {
            let l = f32::from_bits(self.bus_peaks[l_idx].load(Ordering::Relaxed) as u32);
            let r = f32::from_bits(self.bus_peaks[r_idx].load(Ordering::Relaxed) as u32);
            (l, r)
        } else {
            (0.0, 0.0)
        }
    }

    pub fn set_bus_peak(&self, bus_idx: usize, l: f32, r: f32) {
        let l_idx = bus_idx * 2;
        let r_idx = l_idx + 1;
        if r_idx < self.bus_peaks.len() {
            self.bus_peaks[l_idx].store(l.to_bits() as u64, Ordering::Relaxed);
            self.bus_peaks[r_idx].store(r.to_bits() as u64, Ordering::Relaxed);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DSP PROCESSOR STORAGE (per-track EQ instances)
// ═══════════════════════════════════════════════════════════════════════════════

use rf_engine::InsertProcessor;
use rf_engine::{
    Api550Wrapper, Neve1073Wrapper, ProEqWrapper, PultecWrapper,
    RoomCorrectionWrapper, UltraEqWrapper,
};

/// Per-track DSP processor collection
pub struct TrackDsp {
    /// Pro EQ 64-band
    pub pro_eq: Option<ProEqWrapper>,
    /// Ultra EQ 256-band
    pub ultra_eq: Option<UltraEqWrapper>,
    /// Pultec emulation
    pub pultec: Option<PultecWrapper>,
    /// API 550 emulation
    pub api550: Option<Api550Wrapper>,
    /// Neve 1073 emulation
    pub neve1073: Option<Neve1073Wrapper>,
    /// Morphing EQ
    /// Room correction
    pub room_correction: Option<RoomCorrectionWrapper>,
}

impl TrackDsp {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            pro_eq: Some(ProEqWrapper::new(sample_rate)),
            ultra_eq: None,        // On-demand
            pultec: None,          // On-demand
            api550: None,          // On-demand
            neve1073: None,        // On-demand
            room_correction: None, // On-demand
        }
    }

    /// Process audio through all active processors
    pub fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        // Process chain order: EQ → Analog → Room Correction
        if let Some(ref mut eq) = self.pro_eq {
            eq.process_stereo(left, right);
        }
        if let Some(ref mut eq) = self.ultra_eq {
            eq.process_stereo(left, right);
        }
        if let Some(ref mut eq) = self.pultec {
            eq.process_stereo(left, right);
        }
        if let Some(ref mut eq) = self.api550 {
            eq.process_stereo(left, right);
        }
        if let Some(ref mut eq) = self.neve1073 {
            eq.process_stereo(left, right);
        }
        if let Some(ref mut eq) = self.room_correction {
            eq.process_stereo(left, right);
        }
    }

    /// Reset all processors
    pub fn reset(&mut self) {
        if let Some(ref mut eq) = self.pro_eq {
            eq.reset();
        }
        if let Some(ref mut eq) = self.ultra_eq {
            eq.reset();
        }
        if let Some(ref mut eq) = self.pultec {
            eq.reset();
        }
        if let Some(ref mut eq) = self.api550 {
            eq.reset();
        }
        if let Some(ref mut eq) = self.neve1073 {
            eq.reset();
        }
        if let Some(ref mut eq) = self.room_correction {
            eq.reset();
        }
    }

    /// Set sample rate for all processors
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        if let Some(ref mut eq) = self.pro_eq {
            eq.set_sample_rate(sample_rate);
        }
        if let Some(ref mut eq) = self.ultra_eq {
            eq.set_sample_rate(sample_rate);
        }
        if let Some(ref mut eq) = self.pultec {
            eq.set_sample_rate(sample_rate);
        }
        if let Some(ref mut eq) = self.api550 {
            eq.set_sample_rate(sample_rate);
        }
        if let Some(ref mut eq) = self.neve1073 {
            eq.set_sample_rate(sample_rate);
        }
        if let Some(ref mut eq) = self.room_correction {
            eq.set_sample_rate(sample_rate);
        }
    }
}

/// Global DSP storage for all tracks
pub struct DspStorage {
    tracks: HashMap<u32, TrackDsp>,
    sample_rate: f64,
}

impl DspStorage {
    pub fn new(sample_rate: f64) -> Self {
        let mut storage = Self {
            tracks: HashMap::new(),
            sample_rate,
        };
        // Pre-create master DSP (track_id = 0) so EQ works immediately
        storage.tracks.insert(0, TrackDsp::new(sample_rate));
        storage
    }

    /// Get or create track DSP
    pub fn get_or_create(&mut self, track_id: u32) -> &mut TrackDsp {
        self.tracks
            .entry(track_id)
            .or_insert_with(|| TrackDsp::new(self.sample_rate))
    }

    /// Get track DSP if exists
    pub fn get(&mut self, track_id: u32) -> Option<&mut TrackDsp> {
        self.tracks.get_mut(&track_id)
    }

    /// Remove track
    pub fn remove(&mut self, track_id: u32) {
        self.tracks.remove(&track_id);
    }

    /// Set sample rate for all tracks
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for (_, dsp) in self.tracks.iter_mut() {
            dsp.set_sample_rate(sample_rate);
        }
    }

    /// Process commands from queue
    pub fn process_command(&mut self, cmd: DspCommand) {
        // Clone sample_rate to avoid borrow issues
        let sample_rate = self.sample_rate;

        match cmd {
            // Pro EQ commands
            DspCommand::EqSetGain {
                track_id,
                band_index,
                gain_db,
            } => {
                println!(
                    "[DSP] EqSetGain track={} band={} gain={}dB",
                    track_id, band_index, gain_db
                );
                let dsp = self.get_or_create(track_id);
                if let Some(ref mut eq) = dsp.pro_eq {
                    // Get current params and update gain
                    let idx = band_index as usize;
                    eq.set_param(idx * 5 + 1, gain_db); // Param 1 = gain
                    println!("[DSP] -> Applied gain to band {}", band_index);
                }
            }
            DspCommand::EqSetFrequency {
                track_id,
                band_index,
                freq,
            } => {
                let dsp = self.get_or_create(track_id);
                if let Some(ref mut eq) = dsp.pro_eq {
                    let idx = band_index as usize;
                    eq.set_param(idx * 5, freq); // Param 0 = frequency
                }
            }
            DspCommand::EqSetQ {
                track_id,
                band_index,
                q,
            } => {
                let dsp = self.get_or_create(track_id);
                if let Some(ref mut eq) = dsp.pro_eq {
                    let idx = band_index as usize;
                    eq.set_param(idx * 5 + 2, q); // Param 2 = Q
                }
            }
            DspCommand::EqEnableBand {
                track_id,
                band_index,
                enabled,
            } => {
                println!(
                    "[DSP] EqEnableBand track={} band={} enabled={}",
                    track_id, band_index, enabled
                );
                let dsp = self.get_or_create(track_id);
                if let Some(ref mut eq) = dsp.pro_eq {
                    eq.set_band_enabled(band_index as usize, enabled);
                    println!("[DSP] -> Band {} enabled={}", band_index, enabled);
                }
            }
            DspCommand::EqBypass { track_id, bypass } => {
                let dsp = self.get_or_create(track_id);
                if let Some(ref mut eq) = dsp.pro_eq {
                    eq.set_bypass(bypass);
                }
            }

            // Pultec commands
            DspCommand::PultecSetLowBoost {
                track_id,
                boost_db,
                freq: _,
            } => {
                let dsp = self.get_or_create(track_id);
                if dsp.pultec.is_none() {
                    dsp.pultec = Some(PultecWrapper::new(sample_rate));
                }
                if let Some(ref mut eq) = dsp.pultec {
                    eq.set_low_boost(boost_db);
                }
            }
            DspCommand::PultecSetLowAtten { track_id, atten_db } => {
                let dsp = self.get_or_create(track_id);
                if dsp.pultec.is_none() {
                    dsp.pultec = Some(PultecWrapper::new(sample_rate));
                }
                if let Some(ref mut eq) = dsp.pultec {
                    eq.set_low_atten(atten_db);
                }
            }
            DspCommand::PultecSetHighBoost {
                track_id,
                boost_db,
                bandwidth: _,
                freq: _,
            } => {
                let dsp = self.get_or_create(track_id);
                if dsp.pultec.is_none() {
                    dsp.pultec = Some(PultecWrapper::new(sample_rate));
                }
                if let Some(ref mut eq) = dsp.pultec {
                    eq.set_high_boost(boost_db);
                }
            }
            DspCommand::PultecSetHighAtten {
                track_id,
                atten_db,
                freq: _,
            } => {
                let dsp = self.get_or_create(track_id);
                if dsp.pultec.is_none() {
                    dsp.pultec = Some(PultecWrapper::new(sample_rate));
                }
                if let Some(ref mut eq) = dsp.pultec {
                    eq.set_high_atten(atten_db);
                }
            }

            // Neve commands
            DspCommand::Neve1073SetLow {
                track_id,
                gain_db,
                freq_index: _,
            } => {
                let dsp = self.get_or_create(track_id);
                if dsp.neve1073.is_none() {
                    dsp.neve1073 = Some(Neve1073Wrapper::new(sample_rate));
                }
                if let Some(ref mut eq) = dsp.neve1073 {
                    eq.set_low_gain(gain_db);
                }
            }
            DspCommand::Neve1073SetHigh {
                track_id,
                gain_db,
                freq_index: _,
            } => {
                let dsp = self.get_or_create(track_id);
                if dsp.neve1073.is_none() {
                    dsp.neve1073 = Some(Neve1073Wrapper::new(sample_rate));
                }
                if let Some(ref mut eq) = dsp.neve1073 {
                    eq.set_high_gain(gain_db);
                }
            }

            // Room correction
            DspCommand::RoomEqBypass { track_id, bypass } => {
                let dsp = self.get_or_create(track_id);
                if dsp.room_correction.is_none() {
                    dsp.room_correction = Some(RoomCorrectionWrapper::new(sample_rate));
                }
                if let Some(ref mut eq) = dsp.room_correction {
                    eq.set_enabled(!bypass);
                }
            }

            // Ignore other commands for now
            _ => {}
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYBACK CLIP (simple clip for testing without full engine)
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio clip for direct playback (without full engine)
#[derive(Clone)]
pub struct PlaybackClip {
    /// Clip ID
    pub id: String,
    /// Audio data L/R
    pub samples_l: Arc<Vec<f32>>,
    pub samples_r: Arc<Vec<f32>>,
    /// Start position in timeline (samples)
    pub start_sample: u64,
    /// Length in samples
    pub length_samples: u64,
    /// Gain (linear)
    pub gain: f32,
    /// Muted
    pub muted: bool,
}

// ═══════════════════════════════════════════════════════════════════════════════
// STREAM HOLDER (safe wrapper for cpal stream)
// ═══════════════════════════════════════════════════════════════════════════════

/// Wrapper to make Stream Send+Sync
struct StreamHolder(Option<cpal::Stream>);

// SAFETY: Stream is only accessed from one thread at a time
unsafe impl Send for StreamHolder {}
unsafe impl Sync for StreamHolder {}

// ═══════════════════════════════════════════════════════════════════════════════
// UNIFIED PLAYBACK ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified Playback Engine bridging rf-audio and rf-engine
///
/// Provides two modes:
/// 1. Full DAW mode - uses rf-engine::PlaybackEngine with tracks/buses
/// 2. Simple mode - direct clip playback for testing
pub struct PlaybackEngine {
    /// Bridge playback state (for Flutter)
    pub state: Arc<PlaybackState>,
    /// Meters (lock-free for Flutter)
    pub meters: Arc<PlaybackMeters>,
    /// Simple clips (for testing without full engine)
    simple_clips: RwLock<Vec<PlaybackClip>>,
    /// cpal output stream handle
    stream: Mutex<StreamHolder>,
    /// cpal input stream handle (for recording)
    input_stream: Mutex<StreamHolder>,
    /// Is stream running (Arc for sharing with threads)
    running: Arc<AtomicBool>,
    /// rf-engine PlaybackEngine (for full DAW mode)
    engine_playback: RwLock<Option<Arc<EnginePlayback>>>,
    /// Use engine mode (vs simple mode)
    use_engine_mode: AtomicBool,
    /// Master volume (linear, atomic for audio thread) - Arc for sharing with callback
    master_volume: Arc<AtomicU64>,
    /// Bus volumes (linear, atomic for audio thread) - 7 buses including master
    bus_volumes: [AtomicU64; 7],
    /// Audio recorder (for input capture)
    recorder: Arc<AudioRecorder>,
    /// Input level meters (L, R)
    input_peak_l: AtomicU64,
    input_peak_r: AtomicU64,
    /// Requested sample rate (0 = use device default)
    requested_sample_rate: AtomicU64,
    /// Requested buffer size (0 = use device default)
    requested_buffer_size: AtomicU64,
    /// Current output device name
    current_device: RwLock<Option<String>>,
    /// Input ring buffer producer (input thread writes here)
    input_buffer_producer: Mutex<Option<rtrb::Producer<f32>>>,
    /// Input ring buffer consumer (recording thread reads here)
    input_buffer_consumer: Mutex<Option<rtrb::Consumer<f32>>>,
    /// Recording flush thread handle
    recorder_thread: Mutex<Option<std::thread::JoinHandle<()>>>,
    /// Input monitoring enabled (hear input through output)
    input_monitoring: Arc<AtomicBool>,
    /// Input monitoring ring buffer consumer (output thread reads for monitoring)
    monitor_consumer: Mutex<Option<rtrb::Consumer<f32>>>,
}

impl PlaybackEngine {
    /// Create new playback engine
    pub fn new() -> Self {
        // Default recording config
        let rec_config = RecordingConfig {
            output_dir: std::path::PathBuf::from(std::env::var("HOME").unwrap_or("/tmp".into()))
                .join("Documents/Recordings"),
            file_prefix: "Recording".to_string(),
            sample_rate: 48000,
            bit_depth: rf_file::BitDepth::Int24,
            num_channels: 2,
            pre_roll_secs: 2.0,
            capture_pre_roll: true,
            min_disk_space: 100 * 1024 * 1024, // 100MB minimum
            disk_buffer_size: 256 * 1024,      // 256KB buffer
            auto_increment: true,
        };

        Self {
            state: Arc::new(PlaybackState::new(48000.0)),
            meters: Arc::new(PlaybackMeters::new()),
            simple_clips: RwLock::new(Vec::new()),
            stream: Mutex::new(StreamHolder(None)),
            input_stream: Mutex::new(StreamHolder(None)),
            running: Arc::new(AtomicBool::new(false)),
            engine_playback: RwLock::new(None),
            use_engine_mode: AtomicBool::new(false),
            master_volume: Arc::new(AtomicU64::new(1.0_f64.to_bits())), // Unity gain
            bus_volumes: std::array::from_fn(|_| AtomicU64::new(1.0_f64.to_bits())),
            recorder: Arc::new(AudioRecorder::new(rec_config)),
            input_peak_l: AtomicU64::new(0),
            input_peak_r: AtomicU64::new(0),
            requested_sample_rate: AtomicU64::new(0), // 0 = device default
            requested_buffer_size: AtomicU64::new(0), // 0 = device default
            current_device: RwLock::new(None),
            input_buffer_producer: Mutex::new(None),
            input_buffer_consumer: Mutex::new(None),
            recorder_thread: Mutex::new(None),
            input_monitoring: Arc::new(AtomicBool::new(false)),
            monitor_consumer: Mutex::new(None),
        }
    }

    /// Get master volume (linear)
    pub fn get_master_volume(&self) -> f64 {
        f64::from_bits(self.master_volume.load(Ordering::Relaxed))
    }

    /// Set master volume (linear) - used in simple mode
    pub fn set_master_volume_simple(&self, volume: f64) {
        self.master_volume
            .store(volume.to_bits(), Ordering::Relaxed);
    }

    /// Get bus volume (linear)
    pub fn get_bus_volume(&self, bus_idx: usize) -> f64 {
        if bus_idx < self.bus_volumes.len() {
            f64::from_bits(self.bus_volumes[bus_idx].load(Ordering::Relaxed))
        } else {
            1.0
        }
    }

    /// Set bus volume (linear) - used in simple mode
    pub fn set_bus_volume_simple(&self, bus_idx: usize, volume: f64) {
        if bus_idx < self.bus_volumes.len() {
            self.bus_volumes[bus_idx].store(volume.to_bits(), Ordering::Relaxed);
        }
    }

    /// Connect rf-engine PlaybackEngine for full DAW mode
    pub fn connect_engine(&self, engine: Arc<EnginePlayback>) {
        *self.engine_playback.write() = Some(engine);
        self.use_engine_mode.store(true, Ordering::Relaxed);
        log::info!("Connected rf-engine PlaybackEngine");
    }

    /// Disconnect engine (switch to simple mode)
    pub fn disconnect_engine(&self) {
        *self.engine_playback.write() = None;
        self.use_engine_mode.store(false, Ordering::Relaxed);
    }

    /// Start the audio stream
    pub fn start(&self) -> Result<(), String> {
        if self.running.load(Ordering::Acquire) {
            return Ok(());
        }

        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| "No output device found".to_string())?;

        let config = device
            .default_output_config()
            .map_err(|e| format!("Failed to get config: {}", e))?;

        let sample_rate = config.sample_rate().0 as f64;
        self.state.set_sample_rate(sample_rate);

        log::info!(
            "Starting unified audio playback: {} Hz, {} channels",
            config.sample_rate().0,
            config.channels()
        );

        // Clone what we need for the callback
        let state = Arc::clone(&self.state);
        let meters = Arc::clone(&self.meters);
        let engine_playback = self.engine_playback.read().clone();
        let simple_clips = Arc::new(RwLock::new(self.simple_clips.read().clone()));
        let use_engine = self.use_engine_mode.load(Ordering::Relaxed);

        // Share master volume Arc for live updates in callback
        let master_volume = Arc::clone(&self.master_volume);

        // Share input monitoring flag for callback
        let input_monitoring = Arc::clone(&self.input_monitoring);

        // Pre-create ring buffer for monitoring BEFORE output stream
        // This allows us to move consumer into output callback
        let buffer_samples = 192000 * 2;
        let (monitor_producer, monitor_consumer) = rtrb::RingBuffer::<f32>::new(buffer_samples);
        // Store producer in self for input callback to use later
        // Consumer goes directly into output callback
        let monitor_producer_arc = Arc::new(Mutex::new(Some(monitor_producer)));
        let monitor_producer_clone = Arc::clone(&monitor_producer_arc);

        // Peak decay
        let decay = 0.9995_f32.powf(config.sample_rate().0 as f32 / 60.0);
        let channels = config.channels() as usize;

        // Pre-allocated buffers for engine mode
        let buffer_size = 1024;
        let mut engine_output_l = vec![0.0f64; buffer_size];
        let mut engine_output_r = vec![0.0f64; buffer_size];

        // Pre-allocated buffer for input monitoring
        let mut monitor_buffer = vec![0.0f32; buffer_size * 2];

        // DSP storage for per-track processing
        let mut dsp_storage = DspStorage::new(sample_rate);

        // Clone master_volume for I16 path
        let master_volume_i16 = Arc::clone(&master_volume);
        let _input_monitoring_i16 = Arc::clone(&input_monitoring);

        // Move monitor consumer into callback
        let mut monitor_consumer = Some(monitor_consumer);

        let stream = match config.sample_format() {
            cpal::SampleFormat::F32 => {
                device.build_output_stream(
                    &config.into(),
                    move |data: &mut [f32], _| {
                        let frames = data.len() / channels;

                        // Ensure buffers are large enough
                        if engine_output_l.len() < frames {
                            engine_output_l.resize(frames, 0.0);
                            engine_output_r.resize(frames, 0.0);
                        }
                        if monitor_buffer.len() < frames * 2 {
                            monitor_buffer.resize(frames * 2, 0.0);
                        }

                        process_audio_unified(
                            data,
                            channels,
                            frames,
                            &state,
                            &meters,
                            &engine_playback,
                            &simple_clips,
                            use_engine,
                            decay,
                            &mut engine_output_l,
                            &mut engine_output_r,
                            &mut dsp_storage,
                            &master_volume,
                        );

                        // Add input monitoring signal if enabled
                        if input_monitoring.load(Ordering::Relaxed) {
                            if let Some(ref mut consumer) = monitor_consumer {
                                // Read available samples from monitor ring buffer
                                let stereo_samples = frames * 2;
                                let mut read_count = 0;
                                for sample in monitor_buffer[..stereo_samples].iter_mut() {
                                    if let Ok(s) = consumer.pop() {
                                        *sample = s;
                                        read_count += 1;
                                    } else {
                                        *sample = 0.0;
                                    }
                                }

                                // Mix monitoring signal into output
                                if read_count > 0 {
                                    for i in 0..frames {
                                        let idx = i * channels.max(2);
                                        if channels >= 2 && idx + 1 < data.len() {
                                            // Stereo: add L and R
                                            data[idx] += monitor_buffer[i * 2];
                                            data[idx + 1] += monitor_buffer[i * 2 + 1];
                                        } else if channels == 1 && idx < data.len() {
                                            // Mono: mix both channels
                                            data[idx] += (monitor_buffer[i * 2] + monitor_buffer[i * 2 + 1]) * 0.5;
                                        }
                                    }
                                }
                            }
                        }
                    },
                    |err| log::error!("Audio stream error: {}", err),
                    None,
                )
            }
            cpal::SampleFormat::I16 => {
                // For I16, we need a separate closure with its own dsp_storage
                let mut dsp_storage_i16 = DspStorage::new(sample_rate);
                device.build_output_stream(
                    &config.into(),
                    move |data: &mut [i16], _| {
                        let frames = data.len() / channels;

                        // Convert to f32 for processing
                        let mut float_data: Vec<f32> = vec![0.0; data.len()];

                        if engine_output_l.len() < frames {
                            engine_output_l.resize(frames, 0.0);
                            engine_output_r.resize(frames, 0.0);
                        }

                        process_audio_unified(
                            &mut float_data,
                            channels,
                            frames,
                            &state,
                            &meters,
                            &engine_playback,
                            &simple_clips,
                            use_engine,
                            decay,
                            &mut engine_output_l,
                            &mut engine_output_r,
                            &mut dsp_storage_i16,
                            &master_volume_i16,
                        );

                        // Convert back
                        for (out, &f) in data.iter_mut().zip(float_data.iter()) {
                            *out = (f * 32767.0).clamp(-32768.0, 32767.0) as i16;
                        }
                    },
                    |err| log::error!("Audio stream error: {}", err),
                    None,
                )
            }
            _ => return Err("Unsupported sample format".to_string()),
        }
        .map_err(|e| format!("Failed to build stream: {}", e))?;

        stream
            .play()
            .map_err(|e| format!("Failed to start stream: {}", e))?;

        self.stream.lock().0 = Some(stream);

        // Try to start input stream for recording
        if let Some(input_device) = host.default_input_device() {
            if let Ok(input_config) = input_device.default_input_config() {
                log::info!(
                    "Starting input stream for recording: {} Hz, {} channels",
                    input_config.sample_rate().0,
                    input_config.channels()
                );

                // Create lock-free ring buffer for recording
                // Buffer size: 1 second of stereo audio at max sample rate
                let recording_buffer_samples = 192000 * 2;
                let (producer, consumer) = rtrb::RingBuffer::<f32>::new(recording_buffer_samples);
                *self.input_buffer_producer.lock() = Some(producer);
                *self.input_buffer_consumer.lock() = Some(consumer);

                // Clone for input callback
                let input_peak_l = Arc::new(AtomicU64::new(0));
                let input_peak_r = Arc::new(AtomicU64::new(0));
                let input_peak_l_clone = Arc::clone(&input_peak_l);
                let input_peak_r_clone = Arc::clone(&input_peak_r);

                // Get producer for callback (need to take ownership)
                let mut producer_for_callback = self.input_buffer_producer.lock().take();
                // Get monitor producer from Arc (created before output stream)
                let mut monitor_producer_for_callback = monitor_producer_clone.lock().take();

                let input_channels = input_config.channels() as usize;

                let input_stream = input_device
                    .build_input_stream(
                        &input_config.into(),
                        move |data: &[f32], _: &cpal::InputCallbackInfo| {
                            // Calculate input levels
                            let frames = data.len() / input_channels.max(1);
                            let mut peak_l = 0.0f32;
                            let mut peak_r = 0.0f32;

                            for i in 0..frames {
                                let idx = i * input_channels;
                                if input_channels >= 1 {
                                    peak_l = peak_l.max(data[idx].abs());
                                }
                                if input_channels >= 2 {
                                    peak_r = peak_r.max(data[idx + 1].abs());
                                }
                            }

                            // Store peaks atomically
                            input_peak_l_clone.store((peak_l as f64).to_bits(), Ordering::Relaxed);
                            input_peak_r_clone.store((peak_r as f64).to_bits(), Ordering::Relaxed);

                            // Write to ring buffer for recording (non-blocking)
                            if let Some(ref mut producer) = producer_for_callback {
                                for sample in data.iter() {
                                    let _ = producer.push(*sample);
                                }
                            }

                            // Write to monitor ring buffer (non-blocking)
                            if let Some(ref mut producer) = monitor_producer_for_callback {
                                for sample in data.iter() {
                                    let _ = producer.push(*sample);
                                }
                            }
                        },
                        |err| log::error!("Input stream error: {}", err),
                        None,
                    )
                    .map_err(|e| format!("Failed to build input stream: {}", e))?;

                input_stream
                    .play()
                    .map_err(|e| format!("Failed to start input stream: {}", e))?;

                self.input_stream.lock().0 = Some(input_stream);

                // Store input peak atomics for later reading
                self.input_peak_l
                    .store(input_peak_l.load(Ordering::Relaxed), Ordering::Relaxed);
                self.input_peak_r
                    .store(input_peak_r.load(Ordering::Relaxed), Ordering::Relaxed);

                // Start background thread for recording flush
                let recorder_clone = Arc::clone(&self.recorder);
                let consumer_for_thread = self.input_buffer_consumer.lock().take();
                let running_clone = Arc::clone(&self.running);
                let state_clone = Arc::clone(&self.state);

                let recorder_handle = thread::Builder::new()
                    .name("recording-flush".into())
                    .spawn(move || {
                        log::debug!("Recording flush thread started");
                        let mut local_buffer = vec![0.0f32; 4096]; // Pre-allocated

                        // We need to store consumer in the thread
                        let mut consumer = consumer_for_thread;

                        while running_clone.load(Ordering::Acquire) {
                            // Read from ring buffer
                            if let Some(ref mut cons) = consumer {
                                let available = cons.slots();
                                if available > 0 {
                                    let to_read = available.min(local_buffer.len());
                                    for sample_slot in local_buffer.iter_mut().take(to_read) {
                                        if let Ok(sample) = cons.pop() {
                                            *sample_slot = sample;
                                        }
                                    }

                                    // Send to recorder if armed/recording
                                    let rec_state = recorder_clone.state();
                                    if rec_state == RecordingState::Armed
                                        || rec_state == RecordingState::Recording
                                    {
                                        let position =
                                            state_clone.position_samples.load(Ordering::Relaxed);
                                        recorder_clone.process(&local_buffer[..to_read], position);
                                    }
                                }
                            }

                            // Flush pending samples to disk
                            if let Err(e) = recorder_clone.flush_pending() {
                                log::error!("Recording flush error: {}", e);
                            }

                            // Don't busy-wait
                            thread::sleep(Duration::from_millis(5));
                        }

                        log::debug!("Recording flush thread stopped");
                    })
                    .ok();

                *self.recorder_thread.lock() = recorder_handle;

                log::info!("Input stream started for recording");
            } else {
                log::warn!("Could not get input device config");
            }
        } else {
            log::warn!("No input device available for recording");
        }

        self.running.store(true, Ordering::Release);

        Ok(())
    }

    /// Stop the audio stream
    pub fn stop(&self) -> Result<(), String> {
        if !self.running.load(Ordering::Acquire) {
            return Ok(());
        }

        // Stop recording if active
        if self.recorder.state() == RecordingState::Recording {
            let _ = self.recorder.stop();
        }

        // Stop streams
        self.input_stream.lock().0.take();
        self.stream.lock().0.take();
        self.running.store(false, Ordering::Release);
        self.state.playing.store(false, Ordering::Relaxed);

        // Wait for recorder thread
        if let Some(handle) = self.recorder_thread.lock().take() {
            let _ = handle.join();
        }

        Ok(())
    }

    /// Play transport
    pub fn play(&self) {
        self.state.playing.store(true, Ordering::Relaxed);

        // Sync with engine if connected
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.play();
        }
    }

    /// Pause transport
    pub fn pause(&self) {
        self.state.playing.store(false, Ordering::Relaxed);

        if let Some(ref engine) = *self.engine_playback.read() {
            engine.pause();
        }
    }

    /// Stop transport and reset position
    pub fn transport_stop(&self) {
        self.state.playing.store(false, Ordering::Relaxed);
        self.state.position_samples.store(0, Ordering::Relaxed);

        if let Some(ref engine) = *self.engine_playback.read() {
            engine.stop();
        }
    }

    /// Seek to position (seconds)
    pub fn seek(&self, seconds: f64) {
        self.state.set_position_seconds(seconds);

        if let Some(ref engine) = *self.engine_playback.read() {
            engine.seek(seconds);
        }
    }

    /// Set loop range
    pub fn set_loop(&self, enabled: bool, start_sec: f64, end_sec: f64) {
        let sr = self.state.sample_rate();
        self.state.loop_enabled.store(enabled, Ordering::Relaxed);
        self.state
            .loop_start_samples
            .store((start_sec * sr) as u64, Ordering::Relaxed);
        self.state
            .loop_end_samples
            .store((end_sec * sr) as u64, Ordering::Relaxed);

        if let Some(ref engine) = *self.engine_playback.read() {
            engine.position.set_loop(start_sec, end_sec, enabled);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCRUBBING (Pro Tools / Cubase style audio preview)
    // ═══════════════════════════════════════════════════════════════════════

    /// Start scrubbing at given position
    pub fn start_scrub(&self, seconds: f64) {
        self.state.set_position_seconds(seconds);

        if let Some(ref engine) = *self.engine_playback.read() {
            engine.start_scrub(seconds);
        }
    }

    /// Update scrub position with velocity
    pub fn update_scrub(&self, seconds: f64, velocity: f64) {
        self.state.set_position_seconds(seconds);

        if let Some(ref engine) = *self.engine_playback.read() {
            engine.update_scrub(seconds, velocity);
        }
    }

    /// Stop scrubbing
    pub fn stop_scrub(&self) {
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.stop_scrub();
        }
    }

    /// Check if currently scrubbing
    pub fn is_scrubbing(&self) -> bool {
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.is_scrubbing()
        } else {
            false
        }
    }

    /// Set scrub window size in milliseconds
    pub fn set_scrub_window_ms(&self, ms: u64) {
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.set_scrub_window_ms(ms);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OFFLINE RENDERING (for export)
    // ═══════════════════════════════════════════════════════════════════════

    /// Process audio offline at specific position (for export)
    /// Fills output_l and output_r with rendered audio starting at sample_position
    pub fn process_offline(&self, sample_position: u64, output_l: &mut [f64], output_r: &mut [f64]) {
        let frames = output_l.len().min(output_r.len());

        // Try to use rf-engine first for full DAW processing
        if let Some(ref engine) = *self.engine_playback.read() {
            // Process through full engine (tracks, buses, effects)
            engine.process_offline(sample_position as usize, output_l, output_r);
            return;
        }

        // Fallback: Simple clips mode - render clips directly
        if let Some(clips_guard) = self.simple_clips.try_read() {
            let _sample_rate = self.state.sample_rate();

            // Clear output
            output_l.fill(0.0);
            output_r.fill(0.0);

            for i in 0..frames {
                let current_pos = sample_position + i as u64;

                for clip in clips_guard.iter() {
                    if clip.muted {
                        continue;
                    }

                    if current_pos >= clip.start_sample {
                        let clip_pos = (current_pos - clip.start_sample) as usize;
                        if clip_pos < clip.samples_l.len() {
                            output_l[i] += clip.samples_l[clip_pos] as f64 * clip.gain as f64;
                            output_r[i] += clip.samples_r[clip_pos] as f64 * clip.gain as f64;
                        }
                    }
                }
            }

            // Apply master volume
            let master_vol = f64::from_bits(self.master_volume.load(Ordering::Relaxed));
            for i in 0..frames {
                output_l[i] *= master_vol;
                output_r[i] *= master_vol;
            }
        } else {
            // No clips, output silence
            output_l.fill(0.0);
            output_r.fill(0.0);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUS CONTROLS (forwarded to rf-engine)
    // ═══════════════════════════════════════════════════════════════════════

    /// Set bus volume
    pub fn set_bus_volume(&self, bus_idx: usize, volume: f64) {
        // Always set simple mode volume (for fallback)
        self.set_bus_volume_simple(bus_idx, volume);

        // Also forward to engine if connected
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.set_bus_volume(bus_idx, volume);
        }
    }

    /// Set bus pan
    pub fn set_bus_pan(&self, bus_idx: usize, pan: f64) {
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.set_bus_pan(bus_idx, pan);
        }
    }

    /// Set bus mute
    pub fn set_bus_mute(&self, bus_idx: usize, muted: bool) {
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.set_bus_mute(bus_idx, muted);
        }
    }

    /// Set bus solo
    pub fn set_bus_solo(&self, bus_idx: usize, soloed: bool) {
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.set_bus_solo(bus_idx, soloed);
        }
    }

    /// Get bus state
    pub fn get_bus_state(&self, bus_idx: usize) -> Option<BusState> {
        self.engine_playback.read().as_ref()?.get_bus_state(bus_idx)
    }

    /// Set master volume
    pub fn set_master_volume(&self, volume: f64) {
        // Always set simple mode volume (for fallback)
        self.set_master_volume_simple(volume);

        // Also forward to engine if connected
        if let Some(ref engine) = *self.engine_playback.read() {
            engine.set_master_volume(volume);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RECORDING
    // ═══════════════════════════════════════════════════════════════════════

    /// Get the audio recorder
    pub fn recorder(&self) -> &Arc<AudioRecorder> {
        &self.recorder
    }

    /// Arm recording
    pub fn recording_arm(&self) -> bool {
        self.recorder.arm().is_ok()
    }

    /// Disarm recording
    pub fn recording_disarm(&self) {
        self.recorder.disarm();
    }

    /// Start recording
    pub fn recording_start(&self) -> Result<String, String> {
        self.state.recording.store(true, Ordering::Relaxed);
        self.recorder
            .start()
            .map(|path| path.to_string_lossy().to_string())
            .map_err(|e| e.to_string())
    }

    /// Stop recording
    pub fn recording_stop(&self) -> Option<String> {
        self.state.recording.store(false, Ordering::Relaxed);
        self.recorder
            .stop()
            .ok()
            .flatten()
            .map(|path| path.to_string_lossy().to_string())
    }

    /// Pause recording
    pub fn recording_pause(&self) -> bool {
        self.recorder.pause().is_ok()
    }

    /// Resume recording
    pub fn recording_resume(&self) -> bool {
        self.recorder.resume().is_ok()
    }

    /// Get recording state
    pub fn recording_state(&self) -> RecordingState {
        self.recorder.state()
    }

    /// Is recording
    pub fn is_recording(&self) -> bool {
        self.recorder.state() == RecordingState::Recording
    }

    /// Set recording config
    pub fn set_recording_config(&self, config: RecordingConfig) {
        self.recorder.set_config(config);
    }

    /// Get input peak levels
    pub fn get_input_peaks(&self) -> (f32, f32) {
        (
            f32::from_bits(self.input_peak_l.load(Ordering::Relaxed) as u32),
            f32::from_bits(self.input_peak_r.load(Ordering::Relaxed) as u32),
        )
    }

    /// Enable/disable input monitoring (hear input through output)
    pub fn set_input_monitoring(&self, enabled: bool) {
        self.input_monitoring.store(enabled, Ordering::Relaxed);
        log::info!("Input monitoring: {}", if enabled { "ON" } else { "OFF" });
    }

    /// Check if input monitoring is enabled
    pub fn is_input_monitoring(&self) -> bool {
        self.input_monitoring.load(Ordering::Relaxed)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SIMPLE MODE (clips without full engine)
    // ═══════════════════════════════════════════════════════════════════════

    /// Add a clip for simple mode playback
    pub fn add_clip(&self, clip: PlaybackClip) {
        self.simple_clips.write().push(clip);
    }

    /// Remove clip by ID
    pub fn remove_clip(&self, id: &str) {
        self.simple_clips.write().retain(|c| c.id != id);
    }

    /// Clear all simple clips
    pub fn clear_clips(&self) {
        self.simple_clips.write().clear();
    }

    /// Load audio file as simple clip (test tone for now)
    pub fn load_audio_file(&self, id: &str, _path: &str, start_sample: u64) -> Result<(), String> {
        let sample_rate = self.state.sample_rate() as usize;
        let duration_samples = sample_rate * 5; // 5 seconds

        let mut samples_l = Vec::with_capacity(duration_samples);
        let mut samples_r = Vec::with_capacity(duration_samples);

        // Generate 440Hz test tone
        for i in 0..duration_samples {
            let t = i as f32 / sample_rate as f32;
            let sample = (2.0 * std::f32::consts::PI * 440.0 * t).sin() * 0.3;
            samples_l.push(sample);
            samples_r.push(sample);
        }

        let clip = PlaybackClip {
            id: id.to_string(),
            samples_l: Arc::new(samples_l),
            samples_r: Arc::new(samples_r),
            start_sample,
            length_samples: duration_samples as u64,
            gain: 1.0,
            muted: false,
        };

        self.add_clip(clip);
        Ok(())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATUS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if running
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire)
    }

    /// Get current position in seconds
    pub fn position_seconds(&self) -> f64 {
        self.state.position_seconds()
    }

    /// Check if playing
    pub fn is_playing(&self) -> bool {
        self.state.playing.load(Ordering::Relaxed)
    }

    /// Check if using engine mode
    pub fn is_engine_mode(&self) -> bool {
        self.use_engine_mode.load(Ordering::Relaxed)
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> f64 {
        self.state.sample_rate()
    }

    /// Get estimated latency in milliseconds
    pub fn latency_ms(&self) -> f64 {
        // Approximate based on buffer size (assume 256 samples at current rate)
        let buffer_size = 256.0;
        let sr = self.state.sample_rate();
        if sr > 0.0 {
            (buffer_size / sr) * 1000.0
        } else {
            0.0
        }
    }

    /// Get current output device name
    pub fn current_output_device(&self) -> Option<String> {
        // TODO: Store this when setting device
        let host = cpal::default_host();
        host.default_output_device().and_then(|d| d.name().ok())
    }

    /// Start with specific device
    pub fn start_with_device(&self, device_name: &str) -> Result<(), String> {
        if self.running.load(Ordering::Acquire) {
            self.stop()?;
        }

        let host = cpal::default_host();

        // Find device by name
        let device = host
            .output_devices()
            .map_err(|e| format!("Failed to enumerate devices: {}", e))?
            .find(|d| d.name().ok().as_deref() == Some(device_name))
            .ok_or_else(|| format!("Device not found: {}", device_name))?;

        let config = device
            .default_output_config()
            .map_err(|e| format!("Failed to get config: {}", e))?;

        let sample_rate = config.sample_rate().0 as f64;
        self.state.set_sample_rate(sample_rate);

        log::info!(
            "Starting audio on device '{}': {} Hz, {} channels",
            device_name,
            config.sample_rate().0,
            config.channels()
        );

        // Clone what we need for the callback
        let state = Arc::clone(&self.state);
        let meters = Arc::clone(&self.meters);
        let engine_playback = self.engine_playback.read().clone();
        let simple_clips = Arc::new(RwLock::new(self.simple_clips.read().clone()));
        let use_engine = self.use_engine_mode.load(Ordering::Relaxed);
        let master_volume = Arc::clone(&self.master_volume);

        let decay = 0.9995_f32.powf(config.sample_rate().0 as f32 / 60.0);
        let channels = config.channels() as usize;
        let buffer_size = 1024;
        let mut engine_output_l = vec![0.0f64; buffer_size];
        let mut engine_output_r = vec![0.0f64; buffer_size];
        let mut dsp_storage = DspStorage::new(sample_rate);

        // Flag for one-time priority elevation in audio thread
        let priority_set = std::sync::atomic::AtomicBool::new(false);

        let stream = match config.sample_format() {
            cpal::SampleFormat::F32 => {
                device.build_output_stream(
                    &config.into(),
                    move |data: &mut [f32], _| {
                        // Set real-time thread priority on first callback
                        // This runs in the audio thread context
                        if !priority_set.swap(true, Ordering::Relaxed) {
                            rf_audio::set_realtime_priority();
                        }

                        let frames = data.len() / channels;
                        if engine_output_l.len() < frames {
                            engine_output_l.resize(frames, 0.0);
                            engine_output_r.resize(frames, 0.0);
                        }
                        process_audio_unified(
                            data,
                            channels,
                            frames,
                            &state,
                            &meters,
                            &engine_playback,
                            &simple_clips,
                            use_engine,
                            decay,
                            &mut engine_output_l,
                            &mut engine_output_r,
                            &mut dsp_storage,
                            &master_volume,
                        );
                    },
                    |err| log::error!("Audio stream error: {}", err),
                    None,
                )
            }
            _ => return Err("Unsupported sample format".to_string()),
        }
        .map_err(|e| format!("Failed to build stream: {}", e))?;

        stream
            .play()
            .map_err(|e| format!("Failed to start stream: {}", e))?;

        self.stream.lock().0 = Some(stream);
        self.running.store(true, Ordering::Release);

        Ok(())
    }

    /// Play test tone (440Hz for specified duration)
    pub fn play_test_tone(&self, freq: f32, duration_sec: f32) {
        let sample_rate = self.state.sample_rate() as usize;
        let num_samples = (duration_sec * sample_rate as f32) as usize;

        let mut samples_l = Vec::with_capacity(num_samples);
        let mut samples_r = Vec::with_capacity(num_samples);

        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            // Sine wave with envelope
            let envelope = if i < sample_rate / 20 {
                i as f32 / (sample_rate / 20) as f32
            } else if i > num_samples - sample_rate / 20 {
                (num_samples - i) as f32 / (sample_rate / 20) as f32
            } else {
                1.0
            };
            let sample = (2.0 * std::f32::consts::PI * freq * t).sin() * 0.3 * envelope;
            samples_l.push(sample);
            samples_r.push(sample);
        }

        let clip = PlaybackClip {
            id: "_test_tone".to_string(),
            samples_l: Arc::new(samples_l),
            samples_r: Arc::new(samples_r),
            start_sample: self.state.position_samples.load(Ordering::Relaxed),
            length_samples: num_samples as u64,
            gain: 1.0,
            muted: false,
        };

        // Remove old test tone and add new
        self.remove_clip("_test_tone");
        self.add_clip(clip);

        // Start playing if not already
        if !self.is_playing() {
            self.play();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AUDIO DEVICE SETTINGS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Set requested sample rate (will be applied on next start/restart)
    pub fn set_requested_sample_rate(&self, sample_rate: u32) {
        self.requested_sample_rate
            .store(sample_rate as u64, Ordering::Relaxed);
    }

    /// Get requested sample rate (0 = device default)
    pub fn get_requested_sample_rate(&self) -> u32 {
        self.requested_sample_rate.load(Ordering::Relaxed) as u32
    }

    /// Set requested buffer size (will be applied on next start/restart)
    pub fn set_requested_buffer_size(&self, buffer_size: u32) {
        self.requested_buffer_size
            .store(buffer_size as u64, Ordering::Relaxed);
    }

    /// Get requested buffer size (0 = device default)
    pub fn get_requested_buffer_size(&self) -> u32 {
        self.requested_buffer_size.load(Ordering::Relaxed) as u32
    }

    /// Get current buffer size (from stream config)
    pub fn get_current_buffer_size(&self) -> u32 {
        // Approximate - cpal doesn't expose this directly
        // Return requested if set, otherwise default estimate
        let requested = self.get_requested_buffer_size();
        if requested > 0 { requested } else { 256 }
    }

    /// Restart audio with new settings
    pub fn restart_with_settings(
        &self,
        sample_rate: Option<u32>,
        buffer_size: Option<u32>,
    ) -> Result<(), String> {
        // Store new settings
        if let Some(sr) = sample_rate {
            self.set_requested_sample_rate(sr);
        }
        if let Some(bs) = buffer_size {
            self.set_requested_buffer_size(bs);
        }

        // Stop current stream
        let was_playing = self.is_playing();
        if self.running.load(Ordering::Acquire) {
            self.stop()?;
        }

        // Get device
        let device_name = self.current_device.read().clone();
        let host = cpal::default_host();

        let device = if let Some(ref name) = device_name {
            host.output_devices()
                .map_err(|e| format!("Failed to enumerate devices: {}", e))?
                .find(|d| d.name().ok().as_deref() == Some(name))
                .ok_or_else(|| format!("Device not found: {}", name))?
        } else {
            host.default_output_device()
                .ok_or_else(|| "No output device found".to_string())?
        };

        // Get supported configs
        let supported = device
            .supported_output_configs()
            .map_err(|e| format!("Failed to get supported configs: {}", e))?;

        // Find best matching config
        let req_sr = self.get_requested_sample_rate();
        let target_sr = if req_sr > 0 { req_sr } else { 48000 };

        let config = supported
            .filter(|c| c.channels() >= 2).find(|c| c.min_sample_rate().0 <= target_sr && c.max_sample_rate().0 >= target_sr)
            .map(|c| c.with_sample_rate(cpal::SampleRate(target_sr)))
            .or_else(|| device.default_output_config().ok())
            .ok_or_else(|| "No suitable config found".to_string())?;

        let actual_sample_rate = config.sample_rate().0 as f64;
        self.state.set_sample_rate(actual_sample_rate);

        log::info!(
            "Restarting audio: {} Hz, {} channels (requested: {} Hz)",
            config.sample_rate().0,
            config.channels(),
            target_sr
        );

        // Clone what we need for the callback
        let state = Arc::clone(&self.state);
        let meters = Arc::clone(&self.meters);
        let engine_playback = self.engine_playback.read().clone();
        let simple_clips = Arc::new(RwLock::new(self.simple_clips.read().clone()));
        let use_engine = self.use_engine_mode.load(Ordering::Relaxed);
        let master_volume = Arc::clone(&self.master_volume);

        let decay = 0.9995_f32.powf(config.sample_rate().0 as f32 / 60.0);
        let channels = config.channels() as usize;
        let buffer_len = 1024;
        let mut engine_output_l = vec![0.0f64; buffer_len];
        let mut engine_output_r = vec![0.0f64; buffer_len];
        let mut dsp_storage = DspStorage::new(actual_sample_rate);

        let priority_set = std::sync::atomic::AtomicBool::new(false);

        let stream = match config.sample_format() {
            cpal::SampleFormat::F32 => device.build_output_stream(
                &config.into(),
                move |data: &mut [f32], _| {
                    if !priority_set.swap(true, Ordering::Relaxed) {
                        rf_audio::set_realtime_priority();
                    }
                    let frames = data.len() / channels;
                    if engine_output_l.len() < frames {
                        engine_output_l.resize(frames, 0.0);
                        engine_output_r.resize(frames, 0.0);
                    }
                    process_audio_unified(
                        data,
                        channels,
                        frames,
                        &state,
                        &meters,
                        &engine_playback,
                        &simple_clips,
                        use_engine,
                        decay,
                        &mut engine_output_l,
                        &mut engine_output_r,
                        &mut dsp_storage,
                        &master_volume,
                    );
                },
                |err| log::error!("Audio stream error: {}", err),
                None,
            ),
            _ => return Err("Unsupported sample format".to_string()),
        }
        .map_err(|e| format!("Failed to build stream: {}", e))?;

        stream
            .play()
            .map_err(|e| format!("Failed to start stream: {}", e))?;

        self.stream.lock().0 = Some(stream);
        self.running.store(true, Ordering::Release);

        // Resume playback if was playing
        if was_playing {
            self.play();
        }

        Ok(())
    }

    /// Set output device and optionally restart
    pub fn set_output_device(&self, device_name: &str, restart: bool) -> Result<(), String> {
        *self.current_device.write() = Some(device_name.to_string());

        if restart && self.running.load(Ordering::Acquire) {
            self.start_with_device(device_name)?;
        }

        Ok(())
    }
}

impl Default for PlaybackEngine {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO CALLBACK (real-time safe)
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified audio processing callback
/// Supports both engine mode (full DAW) and simple mode (direct clips)
/// Also processes DSP commands from the lock-free queue
#[inline]
fn process_audio_unified(
    data: &mut [f32],
    channels: usize,
    frames: usize,
    state: &PlaybackState,
    meters: &PlaybackMeters,
    engine: &Option<Arc<EnginePlayback>>,
    simple_clips: &RwLock<Vec<PlaybackClip>>,
    use_engine: bool,
    decay: f32,
    engine_output_l: &mut [f64],
    engine_output_r: &mut [f64],
    dsp_storage: &mut DspStorage,
    master_volume: &AtomicU64,
) {
    // Process DSP commands from queue (lock-free, non-blocking)
    // Uses try_lock to avoid blocking the audio thread
    if let Some(mut audio_handle) = audio_command_handle().try_lock() {
        // Process up to 64 commands per callback to avoid stalling
        let mut cmd_count = 0;
        for cmd in audio_handle.poll_commands() {
            dsp_storage.process_command(cmd);
            cmd_count += 1;
            if cmd_count >= 64 {
                break;
            }
        }
    }

    let is_playing = state.playing.load(Ordering::Relaxed);

    if !is_playing {
        // Output silence
        data.fill(0.0);
        // Decay meters
        let peak_l = meters.get_peak_l() * decay;
        let peak_r = meters.get_peak_r() * decay;
        meters.set_peak(peak_l, peak_r);
        return;
    }

    // Get current position
    let pos = state.position_samples.load(Ordering::Relaxed);

    // Check loop
    let loop_enabled = state.loop_enabled.load(Ordering::Relaxed);
    let loop_start = state.loop_start_samples.load(Ordering::Relaxed);
    let loop_end = state.loop_end_samples.load(Ordering::Relaxed);

    // Clear output buffers
    engine_output_l[..frames].fill(0.0);
    engine_output_r[..frames].fill(0.0);

    if use_engine {
        // Full DAW mode - use rf-engine PlaybackEngine
        if let Some(engine) = engine {
            engine.process(
                &mut engine_output_l[..frames],
                &mut engine_output_r[..frames],
            );
        }
    } else {
        // Simple mode - direct clip playback
        let has_clips = simple_clips
            .try_read()
            .map(|c| !c.is_empty())
            .unwrap_or(false);

        if has_clips {
            if let Some(clips_guard) = simple_clips.try_read() {
                for i in 0..frames {
                    let current_pos = pos + i as u64;

                    // Handle loop
                    let actual_pos =
                        if loop_enabled && loop_end > loop_start && current_pos >= loop_end {
                            loop_start + ((current_pos - loop_start) % (loop_end - loop_start))
                        } else {
                            current_pos
                        };

                    for clip in clips_guard.iter() {
                        if clip.muted {
                            continue;
                        }

                        if actual_pos >= clip.start_sample {
                            let clip_pos = (actual_pos - clip.start_sample) as usize;
                            if clip_pos < clip.samples_l.len() {
                                engine_output_l[i] +=
                                    clip.samples_l[clip_pos] as f64 * clip.gain as f64;
                                engine_output_r[i] +=
                                    clip.samples_r[clip_pos] as f64 * clip.gain as f64;
                            }
                        }
                    }
                }
            }
        } else {
            // No clips loaded - generate 440Hz test tone for debugging
            // This helps verify audio output is working
            let sample_rate = state.sample_rate();
            for i in 0..frames {
                let t = (pos + i as u64) as f64 / sample_rate;
                let tone = (2.0 * std::f64::consts::PI * 440.0 * t).sin() * 0.3;
                engine_output_l[i] = tone;
                engine_output_r[i] = tone;
            }
        }
    }

    // Apply master track DSP processing (track_id = 0 is master)
    if let Some(master_dsp) = dsp_storage.get(0) {
        master_dsp.process(
            &mut engine_output_l[..frames],
            &mut engine_output_r[..frames],
        );
    }

    // Get master volume (atomic read, linear)
    let master_vol = f64::from_bits(master_volume.load(Ordering::Relaxed)) as f32;

    // Calculate metering and write to output
    let mut peak_l = meters.get_peak_l() * decay;
    let mut peak_r = meters.get_peak_r() * decay;
    let mut sum_sq_l = 0.0f32;
    let mut sum_sq_r = 0.0f32;

    for i in 0..frames {
        // Apply master volume BEFORE output and metering
        let out_l = engine_output_l[i] as f32 * master_vol;
        let out_r = engine_output_r[i] as f32 * master_vol;

        // Write to output buffer
        let idx = i * channels;
        if channels >= 2 {
            data[idx] = out_l;
            data[idx + 1] = out_r;
        } else if channels == 1 {
            data[idx] = (out_l + out_r) * 0.5;
        }

        // Metering (reflects volume-adjusted signal)
        let abs_l = out_l.abs();
        let abs_r = out_r.abs();
        peak_l = peak_l.max(abs_l);
        peak_r = peak_r.max(abs_r);
        sum_sq_l += out_l * out_l;
        sum_sq_r += out_r * out_r;

        // Clip detection
        if abs_l > 1.0 || abs_r > 1.0 {
            meters.clipped.store(true, Ordering::Relaxed);
        }
    }

    // Update position
    let new_pos = pos + frames as u64;
    let final_pos = if loop_enabled && loop_end > loop_start && new_pos >= loop_end {
        loop_start + ((new_pos - loop_start) % (loop_end - loop_start))
    } else {
        new_pos
    };
    state.position_samples.store(final_pos, Ordering::Relaxed);

    // Update meters
    meters.set_peak(peak_l, peak_r);
    let rms_l = (sum_sq_l / frames as f32).sqrt();
    let rms_r = (sum_sq_r / frames as f32).sqrt();
    meters.set_rms(rms_l, rms_r);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_playback_state() {
        let state = PlaybackState::new(48000.0);

        assert!(!state.playing.load(Ordering::Relaxed));
        assert_eq!(state.sample_rate(), 48000.0);

        state.set_position_seconds(1.0);
        assert_eq!(state.position_samples.load(Ordering::Relaxed), 48000);
    }

    #[test]
    fn test_playback_meters() {
        let meters = PlaybackMeters::new();

        meters.set_peak(0.5, 0.7);
        assert!((meters.get_peak_l() - 0.5).abs() < 0.001);
        assert!((meters.get_peak_r() - 0.7).abs() < 0.001);
    }

    #[test]
    fn test_bus_meters() {
        let meters = PlaybackMeters::new();

        meters.set_bus_peak(0, 0.3, 0.4);
        let (l, r) = meters.get_bus_peak(0);
        assert!((l - 0.3).abs() < 0.001);
        assert!((r - 0.4).abs() < 0.001);
    }

    #[test]
    fn test_engine_creation() {
        let engine = PlaybackEngine::new();

        assert!(!engine.is_running());
        assert!(!engine.is_playing());
        assert!(!engine.is_engine_mode());
    }
}
