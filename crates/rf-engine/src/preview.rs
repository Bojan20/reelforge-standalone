//! Audio Preview Engine — Dedicated one-shot audio playback
//!
//! Separate from main PlaybackEngine, designed for:
//! - Slot Lab layer preview
//! - Audio browser hover preview
//! - Sound effect auditioning
//!
//! Features:
//! - Zero impact on main timeline playback
//! - Dedicated audio thread for preview
//! - Lock-free audio callback (no allocations, no locks)
//! - Simple play/stop API
//! - Volume control
//! - Automatic cleanup on stop

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::thread;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use parking_lot::Mutex;
use rtrb::{Consumer, Producer, RingBuffer};

use crate::audio_import::{AudioImporter, ImportedAudio};

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum concurrent voices (pre-allocated)
const MAX_VOICES: usize = 16;

/// Maximum buffer size for temp mixing (pre-allocated)
const MAX_BUFFER_SIZE: usize = 8192;

/// Command ring buffer size
const COMMAND_BUFFER_SIZE: usize = 64;

// ═══════════════════════════════════════════════════════════════════════════
// COMMANDS (Lock-free UI -> Audio communication)
// ═══════════════════════════════════════════════════════════════════════════

enum PreviewCommand {
    /// Add a new voice to play
    AddVoice {
        audio: Arc<ImportedAudio>,
        volume: f32,
        voice_id: u64,
    },
    /// Stop specific voice
    StopVoice { voice_id: u64 },
    /// Stop all voices
    StopAll,
    /// Set master volume
    SetVolume { volume: f32 },
}

// ═══════════════════════════════════════════════════════════════════════════
// PREVIEW VOICE — Single playing audio (RT-safe)
// ═══════════════════════════════════════════════════════════════════════════

/// Anti-click fade ramp length in frames (~10ms @ 48kHz)
const PREVIEW_FADE_FRAMES: u64 = 480;

// ═══════════════════════════════════════════════════════════════════════════
// LANCZOS-3 SINC INTERPOLATION (duplicated from playback.rs for isolation)
// 6-tap windowed sinc, ~-90dB noise floor, zero-allocation, audio-thread safe
// ═══════════════════════════════════════════════════════════════════════════

#[inline]
fn lanczos3(x: f64) -> f64 {
    if x.abs() < 1e-10 {
        return 1.0;
    }
    if x.abs() >= 3.0 {
        return 0.0;
    }
    let pi_x = std::f64::consts::PI * x;
    let pi_x_3 = pi_x / 3.0;
    (pi_x.sin() * pi_x_3.sin()) / (pi_x * pi_x_3)
}

#[inline]
fn lanczos3_sample(
    src_pos: f64,
    samples: &[f32],
    channels: usize,
    total_frames: usize,
    ch: usize,
) -> f32 {
    let idx_floor = src_pos.floor() as i64;
    let frac = src_pos - idx_floor as f64;

    // Fast path: exact position → no interpolation needed
    if frac.abs() < 1e-10 {
        let i = idx_floor as usize;
        if i < total_frames {
            return samples[i * channels + ch];
        }
        return 0.0;
    }

    let mut sum = 0.0_f64;
    let mut weight_sum = 0.0_f64;

    // Lanczos-3: 6 taps (k = -2..=3)
    for k in -2i64..=3 {
        let sample_idx = idx_floor + k;
        if sample_idx < 0 || sample_idx >= total_frames as i64 {
            continue;
        }
        let x = frac - k as f64;
        let w = lanczos3(x);
        let buf_idx = sample_idx as usize * channels + ch;
        sum += samples[buf_idx] as f64 * w;
        weight_sum += w;
    }

    if weight_sum > 0.0 {
        (sum / weight_sum) as f32
    } else {
        0.0
    }
}

