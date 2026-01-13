//! Waveform Cache Query System
//!
//! Provides efficient tile-based queries for rendering:
//! - Automatic LOD selection based on zoom level
//! - Tile batching for efficient rendering
//! - Memory-efficient iteration over visible tiles

use super::format::{WfcFile, TileData, MIP_TILE_SAMPLES, NUM_MIP_LEVELS};

// ═══════════════════════════════════════════════════════════════════════════
// TILE REQUEST/RESPONSE
// ═══════════════════════════════════════════════════════════════════════════

/// Request for tiles in a frame range
#[derive(Debug, Clone)]
pub struct TileRequest {
    /// Start frame (inclusive)
    pub start_frame: u64,
    /// End frame (exclusive)
    pub end_frame: u64,
    /// Pixels per second (for LOD selection)
    pub pixels_per_second: f64,
    /// Sample rate
    pub sample_rate: u32,
    /// Channel index (None = all channels)
    pub channel: Option<usize>,
}

/// Response with tile data
#[derive(Debug, Clone)]
pub struct TileResponse {
    /// Mip level used
    pub mip_level: usize,
    /// Samples per tile at this level
    pub samples_per_tile: usize,
    /// Start frame of first tile
    pub first_tile_frame: u64,
    /// Tiles for each channel
    /// Layout: tiles[channel][tile_index]
    pub tiles: Vec<Vec<CachedTile>>,
}

/// Single cached tile with position info
#[derive(Debug, Clone, Copy)]
pub struct CachedTile {
    /// Tile index in mip level
    pub tile_index: usize,
    /// Frame offset of this tile start
    pub frame_offset: u64,
    /// Min peak value
    pub min: f32,
    /// Max peak value
    pub max: f32,
}

impl CachedTile {
    /// Get amplitude
    pub fn amplitude(&self) -> f32 {
        self.max - self.min
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVE CACHE QUERY
// ═══════════════════════════════════════════════════════════════════════════

/// Query interface for waveform cache
pub struct WaveCacheQuery<'a> {
    wfc: &'a WfcFile,
}

impl<'a> WaveCacheQuery<'a> {
    /// Create new query interface
    pub fn new(wfc: &'a WfcFile) -> Self {
        Self { wfc }
    }

    /// Get tiles for a frame range at optimal LOD
    pub fn get_tiles(
        &self,
        start_frame: u64,
        end_frame: u64,
        pixels_per_second: f64,
        sample_rate: u32,
    ) -> Vec<TileResponse> {
        // Select optimal mip level
        let mip_level = self.wfc.select_mip_level(pixels_per_second, sample_rate);
        let level_data = &self.wfc.mip_levels[mip_level];
        let samples_per_tile = MIP_TILE_SAMPLES[mip_level];

        // Calculate tile range
        let start_tile = (start_frame as usize) / samples_per_tile;
        let end_tile = ((end_frame as usize) + samples_per_tile - 1) / samples_per_tile;

        let num_channels = level_data.tiles.len();

        // Collect tiles for each channel
        let mut channel_tiles: Vec<Vec<CachedTile>> = Vec::with_capacity(num_channels);

        for ch in 0..num_channels {
            let mut tiles = Vec::new();

            for tile_idx in start_tile..end_tile {
                if let Some(tile_data) = level_data.tiles.get(ch).and_then(|t| t.get(tile_idx)) {
                    tiles.push(CachedTile {
                        tile_index: tile_idx,
                        frame_offset: (tile_idx * samples_per_tile) as u64,
                        min: tile_data.min,
                        max: tile_data.max,
                    });
                }
            }

            channel_tiles.push(tiles);
        }

        vec![TileResponse {
            mip_level,
            samples_per_tile,
            first_tile_frame: (start_tile * samples_per_tile) as u64,
            tiles: channel_tiles,
        }]
    }

