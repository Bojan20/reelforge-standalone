//! Marker Ingest Pipeline — Parse markers from sidecar JSON, BWF cue chunks,
//! and Reaper projects into LoopAsset structures.

use crate::loop_asset::*;

/// Raw marker from any source (before mapping to LoopAsset).
#[derive(Debug, Clone)]
pub struct RawMarker {
    pub marker_type: RawMarkerType,
    pub name: String,
    pub at_samples: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RawMarkerType {
    Entry,
    Exit,
    LoopIn,
    LoopOut,
    Cue,
    Event,
    Sync,
}

/// Ingest configuration.
#[derive(Debug, Clone)]
pub struct IngestConfig {
    /// Default seam fade (ms)
    pub default_seam_fade_ms: f32,
    /// Default crossfade (ms)
    pub default_crossfade_ms: f32,
    /// Default wrap policy
    pub default_wrap_policy: WrapPolicy,
    /// Default loop mode
    pub default_loop_mode: LoopMode,
}

impl Default for IngestConfig {
    fn default() -> Self {
        Self {
            default_seam_fade_ms: 5.0,
            default_crossfade_ms: 50.0,
            default_wrap_policy: WrapPolicy::PlayOnceThenLoop,
            default_loop_mode: LoopMode::Hard,
        }
    }
}

/// Error during marker parsing.
#[derive(Debug, Clone)]
pub enum MarkerError {
    InvalidJson(String),
    MissingField(String),
    InvalidSampleRate,
    PathTraversal(String),
    TooManyMarkers(usize),
    FileTooLarge,
}

impl std::fmt::Display for MarkerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidJson(s) => write!(f, "Invalid JSON: {s}"),
            Self::MissingField(s) => write!(f, "Missing field: {s}"),
            Self::InvalidSampleRate => write!(f, "Invalid sample rate"),
            Self::PathTraversal(s) => write!(f, "Path traversal detected: {s}"),
            Self::TooManyMarkers(n) => write!(f, "Too many markers: {n}"),
            Self::FileTooLarge => write!(f, "File exceeds 1MB limit"),
        }
    }
}

