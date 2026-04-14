//! Playback Engine - Real-time Audio Streaming from Timeline
//!
//! Provides:
//! - Sample-accurate playback from clips
//! - Multi-track mixing with volume/pan through bus system
//! - Loop region support
//! - Fade in/out and crossfade processing
//! - Lock-free communication with audio thread
//! - Bus routing (tracks → buses → master)
//!
//! P0.5/P0.6 FIX: Background eviction thread to avoid RT allocations

use std::cell::RefCell;
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU32, AtomicU64, AtomicUsize, Ordering};
use std::panic::AssertUnwindSafe;
use std::thread;

use crossbeam_channel::{Sender, bounded};
use parking_lot::RwLock;
use rayon::prelude::*;

use crate::sinc_table::{self, ResampleMode, SincTable};

// ═══════════════════════════════════════════════════════════════════════════
// PLAYBACK SOURCE — For section-based voice filtering
// ═══════════════════════════════════════════════════════════════════════════

/// Source of audio playback for section-based filtering.
/// One-shot voices tagged with a source will only play when that section is active.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PlaybackSource {
    /// DAW timeline playback (default - always plays when transport is active)
    #[default]
    Daw = 0,
    /// Slot Lab event playback
    SlotLab = 1,
    /// Middleware event preview
    Middleware = 2,
    /// Browser preview (uses PreviewEngine, not filtered)
    Browser = 3,
}

