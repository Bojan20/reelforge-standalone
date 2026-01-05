//! Playback Engine - Real-time Audio Streaming from Timeline
//!
//! Provides:
//! - Sample-accurate playback from clips
//! - Multi-track mixing with volume/pan through bus system
//! - Loop region support
//! - Fade in/out and crossfade processing
//! - Lock-free communication with audio thread
//! - Bus routing (tracks → buses → master)

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::path::Path;

use parking_lot::RwLock;

use crate::track_manager::{TrackManager, Clip, Track, OutputBus};
use crate::audio_import::{AudioImporter, ImportedAudio};

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO CACHE
// ═══════════════════════════════════════════════════════════════════════════

/// Cache for loaded audio files
pub struct AudioCache {
    /// Map from file path to loaded audio data
    files: RwLock<HashMap<String, Arc<ImportedAudio>>>,
}

impl AudioCache {
    pub fn new() -> Self {
        Self {
            files: RwLock::new(HashMap::new()),
        }
    }

    /// Load audio file into cache (or return cached version)
    pub fn load(&self, path: &str) -> Option<Arc<ImportedAudio>> {
        // Check if already cached
        if let Some(audio) = self.files.read().get(path) {
            return Some(Arc::clone(audio));
        }

        // Load from disk
        match AudioImporter::import(Path::new(path)) {
            Ok(audio) => {
                let arc = Arc::new(audio);
                self.files.write().insert(path.to_string(), Arc::clone(&arc));
                Some(arc)
            }
            Err(e) => {
                log::error!("Failed to load audio file '{}': {}", path, e);
                None
            }
        }
    }

    /// Check if file is cached
    pub fn is_cached(&self, path: &str) -> bool {
        self.files.read().contains_key(path)
    }

    /// Get cached audio (without loading)
    pub fn get(&self, path: &str) -> Option<Arc<ImportedAudio>> {
        self.files.read().get(path).cloned()
    }

    /// Remove file from cache
    pub fn unload(&self, path: &str) {
        self.files.write().remove(path);
    }

    /// Clear entire cache
    pub fn clear(&self) {
        self.files.write().clear();
    }

    /// Get cache size (number of files)
    pub fn size(&self) -> usize {
        self.files.read().len()
    }

    /// Get total memory usage (approximate)
    pub fn memory_usage(&self) -> usize {
        self.files.read()
            .values()
            .map(|a| a.samples.len() * std::mem::size_of::<f32>())
            .sum()
    }
}

impl Default for AudioCache {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLAYBACK STATE (lock-free communication)
// ═══════════════════════════════════════════════════════════════════════════

/// Transport state for playback
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PlaybackState {
    Stopped = 0,
    Playing = 1,
    Paused = 2,
}

impl From<u8> for PlaybackState {
    fn from(value: u8) -> Self {
        match value {
            1 => Self::Playing,
            2 => Self::Paused,
            _ => Self::Stopped,
        }
    }
}

/// Atomic playback position and state
pub struct PlaybackPosition {
    /// Current position in samples
    sample_position: AtomicU64,
    /// Sample rate
    sample_rate: AtomicU64,
    /// Playback state
    state: std::sync::atomic::AtomicU8,
    /// Loop enabled
    loop_enabled: AtomicBool,
    /// Loop start (samples)
    loop_start: AtomicU64,
    /// Loop end (samples)
    loop_end: AtomicU64,
}

impl PlaybackPosition {
    pub fn new(sample_rate: u32) -> Self {
        Self {
            sample_position: AtomicU64::new(0),
            sample_rate: AtomicU64::new(sample_rate as u64),
            state: std::sync::atomic::AtomicU8::new(PlaybackState::Stopped as u8),
            loop_enabled: AtomicBool::new(false),
            loop_start: AtomicU64::new(0),
            loop_end: AtomicU64::new(0),
        }
    }

    #[inline]
    pub fn samples(&self) -> u64 {
        self.sample_position.load(Ordering::Relaxed)
    }