struct PreviewVoice {
    /// Audio data (interleaved stereo f32)
    audio: Arc<ImportedAudio>,
    /// Fractional playback position in source frames (for SRC)
    src_position: f64,
    /// SRC rate ratio: source_sr / engine_sr (e.g., 44100/48000 = 0.91875)
    rate_ratio: f64,
    /// Volume multiplier (0.0 to 1.0)
    volume: f32,
    /// Voice ID for tracking
    id: u64,
    /// Is this voice active
    active: bool,
    /// Fade-in: frames remaining in fade-in ramp
    fade_in_remaining: u64,
    /// Fade-out: true when fading out
    fading_out: bool,
    /// Fade-out: frames remaining
    fade_out_remaining: u64,
}

impl PreviewVoice {
    fn new_inactive() -> Self {
        Self {
            audio: Arc::new(ImportedAudio {
                samples: Vec::new(),
                sample_rate: 44100,
                channels: 2,
                duration_secs: 0.0,
                sample_count: 0,
                source_path: String::new(),
                name: String::new(),
                bit_depth: None,
                format: String::new(),
            }),
            src_position: 0.0,
            rate_ratio: 1.0,
            volume: 1.0,
            id: 0,
            active: false,
            fade_in_remaining: 0,
            fading_out: false,
            fade_out_remaining: 0,
        }
    }

    fn activate(&mut self, audio: Arc<ImportedAudio>, volume: f32, id: u64, engine_sr: u32) {
        // SRC ratio: how many source frames per output frame
        self.rate_ratio = audio.sample_rate as f64 / engine_sr as f64;
        self.audio = audio;
        self.src_position = 0.0;
        self.volume = volume;
        self.id = id;
        self.active = true;
        // Anti-click: 10ms fade-in
        self.fade_in_remaining = PREVIEW_FADE_FRAMES;
        self.fading_out = false;
        self.fade_out_remaining = 0;
    }

    fn deactivate(&mut self) {
        self.active = false;
        self.src_position = 0.0;
        self.fading_out = false;
        self.fade_out_remaining = 0;
        self.fade_in_remaining = 0;
    }

    /// Start a fade-out (anti-click stop)
    fn start_fade_out(&mut self) {
        if self.active && !self.fading_out {
            self.fading_out = true;
            self.fade_out_remaining = PREVIEW_FADE_FRAMES;
        }
    }

