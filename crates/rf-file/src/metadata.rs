//! Audio Metadata — BWF, iXML, ID3, RIFF INFO
//!
//! Provides:
//! - BWF (Broadcast WAV Extension) metadata parsing
//! - iXML chunk parsing (embedded XML in WAV/BWF files)
//! - ID3v2 tag parsing (MP3, FLAC, OGG)
//! - RIFF INFO chunk parsing (WAV)
//! - Unified AudioMetadata model for all formats
//! - Boolean search engine (AND/OR/NOT) across metadata fields
//! - Batch metadata editing

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use crate::FileResult;

// ═══════════════════════════════════════════════════════════════════════════════
// UNIFIED METADATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified metadata container for all audio formats.
/// Fields are Optional — only populated if found in the file.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AudioMetadata {
    // ── BWF Standard Fields ──
    /// Description (BWF: 256 chars max)
    pub description: Option<String>,
    /// Originator (BWF: 32 chars max)
    pub originator: Option<String>,
    /// Originator reference code (BWF: 32 chars max)
    pub originator_reference: Option<String>,
    /// Origination date (BWF: YYYY-MM-DD)
    pub origination_date: Option<String>,
    /// Origination time (BWF: HH:MM:SS)
    pub origination_time: Option<String>,
    /// Time reference — sample position for timeline placement
    pub time_reference: Option<u64>,
    /// BWF version number
    pub bwf_version: Option<u16>,
    /// UMID (Unique Material Identifier, 64 bytes)
    pub umid: Option<String>,
    /// Loudness value (EBU R128, 0.01 LUFS units)
    pub loudness_value: Option<i16>,
    /// Loudness range (EBU R128, 0.01 LU units)
    pub loudness_range: Option<i16>,
    /// Max true peak level (0.01 dBTP units)
    pub max_true_peak: Option<i16>,
    /// Max momentary loudness (0.01 LUFS units)
    pub max_momentary_loudness: Option<i16>,
    /// Max short-term loudness (0.01 LUFS units)
    pub max_short_term_loudness: Option<i16>,

    // ── iXML Fields ──
    /// Project name (from iXML)
    pub project: Option<String>,
    /// Scene name/number
    pub scene: Option<String>,
    /// Take number
    pub take: Option<String>,
    /// Tape/reel identifier
    pub tape: Option<String>,
    /// Circle take (preferred take marker)
    pub circled: Option<bool>,
    /// Production notes
    pub note: Option<String>,
    /// Track names from iXML TRACK_LIST
    pub ixml_track_names: Option<Vec<String>>,

    // ── ID3 / Common Tag Fields ──
    /// Title (ID3: TIT2)
    pub title: Option<String>,
    /// Artist (ID3: TPE1)
    pub artist: Option<String>,
    /// Album (ID3: TALB)
    pub album: Option<String>,
    /// Genre (ID3: TCON)
    pub genre: Option<String>,
    /// Year/Date (ID3: TDRC)
    pub year: Option<String>,
    /// Track number (ID3: TRCK)
    pub track_number: Option<String>,
    /// Comment (ID3: COMM)
    pub comment: Option<String>,
    /// BPM/Tempo (ID3: TBPM)
    pub bpm: Option<f64>,
    /// Key (ID3: TKEY, e.g. "Am", "C#m")
    pub key: Option<String>,
    /// Copyright (ID3: TCOP)
    pub copyright: Option<String>,
    /// Encoder/Software (ID3: TSSE)
    pub encoder: Option<String>,

    // ── RIFF INFO Fields ──
    /// RIFF INFO: INAM (name)
    pub riff_name: Option<String>,
    /// RIFF INFO: IART (artist)
    pub riff_artist: Option<String>,
    /// RIFF INFO: ICMT (comment)
    pub riff_comment: Option<String>,
    /// RIFF INFO: IGNR (genre)
    pub riff_genre: Option<String>,
    /// RIFF INFO: ICRD (creation date)
    pub riff_creation_date: Option<String>,
    /// RIFF INFO: ISFT (software)
    pub riff_software: Option<String>,
    /// RIFF INFO: ICOP (copyright)
    pub riff_copyright: Option<String>,
    /// RIFF INFO: IKEY (keywords)
    pub riff_keywords: Option<String>,

    // ── User/Custom Fields ──
    /// User-defined tags (key-value pairs for custom metadata)
    pub custom_tags: HashMap<String, String>,

    // ── File-level ──
    /// Which metadata sources were found in the file
    pub sources: Vec<MetadataSource>,
}

/// Which metadata sources were detected in the file
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MetadataSource {
    Bwf,
    Ixml,
    Id3v2,
    RiffInfo,
    VorbisComment,
    FlacMetadata,
}

impl AudioMetadata {
    /// Check if any metadata was found
    pub fn is_empty(&self) -> bool {
        self.sources.is_empty()
    }

    /// Get all searchable text fields as a flat list of (field_name, value)
    pub fn searchable_fields(&self) -> Vec<(&str, &str)> {
        let mut fields = Vec::new();
        macro_rules! add {
            ($name:expr, $field:expr) => {
                if let Some(ref v) = $field {
                    fields.push(($name, v.as_str()));
                }
            };
        }
        add!("description", self.description);
        add!("originator", self.originator);
        add!("originator_reference", self.originator_reference);
        add!("project", self.project);
        add!("scene", self.scene);
        add!("take", self.take);
        add!("tape", self.tape);
        add!("note", self.note);
        add!("title", self.title);
        add!("artist", self.artist);
        add!("album", self.album);
        add!("genre", self.genre);
        add!("year", self.year);
        add!("track_number", self.track_number);
        add!("comment", self.comment);
        add!("key", self.key);
        add!("copyright", self.copyright);
        add!("encoder", self.encoder);
        add!("riff_name", self.riff_name);
        add!("riff_artist", self.riff_artist);
        add!("riff_comment", self.riff_comment);
        add!("riff_genre", self.riff_genre);
        add!("riff_creation_date", self.riff_creation_date);
        add!("riff_keywords", self.riff_keywords);
        add!("riff_software", self.riff_software);
        add!("riff_copyright", self.riff_copyright);

        for (k, v) in &self.custom_tags {
            fields.push((k.as_str(), v.as_str()));
        }

        fields
    }

