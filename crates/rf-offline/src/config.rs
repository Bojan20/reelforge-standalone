//! Configuration types for offline processing

use serde::{Deserialize, Serialize};

/// Offline processing configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OfflineConfig {
    /// Number of worker threads (0 = auto)
    pub thread_count: usize,

    /// Buffer size for processing (samples per block)
    pub buffer_size: usize,

    /// Maximum concurrent jobs
    pub max_concurrent_jobs: usize,

    /// Enable progress callbacks
    pub enable_progress: bool,

    /// Temporary directory for intermediate files
    pub temp_dir: Option<String>,
}

impl Default for OfflineConfig {
    fn default() -> Self {
        Self {
            thread_count: 0, // Auto-detect
            buffer_size: 4096,
            max_concurrent_jobs: 4,
            enable_progress: true,
            temp_dir: None,
        }
    }
}

impl OfflineConfig {
    /// Create config for maximum quality (slower)
    pub fn quality() -> Self {
        Self {
            buffer_size: 8192,
            max_concurrent_jobs: 2,
            ..Default::default()
        }
    }

    /// Create config for maximum speed
    pub fn fast() -> Self {
        Self {
            buffer_size: 2048,
            max_concurrent_jobs: 8,
            ..Default::default()
        }
    }

    /// Set thread count
    pub fn with_threads(mut self, count: usize) -> Self {
        self.thread_count = count;
        self
    }

    /// Set buffer size
    pub fn with_buffer_size(mut self, size: usize) -> Self {
        self.buffer_size = size;
        self
    }
}

/// Dithering algorithm for bit depth reduction
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DitheringMode {
    /// No dithering (truncation)
    None,
    /// Rectangular PDF dither
    Rectangular,
    /// Triangular PDF dither (recommended)
    Triangular,
    /// Noise-shaped dithering (best quality)
    NoiseShaped,
}

impl Default for DitheringMode {
    fn default() -> Self {
        Self::Triangular
    }
}

/// Sample rate conversion quality
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SrcQuality {
    /// Fast, lower quality
    Quick,
    /// Medium quality
    Medium,
    /// Best quality (slower)
    Best,
}

impl Default for SrcQuality {
    fn default() -> Self {
        Self::Medium
    }
}
