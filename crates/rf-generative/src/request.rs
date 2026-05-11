//! Request types. Backend-agnostic — anything `tract` or a cloud HTTP backend
//! needs is expressed here so we never have to reach into backend-specific
//! data structures from `rf-bridge` / `rf-engine` / the UI.

use serde::{Deserialize, Serialize};

/// A single generation request. Backend-agnostic.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GenerationRequest {
    /// Free-text prompt. Backends MAY ignore this if they only consume
    /// `style` (the structured fields). For local Stable Audio Open Small
    /// this is the primary input.
    pub prompt: String,

    /// Total duration in seconds. Must be in
    /// `[MIN_DURATION_SECONDS, MAX_DURATION_SECONDS]`.
    pub duration_seconds: f32,

    /// Output sample rate. `0` = "backend native" (recommended; engine
    /// resamples to 48 kHz after the fact).
    #[serde(default)]
    pub sample_rate_hz: u32,

    /// `Some(seed)` → deterministic generation (see `GenerativeBackend`
    /// contract). `None` → backend may roll its own random seed.
    #[serde(default)]
    pub seed: Option<u64>,

    /// Structured style hints. Optional but recommended — emotional arc and
    /// stage hint dramatically improve slot-appropriate output.
    #[serde(default)]
    pub style: GenerationStyle,
}

impl GenerationRequest {
    /// Fully validates against the canonical contract. Backends SHOULD call
    /// this first; the error from `Self::validate` maps 1:1 to
    /// `GenError::InvalidRequest`.
    pub fn validate(&self) -> Result<(), String> {
        if self.prompt.trim().is_empty() {
            return Err("prompt must not be empty or whitespace".into());
        }
        if self.prompt.len() > 4096 {
            return Err(format!(
                "prompt length {} exceeds 4096-character limit",
                self.prompt.len()
            ));
        }
        if !self.duration_seconds.is_finite() {
            return Err("duration_seconds must be finite".into());
        }
        if self.duration_seconds < crate::MIN_DURATION_SECONDS
            || self.duration_seconds > crate::MAX_DURATION_SECONDS
        {
            return Err(format!(
                "duration_seconds {:.3} out of range [{:.3}, {:.3}]",
                self.duration_seconds,
                crate::MIN_DURATION_SECONDS,
                crate::MAX_DURATION_SECONDS
            ));
        }
        // 0 = "backend native" sentinel; otherwise it must be one of the
        // production sample rates the engine knows how to resample from.
        if self.sample_rate_hz != 0
            && !matches!(
                self.sample_rate_hz,
                16_000 | 22_050 | 24_000 | 32_000 | 44_100 | 48_000 | 88_200 | 96_000
            )
        {
            return Err(format!(
                "sample_rate_hz {} not in supported set",
                self.sample_rate_hz
            ));
        }
        self.style.validate()?;
        Ok(())
    }
}

/// Structured slot-domain style hints.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct GenerationStyle {
    /// Coarse slot stage the generated clip is targeting. Drives backend
    /// presets (e.g. `SlotStageHint::BigWin` → trumpet+choir profile).
    #[serde(default)]
    pub stage_hint: Option<SlotStageHint>,

    /// Time-varying emotional intensity. Empty = flat / no shaping.
    #[serde(default)]
    pub emotional_arc: Option<EmotionalArc>,

    /// Free-text style tags. Caller decides taxonomy; backend MAY use them
    /// as additional prompt context.
    #[serde(default)]
    pub tags: Vec<String>,
}

impl GenerationStyle {
    pub fn validate(&self) -> Result<(), String> {
        if let Some(arc) = &self.emotional_arc {
            arc.validate()?;
        }
        if self.tags.len() > 32 {
            return Err(format!(
                "style.tags has {} entries (limit 32)",
                self.tags.len()
            ));
        }
        for (i, tag) in self.tags.iter().enumerate() {
            if tag.is_empty() {
                return Err(format!("style.tags[{i}] is empty"));
            }
            if tag.len() > 64 {
                return Err(format!(
                    "style.tags[{i}] length {} exceeds 64",
                    tag.len()
                ));
            }
        }
        Ok(())
    }
}

/// Coarse stage hints. Subset of `rf-stage` stage variants intentionally —
/// `rf-generative` should not pull in the full stage graph. Map at call site.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SlotStageHint {
    Idle,
    Anticipation,
    ReelStop,
    WinSmall,
    WinMedium,
    WinBig,
    WinMega,
    BonusTrigger,
    FreeSpinStart,
    JackpotHit,
    Cascade,
    GameOver,
}

/// Monotonic-time emotional arc envelope. `points` is normalized to
/// `[0.0, 1.0]` along both axes; the backend rescales to the actual
/// generation duration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EmotionalArc {
    pub points: Vec<EmotionalArcPoint>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct EmotionalArcPoint {
    /// Time, normalized to `[0.0, 1.0]` of the total generation duration.
    pub t: f32,
    /// Emotional intensity, `[0.0, 1.0]`. `0` = calm, `1` = euphoric peak.
    pub intensity: f32,
}

impl EmotionalArc {
    pub fn validate(&self) -> Result<(), String> {
        if self.points.is_empty() {
            return Err("emotional_arc.points must not be empty".into());
        }
        if self.points.len() > 64 {
            return Err(format!(
                "emotional_arc.points has {} entries (limit 64)",
                self.points.len()
            ));
        }
        let mut prev_t = -1.0_f32;
        for (i, p) in self.points.iter().enumerate() {
            if !p.t.is_finite() || !p.intensity.is_finite() {
                return Err(format!("emotional_arc.points[{i}] has non-finite field"));
            }
            if !(0.0..=1.0).contains(&p.t) {
                return Err(format!(
                    "emotional_arc.points[{i}].t = {} out of [0,1]",
                    p.t
                ));
            }
            if !(0.0..=1.0).contains(&p.intensity) {
                return Err(format!(
                    "emotional_arc.points[{i}].intensity = {} out of [0,1]",
                    p.intensity
                ));
            }
            if p.t < prev_t {
                return Err(format!(
                    "emotional_arc.points[{i}].t = {} is not monotonic (prev = {})",
                    p.t, prev_t
                ));
            }
            prev_t = p.t;
        }
        Ok(())
    }

    /// Linear-interpolated intensity at normalized time `t ∈ [0,1]`.
    /// Out-of-range `t` clamps to the endpoints.
    pub fn sample(&self, t: f32) -> f32 {
        if self.points.is_empty() {
            return 0.0;
        }
        let t = t.clamp(0.0, 1.0);
        if t <= self.points[0].t {
            return self.points[0].intensity;
        }
        if t >= self.points[self.points.len() - 1].t {
            return self.points[self.points.len() - 1].intensity;
        }
        // Linear scan is fine — `points.len()` is capped at 64.
        for w in self.points.windows(2) {
            let (a, b) = (w[0], w[1]);
            if t >= a.t && t <= b.t {
                let span = (b.t - a.t).max(f32::EPSILON);
                let alpha = (t - a.t) / span;
                return a.intensity + (b.intensity - a.intensity) * alpha;
            }
        }
        // Unreachable if `validate()` passed; defensive fallback.
        self.points[self.points.len() - 1].intensity
    }
}
