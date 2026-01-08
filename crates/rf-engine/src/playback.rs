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
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

use parking_lot::RwLock;

use crate::audio_import::{AudioImporter, ImportedAudio};
use crate::automation::{AutomationEngine, ParamId};
use crate::groups::{GroupManager, VcaId};
use crate::insert_chain::InsertChain;
use crate::track_manager::{
    Clip, ClipFxChain, ClipFxSlot, ClipFxType, Crossfade, OutputBus, Track, TrackId, TrackManager,
};

use rf_dsp::analysis::FftAnalyzer;
use rf_dsp::delay_compensation::DelayCompensationManager;
use rf_dsp::metering::{LufsMeter, TruePeakMeter};

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO CACHE WITH LRU EVICTION
// ═══════════════════════════════════════════════════════════════════════════

/// Default maximum cache size (512MB)
pub const DEFAULT_CACHE_MAX_BYTES: usize = 512 * 1024 * 1024;

/// Minimum files to keep in cache regardless of size
pub const MIN_CACHE_FILES: usize = 4;

/// Cached audio entry with LRU tracking
struct CacheEntry {
    /// The audio data
    audio: Arc<ImportedAudio>,
    /// Last access time (monotonic counter)
    last_access: u64,
    /// Size in bytes
    size_bytes: usize,
}

/// Cache for loaded audio files with LRU eviction policy
pub struct AudioCache {
    /// Map from file path to cache entry
    entries: RwLock<HashMap<String, CacheEntry>>,
    /// Access counter for LRU tracking
    access_counter: AtomicU64,
    /// Maximum cache size in bytes
    max_bytes: usize,
    /// Current cache size in bytes
    current_bytes: AtomicU64,
}

impl AudioCache {
    /// Create new cache with default size limit
    pub fn new() -> Self {
        Self::with_max_size(DEFAULT_CACHE_MAX_BYTES)
    }

    /// Create cache with custom size limit
    pub fn with_max_size(max_bytes: usize) -> Self {
        Self {
            entries: RwLock::new(HashMap::new()),
            access_counter: AtomicU64::new(0),
            max_bytes,
            current_bytes: AtomicU64::new(0),
        }
    }

    /// Load audio file into cache (or return cached version)
    /// Automatically evicts LRU entries if cache is full
    pub fn load(&self, path: &str) -> Option<Arc<ImportedAudio>> {
        // Check if already cached
        {
            let mut entries = self.entries.write();
            if let Some(entry) = entries.get_mut(path) {
                // Update LRU timestamp
                entry.last_access = self.access_counter.fetch_add(1, Ordering::Relaxed);
                return Some(Arc::clone(&entry.audio));
            }
        }

        // Load from disk
        match AudioImporter::import(Path::new(path)) {
            Ok(audio) => {
                let size_bytes = audio.samples.len() * std::mem::size_of::<f32>();
                let arc = Arc::new(audio);

                // Evict if necessary before adding
                self.evict_if_needed(size_bytes);

                // Add to cache
                let entry = CacheEntry {
                    audio: Arc::clone(&arc),
                    last_access: self.access_counter.fetch_add(1, Ordering::Relaxed),
                    size_bytes,
                };

                self.entries.write().insert(path.to_string(), entry);
                self.current_bytes.fetch_add(size_bytes as u64, Ordering::Relaxed);

                log::debug!(
                    "Cached audio '{}' ({:.2} MB, total cache: {:.2} MB)",
                    path,
                    size_bytes as f64 / 1024.0 / 1024.0,
                    self.current_bytes.load(Ordering::Relaxed) as f64 / 1024.0 / 1024.0
                );

                Some(arc)
            }
            Err(e) => {
                log::error!("Failed to load audio file '{}': {}", path, e);
                None
            }
        }
    }

