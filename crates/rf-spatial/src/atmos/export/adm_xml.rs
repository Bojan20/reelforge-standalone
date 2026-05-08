//! ITU-R BS.2076-2 ADM (Audio Definition Model) XML serializer.
//!
//! Builds an `<ituADM>` graph compatible with the EBU ADM Renderer
//! reference implementation. The graph wires:
//!
//! ```text
//! audioProgramme → audioContent → audioObject ─┬─ audioPackFormat → audioChannelFormat → audioBlockFormat
//!                                              └─ audioTrackUID  → audioTrackFormat   → audioStreamFormat
//! ```
//!
//! All IDs follow ITU-R BS.2094-1 conventions:
//! - `APR_xxxx`, `ACO_xxxx`, `AO_xxxx` — programme/content/object
//! - `AP_yyyyzzzz`, `AC_yyyyzzzz` — pack/channel (yyyy = typeDefinition, zzzz = id)
//! - `AB_yyyyzzzz_xxxxxxxx` — block format
//! - `AS_yyyyzzzz`, `AT_yyyyzzzz_xx` — stream/track format
//! - `ATU_xxxxxxxx` — audioTrackUID (1-based, ATU_00000000 reserved for silence)
//!
//! `typeDefinition`:
//! - `0001` DirectSpeakers (bed)
//! - `0003` Objects

use crate::atmos::metadata::{AdmMetadata, InterpolationType, ObjectMetadata, PositionBlock};
use crate::atmos::AtmosBed;
use quick_xml::events::{BytesDecl, BytesEnd, BytesStart, BytesText, Event};
use quick_xml::Writer;
use std::io::Cursor;

/// Standard 7.1.4 bed speaker layout (Dolby Atmos home reference).
/// Order matches the canonical channel arrangement used by EBU AdmRenderer.
pub const BED_7_1_4_SPEAKERS: &[BedSpeaker] = &[
    BedSpeaker { label: "RoomCentricLeft",        sp_label: "M+030", azimuth:  30.0, elevation:  0.0 },
    BedSpeaker { label: "RoomCentricRight",       sp_label: "M-030", azimuth: -30.0, elevation:  0.0 },
    BedSpeaker { label: "RoomCentricCentre",      sp_label: "M+000", azimuth:   0.0, elevation:  0.0 },
    BedSpeaker { label: "RoomCentricLFE",         sp_label: "LFE",   azimuth:   0.0, elevation: -30.0 },
    BedSpeaker { label: "RoomCentricLeftSide",    sp_label: "M+090", azimuth:  90.0, elevation:  0.0 },
    BedSpeaker { label: "RoomCentricRightSide",   sp_label: "M-090", azimuth: -90.0, elevation:  0.0 },
    BedSpeaker { label: "RoomCentricLeftRear",    sp_label: "M+135", azimuth: 135.0, elevation:  0.0 },
    BedSpeaker { label: "RoomCentricRightRear",   sp_label: "M-135", azimuth:-135.0, elevation:  0.0 },
    BedSpeaker { label: "RoomCentricLeftTopFront",  sp_label: "U+045", azimuth:  45.0, elevation: 30.0 },
    BedSpeaker { label: "RoomCentricRightTopFront", sp_label: "U-045", azimuth: -45.0, elevation: 30.0 },
    BedSpeaker { label: "RoomCentricLeftTopRear",   sp_label: "U+135", azimuth: 135.0, elevation: 30.0 },
    BedSpeaker { label: "RoomCentricRightTopRear",  sp_label: "U-135", azimuth:-135.0, elevation: 30.0 },
];

/// One bed channel entry.
#[derive(Debug, Clone, Copy)]
pub struct BedSpeaker {
    /// Human readable label (used in audioChannelFormatName).
    pub label: &'static str,
    /// ITU-R BS.2051-2 speakerLabel (`M+030`, `LFE`, `U+045` …).
    pub sp_label: &'static str,
    /// Azimuth in degrees (positive = left).
    pub azimuth: f32,
    /// Elevation in degrees (positive = up).
    pub elevation: f32,
}

