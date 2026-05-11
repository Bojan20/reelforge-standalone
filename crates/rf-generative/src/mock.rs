//! Deterministic, zero-dep mock backend.
//!
//! Used by:
//!   1. unit tests across the workspace,
//!   2. the FAZA 5 UI work *before* `feature = "onnx"` ships a real model,
//!   3. CI smoke runs where we just want to know "does the pipeline glue
//!      hold up", not "does the model sound good".
//!
//! Output is a band-limited additive synth whose spectrum is steered by the
//! request's `SlotStageHint` (so a `WinBig` clip actually sounds excited,
//! not identical to `Idle`) and whose amplitude follows the `EmotionalArc`.
//! Seed is a hard contract: same seed + same request ⇒ byte-identical PCM.

use crate::backend::{BackendCapabilities, GenError, GenerativeBackend};
use crate::request::{GenerationRequest, SlotStageHint};
use crate::response::{GenerationResponse, ProvenanceTag};
use std::time::Instant;

pub struct MockBackend {
    id: String,
}

impl MockBackend {
    pub fn new() -> Self {
        Self {
            id: "mock".to_string(),
        }
    }
}

impl Default for MockBackend {
    fn default() -> Self {
        Self::new()
    }
}

impl GenerativeBackend for MockBackend {
    fn id(&self) -> &str {
        &self.id
    }

    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            deterministic: true,
            honors_emotional_arc: true,
            honors_stage_hint: true,
            stereo: true,
            max_duration_seconds: crate::MAX_DURATION_SECONDS,
        }
    }

    fn generate(&self, request: &GenerationRequest) -> Result<GenerationResponse, GenError> {
        request
            .validate()
            .map_err(GenError::InvalidRequest)?;

        let started = Instant::now();

        // Native rate = 48 kHz unless the request explicitly asked for
        // something else.
        let sample_rate = if request.sample_rate_hz == 0 {
            crate::NATIVE_SAMPLE_RATE
        } else {
            request.sample_rate_hz
        };

        // Always stereo so downstream callers don't need to upmix.
        let channels: u16 = 2;
        let total_frames = (request.duration_seconds * sample_rate as f32).round() as usize;
        let mut pcm = Vec::with_capacity(total_frames * channels as usize);

        // Stage-driven partial set. Each stage gets a small chord so the
        // listener can distinguish "BigWin" from "Idle" by ear in dev.
        let partials = stage_partials(request.style.stage_hint);

        // Seed contract: derive everything from this. `None` ⇒ stable
        // "no-seed" value so the test suite is reproducible even when a
        // caller forgets a seed.
        let mut rng = SplitMix64::new(request.seed.unwrap_or(0xF1_0C_F0_06_5A_FE_C0_DEu64));
        // Per-partial phase offsets so two runs with different seeds sound
        // distinct (but a fixed seed is fully reproducible).
        let phase_offsets: Vec<f32> = partials
            .iter()
            .map(|_| rng.next_f32_unit() * std::f32::consts::TAU)
            .collect();

        let arc = request.style.emotional_arc.as_ref();
        let inv_sr = 1.0 / sample_rate as f32;
        let inv_frames = if total_frames <= 1 {
            0.0
        } else {
            1.0 / (total_frames - 1) as f32
        };
        // Linear fade-in / fade-out to kill click-on / click-off transients.
        let fade_frames = ((sample_rate as f32 * 0.005) as usize).min(total_frames / 2);

        for frame_idx in 0..total_frames {
            let t_sec = frame_idx as f32 * inv_sr;
            let t_norm = frame_idx as f32 * inv_frames;
            let envelope = arc.map(|a| a.sample(t_norm)).unwrap_or(0.75);
            let fade = fade_envelope(frame_idx, total_frames, fade_frames);
            let amp = envelope.clamp(0.0, 1.0) * fade * 0.5; // headroom -6 dBFS

            // Sum partials → stereo with mild width via per-channel phase.
            let mut l = 0.0_f32;
            let mut r = 0.0_f32;
            for (i, p) in partials.iter().enumerate() {
                let base_phase = std::f32::consts::TAU * p.freq_hz * t_sec + phase_offsets[i];
                l += p.amp * (base_phase).sin();
                r += p.amp * (base_phase + p.stereo_offset).sin();
            }
            // Normalize across partials so we don't clip even at envelope=1.
            let scale = amp / partials_amp_sum(&partials).max(f32::EPSILON);
            pcm.push((l * scale).clamp(-1.0, 1.0));
            pcm.push((r * scale).clamp(-1.0, 1.0));
        }

        let response = GenerationResponse {
            pcm,
            sample_rate_hz: sample_rate,
            channels,
            latency_ms: started.elapsed().as_millis().min(u32::MAX as u128) as u32,
            provenance: ProvenanceTag {
                backend_id: self.id.clone(),
                model_id: "none".into(),
                seed: request.seed,
                generated_at_utc: iso8601_utc_now(),
            },
        };

        Ok(response)
    }
}

