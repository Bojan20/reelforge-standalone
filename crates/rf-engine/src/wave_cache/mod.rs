//! Wave Cache Module - Cubase-style Multi-Resolution Waveform Caching
//!
//! Provides professional-grade waveform caching with:
//! - Multi-resolution mip-mapped peak data (8 LOD levels)
//! - Binary .wfc file format for fast loading
//! - Memory-mapped file access for queries
//! - Async background cache building
//! - Tile-based rendering support (256 samples/tile base)
//! - Progressive refinement (coarse → fine)
//!
//! Supports 200+ tracks without UI jank.

mod builder;
mod format;
mod query;

pub use builder::{BuildProgress, BuildState, WaveCacheBuilder, build_from_samples};
pub use format::{
    BASE_TILE_SAMPLES, MIP_TILE_SAMPLES, MipLevel, NUM_MIP_LEVELS, TileData, WFC_MAGIC,
    WFC_VERSION, WfcFile, WfcFileMmap, WfcHeader,
};
pub use query::{CachedTile, TileRequest, TileResponse, WaveCacheQuery, tiles_to_flat_array};

use parking_lot::RwLock;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

// ═══════════════════════════════════════════════════════════════════════════
// WAVE CACHE MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// P3.4: Threshold for using mmap instead of full load (10 MB)
const MMAP_THRESHOLD_BYTES: u64 = 10 * 1024 * 1024;

/// P3.4: Cached waveform - either fully loaded or memory-mapped
#[derive(Clone)]
pub enum CachedWaveform {
    /// Fully loaded into heap memory (for small files)
    Loaded(Arc<WfcFile>),
    /// Memory-mapped (for large files - P3.4)
    Mmap(Arc<WfcFileMmap>),
}

impl CachedWaveform {
    /// Get memory usage (heap only, mmap doesn't count)
    pub fn memory_usage(&self) -> usize {
        match self {
            CachedWaveform::Loaded(wfc) => wfc.memory_usage(),
            CachedWaveform::Mmap(mmap) => mmap.memory_usage(), // Only ~100 bytes
        }
    }

    /// Check if this is memory-mapped
    pub fn is_mmap(&self) -> bool {
        matches!(self, CachedWaveform::Mmap(_))
    }

    /// Get header
    pub fn header(&self) -> &WfcHeader {
        match self {
            CachedWaveform::Loaded(wfc) => &wfc.header,
            CachedWaveform::Mmap(mmap) => &mmap.header,
        }
    }

    /// Get tile (works for both variants)
    pub fn get_tile(&self, level: usize, channel: usize, tile_idx: usize) -> Option<TileData> {
        match self {
            CachedWaveform::Loaded(wfc) => wfc
                .mip_levels
                .get(level)?
                .get_tile(channel, tile_idx)
                .cloned(),
            CachedWaveform::Mmap(mmap) => mmap.get_tile(level, channel, tile_idx),
        }
    }

    /// Get tiles range (works for both variants)
    pub fn get_tiles_range(
        &self,
        level: usize,
        channel: usize,
        start: usize,
        end: usize,
    ) -> Vec<TileData> {
        match self {
            CachedWaveform::Loaded(wfc) => {
                if let Some(mip) = wfc.mip_levels.get(level) {
                    if let Some(channel_tiles) = mip.tiles.get(channel) {
                        let s = start.min(channel_tiles.len());
                        let e = end.min(channel_tiles.len());
                        return channel_tiles[s..e].to_vec();
                    }
                }
                Vec::new()
            }
            CachedWaveform::Mmap(mmap) => mmap.get_tiles_range(level, channel, start, end),
        }
    }

    /// Select mip level for zoom
    pub fn select_mip_level(&self, pixels_per_second: f64, sample_rate: u32) -> usize {
        match self {
            CachedWaveform::Loaded(wfc) => wfc.select_mip_level(pixels_per_second, sample_rate),
            CachedWaveform::Mmap(mmap) => mmap.select_mip_level(pixels_per_second, sample_rate),
        }
    }
}

/// Central manager for all waveform caches
/// P1.11 FIX: Properly enforces memory budget with LRU eviction
/// P3.4: Uses mmap for large files (>10MB) to reduce memory usage
pub struct WaveCacheManager {
    /// Cache directory path
    cache_dir: PathBuf,