/// Per-track UID record used to drive `<chna>` and the `<audioTrackUID>` graph.
///
/// `track_index` is 1-based as required by BS.2076 (0 means silence in chna).
#[derive(Debug, Clone)]
pub struct TrackUidEntry {
    /// 1-based PCM track index in the BW64 file.
    pub track_index: u32,
    /// audioTrackUID value (`ATU_xxxxxxxx`).
    pub uid: u32,
    /// Linked audioTrackFormatID.
    pub track_format_id: String,
    /// Linked audioPackFormatID.
    pub pack_format_id: String,
}

/// Result of building the ADM XML — both the bytes and the chna table.
#[derive(Debug, Clone)]
pub struct AdmXmlBuild {
    /// UTF-8 XML payload, ready to embed as the `axml` chunk (no BOM).
    pub xml: Vec<u8>,
    /// Track table — must match channel count of the BW64 `data` chunk.
    pub track_uids: Vec<TrackUidEntry>,
}

/// Build the ADM `<ituADM>` document for a bed + object mix.
///
/// `programme_name` defaults to "FluxForge Atmos Mix" if empty.
/// `bed` may be `None` for object-only exports (rare but legal).
/// Sample rate is required to convert sample positions into the
/// `HH:MM:SS.fffff` time format mandated by BS.2076.
pub fn build_adm_xml(
    metadata: &AdmMetadata,
    bed: Option<&AtmosBed>,
    sample_rate: u32,
) -> Result<AdmXmlBuild, quick_xml::Error> {
    if sample_rate == 0 {
        return Err(quick_xml::Error::Io(std::sync::Arc::new(
            std::io::Error::new(std::io::ErrorKind::InvalidInput, "sample_rate must be > 0"),
        )));
    }

    let mut buf = Cursor::new(Vec::with_capacity(4096));
    let mut w = Writer::new_with_indent(&mut buf, b' ', 2);
    w.write_event(Event::Decl(BytesDecl::new("1.0", Some("UTF-8"), None)))?;

    // Build the track UID table up-front so we can reference and emit it.
    let mut track_uids: Vec<TrackUidEntry> = Vec::new();
    let mut next_track_index: u32 = 1;
    let mut next_track_uid: u32 = 1;

    // Bed: typeDefinition 0001, single pack containing N channels.
    let bed_channels: usize = bed
        .map(|b| b.output_layout().total_channels().min(BED_7_1_4_SPEAKERS.len()))
        .unwrap_or(0);
    let bed_pack_id = "AP_00010001".to_string();
    for ch in 0..bed_channels {
        let ch_id = format!("AC_0001{:04X}", ch + 0x1001);
        let stream_id = format!("AS_0001{:04X}", ch + 0x1001);
        let track_format_id = format!("AT_0001{:04X}_01", ch + 0x1001);
        let _ = (ch_id, stream_id);
        track_uids.push(TrackUidEntry {
            track_index: next_track_index,
            uid: next_track_uid,
            track_format_id,
            pack_format_id: bed_pack_id.clone(),
        });
        next_track_index += 1;
        next_track_uid += 1;
    }

    // Objects: each gets its own pack/channel/stream/track triple (mono per BS.2076 best-practice).
    let mut object_uids: Vec<u32> = Vec::with_capacity(metadata.objects.len());
    for (i, _) in metadata.objects.iter().enumerate() {
        let pack_id = format!("AP_0003{:04X}", i + 0x1001);
        let track_format_id = format!("AT_0003{:04X}_01", i + 0x1001);
        track_uids.push(TrackUidEntry {
            track_index: next_track_index,
            uid: next_track_uid,
            track_format_id,
            pack_format_id: pack_id,
        });
        object_uids.push(next_track_uid);
        next_track_index += 1;
        next_track_uid += 1;
    }

    // <ituADM>
    let mut root = BytesStart::new("ituADM");
    root.push_attribute(("xmlns", "urn:ebu:metadata-schema:ebuCore_2016"));
    w.write_event(Event::Start(root.clone()))?;

    write_open(&mut w, "coreMetadata")?;
    write_open(&mut w, "format")?;
    write_open(&mut w, "audioFormatExtended")?;

    // ---- audioProgramme
    let prog_name = if metadata.programme.name.is_empty() {
        "FluxForge Atmos Mix".to_string()
    } else {
        metadata.programme.name.clone()
    };
    let prog_end_tc = seconds_to_tc(metadata.programme.end.max(0.0));
    let mut programme = BytesStart::new("audioProgramme");
    programme.push_attribute(("audioProgrammeID", "APR_1001"));
    programme.push_attribute(("audioProgrammeName", prog_name.as_str()));
    programme.push_attribute(("start", "00:00:00.00000"));
    programme.push_attribute(("end", prog_end_tc.as_str()));
    if !metadata.programme.language.is_empty() {
        programme.push_attribute(("audioProgrammeLanguage", metadata.programme.language.as_str()));
    }
    w.write_event(Event::Start(programme.clone()))?;
    write_text_elem(&mut w, "audioContentIDRef", "ACO_1001")?;
    if let Some(lufs) = metadata.programme.loudness_integrated {
        write_open(&mut w, "loudnessMetadata")?;
        write_text_elem(&mut w, "integratedLoudness", &format!("{:.2}", lufs))?;
        write_close(&mut w, "loudnessMetadata")?;
    }
    write_close(&mut w, "audioProgramme")?;

    // ---- audioContent
    let content_name = metadata
        .contents
        .first()
        .map(|c| c.name.clone())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "Mix".to_string());
    let mut content = BytesStart::new("audioContent");
    content.push_attribute(("audioContentID", "ACO_1001"));
    content.push_attribute(("audioContentName", content_name.as_str()));
    w.write_event(Event::Start(content.clone()))?;
    if bed_channels > 0 {
        write_text_elem(&mut w, "audioObjectIDRef", "AO_1001")?;
    }
    for i in 0..metadata.objects.len() {
        write_text_elem(&mut w, "audioObjectIDRef", &format!("AO_{:04X}", 0x1002 + i))?;
    }
    write_close(&mut w, "audioContent")?;

    // ---- audioObject for bed (if any)
    if bed_channels > 0 {
        let mut obj = BytesStart::new("audioObject");
        obj.push_attribute(("audioObjectID", "AO_1001"));
        obj.push_attribute(("audioObjectName", "Bed"));
        obj.push_attribute(("start", "00:00:00.00000"));
        w.write_event(Event::Start(obj.clone()))?;
        write_text_elem(&mut w, "audioPackFormatIDRef", &bed_pack_id)?;
        for entry in track_uids.iter().take(bed_channels) {
            write_text_elem(&mut w, "audioTrackUIDRef", &format_atu(entry.uid))?;
        }
        write_close(&mut w, "audioObject")?;
    }

    // ---- audioObject per object
    for (i, om) in metadata.objects.iter().enumerate() {
        let pack_id = format!("AP_0003{:04X}", i + 0x1001);
        let mut obj = BytesStart::new("audioObject");
        obj.push_attribute(("audioObjectID", &*format!("AO_{:04X}", 0x1002 + i)));
        let oname = if om.name.is_empty() {
            format!("Object_{}", i + 1)
        } else {
            om.name.clone()
        };
        obj.push_attribute(("audioObjectName", oname.as_str()));
        let start_tc = samples_to_tc(om.start_sample, sample_rate);
        obj.push_attribute(("start", start_tc.as_str()));
        if om.duration_samples > 0 {
            let dur_tc = samples_to_tc(om.duration_samples, sample_rate);
            obj.push_attribute(("duration", dur_tc.as_str()));
        }
        w.write_event(Event::Start(obj.clone()))?;
        write_text_elem(&mut w, "audioPackFormatIDRef", &pack_id)?;
        write_text_elem(&mut w, "audioTrackUIDRef", &format_atu(object_uids[i]))?;
        if om.gain != 1.0 {
            let mut g = BytesStart::new("gain");
            g.push_attribute(("gainUnit", "linear"));
            w.write_event(Event::Start(g.clone()))?;
            w.write_event(Event::Text(BytesText::new(&format!("{:.6}", om.gain))))?;
            w.write_event(Event::End(BytesEnd::new("gain")))?;
        }
        write_close(&mut w, "audioObject")?;
    }

    // ---- audioPackFormat / audioChannelFormat / audioBlockFormat for bed
    if bed_channels > 0 {
        let mut pack = BytesStart::new("audioPackFormat");
        pack.push_attribute(("audioPackFormatID", bed_pack_id.as_str()));
        pack.push_attribute(("audioPackFormatName", "RoomCentric_7.1.4"));
        pack.push_attribute(("typeLabel", "0001"));
        pack.push_attribute(("typeDefinition", "DirectSpeakers"));
        w.write_event(Event::Start(pack.clone()))?;
        for ch in 0..bed_channels {
            let ch_id = format!("AC_0001{:04X}", ch + 0x1001);
            write_text_elem(&mut w, "audioChannelFormatIDRef", &ch_id)?;
        }
        write_close(&mut w, "audioPackFormat")?;

        for ch in 0..bed_channels {
            let speaker = BED_7_1_4_SPEAKERS[ch];
            let ch_id = format!("AC_0001{:04X}", ch + 0x1001);
            let mut cf = BytesStart::new("audioChannelFormat");
            cf.push_attribute(("audioChannelFormatID", ch_id.as_str()));
            cf.push_attribute(("audioChannelFormatName", speaker.label));
            cf.push_attribute(("typeLabel", "0001"));
            cf.push_attribute(("typeDefinition", "DirectSpeakers"));
            w.write_event(Event::Start(cf.clone()))?;

            let block_id = format!("AB_0001{:04X}_00000001", ch + 0x1001);
            let mut bf = BytesStart::new("audioBlockFormat");
            bf.push_attribute(("audioBlockFormatID", block_id.as_str()));
            bf.push_attribute(("rtime", "00:00:00.00000"));
            w.write_event(Event::Start(bf.clone()))?;
            write_speaker_label(&mut w, speaker.sp_label)?;
            write_position(&mut w, "azimuth", speaker.azimuth)?;
            write_position(&mut w, "elevation", speaker.elevation)?;
            write_position(&mut w, "distance", 1.0)?;
            write_close(&mut w, "audioBlockFormat")?;
            write_close(&mut w, "audioChannelFormat")?;
        }
    }

    // ---- audioPackFormat / audioChannelFormat / audioBlockFormat per object
    for (i, om) in metadata.objects.iter().enumerate() {
        let pack_id = format!("AP_0003{:04X}", i + 0x1001);
        let ch_id = format!("AC_0003{:04X}", i + 0x1001);

        let mut pack = BytesStart::new("audioPackFormat");
        pack.push_attribute(("audioPackFormatID", pack_id.as_str()));
        let oname = if om.name.is_empty() {
            format!("Object_{}", i + 1)
        } else {
            om.name.clone()
        };
        pack.push_attribute(("audioPackFormatName", oname.as_str()));
        pack.push_attribute(("typeLabel", "0003"));
        pack.push_attribute(("typeDefinition", "Objects"));
        w.write_event(Event::Start(pack.clone()))?;
        write_text_elem(&mut w, "audioChannelFormatIDRef", &ch_id)?;
        write_close(&mut w, "audioPackFormat")?;

        let mut cf = BytesStart::new("audioChannelFormat");
        cf.push_attribute(("audioChannelFormatID", ch_id.as_str()));
        cf.push_attribute(("audioChannelFormatName", oname.as_str()));
        cf.push_attribute(("typeLabel", "0003"));
        cf.push_attribute(("typeDefinition", "Objects"));
        w.write_event(Event::Start(cf.clone()))?;
        write_object_blocks(&mut w, om, i, sample_rate)?;
        write_close(&mut w, "audioChannelFormat")?;
    }

    // ---- audioStreamFormat + audioTrackFormat for bed
    if bed_channels > 0 {
        for ch in 0..bed_channels {
            let stream_id = format!("AS_0001{:04X}", ch + 0x1001);
            let track_id = format!("AT_0001{:04X}_01", ch + 0x1001);
            let ch_id = format!("AC_0001{:04X}", ch + 0x1001);
            write_stream_and_track(
                &mut w, &stream_id, &track_id, &ch_id, &bed_pack_id, "PCM", "0001",
            )?;
        }
    }

    // ---- audioStreamFormat + audioTrackFormat per object
    for i in 0..metadata.objects.len() {
        let pack_id = format!("AP_0003{:04X}", i + 0x1001);
        let stream_id = format!("AS_0003{:04X}", i + 0x1001);
        let track_id = format!("AT_0003{:04X}_01", i + 0x1001);
        let ch_id = format!("AC_0003{:04X}", i + 0x1001);
        write_stream_and_track(
            &mut w, &stream_id, &track_id, &ch_id, &pack_id, "PCM", "0001",
        )?;
    }

    // ---- audioTrackUID
    for entry in &track_uids {
        let mut tu = BytesStart::new("audioTrackUID");
        let uid_str = format_atu(entry.uid);
        tu.push_attribute(("UID", uid_str.as_str()));
        tu.push_attribute(("sampleRate", &*sample_rate.to_string()));
        tu.push_attribute(("bitDepth", "24"));
        w.write_event(Event::Start(tu.clone()))?;
        write_text_elem(&mut w, "audioTrackFormatIDRef", &entry.track_format_id)?;
        write_text_elem(&mut w, "audioPackFormatIDRef", &entry.pack_format_id)?;
        write_close(&mut w, "audioTrackUID")?;
    }

    write_close(&mut w, "audioFormatExtended")?;
    write_close(&mut w, "format")?;
    write_close(&mut w, "coreMetadata")?;
    w.write_event(Event::End(BytesEnd::new("ituADM")))?;

    Ok(AdmXmlBuild {
        xml: buf.into_inner(),
        track_uids,
    })
}