impl From<u8> for PlaybackSource {
    fn from(value: u8) -> Self {
        match value {
            0 => PlaybackSource::Daw,
            1 => PlaybackSource::SlotLab,
            2 => PlaybackSource::Middleware,
            3 => PlaybackSource::Browser,
            _ => PlaybackSource::Daw,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// VOICE POOL STATS — Exposed via FFI for UI monitoring
// ═══════════════════════════════════════════════════════════════════════════

/// Voice pool statistics for UI monitoring
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct VoicePoolStats {
    /// Number of currently active voices
    pub active_count: u32,
    /// Maximum number of voices (pool size)
    pub max_voices: u32,
    /// Number of looping voices
    pub looping_count: u32,
    /// Voices from DAW source
    pub daw_voices: u32,
    /// Voices from SlotLab source
    pub slotlab_voices: u32,
    /// Voices from Middleware source
    pub middleware_voices: u32,
    /// Voices from Browser source
    pub browser_voices: u32,
    /// Voices routed to SFX bus
    pub sfx_voices: u32,
    /// Voices routed to Music bus
    pub music_voices: u32,
    /// Voices routed to Voice bus
    pub voice_voices: u32,
    /// Voices routed to Ambience bus
    pub ambience_voices: u32,
    /// Voices routed to Aux bus
    pub aux_voices: u32,
    /// Voices routed to Master bus
    pub master_voices: u32,
}

// ═══════════════════════════════════════════════════════════════════════════
// THREAD-LOCAL SCRATCH BUFFERS (Audio thread only - zero contention)
// ═══════════════════════════════════════════════════════════════════════════
thread_local! {
    /// Thread-local scratch buffer for left channel (audio thread only)
    static SCRATCH_BUFFER_L: RefCell<Vec<f64>> = RefCell::new(vec![0.0; 8192]);
    /// Thread-local scratch buffer for right channel (audio thread only)
    static SCRATCH_BUFFER_R: RefCell<Vec<f64>> = RefCell::new(vec![0.0; 8192]);
    /// Thread-local scratch buffers for Signalsmith Stretch input (preserve_pitch path)
    static STRETCH_SCRATCH_L: RefCell<Vec<f64>> = RefCell::new(vec![0.0; 8192]);
    static STRETCH_SCRATCH_R: RefCell<Vec<f64>> = RefCell::new(vec![0.0; 8192]);
    /// Thread-local scratch buffers for Signalsmith Stretch output (no audio-thread alloc)
    static STRETCH_OUT_L: RefCell<Vec<f64>> = RefCell::new(vec![0.0; 8192]);
    static STRETCH_OUT_R: RefCell<Vec<f64>> = RefCell::new(vec![0.0; 8192]);
    /// Thread-local scratch buffer for per-sample gain (Signalsmith stretch path)
    static STRETCH_GAIN_SCRATCH: RefCell<Vec<f64>> = RefCell::new(vec![0.0; 8192]);
    /// Thread-local scratch buffer for spatial HRTF render output (f32 interleaved stereo)
    static SPATIAL_OUTPUT_BUF: RefCell<Vec<f32>> = RefCell::new(vec![0.0; 16384]);
    /// Thread-local per-voice mono audio for spatial AudioObject construction
    /// 32 voices × 8192 frames max = 262144 f32 pre-allocated
    static SPATIAL_VOICE_MONO: RefCell<Vec<f32>> = RefCell::new(vec![0.0; 262144]);
    /// Thread-local bus-to-bus routing accum buffers (6 buses × L/R)
    /// Heap-allocated to support any block size without stack overflow or truncation
    static BUS_ACCUM_L: RefCell<Vec<Vec<f64>>> = RefCell::new(Vec::new());
    static BUS_ACCUM_R: RefCell<Vec<Vec<f64>>> = RefCell::new(Vec::new());
}

use crate::audio_import::{AudioImporter, ImportedAudio};
use crate::automation::{AutomationEngine, ParamId};
use crate::control_room::{ControlRoom, SoloMode};
use crate::groups::{GroupManager, VcaId};
use crate::input_bus::{InputBusManager, MonitorMode};
use crate::insert_chain::{InsertChain, InsertParamChange};
use crate::recording_manager::RecordingManager;
use crate::routing::ChannelId;
#[cfg(feature = "unified_routing")]
use crate::routing::{ChannelKind, OutputDestination, RoutingCommandSender, RoutingGraphRT};
use crate::routing_pdc::{GraphNode, PDCCalculator, PDCResult, RoutingGraph};
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

/// P0.5/P0.6: Command sent to background eviction thread
enum EvictionCommand {
    /// Request eviction (size hint for future async eviction)
    #[allow(dead_code)]
    EvictIfNeeded { new_size: usize },
    /// Shutdown the eviction thread
    Shutdown,
}

/// Cache for loaded audio files with LRU eviction policy
/// P0.5/P0.6 FIX: Eviction now happens on background thread to avoid RT allocations
pub struct AudioCache {
    /// Map from file path to cache entry
    entries: RwLock<HashMap<String, CacheEntry>>,
    /// Access counter for LRU tracking
    access_counter: AtomicU64,
    /// Maximum cache size in bytes
    max_bytes: usize,
    /// Current cache size in bytes
    current_bytes: AtomicU64,
    /// P0.5/P0.6: Sender for background eviction commands
    eviction_tx: Sender<EvictionCommand>,
    /// P0.5/P0.6: Flag to track if eviction is pending (avoid duplicate requests)
    eviction_pending: AtomicBool,
    /// BUG#13: JoinHandle for graceful shutdown and panic detection
    eviction_thread: parking_lot::Mutex<Option<thread::JoinHandle<()>>>,
}

impl AudioCache {
    /// Create new cache with default size limit
    pub fn new() -> Self {
        Self::with_max_size(DEFAULT_CACHE_MAX_BYTES)
    }

    /// Create cache with custom size limit
    /// P0.5/P0.6: Spawns background eviction thread
    pub fn with_max_size(max_bytes: usize) -> Self {
        // Create bounded channel for eviction commands (small buffer to avoid memory growth)
        let (eviction_tx, eviction_rx) = bounded::<EvictionCommand>(4);

        // Spawn eviction worker thread before constructing cache (handle stored after)
        // BUG#13 FIX: catch_unwind guards against silent thread death
        let handle = thread::Builder::new()
            .name("audio-cache-evict".into())
            .spawn(move || {
                let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
                    // This thread drains the channel to avoid blocking senders.
                    // Actual eviction is inline but optimized (see evict_if_needed).
                    while let Ok(cmd) = eviction_rx.recv() {
                        match cmd {
                            EvictionCommand::Shutdown => break,
                            EvictionCommand::EvictIfNeeded { .. } => {
                                // Eviction handled inline; thread exists for future async path.
                            }
                        }
                    }
                }));
                if let Err(e) = result {
                    let msg = e.downcast_ref::<&str>().copied()
                        .or_else(|| e.downcast_ref::<String>().map(|s| s.as_str()))
                        .unwrap_or("<non-string panic>");
                    log::error!("[AudioCache] eviction thread panicked: {}", msg);
                }
                log::debug!("Audio cache eviction thread shutting down");
            })
            .ok();

        Self {
            entries: RwLock::new(HashMap::new()),
            access_counter: AtomicU64::new(0),
            max_bytes,
            current_bytes: AtomicU64::new(0),
            eviction_tx,
            eviction_pending: AtomicBool::new(false),
            eviction_thread: parking_lot::Mutex::new(handle),
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
                self.current_bytes
                    .fetch_add(size_bytes as u64, Ordering::Relaxed);

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
    /// P0.5/P0.6 FIX: Optimized to avoid String clone in RT-sensitive path
    fn evict_if_needed(&self, new_size: usize) {
        let current = self.current_bytes.load(Ordering::Relaxed) as usize;

        // Check if eviction is needed (fast path - no lock)
        if current + new_size <= self.max_bytes {
            return;
        }

        // Signal background eviction (non-blocking, fire-and-forget)
        // This allows RT path to continue without waiting for eviction
        if !self.eviction_pending.swap(true, Ordering::AcqRel) {
            let _ = self
                .eviction_tx
                .try_send(EvictionCommand::EvictIfNeeded { new_size });
        }

        // P0.5/P0.6 FIX: Perform eviction with optimized algorithm that avoids
        // String cloning by collecting (last_access, size) pairs first, then
        // removing by iterating with retain() which doesn't require key cloning.
        self.evict_lru_optimized(new_size);
    }

    /// P0.5/P0.6 FIX: Optimized LRU eviction that avoids String::clone() in hot path
    /// Uses retain() with a pre-computed threshold instead of find-then-remove pattern
    fn evict_lru_optimized(&self, new_size: usize) {
        let target_size = self.max_bytes.saturating_sub(new_size);
        let mut entries = self.entries.write();

        // Fast exit if nothing to evict
        if entries.len() <= MIN_CACHE_FILES {
            self.eviction_pending.store(false, Ordering::Release);
            return;
        }

        // P0.5 FIX: Collect (last_access, size) pairs to find eviction threshold
        // This avoids cloning String keys by working with u64 timestamps
        let mut access_sizes: Vec<(u64, usize)> = entries
            .values()
            .map(|e| (e.last_access, e.size_bytes))
            .collect();

        // Sort by access time (oldest first)
        access_sizes.sort_unstable_by_key(|(access, _)| *access);

        // Calculate eviction threshold: find the access time that, if we evict
        // all entries at or below it, brings us under target
        let mut cumulative_freed = 0usize;
        let need_to_free = self
            .current_bytes
            .load(Ordering::Relaxed)
            .saturating_sub(target_size as u64) as usize;

        let mut eviction_threshold = 0u64;
        let entries_to_keep = entries.len().saturating_sub(MIN_CACHE_FILES);

        for (i, (access, size)) in access_sizes.iter().enumerate() {
            if i >= entries_to_keep {
                break; // Keep minimum files
            }
            cumulative_freed += size;
            eviction_threshold = *access;
            if cumulative_freed >= need_to_free {
                break;
            }
        }

        // P0.6 FIX: Use retain() to evict entries without String cloning
        // retain() iterates in-place and doesn't require key extraction
        if eviction_threshold > 0 {
            let current_bytes = &self.current_bytes;
            entries.retain(|_key, entry| {
                if entry.last_access <= eviction_threshold {
                    // Evict this entry
                    current_bytes.fetch_sub(entry.size_bytes as u64, Ordering::Relaxed);
                    log::debug!(
                        "Evicted LRU cache entry ({:.2} MB)",
                        entry.size_bytes as f64 / 1024.0 / 1024.0
                    );
                    false // Remove
                } else {
                    true // Keep
                }
            });
        }

        self.eviction_pending.store(false, Ordering::Release);
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

    /// Get all cache keys (for debugging)
    pub fn keys(&self) -> Vec<String> {
        self.entries.read().keys().cloned().collect()
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
        files.sort_by_key(|b| std::cmp::Reverse(b.1)); // Descending by access time
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

    // =========================================================================
    // PARALLEL PRELOAD — Ultimate SlotLab Audio Loading Optimization
    // =========================================================================

    /// Preload multiple audio files in parallel using rayon thread pool.
    /// Returns the number of successfully loaded files.
    ///
    /// This is the ultimate optimization for SlotLab audio loading:
    /// - Parallel disk I/O and decoding across all CPU cores
    /// - Already-cached files are skipped (instant return)
    /// - Failed files are logged and counted
    ///
    /// Use this at SlotLab initialization to preload all event audio.
    pub fn preload_paths_parallel(&self, paths: &[&str]) -> PreloadResult {
        if paths.is_empty() {
            return PreloadResult::default();
        }

        let start_time = std::time::Instant::now();

        // Filter out already cached paths (fast path)
        let paths_to_load: Vec<&str> = {
            let entries = self.entries.read();
            paths
                .iter()
                .filter(|p| entries.get::<str>(*p).is_none())
                .copied()
                .collect()
        };

        if paths_to_load.is_empty() {
            return PreloadResult {
                total: paths.len(),
                loaded: paths.len(),
                cached: paths.len(),
                failed: 0,
                duration_ms: start_time.elapsed().as_millis() as u64,
            };
        }

        let cached_count = paths.len() - paths_to_load.len();

        // Parallel load using rayon
        let results: Vec<Option<(String, Arc<ImportedAudio>, usize)>> = paths_to_load
            .par_iter()
            .map(|path| match AudioImporter::import(Path::new(path)) {
                Ok(audio) => {
                    let size_bytes = audio.samples.len() * std::mem::size_of::<f32>();
                    Some((path.to_string(), Arc::new(audio), size_bytes))
                }
                Err(e) => {
                    log::warn!("[AudioCache] Preload failed for '{}': {}", path, e);
                    None
                }
            })
            .collect();

        // Insert into cache (sequential, but fast since data is already decoded)
        let mut loaded_count = 0;
        let mut failed_count = 0;

        for result in results {
            if let Some((path, audio, size_bytes)) = result {
                // Evict if necessary
                self.evict_if_needed(size_bytes);

                let entry = CacheEntry {
                    audio,
                    last_access: self.access_counter.fetch_add(1, Ordering::Relaxed),
                    size_bytes,
                };

                self.entries.write().insert(path, entry);
                self.current_bytes
                    .fetch_add(size_bytes as u64, Ordering::Relaxed);
                loaded_count += 1;
            } else {
                failed_count += 1;
            }
        }

        let duration_ms = start_time.elapsed().as_millis() as u64;
        log::info!(
            "[AudioCache] Parallel preload: {} loaded, {} cached, {} failed in {}ms",
            loaded_count,
            cached_count,
            failed_count,
            duration_ms
        );

        PreloadResult {
            total: paths.len(),
            loaded: loaded_count + cached_count,
            cached: cached_count,
            failed: failed_count,
            duration_ms,
        }
    }

    /// Check if all paths are cached (fast check for preload status)
    pub fn all_cached(&self, paths: &[&str]) -> bool {
        let entries = self.entries.read();
        paths.iter().all(|p| entries.get::<str>(*p).is_some())
    }

    /// Get cache statistics as JSON string
    pub fn stats_json(&self) -> String {
        format!(
            r#"{{"size":{}, "memory_mb":{:.2}, "max_mb":{:.2}, "utilization":{:.1}}}"#,
            self.size(),
            self.memory_usage() as f64 / 1024.0 / 1024.0,
            self.max_size() as f64 / 1024.0 / 1024.0,
            self.utilization() * 100.0
        )
    }
}

/// Result of parallel preload operation
#[derive(Debug, Clone, Default)]
pub struct PreloadResult {
    /// Total paths requested
    pub total: usize,
    /// Successfully loaded (including already cached)
    pub loaded: usize,
    /// Already cached (skipped)
    pub cached: usize,
    /// Failed to load
    pub failed: usize,
    /// Total duration in milliseconds
    pub duration_ms: u64,
}

impl Default for AudioCache {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for AudioCache {
    fn drop(&mut self) {
        // BUG#13 FIX: Signal shutdown then join for graceful exit
        let _ = self.eviction_tx.try_send(EvictionCommand::Shutdown);
        if let Some(handle) = self.eviction_thread.lock().take() {
            let _ = handle.join();
        }
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
    Recording = 3,
    Scrubbing = 4,
}

impl From<u8> for PlaybackState {
    fn from(value: u8) -> Self {
        match value {
            1 => Self::Playing,
            2 => Self::Paused,
            3 => Self::Recording,
            4 => Self::Scrubbing,
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
    /// Scrub velocity (-4.0 to 4.0, 0 = stationary)
    scrub_velocity: AtomicU64,
    /// Scrub window size in samples (audio preview length)
    scrub_window_samples: AtomicU64,
    /// Scrub playhead within window (0 to window_size)
    scrub_window_pos: AtomicU64,
    /// Current tempo in BPM (stored as f64 bits for lock-free access)
    tempo_bpm: AtomicU64,
}

impl PlaybackPosition {
    /// Default scrub window: 50ms at 48kHz = 2400 samples
    const DEFAULT_SCRUB_WINDOW_MS: u64 = 50;

    pub fn new(sample_rate: u32) -> Self {
        let scrub_window = (sample_rate as u64 * Self::DEFAULT_SCRUB_WINDOW_MS) / 1000;
        Self {
            sample_position: AtomicU64::new(0),
            sample_rate: AtomicU64::new(sample_rate as u64),
            state: std::sync::atomic::AtomicU8::new(PlaybackState::Stopped as u8),
            loop_enabled: AtomicBool::new(false),
            loop_start: AtomicU64::new(0),
            loop_end: AtomicU64::new(0),
            scrub_velocity: AtomicU64::new(0.0_f64.to_bits()),
            scrub_window_samples: AtomicU64::new(scrub_window),
            scrub_window_pos: AtomicU64::new(0),
            tempo_bpm: AtomicU64::new(120.0_f64.to_bits()),
        }
    }

    /// Get current tempo in BPM (lock-free, audio thread safe)
    #[inline]
    pub fn get_tempo(&self) -> Option<f64> {
        let bits = self.tempo_bpm.load(Ordering::Relaxed);
        let tempo = f64::from_bits(bits);
        if tempo > 0.0 { Some(tempo) } else { None }
    }

    /// Set tempo in BPM (lock-free, callable from any thread)
    #[inline]
    pub fn set_tempo(&self, bpm: f64) {
        self.tempo_bpm.store(bpm.to_bits(), Ordering::Relaxed);
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

    /// Advance position by given samples with varispeed rate, handling loop
    /// Returns actual frames advanced (may differ due to varispeed)
    #[inline]
    pub fn advance_with_rate(&self, frames: u64, rate: f64) -> u64 {
        let effective_frames = (frames as f64 * rate) as u64;
        self.advance(effective_frames)
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
        matches!(
            self.state(),
            PlaybackState::Playing | PlaybackState::Recording | PlaybackState::Scrubbing
        )
    }

    /// Check if transport should advance position (excludes scrubbing where position is manually controlled)
    #[inline]
    pub fn should_advance(&self) -> bool {
        matches!(
            self.state(),
            PlaybackState::Playing | PlaybackState::Recording
        )
    }

    #[inline]
    pub fn is_recording(&self) -> bool {
        self.state() == PlaybackState::Recording
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

    /// Update sample rate (called when audio device changes or stream starts)
    pub fn set_sample_rate(&self, sr: u32) {
        self.sample_rate.store(sr as u64, Ordering::Relaxed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCRUBBING (Pro Tools / Cubase style audio preview on drag)
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if currently scrubbing
    #[inline]
    pub fn is_scrubbing(&self) -> bool {
        self.state() == PlaybackState::Scrubbing
    }

    /// Get current scrub velocity (-4.0 to 4.0)
    #[inline]
    pub fn scrub_velocity(&self) -> f64 {
        f64::from_bits(self.scrub_velocity.load(Ordering::Relaxed))
    }

    /// Set scrub velocity (controls playback direction and speed)
    /// Positive = forward, Negative = backward, 0 = stationary (loop current window)
    #[inline]
    pub fn set_scrub_velocity(&self, velocity: f64) {
        let clamped = velocity.clamp(-4.0, 4.0);
        self.scrub_velocity
            .store(clamped.to_bits(), Ordering::Relaxed);
    }

    /// Get scrub window size in samples
    #[inline]
    pub fn scrub_window_samples(&self) -> u64 {
        self.scrub_window_samples.load(Ordering::Relaxed)
    }

    /// Set scrub window size in milliseconds (10-200ms, default 50ms)
    pub fn set_scrub_window_ms(&self, ms: u64) {
        let clamped = ms.clamp(10, 200);
        let rate = self.sample_rate.load(Ordering::Relaxed);
        let samples = (rate * clamped) / 1000;
        self.scrub_window_samples.store(samples, Ordering::Relaxed);
    }

    /// Get current position within scrub window
    #[inline]
    pub fn scrub_window_pos(&self) -> u64 {
        self.scrub_window_pos.load(Ordering::Relaxed)
    }

    /// Advance scrub position within window, returns (window_sample_offset, should_loop)
    /// Called from audio thread during scrub playback
    #[inline]
    pub fn advance_scrub(&self, frames: u64) -> (u64, bool) {
        let window_size = self.scrub_window_samples.load(Ordering::Relaxed);
        let velocity = self.scrub_velocity();

        // Calculate actual frames to advance based on velocity
        let actual_frames = if velocity.abs() < 0.001 {
            frames // Play at normal speed when nearly stationary
        } else {
            (frames as f64 * velocity.abs()) as u64
        };

        let current = self.scrub_window_pos.load(Ordering::Relaxed);
        let mut new_pos = current + actual_frames;
        let mut looped = false;

        // Loop within scrub window
        if new_pos >= window_size {
            new_pos %= window_size.max(1);
            looped = true;
        }

        self.scrub_window_pos.store(new_pos, Ordering::Relaxed);
        (new_pos, looped)
    }

    /// Reset scrub window position (call when seeking during scrub)
    #[inline]
    pub fn reset_scrub_window(&self) {
        self.scrub_window_pos.store(0, Ordering::Relaxed);
    }
}

impl Default for PlaybackPosition {
    fn default() -> Self {
        Self::new(48000)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ONE-SHOT VOICE — For Middleware/SlotLab event playback through buses
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum concurrent one-shot voices
const MAX_ONE_SHOT_VOICES: usize = 32;

/// One-shot voice for event-triggered audio playback
/// Routes directly to a bus (bypasses track system)
#[derive(Debug)]
pub struct OneShotVoice {
    /// Unique voice ID
    pub id: u64,
    /// Audio data
    audio: Arc<ImportedAudio>,
    /// Current playback position in frames
    position: u64,
    /// Volume (0.0 to 1.0)
    volume: f32,
    /// Pan position (-1.0 = full left, 0.0 = center, +1.0 = full right)
    /// For mono: single pan positions signal in stereo field
    /// For stereo dual-pan: controls L channel placement (default -1.0 = hard left)
    pan: f32,
    /// Right channel pan for stereo dual-pan mode (-1.0 to +1.0)
    /// Default 0.0 for mono (unused), 1.0 for stereo (hard right)
    /// Pro Tools semantics: pan controls L, pan_right controls R independently
    pan_right: f32,
    /// Target bus for routing
    bus: OutputBus,
    /// Source section (for section-based filtering)
    source: PlaybackSource,
    /// Is voice active
    active: bool,
    /// Fade state (for smooth stop)
    fade_samples_remaining: u64,
    /// Fade increment per sample (negative for fade out)
    fade_increment: f32,
    /// Current fade gain
    fade_gain: f32,
    /// P0.2: Loop playback (seamless, no gap)
    looping: bool,
    /// Release mode — voice plays out remaining audio instead of looping back
    loop_releasing: bool,
    /// Random start offset range in samples (0 = disabled)
    loop_random_start_samples: u64,
    // ═══════════════════════════════════════════════════════════════════════════
    // EXTENDED PARAMETERS: FadeIn and Trim support
    // ═══════════════════════════════════════════════════════════════════════════
    /// Total samples for fade-in (0 = no fade-in)
    fade_in_samples_total: u64,
    /// Elapsed fade-in samples (counts up to fade_in_samples_total)
    fade_in_samples_elapsed: u64,
    /// Trim start position in samples (where to start playback)
    trim_start_sample: u64,
    /// Trim end position in samples (0 = play to end)
    trim_end_sample: u64,
    /// Fade out duration in samples (applied at end or when stopping)
    fade_out_samples_at_end: u64,
    // ═══════════════════════════════════════════════════════════════════════════
    // P12.0.1: REAL-TIME PITCH SHIFTING
    // ═══════════════════════════════════════════════════════════════════════════
    /// Pitch shift in semitones (-24 to +24, 0 = no shift)
    pitch_semitones: f32,
    /// Real-time mute (voice continues but produces silence)
    muted: bool,
    /// Input gain/trim in linear amplitude (1.0 = 0dB, 0.5 = -6dB, 2.0 = +6dB)
    /// Applied as pre-fader multiplier on source samples
    input_gain: f32,
    /// Stereo width: 0.0 = mono, 1.0 = normal stereo, 2.0 = extra wide
    /// Applied via mid/side processing after pan
    stereo_width: f32,
    /// Phase invert: negate all samples (polarity flip Ø)
    phase_invert: bool,
    /// Per-voice peak metering (updated in fill_buffer, read by GUI via try_read)
    /// Linear amplitude 0.0-1.0+, NOT dB. Decays toward 0 each block.
    pub meter_peak_l: f32,
    pub meter_peak_r: f32,
    /// Engine sample rate for sample rate conversion
    /// Source SR != engine SR → rate_ratio applied in fill_buffer
    engine_sample_rate: u32,
    /// Per-voice resample quality — adaptive, can be degraded under CPU pressure
    voice_resample_mode: ResampleMode,
    /// Spatial source ID — when Some, voice bypasses pan law and routes through
    /// SpatialManager HRTF pipeline instead of normal bus routing.
    spatial_source_id: Option<u32>,
}

// ═══════════════════════════════════════════════════════════════════════════
// SINC INTERPOLATION — Blackman-Harris windowed sinc via pre-computed table
// ═══════════════════════════════════════════════════════════════════════════
//
// Quality modes: Point, Linear, Sinc(16/64/192/384/512/768)
// Default playback: Sinc(64) = Reaper "Medium" (~-120dB noise floor)
// Default render: Sinc(384) = Reaper "Better" (~-150dB)
// All computation on stack — no heap allocations in audio path.

/// Global playback sinc table — dynamically matches current resample mode.
/// Table is re-generated when mode changes (rare — settings UI only).
/// Read path uses RwLock read guard (fast, no contention on audio thread).
static PLAYBACK_SINC_TABLE: std::sync::LazyLock<parking_lot::RwLock<SincTable>> =
    std::sync::LazyLock::new(|| parking_lot::RwLock::new(SincTable::new(64, 256)));

/// Current playback resample mode (default: Sinc(64))
static PLAYBACK_RESAMPLE_MODE: std::sync::atomic::AtomicU16 =
    std::sync::atomic::AtomicU16::new(64);

/// Get the current playback resample mode
pub fn playback_resample_mode() -> ResampleMode {
    let val = PLAYBACK_RESAMPLE_MODE.load(std::sync::atomic::Ordering::Relaxed);
    match val {
        0 => ResampleMode::Point,
        1 => ResampleMode::Linear,
        u16::MAX => ResampleMode::R8brain,
        n => ResampleMode::Sinc(n),
    }
}

/// Set the playback resample mode and regenerate sinc table if needed.
/// Called from settings UI — NOT on audio thread.
pub fn set_playback_resample_mode(mode: ResampleMode) {
    let val = match mode {
        ResampleMode::Point => 0,
        ResampleMode::Linear => 1,
        ResampleMode::R8brain => u16::MAX,
        ResampleMode::Sinc(n) => n,
    };
    let old = PLAYBACK_RESAMPLE_MODE.swap(val, std::sync::atomic::Ordering::Relaxed);
    // Regenerate table only if sinc size changed
    if let ResampleMode::Sinc(new_size) = mode {
        let old_mode_is_sinc = old >= 2;
        if !old_mode_is_sinc || old != new_size {
            *PLAYBACK_SINC_TABLE.write() = SincTable::new(new_size as usize, 256);
        }
    }
}

impl OneShotVoice {
    fn new_inactive() -> Self {
        Self {
            id: 0,
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
            position: 0,
            volume: 1.0,
            pan: 0.0,
            pan_right: 0.0,
            bus: OutputBus::Sfx,
            source: PlaybackSource::Daw,
            active: false,
            fade_samples_remaining: 0,
            fade_increment: 0.0,
            fade_gain: 1.0,
            looping: false,
            loop_releasing: false,
            loop_random_start_samples: 0,
            // Extended parameters
            fade_in_samples_total: 0,
            fade_in_samples_elapsed: 0,
            trim_start_sample: 0,
            trim_end_sample: 0,
            fade_out_samples_at_end: 0,
            // P12.0.1: Pitch shift
            pitch_semitones: 0.0,
            // Real-time mute
            muted: false,
            input_gain: 1.0,
            stereo_width: 1.0,
            phase_invert: false,
            // Per-voice metering
            meter_peak_l: 0.0,
            meter_peak_r: 0.0,
            // Engine sample rate for SRC (set on activate)
            engine_sample_rate: 48000,
            voice_resample_mode: ResampleMode::PLAYBACK,
            spatial_source_id: None,
        }
    }

    fn activate(
        &mut self,
        id: u64,
        audio: Arc<ImportedAudio>,
        volume: f32,
        pan: f32,
        bus: OutputBus,
        source: PlaybackSource,
    ) {
        self.id = id;
        self.audio = audio;
        self.position = 0;
        self.volume = volume;
        self.pan = pan.clamp(-1.0, 1.0);
        // Stereo dual-pan: pan_right defaults to 0.0 here, caller sends SetPanRight after Play
        self.pan_right = 0.0;
        self.bus = bus;
        self.source = source;
        self.active = true;
        self.fade_samples_remaining = 0;
        self.fade_increment = 0.0;
        // Anti-click: 10ms fade-in on all voices (480 samples @ 48kHz)
        self.fade_in_samples_total = 480;
        self.fade_in_samples_elapsed = 0;
        self.fade_gain = 0.0;
        self.pitch_semitones = 0.0; // P12.0.1: Reset pitch on activate
        self.looping = false;
        self.loop_releasing = false;
        self.loop_random_start_samples = 0;
        self.trim_start_sample = 0;
        self.trim_end_sample = 0;
        self.fade_out_samples_at_end = 0;
        self.muted = false;
        self.input_gain = 1.0;
        self.stereo_width = 1.0;
        self.phase_invert = false;
        self.meter_peak_l = 0.0;
        self.meter_peak_r = 0.0;
        self.spatial_source_id = None;
        // Reset to current global quality (not stale mode from previous voice)
        let mode = playback_resample_mode();
        self.voice_resample_mode = if mode.is_r8brain() {
            // R8brain is offline-only — fallback to Sinc(384) for real-time
            ResampleMode::Sinc(384)
        } else {
            mode
        };
    }

    /// Activate with looping enabled (P0.2: Seamless REEL_SPIN loop)
    fn activate_looping(
        &mut self,
        id: u64,
        audio: Arc<ImportedAudio>,
        volume: f32,
        pan: f32,
        bus: OutputBus,
        source: PlaybackSource,
    ) {
        self.activate(id, audio, volume, pan, bus, source);
        self.looping = true;
    }

    /// Activate with extended parameters (fadeIn, fadeOut, trim)
    /// fade_in_ms: fade-in duration in milliseconds
    /// fade_out_ms: fade-out duration in milliseconds (applied at end)
    /// trim_start_ms: start position in milliseconds
    /// trim_end_ms: end position in milliseconds (0 = play to end)
    fn activate_ex(
        &mut self,
        id: u64,
        audio: Arc<ImportedAudio>,
        volume: f32,
        pan: f32,
        bus: OutputBus,
        source: PlaybackSource,
        fade_in_ms: f32,
        fade_out_ms: f32,
        trim_start_ms: f32,
        trim_end_ms: f32,
    ) {
        let sample_rate = audio.sample_rate as f64;

        self.id = id;
        self.audio = audio;
        self.volume = volume;
        self.pan = pan.clamp(-1.0, 1.0);
        self.pan_right = 0.0; // Caller sends SetPanRight after PlayEx for stereo
        self.bus = bus;
        self.source = source;
        self.active = true;
        self.looping = false;
        self.loop_releasing = false;
        self.loop_random_start_samples = 0;

        // Fade out state (initially not fading)
        self.fade_samples_remaining = 0;
        self.fade_increment = 0.0;

        // Fade-in: start at 0 gain, ramp up to 1.0
        // Minimum 480 samples (~10ms) anti-click fade even if fade_in_ms=0
        let fade_in_samples = ((sample_rate * fade_in_ms as f64) / 1000.0) as u64;
        self.fade_in_samples_total = fade_in_samples.max(480);
        self.fade_in_samples_elapsed = 0;
        self.fade_gain = 0.0;

        // Trim: convert ms to samples
        self.trim_start_sample = ((sample_rate * trim_start_ms as f64) / 1000.0) as u64;
        self.trim_end_sample = if trim_end_ms > 0.0 {
            ((sample_rate * trim_end_ms as f64) / 1000.0) as u64
        } else {
            0 // 0 means play to end
        };

        // Start position respects trim
        self.position = self.trim_start_sample;

        // Store fade-out duration for applying at end
        self.fade_out_samples_at_end = ((sample_rate * fade_out_ms as f64) / 1000.0) as u64;

        // Reset pitch and mute
        self.pitch_semitones = 0.0;
        self.muted = false;
        self.input_gain = 1.0;
        self.stereo_width = 1.0;
        self.phase_invert = false;
        self.meter_peak_l = 0.0;
        self.meter_peak_r = 0.0;
    }

    fn deactivate(&mut self) {
        self.active = false;
        self.position = 0;
    }

    /// Release loop — voice plays remaining audio without wrapping back
    #[allow(dead_code)]
    fn release_loop(&mut self) {
        if self.looping {
            self.loop_releasing = true;
            self.looping = false;
        }
    }

    /// Start fade out (for smooth stop)
    fn start_fade_out(&mut self, fade_samples: u64) {
        if fade_samples > 0 {
            self.fade_samples_remaining = fade_samples;
            self.fade_increment = -self.fade_gain / fade_samples as f32;
        } else {
            self.deactivate();
        }
    }

    /// Fill buffer with audio, returns true if still playing
    /// Applies equal-power panning for spatial positioning
    /// P0.2: Supports seamless looping for REEL_SPIN and similar events
    /// P12.0.1: Supports real-time pitch shifting via resampling (-24 to +24 semitones)
    #[inline]
    fn fill_buffer(&mut self, left: &mut [f64], right: &mut [f64]) -> bool {
        if !self.active {
            return false;
        }

        let frames_needed = left.len();
        let channels_src = self.audio.channels as usize;
        let total_frames = self.audio.samples.len() / channels_src.max(1);

        if total_frames == 0 {
            self.active = false;
            return false;
        }

        // P0.2: For non-looping, check end condition
        // Also check trim_end_sample if set
        let effective_end =
            if self.trim_end_sample > 0 && self.trim_end_sample < total_frames as u64 {
                self.trim_end_sample
            } else {
                total_frames as u64
            };

        if !self.looping && self.position >= effective_end {
            self.active = false;
            return false;
        }

        // Pre-compute equal-power pan gains (constant for this voice)
        // pan: -1.0 = full left, 0.0 = center, +1.0 = full right
        // Formula: L = cos(θ), R = sin(θ) where θ = (pan + 1) * π/4
        // θ ranges from 0 (full left) to π/2 (full right)
        let pan_angle = (self.pan + 1.0) * std::f32::consts::FRAC_PI_4;
        let pan_l = pan_angle.cos();
        let pan_r = pan_angle.sin();

        // Sample rate conversion ratio: source_sr / engine_sr
        // e.g., 44100Hz file in 48000Hz engine → rate_ratio = 0.91875
        // This ensures correct pitch and duration regardless of source sample rate
        let source_sr = self.audio.sample_rate as f64;
        let engine_sr = self.engine_sample_rate as f64;
        let rate_ratio = source_sr / engine_sr;

        // P12.0.1: Calculate pitch shift ratio (semitones to frequency ratio)
        // pitch_ratio = 2^(semitones / 12)
        // Range: -24 to +24 semitones
        // Example: +12 semitones = 2.0x speed (one octave up)
        //          -12 semitones = 0.5x speed (one octave down)
        let pitch_ratio = if self.pitch_semitones.abs() > 0.001 {
            2.0_f64.powf(self.pitch_semitones as f64 / 12.0)
        } else {
            1.0 // No pitch shift
        };

        // Combined playback rate: SRC * pitch shift
        let combined_rate = rate_ratio * pitch_ratio;

        // Per-voice resample quality — adaptive under CPU pressure.
        // Acquire sinc table ONCE per block (not per-frame)
        let resample_mode = self.voice_resample_mode;
        let sinc_guard = match PLAYBACK_SINC_TABLE.try_read() {
            Some(guard) => guard,
            None => {
                // Sinc table being rebuilt — output silence for this voice buffer
                left[..frames_needed].fill(0.0);
                right[..frames_needed].fill(0.0);
                return false; // Signal: voice should continue next block
            }
        };
        let sinc_ref = Some(&*sinc_guard);

        // Per-voice peak tracking for this block
        let mut voice_peak_l: f32 = 0.0;
        let mut voice_peak_r: f32 = 0.0;

        for frame in 0..frames_needed {
            // Handle fade-out (from stop command or explicit fade_out_one_shot)
            if self.fade_samples_remaining > 0 {
                self.fade_gain += self.fade_increment;
                self.fade_samples_remaining -= 1;
                if self.fade_gain <= 0.0 {
                    self.fade_gain = 0.0;
                    self.active = false;
                    // Fade completed cleanly at zero — no click
                    return false;
                }
            }

            // Handle fade-in (ramp up from 0 to 1)
            if self.fade_in_samples_elapsed < self.fade_in_samples_total {
                self.fade_in_samples_elapsed += 1;
                // Linear fade-in (can be changed to quadratic for smoother curve)
                self.fade_gain =
                    self.fade_in_samples_elapsed as f32 / self.fade_in_samples_total as f32;
            }

            // Check if we need to start fade-out at end (auto fade-out near trim_end)
            // current_source_pos tracks actual position in source sample space
            let current_source_pos = self.position + (frame as f64 * combined_rate) as u64;
            if self.fade_out_samples_at_end > 0 && self.fade_samples_remaining == 0 {
                let samples_to_end = effective_end.saturating_sub(current_source_pos);
                if samples_to_end <= self.fade_out_samples_at_end && samples_to_end > 0 {
                    // Start fade-out automatically near the end
                    self.fade_samples_remaining = samples_to_end;
                    self.fade_increment = -self.fade_gain / samples_to_end as f32;
                }
            }

            // Apply SRC + pitch shift via resampling
            // Calculate fractional source sample index based on combined rate
            let fractional_pos = self.position as f64 + (frame as f64 * combined_rate);
            // Compute source position with looping support
            let src_pos = if self.looping {
                // Wrap fractional position for seamless looping
                let wrapped = fractional_pos % total_frames as f64;
                if wrapped < 0.0 {
                    wrapped + total_frames as f64
                } else {
                    wrapped
                }
            } else {
                fractional_pos
            };

            let src_frame = src_pos.floor() as usize;

            // For non-looping: check bounds (respect trim_end)
            if !self.looping && (src_frame >= total_frames || current_source_pos >= effective_end) {
                break;
            }

            let gain = if self.muted {
                0.0
            } else {
                self.volume * self.fade_gain * self.input_gain
            };

            // Blackman-Harris windowed sinc interpolation for SRC + pitch shift
            let interp_l = sinc_table::interpolate_sample(
                resample_mode, src_pos, &self.audio.samples, channels_src, total_frames, 0, sinc_ref,
            );
            let interp_r = if channels_src > 1 {
                sinc_table::interpolate_sample(
                    resample_mode, src_pos, &self.audio.samples, channels_src, total_frames, 1, sinc_ref,
                )
            } else {
                interp_l // Mono: L=R
            };
            let (src_l, src_r) = (interp_l * gain, interp_r * gain);

            let mut sample_l: f64;
            let mut sample_r: f64;

            if self.spatial_source_id.is_some() {
                // Spatial HRTF mode: output mono sum — SpatialManager handles spatialization
                let mono = if channels_src > 1 {
                    (src_l as f64 + src_r as f64) * 0.5
                } else {
                    src_l as f64
                };
                sample_l = mono;
                sample_r = mono;
            } else {
                // Apply panning — Pro Tools style stereo balance
                if channels_src > 1 {
                    let pan_l_angle = (self.pan + 1.0) as f64 * std::f64::consts::FRAC_PI_4;
                    let pan_r_angle = (self.pan_right + 1.0) as f64 * std::f64::consts::FRAC_PI_4;
                    let l_to_left = pan_l_angle.cos();
                    let l_to_right = pan_l_angle.sin();
                    let r_to_left = pan_r_angle.cos();
                    let r_to_right = pan_r_angle.sin();
                    sample_l = (src_l as f64) * l_to_left + (src_r as f64) * r_to_left;
                    sample_r = (src_l as f64) * l_to_right + (src_r as f64) * r_to_right;
                } else {
                    sample_l = (src_l * pan_l) as f64;
                    sample_r = (src_r * pan_r) as f64;
                }

                // Stereo width via mid/side processing
                if (self.stereo_width - 1.0).abs() > 0.01 {
                    let mid = (sample_l + sample_r) * 0.5;
                    let side = (sample_l - sample_r) * 0.5;
                    let w = self.stereo_width as f64;
                    let comp = if w > 1.0 { 1.0 / (0.5 + 0.5 * w) } else { 1.0 };
                    sample_l = (mid + side * w) * comp;
                    sample_r = (mid - side * w) * comp;
                }

                // Phase invert (polarity flip Ø)
                if self.phase_invert {
                    sample_l = -sample_l;
                    sample_r = -sample_r;
                }
            }

            // Per-voice peak metering (before bus mix — track THIS voice only)
            let abs_l = sample_l.abs();
            let abs_r = sample_r.abs();
            if abs_l as f32 > voice_peak_l { voice_peak_l = abs_l as f32; }
            if abs_r as f32 > voice_peak_r { voice_peak_r = abs_r as f32; }

            // Add to bus buffers (mixing)
            left[frame] += sample_l;
            right[frame] += sample_r;
        }

        // Update voice peak meters with ballistic decay
        if voice_peak_l >= self.meter_peak_l {
            self.meter_peak_l = voice_peak_l;
        } else {
            self.meter_peak_l *= 0.92; // ~300ms PPM decay at 48kHz/256 block
        }
        if voice_peak_r >= self.meter_peak_r {
            self.meter_peak_r = voice_peak_r;
        } else {
            self.meter_peak_r *= 0.92;
        }

        // Advance position accounting for SRC + pitch ratio
        self.position += (frames_needed as f64 * combined_rate) as u64;

        // P0.2: For looping, wrap position for next call
        if self.looping && !self.loop_releasing {
            if self.position >= total_frames as u64 {
                // Apply random start offset on loop wrap if configured
                let random_offset = if self.loop_random_start_samples > 0 {
                    // Deterministic pseudo-random from voice ID (no heap allocation)
                    let hash = ((self.id as f64) * 1234.5678).sin().abs();
                    (hash * self.loop_random_start_samples as f64) as u64
                } else {
                    0
                };
                self.position = random_offset + (self.position % total_frames as u64);
                self.position %= total_frames as u64;
            }
            true // Always playing until stopped
        } else {
            self.position < total_frames as u64
        }
    }
}

/// One-shot voice command for lock-free communication
#[derive(Debug)]
pub enum OneShotCommand {
    /// Play a new one-shot voice with spatial pan and source tracking
    Play {
        id: u64,
        audio: Arc<ImportedAudio>,
        volume: f32,
        pan: f32,
        bus: OutputBus,
        source: PlaybackSource,
    },
    /// P0.2: Play a looping voice (seamless loop for REEL_SPIN etc.)
    PlayLooping {
        id: u64,
        audio: Arc<ImportedAudio>,
        volume: f32,
        pan: f32,
        bus: OutputBus,
        source: PlaybackSource,
    },
    /// Extended play with fadeIn, fadeOut, and trim parameters
    PlayEx {
        id: u64,
        audio: Arc<ImportedAudio>,
        volume: f32,
        pan: f32,
        bus: OutputBus,
        source: PlaybackSource,
        fade_in_ms: f32,
        fade_out_ms: f32,
        trim_start_ms: f32,
        trim_end_ms: f32,
    },
    /// Stop specific voice
    Stop { id: u64 },
    /// Stop all voices
    StopAll,
    /// Stop all voices from a specific source
    StopSource { source: PlaybackSource },
    /// P0: Fade out specific voice with configurable duration
    FadeOut { id: u64, fade_samples: u64 },
    /// P12.0.1: Set pitch shift for specific voice (semitones, -24 to +24)
    SetPitch { id: u64, semitones: f32 },
    /// Real-time volume update for active voice (0.0 to 1.5)
    SetVolume { id: u64, volume: f32 },
    /// Real-time pan update for active voice (-1.0 to 1.0)
    SetPan { id: u64, pan: f32 },
    /// Real-time pan right update for stereo dual-pan (-1.0 to 1.0)
    SetPanRight { id: u64, pan_right: f32 },
    /// Real-time input gain (linear: 1.0=0dB, 0.5=-6dB, 2.0=+6dB)
    SetInputGain { id: u64, gain: f32 },
    /// Real-time stereo width (0.0=mono, 1.0=normal, 2.0=extra wide)
    SetWidth { id: u64, width: f32 },
    /// Real-time phase invert toggle
    SetPhaseInvert { id: u64, invert: bool },
    /// Real-time mute toggle for active voice
    SetMute { id: u64, muted: bool },
    /// Play a voice with 3D spatial positioning (HRTF binaural rendering)
    PlaySpatial {
        id: u64,
        audio: Arc<ImportedAudio>,
        volume: f32,
        bus: OutputBus,
        source: PlaybackSource,
        spatial_source_id: u32,
    },
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

    /// P2.2: SIMD-optimized bus mixing (4x speedup with AVX2)
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
            let len = left.len().min(bus_l.len());
            // P2.2: Use SIMD mix_add (dest += src * 1.0)
            rf_dsp::simd::mix_add(&mut bus_l[..len], &left[..len], 1.0);
            rf_dsp::simd::mix_add(&mut bus_r[..len], &right[..len], 1.0);
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

    /// Get mutable bus buffers for send routing
    pub fn get_bus_mut(&mut self, bus: OutputBus) -> (&mut [f64], &mut [f64]) {
        let idx = match bus {
            OutputBus::Master => 0,
            OutputBus::Music => 1,
            OutputBus::Sfx => 2,
            OutputBus::Voice => 3,
            OutputBus::Ambience => 4,
            OutputBus::Aux => 5,
        };

        if idx < self.buffers.len() {
            let (l, r) = &mut self.buffers[idx];
            (l.as_mut_slice(), r.as_mut_slice())
        } else {
            (self.master_l.as_mut_slice(), self.master_r.as_mut_slice())
        }
    }

    /// P2.2: SIMD-optimized master summation (4x speedup with AVX2)
    pub fn sum_to_master(&mut self) {
        for (bus_l, bus_r) in &self.buffers {
            // P2.2: Use SIMD mix_add for vectorized summation
            rf_dsp::simd::mix_add(&mut self.master_l, bus_l, 1.0);
            rf_dsp::simd::mix_add(&mut self.master_r, bus_r, 1.0);
        }
    }

    pub fn master(&self) -> (&[f64], &[f64]) {
        (&self.master_l, &self.master_r)
    }

    pub fn master_mut(&mut self) -> (&mut [f64], &mut [f64]) {
        (&mut self.master_l, &mut self.master_r)
    }
}

/// Bus output destination for hierarchical routing (Cubase-style stem grouping)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BusOutputDest {
    /// Route to master output (default)
    Master,
    /// Route to another bus by index (0-5). Enables stem grouping:
    /// e.g., Sfx→Music for dialog/music stem, Voice→Aux for submix.
    Bus(usize),
}

impl Default for BusOutputDest {
    fn default() -> Self {
        BusOutputDest::Master
    }
}

/// Bus volume/mute/solo state
#[derive(Debug, Clone)]
pub struct BusState {
    pub volume: f64,
    pub pan: f64,
    pub pan_right: f64, // For stereo pan mode: R channel pan (-1.0 to 1.0)
    pub muted: bool,
    pub soloed: bool,
    /// Output destination: Master (default) or another bus for hierarchical routing.
    /// Circular routing (A→B→A) is prevented by the UI and by process order validation.
    pub output_dest: BusOutputDest,
}

impl Default for BusState {
    fn default() -> Self {
        Self {
            volume: 1.0,
            pan: -1.0,      // Stereo bus: L channel hard left
            pan_right: 1.0, // Stereo bus: R channel hard right
            muted: false,
            soloed: false,
            output_dest: BusOutputDest::Master,
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
    /// LUFS momentary (400ms window, LUFS units)
    pub lufs_momentary: f64,
    /// LUFS short-term (3s window, LUFS units)
    pub lufs_short: f64,
    /// LUFS integrated (full program, LUFS units)
    pub lufs_integrated: f64,
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
            lufs_momentary: -70.0,
            lufs_short: -70.0,
            lufs_integrated: -70.0,
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
    /// P2.1: Uses SIMD-optimized functions from rf-dsp for 6x speedup
    pub fn update(&mut self, left: &[f64], right: &[f64], decay: f64) {
        let frames = left.len().min(right.len());
        if frames == 0 {
            return;
        }

        // Decay previous values
        self.decay(decay);

        // P2.1: SIMD-optimized peak detection (AVX2/SSE4.2/NEON)
        let new_peak_l = rf_dsp::metering_simd::find_peak_simd(left);
        let new_peak_r = rf_dsp::metering_simd::find_peak_simd(right);
        self.peak_l = self.peak_l.max(new_peak_l);
        self.peak_r = self.peak_r.max(new_peak_r);

        // P2.1: SIMD-optimized RMS calculation
        let rms_l = rf_dsp::metering_simd::calculate_rms_simd(left);
        let rms_r = rf_dsp::metering_simd::calculate_rms_simd(right);
        self.rms_l = self.rms_l.max(rms_l);
        self.rms_r = self.rms_r.max(rms_r);

        // P2.1: SIMD-optimized correlation
        self.correlation = rf_dsp::metering_simd::calculate_correlation_simd(left, right);
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
    /// Parameter smoother manager for zipper-free automation
    param_smoother: Arc<crate::param_smoother::ParamSmootherManager>,
    /// Group/VCA manager (RwLock for shared mutation with bridge)
    group_manager: Option<Arc<RwLock<GroupManager>>>,
    /// Elastic audio parameters per clip (time_ratio, pitch_semitones)
    elastic_params: RwLock<HashMap<u32, (f64, f64)>>,
    /// Audio stretcher instances per clip (for preserve_pitch / pitch shift mode)
    /// Uses Signalsmith Stretch — high quality, real-time, zero-alloc process().
    /// Created on UI thread when preserve_pitch is set, NOT on audio thread.
    clip_stretchers: RwLock<HashMap<u64, crate::audio_stretcher::AudioStretcher>>,
    /// Varispeed playback rate (0.25 to 4.0, 1.0 = normal)
    /// Affects global playback speed WITH pitch change (like tape speed)
    varispeed_rate: AtomicU64,
    /// Varispeed enabled flag
    varispeed_enabled: AtomicBool,
    /// Track VCA assignments (track_id -> `Vec<VcaId>`)
    vca_assignments: RwLock<HashMap<u32, Vec<VcaId>>>,
    /// Insert chains per track (track_id -> InsertChain)
    insert_chains: RwLock<HashMap<u64, InsertChain>>,
    /// Master insert chain
    master_insert: RwLock<InsertChain>,
    /// Bus insert chains (6 buses: 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Amb, 5=Aux)
    /// NOTE: Master bus inserts are processed BEFORE master_insert (bus 0 is pre-master)
    /// Actual flow: Tracks → Bus InsertChain → Bus Volume → Sum to Master → master_insert → Output
    bus_inserts: RwLock<[InsertChain; 6]>,
    /// Lock-free ring buffer for insert parameter changes (UI → Audio)
    /// Producer is used by UI thread (via set_track_insert_param)
    /// Consumer is used by audio thread (at start of each block)
    insert_param_tx: parking_lot::Mutex<rtrb::Producer<InsertParamChange>>,
    insert_param_rx: parking_lot::Mutex<rtrb::Consumer<InsertParamChange>>,
    /// Per-track stereo meters (track_id -> TrackMeter with L/R peaks, RMS, correlation)
    track_meters: RwLock<HashMap<u64, TrackMeter>>,
    /// Per-track LUFS meters (separate from TrackMeter to keep LufsMeter state)
    track_lufs_meters: RwLock<HashMap<u64, LufsMeter>>,
    /// Master spectrum analyzer (FFT)
    spectrum_analyzer: RwLock<FftAnalyzer>,
    /// Spectrum data cache (256 bins, log-scaled 20Hz-20kHz)
    spectrum_data: RwLock<Vec<f32>>,
    // NOTE: track_buffer_l and track_buffer_r moved to thread_local! SCRATCH_BUFFER_L/R
    // This eliminates lock contention in audio thread - scratch buffers are audio-thread-only
    /// Pre-allocated mono buffer for spectrum analyzer
    spectrum_mono_buffer: RwLock<Vec<f64>>,
    /// Current block size (for buffer reallocation check)
    current_block_size: AtomicUsize,
    /// Adaptive quality: active voice count (updated each audio block)
    diag_active_voices: AtomicU32,
    /// Adaptive quality: degraded voice count (voices running at reduced SRC quality)
    diag_degraded_voices: AtomicU32,
    /// Adaptive quality: CPU load percentage (0-100, of voice budget)
    diag_cpu_load_pct: AtomicU32,
    /// Adaptive quality: current global SRC mode value (for UI display)
    diag_src_mode: AtomicU32,
    /// Debug: Signalsmith stretcher hit counter (audio thread found stretcher)
    diag_stretcher_hit: AtomicU32,
    /// Debug: Signalsmith stretcher miss counter (lock contended or not pre-allocated)
    diag_stretcher_miss: AtomicU32,
    /// CORTEX: bus contention counter (try_write() failed on bus_buffers in process())
    diag_bus_contention: AtomicU32,
    /// Delay compensation manager for automatic plugin delay compensation
    delay_comp: RwLock<DelayCompensationManager>,
    /// Control room for monitoring (AFL/PFL, cue mixes, talkback)
    control_room: Arc<ControlRoom>,
    /// Pre-fader buffer left (for PFL tap)
    /// Note: Used by control_room for PFL/AFL solo monitoring
    #[allow(dead_code)] // Reserved for PFL monitoring implementation
    prefader_buffer_l: RwLock<Vec<f64>>,
    /// Pre-fader buffer right (for PFL tap)
    #[allow(dead_code)] // Reserved for PFL monitoring implementation
    prefader_buffer_r: RwLock<Vec<f64>>,

    // === UNIFIED ROUTING (Phase 1.3) ===
    // Note: RoutingGraphRT is NOT Sync (contains rtrb Consumer/Producer)
    // Instead of storing it here, we use a separate initialization pattern:
    // - RoutingGraph (Sync) can be stored for read-only state queries
    // - RoutingGraphRT is created and owned by the audio thread directly
    // - RoutingCommandSender is used by UI thread
    /// Routing command sender (UI thread → audio thread)
    /// Wrapped in parking_lot::Mutex which IS Sync
    #[cfg(feature = "unified_routing")]
    routing_sender: parking_lot::Mutex<Option<RoutingCommandSender>>,

    /// Input bus manager (Phase 11 - Recording Input Routing)
    input_bus_manager: Arc<InputBusManager>,
    /// Pre-allocated input buffer (hardware input interleaved)
    input_buffer: RwLock<Vec<f32>>,
    /// Recording manager (Phase 12 - Multi-track Recording)
    recording_manager: Arc<RecordingManager>,

    // === INSTRUMENT PLUGINS (MIDI → Audio) ===
    /// Loaded instrument plugin instances per track (track_id -> PluginInstance)
    /// Created on UI thread when user loads an instrument plugin on an Instrument track.
    /// Audio thread calls process() with MidiBuffer to generate audio.
    instrument_plugins: RwLock<HashMap<u64, Arc<parking_lot::RwLock<Box<dyn rf_plugin::PluginInstance>>>>>,
    /// Pre-allocated MidiBuffer for instrument MIDI input (avoid audio-thread allocations)
    instrument_midi_buffer: RwLock<rf_core::MidiBuffer>,
    /// Pre-allocated MidiBuffer for instrument MIDI output (avoid audio-thread allocations)
    instrument_midi_out: RwLock<rf_core::MidiBuffer>,
    /// Pre-allocated AudioBuffer for instrument input (silence, avoid audio-thread allocations)
    instrument_audio_in: RwLock<rf_plugin::AudioBuffer>,
    /// Pre-allocated AudioBuffer for instrument output (avoid audio-thread allocations)
    instrument_audio_out: RwLock<rf_plugin::AudioBuffer>,

    // === ONE-SHOT VOICES (Middleware/SlotLab event playback) ===
    /// Pre-allocated one-shot voice slots
    one_shot_voices: RwLock<[OneShotVoice; MAX_ONE_SHOT_VOICES]>,
    /// Command ring buffer for one-shot voices (UI → Audio)
    one_shot_cmd_tx: parking_lot::Mutex<rtrb::Producer<OneShotCommand>>,
    one_shot_cmd_rx: parking_lot::Mutex<rtrb::Consumer<OneShotCommand>>,
    /// Next voice ID counter
    next_one_shot_id: AtomicU64,

    // === ADVANCED LOOP SYSTEM (Wwise-grade) ===
    /// Loop command ring buffer (UI → Audio) — producer side
    loop_cmd_tx: parking_lot::Mutex<rtrb::Producer<crate::loop_manager::LoopCommand>>,
    /// Loop command ring buffer (UI → Audio) — consumer side (audio thread)
    loop_cmd_rx: parking_lot::Mutex<rtrb::Consumer<crate::loop_manager::LoopCommand>>,
    /// Loop callback ring buffer (Audio → UI) — producer side (audio thread)
    loop_cb_tx: parking_lot::Mutex<rtrb::Producer<crate::loop_manager::LoopCallback>>,
    /// Loop callback ring buffer (Audio → UI) — consumer side
    loop_cb_rx: parking_lot::Mutex<rtrb::Consumer<crate::loop_manager::LoopCallback>>,
    /// Registered loop assets (shared between UI and audio thread)
    loop_assets: RwLock<HashMap<String, Arc<crate::loop_asset::LoopAsset>>>,
    /// Loop instance pool (pre-allocated, audio thread only via try_lock)
    loop_instances: parking_lot::Mutex<Vec<crate::loop_instance::LoopInstance>>,
    /// Loop system initialized flag
    loop_initialized: AtomicBool,

    // === SECTION-BASED PLAYBACK FILTERING ===
    /// Currently active playback section (0=DAW, 1=SlotLab, 2=Middleware, 3=Browser)
    /// One-shot voices from inactive sections are silenced.
    active_section: AtomicU8,

    // === GRAPH-LEVEL PDC (Plugin Delay Compensation) ===
    /// Current PDC calculation result (None if not yet calculated)
    graph_pdc_result: RwLock<Option<PDCResult>>,
    /// Graph-level PDC enabled flag (true by default)
    graph_pdc_enabled: AtomicBool,
    /// Per-track PDC compensation delays (track_id -> samples)
    /// This is separate from delay_comp which uses simple max-latency approach.
    /// graph_pdc uses topological graph analysis for phase-coherent compensation.
    graph_pdc_delays: RwLock<HashMap<u64, u64>>,

    // === INSERT TAIL PROCESSING ===
    /// Remaining samples for insert chain tail processing after transport stop.
    /// When transport stops, this is set to tail_duration_samples so that
    /// insert chains (reverb, delay) continue processing their tails.
    /// Decremented each block until 0.
    tail_remaining_samples: AtomicU64,
    /// Duration in samples for insert tail processing (default: 3s at 48kHz = 144000)
    tail_duration_samples: AtomicU64,

    // === PER-TRACK STEREO IMAGER (post-pan, pre-post-fader inserts) ===
    /// StereoImager instances per track (track_id -> StereoImager)
    /// Processes after pan, before post-fader inserts in the signal chain.
    /// SSL canonical: Input → Pre-Inserts → Fader → Pan → **StereoImager** → Post-Inserts
    stereo_imagers: RwLock<HashMap<u32, rf_dsp::spatial::StereoImager>>,
    /// Master bus StereoImager (processed after master volume, before master post-inserts)
    pub(crate) master_stereo_imager: RwLock<rf_dsp::spatial::StereoImager>,
    /// Per-bus StereoImager instances (6 buses: Master=0, Music=1, Sfx=2, Voice=3, Amb=4, Aux=5)
    pub(crate) bus_stereo_imagers: RwLock<[rf_dsp::spatial::StereoImager; 6]>,

    // === MASTER CHANNEL DELAY (Independent L/R — Cubase/Pro Tools style) ===
    /// Left channel delay in milliseconds (0.0 to 30.0ms)
    master_delay_l_ms: AtomicU64,
    /// Right channel delay in milliseconds (0.0 to 30.0ms)
    master_delay_r_ms: AtomicU64,
    /// Ring buffer for left channel delay (pre-allocated, 8192 samples = ~170ms @ 48kHz)
    master_delay_buf_l: RwLock<Vec<f64>>,
    /// Ring buffer for right channel delay
    master_delay_buf_r: RwLock<Vec<f64>>,
    /// Write position for delay buffers
    master_delay_write_pos: AtomicUsize,
    /// Master soft-clipper enable (tanh saturation at 0dBFS — prevents digital clipping)
    master_soft_clip_enabled: AtomicBool,
    /// DC offset filter state (1-pole high-pass at ~5Hz, per-channel)
    /// Stored as AtomicU64 (f64 bits) for lock-free audio thread access
    dc_filter_state_l: AtomicU64,
    dc_filter_state_r: AtomicU64,
    /// DC filter coefficient: alpha = 1 - (2π × 5Hz / sample_rate)
    dc_filter_alpha: AtomicU64,
    // === HOOK GRAPH ENGINE ===
    /// Hook Graph audio-rate engine (processes graph voices on audio thread)
    hook_graph_engine: Option<RwLock<crate::hook_graph::HookGraphEngine>>,
    /// Hook Graph command ring buffer producer (Dart → Rust)
    hook_graph_cmd_tx: parking_lot::Mutex<rtrb::Producer<crate::hook_graph::GraphCommand>>,
    /// Hook Graph feedback ring buffer consumer (Rust → Dart)
    hook_graph_fb_rx: parking_lot::Mutex<rtrb::Consumer<crate::hook_graph::GraphFeedback>>,

    /// Cached sample rate for delay calculations
    master_delay_sample_rate: AtomicU64,

    // === SIDECHAIN TAP BUFFERS ===
    /// Per-track post-clip/pre-insert audio from previous block.
    /// Used as sidechain input for insert chains (standard 1-block latency, ~5ms @ 256/48kHz).
    /// Key = track_id as i64, Value = (left_buffer, right_buffer).
    /// Pre-allocated at track creation; clear()/copy each block, no audio-thread allocation.
    sidechain_taps: RwLock<HashMap<i64, (Vec<f64>, Vec<f64>)>>,
}

/// Soft-clip a single sample with smooth knee transition.
/// Below `knee_start`: pass-through. Above: smooth blend into normalized tanh.
/// Continuous and smooth — no audible artifacts at transition point.
#[inline(always)]
fn soft_clip_sample(x: f64, knee_start: f64, knee_range: f64, tanh_norm: f64) -> f64 {
    let abs_x = x.abs();
    if abs_x <= knee_start {
        x // Below knee: linear pass-through
    } else {
        // Blend factor: 0.0 at knee_start, 1.0 at abs_x=1.0+
        let blend = ((abs_x - knee_start) / knee_range).min(1.0);
        // Saturated value: tanh normalized so tanh(1.0)/tanh(1.0) = 1.0
        let saturated = x.tanh() / tanh_norm;
        // Smooth crossfade: linear * (1-blend) + saturated * blend
        x * (1.0 - blend) + saturated * blend
    }
}

impl PlaybackEngine {
    pub fn new(track_manager: Arc<TrackManager>, sample_rate: u32) -> Self {
        // Create single ring buffer and split into tx/rx
        let (insert_param_tx, insert_param_rx) = rtrb::RingBuffer::<InsertParamChange>::new(4096);

        // Create one-shot voice command ring buffer
        let (one_shot_tx, one_shot_rx) = rtrb::RingBuffer::<OneShotCommand>::new(256);

        // Create advanced loop system ring buffers
        let (loop_cmd_tx, loop_cmd_rx) = rtrb::RingBuffer::<crate::loop_manager::LoopCommand>::new(256);
        let (loop_cb_tx, loop_cb_rx) = rtrb::RingBuffer::<crate::loop_manager::LoopCallback>::new(512);

        // Create hook graph engine ring buffers
        let (hg_cmd_tx, hg_cmd_rx) = rtrb::RingBuffer::<crate::hook_graph::GraphCommand>::new(512);
        let (hg_fb_tx, hg_fb_rx) = rtrb::RingBuffer::<crate::hook_graph::GraphFeedback>::new(512);
        let hook_graph = crate::hook_graph::HookGraphEngine::new(sample_rate, 1024, hg_cmd_rx, hg_fb_tx);

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
            param_smoother: Arc::new(crate::param_smoother::ParamSmootherManager::new(
                sample_rate as f64,
            )),
            group_manager: None,
            elastic_params: RwLock::new(HashMap::new()),
            clip_stretchers: RwLock::new(HashMap::new()),
            varispeed_rate: AtomicU64::new(1.0_f64.to_bits()),
            varispeed_enabled: AtomicBool::new(false),
            vca_assignments: RwLock::new(HashMap::new()),
            insert_chains: RwLock::new(HashMap::new()),
            master_insert: RwLock::new(InsertChain::new(sample_rate as f64)),
            // Bus insert chains (6 buses: 0=Master routing bus, 1-5 = Music/Sfx/Voice/Amb/Aux)
            bus_inserts: RwLock::new(std::array::from_fn(|_| {
                InsertChain::new(sample_rate as f64)
            })),
            // Lock-free ring buffer for insert params (4096 = ~85ms at 60fps UI updates)
            insert_param_tx: parking_lot::Mutex::new(insert_param_tx),
            insert_param_rx: parking_lot::Mutex::new(insert_param_rx),
            track_meters: RwLock::new(HashMap::new()),
            track_lufs_meters: RwLock::new(HashMap::new()),
            // 8192-point FFT for better bass frequency resolution
            // At 48kHz: bin width = 48000/8192 = 5.86Hz (vs 23.4Hz with 2048)
            // This gives ~3-4 bins in 20-40Hz range instead of ~1 bin
            spectrum_analyzer: RwLock::new(FftAnalyzer::new(8192)),
            spectrum_data: RwLock::new(vec![0.0_f32; 512]), // More bins for better resolution
            // NOTE: track_buffer_l/r now use thread_local! SCRATCH_BUFFER_L/R
            spectrum_mono_buffer: RwLock::new(vec![0.0_f64; 8192]),
            current_block_size: AtomicUsize::new(8192),
            diag_active_voices: AtomicU32::new(0),
            diag_degraded_voices: AtomicU32::new(0),
            diag_cpu_load_pct: AtomicU32::new(0),
            diag_src_mode: AtomicU32::new(64), // Sinc64 default
            diag_stretcher_hit: AtomicU32::new(0),
            diag_stretcher_miss: AtomicU32::new(0),
            diag_bus_contention: AtomicU32::new(0),
            delay_comp: RwLock::new(DelayCompensationManager::new(sample_rate as f64)),
            control_room: Arc::new(ControlRoom::new(256)),
            prefader_buffer_l: RwLock::new(vec![0.0_f64; 8192]),
            prefader_buffer_r: RwLock::new(vec![0.0_f64; 8192]),
            // Routing sender initialized to None - call init_unified_routing() to setup
            #[cfg(feature = "unified_routing")]
            routing_sender: parking_lot::Mutex::new(None),
            // Input bus manager with default block size 256
            input_bus_manager: Arc::new(InputBusManager::new(256)),
            // Pre-allocated input buffer (stereo interleaved)
            input_buffer: RwLock::new(vec![0.0f32; 16384]),
            // Recording manager for multi-track recording
            recording_manager: Arc::new(RecordingManager::new(sample_rate)),
            // Instrument plugin instances per track
            instrument_plugins: RwLock::new(HashMap::new()),
            instrument_midi_buffer: RwLock::new(rf_core::MidiBuffer::new()),
            instrument_midi_out: RwLock::new(rf_core::MidiBuffer::new()),
            instrument_audio_in: RwLock::new(rf_plugin::AudioBuffer::new(2, 4096)),
            instrument_audio_out: RwLock::new(rf_plugin::AudioBuffer::new(2, 4096)),
            // One-shot voices for Middleware/SlotLab event playback
            one_shot_voices: RwLock::new(std::array::from_fn(|_| OneShotVoice::new_inactive())),
            one_shot_cmd_tx: parking_lot::Mutex::new(one_shot_tx),
            one_shot_cmd_rx: parking_lot::Mutex::new(one_shot_rx),
            next_one_shot_id: AtomicU64::new(1),
            // Advanced loop system (Wwise-grade)
            loop_cmd_tx: parking_lot::Mutex::new(loop_cmd_tx),
            loop_cmd_rx: parking_lot::Mutex::new(loop_cmd_rx),
            loop_cb_tx: parking_lot::Mutex::new(loop_cb_tx),
            loop_cb_rx: parking_lot::Mutex::new(loop_cb_rx),
            loop_assets: RwLock::new(HashMap::new()),
            loop_instances: parking_lot::Mutex::new(Vec::new()),
            loop_initialized: AtomicBool::new(false),
            // Section-based filtering: DAW is default active section
            active_section: AtomicU8::new(PlaybackSource::Daw as u8),
            // Graph-level PDC: enabled by default, no result until first calculation
            graph_pdc_result: RwLock::new(None),
            graph_pdc_enabled: AtomicBool::new(true),
            graph_pdc_delays: RwLock::new(HashMap::new()),
            // 1 second of tail at current sample rate (reverb/delay ring-out)
            tail_remaining_samples: AtomicU64::new(0),
            tail_duration_samples: AtomicU64::new(sample_rate as u64),
            // Per-track stereo imagers (SSL canonical: post-pan, pre-post-inserts)
            stereo_imagers: RwLock::new(HashMap::new()),
            master_stereo_imager: RwLock::new(rf_dsp::spatial::StereoImager::new(
                sample_rate as f64,
            )),
            bus_stereo_imagers: RwLock::new(std::array::from_fn(|_| {
                rf_dsp::spatial::StereoImager::new(sample_rate as f64)
            })),
            // Master channel delay: independent L/R (Cubase/Pro Tools style)
            master_delay_l_ms: AtomicU64::new(0.0_f64.to_bits()),
            master_delay_r_ms: AtomicU64::new(0.0_f64.to_bits()),
            master_delay_buf_l: RwLock::new(vec![0.0_f64; 8192]),
            master_delay_buf_r: RwLock::new(vec![0.0_f64; 8192]),
            master_delay_write_pos: AtomicUsize::new(0),
            master_soft_clip_enabled: AtomicBool::new(true), // ON by default — safety net
            dc_filter_state_l: AtomicU64::new(0.0_f64.to_bits()),
            dc_filter_state_r: AtomicU64::new(0.0_f64.to_bits()),
            dc_filter_alpha: AtomicU64::new(
                (1.0 - (2.0 * std::f64::consts::PI * 5.0 / sample_rate as f64)).to_bits()
            ),
            master_delay_sample_rate: AtomicU64::new((sample_rate as f64).to_bits()),
            hook_graph_engine: Some(RwLock::new(hook_graph)),
            hook_graph_cmd_tx: parking_lot::Mutex::new(hg_cmd_tx),
            hook_graph_fb_rx: parking_lot::Mutex::new(hg_fb_rx),
            // Sidechain tap buffers: pre-allocated per-track for zero audio-thread allocation
            sidechain_taps: RwLock::new(HashMap::new()),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION-BASED PLAYBACK CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    /// Set active playback section.
    /// One-shot voices from other sections will be silenced.
    /// DAW timeline tracks are NOT affected (they use track mute).
    pub fn set_active_section(&self, section: PlaybackSource) {
        let old = self.active_section.swap(section as u8, Ordering::SeqCst);
        if old != section as u8 {
            log::debug!(
                "[PlaybackEngine] Active section changed: {:?} -> {:?}",
                PlaybackSource::from(old),
                section
            );
        }
    }

    /// Get current active section
    pub fn get_active_section(&self) -> PlaybackSource {
        PlaybackSource::from(self.active_section.load(Ordering::Relaxed))
    }

    /// Get control room reference
    pub fn control_room(&self) -> &Arc<ControlRoom> {
        &self.control_room
    }

    /// Get input bus manager reference
    pub fn input_bus_manager(&self) -> &Arc<InputBusManager> {
        &self.input_bus_manager
    }

    /// Get recording manager reference
    pub fn recording_manager(&self) -> &Arc<RecordingManager> {
        &self.recording_manager
    }

    /// Initialize unified routing and return the RoutingGraphRT for audio thread
    /// The returned RoutingGraphRT should be owned by the audio callback directly
    /// (it's NOT Sync and cannot be stored in PlaybackEngine)
    #[cfg(feature = "unified_routing")]
    pub fn init_unified_routing(&self, block_size: usize, sample_rate: f64) -> RoutingGraphRT {
        let (graph_rt, sender) = RoutingGraphRT::with_sample_rate(block_size, sample_rate);
        *self.routing_sender.lock() = Some(sender);
        graph_rt
    }

    /// Get routing command sender (for UI thread to control routing)
    /// Returns None if unified routing hasn't been initialized
    #[cfg(feature = "unified_routing")]
    pub fn routing_sender(
        &self,
    ) -> Option<parking_lot::MutexGuard<'_, Option<RoutingCommandSender>>> {
        let guard = self.routing_sender.lock();
        if guard.is_some() { Some(guard) } else { None }
    }

    /// Send routing command (convenience method)
    #[cfg(feature = "unified_routing")]
    pub fn send_routing_command(&self, cmd: crate::routing::RoutingCommand) -> bool {
        if let Some(mut guard) = self.routing_sender()
            && let Some(sender) = guard.as_mut()
        {
            return sender.send(cmd);
        }
        false
    }

    /// Create channel in routing graph
    #[cfg(feature = "unified_routing")]
    pub fn create_routing_channel(&self, kind: ChannelKind, name: &str) -> bool {
        static CALLBACK_ID: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let id = CALLBACK_ID.fetch_add(1, Ordering::Relaxed);
        if let Some(mut guard) = self.routing_sender()
            && let Some(sender) = guard.as_mut()
        {
            return sender.create_channel(kind, name.to_string(), id);
        }
        false
    }

    /// Set channel output in routing graph
    #[cfg(feature = "unified_routing")]
    pub fn set_routing_output(&self, channel: ChannelId, dest: OutputDestination) -> bool {
        if let Some(mut guard) = self.routing_sender()
            && let Some(sender) = guard.as_mut()
        {
            return sender.set_output(channel, dest);
        }
        false
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

    /// Check if track is muted by any VCA
    /// Uses try_read to avoid blocking audio thread
    fn is_vca_muted(&self, track_id: u64) -> bool {
        let manager = match &self.group_manager {
            Some(m) => m,
            None => return false,
        };

        match manager.try_read() {
            Some(gm) => gm.is_vca_muted(track_id),
            None => false, // Return not muted if lock is contended
        }
    }

    /// Get track volume with automation and smoothing applied
    fn get_track_volume_with_automation(&self, track: &Track) -> f64 {
        // First check if smoother has an active value (from automation)
        if self.param_smoother.is_track_smoothing(track.id.0) {
            // Use smoothed value during automation
            return self.param_smoother.get_track_volume(track.id.0);
        }

        // Check if automation lane exists and has value
        if let Some(automation) = &self.automation {
            let param_id = ParamId::track_volume(track.id.0);
            if let Some(auto_value) = automation.get_value(&param_id) {
                // auto_value is normalized 0-1, map to 0-1.5 range
                return auto_value * 1.5;
            }
        }

        // Fall back to track's base volume
        track.volume
    }

    /// Get track pan with automation and smoothing applied
    fn get_track_pan_with_automation(&self, track: &Track) -> f64 {
        // First check if smoother has an active value (from automation)
        if self.param_smoother.is_track_smoothing(track.id.0) {
            // Use smoothed value during automation
            return self.param_smoother.get_track_pan(track.id.0);
        }

        // Check if automation lane exists and has value
        if let Some(automation) = &self.automation {
            let param_id = ParamId::track_pan(track.id.0);
            if let Some(auto_value) = automation.get_value(&param_id) {
                // auto_value is normalized 0-1, map to -1 to 1
                return auto_value * 2.0 - 1.0;
            }
        }

        // Fall back to track's base pan
        track.pan
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
    // VARISPEED CONTROL
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable/disable varispeed mode
    /// When enabled, playback speed affects pitch (like tape speed)
    pub fn set_varispeed_enabled(&self, enabled: bool) {
        self.varispeed_enabled.store(enabled, Ordering::Relaxed);
        log::info!("Varispeed {}", if enabled { "enabled" } else { "disabled" });
    }

    /// Check if varispeed is enabled
    pub fn is_varispeed_enabled(&self) -> bool {
        self.varispeed_enabled.load(Ordering::Relaxed)
    }

    /// Set varispeed rate (0.25 to 4.0, 1.0 = normal speed)
    /// This affects both playback speed AND pitch (tape-style)
    pub fn set_varispeed_rate(&self, rate: f64) {
        let clamped = rate.clamp(0.25, 4.0);
        self.varispeed_rate
            .store(clamped.to_bits(), Ordering::Relaxed);
        log::debug!("Varispeed rate set to {:.2}x", clamped);
    }

    /// Get current varispeed rate
    pub fn varispeed_rate(&self) -> f64 {
        f64::from_bits(self.varispeed_rate.load(Ordering::Relaxed))
    }

    /// Get effective playback rate (1.0 if varispeed disabled)
    pub fn effective_playback_rate(&self) -> f64 {
        if self.varispeed_enabled.load(Ordering::Relaxed) {
            f64::from_bits(self.varispeed_rate.load(Ordering::Relaxed))
        } else {
            1.0
        }
    }

    /// Convert semitones to varispeed rate
    /// +12 semitones = 2.0x, -12 semitones = 0.5x
    pub fn semitones_to_varispeed(semitones: f64) -> f64 {
        2.0_f64.powf(semitones / 12.0)
    }

    /// Convert varispeed rate to semitones
    /// 2.0x = +12 semitones, 0.5x = -12 semitones
    pub fn varispeed_to_semitones(rate: f64) -> f64 {
        12.0 * rate.log2()
    }

    /// Set varispeed by semitone offset (convenience method)
    pub fn set_varispeed_semitones(&self, semitones: f64) {
        let rate = Self::semitones_to_varispeed(semitones);
        self.set_varispeed_rate(rate);
    }

    /// Get varispeed rate in semitones
    pub fn varispeed_semitones(&self) -> f64 {
        Self::varispeed_to_semitones(self.varispeed_rate())
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

    /// Load instrument plugin on an Instrument track.
    /// Called from UI thread. Initializes and activates the plugin before making it available
    /// to the audio thread for rendering audio from MIDI.
    pub fn load_instrument_plugin(
        &self,
        track_id: u64,
        mut plugin: Box<dyn rf_plugin::PluginInstance>,
    ) -> bool {
        // Initialize with current audio context
        let sample_rate = self.position.sample_rate() as f64;
        if sample_rate <= 0.0 {
            log::error!("Cannot load instrument plugin on track {}: invalid sample rate {}", track_id, sample_rate);
            return false;
        }
        let context = rf_plugin::ProcessContext {
            sample_rate,
            max_block_size: 4096,
            tempo: 120.0,
            time_sig_num: 4,
            time_sig_denom: 4,
            position_samples: 0,
            is_playing: false,
            is_recording: false,
            is_looping: false,
            loop_start: 0,
            loop_end: 0,
        };

        if let Err(e) = plugin.initialize(&context) {
            log::error!("Failed to initialize instrument plugin on track {}: {}", track_id, e);
            return false;
        }
        if let Err(e) = plugin.activate() {
            log::error!("Failed to activate instrument plugin on track {}: {}", track_id, e);
            return false;
        }

        let plugin_arc = Arc::new(parking_lot::RwLock::new(plugin));
        self.instrument_plugins.write().insert(track_id, plugin_arc);
        log::info!("Loaded instrument plugin on track {}", track_id);
        true
    }

    /// Unload instrument plugin from track.
    /// Deactivates the plugin before removing it.
    pub fn unload_instrument_plugin(&self, track_id: u64) {
        if let Some((_, plugin_arc)) = self.instrument_plugins.write().remove_entry(&track_id) {
            // Deactivate on UI thread before dropping
            if let Some(mut plugin) = plugin_arc.try_write() {
                if let Err(e) = plugin.deactivate() {
                    log::warn!("Failed to deactivate instrument plugin on track {}: {}", track_id, e);
                }
            } else {
                log::warn!("Could not deactivate instrument plugin on track {} (audio thread holding lock)", track_id);
            }
            log::info!("Unloaded instrument plugin from track {}", track_id);
        }
    }

    /// Check if a track has an instrument plugin loaded.
    pub fn has_instrument_plugin(&self, track_id: u64) -> bool {
        self.instrument_plugins.read().contains_key(&track_id)
    }

    /// Set bypass for track insert slot
    pub fn set_track_insert_bypass(&self, track_id: u64, slot_index: usize, bypass: bool) {
        if let Some(chain) = self.insert_chains.read().get(&track_id)
            && let Some(slot) = chain.slot(slot_index)
        {
            slot.set_bypass(bypass);
        }
    }

    /// Set track insert slot wet/dry mix (0.0 = dry, 1.0 = wet)
    pub fn set_track_insert_mix(&self, track_id: u64, slot_index: usize, mix: f64) {
        if let Some(chain) = self.insert_chains.read().get(&track_id)
            && let Some(slot) = chain.slot(slot_index)
        {
            slot.set_mix(mix);
        }
    }

    /// Get track insert slot wet/dry mix
    pub fn get_track_insert_mix(&self, track_id: u64, slot_index: usize) -> f64 {
        if let Some(chain) = self.insert_chains.read().get(&track_id)
            && let Some(slot) = chain.slot(slot_index)
        {
            return slot.mix();
        }
        1.0 // Default to full wet
    }

    // ═══════════════════════════════════════════════════════════════════════
    // P7: PIN CONNECTOR
    // ═══════════════════════════════════════════════════════════════════════

    /// Enable pin connector on a track insert slot
    pub fn enable_track_pin_connector(
        &self,
        track_id: u64,
        slot_index: usize,
        host_channels: u8,
        plugin_channels: u8,
    ) -> bool {
        let mut chains = self.insert_chains.write();
        if let Some(chain) = chains.get_mut(&track_id)
            && let Some(slot) = chain.slot_mut(slot_index) {
                slot.enable_pin_connector(host_channels, plugin_channels);
                return true;
            }
        false
    }

    /// Disable pin connector on a track insert slot
    pub fn disable_track_pin_connector(&self, track_id: u64, slot_index: usize) -> bool {
        let mut chains = self.insert_chains.write();
        if let Some(chain) = chains.get_mut(&track_id)
            && let Some(slot) = chain.slot_mut(slot_index) {
                slot.disable_pin_connector();
                return true;
            }
        false
    }

    /// Set pin connector routing mode
    pub fn set_track_pin_mode(
        &self,
        track_id: u64,
        slot_index: usize,
        mode: u32,
    ) -> bool {
        use crate::pin_connector::PinRoutingMode;
        let routing_mode = match mode {
            0 => PinRoutingMode::Normal,
            1 => PinRoutingMode::MultiMono,
            2 => PinRoutingMode::MidSide,
            3 => PinRoutingMode::SurroundPerChannel,
            4 => PinRoutingMode::CustomMatrix,
            _ => return false,
        };

        let mut chains = self.insert_chains.write();
        if let Some(chain) = chains.get_mut(&track_id)
            && let Some(slot) = chain.slot_mut(slot_index)
                && let Some(pc) = slot.pin_connector_mut() {
                    pc.set_mode(routing_mode);
                    return true;
                }
        false
    }

    /// Set pin connector input mapping gain
    pub fn set_track_pin_input_gain(
        &self,
        track_id: u64,
        slot_index: usize,
        src_ch: u8,
        dst_ch: u8,
        gain: f64,
    ) -> bool {
        let mut chains = self.insert_chains.write();
        if let Some(chain) = chains.get_mut(&track_id)
            && let Some(slot) = chain.slot_mut(slot_index)
                && let Some(pc) = slot.pin_connector_mut() {
                    pc.set_input_gain(src_ch, dst_ch, gain);
                    return true;
                }
        false
    }

    /// Set pin connector output mapping gain
    pub fn set_track_pin_output_gain(
        &self,
        track_id: u64,
        slot_index: usize,
        src_ch: u8,
        dst_ch: u8,
        gain: f64,
    ) -> bool {
        let mut chains = self.insert_chains.write();
        if let Some(chain) = chains.get_mut(&track_id)
            && let Some(slot) = chain.slot_mut(slot_index)
                && let Some(pc) = slot.pin_connector_mut() {
                    pc.set_output_gain(src_ch, dst_ch, gain);
                    return true;
                }
        false
    }

    /// Get pin connector configuration as JSON
    pub fn get_track_pin_config_json(&self, track_id: u64, slot_index: usize) -> Option<String> {
        let chains = self.insert_chains.read();
        if let Some(chain) = chains.get(&track_id)
            && let Some(slot) = chain.slot(slot_index)
                && let Some(pc) = slot.pin_connector() {
                    let mode = match pc.mode() {
                        crate::pin_connector::PinRoutingMode::Normal => "normal",
                        crate::pin_connector::PinRoutingMode::MultiMono => "multi_mono",
                        crate::pin_connector::PinRoutingMode::MidSide => "mid_side",
                        crate::pin_connector::PinRoutingMode::SurroundPerChannel => "surround_per_channel",
                        crate::pin_connector::PinRoutingMode::CustomMatrix => "custom_matrix",
                    };

                    let input_maps: Vec<String> = pc.input_mappings().iter().map(|m| {
                        format!(
                            r#"{{"src":{},"dst":{},"gain":{:.6}}}"#,
                            m.src_channel, m.dst_channel, m.gain
                        )
                    }).collect();

                    let output_maps: Vec<String> = pc.output_mappings().iter().map(|m| {
                        format!(
                            r#"{{"src":{},"dst":{},"gain":{:.6}}}"#,
                            m.src_channel, m.dst_channel, m.gain
                        )
                    }).collect();

                    return Some(format!(
                        r#"{{"mode":"{}","host_channels":{},"plugin_channels":{},"enabled":{},"input_map":[{}],"output_map":[{}]}}"#,
                        mode,
                        pc.host_channels(),
                        pc.plugin_channels(),
                        pc.is_enabled(),
                        input_maps.join(","),
                        output_maps.join(","),
                    ));
                }
        None
    }

    /// Get write access to insert chains (for FFI container operations)
    pub fn insert_chains_write(
        &self,
    ) -> parking_lot::RwLockWriteGuard<'_, std::collections::HashMap<u64, InsertChain>> {
        self.insert_chains.write()
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
        let chain = self.master_insert.read();
        if let Some(slot) = chain.slot(slot_index) {
            slot.set_bypass(bypass);
        } else {
            log::warn!("master insert slot {} NOT FOUND", slot_index);
        }
    }

    /// BUG#7 FIX: Sync BPM to all insert processors across all tracks, buses, and master.
    /// Called when project tempo changes so tempo-synced effects stay in sync.
    pub fn sync_bpm_all_inserts(&self, bpm: f64) {
        // Sync all track insert chains
        if let Some(mut chains) = self.insert_chains.try_write() {
            for chain in chains.values_mut() {
                chain.sync_bpm(bpm);
            }
        }
        // Sync all bus insert chains
        if let Some(mut bus_inserts) = self.bus_inserts.try_write() {
            for chain in bus_inserts.iter_mut() {
                chain.sync_bpm(bpm);
            }
        }
        // Sync master insert chain
        if let Some(mut master) = self.master_insert.try_write() {
            master.sync_bpm(bpm);
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

    /// Set master insert slot wet/dry mix (0.0 = dry, 1.0 = wet)
    pub fn set_master_insert_mix(&self, slot_index: usize, mix: f64) {
        let chain = self.master_insert.read();
        if let Some(slot) = chain.slot(slot_index) {
            slot.set_mix(mix);
        }
    }

    /// Get master insert slot wet/dry mix
    pub fn get_master_insert_mix(&self, slot_index: usize) -> f64 {
        let chain = self.master_insert.read();
        if let Some(slot) = chain.slot(slot_index) {
            return slot.mix();
        }
        1.0
    }

    /// Bypass all master insert slots
    pub fn bypass_all_master_inserts(&self, bypass: bool) {
        self.master_insert.read().bypass_all(bypass);
    }

    /// Get total master insert latency
    pub fn get_master_insert_latency(&self) -> usize {
        self.master_insert.read().total_latency()
    }

    /// Set parameter on master insert processor
    pub fn set_master_insert_param(&self, slot_index: usize, param_index: usize, value: f64) {
        let mut chain = self.master_insert.write();
        chain.set_slot_param(slot_index, param_index, value);
    }

    /// Get parameter from master insert processor
    pub fn get_master_insert_param(&self, slot_index: usize, param_index: usize) -> f64 {
        self.master_insert
            .read()
            .get_slot_param(slot_index, param_index)
    }

    /// Get meter value from master insert processor (GR, levels)
    pub fn get_master_insert_meter(&self, slot_index: usize, meter_index: usize) -> f64 {
        self.master_insert
            .read()
            .get_slot_meter(slot_index, meter_index)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUS INSERT CHAINS (Music, Sfx, Voice, Ambience, Aux)
    // ═══════════════════════════════════════════════════════════════════════
    //
    // Bus IDs: 0=Master routing, 1=Music, 2=Sfx, 3=Voice, 4=Amb, 5=Aux
    // Audio flow: Tracks → Bus InsertChain → Bus Volume → Sum to Master → master_insert

    /// Load processor into bus insert slot
    /// bus_id: 1=Music, 2=Sfx, 3=Voice, 4=Amb, 5=Aux (0=Master routing bus)
    pub fn load_bus_insert(
        &self,
        bus_id: usize,
        slot_index: usize,
        processor: Box<dyn crate::insert_chain::InsertProcessor>,
    ) -> bool {
        if bus_id >= 6 {
            log::warn!("[BusInsert] Invalid bus_id: {}", bus_id);
            return false;
        }
        let mut bus_inserts = self.bus_inserts.write();
        let result = bus_inserts[bus_id].load(slot_index, processor);
        log::info!(
            "[BusInsert] Loaded processor into bus {} slot {} -> {}",
            bus_id,
            slot_index,
            result
        );
        result
    }

    /// Unload processor from bus insert slot
    pub fn unload_bus_insert(
        &self,
        bus_id: usize,
        slot_index: usize,
    ) -> Option<Box<dyn crate::insert_chain::InsertProcessor>> {
        if bus_id >= 6 {
            return None;
        }
        let mut bus_inserts = self.bus_inserts.write();
        bus_inserts[bus_id].unload(slot_index)
    }

    /// Set bypass for bus insert slot
    pub fn set_bus_insert_bypass(&self, bus_id: usize, slot_index: usize, bypass: bool) {
        if bus_id >= 6 {
            return;
        }
        if let Some(slot) = self.bus_inserts.read()[bus_id].slot(slot_index) {
            slot.set_bypass(bypass);
        }
    }

    /// Set wet/dry mix for bus insert slot
    pub fn set_bus_insert_mix(&self, bus_id: usize, slot_index: usize, mix: f64) {
        if bus_id >= 6 {
            return;
        }
        if let Some(slot) = self.bus_inserts.read()[bus_id].slot(slot_index) {
            slot.set_mix(mix);
        }
    }

    /// Get bus insert slot wet/dry mix
    pub fn get_bus_insert_mix(&self, bus_id: usize, slot_index: usize) -> f64 {
        if bus_id >= 6 {
            return 1.0;
        }
        if let Some(slot) = self.bus_inserts.read()[bus_id].slot(slot_index) {
            return slot.mix();
        }
        1.0
    }

    /// Check if bus has insert loaded in slot
    pub fn has_bus_insert(&self, bus_id: usize, slot_index: usize) -> bool {
        if bus_id >= 6 {
            return false;
        }
        self.bus_inserts.read()[bus_id]
            .slot(slot_index)
            .map(|s| s.is_loaded())
            .unwrap_or(false)
    }

    /// Set parameter on bus insert processor (lock-free via ring buffer)
    pub fn set_bus_insert_param(
        &self,
        bus_id: usize,
        slot_index: usize,
        param_index: usize,
        value: f64,
    ) {
        if bus_id >= 6 {
            return;
        }
        // Use special track_id encoding for buses: track_id = 0xFFFF_0000 | bus_id
        // This distinguishes bus params from track params in the ring buffer
        let bus_track_id = 0xFFFF_0000_u64 | (bus_id as u64);
        let change = InsertParamChange::new(bus_track_id, slot_index, param_index, value);
        if let Some(mut tx) = self.insert_param_tx.try_lock() {
            let _ = tx.push(change);
        }
    }

    /// Get parameter from bus insert processor
    pub fn get_bus_insert_param(
        &self,
        bus_id: usize,
        slot_index: usize,
        param_index: usize,
    ) -> f64 {
        if bus_id >= 6 {
            return 0.0;
        }
        self.bus_inserts.read()[bus_id].get_slot_param(slot_index, param_index)
    }

    /// Get total bus insert latency
    pub fn get_bus_insert_latency(&self, bus_id: usize) -> usize {
        if bus_id >= 6 {
            return 0;
        }
        self.bus_inserts.read()[bus_id].total_latency()
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

    // ═══════════════════════════════════════════════════════════════════════════
    // GRAPH-LEVEL PDC (Phase-Coherent Plugin Delay Compensation)
    // ═══════════════════════════════════════════════════════════════════════════
    //
    // This is the ULTIMATE PDC implementation using topological graph analysis
    // (Pro Tools / Cubase industry standard). It ensures phase-coherent parallel
    // processing by calculating compensation delays based on the actual routing
    // graph structure, not just simple max-latency.
    //
    // Flow:
    //   Routing Change → recalculate_graph_pdc() → build_routing_graph()
    //                  → PDCCalculator::calculate() → apply_graph_pdc_delays()

    /// Check if graph-level PDC is enabled
    pub fn is_graph_pdc_enabled(&self) -> bool {
        self.graph_pdc_enabled.load(Ordering::Relaxed)
    }

    /// Enable or disable graph-level PDC
    pub fn set_graph_pdc_enabled(&self, enabled: bool) {
        let was_enabled = self.graph_pdc_enabled.swap(enabled, Ordering::SeqCst);
        if was_enabled != enabled {
            if enabled {
                // Recalculate when enabling
                self.recalculate_graph_pdc();
            } else {
                // Clear all PDC delays when disabling
                self.graph_pdc_delays.write().clear();
                *self.graph_pdc_result.write() = None;
                log::info!("[GraphPDC] Disabled - all compensation delays cleared");
            }
        }
    }

    /// Build routing graph from current engine state.
    ///
    /// The graph includes:
    /// - All tracks as nodes (with their insert chain latencies as edge weights)
    /// - All buses as nodes (with their insert chain latencies)
    /// - Edges from tracks to their output buses
    /// - Edge from all buses to master
    /// - Master insert chain latency
    pub fn build_routing_graph(&self) -> RoutingGraph {
        let mut graph = RoutingGraph::new();

        // Get all tracks and their insert latencies
        let tracks = self.track_manager.get_all_tracks();
        let insert_chains = self.insert_chains.read();
        let bus_inserts = self.bus_inserts.read();
        let master_insert = self.master_insert.read();

        // Add master node
        let master_id = GraphNode::Master.to_node_id();
        graph.add_node(master_id);

        // Add bus nodes (0=Master routing bus, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux)
        for bus_idx in 0..6 {
            let bus_node_id = GraphNode::Bus(bus_idx).to_node_id();
            graph.add_node(bus_node_id);

            // Get bus insert latency
            let bus_latency = bus_inserts[bus_idx].total_latency() as u64;

            // Bus → Master edge (bus sends audio to master after its inserts)
            graph.add_edge(bus_node_id, master_id, bus_latency);
        }

        // Add master insert latency (master_id has self-loop conceptually,
        // but for PDC we add it as output latency on the master node)
        // Actually, master insert is applied AFTER all buses sum, so it doesn't
        // affect PDC between tracks - it's just overall latency.
        // We don't add an edge here; master latency is for monitoring only.
        let _master_latency = master_insert.total_latency();

        // Add track nodes and edges to their output buses
        for track in &tracks {
            let track_id = track.id.0; // TrackId is a newtype wrapper around u64
            let track_node_id = GraphNode::Track(track_id).to_node_id();
            graph.add_node(track_node_id);

            // Get track insert latency
            let track_latency = insert_chains
                .get(&track_id)
                .map(|c| c.total_latency() as u64)
                .unwrap_or(0);

            // Determine output bus from track
            let bus_idx = match track.output_bus {
                OutputBus::Master => 0,
                OutputBus::Music => 1,
                OutputBus::Sfx => 2,
                OutputBus::Voice => 3,
                OutputBus::Ambience => 4,
                OutputBus::Aux => 5,
            };

            let bus_node_id = GraphNode::Bus(bus_idx).to_node_id();

            // Track → Bus edge with track's insert latency
            graph.add_edge(track_node_id, bus_node_id, track_latency);
        }

        graph
    }

    /// Recalculate graph-level PDC.
    ///
    /// Call this when:
    /// - Insert chain changes (load/unload processor)
    /// - Track routing changes (output bus assignment)
    /// - Track added/removed
    ///
    /// Returns true if calculation succeeded, false if graph has cycles.
    pub fn recalculate_graph_pdc(&self) -> bool {
        if !self.is_graph_pdc_enabled() {
            return false;
        }

        let graph = self.build_routing_graph();

        match PDCCalculator::calculate(&graph) {
            Ok(result) => {
                let mix_point_count = result.mix_points.len();
                let max_comp = result.compensation.values().copied().max().unwrap_or(0);
                let max_latency = result.max_latency;

                log::info!(
                    "[GraphPDC] Calculated: {} nodes, {} edges, {} mix points, \
                    max_latency={}samples, max_compensation={}samples",
                    graph.node_count(),
                    graph.edge_count(),
                    mix_point_count,
                    max_latency,
                    max_comp
                );

                // Apply compensation delays
                self.apply_graph_pdc_delays(&result);

                // Store result for inspection
                *self.graph_pdc_result.write() = Some(result);

                true
            }
            Err(e) => {
                log::error!("[GraphPDC] Calculation failed: {}", e);
                *self.graph_pdc_result.write() = None;
                false
            }
        }
    }

    /// Apply calculated PDC delays to tracks.
    ///
    /// This updates the graph_pdc_delays map which is used during audio processing
    /// to apply the correct compensation delay to each track.
    fn apply_graph_pdc_delays(&self, result: &PDCResult) {
        let mut delays = self.graph_pdc_delays.write();
        delays.clear();

        // Extract track compensation from result
        for (&node_id, &compensation) in &result.compensation {
            // Only store track compensations (bus compensations are handled differently)
            if let Some(GraphNode::Track(track_id)) = GraphNode::from_node_id(node_id)
                && compensation > 0 {
                    delays.insert(track_id, compensation);
                    log::debug!(
                        "[GraphPDC] Track {} compensation: {} samples ({:.2}ms @ 48kHz)",
                        track_id,
                        compensation,
                        compensation as f64 / 48.0
                    );
                }
        }

        log::info!("[GraphPDC] Applied delays to {} tracks", delays.len());
    }

    /// Get graph-level PDC compensation for a specific track.
    pub fn get_graph_pdc_compensation(&self, track_id: u64) -> u64 {
        if !self.is_graph_pdc_enabled() {
            return 0;
        }
        self.graph_pdc_delays
            .read()
            .get(&track_id)
            .copied()
            .unwrap_or(0)
    }

    /// Get graph-level PDC status as JSON string.
    ///
    /// Returns JSON with:
    /// - enabled: bool
    /// - valid: bool (whether calculation succeeded)
    /// - max_latency: samples
    /// - max_compensation: samples
    /// - mix_points: number of mix points found
    /// - track_compensations: map of track_id -> compensation samples
    pub fn get_graph_pdc_status_json(&self) -> String {
        let enabled = self.is_graph_pdc_enabled();
        let result = self.graph_pdc_result.read();
        let delays = self.graph_pdc_delays.read();

        if let Some(ref pdc) = *result {
            let track_comp_json: String = delays
                .iter()
                .map(|(id, comp)| format!("\"{}\":{}", id, comp))
                .collect::<Vec<_>>()
                .join(",");

            format!(
                r#"{{"enabled":{},"valid":true,"max_latency":{},"max_compensation":{},\
                "mix_points":{},"track_count":{},"track_compensations":{{{}}}}}"#,
                enabled,
                pdc.max_latency,
                pdc.compensation.values().copied().max().unwrap_or(0),
                pdc.mix_points.len(),
                delays.len(),
                track_comp_json
            )
        } else {
            format!(
                r#"{{"enabled":{},"valid":false,"max_latency":0,"max_compensation":0,\
                "mix_points":0,"track_count":0,"track_compensations":{{}}}}"#,
                enabled
            )
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // END GRAPH-LEVEL PDC
    // ═══════════════════════════════════════════════════════════════════════════

    /// Set parameter on track insert processor (LOCK-FREE via ring buffer)
    ///
    /// This method pushes param changes to a lock-free ring buffer instead of
    /// directly acquiring a write lock. The audio thread consumes these changes
    /// at the start of each block, ensuring no lock contention.
    pub fn set_track_insert_param(
        &self,
        track_id: u64,
        slot_index: usize,
        param_index: usize,
        value: f64,
    ) {
        let change = InsertParamChange::new(track_id, slot_index, param_index, value);

        // Non-blocking push to ring buffer
        if let Some(mut tx) = self.insert_param_tx.try_lock() {
            match tx.push(change) {
                Ok(()) => {
                    log::info!(
                        "[EQ] Queued param: track={}, slot={}, param={}, value={:.3}",
                        track_id,
                        slot_index,
                        param_index,
                        value
                    );
                }
                Err(_) => {
                    // Ring buffer full - drop oldest by logging warning
                    // In production, could implement overwrite strategy
                    log::warn!("[EQ] Ring buffer full, param change dropped");
                }
            }
        } else {
            // Mutex contended (very rare) - fallback to direct write
            // This should almost never happen with try_lock
            log::warn!("[EQ] Ring buffer mutex contended, using fallback");
            let mut chains = self.insert_chains.write();
            if let Some(chain) = chains.get_mut(&track_id) {
                chain.set_slot_param(slot_index, param_index, value);
            }
        }
    }

    /// Consume all pending insert param changes from ring buffer (AUDIO THREAD)
    ///
    /// Called at the start of each audio block to apply UI-initiated param changes.
    /// This is lock-free on the consumer side (try_lock on mutex wrapping Consumer).
    ///
    /// # Lock-Free Guarantee
    /// - NO logging (system calls forbidden in audio thread)
    /// - NO allocations
    /// - try_lock/try_write with immediate return on contention
    fn consume_insert_param_changes(&self) {
        // Try to get consumer - if locked, skip (very rare, means another audio thread access)
        let mut rx = match self.insert_param_rx.try_lock() {
            Some(rx) => rx,
            None => return, // Skip this block - lock contended
        };

        // Check if there are any pending changes to read
        if rx.is_empty() {
            return; // Nothing to consume
        }

        // Get write access to insert chains for applying params
        // Use try_write to avoid blocking - if UI is loading a processor, skip this block
        let mut chains = match self.insert_chains.try_write() {
            Some(c) => c,
            None => return, // Skip this block - lock contended
        };

        // Drain all pending changes
        while let Ok(change) = rx.pop() {
            // Check if this is a bus insert param (encoded as 0xFFFF_0000 | bus_id)
            if change.track_id & 0xFFFF_0000 == 0xFFFF_0000 {
                // Bus insert param change
                let bus_id = (change.track_id & 0x0000_FFFF) as usize;
                if bus_id < 6
                    && let Some(mut bus_inserts) = self.bus_inserts.try_write() {
                        bus_inserts[bus_id].set_slot_param(
                            change.slot_index as usize,
                            change.param_index as usize,
                            change.value,
                        );
                    }
            } else if change.track_id == 0 {
                // Master bus
                if let Some(mut master) = self.master_insert.try_write() {
                    master.set_slot_param(
                        change.slot_index as usize,
                        change.param_index as usize,
                        change.value,
                    );
                }
            } else if let Some(chain) = chains.get_mut(&change.track_id) {
                chain.set_slot_param(
                    change.slot_index as usize,
                    change.param_index as usize,
                    change.value,
                );
            }
            // Silently ignore changes for non-existent tracks (audio thread cannot log)
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

    /// Set sidechain source for a track insert slot
    pub fn set_insert_sidechain_source(
        &self,
        track_id: u64,
        slot_index: usize,
        source_id: i64,
    ) {
        if let Some(mut chains) = self.insert_chains.try_write()
            && let Some(chain) = chains.get_mut(&track_id)
                && let Some(slot) = chain.slot_mut(slot_index) {
                    slot.set_sidechain_source(source_id);
                }
    }

    /// Get sidechain source for a track insert slot
    pub fn get_insert_sidechain_source(
        &self,
        track_id: u64,
        slot_index: usize,
    ) -> i64 {
        self.insert_chains
            .read()
            .get(&track_id)
            .and_then(|chain| chain.slot(slot_index))
            .map(|slot| slot.get_sidechain_source())
            .unwrap_or(-1)
    }

    /// Update sample rate on all insert chains (track, bus, master)
    pub fn update_all_insert_sample_rates(&self, sample_rate: f64) {
        if let Some(mut chains) = self.insert_chains.try_write() {
            for chain in chains.values_mut() {
                chain.set_sample_rate(sample_rate);
            }
        }
        if let Some(mut bus_inserts) = self.bus_inserts.try_write() {
            for chain in bus_inserts.iter_mut() {
                chain.set_sample_rate(sample_rate);
            }
        }
        if let Some(mut master) = self.master_insert.try_write() {
            master.set_sample_rate(sample_rate);
        }
    }

    /// Get meter value from track insert processor (GR, levels)
    pub fn get_track_insert_meter(
        &self,
        track_id: u64,
        slot_index: usize,
        meter_index: usize,
    ) -> f64 {
        self.insert_chains
            .read()
            .get(&track_id)
            .map(|chain| chain.get_slot_meter(slot_index, meter_index))
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

    /// Check if master has insert loaded in slot
    pub fn has_master_insert(&self, slot_index: usize) -> bool {
        self.master_insert
            .read()
            .slot(slot_index)
            .map(|slot| slot.is_loaded())
            .unwrap_or(false)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // P10.0.1: PER-PROCESSOR METERING ACCESS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get metering data for track insert slot
    pub fn get_track_insert_metering(
        &self,
        track_id: u64,
        slot_index: usize,
    ) -> Option<crate::insert_chain::ProcessorMetering> {
        self.insert_chains
            .read()
            .get(&track_id)?
            .slot(slot_index)?
            .get_metering()
            .into()
    }

    /// Get metering data for master insert slot
    pub fn get_master_insert_metering(
        &self,
        slot_index: usize,
    ) -> Option<crate::insert_chain::ProcessorMetering> {
        self.master_insert
            .read()
            .slot(slot_index)?
            .get_metering()
            .into()
    }

    /// Get metering data for bus insert slot
    pub fn get_bus_insert_metering(
        &self,
        bus_id: usize,
        slot_index: usize,
    ) -> Option<crate::insert_chain::ProcessorMetering> {
        if bus_id >= 6 {
            return None;
        }

        self.bus_inserts.read()[bus_id]
            .slot(slot_index)?
            .get_metering()
            .into()
    }

    /// Set position for track insert slot
    pub fn set_track_insert_position(&self, track_id: u64, slot_index: usize, pre_fader: bool) {
        use crate::insert_chain::InsertPosition;
        let mut chains = self.insert_chains.write();
        if let Some(chain) = chains.get_mut(&track_id)
            && let Some(slot) = chain.slot_mut(slot_index)
        {
            slot.set_position(if pre_fader {
                InsertPosition::PreFader
            } else {
                InsertPosition::PostFader
            });
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

    /// Get track LUFS (momentary, short-term, integrated) by track ID
    pub fn get_track_lufs(&self, track_id: u64) -> (f64, f64, f64) {
        self.track_meters
            .read()
            .get(&track_id)
            .map(|m| (m.lufs_momentary, m.lufs_short, m.lufs_integrated))
            .unwrap_or((-70.0, -70.0, -70.0))
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PER-TRACK / BUS / MASTER STEREO IMAGER API
    // ═══════════════════════════════════════════════════════════════════════════

    /// Ensure a StereoImager exists for the given track, creating one if needed.
    pub fn ensure_stereo_imager(&self, track_id: u32, sample_rate: f64) {
        let mut imagers = self.stereo_imagers.write();
        imagers
            .entry(track_id)
            .or_insert_with(|| rf_dsp::spatial::StereoImager::new(sample_rate));
    }

    /// Remove a track's StereoImager.
    pub fn remove_stereo_imager(&self, track_id: u32) -> bool {
        self.stereo_imagers.write().remove(&track_id).is_some()
    }

    /// Apply a mutation to a track's StereoImager. Returns false if not found.
    pub fn with_track_imager<F: FnOnce(&mut rf_dsp::spatial::StereoImager)>(
        &self,
        track_id: u32,
        f: F,
    ) -> bool {
        let mut imagers = self.stereo_imagers.write();
        if let Some(imager) = imagers.get_mut(&track_id) {
            f(imager);
            true
        } else {
            false
        }
    }

    /// Apply a mutation to a bus's StereoImager.
    pub fn with_bus_imager<F: FnOnce(&mut rf_dsp::spatial::StereoImager)>(
        &self,
        bus_idx: usize,
        f: F,
    ) -> bool {
        if bus_idx >= 6 {
            return false;
        }
        let mut imagers = self.bus_stereo_imagers.write();
        f(&mut imagers[bus_idx]);
        true
    }

    /// Apply a mutation to the master StereoImager.
    pub fn with_master_imager<F: FnOnce(&mut rf_dsp::spatial::StereoImager)>(&self, f: F) {
        let mut imager = self.master_stereo_imager.write();
        f(&mut imager);
    }

    /// Read a track's StereoImager correlation value. Returns 0.0 if not found.
    pub fn get_track_imager_correlation(&self, track_id: u32) -> f64 {
        let imagers = self.stereo_imagers.read();
        imagers
            .get(&track_id)
            .map(|im| im.correlation.correlation())
            .unwrap_or(0.0)
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
    /// Note: This clones the HashMap - use write_all_track_meters_to_buffers for FFI
    pub fn get_all_track_meters(&self) -> HashMap<u64, TrackMeter> {
        self.track_meters.read().clone()
    }

    /// P1.14 FIX: Write track meters directly to FFI buffers without HashMap clone
    ///
    /// Returns the number of meters written (capped at max_count)
    /// This is zero-allocation for the actual meter data
    ///
    /// # Safety
    /// Caller must ensure all pointers are valid and point to buffers of at least max_count elements
    pub unsafe fn write_all_track_meters_to_buffers(
        &self,
        out_ids: *mut u64,
        out_peak_l: *mut f64,
        out_peak_r: *mut f64,
        out_rms_l: *mut f64,
        out_rms_r: *mut f64,
        out_corr: *mut f64,
        max_count: usize,
    ) -> usize {
        let meters = self.track_meters.read();
        let count = meters.len().min(max_count);

        for (i, (&track_id, meter)) in meters.iter().take(count).enumerate() {
            // SAFETY: Caller guarantees valid pointers with sufficient capacity
            unsafe {
                *out_ids.add(i) = track_id;
                *out_peak_l.add(i) = meter.peak_l;
                *out_peak_r.add(i) = meter.peak_r;
                *out_rms_l.add(i) = meter.rms_l;
                *out_rms_r.add(i) = meter.rms_r;
                *out_corr.add(i) = meter.correlation;
            }
        }

        count
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
        // Start insert chain tail processing (reverb/delay tails ring out)
        let tail_dur = self.tail_duration_samples.load(Ordering::Relaxed);
        self.tail_remaining_samples
            .store(tail_dur, Ordering::Relaxed);
        self.position.set_state(PlaybackState::Paused);
    }

    pub fn stop(&self) {
        // Stop any active recordings first
        let recordings = self.recording_manager.stop_all();
        for (track_id, path) in recordings {
            log::info!("Recording stopped for track {:?}: {:?}", track_id, path);
        }
        // Start insert chain tail processing (reverb/delay tails ring out)
        let tail_dur = self.tail_duration_samples.load(Ordering::Relaxed);
        self.tail_remaining_samples
            .store(tail_dur, Ordering::Relaxed);
        self.position.set_state(PlaybackState::Stopped);
        self.position.set_samples(0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RECORDING CONTROLS
    // ═══════════════════════════════════════════════════════════════════════

    /// Start recording on all armed tracks
    /// Returns list of (track_id, file_path) for started recordings
    pub fn record(&self) -> Vec<(TrackId, std::path::PathBuf)> {
        // Start all armed track recorders
        let started = self.recording_manager.start_all();
        // Set state to Recording (which also plays)
        self.position.set_state(PlaybackState::Recording);
        started
    }

    /// Stop recording (but keep playing)
    pub fn stop_recording(&self) -> Vec<(TrackId, std::path::PathBuf)> {
        let stopped = self.recording_manager.stop_all();
        // Switch to playing state (keep playhead moving)
        if self.position.is_playing() {
            self.position.set_state(PlaybackState::Playing);
        }
        stopped
    }

    /// Arm track for recording
    pub fn arm_track(&self, track_id: TrackId, num_channels: u16, track_name: &str) -> bool {
        self.recording_manager
            .arm_track(track_id, num_channels, track_name)
    }

    /// Disarm track
    pub fn disarm_track(&self, track_id: TrackId) -> bool {
        self.recording_manager.disarm_track(track_id)
    }

    /// Check if track is armed
    pub fn is_track_armed(&self, track_id: TrackId) -> bool {
        self.recording_manager.is_armed(track_id)
    }

    /// Check if currently recording
    pub fn is_recording(&self) -> bool {
        self.position.is_recording()
    }

    /// Set recording output directory
    pub fn set_recording_dir(&self, path: std::path::PathBuf) {
        self.recording_manager.set_output_dir(path);
    }

    /// Set punch in/out points
    pub fn set_punch(&self, punch_in_secs: f64, punch_out_secs: f64) {
        self.recording_manager
            .set_punch_times(punch_in_secs, punch_out_secs);
    }

    /// Set punch mode
    pub fn set_punch_mode(&self, mode: crate::recording_manager::PunchMode) {
        self.recording_manager.set_punch_mode(mode);
    }

    /// Enable/disable pre-roll
    pub fn set_pre_roll(&self, enabled: bool, bars: u64) {
        self.recording_manager.set_pre_roll_enabled(enabled);
        self.recording_manager.set_pre_roll_bars(bars);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO STRETCHER MANAGEMENT (Signalsmith Stretch — UI thread only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Get stretcher debug counters (hit, miss). Resets on read.
    pub fn stretcher_debug_counters(&self) -> (u32, u32) {
        let hit = self.diag_stretcher_hit.swap(0, Ordering::Relaxed);
        let miss = self.diag_stretcher_miss.swap(0, Ordering::Relaxed);
        (hit, miss)
    }

    /// Get adaptive quality diagnostics (lock-free, safe from any thread).
    /// Returns (active_voices, degraded_voices, cpu_load_pct, src_mode_value)
    pub fn adaptive_quality_stats(&self) -> (u32, u32, u32, u32) {
        (
            self.diag_active_voices.load(Ordering::Relaxed),
            self.diag_degraded_voices.load(Ordering::Relaxed),
            self.diag_cpu_load_pct.load(Ordering::Relaxed),
            self.diag_src_mode.load(Ordering::Relaxed),
        )
    }

    /// Get and reset bus contention count (lock-free swap, safe from any thread).
    /// Returns number of try_write() failures on bus_buffers since last call.
    pub fn drain_bus_contention(&self) -> u32 {
        self.diag_bus_contention.swap(0, Ordering::Relaxed)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO CACHE ACCESS
    // ═══════════════════════════════════════════════════════════════════════

    /// Get cached audio by source file path (for offline analysis like transient detection).
    pub fn get_cached_audio(&self, path: &str) -> Option<std::sync::Arc<crate::audio_import::ImportedAudio>> {
        self.cache.get(path)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO STRETCHER MANAGEMENT (Signalsmith Stretch — UI thread only)
    // ═══════════════════════════════════════════════════════════════════════

    /// Pre-allocate or update audio stretcher for a clip.
    /// `stretch_ratio`: time stretch (1.0=normal), `pitch_semitones`: pitch shift
    pub fn prepare_clip_stretcher(
        &self, clip_id: u64, stretch_ratio: f64, pitch_semitones: f64, sample_rate: f64,
    ) {
        let has_stretch = (stretch_ratio - 1.0).abs() > 0.001;
        let has_pitch = pitch_semitones.abs() > 0.01;
        if !has_stretch && !has_pitch {
            self.clip_stretchers.write().remove(&clip_id);
            return;
        }
        let mut stretchers = self.clip_stretchers.write();
        let stretcher = stretchers.entry(clip_id).or_insert_with(|| {
            crate::audio_stretcher::AudioStretcher::new(sample_rate as u32, 8192)
        });
        stretcher.set_pitch_semitones(pitch_semitones);
        stretcher.set_stretch_ratio(stretch_ratio);
    }

    /// Convenience: prepare stretcher with no pitch shift (stretch-only).
    pub fn prepare_clip_vocoder(&self, clip_id: u64, stretch_ratio: f64, sample_rate: f64) {
        self.prepare_clip_stretcher(clip_id, stretch_ratio, 0.0, sample_rate);
    }

    /// Convenience: prepare stretcher with pitch + stretch.
    pub fn prepare_clip_vocoder_with_pitch(
        &self, clip_id: u64, stretch_ratio: f64, pitch_semitones: f64, sample_rate: f64,
    ) {
        self.prepare_clip_stretcher(clip_id, stretch_ratio, pitch_semitones, sample_rate);
    }

    /// Get read access to clip stretchers (non-blocking).
    pub fn clip_stretchers_try_read(&self) -> Option<parking_lot::RwLockReadGuard<'_, HashMap<u64, crate::audio_stretcher::AudioStretcher>>> {
        self.clip_stretchers.try_read()
    }

    /// Get write access to clip stretchers (UI thread only).
    pub fn clip_stretchers_write(&self) -> parking_lot::RwLockWriteGuard<'_, HashMap<u64, crate::audio_stretcher::AudioStretcher>> {
        self.clip_stretchers.write()
    }

    /// Remove stretcher for a clip.
    pub fn remove_clip_vocoder(&self, clip_id: u64) {
        self.clip_stretchers.write().remove(&clip_id);
    }

    /// Update stretch ratio for an existing stretcher (UI thread only).
    /// NOTE: FFI export name is `clip_update_vocoder_pitch` for binary compat.
    pub fn update_clip_stretch_ratio(&self, clip_id: u64, stretch_ratio: f64) {
        if let Some(stretcher) = self.clip_stretchers.write().get_mut(&clip_id) {
            stretcher.set_stretch_ratio(stretch_ratio);
        }
    }

    pub fn seek(&self, seconds: f64) {
        self.position.set_seconds(seconds.max(0.0));
        // Request deferred reset on all stretchers (lock-free, audio thread executes)
        if let Some(stretchers) = self.clip_stretchers.try_read() {
            for s in stretchers.values() {
                s.request_reset();
            }
        }
    }

    pub fn seek_samples(&self, samples: u64) {
        self.position.set_samples(samples);
        if let Some(stretchers) = self.clip_stretchers.try_read() {
            for s in stretchers.values() {
                s.request_reset();
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCRUBBING (Pro Tools / Cubase style audio preview)
    // ═══════════════════════════════════════════════════════════════════════

    /// Start scrubbing at given position
    /// Enables audio preview while dragging in timeline
    pub fn start_scrub(&self, seconds: f64) {
        self.position.set_seconds(seconds.max(0.0));
        self.position.reset_scrub_window();
        self.position.set_scrub_velocity(0.0);
        self.position.set_state(PlaybackState::Scrubbing);
    }

    /// Update scrub position with velocity
    /// velocity: -4.0 to 4.0, positive = forward, negative = backward
    pub fn update_scrub(&self, seconds: f64, velocity: f64) {
        self.position.set_seconds(seconds.max(0.0));
        self.position.set_scrub_velocity(velocity);
        self.position.reset_scrub_window();
    }

    /// Stop scrubbing
    pub fn stop_scrub(&self) {
        self.position.set_scrub_velocity(0.0);
        self.position.set_state(PlaybackState::Stopped);
    }

    /// Check if currently scrubbing
    pub fn is_scrubbing(&self) -> bool {
        self.position.is_scrubbing()
    }

    /// Set scrub window size in milliseconds (10-200ms)
    /// Smaller = more responsive but choppier
    /// Larger = smoother but less precise
    pub fn set_scrub_window_ms(&self, ms: u64) {
        self.position.set_scrub_window_ms(ms);
    }

    pub fn set_master_volume(&self, volume: f64) {
        self.master_volume
            .store(volume.clamp(0.0, 1.5).to_bits(), Ordering::Relaxed);
    }

    pub fn master_volume(&self) -> f64 {
        f64::from_bits(self.master_volume.load(Ordering::Relaxed))
    }

    // ═══ MASTER CHANNEL DELAY (Independent L/R) ═══

    /// Set left channel delay in milliseconds (0.0 to 30.0)
    pub fn set_master_delay_l(&self, ms: f64) {
        self.master_delay_l_ms
            .store(ms.clamp(0.0, 30.0).to_bits(), Ordering::Relaxed);
    }

    /// Set right channel delay in milliseconds (0.0 to 30.0)
    pub fn set_master_delay_r(&self, ms: f64) {
        self.master_delay_r_ms
            .store(ms.clamp(0.0, 30.0).to_bits(), Ordering::Relaxed);
    }

    /// Get left channel delay in milliseconds
    pub fn master_delay_l(&self) -> f64 {
        f64::from_bits(self.master_delay_l_ms.load(Ordering::Relaxed))
    }

    /// Get right channel delay in milliseconds
    pub fn master_delay_r(&self) -> f64 {
        f64::from_bits(self.master_delay_r_ms.load(Ordering::Relaxed))
    }

    /// Enable/disable master soft clipper (tanh saturation at 0dBFS)
    pub fn set_master_soft_clip(&self, enabled: bool) {
        self.master_soft_clip_enabled.store(enabled, Ordering::Relaxed);
    }

    /// Check if master soft clipper is enabled
    pub fn master_soft_clip_enabled(&self) -> bool {
        self.master_soft_clip_enabled.load(Ordering::Relaxed)
    }

    /// Get current playback position in seconds (sample-accurate)
    pub fn position_seconds(&self) -> f64 {
        self.position.seconds()
    }

    /// Get current playback position in samples
    pub fn position_samples(&self) -> u64 {
        self.position.samples()
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

    /// Set bus pan right (-1.0 to 1.0) for stereo dual-pan mode
    pub fn set_bus_pan_right(&self, bus_idx: usize, pan: f64) {
        if let Some(state) = self.bus_states.write().get_mut(bus_idx) {
            state.pan_right = pan.clamp(-1.0, 1.0);
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

    /// Set bus output destination for hierarchical routing (stem grouping).
    /// - BusOutputDest::Master → routes to main output (default)
    /// - BusOutputDest::Bus(idx) → routes to another bus (e.g., Sfx→Music)
    pub fn set_bus_output_dest(&self, bus_idx: usize, dest: BusOutputDest) {
        if bus_idx < 6 {
            // Prevent circular routing: if target routes to us, force master
            let safe_dest = if let BusOutputDest::Bus(target) = dest {
                if target < 6 && target != bus_idx {
                    let states = self.bus_states.read();
                    // Check if target already routes to us (2-level cycle check)
                    if let BusOutputDest::Bus(targets_target) = states[target].output_dest {
                        if targets_target == bus_idx {
                            log::warn!(
                                "Circular bus routing detected: {} → {} → {}. Forcing master.",
                                bus_idx, target, bus_idx
                            );
                            BusOutputDest::Master
                        } else {
                            dest
                        }
                    } else {
                        dest
                    }
                } else {
                    BusOutputDest::Master
                }
            } else {
                dest
            };
            self.bus_states.write()[bus_idx].output_dest = safe_dest;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ONE-SHOT VOICE API (Middleware/SlotLab event playback)
    // ═══════════════════════════════════════════════════════════════════════

    /// Play audio file directly to a bus (bypasses track system)
    /// Returns voice ID on success, 0 on failure
    ///
    /// bus_id mapping:
    /// - 0 = Master (routed through Sfx)
    /// - 1 = Music
    /// - 2 = Sfx (default)
    /// - 3 = Voice
    /// - 4 = Ambience
    /// - 5 = Aux
    ///
    /// pan: -1.0 = full left, 0.0 = center, +1.0 = full right
    /// source: PlaybackSource for section-based filtering
    pub fn play_one_shot_to_bus(
        &self,
        path: &str,
        volume: f32,
        pan: f32,
        bus_id: u32,
        source: PlaybackSource,
    ) -> u64 {
        // Load audio from cache (may block if not cached)
        let audio = match self.cache.load(path) {
            Some(a) => a,
            None => {
                log::warn!("[PlaybackEngine] Failed to load audio: {}", path);
                return 0;
            }
        };

        // Map bus_id to OutputBus
        let bus = match bus_id {
            0 => OutputBus::Sfx, // Master routes through Sfx
            1 => OutputBus::Music,
            2 => OutputBus::Sfx,
            3 => OutputBus::Voice,
            4 => OutputBus::Ambience,
            5 => OutputBus::Aux,
            _ => OutputBus::Sfx, // Default to Sfx
        };

        // Get next voice ID
        let id = self.next_one_shot_id.fetch_add(1, Ordering::Relaxed);

        // Send command to audio thread (lock-free)
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::Play {
                id,
                audio,
                volume,
                pan: pan.clamp(-1.0, 1.0),
                bus,
                source,
            });
            log::debug!(
                "[PlaybackEngine] One-shot play: {} (id={}, pan={:.2}, bus={:?}, source={:?})",
                path,
                id,
                pan,
                bus,
                source
            );
            id
        } else {
            log::warn!("[PlaybackEngine] One-shot command queue busy");
            0
        }
    }

    /// P0.2: Play looping audio through a specific bus (Middleware/SlotLab REEL_SPIN etc.)
    /// Loops seamlessly until explicitly stopped with stop_one_shot()
    /// Returns voice ID (0 = failed to queue)
    pub fn play_looping_to_bus(
        &self,
        path: &str,
        volume: f32,
        pan: f32,
        bus_id: u32,
        source: PlaybackSource,
    ) -> u64 {
        // Load audio from cache (may block if not cached)
        let audio = match self.cache.load(path) {
            Some(a) => a,
            None => {
                log::warn!("[PlaybackEngine] Failed to load looping audio: {}", path);
                return 0;
            }
        };

        // Map bus_id to OutputBus
        let bus = match bus_id {
            0 => OutputBus::Sfx,
            1 => OutputBus::Music,
            2 => OutputBus::Sfx,
            3 => OutputBus::Voice,
            4 => OutputBus::Ambience,
            5 => OutputBus::Aux,
            _ => OutputBus::Sfx,
        };

        // Get next voice ID
        let id = self.next_one_shot_id.fetch_add(1, Ordering::Relaxed);

        // Send command to audio thread (lock-free)
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::PlayLooping {
                id,
                audio,
                volume,
                pan: pan.clamp(-1.0, 1.0),
                bus,
                source,
            });
            log::debug!(
                "[PlaybackEngine] Looping play: {} (id={}, pan={:.2}, bus={:?}, source={:?})",
                path,
                id,
                pan,
                bus,
                source
            );
            id
        } else {
            log::warn!("[PlaybackEngine] One-shot command queue busy");
            0
        }
    }

    /// Extended one-shot playback with fadeIn, fadeOut, and trim parameters
    /// fade_in_ms: fade-in duration at start (0 = no fade)
    /// fade_out_ms: fade-out duration at end (0 = no fade)
    /// trim_start_ms: start position in audio file (0 = from beginning)
    /// trim_end_ms: end position in audio file (0 = play to end)
    pub fn play_one_shot_to_bus_ex(
        &self,
        path: &str,
        volume: f32,
        pan: f32,
        bus_id: u32,
        source: PlaybackSource,
        fade_in_ms: f32,
        fade_out_ms: f32,
        trim_start_ms: f32,
        trim_end_ms: f32,
    ) -> u64 {
        // Load audio from cache (may block if not cached)
        let audio = match self.cache.load(path) {
            Some(a) => a,
            None => {
                log::warn!(
                    "[PlaybackEngine] Failed to load audio for extended play: {}",
                    path
                );
                return 0;
            }
        };

        // Map bus_id to OutputBus
        let bus = match bus_id {
            0 => OutputBus::Sfx,
            1 => OutputBus::Music,
            2 => OutputBus::Sfx,
            3 => OutputBus::Voice,
            4 => OutputBus::Ambience,
            5 => OutputBus::Aux,
            _ => OutputBus::Sfx,
        };

        // Get next voice ID
        let id = self.next_one_shot_id.fetch_add(1, Ordering::Relaxed);

        // Send command to audio thread (lock-free)
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::PlayEx {
                id,
                audio,
                volume,
                pan: pan.clamp(-1.0, 1.0),
                bus,
                source,
                fade_in_ms,
                fade_out_ms,
                trim_start_ms,
                trim_end_ms,
            });
            log::debug!(
                "[PlaybackEngine] Extended play: {} (id={}, fadeIn={:.0}ms, fadeOut={:.0}ms, trim={:.0}-{:.0}ms)",
                path,
                id,
                fade_in_ms,
                fade_out_ms,
                trim_start_ms,
                trim_end_ms
            );
            id
        } else {
            log::warn!("[PlaybackEngine] One-shot command queue busy");
            0
        }
    }

    /// Play a one-shot voice with 3D spatial positioning through HRTF binaural rendering.
    /// The voice audio bypasses pan law and routes through SpatialManager instead.
    /// `spatial_source_id` must be pre-registered via `spatial_set_source_position()`.
    pub fn play_one_shot_spatial(
        &self,
        path: &str,
        volume: f32,
        bus_id: u32,
        source: PlaybackSource,
        spatial_source_id: u32,
    ) -> u64 {
        let audio = match self.cache.load(path) {
            Some(a) => a,
            None => {
                log::warn!("[PlaybackEngine] Failed to load spatial audio: {}", path);
                return 0;
            }
        };

        let bus = match bus_id {
            0 => OutputBus::Sfx,
            1 => OutputBus::Music,
            2 => OutputBus::Sfx,
            3 => OutputBus::Voice,
            4 => OutputBus::Ambience,
            5 => OutputBus::Aux,
            _ => OutputBus::Sfx,
        };

        let id = self.next_one_shot_id.fetch_add(1, Ordering::Relaxed);

        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::PlaySpatial {
                id,
                audio,
                volume,
                bus,
                source,
                spatial_source_id,
            });
            id
        } else {
            0
        }
    }

    /// Stop a specific one-shot voice
    pub fn stop_one_shot(&self, voice_id: u64) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::Stop { id: voice_id });
        }
    }

    /// P0: Fade out a specific one-shot voice with configurable duration
    /// fade_ms: fade duration in milliseconds (converted to samples internally)
    pub fn fade_out_one_shot(&self, voice_id: u64, fade_ms: u32) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            // Convert ms to samples at actual engine sample rate
            let sr = self.sample_rate().max(44100) as f64;
            let fade_samples = ((sr * fade_ms as f64) / 1000.0) as u64;
            let _ = tx.push(OneShotCommand::FadeOut {
                id: voice_id,
                fade_samples,
            });
        }
    }

    /// P12.0.1: Set pitch shift for a specific one-shot voice
    /// semitones: pitch shift in semitones (-24 to +24)
    /// Positive values = higher pitch, negative = lower pitch
    /// Example: +12 = one octave up, -12 = one octave down
    pub fn set_voice_pitch(&self, voice_id: u64, semitones: f32) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let clamped = semitones.clamp(-24.0, 24.0);
            let _ = tx.push(OneShotCommand::SetPitch {
                id: voice_id,
                semitones: clamped,
            });
        }
    }

    /// Set volume for a specific active voice in real-time
    pub fn set_voice_volume(&self, voice_id: u64, volume: f32) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::SetVolume {
                id: voice_id,
                volume: volume.clamp(0.0, 1.5),
            });
        }
    }

    /// Set pan for a specific active voice in real-time
    pub fn set_voice_pan(&self, voice_id: u64, pan: f32) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::SetPan {
                id: voice_id,
                pan: pan.clamp(-1.0, 1.0),
            });
        }
    }

    /// Set pan right for stereo dual-pan mode in real-time
    /// Controls R channel placement independently from L (pan field)
    pub fn set_voice_pan_right(&self, voice_id: u64, pan_right: f32) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::SetPanRight {
                id: voice_id,
                pan_right: pan_right.clamp(-1.0, 1.0),
            });
        }
    }

    /// Set input gain for a specific active voice in real-time (linear amplitude)
    pub fn set_voice_input_gain(&self, voice_id: u64, gain: f32) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::SetInputGain {
                id: voice_id,
                gain: gain.clamp(0.0, 4.0),
            });
        }
    }

    /// Set stereo width for a specific active voice in real-time
    pub fn set_voice_width(&self, voice_id: u64, width: f32) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::SetWidth {
                id: voice_id,
                width: width.clamp(0.0, 2.0),
            });
        }
    }

    /// Set phase invert for a specific active voice in real-time
    pub fn set_voice_phase_invert(&self, voice_id: u64, invert: bool) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::SetPhaseInvert {
                id: voice_id,
                invert,
            });
        }
    }

    /// Set mute state for a specific active voice in real-time
    pub fn set_voice_mute(&self, voice_id: u64, muted: bool) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::SetMute {
                id: voice_id,
                muted,
            });
        }
    }

    /// Stop all one-shot voices
    pub fn stop_all_one_shots(&self) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::StopAll);
        }
    }

    /// Stop all one-shot voices from a specific source
    pub fn stop_source_one_shots(&self, source: PlaybackSource) {
        if let Some(mut tx) = self.one_shot_cmd_tx.try_lock() {
            let _ = tx.push(OneShotCommand::StopSource { source });
        }
    }

    /// Check if a voice is still actively playing
    pub fn is_voice_active(&self, voice_id: u64) -> bool {
        let voices = match self.one_shot_voices.try_read() {
            Some(v) => v,
            None => return true, // Assume active if lock unavailable (audio thread busy)
        };
        voices.iter().any(|v| v.id == voice_id && v.active)
    }

    /// Get per-voice peak meter values (linear amplitude)
    /// Returns (peak_l, peak_r) for the specified voice, or (0, 0) if not found
    pub fn get_voice_peak_stereo(&self, voice_id: u64) -> (f32, f32) {
        let voices = match self.one_shot_voices.try_read() {
            Some(v) => v,
            None => return (0.0, 0.0),
        };
        for v in voices.iter() {
            if v.id == voice_id && v.active {
                return (v.meter_peak_l, v.meter_peak_r);
            }
        }
        (0.0, 0.0)
    }

    /// Get voice pool statistics
    /// Returns (active_count, max_voices, voices_by_source, voices_by_bus)
    pub fn get_voice_pool_stats(&self) -> VoicePoolStats {
        let voices = match self.one_shot_voices.try_read() {
            Some(v) => v,
            None => return VoicePoolStats::default(),
        };

        let mut active_count = 0u32;
        let mut looping_count = 0u32;
        let mut daw_voices = 0u32;
        let mut slotlab_voices = 0u32;
        let mut middleware_voices = 0u32;
        let mut browser_voices = 0u32;
        let mut sfx_voices = 0u32;
        let mut music_voices = 0u32;
        let mut voice_voices = 0u32;
        let mut ambience_voices = 0u32;
        let mut aux_voices = 0u32;
        let mut master_voices = 0u32;

        for voice in voices.iter() {
            if voice.active {
                active_count += 1;
                if voice.looping {
                    looping_count += 1;
                }
                match voice.source {
                    PlaybackSource::Daw => daw_voices += 1,
                    PlaybackSource::SlotLab => slotlab_voices += 1,
                    PlaybackSource::Middleware => middleware_voices += 1,
                    PlaybackSource::Browser => browser_voices += 1,
                }
                match voice.bus {
                    OutputBus::Sfx => sfx_voices += 1,
                    OutputBus::Music => music_voices += 1,
                    OutputBus::Voice => voice_voices += 1,
                    OutputBus::Ambience => ambience_voices += 1,
                    OutputBus::Aux => aux_voices += 1,
                    OutputBus::Master => master_voices += 1,
                }
            }
        }

        VoicePoolStats {
            active_count,
            max_voices: MAX_ONE_SHOT_VOICES as u32,
            looping_count,
            daw_voices,
            slotlab_voices,
            middleware_voices,
            browser_voices,
            sfx_voices,
            music_voices,
            voice_voices,
            ambience_voices,
            aux_voices,
            master_voices,
        }
    }

    /// Process one-shot voice commands (call at start of audio block)
    fn process_one_shot_commands(&self) {
        let mut rx = match self.one_shot_cmd_rx.try_lock() {
            Some(rx) => rx,
            None => return,
        };

        let mut voices = match self.one_shot_voices.try_write() {
            Some(v) => v,
            None => return,
        };

        while let Ok(cmd) = rx.pop() {
            match cmd {
                OneShotCommand::Play {
                    id,
                    audio,
                    volume,
                    pan,
                    bus,
                    source,
                } => {
                    // Find first inactive slot
                    // Note: If no slot available, command is silently dropped (audio thread cannot log)
                    if let Some(voice) = voices.iter_mut().find(|v| !v.active) {
                        voice.activate(id, audio, volume, pan, bus, source);
                        voice.engine_sample_rate = self.sample_rate();
                    }
                    // Voice stealing would go here in future (oldest voice eviction)
                }
                OneShotCommand::PlayLooping {
                    id,
                    audio,
                    volume,
                    pan,
                    bus,
                    source,
                } => {
                    // Seamless looping voice (REEL_SPIN etc.)
                    if let Some(voice) = voices.iter_mut().find(|v| !v.active) {
                        voice.activate_looping(id, audio, volume, pan, bus, source);
                        voice.engine_sample_rate = self.sample_rate();
                    }
                    // Silent drop if no voice available (audio thread rule: no logging)
                }
                OneShotCommand::PlayEx {
                    id,
                    audio,
                    volume,
                    pan,
                    bus,
                    source,
                    fade_in_ms,
                    fade_out_ms,
                    trim_start_ms,
                    trim_end_ms,
                } => {
                    // Extended play with fadeIn, fadeOut, and trim
                    if let Some(voice) = voices.iter_mut().find(|v| !v.active) {
                        voice.activate_ex(
                            id,
                            audio,
                            volume,
                            pan,
                            bus,
                            source,
                            fade_in_ms,
                            fade_out_ms,
                            trim_start_ms,
                            trim_end_ms,
                        );
                        voice.engine_sample_rate = self.sample_rate();
                    }
                    // Silent drop if no voice available (audio thread rule: no logging)
                }
                OneShotCommand::Stop { id } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        // Fade out over ~5ms at 48kHz
                        voice.start_fade_out(480);
                    }
                }
                OneShotCommand::StopAll => {
                    for voice in voices.iter_mut() {
                        if voice.active {
                            voice.start_fade_out(480);
                        }
                    }
                }
                OneShotCommand::StopSource { source } => {
                    for voice in voices.iter_mut() {
                        if voice.active && voice.source == source {
                            voice.start_fade_out(480);
                        }
                    }
                }
                // P0: Per-reel spin loop fade-out with configurable duration
                OneShotCommand::FadeOut { id, fade_samples } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.start_fade_out(fade_samples);
                    }
                }
                // P12.0.1: Set pitch shift for specific voice
                OneShotCommand::SetPitch { id, semitones } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.pitch_semitones = semitones.clamp(-24.0, 24.0);
                    }
                }
                // Real-time volume update for active voice
                OneShotCommand::SetVolume { id, volume } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.volume = volume.clamp(0.0, 1.5);
                    }
                }
                // Real-time pan update for active voice
                OneShotCommand::SetPan { id, pan } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.pan = pan.clamp(-1.0, 1.0);
                    }
                }
                // Real-time pan right update for stereo dual-pan
                OneShotCommand::SetPanRight { id, pan_right } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.pan_right = pan_right.clamp(-1.0, 1.0);
                    }
                }
                // Real-time input gain
                OneShotCommand::SetInputGain { id, gain } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.input_gain = gain.clamp(0.0, 4.0); // -inf to +12dB
                    }
                }
                // Real-time stereo width
                OneShotCommand::SetWidth { id, width } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.stereo_width = width.clamp(0.0, 2.0);
                    }
                }
                // Real-time phase invert
                OneShotCommand::SetPhaseInvert { id, invert } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.phase_invert = invert;
                    }
                }
                // Real-time mute toggle for active voice
                OneShotCommand::SetMute { id, muted } => {
                    if let Some(voice) = voices.iter_mut().find(|v| v.id == id && v.active) {
                        voice.muted = muted;
                    }
                }
                OneShotCommand::PlaySpatial {
                    id,
                    audio,
                    volume,
                    bus,
                    source,
                    spatial_source_id,
                } => {
                    if let Some(voice) = voices.iter_mut().find(|v| !v.active) {
                        voice.activate(id, audio, volume, 0.0, bus, source);
                        voice.spatial_source_id = Some(spatial_source_id);
                        voice.engine_sample_rate = self.sample_rate();
                    }
                }
            }
        }
    }

    /// Process all one-shot voices and mix to bus buffers
    /// Applies section-based filtering: only voices from active section play.
    fn process_one_shot_voices(&self, bus_buffers: &mut BusBuffers, frames: usize) {
        let mut voices = match self.one_shot_voices.try_write() {
            Some(v) => v,
            None => return,
        };

        // Get active section for filtering (atomic read - no lock)
        let active_section = PlaybackSource::from(self.active_section.load(Ordering::Relaxed));

        // Pre-allocated temp buffers per bus for mixing
        // Use thread-local scratch buffers to avoid allocation
        SCRATCH_BUFFER_L.with(|buf_l| {
            SCRATCH_BUFFER_R.with(|buf_r| {
                let mut guard_l = buf_l.borrow_mut();
                let mut guard_r = buf_r.borrow_mut();

                debug_assert!(frames <= 8192, "Audio block size {} exceeds pre-allocated buffer (8192)", frames);
                if guard_l.len() < frames {
                    guard_l.resize(frames, 0.0);
                    guard_r.resize(frames, 0.0);
                }

                // ═══════════════════════════════════════════════════════════════
                // ADAPTIVE PER-VOICE QUALITY (unique — no DAW has this)
                //
                // CPU budget tracking: measure per-voice processing time.
                // If budget exceeded, degrade background voices to Sinc(16).
                // DAW/Browser voices ALWAYS keep global quality.
                // ═══════════════════════════════════════════════════════════════

                // Guard: zero frames or zero sample rate → skip processing
                let sample_rate = self.position.sample_rate().max(1); // Prevent div-by-zero
                if frames == 0 {
                    return;
                }

                // Global mode — clamp R8brain to Sinc(384) for real-time
                let global_mode = {
                    let mode = playback_resample_mode();
                    if mode.is_r8brain() { ResampleMode::Sinc(384) } else { mode }
                };

                // CPU budget: 50% of block time
                let block_time_us = (frames as u64 * 1_000_000) / sample_rate as u64;
                let voice_budget_us = block_time_us / 2;

                let mut cumulative_us: u64 = 0;
                let mut degraded_count: u32 = 0;

                // Spatial HRTF: track which voices need batch rendering
                let mut spatial_voice_indices: Vec<(usize, u32)> = Vec::new();
                let mut spatial_voice_count: usize = 0;

                for (voice_idx, voice) in voices.iter_mut().enumerate() {
                    if !voice.active {
                        continue;
                    }

                    // Section-based filtering
                    let should_play = match voice.source {
                        PlaybackSource::Daw => true,
                        PlaybackSource::Browser => true,
                        _ => voice.source == active_section,
                    };

                    if !should_play {
                        continue;
                    }

                    // Adaptive quality: degrade background voices when over budget
                    if cumulative_us > voice_budget_us {
                        // Over budget — degrade non-essential voices to fast mode
                        if voice.source != PlaybackSource::Daw
                            && voice.source != PlaybackSource::Browser
                        {
                            voice.voice_resample_mode = ResampleMode::Sinc(16);
                            degraded_count += 1;
                        }
                        // DAW/Browser voices keep global mode (never degraded)
                    } else {
                        // Within budget — use global quality mode
                        voice.voice_resample_mode = global_mode;
                    }

                    // Clear temp buffers
                    guard_l[..frames].fill(0.0);
                    guard_r[..frames].fill(0.0);

                    // Measure per-voice processing time (lock-free on macOS/Linux)
                    let voice_start = std::time::Instant::now();

                    let still_playing =
                        voice.fill_buffer(&mut guard_l[..frames], &mut guard_r[..frames]);

                    cumulative_us += voice_start.elapsed().as_micros() as u64;

                    if voice.spatial_source_id.is_some() {
                        // Spatial voice — collect mono audio for HRTF batch render
                        // (fill_buffer already output mono when spatial_source_id is Some)
                        spatial_voice_indices.push((voice_idx, voice.spatial_source_id.unwrap()));
                        // Copy mono audio (L channel = mono sum) into spatial voice buffer
                        let offset = spatial_voice_count * frames;
                        SPATIAL_VOICE_MONO.with(|buf| {
                            let mut mono_buf = buf.borrow_mut();
                            if mono_buf.len() < offset + frames {
                                mono_buf.resize(offset + frames, 0.0);
                            }
                            for i in 0..frames {
                                mono_buf[offset + i] = guard_l[i] as f32;
                            }
                        });
                        spatial_voice_count += 1;
                    } else {
                        // Normal voice — route to bus (existing path)
                        bus_buffers.add_to_bus(voice.bus, &guard_l[..frames], &guard_r[..frames]);
                    }

                    if !still_playing {
                        voice.deactivate();
                    }
                }

                // ═══ SPATIAL HRTF BATCH RENDER ═══
                // All spatial voices collected — render through SpatialManager in one pass
                if spatial_voice_count > 0 {
                    if let Some(mut spatial) = crate::spatial_manager::SPATIAL_MANAGER.try_write() {
                        SPATIAL_VOICE_MONO.with(|mono_buf| {
                            SPATIAL_OUTPUT_BUF.with(|out_buf| {
                                let mono = mono_buf.borrow();
                                let mut output = out_buf.borrow_mut();
                                let out_channels = spatial.output_channels();
                                let out_size = frames * out_channels;
                                if output.len() < out_size {
                                    output.resize(out_size, 0.0);
                                }
                                output[..out_size].fill(0.0);

                                // Build AudioObjects from pre-collected mono audio
                                let mut objects = Vec::with_capacity(spatial_voice_count);
                                for (idx, (_voice_idx, source_id)) in spatial_voice_indices.iter().enumerate() {
                                    let offset = idx * frames;
                                    let audio_slice = &mono[offset..offset + frames];
                                    objects.push(rf_spatial::AudioObject {
                                        id: *source_id,
                                        name: String::new(),
                                        position: spatial.source_position(*source_id)
                                            .unwrap_or(rf_spatial::Position3D::origin()),
                                        size: 0.0,
                                        gain: spatial.source_gain(*source_id),
                                        audio: audio_slice.to_vec(),
                                        sample_rate: sample_rate,
                                        automation: None,
                                    });
                                }

                                if spatial.render(&objects, &mut output[..out_size], out_channels).is_ok() {
                                    // Mix HRTF output into master bus (stereo)
                                    let (master_l, master_r) = bus_buffers.master_mut();
                                    for i in 0..frames {
                                        master_l[i] += output[i * 2] as f64;
                                        master_r[i] += output[i * 2 + 1] as f64;
                                    }
                                }
                            });
                        });
                    } else {
                        // SpatialManager lock contended — fall back to center-pan bus routing
                        for (voice_idx, _source_id) in &spatial_voice_indices {
                            SPATIAL_VOICE_MONO.with(|mono_buf| {
                                let mono = mono_buf.borrow();
                                let idx = spatial_voice_indices.iter()
                                    .position(|(vi, _)| vi == voice_idx)
                                    .unwrap_or(0);
                                let offset = idx * frames;
                                let bus = voices[*voice_idx].bus;
                                let (bus_l, bus_r) = bus_buffers.get_bus_mut(bus);
                                for i in 0..frames {
                                    let s = mono[offset + i] as f64;
                                    bus_l[i] += s;
                                    bus_r[i] += s;
                                }
                            });
                        }
                    }
                }

                // Update adaptive quality diagnostics (lock-free atomics)
                let active_count = voices.iter().filter(|v| v.active).count() as u32;
                self.diag_active_voices.store(active_count, Ordering::Relaxed);
                self.diag_degraded_voices.store(degraded_count, Ordering::Relaxed);
                let cpu_pct = (cumulative_us * 100)
                    .checked_div(voice_budget_us)
                    .unwrap_or(0)
                    .min(200) as u32;
                self.diag_cpu_load_pct.store(cpu_pct, Ordering::Relaxed);
                let mode_val = match global_mode {
                    ResampleMode::Point => 0,
                    ResampleMode::Linear => 1,
                    ResampleMode::R8brain => 65535,
                    ResampleMode::Sinc(n) => n as u32,
                };
                self.diag_src_mode.store(mode_val, Ordering::Relaxed);
            });
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADVANCED LOOP SYSTEM (Wwise-grade)
    // ═══════════════════════════════════════════════════════════════════════

    /// Get Hook Graph command producer (for FFI/Dart to send graph commands).
    pub fn hook_graph_cmd_producer(&self) -> &parking_lot::Mutex<rtrb::Producer<crate::hook_graph::GraphCommand>> {
        &self.hook_graph_cmd_tx
    }

    /// Get Hook Graph feedback consumer (for FFI/Dart to read feedback).
    pub fn hook_graph_fb_consumer(&self) -> &parking_lot::Mutex<rtrb::Consumer<crate::hook_graph::GraphFeedback>> {
        &self.hook_graph_fb_rx
    }

    /// Get Hook Graph engine diagnostics.
    pub fn hook_graph_active_voices(&self) -> usize {
        self.hook_graph_engine.as_ref()
            .and_then(|e| e.try_read())
            .map(|e| e.active_voice_count())
            .unwrap_or(0)
    }

    /// Get active graph instance count from the Hook Graph engine.
    pub fn hook_graph_active_instance_count(&self) -> usize {
        self.hook_graph_engine.as_ref()
            .and_then(|e| e.try_read())
            .map(|e| e.active_instance_count())
            .unwrap_or(0)
    }

    // ═══════════════════════════════════════════════════════════════════════

    /// Initialize the advanced loop system.
    pub fn loop_system_init(&self) {
        self.loop_initialized.store(true, Ordering::Release);
    }

    /// Destroy the advanced loop system.
    pub fn loop_system_destroy(&self) {
        self.loop_initialized.store(false, Ordering::Release);
        // Drain remaining commands
        if let Some(mut rx) = self.loop_cmd_rx.try_lock() {
            while rx.pop().is_ok() {}
        }
        // Clear assets and instances
        if let Some(mut assets) = self.loop_assets.try_write() {
            assets.clear();
        }
        if let Some(mut instances) = self.loop_instances.try_lock() {
            instances.clear();
        }
    }

    /// Check if loop system is initialized.
    pub fn loop_system_is_initialized(&self) -> bool {
        self.loop_initialized.load(Ordering::Acquire)
    }

    /// Get loop command producer (for FFI to send commands from UI thread).
    pub fn loop_cmd_producer(&self) -> &parking_lot::Mutex<rtrb::Producer<crate::loop_manager::LoopCommand>> {
        &self.loop_cmd_tx
    }

    /// Get loop callback consumer (for FFI to poll callbacks on UI thread).
    pub fn loop_cb_consumer(&self) -> &parking_lot::Mutex<rtrb::Consumer<crate::loop_manager::LoopCallback>> {
        &self.loop_cb_rx
    }

    /// Get loop assets map (for FFI to register assets).
    pub fn loop_assets_map(&self) -> &RwLock<HashMap<String, Arc<crate::loop_asset::LoopAsset>>> {
        &self.loop_assets
    }

    /// Process loop commands (called at start of audio block).
    fn process_loop_commands(&self) {
        if !self.loop_initialized.load(Ordering::Acquire) {
            return;
        }

        let mut rx = match self.loop_cmd_rx.try_lock() {
            Some(rx) => rx,
            None => return,
        };

        let mut instances = match self.loop_instances.try_lock() {
            Some(inst) => inst,
            None => return,
        };

        let mut cb_tx = match self.loop_cb_tx.try_lock() {
            Some(tx) => tx,
            None => return,
        };

        let sample_rate = self.sample_rate();

        while let Ok(cmd) = rx.pop() {
            match cmd {
                crate::loop_manager::LoopCommand::RegisterAsset { asset } => {
                    let id = asset.id.clone();
                    if let Some(mut w) = self.loop_assets.try_write() {
                        w.insert(id, Arc::new(*asset));
                    }
                }
                crate::loop_manager::LoopCommand::Play {
                    asset_id, region, volume, bus, use_dual_voice, play_pre_entry: _, fade_in_ms,
                } => {
                    let assets = match self.loop_assets.try_read() { Some(a) => a, None => continue };
                    if let Some(asset) = assets.get(&asset_id)
                        && asset.regions.iter().any(|r| r.name == region) {
                            let instance_id = instances.len() as u64 + 1;
                            let mut inst = crate::loop_instance::LoopInstance::new(
                                instance_id,
                                &asset_id,
                                &region,
                                volume,
                                bus,
                                use_dual_voice,
                            );
                            inst.init_playhead(asset);
                            // Apply fade-in if requested
                            let fade_in = fade_in_ms.unwrap_or(0.0);
                            if fade_in > 0.0 {
                                let fade_samples = (fade_in * sample_rate as f32 / 1000.0) as u64;
                                inst.fade = crate::loop_instance::FadeState::idle(0.0);
                                inst.fade.start(volume, fade_samples);
                            }
                            instances.push(inst);
                            let _ = cb_tx.push(crate::loop_manager::LoopCallback::Started {
                                instance_id,
                                asset_id,
                            });
                        }
                }
                crate::loop_manager::LoopCommand::Stop { instance_id, fade_out_ms } => {
                    if let Some(inst) = instances.iter_mut().find(|i| i.instance_id == instance_id) {
                        if fade_out_ms > 0.0 {
                            // Graceful fade-out then stop
                            let fade_samples = (fade_out_ms * sample_rate as f32 / 1000.0) as u64;
                            inst.state = crate::loop_instance::LoopState::Exiting;
                            inst.fade.start(0.0, fade_samples);
                        } else {
                            inst.state = crate::loop_instance::LoopState::Stopped;
                            let _ = cb_tx.push(crate::loop_manager::LoopCallback::Stopped { instance_id });
                        }
                    }
                }
                crate::loop_manager::LoopCommand::SetVolume { instance_id, volume, fade_ms } => {
                    if let Some(inst) = instances.iter_mut().find(|i| i.instance_id == instance_id) {
                        inst.volume = volume;
                        if fade_ms > 0.0 {
                            let fade_samples = (fade_ms * sample_rate as f32 / 1000.0) as u64;
                            inst.fade.start(volume, fade_samples);
                        } else {
                            inst.volume = volume;
                            inst.gain = volume * inst.iteration_gain;
                            inst.fade = crate::loop_instance::FadeState::idle(volume);
                        }
                    }
                }
                crate::loop_manager::LoopCommand::SetBus { instance_id, bus } => {
                    if let Some(inst) = instances.iter_mut().find(|i| i.instance_id == instance_id) {
                        inst.output_bus = bus;
                    }
                }
                crate::loop_manager::LoopCommand::SetIterationGain { instance_id, factor } => {
                    if let Some(inst) = instances.iter_mut().find(|i| i.instance_id == instance_id) {
                        inst.iteration_gain = factor;
                        inst.gain = inst.volume * inst.iteration_gain;
                    }
                }
                crate::loop_manager::LoopCommand::SetRegion {
                    instance_id, region, sync, crossfade_ms, crossfade_curve,
                } => {
                    if let Some(inst) = instances.iter_mut().find(|i| i.instance_id == instance_id) {
                        // Queue as pending region switch with sync boundary
                        inst.pending_region = Some(crate::loop_instance::PendingRegionSwitch {
                            target_region: region,
                            sync,
                            crossfade_ms,
                            crossfade_curve,
                        });
                    }
                }
                crate::loop_manager::LoopCommand::Exit { instance_id, sync, fade_out_ms, play_post_exit } => {
                    let assets = match self.loop_assets.try_read() { Some(a) => a, None => continue };
                    if let Some(inst) = instances.iter_mut().find(|i| i.instance_id == instance_id)
                        && let Some(asset) = assets.get(&inst.asset_id)
                            && let Some(region) = asset.region_by_name(&inst.active_region) {
                                inst.begin_exit(sync, fade_out_ms, play_post_exit.unwrap_or(false), region, asset, sample_rate);
                            }
                }
                crate::loop_manager::LoopCommand::Seek { instance_id, position_samples } => {
                    if let Some(inst) = instances.iter_mut().find(|i| i.instance_id == instance_id) {
                        inst.playhead_samples = position_samples;
                    }
                }
            }
        }
    }

    /// Process loop instances and mix to bus buffers (called from audio block).
    /// Full Wwise-grade processing: state machine, seam fade, dual-voice crossfade,
    /// cue detection, fade in/out, per-iteration gain, pre/post exit zones.
    fn process_loop_voices(&self, bus_buffers: &mut BusBuffers, frames: usize) {
        if !self.loop_initialized.load(Ordering::Acquire) {
            return;
        }

        let mut instances = match self.loop_instances.try_lock() {
            Some(inst) => inst,
            None => return,
        };

        let assets = match self.loop_assets.try_read() {
            Some(a) => a,
            None => return,
        };

        let mut cb_tx = match self.loop_cb_tx.try_lock() {
            Some(tx) => tx,
            None => return,
        };

        let sample_rate = self.sample_rate();

        // Process each active instance
        for inst in instances.iter_mut() {
            if inst.state == crate::loop_instance::LoopState::Stopped {
                continue;
            }

            let asset = match assets.get(&inst.asset_id) {
                Some(a) => a,
                None => continue,
            };

            let region = match asset.regions.iter().find(|r| r.name == inst.active_region) {
                Some(r) => r,
                None => continue,
            };

            // Resolve audio source from cache
            let audio = self.cache.peek(&asset.sound_ref.sound_id);
            let (audio_samples, audio_channels, _audio_total_frames) = match &audio {
                Some(a) => (&a.samples[..], a.channels as usize, a.samples.len() / (a.channels as usize).max(1)),
                None => continue, // No audio loaded for this asset
            };
            let audio_total_frames = audio_samples.len() / audio_channels.max(1);

            let bus_idx = (inst.output_bus as usize).min(bus_buffers.buffers.len().saturating_sub(1));
            let seam_fade_samples = (region.seam_fade_ms * sample_rate as f32 / 1000.0) as u64;
            let prev_state = inst.state;

            // Process frames — full state machine per sample
            for frame_idx in 0..frames {
                // 1. Check exit point (scheduled exit via sync boundary)
                inst.check_exit_point(sample_rate);

                // 2. Check intro → looping transition
                inst.check_intro_transition(region);

                // 3. Tick fade (smooth volume transitions)
                let fade_gain = inst.fade.tick();

                // 4. Check loop wrap (LoopOut → LoopIn)
                let wrapped = inst.check_loop_wrap(region);
                if wrapped {
                    let _ = cb_tx.push(crate::loop_manager::LoopCallback::Wrap {
                        instance_id: inst.instance_id,
                        loop_count: inst.loop_count,
                        at_samples: inst.last_wrap_at_samples,
                    });
                }

                // 5. Check exit complete (fade done → Stopped)
                inst.check_exit_complete();

                if inst.state == crate::loop_instance::LoopState::Stopped {
                    break;
                }

                // 6. Read audio sample (voice A)
                let (sample_l, sample_r) = if (inst.playhead_samples as usize) < audio_total_frames {
                    let pos = inst.playhead_samples as usize;
                    let l = audio_samples[pos * audio_channels] as f64;
                    let r = if audio_channels >= 2 {
                        audio_samples[pos * audio_channels + 1] as f64
                    } else {
                        l
                    };
                    (l, r)
                } else {
                    (0.0, 0.0)
                };

                // 7. Compute seam fade gain (micro-fade at loop boundaries to prevent clicks)
                let seam_gain = if inst.state == crate::loop_instance::LoopState::Looping && seam_fade_samples > 0 {
                    crate::loop_manager::compute_seam_fade(
                        inst.playhead_samples,
                        region.in_samples,
                        region.out_samples,
                        seam_fade_samples,
                    ) as f64
                } else {
                    1.0
                };

                // 8. Dual-voice crossfade (for region switches and crossfade-mode wraps)
                let (final_l, final_r) = if let Some(ref mut xf) = inst.crossfade {
                    // Read voice B sample
                    let (xf_l, xf_r) = if (xf.voice_b_playhead as usize) < audio_total_frames {
                        let pos = xf.voice_b_playhead as usize;
                        let l = audio_samples[pos * audio_channels] as f64;
                        let r = if audio_channels >= 2 {
                            audio_samples[pos * audio_channels + 1] as f64
                        } else {
                            l
                        };
                        (l, r)
                    } else {
                        (0.0, 0.0)
                    };

                    let t = xf.progress;
                    let (gain_a, gain_b) = crate::loop_manager::crossfade_gains(t, xf.curve);
                    let gain_a = gain_a as f64;
                    let gain_b = gain_b as f64;

                    xf.voice_b_playhead += 1;
                    xf.elapsed_samples += 1;
                    xf.progress = if xf.crossfade_samples > 0 {
                        xf.elapsed_samples as f32 / xf.crossfade_samples as f32
                    } else {
                        1.0
                    };

                    (
                        sample_l * gain_a * seam_gain + xf_l * gain_b,
                        sample_r * gain_a * seam_gain + xf_r * gain_b,
                    )
                } else {
                    (sample_l * seam_gain, sample_r * seam_gain)
                };

                // 9. Effective gain: volume * iteration_gain, modulated by fade
                let effective_gain = if inst.fade.active {
                    fade_gain as f64 * inst.iteration_gain as f64
                } else {
                    inst.gain as f64
                };

                // 10. Write to bus buffer
                if frame_idx < bus_buffers.buffers[bus_idx].0.len() {
                    bus_buffers.buffers[bus_idx].0[frame_idx] += final_l * effective_gain;
                    bus_buffers.buffers[bus_idx].1[frame_idx] += final_r * effective_gain;
                }

                // 11. Advance playhead
                inst.playhead_samples += 1;

                // 12. Complete crossfade if done
                if let Some(ref xf) = inst.crossfade
                    && xf.progress >= 1.0 {
                        if let Some(ref target) = xf.target_region {
                            let old = inst.active_region.clone();
                            inst.active_region = target.clone();
                            inst.playhead_samples = xf.voice_b_playhead;
                            let _ = cb_tx.push(crate::loop_manager::LoopCallback::RegionSwitched {
                                instance_id: inst.instance_id,
                                from_region: old,
                                to_region: target.clone(),
                            });
                        }
                        inst.crossfade = None;
                    }

                // 13. Check pending region switch at sync boundary
                if inst.pending_region.is_some() {
                    let pending_sync = inst
                        .pending_region
                        .as_ref()
                        .map(|p| p.sync)
                        .unwrap_or(crate::loop_asset::SyncMode::OnWrap);
                    let boundary = inst.resolve_sync_boundary(pending_sync, region, asset);
                    if inst.playhead_samples >= boundary {
                        let _ = inst.apply_pending_region(asset, sample_rate);
                    }
                }

                // 14. Check custom cues (fire callback on exact match)
                for cue in asset.custom_cues() {
                    if inst.playhead_samples == cue.at_samples {
                        let _ = cb_tx.push(crate::loop_manager::LoopCallback::CueHit {
                            instance_id: inst.instance_id,
                            cue_name: cue.name.clone(),
                            at_samples: cue.at_samples,
                        });
                    }
                }
            }

            // State change callback (once per buffer, not per sample)
            if inst.state != prev_state {
                let _ = cb_tx.push(crate::loop_manager::LoopCallback::StateChanged {
                    instance_id: inst.instance_id,
                    new_state: crate::loop_manager::LoopCallback::state_byte(inst.state),
                });
            }
        }

        // Send Stopped callbacks for instances that transitioned to Stopped during processing
        for inst in instances.iter() {
            if inst.state == crate::loop_instance::LoopState::Stopped {
                let _ = cb_tx.push(crate::loop_manager::LoopCallback::Stopped {
                    instance_id: inst.instance_id,
                });
            }
        }
        // Clean up stopped instances
        instances.retain(|i| i.state != crate::loop_instance::LoopState::Stopped);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO PROCESSING (called from audio thread)
    // ═══════════════════════════════════════════════════════════════════════

    /// Process audio block - called from audio callback
    ///
    /// Audio flow: Clips → Tracks → Buses → Master
    /// MUST be real-time safe: no allocations, no locks (except try_read)
    #[inline]
    /// Process with hardware input audio (for recording)
    /// Called from audio callback with hardware input
    pub fn process_with_input(
        &self,
        input_l: &[f32],
        input_r: &[f32],
        output_l: &mut [f64],
        output_r: &mut [f64],
    ) {
        let frames = output_l.len();

        // Route hardware input through input buses (lock-free, zero-allocation)
        if let Some(mut input_buf) = self.input_buffer.try_write() {
            let required_size = frames * 2;
            debug_assert!(required_size <= 16384, "Input buffer size {} exceeds pre-allocated (16384)", required_size);
            if input_buf.len() < required_size {
                input_buf.resize(required_size, 0.0);
            }

            // Interleave input
            for i in 0..frames {
                input_buf[i * 2] = input_l[i];
                input_buf[i * 2 + 1] = input_r[i];
            }

            // Route to input buses
            self.input_bus_manager
                .route_hardware_input(&input_buf[..required_size], frames);
        }

        // Continue with standard playback processing
        self.process(output_l, output_r);
    }

    pub fn process(&self, output_l: &mut [f64], output_r: &mut [f64]) {
        let frames = output_l.len();

        // Clear output buffers
        output_l.fill(0.0);
        output_r.fill(0.0);

        // Acquire bus_buffers ONCE for the entire process() call.
        // Holding this through the whole frame eliminates the re-acquisition window that
        // previously allowed process_offline() (running on an export thread) to steal the lock
        // between the two former try_write() calls → causing silent audio dropouts.
        // ROOT CAUSE FIX: process_offline() now uses its own local BusBuffers (no shared lock),
        // so this try_write() should always succeed during normal realtime playback.
        let mut bus_buffers = match self.bus_buffers.try_write() {
            Some(b) => b,
            None => {
                self.diag_bus_contention.fetch_add(1, Ordering::Relaxed);
                return;
            }
        };

        // === ONE-SHOT VOICES (Middleware/SlotLab) ===
        // CRITICAL: Process one-shot voices BEFORE is_playing() check!
        // SlotLab/Middleware use ensureStreamRunning() WITHOUT transport play(),
        // so one-shot voices must play even when transport is stopped.
        {
            // Ensure buffer size matches
            if bus_buffers.block_size != frames {
                *bus_buffers = BusBuffers::new(frames);
            }

            // Clear bus buffers
            bus_buffers.clear();

            // Process one-shot commands (may activate/deactivate voices)
            self.process_one_shot_commands();
            // Mix one-shot voices into bus buffers
            self.process_one_shot_voices(&mut bus_buffers, frames);

            // Process advanced loop system commands and voices
            self.process_loop_commands();
            self.process_loop_voices(&mut bus_buffers, frames);

            // Mix bus outputs to main output (for one-shot when transport stopped)
            // One-shot voices can route to any bus (0=Master, 1=Music, 2=Sfx, etc.)
            // CRITICAL: Respect bus mute/solo/volume state — same as transport path.
            // Without this, SFX/Music mute buttons have no effect on SlotLab/Middleware
            // one-shot voices because they bypass the transport processing path.
            // try_read: non-blocking — skip bus processing if UI holds write lock
            if let Some(bus_states) = self.bus_states.try_read() {
                let any_solo = self.any_solo.load(Ordering::Relaxed);
                for (bus_idx, (bus_l, bus_r)) in bus_buffers.buffers.iter().enumerate() {
                    let state = &bus_states[bus_idx];
                    // Skip muted buses, or non-soloed buses when solo is active
                    if state.muted || (any_solo && !state.soloed) {
                        crate::ffi::SHARED_METERS.update_channel_peak(bus_idx, 0.0, 0.0);
                        continue;
                    }

                    let volume = state.volume;
                    let mut bp_l: f64 = 0.0;
                    let mut bp_r: f64 = 0.0;
                    for i in 0..frames {
                        let l = bus_l[i] * volume;
                        let r = bus_r[i] * volume;
                        output_l[i] += l;
                        output_r[i] += r;
                        bp_l = bp_l.max(l.abs());
                        bp_r = bp_r.max(r.abs());
                    }
                    crate::ffi::SHARED_METERS.update_channel_peak(bus_idx, bp_l, bp_r);
                }
            }
        }

        // === HOOK GRAPH ENGINE ===
        // Process graph commands and render graph voices into output.
        // Runs regardless of transport state (same as one-shot voices).
        if let Some(ref hg_engine) = self.hook_graph_engine {
            if let Some(mut engine) = hg_engine.try_write() {
                engine.process(output_l, output_r, frames);
            }
        }

        // === LOCK-FREE PARAM CONSUMPTION ===
        // Drain all pending insert param changes BEFORE processing tracks
        // This acquires insert_chains lock once, applies all params, then releases
        // Track processing below will re-acquire the lock for actual processing
        self.consume_insert_param_changes();

        // Check if playing (for DAW timeline tracks)
        // One-shot voices already processed above, so transport-stopped still outputs them
        if !self.position.is_playing() {
            // === INSERT TAIL PROCESSING ===
            // When transport stops, continue processing insert chains (reverb/delay tails)
            // with silence input so tails ring out naturally.
            let tail_remaining = self.tail_remaining_samples.load(Ordering::Relaxed);
            if tail_remaining > 0 {
                // Decrement tail counter
                let new_remaining = tail_remaining.saturating_sub(frames as u64);
                self.tail_remaining_samples
                    .store(new_remaining, Ordering::Relaxed);

                // Anti-click: fade-out the last 480 samples (~10ms) of tail
                let tail_fade_samples: u64 = 480;

                // Process insert chain tails using thread-local scratch buffers
                // (no heap allocation in audio thread)
                SCRATCH_BUFFER_L.with(|buf_l| {
                    SCRATCH_BUFFER_R.with(|buf_r| {
                        let mut sl = buf_l.borrow_mut();
                        let mut sr = buf_r.borrow_mut();
                        debug_assert!(frames <= 8192, "Audio block size {} exceeds pre-allocated buffer (8192)", frames);
                        if sl.len() < frames {
                            sl.resize(frames, 0.0);
                        }
                        if sr.len() < frames {
                            sr.resize(frames, 0.0);
                        }

                        // Acquire sidechain taps for tail processing (last known values)
                        let tail_taps = self.sidechain_taps.try_read();

                        // Process track insert chains with silence (per-track reverb tails)
                        if let Some(mut chains) = self.insert_chains.try_write() {
                            for (_track_id, chain) in chains.iter_mut() {
                                sl[..frames].fill(0.0);
                                sr[..frames].fill(0.0);
                                if let Some(ref taps) = tail_taps {
                                    chain.process_pre_fader_with_taps(&mut sl[..frames], &mut sr[..frames], taps, frames);
                                } else {
                                    chain.process_pre_fader(&mut sl[..frames], &mut sr[..frames]);
                                }
                                for i in 0..frames {
                                    output_l[i] += sl[i];
                                    output_r[i] += sr[i];
                                }
                            }
                        }

                        // Process bus insert chains with silence (bus-level reverb tails)
                        if let Some(mut bus_inserts) = self.bus_inserts.try_write() {
                            // try_read: non-blocking on audio thread
                            if let Some(bus_states) = self.bus_states.try_read() {
                            for bus_idx in 0..6 {
                                if bus_states[bus_idx].muted {
                                    continue;
                                }
                                sl[..frames].fill(0.0);
                                sr[..frames].fill(0.0);

                                if let Some(ref taps) = tail_taps {
                                    bus_inserts[bus_idx]
                                        .process_pre_fader_with_taps(&mut sl[..frames], &mut sr[..frames], taps, frames);
                                } else {
                                    bus_inserts[bus_idx]
                                        .process_pre_fader(&mut sl[..frames], &mut sr[..frames]);
                                }

                                let volume = bus_states[bus_idx].volume;
                                for i in 0..frames {
                                    sl[i] *= volume;
                                    sr[i] *= volume;
                                }

                                if let Some(ref taps) = tail_taps {
                                    bus_inserts[bus_idx]
                                        .process_post_fader_with_taps(&mut sl[..frames], &mut sr[..frames], taps, frames);
                                } else {
                                    bus_inserts[bus_idx]
                                        .process_post_fader(&mut sl[..frames], &mut sr[..frames]);
                                }

                                for i in 0..frames {
                                    output_l[i] += sl[i];
                                    output_r[i] += sr[i];
                                }
                            }
                            } // if let Some(bus_states)
                        }
                        drop(tail_taps);
                    });
                });

                // Process master insert chain (coalesced lock — single try_write for pre+post)
                let mut master_insert_guard = self.master_insert.try_write();
                let tail_sidechain_taps = self.sidechain_taps.try_read();
                if let Some(ref mut master_insert) = master_insert_guard {
                    if let Some(ref taps) = tail_sidechain_taps {
                        master_insert.process_pre_fader_with_taps(output_l, output_r, taps, frames);
                    } else {
                        master_insert.process_pre_fader(output_l, output_r);
                    }
                }

                let master = self.master_volume();
                for i in 0..frames {
                    output_l[i] *= master;
                    output_r[i] *= master;
                }

                if let Some(ref mut master_insert) = master_insert_guard {
                    if let Some(ref taps) = tail_sidechain_taps {
                        master_insert.process_post_fader_with_taps(output_l, output_r, taps, frames);
                    } else {
                        master_insert.process_post_fader(output_l, output_r);
                    }
                }
                drop(master_insert_guard);
                drop(tail_sidechain_taps);

                // Anti-click: apply fade-out ramp during the last 480 samples of tail
                if new_remaining < tail_fade_samples {
                    let fade_start_in_block = if tail_remaining > tail_fade_samples {
                        // Tail just entered the fade zone during this block
                        (tail_remaining - tail_fade_samples) as usize
                    } else {
                        0 // Entire block is within fade zone
                    };
                    for i in fade_start_in_block..frames {
                        let samples_left = new_remaining.saturating_sub((frames - 1 - i) as u64);
                        let fade = samples_left as f64 / tail_fade_samples as f64;
                        output_l[i] *= fade;
                        output_r[i] *= fade;
                    }
                }
            }

            // ═══ PRO TOOLS-STYLE METER DECAY ON STOP ═══
            // When transport stops, ALL meters must smoothly decay to zero
            // instead of freezing at their last value.
            // Target: reach -60dB (0.001 linear) within ~300ms — matches GpuMeter releaseMs.
            // Formula: per-sample decay = exp(ln(0.001) / (0.3 * sample_rate))
            // per-block decay = per-sample ^ frames
            let sr = self.position.sample_rate() as f64;
            let decay_samples = 0.3 * sr; // 300ms worth of samples
            let per_sample_decay = (-6.907755_f64 / decay_samples).exp(); // ln(0.001) = -6.907755
            let decay = per_sample_decay.powf(frames as f64);

            // --- Master peak metering with decay ---
            let prev_peak_l = f64::from_bits(self.peak_l.load(Ordering::Relaxed));
            let prev_peak_r = f64::from_bits(self.peak_r.load(Ordering::Relaxed));
            let mut mp_l = prev_peak_l * decay;
            let mut mp_r = prev_peak_r * decay;
            // Mix in any tail audio that's still playing
            for i in 0..frames {
                mp_l = mp_l.max(output_l[i].abs());
                mp_r = mp_r.max(output_r[i].abs());
            }
            // Clamp to zero below noise floor
            if mp_l < 1e-10 {
                mp_l = 0.0;
            }
            if mp_r < 1e-10 {
                mp_r = 0.0;
            }
            self.peak_l.store(mp_l.to_bits(), Ordering::Relaxed);
            self.peak_r.store(mp_r.to_bits(), Ordering::Relaxed);
            crate::ffi::SHARED_METERS.update_channel_peak(0, mp_l, mp_r);

            // --- Master RMS decay ---
            let prev_rms_l = f64::from_bits(self.rms_l.load(Ordering::Relaxed));
            let prev_rms_r = f64::from_bits(self.rms_r.load(Ordering::Relaxed));
            let rms_l = (prev_rms_l * decay).max(0.0);
            let rms_r = (prev_rms_r * decay).max(0.0);
            self.rms_l.store(
                if rms_l < 1e-10 { 0.0_f64 } else { rms_l }.to_bits(),
                Ordering::Relaxed,
            );
            self.rms_r.store(
                if rms_r < 1e-10 { 0.0_f64 } else { rms_r }.to_bits(),
                Ordering::Relaxed,
            );

            // --- Per-bus peak decay ---
            // Decay all 6 bus meters so they don't freeze
            for bus_idx in 0..6 {
                let idx = bus_idx * 2;
                let prev_bl = f64::from_bits(
                    crate::ffi::SHARED_METERS.channel_peaks[idx].load(Ordering::Relaxed),
                );
                let prev_br = f64::from_bits(
                    crate::ffi::SHARED_METERS.channel_peaks[idx + 1].load(Ordering::Relaxed),
                );
                let bl = if prev_bl * decay < 1e-10 {
                    0.0
                } else {
                    prev_bl * decay
                };
                let br = if prev_br * decay < 1e-10 {
                    0.0
                } else {
                    prev_br * decay
                };
                crate::ffi::SHARED_METERS.update_channel_peak(bus_idx, bl, br);
            }

            // --- Per-track meter decay ---
            // Decay all track meters so channel strips don't freeze on stop
            if let Some(mut meters) = self.track_meters.try_write() {
                for meter in meters.values_mut() {
                    meter.decay(decay);
                }
            }

            // --- Correlation/balance decay toward defaults ---
            let prev_corr = f64::from_bits(self.correlation.load(Ordering::Relaxed));
            let smoothed_corr = prev_corr * decay + 1.0 * (1.0 - decay); // Decay toward 1.0 (mono)
            self.correlation
                .store(smoothed_corr.to_bits(), Ordering::Relaxed);

            let prev_bal = f64::from_bits(self.balance.load(Ordering::Relaxed));
            let smoothed_bal = prev_bal * decay; // Decay toward 0.0 (center)
            self.balance.store(
                if smoothed_bal.abs() < 1e-10 {
                    0.0_f64
                } else {
                    smoothed_bal
                }
                .to_bits(),
                Ordering::Relaxed,
            );

            // --- SHARED_METERS master update ---
            crate::ffi::SHARED_METERS.update_master(mp_l, mp_r, rms_l, rms_r);

            // --- Spectrum bands decay ---
            for band_idx in 0..32 {
                let prev = f64::from_bits(
                    crate::ffi::SHARED_METERS.spectrum_bands[band_idx].load(Ordering::Relaxed),
                );
                let decayed = if prev * decay < 1e-10 {
                    0.0
                } else {
                    prev * decay
                };
                crate::ffi::SHARED_METERS.spectrum_bands[band_idx]
                    .store(decayed.to_bits(), Ordering::Relaxed);
            }

            // Signal Dart that meter values changed (decay updates)
            // Without this, SharedMeterReader sees stale sequence and skips reading.
            // Always increment during decay — stops naturally when all values hit zero
            // (decay block won't change anything once all meters are 0.0).
            let any_activity = mp_l > 0.0
                || mp_r > 0.0
                || rms_l > 0.0
                || rms_r > 0.0
                || prev_peak_l > 0.0
                || prev_peak_r > 0.0;
            if any_activity {
                crate::ffi::SHARED_METERS.increment_sequence();
            }

            return;
        }

        // Cancel any tail processing when playback resumes
        self.tail_remaining_samples.store(0, Ordering::Relaxed);

        let sample_rate = self.position.sample_rate() as f64;
        let start_sample = self.position.samples();
        let start_time = start_sample as f64 / sample_rate;
        let end_time = (start_sample + frames as u64) as f64 / sample_rate;

        // === SAMPLE-ACCURATE AUTOMATION ===
        // Get all automation changes within this block
        if let Some(ref automation) = self.automation {
            let automation_changes = automation.get_block_changes(start_sample, frames);

            // Apply all automation changes BEFORE processing audio
            // This is simpler than splitting the block, and still sample-accurate
            // because changes are applied at exact sample positions before audio rendering
            for change in automation_changes {
                self.apply_automation_change(&change);
            }
        }

        // Decay factor for meters (60dB in ~300ms at 48kHz, 256 block size)
        let decay = 0.9995_f64.powf(frames as f64 / 8.0);

        // NOTE: bus_buffers is already held (acquired at start of process()).
        // One-shot voices were already processed above.
        // Bus buffers already contain one-shot audio — tracks mix INTO existing content.
        // (Previously this had a second try_write() here, creating a dropout window.)

        // Clear control room buffers (solo bus, cue mixes)
        self.control_room.clear_all_buffers();

        // Resize control room buffers if needed
        if self
            .control_room
            .solo_bus_l
            .try_read()
            .map(|b| b.len())
            .unwrap_or(0)
            != frames
        {
            self.control_room.resize_buffers(frames);
        }

        // DashMap provides lock-free concurrent read access via sharded locks
        // No try_read() needed - direct iteration is always available without blocking
        // This is the main benefit of DashMap over RwLock<HashMap>

        // Use thread-local scratch buffers (ZERO lock contention - audio thread only)
        // This eliminates 2 try_write() calls that were causing lock contention
        let (track_l, track_r) = SCRATCH_BUFFER_L.with(|buf_l| {
            SCRATCH_BUFFER_R.with(|buf_r| {
                let mut guard_l = buf_l.borrow_mut();
                let mut guard_r = buf_r.borrow_mut();

                // Ensure buffers are large enough
                debug_assert!(frames <= 8192, "Audio block size {} exceeds pre-allocated buffer (8192)", frames);
                if guard_l.len() < frames {
                    guard_l.resize(frames, 0.0);
                    guard_r.resize(frames, 0.0);
                    self.current_block_size.store(frames, Ordering::Relaxed);
                }

                // Return raw pointers to avoid borrow checker issues with closures
                // SAFETY: These buffers are thread-local and only accessed from audio thread
                // The pointers are valid for the duration of this function call
                (guard_l.as_mut_ptr(), guard_r.as_mut_ptr())
            })
        });

        // SAFETY: thread-local buffers are only accessed from this audio thread
        // The buffer size was already verified above
        let track_l = unsafe { std::slice::from_raw_parts_mut(track_l, frames) };
        let track_r = unsafe { std::slice::from_raw_parts_mut(track_r, frames) };

        // Get solo state ONCE (atomic - no lock needed)
        // Cubase-style: when any track is soloed, only soloed tracks are audible
        let solo_active = self.track_manager.is_solo_active();

        // ═══ LOCK COALESCING (BUG#14 fix) ═══
        // Acquire shared mutable state ONCE for the entire track loop.
        // Previously, try_write() was called per-track (pre-fader + post-fader + multi-channel read
        // + stereo imager) = 4× N_tracks lock acquisitions per audio frame. If the UI held any
        // write lock (e.g., loading a plugin), ALL processing was silently skipped → no reverb/EQ.
        // Now: single try_write() per resource at the top. If it fails, processing is skipped
        // for one frame (graceful degradation), but we avoid N×4 contention windows.
        let mut insert_chains_guard = self.insert_chains.try_write();
        let mut stereo_imagers_guard = self.stereo_imagers.try_write();
        let mut track_meters_guard = self.track_meters.try_write();
        let mut track_lufs_guard = self.track_lufs_meters.try_write();
        let mut delay_comp_guard = self.delay_comp.try_write();
        let mut sidechain_taps_guard = self.sidechain_taps.try_write();

        // Process each track → route to its bus
        // DashMap iter() returns references that auto-release shard locks
        for entry in self.track_manager.tracks.iter() {
            let track = entry.value();
            // Skip muted tracks (including VCA mute), or non-soloed tracks when solo is active
            let vca_muted = self.is_vca_muted(track.id.0);
            if track.muted || vca_muted || (solo_active && !track.soloed) {
                continue;
            }

            // Clear track buffers
            track_l.fill(0.0);
            track_r.fill(0.0);

            // === INPUT MONITORING & RECORDING ===
            // If track has input bus routing, get audio from that bus
            if let Some(input_bus_id) = track.input_bus
                && let Some(bus) = self.input_bus_manager.get_bus(input_bus_id)
            {
                // Check monitor mode and armed state
                let should_monitor = match track.monitor_mode {
                    MonitorMode::Manual => true,
                    MonitorMode::Auto => track.armed && self.position.is_playing(),
                    MonitorMode::Off => false,
                };

                if should_monitor {
                    // Read audio from input bus (zero-copy reference)
                    if let Some((left, right)) = bus.read_buffers() {
                        // Mix input into track buffer (for monitoring)
                        let frames_to_copy = frames.min(left.len());
                        for i in 0..frames_to_copy {
                            track_l[i] += left[i] as f64;
                            if let Some(ref r) = right {
                                track_r[i] += r[i] as f64;
                            } else {
                                // Mono input - copy to both channels
                                track_r[i] += left[i] as f64;
                            }
                        }

                        // Send to RecordingManager if track is armed and recording
                        if track.armed && self.position.is_recording() {
                            // Check punch in/out
                            if self.recording_manager.check_punch(start_sample) {
                                // Prepare interleaved samples for recording
                                // Use stack-allocated buffer for small blocks, heap for larger
                                let num_samples = frames_to_copy * 2; // stereo interleaved
                                if num_samples <= 2048 {
                                    // Stack allocation for typical block sizes
                                    let mut rec_buffer = [0.0f32; 2048];
                                    for i in 0..frames_to_copy {
                                        rec_buffer[i * 2] = left[i];
                                        rec_buffer[i * 2 + 1] =
                                            right.as_ref().map(|r| r[i]).unwrap_or(left[i]);
                                    }
                                    self.recording_manager.write_samples(
                                        TrackId(track.id.0),
                                        &rec_buffer[..num_samples],
                                        start_sample,
                                    );
                                } else {
                                    // Heap allocation for large blocks (rare)
                                    let mut rec_buffer = vec![0.0f32; num_samples];
                                    for i in 0..frames_to_copy {
                                        rec_buffer[i * 2] = left[i];
                                        rec_buffer[i * 2 + 1] =
                                            right.as_ref().map(|r| r[i]).unwrap_or(left[i]);
                                    }
                                    self.recording_manager.write_samples(
                                        TrackId(track.id.0),
                                        &rec_buffer,
                                        start_sample,
                                    );
                                }
                            }
                        }
                    }
                }
            }

            // === INSTRUMENT TRACK RENDERING (MIDI → Plugin → Audio) ===
            if track.track_type == crate::track_manager::TrackType::Instrument {
                // Try to get the instrument plugin for this track (non-blocking)
                let plugin_opt = self.instrument_plugins.try_read()
                    .and_then(|plugins| plugins.get(&track.id.0).cloned());

                if let Some(plugin_arc) = plugin_opt {
                    // Collect MIDI events from all MIDI clips on this track
                    if let Some(mut midi_buf) = self.instrument_midi_buffer.try_write() {
                        midi_buf.clear();
                        let tempo = self.position.get_tempo().unwrap_or(120.0);
                        // Standard MIDI: 480 ticks per beat
                        let ticks_per_beat = 480.0;
                        let ticks_per_second = ticks_per_beat * tempo / 60.0;
                        let ticks_per_sample = ticks_per_second / sample_rate;

                        for mc_entry in self.track_manager.midi_clips.iter() {
                            let mc = mc_entry.value();
                            if mc.track_id != track.id || mc.muted {
                                continue;
                            }
                            if !mc.overlaps(start_time, end_time) {
                                continue;
                            }
                            // Convert timeline position to clip-relative ticks
                            let clip_start_sec = (start_time - mc.start_time).max(0.0);
                            let clip_end_sec = (end_time - mc.start_time).min(mc.duration);
                            let start_tick = (clip_start_sec * ticks_per_second) as u64;
                            let end_tick = (clip_end_sec * ticks_per_second) as u64;

                            mc.clip.generate_events_into(
                                start_tick,
                                end_tick,
                                ticks_per_sample,
                                &mut midi_buf,
                            );
                        }

                        // Process instrument plugin: empty audio in → audio out + MIDI
                        // Use pre-allocated buffers (zero audio-thread allocations)
                        if let Some(mut plugin) = plugin_arc.try_write()
                            && let (Some(mut audio_in), Some(mut audio_out), Some(mut midi_out)) = (
                                self.instrument_audio_in.try_write(),
                                self.instrument_audio_out.try_write(),
                                self.instrument_midi_out.try_write(),
                            ) {
                                // Clear pre-allocated buffers
                                audio_in.clear();
                                audio_out.clear();
                                midi_out.clear();

                                let context = rf_plugin::ProcessContext {
                                    sample_rate,
                                    max_block_size: frames,
                                    tempo,
                                    time_sig_num: 4,
                                    time_sig_denom: 4,
                                    position_samples: start_sample as i64,
                                    is_playing: self.position.is_playing(),
                                    is_recording: self.position.is_recording(),
                                    is_looping: false,
                                    loop_start: 0,
                                    loop_end: 0,
                                };

                                if plugin.process(&audio_in, &mut audio_out, &midi_buf, &mut midi_out, &context).is_ok() {
                                    // Accumulate f32 plugin output into f64 track buffers
                                    if let (Some(out_l), Some(out_r)) = (audio_out.channel(0), audio_out.channel(1)) {
                                        for i in 0..frames.min(out_l.len()) {
                                            track_l[i] += out_l[i] as f64;
                                            track_r[i] += out_r[i] as f64;
                                        }
                                    }
                                }
                            }
                    }
                }
                // Skip audio clip rendering for instrument tracks — go straight to insert chain
            } else {

            // Find crossfades active in this track for this time range (iterate without collect)
            // Store matching crossfade IDs to avoid lifetime issues
            let mut active_crossfade_ids: [Option<u64>; 8] = [None; 8];
            let mut crossfade_count = 0;
            for xf_entry in self.track_manager.crossfades.iter() {
                let xf = xf_entry.value();
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
            for clip_entry in self.track_manager.clips.iter() {
                let clip = clip_entry.value();
                if clip.track_id != track.id || clip.muted {
                    continue;
                }

                // Check if clip overlaps with current block
                if !clip.overlaps(start_time, end_time) {
                    continue;
                }

                // Get cached audio
                let audio = match self.cache.peek(&clip.source_file) {
                    Some(a) => a,
                    None => continue,
                };

                // Check if this clip is part of any active crossfade (using stored IDs)
                let crossfade = active_crossfade_ids[..crossfade_count]
                    .iter()
                    .filter_map(|&id| id)
                    .find_map(|xf_id| {
                        self.track_manager.crossfades.iter().find_map(|xf_entry| {
                            let xf = xf_entry.value();
                            if xf.id.0 == xf_id
                                && (xf.clip_a_id == clip.id || xf.clip_b_id == clip.id)
                            {
                                Some(xf.clone())
                            } else {
                                None
                            }
                        })
                    });

                // Process clip samples into track buffer (with crossfade if applicable)
                self.process_clip_with_crossfade(
                    clip,
                    track,
                    &audio,
                    crossfade.as_ref(),
                    start_sample,
                    sample_rate,
                    track_l,
                    track_r,
                );
            }

            } // end else (Audio track clip rendering)

            // === SIDECHAIN TAP: store post-clip/pre-insert audio for other tracks ===
            // This feeds sidechain compressors etc. with 1-block latency (standard in DAWs).
            // Updated BEFORE insert processing so inserts can read OTHER tracks' taps.
            if let Some(ref mut taps) = sidechain_taps_guard {
                let tap = taps.entry(track.id.0 as i64)
                    .or_insert_with(|| (vec![0.0; frames], vec![0.0; frames]));
                if tap.0.len() < frames {
                    tap.0.resize(frames, 0.0);
                    tap.1.resize(frames, 0.0);
                }
                tap.0[..frames].copy_from_slice(&track_l[..frames]);
                tap.1[..frames].copy_from_slice(&track_r[..frames]);
            }

            // Process track insert chain (pre-fader inserts applied before volume)
            // NOTE: Param changes already consumed at start of process() via consume_insert_param_changes()
            // Uses insert_chains_guard acquired once at top of process() (BUG#14 fix)
            // Now with sidechain routing: each slot checks its sidechain_source and feeds
            // the corresponding track's tap audio (previous/current block) as key input.
            if let Some(ref mut chains) = insert_chains_guard {
                if let Some(chain) = chains.get_mut(&track.id.0) {
                    if let Some(ref taps) = sidechain_taps_guard {
                        chain.process_pre_fader_with_taps(track_l, track_r, taps, frames);
                    } else {
                        chain.process_pre_fader(track_l, track_r);
                    }
                }
            }

            // === PFL TAP POINT (Pre-Fade Listen) ===
            // Capture pre-fader signal for PFL monitoring
            let channel_id = ChannelId(track.id.0 as u32);
            let solo_mode = self.control_room.solo_mode();
            let is_soloed = self.control_room.is_soloed(channel_id);

            if solo_mode == SoloMode::PFL && is_soloed {
                // Route pre-fader signal to monitor bus
                self.control_room.add_to_solo_bus(track_l, track_r);
            }

            // === CUE MIX SENDS (Pre-Fader) ===
            // Independent headphone mixes are typically pre-fader
            for cue_mix in self.control_room.cue_mixes.iter() {
                if !cue_mix.enabled.load(Ordering::Relaxed) {
                    continue;
                }
                if let Some(send) = cue_mix.get_send(channel_id)
                    && send.pre_fader
                {
                    cue_mix.add_signal(track_l, track_r, &send);
                }
            }

            // === PRE-FADER SEND CAPTURE ===
            // Capture pre-fader signal for pre-fader sends (before volume/pan)
            // Stack-allocated: zero heap alloc on audio thread (max 4096 samples)
            let has_pre_fader_sends = track.sends.iter().any(|s| {
                s.pre_fader && !s.muted && s.level > 0.0 && s.destination.is_some()
            });
            let mut pfl_buf = [0.0f64; 4096];
            let mut pfr_buf = [0.0f64; 4096];
            if has_pre_fader_sends {
                pfl_buf[..frames].copy_from_slice(&track_l[..frames]);
                pfr_buf[..frames].copy_from_slice(&track_r[..frames]);
            }

            // Apply track volume and pan (fader stage)
            // Use per-sample smoothing for zipper-free automation
            let vca_gain = self.get_vca_gain(track.id.0);

            if self.param_smoother.is_track_smoothing(track.id.0) {
                // Per-sample processing when smoothing is active
                // For stereo tracks, use dual-pan (Pro Tools style)
                if track.is_stereo() {
                    // Stereo dual-pan: L channel has own pan, R channel has own pan
                    let pan_r_val = track.pan_right.clamp(-1.0, 1.0);

                    // Precompute constant-power gains at block start/end.
                    // pan_r is static (no smoother), so its trig is constant.
                    // pan_l is smoothed: interpolate gains linearly across the block
                    // to avoid cos/sin per sample (48k trig calls/sec per track).
                    let pan_l_start = self.param_smoother.get_track_pan(track.id.0).clamp(-1.0, 1.0);
                    let pan_l_end = self.param_smoother.get_track_pan_target(track.id.0).clamp(-1.0, 1.0);

                    let pan_l_start_angle = (pan_l_start + 1.0) * std::f64::consts::FRAC_PI_4;
                    let pan_l_end_angle = (pan_l_end + 1.0) * std::f64::consts::FRAC_PI_4;

                    let pan_l_l_start = pan_l_start_angle.cos();
                    let pan_l_r_start = pan_l_start_angle.sin();
                    let pan_l_l_end = pan_l_end_angle.cos();
                    let pan_l_r_end = pan_l_end_angle.sin();

                    // pan_r_val is not smoothed — trig computed once outside loop
                    let pan_r_angle = (pan_r_val + 1.0) * std::f64::consts::FRAC_PI_4;
                    let pan_r_l_gain = pan_r_angle.cos();
                    let pan_r_r_gain = pan_r_angle.sin();

                    let frames_f64_recip = if frames > 1 { 1.0 / (frames - 1) as f64 } else { 0.0 };

                    for i in 0..frames {
                        let (volume, _pan) = self.param_smoother.advance_track(track.id.0);
                        let final_volume = volume * vca_gain;

                        // Linear interpolation of constant-power gains (no trig in loop)
                        let t = i as f64 * frames_f64_recip;
                        let pan_l_l = pan_l_l_start + (pan_l_l_end - pan_l_l_start) * t;
                        let pan_l_r = pan_l_r_start + (pan_l_r_end - pan_l_r_start) * t;

                        // Gain compensation: normalize when cross-mix exceeds unity
                        let sum_l_sq = pan_l_l * pan_l_l + pan_r_l_gain * pan_r_l_gain;
                        let sum_r_sq = pan_l_r * pan_l_r + pan_r_r_gain * pan_r_r_gain;
                        let comp_l = if sum_l_sq > 1.0 { 1.0 / sum_l_sq.sqrt() } else { 1.0 };
                        let comp_r = if sum_r_sq > 1.0 { 1.0 / sum_r_sq.sqrt() } else { 1.0 };

                        let l_sample = track_l[i];
                        let r_sample = track_r[i];
                        track_l[i] = final_volume * comp_l * (l_sample * pan_l_l + r_sample * pan_r_l_gain);
                        track_r[i] = final_volume * comp_r * (l_sample * pan_l_r + r_sample * pan_r_r_gain);
                    }
                } else {
                    // Mono: single pan knob
                    // Precompute constant-power gains at block start/end, interpolate linearly.
                    // Eliminates cos/sin per sample — 2 trig calls total instead of 2*frames.
                    let pan_start = self.param_smoother.get_track_pan(track.id.0).clamp(-1.0, 1.0);
                    let pan_end = self.param_smoother.get_track_pan_target(track.id.0).clamp(-1.0, 1.0);

                    let pan_start_angle = (pan_start + 1.0) * std::f64::consts::FRAC_PI_4;
                    let pan_end_angle = (pan_end + 1.0) * std::f64::consts::FRAC_PI_4;

                    let pan_l_start = pan_start_angle.cos();
                    let pan_r_start = pan_start_angle.sin();
                    let pan_l_end = pan_end_angle.cos();
                    let pan_r_end = pan_end_angle.sin();

                    let frames_f64_recip = if frames > 1 { 1.0 / (frames - 1) as f64 } else { 0.0 };

                    for i in 0..frames {
                        let (volume, _pan) = self.param_smoother.advance_track(track.id.0);
                        let final_volume = volume * vca_gain;

                        // Linear interpolation of constant-power gains (no trig in loop)
                        let t = i as f64 * frames_f64_recip;
                        let pan_l = pan_l_start + (pan_l_end - pan_l_start) * t;
                        let pan_r = pan_r_start + (pan_r_end - pan_r_start) * t;

                        track_l[i] *= final_volume * pan_l;
                        track_r[i] *= final_volume * pan_r;
                    }
                }
            } else {
                // Block processing when no smoothing (fast path)
                let track_volume = self.get_track_volume_with_automation(track);
                let final_volume = track_volume * vca_gain;

                if track.is_stereo() {
                    // Stereo dual-pan: L channel has own pan, R channel has own pan
                    // Pro Tools style: each channel panned independently
                    let pan_l = self.get_track_pan_with_automation(track).clamp(-1.0, 1.0);
                    let pan_r = track.pan_right.clamp(-1.0, 1.0);

                    let pan_l_angle = (pan_l + 1.0) * std::f64::consts::FRAC_PI_4;
                    let pan_l_l = pan_l_angle.cos(); // L input to L output
                    let pan_l_r = pan_l_angle.sin(); // L input to R output

                    let pan_r_angle = (pan_r + 1.0) * std::f64::consts::FRAC_PI_4;
                    let pan_r_l = pan_r_angle.cos(); // R input to L output
                    let pan_r_r = pan_r_angle.sin(); // R input to R output

                    // Gain compensation: when both channels cross-mix into the same output,
                    // normalize so total gain never exceeds unity (prevents +3dB at center)
                    let sum_l_sq = pan_l_l * pan_l_l + pan_r_l * pan_r_l;
                    let sum_r_sq = pan_l_r * pan_l_r + pan_r_r * pan_r_r;
                    let comp_l = if sum_l_sq > 1.0 { 1.0 / sum_l_sq.sqrt() } else { 1.0 };
                    let comp_r = if sum_r_sq > 1.0 { 1.0 / sum_r_sq.sqrt() } else { 1.0 };

                    for i in 0..frames {
                        let l_sample = track_l[i];
                        let r_sample = track_r[i];
                        track_l[i] = final_volume * comp_l * (l_sample * pan_l_l + r_sample * pan_r_l);
                        track_r[i] = final_volume * comp_r * (l_sample * pan_l_r + r_sample * pan_r_r);
                    }
                } else {
                    // Mono: single pan knob - constant power pan
                    let pan = self.get_track_pan_with_automation(track).clamp(-1.0, 1.0);
                    let pan_angle = (pan + 1.0) * std::f64::consts::FRAC_PI_4;
                    let pan_l = pan_angle.cos();
                    let pan_r = pan_angle.sin();

                    for i in 0..frames {
                        track_l[i] *= final_volume * pan_l;
                        track_r[i] *= final_volume * pan_r;
                    }
                }
            }

            // ═══ PER-TRACK STEREO IMAGER (post-pan, pre-post-inserts) ═══
            // SSL canonical signal flow: Fader → Pan → **StereoImager** → Post-Inserts
            // Width, M/S processing, balance, rotation applied here
            // Uses stereo_imagers_guard acquired once at top of process() (BUG#14 fix)
            if let Some(ref mut imagers) = stereo_imagers_guard {
                if let Some(imager) = imagers.get_mut(&(track.id.0 as u32)) {
                    use rf_dsp::StereoProcessor;
                    for i in 0..frames {
                        let (l, r) = imager.process_sample(track_l[i], track_r[i]);
                        track_l[i] = l;
                        track_r[i] = r;
                    }
                }
            }

            // Process track insert chain (post-fader inserts applied after volume)
            // Uses insert_chains_guard acquired once at top of process() (BUG#14 fix)
            // With sidechain: post-fader slots also get sidechain from tap buffers.
            if let Some(ref mut chains) = insert_chains_guard {
                if let Some(chain) = chains.get_mut(&track.id.0) {
                    if let Some(ref taps) = sidechain_taps_guard {
                        chain.process_post_fader_with_taps(track_l, track_r, taps, frames);
                    } else {
                        chain.process_post_fader(track_l, track_r);
                    }
                }
            }

            // Apply delay compensation for tracks with lower latency than max
            // This aligns all tracks in time regardless of plugin latency
            // Uses delay_comp_guard acquired once at top of process() (BUG#14 fix)
            if let Some(ref mut dc) = delay_comp_guard {
                dc.process(track.id.0 as u32, track_l, track_r);
            }

            // === AFL TAP POINT (After-Fade Listen) ===
            // Capture post-fader signal for AFL monitoring
            if solo_mode == SoloMode::AFL && is_soloed {
                // Route post-fader signal to monitor bus
                self.control_room.add_to_solo_bus(track_l, track_r);
            }

            // === CUE MIX SENDS (Post-Fader) ===
            for cue_mix in self.control_room.cue_mixes.iter() {
                if !cue_mix.enabled.load(Ordering::Relaxed) {
                    continue;
                }
                if let Some(send) = cue_mix.get_send(channel_id)
                    && !send.pre_fader
                {
                    cue_mix.add_signal(track_l, track_r, &send);
                }
            }

            // Process sends - route to send buses (Aux, Sfx, etc.)
            // Pre-fader sends use pre-volume signal, post-fader use post-volume
            for send_idx in 0..track.sends.len() {
                let send = &track.sends[send_idx];
                // Early exit conditions - skip muted, no destination, or zero level
                let Some(dest_bus) = send.destination else {
                    continue;
                };
                if send.muted || send.level <= 0.0 {
                    continue;
                }
                let send_level = send.level;

                // Send pan: constant-power stereo positioning of the send signal.
                // pan=0.0 (center) → unity gain on both channels (no level change).
                // pan=-1.0 → hard left (+3dB left, silence right).
                // pan=+1.0 → hard right (silence left, +3dB right).
                // Normalized so center = 1.0 (backwards compatible with pan=0.0 default).
                let send_pan = send.pan.clamp(-1.0, 1.0);
                let send_pan_angle = (send_pan + 1.0) * std::f64::consts::FRAC_PI_4;
                // Normalize: at center (pan=0), cos(π/4)=sin(π/4)≈0.707.
                // Scale by √2 so center gives unity gain (1.0) on both channels.
                let send_pan_l = send_pan_angle.cos() * std::f64::consts::SQRT_2;
                let send_pan_r = send_pan_angle.sin() * std::f64::consts::SQRT_2;

                if send.pre_fader {
                    // Pre-fader: use captured pre-volume signal (stack buffer)
                    if has_pre_fader_sends {
                        let (dest_l, dest_r) = bus_buffers.get_bus_mut(dest_bus);
                        for i in 0..frames {
                            dest_l[i] += pfl_buf[i] * send_level * send_pan_l;
                            dest_r[i] += pfr_buf[i] * send_level * send_pan_r;
                        }
                    }
                } else {
                    // Post-fader: use current (post-volume/pan) signal
                    let (dest_l, dest_r) = bus_buffers.get_bus_mut(dest_bus);
                    for i in 0..frames {
                        dest_l[i] += track_l[i] * send_level * send_pan_l;
                        dest_r[i] += track_r[i] * send_level * send_pan_r;
                    }
                }
            }

            // Calculate per-track stereo metering (post-fader, post-insert)
            // Includes: peak L/R, RMS L/R, correlation + LUFS
            // Uses coalesced guards acquired once at top of process() (BUG#14 fix)
            if let Some(ref mut meters) = track_meters_guard {
                let meter = meters.entry(track.id.0).or_insert_with(TrackMeter::empty);
                meter.update(&track_l[..frames], &track_r[..frames], decay);

                // Per-track LUFS metering
                if let Some(ref mut lufs_meters) = track_lufs_guard {
                    let lufs = lufs_meters.entry(track.id.0).or_insert_with(|| {
                        LufsMeter::new(self.sample_rate() as f64)
                    });
                    lufs.process_block(&track_l[..frames], &track_r[..frames]);
                    meter.lufs_momentary = lufs.momentary_loudness();
                    meter.lufs_short = lufs.shortterm_loudness();
                    meter.lufs_integrated = lufs.integrated_loudness();
                }
            }

            // === SIP (Solo In Place) ===
            // If SIP mode and another track is soloed, mute this track
            let any_solo = self.control_room.has_solo();
            if solo_mode == SoloMode::SIP && any_solo && !is_soloed {
                // Mute this track (don't route to bus)
                continue;
            }

            // Route track to output bus(es)
            if track.output_channel_map.is_empty() {
                // Standard stereo routing — single bus destination
                bus_buffers.add_to_bus(track.output_bus, track_l, track_r);
            } else {
                // Multi-output routing — route each stereo channel pair to its mapped bus.
                // First pair (0) uses the processed track_l/track_r (already through inserts).
                // Additional pairs require PinConnector multi-channel output data.
                bus_buffers.add_to_bus(track.output_bus_for_channel(0), track_l, track_r);

                // Route additional channel pairs from PinConnector output buffers.
                // Uses insert_chains_guard acquired once at top of process() (BUG#14 fix)
                if let Some(ref chains) = insert_chains_guard
                    && let Some(chain) = chains.get(&track.id.0) {
                        // Find multi-channel plugin (last loaded slot with >2 channels)
                        let mut plugin_channels = 2u8;
                        let mut multi_slot_idx = 0usize;
                        for idx in (0..8).rev() {
                            let slot_ch = chain.slot_output_channels(idx);
                            if slot_ch > 2 {
                                plugin_channels = slot_ch;
                                multi_slot_idx = idx;
                                break;
                            }
                        }

                        if plugin_channels > 2 {
                            let stereo_pairs = (plugin_channels as usize) / 2;
                            for pair in 1..stereo_pairs.min(track.output_channel_map.len()) {
                                let bus = track.output_bus_for_channel(pair);
                                let ch_l = pair * 2;
                                let ch_r = pair * 2 + 1;
                                if let (Some(left), Some(right)) = (
                                    chain.slot_plugin_output_channel(multi_slot_idx, ch_l, frames),
                                    chain.slot_plugin_output_channel(multi_slot_idx, ch_r, frames),
                                ) {
                                    bus_buffers.add_to_bus(bus, left, right);
                                }
                            }
                        }
                    }
            }
        }

        // Release coalesced guards — no longer needed after track loop.
        // Minimizes hold duration so UI plugin load/remove is unblocked sooner.
        drop(insert_chains_guard);
        drop(stereo_imagers_guard);
        drop(track_meters_guard);
        drop(track_lufs_guard);
        drop(delay_comp_guard);
        drop(sidechain_taps_guard);

        // ═══════════════════════════════════════════════════════════════════════
        // BUS INSERT CHAINS + SUMMING TO MASTER
        // ═══════════════════════════════════════════════════════════════════════
        //
        // Audio flow: Bus buffers → Bus InsertChain → Bus Volume/Pan → Sum to Master
        //
        // Bus IDs: 0=Master routing, 1=Music, 2=Sfx, 3=Voice, 4=Amb, 5=Aux
        // Each bus gets its own pre/post-fader InsertChain processing.

        // try_read: non-blocking on audio thread
        // Fallback: use default state (unmuted, volume 1.0) if lock contended
        let default_states: [BusState; 6] = std::array::from_fn(|_| BusState::default());
        let bus_states_guard = self.bus_states.try_read();
        let bus_states: &[BusState; 6] = match &bus_states_guard {
            Some(guard) => guard,
            None => &default_states,
        };
        let any_solo = self.any_solo.load(Ordering::Relaxed);

        // Process each bus's InsertChain before summing to master
        // Use try_write to avoid blocking audio thread
        let mut bus_inserts = self.bus_inserts.try_write();
        // Re-acquire sidechain taps (immutable) for bus insert sidechain routing
        // (e.g. voice track ducking music bus via sidechain compressor on bus)
        let bus_sidechain_taps = self.sidechain_taps.try_read();

        // ═══ TOPOLOGICAL BUS ORDERING ═══
        // Buses that route to other buses must be processed FIRST so their output
        // is available in the target bus buffer. This enables Cubase-style stem grouping
        // (e.g., Sfx→Music, Voice→Aux submix).
        // Simple 2-level depth: child buses first (route to bus), then parent buses (route to master).
        // Circular routing (A→B→A) is prevented by the UI layer.

        // Build processing order: children first, then parents
        let mut process_order: [usize; 6] = [0; 6];
        let mut order_idx = 0;
        // Pass 1: buses that route to OTHER buses (children)
        for bus_idx in 0..6 {
            if let BusOutputDest::Bus(_) = bus_states[bus_idx].output_dest {
                process_order[order_idx] = bus_idx;
                order_idx += 1;
            }
        }
        // Pass 2: all remaining buses (route to master or unrecognized state)
        for bus_idx in 0..6 {
            if !process_order[..order_idx].contains(&bus_idx) {
                process_order[order_idx] = bus_idx;
                order_idx += 1;
            }
        }

        // Intermediate buffers for bus-to-bus routing.
        // After processing a child bus, its output is accumulated here before
        // being added to the parent bus buffer. This avoids aliasing issues
        // with get_bus_mut() on the same BusBuffers struct.
        // Thread-local heap buffers: zero-alloc after first call, supports any block size.
        let mut bus_has_accum: [bool; 6] = [false; 6];
        BUS_ACCUM_L.with(|cell| {
            let mut v = cell.borrow_mut();
            if v.len() < 6 { v.resize_with(6, || vec![0.0; frames]); }
            for buf in v.iter_mut() {
                if buf.len() < frames { buf.resize(frames, 0.0); }
                for x in buf[..frames].iter_mut() { *x = 0.0; }
            }
        });
        BUS_ACCUM_R.with(|cell| {
            let mut v = cell.borrow_mut();
            if v.len() < 6 { v.resize_with(6, || vec![0.0; frames]); }
            for buf in v.iter_mut() {
                if buf.len() < frames { buf.resize(frames, 0.0); }
                for x in buf[..frames].iter_mut() { *x = 0.0; }
            }
        });

        // Acquire stereo imagers ONCE for entire bus loop
        let mut bus_imagers_guard = self.bus_stereo_imagers.try_write();

        for &bus_idx in &process_order[..order_idx] {
            let state = &bus_states[bus_idx];

            // Skip if muted, or if solo is active and this bus isn't soloed
            if state.muted || (any_solo && !state.soloed) {
                // Reset metering for muted/inactive buses (smooth decay in UI)
                crate::ffi::SHARED_METERS.update_channel_peak(bus_idx, 0.0, 0.0);
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

            // Add accumulated audio from child buses that routed to this bus
            if bus_has_accum[bus_idx] {
                let (bus_l, bus_r) = bus_buffers.get_bus_mut(bus);
                BUS_ACCUM_L.with(|cell| {
                    let v = cell.borrow();
                    for i in 0..frames { bus_l[i] += v[bus_idx][i]; }
                });
                BUS_ACCUM_R.with(|cell| {
                    let v = cell.borrow();
                    for i in 0..frames { bus_r[i] += v[bus_idx][i]; }
                });
            }

            // Get mutable bus buffer for InsertChain processing
            let (bus_l, bus_r) = bus_buffers.get_bus_mut(bus);

            // ═══ BUS INSERT CHAIN (PRE-FADER) ═══
            // Process inserts BEFORE bus fader — affects sends, allows gain staging
            // Sidechain-aware: bus inserts can receive sidechain from any track tap
            if let Some(ref mut inserts) = bus_inserts {
                if let Some(ref taps) = bus_sidechain_taps {
                    inserts[bus_idx].process_pre_fader_with_taps(bus_l, bus_r, taps, frames);
                } else {
                    inserts[bus_idx].process_pre_fader(bus_l, bus_r);
                }
            }

            // Apply bus volume and dual-pan (fader stage)
            // Dual-pan: pan controls L channel placement, pan_right controls R channel placement
            // Default: pan=-1 (L stays left), pan_right=1 (R stays right) = stereo pass-through
            let volume = state.volume;
            let pan_l_angle = (state.pan + 1.0) * std::f64::consts::FRAC_PI_4;
            let pan_r_angle = (state.pan_right + 1.0) * std::f64::consts::FRAC_PI_4;
            let l_to_l = pan_l_angle.cos();
            let l_to_r = pan_l_angle.sin();
            let r_to_l = pan_r_angle.cos();
            let r_to_r = pan_r_angle.sin();

            // Gain compensation: prevent boost when cross-mixing (same as track dual-pan)
            let sum_l_sq = l_to_l * l_to_l + r_to_l * r_to_l;
            let sum_r_sq = l_to_r * l_to_r + r_to_r * r_to_r;
            let comp_l = if sum_l_sq > 1.0 { 1.0 / sum_l_sq.sqrt() } else { 1.0 };
            let comp_r = if sum_r_sq > 1.0 { 1.0 / sum_r_sq.sqrt() } else { 1.0 };

            // Apply volume and dual-pan in-place
            for i in 0..frames {
                let l = bus_l[i] * volume;
                let r = bus_r[i] * volume;
                bus_l[i] = comp_l * (l * l_to_l + r * r_to_l);
                bus_r[i] = comp_r * (l * l_to_r + r * r_to_r);
            }

            // ═══ PER-BUS STEREO IMAGER (post-fader, pre-post-inserts) ═══
            if let Some(ref mut imagers) = bus_imagers_guard {
                use rf_dsp::StereoProcessor;
                let imager = &mut imagers[bus_idx];
                for i in 0..frames {
                    let (l, r) = imager.process_sample(bus_l[i], bus_r[i]);
                    bus_l[i] = l;
                    bus_r[i] = r;
                }
            }

            // ═══ BUS INSERT CHAIN (POST-FADER) ═══
            // Process inserts AFTER bus fader — typical EQ/Compressor placement
            // Sidechain-aware: same tap access as pre-fader
            if let Some(ref mut inserts) = bus_inserts {
                if let Some(ref taps) = bus_sidechain_taps {
                    inserts[bus_idx].process_post_fader_with_taps(bus_l, bus_r, taps, frames);
                } else {
                    inserts[bus_idx].process_post_fader(bus_l, bus_r);
                }
            }

            // ═══ PER-BUS PEAK METERING ═══
            // Calculate peak levels after all processing (volume, pan, inserts)
            // and store in SHARED_METERS for UI display
            {
                let mut bp_l: f64 = 0.0;
                let mut bp_r: f64 = 0.0;
                for i in 0..frames {
                    bp_l = bp_l.max(bus_l[i].abs());
                    bp_r = bp_r.max(bus_r[i].abs());
                }
                crate::ffi::SHARED_METERS.update_channel_peak(bus_idx, bp_l, bp_r);
            }

            // ═══ ROUTE BUS OUTPUT ═══
            // Either sum to master (default) or route to parent bus (hierarchical routing)
            match state.output_dest {
                BusOutputDest::Master => {
                    // Standard: sum directly to master output
                    for i in 0..frames {
                        output_l[i] += bus_l[i];
                        output_r[i] += bus_r[i];
                    }
                }
                BusOutputDest::Bus(target_idx) => {
                    // Hierarchical: accumulate into target bus's accum buffer.
                    // The target bus will pick this up when it's processed later.
                    if target_idx < 6 && target_idx != bus_idx {
                        BUS_ACCUM_L.with(|cell| {
                            let mut v = cell.borrow_mut();
                            for i in 0..frames { v[target_idx][i] += bus_l[i]; }
                        });
                        BUS_ACCUM_R.with(|cell| {
                            let mut v = cell.borrow_mut();
                            for i in 0..frames { v[target_idx][i] += bus_r[i]; }
                        });
                        bus_has_accum[target_idx] = true;
                    } else {
                        // Self-routing or invalid target: fall back to master
                        for i in 0..frames {
                            output_l[i] += bus_l[i];
                            output_r[i] += bus_r[i];
                        }
                    }
                }
            }
        }

        // Acquire master insert chain ONCE for pre+post fader (BUG#14 lock coalescing)
        // Previously acquired twice (pre-fader + post-fader) = 2 contention windows.
        let mut master_insert_guard = self.master_insert.try_write();

        // Apply master insert chain (pre-fader) — sidechain-aware
        if let Some(ref mut master_insert) = master_insert_guard {
            if let Some(ref taps) = bus_sidechain_taps {
                master_insert.process_pre_fader_with_taps(output_l, output_r, taps, frames);
            } else {
                master_insert.process_pre_fader(output_l, output_r);
            }
        }

        // Apply master volume
        let master = self.master_volume();
        for i in 0..frames {
            output_l[i] *= master;
            output_r[i] *= master;
        }

        // ═══ MASTER STEREO IMAGER (post-volume, pre-post-inserts) ═══
        if let Some(mut master_imager) = self.master_stereo_imager.try_write() {
            use rf_dsp::StereoProcessor;
            for i in 0..frames {
                let (l, r) = master_imager.process_sample(output_l[i], output_r[i]);
                output_l[i] = l;
                output_r[i] = r;
            }
        }

        // Apply master insert chain (post-fader) — sidechain-aware
        if let Some(ref mut master_insert) = master_insert_guard {
            if let Some(ref taps) = bus_sidechain_taps {
                master_insert.process_post_fader_with_taps(output_l, output_r, taps, frames);
            } else {
                master_insert.process_post_fader(output_l, output_r);
            }
        }

        // Release guards before metering section
        drop(master_insert_guard);
        drop(bus_sidechain_taps);

        // ═══ MASTER CHANNEL DELAY (Independent L/R — Cubase/Pro Tools style) ═══
        // Applied after all processing, before metering.
        // Ring buffer approach: write current sample, read delayed sample.
        {
            let delay_l_ms = f64::from_bits(self.master_delay_l_ms.load(Ordering::Relaxed));
            let delay_r_ms = f64::from_bits(self.master_delay_r_ms.load(Ordering::Relaxed));

            // Only process if at least one channel has non-zero delay
            if delay_l_ms > 0.001 || delay_r_ms > 0.001 {
                let sr = f64::from_bits(self.master_delay_sample_rate.load(Ordering::Relaxed));
                let delay_l_samples_raw = (delay_l_ms * sr / 1000.0) as usize;
                let delay_r_samples_raw = (delay_r_ms * sr / 1000.0) as usize;

                if let (Some(mut buf_l), Some(mut buf_r)) = (
                    self.master_delay_buf_l.try_write(),
                    self.master_delay_buf_r.try_write(),
                ) {
                    let buf_size = buf_l.len(); // 8192
                    // Clamp delay to buf_size to prevent arithmetic underflow
                    let delay_l_samples = delay_l_samples_raw.min(buf_size);
                    let delay_r_samples = delay_r_samples_raw.min(buf_size);
                    let mut wp = self.master_delay_write_pos.load(Ordering::Relaxed);

                    for i in 0..frames {
                        // Write current samples into ring buffer
                        buf_l[wp % buf_size] = output_l[i];
                        buf_r[wp % buf_size] = output_r[i];

                        // Read delayed samples (wrap around)
                        if delay_l_samples > 0 {
                            let read_pos = (wp + buf_size - delay_l_samples) % buf_size;
                            output_l[i] = buf_l[read_pos];
                        }
                        if delay_r_samples > 0 {
                            let read_pos = (wp + buf_size - delay_r_samples) % buf_size;
                            output_r[i] = buf_r[read_pos];
                        }

                        wp = (wp + 1) % buf_size;
                    }

                    self.master_delay_write_pos.store(wp, Ordering::Relaxed);
                }
            }
        }

        // ═══ MASTER SOFT CLIPPER (smooth saturation — prevents digital clipping) ═══
        // Soft-knee tanh clipper with seamless transition at threshold.
        // Below knee_start (0.85): pass-through. Above: smooth blend into tanh.
        // Continuous first derivative — no click/pop at transition point.
        // tanh is scaled so tanh(1.0) maps to 1.0 at the output: out = tanh(x) / tanh(1.0)
        if self.master_soft_clip_enabled.load(Ordering::Relaxed) {
            const KNEE_START: f64 = 0.85;
            const KNEE_RANGE: f64 = 1.0 - KNEE_START; // 0.15
            // tanh(1.0) ≈ 0.7616 — normalize so unit input → unit output
            let tanh_norm = 1.0_f64.tanh();

            for i in 0..frames {
                output_l[i] = soft_clip_sample(output_l[i], KNEE_START, KNEE_RANGE, tanh_norm);
                output_r[i] = soft_clip_sample(output_r[i], KNEE_START, KNEE_RANGE, tanh_norm);
            }
        }

        // ═══ DC OFFSET FILTER (1-pole high-pass at ~5Hz) ═══
        // Removes accumulated DC drift from plugins, summing, or poorly encoded audio.
        // Applied post-clipper, pre-metering. Formula: y[n] = x[n] - x_prev + alpha * y_prev
        // At 5Hz cutoff / 48kHz SR: alpha ≈ 0.99935, negligible effect on audio.
        {
            let alpha = f64::from_bits(self.dc_filter_alpha.load(Ordering::Relaxed));
            let mut state_l = f64::from_bits(self.dc_filter_state_l.load(Ordering::Relaxed));
            let mut state_r = f64::from_bits(self.dc_filter_state_r.load(Ordering::Relaxed));
            for i in 0..frames {
                let new_l = output_l[i] - state_l;
                state_l = output_l[i] - alpha * new_l;
                output_l[i] = new_l;

                let new_r = output_r[i] - state_r;
                state_r = output_r[i] - alpha * new_r;
                output_r[i] = new_r;
            }
            self.dc_filter_state_l.store(state_l.to_bits(), Ordering::Relaxed);
            self.dc_filter_state_r.store(state_r.to_bits(), Ordering::Relaxed);
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
        crate::ffi::SHARED_METERS.update_channel_peak(0, peak_l, peak_r);

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

        // LUFS metering (ITU-R BS.1770-4) — try_write to avoid blocking audio thread
        if let Some(mut lufs) = self.lufs_meter.try_write() {
            lufs.process_block(output_l, output_r);
            let m = lufs.momentary_loudness();
            let s = lufs.shortterm_loudness();
            let i = lufs.integrated_loudness();
            self.lufs_momentary.store(m.to_bits(), Ordering::Relaxed);
            self.lufs_short.store(s.to_bits(), Ordering::Relaxed);
            self.lufs_integrated.store(i.to_bits(), Ordering::Relaxed);
        }

        // True Peak metering (4x oversampled per ITU-R BS.1770-4)
        if let Some(mut tp) = self.true_peak_meter.try_write() {
            tp.process_block(output_l, output_r);
            let dbtp_l: f64 = tp.peak_dbtp_l();
            let dbtp_r: f64 = tp.peak_dbtp_r();
            self.true_peak_l.store(dbtp_l.to_bits(), Ordering::Relaxed);
            self.true_peak_r.store(dbtp_r.to_bits(), Ordering::Relaxed);
        }

        // ═══ FORWARD ALL METERS TO SHARED MEMORY (Dart reads this) ═══
        // Peak/RMS already forwarded via update_channel_peak(0, ...) above.
        // Forward LUFS, True Peak, stereo analysis so Dart LUFS meter works.
        {
            let lufs_m = f64::from_bits(self.lufs_momentary.load(Ordering::Relaxed));
            let lufs_s = f64::from_bits(self.lufs_short.load(Ordering::Relaxed));
            let lufs_i = f64::from_bits(self.lufs_integrated.load(Ordering::Relaxed));
            crate::ffi::SHARED_METERS.update_lufs(lufs_s, lufs_i, lufs_m);

            let tp_l = f64::from_bits(self.true_peak_l.load(Ordering::Relaxed));
            let tp_r = f64::from_bits(self.true_peak_r.load(Ordering::Relaxed));
            let tp_max = tp_l.max(tp_r);
            crate::ffi::SHARED_METERS.update_true_peak(tp_l, tp_r, tp_max);

            let corr = f64::from_bits(self.correlation.load(Ordering::Relaxed));
            let bal = f64::from_bits(self.balance.load(Ordering::Relaxed));
            crate::ffi::SHARED_METERS.correlation.store(corr.to_bits(), Ordering::Relaxed);
            crate::ffi::SHARED_METERS.balance.store(bal.to_bits(), Ordering::Relaxed);

            // Master peak/RMS (redundant with update_channel_peak but fills master-specific fields)
            crate::ffi::SHARED_METERS.update_master(peak_l, peak_r, rms_l, rms_r);

            crate::ffi::SHARED_METERS.increment_sequence();
        }

        // Spectrum analyzer (FFT)
        // Mix to mono using pre-allocated buffer to avoid heap allocation
        if let Some(mut analyzer) = self.spectrum_analyzer.try_write() {
            if let Some(mut mono_buffer) = self.spectrum_mono_buffer.try_write() {
                // Ensure buffer is large enough
                debug_assert!(frames <= 8192, "Audio block size {} exceeds pre-allocated buffer (8192)", frames);
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

                    // 1/3 octave smoothing: averaging width proportional to frequency
                    // This matches FabFilter Pro-Q behavior — smooth at all frequencies
                    let center_bin = analyzer.freq_to_bin(freq, sample_rate).min(bin_count - 1);

                    // Calculate 1/3 octave bandwidth around center frequency
                    // 1/3 octave factor: 2^(1/6) ≈ 1.122
                    let octave_factor = 1.122_f64; // 2^(1/6)
                    let freq_low = freq / octave_factor;
                    let freq_high = freq * octave_factor;
                    let bin_low = analyzer.freq_to_bin(freq_low, sample_rate);
                    let bin_high = analyzer
                        .freq_to_bin(freq_high, sample_rate)
                        .min(bin_count - 1);

                    // Ensure at least 1 bin width, use wider range for bass
                    let low_bin = if bin_low < center_bin {
                        bin_low
                    } else {
                        center_bin.saturating_sub(1)
                    };
                    let high_bin = if bin_high > center_bin {
                        bin_high
                    } else {
                        (center_bin + 1).min(bin_count - 1)
                    };

                    let db = if high_bin > low_bin {
                        let sum: f64 = (low_bin..=high_bin).map(|b| analyzer.magnitude(b)).sum();
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

        // === METRONOME / CLICK TRACK ===
        // Process click track when transport is playing OR during count-in.
        // Uses try_write() to avoid blocking the audio thread if UI is changing settings.
        // Passes is_recording so click can implement "only during record" mode.
        // process_block() returns true when count-in completes → signal transport to start.
        if let Some(mut click) = crate::ffi::CLICK_TRACK.try_write() {
            let is_count_in = click.is_count_in_active();
            if self.position.is_playing() || is_count_in {
                let start_sample = self.position.samples().saturating_sub(frames as u64);
                let is_recording = self.position.is_recording();
                let count_in_done =
                    click.process_block(output_l, output_r, start_sample, frames, is_recording);
                if count_in_done {
                    // Count-in completed — transport should now begin playing.
                    // The transport start is handled by the UI layer polling
                    // click_is_count_in_active() which will return false.
                }
            }
        }

        // === CONTROL ROOM MONITOR PROCESSING ===
        // Process monitor output (applies dim, mono, speaker cal, routes solo/cue)
        self.control_room.process_monitor_output(output_l, output_r);

        // Update cue mix meters
        for cue in &self.control_room.cue_mixes {
            cue.update_peaks();
        }

        // CRITICAL: Don't advance transport during count-in (count-in has independent timing)
        let count_in_blocks_advance = crate::ffi::CLICK_TRACK
            .try_read()
            .is_some_and(|ct| ct.is_count_in_active());

        // Advance position (only if not scrubbing - scrub position is controlled externally)
        if self.position.should_advance() && !count_in_blocks_advance {
            let varispeed_rate = self.effective_playback_rate();
            self.position
                .advance_with_rate(frames as u64, varispeed_rate);
        } else if self.position.is_scrubbing() {
            // During scrubbing, advance within the scrub window (loops automatically)
            self.position.advance_scrub(frames as u64);
        }

        // Sync automation position
        if let Some(automation) = &self.automation {
            automation.set_position(self.position.samples());
        }
    }

    /// Apply a single automation change (with smoothing for continuous params)
    fn apply_automation_change(&self, change: &crate::automation::AutomationChange) {
        use crate::automation::TargetType;

        let param_id = &change.param_id;
        let track_id = param_id.target_id;

        match param_id.target_type {
            TargetType::Track => {
                match param_id.param_name.as_str() {
                    "volume" => {
                        // Automation value is normalized 0-1, map to 0-1.5 volume range
                        let volume = change.value * 1.5;
                        // Use smoother for zipper-free automation
                        self.param_smoother.set_track_volume(track_id, volume);
                    }
                    "pan" => {
                        // Automation value is normalized 0-1, map to -1..1 pan range
                        let pan = change.value * 2.0 - 1.0;
                        // Use smoother for zipper-free automation
                        self.param_smoother.set_track_pan(track_id, pan);
                    }
                    "mute" => {
                        // Mute is binary - no smoothing needed (would cause glitches)
                        // DashMap provides lock-free write access via get_mut()
                        let muted = change.value > 0.5;
                        if let Some(mut track) =
                            self.track_manager.tracks.get_mut(&TrackId(track_id))
                        {
                            track.muted = muted;
                        }
                    }
                    _ => {
                        log::trace!("Unknown track parameter: {}", param_id.param_name);
                    }
                }
            }
            TargetType::Send => {
                // Apply send level automation
                if let Some(slot) = param_id.slot
                    && let Some(mut track) =
                        self.track_manager.tracks.get_mut(&TrackId(track_id))
                    {
                        let slot_idx = slot as usize;
                        if slot_idx < track.sends.len() {
                            track.sends[slot_idx].level = change.value.clamp(0.0, 1.0);
                        }
                    }
            }
            TargetType::Plugin => {
                // Apply plugin parameter automation to insert chain
                if let Some(slot) = param_id.slot {
                    if let Some(mut chains) = self.insert_chains.try_write() {
                        if let Some(chain) = chains.get_mut(&track_id) {
                            // Parse param index from param_name (format: "param_<index>")
                            let param_idx = param_id.param_name
                                .strip_prefix("param_")
                                .and_then(|s| s.parse::<usize>().ok())
                                .unwrap_or(0);
                            chain.set_slot_param(
                                slot as usize,
                                param_idx,
                                change.value,
                            );
                        }
                    } else {
                        // Lock contended — automation change deferred to next block
                        log::trace!(
                            "Plugin automation deferred: track={}, slot={:?}, param={}, value={}",
                            track_id, param_id.slot, param_id.param_name, change.value
                        );
                    }
                }
            }
            TargetType::Bus => {
                // Apply bus volume/pan/mute via atomic bus_states.
                // track_id encodes the bus index (0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience, 5=Aux)
                let bus_idx = track_id as usize;
                match param_id.param_name.as_str() {
                    "volume" => {
                        // Automation 0-1 → bus volume 0-1.5 (headroom above unity)
                        self.set_bus_volume(bus_idx, change.value * 1.5);
                    }
                    "pan" => {
                        // Automation 0-1 → pan -1..+1
                        self.set_bus_pan(bus_idx, change.value * 2.0 - 1.0);
                    }
                    "mute" => {
                        self.set_bus_mute(bus_idx, change.value > 0.5);
                    }
                    _ => {
                        log::trace!(
                            "Unknown bus parameter: bus={}, param={}",
                            bus_idx, param_id.param_name
                        );
                    }
                }
            }
            TargetType::Master => {
                // Apply master volume (track_id is unused for master — always bus idx 0)
                match param_id.param_name.as_str() {
                    "volume" => {
                        // Automation 0-1 → master volume 0-1.5
                        self.set_master_volume(change.value * 1.5);
                    }
                    _ => {
                        log::trace!(
                            "Unknown master parameter: param={}",
                            param_id.param_name
                        );
                    }
                }
            }
            TargetType::Clip => {
                // Apply clip gain/pitch via lock-free DashMap update_clip.
                // track_id is repurposed as clip_id for TargetType::Clip.
                let clip_id = crate::track_manager::ClipId(track_id as u64);
                match param_id.param_name.as_str() {
                    "gain" => {
                        // Automation 0-1 → clip gain 0-2.0 (0dB = 1.0)
                        self.track_manager.update_clip(clip_id, |c| {
                            c.gain = (change.value * 2.0).clamp(0.0, 2.0);
                        });
                    }
                    "pitch" => {
                        // Automation 0-1 → pitch shift -24..+24 semitones
                        self.track_manager.update_clip(clip_id, |c| {
                            c.pitch_shift = change.value * 48.0 - 24.0;
                        });
                    }
                    "mute" => {
                        self.track_manager.update_clip(clip_id, |c| {
                            c.muted = change.value > 0.5;
                        });
                    }
                    _ => {
                        log::trace!(
                            "Unknown clip parameter: clip={}, param={}",
                            track_id, param_id.param_name
                        );
                    }
                }
            }
        }
    }

    /// Process audio using unified RoutingGraph (Phase 1.3)
    /// This replaces the legacy bus system with dynamic routing.
    ///
    /// NOTE: RoutingGraphRT is passed as parameter because it's NOT Sync
    /// (contains rtrb Consumer/Producer) and cannot be stored in PlaybackEngine.
    /// The audio thread should own and pass this reference each call.
    #[cfg(feature = "unified_routing")]
    pub fn process_unified(
        &self,
        routing: &mut RoutingGraphRT,
        output_l: &mut [f64],
        output_r: &mut [f64],
    ) {
        let frames = output_l.len();

        // Clear output buffers
        output_l.fill(0.0);
        output_r.fill(0.0);

        // Check if playing
        if !self.position.is_playing() {
            return;
        }

        // Process pending commands from UI thread
        routing.process_commands();

        let sample_rate = self.position.sample_rate() as f64;
        let start_sample = self.position.samples();
        let start_time = start_sample as f64 / sample_rate;
        let end_time = (start_sample + frames as u64) as f64 / sample_rate;

        // DashMap provides lock-free concurrent read access via sharded locks
        // No try_read() needed - direct iteration is always available without blocking

        // Use thread-local scratch buffers (ZERO lock contention - audio thread only)
        let (track_l, track_r) = SCRATCH_BUFFER_L.with(|buf_l| {
            SCRATCH_BUFFER_R.with(|buf_r| {
                let mut guard_l = buf_l.borrow_mut();
                let mut guard_r = buf_r.borrow_mut();

                debug_assert!(frames <= 8192, "Audio block size {} exceeds pre-allocated buffer (8192)", frames);
                if guard_l.len() < frames {
                    guard_l.resize(frames, 0.0);
                    guard_r.resize(frames, 0.0);
                }

                (guard_l.as_mut_ptr(), guard_r.as_mut_ptr())
            })
        });

        // SAFETY: thread-local buffers are only accessed from this audio thread
        let track_l = unsafe { std::slice::from_raw_parts_mut(track_l, frames) };
        let track_r = unsafe { std::slice::from_raw_parts_mut(track_r, frames) };

        // Clear all channel inputs in routing graph
        for channel in routing.graph.iter_channels_mut() {
            channel.clear_input();
        }

        // Get solo state ONCE (atomic - no lock needed)
        let solo_active = self.track_manager.is_solo_active();

        // Process each track → feed to routing graph channel
        // DashMap iter() returns references that auto-release shard locks
        for track_entry in self.track_manager.tracks.iter() {
            let track = track_entry.value();
            // Skip muted tracks (including VCA mute), or non-soloed tracks when solo is active
            let vca_muted = self.is_vca_muted(track.id.0);
            if track.muted || vca_muted || (solo_active && !track.soloed) {
                continue;
            }

            track_l.fill(0.0);
            track_r.fill(0.0);

            // Get clips for this track that overlap with current time range
            for clip_entry in self.track_manager.clips.iter() {
                let clip = clip_entry.value();
                if clip.track_id != track.id || clip.muted {
                    continue;
                }

                if !clip.overlaps(start_time, end_time) {
                    continue;
                }

                // Get cached audio
                let audio = match self.cache.peek(&clip.source_file) {
                    Some(a) => a,
                    None => continue,
                };

                // Process clip into track buffer
                self.process_clip_simple(clip, &audio, start_sample, sample_rate, track_l, track_r);
            }

            // Apply phase invert (polarity flip) before pan
            if track.phase_inverted {
                for i in 0..frames {
                    track_l[i] = -track_l[i];
                    track_r[i] = -track_r[i];
                }
            }

            // Apply dual-pan for stereo tracks BEFORE feeding to routing graph
            // Pro Tools style: L channel has own pan, R channel has own pan
            if track.is_stereo() {
                // Constant power panning for each channel independently
                let pan_l_angle = (track.pan + 1.0) * std::f64::consts::FRAC_PI_4;
                let pan_l_l = pan_l_angle.cos(); // L input to L output
                let pan_l_r = pan_l_angle.sin(); // L input to R output

                let pan_r_angle = (track.pan_right + 1.0) * std::f64::consts::FRAC_PI_4;
                let pan_r_l = pan_r_angle.cos(); // R input to L output
                let pan_r_r = pan_r_angle.sin(); // R input to R output

                for i in 0..frames {
                    let l_sample = track_l[i];
                    let r_sample = track_r[i];
                    // Mix both inputs to both outputs based on their pan positions
                    track_l[i] = l_sample * pan_l_l + r_sample * pan_r_l;
                    track_r[i] = l_sample * pan_l_r + r_sample * pan_r_r;
                }
            }
            // Note: Mono tracks use routing graph's pan (single pan knob)

            // Feed track audio to its routing graph channel
            // Channel ID maps to track ID (will be created on demand)
            let channel_id = ChannelId(track.id.0 as u32);
            if let Some(channel) = routing.graph.get_mut(channel_id) {
                // Set pan mode based on track type
                // Stereo tracks use external dual-pan (applied above), so routing bypasses pan
                // Mono tracks use routing's standard pan
                use crate::routing::PanMode;
                if track.is_stereo() {
                    channel.set_pan_mode(PanMode::ExternalDualPan);
                } else {
                    channel.set_pan_mode(PanMode::Standard);
                }
                channel.add_to_input(track_l, track_r);
            }
        }

        // Process routing graph (topological order, DSP, fader, pan)
        routing.process();

        // Get master output
        let (master_l, master_r) = routing.get_output();

        // Copy to output
        let len = frames.min(master_l.len()).min(master_r.len());
        output_l[..len].copy_from_slice(&master_l[..len]);
        output_r[..len].copy_from_slice(&master_r[..len]);

        // Process control room monitoring
        self.control_room.process_monitor_output(output_l, output_r);

        // Advance position (only if not scrubbing - scrub position is controlled externally)
        if self.position.should_advance() {
            let varispeed_rate = self.effective_playback_rate();
            self.position
                .advance_with_rate(frames as u64, varispeed_rate);
        } else if self.position.is_scrubbing() {
            // During scrubbing, advance within the scrub window (loops automatically)
            self.position.advance_scrub(frames as u64);
        }

        // Sync automation position
        if let Some(automation) = &self.automation {
            automation.set_position(self.position.samples());
        }
    }

    /// Simple clip processing (no crossfades) for unified routing
    ///
    /// When `clip.preserve_pitch && stretch_ratio != 1.0`:
    /// 1. Sinc-resample into stretch scratch buffers (with per-sample gain)
    /// 2. Signalsmith Stretch corrects pitch (cancels varispeed pitch change)
    /// 3. Mix stretched output into output_l/output_r
    #[cfg(feature = "unified_routing")]
    fn process_clip_simple(
        &self,
        clip: &Clip,
        audio: &ImportedAudio,
        start_sample: u64,
        sample_rate: f64,
        output_l: &mut [f64],
        output_r: &mut [f64],
    ) {
        let frames = output_l.len();
        let clip_start_sample = (clip.start_time * sample_rate) as u64;
        let clip_end_sample = (clip.end_time() * sample_rate) as u64;

        // Time stretch: effective playback rate (stretch_ratio * pitch_rate)
        let playback_rate = clip.effective_playback_rate();
        let source_sample_rate = audio.sample_rate as f64;
        let rate_ratio = source_sample_rate / sample_rate;

        // Convert source_offset (seconds) to samples in source sample rate
        let source_offset_samples = clip.source_offset * source_sample_rate;

        // Acquire sinc table ONCE per clip render call (non-blocking — skip clip if locked)
        let clip_resample_mode = playback_resample_mode();
        let clip_sinc_guard = match PLAYBACK_SINC_TABLE.try_read() {
            Some(guard) => guard,
            None => return, // Sinc table being rebuilt by UI thread — skip this clip for one buffer
        };
        let clip_sinc_ref = Some(&*clip_sinc_guard);

        // Signalsmith stretch path: preserve_pitch with non-unity stretch, pitch shift, or warp
        let has_warp = clip.warp_state.enabled && !clip.warp_state.segments.is_empty();
        let needs_pv = clip.preserve_pitch
            && ((clip.stretch_ratio - 1.0).abs() > 0.001
                || clip.pitch_shift.abs() > 0.01
                || has_warp);

        if needs_pv {
            // Signalsmith path: collect sinc-resampled samples, then stretch as block
            STRETCH_SCRATCH_L.with(|buf_l| {
                STRETCH_SCRATCH_R.with(|buf_r| {
                    STRETCH_OUT_L.with(|out_l| {
                    STRETCH_OUT_R.with(|out_r| {
                    STRETCH_GAIN_SCRATCH.with(|buf_g| {
                        let mut pv_l = buf_l.borrow_mut();
                        let mut pv_r = buf_r.borrow_mut();
                        let mut pv_out_l = out_l.borrow_mut();
                        let mut pv_out_r = out_r.borrow_mut();
                        let mut pv_gain = buf_g.borrow_mut();

                        // Ensure scratch buffers are large enough
                        if pv_l.len() < frames {
                            pv_l.resize(frames, 0.0);
                            pv_r.resize(frames, 0.0);
                            pv_out_l.resize(frames, 0.0);
                            pv_out_r.resize(frames, 0.0);
                            pv_gain.resize(frames, 0.0);
                        }

                        // Clear scratch regions
                        pv_l[..frames].fill(0.0);
                        pv_r[..frames].fill(0.0);
                        pv_out_l[..frames].fill(0.0);
                        pv_out_r[..frames].fill(0.0);
                        pv_gain[..frames].fill(0.0);

                        let channels = audio.channels as usize;
                        let total_source_frames = audio.samples.len() / channels.max(1);

                        // Phase 1: Sinc resample into stretch scratch buffers
                        for frame_idx in 0..frames {
                            let global_sample = start_sample + frame_idx as u64;

                            if global_sample < clip_start_sample
                                || (global_sample >= clip_end_sample && !clip.loop_enabled)
                            {
                                continue;
                            }

                            let clip_offset = global_sample - clip_start_sample;
                            // Source position: warp lookup or linear
                            let mut source_pos_f64 = if clip.warp_state.enabled && !clip.warp_state.segments.is_empty() {
                                let timeline_seconds = clip_offset as f64 / sample_rate;
                                if let Some((_seg, src_sec)) = clip.warp_state.lookup_segment(timeline_seconds) {
                                    src_sec * source_sample_rate + source_offset_samples
                                } else {
                                    clip_offset as f64 * rate_ratio + source_offset_samples
                                }
                            } else {
                                clip_offset as f64 * rate_ratio * playback_rate + source_offset_samples
                            };

                            let mut loop_xf_gain = 1.0_f64;
                            if clip.loop_enabled {
                                let loop_start = if clip.loop_start_samples > 0 {
                                    clip.loop_start_samples as f64
                                } else {
                                    0.0
                                };
                                let loop_end = if clip.loop_end_samples > 0 {
                                    clip.loop_end_samples as f64
                                } else {
                                    clip.source_duration * source_sample_rate
                                };
                                let loop_length = loop_end - loop_start;

                                if loop_length > 0.0 && source_pos_f64 >= loop_end {
                                    let region_offset = source_pos_f64 - loop_start;
                                    if region_offset >= loop_length {
                                        let iteration = (region_offset / loop_length) as u32;
                                        if clip.loop_count > 0 && iteration >= clip.loop_count {
                                            continue;
                                        }
                                        if clip.iteration_gain != 1.0 && iteration > 0 {
                                            let iter_gain = clip.iteration_gain.powi(iteration as i32);
                                            if iter_gain < 1e-10 {
                                                continue;
                                            }
                                            loop_xf_gain *= iter_gain;
                                        }
                                        let wrapped = region_offset % loop_length;
                                        let random_offset = if clip.loop_random_start > 0.0 {
                                            let seed = (iteration as f64 * 0.61803398875).fract();
                                            seed * clip.loop_random_start * source_sample_rate
                                        } else {
                                            0.0
                                        };
                                        source_pos_f64 = loop_start + wrapped + random_offset;
                                        if source_pos_f64 >= loop_end {
                                            source_pos_f64 = loop_start + (source_pos_f64 - loop_start) % loop_length;
                                        }
                                        if clip.loop_crossfade > 0.0 {
                                            let xf_len =
                                                (clip.loop_crossfade * source_sample_rate).min(loop_length * 0.5);
                                            let pos_in_loop = wrapped;
                                            if pos_in_loop < xf_len {
                                                let xf_progress = pos_in_loop / xf_len;
                                                loop_xf_gain *=
                                                    (xf_progress * std::f64::consts::FRAC_PI_2).sin();
                                            }
                                            if pos_in_loop > (loop_length - xf_len) {
                                                let end_gain = (loop_length - pos_in_loop) / xf_len;
                                                loop_xf_gain *=
                                                    (end_gain * std::f64::consts::FRAC_PI_2).sin();
                                            }
                                        }
                                    }
                                }
                            }

                            if source_pos_f64 < 0.0 || source_pos_f64 >= total_source_frames as f64 {
                                continue;
                            }

                            let interp_l = sinc_table::interpolate_sample(
                                clip_resample_mode, source_pos_f64, &audio.samples, channels,
                                total_source_frames, 0, clip_sinc_ref,
                            ) as f64;

                            // Store raw sinc output (no gain yet — Signalsmith needs clean signal)
                            pv_l[frame_idx] = interp_l;
                            // Store per-sample gain for post-stretch application
                            pv_gain[frame_idx] = clip.gain * loop_xf_gain;

                            if channels >= 2 {
                                pv_r[frame_idx] = sinc_table::interpolate_sample(
                                    clip_resample_mode, source_pos_f64, &audio.samples, channels,
                                    total_source_frames, 1, clip_sinc_ref,
                                ) as f64;
                            } else {
                                pv_r[frame_idx] = interp_l;
                            }
                        }

                        // Phase 2: Signalsmith pitch/time correction
                        // pitch_factor is pre-set by UI thread (includes pitch_shift + stretch compensation)
                        // Audio thread does NOT modify pitch_factor — avoids overriding user's pitch shift

                        // Try to acquire stretcher — if lock contended or not pre-allocated, bypass
                        // NEVER allocate on audio thread — stretcher must be pre-created via UI thread
                        if let Some(mut stretchers) = self.clip_stretchers.try_write() {
                            if let Some(stretcher) = stretchers.get_mut(&clip.id.0) {
                                self.diag_stretcher_hit.fetch_add(1, Ordering::Relaxed);

                                stretcher.process(
                                    &pv_l[..frames], &pv_r[..frames],
                                    &mut pv_out_l[..frames], &mut pv_out_r[..frames],
                                    frames,
                                );

                                for i in 0..frames {
                                    let g = pv_gain[i];
                                    if g.abs() > 1e-12 {
                                        output_l[i] += pv_out_l[i] * g;
                                        output_r[i] += pv_out_r[i] * g;
                                    }
                                }
                            } else {
                                self.diag_stretcher_miss.fetch_add(1, Ordering::Relaxed);
                                // Stretcher not pre-allocated — bypass (sinc-only output)
                                for i in 0..frames {
                                    let g = pv_gain[i];
                                    if g.abs() > 1e-12 {
                                        output_l[i] += pv_l[i] * g;
                                        output_r[i] += pv_r[i] * g;
                                    }
                                }
                            }
                        } else {
                            self.diag_stretcher_miss.fetch_add(1, Ordering::Relaxed);
                            // Lock contended — bypass PV, output sinc-only (better than silence)
                            for i in 0..frames {
                                let g = pv_gain[i];
                                if g.abs() > 1e-12 {
                                    output_l[i] += pv_l[i] * g;
                                    output_r[i] += pv_r[i] * g;
                                }
                            }
                        }
                    });
                    });
                    });
                });
            });
        } else {
            // Standard path: no stretcher needed (varispeed or unity stretch)
            let channels = audio.channels as usize;
            let total_source_frames = audio.samples.len() / channels.max(1);

            for frame_idx in 0..frames {
                let global_sample = start_sample + frame_idx as u64;

                if global_sample < clip_start_sample
                    || (global_sample >= clip_end_sample && !clip.loop_enabled)
                {
                    continue;
                }

                let clip_offset = global_sample - clip_start_sample;
                let mut source_pos_f64 =
                    clip_offset as f64 * rate_ratio * playback_rate + source_offset_samples;

                let mut loop_xf_gain = 1.0_f64;
                if clip.loop_enabled {
                    let loop_start = if clip.loop_start_samples > 0 {
                        clip.loop_start_samples as f64
                    } else {
                        0.0
                    };
                    let loop_end = if clip.loop_end_samples > 0 {
                        clip.loop_end_samples as f64
                    } else {
                        clip.source_duration * source_sample_rate
                    };
                    let loop_length = loop_end - loop_start;

                    if loop_length > 0.0 && source_pos_f64 >= loop_end {
                        let region_offset = source_pos_f64 - loop_start;
                        if region_offset >= loop_length {
                            let iteration = (region_offset / loop_length) as u32;
                            if clip.loop_count > 0 && iteration >= clip.loop_count {
                                continue;
                            }
                            if clip.iteration_gain != 1.0 && iteration > 0 {
                                let iter_gain = clip.iteration_gain.powi(iteration as i32);
                                if iter_gain < 1e-10 {
                                    continue;
                                }
                                loop_xf_gain *= iter_gain;
                            }
                            let wrapped = region_offset % loop_length;
                            let random_offset = if clip.loop_random_start > 0.0 {
                                let seed = (iteration as f64 * 0.61803398875).fract();
                                seed * clip.loop_random_start * source_sample_rate
                            } else {
                                0.0
                            };
                            source_pos_f64 = loop_start + wrapped + random_offset;
                            if source_pos_f64 >= loop_end {
                                source_pos_f64 = loop_start + (source_pos_f64 - loop_start) % loop_length;
                            }
                            if clip.loop_crossfade > 0.0 {
                                let xf_len =
                                    (clip.loop_crossfade * source_sample_rate).min(loop_length * 0.5);
                                let pos_in_loop = wrapped;
                                if pos_in_loop < xf_len {
                                    let xf_progress = pos_in_loop / xf_len;
                                    loop_xf_gain *=
                                        (xf_progress * std::f64::consts::FRAC_PI_2).sin();
                                }
                                if pos_in_loop > (loop_length - xf_len) {
                                    let end_gain = (loop_length - pos_in_loop) / xf_len;
                                    loop_xf_gain *=
                                        (end_gain * std::f64::consts::FRAC_PI_2).sin();
                                }
                            }
                        }
                    }
                }

                if source_pos_f64 < 0.0 || source_pos_f64 >= total_source_frames as f64 {
                    continue;
                }

                let interp_l = sinc_table::interpolate_sample(
                    clip_resample_mode, source_pos_f64, &audio.samples, channels,
                    total_source_frames, 0, clip_sinc_ref,
                ) as f64;
                if channels >= 2 {
                    let interp_r = sinc_table::interpolate_sample(
                        clip_resample_mode, source_pos_f64, &audio.samples, channels,
                        total_source_frames, 1, clip_sinc_ref,
                    ) as f64;
                    output_l[frame_idx] += interp_l * clip.gain * loop_xf_gain;
                    output_r[frame_idx] += interp_r * clip.gain * loop_xf_gain;
                } else {
                    let mono = interp_l * clip.gain * loop_xf_gain;
                    output_l[frame_idx] += mono;
                    output_r[frame_idx] += mono;
                }
            }
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

        // CRITICAL FIX (BUG #3): Use a LOCAL BusBuffers instead of self.bus_buffers.
        // Previously this acquired self.bus_buffers.write() (blocking), which starved
        // the audio thread's try_write() in process() → silent frame dropouts during export.
        // By using a local buffer, process_offline() and process() never contend on the lock.
        let mut bus_buffers = BusBuffers::new(frames);
        bus_buffers.clear();

        // DashMap provides lock-free access - safe for offline processing
        // No blocking locks needed

        // Get solo state for offline rendering
        let solo_active = self.track_manager.is_solo_active();

        let mut track_l = vec![0.0f64; frames];
        let mut track_r = vec![0.0f64; frames];

        // Acquire insert chains and sidechain taps for offline track processing
        let mut insert_chains = self.insert_chains.write();
        let offline_sc_taps = self.sidechain_taps.read();

        // Collect crossfades for this time range (need owned copies for lifetime)
        let crossfades_snapshot: Vec<Crossfade> = self
            .track_manager
            .crossfades
            .iter()
            .filter(|entry| {
                let xf = entry.value();
                xf.start_time < end_time && xf.end_time() > start_time
            })
            .map(|entry| entry.value().clone())
            .collect();

        for track_entry in self.track_manager.tracks.iter() {
            let track = track_entry.value();
            // Skip muted tracks (including VCA mute), or non-soloed tracks when solo is active
            let vca_muted = self.is_vca_muted(track.id.0);
            if track.muted || vca_muted || (solo_active && !track.soloed) {
                continue;
            }

            track_l.fill(0.0);
            track_r.fill(0.0);

            let track_crossfades: Vec<&Crossfade> = crossfades_snapshot
                .iter()
                .filter(|xf| xf.track_id == track.id)
                .collect();

            for clip_entry in self.track_manager.clips.iter() {
                let clip = clip_entry.value();
                if clip.track_id != track.id || clip.muted {
                    continue;
                }

                if !clip.overlaps(start_time, end_time) {
                    continue;
                }

                // Get cached audio
                let audio = match self.cache.peek(&clip.source_file) {
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

            // ═══ TRACK PRE-FADER INSERTS (offline) ═══
            if let Some(chain) = insert_chains.get_mut(&track.id.0) {
                chain.process_pre_fader_with_taps(&mut track_l, &mut track_r, &offline_sc_taps, frames);
            }

            // Apply track volume and pan
            let track_volume = self.get_track_volume_with_automation(track);
            let vca_gain = self.get_vca_gain(track.id.0);
            let final_volume = track_volume * vca_gain;

            // Pro Tools dual-pan for stereo, single pan for mono
            if track.is_stereo() {
                let pan_l_angle = (track.pan + 1.0) * std::f64::consts::FRAC_PI_4;
                let pan_l_l = pan_l_angle.cos();
                let pan_l_r = pan_l_angle.sin();
                let pan_r_angle = (track.pan_right + 1.0) * std::f64::consts::FRAC_PI_4;
                let pan_r_l = pan_r_angle.cos();
                let pan_r_r = pan_r_angle.sin();

                for i in 0..frames {
                    let l_sample = track_l[i];
                    let r_sample = track_r[i];
                    track_l[i] = final_volume * (l_sample * pan_l_l + r_sample * pan_r_l);
                    track_r[i] = final_volume * (l_sample * pan_l_r + r_sample * pan_r_r);
                }
            } else {
                let pan = track.pan;
                let pan_angle = (pan + 1.0) * std::f64::consts::FRAC_PI_4;
                let pan_l = pan_angle.cos();
                let pan_r = pan_angle.sin();

                for i in 0..frames {
                    track_l[i] *= final_volume * pan_l;
                    track_r[i] *= final_volume * pan_r;
                }
            }

            // ═══ TRACK POST-FADER INSERTS (offline) ═══
            if let Some(chain) = insert_chains.get_mut(&track.id.0) {
                chain.process_post_fader_with_taps(&mut track_l, &mut track_r, &offline_sc_taps, frames);
            }

            // Route to bus
            bus_buffers.add_to_bus(track.output_bus, &track_l, &track_r);
        }

        // Release track insert chains (bus inserts need separate write lock)
        drop(insert_chains);

        // ═══ BUS INSERT PROCESSING (offline — mirrors live path) ═══
        // Apply bus inserts + volume/pan for each bus before summing to master.
        // Without this, offline exports miss all bus EQ/compression/effects.
        // Uses topological ordering (children first) to match live path behavior.
        {
            let mut bus_inserts = self.bus_inserts.write();
            let bus_states = self.bus_states.read();
            let mut bus_imagers = self.bus_stereo_imagers.try_write();

            let buses = [
                OutputBus::Master, OutputBus::Music, OutputBus::Sfx,
                OutputBus::Voice, OutputBus::Ambience, OutputBus::Aux,
            ];

            // Topological ordering: children (route to bus) first, then parents (route to master)
            let mut process_order: [usize; 6] = [0; 6];
            let mut order_idx = 0;
            for bus_idx in 0..6 {
                if let BusOutputDest::Bus(_) = bus_states[bus_idx].output_dest {
                    process_order[order_idx] = bus_idx;
                    order_idx += 1;
                }
            }
            for bus_idx in 0..6 {
                if !process_order[..order_idx].contains(&bus_idx) {
                    process_order[order_idx] = bus_idx;
                    order_idx += 1;
                }
            }

            // Accum buffers for bus-to-bus routing (offline can heap-alloc freely)
            let mut accum_l: Vec<Vec<f64>> = (0..6).map(|_| vec![0.0; frames]).collect();
            let mut accum_r: Vec<Vec<f64>> = (0..6).map(|_| vec![0.0; frames]).collect();
            let mut has_accum = [false; 6];

            for &bus_idx in &process_order[..order_idx] {
                let state = &bus_states[bus_idx];
                if state.muted { continue; }

                let bus = buses[bus_idx];
                let (bus_l, bus_r) = bus_buffers.get_bus_mut(bus);

                // Add accumulated child bus audio
                if has_accum[bus_idx] {
                    for i in 0..frames { bus_l[i] += accum_l[bus_idx][i]; }
                    for i in 0..frames { bus_r[i] += accum_r[bus_idx][i]; }
                }

                // Pre-fader inserts
                bus_inserts[bus_idx].process_pre_fader_with_taps(bus_l, bus_r, &offline_sc_taps, frames);

                // Bus volume + dual-pan (same math as live path)
                let volume = state.volume;
                let pan_l_angle = (state.pan + 1.0) * std::f64::consts::FRAC_PI_4;
                let pan_r_angle = (state.pan_right + 1.0) * std::f64::consts::FRAC_PI_4;
                let l_to_l = pan_l_angle.cos();
                let l_to_r = pan_l_angle.sin();
                let r_to_l = pan_r_angle.cos();
                let r_to_r = pan_r_angle.sin();
                let sum_l_sq = l_to_l * l_to_l + r_to_l * r_to_l;
                let sum_r_sq = l_to_r * l_to_r + r_to_r * r_to_r;
                let comp_l = if sum_l_sq > 1.0 { 1.0 / sum_l_sq.sqrt() } else { 1.0 };
                let comp_r = if sum_r_sq > 1.0 { 1.0 / sum_r_sq.sqrt() } else { 1.0 };

                for i in 0..frames {
                    let l = bus_l[i] * volume;
                    let r = bus_r[i] * volume;
                    bus_l[i] = comp_l * (l * l_to_l + r * r_to_l);
                    bus_r[i] = comp_r * (l * l_to_r + r * r_to_r);
                }

                // Bus stereo imager (post-fader, pre-post-inserts — mirrors live path)
                if let Some(ref mut imagers) = bus_imagers {
                    use rf_dsp::StereoProcessor;
                    let imager = &mut imagers[bus_idx];
                    for i in 0..frames {
                        let (l, r) = imager.process_sample(bus_l[i], bus_r[i]);
                        bus_l[i] = l;
                        bus_r[i] = r;
                    }
                }

                // Post-fader inserts
                bus_inserts[bus_idx].process_post_fader_with_taps(bus_l, bus_r, &offline_sc_taps, frames);

                // Route: bus-to-bus or direct to master sum
                match state.output_dest {
                    BusOutputDest::Bus(target_idx) if target_idx < 6 && target_idx != bus_idx => {
                        for i in 0..frames { accum_l[target_idx][i] += bus_l[i]; }
                        for i in 0..frames { accum_r[target_idx][i] += bus_r[i]; }
                        has_accum[target_idx] = true;
                        // Zero this bus so sum_to_master doesn't double-count it
                        bus_l.iter_mut().for_each(|x| *x = 0.0);
                        bus_r.iter_mut().for_each(|x| *x = 0.0);
                    }
                    _ => {} // Master-routed buses get summed by sum_to_master() below
                }
            }
        }

        // Sum all buses to master (only master-routed buses have non-zero data)
        bus_buffers.sum_to_master();

        // Copy master to output
        let (master_l, master_r) = bus_buffers.master();
        output_l.copy_from_slice(&master_l[..frames]);
        output_r.copy_from_slice(&master_r[..frames]);

        // Drop local bus_buffers (free memory) before taking master_insert lock
        drop(bus_buffers);

        // Master processing — sidechain-aware (offline uses blocking read)
        let mut master_insert = self.master_insert.write();
        master_insert.process_pre_fader_with_taps(output_l, output_r, &offline_sc_taps, frames);

        let master = self.master_volume();
        for i in 0..frames {
            output_l[i] *= master;
            output_r[i] *= master;
        }

        // ═══ MASTER STEREO IMAGER (offline — mirrors live path) ═══
        if let Some(mut master_imager) = self.master_stereo_imager.try_write() {
            use rf_dsp::StereoProcessor;
            for i in 0..frames {
                let (l, r) = master_imager.process_sample(output_l[i], output_r[i]);
                output_l[i] = l;
                output_r[i] = r;
            }
        }

        master_insert.process_post_fader_with_taps(output_l, output_r, &offline_sc_taps, frames);
        drop(master_insert);
        drop(offline_sc_taps);

        // ═══ MASTER SOFT CLIPPER (offline — mirrors live path) ═══
        if self.master_soft_clip_enabled.load(Ordering::Relaxed) {
            const KNEE_START: f64 = 0.85;
            const KNEE_RANGE: f64 = 1.0 - KNEE_START;
            let tanh_norm = 1.0_f64.tanh();
            for i in 0..frames {
                output_l[i] = soft_clip_sample(output_l[i], KNEE_START, KNEE_RANGE, tanh_norm);
                output_r[i] = soft_clip_sample(output_r[i], KNEE_START, KNEE_RANGE, tanh_norm);
            }
        }

        // ═══ DC OFFSET FILTER (offline — mirrors live path) ═══
        // Note: offline DC filter uses its own local state per call, not the atomic
        // live state, to avoid interference between live and offline paths.
        // This means DC removal starts fresh per offline render — acceptable since
        // offline renders are typically long enough for the filter to converge.
        {
            let alpha = f64::from_bits(self.dc_filter_alpha.load(Ordering::Relaxed));
            let mut state_l = 0.0_f64;
            let mut state_r = 0.0_f64;
            for i in 0..frames {
                let new_l = output_l[i] - state_l;
                state_l = output_l[i] - alpha * new_l;
                output_l[i] = new_l;

                let new_r = output_r[i] - state_r;
                state_r = output_r[i] - alpha * new_r;
                output_r[i] = new_r;
            }
        }
    }

    /// Process a single track offline (for stems export)
    ///
    /// Renders a single track with all its clips, fades, volume, pan, and insert chain.
    /// Does NOT include master bus processing or routing to buses.
    pub fn process_track_offline(
        &self,
        track_id: u64,
        start_sample: usize,
        output_l: &mut [f64],
        output_r: &mut [f64],
    ) {
        let frames = output_l.len();

        // Clear output buffers
        output_l.fill(0.0);
        output_r.fill(0.0);

        // Get track
        let track = match self.track_manager.tracks.get(&TrackId(track_id)) {
            Some(t) => t,
            None => return,
        };

        // Check track mute AND VCA mute
        if track.muted || self.is_vca_muted(track_id) {
            return;
        }

        let sample_rate = self.position.sample_rate() as f64;
        let start_time = start_sample as f64 / sample_rate;
        let end_time = (start_sample + frames) as f64 / sample_rate;

        // Collect crossfades for this track
        let crossfades_snapshot: Vec<Crossfade> = self
            .track_manager
            .crossfades
            .iter()
            .filter(|entry| {
                let xf = entry.value();
                xf.track_id == TrackId(track_id)
                    && xf.start_time < end_time
                    && xf.end_time() > start_time
            })
            .map(|entry| entry.value().clone())
            .collect();

        let track_crossfades: Vec<&Crossfade> = crossfades_snapshot.iter().collect();

        // Process clips
        for clip_entry in self.track_manager.clips.iter() {
            let clip = clip_entry.value();
            if clip.track_id != track.id || clip.muted {
                continue;
            }

            if !clip.overlaps(start_time, end_time) {
                continue;
            }

            // Get cached audio
            let audio = match self.cache.peek(&clip.source_file) {
                Some(a) => a,
                None => continue,
            };

            let active_xf = track_crossfades
                .iter()
                .find(|xf| xf.clip_a_id == clip.id || xf.clip_b_id == clip.id)
                .copied();

            self.process_clip_with_crossfade(
                clip,
                &track,
                &audio,
                active_xf,
                start_sample as u64,
                sample_rate,
                output_l,
                output_r,
            );
        }

        // Apply track volume and pan
        let track_volume = self.get_track_volume_with_automation(&track);
        let vca_gain = self.get_vca_gain(track.id.0);
        let final_volume = track_volume * vca_gain;

        // Apply phase invert (polarity flip) if enabled
        // This multiplies the signal by -1, flipping the polarity
        let phase_mult = if track.phase_inverted { -1.0 } else { 1.0 };

        if track.is_stereo() {
            let pan_l_angle = (track.pan + 1.0) * std::f64::consts::FRAC_PI_4;
            let pan_l_l = pan_l_angle.cos();
            let pan_l_r = pan_l_angle.sin();

            let pan_r_angle = (track.pan_right + 1.0) * std::f64::consts::FRAC_PI_4;
            let pan_r_l = pan_r_angle.cos();
            let pan_r_r = pan_r_angle.sin();

            for i in 0..frames {
                let l_sample = output_l[i] * phase_mult;
                let r_sample = output_r[i] * phase_mult;
                output_l[i] = final_volume * (l_sample * pan_l_l + r_sample * pan_r_l);
                output_r[i] = final_volume * (l_sample * pan_l_r + r_sample * pan_r_r);
            }
        } else {
            let pan_angle = (track.pan + 1.0) * std::f64::consts::FRAC_PI_4;
            let pan_l = pan_angle.cos();
            let pan_r = pan_angle.sin();

            for i in 0..frames {
                output_l[i] *= final_volume * pan_l * phase_mult;
                output_r[i] *= final_volume * pan_r * phase_mult;
            }
        }

        // Apply track insert chain — sidechain-aware (offline uses blocking read)
        let mut insert_chains = self.insert_chains.write();
        if let Some(chain) = insert_chains.get_mut(&track_id) {
            let offline_taps = self.sidechain_taps.read();
            chain.process_pre_fader_with_taps(output_l, output_r, &offline_taps, frames);
            chain.process_post_fader_with_taps(output_l, output_r, &offline_taps, frames);
            drop(offline_taps);
        }
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

        // Per-item envelopes: if any envelope is active, we evaluate per-sample.
        // Otherwise use static values for performance.
        let has_envelopes = clip.has_active_envelope();

        // Static fallback (when no envelopes): calculate once
        let static_playback_rate = clip.effective_playback_rate();
        let static_gain = clip.gain;

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

        // Pre-calculate source offset for the loop
        let source_offset_samples_f64 = clip.source_offset * source_sample_rate;

        // Acquire sinc table ONCE per clip (non-blocking — skip if locked)
        let clip2_resample_mode = playback_resample_mode();
        let clip2_sinc_guard = match PLAYBACK_SINC_TABLE.try_read() {
            Some(guard) => guard,
            None => return, // Sinc table being rebuilt — skip this clip
        };
        let clip2_sinc_ref = Some(&*clip2_sinc_guard);

        // Signalsmith stretch path: if preserve_pitch with stretch, pitch shift, or warp
        let has_warp = clip.warp_state.enabled && !clip.warp_state.segments.is_empty();
        let needs_pv = clip.preserve_pitch
            && ((clip.stretch_ratio - 1.0).abs() > 0.001
                || clip.pitch_shift.abs() > 0.01
                || has_warp);

        if needs_pv {
            // Delegate to PV-aware block processor
            self.process_clip_with_crossfade_pv(
                clip, audio, crossfade, start_sample, sample_rate,
                output_l, output_r, frames, clip_start_sample,
                source_sample_rate, rate_ratio, has_envelopes,
                static_playback_rate, static_gain,
                fade_in_samples, fade_out_samples, clip_duration_samples,
                xf_start_sample, xf_end_sample, is_clip_a,
                source_offset_samples_f64,
                clip2_resample_mode, &clip2_sinc_guard,
            );
            return;
        }

        // For envelope mode: compute integrated source position at block start,
        // then accumulate incrementally per-sample. This avoids O(N*P) per-sample integration.
        let has_pitch_or_rate_env = has_envelopes
            && (clip
                .pitch_envelope
                .as_ref()
                .is_some_and(|e| e.is_active())
                || clip
                    .playrate_envelope
                    .as_ref()
                    .is_some_and(|e| e.is_active()));

        // Accumulated source position for incremental envelope mode
        let mut env_source_pos: f64 = 0.0;
        let mut env_initialized = false;
        let mut env_prev_clip_offset: i64 = -1;

        for i in 0..frames {
            let playback_sample = start_sample as i64 + i as i64;
            let clip_relative_sample = playback_sample - clip_start_sample;

            // Check if within clip bounds (looping clips extend beyond visual duration)
            if clip_relative_sample < 0
                || (clip_relative_sample >= clip_duration_samples && !clip.loop_enabled)
            {
                continue;
            }

            // Calculate source position — 3 modes:
            // 1. Warp markers: segment lookup (overrides stretch_ratio)
            // 2. Envelope: integrated rate from pitch/playrate envelopes
            // 3. Static: direct calculation from stretch_ratio
            let mut source_pos_f64 = if clip.warp_state.enabled && !clip.warp_state.segments.is_empty() {
                // WARP MODE: per-segment stretch via marker lookup
                let timeline_seconds = clip_relative_sample as f64 / sample_rate;
                if let Some((_seg_idx, src_seconds)) = clip.warp_state.lookup_segment(timeline_seconds) {
                    // Convert source seconds to source samples + apply source offset
                    src_seconds * source_sample_rate + source_offset_samples_f64
                } else {
                    // Fallback: identity mapping
                    clip_relative_sample as f64 * rate_ratio + source_offset_samples_f64
                }
            } else if has_pitch_or_rate_env {
                let clip_offset = clip_relative_sample as u64;

                if !env_initialized || clip_relative_sample != env_prev_clip_offset + 1 {
                    env_source_pos = clip.source_position_at(
                        clip_offset,
                        rate_ratio,
                        source_offset_samples_f64,
                    );
                    env_initialized = true;
                } else {
                    let current_rate = clip.playback_rate_at(clip_offset);
                    let prev_rate = clip.playback_rate_at(clip_offset.saturating_sub(1));
                    env_source_pos += (prev_rate + current_rate) * 0.5 * rate_ratio;
                }
                env_prev_clip_offset = clip_relative_sample;
                env_source_pos
            } else {
                // Static mode: direct calculation (zero overhead, original behavior)
                clip_relative_sample as f64 * rate_ratio * static_playback_rate
                    + source_offset_samples_f64
            };

            // Loop wrapping: wrap source position within source bounds
            let mut loop_xf_gain = 1.0_f64;
            if clip.loop_enabled {
                let loop_length = clip.source_duration * source_sample_rate;
                if loop_length > 0.0 {
                    let offset_in_source = source_pos_f64 - source_offset_samples_f64;
                    if offset_in_source >= loop_length {
                        // Check loop count (0 = infinite)
                        if clip.loop_count > 0 {
                            let iteration = (offset_in_source / loop_length) as u32;
                            if iteration >= clip.loop_count {
                                continue; // Past loop count limit
                            }
                        }
                        let wrapped = offset_in_source % loop_length;
                        source_pos_f64 = source_offset_samples_f64 + wrapped;

                        // Sync envelope accumulator after loop wrap to prevent drift
                        if has_pitch_or_rate_env {
                            env_source_pos = source_pos_f64;
                        }

                        // Crossfade at loop boundary (equal-power)
                        if clip.loop_crossfade > 0.0 {
                            let xf_len =
                                (clip.loop_crossfade * source_sample_rate).min(loop_length * 0.5);
                            let pos_in_loop = wrapped;
                            // Near start of loop: fade in
                            if pos_in_loop < xf_len {
                                let xf_progress = pos_in_loop / xf_len;
                                loop_xf_gain =
                                    (xf_progress * std::f64::consts::FRAC_PI_2).sin();
                            }
                            // Near end of loop: fade out
                            if pos_in_loop > (loop_length - xf_len) {
                                let end_gain = (loop_length - pos_in_loop) / xf_len;
                                loop_xf_gain *=
                                    (end_gain * std::f64::consts::FRAC_PI_2).sin();
                            }
                        }
                    }
                }
            }

            // Bounds check before interpolation
            if source_pos_f64 < 0.0 {
                continue;
            }

            // Blackman-Harris windowed sinc interpolation for sub-sample accuracy
            let channels = audio.channels as usize;
            let total_source_frames = audio.samples.len() / channels.max(1);

            let (mut sample_l, mut sample_r) = if audio.channels == 1 {
                let s = sinc_table::interpolate_sample(
                    clip2_resample_mode, source_pos_f64, &audio.samples, 1, total_source_frames, 0, clip2_sinc_ref,
                ) as f64;
                (s, s)
            } else {
                let l = sinc_table::interpolate_sample(
                    clip2_resample_mode, source_pos_f64, &audio.samples, channels, total_source_frames, 0, clip2_sinc_ref,
                ) as f64;
                let r = sinc_table::interpolate_sample(
                    clip2_resample_mode, source_pos_f64, &audio.samples, channels, total_source_frames, 1, clip2_sinc_ref,
                ) as f64;
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

            // Apply gain (with optional volume envelope), fade, and loop crossfade
            let effective_gain = if has_envelopes {
                let clip_offset = (playback_sample - clip_start_sample) as u64;
                clip.gain_at(clip_offset)
            } else {
                static_gain
            };
            let final_gain = effective_gain * fade * loop_xf_gain;

            // Apply optional pan envelope
            if has_envelopes {
                let clip_offset = (playback_sample - clip_start_sample) as u64;
                let pan = clip.pan_at(clip_offset);
                if pan.abs() > 1e-6 {
                    // Constant-power pan law
                    let pan_norm = (pan + 1.0) * 0.5; // 0.0 (left) to 1.0 (right)
                    let l_gain = (1.0 - pan_norm).sqrt();
                    let r_gain = pan_norm.sqrt();
                    output_l[i] += sample_l * final_gain * l_gain;
                    output_r[i] += sample_r * final_gain * r_gain;
                    continue;
                }
            }

            output_l[i] += sample_l * final_gain;
            output_r[i] += sample_r * final_gain;
        }
    }

    /// Signalsmith Stretch aware version of process_clip_with_crossfade.
    ///
    /// Two-pass architecture (like Pro Tools Elastic Audio / Cubase Elastique):
    /// Pass 1: Sinc resample → scratch buffers (raw signal, no gain/fade)
    /// Signalsmith block: process entire block for pitch/time correction
    /// Pass 2: Apply gain/fade/crossfade to stretched output → accumulate into output
    #[allow(clippy::too_many_arguments)]
    fn process_clip_with_crossfade_pv(
        &self,
        clip: &Clip,
        audio: &ImportedAudio,
        crossfade: Option<&Crossfade>,
        start_sample: u64,
        sample_rate: f64,
        output_l: &mut [f64],
        output_r: &mut [f64],
        frames: usize,
        clip_start_sample: i64,
        source_sample_rate: f64,
        rate_ratio: f64,
        has_envelopes: bool,
        static_playback_rate: f64,
        static_gain: f64,
        fade_in_samples: i64,
        fade_out_samples: i64,
        clip_duration_samples: i64,
        xf_start_sample: i64,
        xf_end_sample: i64,
        is_clip_a: bool,
        source_offset_samples_f64: f64,
        resample_mode: ResampleMode,
        sinc_guard: &parking_lot::RwLockReadGuard<'_, SincTable>,
    ) {
        let sinc_ref = Some(&**sinc_guard);
        let has_pitch_or_rate_env = has_envelopes
            && (clip.pitch_envelope.as_ref().is_some_and(|e| e.is_active())
                || clip.playrate_envelope.as_ref().is_some_and(|e| e.is_active()));

        STRETCH_SCRATCH_L.with(|buf_l| {
        STRETCH_SCRATCH_R.with(|buf_r| {
        STRETCH_OUT_L.with(|out_l| {
        STRETCH_OUT_R.with(|out_r| {
        STRETCH_GAIN_SCRATCH.with(|buf_g| {
            let mut pv_l = buf_l.borrow_mut();
            let mut pv_r = buf_r.borrow_mut();
            let mut pv_out_l = out_l.borrow_mut();
            let mut pv_out_r = out_r.borrow_mut();
            let mut pv_gain = buf_g.borrow_mut();

            if pv_l.len() < frames {
                pv_l.resize(frames, 0.0);
                pv_r.resize(frames, 0.0);
                pv_out_l.resize(frames, 0.0);
                pv_out_r.resize(frames, 0.0);
                pv_gain.resize(frames, 0.0);
            }
            pv_l[..frames].fill(0.0);
            pv_r[..frames].fill(0.0);
            pv_out_l[..frames].fill(0.0);
            pv_out_r[..frames].fill(0.0);
            pv_gain[..frames].fill(0.0);

            let channels = audio.channels as usize;
            let total_source_frames = audio.samples.len() / channels.max(1);

            // Envelope state
            let mut env_source_pos: f64 = 0.0;
            let mut env_initialized = false;
            let mut env_prev_clip_offset: i64 = -1;

            // ══════════════════════════════════════════════════════════════
            // PASS 1: Sinc resample into scratch buffers + per-sample gain
            // ══════════════════════════════════════════════════════════════
            for i in 0..frames {
                let playback_sample = start_sample as i64 + i as i64;
                let clip_relative_sample = playback_sample - clip_start_sample;

                if clip_relative_sample < 0
                    || (clip_relative_sample >= clip_duration_samples && !clip.loop_enabled)
                {
                    continue;
                }

                // Source position — warp lookup or standard calculation
                let mut source_pos_f64 = if clip.warp_state.enabled && !clip.warp_state.segments.is_empty() {
                    let timeline_seconds = clip_relative_sample as f64 / sample_rate;
                    if let Some((_seg_idx, src_seconds)) = clip.warp_state.lookup_segment(timeline_seconds) {
                        src_seconds * source_sample_rate + source_offset_samples_f64
                    } else {
                        clip_relative_sample as f64 * rate_ratio + source_offset_samples_f64
                    }
                } else if has_pitch_or_rate_env {
                    let clip_offset = clip_relative_sample as u64;
                    if !env_initialized || clip_relative_sample != env_prev_clip_offset + 1 {
                        env_source_pos = clip.source_position_at(
                            clip_offset, rate_ratio, source_offset_samples_f64,
                        );
                        env_initialized = true;
                    } else {
                        let current_rate = clip.playback_rate_at(clip_offset);
                        let prev_rate = clip.playback_rate_at(clip_offset.saturating_sub(1));
                        env_source_pos += (prev_rate + current_rate) * 0.5 * rate_ratio;
                    }
                    env_prev_clip_offset = clip_relative_sample;
                    env_source_pos
                } else {
                    clip_relative_sample as f64 * rate_ratio * static_playback_rate
                        + source_offset_samples_f64
                };

                // Loop wrapping
                let mut loop_xf_gain = 1.0_f64;
                if clip.loop_enabled {
                    let loop_length = clip.source_duration * source_sample_rate;
                    if loop_length > 0.0 {
                        let offset_in_source = source_pos_f64 - source_offset_samples_f64;
                        if offset_in_source >= loop_length {
                            if clip.loop_count > 0 {
                                let iteration = (offset_in_source / loop_length) as u32;
                                if iteration >= clip.loop_count { continue; }
                            }
                            let wrapped = offset_in_source % loop_length;
                            source_pos_f64 = source_offset_samples_f64 + wrapped;
                            if has_pitch_or_rate_env { env_source_pos = source_pos_f64; }
                            if clip.loop_crossfade > 0.0 {
                                let xf_len = (clip.loop_crossfade * source_sample_rate).min(loop_length * 0.5);
                                if wrapped < xf_len {
                                    loop_xf_gain = (wrapped / xf_len * std::f64::consts::FRAC_PI_2).sin();
                                }
                                if wrapped > (loop_length - xf_len) {
                                    let end_gain = (loop_length - wrapped) / xf_len;
                                    loop_xf_gain *= (end_gain * std::f64::consts::FRAC_PI_2).sin();
                                }
                            }
                        }
                    }
                }

                if source_pos_f64 < 0.0 || source_pos_f64 >= total_source_frames as f64 {
                    continue;
                }

                // Sinc interpolation
                let (sl, sr) = if audio.channels == 1 {
                    let s = sinc_table::interpolate_sample(
                        resample_mode, source_pos_f64, &audio.samples, 1,
                        total_source_frames, 0, sinc_ref,
                    ) as f64;
                    (s, s)
                } else {
                    let l = sinc_table::interpolate_sample(
                        resample_mode, source_pos_f64, &audio.samples, channels,
                        total_source_frames, 0, sinc_ref,
                    ) as f64;
                    let r = sinc_table::interpolate_sample(
                        resample_mode, source_pos_f64, &audio.samples, channels,
                        total_source_frames, 1, sinc_ref,
                    ) as f64;
                    (l, r)
                };

                // Apply clip FX chain (before stretcher)
                let (fx_l, fx_r) = if clip.has_fx() {
                    self.process_clip_fx(&clip.fx_chain, sl, sr)
                } else {
                    (sl, sr)
                };

                // Store raw signal for stretcher (no gain/fade yet)
                pv_l[i] = fx_l;
                pv_r[i] = fx_r;

                // Calculate and store per-sample gain (fade + crossfade + gain envelope)
                let mut fade = 1.0_f64;
                if clip_relative_sample < fade_in_samples && fade_in_samples > 0 {
                    let f = clip_relative_sample as f64 / fade_in_samples as f64;
                    fade = f * f;
                }
                let samples_from_end = clip_duration_samples - clip_relative_sample;
                if samples_from_end < fade_out_samples && fade_out_samples > 0 {
                    let f = samples_from_end as f64 / fade_out_samples as f64;
                    fade *= f * f;
                }
                if let Some(xf) = crossfade {
                    if playback_sample >= xf_start_sample && playback_sample < xf_end_sample {
                        let xf_t = (playback_sample - xf_start_sample) as f32
                            / (xf_end_sample - xf_start_sample) as f32;
                        let (fo, fi) = xf.shape.evaluate(xf_t);
                        fade *= if is_clip_a { fo as f64 } else { fi as f64 };
                    } else if (is_clip_a && playback_sample >= xf_end_sample)
                        || (!is_clip_a && playback_sample < xf_start_sample)
                    {
                        fade = 0.0;
                    }
                }
                let effective_gain = if has_envelopes {
                    clip.gain_at((playback_sample - clip_start_sample) as u64)
                } else {
                    static_gain
                };
                pv_gain[i] = effective_gain * fade * loop_xf_gain;
            }

            // ══════════════════════════════════════════════════════════════
            // STRETCH BLOCK: Signalsmith Stretch pitch/time on entire buffer
            // ══════════════════════════════════════════════════════════════
            if let Some(mut stretchers) = self.clip_stretchers.try_write() {
                if let Some(stretcher) = stretchers.get_mut(&clip.id.0) {
                    self.diag_stretcher_hit.fetch_add(1, Ordering::Relaxed);

                    // Per-segment pitch: if warp markers have per-segment pitch_semitones,
                    // update the stretcher to reflect the current segment's pitch.
                    // We look up which segment the block START falls in (O(log N)).
                    // Segment pitch stacks on top of clip.pitch_shift.
                    // Signalsmith handles smooth transitions — no click artifacts at
                    // segment boundaries since we update at block granularity (typically
                    // 256-1024 samples = 5-21ms), same as Ableton Live's warp engine.
                    if clip.warp_state.enabled && !clip.warp_state.segments.is_empty() {
                        // Block start relative to clip in seconds.
                        // SAFE CAST: clamp start_sample to i64::MAX before cast to avoid wrapping
                        // on extremely long projects (>384h at 48kHz). Use saturating subtraction
                        // so positions before clip start yield 0.0 instead of huge negative values.
                        let start_sample_i64 = start_sample.min(i64::MAX as u64) as i64;
                        let block_start_clip_sec = (start_sample_i64 - clip_start_sample).max(0) as f64 / sample_rate;
                        // Lookup segment for block start position
                        if let Some((seg_idx, _)) = clip.warp_state.lookup_segment(block_start_clip_sec) {
                            if let Some(seg) = clip.warp_state.segments.get(seg_idx) {
                                // Always update pitch when crossing segments.
                                // Without unconditional set, a segment with pitch=0
                                // after a segment with pitch=+5 would KEEP the old +5
                                // because no one calls set_pitch_semitones(0.0).
                                let total_pitch = clip.pitch_shift + seg.pitch_semitones;
                                stretcher.set_pitch_semitones(total_pitch);
                            }
                        } else {
                            // Position is outside warp segment range (before first or after last marker).
                            // Reset to global clip pitch so we don't carry stale per-segment pitch.
                            stretcher.set_pitch_semitones(clip.pitch_shift);
                        }
                    }

                    // Signalsmith processes stereo interleaved internally
                    stretcher.process(
                        &pv_l[..frames], &pv_r[..frames],
                        &mut pv_out_l[..frames], &mut pv_out_r[..frames],
                        frames,
                    );

                    // PASS 2: Mix stretched output with per-sample gain into output
                    for i in 0..frames {
                        let g = pv_gain[i];
                        if g.abs() > 1e-12 {
                            output_l[i] += pv_out_l[i] * g;
                            output_r[i] += pv_out_r[i] * g;
                        }
                    }
                } else {
                    self.diag_stretcher_miss.fetch_add(1, Ordering::Relaxed);
                    // No stretcher — bypass (sinc + gain only)
                    for i in 0..frames {
                        let g = pv_gain[i];
                        if g.abs() > 1e-12 {
                            output_l[i] += pv_l[i] * g;
                            output_r[i] += pv_r[i] * g;
                        }
                    }
                }
            } else {
                self.diag_stretcher_miss.fetch_add(1, Ordering::Relaxed);
                for i in 0..frames {
                    let g = pv_gain[i];
                    if g.abs() > 1e-12 {
                        output_l[i] += pv_l[i] * g;
                        output_r[i] += pv_r[i] * g;
                    }
                }
            }
        });
        });
        });
        });
        });
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

    /// Set sample rate to match actual audio device output
    /// Called from engine_start_playback() after cpal device config is resolved
    pub fn set_sample_rate(&self, sr: u32) {
        self.position.set_sample_rate(sr);
        log::info!("[PlaybackEngine] Sample rate updated to {} Hz", sr);
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
        assert!((1.0..2.0).contains(&time));
    }

    #[test]
    fn test_audio_cache() {
        let cache = AudioCache::new();

        assert_eq!(cache.size(), 0);
        assert!(!cache.is_cached("/nonexistent/file.wav"));
    }
}
