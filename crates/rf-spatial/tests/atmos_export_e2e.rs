//! Atmos export end-to-end integration test.
//!
//! Exercises the full `AtmosExporter` path:
//! 1. Build a 7.1.4 bed + N objects with automation
//! 2. Write a BW64 file
//! 3. Re-parse the file with a minimal RIFF walker
//! 4. Verify: chna rows match metadata, axml is well-formed XML, data chunk
//!    byte length is consistent with declared sample/channel/bit_depth math
//! 5. Validate that promoting `force_rf64` produces a parsable RF64
//! 6. Validate object-only export (no bed)

use rf_spatial::atmos::{
    AdmMetadata, AtmosBed, AtmosExporter, BedConfig, ExportSettings, InterpolationType,
    ObjectMetadata, PositionBlock,
};
use rf_spatial::Position3D;
use std::path::PathBuf;

fn unique_tmp(prefix: &str) -> PathBuf {
    let n = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let p = std::env::temp_dir().join(format!("rf-spatial-e2e-{}-{}", prefix, n));
    std::fs::create_dir_all(&p).unwrap();
    p
}

/// Walk RIFF/RF64, return chunk list `[(id, payload_bytes)]`.
fn read_chunks(path: &std::path::Path) -> (bool, Vec<(String, Vec<u8>)>) {
    let data = std::fs::read(path).unwrap();
    let is_rf64 = &data[0..4] == b"RF64";
    assert!(is_rf64 || &data[0..4] == b"RIFF");
    assert_eq!(&data[8..12], b"WAVE");
    let mut p: usize = 12;
    let mut out = Vec::new();
    while p + 8 < data.len() {
        let id = String::from_utf8_lossy(&data[p..p + 4]).to_string();
        let size32 = u32::from_le_bytes([data[p + 4], data[p + 5], data[p + 6], data[p + 7]]);
        let actual_size: usize = if id == "data" && size32 == u32::MAX {
            // RF64: pull real data size from ds64.
            let ds64 = out
                .iter()
                .find(|(i, _): &&(String, Vec<u8>)| i == "ds64")
                .map(|(_, v)| v.clone())
                .expect("ds64 missing");
            u64::from_le_bytes([
                ds64[8], ds64[9], ds64[10], ds64[11], ds64[12], ds64[13], ds64[14], ds64[15],
            ]) as usize
        } else {
            size32 as usize
        };
        let payload = data[p + 8..p + 8 + actual_size].to_vec();
        out.push((id, payload));
        let mut adv = 8 + actual_size;
        if adv % 2 == 1 {
            adv += 1;
        }
        p += adv;
    }
    (is_rf64, out)
}

fn build_meta_with_two_objects(start_samples: u64) -> AdmMetadata {
    let mut meta = AdmMetadata::new();
    meta.programme.name = "FluxForge E2E".into();
    meta.programme.end = 2.0;

    let mut helo = ObjectMetadata {
        id: 1,
        name: "Helicopter".into(),
        position: Position3D::new(0.5, 1.0, 0.3),
        gain: 0.9,
        start_sample: start_samples,
        duration_samples: 96_000,
        ..Default::default()
    };
    helo.position_blocks.push(PositionBlock {
        start_sample: 0,
        duration_samples: 48_000,
        position: Position3D::new(-1.0, 0.5, 0.5),
        interpolation: InterpolationType::Jump,
    });
    helo.position_blocks.push(PositionBlock {
        start_sample: 48_000,
        duration_samples: 48_000,
        position: Position3D::new(1.0, 0.5, 0.5),
        interpolation: InterpolationType::Linear,
    });

    let voice = ObjectMetadata {
        id: 2,
        name: "Voice".into(),
        position: Position3D::new(0.0, 1.0, 0.0),
        gain: 1.0,
        start_sample: 0,
        duration_samples: 96_000,
        ..Default::default()
    };

    meta.add_object(helo);
    meta.add_object(voice);
    meta
}