fn write_open<W: std::io::Write>(w: &mut Writer<W>, name: &str) -> Result<(), quick_xml::Error> {
    w.write_event(Event::Start(BytesStart::new(name)))?;
    Ok(())
}

fn write_close<W: std::io::Write>(w: &mut Writer<W>, name: &str) -> Result<(), quick_xml::Error> {
    w.write_event(Event::End(BytesEnd::new(name)))?;
    Ok(())
}

fn write_text_elem<W: std::io::Write>(
    w: &mut Writer<W>,
    name: &str,
    text: &str,
) -> Result<(), quick_xml::Error> {
    w.write_event(Event::Start(BytesStart::new(name)))?;
    w.write_event(Event::Text(BytesText::new(text)))?;
    w.write_event(Event::End(BytesEnd::new(name)))?;
    Ok(())
}

fn write_position<W: std::io::Write>(
    w: &mut Writer<W>,
    coord: &str,
    value: f32,
) -> Result<(), quick_xml::Error> {
    let mut start = BytesStart::new("position");
    start.push_attribute(("coordinate", coord));
    w.write_event(Event::Start(start.clone()))?;
    w.write_event(Event::Text(BytesText::new(&format!("{:.5}", value))))?;
    w.write_event(Event::End(BytesEnd::new("position")))?;
    Ok(())
}