    /// In-memory cache of loaded .wfc files (both full and mmap)
    /// P3.4: Now stores CachedWaveform enum instead of Arc<WfcFile>
    loaded_caches: RwLock<HashMap<String, CachedWaveform>>,

    /// Active builders (file_hash -> builder)
    active_builders: RwLock<HashMap<String, Arc<WaveCacheBuilder>>>,

    /// P1.11: LRU order tracking (hash -> last_accessed_ms)
    lru_order: RwLock<HashMap<String, u64>>,

    /// Memory budget in bytes (default 512MB)
    memory_budget: std::sync::atomic::AtomicUsize,

    /// Current memory usage in bytes
    memory_usage: std::sync::atomic::AtomicUsize,

    /// P3.4: Threshold for mmap (configurable)
    mmap_threshold: std::sync::atomic::AtomicUsize,
}

impl WaveCacheManager {
    /// Create new cache manager
    pub fn new(cache_dir: impl AsRef<Path>) -> Self {
        let cache_dir = cache_dir.as_ref().to_path_buf();

        // Create cache directory if it doesn't exist
        std::fs::create_dir_all(&cache_dir).ok();

        Self {
            cache_dir,
            loaded_caches: RwLock::new(HashMap::new()),
            active_builders: RwLock::new(HashMap::new()),
            lru_order: RwLock::new(HashMap::new()),
            memory_budget: std::sync::atomic::AtomicUsize::new(512 * 1024 * 1024), // 512MB default
            memory_usage: std::sync::atomic::AtomicUsize::new(0),
            mmap_threshold: std::sync::atomic::AtomicUsize::new(MMAP_THRESHOLD_BYTES as usize),
        }
    }

    /// Set memory budget in bytes
    /// P1.11: Now properly enforced with atomic operations
    pub fn set_memory_budget(&self, bytes: usize) {
        self.memory_budget
            .store(bytes, std::sync::atomic::Ordering::Relaxed);
        // Trigger eviction if currently over budget
        self.enforce_budget();
    }

    /// P1.11: Get current memory usage
    pub fn current_memory_usage(&self) -> usize {
        self.memory_usage.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// P1.11: Get memory budget
    pub fn get_memory_budget(&self) -> usize {
        self.memory_budget
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    /// P1.11: Enforce memory budget by evicting LRU caches
    fn enforce_budget(&self) {
        let budget = self
            .memory_budget
            .load(std::sync::atomic::Ordering::Relaxed);
        let mut current = self.memory_usage.load(std::sync::atomic::Ordering::Relaxed);

        if current <= budget {
            return;
        }

        // Get LRU order snapshot
        let lru_snapshot: Vec<(String, u64)> = {
            let lru = self.lru_order.read();
            let mut entries: Vec<_> = lru.iter().map(|(k, &v)| (k.clone(), v)).collect();
            // Sort by access time (oldest first)
            entries.sort_by_key(|(_, ts)| *ts);
            entries
        };

        // Evict until under budget (target 80% to avoid thrashing)
        let target = (budget * 80) / 100;
        let mut evicted = 0;

        for (hash, _) in lru_snapshot {
            if current <= target {
                break;
            }

            // Remove from cache
            if let Some(cache) = self.loaded_caches.write().remove(&hash) {
                let size = cache.memory_usage();
                current = self
                    .memory_usage
                    .fetch_sub(size, std::sync::atomic::Ordering::Relaxed)
                    - size;
                self.lru_order.write().remove(&hash);
                evicted += 1;
                log::debug!(
                    "[WaveCache] Evicted {} ({} bytes, now {} MB)",
                    hash,
                    size,
                    current / 1024 / 1024
                );
            }
        }

        if evicted > 0 {
            log::info!(
                "[WaveCache] Budget enforcement: evicted {} caches, now {} MB / {} MB",
                evicted,
                current / 1024 / 1024,
                budget / 1024 / 1024
            );
        }
    }

    /// P1.11: Update LRU timestamp for a cache
    fn touch_lru(&self, hash: &str) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        self.lru_order.write().insert(hash.to_string(), now);
    }

    /// Get cache file path for an audio file
    pub fn cache_path_for(&self, audio_path: &str) -> PathBuf {
        let hash = Self::hash_path(audio_path);
        self.cache_dir.join(format!("{}.wfc", hash))
    }

    /// Hash a path to create cache key
    fn hash_path(path: &str) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        path.hash(&mut hasher);
        format!("{:016x}", hasher.finish())
    }