/// Sidecar marker file format (.ffmarkers.json).
#[derive(Debug, Clone, serde::Deserialize)]
pub struct SidecarFile {
    pub file: String,
    #[serde(rename = "sampleRate")]
    pub sample_rate: u32,
    pub markers: Vec<SidecarMarker>,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct SidecarMarker {
    #[serde(rename = "type")]
    pub marker_type: String,
    pub name: String,
    #[serde(rename = "atSamples")]
    pub at_samples: u64,
}

/// Parse a `.ffmarkers.json` sidecar file.
pub fn parse_sidecar_json(json_str: &str) -> Result<Vec<RawMarker>, MarkerError> {
    // Security: limit file size
    if json_str.len() > 1_048_576 {
        return Err(MarkerError::FileTooLarge);
    }

    let sidecar: SidecarFile =
        serde_json::from_str(json_str).map_err(|e| MarkerError::InvalidJson(e.to_string()))?;

    // Security: validate filename (no path separators)
    if sidecar.file.contains('/') || sidecar.file.contains('\\') || sidecar.file.contains("..") {
        return Err(MarkerError::PathTraversal(sidecar.file));
    }

    if sidecar.sample_rate == 0 {
        return Err(MarkerError::InvalidSampleRate);
    }

    if sidecar.markers.len() > MAX_CUES_PER_ASSET + MAX_REGIONS_PER_ASSET * 2 {
        return Err(MarkerError::TooManyMarkers(sidecar.markers.len()));
    }

    let markers = sidecar
        .markers
        .iter()
        .map(|m| {
            let marker_type = match_marker_type(&m.marker_type);
            RawMarker {
                marker_type,
                name: m.name.clone(),
                at_samples: m.at_samples,
            }
        })
        .collect();

    Ok(markers)
}

/// Map raw marker type string to enum.
fn match_marker_type(s: &str) -> RawMarkerType {
    match s.to_uppercase().as_str() {
        "ENTRY" | "START" => RawMarkerType::Entry,
        "EXIT" | "END" => RawMarkerType::Exit,
        "LOOP_IN" | "LOOPIN" | "LOOP_START" | "LOOP_A_IN" => RawMarkerType::LoopIn,
        "LOOP_OUT" | "LOOPOUT" | "LOOP_END" | "LOOP_A_OUT" => RawMarkerType::LoopOut,
        "EVENT" => RawMarkerType::Event,
        "SYNC" => RawMarkerType::Sync,
        _ => RawMarkerType::Cue,
    }
}

/// Map marker name to type using naming convention.
fn infer_marker_type_from_name(name: &str) -> RawMarkerType {
    let lower = name.to_lowercase();
    if lower == "entry" || lower == "start" {
        RawMarkerType::Entry
    } else if lower == "exit" || lower == "end" {
        RawMarkerType::Exit
    } else if lower.contains("loop") && (lower.contains("in") || lower.contains("start")) {
        RawMarkerType::LoopIn
    } else if lower.contains("loop") && (lower.contains("out") || lower.contains("end")) {
        RawMarkerType::LoopOut
    } else {
        RawMarkerType::Cue
    }
}

/// Convert raw markers to a LoopAsset.
pub fn markers_to_loop_asset(
    markers: &[RawMarker],
    asset_id: &str,
    sound_id: &str,
    sample_rate: u32,
    channels: u16,
    length_samples: u64,
    config: &IngestConfig,
) -> Result<LoopAsset, MarkerError> {
    let mut cues = Vec::new();
    let mut loop_in_samples: Option<u64> = None;
    let mut loop_out_samples: Option<u64> = None;

    // Collect additional loop region pairs (B, C, etc.)
    let mut extra_loop_ins: Vec<(String, u64)> = Vec::new();
    let mut extra_loop_outs: Vec<(String, u64)> = Vec::new();

    for m in markers {
        match m.marker_type {
            RawMarkerType::Entry => {
                cues.push(Cue {
                    name: m.name.clone(),
                    at_samples: m.at_samples,
                    cue_type: CueType::Entry,
                });
            }
            RawMarkerType::Exit => {
                cues.push(Cue {
                    name: m.name.clone(),
                    at_samples: m.at_samples,
                    cue_type: CueType::Exit,
                });
            }
            RawMarkerType::LoopIn => {
                let lower = m.name.to_lowercase();
                if lower.contains("_b_") || lower.contains("loopb") {
                    extra_loop_ins.push(("LoopB".into(), m.at_samples));
                } else if lower.contains("_c_") || lower.contains("loopc") {
                    extra_loop_ins.push(("LoopC".into(), m.at_samples));
                } else {
                    loop_in_samples = Some(m.at_samples);
                }
            }
            RawMarkerType::LoopOut => {
                let lower = m.name.to_lowercase();
                if lower.contains("_b_") || lower.contains("loopb") {
                    extra_loop_outs.push(("LoopB".into(), m.at_samples));
                } else if lower.contains("_c_") || lower.contains("loopc") {
                    extra_loop_outs.push(("LoopC".into(), m.at_samples));
                } else {
                    loop_out_samples = Some(m.at_samples);
                }
            }
            RawMarkerType::Cue => {
                cues.push(Cue {
                    name: m.name.clone(),
                    at_samples: m.at_samples,
                    cue_type: CueType::Custom,
                });
            }
            RawMarkerType::Event => {
                cues.push(Cue {
                    name: m.name.clone(),
                    at_samples: m.at_samples,
                    cue_type: CueType::Event,
                });
            }
            RawMarkerType::Sync => {
                cues.push(Cue {
                    name: m.name.clone(),
                    at_samples: m.at_samples,
                    cue_type: CueType::Sync,
                });
            }
        }
    }

    // Fallback: if no Entry/Exit, create defaults
    if !cues.iter().any(|c| c.cue_type == CueType::Entry) {
        cues.push(Cue {
            name: "Entry".into(),
            at_samples: 0,
            cue_type: CueType::Entry,
        });
    }
    if !cues.iter().any(|c| c.cue_type == CueType::Exit) {
        cues.push(Cue {
            name: "Exit".into(),
            at_samples: length_samples.saturating_sub(1),
            cue_type: CueType::Exit,
        });
    }

    // Build regions
    let entry = cues
        .iter()
        .find(|c| c.cue_type == CueType::Entry)
        .map(|c| c.at_samples)
        .unwrap_or(0);
    let exit = cues
        .iter()
        .find(|c| c.cue_type == CueType::Exit)
        .map(|c| c.at_samples)
        .unwrap_or(length_samples.saturating_sub(1));

    let loop_in = loop_in_samples.unwrap_or(entry);
    let loop_out = loop_out_samples.unwrap_or(exit);

    let mut regions = vec![AdvancedLoopRegion {
        name: "LoopA".into(),
        in_samples: loop_in,
        out_samples: loop_out,
        mode: config.default_loop_mode,
        wrap_policy: config.default_wrap_policy,
        seam_fade_ms: config.default_seam_fade_ms,
        crossfade_ms: config.default_crossfade_ms,
        crossfade_curve: LoopCrossfadeCurve::EqualPower,
        quantize: None,
        max_loops: None,
        iteration_gain_factor: None,
        random_start_range: 0,
    }];

    // Extra regions (B, C)
    for (name, in_s) in &extra_loop_ins {
        let out_s = extra_loop_outs
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, s)| *s)
            .unwrap_or(exit);
        regions.push(AdvancedLoopRegion {
            name: name.clone(),
            in_samples: *in_s,
            out_samples: out_s,
            mode: config.default_loop_mode,
            wrap_policy: config.default_wrap_policy,
            seam_fade_ms: config.default_seam_fade_ms,
            crossfade_ms: config.default_crossfade_ms,
            crossfade_curve: LoopCrossfadeCurve::EqualPower,
            quantize: None,
            max_loops: None,
            iteration_gain_factor: None,
            random_start_range: 0,
        });
    }

    Ok(LoopAsset {
        id: asset_id.to_string(),
        sound_ref: SoundRef {
            source_type: SourceType::File,
            sound_id: sound_id.to_string(),
            sprite_id: None,
        },
        timeline: TimelineInfo {
            sample_rate,
            channels,
            length_samples,
            bpm: None,
            beats_per_bar: None,
        },
        cues,
        regions,
        pre_entry: ZonePolicy::default(),
        post_exit: ZonePolicy::default(),
    })
}

