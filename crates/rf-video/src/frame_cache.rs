//! Frame Cache
//!
//! LRU cache for decoded video frames to enable smooth playback.

use std::collections::HashMap;
use std::sync::Arc;

use parking_lot::RwLock;

use crate::decoder::VideoFrame;

// ============ Cache Config ============

/// Frame cache configuration
#[derive(Debug, Clone)]
pub struct CacheConfig {
    /// Maximum number of frames to cache
    pub max_frames: usize,
    /// Preload frames ahead of playhead
    pub preload_ahead: usize,
    /// Keep frames behind playhead
    pub keep_behind: usize,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            max_frames: 120,   // ~4 seconds at 30fps
            preload_ahead: 30, // ~1 second ahead
            keep_behind: 30,   // ~1 second behind
        }
    }
}

impl CacheConfig {
    /// High quality config (more frames)
    pub fn high_quality() -> Self {
        Self {
            max_frames: 300, // ~10 seconds at 30fps
            preload_ahead: 60,
            keep_behind: 60,
        }
    }

    /// Low memory config
    pub fn low_memory() -> Self {
        Self {
            max_frames: 30, // ~1 second at 30fps
            preload_ahead: 15,
            keep_behind: 10,
        }
    }
}

// ============ Cache Entry ============

struct CacheEntry {
    frame: VideoFrame,
    last_access: u64,
}

// ============ Frame Cache ============

/// LRU frame cache for video playback
#[derive(Clone)]
pub struct FrameCache {
    inner: Arc<RwLock<FrameCacheInner>>,
}

struct FrameCacheInner {
    /// Cached frames
    frames: HashMap<u64, CacheEntry>,
    /// Configuration
    config: CacheConfig,
    /// Access counter for LRU
    access_counter: u64,
    /// Current playhead (for preload decisions)
    playhead: u64,
    /// Total memory used (approximate)
    memory_used: usize,
}

impl FrameCache {
    pub fn new(config: CacheConfig) -> Self {
        Self {
            inner: Arc::new(RwLock::new(FrameCacheInner {
                frames: HashMap::with_capacity(config.max_frames),
                config,
                access_counter: 0,
                playhead: 0,
                memory_used: 0,
            })),
        }
    }

    /// Get frame from cache
    pub fn get(&self, frame_number: u64) -> Option<VideoFrame> {
        let mut inner = self.inner.write();
        inner.access_counter += 1;
        let access = inner.access_counter;

        if let Some(entry) = inner.frames.get_mut(&frame_number) {
            entry.last_access = access;
            return Some(entry.frame.clone());
        }

        None
    }

    /// Insert frame into cache
    pub fn insert(&self, frame_number: u64, frame: VideoFrame) {
        let mut inner = self.inner.write();

        let frame_size = frame.data.len();

        // Evict if at capacity
        while inner.frames.len() >= inner.config.max_frames {
            inner.evict_lru();
        }

        inner.access_counter += 1;
        let access = inner.access_counter;

        inner.frames.insert(
            frame_number,
            CacheEntry {
                frame,
                last_access: access,
            },
        );

        inner.memory_used += frame_size;
    }

    /// Check if frame is cached
    pub fn contains(&self, frame_number: u64) -> bool {
        self.inner.read().frames.contains_key(&frame_number)
    }

    /// Clear all cached frames
    pub fn clear(&self) {
        let mut inner = self.inner.write();
        inner.frames.clear();
        inner.memory_used = 0;
    }

    /// Update playhead position
    pub fn set_playhead(&self, playhead: u64) {
        let mut inner = self.inner.write();
        inner.playhead = playhead;

        // Evict frames that are too far behind
        let keep_from = playhead.saturating_sub(inner.config.keep_behind as u64);
        let keys_to_remove: Vec<u64> = inner
            .frames
            .keys()
            .filter(|&&k| k < keep_from)
            .copied()
            .collect();

        for key in keys_to_remove {
            if let Some(entry) = inner.frames.remove(&key) {
                inner.memory_used -= entry.frame.data.len();
            }
        }
    }

    /// Get frames that should be preloaded
    pub fn frames_to_preload(&self) -> Vec<u64> {
        let inner = self.inner.read();
        let playhead = inner.playhead;
        let preload_ahead = inner.config.preload_ahead as u64;

        (playhead..playhead + preload_ahead)
            .filter(|f| !inner.frames.contains_key(f))
            .collect()
    }

    /// Get cache statistics
    pub fn stats(&self) -> CacheStats {
        let inner = self.inner.read();
        CacheStats {
            cached_frames: inner.frames.len(),
            max_frames: inner.config.max_frames,
            memory_used: inner.memory_used,
            playhead: inner.playhead,
        }
    }
}

impl FrameCacheInner {
    fn evict_lru(&mut self) {
        if let Some((&oldest_key, _)) = self
            .frames
            .iter()
            .min_by_key(|(_, entry)| entry.last_access)
            && let Some(entry) = self.frames.remove(&oldest_key)
        {
            self.memory_used -= entry.frame.data.len();
        }
    }
}

// ============ Cache Stats ============

/// Cache statistics
#[derive(Debug, Clone)]
pub struct CacheStats {
    /// Number of cached frames
    pub cached_frames: usize,
    /// Maximum frames capacity
    pub max_frames: usize,
    /// Approximate memory used in bytes
    pub memory_used: usize,
    /// Current playhead position
    pub playhead: u64,
}

impl CacheStats {
    /// Cache fill percentage
    pub fn fill_percentage(&self) -> f64 {
        if self.max_frames == 0 {
            0.0
        } else {
            self.cached_frames as f64 / self.max_frames as f64 * 100.0
        }
    }

    /// Memory used in MB
    pub fn memory_mb(&self) -> f64 {
        self.memory_used as f64 / (1024.0 * 1024.0)
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decoder::PixelFormat;

    fn create_test_frame(frame_number: u64) -> VideoFrame {
        VideoFrame {
            frame_number,
            pts: frame_number as i64,
            width: 100,
            height: 100,
            format: PixelFormat::Rgb24,
            data: vec![0; 100 * 100 * 3],
            stride: 300,
        }
    }

    #[test]
    fn test_cache_insert_get() {
        let cache = FrameCache::new(CacheConfig::default());

        let frame = create_test_frame(0);
        cache.insert(0, frame);

        assert!(cache.contains(0));
        assert!(!cache.contains(1));

        let retrieved = cache.get(0);
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().frame_number, 0);
    }

    #[test]
    fn test_cache_eviction() {
        let config = CacheConfig {
            max_frames: 3,
            preload_ahead: 1,
            keep_behind: 1,
        };
        let cache = FrameCache::new(config);

        // Insert 4 frames (exceeds capacity)
        for i in 0..4 {
            cache.insert(i, create_test_frame(i));
        }

        // Should have evicted oldest
        assert!(!cache.contains(0));
        assert!(cache.contains(3));

        let stats = cache.stats();
        assert_eq!(stats.cached_frames, 3);
    }

    #[test]
    fn test_cache_clear() {
        let cache = FrameCache::new(CacheConfig::default());

        for i in 0..10 {
            cache.insert(i, create_test_frame(i));
        }

        cache.clear();

        let stats = cache.stats();
        assert_eq!(stats.cached_frames, 0);
        assert_eq!(stats.memory_used, 0);
    }
}