    #[inline]
    pub fn seconds(&self) -> f64 {
        let samples = self.samples();
        let rate = self.sample_rate.load(Ordering::Relaxed);
        samples as f64 / rate as f64
    }

    #[inline]
    pub fn set_samples(&self, samples: u64) {
        self.sample_position.store(samples, Ordering::Relaxed);
    }

    #[inline]
    pub fn set_seconds(&self, seconds: f64) {
        let rate = self.sample_rate.load(Ordering::Relaxed);
        let samples = (seconds * rate as f64) as u64;
        self.sample_position.store(samples, Ordering::Relaxed);
    }

    /// Advance position by given samples, handling loop
    #[inline]
    pub fn advance(&self, frames: u64) -> u64 {
        let current = self.sample_position.load(Ordering::Relaxed);
        let mut new_pos = current + frames;

        // Handle loop
        if self.loop_enabled.load(Ordering::Relaxed) {
            let loop_end = self.loop_end.load(Ordering::Relaxed);
            let loop_start = self.loop_start.load(Ordering::Relaxed);

            if new_pos >= loop_end && loop_end > loop_start {
                let loop_len = loop_end - loop_start;
                new_pos = loop_start + ((new_pos - loop_start) % loop_len);
            }
        }

        self.sample_position.store(new_pos, Ordering::Relaxed);
        new_pos
    }

    #[inline]
    pub fn state(&self) -> PlaybackState {
        PlaybackState::from(self.state.load(Ordering::Relaxed))
    }

    #[inline]
    pub fn set_state(&self, state: PlaybackState) {
        self.state.store(state as u8, Ordering::Relaxed);
    }

    #[inline]
    pub fn is_playing(&self) -> bool {
        self.state() == PlaybackState::Playing
    }

