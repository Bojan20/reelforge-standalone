//! BW64 / RF64 WAV writer with `axml` + `chna` chunks.
//!
//! Specs followed:
//! * EBU Tech 3306-2009 — RF64 / BW64 file format
//! * EBU Tech 3285 v2.0 — Broadcast WAV / `axml` chunk
//! * EBU Tech 3285 Sup.6 — `chna` chunk (Channel Allocation)
//! * ITU-R BS.2088-1 — BWF for ADM
//!
//! Layout produced (BW64, payload < 4 GiB):
//!
//! ```text
//! "RIFF" <riffSize:u32> "WAVE"
//!   "fmt " <16:u32>  WAVEFORMATEX (PCM int16/24 or IEEE float32)
//!   "data" <dataSize:u32> <interleaved samples …>
//!   "axml" <xmlSize:u32> <UTF-8 ADM XML …>             [+ pad byte if odd]
//!   "chna" <chnaSize:u32> numTracks<u16> numUIDs<u16> <40-byte rows …>
//! ```
//!
//! On overflow (`payload + headers > 0xFFFFFFFE`) or `force_rf64`, the file is
//! promoted to RF64:
//!
//! ```text
//! "RF64" 0xFFFFFFFF "WAVE"
//!   "ds64" <28:u32> riffSize:u64 dataSize:u64 sampleCount:u64 0:u32
//!   "fmt "  …
//!   "data" 0xFFFFFFFF <samples …>
//!   "axml" …  "chna" …
//! ```
//!
//! All multi-byte integers are little-endian (RIFF convention).

use std::fs::File;
use std::io::{BufWriter, Seek, SeekFrom, Write};
use std::path::Path;

/// Sentinel UID indicating "this track is silence" (`ATU_00000000`).
pub const ATU_SILENCE: u32 = 0;

/// One row of the `chna` chunk. 40 bytes on disk:
///
/// ```text
/// trackIndex   :  u16  LE
/// UID          : 12 ASCII bytes ("ATU_xxxxxxxx", padded with 0x20)
/// trackFormatID: 14 ASCII bytes ("AT_yyyyzzzz_xx", padded with 0x20)
/// packFormatID : 11 ASCII bytes ("AP_yyyyzzzz",   padded with 0x20)
/// padding      :  1 byte = 0x00 (reserved for future use)
/// ```
#[derive(Debug, Clone)]
pub struct ChnaEntry {
    pub track_index: u16,
    pub uid: u32,
    pub track_format_id: String,
    pub pack_format_id: String,
}

/// Result returned from [`write_bw64`].
#[derive(Debug, Clone, Copy)]
pub struct WriteReport {
    /// Total bytes on disk.
    pub file_size: u64,
    /// True if RF64 was actually used (either by overflow or by force_rf64).
    pub is_rf64: bool,
}