/// A partial in the additive synth.
#[derive(Debug, Clone, Copy)]
struct Partial {
    freq_hz: f32,
    amp: f32,
    /// Inter-channel phase offset in radians. Wider = more stereo spread.
    stereo_offset: f32,
}

/// Each stage gets a hand-tuned chord. Numbers are coarse — the point is
/// audible distinction, not musical perfection. Stable Audio Open Small
/// will replace this entirely once 5.1.2 lands.
fn stage_partials(hint: Option<SlotStageHint>) -> Vec<Partial> {
    use SlotStageHint::*;
    let p = |freq_hz, amp, stereo_offset| Partial {
        freq_hz,
        amp,
        stereo_offset,
    };
    match hint {
        // Deep, slow, narrow — a calm hum.
        Some(Idle) | None => vec![
            p(110.0, 1.0, 0.05),
            p(165.0, 0.5, 0.10),
        ],
        // Tension build — slight detune for unease.
        Some(Anticipation) => vec![
            p(220.0, 1.0, 0.20),
            p(221.3, 0.6, 0.30),
            p(330.0, 0.4, 0.40),
        ],
        // Short percussive cluster.
        Some(ReelStop) => vec![
            p(440.0, 1.0, 0.15),
            p(660.0, 0.7, 0.20),
        ],
        // Small win — bright triad.
        Some(WinSmall) => vec![
            p(523.0, 1.0, 0.20),
            p(659.0, 0.8, 0.25),
            p(784.0, 0.6, 0.30),
        ],
        // Medium win — fuller chord.
        Some(WinMedium) => vec![
            p(392.0, 1.0, 0.20),
            p(494.0, 0.8, 0.25),
            p(587.0, 0.7, 0.30),
            p(784.0, 0.5, 0.35),
        ],
        // Big win — wider, brassy.
        Some(WinBig) => vec![
            p(261.6, 1.0, 0.25),
            p(329.6, 0.9, 0.30),
            p(392.0, 0.8, 0.35),
            p(523.2, 0.7, 0.40),
            p(659.2, 0.5, 0.45),
        ],
        // Mega win — six partials, max width.
        Some(WinMega) => vec![
            p(174.6, 1.0, 0.30),
            p(220.0, 1.0, 0.35),
            p(261.6, 1.0, 0.40),
            p(329.6, 0.9, 0.45),
            p(392.0, 0.8, 0.50),
            p(523.2, 0.7, 0.55),
        ],
        // Bonus trigger — bright sparkle stack.
        Some(BonusTrigger) => vec![
            p(880.0, 1.0, 0.30),
            p(1318.5, 0.8, 0.40),
            p(1760.0, 0.6, 0.50),
        ],
        // FreeSpin start — choir-like.
        Some(FreeSpinStart) => vec![
            p(261.6, 1.0, 0.25),
            p(392.0, 0.9, 0.30),
            p(523.2, 0.8, 0.35),
            p(783.9, 0.6, 0.40),
        ],
        // Jackpot — densest stack, full width.
        Some(JackpotHit) => vec![
            p(130.8, 1.0, 0.30),
            p(196.0, 1.0, 0.35),
            p(261.6, 1.0, 0.40),
            p(392.0, 0.9, 0.45),
            p(523.2, 0.8, 0.50),
            p(784.0, 0.7, 0.55),
            p(1046.5, 0.5, 0.60),
        ],
        // Cascade — short rising arpeggio fragment.
        Some(Cascade) => vec![
            p(440.0, 1.0, 0.20),
            p(554.4, 0.7, 0.25),
            p(659.3, 0.5, 0.30),
        ],
        // Game over — minor, dark.
        Some(GameOver) => vec![
            p(110.0, 1.0, 0.15),
            p(130.8, 0.7, 0.20),
            p(155.6, 0.5, 0.25),
        ],
    }
}

