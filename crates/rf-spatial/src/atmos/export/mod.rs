//! Dolby Atmos / ADM export pipeline.
//!
//! Public façade that turns an `AdmMetadata` + bed/object PCM tracks into a
//! BW64 (or RF64 when payload > 4 GiB) `.wav` file with embedded ADM XML
//! (`axml` chunk) and Channel Allocation table (`chna` chunk), as defined by
//! ITU-R BS.2076-2 and EBU Tech 3285 / Tech 3306.
//!
//! Layout: `[bed channels …][object channels …]` — bed first, objects after,
//! both interleaved per BS.2088 BWF authoring conventions.

mod adm_xml;
mod bw64;

pub use adm_xml::{build_adm_xml, AdmXmlBuild, BedSpeaker, TrackUidEntry, BED_7_1_4_SPEAKERS};
pub use bw64::{write_bw64, ChnaEntry, ATU_SILENCE};

use crate::atmos::metadata::AdmMetadata;
use crate::atmos::AtmosBed;
use std::path::Path;

/// Errors emitted by the Atmos exporter.
#[derive(Debug, thiserror::Error)]
pub enum ExportError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("xml: {0}")]
    Xml(#[from] quick_xml::Error),
    #[error("invalid input: {0}")]
    Invalid(String),
}

/// Public exporter settings.
#[derive(Debug, Clone)]
pub struct ExportSettings {
    /// Sample rate in Hz (typical: 48000 for film/TV).
    pub sample_rate: u32,
    /// Bit depth: only 16, 24 (recommended), and 32 are accepted. 32 is float.
    pub bit_depth: u16,
    /// If true, always emit RF64 even when payload fits in BW64. Useful for
    /// downstream tools that don't dynamically promote on overflow.
    pub force_rf64: bool,
}

impl Default for ExportSettings {
    fn default() -> Self {
        Self {
            sample_rate: 48_000,
            bit_depth: 24,
            force_rf64: false,
        }
    }
}

/// High-level exporter: bed + objects → BW64 file.
///
/// `bed_pcm` and `object_pcm` are deinterleaved (one `Vec<f32>` per channel,
/// each holding the same number of samples). Bed length determines the
/// programme duration; object lengths must match bed length, missing tail
/// samples are zero-padded for safety.
pub struct AtmosExporter<'a> {
    pub metadata: &'a AdmMetadata,
    pub bed: Option<&'a AtmosBed>,
    pub bed_pcm: &'a [Vec<f32>],
    pub object_pcm: &'a [Vec<f32>],
    pub settings: ExportSettings,
}

impl<'a> AtmosExporter<'a> {
    /// Validate inputs and write the BW64 file to `path`.
    pub fn write_to<P: AsRef<Path>>(&self, path: P) -> Result<ExportReport, ExportError> {
        // 1. Channel count sanity.
        let bed_ch_meta = self
            .bed
            .map(|b| b.output_layout().total_channels())
            .unwrap_or(0);
        if bed_ch_meta > 0 && self.bed_pcm.len() != bed_ch_meta {
            return Err(ExportError::Invalid(format!(
                "bed pcm channel count {} != layout channel count {}",
                self.bed_pcm.len(),
                bed_ch_meta
            )));
        }
        if self.object_pcm.len() != self.metadata.objects.len() {
            return Err(ExportError::Invalid(format!(
                "object pcm count {} != metadata object count {}",
                self.object_pcm.len(),
                self.metadata.objects.len()
            )));
        }
        if !matches!(self.settings.bit_depth, 16 | 24 | 32) {
            return Err(ExportError::Invalid(format!(
                "unsupported bit_depth {} (16/24/32 only)",
                self.settings.bit_depth
            )));
        }
        if self.settings.sample_rate == 0 {
            return Err(ExportError::Invalid("sample_rate must be > 0".into()));
        }

        // 2. Build the ADM XML graph + chna table.
        let xml_build = build_adm_xml(self.metadata, self.bed, self.settings.sample_rate)?;

        // 3. Stitch bed + objects into one channel-major slice list.
        let mut all_channels: Vec<&Vec<f32>> = Vec::with_capacity(
            self.bed_pcm.len() + self.object_pcm.len(),
        );
        all_channels.extend(self.bed_pcm.iter());
        all_channels.extend(self.object_pcm.iter());

        // Sample length = max across all tracks (allows objects to fade in late).
        let sample_count = all_channels.iter().map(|c| c.len()).max().unwrap_or(0);

        // 4. chna entries — exactly one row per non-silent track. Track index
        //    is 1-based; UID 0 = silence reserved.
        let chna_entries: Vec<ChnaEntry> = xml_build
            .track_uids
            .iter()
            .map(|t| ChnaEntry {
                track_index: t.track_index as u16,
                uid: t.uid,
                track_format_id: t.track_format_id.clone(),
                pack_format_id: t.pack_format_id.clone(),
            })
            .collect();

        // 5. Write the file.
        let report = write_bw64(
            path.as_ref(),
            &all_channels,
            sample_count,
            self.settings.sample_rate,
            self.settings.bit_depth,
            &xml_build.xml,
            &chna_entries,
            self.settings.force_rf64,
        )?;

        Ok(ExportReport {
            channels: all_channels.len(),
            samples: sample_count,
            xml_bytes: xml_build.xml.len(),
            chna_entries: chna_entries.len(),
            file_size: report.file_size,
            is_rf64: report.is_rf64,
        })
    }
}

/// Diagnostics returned to the caller after a successful export.
#[derive(Debug, Clone, Copy)]
pub struct ExportReport {
    pub channels: usize,
    pub samples: usize,
    pub xml_bytes: usize,
    pub chna_entries: usize,
    pub file_size: u64,
    pub is_rf64: bool,
}