    /// Evict least recently used entries until we have room for new_size bytes
    fn evict_if_needed(&self, new_size: usize) {
        let current = self.current_bytes.load(Ordering::Relaxed) as usize;

        // Check if eviction is needed
        if current + new_size <= self.max_bytes {
            return;
        }

        let target_size = self.max_bytes.saturating_sub(new_size);
        let mut entries = self.entries.write();

        // Keep evicting until we're under target or at minimum files
        while self.current_bytes.load(Ordering::Relaxed) as usize > target_size
            && entries.len() > MIN_CACHE_FILES
        {
            // Find LRU entry
            let lru_key = entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_access)
                .map(|(k, _)| k.clone());

            if let Some(key) = lru_key {
                if let Some(entry) = entries.remove(&key) {
                    self.current_bytes
                        .fetch_sub(entry.size_bytes as u64, Ordering::Relaxed);
                    log::debug!(
                        "Evicted LRU cache entry '{}' ({:.2} MB)",
                        key,
                        entry.size_bytes as f64 / 1024.0 / 1024.0
                    );
                }
            } else {
                break;
            }
        }
    }

    /// Check if file is cached
    pub fn is_cached(&self, path: &str) -> bool {
        self.entries.read().contains_key(path)
    }

    /// Get cached audio (without loading) - updates LRU timestamp
    pub fn get(&self, path: &str) -> Option<Arc<ImportedAudio>> {
        let mut entries = self.entries.write();
        if let Some(entry) = entries.get_mut(path) {
            entry.last_access = self.access_counter.fetch_add(1, Ordering::Relaxed);
            return Some(Arc::clone(&entry.audio));
        }
        None
    }

    /// Peek cached audio without updating LRU timestamp
    pub fn peek(&self, path: &str) -> Option<Arc<ImportedAudio>> {
        self.entries.read().get(path).map(|e| Arc::clone(&e.audio))
    }

    /// Remove file from cache
    pub fn unload(&self, path: &str) {
        if let Some(entry) = self.entries.write().remove(path) {
            self.current_bytes
                .fetch_sub(entry.size_bytes as u64, Ordering::Relaxed);
        }
    }

    /// Clear entire cache
    pub fn clear(&self) {
        self.entries.write().clear();
        self.current_bytes.store(0, Ordering::Relaxed);
    }

    /// Get cache size (number of files)
    pub fn size(&self) -> usize {
        self.entries.read().len()
    }

    /// Get total memory usage (bytes)
    pub fn memory_usage(&self) -> usize {
        self.current_bytes.load(Ordering::Relaxed) as usize
    }

    /// Get maximum cache size (bytes)
    pub fn max_size(&self) -> usize {
        self.max_bytes
    }

    /// Get cache utilization (0.0 - 1.0)
    pub fn utilization(&self) -> f64 {
        self.memory_usage() as f64 / self.max_bytes as f64
    }

    /// Set new maximum cache size, evicting if necessary
    pub fn set_max_size(&mut self, max_bytes: usize) {
        self.max_bytes = max_bytes;
        self.evict_if_needed(0);
    }

    /// Get list of cached file paths ordered by recency (most recent first)
    pub fn cached_files(&self) -> Vec<String> {
        let entries = self.entries.read();
        let mut files: Vec<_> = entries
            .iter()
            .map(|(k, v)| (k.clone(), v.last_access))
            .collect();
        files.sort_by(|a, b| b.1.cmp(&a.1)); // Descending by access time
        files.into_iter().map(|(k, _)| k).collect()
    }

    /// Touch entry to mark as recently used (without returning data)
    pub fn touch(&self, path: &str) {
        if let Some(entry) = self.entries.write().get_mut(path) {
            entry.last_access = self.access_counter.fetch_add(1, Ordering::Relaxed);
        }
    }

    /// Insert audio directly into cache (for pre-loaded/rendered audio)
    /// This bypasses disk loading
    pub fn insert(&self, path: String, audio: Arc<ImportedAudio>) {
        let size_bytes = audio.samples.len() * std::mem::size_of::<f32>();

        // Evict if necessary
        self.evict_if_needed(size_bytes);

        let entry = CacheEntry {
            audio,
            last_access: self.access_counter.fetch_add(1, Ordering::Relaxed),
            size_bytes,
        };

        // Check if replacing existing entry
        if let Some(old) = self.entries.write().insert(path, entry) {
            // Adjust size if replacing
            self.current_bytes
                .fetch_sub(old.size_bytes as u64, Ordering::Relaxed);
        }

        self.current_bytes
            .fetch_add(size_bytes as u64, Ordering::Relaxed);
    }

    /// Get all entries as HashMap (for offline rendering compatibility)
    /// Creates a temporary copy - suitable for offline operations
    pub fn to_hashmap(&self) -> HashMap<String, Arc<ImportedAudio>> {
        self.entries
            .read()
            .iter()
            .map(|(k, v)| (k.clone(), Arc::clone(&v.audio)))
            .collect()
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
        self.loop_start
            .store((start_secs * rate as f64) as u64, Ordering::Relaxed);
        self.loop_end
            .store((end_secs * rate as f64) as u64, Ordering::Relaxed);
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
            OutputBus::Master => 0, // Routes directly to master
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

/// Per-track stereo metering data
#[derive(Debug, Clone, Copy, Default)]
pub struct TrackMeter {
    /// Peak level left channel (linear 0.0 - 1.0+)
    pub peak_l: f64,
    /// Peak level right channel (linear 0.0 - 1.0+)
    pub peak_r: f64,
    /// RMS level left channel (linear)
    pub rms_l: f64,
    /// RMS level right channel (linear)
    pub rms_r: f64,
    /// Stereo correlation (-1.0 out of phase, 0.0 uncorrelated, 1.0 mono)
    pub correlation: f64,
}

impl TrackMeter {
    /// Create empty meter (silence)
    pub fn empty() -> Self {
        Self {
            peak_l: 0.0,
            peak_r: 0.0,
            rms_l: 0.0,
            rms_r: 0.0,
            correlation: 1.0, // Mono when silent
        }
    }

    /// Apply decay to meter values
    pub fn decay(&mut self, factor: f64) {
        self.peak_l *= factor;
        self.peak_r *= factor;
        self.rms_l *= factor;
        self.rms_r *= factor;
    }

    /// Update with new sample data
    pub fn update(&mut self, left: &[f64], right: &[f64], decay: f64) {
        let frames = left.len().min(right.len());
        if frames == 0 {
            return;
        }

        // Decay previous values
        self.decay(decay);

        // Calculate new peaks and RMS
        let mut sum_l_sq = 0.0;
        let mut sum_r_sq = 0.0;
        let mut sum_lr = 0.0;

        for i in 0..frames {
            let l = left[i];
            let r = right[i];

            // Peak (max with decayed)
            self.peak_l = self.peak_l.max(l.abs());
            self.peak_r = self.peak_r.max(r.abs());

            // For RMS and correlation
            sum_l_sq += l * l;
            sum_r_sq += r * r;
            sum_lr += l * r;
        }

        // RMS (root mean square)
        let rms_l = (sum_l_sq / frames as f64).sqrt();
        let rms_r = (sum_r_sq / frames as f64).sqrt();
        self.rms_l = self.rms_l.max(rms_l);
        self.rms_r = self.rms_r.max(rms_r);

        // Correlation: r = Σ(L*R) / sqrt(Σ(L²) * Σ(R²))
        let denominator = (sum_l_sq * sum_r_sq).sqrt();
        if denominator > 1e-10 {
            self.correlation = (sum_lr / denominator).clamp(-1.0, 1.0);
        }
    }
}

/// Main playback engine for timeline audio
pub struct PlaybackEngine {
    /// Track manager reference
    track_manager: Arc<TrackManager>,
    /// Audio file cache
    pub(crate) cache: Arc<AudioCache>,
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
    /// LUFS metering (ITU-R BS.1770-4)
    lufs_meter: RwLock<LufsMeter>,
    /// LUFS values (atomic for lock-free UI reads)
    pub lufs_momentary: AtomicU64,
    pub lufs_short: AtomicU64,
    pub lufs_integrated: AtomicU64,
    /// True Peak metering (4x oversampled)
    true_peak_meter: RwLock<TruePeakMeter>,
    /// True Peak values in dBTP
    pub true_peak_l: AtomicU64,
    pub true_peak_r: AtomicU64,
    /// Stereo correlation (-1.0 to 1.0)
    pub correlation: AtomicU64,
    /// Stereo balance (-1.0 left to 1.0 right)
    pub balance: AtomicU64,
    /// Automation engine
    automation: Option<Arc<AutomationEngine>>,
    /// Group/VCA manager (RwLock for shared mutation with bridge)
    group_manager: Option<Arc<RwLock<GroupManager>>>,
    /// Elastic audio parameters per clip (time_ratio, pitch_semitones)
    elastic_params: RwLock<HashMap<u32, (f64, f64)>>,
    /// Track VCA assignments (track_id -> Vec<VcaId>)
    vca_assignments: RwLock<HashMap<u32, Vec<VcaId>>>,
    /// Insert chains per track (track_id -> InsertChain)
    insert_chains: RwLock<HashMap<u64, InsertChain>>,
    /// Master insert chain
    master_insert: RwLock<InsertChain>,
    /// Per-track stereo meters (track_id -> TrackMeter with L/R peaks, RMS, correlation)
    track_meters: RwLock<HashMap<u64, TrackMeter>>,
    /// Master spectrum analyzer (FFT)
    spectrum_analyzer: RwLock<FftAnalyzer>,
    /// Spectrum data cache (256 bins, log-scaled 20Hz-20kHz)
    spectrum_data: RwLock<Vec<f32>>,
    /// Pre-allocated track buffer left (avoid heap alloc in audio thread)
    track_buffer_l: RwLock<Vec<f64>>,
    /// Pre-allocated track buffer right (avoid heap alloc in audio thread)
    track_buffer_r: RwLock<Vec<f64>>,
    /// Pre-allocated mono buffer for spectrum analyzer
    spectrum_mono_buffer: RwLock<Vec<f64>>,
    /// Current block size (for buffer reallocation check)
    current_block_size: AtomicUsize,
    /// Delay compensation manager for automatic plugin delay compensation
    delay_comp: RwLock<DelayCompensationManager>,
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
            lufs_meter: RwLock::new(LufsMeter::new(sample_rate as f64)),
            lufs_momentary: AtomicU64::new((-70.0_f64).to_bits()),
            lufs_short: AtomicU64::new((-70.0_f64).to_bits()),
            lufs_integrated: AtomicU64::new((-70.0_f64).to_bits()),
            true_peak_meter: RwLock::new(TruePeakMeter::new(sample_rate as f64)),
            true_peak_l: AtomicU64::new((-70.0_f64).to_bits()),
            true_peak_r: AtomicU64::new((-70.0_f64).to_bits()),
            correlation: AtomicU64::new(1.0_f64.to_bits()),
            balance: AtomicU64::new(0.0_f64.to_bits()),
            automation: None,
            group_manager: None,
            elastic_params: RwLock::new(HashMap::new()),
            vca_assignments: RwLock::new(HashMap::new()),
            insert_chains: RwLock::new(HashMap::new()),
            master_insert: RwLock::new(InsertChain::new(sample_rate as f64)),
            track_meters: RwLock::new(HashMap::new()),
            // 8192-point FFT for better bass frequency resolution
            // At 48kHz: bin width = 48000/8192 = 5.86Hz (vs 23.4Hz with 2048)
            // This gives ~3-4 bins in 20-40Hz range instead of ~1 bin
            spectrum_analyzer: RwLock::new(FftAnalyzer::new(8192)),
            spectrum_data: RwLock::new(vec![0.0_f32; 512]), // More bins for better resolution
            // Pre-allocate buffers for common block size (will resize if needed)
            track_buffer_l: RwLock::new(vec![0.0_f64; 8192]),
            track_buffer_r: RwLock::new(vec![0.0_f64; 8192]),
            spectrum_mono_buffer: RwLock::new(vec![0.0_f64; 8192]),
            current_block_size: AtomicUsize::new(8192),
            delay_comp: RwLock::new(DelayCompensationManager::new(sample_rate as f64)),
        }
    }

    /// Attach automation engine
    pub fn set_automation(&mut self, automation: Arc<AutomationEngine>) {
        self.automation = Some(automation);
    }

    /// Attach group/VCA manager (shared with bridge)
    pub fn set_group_manager(&mut self, manager: Arc<RwLock<GroupManager>>) {
        self.group_manager = Some(manager);
    }

    /// Get automation engine
    pub fn automation(&self) -> Option<&Arc<AutomationEngine>> {
        self.automation.as_ref()
    }

    /// Assign track to VCA
    pub fn assign_track_to_vca(&self, track_id: u32, vca_id: VcaId) {
        let mut assignments = self.vca_assignments.write();
        assignments.entry(track_id).or_default().push(vca_id);
    }

    /// Remove track from VCA
    pub fn remove_track_from_vca(&self, track_id: u32, vca_id: VcaId) {
        let mut assignments = self.vca_assignments.write();
        if let Some(vcas) = assignments.get_mut(&track_id) {
            vcas.retain(|v| *v != vca_id);
        }
    }

    /// Get combined VCA gain for track
    /// Uses the GroupManager's get_vca_contribution which handles nested VCAs
    fn get_vca_gain(&self, track_id: u64) -> f64 {
        let manager = match &self.group_manager {
            Some(m) => m,
            None => return 1.0,
        };

        // GroupManager uses u64 track_id directly (groups::TrackId = u64)
        // Use try_read to avoid blocking audio thread
        match manager.try_read() {
            Some(gm) => gm.get_vca_contribution(track_id),
            None => 1.0, // Return unity gain if lock is contended
        }
    }

    /// Get track volume with automation applied
    fn get_track_volume_with_automation(&self, track: &Track) -> f64 {
        let base_volume = track.volume;

        if let Some(automation) = &self.automation {
            let param_id = ParamId::track_volume(track.id.0);
            if let Some(auto_value) = automation.get_value(&param_id) {
                // auto_value is normalized 0-1, map to 0-1.5 range
                return auto_value * 1.5;
            }
        }

        base_volume
    }

    /// Get track pan with automation applied
    fn get_track_pan_with_automation(&self, track: &Track) -> f64 {
        let base_pan = track.pan;

        if let Some(automation) = &self.automation {
            let param_id = ParamId::track_pan(track.id.0);
            if let Some(auto_value) = automation.get_value(&param_id) {
                // auto_value is normalized 0-1, map to -1 to 1
                return auto_value * 2.0 - 1.0;
            }
        }

        base_pan
    }

    /// Set elastic audio parameters for clip
    /// time_ratio: 1.0 = normal, 0.5 = half speed, 2.0 = double speed
    /// pitch_semitones: pitch shift in semitones
    pub fn set_elastic_params(&self, clip_id: u32, time_ratio: f64, pitch_semitones: f64) {
        self.elastic_params
            .write()
            .insert(clip_id, (time_ratio, pitch_semitones));
    }

    /// Get elastic audio parameters for clip
    pub fn get_elastic_params(&self, clip_id: u32) -> Option<(f64, f64)> {
        self.elastic_params.read().get(&clip_id).copied()
    }

    /// Remove elastic audio parameters
    pub fn remove_elastic_params(&self, clip_id: u32) {
        self.elastic_params.write().remove(&clip_id);
    }

    /// Check if clip has elastic audio enabled
    pub fn has_elastic_audio(&self, clip_id: u32) -> bool {
        self.elastic_params.read().contains_key(&clip_id)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INSERT CHAIN MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /// Get insert chain for track (creates if not exists)
    pub fn get_track_insert_chain(&self, _track_id: TrackId) -> &RwLock<HashMap<u64, InsertChain>> {
        &self.insert_chains
    }

    /// Get or create insert chain for a track
    pub fn ensure_track_insert_chain(&self, track_id: u64, sample_rate: f64) {
        let mut chains = self.insert_chains.write();
        chains
            .entry(track_id)
            .or_insert_with(|| InsertChain::new(sample_rate));
    }

    /// Load processor into track insert slot
    pub fn load_track_insert(
        &self,
        track_id: u64,
        slot_index: usize,
        processor: Box<dyn crate::insert_chain::InsertProcessor>,
    ) -> bool {
        let sample_rate = self.position.sample_rate() as f64;
        let mut chains = self.insert_chains.write();
        let chain = chains
            .entry(track_id)
            .or_insert_with(|| InsertChain::new(sample_rate));
        let result = chain.load(slot_index, processor);

        // Update delay compensation after loading plugin
        if result {
            drop(chains); // Release chains lock before acquiring delay_comp lock
            self.update_track_delay_compensation(track_id);
        }
        result
    }

    /// Unload processor from track insert slot
    pub fn unload_track_insert(
        &self,
        track_id: u64,
        slot_index: usize,
    ) -> Option<Box<dyn crate::insert_chain::InsertProcessor>> {
        let mut chains = self.insert_chains.write();
        let result = chains
            .get_mut(&track_id)
            .and_then(|chain| chain.unload(slot_index));

        // Update delay compensation after unloading plugin
        if result.is_some() {
            drop(chains); // Release chains lock before acquiring delay_comp lock
            self.update_track_delay_compensation(track_id);
        }
        result
    }

    /// Set bypass for track insert slot
    pub fn set_track_insert_bypass(&self, track_id: u64, slot_index: usize, bypass: bool) {
        if let Some(chain) = self.insert_chains.read().get(&track_id) {
            if let Some(slot) = chain.slot(slot_index) {
                slot.set_bypass(bypass);
            }
        }
    }

    /// Get master insert chain
    pub fn master_insert_chain(&self) -> &RwLock<InsertChain> {
        &self.master_insert
    }

    /// Load processor into master insert slot
    pub fn load_master_insert(
        &self,
        slot_index: usize,
        processor: Box<dyn crate::insert_chain::InsertProcessor>,
    ) -> bool {
        self.master_insert.write().load(slot_index, processor)
    }

    /// Unload processor from master insert slot
    pub fn unload_master_insert(
        &self,
        slot_index: usize,
    ) -> Option<Box<dyn crate::insert_chain::InsertProcessor>> {
        self.master_insert.write().unload(slot_index)
    }

    /// Set bypass for master insert slot
    pub fn set_master_insert_bypass(&self, slot_index: usize, bypass: bool) {
        if let Some(slot) = self.master_insert.read().slot(slot_index) {
            slot.set_bypass(bypass);
        }
    }

    /// Get total insert latency for track
    pub fn get_track_insert_latency(&self, track_id: u64) -> usize {
        self.insert_chains
            .read()
            .get(&track_id)
            .map(|c| c.total_latency())
            .unwrap_or(0)
    }

    /// Get total master insert latency
    pub fn get_master_insert_latency(&self) -> usize {
        self.master_insert.read().total_latency()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DELAY COMPENSATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable/disable automatic delay compensation
    pub fn set_delay_compensation_enabled(&self, enabled: bool) {
        self.delay_comp.write().set_enabled(enabled);
    }

    /// Check if delay compensation is enabled
    pub fn is_delay_compensation_enabled(&self) -> bool {
        self.delay_comp.read().is_enabled()
    }

    /// Update delay compensation for a track based on its insert chain latency
    pub fn update_track_delay_compensation(&self, track_id: u64) {
        let latency = self.get_track_insert_latency(track_id);
        let mut dc = self.delay_comp.write();
        // Register node if not already registered
        dc.register_node(track_id as u32);
        // Report the latency
        dc.report_latency(track_id as u32, latency);
    }

    /// Get compensation delay needed for a track
    pub fn get_track_compensation_delay(&self, track_id: u64) -> usize {
        self.delay_comp
            .read()
            .get_latency(track_id as u32)
            .map(|l| l.compensation_delay)
            .unwrap_or(0)
    }

    /// Get maximum latency in the graph (for monitoring)
    pub fn get_max_latency(&self) -> usize {
        self.delay_comp.read().total_latency()
    }

    /// Apply delay compensation to track buffers
    pub fn apply_track_delay_compensation(
        &self,
        track_id: u64,
        left: &mut [f64],
        right: &mut [f64],
    ) {
        let mut dc = self.delay_comp.write();
        dc.process(track_id as u32, left, right);
    }

    /// Set mix for track insert slot
    pub fn set_track_insert_mix(&self, track_id: u64, slot_index: usize, mix: f64) {
        if let Some(chain) = self.insert_chains.read().get(&track_id) {
            if let Some(slot) = chain.slot(slot_index) {
                slot.set_mix(mix);
            }
        }
    }

    /// Set parameter on track insert processor
    pub fn set_track_insert_param(
        &self,
        track_id: u64,
        slot_index: usize,
        param_index: usize,
        value: f64,
    ) {
        let mut chains = self.insert_chains.write();
        if let Some(chain) = chains.get_mut(&track_id) {
            chain.set_slot_param(slot_index, param_index, value);
        }
    }

    /// Get parameter from track insert processor
    pub fn get_track_insert_param(
        &self,
        track_id: u64,
        slot_index: usize,
        param_index: usize,
    ) -> f64 {
        self.insert_chains
            .read()
            .get(&track_id)
            .map(|chain| chain.get_slot_param(slot_index, param_index))
            .unwrap_or(0.0)
    }

    /// Check if track has insert loaded in slot
    pub fn has_track_insert(&self, track_id: u64, slot_index: usize) -> bool {
        self.insert_chains
            .read()
            .get(&track_id)
            .and_then(|chain| chain.slot(slot_index))
            .map(|slot| slot.is_loaded())
            .unwrap_or(false)
    }

    /// Set position for track insert slot
    pub fn set_track_insert_position(&self, track_id: u64, slot_index: usize, pre_fader: bool) {
        use crate::insert_chain::InsertPosition;
        let mut chains = self.insert_chains.write();
        if let Some(chain) = chains.get_mut(&track_id) {
            if let Some(slot) = chain.slot_mut(slot_index) {
                slot.set_position(if pre_fader {
                    InsertPosition::PreFader
                } else {
                    InsertPosition::PostFader
                });
            }
        }
    }

    /// Bypass all inserts on track
    pub fn bypass_all_track_inserts(&self, track_id: u64, bypass: bool) {
        if let Some(chain) = self.insert_chains.read().get(&track_id) {
            chain.bypass_all(bypass);
        }
    }

    /// Get insert slot info for track
    pub fn get_track_insert_info(
        &self,
        track_id: u64,
    ) -> Vec<(usize, String, bool, bool, bool, f64, usize)> {
        // Returns: (index, name, is_loaded, is_bypassed, is_pre_fader, mix, latency)
        use crate::insert_chain::InsertPosition;
        let chains = self.insert_chains.read();
        if let Some(chain) = chains.get(&track_id) {
            let mut result = Vec::with_capacity(8);
            for i in 0..8 {
                if let Some(slot) = chain.slot(i) {
                    result.push((
                        i,
                        slot.name().to_string(),
                        slot.is_loaded(),
                        slot.is_bypassed(),
                        slot.position() == InsertPosition::PreFader,
                        slot.mix(),
                        slot.latency(),
                    ));
                }
            }
            result
        } else {
            // Return empty slots
            (0..8)
                .map(|i| (i, "Empty".to_string(), false, false, i < 4, 1.0, 0))
                .collect()
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

    /// Get LUFS values (momentary, short-term, integrated) in LUFS
    pub fn get_lufs(&self) -> (f64, f64, f64) {
        (
            f64::from_bits(self.lufs_momentary.load(Ordering::Relaxed)),
            f64::from_bits(self.lufs_short.load(Ordering::Relaxed)),
            f64::from_bits(self.lufs_integrated.load(Ordering::Relaxed)),
        )
    }

    /// Get true peak values (left, right) in dBTP
    pub fn get_true_peak(&self) -> (f64, f64) {
        (
            f64::from_bits(self.true_peak_l.load(Ordering::Relaxed)),
            f64::from_bits(self.true_peak_r.load(Ordering::Relaxed)),
        )
    }

    /// Get stereo correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono)
    pub fn get_correlation(&self) -> f64 {
        f64::from_bits(self.correlation.load(Ordering::Relaxed))
    }

    /// Get stereo balance (-1.0 = full left, 0.0 = center, 1.0 = full right)
    pub fn get_balance(&self) -> f64 {
        f64::from_bits(self.balance.load(Ordering::Relaxed))
    }

    /// Get track peak by track ID (0.0 - 1.0+) - returns max of L/R for backward compatibility
    pub fn get_track_peak(&self, track_id: u64) -> f64 {
        self.track_meters
            .read()
            .get(&track_id)
            .map(|m| m.peak_l.max(m.peak_r))
            .unwrap_or(0.0)
    }

    /// Get track stereo peaks (peak_l, peak_r) by track ID
    pub fn get_track_peak_stereo(&self, track_id: u64) -> (f64, f64) {
        self.track_meters
            .read()
            .get(&track_id)
            .map(|m| (m.peak_l, m.peak_r))
            .unwrap_or((0.0, 0.0))
    }

    /// Get track RMS stereo (rms_l, rms_r) by track ID
    pub fn get_track_rms_stereo(&self, track_id: u64) -> (f64, f64) {
        self.track_meters
            .read()
            .get(&track_id)
            .map(|m| (m.rms_l, m.rms_r))
            .unwrap_or((0.0, 0.0))
    }

    /// Get track correlation by track ID (-1.0 to 1.0)
    pub fn get_track_correlation(&self, track_id: u64) -> f64 {
        self.track_meters
            .read()
            .get(&track_id)
            .map(|m| m.correlation)
            .unwrap_or(1.0)
    }

    /// Get full track meter (all stereo data) by track ID
    pub fn get_track_meter(&self, track_id: u64) -> TrackMeter {
        self.track_meters
            .read()
            .get(&track_id)
            .copied()
            .unwrap_or_else(TrackMeter::empty)
    }

    /// Get all track meters as HashMap
    /// Note: This clones the HashMap - use get_track_meters_for_ids for better performance
    pub fn get_all_track_meters(&self) -> HashMap<u64, TrackMeter> {
        self.track_meters.read().clone()
    }

    /// Get track meters for specific track IDs (more efficient than get_all_track_meters)
    /// Avoids cloning the entire HashMap when only a subset of tracks is needed
    pub fn get_track_meters_for_ids(&self, track_ids: &[u64]) -> Vec<(u64, TrackMeter)> {
        let meters = self.track_meters.read();
        track_ids
            .iter()
            .filter_map(|&id| meters.get(&id).map(|m| (id, *m)))
            .collect()
    }

    /// Get all track peaks as HashMap (backward compatibility - returns max of L/R)
    /// Note: This allocates a new HashMap - use get_track_peaks_for_ids for better performance
    pub fn get_all_track_peaks(&self) -> HashMap<u64, f64> {
        self.track_meters
            .read()
            .iter()
            .map(|(&id, m)| (id, m.peak_l.max(m.peak_r)))
            .collect()
    }

    /// Get track peaks for specific track IDs (more efficient)
    pub fn get_track_peaks_for_ids(&self, track_ids: &[u64]) -> Vec<(u64, f64)> {
        let meters = self.track_meters.read();
        track_ids
            .iter()
            .filter_map(|&id| meters.get(&id).map(|m| (id, m.peak_l.max(m.peak_r))))
            .collect()
    }

    /// Get spectrum data (256 bins, normalized 0-1, log-scaled 20Hz-20kHz)
    pub fn get_spectrum_data(&self) -> Vec<f32> {
        self.spectrum_data.read().clone()
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
        self.master_volume
            .store(volume.clamp(0.0, 1.5).to_bits(), Ordering::Relaxed);
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

        // Decay factor for meters (60dB in ~300ms at 48kHz, 256 block size)
        let decay = 0.9995_f64.powf(frames as f64 / 8.0);

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

        let crossfades = match self.track_manager.crossfades.try_read() {
            Some(x) => x,
            None => return,
        };

        // Use pre-allocated track buffers (resize only if block size changed)
        let mut track_l_guard = match self.track_buffer_l.try_write() {
            Some(g) => g,
            None => return,
        };
        let mut track_r_guard = match self.track_buffer_r.try_write() {
            Some(g) => g,
            None => return,
        };

        // Ensure buffers are large enough (only reallocates if frames > current capacity)
        if track_l_guard.len() < frames {
            track_l_guard.resize(frames, 0.0);
            track_r_guard.resize(frames, 0.0);
            self.current_block_size.store(frames, Ordering::Relaxed);
        }

        // Get mutable slices of the exact size needed
        let track_l = &mut track_l_guard[..frames];
        let track_r = &mut track_r_guard[..frames];

        // Process each track → route to its bus
        for track in tracks.values() {
            if track.muted {
                continue;
            }

            // Clear track buffers
            track_l.fill(0.0);
            track_r.fill(0.0);

            // Find crossfades active in this track for this time range (iterate without collect)
            // Store matching crossfade IDs to avoid lifetime issues
            let mut active_crossfade_ids: [Option<u64>; 8] = [None; 8];
            let mut crossfade_count = 0;
            for xf in crossfades.values() {
                if xf.track_id == track.id
                    && xf.start_time < end_time
                    && xf.end_time() > start_time
                    && crossfade_count < 8
                {
                    active_crossfade_ids[crossfade_count] = Some(xf.id.0);
                    crossfade_count += 1;
                }
            }

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

                // Check if this clip is part of any active crossfade (using stored IDs)
                let crossfade = active_crossfade_ids[..crossfade_count]
                    .iter()
                    .filter_map(|&id| id)
                    .find_map(|xf_id| {
                        crossfades.values().find(|xf| {
                            xf.id.0 == xf_id
                                && (xf.clip_a_id == clip.id || xf.clip_b_id == clip.id)
                        })
                    });

                // Process clip samples into track buffer (with crossfade if applicable)
                self.process_clip_with_crossfade(
                    clip,
                    track,
                    &audio,
                    crossfade,
                    start_sample,
                    sample_rate,
                    track_l,
                    track_r,
                );
            }

            // Process track insert chain (pre-fader inserts applied before volume)
            // Use try_write to avoid blocking audio thread - skip inserts if lock contended
            if let Some(mut chains) = self.insert_chains.try_write() {
                if let Some(chain) = chains.get_mut(&track.id.0) {
                    chain.process_pre_fader(track_l, track_r);
                }
            }

            // Apply track volume and pan (fader stage)
            let track_volume = self.get_track_volume_with_automation(track);
            let vca_gain = self.get_vca_gain(track.id.0);
            let final_volume = track_volume * vca_gain;

            let pan = self.get_track_pan_with_automation(track).clamp(-1.0, 1.0);
            // Constant power pan: pan -1 = full left, 0 = center, 1 = full right
            let pan_angle = (pan + 1.0) * std::f64::consts::FRAC_PI_4; // 0 to PI/2
            let pan_l = pan_angle.cos();  // 1 at left, 0.707 at center, 0 at right
            let pan_r = pan_angle.sin();  // 0 at left, 0.707 at center, 1 at right

            for i in 0..frames {
                track_l[i] *= final_volume * pan_l;
                track_r[i] *= final_volume * pan_r;
            }

            // Process track insert chain (post-fader inserts applied after volume)
            // Use try_write to avoid blocking audio thread - skip inserts if lock contended
            if let Some(mut chains) = self.insert_chains.try_write() {
                if let Some(chain) = chains.get_mut(&track.id.0) {
                    chain.process_post_fader(track_l, track_r);
                }
            }

            // Apply delay compensation for tracks with lower latency than max
            // This aligns all tracks in time regardless of plugin latency
            if let Some(mut dc) = self.delay_comp.try_write() {
                dc.process(track.id.0 as u32, track_l, track_r);
            }

            // Calculate per-track stereo metering (post-fader, post-insert)
            // Includes: peak L/R, RMS L/R, correlation
            if let Some(mut meters) = self.track_meters.try_write() {
                let meter = meters.entry(track.id.0).or_insert_with(TrackMeter::empty);
                meter.update(&track_l[..frames], &track_r[..frames], decay);
            }

            // Route track to its output bus
            bus_buffers.add_to_bus(track.output_bus, track_l, track_r);
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
            // Constant power pan: pan -1 = full left, 0 = center, 1 = full right
            let pan_angle = (pan + 1.0) * std::f64::consts::FRAC_PI_4;
            let pan_l = pan_angle.cos();
            let pan_r = pan_angle.sin();

            for i in 0..frames {
                output_l[i] += bus_l[i] * volume * pan_l;
                output_r[i] += bus_r[i] * volume * pan_r;
            }
        }

        // Apply master insert chain (pre-fader)
        if let Some(mut master_insert) = self.master_insert.try_write() {
            master_insert.process_pre_fader(output_l, output_r);
        }

        // Apply master volume
        let master = self.master_volume();
        for i in 0..frames {
            output_l[i] *= master;
            output_r[i] *= master;
        }

        // Apply master insert chain (post-fader)
        if let Some(mut master_insert) = self.master_insert.try_write() {
            master_insert.process_post_fader(output_l, output_r);
        }

        // Calculate metering (after volume is applied)
        let prev_peak_l = f64::from_bits(self.peak_l.load(Ordering::Relaxed));
        let prev_peak_r = f64::from_bits(self.peak_r.load(Ordering::Relaxed));

        let mut peak_l = prev_peak_l * decay;
        let mut peak_r = prev_peak_r * decay;
        let mut sum_sq_l = 0.0;
        let mut sum_sq_r = 0.0;

        let mut sum_lr = 0.0; // For correlation calculation

        for i in 0..frames {
            let l = output_l[i];
            let r = output_r[i];
            let abs_l = l.abs();
            let abs_r = r.abs();
            peak_l = peak_l.max(abs_l);
            peak_r = peak_r.max(abs_r);
            sum_sq_l += l * l;
            sum_sq_r += r * r;
            sum_lr += l * r; // Cross-correlation
        }

        // Store peaks
        self.peak_l.store(peak_l.to_bits(), Ordering::Relaxed);
        self.peak_r.store(peak_r.to_bits(), Ordering::Relaxed);

        // RMS
        let rms_l = (sum_sq_l / frames as f64).sqrt();
        let rms_r = (sum_sq_r / frames as f64).sqrt();
        self.rms_l.store(rms_l.to_bits(), Ordering::Relaxed);
        self.rms_r.store(rms_r.to_bits(), Ordering::Relaxed);

        // Stereo correlation: r = Σ(L*R) / √(Σ(L²) * Σ(R²))
        // -1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono/correlated
        let denom = (sum_sq_l * sum_sq_r).sqrt();
        let correlation = if denom > 1e-10 {
            (sum_lr / denom).clamp(-1.0, 1.0)
        } else {
            1.0 // Silent = mono (default)
        };
        // Smooth correlation with decay to avoid jitter
        let prev_corr = f64::from_bits(self.correlation.load(Ordering::Relaxed));
        let smoothed_corr = prev_corr * 0.9 + correlation * 0.1;
        self.correlation
            .store(smoothed_corr.to_bits(), Ordering::Relaxed);

        // Stereo balance: based on RMS difference
        // -1.0 = full left, 0.0 = center, 1.0 = full right
        let balance = if rms_l + rms_r > 1e-10 {
            ((rms_r - rms_l) / (rms_l + rms_r)).clamp(-1.0, 1.0)
        } else {
            0.0 // Silent = center
        };
        // Smooth balance
        let prev_bal = f64::from_bits(self.balance.load(Ordering::Relaxed));
        let smoothed_bal = prev_bal * 0.9 + balance * 0.1;
        self.balance
            .store(smoothed_bal.to_bits(), Ordering::Relaxed);

        // LUFS metering (ITU-R BS.1770-4)
        // Use try_write to avoid blocking audio thread if UI is reading
        if let Some(mut lufs) = self.lufs_meter.try_write() {
            lufs.process_block(output_l, output_r);
            self.lufs_momentary
                .store(lufs.momentary_loudness().to_bits(), Ordering::Relaxed);
            self.lufs_short
                .store(lufs.shortterm_loudness().to_bits(), Ordering::Relaxed);
            self.lufs_integrated
                .store(lufs.integrated_loudness().to_bits(), Ordering::Relaxed);
        }

        // True Peak metering (4x oversampled per ITU-R BS.1770-4)
        if let Some(mut tp) = self.true_peak_meter.try_write() {
            tp.process_block(output_l, output_r);
            // Store dBTP values directly
            let dbtp_l: f64 = tp.peak_dbtp_l();
            let dbtp_r: f64 = tp.peak_dbtp_r();
            self.true_peak_l.store(dbtp_l.to_bits(), Ordering::Relaxed);
            self.true_peak_r.store(dbtp_r.to_bits(), Ordering::Relaxed);
        }

        // Spectrum analyzer (FFT)
        // Mix to mono using pre-allocated buffer to avoid heap allocation
        if let Some(mut analyzer) = self.spectrum_analyzer.try_write() {
            if let Some(mut mono_buffer) = self.spectrum_mono_buffer.try_write() {
                // Ensure buffer is large enough
                if mono_buffer.len() < frames {
                    mono_buffer.resize(frames, 0.0);
                }
                // Mix stereo to mono in-place
                for i in 0..frames {
                    mono_buffer[i] = (output_l[i] + output_r[i]) * 0.5;
                }
                analyzer.push_samples(&mono_buffer[..frames]);
            }
            analyzer.analyze();

            // Convert FFT bins to log-scaled 512 bins (20Hz-20kHz)
            // With 8192-point FFT at 48kHz, bin width = 5.86Hz
            // This gives much better bass resolution than 2048-point (23.4Hz)
            if let Some(mut spectrum) = self.spectrum_data.try_write() {
                let sample_rate = self.position.sample_rate() as f64;
                let bin_count = analyzer.bin_count();
                let output_bins = spectrum.len().min(512);

                for i in 0..output_bins {
                    // Log-scale frequency mapping: 20Hz to 20kHz
                    let freq_ratio = i as f64 / (output_bins - 1) as f64;
                    let freq = 20.0 * (1000.0_f64).powf(freq_ratio); // 20Hz to 20kHz

                    // For bass frequencies, average multiple FFT bins for smoother result
                    // This is similar to 1/3 octave smoothing
                    let center_bin = analyzer.freq_to_bin(freq, sample_rate).min(bin_count - 1);

                    let db = if freq < 200.0 {
                        // Bass: average 3 neighboring bins for smoother response
                        let low_bin = center_bin.saturating_sub(1);
                        let high_bin = (center_bin + 1).min(bin_count - 1);
                        let sum: f64 = (low_bin..=high_bin)
                            .map(|b| analyzer.magnitude(b))
                            .sum();
                        sum / (high_bin - low_bin + 1) as f64
                    } else {
                        analyzer.magnitude(center_bin)
                    };

                    // Normalize to 0-1 range (-80dB to 0dB)
                    let normalized = ((db + 80.0) / 80.0).clamp(0.0, 1.0);
                    spectrum[i] = normalized as f32;
                }
            }
        }

        // Advance position
        self.position.advance(frames as u64);

        // Sync automation position
        if let Some(automation) = &self.automation {
            automation.set_position(self.position.samples());
        }
    }

    /// Process audio offline at a specific position (for export/bounce)
    ///
    /// Unlike `process()`, this:
    /// - Takes a specific start position instead of using transport
    /// - Uses blocking locks (safe for offline processing)
    /// - Does not update meters or advance transport
    pub fn process_offline(&self, start_sample: usize, output_l: &mut [f64], output_r: &mut [f64]) {
        let frames = output_l.len();

        // Clear output buffers
        output_l.fill(0.0);
        output_r.fill(0.0);

        let sample_rate = self.position.sample_rate() as f64;
        let start_time = start_sample as f64 / sample_rate;
        let end_time = (start_sample + frames) as f64 / sample_rate;

        // Get bus buffers
        let mut bus_buffers = self.bus_buffers.write();
        if bus_buffers.block_size != frames {
            *bus_buffers = BusBuffers::new(frames);
        }
        bus_buffers.clear();

        // Get data (blocking - safe for offline)
        let tracks = self.track_manager.tracks.read();
        let clips = self.track_manager.clips.read();
        let crossfades = self.track_manager.crossfades.read();

        let mut track_l = vec![0.0f64; frames];
        let mut track_r = vec![0.0f64; frames];

        for track in tracks.values() {
            if track.muted {
                continue;
            }

            track_l.fill(0.0);
            track_r.fill(0.0);

            let track_crossfades: Vec<&Crossfade> = crossfades
                .values()
                .filter(|xf| {
                    xf.track_id == track.id
                        && (xf.start_time < end_time && xf.end_time() > start_time)
                })
                .collect();

            for clip in clips.values() {
                if clip.track_id != track.id || clip.muted {
                    continue;
                }

                if !clip.overlaps(start_time, end_time) {
                    continue;
                }

                // Get cached audio
                let audio = match self.cache.get(&clip.source_file) {
                    Some(a) => a,
                    None => continue, // Audio not cached - skip
                };

                let active_xf = track_crossfades
                    .iter()
                    .find(|xf| xf.clip_a_id == clip.id || xf.clip_b_id == clip.id)
                    .copied();

                self.process_clip_with_crossfade(
                    clip,
                    track,
                    &audio,
                    active_xf,
                    start_sample as u64,
                    sample_rate,
                    &mut track_l,
                    &mut track_r,
                );
            }

            // Apply track volume and pan
            let track_volume = self.get_track_volume_with_automation(track);
            let vca_gain = self.get_vca_gain(track.id.0);
            let final_volume = track_volume * vca_gain;
            let pan = track.pan;
            // Constant power pan: pan -1 = full left, 0 = center, 1 = full right
            let pan_angle = (pan + 1.0) * std::f64::consts::FRAC_PI_4;
            let pan_l = pan_angle.cos();
            let pan_r = pan_angle.sin();

            for i in 0..frames {
                track_l[i] *= final_volume * pan_l;
                track_r[i] *= final_volume * pan_r;
            }

            // Route to bus
            bus_buffers.add_to_bus(track.output_bus, &track_l, &track_r);
        }

        // Sum all buses to master
        bus_buffers.sum_to_master();

        // Copy master to output
        let (master_l, master_r) = bus_buffers.master();
        output_l.copy_from_slice(&master_l[..frames]);
        output_r.copy_from_slice(&master_r[..frames]);

        // Drop bus_buffers lock before taking master_insert lock
        drop(bus_buffers);

        // Master processing
        let mut master_insert = self.master_insert.write();
        master_insert.process_pre_fader(output_l, output_r);

        let master = self.master_volume();
        for i in 0..frames {
            output_l[i] *= master;
            output_r[i] *= master;
        }

        master_insert.process_post_fader(output_l, output_r);
    }

    /// Process a single clip into output buffers (without crossfade)
    /// Kept for backward compatibility
    #[inline]
    #[allow(dead_code)]
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
        self.process_clip_with_crossfade(
            clip,
            track,
            audio,
            None,
            start_sample,
            sample_rate,
            output_l,
            output_r,
        );
    }

    /// Process a single clip into output buffers with optional crossfade
    #[inline]
    fn process_clip_with_crossfade(
        &self,
        clip: &Clip,
        track: &Track,
        audio: &ImportedAudio,
        crossfade: Option<&Crossfade>,
        start_sample: u64,
        sample_rate: f64,
        output_l: &mut [f64],
        output_r: &mut [f64],
    ) {
        // Suppress unused variable warning for track - we use track.id but not other fields here
        // Track volume/pan is now applied in process() after all clips are mixed
        let _ = track;

        let frames = output_l.len();
        let clip_start_sample = (clip.start_time * sample_rate) as i64;
        let source_sample_rate = audio.sample_rate as f64;
        let rate_ratio = source_sample_rate / sample_rate;

        // Only apply clip gain here - track volume/pan is applied later in process()
        let gain = clip.gain;

        // Fade parameters
        let fade_in_samples = (clip.fade_in * sample_rate) as i64;
        let fade_out_samples = (clip.fade_out * sample_rate) as i64;
        let clip_duration_samples = (clip.duration * sample_rate) as i64;

        // Crossfade parameters (if applicable)
        let (xf_start_sample, xf_end_sample, is_clip_a) = if let Some(xf) = crossfade {
            let xf_start = (xf.start_time * sample_rate) as i64;
            let xf_end = ((xf.start_time + xf.duration) * sample_rate) as i64;
            let is_a = xf.clip_a_id == clip.id;
            (xf_start, xf_end, is_a)
        } else {
            (0, 0, false)
        };

        for i in 0..frames {
            let playback_sample = start_sample as i64 + i as i64;
            let clip_relative_sample = playback_sample - clip_start_sample;

            // Check if within clip bounds
            if clip_relative_sample < 0 || clip_relative_sample >= clip_duration_samples {
                continue;
            }

            // Calculate source position (with offset and rate conversion)
            let source_offset_samples = (clip.source_offset * source_sample_rate) as i64;
            let source_sample = ((clip_relative_sample as f64 * rate_ratio) as i64
                + source_offset_samples) as usize;

            // Get sample from audio buffer
            let (mut sample_l, mut sample_r) = if audio.channels == 1 {
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

            // Apply clip FX chain (before track processing)
            if clip.has_fx() {
                let (fx_l, fx_r) = self.process_clip_fx(&clip.fx_chain, sample_l, sample_r);
                sample_l = fx_l;
                sample_r = fx_r;
            }

            // Calculate fade envelope
            let mut fade = 1.0;

            // Fade in (only if not in crossfade or this is clip B)
            if clip_relative_sample < fade_in_samples && fade_in_samples > 0 {
                fade = clip_relative_sample as f64 / fade_in_samples as f64;
                fade = fade * fade; // Quadratic curve
            }

            // Fade out (only if not in crossfade or this is clip A)
            let samples_from_end = clip_duration_samples - clip_relative_sample;
            if samples_from_end < fade_out_samples && fade_out_samples > 0 {
                let fade_out = samples_from_end as f64 / fade_out_samples as f64;
                fade *= fade_out * fade_out;
            }

            // Apply crossfade envelope if within crossfade region
            if let Some(xf) = crossfade {
                if playback_sample >= xf_start_sample && playback_sample < xf_end_sample {
                    // Calculate normalized position within crossfade (0.0 to 1.0)
                    let xf_t = (playback_sample - xf_start_sample) as f32
                        / (xf_end_sample - xf_start_sample) as f32;

                    // Get gains from crossfade shape
                    let (fade_out_gain, fade_in_gain) = xf.shape.evaluate(xf_t);

                    // Apply the appropriate gain
                    if is_clip_a {
                        // Clip A is fading out
                        fade *= fade_out_gain as f64;
                    } else {
                        // Clip B is fading in
                        fade *= fade_in_gain as f64;
                    }
                } else if is_clip_a && playback_sample >= xf_end_sample {
                    // Clip A after crossfade - silent
                    fade = 0.0;
                } else if !is_clip_a && playback_sample < xf_start_sample {
                    // Clip B before crossfade - silent
                    fade = 0.0;
                }
            }

            // Apply gain and fade (pan is applied later in process())
            let final_gain = gain * fade;
            output_l[i] += sample_l * final_gain;
            output_r[i] += sample_r * final_gain;
        }
    }

    /// Process clip FX chain on audio samples
    /// Returns processed samples with FX applied
    ///
    /// This is a simplified version for built-in FX types.
    /// For full processing, use the dsp_wrappers module.
    #[inline]
    fn process_clip_fx(&self, fx_chain: &ClipFxChain, sample_l: f64, sample_r: f64) -> (f64, f64) {
        // Skip if chain is bypassed or empty
        if fx_chain.bypass || fx_chain.is_empty() {
            return (sample_l, sample_r);
        }

        // Apply input gain
        let input_gain = fx_chain.input_gain_linear();
        let mut l = sample_l * input_gain;
        let mut r = sample_r * input_gain;

        // Process each active slot
        for slot in fx_chain.active_slots() {
            let (processed_l, processed_r) = self.process_fx_slot(slot, l, r);

            // Apply wet/dry mix
            let wet = slot.wet_dry;
            let dry = 1.0 - wet;
            l = l * dry + processed_l * wet;
            r = r * dry + processed_r * wet;

            // Apply slot output gain
            let slot_gain = slot.output_gain_linear();
            l *= slot_gain;
            r *= slot_gain;
        }

        // Apply output gain
        let output_gain = fx_chain.output_gain_linear();
        (l * output_gain, r * output_gain)
    }

    /// Process a single FX slot
    /// Implements basic built-in FX processing
    #[inline]
    fn process_fx_slot(&self, slot: &ClipFxSlot, sample_l: f64, sample_r: f64) -> (f64, f64) {
        match &slot.fx_type {
            ClipFxType::Gain { db, pan } => {
                // Simple gain and pan
                let gain = if *db <= -96.0 {
                    0.0
                } else {
                    10.0_f64.powf(*db / 20.0)
                };

                let pan_val = pan.clamp(-1.0, 1.0);
                // Constant power pan: pan -1 = full left, 0 = center, 1 = full right
                let pan_angle = (pan_val + 1.0) * std::f64::consts::FRAC_PI_4;
                let pan_l = pan_angle.cos();
                let pan_r = pan_angle.sin();

                (sample_l * gain * pan_l, sample_r * gain * pan_r)
            }

            ClipFxType::Saturation { drive, mix: _ } => {
                // Simple soft clipping saturation
                let drive_amount = 1.0 + drive * 10.0;
                let l = (sample_l * drive_amount).tanh() / drive_amount.tanh();
                let r = (sample_r * drive_amount).tanh() / drive_amount.tanh();
                (l, r)
            }

            ClipFxType::Compressor {
                ratio,
                threshold_db,
                attack_ms: _,
                release_ms: _,
            } => {
                // Simplified static compression (no envelope follower for now)
                // Full implementation would use stateful processor
                let threshold = 10.0_f64.powf(*threshold_db / 20.0);
                let ratio_inv = 1.0 / ratio;

                let compress = |sample: f64| -> f64 {
                    let abs_sample = sample.abs();
                    if abs_sample > threshold {
                        let over = abs_sample - threshold;
                        let compressed_over = over * ratio_inv;
                        (threshold + compressed_over) * sample.signum()
                    } else {
                        sample
                    }
                };

                (compress(sample_l), compress(sample_r))
            }

            ClipFxType::Limiter { ceiling_db } => {
                // Simple hard limiter
                let ceiling = 10.0_f64.powf(*ceiling_db / 20.0);
                let l = sample_l.clamp(-ceiling, ceiling);
                let r = sample_r.clamp(-ceiling, ceiling);
                (l, r)
            }

            ClipFxType::Gate {
                threshold_db,
                attack_ms: _,
                release_ms: _,
            } => {
                // Simplified static gate (no envelope follower)
                let threshold = 10.0_f64.powf(*threshold_db / 20.0);
                let level = (sample_l.abs() + sample_r.abs()) / 2.0;

                if level < threshold {
                    (0.0, 0.0)
                } else {
                    (sample_l, sample_r)
                }
            }

            ClipFxType::PitchShift {
                semitones: _,
                cents: _,
            } => {
                // Pitch shifting requires stateful buffer - pass through for now
                // Full implementation in dsp_wrappers
                (sample_l, sample_r)
            }

            ClipFxType::TimeStretch { ratio: _ } => {
                // Time stretch is typically offline - pass through
                (sample_l, sample_r)
            }

            // EQ types - require full DSP processor instances
            ClipFxType::ProEq { .. }
            | ClipFxType::UltraEq
            | ClipFxType::Pultec
            | ClipFxType::Api550
            | ClipFxType::Neve1073
            | ClipFxType::MorphEq
            | ClipFxType::RoomCorrection => {
                // These require stateful biquad filters
                // Full implementation should use dsp_wrappers
                (sample_l, sample_r)
            }

            ClipFxType::External { .. } => {
                // External plugins require VST/AU/CLAP hosting
                (sample_l, sample_r)
            }
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

    /// Get current sample rate
    pub fn sample_rate(&self) -> u32 {
        self.position.sample_rate()
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