    pub fn set_loop(&self, start_secs: f64, end_secs: f64, enabled: bool) {
        let rate = self.sample_rate.load(Ordering::Relaxed);
        self.loop_start.store((start_secs * rate as f64) as u64, Ordering::Relaxed);
        self.loop_end.store((end_secs * rate as f64) as u64, Ordering::Relaxed);
        self.loop_enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate.load(Ordering::Relaxed) as u32
    }
}

impl Default for PlaybackPosition {
    fn default() -> Self {
        Self::new(48000)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLAYBACK ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// Bus buffers for routing audio
pub struct BusBuffers {
    /// Per-bus stereo buffers [bus_id][left/right][sample]
    buffers: Vec<(Vec<f64>, Vec<f64>)>,
    /// Master output
    master_l: Vec<f64>,
    master_r: Vec<f64>,
    /// Block size
    block_size: usize,
}

impl BusBuffers {
    pub fn new(block_size: usize) -> Self {
        // 6 buses + master
        let buffers = (0..6)
            .map(|_| (vec![0.0; block_size], vec![0.0; block_size]))
            .collect();

        Self {
            buffers,
            master_l: vec![0.0; block_size],
            master_r: vec![0.0; block_size],
            block_size,
        }
    }

    pub fn clear(&mut self) {
        for (l, r) in &mut self.buffers {
            l.fill(0.0);
            r.fill(0.0);
        }
        self.master_l.fill(0.0);
        self.master_r.fill(0.0);
    }

    pub fn add_to_bus(&mut self, bus: OutputBus, left: &[f64], right: &[f64]) {
        let idx = match bus {
            OutputBus::Master => 0,  // Routes directly to master
            OutputBus::Music => 1,
            OutputBus::Sfx => 2,
            OutputBus::Voice => 3,
            OutputBus::Ambience => 4,
            OutputBus::Aux => 5,
        };

        if idx < self.buffers.len() {
            let (bus_l, bus_r) = &mut self.buffers[idx];
            for i in 0..left.len().min(bus_l.len()) {
                bus_l[i] += left[i];
                bus_r[i] += right[i];
            }
        }
    }

    pub fn get_bus(&self, bus: OutputBus) -> (&[f64], &[f64]) {
        let idx = match bus {
            OutputBus::Master => 0,
            OutputBus::Music => 1,
            OutputBus::Sfx => 2,
            OutputBus::Voice => 3,
            OutputBus::Ambience => 4,
            OutputBus::Aux => 5,
        };

        if idx < self.buffers.len() {
            (&self.buffers[idx].0, &self.buffers[idx].1)
        } else {
            (&self.master_l, &self.master_r)
        }
    }

    pub fn sum_to_master(&mut self) {
        for (bus_l, bus_r) in &self.buffers {
            for i in 0..self.block_size {
                self.master_l[i] += bus_l[i];
                self.master_r[i] += bus_r[i];
            }
        }
    }

    pub fn master(&self) -> (&[f64], &[f64]) {
        (&self.master_l, &self.master_r)
    }

    pub fn master_mut(&mut self) -> (&mut [f64], &mut [f64]) {
        (&mut self.master_l, &mut self.master_r)
    }
}

/// Bus volume/mute/solo state
#[derive(Debug, Clone)]
pub struct BusState {
    pub volume: f64,
    pub pan: f64,
    pub muted: bool,
    pub soloed: bool,
}

impl Default for BusState {
    fn default() -> Self {
        Self {
            volume: 1.0,
            pan: 0.0,
            muted: false,
            soloed: false,
        }
    }
}

/// Main playback engine for timeline audio
pub struct PlaybackEngine {
    /// Track manager reference
    track_manager: Arc<TrackManager>,
    /// Audio file cache
    cache: Arc<AudioCache>,
    /// Playback position (shared with audio thread)
    pub position: Arc<PlaybackPosition>,
    /// Master volume (0.0 to 1.5)
    master_volume: AtomicU64,
    /// Bus buffers for audio routing
    bus_buffers: RwLock<BusBuffers>,
    /// Bus states (volume, pan, mute, solo)
    bus_states: RwLock<[BusState; 6]>,
    /// Any bus soloed flag
    any_solo: AtomicBool,
    /// Peak meters L/R (atomic for lock-free access)
    pub peak_l: AtomicU64,
    pub peak_r: AtomicU64,
    /// RMS meters L/R
    pub rms_l: AtomicU64,
    pub rms_r: AtomicU64,
}

impl PlaybackEngine {
    pub fn new(track_manager: Arc<TrackManager>, sample_rate: u32) -> Self {
        Self {
            track_manager,
            cache: Arc::new(AudioCache::new()),
            position: Arc::new(PlaybackPosition::new(sample_rate)),
            master_volume: AtomicU64::new(1.0_f64.to_bits()),
            bus_buffers: RwLock::new(BusBuffers::new(256)),
            bus_states: RwLock::new(std::array::from_fn(|_| BusState::default())),
            any_solo: AtomicBool::new(false),
            peak_l: AtomicU64::new(0.0_f64.to_bits()),
            peak_r: AtomicU64::new(0.0_f64.to_bits()),
            rms_l: AtomicU64::new(0.0_f64.to_bits()),
            rms_r: AtomicU64::new(0.0_f64.to_bits()),
        }
    }

    /// Get peak meter values (left, right) as linear amplitude
    pub fn get_peaks(&self) -> (f64, f64) {
        (
            f64::from_bits(self.peak_l.load(Ordering::Relaxed)),
            f64::from_bits(self.peak_r.load(Ordering::Relaxed)),
        )
    }

    /// Get RMS meter values (left, right) as linear amplitude
    pub fn get_rms(&self) -> (f64, f64) {
        (
            f64::from_bits(self.rms_l.load(Ordering::Relaxed)),
            f64::from_bits(self.rms_r.load(Ordering::Relaxed)),
        )
    }

    /// Get audio cache
    pub fn cache(&self) -> &Arc<AudioCache> {
        &self.cache
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRANSPORT CONTROLS
    // ═══════════════════════════════════════════════════════════════════════

    pub fn play(&self) {
        self.position.set_state(PlaybackState::Playing);
    }

    pub fn pause(&self) {
        self.position.set_state(PlaybackState::Paused);
    }

    pub fn stop(&self) {
        self.position.set_state(PlaybackState::Stopped);
        self.position.set_samples(0);
    }

    pub fn seek(&self, seconds: f64) {
        self.position.set_seconds(seconds.max(0.0));
    }

    pub fn seek_samples(&self, samples: u64) {
        self.position.set_samples(samples);
    }

    pub fn set_master_volume(&self, volume: f64) {
        self.master_volume.store(volume.clamp(0.0, 1.5).to_bits(), Ordering::Relaxed);
    }

    pub fn master_volume(&self) -> f64 {
        f64::from_bits(self.master_volume.load(Ordering::Relaxed))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUS CONTROLS
    // ═══════════════════════════════════════════════════════════════════════

    /// Set bus volume (0.0 to 1.5)
    pub fn set_bus_volume(&self, bus_idx: usize, volume: f64) {
        if let Some(state) = self.bus_states.write().get_mut(bus_idx) {
            state.volume = volume.clamp(0.0, 1.5);
        }
    }

    /// Set bus pan (-1.0 to 1.0)
    pub fn set_bus_pan(&self, bus_idx: usize, pan: f64) {
        if let Some(state) = self.bus_states.write().get_mut(bus_idx) {
            state.pan = pan.clamp(-1.0, 1.0);
        }
    }

    /// Set bus mute state
    pub fn set_bus_mute(&self, bus_idx: usize, muted: bool) {
        if let Some(state) = self.bus_states.write().get_mut(bus_idx) {
            state.muted = muted;
        }
    }

    /// Set bus solo state
    pub fn set_bus_solo(&self, bus_idx: usize, soloed: bool) {
        {
            if let Some(state) = self.bus_states.write().get_mut(bus_idx) {
                state.soloed = soloed;
            }
        }
        // Update any_solo flag
        let any = self.bus_states.read().iter().any(|s| s.soloed);
        self.any_solo.store(any, Ordering::Relaxed);
    }

    /// Get bus state
    pub fn get_bus_state(&self, bus_idx: usize) -> Option<BusState> {
        self.bus_states.read().get(bus_idx).cloned()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO PROCESSING (called from audio thread)
    // ═══════════════════════════════════════════════════════════════════════

    /// Process audio block - called from audio callback
    ///
    /// Audio flow: Clips → Tracks → Buses → Master
    /// MUST be real-time safe: no allocations, no locks (except try_read)
    #[inline]
    pub fn process(&self, output_l: &mut [f64], output_r: &mut [f64]) {
        let frames = output_l.len();

        // Clear output buffers
        output_l.fill(0.0);
        output_r.fill(0.0);

        // Check if playing
        if !self.position.is_playing() {
            return;
        }

        let sample_rate = self.position.sample_rate() as f64;
        let start_sample = self.position.samples();
        let start_time = start_sample as f64 / sample_rate;
        let end_time = (start_sample + frames as u64) as f64 / sample_rate;

        // Get bus buffers (try lock)
        let mut bus_buffers = match self.bus_buffers.try_write() {
            Some(b) => b,
            None => return,
        };

        // Ensure buffer size matches
        if bus_buffers.block_size != frames {
            *bus_buffers = BusBuffers::new(frames);
        }

        // Clear bus buffers
        bus_buffers.clear();

        // Get tracks (try to read, skip if locked)
        let tracks = match self.track_manager.tracks.try_read() {
            Some(t) => t,
            None => return,
        };

        let clips = match self.track_manager.clips.try_read() {
            Some(c) => c,
            None => return,
        };

        // Temporary track output buffer
        let mut track_l = vec![0.0f64; frames];
        let mut track_r = vec![0.0f64; frames];

        // Process each track → route to its bus
        for track in tracks.values() {
            if track.muted {
                continue;
            }

            // Clear track buffers
            track_l.fill(0.0);
            track_r.fill(0.0);

            // Get clips for this track that overlap with current time range
            for clip in clips.values() {
                if clip.track_id != track.id || clip.muted {
                    continue;
                }

                // Check if clip overlaps with current block
                if !clip.overlaps(start_time, end_time) {
                    continue;
                }

                // Get cached audio
                let audio = match self.cache.get(&clip.source_file) {
                    Some(a) => a,
                    None => continue,
                };

                // Process clip samples into track buffer
                self.process_clip(
                    clip,
                    track,
                    &audio,
                    start_sample,
                    sample_rate,
                    &mut track_l,
                    &mut track_r,
                );
            }

            // Route track to its output bus
            bus_buffers.add_to_bus(track.output_bus, &track_l, &track_r);
        }

        // Process buses → sum to master
        let bus_states = self.bus_states.read();
        let any_solo = self.any_solo.load(Ordering::Relaxed);

        for (bus_idx, state) in bus_states.iter().enumerate() {
            // Skip if muted, or if solo is active and this bus isn't soloed
            if state.muted || (any_solo && !state.soloed) {
                continue;
            }

            let bus = match bus_idx {
                0 => OutputBus::Master,
                1 => OutputBus::Music,
                2 => OutputBus::Sfx,
                3 => OutputBus::Voice,
                4 => OutputBus::Ambience,
                5 => OutputBus::Aux,
                _ => continue,
            };

            let (bus_l, bus_r) = bus_buffers.get_bus(bus);

            // Apply bus volume and pan
            let volume = state.volume;
            let pan = state.pan;
            let pan_l = ((1.0 - pan) * std::f64::consts::FRAC_PI_4).cos();
            let pan_r = ((1.0 + pan) * std::f64::consts::FRAC_PI_4).cos();

            for i in 0..frames {
                output_l[i] += bus_l[i] * volume * pan_l;
                output_r[i] += bus_r[i] * volume * pan_r;
            }
        }

        // Apply master volume
        let master = self.master_volume();
        for i in 0..frames {
            output_l[i] *= master;
            output_r[i] *= master;
        }

        // Calculate metering (after volume is applied)
        // Peak with decay (60dB in ~300ms at 48kHz, 256 block size)
        let decay = 0.9995_f64.powf(frames as f64 / 8.0);
        let prev_peak_l = f64::from_bits(self.peak_l.load(Ordering::Relaxed));
        let prev_peak_r = f64::from_bits(self.peak_r.load(Ordering::Relaxed));

        let mut peak_l = prev_peak_l * decay;
        let mut peak_r = prev_peak_r * decay;
        let mut sum_sq_l = 0.0;
        let mut sum_sq_r = 0.0;

        for i in 0..frames {
            let abs_l = output_l[i].abs();
            let abs_r = output_r[i].abs();
            peak_l = peak_l.max(abs_l);
            peak_r = peak_r.max(abs_r);
            sum_sq_l += output_l[i] * output_l[i];
            sum_sq_r += output_r[i] * output_r[i];
        }

        // Store peaks
        self.peak_l.store(peak_l.to_bits(), Ordering::Relaxed);
        self.peak_r.store(peak_r.to_bits(), Ordering::Relaxed);

        // RMS
        let rms_l = (sum_sq_l / frames as f64).sqrt();
        let rms_r = (sum_sq_r / frames as f64).sqrt();
        self.rms_l.store(rms_l.to_bits(), Ordering::Relaxed);
        self.rms_r.store(rms_r.to_bits(), Ordering::Relaxed);

        // Advance position
        self.position.advance(frames as u64);
    }

    /// Process a single clip into output buffers
    #[inline]
    fn process_clip(
        &self,
        clip: &Clip,
        track: &Track,
        audio: &ImportedAudio,
        start_sample: u64,
        sample_rate: f64,
        output_l: &mut [f64],
        output_r: &mut [f64],
    ) {
        let frames = output_l.len();
        let clip_start_sample = (clip.start_time * sample_rate) as i64;
        let source_sample_rate = audio.sample_rate as f64;
        let rate_ratio = source_sample_rate / sample_rate;

        // Combined gain: clip gain * track volume
        let gain = clip.gain * track.volume;

        // Pan calculation (constant power)
        let pan = track.pan.clamp(-1.0, 1.0);
        let pan_l = ((1.0 - pan) * std::f64::consts::FRAC_PI_4).cos();
        let pan_r = ((1.0 + pan) * std::f64::consts::FRAC_PI_4).cos();

        // Fade parameters
        let fade_in_samples = (clip.fade_in * sample_rate) as i64;
        let fade_out_samples = (clip.fade_out * sample_rate) as i64;
        let clip_duration_samples = (clip.duration * sample_rate) as i64;

        for i in 0..frames {
            let playback_sample = start_sample as i64 + i as i64;
            let clip_relative_sample = playback_sample - clip_start_sample;

            // Check if within clip bounds
            if clip_relative_sample < 0 || clip_relative_sample >= clip_duration_samples {
                continue;
            }

            // Calculate source position (with offset and rate conversion)
            let source_offset_samples = (clip.source_offset * source_sample_rate) as i64;
            let source_sample = ((clip_relative_sample as f64 * rate_ratio) as i64 + source_offset_samples) as usize;

            // Get sample from audio buffer
            let (sample_l, sample_r) = if audio.channels == 1 {
                // Mono
                let s = audio.samples.get(source_sample).copied().unwrap_or(0.0) as f64;
                (s, s)
            } else {
                // Stereo (interleaved)
                let idx = source_sample * 2;
                let l = audio.samples.get(idx).copied().unwrap_or(0.0) as f64;
                let r = audio.samples.get(idx + 1).copied().unwrap_or(0.0) as f64;
                (l, r)
            };

            // Calculate fade envelope
            let mut fade = 1.0;

            // Fade in
            if clip_relative_sample < fade_in_samples && fade_in_samples > 0 {
                fade = clip_relative_sample as f64 / fade_in_samples as f64;
                fade = fade * fade; // Quadratic curve
            }

            // Fade out
            let samples_from_end = clip_duration_samples - clip_relative_sample;
            if samples_from_end < fade_out_samples && fade_out_samples > 0 {
                let fade_out = samples_from_end as f64 / fade_out_samples as f64;
                fade *= fade_out * fade_out;
            }

            // Apply gain, pan, and fade
            let final_gain = gain * fade;
            output_l[i] += sample_l * final_gain * pan_l;
            output_r[i] += sample_r * final_gain * pan_r;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UTILITIES
    // ═══════════════════════════════════════════════════════════════════════

    /// Preload audio for all clips (call before playback)
    pub fn preload_all(&self) {
        let clips = self.track_manager.get_all_clips();
        for clip in clips {
            self.cache.load(&clip.source_file);
        }
    }

    /// Preload audio for clips in time range
    pub fn preload_range(&self, start_time: f64, end_time: f64) {
        let clips = self.track_manager.get_all_clips();
        for clip in clips {
            if clip.overlaps(start_time, end_time) {
                self.cache.load(&clip.source_file);
            }
        }
    }

    /// Get current playback time in seconds
    pub fn current_time(&self) -> f64 {
        self.position.seconds()
    }

    /// Get playback state
    pub fn state(&self) -> PlaybackState {
        self.position.state()
    }

    /// Check if playing
    pub fn is_playing(&self) -> bool {
        self.position.is_playing()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_playback_position() {
        let pos = PlaybackPosition::new(48000);

        assert_eq!(pos.samples(), 0);
        assert_eq!(pos.state(), PlaybackState::Stopped);

        pos.set_state(PlaybackState::Playing);
        pos.advance(48000);

        assert_eq!(pos.samples(), 48000);
        assert!((pos.seconds() - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_playback_loop() {
        let pos = PlaybackPosition::new(48000);

        // Set loop from 1.0 to 2.0 seconds
        pos.set_loop(1.0, 2.0, true);
        pos.set_seconds(1.5);

        // Advance past loop end
        pos.advance(48000); // +1 second

        // Should wrap to somewhere in loop region
        let time = pos.seconds();
        assert!(time >= 1.0 && time < 2.0);
    }

    #[test]
    fn test_audio_cache() {
        let cache = AudioCache::new();

        assert_eq!(cache.size(), 0);
        assert!(!cache.is_cached("/nonexistent/file.wav"));
    }
}