fn partials_amp_sum(partials: &[Partial]) -> f32 {
    partials.iter().map(|p| p.amp).sum()
}

fn fade_envelope(idx: usize, total: usize, fade: usize) -> f32 {
    if fade == 0 || total == 0 {
        return 1.0;
    }
    if idx < fade {
        return idx as f32 / fade as f32;
    }
    if idx + fade >= total {
        let from_end = total - idx;
        return from_end as f32 / fade as f32;
    }
    1.0
}

/// Tiny SplitMix64 PRNG. Stdlib has no built-in deterministic RNG so we
/// roll our own — fewer bytes than pulling `rand`. Hard contract: same
/// seed ⇒ same stream, on every platform we care about (little-endian).
struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform `[0.0, 1.0)` f32.
    fn next_f32_unit(&mut self) -> f32 {
        // Use the top 24 bits — that's all f32's mantissa can hold without
        // bias.
        let bits = (self.next_u64() >> 40) as u32;
        (bits as f32) / (1u32 << 24) as f32
    }
}

/// Tiny zero-dep ISO 8601 UTC timestamp. We don't pull `chrono` for one
/// log field. Format: `2026-05-11T15:30:00Z`.
fn iso8601_utc_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // Conway-style calendar conversion. Accurate from 1970 → 9999.
    let (year, month, day, hour, minute, second) = epoch_secs_to_utc(secs);
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
}