    /// Check if cache exists for audio file
    pub fn has_cache(&self, audio_path: &str) -> bool {
        let cache_path = self.cache_path_for(audio_path);
        cache_path.exists()
    }

    /// P3.4: Set mmap threshold (files larger than this use mmap)
    pub fn set_mmap_threshold(&self, bytes: usize) {
        self.mmap_threshold
            .store(bytes, std::sync::atomic::Ordering::Relaxed);
    }

    /// P3.4: Get mmap threshold
    pub fn get_mmap_threshold(&self) -> usize {
        self.mmap_threshold
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Load or create cache for audio file
    /// Returns immediately with existing cache or starts background build
    /// P3.4: Uses mmap for files larger than mmap_threshold
    pub fn get_or_build(
        &self,
        audio_path: &str,
        sample_rate: u32,
        channels: u8,
        total_frames: u64,
    ) -> Result<GetCacheResult, WaveCacheError> {
        let hash = Self::hash_path(audio_path);

        // Check if already loaded
        if let Some(cache) = self.loaded_caches.read().get(&hash) {
            // P1.11: Update LRU on access
            self.touch_lru(&hash);
            return Ok(GetCacheResult::Ready(cache.clone()));
        }

        // Check if .wfc file exists on disk
        let cache_path = self.cache_path_for(audio_path);
        if cache_path.exists() {
            // P3.4: Check file size to decide between mmap and full load
            let file_size = std::fs::metadata(&cache_path).map(|m| m.len()).unwrap_or(0);

            let mmap_threshold = self
                .mmap_threshold
                .load(std::sync::atomic::Ordering::Relaxed) as u64;

            if file_size > mmap_threshold {
                // P3.4: Use mmap for large files
                match WfcFileMmap::open(&cache_path) {
                    Ok(mmap) => {
                        let size = mmap.memory_usage(); // Only ~100 bytes
                        let cached = CachedWaveform::Mmap(Arc::new(mmap));

                        self.memory_usage
                            .fetch_add(size, std::sync::atomic::Ordering::Relaxed);
                        self.touch_lru(&hash);
                        self.loaded_caches
                            .write()
                            .insert(hash.clone(), cached.clone());

                        log::info!(
                            "[WaveCache] Opened {} via mmap ({:.2} MB file, {:.0} bytes heap)",
                            audio_path,
                            file_size as f64 / 1024.0 / 1024.0,
                            size
                        );

                        return Ok(GetCacheResult::Ready(cached));
                    }
                    Err(e) => {
                        log::warn!(
                            "Failed to mmap cache {}: {:?}, falling back to full load",
                            cache_path.display(),
                            e
                        );
                        // Fall through to full load
                    }
                }
            }

            // Full load for small files (or mmap fallback)
            match WfcFile::load(&cache_path) {
                Ok(wfc) => {
                    let size = wfc.memory_usage();
                    let cached = CachedWaveform::Loaded(Arc::new(wfc));

                    // P1.11: Track memory usage
                    self.memory_usage
                        .fetch_add(size, std::sync::atomic::Ordering::Relaxed);
                    self.touch_lru(&hash);
                    self.loaded_caches
                        .write()
                        .insert(hash.clone(), cached.clone());

                    // P1.11: Enforce budget after adding
                    self.enforce_budget();

                    return Ok(GetCacheResult::Ready(cached));
                }
                Err(e) => {
                    log::warn!("Failed to load cache {}: {:?}", cache_path.display(), e);
                    // Fall through to rebuild
                }
            }
        }

        // Check if already building
        if let Some(builder) = self.active_builders.read().get(&hash) {
            return Ok(GetCacheResult::Building(Arc::clone(builder)));
        }

        // Start new build
        let builder = Arc::new(WaveCacheBuilder::new(
            audio_path.to_string(),
            cache_path,
            sample_rate,
            channels,
            total_frames,
        ));

        self.active_builders
            .write()
            .insert(hash.clone(), Arc::clone(&builder));

        // Start background build
        let builder_clone = Arc::clone(&builder);
        let _hash_clone = hash.clone();
        // These are unused but kept for future implementation
        let _loaded_caches: Arc<parking_lot::RwLock<HashMap<String, Arc<WfcFile>>>> =
            Arc::new(parking_lot::RwLock::new(HashMap::new()));
        let _active_builders: Arc<parking_lot::RwLock<HashMap<String, Arc<WaveCacheBuilder>>>> =
            Arc::new(parking_lot::RwLock::new(HashMap::new()));

        std::thread::spawn(move || {
            if let Err(e) = builder_clone.build() {
                log::error!("Failed to build waveform cache: {:?}", e);
            }
        });

        Ok(GetCacheResult::Building(builder))
    }

    /// Get build progress for an audio file (0.0 - 1.0)
    pub fn build_progress(&self, audio_path: &str) -> Option<f32> {
        let hash = Self::hash_path(audio_path);
        self.active_builders.read().get(&hash).map(|b| b.progress())
    }

    /// Query tiles for rendering
    /// P3.4: Works with both loaded and mmap-backed caches
    pub fn query_tiles(
        &self,
        audio_path: &str,
        start_frame: u64,
        end_frame: u64,
        pixels_per_second: f64,
        sample_rate: u32,
    ) -> Result<Vec<TileResponse>, WaveCacheError> {
        let hash = Self::hash_path(audio_path);

        let cache = self
            .loaded_caches
            .read()
            .get(&hash)
            .cloned()
            .ok_or(WaveCacheError::NotLoaded)?;

        // P3.4: Use CachedWaveform's unified query interface
        let mip_level = cache.select_mip_level(pixels_per_second, sample_rate);
        let samples_per_tile = MIP_TILE_SAMPLES[mip_level];
        let num_channels = cache.header().channels as usize;

        let start_tile = (start_frame as usize) / samples_per_tile;
        let end_tile = (end_frame as usize).div_ceil(samples_per_tile);

        let mut channel_tiles: Vec<Vec<CachedTile>> = Vec::with_capacity(num_channels);

        for ch in 0..num_channels {
            let tile_data = cache.get_tiles_range(mip_level, ch, start_tile, end_tile);
            let tiles: Vec<CachedTile> = tile_data
                .into_iter()
                .enumerate()
                .map(|(i, td)| CachedTile {
                    tile_index: start_tile + i,
                    frame_offset: ((start_tile + i) * samples_per_tile) as u64,
                    min: td.min,
                    max: td.max,
                })
                .collect();
            channel_tiles.push(tiles);
        }

        Ok(vec![TileResponse {
            mip_level,
            samples_per_tile,
            first_tile_frame: (start_tile * samples_per_tile) as u64,
            tiles: channel_tiles,
        }])
    }

    /// Unload cache from memory (keeps .wfc file on disk)
    /// P1.11: Properly tracks memory usage on unload
    pub fn unload(&self, audio_path: &str) {
        let hash = Self::hash_path(audio_path);
        if let Some(cache) = self.loaded_caches.write().remove(&hash) {
            let size = cache.memory_usage();
            self.memory_usage
                .fetch_sub(size, std::sync::atomic::Ordering::Relaxed);
            self.lru_order.write().remove(&hash);
        }
    }

    /// Delete cache file
    /// P1.11: Properly tracks memory usage on delete
    pub fn delete_cache(&self, audio_path: &str) {
        let hash = Self::hash_path(audio_path);
        if let Some(cache) = self.loaded_caches.write().remove(&hash) {
            let size = cache.memory_usage();
            self.memory_usage
                .fetch_sub(size, std::sync::atomic::Ordering::Relaxed);
            self.lru_order.write().remove(&hash);
        }

        let cache_path = self.cache_path_for(audio_path);
        std::fs::remove_file(cache_path).ok();
    }

    /// Clear all caches
    /// P1.11: Resets memory usage tracking
    pub fn clear_all(&self) {
        self.loaded_caches.write().clear();
        self.lru_order.write().clear();
        self.memory_usage
            .store(0, std::sync::atomic::Ordering::Relaxed);

        // Delete all .wfc files
        if let Ok(entries) = std::fs::read_dir(&self.cache_dir) {
            for entry in entries.flatten() {
                if entry.path().extension().is_some_and(|e| e == "wfc") {
                    std::fs::remove_file(entry.path()).ok();
                }
            }
        }
    }

    /// Get cache directory
    pub fn cache_dir(&self) -> &Path {
        &self.cache_dir
    }

    /// Get number of loaded caches
    pub fn loaded_count(&self) -> usize {
        self.loaded_caches.read().len()
    }
}

impl Default for WaveCacheManager {
    fn default() -> Self {
        // Use system cache directory
        let cache_dir = std::env::var("HOME")
            .map(|h| PathBuf::from(h).join("Library").join("Caches"))
            .unwrap_or_else(|_| PathBuf::from("."))
            .join("fluxforge")
            .join("waveform_cache");

        Self::new(cache_dir)
    }
}

// P1.11: Statistics for monitoring
// P3.4: Extended with mmap statistics
impl WaveCacheManager {
    /// Get cache statistics
    pub fn stats(&self) -> WaveCacheStats {
        let caches = self.loaded_caches.read();
        let mmap_count = caches.values().filter(|c| c.is_mmap()).count();

        WaveCacheStats {
            loaded_count: caches.len(),
            mmap_count,
            memory_usage_bytes: self.memory_usage.load(std::sync::atomic::Ordering::Relaxed),
            memory_budget_bytes: self
                .memory_budget
                .load(std::sync::atomic::Ordering::Relaxed),
            mmap_threshold_bytes: self
                .mmap_threshold
                .load(std::sync::atomic::Ordering::Relaxed),
            active_builds: self.active_builders.read().len(),
        }
    }
}

/// P1.11/P3.4: Cache statistics
#[derive(Debug, Clone)]
pub struct WaveCacheStats {
    pub loaded_count: usize,
    /// P3.4: Number of caches using memory-mapping
    pub mmap_count: usize,
    pub memory_usage_bytes: usize,
    pub memory_budget_bytes: usize,
    /// P3.4: Threshold above which mmap is used
    pub mmap_threshold_bytes: usize,
    pub active_builds: usize,
}

impl WaveCacheStats {
    pub fn usage_percent(&self) -> f64 {
        if self.memory_budget_bytes == 0 {
            return 0.0;
        }
        (self.memory_usage_bytes as f64 / self.memory_budget_bytes as f64) * 100.0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// RESULT TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Result of get_or_build operation
/// P3.4: Now returns CachedWaveform which may be mmap-backed
pub enum GetCacheResult {
    /// Cache is ready to use (may be mmap for large files)
    Ready(CachedWaveform),
    /// Cache is being built in background
    Building(Arc<WaveCacheBuilder>),
}

impl GetCacheResult {
    /// Legacy helper: Get as WfcFile Arc if this is a loaded (non-mmap) cache
    /// Returns None if mmap-backed or still building
    pub fn as_loaded(&self) -> Option<Arc<WfcFile>> {
        match self {
            GetCacheResult::Ready(CachedWaveform::Loaded(wfc)) => Some(Arc::clone(wfc)),
            _ => None,
        }
    }

    /// Check if ready (either loaded or mmap)
    pub fn is_ready(&self) -> bool {
        matches!(self, GetCacheResult::Ready(_))
    }

    /// Get the cached waveform if ready
    pub fn as_cached(&self) -> Option<&CachedWaveform> {
        match self {
            GetCacheResult::Ready(c) => Some(c),
            GetCacheResult::Building(_) => None,
        }
    }
}

/// Wave cache errors
#[derive(Debug, Clone)]
pub enum WaveCacheError {
    /// Cache file not found
    NotFound,
    /// Cache not loaded in memory
    NotLoaded,
    /// Invalid cache format
    InvalidFormat(String),
    /// IO error
    IoError(String),
    /// Build error
    BuildError(String),
}

impl std::fmt::Display for WaveCacheError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WaveCacheError::NotFound => write!(f, "Cache file not found"),
            WaveCacheError::NotLoaded => write!(f, "Cache not loaded in memory"),
            WaveCacheError::InvalidFormat(s) => write!(f, "Invalid format: {}", s),
            WaveCacheError::IoError(s) => write!(f, "IO error: {}", s),
            WaveCacheError::BuildError(s) => write!(f, "Build error: {}", s),
        }
    }
}

impl std::error::Error for WaveCacheError {}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_path_hashing() {
        let hash1 = WaveCacheManager::hash_path("/path/to/file.wav");
        let hash2 = WaveCacheManager::hash_path("/path/to/file.wav");
        let hash3 = WaveCacheManager::hash_path("/path/to/other.wav");

        assert_eq!(hash1, hash2);
        assert_ne!(hash1, hash3);
    }
}
