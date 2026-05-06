//! WAV file writer — Problems Inbox replay export (FLUX_MASTER_TODO 2.2.2).
//!
//! Pre-fix `MasterRingBuffer::snapshot()` je vraćao raw `Vec<f32>` parove
//! ali nije bilo načina da se zapišu kao WAV file za QA replay.
//! Problems Inbox snima screenshot + meter values, ali audio je nestajao
//! sa svakom novom session-om — neproductivno za regression analizu.
//!
//! Ovaj modul pokriva tu rupu sa zero-dep, no_std-friendly RIFF/WAVE
//! writer-om koji ide u 16-bit signed PCM (industry-standard za QA
//! replay) sa interleaved L/R kanalima.
//!
//! ## Format (RIFF/WAVE PCM 16-bit stereo)
//!
//! ```text
//! Bytes 0–3   "RIFF"
//! Bytes 4–7   file_size - 8 (little-endian u32)
//! Bytes 8–11  "WAVE"
//! Bytes 12–15 "fmt "
//! Bytes 16–19 16 (fmt chunk size)
//! Bytes 20–21 1  (PCM format code)
//! Bytes 22–23 channels (2 = stereo)
//! Bytes 24–27 sample_rate
//! Bytes 28–31 byte_rate (sample_rate × channels × bytes_per_sample)
//! Bytes 32–33 block_align (channels × bytes_per_sample)
//! Bytes 34–35 bits_per_sample (16)
//! Bytes 36–39 "data"
//! Bytes 40–43 data_size (samples × channels × bytes_per_sample)
//! Bytes 44+   interleaved L0,R0,L1,R1,...
//! ```
//!
//! ## Clipping behavior
//!
//! `f32` samples u rasponu `[-1.0, 1.0]` mapiraju se na `i16` range
//! `[-32768, 32767]`. Vrednosti van range-a se **clip-uju** (saturate),
//! ne overflow-uju. To je standardno ponašanje — overflow bi proizveo
//! "click" artefakte koji bi maskirali stvarni audio bug u replay-u.

use std::fs::File;
use std::io::{self, BufWriter, Seek, SeekFrom, Write};
use std::path::Path;

/// 16-bit signed PCM bytes per sample (per channel).
const BYTES_PER_SAMPLE: u16 = 2;
/// Stereo — 2 kanala, interleaved L/R u data chunk-u.
const NUM_CHANNELS: u16 = 2;
/// PCM format code (uncompressed integer).
const PCM_FORMAT_CODE: u16 = 1;

/// Write stereo f32 buffers as 16-bit PCM WAV file.
///
/// `left` i `right` moraju imati istu dužinu (stereo paritet). Mismatch
/// vraća `InvalidData` — ne pokušavamo da reconstruct missing kanal jer
/// bi tihi mismatch maskirao bug u source pipeline-u (audio QA vrednost
/// = 0 ako kanali drift-uju).
///
/// Sample rate mora biti > 0. Vrednost 0 vraća `InvalidInput` — WAV
/// reader-i bi inače decode-ovali kao "instant playback" (NaN duration).
pub fn write_wav<P: AsRef<Path>>(
    path: P,
    left: &[f32],
    right: &[f32],
    sample_rate: u32,
) -> io::Result<()> {
    if left.len() != right.len() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "stereo channel length mismatch: left={}, right={}",
                left.len(),
                right.len()
            ),
        ));
    }
    if sample_rate == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "sample_rate must be > 0",
        ));
    }

    let frames = left.len();
    let data_size = (frames as u32)
        .checked_mul(NUM_CHANNELS as u32)
        .and_then(|n| n.checked_mul(BYTES_PER_SAMPLE as u32))
        .ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "data_size u32 overflow")
        })?;
    // RIFF size = file size minus 8 (RIFF header je 8 bytes excluded).
    let riff_size = 36u32.checked_add(data_size).ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "riff_size u32 overflow")
    })?;
    let byte_rate = sample_rate
        .checked_mul(NUM_CHANNELS as u32)
        .and_then(|n| n.checked_mul(BYTES_PER_SAMPLE as u32))
        .ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "byte_rate u32 overflow")
        })?;
    let block_align: u16 = NUM_CHANNELS * BYTES_PER_SAMPLE;
    let bits_per_sample: u16 = BYTES_PER_SAMPLE * 8;

    let file = File::create(path.as_ref())?;
    let mut w = BufWriter::new(file);

    // ── RIFF header ─────────────────────────────────────────────────
    w.write_all(b"RIFF")?;
    w.write_all(&riff_size.to_le_bytes())?;
    w.write_all(b"WAVE")?;

    // ── fmt chunk (16 bytes) ────────────────────────────────────────
    w.write_all(b"fmt ")?;
    w.write_all(&16u32.to_le_bytes())?; // fmt chunk size
    w.write_all(&PCM_FORMAT_CODE.to_le_bytes())?;
    w.write_all(&NUM_CHANNELS.to_le_bytes())?;
    w.write_all(&sample_rate.to_le_bytes())?;
    w.write_all(&byte_rate.to_le_bytes())?;
    w.write_all(&block_align.to_le_bytes())?;
    w.write_all(&bits_per_sample.to_le_bytes())?;

    // ── data chunk header ───────────────────────────────────────────
    w.write_all(b"data")?;
    w.write_all(&data_size.to_le_bytes())?;

    // ── interleaved samples — clamp + cast u jednom prolazu ─────────
    // Buffer je local stack alloc — 4 bytes per frame, ~24 KB za 5s
    // burst. Zero allocations u petlji (write_all je fixed).
    let mut sample_bytes = [0u8; 4];
    for i in 0..frames {
        let l = float_to_pcm16(left[i]);
        let r = float_to_pcm16(right[i]);
        sample_bytes[0..2].copy_from_slice(&l.to_le_bytes());
        sample_bytes[2..4].copy_from_slice(&r.to_le_bytes());
        w.write_all(&sample_bytes)?;
    }

    w.flush()?;
    // Ensure file is closed before returning so caller can immediately
    // open it (e.g. WAV reader test ili user opens u Audacity-u).
    drop(w);
    Ok(())
}

