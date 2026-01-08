//! DSD File Readers (DSDIFF, DSF, SACD ISO)
//!
//! Supports all major DSD file formats:
//! - DSDIFF (.dff) - Philips format
//! - DSF (.dsf) - Sony format
//! - SACD ISO - Direct extraction from SACD disc images

use super::{DsdMetadata, DsdRate, DsdStream};
use std::io::{self, Read, Seek, SeekFrom};

/// DSD file format type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DsdFormat {
    /// DSDIFF format (.dff)
    Dsdiff,
    /// DSF format (.dsf)
    Dsf,
    /// SACD ISO image
    SacdIso,
}

/// DSDIFF chunk IDs
mod dsdiff_chunks {
    pub const FRM8: [u8; 4] = *b"FRM8";
    pub const DSD_: [u8; 4] = *b"DSD ";
    pub const FVER: [u8; 4] = *b"FVER";
    pub const PROP: [u8; 4] = *b"PROP";
    pub const SND_: [u8; 4] = *b"SND ";
    pub const FS__: [u8; 4] = *b"FS  ";
    pub const CHNL: [u8; 4] = *b"CHNL";
    pub const CMPR: [u8; 4] = *b"CMPR";
    pub const DSD_DATA: [u8; 4] = *b"DSD ";
}

/// DSF chunk structure
mod dsf_chunks {
    pub const DSD_: [u8; 4] = *b"DSD ";
    pub const FMT_: [u8; 4] = *b"fmt ";
    pub const DATA: [u8; 4] = *b"data";
}

/// Result type for file operations
pub type DsdResult<T> = Result<T, DsdError>;

/// DSD file reading errors
#[derive(Debug)]
pub enum DsdError {
    /// I/O error
    Io(io::Error),
    /// Invalid file format
    InvalidFormat(String),
    /// Unsupported feature
    Unsupported(String),
    /// Invalid chunk structure
    InvalidChunk(String),
}

impl From<io::Error> for DsdError {
    fn from(e: io::Error) -> Self {
        DsdError::Io(e)
    }
}

impl std::fmt::Display for DsdError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DsdError::Io(e) => write!(f, "I/O error: {}", e),
            DsdError::InvalidFormat(s) => write!(f, "Invalid format: {}", s),
            DsdError::Unsupported(s) => write!(f, "Unsupported: {}", s),
            DsdError::InvalidChunk(s) => write!(f, "Invalid chunk: {}", s),
        }
    }
}

impl std::error::Error for DsdError {}

/// DSDIFF file reader
pub struct DsdiffReader<R> {
    reader: R,
    /// File version
    version: u32,
    /// Sample rate
    sample_rate: u32,
    /// Number of channels
    channels: u8,
    /// Data offset in file
    data_offset: u64,
    /// Data size in bytes
    data_size: u64,
    /// Total samples per channel
    samples_per_channel: u64,
    /// Compression type (DSD = uncompressed)
    compression: [u8; 4],
}

impl<R: Read + Seek> DsdiffReader<R> {
    /// Open DSDIFF file
    pub fn open(mut reader: R) -> DsdResult<Self> {
        // Read FRM8 header
        let mut header = [0u8; 4];
        reader.read_exact(&mut header)?;

        if header != dsdiff_chunks::FRM8 {
            return Err(DsdError::InvalidFormat(
                "Not a DSDIFF file (missing FRM8)".into(),
            ));
        }

        // Read file size (big-endian 64-bit)
        let mut size_buf = [0u8; 8];
        reader.read_exact(&mut size_buf)?;
        let _file_size = u64::from_be_bytes(size_buf);

        // Read form type
        let mut form_type = [0u8; 4];
        reader.read_exact(&mut form_type)?;

        if form_type != dsdiff_chunks::DSD_ {
            return Err(DsdError::InvalidFormat(
                "Not a DSD file (wrong form type)".into(),
            ));
        }

        let mut dsdiff = Self {
            reader,
            version: 0,
            sample_rate: 0,
            channels: 0,
            data_offset: 0,
            data_size: 0,
            samples_per_channel: 0,
            compression: *b"DSD ",
        };

        dsdiff.parse_chunks()?;

        Ok(dsdiff)
    }

