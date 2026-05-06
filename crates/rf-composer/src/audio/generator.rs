//! `AudioGenerator` trait — the seam between Composer and audio production backends.
//!
//! Composer produces a `StageAssetMap` with `generation_prompt` per asset. This
//! module turns those prompts into actual audio files on disk. Three flavors:
//!
//! - **SFX** (kind = oneshot/transition/sting/loop) → short prompt-driven audio
//! - **TTS** (kind = vo) → text-to-speech
//! - **MUSIC** (kind = ambient/music in non-sfx bus) → longer composed pieces

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use thiserror::Error;

/// What kind of audio to produce.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioKind {
    /// Short SFX (loops, oneshots, stings, transitions).
    Sfx,
    /// Text-to-speech voice line.
    Tts,
    /// Longer composed music (ambient bed, bonus theme, etc.).
    Music,
}

/// Prompt to send to an `AudioGenerator`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioPrompt {
    /// Free-form description of the desired audio.
    pub prompt: String,
    /// Kind of audio (drives backend routing).
    pub kind: AudioKind,
    /// Target length in seconds (None = backend default).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub length_seconds: Option<f32>,
    /// Voice ID for TTS (ignored for SFX/MUSIC).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub voice_id: Option<String>,
    /// Suggested filename (no extension — backend adds the right one).
    pub suggested_name: String,
}

/// Backend identifier — what the user picked in Settings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioBackendId {
    /// ElevenLabs — SFX + TTS via api.elevenlabs.io.
    Elevenlabs,
    /// Suno AI — music generation.
    Suno,
    /// Local on-device generation (MusicGen / Stable Audio Open via candle).
    Local,
}

impl AudioBackendId {
    /// Human-readable label for the UI.
    pub fn label(&self) -> &'static str {
        match self {
            Self::Elevenlabs => "ElevenLabs (SFX + TTS)",
            Self::Suno => "Suno (Music)",
            Self::Local => "Local (Offline)",
        }
    }

    /// Default kinds this backend can handle.
    pub fn supports(&self, kind: AudioKind) -> bool {
        match self {
            Self::Elevenlabs => matches!(kind, AudioKind::Sfx | AudioKind::Tts),
            Self::Suno => matches!(kind, AudioKind::Music),
            // Local backend is a stub that "produces" silent placeholder WAVs —
            // useful for offline / air-gapped deployments where customer
            // wires their own model later. Supports all kinds because the
            // placeholder is generic.
            Self::Local => true,
        }
    }

    /// Iterate all variants in stable UI order.
    pub fn all() -> [AudioBackendId; 3] {
        [Self::Elevenlabs, Self::Suno, Self::Local]
    }
}

/// Result of a single audio generation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioOutput {
    /// Absolute path to the produced file.
    pub path: PathBuf,
    /// Container format (mp3, wav, ogg).
    pub format: String,
    /// Wall-clock duration in milliseconds (best-effort estimate).
    pub duration_ms: u32,
    /// Bytes written.
    pub bytes: u64,
    /// Backend that produced it.
    pub backend: AudioBackendId,
    /// Original prompt (for asset metadata).
    pub prompt: String,
    /// Kind that was generated.
    pub kind: AudioKind,
}

/// All errors an `AudioGenerator` can produce.
#[derive(Error, Debug)]
pub enum AudioError {
    /// Backend authentication failed (missing or invalid key).
    #[error("audio auth: {0}")]
    Auth(String),
    /// Network / HTTP failure.
    #[error("audio network: {0}")]
    Network(String),
    /// Backend rejected the prompt (unsafe content, too long, etc).
    #[error("audio rejected: {0}")]
    Rejected(String),
    /// Backend rate-limited.
    #[error("audio rate limited: {0}")]
    RateLimited(String),
    /// Backend doesn't support this kind.
    #[error("audio unsupported: backend {backend:?} cannot produce {kind:?}")]
    Unsupported {
        /// Which backend.
        backend: AudioBackendId,
        /// Which kind.
        kind: AudioKind,
    },
    /// Filesystem error writing the output.
    #[error("audio io: {0}")]
    Io(String),
    /// Configuration missing or invalid.
    #[error("audio config: {0}")]
    Config(String),
    /// User cancelled the operation.
    #[error("audio cancelled")]
    Cancelled,
    /// Other catch-all.
    #[error("audio: {0}")]
    Other(#[from] anyhow::Error),
}

/// Result alias for audio operations.
pub type AudioResult<T> = Result<T, AudioError>;

/// The seam every audio backend implements.
#[async_trait]
pub trait AudioGenerator: Send + Sync {
    /// Stable identifier.
    fn id(&self) -> AudioBackendId;

    /// Lightweight liveness check.
    async fn health_check(&self) -> AudioResult<()>;

    /// Generate one audio file. The implementation MUST write the file to
    /// `out_dir` using a derived filename, and return the full output path.
    async fn generate(
        &self,
        prompt: &AudioPrompt,
        out_dir: &std::path::Path,
    ) -> AudioResult<AudioOutput>;
}

/// Sanitize a string for use as a filename: lowercase ASCII, replace
/// non-alphanumerics with underscore, dedup adjacent underscores, trim,
/// truncate to 64 chars.
pub fn sanitize_filename(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut last_underscore = false;
    for c in input.chars() {
        let mapped = if c.is_ascii_alphanumeric() {
            c.to_ascii_lowercase()
        } else {
            '_'
        };
        if mapped == '_' {
            if last_underscore {
                continue;
            }
            last_underscore = true;
        } else {
            last_underscore = false;
        }
        out.push(mapped);
        if out.len() >= 64 {
            break;
        }
    }
    let trimmed = out.trim_matches('_');
    if trimmed.is_empty() {
        "asset".to_string()
    } else {
        trimmed.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_basic() {
        assert_eq!(sanitize_filename("Big Win Stinger!"), "big_win_stinger");
    }

    #[test]
    fn sanitize_consolidates_underscores() {
        assert_eq!(sanitize_filename("a   b___c"), "a_b_c");
    }

    #[test]
    fn sanitize_truncates() {
        let long = "a".repeat(200);
        assert!(sanitize_filename(&long).len() <= 64);
    }

    #[test]
    fn sanitize_empty_input() {
        assert_eq!(sanitize_filename(""), "asset");
        assert_eq!(sanitize_filename("___"), "asset");
    }

    #[test]
    fn sanitize_unicode_replaced() {
        assert_eq!(sanitize_filename("Mégàloop №1"), "m_g_loop_1");
    }

    #[test]
    fn backend_supports_routing() {
        assert!(AudioBackendId::Elevenlabs.supports(AudioKind::Sfx));
        assert!(AudioBackendId::Elevenlabs.supports(AudioKind::Tts));
        assert!(!AudioBackendId::Elevenlabs.supports(AudioKind::Music));
        assert!(AudioBackendId::Suno.supports(AudioKind::Music));
        assert!(!AudioBackendId::Suno.supports(AudioKind::Sfx));
        assert!(AudioBackendId::Local.supports(AudioKind::Sfx));
    }

    #[test]
    fn backend_labels_unique() {
        let mut labels: Vec<_> = AudioBackendId::all().iter().map(|b| b.label()).collect();
        labels.sort();
        labels.dedup();
        assert_eq!(labels.len(), 3);
    }
}