fn write_speaker_label<W: std::io::Write>(
    w: &mut Writer<W>,
    label: &str,
) -> Result<(), quick_xml::Error> {
    write_text_elem(w, "speakerLabel", &format!("urn:itu:bs:2051:0:speaker:{}", label))
}

fn write_object_blocks<W: std::io::Write>(
    w: &mut Writer<W>,
    om: &ObjectMetadata,
    object_idx: usize,
    sample_rate: u32,
) -> Result<(), quick_xml::Error> {
    let blocks: Vec<PositionBlock> = if om.position_blocks.is_empty() {
        vec![PositionBlock {
            start_sample: 0,
            duration_samples: om.duration_samples,
            position: om.position,
            interpolation: InterpolationType::Jump,
        }]
    } else {
        om.position_blocks.clone()
    };

    for (b_idx, block) in blocks.iter().enumerate() {
        let block_id = format!("AB_0003{:04X}_{:08X}", object_idx + 0x1001, b_idx + 1);
        let mut bf = BytesStart::new("audioBlockFormat");
        bf.push_attribute(("audioBlockFormatID", block_id.as_str()));
        let rtime = samples_to_tc(block.start_sample, sample_rate);
        bf.push_attribute(("rtime", rtime.as_str()));
        if block.duration_samples > 0 {
            let dur = samples_to_tc(block.duration_samples, sample_rate);
            bf.push_attribute(("duration", dur.as_str()));
        }
        w.write_event(Event::Start(bf.clone()))?;

        // Convert FluxForge cartesian (x, y, z) to BS.2076 azimuth/elevation/distance.
        // FluxForge: y = forward, x = right, z = up. BS.2076: azimuth 0 = front,
        // positive azimuth rotates left (CCW from above), elevation positive = up.
        let p = block.position;
        let dist = (p.x * p.x + p.y * p.y + p.z * p.z).sqrt().max(1e-6);
        let elevation = (p.z / dist).asin().to_degrees();
        let azimuth = (-p.x).atan2(p.y).to_degrees();
        write_position(w, "azimuth", azimuth)?;
        write_position(w, "elevation", elevation)?;
        write_position(w, "distance", dist.min(1.0))?;

        // Jump flag (no smoothing into this block).
        if matches!(block.interpolation, InterpolationType::Jump) {
            write_text_elem(w, "jumpPosition", "1")?;
        }

        write_close(w, "audioBlockFormat")?;
    }
    Ok(())
}

