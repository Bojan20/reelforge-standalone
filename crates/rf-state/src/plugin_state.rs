//! Plugin State Management
//!
//! Handles third-party plugin state persistence for project portability.
//! Supports VST3, AU, CLAP, and AAX plugin formats.
//!
//! File format: .ffstate (FluxForge State)
//!
//! Documentation: .claude/architecture/PLUGIN_STATE_SYSTEM.md

use std::io::{Read, Write};
use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Magic bytes for .ffstate files
pub const FFSTATE_MAGIC: [u8; 4] = [0x46, 0x46, 0x53, 0x54]; // "FFST"

/// Current file format version
pub const FFSTATE_VERSION: u32 = 1;

/// Header size (fixed)
pub const FFSTATE_HEADER_SIZE: usize = 32;

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN FORMAT
// ═══════════════════════════════════════════════════════════════════════════

/// Supported plugin formats
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum PluginFormat {
    Vst3 = 0,
    Au = 1,
    Clap = 2,
    Aax = 3,
    Lv2 = 4,
}

impl PluginFormat {
    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            0 => Some(Self::Vst3),
            1 => Some(Self::Au),
            2 => Some(Self::Clap),
            3 => Some(Self::Aax),
            4 => Some(Self::Lv2),
            _ => None,
        }
    }

    pub fn extension(&self) -> &'static str {
        match self {
            Self::Vst3 => "vst3",
            Self::Au => "component",
            Self::Clap => "clap",
            Self::Aax => "aaxplugin",
            Self::Lv2 => "lv2",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Vst3 => "VST3",
            Self::Au => "Audio Units",
            Self::Clap => "CLAP",
            Self::Aax => "AAX",
            Self::Lv2 => "LV2",
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN UID
// ═══════════════════════════════════════════════════════════════════════════

/// Universal Plugin Identifier
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PluginUid {
    pub format: PluginFormat,
    /// VST3: 32-char hex FUID
    /// AU: "type:subtype:manufacturer"
    /// CLAP: reverse domain notation
    pub uid: String,
}

impl PluginUid {
    pub fn new(format: PluginFormat, uid: impl Into<String>) -> Self {
        Self {
            format,
            uid: uid.into(),
        }
    }

    /// Create VST3 UID from 128-bit FUID
    pub fn vst3(fuid: [u8; 16]) -> Self {
        let hex: String = fuid.iter().map(|b| format!("{:02X}", b)).collect();
        Self::new(PluginFormat::Vst3, hex)
    }

    /// Create VST3 UID from hex string
    pub fn vst3_hex(hex: &str) -> Result<Self, &'static str> {
        let clean: String = hex
            .chars()
            .filter(|c| c.is_ascii_hexdigit())
            .collect();
        if clean.len() != 32 {
            return Err("VST3 FUID must be 32 hex characters");
        }
        Ok(Self::new(PluginFormat::Vst3, clean.to_uppercase()))
    }

    /// Create AU Component ID
    pub fn au(type_code: &str, subtype: &str, manufacturer: &str) -> Self {
        Self::new(PluginFormat::Au, format!("{}:{}:{}", type_code, subtype, manufacturer))
    }

    /// Create CLAP ID
    pub fn clap(id: &str) -> Self {
        Self::new(PluginFormat::Clap, id)
    }

    /// Parse AU component parts
    pub fn au_components(&self) -> Option<(&str, &str, &str)> {
        if self.format != PluginFormat::Au {
            return None;
        }
        let parts: Vec<&str> = self.uid.split(':').collect();
        if parts.len() != 3 {
            return None;
        }
        Some((parts[0], parts[1], parts[2]))
    }
}

impl std::fmt::Display for PluginUid {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.format.display_name(), self.uid)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN STATE CHUNK
// ═══════════════════════════════════════════════════════════════════════════

/// Binary state data from a plugin
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginStateChunk {
    /// Plugin this state belongs to
    pub plugin_uid: PluginUid,

    /// Raw binary state data (plugin-specific format)
    pub state_data: Vec<u8>,

    /// When state was captured (Unix timestamp ms)
    pub captured_at: i64,

    /// Optional preset name
    pub preset_name: Option<String>,
}

impl PluginStateChunk {
    pub fn new(plugin_uid: PluginUid, state_data: Vec<u8>) -> Self {
        Self {
            plugin_uid,
            state_data,
            captured_at: chrono::Utc::now().timestamp_millis(),
            preset_name: None,
        }
    }

    pub fn with_preset(mut self, name: impl Into<String>) -> Self {
        self.preset_name = Some(name.into());
        self
    }