/// Parse BWF cue chunk markers from WAV data (simplified parser).
/// Reads RIFF `cue ` chunk positions and `LIST/adtl` labels.
pub fn parse_bwf_cue_chunk(wav_data: &[u8]) -> Result<Vec<RawMarker>, MarkerError> {
    // Validate RIFF header
    if wav_data.len() < 44 {
        return Err(MarkerError::InvalidJson("Not a valid WAV file".into()));
    }
    if &wav_data[0..4] != b"RIFF" || &wav_data[8..12] != b"WAVE" {
        return Err(MarkerError::InvalidJson("Not a RIFF/WAVE file".into()));
    }

    let mut markers = Vec::new();
    let mut pos = 12;

    // Maps: cue_id -> sample_position
    let mut cue_positions: Vec<(u32, u64)> = Vec::new();
    // Maps: cue_id -> label name
    let mut cue_labels: Vec<(u32, String)> = Vec::new();

    while pos + 8 <= wav_data.len() {
        let chunk_id = &wav_data[pos..pos + 4];
        let chunk_size = u32::from_le_bytes([
            wav_data[pos + 4],
            wav_data[pos + 5],
            wav_data[pos + 6],
            wav_data[pos + 7],
        ]) as usize;
        let data_start = pos + 8;
        let data_end = (data_start + chunk_size).min(wav_data.len());

        if chunk_id == b"cue " && chunk_size >= 4 {
            // Parse cue chunk
            let num_cues = u32::from_le_bytes([
                wav_data[data_start],
                wav_data[data_start + 1],
                wav_data[data_start + 2],
                wav_data[data_start + 3],
            ]);
            let mut cue_pos = data_start + 4;
            for _ in 0..num_cues {
                if cue_pos + 24 > data_end {
                    break;
                }
                let cue_id = u32::from_le_bytes([
                    wav_data[cue_pos],
                    wav_data[cue_pos + 1],
                    wav_data[cue_pos + 2],
                    wav_data[cue_pos + 3],
                ]);
                let sample_offset = u32::from_le_bytes([
                    wav_data[cue_pos + 20],
                    wav_data[cue_pos + 21],
                    wav_data[cue_pos + 22],
                    wav_data[cue_pos + 23],
                ]);
                cue_positions.push((cue_id, sample_offset as u64));
                cue_pos += 24;
            }
        } else if chunk_id == b"LIST" && chunk_size >= 4 {
            let list_type = &wav_data[data_start..data_start + 4];
            if list_type == b"adtl" {
                // Parse associated data list (labels)
                let mut adtl_pos = data_start + 4;
                while adtl_pos + 8 <= data_end {
                    let sub_id = &wav_data[adtl_pos..adtl_pos + 4];
                    let sub_size = u32::from_le_bytes([
                        wav_data[adtl_pos + 4],
                        wav_data[adtl_pos + 5],
                        wav_data[adtl_pos + 6],
                        wav_data[adtl_pos + 7],
                    ]) as usize;
                    let sub_data_start = adtl_pos + 8;

                    if sub_id == b"labl" && sub_size >= 4 {
                        let cue_id = u32::from_le_bytes([
                            wav_data[sub_data_start],
                            wav_data[sub_data_start + 1],
                            wav_data[sub_data_start + 2],
                            wav_data[sub_data_start + 3],
                        ]);
                        let label_end = (sub_data_start + sub_size).min(data_end);
                        let label_bytes = &wav_data[sub_data_start + 4..label_end];
                        // Trim null bytes
                        let label = String::from_utf8_lossy(label_bytes)
                            .trim_end_matches('\0')
                            .to_string();
                        cue_labels.push((cue_id, label));
                    }

                    adtl_pos += 8 + sub_size;
                    // Pad to word boundary
                    if adtl_pos % 2 != 0 {
                        adtl_pos += 1;
                    }
                }
            }
        }

        pos = data_end;
        // Pad to word boundary
        if pos % 2 != 0 {
            pos += 1;
        }
    }

    // Merge positions + labels
    for (cue_id, sample_pos) in &cue_positions {
        let name = cue_labels
            .iter()
            .find(|(id, _)| id == cue_id)
            .map(|(_, label)| label.clone())
            .unwrap_or_else(|| format!("Cue{cue_id}"));
        let marker_type = infer_marker_type_from_name(&name);
        markers.push(RawMarker {
            marker_type,
            name,
            at_samples: *sample_pos,
        });
    }

    Ok(markers)
}