fn write_stream_and_track<W: std::io::Write>(
    w: &mut Writer<W>,
    stream_id: &str,
    track_id: &str,
    channel_id: &str,
    pack_id: &str,
    fmt_label_text: &str,
    fmt_label_code: &str,
) -> Result<(), quick_xml::Error> {
    let mut sf = BytesStart::new("audioStreamFormat");
    sf.push_attribute(("audioStreamFormatID", stream_id));
    sf.push_attribute(("audioStreamFormatName", &*format!("PCM_{}", stream_id)));
    sf.push_attribute(("formatLabel", fmt_label_code));
    sf.push_attribute(("formatDefinition", fmt_label_text));
    w.write_event(Event::Start(sf.clone()))?;
    write_text_elem(w, "audioChannelFormatIDRef", channel_id)?;
    write_text_elem(w, "audioPackFormatIDRef", pack_id)?;
    write_text_elem(w, "audioTrackFormatIDRef", track_id)?;
    write_close(w, "audioStreamFormat")?;

    let mut tf = BytesStart::new("audioTrackFormat");
    tf.push_attribute(("audioTrackFormatID", track_id));
    tf.push_attribute(("audioTrackFormatName", &*format!("PCM_{}", track_id)));
    tf.push_attribute(("formatLabel", fmt_label_code));
    tf.push_attribute(("formatDefinition", fmt_label_text));
    w.write_event(Event::Start(tf.clone()))?;
    write_text_elem(w, "audioStreamFormatIDRef", stream_id)?;
    write_close(w, "audioTrackFormat")?;
    Ok(())
}

