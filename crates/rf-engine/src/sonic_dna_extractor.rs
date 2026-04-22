//! Sonic DNA Feature Extractor
//!
//! Čita WAV/FLAC/MP3 fajlove i ekstraktuje 7-feature acoustic vector
//! koji Sonic DNA Classifier koristi za klasifikaciju.
//!
//! ## Features
//! - Duration (trivial)
//! - RMS Energy
//! - Spectral Centroid (FFT-based)
//! - Transient Density (energy diff detector)
//! - Zero Crossing Rate
//! - Spectral Flux (inter-frame spectral change)
//! - Envelope Shape (via EnvelopeShape::detect)
//! - Harmonic Ratio (FFT peak regularity)

use std::path::Path;

use rustfft::{FftPlanner, num_complex::Complex};
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

use rf_stage::sonic_dna::{EnvelopeShape, FeatureVector};

/// Greška pri ekstrakciji
#[derive(Debug)]
pub enum ExtractionError {
    IoError(std::io::Error),
    DecodeError(String),
    UnsupportedFormat,
    EmptyFile,
}

impl std::fmt::Display for ExtractionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::IoError(e) => write!(f, "IO: {e}"),
            Self::DecodeError(s) => write!(f, "Decode: {s}"),
            Self::UnsupportedFormat => write!(f, "Unsupported format"),
            Self::EmptyFile => write!(f, "Empty file"),
        }
    }
}

impl From<std::io::Error> for ExtractionError {
    fn from(e: std::io::Error) -> Self {
        Self::IoError(e)
    }
}