    /// Get tiles for specific channel only
    pub fn get_channel_tiles(
        &self,
        channel: usize,
        start_frame: u64,
        end_frame: u64,
        pixels_per_second: f64,
        sample_rate: u32,
    ) -> Option<(usize, Vec<CachedTile>)> {
        let mip_level = self.wfc.select_mip_level(pixels_per_second, sample_rate);
        let level_data = &self.wfc.mip_levels[mip_level];
        let samples_per_tile = MIP_TILE_SAMPLES[mip_level];

        let channel_data = level_data.tiles.get(channel)?;

        let start_tile = (start_frame as usize) / samples_per_tile;
        let end_tile = ((end_frame as usize) + samples_per_tile - 1) / samples_per_tile;

        let tiles: Vec<CachedTile> = (start_tile..end_tile)
            .filter_map(|tile_idx| {
                channel_data.get(tile_idx).map(|td| CachedTile {
                    tile_index: tile_idx,
                    frame_offset: (tile_idx * samples_per_tile) as u64,
                    min: td.min,
                    max: td.max,
                })
            })
            .collect();

        Some((mip_level, tiles))
    }

    /// Get merged (L+R combined) tiles for stereo display
    pub fn get_merged_tiles(
        &self,
        start_frame: u64,
        end_frame: u64,
        pixels_per_second: f64,
        sample_rate: u32,
    ) -> Vec<CachedTile> {
        let mip_level = self.wfc.select_mip_level(pixels_per_second, sample_rate);
        let level_data = &self.wfc.mip_levels[mip_level];
        let samples_per_tile = MIP_TILE_SAMPLES[mip_level];

        let start_tile = (start_frame as usize) / samples_per_tile;
        let end_tile = ((end_frame as usize) + samples_per_tile - 1) / samples_per_tile;

        let num_channels = level_data.tiles.len();

        (start_tile..end_tile)
            .filter_map(|tile_idx| {
                // Merge all channels
                let mut min = f32::MAX;
                let mut max = f32::MIN;

                for ch in 0..num_channels {
                    if let Some(tile) = level_data.tiles.get(ch).and_then(|t| t.get(tile_idx)) {
                        min = min.min(tile.min);
                        max = max.max(tile.max);
                    }
                }

                if min <= max {
                    Some(CachedTile {
                        tile_index: tile_idx,
                        frame_offset: (tile_idx * samples_per_tile) as u64,
                        min,
                        max,
                    })
                } else {
                    None
                }
            })
            .collect()
    }

    /// Get peak value at specific time
    pub fn get_peak_at_time(&self, time_secs: f64, sample_rate: u32) -> Option<TileData> {
        let frame = (time_secs * sample_rate as f64) as u64;

        // Use finest mip level for accuracy
        let level = &self.wfc.mip_levels[0];
        let samples_per_tile = MIP_TILE_SAMPLES[0];
        let tile_idx = (frame as usize) / samples_per_tile;

        // Merge all channels
        let mut min = f32::MAX;
        let mut max = f32::MIN;

        for ch_tiles in &level.tiles {
            if let Some(tile) = ch_tiles.get(tile_idx) {
                min = min.min(tile.min);
                max = max.max(tile.max);
            }
        }

        if min <= max {
            Some(TileData::new(min, max))
        } else {
            None
        }
    }

    /// Get statistics for a time range
    pub fn get_range_stats(&self, start_frame: u64, end_frame: u64) -> RangeStats {
        let level = &self.wfc.mip_levels[0]; // Use finest level
        let samples_per_tile = MIP_TILE_SAMPLES[0];

        let start_tile = (start_frame as usize) / samples_per_tile;
        let end_tile = ((end_frame as usize) + samples_per_tile - 1) / samples_per_tile;

        let mut peak_min = f32::MAX;
        let mut peak_max = f32::MIN;
        let mut tile_count = 0;

        for ch_tiles in &level.tiles {
            for tile_idx in start_tile..end_tile {
                if let Some(tile) = ch_tiles.get(tile_idx) {
                    peak_min = peak_min.min(tile.min);
                    peak_max = peak_max.max(tile.max);
                    tile_count += 1;
                }
            }
        }

        RangeStats {
            peak_min,
            peak_max,
            peak_amplitude: peak_max - peak_min,
            tile_count,
        }
    }