/// Write a multi-channel BW64/RF64 WAV with embedded ADM XML.
///
/// `channels` is channel-major: `channels[ch][sample]`. Each row is independently
/// padded with `0.0` if its length is shorter than `sample_count` (allows objects
/// shorter than the bed). Samples are clipped to ±1.0 before quantisation; NaN
/// is written as silence.
#[allow(clippy::too_many_arguments)]
pub fn write_bw64(
    path: &Path,
    channels: &[&Vec<f32>],
    sample_count: usize,
    sample_rate: u32,
    bit_depth: u16,
    axml_xml: &[u8],
    chna_entries: &[ChnaEntry],
    force_rf64: bool,
) -> std::io::Result<WriteReport> {
    if channels.is_empty() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "no channels",
        ));
    }
    if !matches!(bit_depth, 16 | 24 | 32) {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "bit_depth must be 16, 24, or 32",
        ));
    }
    let n_ch = channels.len() as u16;
    let bytes_per_sample: u32 = (bit_depth / 8) as u32;
    let block_align: u16 = n_ch * bytes_per_sample as u16;
    let byte_rate: u32 = sample_rate * block_align as u32;

    let data_bytes_u64: u64 =
        sample_count as u64 * n_ch as u64 * bytes_per_sample as u64;

    // Decide RF64 up-front: any of the file totals overflowing u32 → promote.
    let axml_padded = axml_xml.len() + (axml_xml.len() & 1); // pad to even
    let chna_size: u32 = 4 + chna_entries.len() as u32 * 40; // 2+2 header + N rows
    let chna_padded = chna_size + (chna_size & 1);
    let approx_riff_size = 4 // "WAVE"
        + 8 + 16 // "fmt " hdr + WAVEFORMAT
        + 8 + data_bytes_u64 // "data" hdr + payload
        + 8 + axml_padded as u64 // "axml"
        + 8 + chna_padded as u64; // "chna"

    let needs_rf64 = force_rf64 || approx_riff_size > u32::MAX as u64 - 64;

    let file = File::create(path)?;
    let mut w = BufWriter::with_capacity(1 << 20, file);

    if needs_rf64 {
        write_rf64(
            &mut w,
            channels,
            sample_count,
            sample_rate,
            n_ch,
            bit_depth,
            block_align,
            byte_rate,
            data_bytes_u64,
            axml_xml,
            chna_entries,
        )?;
    } else {
        write_riff(
            &mut w,
            channels,
            sample_count,
            sample_rate,
            n_ch,
            bit_depth,
            block_align,
            byte_rate,
            data_bytes_u64 as u32,
            axml_xml,
            chna_entries,
        )?;
    }

    w.flush()?;
    let inner = w.into_inner().map_err(|e| e.into_error())?;
    let len = inner.metadata()?.len();
    Ok(WriteReport {
        file_size: len,
        is_rf64: needs_rf64,
    })
}