#[test]
fn full_bed_plus_objects_export_is_round_trippable() {
    let dir = unique_tmp("full");
    let path = dir.join("mix.wav");

    let bed = AtmosBed::new(BedConfig::default());
    let bed_pcm: Vec<Vec<f32>> = (0..bed.output_layout().total_channels())
        .map(|c| {
            (0..96_000)
                .map(|i| ((c + 1) as f32 * 0.001 * i as f32).sin() * 0.1)
                .collect()
        })
        .collect();
    let object_pcm: Vec<Vec<f32>> = vec![vec![0.2_f32; 96_000], vec![-0.2_f32; 96_000]];

    let meta = build_meta_with_two_objects(0);

    let exporter = AtmosExporter {
        metadata: &meta,
        bed: Some(&bed),
        bed_pcm: &bed_pcm,
        object_pcm: &object_pcm,
        settings: ExportSettings::default(),
    };

    let report = exporter.write_to(&path).unwrap();
    assert_eq!(report.channels, 12 + 2);
    assert_eq!(report.samples, 96_000);
    assert!(report.xml_bytes > 1000, "ADM XML too small: {}", report.xml_bytes);
    assert_eq!(report.chna_entries, 14);
    assert!(!report.is_rf64);

    let (is_rf64, chunks) = read_chunks(&path);
    assert!(!is_rf64);

    // Required chunks present and well-formed.
    let fmt = chunks.iter().find(|(id, _)| id == "fmt ").expect("fmt missing");
    let n_ch = u16::from_le_bytes([fmt.1[2], fmt.1[3]]);
    let sr = u32::from_le_bytes([fmt.1[4], fmt.1[5], fmt.1[6], fmt.1[7]]);
    let bit_depth = u16::from_le_bytes([fmt.1[14], fmt.1[15]]);
    assert_eq!(n_ch, 14);
    assert_eq!(sr, 48_000);
    assert_eq!(bit_depth, 24);

    let data = chunks.iter().find(|(id, _)| id == "data").expect("data missing");
    let expected_data = 96_000usize * 14 * 3;
    assert_eq!(data.1.len(), expected_data);

    let axml = chunks.iter().find(|(id, _)| id == "axml").expect("axml missing");
    let xml = std::str::from_utf8(&axml.1).expect("axml is not utf-8");
    assert!(xml.contains("<ituADM"));
    assert!(xml.contains("audioObjectName=\"Helicopter\""));
    assert!(xml.contains("audioObjectName=\"Voice\""));
    assert!(xml.contains("typeDefinition=\"DirectSpeakers\""));
    assert!(xml.contains("typeDefinition=\"Objects\""));
    assert!(xml.contains("<jumpPosition>1</jumpPosition>"));

    let chna = chunks.iter().find(|(id, _)| id == "chna").expect("chna missing");
    let n_tracks = u16::from_le_bytes([chna.1[0], chna.1[1]]);
    let n_uids = u16::from_le_bytes([chna.1[2], chna.1[3]]);
    assert_eq!(n_tracks, 14);
    assert_eq!(n_uids, 14);
    // Row 0 → bed channel 1, ATU_00000001
    assert_eq!(u16::from_le_bytes([chna.1[4], chna.1[5]]), 1);
    let uid0 = std::str::from_utf8(&chna.1[6..18]).unwrap();
    assert_eq!(uid0, "ATU_00000001");
    // Row 13 (objects[1]) → track index 14, ATU_0000000E
    let row13 = &chna.1[4 + 13 * 40..4 + 14 * 40];
    let idx13 = u16::from_le_bytes([row13[0], row13[1]]);
    assert_eq!(idx13, 14);
    let uid13 = std::str::from_utf8(&row13[2..14]).unwrap();
    assert_eq!(uid13, "ATU_0000000E");
}

#[test]
fn force_rf64_promotes_and_remains_parseable() {
    let dir = unique_tmp("rf64");
    let path = dir.join("rf64.wav");

    let bed = AtmosBed::new(BedConfig::default());
    let bed_pcm: Vec<Vec<f32>> = (0..bed.output_layout().total_channels())
        .map(|_| vec![0.0_f32; 4_096])
        .collect();
    let meta = AdmMetadata::new();

    let exporter = AtmosExporter {
        metadata: &meta,
        bed: Some(&bed),
        bed_pcm: &bed_pcm,
        object_pcm: &[],
        settings: ExportSettings { force_rf64: true, ..Default::default() },
    };
    let report = exporter.write_to(&path).unwrap();
    assert!(report.is_rf64);

    let (is_rf64, chunks) = read_chunks(&path);
    assert!(is_rf64);
    let ds64 = chunks.iter().find(|(id, _)| id == "ds64").expect("ds64 missing");
    assert_eq!(ds64.1.len(), 28);
}