    /// Get info about the cache
    pub fn info(&self) -> CacheInfo {
        CacheInfo {
            channels: self.wfc.header.channels,
            sample_rate: self.wfc.header.sample_rate,
            total_frames: self.wfc.header.total_frames,
            duration_secs: self.wfc.header.duration_secs,
            base_tiles: self.wfc.header.num_base_tiles,
            memory_usage: self.wfc.memory_usage(),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATS
// ═══════════════════════════════════════════════════════════════════════════

/// Statistics for a time range
#[derive(Debug, Clone)]
pub struct RangeStats {
    pub peak_min: f32,
    pub peak_max: f32,
    pub peak_amplitude: f32,
    pub tile_count: usize,
}

/// Cache info
#[derive(Debug, Clone)]
pub struct CacheInfo {
    pub channels: u8,
    pub sample_rate: u32,
    pub total_frames: u64,
    pub duration_secs: f64,
    pub base_tiles: u32,
    pub memory_usage: usize,
}

// ═══════════════════════════════════════════════════════════════════════════
// FLAT ARRAY OUTPUT FOR FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Convert tiles to flat f32 array for FFI
///
/// Format: [min0, max0, min1, max1, ...]
pub fn tiles_to_flat_array(tiles: &[CachedTile]) -> Vec<f32> {
    let mut result = Vec::with_capacity(tiles.len() * 2);
    for tile in tiles {
        result.push(tile.min);
        result.push(tile.max);
    }
    result
}

/// Convert tiles to flat array with frame offsets
///
/// Format: [frame0, min0, max0, frame1, min1, max1, ...]
#[allow(dead_code)]
pub fn tiles_to_flat_with_frames(tiles: &[CachedTile]) -> Vec<f32> {
    let mut result = Vec::with_capacity(tiles.len() * 3);
    for tile in tiles {
        result.push(tile.frame_offset as f32);
        result.push(tile.min);
        result.push(tile.max);
    }
    result
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::format::WfcFile;

    fn create_test_wfc() -> WfcFile {
        let mut wfc = WfcFile::new(2, 48000, 48000); // 1 second stereo

        // Fill with test data
        for level_idx in 0..NUM_MIP_LEVELS {
            let samples_per_tile = MIP_TILE_SAMPLES[level_idx];
            let num_tiles = (48000 + samples_per_tile - 1) / samples_per_tile;

            for ch in 0..2 {
                wfc.mip_levels[level_idx].tiles[ch] = (0..num_tiles)
                    .map(|i| {
                        let t = i as f32 / num_tiles as f32;
                        TileData::new(-0.5 * t, 0.5 * t)
                    })
                    .collect();
            }
        }

        wfc
    }

    #[test]
    fn test_get_tiles() {
        let wfc = create_test_wfc();
        let query = WaveCacheQuery::new(&wfc);

        let response = query.get_tiles(0, 24000, 100.0, 48000);
        assert_eq!(response.len(), 1);
        assert!(!response[0].tiles.is_empty());
    }

    #[test]
    fn test_merged_tiles() {
        let wfc = create_test_wfc();
        let query = WaveCacheQuery::new(&wfc);

        let tiles = query.get_merged_tiles(0, 48000, 100.0, 48000);
        assert!(!tiles.is_empty());
    }

    #[test]
    fn test_flat_array_output() {
        let tiles = vec![
            CachedTile { tile_index: 0, frame_offset: 0, min: -0.5, max: 0.5 },
            CachedTile { tile_index: 1, frame_offset: 256, min: -0.3, max: 0.3 },
        ];

        let flat = tiles_to_flat_array(&tiles);
        assert_eq!(flat.len(), 4);
        assert_eq!(flat[0], -0.5);
        assert_eq!(flat[1], 0.5);
    }
}
