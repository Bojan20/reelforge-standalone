//! Response types. Caller-friendly: PCM is owned, sample rate is explicit,
//! provenance is required (so AudioSeal / 5.2.4 watermarking can hook).

use serde::{Deserialize, Serialize};

/// What every backend returns. Owned data — caller is free to move into a
/// ring buffer, write to disk, hand to ffmpeg, etc.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GenerationResponse {
    /// Interleaved PCM. For mono: `[s0, s1, s2, ...]`. For stereo:
    /// `[L0, R0, L1, R1, ...]`. Range `[-1.0, 1.0]` (no DC, no clipping —
    /// backends MUST normalize before returning).
    pub pcm: Vec<f32>,

    /// Sample rate of `pcm` in Hz. Always > 0.
    pub sample_rate_hz: u32,

    /// 1 = mono, 2 = stereo. Other values are invalid.
    pub channels: u16,

    /// How long inference took on the backend, wall-clock. Used by the UI
    /// to display a perf badge and by telemetry to flag regressions.
    pub latency_ms: u32,

    /// Required provenance metadata. Audited in compliance pipelines.
    pub provenance: ProvenanceTag,
}

impl GenerationResponse {
    /// Number of frames (samples per channel) actually returned.
    pub fn frame_count(&self) -> usize {
        if self.channels == 0 {
            return 0;
        }
        self.pcm.len() / self.channels as usize
    }

    /// Total clip duration in seconds, derived from `pcm` length and
    /// `sample_rate_hz` (NOT from the request — backends may round).
    pub fn duration_seconds(&self) -> f32 {
        if self.sample_rate_hz == 0 || self.channels == 0 {
            return 0.0;
        }
        self.frame_count() as f32 / self.sample_rate_hz as f32
    }

    /// Defensive checks. Backends MAY skip; integration tests should not.
    pub fn validate(&self) -> Result<(), String> {
        if self.sample_rate_hz == 0 {
            return Err("response.sample_rate_hz must be > 0".into());
        }
        if !matches!(self.channels, 1 | 2) {
            return Err(format!(
                "response.channels = {} (must be 1 or 2)",
                self.channels
            ));
        }
        if self.pcm.is_empty() {
            return Err("response.pcm must not be empty".into());
        }
        if self.pcm.len() % self.channels as usize != 0 {
            return Err(format!(
                "response.pcm length {} not divisible by channels {}",
                self.pcm.len(),
                self.channels
            ));
        }
        for (i, s) in self.pcm.iter().enumerate() {
            if !s.is_finite() {
                return Err(format!("response.pcm[{i}] is non-finite ({s})"));
            }
            if s.abs() > 1.000_01 {
                return Err(format!(
                    "response.pcm[{i}] = {s} outside normalized range [-1,1]"
                ));
            }
        }
        Ok(())
    }
}

/// Mandatory provenance. The compliance layer (5.1.8) refuses to accept
/// any clip without this tag — keeps generated content auditable.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProvenanceTag {
    /// Backend that produced the clip, e.g. `"mock"`, `"tract-sam-small"`.
    pub backend_id: String,
    /// Model identifier, e.g. `"stable-audio-open-small@1.0"`. `"none"` for
    /// fully procedural backends.
    pub model_id: String,
    /// Seed that was used. `None` ⇒ non-deterministic run (flagged in audit).
    pub seed: Option<u64>,
    /// ISO 8601 timestamp at the start of inference, UTC.
    pub generated_at_utc: String,
}