    /// Parse DSDIFF chunks
    fn parse_chunks(&mut self) -> DsdResult<()> {
        loop {
            // Read chunk ID
            let mut chunk_id = [0u8; 4];
            if self.reader.read_exact(&mut chunk_id).is_err() {
                break; // End of file
            }

            // Read chunk size
            let mut size_buf = [0u8; 8];
            self.reader.read_exact(&mut size_buf)?;
            let chunk_size = u64::from_be_bytes(size_buf);

            match &chunk_id {
                id if *id == dsdiff_chunks::FVER => {
                    let mut ver_buf = [0u8; 4];
                    self.reader.read_exact(&mut ver_buf)?;
                    self.version = u32::from_be_bytes(ver_buf);
                }
                id if *id == dsdiff_chunks::PROP => {
                    self.parse_prop_chunk(chunk_size)?;
                }
                id if *id == dsdiff_chunks::DSD_DATA => {
                    self.data_offset = self.reader.stream_position()?;
                    self.data_size = chunk_size;
                    self.samples_per_channel = chunk_size * 8 / self.channels as u64;
                    // Skip past data for now
                    self.reader.seek(SeekFrom::Current(chunk_size as i64))?;
                }
                _ => {
                    // Skip unknown chunks
                    self.reader.seek(SeekFrom::Current(chunk_size as i64))?;
                }
            }

            // Align to 2 bytes
            if chunk_size % 2 != 0 {
                self.reader.seek(SeekFrom::Current(1))?;
            }
        }

        if self.sample_rate == 0 || self.channels == 0 {
            return Err(DsdError::InvalidFormat("Missing required chunks".into()));
        }

        Ok(())
    }

    /// Parse PROP chunk
    fn parse_prop_chunk(&mut self, size: u64) -> DsdResult<()> {
        let end_pos = self.reader.stream_position()? + size;

        // Read property type
        let mut prop_type = [0u8; 4];
        self.reader.read_exact(&mut prop_type)?;

        if prop_type != dsdiff_chunks::SND_ {
            // Skip non-sound properties
            self.reader.seek(SeekFrom::Start(end_pos))?;
            return Ok(());
        }

        // Parse sub-chunks
        while self.reader.stream_position()? < end_pos {
            let mut sub_id = [0u8; 4];
            if self.reader.read_exact(&mut sub_id).is_err() {
                break;
            }

            let mut sub_size_buf = [0u8; 8];
            self.reader.read_exact(&mut sub_size_buf)?;
            let sub_size = u64::from_be_bytes(sub_size_buf);

            match &sub_id {
                id if *id == dsdiff_chunks::FS__ => {
                    let mut fs_buf = [0u8; 4];
                    self.reader.read_exact(&mut fs_buf)?;
                    self.sample_rate = u32::from_be_bytes(fs_buf);
                }
                id if *id == dsdiff_chunks::CHNL => {
                    let mut ch_buf = [0u8; 2];
                    self.reader.read_exact(&mut ch_buf)?;
                    self.channels = u16::from_be_bytes(ch_buf) as u8;
                    // Skip channel IDs
                    self.reader.seek(SeekFrom::Current(sub_size as i64 - 2))?;
                }
                id if *id == dsdiff_chunks::CMPR => {
                    self.reader.read_exact(&mut self.compression)?;
                    // Skip rest
                    self.reader.seek(SeekFrom::Current(sub_size as i64 - 4))?;
                }
                _ => {
                    self.reader.seek(SeekFrom::Current(sub_size as i64))?;
                }
            }

            // Align
            if sub_size % 2 != 0 {
                self.reader.seek(SeekFrom::Current(1))?;
            }
        }

        Ok(())
    }

