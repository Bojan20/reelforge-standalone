//! .wfc File Format - Binary Waveform Cache Format
//!
//! File structure:
//! ```text
//! +----------------------------------------+
//! | Header (64 bytes)                      |
//! +----------------------------------------+
//! | Mip Level 0 (finest - 256 samples)     |
//! |   - Tiles: [min, max] per tile         |
//! +----------------------------------------+
//! | Mip Level 1 (512 samples)              |
//! +----------------------------------------+
//! | Mip Level 2 (1024 samples)             |
//! +----------------------------------------+
//! | ... up to Mip Level 7                  |
//! +----------------------------------------+
//! ```
//!
//! Each mip level stores (min, max) pairs as f32 for each channel.

use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::Path;

use memmap2::Mmap;

use super::WaveCacheError;

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Magic number for .wfc files
pub const WFC_MAGIC: [u8; 4] = *b"WFC1";

/// Current format version
pub const WFC_VERSION: u16 = 1;

/// Number of mip levels (LOD)
pub const NUM_MIP_LEVELS: usize = 8;

/// Samples per tile at base (finest) level
pub const BASE_TILE_SAMPLES: usize = 256;

/// Samples per tile at each mip level
pub const MIP_TILE_SAMPLES: [usize; NUM_MIP_LEVELS] = [
    256,   // Level 0: finest
    512,   // Level 1
    1024,  // Level 2
    2048,  // Level 3
    4096,  // Level 4
    8192,  // Level 5
    16384, // Level 6
    32768, // Level 7: coarsest
];

// ═══════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════

/// .wfc file header (64 bytes)
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct WfcHeader {
    /// Magic number "WFC1"
    pub magic: [u8; 4],
    /// Format version
    pub version: u16,
    /// Number of channels (1 = mono, 2 = stereo)
    pub channels: u8,
    /// Reserved for flags
    pub flags: u8,
    /// Sample rate of source audio
    pub sample_rate: u32,
    /// Total frames in source audio
    pub total_frames: u64,
    /// Duration in seconds (f64)
    pub duration_secs: f64,
    /// Number of tiles at base (finest) mip level
    pub num_base_tiles: u32,
    /// Offset to mip level 0 data
    pub mip_offsets: [u32; NUM_MIP_LEVELS],
    /// Reserved padding to 64 bytes
    pub _reserved: [u8; 4],
}

impl WfcHeader {
    pub fn new(channels: u8, sample_rate: u32, total_frames: u64) -> Self {
        let duration_secs = total_frames as f64 / sample_rate as f64;
        let num_base_tiles = (total_frames as usize).div_ceil(BASE_TILE_SAMPLES) as u32;

        Self {
            magic: WFC_MAGIC,
            version: WFC_VERSION,
            channels,
            flags: 0,
            sample_rate,
            total_frames,
            duration_secs,
            num_base_tiles,
            mip_offsets: [0; NUM_MIP_LEVELS],
            _reserved: [0; 4],
        }
    }

    /// Calculate number of tiles at a given mip level
    pub fn tiles_at_level(&self, level: usize) -> usize {
        let samples_per_tile = MIP_TILE_SAMPLES[level.min(NUM_MIP_LEVELS - 1)];
        (self.total_frames as usize).div_ceil(samples_per_tile)
    }

    /// Validate header
    pub fn validate(&self) -> Result<(), WaveCacheError> {
        if self.magic != WFC_MAGIC {
            return Err(WaveCacheError::InvalidFormat(
                "Invalid magic number".to_string(),
            ));
        }
        if self.version != WFC_VERSION {
            return Err(WaveCacheError::InvalidFormat(format!(
                "Unsupported version: {}",
                self.version
            )));
        }
        if self.channels == 0 || self.channels > 2 {
            return Err(WaveCacheError::InvalidFormat(format!(
                "Invalid channel count: {}",
                self.channels
            )));
        }
        Ok(())
    }

    /// Serialize header to bytes
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(64);

        bytes.extend_from_slice(&self.magic);
        bytes.extend_from_slice(&self.version.to_le_bytes());
        bytes.push(self.channels);
        bytes.push(self.flags);
        bytes.extend_from_slice(&self.sample_rate.to_le_bytes());
        bytes.extend_from_slice(&self.total_frames.to_le_bytes());
        bytes.extend_from_slice(&self.duration_secs.to_le_bytes());
        bytes.extend_from_slice(&self.num_base_tiles.to_le_bytes());

        for offset in &self.mip_offsets {
            bytes.extend_from_slice(&offset.to_le_bytes());
        }

        bytes.extend_from_slice(&self._reserved);