/// Ekstrakt feature vector iz audio fajla
pub fn extract_features(path: &Path) -> Result<FeatureVector, ExtractionError> {
    let file = std::fs::File::open(path)?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| ExtractionError::DecodeError(e.to_string()))?;

    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or(ExtractionError::UnsupportedFormat)?;

    let sample_rate = track.codec_params.sample_rate.unwrap_or(44100) as f32;
    let track_id = track.id;

    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| ExtractionError::DecodeError(e.to_string()))?;

    // Decode sve samplovane podatke u mono f32 buffer
    let mut mono_samples: Vec<f32> = Vec::with_capacity(sample_rate as usize * 10);

    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(_) => break,
        };
        if packet.track_id() != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(_) => continue,
        };
        let spec = *decoded.spec();
        let mut buf = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
        buf.copy_interleaved_ref(decoded);
        let samples = buf.samples();
        let channels = spec.channels.count();

        // Mixdown to mono
        if channels == 1 {
            mono_samples.extend_from_slice(samples);
        } else {
            for chunk in samples.chunks(channels) {
                let sum: f32 = chunk.iter().sum();
                mono_samples.push(sum / channels as f32);
            }
        }

        // Limit: max 30s za analizu (brže za dugačke fajlove)
        if mono_samples.len() > (sample_rate * 30.0) as usize {
            break;
        }
    }

    if mono_samples.is_empty() {
        return Err(ExtractionError::EmptyFile);
    }

    let total_samples = mono_samples.len();
    let duration_s = total_samples as f32 / sample_rate;

    // ─── RMS Energy ──────────────────────────────────────────────────────────
    let rms = {
        let sq_sum: f32 = mono_samples.iter().map(|&v| v * v).sum();
        (sq_sum / total_samples as f32).sqrt().min(1.0)
    };

    // ─── Zero Crossing Rate ──────────────────────────────────────────────────
    let zcr = {
        let crossings = mono_samples
            .windows(2)
            .filter(|w| (w[0] >= 0.0) != (w[1] >= 0.0))
            .count();
        // Normalize: max ~4400 crossings/s na 44100Hz (nyquist/2)
        (crossings as f32 / total_samples as f32 * 2.0).min(1.0)
    };

    // ─── FFT Analysis (spectral centroid, flux, harmonic) ────────────────────
    let fft_size = 2048usize;
    let hop = fft_size / 2;

    let mut planner = FftPlanner::<f32>::new();
    let fft = planner.plan_fft_forward(fft_size);

    let mut centroid_sum = 0.0f64;
    let mut centroid_frames = 0usize;
    let mut flux_sum = 0.0f64;
    let mut flux_frames = 0usize;
    let mut harmonic_sum = 0.0f64;
    let mut harmonic_frames = 0usize;
    let mut prev_magnitude: Option<Vec<f32>> = None;

    // Hann window
    let window: Vec<f32> = (0..fft_size)
        .map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / (fft_size - 1) as f32).cos()))
        .collect();

    let num_bins = fft_size / 2 + 1;
    let freq_per_bin = sample_rate / fft_size as f32;

    for start in (0..total_samples.saturating_sub(fft_size)).step_by(hop) {
        let frame = &mono_samples[start..start + fft_size];

        let mut buf: Vec<Complex<f32>> = frame
            .iter()
            .zip(&window)
            .map(|(&s, &w)| Complex::new(s * w, 0.0))
            .collect();

        fft.process(&mut buf);

        let magnitude: Vec<f32> = buf[..num_bins]
            .iter()
            .map(|c| (c.re * c.re + c.im * c.im).sqrt())
            .collect();

        let mag_sum: f32 = magnitude.iter().sum();

        // Spectral Centroid
        if mag_sum > 1e-10 {
            let weighted: f32 = magnitude
                .iter()
                .enumerate()
                .map(|(k, &m)| k as f32 * m)
                .sum::<f32>();
            let centroid_hz = (weighted / mag_sum) * freq_per_bin;
            // Normalize: 0=0Hz, 1=nyquist
            centroid_sum += (centroid_hz / (sample_rate * 0.5)) as f64;
            centroid_frames += 1;
        }

        // Spectral Flux
        if let Some(ref prev) = prev_magnitude {
            let flux: f32 = magnitude
                .iter()
                .zip(prev.iter())
                .map(|(&a, &b)| (a - b).max(0.0))
                .sum::<f32>();
            let normalized_flux = if mag_sum > 1e-10 { flux / mag_sum } else { 0.0 };
            flux_sum += normalized_flux as f64;
            flux_frames += 1;
        }
        prev_magnitude = Some(magnitude.clone());

        // Harmonic Ratio — FFT peak regularity test
        // Muzika ima pravilne harmonike, SFX ima neravnomerne.
        // Tražimo uzorak gde su jaki peak-ovi na regularnim intervalima.
        if mag_sum > 1e-6 {
            let top_threshold = mag_sum * 0.1;
            let peaks: Vec<usize> = magnitude
                .windows(3)
                .enumerate()
                .filter_map(|(i, w)| {
                    if w[1] > w[0] && w[1] > w[2] && w[1] > top_threshold {
                        Some(i + 1)
                    } else {
                        None
                    }
                })
                .take(8)
                .collect();

            if peaks.len() >= 3 {
                // Da li su razmaci između peak-ova regularne?
                let intervals: Vec<f32> = peaks
                    .windows(2)
                    .map(|w| (w[1] - w[0]) as f32)
                    .collect();
                let mean_interval = intervals.iter().sum::<f32>() / intervals.len() as f32;
                let variance_norm: f32 = if mean_interval > 0.0 {
                    intervals
                        .iter()
                        .map(|&x| ((x - mean_interval) / mean_interval).powi(2))
                        .sum::<f32>()
                        / intervals.len() as f32
                } else {
                    1.0
                };
                // Niska varijansa = regularni harmonici = muzika
                let ratio = (1.0 - variance_norm.min(1.0)).max(0.0);
                harmonic_sum += ratio as f64;
                harmonic_frames += 1;
            }
        }
    }

    let spectral_centroid = if centroid_frames > 0 {
        (centroid_sum / centroid_frames as f64) as f32
    } else {
        0.3
    };

    let spectral_flux = if flux_frames > 0 {
        ((flux_sum / flux_frames as f64) as f32).min(1.0)
    } else {
        0.0
    };

    let harmonic_ratio = if harmonic_frames > 0 {
        (harmonic_sum / harmonic_frames as f64) as f32
    } else {
        0.0
    };

    // ─── Transient Density ───────────────────────────────────────────────────
    let transient_density = {
        let frame_len = (sample_rate * 0.01) as usize; // 10ms frames
        if frame_len == 0 {
            0.0
        } else {
            let frame_energies: Vec<f32> = mono_samples
                .chunks(frame_len)
                .map(|chunk| {
                    let sum: f32 = chunk.iter().map(|&v| v * v).sum();
                    sum / chunk.len() as f32
                })
                .collect();

            let transient_count = frame_energies
                .windows(2)
                .filter(|w| w[1] > w[0] * 3.0 && w[1] > 1e-6)
                .count();

            transient_count as f32 / duration_s.max(0.001)
        }
    };

    // ─── Envelope Shape ──────────────────────────────────────────────────────
    // Downsample na max 1000 tačaka za envelope detekciju
    let envelope: Vec<f32> = if mono_samples.len() > 1000 {
        let step = mono_samples.len() / 1000;
        (0..1000)
            .map(|i| mono_samples[i * step].abs())
            .collect()
    } else {
        mono_samples.iter().map(|&v| v.abs()).collect()
    };
    let envelope_shape = EnvelopeShape::detect(&envelope);

    Ok(FeatureVector {
        duration_s,
        rms_energy: rms,
        spectral_centroid: spectral_centroid.clamp(0.0, 1.0),
        transient_density,
        zero_crossing_rate: zcr,
        spectral_flux: spectral_flux.clamp(0.0, 1.0),
        envelope_shape,
        harmonic_ratio: harmonic_ratio.clamp(0.0, 1.0),
    })
}

/// Batch ekstrakcija iz foldera — svi podržani audio fajlovi
pub fn extract_features_from_folder(folder: &Path) -> Vec<(String, FeatureVector)> {
    const AUDIO_EXTS: &[&str] = &["wav", "flac", "mp3", "ogg", "aiff", "aif"];

    let entries = match std::fs::read_dir(folder) {
        Ok(e) => e,
        Err(_) => return vec![],
    };

    let mut results = Vec::new();

    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();
        if !AUDIO_EXTS.contains(&ext.as_str()) {
            continue;
        }
        match extract_features(&path) {
            Ok(fv) => {
                results.push((path.to_string_lossy().to_string(), fv));
            }
            Err(e) => {
                // Ignoriši fajlove koji se ne mogu dekodirati
                log::warn!("[SonicDNA] Skipping {:?}: {}", path, e);
            }
        }
    }

    // Sortiramo po putanji za konzistentnost
    results.sort_by(|a, b| a.0.cmp(&b.0));
    results
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_nonexistent_file_returns_err() {
        let result = extract_features(Path::new("/nonexistent/file.wav"));
        assert!(result.is_err());
    }

    #[test]
    fn test_extract_folder_empty_dir() {
        let tmp = std::env::temp_dir();
        // Prazan temp dir ne sme da crasha
        let results = extract_features_from_folder(&tmp);
        // Može biti 0 ili više, ali ne crash
        let _ = results;
    }
}