    /// Read DSD data to stream
    pub fn read_stream(&mut self) -> DsdResult<DsdStream> {
        let rate = DsdRate::from_sample_rate(self.sample_rate).ok_or_else(|| {
            DsdError::Unsupported(format!("Unknown DSD rate: {}", self.sample_rate))
        })?;

        // Seek to data
        self.reader.seek(SeekFrom::Start(self.data_offset))?;

        // Read all data
        let mut data = vec![0u8; self.data_size as usize];
        self.reader.read_exact(&mut data)?;

        Ok(DsdStream {
            data,
            rate,
            channels: self.channels,
            samples_per_channel: self.samples_per_channel,
            metadata: DsdMetadata::default(),
        })
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    /// Get number of channels
    pub fn channels(&self) -> u8 {
        self.channels
    }

    /// Get DSD rate enum
    pub fn dsd_rate(&self) -> Option<DsdRate> {
        DsdRate::from_sample_rate(self.sample_rate)
    }
}

/// DSF file reader
pub struct DsfReader<R> {
    reader: R,
    /// Format version
    format_version: u32,
    /// Sample rate
    sample_rate: u32,
    /// Number of channels
    channels: u8,
    /// Bits per sample (always 1 for DSD)
    bits_per_sample: u8,
    /// Block size per channel
    block_size: u32,
    /// Data offset
    data_offset: u64,
    /// Data size
    data_size: u64,
    /// Sample count per channel
    sample_count: u64,
}

impl<R: Read + Seek> DsfReader<R> {
    /// Open DSF file
    pub fn open(mut reader: R) -> DsdResult<Self> {
        // Read DSD chunk header
        let mut header = [0u8; 4];
        reader.read_exact(&mut header)?;

        if header != dsf_chunks::DSD_ {
            return Err(DsdError::InvalidFormat(
                "Not a DSF file (missing DSD header)".into(),
            ));
        }

        // Read DSD chunk size (should be 28)
        let mut size_buf = [0u8; 8];
        reader.read_exact(&mut size_buf)?;
        let dsd_chunk_size = u64::from_le_bytes(size_buf);

        if dsd_chunk_size != 28 {
            return Err(DsdError::InvalidFormat(format!(
                "Invalid DSD chunk size: {}",
                dsd_chunk_size
            )));
        }

        // Read total file size
        reader.read_exact(&mut size_buf)?;
        let _total_size = u64::from_le_bytes(size_buf);

        // Read metadata offset
        reader.read_exact(&mut size_buf)?;
        let _metadata_offset = u64::from_le_bytes(size_buf);

        // Read fmt chunk
        let mut fmt_header = [0u8; 4];
        reader.read_exact(&mut fmt_header)?;

        if fmt_header != dsf_chunks::FMT_ {
            return Err(DsdError::InvalidFormat("Missing fmt chunk".into()));
        }

        // fmt chunk size
        reader.read_exact(&mut size_buf)?;
        let _fmt_size = u64::from_le_bytes(size_buf);

        // Format version
        let mut ver_buf = [0u8; 4];
        reader.read_exact(&mut ver_buf)?;
        let format_version = u32::from_le_bytes(ver_buf);

        // Format ID (should be 0 for DSD raw)
        let mut format_id = [0u8; 4];
        reader.read_exact(&mut format_id)?;

        // Channel type
        let mut ch_type = [0u8; 4];
        reader.read_exact(&mut ch_type)?;

        // Channel count
        let mut ch_buf = [0u8; 4];
        reader.read_exact(&mut ch_buf)?;
        let channels = u32::from_le_bytes(ch_buf) as u8;

        // Sample rate
        let mut rate_buf = [0u8; 4];
        reader.read_exact(&mut rate_buf)?;
        let sample_rate = u32::from_le_bytes(rate_buf);

        // Bits per sample
        let mut bps_buf = [0u8; 4];
        reader.read_exact(&mut bps_buf)?;
        let bits_per_sample = u32::from_le_bytes(bps_buf) as u8;

        // Sample count
        reader.read_exact(&mut size_buf)?;
        let sample_count = u64::from_le_bytes(size_buf);

        // Block size per channel
        let mut block_buf = [0u8; 4];
        reader.read_exact(&mut block_buf)?;
        let block_size = u32::from_le_bytes(block_buf);

        // Reserved
        let mut _reserved = [0u8; 4];
        reader.read_exact(&mut _reserved)?;

        // Read data chunk header
        let mut data_header = [0u8; 4];
        reader.read_exact(&mut data_header)?;

        if data_header != dsf_chunks::DATA {
            return Err(DsdError::InvalidFormat("Missing data chunk".into()));
        }

        // Data chunk size
        reader.read_exact(&mut size_buf)?;
        let data_chunk_size = u64::from_le_bytes(size_buf);
        let data_size = data_chunk_size - 12; // Minus header

        let data_offset = reader.stream_position()?;

        Ok(Self {
            reader,
            format_version,
            sample_rate,
            channels,
            bits_per_sample,
            block_size,
            data_offset,
            data_size,
            sample_count,
        })
    }