/// Saturate-cast f32 → i16. Vrednosti van [-1.0, 1.0] se clamp-uju
/// na rub i16 range. NaN se mapira na 0 (silence) — bolji default
/// nego "garbage truncation" koji bi proizveo random click.
#[inline]
fn float_to_pcm16(s: f32) -> i16 {
    if s.is_nan() {
        return 0;
    }
    let scaled = (s * i16::MAX as f32).round();
    if scaled >= i16::MAX as f32 {
        i16::MAX
    } else if scaled <= i16::MIN as f32 {
        i16::MIN
    } else {
        scaled as i16
    }
}

/// Convenience wrapper koji koristi temporary file path generation.
/// Pretežno za UI snapshot capture flow gde se file-name radi sa
/// timestamp-om za uniqueness. Caller bira folder.
pub fn write_wav_named<P: AsRef<Path>>(
    folder: P,
    file_name: &str,
    left: &[f32],
    right: &[f32],
    sample_rate: u32,
) -> io::Result<std::path::PathBuf> {
    std::fs::create_dir_all(folder.as_ref())?;
    let mut path = folder.as_ref().to_path_buf();
    path.push(file_name);
    write_wav(&path, left, right, sample_rate)?;
    Ok(path)
}

/// Re-seekable variant — koristi `Seek` ako neko pišeš u in-memory
/// `Cursor<Vec<u8>>` (npr. testovi). Ostavljen public za buduće
/// streaming use-case-ove gde se RIFF size-ovi popravljaju tek na
/// kraju.
pub fn write_wav_to<W: Write + Seek>(
    writer: &mut W,
    left: &[f32],
    right: &[f32],
    sample_rate: u32,
) -> io::Result<()> {
    if left.len() != right.len() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "stereo channel length mismatch",
        ));
    }
    if sample_rate == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "sample_rate must be > 0",
        ));
    }

    let frames = left.len();
    let data_size = (frames as u32) * (NUM_CHANNELS as u32) * (BYTES_PER_SAMPLE as u32);
    let riff_size = 36u32 + data_size;
    let byte_rate = sample_rate * (NUM_CHANNELS as u32) * (BYTES_PER_SAMPLE as u32);
    let block_align = NUM_CHANNELS * BYTES_PER_SAMPLE;
    let bits_per_sample = BYTES_PER_SAMPLE * 8;

    writer.seek(SeekFrom::Start(0))?;
    writer.write_all(b"RIFF")?;
    writer.write_all(&riff_size.to_le_bytes())?;
    writer.write_all(b"WAVE")?;
    writer.write_all(b"fmt ")?;
    writer.write_all(&16u32.to_le_bytes())?;
    writer.write_all(&PCM_FORMAT_CODE.to_le_bytes())?;
    writer.write_all(&NUM_CHANNELS.to_le_bytes())?;
    writer.write_all(&sample_rate.to_le_bytes())?;
    writer.write_all(&byte_rate.to_le_bytes())?;
    writer.write_all(&block_align.to_le_bytes())?;
    writer.write_all(&bits_per_sample.to_le_bytes())?;
    writer.write_all(b"data")?;
    writer.write_all(&data_size.to_le_bytes())?;

    for i in 0..frames {
        writer.write_all(&float_to_pcm16(left[i]).to_le_bytes())?;
        writer.write_all(&float_to_pcm16(right[i]).to_le_bytes())?;
    }
    writer.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Cursor, Read};

    /// Helper: parse 16-bit little-endian signed iz raw bytes.
    fn read_i16_le(bytes: &[u8], offset: usize) -> i16 {
        i16::from_le_bytes([bytes[offset], bytes[offset + 1]])
    }
    fn read_u32_le(bytes: &[u8], offset: usize) -> u32 {
        u32::from_le_bytes([
            bytes[offset],
            bytes[offset + 1],
            bytes[offset + 2],
            bytes[offset + 3],
        ])
    }

    #[test]
    fn float_to_pcm16_clamps_at_extremes() {
        // Saturation ne sme da overflow-uje. +∞ ili 2.0 mora da daje i16::MAX.
        assert_eq!(float_to_pcm16(2.0), i16::MAX);
        assert_eq!(float_to_pcm16(1.0), i16::MAX);
        // Beyond-range negative clamps to i16::MIN (out-of-range path).
        assert_eq!(float_to_pcm16(-2.0), i16::MIN);
        // s=-1.0 sa simetričnim ×i16::MAX scaling-om daje -32767 (ne -32768).
        // Industry-standardni "normal" mapping — asimetrija od 1 LSB je
        // ispod noise floor-a (audio-perceptually identično). -32768 se
        // proizvodi samo iz < -1.0 input-a (out-of-range path iznad).
        assert_eq!(float_to_pcm16(-1.0), -i16::MAX);
    }

    #[test]
    fn float_to_pcm16_zero_is_silence() {
        assert_eq!(float_to_pcm16(0.0), 0);
    }

    #[test]
    fn float_to_pcm16_nan_silenced() {
        // NaN bi inače producirao garbage int — explicit 0 (silence)
        // sprečava clicks koji bi maskirali pravi audio bug u replay-u.
        assert_eq!(float_to_pcm16(f32::NAN), 0);
    }

    #[test]
    fn float_to_pcm16_roundtrip_within_quantization() {
        // Tipičan in-range sample mora da round-trip-uje sa <= 1 LSB
        // greškom (16-bit quantization).
        for v in [0.5_f32, -0.5, 0.25, 0.123, -0.789] {
            let pcm = float_to_pcm16(v);
            let back = pcm as f32 / i16::MAX as f32;
            assert!((back - v).abs() < 1.0 / 32767.0 + 1e-6,
                    "v={v}, pcm={pcm}, back={back}");
        }
    }

    #[test]
    fn write_wav_to_emits_canonical_44_byte_header() {
        let mut buf = Cursor::new(Vec::<u8>::new());
        let l = vec![0.0_f32; 10];
        let r = vec![0.0_f32; 10];
        write_wav_to(&mut buf, &l, &r, 48000).unwrap();
        let bytes = buf.into_inner();

        // Header je tačno 44 bytes.
        assert!(bytes.len() >= 44);
        // RIFF + WAVE + fmt + data magic markers.
        assert_eq!(&bytes[0..4], b"RIFF");
        assert_eq!(&bytes[8..12], b"WAVE");
        assert_eq!(&bytes[12..16], b"fmt ");
        assert_eq!(&bytes[36..40], b"data");
        // PCM format code = 1.
        assert_eq!(read_u32_le(&bytes, 16), 16); // fmt chunk size
        assert_eq!(read_i16_le(&bytes, 20), 1);  // PCM
        assert_eq!(read_i16_le(&bytes, 22), 2);  // stereo
        assert_eq!(read_u32_le(&bytes, 24), 48000); // sample rate
        // 10 frames × 2 channels × 2 bytes = 40 bytes data.
        assert_eq!(read_u32_le(&bytes, 40), 40);
        // RIFF size = total - 8 = 44 + 40 - 8 = 76.
        assert_eq!(read_u32_le(&bytes, 4), 76);
        // Total bytes (header + data) = 44 + 40.
        assert_eq!(bytes.len(), 84);
    }

    #[test]
    fn write_wav_to_interleaves_l_r_correctly() {
        // Sample 0: L=0.5, R=-0.5; sample 1: L=0.25, R=-0.25.
        let mut buf = Cursor::new(Vec::<u8>::new());
        let l = vec![0.5_f32, 0.25];
        let r = vec![-0.5_f32, -0.25];
        write_wav_to(&mut buf, &l, &r, 1000).unwrap();
        let bytes = buf.into_inner();

        // First sample frame at byte 44.
        let s0_l = read_i16_le(&bytes, 44); // L0
        let s0_r = read_i16_le(&bytes, 46); // R0
        let s1_l = read_i16_le(&bytes, 48); // L1
        let s1_r = read_i16_le(&bytes, 50); // R1

        assert!((s0_l as f32 / i16::MAX as f32 - 0.5).abs() < 0.001);
        assert!((s0_r as f32 / i16::MAX as f32 - (-0.5)).abs() < 0.001);
        assert!((s1_l as f32 / i16::MAX as f32 - 0.25).abs() < 0.001);
        assert!((s1_r as f32 / i16::MAX as f32 - (-0.25)).abs() < 0.001);
    }

    #[test]
    fn write_wav_rejects_channel_mismatch() {
        let mut buf = Cursor::new(Vec::<u8>::new());
        let l = vec![0.0_f32; 10];
        let r = vec![0.0_f32; 5]; // mismatch
        let err = write_wav_to(&mut buf, &l, &r, 48000).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn write_wav_rejects_zero_sample_rate() {
        let mut buf = Cursor::new(Vec::<u8>::new());
        let l = vec![0.0_f32; 10];
        let r = vec![0.0_f32; 10];
        let err = write_wav_to(&mut buf, &l, &r, 0).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
    }

    #[test]
    fn write_wav_to_disk_round_trip() {
        // End-to-end: write → read raw → parse header → verify samples.
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("snapshot.wav");
        let l: Vec<f32> = (0..100).map(|i| (i as f32) / 100.0 * 0.5).collect();
        let r: Vec<f32> = l.iter().map(|x| -x).collect();
        write_wav(&path, &l, &r, 44100).unwrap();

        let mut bytes = Vec::new();
        std::fs::File::open(&path)
            .unwrap()
            .read_to_end(&mut bytes)
            .unwrap();

        // Header sanity.
        assert_eq!(&bytes[0..4], b"RIFF");
        assert_eq!(&bytes[8..12], b"WAVE");
        assert_eq!(read_u32_le(&bytes, 24), 44100);
        // 100 frames × 2 channels × 2 bytes = 400.
        assert_eq!(read_u32_le(&bytes, 40), 400);
        assert_eq!(bytes.len(), 44 + 400);

        // Spot check 50th frame.
        let off = 44 + 50 * 4;
        let l50 = read_i16_le(&bytes, off);
        let r50 = read_i16_le(&bytes, off + 2);
        let l50f = l50 as f32 / i16::MAX as f32;
        let r50f = r50 as f32 / i16::MAX as f32;
        assert!((l50f - 0.25).abs() < 0.001, "l50f={l50f}");
        assert!((r50f - (-0.25)).abs() < 0.001, "r50f={r50f}");
    }

    #[test]
    fn write_wav_named_creates_folder_if_missing() {
        let dir = tempfile::tempdir().unwrap();
        let nested = dir.path().join("a/b/c");
        let l = vec![0.0_f32; 5];
        let r = vec![0.0_f32; 5];
        let path = write_wav_named(&nested, "test.wav", &l, &r, 48000).unwrap();
        assert!(path.exists());
        assert!(nested.exists(), "intermediate folders must be created");
    }

    #[test]
    fn write_wav_with_zero_frames_emits_valid_empty_wav() {
        // Defensive: snapshot može da vrati prazan buffer (0 frames written).
        // WAV header mora i dalje biti validan (data_size=0).
        let mut buf = Cursor::new(Vec::<u8>::new());
        write_wav_to(&mut buf, &[], &[], 48000).unwrap();
        let bytes = buf.into_inner();
        assert_eq!(bytes.len(), 44);
        assert_eq!(read_u32_le(&bytes, 40), 0); // data_size = 0
    }
}