        bytes
    }

    /// Deserialize header from bytes
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, WaveCacheError> {
        if bytes.len() < 64 {
            return Err(WaveCacheError::InvalidFormat(
                "Header too short".to_string(),
            ));
        }

        let mut magic = [0u8; 4];
        magic.copy_from_slice(&bytes[0..4]);

        let version = u16::from_le_bytes([bytes[4], bytes[5]]);
        let channels = bytes[6];
        let flags = bytes[7];
        let sample_rate = u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]);
        let total_frames = u64::from_le_bytes([
            bytes[12], bytes[13], bytes[14], bytes[15], bytes[16], bytes[17], bytes[18], bytes[19],
        ]);
        let duration_secs = f64::from_le_bytes([
            bytes[20], bytes[21], bytes[22], bytes[23], bytes[24], bytes[25], bytes[26], bytes[27],
        ]);
        let num_base_tiles = u32::from_le_bytes([bytes[28], bytes[29], bytes[30], bytes[31]]);

        let mut mip_offsets = [0u32; NUM_MIP_LEVELS];
        for (i, offset) in mip_offsets.iter_mut().enumerate() {
            let start = 32 + i * 4;
            *offset = u32::from_le_bytes([
                bytes[start],
                bytes[start + 1],
                bytes[start + 2],
                bytes[start + 3],
            ]);
        }

        let mut _reserved = [0u8; 4];
        _reserved.copy_from_slice(&bytes[60..64]);

        let header = Self {
            magic,
            version,
            channels,
            flags,
            sample_rate,
            total_frames,
            duration_secs,
            num_base_tiles,
            mip_offsets,
            _reserved,
        };

        header.validate()?;
        Ok(header)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIP LEVEL DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Single mip level data
#[derive(Debug, Clone)]
pub struct MipLevel {
    /// Mip level index (0 = finest)
    pub level: usize,
    /// Samples per tile at this level
    pub samples_per_tile: usize,
    /// Tile data for each channel
    /// Layout: [channel][tile_index] = TileData
    pub tiles: Vec<Vec<TileData>>,
}

impl MipLevel {
    pub fn new(level: usize, channels: usize) -> Self {
        Self {
            level,
            samples_per_tile: MIP_TILE_SAMPLES[level.min(NUM_MIP_LEVELS - 1)],
            tiles: vec![Vec::new(); channels],
        }
    }

    /// Get tile count
    pub fn tile_count(&self) -> usize {
        self.tiles.first().map_or(0, |v| v.len())
    }

    /// Get tile for specific channel
    pub fn get_tile(&self, channel: usize, tile_idx: usize) -> Option<&TileData> {
        self.tiles.get(channel).and_then(|ch| ch.get(tile_idx))
    }