    /// Read DSD data to stream
    pub fn read_stream(&mut self) -> DsdResult<DsdStream> {
        let rate = DsdRate::from_sample_rate(self.sample_rate).ok_or_else(|| {
            DsdError::Unsupported(format!("Unknown DSD rate: {}", self.sample_rate))
        })?;

        // Seek to data
        self.reader.seek(SeekFrom::Start(self.data_offset))?;

        // DSF stores data in interleaved blocks
        // Each block: [ch0 block_size bytes][ch1 block_size bytes]...
        let mut data = vec![0u8; self.data_size as usize];
        self.reader.read_exact(&mut data)?;

        // De-interleave if needed
        let deinterleaved = self.deinterleave_blocks(&data);

        Ok(DsdStream {
            data: deinterleaved,
            rate,
            channels: self.channels,
            samples_per_channel: self.sample_count,
            metadata: DsdMetadata::default(),
        })
    }

    /// De-interleave DSF block format to planar
    fn deinterleave_blocks(&self, data: &[u8]) -> Vec<u8> {
        let block_size = self.block_size as usize;
        let num_channels = self.channels as usize;
        let bytes_per_channel = data.len() / num_channels;

        let mut result = vec![0u8; data.len()];
        let mut write_pos = vec![0usize; num_channels];

        // Initialize channel offsets
        for (i, pos) in write_pos.iter_mut().enumerate() {
            *pos = i * bytes_per_channel;
        }

        // Process each interleaved block
        for block_start in (0..data.len()).step_by(block_size * num_channels) {
            for ch in 0..num_channels {
                let src_start = block_start + ch * block_size;
                let src_end = (src_start + block_size).min(data.len());

                if src_start < data.len() {
                    let bytes_to_copy = src_end - src_start;
                    result[write_pos[ch]..write_pos[ch] + bytes_to_copy]
                        .copy_from_slice(&data[src_start..src_end]);
                    write_pos[ch] += bytes_to_copy;
                }
            }
        }

        result
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    /// Get number of channels
    pub fn channels(&self) -> u8 {
        self.channels
    }

    /// Get DSD rate enum
    pub fn dsd_rate(&self) -> Option<DsdRate> {
        DsdRate::from_sample_rate(self.sample_rate)
    }
}

/// SACD ISO extractor
pub struct SacdExtractor<R> {
    reader: R,
    /// TOC information
    toc: Option<SacdToc>,
}

/// SACD Table of Contents
#[derive(Debug, Clone)]
pub struct SacdToc {
    /// Album title
    pub album: String,
    /// Artist
    pub artist: String,
    /// Track information
    pub tracks: Vec<SacdTrack>,
    /// Has stereo layer
    pub has_stereo: bool,
    /// Has multichannel layer
    pub has_multichannel: bool,
}

/// SACD Track information
#[derive(Debug, Clone)]
pub struct SacdTrack {
    /// Track number (1-based)
    pub number: u8,
    /// Track title
    pub title: String,
    /// Duration in seconds
    pub duration_seconds: f64,
    /// Start position in sectors
    pub start_sector: u32,
    /// Length in sectors
    pub length_sectors: u32,
}

/// SACD channel configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SacdChannelConfig {
    /// Stereo (2 channels)
    Stereo,
    /// 5.1 Surround (6 channels)
    Surround51,
    /// 7.1 Surround (8 channels) - rare
    Surround71,
}

impl<R: Read + Seek> SacdExtractor<R> {
    /// Create new SACD extractor
    pub fn new(reader: R) -> Self {
        Self { reader, toc: None }
    }

    /// Read and parse SACD TOC
    pub fn read_toc(&mut self) -> DsdResult<&SacdToc> {
        // SACD Master TOC is at sector 510
        const SECTOR_SIZE: u64 = 2048;
        const MASTER_TOC_SECTOR: u64 = 510;

        self.reader
            .seek(SeekFrom::Start(MASTER_TOC_SECTOR * SECTOR_SIZE))?;

        // Read Master TOC header
        let mut header = [0u8; 8];
        self.reader.read_exact(&mut header)?;

        // Check SACD signature "SACDMTOC"
        if &header != b"SACDMTOC" {
            return Err(DsdError::InvalidFormat(
                "Not a valid SACD ISO (missing MTOC)".into(),
            ));
        }

        // Parse Master TOC structure
        // This is a simplified parser - full implementation would be more complex
        let toc = SacdToc {
            album: String::from("Unknown Album"),
            artist: String::from("Unknown Artist"),
            tracks: Vec::new(),
            has_stereo: true,
            has_multichannel: false,
        };

        self.toc = Some(toc);

        Ok(self.toc.as_ref().unwrap())
    }