    /// Merge metadata from another source (non-destructive — only fills None fields)
    pub fn merge(&mut self, other: &AudioMetadata) {
        macro_rules! merge_field {
            ($field:ident) => {
                if self.$field.is_none() && other.$field.is_some() {
                    self.$field = other.$field.clone();
                }
            };
        }
        merge_field!(description);
        merge_field!(originator);
        merge_field!(originator_reference);
        merge_field!(origination_date);
        merge_field!(origination_time);
        merge_field!(time_reference);
        merge_field!(bwf_version);
        merge_field!(umid);
        merge_field!(loudness_value);
        merge_field!(loudness_range);
        merge_field!(max_true_peak);
        merge_field!(max_momentary_loudness);
        merge_field!(max_short_term_loudness);
        merge_field!(project);
        merge_field!(scene);
        merge_field!(take);
        merge_field!(tape);
        merge_field!(circled);
        merge_field!(note);
        merge_field!(ixml_track_names);
        merge_field!(title);
        merge_field!(artist);
        merge_field!(album);
        merge_field!(genre);
        merge_field!(year);
        merge_field!(track_number);
        merge_field!(comment);
        merge_field!(bpm);
        merge_field!(key);
        merge_field!(copyright);
        merge_field!(encoder);
        merge_field!(riff_name);
        merge_field!(riff_artist);
        merge_field!(riff_comment);
        merge_field!(riff_genre);
        merge_field!(riff_creation_date);
        merge_field!(riff_software);
        merge_field!(riff_copyright);
        merge_field!(riff_keywords);

        for (k, v) in &other.custom_tags {
            self.custom_tags.entry(k.clone()).or_insert_with(|| v.clone());
        }

        for src in &other.sources {
            if !self.sources.contains(src) {
                self.sources.push(*src);
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BWF (Broadcast WAV Extension) PARSER
// ═══════════════════════════════════════════════════════════════════════════════

/// BWF 'bext' chunk structure (EBU Tech 3285)
/// Total fixed size: 602 bytes (before coding_history)
const BEXT_FIXED_SIZE: usize = 602;

/// Parse BWF 'bext' chunk from raw bytes
fn parse_bext_chunk(data: &[u8]) -> AudioMetadata {
    let mut meta = AudioMetadata::default();
    meta.sources.push(MetadataSource::Bwf);

    if data.len() < BEXT_FIXED_SIZE {
        return meta;
    }

    // Description: 256 bytes at offset 0
    meta.description = read_fixed_string(data, 0, 256);
    // Originator: 32 bytes at offset 256
    meta.originator = read_fixed_string(data, 256, 32);
    // OriginatorReference: 32 bytes at offset 288
    meta.originator_reference = read_fixed_string(data, 288, 32);
    // OriginationDate: 10 bytes at offset 320 (YYYY-MM-DD)
    meta.origination_date = read_fixed_string(data, 320, 10);
    // OriginationTime: 8 bytes at offset 330 (HH:MM:SS)
    meta.origination_time = read_fixed_string(data, 330, 8);
    // TimeReference: 8 bytes (u64 LE) at offset 338
    if data.len() >= 346 {
        meta.time_reference = Some(u64::from_le_bytes([
            data[338], data[339], data[340], data[341],
            data[342], data[343], data[344], data[345],
        ]));
    }
    // Version: 2 bytes (u16 LE) at offset 346
    if data.len() >= 348 {
        meta.bwf_version = Some(u16::from_le_bytes([data[346], data[347]]));
    }
    // UMID: 64 bytes at offset 348
    if data.len() >= 412 {
        let umid_bytes = &data[348..412];
        if umid_bytes.iter().any(|&b| b != 0) {
            meta.umid = Some(
                umid_bytes.iter().map(|b| format!("{:02X}", b)).collect::<String>()
            );
        }
    }
    // Loudness fields (BWF v2): offsets 412-421, each 2 bytes
    if data.len() >= 414 {
        let lv = i16::from_le_bytes([data[412], data[413]]);
        if lv != 0 { meta.loudness_value = Some(lv); }
    }
    if data.len() >= 416 {
        let lr = i16::from_le_bytes([data[414], data[415]]);
        if lr != 0 { meta.loudness_range = Some(lr); }
    }
    if data.len() >= 418 {
        let mtp = i16::from_le_bytes([data[416], data[417]]);
        if mtp != 0 { meta.max_true_peak = Some(mtp); }
    }
    if data.len() >= 420 {
        let mml = i16::from_le_bytes([data[418], data[419]]);
        if mml != 0 { meta.max_momentary_loudness = Some(mml); }
    }
    if data.len() >= 422 {
        let msl = i16::from_le_bytes([data[420], data[421]]);
        if msl != 0 { meta.max_short_term_loudness = Some(msl); }
    }

    meta
}

/// Read a fixed-length string from a byte buffer, trimming null bytes and whitespace
fn read_fixed_string(data: &[u8], offset: usize, len: usize) -> Option<String> {
    if data.len() < offset + len {
        return None;
    }
    let bytes = &data[offset..offset + len];
    let s = String::from_utf8_lossy(bytes)
        .trim_end_matches('\0')
        .trim()
        .to_string();
    if s.is_empty() { None } else { Some(s) }
}

// ═══════════════════════════════════════════════════════════════════════════════
// iXML PARSER
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse iXML chunk from raw bytes (XML embedded in WAV/BWF)
fn parse_ixml_chunk(data: &[u8]) -> AudioMetadata {
    let mut meta = AudioMetadata::default();
    meta.sources.push(MetadataSource::Ixml);

    let xml = String::from_utf8_lossy(data);
    let xml = xml.trim_end_matches('\0');

    // Simple XML tag extraction (no dependency on full XML parser)
    meta.project = extract_xml_tag(xml, "PROJECT");
    meta.scene = extract_xml_tag(xml, "SCENE");
    meta.take = extract_xml_tag(xml, "TAKE");
    meta.tape = extract_xml_tag(xml, "TAPE");
    meta.note = extract_xml_tag(xml, "NOTE");

    if let Some(circled_str) = extract_xml_tag(xml, "CIRCLED") {
        meta.circled = Some(circled_str == "TRUE" || circled_str == "1");
    }

    // Extract track names from TRACK_LIST — position-based to avoid infinite loop
    let mut track_names = Vec::new();
    let mut search_pos = 0;
    let open_tag = "<NAME>";
    let close_tag = "</NAME>";
    while search_pos < xml.len() {
        if let Some(open_pos) = xml[search_pos..].find(open_tag) {
            let abs_open = search_pos + open_pos;
            let content_start = abs_open + open_tag.len();
            if let Some(close_pos) = xml[content_start..].find(close_tag) {
                let content = xml[content_start..content_start + close_pos].trim();
                if !content.is_empty() {
                    track_names.push(content.to_string());
                }
                // Always advance past this close tag
                search_pos = content_start + close_pos + close_tag.len();
            } else {
                break; // No matching close tag
            }
        } else {
            break; // No more open tags
        }
    }
    if !track_names.is_empty() {
        meta.ixml_track_names = Some(track_names);
    }

    // BWF fields can also appear in iXML
    if let Some(desc) = extract_xml_tag(xml, "BWF_DESCRIPTION") {
        meta.description = Some(desc);
    }
    if let Some(orig) = extract_xml_tag(xml, "BWF_ORIGINATOR") {
        meta.originator = Some(orig);
    }
    if let Some(orig_ref) = extract_xml_tag(xml, "BWF_ORIGINATOR_REFERENCE") {
        meta.originator_reference = Some(orig_ref);
    }
    if let Some(date) = extract_xml_tag(xml, "BWF_ORIGINATION_DATE") {
        meta.origination_date = Some(date);
    }
    if let Some(time) = extract_xml_tag(xml, "BWF_ORIGINATION_TIME") {
        meta.origination_time = Some(time);
    }

    meta
}

/// Extract content of an XML tag: <TAG>content</TAG>
fn extract_xml_tag(xml: &str, tag: &str) -> Option<String> {
    extract_xml_tag_from(xml, tag)
}

fn extract_xml_tag_from(xml: &str, tag: &str) -> Option<String> {
    let open = format!("<{}>", tag);
    let close = format!("</{}>", tag);
    if let Some(start) = xml.find(&open) {
        let content_start = start + open.len();
        if let Some(end) = xml[content_start..].find(&close) {
            let content = xml[content_start..content_start + end].trim();
            if !content.is_empty() {
                return Some(content.to_string());
            }
        }
    }
    None
}

// ═══════════════════════════════════════════════════════════════════════════════
// RIFF INFO PARSER
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse RIFF LIST/INFO chunk from raw bytes
fn parse_riff_info_chunk(data: &[u8]) -> AudioMetadata {
    let mut meta = AudioMetadata::default();
    meta.sources.push(MetadataSource::RiffInfo);

    // INFO sub-chunks: 4-byte ID + 4-byte size + data
    let mut pos = 0;
    while pos + 8 <= data.len() {
        let id = &data[pos..pos + 4];
        let size = u32::from_le_bytes([
            data[pos + 4], data[pos + 5], data[pos + 6], data[pos + 7],
        ]) as usize;
        pos += 8;

        if pos + size > data.len() {
            break;
        }

        let value = String::from_utf8_lossy(&data[pos..pos + size])
            .trim_end_matches('\0')
            .trim()
            .to_string();

        if !value.is_empty() {
            match id {
                b"INAM" => meta.riff_name = Some(value),
                b"IART" => meta.riff_artist = Some(value),
                b"ICMT" => meta.riff_comment = Some(value),
                b"IGNR" => meta.riff_genre = Some(value),
                b"ICRD" => meta.riff_creation_date = Some(value),
                b"ISFT" => meta.riff_software = Some(value),
                b"ICOP" => meta.riff_copyright = Some(value),
                b"IKEY" => meta.riff_keywords = Some(value),
                _ => {
                    let key = String::from_utf8_lossy(id).to_string();
                    meta.custom_tags.insert(key, value);
                }
            }
        }

        // Pad to word boundary
        pos += size;
        if pos % 2 != 0 {
            pos += 1;
        }
    }

    meta
}

// ═══════════════════════════════════════════════════════════════════════════════
// ID3v2 PARSER (for MP3 files)
// ═══════════════════════════════════════════════════════════════════════════════

/// Parse ID3v2 tags from file start
fn parse_id3v2(file: &mut File) -> Option<AudioMetadata> {
    file.seek(SeekFrom::Start(0)).ok()?;

    // ID3v2 header: "ID3" + version(2) + flags(1) + size(4)
    let mut header = [0u8; 10];
    file.read_exact(&mut header).ok()?;

    if &header[0..3] != b"ID3" {
        return None;
    }

    let major_version = header[3];
    let _minor_version = header[4];
    let is_v24 = major_version >= 4;
    // Syncsafe size: 4 bytes, 7 bits each
    let size = ((header[6] as u32 & 0x7F) << 21)
        | ((header[7] as u32 & 0x7F) << 14)
        | ((header[8] as u32 & 0x7F) << 7)
        | (header[9] as u32 & 0x7F);

    let mut tag_data = vec![0u8; size as usize];
    file.read_exact(&mut tag_data).ok()?;

    let mut meta = AudioMetadata::default();
    meta.sources.push(MetadataSource::Id3v2);

    // Parse frames: 4-byte ID + 4-byte size + 2-byte flags + data
    let mut pos = 0;
    while pos + 10 <= tag_data.len() {
        let frame_id = &tag_data[pos..pos + 4];

        // Check for padding (null bytes)
        if frame_id[0] == 0 {
            break;
        }

        // ID3v2.4 uses syncsafe frame sizes, v2.3 uses regular big-endian
        let frame_size = if is_v24 {
            ((tag_data[pos + 4] as u32 & 0x7F) << 21)
                | ((tag_data[pos + 5] as u32 & 0x7F) << 14)
                | ((tag_data[pos + 6] as u32 & 0x7F) << 7)
                | (tag_data[pos + 7] as u32 & 0x7F)
        } else {
            u32::from_be_bytes([
                tag_data[pos + 4],
                tag_data[pos + 5],
                tag_data[pos + 6],
                tag_data[pos + 7],
            ])
        } as usize;

        pos += 10; // Skip frame header

        if frame_size == 0 || pos + frame_size > tag_data.len() {
            break;
        }

        let frame_data = &tag_data[pos..pos + frame_size];

        // Text frames start with encoding byte
        if frame_id[0] == b'T' && frame_size > 1 {
            let text = decode_id3_text(frame_data);
            match frame_id {
                b"TIT2" => meta.title = Some(text),
                b"TPE1" => meta.artist = Some(text),
                b"TALB" => meta.album = Some(text),
                b"TCON" => meta.genre = Some(text),
                b"TDRC" | b"TYER" => meta.year = Some(text),
                b"TRCK" => meta.track_number = Some(text),
                b"TBPM" => meta.bpm = text.parse::<f64>().ok(),
                b"TKEY" => meta.key = Some(text),
                b"TCOP" => meta.copyright = Some(text),
                b"TSSE" => meta.encoder = Some(text),
                _ => {
                    let key = String::from_utf8_lossy(frame_id).to_string();
                    meta.custom_tags.insert(key, text);
                }
            }
        } else if frame_id == b"COMM" && frame_size > 4 {
            // Comment frame: encoding(1) + language(3) + short_desc(null-term) + text
            let encoding = frame_data[0];
            // Skip language (3 bytes), find null terminator after short description
            let desc_start = 4; // after encoding + language
            let null_sep = if encoding == 1 || encoding == 2 {
                // UTF-16: look for double-null (0x00 0x00)
                frame_data[desc_start..]
                    .windows(2)
                    .position(|w| w == [0, 0])
                    .map(|p| desc_start + p + 2)
            } else {
                // ISO-8859-1 or UTF-8: look for single null
                frame_data[desc_start..]
                    .iter()
                    .position(|&b| b == 0)
                    .map(|p| desc_start + p + 1)
            };
            let text_start = null_sep.unwrap_or(desc_start);
            if text_start < frame_data.len() {
                // Prepend encoding byte for decode_id3_text
                let mut text_with_enc = vec![encoding];
                text_with_enc.extend_from_slice(&frame_data[text_start..]);
                let text = decode_id3_text(&text_with_enc);
                if !text.is_empty() {
                    meta.comment = Some(text);
                }
            }
        }

        pos += frame_size;
    }

    Some(meta)
}

/// Decode ID3v2 text frame data (encoding byte + text)
fn decode_id3_text(data: &[u8]) -> String {
    if data.is_empty() {
        return String::new();
    }

    let encoding = data[0];
    let text_data = &data[1..];

    match encoding {
        0 => {
            // ISO-8859-1
            String::from_utf8_lossy(text_data)
                .trim_end_matches('\0')
                .to_string()
        }
        1 => {
            // UTF-16 with BOM
            if text_data.len() < 2 {
                return String::new();
            }
            decode_utf16_with_bom(text_data)
        }
        2 => {
            // UTF-16BE without BOM
            decode_utf16_be(text_data)
        }
        3 => {
            // UTF-8
            String::from_utf8_lossy(text_data)
                .trim_end_matches('\0')
                .to_string()
        }
        _ => String::from_utf8_lossy(text_data)
            .trim_end_matches('\0')
            .to_string(),
    }
}

fn decode_utf16_with_bom(data: &[u8]) -> String {
    if data.len() < 2 {
        return String::new();
    }
    let (is_le, text_data) = if data[0] == 0xFF && data[1] == 0xFE {
        (true, &data[2..])  // UTF-16 LE BOM
    } else if data[0] == 0xFE && data[1] == 0xFF {
        (false, &data[2..]) // UTF-16 BE BOM
    } else {
        (true, data) // No BOM — assume LE (most common in ID3)
    };
    let words: Vec<u16> = text_data
        .chunks_exact(2)
        .map(|c| {
            if is_le {
                u16::from_le_bytes([c[0], c[1]])
            } else {
                u16::from_be_bytes([c[0], c[1]])
            }
        })
        .take_while(|&w| w != 0)
        .collect();
    String::from_utf16_lossy(&words)
}

fn decode_utf16_be(data: &[u8]) -> String {
    let words: Vec<u16> = data
        .chunks_exact(2)
        .map(|c| u16::from_be_bytes([c[0], c[1]]))
        .take_while(|&w| w != 0)
        .collect();
    String::from_utf16_lossy(&words)
}

// ═══════════════════════════════════════════════════════════════════════════════
// UNIFIED METADATA READER
// ═══════════════════════════════════════════════════════════════════════════════

/// Read all available metadata from an audio file.
/// Automatically detects format and parses BWF, iXML, RIFF INFO, ID3v2.
pub fn read_metadata<P: AsRef<Path>>(path: P) -> FileResult<AudioMetadata> {
    let path = path.as_ref();
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    match ext.as_str() {
        "wav" | "wave" | "bwf" => read_wav_metadata(path),
        "mp3" => read_mp3_metadata(path),
        "flac" => read_flac_metadata(path),
        "ogg" | "oga" => read_vorbis_metadata(path),
        _ => Ok(AudioMetadata::default()),
    }
}

/// Read metadata from WAV/BWF files (bext, iXML, LIST/INFO chunks)
fn read_wav_metadata(path: &Path) -> FileResult<AudioMetadata> {
    let mut file = File::open(path)?;
    let mut meta = AudioMetadata::default();

    // Read RIFF header
    let mut header = [0u8; 12];
    if file.read_exact(&mut header).is_err() {
        return Ok(meta);
    }

    if &header[0..4] != b"RIFF" || &header[8..12] != b"WAVE" {
        return Ok(meta);
    }

    let file_size = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as u64 + 8;

    // Scan chunks
    let mut pos: u64 = 12;
    while pos + 8 < file_size {
        file.seek(SeekFrom::Start(pos))?;
        let mut chunk_header = [0u8; 8];
        if file.read_exact(&mut chunk_header).is_err() {
            break;
        }

        let chunk_id = [chunk_header[0], chunk_header[1], chunk_header[2], chunk_header[3]];
        let chunk_size = u32::from_le_bytes([
            chunk_header[4], chunk_header[5], chunk_header[6], chunk_header[7],
        ]) as u64;

        match &chunk_id {
            b"bext" => {
                // BWF broadcast extension
                let read_size = chunk_size.min(4096) as usize; // Cap at 4KB
                let mut data = vec![0u8; read_size];
                if file.read_exact(&mut data).is_ok() {
                    let bwf = parse_bext_chunk(&data);
                    meta.merge(&bwf);
                }
            }
            b"iXML" => {
                // iXML embedded XML
                let read_size = chunk_size.min(65536) as usize; // Cap at 64KB
                let mut data = vec![0u8; read_size];
                if file.read_exact(&mut data).is_ok() {
                    let ixml = parse_ixml_chunk(&data);
                    meta.merge(&ixml);
                }
            }
            b"LIST" => {
                // Read list type (4 bytes)
                let mut list_type = [0u8; 4];
                if file.read_exact(&mut list_type).is_ok() && &list_type == b"INFO" {
                    let info_size = (chunk_size - 4).min(8192) as usize;
                    let mut data = vec![0u8; info_size];
                    if file.read_exact(&mut data).is_ok() {
                        let info = parse_riff_info_chunk(&data);
                        meta.merge(&info);
                    }
                }
            }
            _ => {} // Skip unknown chunks (fmt, data, etc.)
        }

        // Move to next chunk (pad to word boundary)
        pos += 8 + chunk_size;
        if !pos.is_multiple_of(2) {
            pos += 1;
        }
    }

    Ok(meta)
}

/// Read ID3v2 metadata from MP3 files
fn read_mp3_metadata(path: &Path) -> FileResult<AudioMetadata> {
    let mut file = File::open(path)?;
    Ok(parse_id3v2(&mut file).unwrap_or_default())
}

/// Read metadata from FLAC files (Vorbis Comments in FLAC metadata blocks)
fn read_flac_metadata(path: &Path) -> FileResult<AudioMetadata> {
    let mut file = File::open(path)?;

    // FLAC starts with "fLaC" magic
    let mut magic = [0u8; 4];
    if file.read_exact(&mut magic).is_err() || &magic != b"fLaC" {
        return Ok(AudioMetadata::default());
    }

    let mut meta = AudioMetadata::default();

    // Parse metadata blocks
    loop {
        let mut block_header = [0u8; 4];
        if file.read_exact(&mut block_header).is_err() {
            break;
        }

        let is_last = (block_header[0] & 0x80) != 0;
        let block_type = block_header[0] & 0x7F;
        let block_size = ((block_header[1] as u32) << 16)
            | ((block_header[2] as u32) << 8)
            | (block_header[3] as u32);

        if block_type == 4 {
            // VORBIS_COMMENT
            let read_size = block_size.min(65536) as usize;
            let mut data = vec![0u8; read_size];
            if file.read_exact(&mut data).is_ok() {
                let vc = parse_vorbis_comment(&data);
                meta.merge(&vc);
            }
            break; // Found what we need
        } else {
            // Skip block
            file.seek(SeekFrom::Current(block_size as i64)).ok();
        }

        if is_last {
            break;
        }
    }

    Ok(meta)
}

/// Read Vorbis Comments from OGG files
fn read_vorbis_metadata(path: &Path) -> FileResult<AudioMetadata> {
    let mut file = File::open(path)?;

    // OGG page header: "OggS" magic
    let mut magic = [0u8; 4];
    if file.read_exact(&mut magic).is_err() || &magic != b"OggS" {
        return Ok(AudioMetadata::default());
    }

    // Skip to second page (comment header is on second page)
    // Read first page header to get segments
    file.seek(SeekFrom::Start(0))?;
    if let Some(second_page_offset) = skip_ogg_page(&mut file) {
        file.seek(SeekFrom::Start(second_page_offset))?;

        // Read second page (may contain comment header)
        let mut page_data = vec![0u8; 65536];
        let bytes_read = file.read(&mut page_data).unwrap_or(0);
        if bytes_read > 0 {
            page_data.truncate(bytes_read);

            // Look for Vorbis comment header (starts with 0x03 + "vorbis")
            if let Some(vc_pos) = find_pattern(&page_data, &[0x03, b'v', b'o', b'r', b'b', b'i', b's']) {
                let vc_data = &page_data[vc_pos + 7..]; // Skip header
                let vc = parse_vorbis_comment(vc_data);
                return Ok(vc);
            }
        }
    }

    Ok(AudioMetadata::default())
}

/// Skip one OGG page and return the byte offset of the next page
fn skip_ogg_page(file: &mut File) -> Option<u64> {
    let mut header = [0u8; 27];
    file.read_exact(&mut header).ok()?;
    if &header[0..4] != b"OggS" {
        return None;
    }
    let num_segments = header[26] as usize;
    let mut segment_table = vec![0u8; num_segments];
    file.read_exact(&mut segment_table).ok()?;
    let page_data_size: u64 = segment_table.iter().map(|&s| s as u64).sum();
    let next_offset = file.stream_position().ok()? + page_data_size;
    Some(next_offset)
}

/// Find a byte pattern in a buffer
fn find_pattern(data: &[u8], pattern: &[u8]) -> Option<usize> {
    data.windows(pattern.len()).position(|w| w == pattern)
}

/// Parse Vorbis Comments block
fn parse_vorbis_comment(data: &[u8]) -> AudioMetadata {
    let mut meta = AudioMetadata::default();
    meta.sources.push(MetadataSource::VorbisComment);

    if data.len() < 4 {
        return meta;
    }

    // Vendor string length (LE u32)
    let vendor_len = u32::from_le_bytes([data[0], data[1], data[2], data[3]]) as usize;
    let mut pos = 4 + vendor_len;

    if pos + 4 > data.len() {
        return meta;
    }

    // Comment count (capped at 10000 to prevent DoS from malformed data)
    let raw_count = u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]);
    let count = (raw_count as usize).min(10000);
    pos += 4;

    for _ in 0..count {
        if pos + 4 > data.len() {
            break;
        }
        let comment_len = u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]) as usize;
        pos += 4;

        if pos + comment_len > data.len() {
            break;
        }

        let comment = String::from_utf8_lossy(&data[pos..pos + comment_len]).to_string();
        pos += comment_len;

        if let Some((key, value)) = comment.split_once('=') {
            let key_upper = key.to_uppercase();
            match key_upper.as_str() {
                "TITLE" => meta.title = Some(value.to_string()),
                "ARTIST" | "PERFORMER" => meta.artist = Some(value.to_string()),
                "ALBUM" => meta.album = Some(value.to_string()),
                "GENRE" => meta.genre = Some(value.to_string()),
                "DATE" | "YEAR" => meta.year = Some(value.to_string()),
                "TRACKNUMBER" => meta.track_number = Some(value.to_string()),
                "COMMENT" | "DESCRIPTION" => meta.comment = Some(value.to_string()),
                "BPM" | "TEMPO" => meta.bpm = value.parse::<f64>().ok(),
                "KEY" => meta.key = Some(value.to_string()),
                "COPYRIGHT" => meta.copyright = Some(value.to_string()),
                "ENCODER" => meta.encoder = Some(value.to_string()),
                _ => {
                    meta.custom_tags.insert(key_upper, value.to_string());
                }
            }
        }
    }