    /// Calculate byte size
    pub fn byte_size(&self) -> usize {
        let tiles_per_channel = self.tile_count();
        let channels = self.tiles.len();
        // Each tile is 8 bytes (min: f32, max: f32)
        channels * tiles_per_channel * 8
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TILE DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Peak data for a single tile
#[derive(Debug, Clone, Copy, Default)]
pub struct TileData {
    /// Minimum sample value in tile
    pub min: f32,
    /// Maximum sample value in tile
    pub max: f32,
}

impl TileData {
    pub fn new(min: f32, max: f32) -> Self {
        Self { min, max }
    }

    /// Get amplitude (range)
    pub fn amplitude(&self) -> f32 {
        self.max - self.min
    }

    /// Merge two tiles (take min of mins, max of maxes)
    pub fn merge(&self, other: &TileData) -> TileData {
        TileData {
            min: self.min.min(other.min),
            max: self.max.max(other.max),
        }
    }

    /// Convert to bytes (little-endian)
    pub fn to_bytes(&self) -> [u8; 8] {
        let mut bytes = [0u8; 8];
        bytes[0..4].copy_from_slice(&self.min.to_le_bytes());
        bytes[4..8].copy_from_slice(&self.max.to_le_bytes());
        bytes
    }

    /// Convert from bytes (little-endian)
    pub fn from_bytes(bytes: &[u8; 8]) -> Self {
        Self {
            min: f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]),
            max: f32::from_le_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WFC FILE
// ═══════════════════════════════════════════════════════════════════════════

/// Complete .wfc file in memory
#[derive(Debug)]
pub struct WfcFile {
    /// File header
    pub header: WfcHeader,
    /// Mip levels
    pub mip_levels: [MipLevel; NUM_MIP_LEVELS],
}

impl WfcFile {
    /// Create new empty .wfc file structure
    pub fn new(channels: u8, sample_rate: u32, total_frames: u64) -> Self {
        let header = WfcHeader::new(channels, sample_rate, total_frames);

        let mip_levels = std::array::from_fn(|i| MipLevel::new(i, channels as usize));

        Self { header, mip_levels }
    }

    /// Save to file
    pub fn save(&self, path: &Path) -> Result<(), WaveCacheError> {
        let file = File::create(path).map_err(|e| WaveCacheError::IoError(e.to_string()))?;
        let mut writer = BufWriter::new(file);

        // Calculate offsets
        let mut current_offset = 64u32; // Header size
        let mut mip_offsets = [0u32; NUM_MIP_LEVELS];

        for (i, level) in self.mip_levels.iter().enumerate() {
            mip_offsets[i] = current_offset;
            current_offset += level.byte_size() as u32;
        }

        // Write header with correct offsets
        let mut header = self.header;
        header.mip_offsets = mip_offsets;
        writer
            .write_all(&header.to_bytes())
            .map_err(|e| WaveCacheError::IoError(e.to_string()))?;

        // Write mip levels
        for level in &self.mip_levels {
            for channel_tiles in &level.tiles {
                for tile in channel_tiles {
                    writer
                        .write_all(&tile.to_bytes())
                        .map_err(|e| WaveCacheError::IoError(e.to_string()))?;
                }
            }
        }

        writer
            .flush()
            .map_err(|e| WaveCacheError::IoError(e.to_string()))?;

        Ok(())
    }

    /// Load from file
    pub fn load(path: &Path) -> Result<Self, WaveCacheError> {
        let file = File::open(path).map_err(|e| WaveCacheError::IoError(e.to_string()))?;
        let mut reader = BufReader::new(file);

        // Read header
        let mut header_bytes = [0u8; 64];
        reader
            .read_exact(&mut header_bytes)
            .map_err(|e| WaveCacheError::IoError(e.to_string()))?;

        let header = WfcHeader::from_bytes(&header_bytes)?;
        let channels = header.channels as usize;

        // Read mip levels
        let mip_levels: [MipLevel; NUM_MIP_LEVELS] = std::array::from_fn(|level_idx| {
            let num_tiles = header.tiles_at_level(level_idx);
            let mut level = MipLevel::new(level_idx, channels);

            // Read tiles for each channel
            for ch in 0..channels {
                level.tiles[ch] = Vec::with_capacity(num_tiles);
                for _ in 0..num_tiles {
                    let mut tile_bytes = [0u8; 8];
                    if reader.read_exact(&mut tile_bytes).is_ok() {
                        level.tiles[ch].push(TileData::from_bytes(&tile_bytes));
                    }
                }
            }

            level
        });

        Ok(Self { header, mip_levels })
    }

    /// Get optimal mip level for given zoom
    ///
    /// pixels_per_second: how many pixels represent one second of audio
    /// sample_rate: audio sample rate
    ///
    /// Returns mip level index (0 = finest, 7 = coarsest)
    pub fn select_mip_level(&self, pixels_per_second: f64, sample_rate: u32) -> usize {
        // Calculate how many samples we need per pixel
        // We want roughly 1-2 tiles per pixel for good visual density
        let samples_per_pixel = sample_rate as f64 / pixels_per_second;

        // Find the mip level where tile size is close to samples_per_pixel
        // We want tile_samples ~= samples_per_pixel * 2-4
        let target_tile_samples = (samples_per_pixel * 2.0) as usize;

        for (level, &tile_samples) in MIP_TILE_SAMPLES.iter().enumerate() {
            if tile_samples >= target_tile_samples {
                return level;
            }
        }

        NUM_MIP_LEVELS - 1
    }

    /// Get total memory usage
    pub fn memory_usage(&self) -> usize {
        let header_size = std::mem::size_of::<WfcHeader>();
        let level_size: usize = self.mip_levels.iter().map(|l| l.byte_size()).sum();
        header_size + level_size
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MEMORY-MAPPED WFC FILE (P3.4: Load only needed regions from disk)
// ═══════════════════════════════════════════════════════════════════════════

/// Memory-mapped .wfc file for efficient large file access.
/// P3.4: Only loads header into memory, tile data is read directly from disk via mmap.
/// This reduces memory usage from O(file_size) to O(header_size) for large files.
pub struct WfcFileMmap {
    /// File header (always in memory - 64 bytes)
    pub header: WfcHeader,
    /// Memory-mapped file data
    mmap: Mmap,
}

impl WfcFileMmap {
    /// Open .wfc file with memory mapping
    pub fn open(path: &Path) -> Result<Self, WaveCacheError> {
        let file = File::open(path).map_err(|e| WaveCacheError::IoError(e.to_string()))?;

        // Safety: The file must exist and be valid
        let mmap = unsafe {
            Mmap::map(&file).map_err(|e| WaveCacheError::IoError(format!("mmap failed: {}", e)))?
        };

        if mmap.len() < 64 {
            return Err(WaveCacheError::InvalidFormat(
                "File too small for header".to_string(),
            ));
        }

        // Parse header from mmap
        let header = WfcHeader::from_bytes(&mmap[0..64])?;

        Ok(Self { header, mmap })
    }

    /// Get tile data for a specific mip level, channel, and tile index.
    /// P3.4: Reads directly from memory-mapped file without copying.
    pub fn get_tile(&self, level: usize, channel: usize, tile_idx: usize) -> Option<TileData> {
        if level >= NUM_MIP_LEVELS || channel >= self.header.channels as usize {
            return None;
        }

        let num_tiles = self.header.tiles_at_level(level);
        if tile_idx >= num_tiles {
            return None;
        }

        let offset = self.header.mip_offsets[level] as usize;
        let tiles_per_channel = num_tiles;

        // Calculate byte offset: offset + (channel * tiles_per_channel + tile_idx) * 8
        let tile_offset = offset + (channel * tiles_per_channel + tile_idx) * 8;

        if tile_offset + 8 > self.mmap.len() {
            return None;
        }

        let bytes: [u8; 8] = self.mmap[tile_offset..tile_offset + 8].try_into().ok()?;

        Some(TileData::from_bytes(&bytes))
    }

    /// Get tiles for a range (optimized batch read)
    /// P3.4: Returns an iterator that reads directly from mmap.
    pub fn get_tiles_range(
        &self,
        level: usize,
        channel: usize,
        start_tile: usize,
        end_tile: usize,
    ) -> Vec<TileData> {
        if level >= NUM_MIP_LEVELS || channel >= self.header.channels as usize {
            return Vec::new();
        }

        let num_tiles = self.header.tiles_at_level(level);
        let start = start_tile.min(num_tiles);
        let end = end_tile.min(num_tiles);

        if start >= end {
            return Vec::new();
        }

        let offset = self.header.mip_offsets[level] as usize;
        let tiles_per_channel = num_tiles;

        let mut result = Vec::with_capacity(end - start);

        for tile_idx in start..end {
            let tile_offset = offset + (channel * tiles_per_channel + tile_idx) * 8;

            if tile_offset + 8 > self.mmap.len() {
                break;
            }

            if let Ok(bytes) = self.mmap[tile_offset..tile_offset + 8].try_into() {
                result.push(TileData::from_bytes(&bytes));
            }
        }

        result
    }

    /// Get optimal mip level for given zoom (same algorithm as WfcFile)
    pub fn select_mip_level(&self, pixels_per_second: f64, sample_rate: u32) -> usize {
        let samples_per_pixel = sample_rate as f64 / pixels_per_second;
        let target_tile_samples = (samples_per_pixel * 2.0) as usize;

        for (level, &tile_samples) in MIP_TILE_SAMPLES.iter().enumerate() {
            if tile_samples >= target_tile_samples {
                return level;
            }
        }

        NUM_MIP_LEVELS - 1
    }

    /// Memory usage: Only header (64 bytes) + mmap overhead
    /// P3.4: Actual file content is NOT in heap memory
    pub fn memory_usage(&self) -> usize {
        std::mem::size_of::<WfcHeader>() + std::mem::size_of::<Mmap>()
    }

    /// File size on disk
    pub fn file_size(&self) -> usize {
        self.mmap.len()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_header_serialization() {
        let header = WfcHeader::new(2, 48000, 480000);
        let bytes = header.to_bytes();
        let parsed = WfcHeader::from_bytes(&bytes).unwrap();

        assert_eq!(parsed.magic, WFC_MAGIC);
        assert_eq!(parsed.version, WFC_VERSION);
        assert_eq!(parsed.channels, 2);
        assert_eq!(parsed.sample_rate, 48000);
        assert_eq!(parsed.total_frames, 480000);
    }

    #[test]
    fn test_tile_serialization() {
        let tile = TileData::new(-0.5, 0.8);
        let bytes = tile.to_bytes();
        let parsed = TileData::from_bytes(&bytes);

        assert!((parsed.min - (-0.5)).abs() < 0.0001);
        assert!((parsed.max - 0.8).abs() < 0.0001);
    }

    #[test]
    fn test_mip_level_selection() {
        let wfc = WfcFile::new(2, 48000, 48000 * 60); // 1 minute stereo

        // High zoom (many pixels per second) -> fine mip level
        let level_high = wfc.select_mip_level(10000.0, 48000);
        assert!(
            level_high <= 2,
            "High zoom should use fine level, got {}",
            level_high
        );

        // Low zoom (few pixels per second) -> coarse mip level
        let level_low = wfc.select_mip_level(10.0, 48000);
        assert!(
            level_low >= 4,
            "Low zoom should use coarse level, got {}",
            level_low
        );
    }

    #[test]
    fn test_tiles_at_level() {
        let header = WfcHeader::new(2, 48000, 48000); // 1 second

        // Level 0: 256 samples per tile
        assert_eq!(header.tiles_at_level(0), 48000 / 256 + 1); // ceil division

        // Level 7: 32768 samples per tile
        assert_eq!(header.tiles_at_level(7), 2); // 48000 / 32768 rounds up to 2
    }
}