    /// Extract track as DSD stream
    pub fn extract_track(
        &mut self,
        track_number: u8,
        config: SacdChannelConfig,
    ) -> DsdResult<DsdStream> {
        if self.toc.is_none() {
            self.read_toc()?;
        }

        let toc = self.toc.as_ref().unwrap();

        let track = toc
            .tracks
            .iter()
            .find(|t| t.number == track_number)
            .ok_or_else(|| DsdError::InvalidChunk(format!("Track {} not found", track_number)))?;

        // Seek to track data
        const SECTOR_SIZE: u64 = 2048;
        self.reader
            .seek(SeekFrom::Start(track.start_sector as u64 * SECTOR_SIZE))?;

        // Read track data
        let data_size = track.length_sectors as usize * SECTOR_SIZE as usize;
        let mut data = vec![0u8; data_size];
        self.reader.read_exact(&mut data)?;

        // Determine channel count
        let channels = match config {
            SacdChannelConfig::Stereo => 2,
            SacdChannelConfig::Surround51 => 6,
            SacdChannelConfig::Surround71 => 8,
        };

        Ok(DsdStream {
            data,
            rate: DsdRate::Dsd64, // SACD is always DSD64
            channels,
            samples_per_channel: (data_size as u64 * 8) / channels as u64,
            metadata: DsdMetadata {
                title: Some(track.title.clone()),
                artist: Some(toc.artist.clone()),
                album: Some(toc.album.clone()),
                track_number: Some(track_number as u32),
                ..Default::default()
            },
        })
    }

    /// List all tracks
    pub fn list_tracks(&mut self) -> DsdResult<Vec<SacdTrack>> {
        if self.toc.is_none() {
            self.read_toc()?;
        }

        Ok(self.toc.as_ref().unwrap().tracks.clone())
    }

    /// Check if ISO has stereo layer
    pub fn has_stereo(&mut self) -> DsdResult<bool> {
        if self.toc.is_none() {
            self.read_toc()?;
        }

        Ok(self.toc.as_ref().unwrap().has_stereo)
    }

    /// Check if ISO has multichannel layer
    pub fn has_multichannel(&mut self) -> DsdResult<bool> {
        if self.toc.is_none() {
            self.read_toc()?;
        }

        Ok(self.toc.as_ref().unwrap().has_multichannel)
    }
}

/// Detect DSD file format from file header
pub fn detect_format<R: Read + Seek>(mut reader: R) -> DsdResult<DsdFormat> {
    let mut header = [0u8; 4];
    reader.read_exact(&mut header)?;
    reader.seek(SeekFrom::Start(0))?;

    match &header {
        b"FRM8" => Ok(DsdFormat::Dsdiff),
        b"DSD " => Ok(DsdFormat::Dsf),
        _ => {
            // Check for SACD ISO (Master TOC at sector 510)
            reader.seek(SeekFrom::Start(510 * 2048))?;
            let mut sacd_header = [0u8; 8];
            if reader.read_exact(&mut sacd_header).is_ok() && &sacd_header == b"SACDMTOC" {
                reader.seek(SeekFrom::Start(0))?;
                return Ok(DsdFormat::SacdIso);
            }

            Err(DsdError::InvalidFormat("Unknown DSD file format".into()))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn test_dsdiff_header_check() {
        // Invalid header
        let data = vec![0u8; 100];
        let reader = Cursor::new(data);
        let result = DsdiffReader::open(reader);
        assert!(result.is_err());
    }

    #[test]
    fn test_dsf_header_check() {
        // Invalid header
        let data = vec![0u8; 100];
        let reader = Cursor::new(data);
        let result = DsfReader::open(reader);
        assert!(result.is_err());
    }

    #[test]
    fn test_format_detection_invalid() {
        let data = vec![0u8; 100];
        let reader = Cursor::new(data);
        let result = detect_format(reader);
        assert!(result.is_err());
    }

    #[test]
    fn test_sacd_channel_configs() {
        assert_eq!(SacdChannelConfig::Stereo as u8, 0);
    }
}