    /// Size of state data in bytes
    pub fn size(&self) -> usize {
        self.state_data.len()
    }

    /// Write to .ffstate binary format
    pub fn write_to<W: Write>(&self, writer: &mut W) -> std::io::Result<()> {
        let uid_bytes = self.plugin_uid.to_string().as_bytes().to_vec();
        let preset_bytes = self.preset_name.as_ref().map(|s| s.as_bytes().to_vec()).unwrap_or_default();

        // Header (32 bytes)
        writer.write_all(&FFSTATE_MAGIC)?;
        writer.write_all(&FFSTATE_VERSION.to_le_bytes())?;
        writer.write_all(&self.captured_at.to_le_bytes())?;
        writer.write_all(&[0u8; 12])?; // Padding to 32 bytes

        // UID
        writer.write_all(&(uid_bytes.len() as u32).to_le_bytes())?;
        writer.write_all(&uid_bytes)?;

        // Preset name
        writer.write_all(&(preset_bytes.len() as u32).to_le_bytes())?;
        if !preset_bytes.is_empty() {
            writer.write_all(&preset_bytes)?;
        }

        // State data
        writer.write_all(&(self.state_data.len() as u64).to_le_bytes())?;
        writer.write_all(&self.state_data)?;

        // CRC32
        let crc = crc32_checksum(&self.state_data);
        writer.write_all(&crc.to_le_bytes())?;

        Ok(())
    }

    /// Write to bytes
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buffer = Vec::new();
        self.write_to(&mut buffer).expect("Vec write should not fail");
        buffer
    }

    /// Read from .ffstate binary format
    pub fn read_from<R: Read>(reader: &mut R) -> std::io::Result<Self> {
        // Header
        let mut magic = [0u8; 4];
        reader.read_exact(&mut magic)?;
        if magic != FFSTATE_MAGIC {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Invalid .ffstate magic",
            ));
        }

        let mut version_bytes = [0u8; 4];
        reader.read_exact(&mut version_bytes)?;
        let version = u32::from_le_bytes(version_bytes);
        if version > FFSTATE_VERSION {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("Unsupported .ffstate version: {}", version),
            ));
        }

        let mut timestamp_bytes = [0u8; 8];
        reader.read_exact(&mut timestamp_bytes)?;
        let captured_at = i64::from_le_bytes(timestamp_bytes);

        let mut padding = [0u8; 12];
        reader.read_exact(&mut padding)?;

        // UID
        let mut uid_len_bytes = [0u8; 4];
        reader.read_exact(&mut uid_len_bytes)?;
        let uid_len = u32::from_le_bytes(uid_len_bytes) as usize;
        let mut uid_bytes = vec![0u8; uid_len];
        reader.read_exact(&mut uid_bytes)?;
        let uid_string = String::from_utf8(uid_bytes).map_err(|e| {
            std::io::Error::new(std::io::ErrorKind::InvalidData, e)
        })?;

        // Parse UID (format:value)
        let plugin_uid = parse_uid_string(&uid_string)?;

        // Preset name
        let mut preset_len_bytes = [0u8; 4];
        reader.read_exact(&mut preset_len_bytes)?;
        let preset_len = u32::from_le_bytes(preset_len_bytes) as usize;
        let preset_name = if preset_len > 0 {
            let mut preset_bytes = vec![0u8; preset_len];
            reader.read_exact(&mut preset_bytes)?;
            Some(String::from_utf8(preset_bytes).map_err(|e| {
                std::io::Error::new(std::io::ErrorKind::InvalidData, e)
            })?)
        } else {
            None
        };

        // State data
        let mut state_len_bytes = [0u8; 8];
        reader.read_exact(&mut state_len_bytes)?;
        let state_len = u64::from_le_bytes(state_len_bytes) as usize;
        let mut state_data = vec![0u8; state_len];
        reader.read_exact(&mut state_data)?;

        // CRC32 (verify)
        let mut crc_bytes = [0u8; 4];
        reader.read_exact(&mut crc_bytes)?;
        let stored_crc = u32::from_le_bytes(crc_bytes);
        let computed_crc = crc32_checksum(&state_data);
        if stored_crc != computed_crc {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "CRC32 checksum mismatch",
            ));
        }

        Ok(Self {
            plugin_uid,
            state_data,
            captured_at,
            preset_name,
        })
    }

    /// Read from bytes
    pub fn from_bytes(bytes: &[u8]) -> std::io::Result<Self> {
        Self::read_from(&mut std::io::Cursor::new(bytes))
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN STATE STORAGE
// ═══════════════════════════════════════════════════════════════════════════

/// Storage for plugin states (in-memory cache)
#[derive(Debug, Default)]
pub struct PluginStateStorage {
    /// Map: (track_id, slot_index) -> state chunk
    states: std::collections::HashMap<(u32, u32), PluginStateChunk>,
}

impl PluginStateStorage {
    pub fn new() -> Self {
        Self::default()
    }

    /// Store plugin state
    pub fn store(&mut self, track_id: u32, slot_index: u32, chunk: PluginStateChunk) {
        self.states.insert((track_id, slot_index), chunk);
    }

    /// Get plugin state
    pub fn get(&self, track_id: u32, slot_index: u32) -> Option<&PluginStateChunk> {
        self.states.get(&(track_id, slot_index))
    }

    /// Remove plugin state
    pub fn remove(&mut self, track_id: u32, slot_index: u32) -> Option<PluginStateChunk> {
        self.states.remove(&(track_id, slot_index))
    }

    /// Get all states for a track
    pub fn get_track_states(&self, track_id: u32) -> Vec<(u32, &PluginStateChunk)> {
        self.states
            .iter()
            .filter(|((tid, _), _)| *tid == track_id)
            .map(|((_, slot), chunk)| (*slot, chunk))
            .collect()
    }

    /// Clear all states
    pub fn clear(&mut self) {
        self.states.clear();
    }

    /// Number of stored states
    pub fn len(&self) -> usize {
        self.states.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.states.is_empty()
    }

    /// Iterate all states
    pub fn iter(&self) -> impl Iterator<Item = ((u32, u32), &PluginStateChunk)> {
        self.states.iter().map(|(k, v)| (*k, v))
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Parse UID string (format:value)
fn parse_uid_string(s: &str) -> std::io::Result<PluginUid> {
    let parts: Vec<&str> = s.splitn(2, ':').collect();
    if parts.len() != 2 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("Invalid UID format: {}", s),
        ));
    }

    let format = match parts[0] {
        "VST3" => PluginFormat::Vst3,
        "Audio Units" => PluginFormat::Au,
        "CLAP" => PluginFormat::Clap,
        "AAX" => PluginFormat::Aax,
        "LV2" => PluginFormat::Lv2,
        _ => {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("Unknown plugin format: {}", parts[0]),
            ))
        }
    };

    Ok(PluginUid::new(format, parts[1]))
}