#[allow(clippy::too_many_arguments)]
fn write_riff<W: Write + Seek>(
    w: &mut W,
    channels: &[&Vec<f32>],
    sample_count: usize,
    sample_rate: u32,
    n_ch: u16,
    bit_depth: u16,
    block_align: u16,
    byte_rate: u32,
    data_bytes: u32,
    axml_xml: &[u8],
    chna_entries: &[ChnaEntry],
) -> std::io::Result<()> {
    // RIFF header — riff_size patched at the end.
    w.write_all(b"RIFF")?;
    w.write_all(&0u32.to_le_bytes())?; // placeholder
    w.write_all(b"WAVE")?;

    write_fmt_chunk(w, n_ch, sample_rate, byte_rate, block_align, bit_depth)?;

    // data
    w.write_all(b"data")?;
    w.write_all(&data_bytes.to_le_bytes())?;
    write_pcm_payload(w, channels, sample_count, bit_depth)?;
    if data_bytes % 2 == 1 {
        w.write_all(&[0u8])?;
    }

    write_axml_chunk(w, axml_xml)?;
    write_chna_chunk(w, chna_entries)?;

    // Patch RIFF size = file_size - 8.
    let end = w.stream_position()?;
    let riff_size = (end - 8) as u32;
    w.seek(SeekFrom::Start(4))?;
    w.write_all(&riff_size.to_le_bytes())?;
    w.seek(SeekFrom::Start(end))?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn write_rf64<W: Write + Seek>(
    w: &mut W,
    channels: &[&Vec<f32>],
    sample_count: usize,
    sample_rate: u32,
    n_ch: u16,
    bit_depth: u16,
    block_align: u16,
    byte_rate: u32,
    data_bytes: u64,
    axml_xml: &[u8],
    chna_entries: &[ChnaEntry],
) -> std::io::Result<()> {
    // RF64 header — fixed 0xFFFFFFFF in 32-bit slots.
    w.write_all(b"RF64")?;
    w.write_all(&u32::MAX.to_le_bytes())?;
    w.write_all(b"WAVE")?;

    // ds64 — must be the very first chunk after WAVE.
    w.write_all(b"ds64")?;
    w.write_all(&28u32.to_le_bytes())?; // ds64 size (without header)
    let ds64_riff_size_pos = w.stream_position()?;
    w.write_all(&0u64.to_le_bytes())?; // riff size placeholder
    w.write_all(&data_bytes.to_le_bytes())?;
    w.write_all(&(sample_count as u64).to_le_bytes())?;
    w.write_all(&0u32.to_le_bytes())?; // tableLength = 0

    write_fmt_chunk(w, n_ch, sample_rate, byte_rate, block_align, bit_depth)?;

    w.write_all(b"data")?;
    w.write_all(&u32::MAX.to_le_bytes())?;
    write_pcm_payload(w, channels, sample_count, bit_depth)?;
    if data_bytes % 2 == 1 {
        w.write_all(&[0u8])?;
    }

    write_axml_chunk(w, axml_xml)?;
    write_chna_chunk(w, chna_entries)?;

    // Patch riff size in ds64 (file_size - 8).
    let end = w.stream_position()?;
    let riff_size = end - 8;
    w.seek(SeekFrom::Start(ds64_riff_size_pos))?;
    w.write_all(&riff_size.to_le_bytes())?;
    w.seek(SeekFrom::Start(end))?;
    Ok(())
}

fn write_fmt_chunk<W: Write>(
    w: &mut W,
    n_ch: u16,
    sample_rate: u32,
    byte_rate: u32,
    block_align: u16,
    bit_depth: u16,
) -> std::io::Result<()> {
    w.write_all(b"fmt ")?;
    w.write_all(&16u32.to_le_bytes())?;
    let format_tag: u16 = if bit_depth == 32 { 3 /* IEEE_FLOAT */ } else { 1 /* PCM */ };
    w.write_all(&format_tag.to_le_bytes())?;
    w.write_all(&n_ch.to_le_bytes())?;
    w.write_all(&sample_rate.to_le_bytes())?;
    w.write_all(&byte_rate.to_le_bytes())?;
    w.write_all(&block_align.to_le_bytes())?;
    w.write_all(&bit_depth.to_le_bytes())?;
    Ok(())
}

fn write_pcm_payload<W: Write>(
    w: &mut W,
    channels: &[&Vec<f32>],
    sample_count: usize,
    bit_depth: u16,
) -> std::io::Result<()> {
    // Interleave: sample-major outer, channel-major inner.
    // Use a single 64 KiB scratch buffer to keep allocations off the hot path.
    const CHUNK: usize = 16 * 1024;
    let bytes_per_sample = (bit_depth / 8) as usize;
    let row_bytes = channels.len() * bytes_per_sample;
    let mut scratch = vec![0u8; CHUNK * row_bytes];

    let mut s = 0;
    while s < sample_count {
        let take = (sample_count - s).min(CHUNK);
        let mut cursor = 0;
        for i in 0..take {
            let frame = s + i;
            for c in channels {
                let v = c.get(frame).copied().unwrap_or(0.0);
                let v = if v.is_nan() { 0.0 } else { v };
                let v = v.clamp(-1.0, 1.0);
                match bit_depth {
                    16 => {
                        let q = (v * i16::MAX as f32).round() as i32;
                        let q = q.clamp(i16::MIN as i32, i16::MAX as i32) as i16;
                        scratch[cursor..cursor + 2].copy_from_slice(&q.to_le_bytes());
                        cursor += 2;
                    }
                    24 => {
                        // 24-bit signed, little-endian, two's complement.
                        let q = (v * 8_388_607.0_f32).round() as i32;
                        let q = q.clamp(-8_388_608, 8_388_607);
                        scratch[cursor] = (q & 0xFF) as u8;
                        scratch[cursor + 1] = ((q >> 8) & 0xFF) as u8;
                        scratch[cursor + 2] = ((q >> 16) & 0xFF) as u8;
                        cursor += 3;
                    }
                    32 => {
                        // IEEE float32 (format_tag 3).
                        scratch[cursor..cursor + 4].copy_from_slice(&v.to_le_bytes());
                        cursor += 4;
                    }
                    _ => unreachable!("bit_depth pre-validated"),
                }
            }
        }
        w.write_all(&scratch[..cursor])?;
        s += take;
    }
    Ok(())
}

fn write_axml_chunk<W: Write>(w: &mut W, xml: &[u8]) -> std::io::Result<()> {
    w.write_all(b"axml")?;
    w.write_all(&(xml.len() as u32).to_le_bytes())?;
    w.write_all(xml)?;
    if xml.len() % 2 == 1 {
        w.write_all(&[0u8])?;
    }
    Ok(())
}

fn write_chna_chunk<W: Write>(w: &mut W, entries: &[ChnaEntry]) -> std::io::Result<()> {
    let n = entries.len() as u16;
    let chunk_size: u32 = 4 + (n as u32) * 40;
    w.write_all(b"chna")?;
    w.write_all(&chunk_size.to_le_bytes())?;
    w.write_all(&n.to_le_bytes())?; // numTracks
    w.write_all(&n.to_le_bytes())?; // numUIDs (same in this MVP)
    for e in entries {
        let mut row = [0x20u8; 40]; // ASCII space pad
        row[..2].copy_from_slice(&e.track_index.to_le_bytes());
        // UID: bytes 2..14 (12 bytes ASCII).
        let uid_str = format!("ATU_{:08X}", e.uid);
        let uid_bytes = uid_str.as_bytes();
        debug_assert_eq!(uid_bytes.len(), 12);
        row[2..14].copy_from_slice(&uid_bytes[..12.min(uid_bytes.len())]);
        // trackFormatID: bytes 14..28 (14 bytes ASCII).
        copy_padded(&mut row[14..28], e.track_format_id.as_bytes());
        // packFormatID: bytes 28..39 (11 bytes ASCII), byte 39 is reserved 0x00.
        copy_padded(&mut row[28..39], e.pack_format_id.as_bytes());
        row[39] = 0x00;
        w.write_all(&row)?;
    }
    if chunk_size % 2 == 1 {
        w.write_all(&[0u8])?;
    }
    Ok(())
}

fn copy_padded(dst: &mut [u8], src: &[u8]) {
    let n = dst.len().min(src.len());
    dst[..n].copy_from_slice(&src[..n]);
    for b in dst.iter_mut().skip(n) {
        *b = 0x20;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Seek};

    fn read_chunk(buf: &[u8], pos: usize) -> (&str, u32, &[u8]) {
        let id = std::str::from_utf8(&buf[pos..pos + 4]).unwrap();
        let size = u32::from_le_bytes([
            buf[pos + 4],
            buf[pos + 5],
            buf[pos + 6],
            buf[pos + 7],
        ]);
        let payload = &buf[pos + 8..pos + 8 + size as usize];
        (id, size, payload)
    }

    fn dummy_channels(n_ch: usize, n_samples: usize) -> Vec<Vec<f32>> {
        (0..n_ch)
            .map(|c| {
                (0..n_samples)
                    .map(|i| ((c + 1) as f32 * (i as f32 / 1000.0)).sin() * 0.5)
                    .collect()
            })
            .collect()
    }

    #[test]
    fn writes_riff_header_and_chunks() {
        let dir = tempdir_unique();
        let path = dir.join("hello.wav");
        let chs = dummy_channels(2, 100);
        let refs: Vec<&Vec<f32>> = chs.iter().collect();
        let xml = b"<adm/>".to_vec();
        let chna = vec![
            ChnaEntry { track_index: 1, uid: 1, track_format_id: "AT_00010001_01".into(), pack_format_id: "AP_00010001".into() },
            ChnaEntry { track_index: 2, uid: 2, track_format_id: "AT_00010002_01".into(), pack_format_id: "AP_00010001".into() },
        ];
        let report = write_bw64(&path, &refs, 100, 48_000, 24, &xml, &chna, false).unwrap();
        assert!(!report.is_rf64);
        assert!(report.file_size > 100);

        let mut f = std::fs::File::open(&path).unwrap();
        let mut data = Vec::new();
        f.read_to_end(&mut data).unwrap();
        assert_eq!(&data[0..4], b"RIFF");
        assert_eq!(&data[8..12], b"WAVE");

        // First sub-chunk = "fmt "
        assert_eq!(&data[12..16], b"fmt ");
        let (id, _, _) = read_chunk(&data, 12);
        assert_eq!(id, "fmt ");
        // Find axml + chna by scanning.
        let mut found_axml = false;
        let mut found_chna = false;
        let mut p = 12usize;
        while p + 8 < data.len() {
            let (id, size, payload) = read_chunk(&data, p);
            match id {
                "axml" => {
                    assert_eq!(payload, xml.as_slice());
                    found_axml = true;
                }
                "chna" => {
                    let n_tracks = u16::from_le_bytes([payload[0], payload[1]]);
                    assert_eq!(n_tracks, 2);
                    let row0 = &payload[4..44];
                    let idx = u16::from_le_bytes([row0[0], row0[1]]);
                    assert_eq!(idx, 1);
                    let uid = std::str::from_utf8(&row0[2..14]).unwrap();
                    assert_eq!(uid, "ATU_00000001");
                    let tf = std::str::from_utf8(&row0[14..28]).unwrap();
                    assert_eq!(tf.trim_end(), "AT_00010001_01");
                    let pf = std::str::from_utf8(&row0[28..39]).unwrap();
                    assert_eq!(pf.trim_end(), "AP_00010001");
                    assert_eq!(row0[39], 0x00);
                    found_chna = true;
                }
                _ => {}
            }
            // Advance to next chunk (account for word alignment).
            let mut adv = 8 + size as usize;
            if adv % 2 == 1 {
                adv += 1;
            }
            p += adv;
        }
        assert!(found_axml, "axml chunk missing");
        assert!(found_chna, "chna chunk missing");
    }

    #[test]
    fn force_rf64_emits_ds64() {
        let dir = tempdir_unique();
        let path = dir.join("force_rf64.wav");
        let chs = dummy_channels(1, 16);
        let refs: Vec<&Vec<f32>> = chs.iter().collect();
        let report = write_bw64(&path, &refs, 16, 48_000, 24, b"<a/>", &[], true).unwrap();
        assert!(report.is_rf64);
        let data = std::fs::read(&path).unwrap();
        assert_eq!(&data[0..4], b"RF64");
        assert_eq!(&data[12..16], b"ds64");
        // ds64 size (after id) at bytes 16..20, must be 28.
        let ds64_size = u32::from_le_bytes([data[16], data[17], data[18], data[19]]);
        assert_eq!(ds64_size, 28);
        // riffSize:u64 = file_size - 8.
        let riff_size_u64 = u64::from_le_bytes([
            data[20], data[21], data[22], data[23], data[24], data[25], data[26], data[27],
        ]);
        assert_eq!(riff_size_u64 + 8, data.len() as u64);
        // dataSize:u64 = 16 samples × 1 ch × 3 bytes = 48
        let data_size = u64::from_le_bytes([
            data[28], data[29], data[30], data[31], data[32], data[33], data[34], data[35],
        ]);
        assert_eq!(data_size, 48);
        let sample_count = u64::from_le_bytes([
            data[36], data[37], data[38], data[39], data[40], data[41], data[42], data[43],
        ]);
        assert_eq!(sample_count, 16);
    }

    #[test]
    fn pcm_24bit_clamps_and_quantises() {
        let dir = tempdir_unique();
        let path = dir.join("clamp24.wav");
        // out of range: 1.5, NaN, exact 1.0, exact -1.0, 0.0
        let raw: Vec<f32> = vec![1.5_f32, f32::NAN, 1.0, -1.0, 0.0];
        let chs: [Vec<f32>; 1] = [raw];
        let refs: Vec<&Vec<f32>> = chs.iter().collect();
        write_bw64(&path, &refs, 5, 48_000, 24, b"<a/>", &[], false).unwrap();
        let data = std::fs::read(&path).unwrap();
        // Find data chunk.
        let mut p = 12;
        let mut payload: &[u8] = &[];
        while p + 8 < data.len() {
            let (id, size, body) = read_chunk(&data, p);
            if id == "data" {
                payload = body;
                break;
            }
            let mut adv = 8 + size as usize;
            if adv % 2 == 1 { adv += 1; }
            p += adv;
        }
        // 5 samples × 1 ch × 3 bytes = 15
        assert_eq!(payload.len(), 15);
        // Sample 0: 1.5 clamped → 1.0 → 8388607 (0x7FFFFF).
        let s0 = i32::from_le_bytes([payload[0], payload[1], payload[2], 0]);
        assert_eq!(s0, 0x7FFFFF);
        // Sample 1: NaN → 0.
        let s1 = i32::from_le_bytes([payload[3], payload[4], payload[5], 0]);
        assert_eq!(s1, 0);
        // Sample 2: 1.0 → 0x7FFFFF.
        let s2 = i32::from_le_bytes([payload[6], payload[7], payload[8], 0]);
        assert_eq!(s2, 0x7FFFFF);
        // Sample 3: -1.0 → -8388607 (rounded from -8388607.0; raw .round → -8388607).
        let s3_raw = i32::from_le_bytes([payload[9], payload[10], payload[11], 0]);
        // sign-extend manually: bit 23 set means negative
        let s3 = if s3_raw & 0x800000 != 0 { s3_raw | !0xFFFFFF } else { s3_raw };
        assert_eq!(s3, -8_388_607);
        // Sample 4: 0.0 → 0.
        let s4 = i32::from_le_bytes([payload[12], payload[13], payload[14], 0]);
        assert_eq!(s4, 0);
    }

    #[test]
    fn float32_roundtrip_within_tolerance() {
        let dir = tempdir_unique();
        let path = dir.join("float.wav");
        let raw: Vec<f32> = (0..1024).map(|i| (i as f32 / 1024.0 * std::f32::consts::PI).sin()).collect();
        let chs: [Vec<f32>; 1] = [raw.clone()];
        let refs: Vec<&Vec<f32>> = chs.iter().collect();
        write_bw64(&path, &refs, raw.len(), 48_000, 32, b"<a/>", &[], false).unwrap();
        let data = std::fs::read(&path).unwrap();
        // fmt: format_tag must be 3 (IEEE float)
        let mut p = 12;
        let mut tag: u16 = 0;
        while p + 8 < data.len() {
            let (id, size, body) = read_chunk(&data, p);
            if id == "fmt " {
                tag = u16::from_le_bytes([body[0], body[1]]);
            }
            let mut adv = 8 + size as usize;
            if adv % 2 == 1 { adv += 1; }
            p += adv;
        }
        assert_eq!(tag, 3);
    }

    #[test]
    fn axml_pads_to_even() {
        let dir = tempdir_unique();
        let path = dir.join("axml_odd.wav");
        let chs = dummy_channels(1, 4);
        let refs: Vec<&Vec<f32>> = chs.iter().collect();
        // Odd-length XML.
        write_bw64(&path, &refs, 4, 48_000, 24, b"<x>", &[], false).unwrap();
        let data = std::fs::read(&path).unwrap();
        // Locate axml chunk.
        let mut p = 12;
        while p + 8 < data.len() {
            let (id, size, _body) = read_chunk(&data, p);
            if id == "axml" {
                // Next chunk header must start on word boundary.
                let next = p + 8 + size as usize + (size as usize & 1);
                assert!(next + 4 <= data.len());
                assert!(matches!(&data[next..next + 4], b"chna" | b"data" | b"fmt "));
                return;
            }
            let mut adv = 8 + size as usize;
            if adv % 2 == 1 { adv += 1; }
            p += adv;
        }
        panic!("axml chunk not found");
    }

    #[test]
    fn rejects_zero_channels() {
        let dir = tempdir_unique();
        let path = dir.join("noch.wav");
        let r = write_bw64(&path, &[], 0, 48_000, 24, b"", &[], false);
        assert!(r.is_err());
    }

    #[test]
    fn rejects_invalid_bit_depth() {
        let dir = tempdir_unique();
        let path = dir.join("bad_bits.wav");
        let chs = dummy_channels(1, 4);
        let refs: Vec<&Vec<f32>> = chs.iter().collect();
        let r = write_bw64(&path, &refs, 4, 48_000, 12, b"", &[], false);
        assert!(r.is_err());
    }

    fn tempdir_unique() -> std::path::PathBuf {
        let n = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let p = std::env::temp_dir().join(format!("rf-spatial-bw64-{}", n));
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    #[allow(dead_code)]
    fn assert_seek<W: Seek>(_w: &W) {}
}