    /// Fill buffer with audio using Lanczos-3 SRC, returns true if still playing
    #[inline]
    fn fill_buffer(&mut self, output: &mut [f32], channels: usize) -> bool {
        if !self.active {
            return false;
        }

        let frames_needed = output.len() / channels;
        let channels_src = self.audio.channels as usize;
        let total_frames = self.audio.samples.len() / channels_src;

        if self.src_position >= total_frames as f64 {
            self.active = false;
            return false;
        }

        for frame in 0..frames_needed {
            // SRC: fractional source position advances by rate_ratio per output frame
            let src_pos = self.src_position + (frame as f64 * self.rate_ratio);
            let src_frame = src_pos.floor() as usize;

            if src_frame >= total_frames {
                // Fill remaining with silence
                for ch in 0..channels {
                    output[frame * channels + ch] = 0.0;
                }
                continue;
            }

            // Calculate fade envelope
            let mut fade: f32 = 1.0;

            // Fade-in ramp
            if self.fade_in_remaining > 0 {
                let elapsed = PREVIEW_FADE_FRAMES - self.fade_in_remaining;
                fade = elapsed as f32 / PREVIEW_FADE_FRAMES as f32;
                self.fade_in_remaining -= 1;
            }

            // Natural end-of-file fade-out (last 480 source frames)
            let source_frames_until_end = total_frames as f64 - src_pos;
            if source_frames_until_end < PREVIEW_FADE_FRAMES as f64 && !self.fading_out {
                fade *= (source_frames_until_end / PREVIEW_FADE_FRAMES as f64) as f32;
            }

            // Fade-out ramp (overrides fade-in if both active)
            if self.fading_out {
                if self.fade_out_remaining > 0 {
                    fade = self.fade_out_remaining as f32 / PREVIEW_FADE_FRAMES as f32;
                    self.fade_out_remaining -= 1;
                } else {
                    // Fade-out complete — deactivate cleanly
                    self.active = false;
                    // Zero remaining output
                    for remaining_frame in frame..frames_needed {
                        for ch in 0..channels {
                            output[remaining_frame * channels + ch] = 0.0;
                        }
                    }
                    return false;
                }
            }

            let gain = self.volume * fade;

            // Lanczos-3 sinc interpolation for sample rate conversion
            let left = lanczos3_sample(src_pos, &self.audio.samples, channels_src, total_frames, 0) * gain;
            let right = if channels_src > 1 {
                lanczos3_sample(src_pos, &self.audio.samples, channels_src, total_frames, 1) * gain
            } else {
                left // Mono to stereo
            };

            // Write to output (handle mono, stereo, or multichannel output)
            match channels {
                1 => output[frame] = (left + right) * 0.5,
                2 => {
                    output[frame * 2] = left;
                    output[frame * 2 + 1] = right;
                }
                _ => {
                    // Multichannel: put audio in first two channels
                    output[frame * channels] = left;
                    output[frame * channels + 1] = right;
                    for ch in 2..channels {
                        output[frame * channels + ch] = 0.0;
                    }
                }
            }
        }

        self.src_position += frames_needed as f64 * self.rate_ratio;
        self.src_position < total_frames as f64
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// RT STATE — Pre-allocated state for audio thread (no locks, no allocations)
// ═══════════════════════════════════════════════════════════════════════════

struct RtState {
    /// Pre-allocated voice slots
    voices: [PreviewVoice; MAX_VOICES],
    /// Pre-allocated temp buffer for mixing
    temp_buffer: [f32; MAX_BUFFER_SIZE],
    /// Master volume (atomic for lock-free access)
    master_volume: f32,
    /// Command consumer (lock-free)
    command_rx: Consumer<PreviewCommand>,
    /// Device output sample rate (for SRC calculation)
    engine_sample_rate: u32,
}

impl RtState {
    fn new(command_rx: Consumer<PreviewCommand>, sample_rate: u32) -> Self {
        Self {
            voices: std::array::from_fn(|_| PreviewVoice::new_inactive()),
            temp_buffer: [0.0; MAX_BUFFER_SIZE],
            master_volume: 1.0,
            command_rx,
            engine_sample_rate: sample_rate,
        }
    }

    /// Process pending commands (lock-free)
    #[inline]
    fn process_commands(&mut self) {
        while let Ok(cmd) = self.command_rx.pop() {
            match cmd {
                PreviewCommand::AddVoice {
                    audio,
                    volume,
                    voice_id,
                } => {
                    // Find first inactive slot
                    if let Some(voice) = self.voices.iter_mut().find(|v| !v.active) {
                        voice.activate(audio, volume, voice_id, self.engine_sample_rate);
                    }
                    // If no slot available, voice is dropped (graceful degradation)
                }
                PreviewCommand::StopVoice { voice_id } => {
                    if let Some(voice) = self
                        .voices
                        .iter_mut()
                        .find(|v| v.id == voice_id && v.active)
                    {
                        voice.start_fade_out();
                    }
                }
                PreviewCommand::StopAll => {
                    for voice in &mut self.voices {
                        if voice.active {
                            voice.start_fade_out();
                        }
                    }
                }
                PreviewCommand::SetVolume { volume } => {
                    self.master_volume = volume;
                }
            }
        }
    }

    /// Process audio callback (lock-free, no allocations)
    #[inline]
    fn process(&mut self, output: &mut [f32], channels: usize) {
        // Process any pending commands first
        self.process_commands();

        // Zero the output buffer
        for sample in output.iter_mut() {
            *sample = 0.0;
        }

        // Limit temp buffer size
        let temp_len = output.len().min(MAX_BUFFER_SIZE);

        // Mix all active voices
        for voice in &mut self.voices {
            if !voice.active {
                continue;
            }

            // Zero temp buffer (use slice, not allocation)
            for s in &mut self.temp_buffer[..temp_len] {
                *s = 0.0;
            }

            // Fill temp buffer
            let still_playing = voice.fill_buffer(&mut self.temp_buffer[..temp_len], channels);

            // Mix into output with master volume
            for (out, &src) in output.iter_mut().zip(self.temp_buffer[..temp_len].iter()) {
                *out += src * self.master_volume;
            }

            if !still_playing {
                voice.deactivate();
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PREVIEW ENGINE (UI thread interface)
// ═══════════════════════════════════════════════════════════════════════════

/// Audio Preview Engine
pub struct PreviewEngine {
    /// Command producer (lock-free send to audio thread)
    command_tx: Mutex<Option<Producer<PreviewCommand>>>,
    /// Audio cache (UI thread only, protected by Mutex)
    cache: Mutex<HashMap<String, Arc<ImportedAudio>>>,
    /// Voice ID counter
    next_voice_id: AtomicU64,
    /// Is stream running
    stream_running: AtomicBool,
    /// Stream thread handle
    stream_handle: Mutex<Option<thread::JoinHandle<()>>>,
    /// Stop signal
    stop_signal: Arc<AtomicBool>,
    /// Active voice count (approximate, for is_playing check)
    active_voice_count: AtomicU32,
}

impl PreviewEngine {
    /// Create new preview engine
    pub fn new() -> Self {
        Self {
            command_tx: Mutex::new(None),
            cache: Mutex::new(HashMap::new()),
            next_voice_id: AtomicU64::new(1),
            stream_running: AtomicBool::new(false),
            stream_handle: Mutex::new(None),
            stop_signal: Arc::new(AtomicBool::new(false)),
            active_voice_count: AtomicU32::new(0),
        }
    }

    /// Start the audio stream
    pub fn start(&self) -> Result<(), String> {
        if self.stream_running.load(Ordering::Acquire) {
            return Ok(()); // Already running
        }

        // Create command ring buffer
        let (producer, consumer) = RingBuffer::new(COMMAND_BUFFER_SIZE);
        *self.command_tx.lock() = Some(producer);

        let stop_signal = Arc::clone(&self.stop_signal);
        self.stop_signal.store(false, Ordering::Release);

        let handle = thread::spawn(move || {
            if let Err(e) = run_preview_stream(consumer, stop_signal) {
                eprintln!("[PreviewEngine] Stream error: {}", e);
            }
        });

        *self.stream_handle.lock() = Some(handle);
        self.stream_running.store(true, Ordering::Release);
        Ok(())
    }

    /// Stop the audio stream
    pub fn stop_stream(&self) {
        self.stop_signal.store(true, Ordering::Release);

        if let Some(handle) = self.stream_handle.lock().take() {
            let _ = handle.join();
        }

        *self.command_tx.lock() = None;
        self.stream_running.store(false, Ordering::Release);
    }

    /// Play audio file (returns voice ID)
    pub fn play(&self, path: &str, volume: f32) -> Result<u64, String> {
        // Ensure stream is running
        self.start()?;

        // Load audio (from cache or disk) — UI thread, OK to use Mutex
        let audio = {
            let mut cache = self.cache.lock();
            if let Some(audio) = cache.get(path) {
                Arc::clone(audio)
            } else {
                // Load from disk
                let imported = AudioImporter::import(std::path::Path::new(path))
                    .map_err(|e| format!("Failed to load audio: {}", e))?;
                let arc = Arc::new(imported);
                cache.insert(path.to_string(), Arc::clone(&arc));
                arc
            }
        };

        // Create voice ID
        let voice_id = self.next_voice_id.fetch_add(1, Ordering::Relaxed);

        // Send command to audio thread (lock-free)
        if let Some(tx) = self.command_tx.lock().as_mut() {
            let _ = tx.push(PreviewCommand::AddVoice {
                audio,
                volume,
                voice_id,
            });
            self.active_voice_count.fetch_add(1, Ordering::Relaxed);
        }

        log::debug!("[PreviewEngine] Playing {} (voice {})", path, voice_id);
        Ok(voice_id)
    }

    /// Stop specific voice
    pub fn stop_voice(&self, voice_id: u64) {
        if let Some(tx) = self.command_tx.lock().as_mut() {
            let _ = tx.push(PreviewCommand::StopVoice { voice_id });
            self.active_voice_count.fetch_sub(1, Ordering::Relaxed);
        }
    }

    /// Stop all voices
    pub fn stop_all(&self) {
        if let Some(tx) = self.command_tx.lock().as_mut() {
            let _ = tx.push(PreviewCommand::StopAll);
            self.active_voice_count.store(0, Ordering::Relaxed);
        }
    }

    /// Check if any voice is playing (approximate)
    pub fn is_playing(&self) -> bool {
        self.active_voice_count.load(Ordering::Relaxed) > 0
    }

    /// Set master volume (0.0 to 1.0)
    pub fn set_volume(&self, volume: f32) {
        if let Some(tx) = self.command_tx.lock().as_mut() {
            let _ = tx.push(PreviewCommand::SetVolume {
                volume: volume.clamp(0.0, 1.0),
            });
        }
    }

    /// Clear audio cache
    pub fn clear_cache(&self) {
        self.cache.lock().clear();
    }
}

impl Default for PreviewEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for PreviewEngine {
    fn drop(&mut self) {
        self.stop_stream();
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO STREAM THREAD (lock-free processing)
// ═══════════════════════════════════════════════════════════════════════════

fn run_preview_stream(
    command_rx: Consumer<PreviewCommand>,
    stop_signal: Arc<AtomicBool>,
) -> Result<(), String> {
    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .ok_or("No audio output device found")?;

    let config = device
        .default_output_config()
        .map_err(|e| format!("Failed to get audio config: {}", e))?;

    let channels = config.channels() as usize;
    let sample_rate = config.sample_rate().0;

    log::info!(
        "[PreviewEngine] Starting stream: {} Hz, {} channels",
        sample_rate,
        channels
    );

    // Create RT state with pre-allocated buffers and device sample rate for SRC
    let mut rt_state = RtState::new(command_rx, sample_rate);

    let stream = device
        .build_output_stream(
            &config.into(),
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                // Lock-free, allocation-free processing
                rt_state.process(data, channels);
            },
            |err| {
                eprintln!("[PreviewEngine] Stream error: {}", err);
            },
            None,
        )
        .map_err(|e| format!("Failed to build stream: {}", e))?;

    stream
        .play()
        .map_err(|e| format!("Failed to play stream: {}", e))?;

    // Wait for stop signal
    while !stop_signal.load(Ordering::Acquire) {
        thread::sleep(std::time::Duration::from_millis(50));
    }

    drop(stream);

    log::info!("[PreviewEngine] Stream stopped");
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL SINGLETON
// ═══════════════════════════════════════════════════════════════════════════

use std::sync::LazyLock;

/// Global preview engine instance
pub static PREVIEW_ENGINE: LazyLock<PreviewEngine> = LazyLock::new(|| PreviewEngine::new());

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preview_engine_creation() {
        let engine = PreviewEngine::new();
        assert!(!engine.stream_running.load(Ordering::Relaxed));
        assert!(!engine.is_playing());
    }

    #[test]
    fn test_voice_slot_allocation() {
        let (_, rx) = RingBuffer::new(8);
        let mut rt = RtState::new(rx);

        // All voices start inactive
        assert!(rt.voices.iter().all(|v| !v.active));
    }
}