/// Simple CRC32 checksum (IEEE polynomial)
fn crc32_checksum(data: &[u8]) -> u32 {
    let mut crc = 0xFFFFFFFFu32;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            if (crc & 1) != 0 {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    !crc
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plugin_uid_vst3() {
        let uid = PluginUid::vst3_hex("58E595CC2C1242FB8E32F4C9D39C5F42").unwrap();
        assert_eq!(uid.format, PluginFormat::Vst3);
        assert_eq!(uid.uid, "58E595CC2C1242FB8E32F4C9D39C5F42");
    }

    #[test]
    fn test_plugin_uid_au() {
        let uid = PluginUid::au("aufx", "prQ3", "FabF");
        assert_eq!(uid.format, PluginFormat::Au);
        assert_eq!(uid.au_components(), Some(("aufx", "prQ3", "FabF")));
    }

    #[test]
    fn test_state_chunk_roundtrip() {
        let uid = PluginUid::vst3_hex("58E595CC2C1242FB8E32F4C9D39C5F42").unwrap();
        let state_data = vec![1, 2, 3, 4, 5, 6, 7, 8];
        let chunk = PluginStateChunk::new(uid, state_data.clone())
            .with_preset("My Preset");

        let bytes = chunk.to_bytes();
        let restored = PluginStateChunk::from_bytes(&bytes).unwrap();

        assert_eq!(restored.plugin_uid, chunk.plugin_uid);
        assert_eq!(restored.state_data, state_data);
        assert_eq!(restored.preset_name, Some("My Preset".to_string()));
    }

    #[test]
    fn test_state_storage() {
        let mut storage = PluginStateStorage::new();
        let uid = PluginUid::clap("com.fabfilter.pro-q-3");
        let chunk = PluginStateChunk::new(uid, vec![1, 2, 3]);

        storage.store(1, 0, chunk.clone());
        assert_eq!(storage.len(), 1);

        let retrieved = storage.get(1, 0).unwrap();
        assert_eq!(retrieved.state_data, vec![1, 2, 3]);

        let track_states = storage.get_track_states(1);
        assert_eq!(track_states.len(), 1);
    }
}