fn format_atu(uid: u32) -> String {
    format!("ATU_{:08X}", uid)
}

/// Convert a sample offset to BS.2076 `HH:MM:SS.fffff` time-code.
/// Five fractional digits as required by the spec (5 decimal places of seconds).
fn samples_to_tc(samples: u64, sample_rate: u32) -> String {
    seconds_to_tc(samples as f64 / sample_rate as f64)
}

fn seconds_to_tc(seconds: f64) -> String {
    let total = seconds.max(0.0);
    let hours = (total / 3600.0).floor() as u64;
    let mins = ((total % 3600.0) / 60.0).floor() as u64;
    let secs_full = total % 60.0;
    let secs_int = secs_full.floor() as u64;
    let frac = ((secs_full - secs_int as f64) * 100_000.0).round() as u64;
    // Carry on rounding overflow (e.g. 0.999996 → 1.00000 must bump seconds).
    let (secs_int, frac) = if frac >= 100_000 {
        (secs_int + 1, frac - 100_000)
    } else {
        (secs_int, frac)
    };
    format!("{:02}:{:02}:{:02}.{:05}", hours, mins, secs_int, frac)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::atmos::AtmosBed;
    use crate::position::Position3D;

    #[test]
    fn seconds_to_tc_basic() {
        assert_eq!(seconds_to_tc(0.0), "00:00:00.00000");
        assert_eq!(seconds_to_tc(1.5), "00:00:01.50000");
        assert_eq!(seconds_to_tc(3661.12345), "01:01:01.12345");
    }

    #[test]
    fn seconds_to_tc_carries_on_round() {
        // 0.999996 → 1.00000 (carry, no .100000 bug)
        let tc = seconds_to_tc(0.999996);
        assert_eq!(tc, "00:00:01.00000");
    }

    #[test]
    fn samples_to_tc_48k() {
        assert_eq!(samples_to_tc(48_000, 48_000), "00:00:01.00000");
        assert_eq!(samples_to_tc(72_000, 48_000), "00:00:01.50000");
    }

    #[test]
    fn build_xml_bed_only() {
        let bed = AtmosBed::new(crate::atmos::bed::BedConfig::default());
        let meta = AdmMetadata::new();
        let out = build_adm_xml(&meta, Some(&bed), 48_000).unwrap();
        let text = String::from_utf8(out.xml.clone()).unwrap();
        assert!(text.contains("<ituADM"));
        assert!(text.contains("audioPackFormatID=\"AP_00010001\""));
        assert!(text.contains("typeDefinition=\"DirectSpeakers\""));
        // 12 bed channels → 12 track UIDs
        assert_eq!(out.track_uids.len(), 12);
        assert_eq!(out.track_uids[0].track_index, 1);
        assert_eq!(out.track_uids[11].track_index, 12);
    }

    #[test]
    fn build_xml_objects_only() {
        let mut meta = AdmMetadata::new();
        meta.add_object(ObjectMetadata {
            id: 1,
            name: "Voice".into(),
            position: Position3D::new(0.5, 1.0, 0.2),
            duration_samples: 48_000,
            ..Default::default()
        });
        let out = build_adm_xml(&meta, None, 48_000).unwrap();
        let text = String::from_utf8(out.xml).unwrap();
        assert!(text.contains("typeDefinition=\"Objects\""));
        assert!(text.contains("audioObjectName=\"Voice\""));
        assert!(text.contains("<position coordinate=\"azimuth\""));
        assert_eq!(out.track_uids.len(), 1);
    }

    #[test]
    fn build_xml_full_mix() {
        let bed = AtmosBed::new(crate::atmos::bed::BedConfig::default());
        let mut meta = AdmMetadata::new();
        meta.programme.name = "Helix Demo".into();
        meta.programme.end = 5.0;
        meta.add_object(ObjectMetadata {
            id: 1,
            name: "Helicopter".into(),
            duration_samples: 240_000,
            ..Default::default()
        });
        meta.add_object(ObjectMetadata {
            id: 2,
            name: "Voice".into(),
            duration_samples: 240_000,
            ..Default::default()
        });
        let out = build_adm_xml(&meta, Some(&bed), 48_000).unwrap();
        // 12 bed + 2 objects = 14 track UIDs, 1-based indices 1..=14
        assert_eq!(out.track_uids.len(), 14);
        assert_eq!(out.track_uids.last().unwrap().track_index, 14);

        let text = String::from_utf8(out.xml).unwrap();
        assert!(text.contains("audioProgrammeName=\"Helix Demo\""));
        assert!(text.contains("audioObjectName=\"Helicopter\""));
        assert!(text.contains("audioObjectName=\"Voice\""));
        assert!(text.contains("typeDefinition=\"DirectSpeakers\""));
        assert!(text.contains("typeDefinition=\"Objects\""));
    }

    #[test]
    fn build_xml_rejects_zero_sample_rate() {
        let meta = AdmMetadata::new();
        assert!(build_adm_xml(&meta, None, 0).is_err());
    }

    #[test]
    fn position_block_emits_jump_flag() {
        let mut meta = AdmMetadata::new();
        let mut obj = ObjectMetadata {
            id: 1,
            name: "Pan".into(),
            duration_samples: 96_000,
            ..Default::default()
        };
        obj.position_blocks.push(PositionBlock {
            start_sample: 0,
            duration_samples: 48_000,
            position: Position3D::new(-1.0, 0.0, 0.0),
            interpolation: InterpolationType::Jump,
        });
        obj.position_blocks.push(PositionBlock {
            start_sample: 48_000,
            duration_samples: 48_000,
            position: Position3D::new(1.0, 0.0, 0.0),
            interpolation: InterpolationType::Linear,
        });
        meta.add_object(obj);
        let out = build_adm_xml(&meta, None, 48_000).unwrap();
        let text = String::from_utf8(out.xml).unwrap();
        // First block has Jump → jumpPosition=1; second block has Linear → no flag
        let occ = text.matches("<jumpPosition>1</jumpPosition>").count();
        assert_eq!(occ, 1);
    }
}