fn epoch_secs_to_utc(secs: u64) -> (i32, u32, u32, u32, u32, u32) {
    let second = (secs % 60) as u32;
    let minutes_total = secs / 60;
    let minute = (minutes_total % 60) as u32;
    let hours_total = minutes_total / 60;
    let hour = (hours_total % 24) as u32;
    let days_total = hours_total / 24;

    // 1970-01-01 → 719_468 days from year 0 (civil_from_days reference).
    let z = days_total as i64 + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y as i32, m as u32, d as u32, hour, minute, second)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::request::{EmotionalArc, EmotionalArcPoint, GenerationStyle};

    fn req(duration: f32, seed: Option<u64>, hint: Option<SlotStageHint>) -> GenerationRequest {
        GenerationRequest {
            prompt: "test clip".into(),
            duration_seconds: duration,
            sample_rate_hz: 0,
            seed,
            style: GenerationStyle {
                stage_hint: hint,
                emotional_arc: None,
                tags: vec![],
            },
        }
    }

    #[test]
    fn generates_expected_frame_count_at_native_rate() {
        let backend = MockBackend::new();
        let res = backend.generate(&req(0.5, Some(42), None)).unwrap();
        assert_eq!(res.sample_rate_hz, crate::NATIVE_SAMPLE_RATE);
        assert_eq!(res.channels, 2);
        // 0.5s × 48k = 24 000 frames; ±1 for round() drift, but exact here.
        assert_eq!(res.frame_count(), 24_000);
        assert_eq!(res.pcm.len(), 24_000 * 2);
    }

    #[test]
    fn determinism_byte_identical_for_same_seed() {
        let backend = MockBackend::new();
        let a = backend.generate(&req(0.25, Some(7), Some(SlotStageHint::WinBig))).unwrap();
        let b = backend.generate(&req(0.25, Some(7), Some(SlotStageHint::WinBig))).unwrap();
        assert_eq!(a.pcm, b.pcm);
        assert_eq!(a.frame_count(), b.frame_count());
        assert_eq!(a.provenance.seed, Some(7));
    }

    #[test]
    fn determinism_differs_for_different_seeds() {
        let backend = MockBackend::new();
        let a = backend.generate(&req(0.25, Some(1), None)).unwrap();
        let b = backend.generate(&req(0.25, Some(2), None)).unwrap();
        // Phase offset depends on seed → first-frame samples should diverge.
        assert_ne!(&a.pcm[..32], &b.pcm[..32]);
    }

    #[test]
    fn stage_hint_changes_output_spectrum() {
        let backend = MockBackend::new();
        let idle = backend.generate(&req(0.1, Some(9), Some(SlotStageHint::Idle))).unwrap();
        let mega = backend.generate(&req(0.1, Some(9), Some(SlotStageHint::WinMega))).unwrap();
        assert_eq!(idle.pcm.len(), mega.pcm.len());
        // A 110 Hz hum and a six-partial WinMega chord must produce
        // measurably different waveforms at the same seed.
        assert_ne!(idle.pcm, mega.pcm);
    }

    #[test]
    fn emotional_arc_modulates_amplitude() {
        let backend = MockBackend::new();
        // Crescendo arc: 0 → 1.
        let mut r = req(1.0, Some(11), Some(SlotStageHint::WinBig));
        r.style.emotional_arc = Some(EmotionalArc {
            points: vec![
                EmotionalArcPoint { t: 0.0, intensity: 0.05 },
                EmotionalArcPoint { t: 1.0, intensity: 1.0 },
            ],
        });
        let res = backend.generate(&r).unwrap();
        // RMS of first 10% should be much smaller than RMS of last 10%.
        let n = res.frame_count();
        let head_rms = rms_slice(&res.pcm, 0, (n * 10) / 100);
        let tail_rms = rms_slice(&res.pcm, (n * 90) / 100, n);
        assert!(
            tail_rms > head_rms * 4.0,
            "expected tail RMS >> head RMS, got head={head_rms} tail={tail_rms}"
        );
    }

    #[test]
    fn output_in_normalized_range() {
        let backend = MockBackend::new();
        let res = backend
            .generate(&req(0.2, Some(13), Some(SlotStageHint::JackpotHit)))
            .unwrap();
        for (i, s) in res.pcm.iter().enumerate() {
            assert!(s.is_finite(), "pcm[{i}] = {s} non-finite");
            assert!(s.abs() <= 1.0001, "pcm[{i}] = {s} clipping");
        }
        res.validate().expect("response must pass self-validation");
    }

    #[test]
    fn rejects_invalid_request() {
        let backend = MockBackend::new();
        let mut bad = req(0.5, Some(1), None);
        bad.prompt = "".into();
        let err = backend.generate(&bad).unwrap_err();
        assert!(matches!(err, GenError::InvalidRequest(_)));
    }

    #[test]
    fn rejects_out_of_range_duration() {
        let backend = MockBackend::new();
        let too_long = req(crate::MAX_DURATION_SECONDS + 1.0, Some(1), None);
        let err = backend.generate(&too_long).unwrap_err();
        assert!(matches!(err, GenError::InvalidRequest(_)));

        let too_short = req(0.0, Some(1), None);
        let err = backend.generate(&too_short).unwrap_err();
        assert!(matches!(err, GenError::InvalidRequest(_)));
    }

    #[test]
    fn fade_in_out_kills_clicks() {
        let backend = MockBackend::new();
        let res = backend
            .generate(&req(0.05, Some(1), Some(SlotStageHint::ReelStop)))
            .unwrap();
        // First and last frame should both be near zero (fade endpoints).
        assert!(res.pcm[0].abs() < 0.01, "fade-in: pcm[0] = {}", res.pcm[0]);
        let last = res.pcm.len() - 1;
        assert!(res.pcm[last].abs() < 0.01, "fade-out: pcm[last] = {}", res.pcm[last]);
    }

    #[test]
    fn capabilities_advertised() {
        let backend = MockBackend::new();
        let caps = backend.capabilities();
        assert!(caps.deterministic);
        assert!(caps.honors_emotional_arc);
        assert!(caps.honors_stage_hint);
        assert!(caps.stereo);
        assert_eq!(caps.max_duration_seconds, crate::MAX_DURATION_SECONDS);
    }

    #[test]
    fn iso8601_format_is_well_formed() {
        let ts = iso8601_utc_now();
        // Shape: YYYY-MM-DDTHH:MM:SSZ
        assert_eq!(ts.len(), 20, "got {ts}");
        assert_eq!(&ts[4..5], "-");
        assert_eq!(&ts[7..8], "-");
        assert_eq!(&ts[10..11], "T");
        assert_eq!(&ts[13..14], ":");
        assert_eq!(&ts[16..17], ":");
        assert_eq!(&ts[19..20], "Z");
    }

    #[test]
    fn epoch_zero_is_1970() {
        let (y, mo, d, h, mi, s) = epoch_secs_to_utc(0);
        assert_eq!((y, mo, d, h, mi, s), (1970, 1, 1, 0, 0, 0));
    }

    #[test]
    fn epoch_known_timestamp_matches() {
        // 2026-05-11T00:00:00Z = 1_778_457_600 (verified externally).
        let (y, mo, d, h, mi, s) = epoch_secs_to_utc(1_778_457_600);
        assert_eq!((y, mo, d, h, mi, s), (2026, 5, 11, 0, 0, 0));
    }

    fn rms_slice(pcm: &[f32], start: usize, end: usize) -> f32 {
        if end <= start {
            return 0.0;
        }
        let slice = &pcm[start..end];
        let sum_sq: f32 = slice.iter().map(|s| s * s).sum();
        (sum_sq / slice.len() as f32).sqrt()
    }
}