#[test]
fn objects_only_export_omits_bed_pack() {
    let dir = unique_tmp("obj");
    let path = dir.join("obj.wav");

    let mut meta = AdmMetadata::new();
    meta.add_object(ObjectMetadata {
        id: 1,
        name: "Solo".into(),
        position: Position3D::new(0.0, 1.0, 0.0),
        duration_samples: 4_800,
        ..Default::default()
    });
    let pcm = vec![vec![0.5_f32; 4_800]];

    let exporter = AtmosExporter {
        metadata: &meta,
        bed: None,
        bed_pcm: &[],
        object_pcm: &pcm,
        settings: ExportSettings::default(),
    };
    let report = exporter.write_to(&path).unwrap();
    assert_eq!(report.channels, 1);
    assert_eq!(report.chna_entries, 1);

    let (_, chunks) = read_chunks(&path);
    let xml = chunks.iter().find(|(id, _)| id == "axml").unwrap();
    let xml_text = std::str::from_utf8(&xml.1).unwrap();
    assert!(!xml_text.contains("typeDefinition=\"DirectSpeakers\""));
    assert!(xml_text.contains("typeDefinition=\"Objects\""));
    assert!(xml_text.contains("audioObjectName=\"Solo\""));
}

#[test]
fn channel_count_mismatch_is_rejected() {
    let dir = unique_tmp("mismatch");
    let path = dir.join("mismatch.wav");
    let bed = AtmosBed::new(BedConfig::default());
    // wrong number of bed channels (want 12, give 5)
    let bed_pcm: Vec<Vec<f32>> = (0..5).map(|_| vec![0.0_f32; 64]).collect();
    let meta = AdmMetadata::new();
    let exporter = AtmosExporter {
        metadata: &meta,
        bed: Some(&bed),
        bed_pcm: &bed_pcm,
        object_pcm: &[],
        settings: ExportSettings::default(),
    };
    let r = exporter.write_to(&path);
    assert!(matches!(r, Err(rf_spatial::atmos::ExportError::Invalid(_))));
}

#[test]
fn bit_depth_must_be_16_24_or_32() {
    let dir = unique_tmp("bits");
    let path = dir.join("bad.wav");
    let bed = AtmosBed::new(BedConfig::default());
    let bed_pcm: Vec<Vec<f32>> = (0..bed.output_layout().total_channels())
        .map(|_| vec![0.0_f32; 64])
        .collect();
    let meta = AdmMetadata::new();
    let exporter = AtmosExporter {
        metadata: &meta,
        bed: Some(&bed),
        bed_pcm: &bed_pcm,
        object_pcm: &[],
        settings: ExportSettings { bit_depth: 12, ..Default::default() },
    };
    let r = exporter.write_to(&path);
    assert!(matches!(r, Err(rf_spatial::atmos::ExportError::Invalid(_))));
}

#[test]
fn pcm_data_size_matches_declared_layout() {
    // Verifies samples × channels × bytes_per_sample == data chunk payload size
    let dir = unique_tmp("size");
    let path = dir.join("size.wav");

    let bed = AtmosBed::new(BedConfig::default());
    let bed_pcm: Vec<Vec<f32>> = (0..bed.output_layout().total_channels())
        .map(|_| vec![0.1_f32; 1234])
        .collect();
    let object_pcm = vec![vec![0.2_f32; 1234]];
    let mut meta = AdmMetadata::new();
    meta.add_object(ObjectMetadata {
        id: 1,
        name: "X".into(),
        duration_samples: 1234,
        ..Default::default()
    });

    let exporter = AtmosExporter {
        metadata: &meta,
        bed: Some(&bed),
        bed_pcm: &bed_pcm,
        object_pcm: &object_pcm,
        settings: ExportSettings { bit_depth: 16, ..Default::default() },
    };
    let _ = exporter.write_to(&path).unwrap();
    let (_, chunks) = read_chunks(&path);
    let data = chunks.iter().find(|(id, _)| id == "data").unwrap();
    assert_eq!(data.1.len(), 1234 * 13 * 2);
}