    meta
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOOLEAN SEARCH ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Boolean search token
#[derive(Debug, Clone, PartialEq)]
pub enum SearchToken {
    /// A search term (case-insensitive substring match)
    Term(String),
    /// AND operator — both sides must match
    And,
    /// OR operator — either side must match
    Or,
    /// NOT operator — inverts next term
    Not,
    /// Grouped expression
    Group(Vec<SearchToken>),
    /// Field-specific search: field:value
    FieldTerm(String, String),
}

/// Parse a boolean search query string into tokens.
/// Supports: AND, OR, NOT, parentheses, field:value, quoted phrases.
/// Example: `"foley" AND (scene:12 OR take:3) NOT "wild track"`
pub fn parse_search_query(query: &str) -> Vec<SearchToken> {
    let mut tokens = Vec::new();
    let mut chars = query.chars().peekable();

    while let Some(&ch) = chars.peek() {
        match ch {
            ' ' | '\t' => {
                chars.next();
            }
            '(' => {
                chars.next();
                let mut depth = 1;
                let mut inner = String::new();
                while let Some(&c) = chars.peek() {
                    chars.next();
                    if c == '(' {
                        depth += 1;
                        inner.push(c);
                    } else if c == ')' {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                        inner.push(c);
                    } else {
                        inner.push(c);
                    }
                }
                tokens.push(SearchToken::Group(parse_search_query(&inner)));
            }
            '"' => {
                chars.next();
                let mut phrase = String::new();
                while let Some(&c) = chars.peek() {
                    chars.next();
                    if c == '"' {
                        break;
                    }
                    phrase.push(c);
                }
                if !phrase.is_empty() {
                    tokens.push(SearchToken::Term(phrase.to_lowercase()));
                }
            }
            _ => {
                let mut word = String::new();
                while let Some(&c) = chars.peek() {
                    if c == ' ' || c == '(' || c == ')' || c == '"' {
                        break;
                    }
                    word.push(c);
                    chars.next();
                }

                match word.to_uppercase().as_str() {
                    "AND" | "&&" => tokens.push(SearchToken::And),
                    "OR" | "||" => tokens.push(SearchToken::Or),
                    "NOT" | "!" => tokens.push(SearchToken::Not),
                    _ => {
                        if let Some((field, value)) = word.split_once(':') {
                            tokens.push(SearchToken::FieldTerm(
                                field.to_lowercase(),
                                value.to_lowercase(),
                            ));
                        } else {
                            tokens.push(SearchToken::Term(word.to_lowercase()));
                        }
                    }
                }
            }
        }
    }

    tokens
}

/// Evaluate a parsed search query against metadata.
/// Returns true if the metadata matches the query.
pub fn evaluate_search(tokens: &[SearchToken], meta: &AudioMetadata) -> bool {
    if tokens.is_empty() {
        return true;
    }

    let fields = meta.searchable_fields();

    evaluate_tokens(tokens, &fields)
}

fn evaluate_tokens(tokens: &[SearchToken], fields: &[(&str, &str)]) -> bool {
    if tokens.is_empty() {
        return true;
    }

    // Build implicit AND between consecutive terms
    let mut result = true;
    let mut pending_op = SearchToken::And; // Default: AND
    let mut pending_not = false;
    let mut i = 0;

    while i < tokens.len() {
        match &tokens[i] {
            SearchToken::And => {
                pending_op = SearchToken::And;
                i += 1;
            }
            SearchToken::Or => {
                pending_op = SearchToken::Or;
                i += 1;
            }
            SearchToken::Not => {
                pending_not = !pending_not;
                i += 1;
            }
            SearchToken::Term(term) => {
                let mut matches = fields.iter().any(|(_, v)| v.to_lowercase().contains(term));
                if pending_not {
                    matches = !matches;
                    pending_not = false;
                }
                result = apply_op(result, matches, &pending_op);
                pending_op = SearchToken::And;
                i += 1;
            }
            SearchToken::FieldTerm(field, value) => {
                let mut matches = fields
                    .iter()
                    .any(|(f, v)| f.to_lowercase() == *field && v.to_lowercase().contains(value));
                if pending_not {
                    matches = !matches;
                    pending_not = false;
                }
                result = apply_op(result, matches, &pending_op);
                pending_op = SearchToken::And;
                i += 1;
            }
            SearchToken::Group(inner) => {
                let mut matches = evaluate_tokens(inner, fields);
                if pending_not {
                    matches = !matches;
                    pending_not = false;
                }
                result = apply_op(result, matches, &pending_op);
                pending_op = SearchToken::And;
                i += 1;
            }
        }
    }

    result
}

fn apply_op(current: bool, new_value: bool, op: &SearchToken) -> bool {
    match op {
        SearchToken::And => current && new_value,
        SearchToken::Or => current || new_value,
        _ => current && new_value, // Default AND
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BATCH METADATA EDITING
// ═══════════════════════════════════════════════════════════════════════════════

/// Batch edit operation — defines what to change
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetadataEdit {
    /// Which field to edit
    pub field: MetadataField,
    /// New value (None = clear the field)
    pub value: Option<String>,
}

/// Editable metadata fields
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MetadataField {
    Description,
    Originator,
    OriginatorReference,
    OriginationDate,
    OriginationTime,
    Project,
    Scene,
    Take,
    Tape,
    Note,
    Title,
    Artist,
    Album,
    Genre,
    Year,
    TrackNumber,
    Comment,
    Bpm,
    Key,
    Copyright,
}

impl MetadataField {
    /// Apply an edit to metadata in-memory
    pub fn apply(&self, meta: &mut AudioMetadata, value: Option<String>) {
        match self {
            Self::Description => meta.description = value,
            Self::Originator => meta.originator = value,
            Self::OriginatorReference => meta.originator_reference = value,
            Self::OriginationDate => meta.origination_date = value,
            Self::OriginationTime => meta.origination_time = value,
            Self::Project => meta.project = value,
            Self::Scene => meta.scene = value,
            Self::Take => meta.take = value,
            Self::Tape => meta.tape = value,
            Self::Note => meta.note = value,
            Self::Title => meta.title = value,
            Self::Artist => meta.artist = value,
            Self::Album => meta.album = value,
            Self::Genre => meta.genre = value,
            Self::Year => meta.year = value,
            Self::TrackNumber => meta.track_number = value,
            Self::Comment => meta.comment = value,
            Self::Bpm => meta.bpm = value.as_ref().and_then(|v| v.parse::<f64>().ok()),
            Self::Key => meta.key = value,
            Self::Copyright => meta.copyright = value,
        }
    }
}

/// Apply batch edits to metadata in-memory.
/// Returns the modified metadata.
pub fn apply_batch_edits(meta: &mut AudioMetadata, edits: &[MetadataEdit]) {
    for edit in edits {
        edit.field.apply(meta, edit.value.clone());
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bext_parse() {
        // Minimal bext chunk: 602 bytes
        let mut data = vec![0u8; 602];
        // Description at offset 0 (256 bytes)
        let desc = b"Test recording in studio A";
        data[..desc.len()].copy_from_slice(desc);
        // Originator at offset 256 (32 bytes)
        let orig = b"FluxForge Studio";
        data[256..256 + orig.len()].copy_from_slice(orig);
        // Origination date at offset 320 (10 bytes)
        let date = b"2026-03-09";
        data[320..330].copy_from_slice(date);
        // Origination time at offset 330 (8 bytes)
        let time = b"14:30:00";
        data[330..338].copy_from_slice(time);
        // TimeReference at offset 338 (u64 LE)
        let time_ref: u64 = 48000;
        data[338..346].copy_from_slice(&time_ref.to_le_bytes());

        let meta = parse_bext_chunk(&data);
        assert_eq!(meta.description.as_deref(), Some("Test recording in studio A"));
        assert_eq!(meta.originator.as_deref(), Some("FluxForge Studio"));
        assert_eq!(meta.origination_date.as_deref(), Some("2026-03-09"));
        assert_eq!(meta.origination_time.as_deref(), Some("14:30:00"));
        assert_eq!(meta.time_reference, Some(48000));
        assert!(meta.sources.contains(&MetadataSource::Bwf));
    }

    #[test]
    fn test_ixml_parse() {
        let xml = br#"<?xml version="1.0" encoding="UTF-8"?>
<BWFXML>
  <PROJECT>MyFilm</PROJECT>
  <SCENE>12B</SCENE>
  <TAKE>4</TAKE>
  <TAPE>DAY3</TAPE>
  <CIRCLED>TRUE</CIRCLED>
  <NOTE>Room tone with AC off</NOTE>
</BWFXML>"#;

        let meta = parse_ixml_chunk(xml);
        assert_eq!(meta.project.as_deref(), Some("MyFilm"));
        assert_eq!(meta.scene.as_deref(), Some("12B"));
        assert_eq!(meta.take.as_deref(), Some("4"));
        assert_eq!(meta.tape.as_deref(), Some("DAY3"));
        assert_eq!(meta.circled, Some(true));
        assert_eq!(meta.note.as_deref(), Some("Room tone with AC off"));
        assert!(meta.sources.contains(&MetadataSource::Ixml));
    }

    #[test]
    fn test_riff_info_parse() {
        // Build INFO chunk data: INAM + IART
        let mut data = Vec::new();
        // INAM chunk
        let name = b"Explosion SFX\0";
        data.extend_from_slice(b"INAM");
        data.extend_from_slice(&(name.len() as u32).to_le_bytes());
        data.extend_from_slice(name);
        // IART chunk
        let artist = b"Sound Design Co\0";
        data.extend_from_slice(b"IART");
        data.extend_from_slice(&(artist.len() as u32).to_le_bytes());
        data.extend_from_slice(artist);

        let meta = parse_riff_info_chunk(&data);
        assert_eq!(meta.riff_name.as_deref(), Some("Explosion SFX"));
        assert_eq!(meta.riff_artist.as_deref(), Some("Sound Design Co"));
    }

    #[test]
    fn test_search_simple() {
        let mut meta = AudioMetadata::default();
        meta.title = Some("Footstep Concrete Heel".to_string());
        meta.artist = Some("Foley Artist".to_string());

        let tokens = parse_search_query("footstep");
        assert!(evaluate_search(&tokens, &meta));

        let tokens = parse_search_query("explosion");
        assert!(!evaluate_search(&tokens, &meta));
    }

    #[test]
    fn test_search_boolean_and() {
        let mut meta = AudioMetadata::default();
        meta.title = Some("Footstep Wood".to_string());
        meta.genre = Some("Foley".to_string());

        let tokens = parse_search_query("footstep AND foley");
        assert!(evaluate_search(&tokens, &meta));

        let tokens = parse_search_query("footstep AND explosion");
        assert!(!evaluate_search(&tokens, &meta));
    }

    #[test]
    fn test_search_boolean_or() {
        let mut meta = AudioMetadata::default();
        meta.title = Some("Gunshot".to_string());

        let tokens = parse_search_query("footstep OR gunshot");
        assert!(evaluate_search(&tokens, &meta));

        let tokens = parse_search_query("footstep OR explosion");
        assert!(!evaluate_search(&tokens, &meta));
    }

    #[test]
    fn test_search_boolean_not() {
        let mut meta = AudioMetadata::default();
        meta.title = Some("Wind Forest".to_string());

        let tokens = parse_search_query("wind NOT rain");
        assert!(evaluate_search(&tokens, &meta));

        let tokens = parse_search_query("wind NOT forest");
        assert!(!evaluate_search(&tokens, &meta));
    }

    #[test]
    fn test_search_field_specific() {
        let mut meta = AudioMetadata::default();
        meta.title = Some("Ambience Park".to_string());
        meta.artist = Some("Field Recorder".to_string());

        let tokens = parse_search_query("title:park");
        assert!(evaluate_search(&tokens, &meta));

        let tokens = parse_search_query("artist:park");
        assert!(!evaluate_search(&tokens, &meta));
    }

    #[test]
    fn test_search_quoted_phrase() {
        let mut meta = AudioMetadata::default();
        meta.description = Some("Room tone with air conditioning".to_string());

        let tokens = parse_search_query(r#""room tone""#);
        assert!(evaluate_search(&tokens, &meta));

        let tokens = parse_search_query(r#""tone room""#);
        assert!(!evaluate_search(&tokens, &meta));
    }

    #[test]
    fn test_search_complex() {
        let mut meta = AudioMetadata::default();
        meta.title = Some("Car Engine Start".to_string());
        meta.genre = Some("Vehicle SFX".to_string());
        meta.scene = Some("12".to_string());

        let tokens = parse_search_query("(car OR truck) AND sfx NOT horn");
        assert!(evaluate_search(&tokens, &meta));

        let tokens = parse_search_query("scene:12 AND car");
        assert!(evaluate_search(&tokens, &meta));
    }

    #[test]
    fn test_batch_edit() {
        let mut meta = AudioMetadata::default();
        meta.title = Some("Old Title".to_string());
        meta.artist = Some("Old Artist".to_string());

        let edits = vec![
            MetadataEdit {
                field: MetadataField::Title,
                value: Some("New Title".to_string()),
            },
            MetadataEdit {
                field: MetadataField::Artist,
                value: None, // Clear
            },
            MetadataEdit {
                field: MetadataField::Genre,
                value: Some("Ambience".to_string()),
            },
        ];

        apply_batch_edits(&mut meta, &edits);
        assert_eq!(meta.title.as_deref(), Some("New Title"));
        assert!(meta.artist.is_none());
        assert_eq!(meta.genre.as_deref(), Some("Ambience"));
    }

    #[test]
    fn test_metadata_merge() {
        let mut bwf = AudioMetadata::default();
        bwf.description = Some("BWF Desc".to_string());
        bwf.originator = Some("BWF Orig".to_string());
        bwf.sources.push(MetadataSource::Bwf);

        let mut ixml = AudioMetadata::default();
        ixml.project = Some("MyProject".to_string());
        ixml.description = Some("iXML Desc".to_string()); // Should NOT overwrite BWF
        ixml.sources.push(MetadataSource::Ixml);

        bwf.merge(&ixml);
        assert_eq!(bwf.description.as_deref(), Some("BWF Desc")); // Kept original
        assert_eq!(bwf.project.as_deref(), Some("MyProject")); // Added from iXML
        assert_eq!(bwf.sources.len(), 2);
    }

    #[test]
    fn test_vorbis_comment_parse() {
        // Build a Vorbis Comment block
        let mut data = Vec::new();
        // Vendor string: "FluxForge"
        let vendor = b"FluxForge";
        data.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
        data.extend_from_slice(vendor);
        // Comment count: 3
        data.extend_from_slice(&3u32.to_le_bytes());
        // Comments
        for comment in &["TITLE=Rain Forest", "ARTIST=Nature Sounds", "BPM=120"] {
            let bytes = comment.as_bytes();
            data.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
            data.extend_from_slice(bytes);
        }

        let meta = parse_vorbis_comment(&data);
        assert_eq!(meta.title.as_deref(), Some("Rain Forest"));
        assert_eq!(meta.artist.as_deref(), Some("Nature Sounds"));
        assert_eq!(meta.bpm, Some(120.0));
    }
}