#[cfg(test)]
mod request_validation_tests {
    use super::*;
    use crate::request::{EmotionalArc, EmotionalArcPoint, GenerationStyle};

    #[test]
    fn validate_accepts_canonical_request() {
        let r = GenerationRequest {
            prompt: "big win sting".into(),
            duration_seconds: 2.0,
            sample_rate_hz: 48_000,
            seed: Some(1),
            style: GenerationStyle::default(),
        };
        assert!(r.validate().is_ok());
    }

    #[test]
    fn validate_rejects_non_finite_duration() {
        let r = GenerationRequest {
            prompt: "x".into(),
            duration_seconds: f32::NAN,
            sample_rate_hz: 0,
            seed: None,
            style: GenerationStyle::default(),
        };
        assert!(r.validate().is_err());
    }

    #[test]
    fn validate_rejects_weird_sample_rate() {
        let r = GenerationRequest {
            prompt: "x".into(),
            duration_seconds: 1.0,
            sample_rate_hz: 12_345,
            seed: None,
            style: GenerationStyle::default(),
        };
        assert!(r.validate().is_err());
    }

    #[test]
    fn arc_sample_clamps_and_interpolates() {
        let arc = EmotionalArc {
            points: vec![
                EmotionalArcPoint { t: 0.0, intensity: 0.0 },
                EmotionalArcPoint { t: 0.5, intensity: 1.0 },
                EmotionalArcPoint { t: 1.0, intensity: 0.5 },
            ],
        };
        arc.validate().unwrap();
        assert!((arc.sample(0.0) - 0.0).abs() < 1e-6);
        assert!((arc.sample(0.25) - 0.5).abs() < 1e-6);
        assert!((arc.sample(0.5) - 1.0).abs() < 1e-6);
        assert!((arc.sample(0.75) - 0.75).abs() < 1e-6);
        assert!((arc.sample(1.0) - 0.5).abs() < 1e-6);
        // Out-of-range clamps.
        assert!((arc.sample(-1.0) - 0.0).abs() < 1e-6);
        assert!((arc.sample(2.0) - 0.5).abs() < 1e-6);
    }

    #[test]
    fn arc_rejects_non_monotonic_points() {
        let arc = EmotionalArc {
            points: vec![
                EmotionalArcPoint { t: 0.5, intensity: 0.5 },
                EmotionalArcPoint { t: 0.2, intensity: 0.5 },
            ],
        };
        assert!(arc.validate().is_err());
    }
}
