//! Local on-device audio generator (offline / air-gapped).
//!
//! ## Status
//!
//! This is a **deterministic placeholder** generator that writes a short,
//! silent (or low-amplitude) WAV with a length matching the prompt's
//! `length_seconds` (or 1.0s default). The point: the rest of the pipeline
//! works end-to-end even when the customer is fully air-gapped and has no
//! GPU yet — they get a usable file in the right place with the right name,
//! ready to be replaced manually or by a future model.
//!
//! ## Future
//!
//! When MusicGen / Stable Audio Open / other on-device models land, this
//! struct stays — only the body of `generate` changes. The trait surface is
//! already correct.

use crate::audio::generator::{
    sanitize_filename, AudioBackendId, AudioError, AudioGenerator, AudioOutput, AudioPrompt,
    AudioResult,
};
use async_trait::async_trait;
use std::io::Write;
use std::path::Path;

/// Local placeholder generator (writes a deterministic WAV).
#[derive(Default, Clone)]
pub struct LocalBackend;

impl LocalBackend {
    /// Construct a new local backend.
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl AudioGenerator for LocalBackend {
    fn id(&self) -> AudioBackendId {
        AudioBackendId::Local
    }

    async fn health_check(&self) -> AudioResult<()> {
        // Local backend is always available.
        Ok(())
    }

    async fn generate(&self, prompt: &AudioPrompt, out_dir: &Path) -> AudioResult<AudioOutput> {
        tokio::fs::create_dir_all(out_dir)
            .await
            .map_err(|e| AudioError::Io(format!("mkdir: {}", e)))?;

        let length_seconds = prompt.length_seconds.unwrap_or(1.0).clamp(0.1, 30.0);
        let sample_rate: u32 = 48_000;
        let total_samples = (length_seconds * sample_rate as f32) as u32;

        // Channel-deterministic shaped placeholder: a 1 Hz sine envelope at
        // -60 dBFS so it's audibly silent but the file is a real waveform.
        // Hash the prompt to seed the carrier frequency so different prompts
        // produce distinguishable preview files.
        let carrier_hz = prompt_to_carrier(&prompt.prompt);
        let amp = 0.001_f32; // ~ -60 dBFS

        let mut pcm: Vec<i16> = Vec::with_capacity(total_samples as usize * 2);
        for n in 0..total_samples {
            let t = n as f32 / sample_rate as f32;
            let env = (2.0 * std::f32::consts::PI * t).sin().abs();
            let s = (2.0 * std::f32::consts::PI * carrier_hz * t).sin() * env * amp;
            let i = (s * i16::MAX as f32) as i16;
            pcm.push(i); // L
            pcm.push(i); // R
        }

        let safe = sanitize_filename(&prompt.suggested_name);
        let path = out_dir.join(format!("{}.wav", safe));

        let bytes = encode_wav_pcm16_stereo(&pcm, sample_rate);
        let written = bytes.len() as u64;
        tokio::fs::write(&path, bytes)
            .await
            .map_err(|e| AudioError::Io(format!("write {}: {}", path.display(), e)))?;

        Ok(AudioOutput {
            path,
            format: "wav".to_string(),
            duration_ms: (length_seconds * 1000.0) as u32,
            bytes: written,
            backend: AudioBackendId::Local,
            prompt: prompt.prompt.clone(),
            kind: prompt.kind,
        })
    }
}

/// Map a prompt to a carrier frequency in [110, 880] Hz.
fn prompt_to_carrier(prompt: &str) -> f32 {
    let mut hash: u64 = 1469598103934665603;
    for byte in prompt.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(1099511628211);
    }
    let normalized = (hash as f64 / u64::MAX as f64) as f32; // [0, 1]
    110.0 + normalized * 770.0
}

/// Minimal RIFF/WAVE PCM16 stereo encoder.
fn encode_wav_pcm16_stereo(samples: &[i16], sample_rate: u32) -> Vec<u8> {
    let num_channels: u16 = 2;
    let bits_per_sample: u16 = 16;
    let byte_rate = sample_rate * num_channels as u32 * bits_per_sample as u32 / 8;
    let block_align = num_channels * bits_per_sample / 8;
    let data_size = (samples.len() * 2) as u32;
    let riff_size = 36 + data_size;

    let mut out = Vec::with_capacity(44 + data_size as usize);
    out.write_all(b"RIFF").unwrap();
    out.write_all(&riff_size.to_le_bytes()).unwrap();
    out.write_all(b"WAVE").unwrap();
    out.write_all(b"fmt ").unwrap();
    out.write_all(&16u32.to_le_bytes()).unwrap();
    out.write_all(&1u16.to_le_bytes()).unwrap(); // PCM
    out.write_all(&num_channels.to_le_bytes()).unwrap();
    out.write_all(&sample_rate.to_le_bytes()).unwrap();
    out.write_all(&byte_rate.to_le_bytes()).unwrap();
    out.write_all(&block_align.to_le_bytes()).unwrap();
    out.write_all(&bits_per_sample.to_le_bytes()).unwrap();
    out.write_all(b"data").unwrap();
    out.write_all(&data_size.to_le_bytes()).unwrap();
    for s in samples {
        out.write_all(&s.to_le_bytes()).unwrap();
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::generator::AudioKind;

    #[tokio::test]
    async fn produces_a_real_wav_file() {
        let dir = std::env::temp_dir().join("rf-composer-local-test");
        let _ = std::fs::remove_dir_all(&dir);
        let b = LocalBackend::new();
        let p = AudioPrompt {
            prompt: "test prompt".to_string(),
            kind: AudioKind::Sfx,
            length_seconds: Some(0.5),
            voice_id: None,
            suggested_name: "test_asset".to_string(),
        };
        let out = b.generate(&p, &dir).await.unwrap();
        assert_eq!(out.format, "wav");
        assert!(out.bytes > 44, "WAV must be larger than header");
        assert!(out.path.exists(), "file must exist on disk");
        let bytes = std::fs::read(&out.path).unwrap();
        assert_eq!(&bytes[..4], b"RIFF");
        assert_eq!(&bytes[8..12], b"WAVE");
    }

    #[test]
    fn carrier_in_range() {
        for s in &["a", "different", "yet another long prompt"] {
            let f = prompt_to_carrier(s);
            assert!((110.0..=880.0).contains(&f));
        }
    }

    #[test]
    fn carrier_deterministic() {
        assert_eq!(prompt_to_carrier("abc"), prompt_to_carrier("abc"));
        assert_ne!(prompt_to_carrier("abc"), prompt_to_carrier("xyz"));
    }

    #[tokio::test]
    async fn always_healthy() {
        assert!(LocalBackend::new().health_check().await.is_ok());
    }
}
